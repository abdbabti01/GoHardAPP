import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/workout_template.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../local/services/local_database_service.dart';

/// Repository for workout templates with **offline-first reads and
/// online-only mutations**.
///
/// ## Online requirement for every mutation
///
/// `createTemplate`, `updateTemplate`, `toggleActive`, `deleteTemplate`,
/// `incrementUsageCount` and `rateTemplate` all require connectivity. Called
/// offline they throw immediately, perform **zero** Isar writes, allocate no
/// local id, and never report success. There is no offline queue, no
/// `pending`/`isSynced` state and no local-only template creation - a
/// mutation that cannot reach the server simply fails. (A dedicated
/// `SyncService` phase would be required to add durable offline mutations;
/// this repository does not attempt a partial version of it.)
///
/// ## Session/ownership model
///
/// Every public asynchronous operation captures a [SessionRequestContext]
/// via [_sessionCoordinator] at operation entry (never after an internal
/// `await`), and uses `context.epochToken.userId` as the sole authoritative
/// user for the rest of that operation - never a later re-read of
/// `AuthService`. A `null` capture (logged out, or the session changed while
/// the JWT read was in flight) follows each method's not-found convention:
/// `[]`/`null`/`false` for reads and the bool/nullable mutations,
/// `Exception('No authenticated user')` for `createTemplate`/`updateTemplate`
/// (which always threw on failure).
///
/// Every [ApiService] call is bound to the captured context via
/// `sessionContext:`, so it carries the pinned JWT and can never dispatch
/// after the session that started it ended. The detached list refreshes
/// scheduled by [getTemplates]/[getCommunityTemplates] receive the exact
/// context captured at that public entry point - never one recaptured inside
/// the closure.
///
/// ## Cache ownership
///
/// A cached row is identified by (`serverId`, `cachedForUserId`).
/// [WorkoutTemplate.createdByUserId] is the *author* and is identical on
/// every device; it can never identify the cache owner.
/// [WorkoutTemplate.cachedForUserId] carries that, always stamped from
/// `context.epochToken.userId` - never from response JSON, never from a live
/// `AuthService` read. Every local read is scoped to
/// `cachedForUserId == context.userId`, so a legacy (`null`-owner) row and
/// another user's row are both invisible to an authenticated reader.
///
/// ## Legacy rows
///
/// Rows written by the previous implementation deserialize with
/// `cachedForUserId == null` (and possibly `serverId == null`). They are
/// invisible to every authenticated read and are never treated as
/// synchronized data. A legacy row whose `serverId` matches a template still
/// on the server is adopted (restamped for the current user) by the next
/// full owner-list refresh; a legacy `serverId == null` row is left inert and
/// removed only by `LocalDatabaseService.clearAll()` on logout.
///
/// ## Conflict model and write ordering
///
/// Content is **server-authoritative**: there is no offline editing, so every
/// mutation reconciles against fresh server state ([updateTemplate] does
/// `PUT` then `GET`; toggle/rate/increment apply the server-acknowledged
/// field values; create uses the `POST` response). The client never merges.
///
/// Every write to Isar goes through one of [_cacheServerTemplates],
/// [_writeOwnedRowByServerId] or [_deleteOwnedRow], and all apply the
/// five-checkpoint logout-race shape (post-HTTP recheck, pre-`writeTxn`
/// recheck, first-statement-inside-`writeTxn` recheck, fresh re-read of the
/// target row + ownership check, and a post-`writeTxn` recheck by the
/// caller).
///
/// [_cacheServerTemplates] and [_writeOwnedRowByServerId] additionally apply a
/// **per-`serverId` write clock** ([_serverIdWriteClock]): every mutation and
/// every refresh takes a monotonically increasing ticket at entry
/// ([_nextWriteTicket]); such a write to a `serverId` is skipped when a write
/// with a strictly higher ticket has already landed on that `serverId`. This
/// orders writes by *operation-start*, not by a server version (the DTO
/// exposes none), which is sufficient for the races this feature actually
/// has: two rapid toggles/updates of the same row (the later-started one
/// wins regardless of ack order), and an in-flight update that must not
/// recreate a row a newer delete removed. It does **not** attempt a version
/// vector: a refresh that starts after a mutation but observes a
/// pre-mutation snapshot and writes last will still land its (server-truth,
/// merely slightly behind) value - acceptable because content is
/// server-authoritative and the very next refresh converges. The clock is
/// reset whenever the session generation changes, so no prior session's
/// ticket can gate a new session's write.
///
/// [_deleteOwnedRow] deliberately does *not* consult the write clock: a
/// successful server `DELETE` is terminal (the record is gone
/// server-side), so removing the local row always converges to truth, and a
/// later higher-ticket write for that `serverId` is either another no-op
/// delete or an update the server itself 404s. It only *records* its ticket,
/// so a slower in-flight update's [_writeOwnedRowByServerId] /
/// [_cacheServerTemplates] write is skipped.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes, not failures: reads convert them to their empty
/// result, mutations to a silent no-op ([toggleActive]/[deleteTemplate]/
/// [incrementUsageCount]) or the [_unauthenticated] outcome
/// ([createTemplate]/[updateTemplate]/[rateTemplate]); none is logged as an
/// ordinary failure or retried.
class WorkoutTemplateRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;

  // Kept for constructor-shape consistency with this repository's existing
  // ProxyProvider4 wiring in main.dart. No longer read directly.
  // ignore: unused_field
  final AuthService _authService;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// every other Provider/repository (see main.dart). This repository only
  /// ever reads it via capture()/isCurrent().
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext] for
  /// every session-bound HTTP call. The SAME instance handed to every other
  /// consumer (see main.dart); never constructed privately.
  final SessionRequestCoordinator _sessionCoordinator;

  WorkoutTemplateRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._authService,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  static const String _unauthenticated = 'No authenticated user';

  // ============ Per-serverId write ordering ============

  int _writeClock = 0;
  int _clockGeneration = -1;
  final Map<int, int> _serverIdWriteClock = {};

  /// Returns the next monotonically increasing write ticket, resetting the
  /// per-`serverId` clock whenever the session generation changes so no
  /// ticket from a previous session can gate a new session's writes.
  int _nextWriteTicket(UserSessionToken token) {
    if (token.generation != _clockGeneration) {
      _clockGeneration = token.generation;
      _serverIdWriteClock.clear();
    }
    return ++_writeClock;
  }

  /// True when a write for [serverId] carrying [ticket] is stale - i.e. a
  /// write with a strictly higher ticket has already landed on [serverId].
  bool _isSupersededWrite(int serverId, int ticket) {
    final applied = _serverIdWriteClock[serverId];
    return applied != null && applied > ticket;
  }

  /// Records that a write carrying [ticket] landed on [serverId].
  void _recordWrite(int serverId, int ticket) {
    final applied = _serverIdWriteClock[serverId];
    if (applied == null || ticket > applied) {
      _serverIdWriteClock[serverId] = ticket;
    }
  }

  // ============ Test-only session-race seams ============
  //
  // Mirrors SharedWorkoutRepository / ChatRepository / RunningRepository.
  // Each is @visibleForTesting, defaults to null, never assigned outside test
  // code - production control flow/performance are unaffected.
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

  /// Fired immediately after a FOREGROUND HTTP call's own post-response epoch
  /// checkpoint passes, right before touching Isar.
  @visibleForTesting
  Future<void> Function()? afterForegroundHttpResponseForTesting;

  /// Fired synchronously, once per [_backgroundSync] call, with the Future
  /// that completes once THAT detached operation has fully settled (it never
  /// rejects). Tests await this instead of guessing with a delay.
  @visibleForTesting
  void Function(Future<void> operationSettled)?
  onBackgroundSyncScheduledForTesting;

  Future<void> _runTestHook(Future<void> Function()? hook) async {
    if (hook != null) {
      await hook();
    }
  }

  /// Schedules [operation] to run detached from the caller. [operation] must
  /// already be bound to a captured [SessionRequestContext]/
  /// [UserSessionToken].
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

  /// Captures a context for an operation that requires connectivity. Throws
  /// [_unauthenticated] if there is no active session, or [offlineMessage] if
  /// there is a session but no connection. No Isar read/write and no HTTP
  /// happens in either failure case.
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

  // ============ Public reads ============

  /// Get the current user's own workout templates. Offline-first: returns
  /// this user's cached rows immediately, and, when online, refreshes the
  /// cache from the server on a detached, deterministic background operation
  /// bound to the captured session.
  Future<List<WorkoutTemplate>> getTemplates({bool activeOnly = false}) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return [];
    final token = context.epochToken;
    final Isar db = _localDb.database;

    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _refreshTemplatesFromServer(db, context),
        'Workout templates cache updated',
      );
    }

    if (!_sessionEpoch.isCurrent(token)) return [];
    return _localOwnTemplates(db, token.userId, activeOnly: activeOnly);
  }

  /// Get community workout templates: system templates plus custom templates
  /// their owners have explicitly published.
  Future<List<WorkoutTemplate>> getCommunityTemplates({
    String? category,
    int? limit = 50,
  }) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return [];
    final token = context.epochToken;
    final Isar db = _localDb.database;

    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _refreshCommunityFromServer(
          db,
          context,
          category: category,
          limit: limit,
        ),
        'Community templates cache updated',
      );
    }

    if (!_sessionEpoch.isCurrent(token)) return [];
    return _localCommunityTemplates(
      db,
      token.userId,
      category: category,
      limit: limit,
    );
  }

  /// Get a specific template by its server ID. Returns a cached copy if this
  /// user has one; otherwise (online) fetches it. A template hidden from the
  /// caller and a nonexistent id are indistinguishable (`null`).
  Future<WorkoutTemplate?> getTemplateById(int serverId) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return null;
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final cached = await _ownedRowByServerId(db, serverId, token);
    if (cached != null) return cached;

    if (!_connectivity.isOnline) return null;

    final ticket = _nextWriteTicket(token);
    final Map<String, dynamic> data;
    try {
      data = await _apiService.get<Map<String, dynamic>>(
        '${ApiConfig.workoutTemplates}/$serverId',
        sessionContext: context,
      );
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      debugPrint('Error fetching template: $e');
      return null;
    }

    if (!_sessionEpoch.isCurrent(token)) return null;
    await _runTestHook(afterForegroundHttpResponseForTesting);

    final fetched = WorkoutTemplateJson.fromJson(data);
    await _cacheServerTemplates(db, context, [fetched], writeTicket: ticket);
    if (!_sessionEpoch.isCurrent(token)) return null;
    return _ownedRowByServerId(db, serverId, token);
  }

  /// Get the caller's own active templates scheduled for a specific date.
  Future<List<WorkoutTemplate>> getTemplatesForDate(DateTime date) async {
    final templates = await getTemplates(activeOnly: true);
    return templates.where((t) => _isScheduledForDate(t, date)).toList();
  }

  // ============ Public mutations (online only) ============

  /// Create a new workout template - always owned by the captured user,
  /// always a custom template. Requires connectivity: called offline it
  /// throws before any Isar write and allocates no local id.
  Future<WorkoutTemplate> createTemplate({
    required String name,
    String? description,
    required String exercisesJson,
    required String recurrencePattern,
    String? daysOfWeek,
    int? intervalDays,
    int? estimatedDuration,
    String? category,
    bool isActive = true,
    bool isPublic = false,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot create templates while offline',
    );
    final token = context.epochToken;
    final Isar db = _localDb.database;
    final ticket = _nextWriteTicket(token);

    // Transient object used only to build the request body via the model's
    // single serialization path - never persisted.
    final draft = WorkoutTemplate(
      name: name,
      description: description,
      exercisesJson: exercisesJson,
      recurrencePattern: recurrencePattern,
      daysOfWeek: daysOfWeek,
      intervalDays: intervalDays,
      estimatedDuration: estimatedDuration,
      category: category,
      isActive: isActive,
      isPublic: isPublic,
      createdAt: DateTime.now(),
    );

    final Map<String, dynamic> data;
    try {
      data = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.workoutTemplates,
        data: draft.toRequestJson(),
        sessionContext: context,
      );
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('Error creating template: $e');
      rethrow;
    }

    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    await _runTestHook(afterForegroundHttpResponseForTesting);

    final created = WorkoutTemplateJson.fromJson(data);
    await _cacheServerTemplates(db, context, [created], writeTicket: ticket);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    final serverId = created.serverId;
    if (serverId != null) {
      final stored = await _ownedRowByServerId(db, serverId, token);
      if (stored != null) return stored;
    }
    created.cachedForUserId = token.userId;
    return created;
  }

  /// Update an existing template. Requires connectivity and a `serverId`.
  /// Online: `PUT` (204 No Content), then a re-fetch to refresh the cache
  /// with the server's canonical row.
  Future<WorkoutTemplate> updateTemplate(WorkoutTemplate template) async {
    final context = await _requireOnlineContext(
      'Cannot update templates while offline',
    );
    final token = context.epochToken;
    final Isar db = _localDb.database;
    final serverId = template.serverId;
    if (serverId == null) {
      throw Exception('Cannot update an unsynced template');
    }
    final ticket = _nextWriteTicket(token);

    try {
      await _apiService.put<dynamic>(
        '${ApiConfig.workoutTemplates}/$serverId',
        data: template.toRequestJson(),
        sessionContext: context,
      );
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('Error updating template: $e');
      rethrow;
    }

    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    await _runTestHook(afterForegroundHttpResponseForTesting);

    // The PUT returns no body; re-fetch the canonical row. A 404 here (the
    // template was deleted between the PUT and this GET) propagates as a
    // normal error - the cache is not touched.
    final Map<String, dynamic> data;
    try {
      data = await _apiService.get<Map<String, dynamic>>(
        '${ApiConfig.workoutTemplates}/$serverId',
        sessionContext: context,
      );
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('Error re-fetching updated template: $e');
      rethrow;
    }

    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    final updated = WorkoutTemplateJson.fromJson(data);
    await _cacheServerTemplates(db, context, [updated], writeTicket: ticket);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    return (await _ownedRowByServerId(db, serverId, token)) ??
        (updated..cachedForUserId = token.userId);
  }

  /// Toggle active status of a template. Owner-only server-side. Requires
  /// connectivity and a `serverId`. Applies the acknowledged state to this
  /// user's owned cached row.
  Future<WorkoutTemplate?> toggleActive(WorkoutTemplate template) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return null;
    if (!_connectivity.isOnline) {
      throw Exception('Cannot change a template while offline');
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;
    final serverId = template.serverId;
    if (serverId == null) {
      throw Exception('Cannot change an unsynced template');
    }
    final ticket = _nextWriteTicket(token);

    final Map<String, dynamic>? response;
    try {
      response = await _apiService.patch<Map<String, dynamic>>(
        '${ApiConfig.workoutTemplates}/$serverId/toggle-active',
        sessionContext: context,
      );
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      debugPrint('Error toggling template active: $e');
      rethrow;
    }

    if (!_sessionEpoch.isCurrent(token)) return null;
    await _runTestHook(afterForegroundHttpResponseForTesting);

    final isActive = response?['isActive'] as bool? ?? !template.isActive;
    return _writeOwnedRowByServerId(db, serverId, token, ticket, (row) {
      row.isActive = isActive;
    });
  }

  /// Delete a template. Requires connectivity and a `serverId`. The server
  /// `DELETE` runs first: only a successful 204/200 removes this user's owned
  /// local row. Any other server failure is rethrown and the local row is
  /// kept, so a caller never sees a misleading success. A stale/cancelled
  /// outcome is a silent `false` and never deletes.
  Future<bool> deleteTemplate(WorkoutTemplate template) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return false;
    if (!_connectivity.isOnline) {
      throw Exception('Cannot delete templates while offline');
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;
    final serverId = template.serverId;
    if (serverId == null) {
      throw Exception('Cannot delete an unsynced template');
    }
    final ticket = _nextWriteTicket(token);

    final bool serverDeleted;
    try {
      serverDeleted = await _apiService.delete(
        '${ApiConfig.workoutTemplates}/$serverId',
        sessionContext: context,
      );
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      debugPrint('Error deleting template from server: $e');
      rethrow;
    }
    if (!serverDeleted) return false;

    if (!_sessionEpoch.isCurrent(token)) return false;
    await _runTestHook(afterForegroundHttpResponseForTesting);

    return _deleteOwnedRow(db, serverId, token, ticket);
  }

  /// Record that the caller used one of their own templates. Owner-only
  /// server-side. Requires connectivity and a `serverId`. Applies the
  /// acknowledged `usageCount` (and `lastUsedAt`) to this user's owned row.
  Future<void> incrementUsageCount(WorkoutTemplate template) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return;
    if (!_connectivity.isOnline) {
      throw Exception('Cannot update template usage while offline');
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;
    final serverId = template.serverId;
    if (serverId == null) {
      throw Exception('Cannot update usage on an unsynced template');
    }
    final ticket = _nextWriteTicket(token);

    final Map<String, dynamic> response;
    try {
      response = await _apiService.post<Map<String, dynamic>>(
        '${ApiConfig.workoutTemplates}/$serverId/increment-usage',
        data: {},
        sessionContext: context,
      );
    } on SessionStaleException {
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      debugPrint('⚠️ Failed to increment usage on server: $e');
      rethrow;
    }

    if (!_sessionEpoch.isCurrent(token)) return;
    await _runTestHook(afterForegroundHttpResponseForTesting);

    final usageCount = response['usageCount'] as int?;
    await _writeOwnedRowByServerId(db, serverId, token, ticket, (row) {
      row.usageCount = usageCount ?? row.usageCount + 1;
      row.lastUsedAt = DateTime.now();
    });
  }

  /// Rate a community template the caller can see. Requires connectivity.
  /// Applies the acknowledged `{rating, ratingCount}` to this user's owned
  /// cached row.
  Future<void> rateTemplate(int serverId, double rating) async {
    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be between 1 and 5');
    }
    final context = await _requireOnlineContext('Cannot rate while offline');
    final token = context.epochToken;
    final Isar db = _localDb.database;
    final ticket = _nextWriteTicket(token);

    final Map<String, dynamic> response;
    try {
      response = await _apiService.post<Map<String, dynamic>>(
        '${ApiConfig.workoutTemplates}/$serverId/rate',
        data: {'rating': rating},
        sessionContext: context,
      );
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('Error rating template: $e');
      rethrow;
    }

    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    await _runTestHook(afterForegroundHttpResponseForTesting);

    final newRating = (response['rating'] as num?)?.toDouble();
    final newRatingCount = response['ratingCount'] as int?;
    await _writeOwnedRowByServerId(db, serverId, token, ticket, (row) {
      if (newRating != null) row.rating = newRating;
      if (newRatingCount != null) row.ratingCount = newRatingCount;
    });
  }

  // ============ Private: local reads ============

  Future<List<WorkoutTemplate>> _localOwnTemplates(
    Isar db,
    int userId, {
    required bool activeOnly,
  }) async {
    var rows =
        await db.workoutTemplates
            .filter()
            .cachedForUserIdEqualTo(userId)
            .and()
            .createdByUserIdEqualTo(userId)
            .findAll();
    if (activeOnly) {
      rows = rows.where((t) => t.isActive).toList();
    }
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  Future<List<WorkoutTemplate>> _localCommunityTemplates(
    Isar db,
    int userId, {
    String? category,
    int? limit,
  }) async {
    var rows =
        await db.workoutTemplates
            .filter()
            .cachedForUserIdEqualTo(userId)
            .findAll();

    rows =
        rows
            .where((t) => t.isPublic || !t.isCustom)
            .where((t) => category == null || t.category == category)
            .toList();

    rows.sort((a, b) {
      final byRating = (b.rating ?? 0).compareTo(a.rating ?? 0);
      if (byRating != 0) return byRating;
      return b.usageCount.compareTo(a.usageCount);
    });

    if (limit != null && rows.length > limit) {
      return rows.sublist(0, limit);
    }
    return rows;
  }

  /// Resolves [serverId] to a row owned by [token.userId], or `null` if it is
  /// missing OR belongs to a different cache owner - indistinguishable to
  /// callers.
  Future<WorkoutTemplate?> _ownedRowByServerId(
    Isar db,
    int serverId,
    UserSessionToken token,
  ) async {
    final row =
        await db.workoutTemplates
            .filter()
            .serverIdEqualTo(serverId)
            .and()
            .cachedForUserIdEqualTo(token.userId)
            .findFirst();
    if (!_sessionEpoch.isCurrent(token)) return null;
    return row;
  }

  // ============ Private: writes ============

  /// Upserts a server representation into this user's cache, stamping every
  /// row with the captured cache owner. Reuses this user's own row for the
  /// `serverId` when there is one; otherwise adopts a single legacy
  /// (`cachedForUserId == null`) row for that `serverId`; otherwise inserts a
  /// fresh row. A row owned by a *different* user is never touched.
  ///
  /// Every per-`serverId` write is gated by [writeTicket]: a row whose
  /// `serverId` already carries a strictly higher applied ticket
  /// ([_isSupersededWrite]) is left untouched, so a stale refresh can neither
  /// overwrite a newer mutation acknowledgment nor recreate a row a newer
  /// delete removed.
  ///
  /// When [sweepOwnTemplates] is set, [templates] is the complete
  /// authoritative list of the captured user's own templates: any
  /// server-backed row this user owns and authored that is absent from
  /// [templates] (deleted elsewhere) is removed. Offline-only rows
  /// (`serverId == null`), rows authored by other users, and rows with a
  /// higher applied write ticket are never swept.
  Future<void> _cacheServerTemplates(
    Isar db,
    SessionRequestContext context,
    List<WorkoutTemplate> templates, {
    required int writeTicket,
    bool sweepOwnTemplates = false,
  }) async {
    final token = context.epochToken;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      if (sweepOwnTemplates) {
        final serverIds =
            templates.map((t) => t.serverId).whereType<int>().toSet();
        final owned =
            await db.workoutTemplates
                .filter()
                .cachedForUserIdEqualTo(token.userId)
                .and()
                .createdByUserIdEqualTo(token.userId)
                .findAll();
        for (final row in owned) {
          final rid = row.serverId;
          if (rid != null &&
              !serverIds.contains(rid) &&
              !_isSupersededWrite(rid, writeTicket)) {
            await db.workoutTemplates.delete(row.localId);
            _recordWrite(rid, writeTicket);
          }
        }
      }

      for (final t in templates) {
        final serverId = t.serverId;
        if (serverId == null) continue;
        if (_isSupersededWrite(serverId, writeTicket)) continue;

        var existing =
            await db.workoutTemplates
                .filter()
                .serverIdEqualTo(serverId)
                .and()
                .cachedForUserIdEqualTo(token.userId)
                .findFirst();
        existing ??=
            await db.workoutTemplates
                .filter()
                .serverIdEqualTo(serverId)
                .and()
                .cachedForUserIdIsNull()
                .findFirst();

        t.cachedForUserId = token.userId;
        if (existing != null) {
          t.localId = existing.localId;
        }
        await db.workoutTemplates.put(t);
        _recordWrite(serverId, writeTicket);
      }
    });

    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Applies [mutate] to the row identified by ([serverId], captured user),
  /// re-read fresh inside the transaction. Returns the mutated row, or `null`
  /// if a checkpoint rejected the write, the row is not this user's, or a
  /// newer write ([_isSupersededWrite]) already landed on [serverId].
  Future<WorkoutTemplate?> _writeOwnedRowByServerId(
    Isar db,
    int serverId,
    UserSessionToken token,
    int writeTicket,
    void Function(WorkoutTemplate row) mutate,
  ) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (_isSupersededWrite(serverId, writeTicket)) return null;

    WorkoutTemplate? result;
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      if (_isSupersededWrite(serverId, writeTicket)) return;

      final row =
          await db.workoutTemplates
              .filter()
              .serverIdEqualTo(serverId)
              .and()
              .cachedForUserIdEqualTo(token.userId)
              .findFirst();
      if (row == null) return;

      mutate(row);
      await db.workoutTemplates.put(row);
      _recordWrite(serverId, writeTicket);
      result = row;
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return null;
    return result;
  }

  /// Deletes this user's owned row for [serverId]. A foreign or missing row
  /// no-ops. Records [writeTicket] on [serverId] so a slower in-flight update
  /// cannot recreate the row. Returns `true` only if a row owned by the
  /// captured user was actually deleted.
  Future<bool> _deleteOwnedRow(
    Isar db,
    int serverId,
    UserSessionToken token,
    int writeTicket,
  ) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return false;

    var deleted = false;
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final row =
          await db.workoutTemplates
              .filter()
              .serverIdEqualTo(serverId)
              .and()
              .cachedForUserIdEqualTo(token.userId)
              .findFirst();
      _recordWrite(serverId, writeTicket);
      if (row == null) return;

      await db.workoutTemplates.delete(row.localId);
      deleted = true;
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return false;
    return deleted;
  }

  // ============ Private: background refresh ============

  /// Refreshes this user's own-templates cache. Always fetches the full owner
  /// list (no `activeOnly` server filter) so a template deactivated on
  /// another device is refreshed here rather than kept active in the cache;
  /// the `activeOnly` view is applied by [_localOwnTemplates].
  Future<void> _refreshTemplatesFromServer(
    Isar db,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;
    final ticket = _nextWriteTicket(token);

    await _runTestHook(beforeBackgroundHttpDispatchForTesting);

    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.workoutTemplates,
      sessionContext: context,
    );

    if (!_sessionEpoch.isCurrent(token)) return;
    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final templates =
        data
            .map(
              (json) =>
                  WorkoutTemplateJson.fromJson(json as Map<String, dynamic>),
            )
            .toList();

    await _cacheServerTemplates(
      db,
      context,
      templates,
      writeTicket: ticket,
      sweepOwnTemplates: true,
    );
  }

  Future<void> _refreshCommunityFromServer(
    Isar db,
    SessionRequestContext context, {
    String? category,
    int? limit,
  }) async {
    final token = context.epochToken;
    final ticket = _nextWriteTicket(token);

    await _runTestHook(beforeBackgroundHttpDispatchForTesting);

    final queryParameters = <String, dynamic>{};
    if (category != null) queryParameters['category'] = category;
    if (limit != null) queryParameters['limit'] = limit;

    final data = await _apiService.get<List<dynamic>>(
      '${ApiConfig.workoutTemplates}/community',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
      sessionContext: context,
    );

    if (!_sessionEpoch.isCurrent(token)) return;
    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final templates =
        data
            .map(
              (json) =>
                  WorkoutTemplateJson.fromJson(json as Map<String, dynamic>),
            )
            .toList();

    await _cacheServerTemplates(db, context, templates, writeTicket: ticket);
  }

  // ============ Private: scheduling ============

  bool _isScheduledForDate(WorkoutTemplate template, DateTime date) {
    switch (template.recurrencePattern) {
      case 'daily':
        return true;
      case 'weekly':
        return template.daysOfWeekList.contains(date.weekday);
      case 'custom':
        if (template.intervalDays == null) return false;
        final anchor = template.lastUsedAt ?? template.createdAt;
        final daysSinceAnchor = date.difference(anchor).inDays.abs();
        return daysSinceAnchor % template.intervalDays! == 0;
      default:
        return false;
    }
  }
}
