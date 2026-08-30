import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_chat_conversation.dart';
import 'package:go_hard_app/data/local/models/local_chat_message.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/repositories/chat_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'chat_repository_session_ownership_test.mocks.dart';

@GenerateMocks([AuthService, ConnectivityService])
/// Proves that ChatRepository is fully session-bound (every HTTP call,
/// foreground and background, carries the session that started the
/// operation) and locally ownership-safe (every conversation/message read
/// and write is scoped to the calling user, with messages proven through a
/// fresh parent-chain lookup), mirroring
/// `running_repository_session_ownership_test.dart`.
///
/// Uses a REAL [ApiService] wired to a fake [HttpClientAdapter] so
/// credential pinning and dispatch-time staleness rejection are proven
/// against the real production interceptor pipeline, not a stub of it.
///
/// ## Deterministic synchronization
///
/// No test in this file uses a wall-clock delay to prove detached work has
/// finished:
///
/// - [_FakeHttpClientAdapter.nextDispatch] completes the instant the fake
///   transport's `fetch()` is actually invoked.
/// - `scheduledBackgroundSyncs` collects the exact `Future<void>` each
///   [ChatRepository._backgroundSync] call hands back via the
///   `onBackgroundSyncScheduledForTesting` seam - it completes only once
///   that specific detached operation has fully settled. Awaiting
///   `scheduledBackgroundSyncs.single` is both the completion wait and an
///   implicit assertion that exactly one background operation was
///   scheduled.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late ChatRepository repository;
  late List<Future<void>> scheduledBackgroundSyncs;

  const userA = 1;
  const userB = 2;

  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_repo_owner_');
    isar = await Isar.open(
      [LocalChatConversationSchema, LocalChatMessageSchema],
      directory: tempDir.path,
      inspector: false,
    );

    currentAuthUserId = null;
    mockAuthService = MockAuthService();
    mockConnectivity = MockConnectivityService();
    when(mockConnectivity.isOnline).thenReturn(true);
    when(
      mockAuthService.getUserId(),
    ).thenAnswer((_) async => currentAuthUserId);
    when(mockAuthService.getToken()).thenAnswer(
      (_) async => currentAuthUserId == null ? null : 'jwt-$currentAuthUserId',
    );

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch();
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );
    apiService = ApiService(mockAuthService, sessionEpoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;

    repository = ChatRepository(
      apiService,
      localDb,
      mockConnectivity,
      mockAuthService,
      sessionEpoch,
      sessionCoordinator,
    );

    scheduledBackgroundSyncs = [];
    repository.onBackgroundSyncScheduledForTesting =
        scheduledBackgroundSyncs.add;
  });

  tearDown(() async {
    repository.beforeWriteTxnForTesting = null;
    repository.insideWriteTxnForTesting = null;
    repository.afterWriteTxnForTesting = null;
    repository.beforeBackgroundHttpDispatchForTesting = null;
    repository.afterBackgroundHttpResponseForTesting = null;
    repository.afterForegroundHttpResponseForTesting = null;
    repository.onBackgroundSyncScheduledForTesting = null;
    apiService.beforeDispatchEpochCheckForTesting = null;
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  void loginAs(int userId) {
    currentAuthUserId = userId;
    sessionEpoch.activate(userId);
  }

  void logout() {
    currentAuthUserId = null;
    sessionEpoch.invalidate();
  }

  // ============ Seed helpers ============

  Future<LocalChatConversation> insertConversation({
    int uid = userA,
    int? serverId,
    String title = 'Conversation',
    String type = 'general',
    bool isArchived = false,
    String syncStatus = 'synced',
    bool? isSynced,
    DateTime? lastMessageAt,
  }) async {
    final convo = LocalChatConversation(
      serverId: serverId,
      userId: uid,
      title: title,
      type: type,
      createdAt: DateTime.utc(2026, 1, 1),
      lastMessageAt: lastMessageAt,
      isArchived: isArchived,
      isSynced: isSynced ?? (serverId != null),
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now().toUtc(),
    );
    await isar.writeTxn(() => isar.localChatConversations.put(convo));
    return convo;
  }

  Future<LocalChatMessage> insertMessage({
    required int conversationLocalId,
    int? conversationServerId,
    int? serverId,
    String role = 'user',
    String content = 'hi',
  }) async {
    final msg = LocalChatMessage(
      serverId: serverId,
      conversationLocalId: conversationLocalId,
      conversationServerId: conversationServerId,
      role: role,
      content: content,
      createdAt: DateTime.now().toUtc(),
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.now().toUtc(),
    );
    await isar.writeTxn(() => isar.localChatMessages.put(msg));
    return msg;
  }

  Map<String, dynamic> conversationJson({
    required int id,
    required int userId,
    String title = 'Conversation',
    String type = 'general',
    DateTime? createdAt,
    DateTime? lastMessageAt,
    bool isArchived = false,
    List<Map<String, dynamic>> messages = const [],
  }) => {
    'id': id,
    'userId': userId,
    'title': title,
    'type': type,
    'createdAt': (createdAt ?? DateTime.utc(2026, 1, 1)).toIso8601String(),
    'lastMessageAt': lastMessageAt?.toIso8601String(),
    'isArchived': isArchived,
    'messages': messages,
    'messageCount': messages.length,
  };

  Map<String, dynamic> messageJson({
    required int id,
    required int conversationId,
    String role = 'assistant',
    String content = 'Hello',
    DateTime? createdAt,
  }) => {
    'id': id,
    'conversationId': conversationId,
    'role': role,
    'content': content,
    'createdAt': (createdAt ?? DateTime.utc(2026, 1, 1)).toIso8601String(),
    'inputTokens': null,
    'outputTokens': null,
    'model': null,
  };

  ResponseBody jsonResponse(Object? json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  Matcher throwsNotAuthenticated() => throwsA(
    isA<Exception>().having(
      (e) => e.toString(),
      'message',
      contains('No authenticated user'),
    ),
  );

  // ============ 1. Logged out ============

  group('logged out', () {
    test('every method performs no Isar mutation and no HTTP when logged out '
        '(req 1)', () async {
      final untouched = await insertConversation(uid: userA, serverId: 1);

      expect(await repository.getConversations(), isEmpty);
      expect(await repository.getConversation(1), isNull);
      await expectLater(
        () => repository.createConversation(title: 'T', type: 'general'),
        throwsNotAuthenticated(),
      );
      await expectLater(
        () => repository.sendMessage(conversationId: 1, message: 'hi'),
        throwsNotAuthenticated(),
      );
      expect(await repository.deleteConversation(1), isFalse);
      await expectLater(
        () => repository.generateWorkoutPlan(
          goal: 'g',
          experienceLevel: 'b',
          daysPerWeek: 3,
          equipment: 'none',
        ),
        throwsNotAuthenticated(),
      );
      await expectLater(
        () => repository.generateMealPlan(dietaryGoal: 'g'),
        throwsNotAuthenticated(),
      );
      await expectLater(
        () => repository.analyzeProgress(),
        throwsNotAuthenticated(),
      );
      await expectLater(
        () => repository.previewMealPlan(1),
        throwsNotAuthenticated(),
      );
      await expectLater(
        () => repository.applyMealPlanToToday(1),
        throwsNotAuthenticated(),
      );
      await expectLater(
        () => repository.applyMealPlanWeek(1),
        throwsNotAuthenticated(),
      );
      await expectLater(
        () => repository.previewSessionsFromPlan(conversationId: 1),
        throwsNotAuthenticated(),
      );
      await expectLater(
        () => repository.createSessionsFromPlan(conversationId: 1),
        throwsNotAuthenticated(),
      );
      await expectLater(
        () => repository.createProgramFromPlan(conversationId: 1),
        throwsNotAuthenticated(),
      );

      expect(adapter.capturedRequests, isEmpty);
      final stillThere = await isar.localChatConversations.get(
        untouched.localId,
      );
      expect(stillThere, isNotNull);
      expect(stillThere!.title, untouched.title);
    });
  });

  // ============ 2. Local conversation list scoping ============

  group('local conversation list', () {
    test('getConversations returns only the current user\'s non-archived '
        'conversations (req 2)', () async {
      when(mockConnectivity.isOnline).thenReturn(false);
      loginAs(userA);
      await insertConversation(uid: userA, serverId: 1, title: 'A1');
      await insertConversation(uid: userB, serverId: 2, title: 'B1');
      await insertConversation(
        uid: userA,
        serverId: 3,
        title: 'A2 archived',
        isArchived: true,
      );

      final result = await repository.getConversations();

      expect(result.map((c) => c.title), ['A1']);
    });
  });

  // ============ 3-5. getConversation offline/fallback ownership ============

  group('getConversation offline and fallback ownership', () {
    test('offline returns null for foreign/missing and the row for owned '
        '(req 3)', () async {
      when(mockConnectivity.isOnline).thenReturn(false);
      loginAs(userA);
      final owned = await insertConversation(
        uid: userA,
        serverId: 1,
        title: 'Mine',
      );
      await insertMessage(
        conversationLocalId: owned.localId,
        conversationServerId: 1,
        content: 'hi',
      );
      await insertConversation(uid: userB, serverId: 2, title: 'Theirs');

      expect(await repository.getConversation(2), isNull);
      expect(await repository.getConversation(999), isNull);

      final mine = await repository.getConversation(1);
      expect(mine, isNotNull);
      expect(mine!.title, 'Mine');
      expect(mine.messages, hasLength(1));
    });

    test('online failure does not fall back to a foreign cached conversation '
        '(req 4)', () async {
      loginAs(userA);
      await insertConversation(uid: userB, serverId: 2, title: 'Theirs');
      adapter.responder =
          (_) async => ResponseBody.fromString('{"message":"boom"}', 404);

      final result = await repository.getConversation(2);

      expect(result, isNull);
    });

    test('online failure DOES fall back to the SAME user\'s cached '
        'conversation (req 5)', () async {
      loginAs(userA);
      final mine = await insertConversation(
        uid: userA,
        serverId: 3,
        title: 'Cached mine',
      );
      await insertMessage(
        conversationLocalId: mine.localId,
        conversationServerId: 3,
        content: 'hey',
      );
      adapter.responder =
          (_) async => ResponseBody.fromString('{"message":"boom"}', 500);

      final result = await repository.getConversation(3);

      expect(result, isNotNull);
      expect(result!.title, 'Cached mine');
      expect(result.messages, hasLength(1));
    });
  });

  // ============ 6-7. Cache-write ownership ============

  group('cache-write ownership', () {
    test('a foreign server-ID collision cannot overwrite a row owned by a '
        'different user (req 6)', () async {
      final foreignRow = await insertConversation(
        uid: userB,
        serverId: 9,
        title: 'B original',
      );
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse(
            conversationJson(id: 9, userId: userA, title: 'A attempt'),
          );

      await repository.getConversation(9);

      final stored = await isar.localChatConversations.get(foreignRow.localId);
      expect(stored!.userId, userB);
      expect(stored.title, 'B original');
    });

    test('cache writes stamp ownership from the captured context, never the '
        'response payload\'s own userId field (req 7)', () async {
      loginAs(userA);
      // Server payload claims a different userId than the captured
      // context - should never happen from a correctly-scoped API, but
      // this proves the local row is always stamped from the session,
      // not this field.
      adapter.responder =
          (_) async => jsonResponse(
            conversationJson(id: 11, userId: 999, title: 'Weird payload'),
          );

      final result = await repository.createConversation(
        title: 'T',
        type: 'general',
      );

      expect(result, isNotNull);
      final stored =
          await isar.localChatConversations
              .filter()
              .serverIdEqualTo(11)
              .findFirst();
      expect(
        stored!.userId,
        userA,
        reason:
            'must be stamped with the CAPTURED session\'s user, never '
            'the untrusted response payload\'s own userId field',
      );
    });
  });

  // ============ 8-10. Message parent-chain ownership ============

  group('message parent-chain ownership', () {
    test('message reads are scoped to the parent\'s own localId, rejecting '
        'orphans and foreign parents (req 8, req 9)', () async {
      when(mockConnectivity.isOnline).thenReturn(false);
      loginAs(userA);
      final mine = await insertConversation(
        uid: userA,
        serverId: 5,
        title: 'Mine',
      );
      await insertMessage(
        conversationLocalId: mine.localId,
        conversationServerId: 5,
        content: 'my message',
      );
      // A stray message row that claims the SAME conversationServerId
      // but whose conversationLocalId does not resolve to this (or any)
      // conversation - simulating an orphan/drifted row.
      await insertMessage(
        conversationLocalId: 999999,
        conversationServerId: 5,
        content: 'orphaned drift',
      );

      final result = await repository.getConversation(5);

      expect(result!.messages, hasLength(1));
      expect(result.messages.single.content, 'my message');
    });

    test('a foreign message-serverId collision cannot overwrite an owned '
        'message (req 10)', () async {
      final foreignConvo = await insertConversation(uid: userB, serverId: 20);
      final foreignMsg = await insertMessage(
        conversationLocalId: foreignConvo.localId,
        conversationServerId: 20,
        serverId: 500,
        content: 'B\'s message',
      );

      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse(
            conversationJson(
              id: 21,
              userId: userA,
              title: 'A convo',
              messages: [
                messageJson(
                  id: 500,
                  conversationId: 21,
                  role: 'assistant',
                  content: 'A hijack attempt',
                ),
              ],
            ),
          );

      await repository.createConversation(title: 'A convo', type: 'general');

      final stillForeign = await isar.localChatMessages.get(foreignMsg.localId);
      expect(
        stillForeign!.content,
        'B\'s message',
        reason:
            'a message serverId collision across different parent '
            'conversations must never overwrite the foreign message row',
      );

      final myConvo =
          await isar.localChatConversations
              .filter()
              .serverIdEqualTo(21)
              .findFirst();
      final myMessages =
          await isar.localChatMessages
              .filter()
              .conversationLocalIdEqualTo(myConvo!.localId)
              .findAll();
      expect(myMessages, hasLength(1));
      expect(myMessages.single.content, 'A hijack attempt');
      expect(
        myMessages.single.serverId,
        500,
        reason:
            'a fresh, correctly-parented row is created rather than '
            'touching the foreign one, even though the server id (500) '
            'collides',
      );
    });
  });

  // ============ 11. Every ApiService call is bound ============

  test(
    'every foreground ApiService call is bound to sessionContext (req 11)',
    () async {
      loginAs(userA);
      await insertConversation(uid: userA, serverId: 1, title: 'Seed');

      final scenarios = <String, Future<void> Function()>{
        'getConversation': () => repository.getConversation(1),
        'createConversation':
            () => repository.createConversation(title: 'T', type: 'general'),
        'sendMessage':
            () => repository.sendMessage(conversationId: 1, message: 'hi'),
        'deleteConversation': () => repository.deleteConversation(1),
        'generateWorkoutPlan':
            () => repository.generateWorkoutPlan(
              goal: 'g',
              experienceLevel: 'b',
              daysPerWeek: 3,
              equipment: 'none',
            ),
        'generateMealPlan': () => repository.generateMealPlan(dietaryGoal: 'g'),
        'analyzeProgress': () => repository.analyzeProgress(),
        'previewMealPlan': () => repository.previewMealPlan(1),
        'applyMealPlanToToday': () => repository.applyMealPlanToToday(1),
        'applyMealPlanWeek': () => repository.applyMealPlanWeek(1),
        'previewSessionsFromPlan':
            () => repository.previewSessionsFromPlan(conversationId: 1),
        'createSessionsFromPlan':
            () => repository.createSessionsFromPlan(conversationId: 1),
        'createProgramFromPlan':
            () => repository.createProgramFromPlan(conversationId: 1),
      };

      for (final entry in scenarios.entries) {
        // Re-login (same user, fresh generation) before each scenario so
        // the staleness hook below has a genuinely current context to
        // invalidate mid-dispatch.
        logout();
        loginAs(userA);
        adapter.capturedRequests.clear();
        apiService.beforeDispatchEpochCheckForTesting = () async => logout();

        try {
          await entry.value();
        } catch (_) {
          // Expected for most scenarios - the assertion below is what
          // actually proves the point.
        }

        expect(
          adapter.capturedRequests,
          isEmpty,
          reason:
              '${entry.key} must be bound to sessionContext - an unbound '
              'call ignores the mid-dispatch staleness hook and would '
              'still reach the network',
        );

        apiService.beforeDispatchEpochCheckForTesting = null;
      }
    },
  );

  // ============ 12. Detached refresh context capture ============

  test('the background refresh\'s context is pinned at scheduling time, not '
      're-captured at execution (req 12)', () async {
    loginAs(userA);
    final responseCompleter = Completer<ResponseBody>();
    adapter.responder = (_) => responseCompleter.future;

    final dispatched = adapter.nextDispatch();
    // Deliberately NOT awaited here: the point is to flip the live token
    // before this call's own internal awaits (context capture, the local
    // Isar read, scheduling the background sync) have had a chance to
    // resolve - exactly like the equivalent RunningRepository test. If the
    // background closure (re)captured its own context lazily instead of
    // reusing the one captured at scheduling time, it would read the
    // flipped token on ITS OWN later getToken() call, which only happens
    // once the event loop actually resumes below.
    final getConversationsFuture = repository.getConversations();

    // Simulate secure storage now holding B's token, WITHOUT going
    // through logout()/loginAs() (the real epoch is untouched).
    currentAuthUserId = userB;

    await dispatched;

    expect(
      adapter.capturedRequests.single.headers['Authorization'],
      'Bearer jwt-$userA',
    );

    responseCompleter.complete(jsonResponse(<dynamic>[]));
    await getConversationsFuture;
    await scheduledBackgroundSyncs.single;
  });

  // ============ 13-14. Logout/account-switch races ============

  group('logout/account-switch races', () {
    test(
      'logout before dispatch produces no write and no request (req 13)',
      () async {
        loginAs(userA);
        apiService.beforeDispatchEpochCheckForTesting = () async => logout();

        await expectLater(
          () => repository.createConversation(title: 'T', type: 'general'),
          throwsNotAuthenticated(),
        );

        expect(adapter.capturedRequests, isEmpty);
        expect(await isar.localChatConversations.where().findAll(), isEmpty);
      },
    );

    test('logout after HTTP success but before acknowledgment produces no '
        'write (req 14)', () async {
      loginAs(userA);
      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      final created = repository.createConversation(
        title: 'T',
        type: 'general',
      );
      await dispatched;

      logout();
      responseCompleter.complete(
        jsonResponse(conversationJson(id: 1, userId: userA)),
      );

      await expectLater(() => created, throwsNotAuthenticated());
      expect(await isar.localChatConversations.where().findAll(), isEmpty);
    });

    test('the post-HTTP checkpoint in createConversation rejects before ever '
        'running the after-response hook, not relying on a later '
        'structurally-shadowing check', () async {
      loginAs(userA);
      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;
      var hookFired = false;
      repository.afterForegroundHttpResponseForTesting = () async {
        hookFired = true;
      };

      final dispatched = adapter.nextDispatch();
      final created = repository.createConversation(
        title: 'T',
        type: 'general',
      );
      await dispatched;

      logout();
      responseCompleter.complete(
        jsonResponse(conversationJson(id: 1, userId: userA)),
      );

      await expectLater(() => created, throwsNotAuthenticated());

      expect(
        hookFired,
        isFalse,
        reason:
            'the post-HTTP checkpoint must reject and return immediately '
            'once the response arrives under a stale session, before '
            'ever reaching the after-response hook - '
            '_cacheConversationWithMessages catching the same '
            'staleness later is not a substitute for this earlier exit',
      );
    });

    test('the post-HTTP checkpoint in sendMessage rejects before ever '
        'running the after-response hook, not relying on a later '
        'structurally-shadowing check', () async {
      loginAs(userA);
      await insertConversation(uid: userA, serverId: 1);
      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;
      var hookFired = false;
      repository.afterForegroundHttpResponseForTesting = () async {
        hookFired = true;
      };

      final dispatched = adapter.nextDispatch();
      final sent = repository.sendMessage(conversationId: 1, message: 'hi');
      await dispatched;

      logout();
      responseCompleter.complete(
        jsonResponse(messageJson(id: 1, conversationId: 1, content: 'reply')),
      );

      await expectLater(() => sent, throwsNotAuthenticated());

      expect(hookFired, isFalse);
    });

    test('the pre-writeTxn checkpoint in _cacheConversationWithMessages '
        'avoids entering the transaction at all once already stale', () async {
      loginAs(userA);
      var enteredTxn = false;
      repository.beforeWriteTxnForTesting = () async => logout();
      repository.insideWriteTxnForTesting = () async {
        enteredTxn = true;
      };
      adapter.responder =
          (_) async => jsonResponse(conversationJson(id: 1, userId: userA));

      await expectLater(
        () => repository.createConversation(title: 'T', type: 'general'),
        throwsNotAuthenticated(),
      );

      expect(
        enteredTxn,
        isFalse,
        reason:
            'once the session is already known stale immediately before '
            'entering writeTxn, the checkpoint there must skip starting '
            'the transaction altogether, rather than relying solely on '
            'the first-statement-inside-writeTxn check to reject after '
            'the fact',
      );
    });

    test('the first-statement-inside-writeTxn checkpoint in '
        '_cacheConversationWithMessages prevents a write when the session '
        'goes stale mid-transaction, not just before it', () async {
      loginAs(userA);
      repository.insideWriteTxnForTesting = () async => logout();
      adapter.responder =
          (_) async => jsonResponse(conversationJson(id: 2, userId: userA));

      await expectLater(
        () => repository.createConversation(title: 'T', type: 'general'),
        throwsNotAuthenticated(),
      );

      final stored =
          await isar.localChatConversations
              .filter()
              .serverIdEqualTo(2)
              .findFirst();
      expect(
        stored,
        isNull,
        reason:
            'a session that goes stale after entering the write '
            'transaction must still block the write - the '
            'before-entering-the-transaction check alone is not '
            'sufficient, since the session can end while Isar\'s write '
            'lock is being awaited',
      );
    });
  });

  // ============ 15. clearAll cannot be followed by resurrection ============

  test('logout clearAll cannot be followed by a stale background sync '
      'resurrecting A\'s data under B (req 15)', () async {
    loginAs(userA);
    final responseCompleter = Completer<ResponseBody>();
    adapter.responder = (_) => responseCompleter.future;

    final dispatched = adapter.nextDispatch();
    await repository.getConversations();
    await dispatched;

    // Simulate logout's clearAll() wiping the database, then B logging
    // in.
    await isar.writeTxn(() => isar.clear());
    logout();
    loginAs(userB);

    responseCompleter.complete(
      jsonResponse([conversationJson(id: 10, userId: userA, title: 'A convo')]),
    );
    await scheduledBackgroundSyncs.single;

    final stored = await isar.localChatConversations.where().findAll();
    expect(
      stored,
      isEmpty,
      reason:
          'A\'s stale background sync must never resurrect data after '
          'clearAll, even though it is still "successfully" completing '
          'under B\'s now-active session',
    );
  });

  // ============ 16-17. _syncConversationsFromServer ownership ============

  group('_syncConversationsFromServer ownership', () {
    test('cannot overwrite a foreign server-ID row (req 16)', () async {
      final foreign = await insertConversation(
        uid: userB,
        serverId: 42,
        title: 'B convo',
      );
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse([
            conversationJson(id: 42, userId: userA, title: 'Hijacked'),
          ]);

      await repository.getConversations();
      await Future.wait(scheduledBackgroundSyncs);

      final stored = await isar.localChatConversations.get(foreign.localId);
      expect(stored!.title, 'B convo');
      expect(stored.userId, userB);
    });

    test('preserves pending_delete and pending_update rows (req 17)', () async {
      loginAs(userA);
      final pendingDelete = await insertConversation(
        uid: userA,
        serverId: 7,
        title: 'Original delete',
        syncStatus: 'pending_delete',
      );
      final pendingUpdate = await insertConversation(
        uid: userA,
        serverId: 8,
        title: 'Original update',
        syncStatus: 'pending_update',
      );
      adapter.responder =
          (_) async => jsonResponse([
            conversationJson(id: 7, userId: userA, title: 'Server delete'),
            conversationJson(id: 8, userId: userA, title: 'Server update'),
          ]);

      await repository.getConversations();
      await Future.wait(scheduledBackgroundSyncs);

      final storedDelete = await isar.localChatConversations.get(
        pendingDelete.localId,
      );
      final storedUpdate = await isar.localChatConversations.get(
        pendingUpdate.localId,
      );
      expect(storedDelete!.title, 'Original delete');
      expect(storedDelete.syncStatus, 'pending_delete');
      expect(storedUpdate!.title, 'Original update');
      expect(storedUpdate.syncStatus, 'pending_update');
    });
  });

  // ============ 18-19. deleteConversation ownership/failure ============

  group('deleteConversation', () {
    test('a local ID reused by a different user\'s row during the server '
        'round-trip is re-resolved fresh, never deleted via a stale '
        'closure-captured reference', () async {
      loginAs(userA);
      final convo = await insertConversation(
        uid: userA,
        serverId: 1,
        title: 'Original',
      );
      final reusedLocalId = convo.localId;

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;
      final dispatched = adapter.nextDispatch();
      final deleteFuture = repository.deleteConversation(1);
      await dispatched;

      // While the server round-trip is in flight, this local row is
      // wiped and replaced by a DIFFERENT user's conversation that
      // happens to reuse both the same local ID (Isar's auto-increment
      // resets after a full clear) AND the same server ID.
      await isar.writeTxn(() => isar.localChatConversations.clear());
      final replacement = LocalChatConversation(
        serverId: 1,
        userId: userB,
        title: 'B replacement',
        type: 'general',
        createdAt: DateTime.utc(2026, 1, 1),
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now().toUtc(),
      )..localId = reusedLocalId;
      await isar.writeTxn(() => isar.localChatConversations.put(replacement));

      responseCompleter.complete(ResponseBody.fromString('', 204));
      await deleteFuture;

      final stillThere = await isar.localChatConversations.get(reusedLocalId);
      expect(
        stillThere,
        isNotNull,
        reason:
            'A\'s delete must never remove B\'s row just because it '
            'reused the same local ID after a clear - the acknowledgment '
            'must re-resolve by serverId + ownership fresh, never reuse '
            'the localId captured before the server round-trip',
      );
      expect(stillThere!.userId, userB);
      expect(stillThere.title, 'B replacement');
    });

    test(
      'purges only the owned conversation and its own messages (req 18)',
      () async {
        loginAs(userA);
        final convoA = await insertConversation(uid: userA, serverId: 1);
        final msgA1 = await insertMessage(
          conversationLocalId: convoA.localId,
          conversationServerId: 1,
          content: 'hi',
        );
        final convoOther = await insertConversation(uid: userA, serverId: 2);
        final msgOther = await insertMessage(
          conversationLocalId: convoOther.localId,
          conversationServerId: 2,
          content: 'other',
        );

        adapter.responder = (_) async => ResponseBody.fromString('', 204);
        final deleted = await repository.deleteConversation(1);

        expect(deleted, isTrue);
        expect(await isar.localChatConversations.get(convoA.localId), isNull);
        expect(await isar.localChatMessages.get(msgA1.localId), isNull);
        expect(
          await isar.localChatConversations.get(convoOther.localId),
          isNotNull,
        );
        expect(await isar.localChatMessages.get(msgOther.localId), isNotNull);
      },
    );

    test(
      'rejects a foreign conversation without touching it or the network',
      () async {
        loginAs(userA);
        final foreign = await insertConversation(
          uid: userB,
          serverId: 30,
          title: 'Theirs',
        );

        final result = await repository.deleteConversation(30);

        expect(result, isFalse);
        expect(adapter.capturedRequests, isEmpty);
        expect(
          await isar.localChatConversations.get(foreign.localId),
          isNotNull,
        );
      },
    );

    test(
      'a server delete failure does not purge local data (req 19)',
      () async {
        loginAs(userA);
        final convo = await insertConversation(uid: userA, serverId: 5);
        adapter.responder =
            (_) async => ResponseBody.fromString('{"error":"boom"}', 500);

        final deleted = await repository.deleteConversation(5);

        expect(deleted, isFalse);
        expect(await isar.localChatConversations.get(convo.localId), isNotNull);
      },
    );

    test(
      'a non-2xx-success delete response does not purge local data (req 19)',
      () async {
        loginAs(userA);
        final convo = await insertConversation(uid: userA, serverId: 6);
        adapter.responder = (_) async => ResponseBody.fromString('', 202);

        final deleted = await repository.deleteConversation(6);

        expect(deleted, isFalse);
        expect(await isar.localChatConversations.get(convo.localId), isNotNull);
      },
    );

    test('a stale session during the server round-trip does not purge local '
        'data (req 19)', () async {
      loginAs(userA);
      final convo = await insertConversation(uid: userA, serverId: 8);
      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      final deleteFuture = repository.deleteConversation(8);
      await dispatched;

      logout();
      responseCompleter.complete(ResponseBody.fromString('', 204));

      expect(await deleteFuture, isFalse);
      expect(await isar.localChatConversations.get(convo.localId), isNotNull);
    });

    test('a stale session immediately after the delete transaction commits '
        'does not report success, and does not affect a freshly-logged-in '
        'B (post-transaction checkpoint)', () async {
      loginAs(userA);
      final convo = await insertConversation(uid: userA, serverId: 1);
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      // Fires inside _deleteOwnedConversation, immediately AFTER its own
      // writeTxn has already committed the delete - simulating A's
      // session ending in the gap between that commit and
      // deleteConversation() reporting a result back to its caller.
      repository.afterWriteTxnForTesting = () async {
        logout();
        loginAs(userB);
      };

      final result = await repository.deleteConversation(1);

      expect(
        result,
        isFalse,
        reason:
            'the delete transaction committed while A was still current, '
            'but the session ended before deleteConversation() could '
            'report the result - reporting success here would mislead a '
            'caller that no longer represents the session that requested '
            'it',
      );

      // A's own row is legitimately gone (the delete itself was valid
      // when it ran) - that physical fact must not be conflated with
      // reporting success to what is now a stale caller.
      expect(await isar.localChatConversations.get(convo.localId), isNull);

      // Clear the hook before B's own operation - it already fired once
      // (for A's delete) and must not fire again mid-B-operation, which
      // would spuriously re-activate B and bump B's own generation stale
      // against itself.
      repository.afterWriteTxnForTesting = null;

      // B, now the active session, is completely unaffected and can
      // operate normally.
      adapter.responder =
          (_) async => jsonResponse(
            conversationJson(id: 2, userId: userB, title: 'B convo'),
          );
      final bConversation = await repository.getConversation(2);
      expect(bConversation, isNotNull);
      expect(bConversation!.title, 'B convo');
    });
  });

  // ============ 20. sendMessage completion after deletion ============

  test('sendMessage completion after its conversation was deleted creates no '
      'orphan message (req 20)', () async {
    loginAs(userA);
    final convo = await insertConversation(uid: userA, serverId: 3);

    final responseCompleter = Completer<ResponseBody>();
    adapter.responder = (_) => responseCompleter.future;
    final dispatched = adapter.nextDispatch();
    final sendFuture = repository.sendMessage(
      conversationId: 3,
      message: 'hello',
    );
    await dispatched;

    // Delete the local conversation row while the AI response is still
    // in flight.
    await isar.writeTxn(
      () => isar.localChatConversations.delete(convo.localId),
    );

    responseCompleter.complete(
      jsonResponse(
        messageJson(
          id: 99,
          conversationId: 3,
          role: 'assistant',
          content: 'hi back',
        ),
      ),
    );

    final aiMessage = await sendFuture;
    expect(
      aiMessage,
      isNotNull,
      reason:
          'the HTTP call itself succeeded - ChatProvider\'s own '
          'conversation-identity check is what discards this response '
          'in the UI; the repository\'s job is only to never write it '
          'as an orphan below',
    );

    final messages = await isar.localChatMessages.where().findAll();
    expect(
      messages,
      isEmpty,
      reason:
          'the parent conversation was deleted before acknowledgment, '
          'so both the user message and AI response must be dropped '
          'rather than written as orphans',
    );
  });

  test(
    'sendMessage acknowledgment is dropped when the local conversation for '
    'that id is owned by a different user (req 20 - foreign parent)',
    () async {
      final foreignConvo = await insertConversation(
        uid: userB,
        serverId: 3,
        title: 'B convo',
      );

      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse(
            messageJson(
              id: 100,
              conversationId: 3,
              role: 'assistant',
              content: 'reply',
            ),
          );

      final aiMessage = await repository.sendMessage(
        conversationId: 3,
        message: 'hello',
      );

      expect(aiMessage, isNotNull);
      final messages =
          await isar.localChatMessages
              .filter()
              .conversationLocalIdEqualTo(foreignConvo.localId)
              .findAll();
      expect(
        messages,
        isEmpty,
        reason:
            'A must never be able to write a message acknowledgment into '
            'a conversation locally owned by B, even though the '
            'server-side id happens to match',
      );
    },
  );

  // ============ 21-22. Cross-session isolation ============

  group('cross-session isolation', () {
    test('user B can use chat normally after A\'s session is cancelled '
        '(req 21)', () async {
      loginAs(userA);
      final aResponseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => aResponseCompleter.future;
      final aDispatched = adapter.nextDispatch();
      final aFuture = repository.createConversation(
        title: 'A convo',
        type: 'general',
      );
      await aDispatched;

      logout();
      sessionCoordinator.cancelCurrentGeneration();
      await expectLater(aFuture, throwsA(isA<Exception>()));

      loginAs(userB);
      adapter.responder =
          (_) async => jsonResponse(
            conversationJson(id: 50, userId: userB, title: 'B convo'),
          );
      final created = await repository.createConversation(
        title: 'B convo',
        type: 'general',
      );

      expect(created, isNotNull);
      expect(created!.id, 50);
      final stored =
          await isar.localChatConversations
              .filter()
              .serverIdEqualTo(50)
              .findFirst();
      expect(stored!.userId, userB);
    });

    test(
      'A\'s stale, late-resolving response cannot mutate B\'s '
      'already-cached data, even under a server-ID collision (req 22)',
      () async {
        loginAs(userA);
        final aResponseCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => aResponseCompleter.future;
        final aDispatched = adapter.nextDispatch();
        final aFuture = repository.createConversation(
          title: 'A convo',
          type: 'general',
        );
        await aDispatched;

        logout();
        loginAs(userB);
        adapter.responder =
            (_) async => jsonResponse(
              conversationJson(id: 60, userId: userB, title: 'B convo'),
            );
        final bCreated = await repository.createConversation(
          title: 'B convo',
          type: 'general',
        );
        expect(bCreated!.id, 60);

        // A's original (still-pending) request now resolves, claiming the
        // SAME server id B's own conversation was just created with.
        aResponseCompleter.complete(
          jsonResponse(
            conversationJson(id: 60, userId: userA, title: 'Hijacked by A'),
          ),
        );
        await expectLater(aFuture, throwsA(isA<Exception>()));

        final stored =
            await isar.localChatConversations
                .filter()
                .serverIdEqualTo(60)
                .findFirst();
        expect(stored!.userId, userB);
        expect(
          stored.title,
          'B convo',
          reason:
              'A\'s stale, late-resolving response must never overwrite '
              'B\'s already-cached row, even under a server-ID collision',
        );
      },
    );
  });

  // ============ 23. Cancellation/staleness are silent ============

  test('cancellation is a silent expected lifecycle outcome for the '
      'background refresh, never logged as a failure (req 23)', () async {
    loginAs(userA);
    adapter.responder = (_) => Completer<ResponseBody>().future;

    final captured = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) captured.add(message);
    };

    try {
      final dispatched = adapter.nextDispatch();
      await repository.getConversations();
      await dispatched;

      sessionCoordinator.cancelCurrentGeneration();
      await scheduledBackgroundSyncs.single;
    } finally {
      debugPrint = originalDebugPrint;
    }

    expect(
      captured.any((line) => line.contains('Background sync failed')),
      isFalse,
    );
    expect(
      captured.any((line) => line.contains('skipped (session ended)')),
      isTrue,
    );
  });

  // ============ Background determinism sanity ============

  test('exactly one background operation is scheduled per getConversations '
      'call while online', () async {
    loginAs(userA);
    adapter.responder = (_) async => jsonResponse(<dynamic>[]);

    await repository.getConversations();

    expect(
      scheduledBackgroundSyncs,
      hasLength(1),
      reason:
          'awaiting scheduledBackgroundSyncs.single elsewhere in this '
          'file is only a valid completion signal if exactly one '
          'background operation is ever scheduled per call - this pins '
          'that invariant explicitly',
    );
    await scheduledBackgroundSyncs.single;
  });
}

/// A deterministic fake Dio transport. Records every [RequestOptions] Dio
/// actually attempts to send, so tests can assert on the real
/// headers/extra/cancelToken the real interceptor pipeline produced - never
/// a stub of the interceptor itself. Mirrors the fake adapter used in
/// running_repository_session_ownership_test.dart.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  Future<ResponseBody> Function(RequestOptions options)? responder;

  Completer<void>? _dispatchSignal;

  /// Returns a Future that completes deterministically the next time
  /// [fetch] is invoked - i.e. the moment a request actually reaches this
  /// fake transport - distinct from the response being produced or
  /// consumed. Must be called before the operation that will trigger the
  /// dispatch, so the signal can never be missed.
  Future<void> nextDispatch() {
    final completer = Completer<void>();
    _dispatchSignal = completer;
    return completer.future;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
    _dispatchSignal?.complete();
    _dispatchSignal = null;
    final respond = responder;
    if (respond != null) {
      return respond(options);
    }
    return Future.value(
      ResponseBody.fromString(
        '{}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}
