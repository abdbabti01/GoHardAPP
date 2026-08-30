import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../local/services/local_database_service.dart';
import '../local/models/local_chat_conversation.dart';
import '../local/models/local_chat_message.dart';

/// Repository for chat operations with offline support.
///
/// Note: sending messages and generating plans require an online
/// connection (AI responses) - this repository has no offline-write/queued
/// -sync path for those, unlike [RunningRepository]. Only conversation
/// *reads* are offline-first (cached list/detail, background refresh).
///
/// ## Session/ownership model
///
/// Every public asynchronous operation below that touches authenticated
/// chat data captures a [SessionRequestContext] via [_sessionCoordinator]
/// at operation entry (never after an internal `await`), and uses
/// `context.epochToken.userId` as the sole authoritative user for the
/// remainder of that operation - never a later, independently re-read
/// `AuthService.getUserId()`. A `null` capture (logged out, or the session
/// changed while the JWT read was in flight) follows the existing
/// not-found/unauthenticated convention each method already used before
/// this fix: `[]`/`null` for reads, `Exception('No authenticated user')`
/// for every mutation that previously threw unconditionally on failure,
/// and `false` for [deleteConversation] (which already returned a bool on
/// failure).
///
/// Every [ApiService] call this repository makes - foreground (awaited
/// inline, e.g. [sendMessage]) or background (fire-and-forget,
/// [_syncConversationsFromServer]) - is bound to that captured context, so
/// it carries the pinned JWT captured at entry rather than whatever the
/// live token happens to be, and can never be dispatched after the session
/// that started it has ended (see [ApiService]'s own class doc comment).
/// The background refresh schedules with the context already captured at
/// the public entry point that scheduled it ([getConversations]) - never a
/// context (re)captured inside the closure itself - so it stays bound to
/// the session that scheduled it, not whichever session happens to be
/// active when it finally runs.
///
/// ## Local ownership
///
/// Every [LocalChatConversation] lookup and mutation is scoped by direct
/// `userId` ownership via [_ownedConversationByServerId] (reads),
/// [_cacheConversationWithMessages] (creates/updates), and
/// [_deleteOwnedConversation] (deletes): the row is resolved AND verified
/// to belong to `context.epochToken.userId` before anything about it is
/// returned or changed. A foreign or missing target is always
/// indistinguishable - the existing not-found convention (`null` return or
/// `false`) never reveals whether a foreign row exists. This uses plain
/// [Isar] `.filter()` queries (a full-collection scan, not an indexed
/// `.where()` lookup) rather than adding a new `@Index()` to `userId` -
/// the cached-conversation-list size this app deals with does not warrant
/// a schema/migration change for this fix, matching how
/// [LocalRunSession.userId] is filtered the same way in [RunningRepository]
/// without an index.
///
/// ## Message parent-chain ownership
///
/// [LocalChatMessage] has no `userId` field of its own - ownership is
/// always proven transitively through its parent [LocalChatConversation]
/// via `conversationLocalId`, never invented as a redundant field on the
/// message itself. Every message read/write freshly re-resolves that
/// parent conversation (server-ID lookup + `userId` ownership check) first,
/// and only then queries/writes messages scoped to the parent's own
/// `localId` - never by a message's `serverId` alone, and never by trusting
/// a message row's own `conversationServerId` field without having already
/// verified the parent it claims to belong to is both present and owned.
/// A message whose parent is missing, foreign, or was deleted between HTTP
/// dispatch and acknowledgment is always silently dropped, never written as
/// an orphan.
///
/// ## Transaction/logout race protection
///
/// [_cacheConversationWithMessages], [_cacheMessageAcknowledgment], and
/// [_deleteOwnedConversation] are the SOLE way this repository writes to
/// Isar, and all three apply the same checkpoint shape: immediately before
/// entering `writeTxn`, as the FIRST statement inside `writeTxn`, and a
/// fresh re-read of the target row(s) (never a possibly-stale reference a
/// caller already resolved) with a repeated ownership check immediately
/// inside that same `writeTxn`. Every public method that calls one of these
/// also rechecks the epoch once more immediately after it returns, before
/// returning any caller-visible result. This guarantees a logout landing
/// anywhere in that window - including while Isar's write lock is being
/// awaited, and including after `LocalDatabaseService.clearAll()` has
/// already run on logout - never lets a write land against a
/// foreign/replaced row, and never resurrects or overwrites a
/// since-cleared user's data.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures: for the
/// background refresh they are classified by [_backgroundSync] as neither a
/// success nor an error, never logged as a generic failure, and never
/// grounds to retry or mark anything permanently failed. Foreground
/// callers that hit either exception treat it the same as "the operation
/// no longer has an authenticated session" - converting it to this
/// repository's own [_unauthenticated] outcome rather than surfacing Dio's
/// exception type to callers, and never logging it as an ordinary failure.
class ChatRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;

  // Kept for constructor-shape consistency with this repository's existing
  // ProxyProvider4<ApiService, LocalDatabaseService, ConnectivityService,
  // AuthService, ...> wiring in main.dart. No longer read directly - every
  // userId lookup this repository needs now comes from the captured
  // SessionRequestContext/UserSessionToken instead, per the class doc
  // comment above.
  // ignore: unused_field
  final AuthService _authService;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// every other Provider/repository that needs it (see main.dart). Only
  /// AuthProvider ever calls activate()/invalidate() on it; this repository
  /// only ever reads it via capture()/isCurrent().
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext]
  /// (pinned JWT + generation-scoped CancelToken) for every session-bound
  /// HTTP call this repository makes. The SAME instance handed to every
  /// other consumer (see main.dart); never constructed privately.
  final SessionRequestCoordinator _sessionCoordinator;

  ChatRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._authService,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  static const String _unauthenticated = 'No authenticated user';

  // ============ Test-only session-race seams ============
  //
  // One hook per checkpoint, mirroring RunningRepository's identical seams.
  // Each is @visibleForTesting, defaults to null, and is never assigned
  // outside test code - production control flow/performance are unaffected.
  @visibleForTesting
  Future<void> Function()? beforeWriteTxnForTesting;

  @visibleForTesting
  Future<void> Function()? insideWriteTxnForTesting;

  @visibleForTesting
  Future<void> Function()? afterWriteTxnForTesting;

  @visibleForTesting
  Future<void> Function()? beforeBackgroundHttpDispatchForTesting;

  @visibleForTesting
  Future<void> Function()? afterBackgroundHttpResponseForTesting;

  /// Same purpose as [afterBackgroundHttpResponseForTesting], but for the
  /// FOREGROUND acknowledgment paths ([_createConversationViaPost],
  /// [sendMessage]): fired immediately after each one's own post-HTTP
  /// epoch checkpoint passes, right before touching Isar. Lets a test
  /// prove that checkpoint rejects and returns before ever reaching this
  /// point, rather than merely relying on a later, structurally-shadowing
  /// check (the acknowledgment helper's own internal checkpoints) to
  /// produce the same externally-observable outcome.
  @visibleForTesting
  Future<void> Function()? afterForegroundHttpResponseForTesting;

  Future<void> _runTestHook(Future<void> Function()? hook) async {
    if (hook != null) {
      await hook();
    }
  }

  /// Fired synchronously, exactly once per [_backgroundSync] call, with the
  /// Future that completes once THAT SPECIFIC detached operation has fully
  /// settled - after its HTTP dispatch, its success/error handling, and any
  /// acknowledgment writeTxn or guarded stale/cancelled exit inside
  /// [operation] have all finished (it never rejects: the same
  /// success/error handling [_backgroundSync] always applies runs first, so
  /// this always completes, never throws). Tests use it to await
  /// deterministic completion of detached work instead of guessing with a
  /// delay - see `chat_repository_session_ownership_test.dart`.
  ///
  /// Defaults to null in production - a pure no-op that does not change
  /// scheduling, timing, or error handling.
  @visibleForTesting
  void Function(Future<void> operationSettled)?
  onBackgroundSyncScheduledForTesting;

  /// Schedules [operation] to run detached from the caller. [operation]
  /// must already be bound to a captured [SessionRequestContext]/
  /// [UserSessionToken] - this helper only handles the fire-and-forget
  /// execution and expected-lifecycle-outcome classification, mirroring
  /// RunningRepository's identical helper.
  void _backgroundSync(
    Future<void> Function() operation,
    String successMessage,
  ) {
    final settled = operation()
        .then((_) {
          debugPrint('✅ Background sync: $successMessage');
        })
        .catchError((e) {
          if (e is SessionStaleException || e is RequestCancelledException) {
            debugPrint(
              'ℹ️ Background sync skipped (session ended): $successMessage',
            );
            return;
          }
          debugPrint('⚠️ Background sync failed, will retry later: $e');
        });
    onBackgroundSyncScheduledForTesting?.call(settled);
  }

  /// Wraps a single background HTTP call with the before-dispatch test
  /// seam. Staleness AT dispatch time is already enforced by [ApiService]
  /// itself via the bound [SessionRequestContext.epochToken].
  Future<T> _dispatchBackgroundHttp<T>(Future<T> Function() call) async {
    await _runTestHook(beforeBackgroundHttpDispatchForTesting);
    return call();
  }

  /// Captures a context for an operation that requires connectivity,
  /// throwing this repository's existing per-operation conventions if
  /// either precondition fails: [_unauthenticated] if there is no active
  /// session, or [offlineMessage] if there is a session but no connection.
  /// No Isar read/write and no HTTP request occurs in either case.
  Future<SessionRequestContext> _requireOnlineContext(
    String offlineMessage,
  ) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    if (!_connectivity.isOnline) {
      throw Exception(offlineMessage);
    }
    return context;
  }

  // ============ Session/ownership helpers ============

  /// Resolves [conversationId] (a server ID) to a [LocalChatConversation]
  /// owned by [token.userId], or `null` if it is missing OR belongs to a
  /// different user - the two cases are always indistinguishable to
  /// callers, per the class doc comment.
  Future<LocalChatConversation?> _ownedConversationByServerId(
    Isar db,
    int conversationId,
    UserSessionToken token,
  ) async {
    final row =
        await db.localChatConversations
            .filter()
            .serverIdEqualTo(conversationId)
            .findFirst();
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (row == null || row.userId != token.userId) return null;
    return row;
  }

  /// Builds a full [ChatConversation] (with messages) from the local cache,
  /// but only if [conversationId] is owned by [token.userId]. Messages are
  /// looked up strictly via the already-verified parent's own `localId` -
  /// the message parent-chain ownership check this class doc comment
  /// describes - never by `conversationServerId` alone.
  Future<ChatConversation?> _localConversationWithMessages(
    Isar db,
    int conversationId,
    UserSessionToken token,
  ) async {
    final localConvo = await _ownedConversationByServerId(
      db,
      conversationId,
      token,
    );
    if (localConvo == null) return null;

    final localMessages =
        await db.localChatMessages
            .filter()
            .conversationLocalIdEqualTo(localConvo.localId)
            .sortByCreatedAt()
            .findAll();
    if (!_sessionEpoch.isCurrent(token)) return null;

    return ChatConversation(
      id: conversationId,
      userId: localConvo.userId,
      title: localConvo.title,
      type: localConvo.type,
      createdAt: localConvo.createdAt,
      lastMessageAt: localConvo.lastMessageAt,
      isArchived: localConvo.isArchived,
      messages:
          localMessages
              .map((local) => _localToMessage(local, conversationId))
              .toList(),
    );
  }

  /// Caches [conversation] and its messages, stamping/validating ownership
  /// from [token] - never from `conversation.userId` (an untrusted response
  /// field) and never from a live `AuthService` read. Applies the class doc
  /// comment's four-checkpoint shape. A `serverId` collision with a row
  /// already owned by a different user is skipped entirely rather than
  /// overwritten.
  Future<void> _cacheConversationWithMessages(
    Isar db,
    ChatConversation conversation,
    UserSessionToken token,
  ) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final existingLocal =
          await db.localChatConversations
              .filter()
              .serverIdEqualTo(conversation.id)
              .findFirst();

      if (existingLocal != null && existingLocal.userId != token.userId) {
        debugPrint(
          '⏭️ Skipping conversation ${conversation.id} - local row owned '
          'by a different user',
        );
        return;
      }

      final LocalChatConversation localConvo;
      if (existingLocal != null) {
        existingLocal.title = conversation.title;
        existingLocal.type = conversation.type;
        existingLocal.lastMessageAt = conversation.lastMessageAt;
        existingLocal.isArchived = conversation.isArchived;
        existingLocal.isSynced = true;
        existingLocal.syncStatus = 'synced';
        existingLocal.lastModifiedServer = DateTime.now().toUtc();
        await db.localChatConversations.put(existingLocal);
        localConvo = existingLocal;
      } else {
        final newLocal = LocalChatConversation(
          serverId: conversation.id,
          userId: token.userId,
          title: conversation.title,
          type: conversation.type,
          createdAt: conversation.createdAt,
          lastMessageAt: conversation.lastMessageAt,
          isArchived: conversation.isArchived,
          isSynced: true,
          syncStatus: 'synced',
          lastModifiedLocal: DateTime.now().toUtc(),
          lastModifiedServer: DateTime.now().toUtc(),
        );
        await db.localChatConversations.put(newLocal);
        localConvo = newLocal;
      }

      for (final message in conversation.messages) {
        final existingMessage =
            await db.localChatMessages
                .filter()
                .serverIdEqualTo(message.id)
                .conversationLocalIdEqualTo(localConvo.localId)
                .findFirst();

        if (existingMessage == null) {
          final newMessage = LocalChatMessage(
            serverId: message.id,
            conversationLocalId: localConvo.localId,
            conversationServerId: conversation.id,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            inputTokens: message.inputTokens,
            outputTokens: message.outputTokens,
            model: message.model,
            isSynced: true,
            syncStatus: 'synced',
            lastModifiedLocal: DateTime.now().toUtc(),
          );
          await db.localChatMessages.put(newMessage);
        }
      }
    });

    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Acknowledges a successful [sendMessage] HTTP response by caching the
  /// user's message and the AI's response locally. The FIRST effective
  /// operation inside the transaction is a fresh re-resolution of the
  /// parent conversation by server ID + ownership - if it is missing (e.g.
  /// deleted while the AI request was in flight) or foreign, both messages
  /// are silently dropped rather than written as orphans.
  Future<void> _cacheMessageAcknowledgment(
    Isar db, {
    required int conversationId,
    required String userMessage,
    required ChatMessage aiResponse,
    required UserSessionToken token,
  }) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      // First effective operation: fresh parent-chain re-resolution.
      final localConvo =
          await db.localChatConversations
              .filter()
              .serverIdEqualTo(conversationId)
              .findFirst();
      if (localConvo == null || localConvo.userId != token.userId) return;

      final userMsg = LocalChatMessage(
        conversationLocalId: localConvo.localId,
        conversationServerId: conversationId,
        role: 'user',
        content: userMessage,
        createdAt: DateTime.now().toUtc(),
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await db.localChatMessages.put(userMsg);

      final aiMsg = LocalChatMessage(
        serverId: aiResponse.id,
        conversationLocalId: localConvo.localId,
        conversationServerId: conversationId,
        role: aiResponse.role,
        content: aiResponse.content,
        createdAt: aiResponse.createdAt,
        inputTokens: aiResponse.inputTokens,
        outputTokens: aiResponse.outputTokens,
        model: aiResponse.model,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await db.localChatMessages.put(aiMsg);

      localConvo.lastMessageAt = aiResponse.createdAt;
      await db.localChatConversations.put(localConvo);
    });

    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Same checkpoint shape as [_cacheConversationWithMessages], but deletes
  /// the conversation and every message scoped to its own `localId`
  /// instead of caching. Returns `true` only if a row owned by
  /// [token.userId] was actually found and deleted.
  Future<bool> _deleteOwnedConversation(
    Isar db,
    int conversationId,
    UserSessionToken token,
  ) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return false;

    var deleted = false;
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final current =
          await db.localChatConversations
              .filter()
              .serverIdEqualTo(conversationId)
              .findFirst();
      if (current == null || current.userId != token.userId) return;

      final messages =
          await db.localChatMessages
              .filter()
              .conversationLocalIdEqualTo(current.localId)
              .findAll();
      for (final msg in messages) {
        await db.localChatMessages.delete(msg.localId);
      }

      await db.localChatConversations.delete(current.localId);
      deleted = true;
    });

    await _runTestHook(afterWriteTxnForTesting);
    return deleted;
  }

  /// Shared shape for every "POST a prompt, get back a conversation +
  /// initial AI message(s)" operation ([createConversation],
  /// [generateWorkoutPlan], [generateMealPlan], [analyzeProgress]).
  /// [SessionStaleException]/[RequestCancelledException] are converted to
  /// this repository's [_unauthenticated] outcome without logging; every
  /// other failure is logged and rethrown unchanged, matching each
  /// method's pre-existing behavior.
  Future<ChatConversation> _createConversationViaPost(
    SessionRequestContext context,
    UserSessionToken token,
    Isar db,
    String path,
    Map<String, dynamic> data,
    String errorLabel,
  ) async {
    final Map<String, dynamic> response;
    try {
      response = await _apiService.post<Map<String, dynamic>>(
        path,
        data: data,
        sessionContext: context,
      );
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('❌ Error $errorLabel: $e');
      rethrow;
    }

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(afterForegroundHttpResponseForTesting);

    final conversation = ChatConversation.fromJson(response);
    await _cacheConversationWithMessages(db, conversation, token);

    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    return conversation;
  }

  // ============ Public operations ============

  /// Get all conversations for the current user.
  /// Offline-first: returns local cache immediately, syncs with server in
  /// background if online.
  Future<List<ChatConversation>> getConversations() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      debugPrint('⚠️ No authenticated session, returning empty list');
      return [];
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localConvos =
        await db.localChatConversations
            .filter()
            .userIdEqualTo(token.userId)
            .isArchivedEqualTo(false)
            .sortByLastMessageAtDesc()
            .findAll();
    if (!_sessionEpoch.isCurrent(token)) return [];

    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _syncConversationsFromServer(db, context),
        'Conversations synced from server',
      );
    }

    return localConvos.map((local) => _localToConversation(local)).toList();
  }

  /// Get a single conversation with all messages. Returns `null` if it is
  /// missing or belongs to a different user - the two are always
  /// indistinguishable. Requires online connection to fetch fresh messages;
  /// falls back to the local cache offline, or if the online fetch fails
  /// for any reason (never to a foreign cached row either way).
  Future<ChatConversation?> getConversation(int conversationId) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return null;
    final token = context.epochToken;
    final Isar db = _localDb.database;

    if (!_connectivity.isOnline) {
      return _localConversationWithMessages(db, conversationId, token);
    }

    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.chatConversationById(conversationId),
        sessionContext: context,
      );
      // Checkpoint: post-HTTP, before touching Isar at all.
      if (!_sessionEpoch.isCurrent(token)) return null;

      final conversation = ChatConversation.fromJson(data);
      if (conversation.userId != token.userId) {
        // Defense-in-depth: never trust a response claiming a different
        // owner than the session that requested it.
        return null;
      }

      await _cacheConversationWithMessages(db, conversation, token);
      // Checkpoint: after the acknowledgment writeTxn.
      if (!_sessionEpoch.isCurrent(token)) return null;

      return conversation;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching conversation: $e');
      // Fallback to cache - but ONLY for this same, still-current
      // session/user. An online failure (403/404 for a foreign ID,
      // network error, etc.) must never expose another user's cached
      // conversation; it can only ever surface what this user's own
      // local cache already has for this ID, which is exactly what
      // _localConversationWithMessages already scopes to.
      if (!_sessionEpoch.isCurrent(token)) return null;
      return _localConversationWithMessages(db, conversationId, token);
    }
  }

  /// Create a new conversation, always owned by the captured user.
  /// Requires online connection.
  Future<ChatConversation?> createConversation({
    required String title,
    required String type,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot create conversations offline',
    );
    final token = context.epochToken;
    final db = _localDb.database;

    return _createConversationViaPost(
      context,
      token,
      db,
      ApiConfig.chatConversations,
      {'title': title, 'type': type},
      'creating conversation',
    );
  }

  /// Send a message and get AI response. Requires online connection.
  Future<ChatMessage?> sendMessage({
    required int conversationId,
    required String message,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot send messages offline - AI requires connection',
    );
    final token = context.epochToken;
    final db = _localDb.database;

    final Map<String, dynamic> response;
    try {
      response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatMessages(conversationId),
        data: {'message': message, 'stream': false},
        sessionContext: context,
      );
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      rethrow;
    }

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(afterForegroundHttpResponseForTesting);

    final aiMessage = ChatMessage.fromJson(response);

    await _cacheMessageAcknowledgment(
      db,
      conversationId: conversationId,
      userMessage: message,
      aiResponse: aiMessage,
      token: token,
    );

    // Checkpoint: after the acknowledgment writeTxn.
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    return aiMessage;
  }

  /// Delete a conversation. Returns `true` only if an owned row was
  /// actually deleted server-side AND locally - a foreign or
  /// already-missing target safely no-ops and returns `false`, never
  /// deleting another user's row, and a server failure/staleness never
  /// purges local data. Requires online connection.
  Future<bool> deleteConversation(int conversationId) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return false;
    if (!_connectivity.isOnline) {
      throw Exception('Cannot delete conversations offline');
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    // Re-resolve the owned row BEFORE attempting the server delete - a
    // foreign or already-missing conversation must never even reach the
    // network call.
    final owned = await _ownedConversationByServerId(db, conversationId, token);
    if (owned == null) return false;

    bool serverSucceeded;
    try {
      serverSucceeded = await _apiService.delete(
        ApiConfig.chatConversationById(conversationId),
        sessionContext: context,
      );
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      debugPrint('❌ Error deleting conversation: $e');
      return false;
    }

    if (!serverSucceeded) return false;
    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return false;

    final deleted = await _deleteOwnedConversation(db, conversationId, token);
    // Checkpoint: after the delete transaction, before reporting any
    // caller-visible result - the session can end in the gap between
    // _deleteOwnedConversation's own internal afterWriteTxnForTesting hook
    // and this return, and a stale session by this point must not report a
    // misleading success back to a caller that no longer represents the
    // active session, regardless of whether the row was in fact deleted.
    if (!_sessionEpoch.isCurrent(token)) return false;
    if (deleted) {
      debugPrint('🗑️ Conversation deleted: $conversationId');
    }
    return deleted;
  }

  /// Generate workout plan (creates conversation + first AI response).
  /// Requires online connection.
  Future<ChatConversation?> generateWorkoutPlan({
    required String goal,
    required String experienceLevel,
    required int daysPerWeek,
    required String equipment,
    String? limitations,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot generate workout plan offline',
    );
    final token = context.epochToken;
    final db = _localDb.database;

    return _createConversationViaPost(
      context,
      token,
      db,
      ApiConfig.chatWorkoutPlan,
      {
        'goal': goal,
        'experienceLevel': experienceLevel,
        'daysPerWeek': daysPerWeek,
        'equipment': equipment,
        'limitations': limitations ?? '',
      },
      'generating workout plan',
    );
  }

  /// Generate meal plan (creates conversation + first AI response).
  /// Requires online connection.
  Future<ChatConversation?> generateMealPlan({
    required String dietaryGoal,
    int? targetCalories,
    String? macros,
    String? restrictions,
    String? preferences,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot generate meal plan offline',
    );
    final token = context.epochToken;
    final db = _localDb.database;

    return _createConversationViaPost(
      context,
      token,
      db,
      ApiConfig.chatMealPlan,
      {
        'dietaryGoal': dietaryGoal,
        'targetCalories': targetCalories,
        'macros': macros ?? '',
        'restrictions': restrictions ?? '',
        'preferences': preferences ?? '',
      },
      'generating meal plan',
    );
  }

  /// Analyze user's progress (creates conversation + AI analysis).
  /// Requires online connection.
  Future<ChatConversation?> analyzeProgress({
    DateTime? startDate,
    DateTime? endDate,
    String? focusArea,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot analyze progress offline',
    );
    final token = context.epochToken;
    final db = _localDb.database;

    final data = <String, dynamic>{};
    if (startDate != null) data['startDate'] = startDate.toIso8601String();
    if (endDate != null) data['endDate'] = endDate.toIso8601String();
    if (focusArea != null) data['focusArea'] = focusArea;

    return _createConversationViaPost(
      context,
      token,
      db,
      ApiConfig.chatAnalyzeProgress,
      data,
      'analyzing progress',
    );
  }

  /// Preview all 7 days of a meal plan for user selection.
  /// Requires online connection.
  Future<MealPlanPreview> previewMealPlan(int conversationId) async {
    final context = await _requireOnlineContext(
      'Cannot preview meal plan offline',
    );

    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.chatPreviewMealPlan(conversationId),
        sessionContext: context,
      );

      debugPrint(
        '✅ Previewed meal plan: ${response['days']?.length ?? 0} days',
      );

      return MealPlanPreview.fromJson(response);
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('❌ Error previewing meal plan: $e');
      rethrow;
    }
  }

  /// Apply meal plan from a conversation to today's meal log.
  /// [day] specifies which day (1-7) of the meal plan to apply.
  /// Requires online connection.
  Future<ApplyMealPlanResult> applyMealPlanToToday(
    int conversationId, {
    int day = 1,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot apply meal plan offline',
    );

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatApplyMealPlan(conversationId, day: day),
        sessionContext: context,
      );

      debugPrint(
        '✅ Applied meal plan day $day: ${response['foodsAdded']} foods added',
      );

      return ApplyMealPlanResult.fromJson(response);
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('❌ Error applying meal plan: $e');
      rethrow;
    }
  }

  /// Apply multiple days of a meal plan.
  /// [applyAllDays] - if true, applies all 7 days.
  /// [days] - specific days to apply (1-7), ignored if applyAllDays is true.
  /// [startDate] - the date to start applying from (defaults to today).
  /// [overwriteExisting] - if true, replaces existing meal entries.
  /// Requires online connection.
  Future<ApplyMealPlanWeekResult> applyMealPlanWeek(
    int conversationId, {
    bool applyAllDays = false,
    List<int>? days,
    DateTime? startDate,
    bool overwriteExisting = true,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot apply meal plan offline',
    );

    try {
      final data = <String, dynamic>{
        'applyAllDays': applyAllDays,
        'overwriteExisting': overwriteExisting,
      };
      if (days != null && !applyAllDays) {
        data['days'] = days;
      }
      if (startDate != null) {
        data['startDate'] = startDate.toIso8601String();
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatApplyMealPlanWeek(conversationId),
        data: data,
        sessionContext: context,
      );

      debugPrint('✅ Applied ${response['daysApplied']} days of meal plan');

      return ApplyMealPlanWeekResult.fromJson(response);
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('❌ Error applying meal plan week: $e');
      rethrow;
    }
  }

  /// Preview workout sessions from an AI-generated workout plan (without
  /// creating). Requires online connection.
  Future<Map<String, dynamic>> previewSessionsFromPlan({
    required int conversationId,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot preview sessions offline',
    );

    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.chatPreviewSessions(conversationId),
        sessionContext: context,
      );

      debugPrint(
        '✅ Previewed ${response['sessionsCount']} sessions from workout plan',
      );

      return response;
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('❌ Error previewing sessions: $e');
      rethrow;
    }
  }

  /// Create workout sessions from an AI-generated workout plan.
  /// Requires online connection - cannot create sessions offline.
  Future<Map<String, dynamic>> createSessionsFromPlan({
    required int conversationId,
    DateTime? startDate,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot create sessions offline',
    );

    try {
      final data = <String, dynamic>{};
      if (startDate != null) {
        data['startDate'] = startDate.toIso8601String();
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatCreateSessions(conversationId),
        data: data,
        sessionContext: context,
      );

      debugPrint(
        '✅ Created ${response['sessions'].length} sessions from workout plan',
      );

      return response;
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('❌ Error creating sessions from plan: $e');
      rethrow;
    }
  }

  /// Create a Program from an AI-generated workout plan.
  /// Requires online connection - cannot create programs offline.
  Future<Map<String, dynamic>> createProgramFromPlan({
    required int conversationId,
    String? title,
    String? description,
    int? goalId,
    int? totalWeeks,
    int? daysPerWeek,
    DateTime? startDate,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot create program offline',
    );

    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (description != null) data['description'] = description;
      if (goalId != null) data['goalId'] = goalId;
      if (totalWeeks != null) data['totalWeeks'] = totalWeeks;
      if (daysPerWeek != null) data['daysPerWeek'] = daysPerWeek;
      if (startDate != null) data['startDate'] = startDate.toIso8601String();

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatCreateProgram(conversationId),
        data: data,
        sessionContext: context,
      );

      debugPrint(
        '✅ Created program from workout plan: ${response['program']['title']}',
      );

      return response;
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('❌ Error creating program from plan: $e');
      rethrow;
    }
  }

  // ============ Background refresh ============

  /// Background sync: fetch conversations from server and update cache.
  /// Bound to [context]: the HTTP call carries its pinned JWT, and every
  /// cache write is gated behind the class doc comment's checkpoint shape
  /// plus a direct [LocalChatConversation.userId] ownership check.
  Future<void> _syncConversationsFromServer(
    Isar db,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    final response = await _dispatchBackgroundHttp(
      () => _apiService.get<List<dynamic>>(
        ApiConfig.chatConversations,
        sessionContext: context,
      ),
    );

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final apiConversations =
        response
            .map(
              (json) => ChatConversation.fromJson(json as Map<String, dynamic>),
            )
            .toList();

    final currentUserId = token.userId;

    // Checkpoint: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      // Checkpoint: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(token)) return;

      for (final apiConvo in apiConversations) {
        // The server itself already scopes this list to the authenticated
        // JWT (see GoHardAPI ChatController.GetConversations), but never
        // trust the payload's own userId field over the captured session
        // identity.
        if (apiConvo.userId != currentUserId) {
          continue;
        }

        final existingLocal =
            await db.localChatConversations
                .filter()
                .serverIdEqualTo(apiConvo.id)
                .findFirst();

        // Never overwrite a row that no longer belongs to the current
        // user - a serverId collision (or a foreign row somehow sharing
        // it) must never be silently claimed by this refresh.
        if (existingLocal != null && existingLocal.userId != currentUserId) {
          debugPrint(
            '⏭️ Skipping conversation ${apiConvo.id} - local row owned by '
            'a different user',
          );
          continue;
        }

        // Never clobber a locally pending row that has not yet round
        // -tripped through the server.
        if (existingLocal != null &&
            (existingLocal.syncStatus == 'pending_delete' ||
                existingLocal.syncStatus == 'pending_update')) {
          continue;
        }

        if (existingLocal != null) {
          existingLocal.title = apiConvo.title;
          existingLocal.type = apiConvo.type;
          existingLocal.lastMessageAt = apiConvo.lastMessageAt;
          existingLocal.isArchived = apiConvo.isArchived;
          existingLocal.isSynced = true;
          existingLocal.syncStatus = 'synced';
          existingLocal.lastModifiedServer = DateTime.now().toUtc();

          await db.localChatConversations.put(existingLocal);
        } else {
          final newLocal = LocalChatConversation(
            serverId: apiConvo.id,
            userId: currentUserId,
            title: apiConvo.title,
            type: apiConvo.type,
            createdAt: apiConvo.createdAt,
            lastMessageAt: apiConvo.lastMessageAt,
            isArchived: apiConvo.isArchived,
            isSynced: true,
            syncStatus: 'synced',
            lastModifiedLocal: DateTime.now().toUtc(),
            lastModifiedServer: DateTime.now().toUtc(),
          );

          await db.localChatConversations.put(newLocal);
        }
      }
    });

    debugPrint(
      '🔄 Synced ${apiConversations.length} conversations from server',
    );
  }

  // ============ Local <-> model mapping ============

  ChatConversation _localToConversation(LocalChatConversation local) {
    return ChatConversation(
      id: local.serverId ?? 0,
      userId: local.userId,
      title: local.title,
      type: local.type,
      createdAt: local.createdAt,
      lastMessageAt: local.lastMessageAt,
      isArchived: local.isArchived,
      messageCount: 0, // Will be loaded when conversation is opened
    );
  }

  ChatMessage _localToMessage(LocalChatMessage local, int conversationId) {
    return ChatMessage(
      id: local.serverId ?? 0,
      conversationId: conversationId,
      role: local.role,
      content: local.content,
      createdAt: local.createdAt,
      inputTokens: local.inputTokens,
      outputTokens: local.outputTokens,
      model: local.model,
    );
  }
}

/// Result of applying a meal plan to today's log
class ApplyMealPlanResult {
  final bool success;
  final String message;
  final int foodsAdded;
  final double totalCaloriesAdded;
  final double totalProteinAdded;
  final double totalCarbsAdded;
  final double totalFatAdded;

  /// Whether the nutrition goal was updated
  final bool goalUpdated;

  /// New daily calorie goal (if updated)
  final double? newDailyCalorieGoal;

  /// New daily protein goal (if updated)
  final double? newDailyProteinGoal;

  /// New daily carbs goal (if updated)
  final double? newDailyCarbsGoal;

  /// New daily fat goal (if updated)
  final double? newDailyFatGoal;

  ApplyMealPlanResult({
    required this.success,
    required this.message,
    required this.foodsAdded,
    required this.totalCaloriesAdded,
    required this.totalProteinAdded,
    required this.totalCarbsAdded,
    required this.totalFatAdded,
    this.goalUpdated = false,
    this.newDailyCalorieGoal,
    this.newDailyProteinGoal,
    this.newDailyCarbsGoal,
    this.newDailyFatGoal,
  });

  factory ApplyMealPlanResult.fromJson(Map<String, dynamic> json) {
    return ApplyMealPlanResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      foodsAdded: json['foodsAdded'] as int? ?? 0,
      totalCaloriesAdded: (json['totalCaloriesAdded'] as num?)?.toDouble() ?? 0,
      totalProteinAdded: (json['totalProteinAdded'] as num?)?.toDouble() ?? 0,
      totalCarbsAdded: (json['totalCarbsAdded'] as num?)?.toDouble() ?? 0,
      totalFatAdded: (json['totalFatAdded'] as num?)?.toDouble() ?? 0,
      goalUpdated: json['goalUpdated'] as bool? ?? false,
      newDailyCalorieGoal: (json['newDailyCalorieGoal'] as num?)?.toDouble(),
      newDailyProteinGoal: (json['newDailyProteinGoal'] as num?)?.toDouble(),
      newDailyCarbsGoal: (json['newDailyCarbsGoal'] as num?)?.toDouble(),
      newDailyFatGoal: (json['newDailyFatGoal'] as num?)?.toDouble(),
    );
  }
}

/// Preview of a 7-day meal plan for user selection
class MealPlanPreview {
  final bool success;
  final String? message;
  final double targetCalories;
  final List<MealPlanDayPreview> days;

  MealPlanPreview({
    required this.success,
    this.message,
    required this.targetCalories,
    required this.days,
  });

  factory MealPlanPreview.fromJson(Map<String, dynamic> json) {
    return MealPlanPreview(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      targetCalories: (json['targetCalories'] as num?)?.toDouble() ?? 2000,
      days:
          (json['days'] as List<dynamic>?)
              ?.map(
                (d) => MealPlanDayPreview.fromJson(d as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

/// Preview of a single day in the meal plan
class MealPlanDayPreview {
  final int day;
  final String summary;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final bool isWithinTarget;
  final List<MealPreview> meals;

  MealPlanDayPreview({
    required this.day,
    required this.summary,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.isWithinTarget,
    required this.meals,
  });

  factory MealPlanDayPreview.fromJson(Map<String, dynamic> json) {
    return MealPlanDayPreview(
      day: json['day'] as int? ?? 1,
      summary: json['summary'] as String? ?? '',
      totalCalories: (json['totalCalories'] as num?)?.toDouble() ?? 0,
      totalProtein: (json['totalProtein'] as num?)?.toDouble() ?? 0,
      totalCarbs: (json['totalCarbs'] as num?)?.toDouble() ?? 0,
      totalFat: (json['totalFat'] as num?)?.toDouble() ?? 0,
      isWithinTarget: json['isWithinTarget'] as bool? ?? false,
      meals:
          (json['meals'] as List<dynamic>?)
              ?.map((m) => MealPreview.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Preview of a single meal
class MealPreview {
  final String mealType;
  final List<String> foods;
  final double calories;

  MealPreview({
    required this.mealType,
    required this.foods,
    required this.calories,
  });

  factory MealPreview.fromJson(Map<String, dynamic> json) {
    return MealPreview(
      mealType: json['mealType'] as String? ?? '',
      foods:
          (json['foods'] as List<dynamic>?)
              ?.map((f) => f.toString())
              .toList() ??
          [],
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Result of applying multiple days of a meal plan
class ApplyMealPlanWeekResult {
  final bool success;
  final String message;
  final int daysApplied;
  final int totalFoodsAdded;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final List<DayApplyResult> dayResults;

  ApplyMealPlanWeekResult({
    required this.success,
    required this.message,
    required this.daysApplied,
    required this.totalFoodsAdded,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.dayResults,
  });

  factory ApplyMealPlanWeekResult.fromJson(Map<String, dynamic> json) {
    return ApplyMealPlanWeekResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      daysApplied: json['daysApplied'] as int? ?? 0,
      totalFoodsAdded: json['totalFoodsAdded'] as int? ?? 0,
      totalCalories: (json['totalCalories'] as num?)?.toDouble() ?? 0,
      totalProtein: (json['totalProtein'] as num?)?.toDouble() ?? 0,
      totalCarbs: (json['totalCarbs'] as num?)?.toDouble() ?? 0,
      totalFat: (json['totalFat'] as num?)?.toDouble() ?? 0,
      dayResults:
          (json['dayResults'] as List<dynamic>?)
              ?.map((d) => DayApplyResult.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Result for each day applied in a multi-day meal plan application
class DayApplyResult {
  final int day;
  final DateTime date;
  final int foodsAdded;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  DayApplyResult({
    required this.day,
    required this.date,
    required this.foodsAdded,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  factory DayApplyResult.fromJson(Map<String, dynamic> json) {
    return DayApplyResult(
      day: json['day'] as int? ?? 0,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      foodsAdded: json['foodsAdded'] as int? ?? 0,
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
    );
  }
}
