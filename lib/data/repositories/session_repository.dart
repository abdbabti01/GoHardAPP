import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/session.dart';
import '../models/exercise.dart';
import '../models/program_workout.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../services/session_update_sync_helper.dart';
import '../local/services/local_database_service.dart';
import '../local/services/model_mapper.dart';
import '../local/models/local_session.dart';
import '../local/models/local_exercise.dart';
import '../local/models/local_exercise_set.dart';
import '../local/models/local_exercise_template.dart';

/// Repository for session (workout) operations with offline support.
///
/// ## Session/ownership model
///
/// Every public asynchronous operation below that touches authenticated
/// session data captures a [SessionRequestContext] via
/// [_sessionCoordinator] at operation entry (never after an internal
/// `await`), and uses `context.epochToken.userId` as the sole authoritative
/// user for the remainder of that operation - never a later, independently
/// re-read user ID. A `null` capture (logged out, or the session changed
/// while the JWT read was in flight) is treated exactly like today's
/// existing unauthenticated/not-found convention: no Isar mutation, no HTTP.
///
/// Every [ApiService] call this repository makes - foreground (awaited
/// inline) or background (fire-and-forget) - is bound to that captured
/// context, so it carries the pinned JWT captured at entry rather than
/// whatever the live token happens to be, and can never be dispatched after
/// the session that started it has ended (see [ApiService]'s own class doc
/// comment). Every detached/background push schedules
/// [SessionRequestCoordinator.captureContext] (or reuses the context already
/// captured at entry) SYNCHRONOUSLY, before any later callback, so the
/// background closure is always bound to the session that scheduled it, not
/// whichever session happens to be active when it finally runs.
///
/// ## Local ID ownership
///
/// Every public ID (`serverId ?? localId`, see `ModelMapper.localToSession`)
/// is resolved through [_resolveOwnedSession]/[_resolveOwnedSessionOrThrow]:
/// the server-ID interpretation is tried first, but only a match owned by
/// the captured user is accepted - a foreign server-ID match (same numeric
/// ID, different owner) never blocks falling through to the local-ID
/// interpretation, since server IDs and Isar auto-increment local IDs are
/// independent sequences that can collide on the same number. A foreign or
/// missing target always follows the existing not-found convention
/// (`Exception('Session not found: $id')`) without revealing whether a
/// foreign row exists.
///
/// ## Session graph ownership
///
/// [LocalExercise] is owned transitively through `sessionLocalId ->
/// LocalSession.userId`, and [LocalExerciseSet] through `exerciseLocalId ->
/// LocalExercise.sessionLocalId -> LocalSession.userId`. A background cache
/// refresh only ever writes/deletes child rows for a [LocalSession] it has
/// independently re-validated as owned by the captured user - never a
/// replacement or foreign session's children.
///
/// ## Transaction/logout race protection
///
/// Every mutation/cache acknowledgment below rechecks
/// [UserSessionEpoch.isCurrent] immediately after every awaited HTTP/local
/// lookup, immediately before entering its `writeTxn`, and again as the
/// FIRST statement inside that `writeTxn` - the three-checkpoint shape that
/// guarantees a logout landing anywhere in that window (including while
/// Isar's write lock is being awaited) never lets a write land after
/// `LocalDatabaseService.clearAll()` has already run, and never lets a
/// stale acknowledgment resurrect or overwrite a since-replaced row. See the
/// `beforeWriteTxnForTesting` / `insideWriteTxnForTesting` /
/// `afterWriteTxnForTesting` and background-flavored equivalents below for
/// how this is exercised deterministically in tests.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures: they are
/// logged as neither a success nor an error, never surfaced to the user,
/// and never treated as grounds to mark a row permanently failed or
/// increment a retry counter. Every other exception preserves this
/// repository's existing "log and continue, retry later" behavior.
class SessionRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;
  // Kept for constructor-shape consistency with every other repository's
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

  SessionRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._authService,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  static const String _unauthenticated = 'User not authenticated';

  // ============ Test-only session-race seams ============
  //
  // One hook per checkpoint, mirroring NutritionRepository's identical
  // seams. Each is @visibleForTesting, defaults to null, and is never
  // assigned outside test code - production control flow/performance are
  // unaffected.
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

  @visibleForTesting
  Future<void> Function()? insideBackgroundWriteTxnForTesting;

  /// Fires immediately before each child (Exercise/ExerciseSet) delete
  /// inside [_deleteSessionAndRelatedData]'s transaction, after the
  /// exercises have already been queried - lets a test land a parent
  /// reassignment exactly in the window the grandparent-ownership recheck
  /// below is meant to close.
  @visibleForTesting
  Future<void> Function()? beforeChildDeleteForTesting;

  Future<void> _runTestHook(Future<void> Function()? hook) async {
    if (hook != null) {
      await hook();
    }
  }

  // ============ Session/ownership helpers ============

  /// Resolves a [LocalSession] identified ambiguously by [id] (server ID or
  /// local Isar ID) to a row owned by [token.userId], or `null` if neither
  /// interpretation yields an owned row. See the class doc comment's "Local
  /// ID ownership" section.
  Future<LocalSession?> _resolveOwnedSession(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final byServerId =
        await db.localSessions
            .filter()
            .serverIdEqualTo(id)
            .userIdEqualTo(token.userId)
            .findFirst();
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byServerId != null) return byServerId;

    final byLocalId = await db.localSessions.get(id);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byLocalId != null && byLocalId.userId == token.userId) {
      return byLocalId;
    }

    return null;
  }

  /// Same as [_resolveOwnedSession], but throws the existing not-found
  /// convention when no owned row exists.
  Future<LocalSession> _resolveOwnedSessionOrThrow(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final session = await _resolveOwnedSession(db, id, token);
    if (session == null) {
      throw Exception('Session not found: $id');
    }
    return session;
  }

  /// Re-resolves [localId] by its STABLE local identity and verifies direct
  /// ownership against [token.userId]. Used by every background
  /// acknowledgment to confirm the row it is about to write to still
  /// belongs to the session that started the operation, rather than
  /// trusting a captured reference that may since have been replaced.
  Future<LocalSession?> _ownedSessionByLocalId(
    Isar db,
    int localId,
    UserSessionToken token,
  ) async {
    final row = await db.localSessions.get(localId);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (row == null || row.userId != token.userId) return null;
    return row;
  }

  /// True if [sessionLocalId] resolves to a [LocalSession] owned by
  /// [token.userId]. False (never throws) for a missing/orphaned parent, so
  /// an orphaned exercise is treated the same as a foreign one - never
  /// mutated.
  Future<bool> _isSessionOwnedByLocalId(
    Isar db,
    int sessionLocalId,
    UserSessionToken token,
  ) async {
    final parent = await db.localSessions.get(sessionLocalId);
    if (!_sessionEpoch.isCurrent(token)) return false;
    return parent != null && parent.userId == token.userId;
  }

  // ============ Generic helpers ============

  /// Load exercises for a session from local database
  Future<List<Exercise>> _loadExercisesForSession(
    Isar db,
    int sessionLocalId,
  ) async {
    final localExercises =
        await db.localExercises
            .filter()
            .sessionLocalIdEqualTo(sessionLocalId)
            .findAll();

    return localExercises
        .map((localEx) => ModelMapper.localToExercise(localEx))
        .toList();
  }

  /// Convert a LocalSession to Session with exercises loaded
  Future<Session> _localSessionToSessionWithExercises(
    Isar db,
    LocalSession localSession,
  ) async {
    final exercises = await _loadExercisesForSession(db, localSession.localId);
    return ModelMapper.localToSession(localSession, exercises: exercises);
  }

  /// Fired synchronously, exactly once per [_backgroundSync] call, with the
  /// Future that completes once THAT SPECIFIC detached operation has fully
  /// settled - after its HTTP dispatch, its success/error handling, and any
  /// acknowledgment writeTxn or guarded stale/cancelled exit inside
  /// [operation] have all finished (it never rejects: the same
  /// success/error handling [_backgroundSync] always applies runs first,
  /// so this always completes, never throws). Tests use it to await
  /// deterministic completion of detached work instead of guessing with a
  /// delay - see `session_repository_session_ownership_test.dart`.
  ///
  /// Each call passes its OWN distinct Future, so a test scheduling
  /// multiple overlapping background operations (e.g. two repository calls
  /// in quick succession) can tell them apart by call order rather than
  /// awaiting the wrong one. Defaults to null in production - a pure
  /// no-op that does not change scheduling, timing, or error handling.
  @visibleForTesting
  void Function(Future<void> operationSettled)?
  onBackgroundSyncScheduledForTesting;

  /// Schedules [operation] to run detached from the caller. [operation]
  /// must already be bound to a captured [SessionRequestContext]/
  /// [UserSessionToken] - this helper only handles the fire-and-forget
  /// execution and expected-lifecycle-outcome classification, exactly like
  /// NutritionRepository's identical helper.
  ///
  /// [SessionStaleException] and [RequestCancelledException] are logged as
  /// neither a success nor a failure - never surfaced as a user-visible
  /// error, never grounds to mark anything permanently failed. Every other
  /// exception preserves this repository's original "log and continue"
  /// behavior.
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

  /// Wraps a single background HTTP call with the before-dispatch test seam.
  /// Staleness AT dispatch time is already enforced by [ApiService] itself
  /// via the bound [SessionRequestContext.epochToken].
  Future<T> _dispatchBackgroundHttp<T>(Future<T> Function() call) async {
    await _runTestHook(beforeBackgroundHttpDispatchForTesting);
    return call();
  }

  /// True while [localSession] has an unresolved 409 conflict recorded
  /// (see SessionUpdateSyncHelper). Only an explicit Keep Mine / Use Server
  /// resolution - not implemented yet - may leave this state; a routine
  /// local edit must never flip it back to pending_update, clear its
  /// conflict metadata, or queue it for a background PUT.
  bool _isConflicted(LocalSession localSession) =>
      localSession.syncStatus == 'conflict';

  /// Apply the standard local-edit sync-tracking bookkeeping
  /// (lastModifiedLocal / isSynced / syncStatus) to [localSession],
  /// preserving the conflict invariant above. Field-specific edits (name,
  /// date, status, timestamps, ...) are applied by the caller - this only
  /// manages the fields every edit path shares. [newStatus], if given, is
  /// applied even for a conflicted row, since a workout status change is
  /// itself a local mutable-field edit ("mine"), not a sync-status change.
  void _applyLocalEditBookkeeping(
    LocalSession localSession, {
    String? newStatus,
  }) {
    if (newStatus != null) {
      localSession.status = newStatus;
    }
    localSession.lastModifiedLocal = DateTime.now().toUtc();

    if (_isConflicted(localSession)) {
      // Conflict state and its metadata are intentionally left untouched.
      return;
    }

    localSession.isSynced = false;
    if (localSession.serverId != null) {
      localSession.syncStatus = 'pending_update';
    }
  }

  /// Whether a local edit to [localSession] should trigger an immediate
  /// background push to the server. Conflicted rows are excluded - they
  /// may only be resolved through an explicit Keep Mine / Use Server
  /// operation, never by a routine edit or the periodic sync loop.
  bool _shouldPushAfterEdit(LocalSession localSession) =>
      !_isConflicted(localSession) &&
      _connectivity.isOnline &&
      localSession.serverId != null;

  /// Mark a local session as needing sync (pending_update if server ID
  /// exists). [token] is rechecked as the first statement inside the write
  /// transaction, per the class doc comment's transaction-race section.
  Future<void> _markSessionForSync(
    Isar db,
    LocalSession localSession,
    UserSessionToken token, {
    String? newStatus,
  }) async {
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      _applyLocalEditBookkeeping(localSession, newStatus: newStatus);
      await db.localSessions.put(localSession);
    });
  }

  /// Get all sessions for the current user
  /// Offline-first: returns local cache immediately, syncs with server in background
  /// Set [waitForSync] to true to wait for server sync before returning (useful after login)
  Future<List<Session>> getSessions({bool waitForSync = false}) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      debugPrint('⚠️ No authenticated session, returning empty list');
      return [];
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    // If waitForSync is true and we're online, sync first then return fresh data
    if (waitForSync && _connectivity.isOnline) {
      debugPrint('⏳ Waiting for server sync before returning sessions...');
      try {
        await _syncSessionsFromServer(db, context);
      } on SessionStaleException {
        // Expected lifecycle outcome.
      } on RequestCancelledException {
        // Expected lifecycle outcome.
      }
      if (!_sessionEpoch.isCurrent(token)) return [];
      final freshSessions = await _getLocalSessions(db, token);
      return freshSessions;
    }

    // Otherwise, use offline-first approach: load from cache first for instant response
    final cachedSessions = await _getLocalSessions(db, token);

    // Then sync with server in background if online (don't block). The
    // context captured above is handed straight into the closure, so this
    // detached refresh stays bound to the session that scheduled it even
    // if a different user logs in before it completes.
    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _syncSessionsFromServer(db, context),
        'Sessions synced from server',
      );
    }

    return cachedSessions;
  }

  /// Get all in-progress sessions for the current user
  /// Used to ensure only one workout is active at a time
  Future<List<Session>> getInProgressSessions() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      debugPrint('⚠️ No authenticated session, returning empty list');
      return [];
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    // Get all in-progress sessions from local DB
    final localSessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(token.userId)
            .statusEqualTo('in_progress')
            .findAll();
    if (!_sessionEpoch.isCurrent(token)) return [];

    // Convert to Session models with exercises (using helper)
    final sessions = <Session>[];
    for (final localSession in localSessions) {
      sessions.add(await _localSessionToSessionWithExercises(db, localSession));
    }

    return sessions;
  }

  /// Background sync: Fetch sessions from server and update cache. Bound to
  /// [context]: the HTTP call carries its pinned JWT, and every cache write
  /// is gated behind the class doc comment's three-checkpoint shape plus a
  /// direct [LocalSession.userId] ownership check.
  Future<void> _syncSessionsFromServer(
    Isar db,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    // Fetch from API
    final data = await _dispatchBackgroundHttp(
      () => _apiService.get<List<dynamic>>(
        ApiConfig.sessions,
        sessionContext: context,
      ),
    );

    debugPrint('📥 Received ${data.length} sessions from API');

    final apiSessions =
        data
            .map((json) => Session.fromJson(json as Map<String, dynamic>))
            .toList();

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final currentUserId = token.userId;

    // Checkpoint: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(token)) return;

    // Update local cache (sessions AND their exercises)
    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(token)) return;

      for (final apiSession in apiSessions) {
        // Only cache sessions belonging to current user
        if (apiSession.userId != currentUserId) {
          debugPrint(
            '  ⏭️ Skipping session ${apiSession.id} - belongs to different user (${apiSession.userId} != $currentUserId)',
          );
          continue;
        }

        // Check if session already exists locally
        final existingLocal =
            await db.localSessions
                .filter()
                .serverIdEqualTo(apiSession.id)
                .findFirst();

        // Never overwrite a row that no longer belongs to the current
        // user - a serverId collision (or a foreign row somehow sharing
        // it) must never be silently claimed by this refresh.
        if (existingLocal != null && existingLocal.userId != currentUserId) {
          debugPrint(
            '  ⏭️ Skipping session ${apiSession.id} - local row owned by a different user',
          );
          continue;
        }

        // Skip sessions with pending local changes - don't overwrite with
        // server data. 'conflict' rows are included here: a background
        // cache refresh must never silently discard the local edit and
        // conflict metadata a 409 resolution still needs.
        if (existingLocal != null &&
            (existingLocal.syncStatus == 'pending_delete' ||
                existingLocal.syncStatus == 'pending_update' ||
                existingLocal.syncStatus == 'conflict')) {
          debugPrint(
            '  ⏭️ Skipping session ${apiSession.id} - has pending local changes (${existingLocal.syncStatus})',
          );
          continue;
        }

        // CRITICAL FIX: Never overwrite in-progress sessions from server!
        // This prevents the 5-hour timer bug caused by server returning incorrect timestamps.
        // Local state is authoritative for active workouts.
        if (existingLocal != null && existingLocal.status == 'in_progress') {
          debugPrint(
            '  ⏭️ Skipping session ${apiSession.id} - in_progress workout, keeping local timestamps',
          );
          continue;
        }

        LocalSession savedSession;
        if (existingLocal != null) {
          // Update existing local session
          final updated = ModelMapper.sessionToLocal(
            apiSession,
            localId: existingLocal.localId,
            isSynced: true,
          );
          await db.localSessions.put(updated);
          savedSession = updated;
        } else {
          // Create new local session
          final localSession = ModelMapper.sessionToLocal(apiSession);
          await db.localSessions.put(localSession);
          savedSession = localSession;
        }

        // Save exercises for this session
        int exerciseCount = 0;
        for (final apiExercise in apiSession.exercises) {
          // Check if exercise already exists locally
          final existingExercise =
              await db.localExercises
                  .filter()
                  .serverIdEqualTo(apiExercise.id)
                  .findFirst();

          if (existingExercise != null) {
            // Update existing
            final updated = ModelMapper.exerciseToLocal(
              apiExercise,
              sessionLocalId: savedSession.localId,
              localId: existingExercise.localId,
              isSynced: true,
            );
            await db.localExercises.put(updated);
          } else {
            // Create new
            final localExercise = ModelMapper.exerciseToLocal(
              apiExercise,
              sessionLocalId: savedSession.localId,
            );
            await db.localExercises.put(localExercise);
          }
          exerciseCount++;
        }
        debugPrint(
          '  📝 Cached $exerciseCount exercises for session ${apiSession.id}',
        );
      }

      // Remove sessions that were deleted on the server (cascade delete cleanup).
      // Already scoped to currentUserId, so this cannot touch another
      // user's rows.
      final serverSessionIds = apiSessions.map((s) => s.id).toSet();
      final allLocalSessions =
          await db.localSessions
              .filter()
              .userIdEqualTo(currentUserId)
              .serverIdIsNotNull()
              .findAll();

      for (final localSession in allLocalSessions) {
        if (!serverSessionIds.contains(localSession.serverId)) {
          debugPrint(
            '  🗑️ Removing session ${localSession.serverId} (deleted on server)',
          );

          final exercisesToDelete =
              await db.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(localSession.localId)
                  .findAll();

          for (final exercise in exercisesToDelete) {
            await db.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(exercise.localId)
                .deleteAll();
            await db.localExercises.delete(exercise.localId);
          }

          await db.localSessions.delete(localSession.localId);
        }
      }
    });

    debugPrint('✅ Synced ${apiSessions.length} sessions from server');
  }

  /// Get sessions from local database with exercises, scoped to [token].
  Future<List<Session>> _getLocalSessions(
    Isar db,
    UserSessionToken token,
  ) async {
    final localSessions =
        await db.localSessions.filter().userIdEqualTo(token.userId).findAll();
    if (!_sessionEpoch.isCurrent(token)) return [];

    // Convert to Session models, skipping deleted/archived (using helper)
    final sessions = <Session>[];
    for (final localSession in localSessions) {
      // Skip sessions marked for deletion or archived
      if (localSession.syncStatus == 'pending_delete' ||
          localSession.status == 'archived') {
        continue;
      }

      sessions.add(await _localSessionToSessionWithExercises(db, localSession));
    }

    return sessions;
  }

  /// Get session by ID
  /// Offline-first: returns local cache, then tries to sync with server
  Future<Session> getSession(int id) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    // Check if there's a local (owned) version with pending changes
    final localSession = await _resolveOwnedSession(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // If local session has pending changes, return it instead of fetching from server
    if (localSession != null && !localSession.isSynced) {
      debugPrint('📝 Session has pending changes, returning local version');
      return await _localSessionToSessionWithExercises(db, localSession);
    }

    // CRITICAL FIX: Always use local data for in-progress sessions!
    // This prevents the 5-hour timer bug caused by server returning incorrect timestamps.
    // Local timestamps are authoritative during active workouts.
    if (localSession != null && localSession.status == 'in_progress') {
      debugPrint(
        '🏋️ In-progress session - using local timestamps (startedAt: ${localSession.startedAt})',
      );
      return await _localSessionToSessionWithExercises(db, localSession);
    }

    if (_connectivity.isOnline) {
      try {
        // Fetch from API
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.sessionById(id),
          sessionContext: context,
        );

        final apiSession = Session.fromJson(data);

        if (apiSession.userId != token.userId) {
          debugPrint('⚠️ Server returned a session for a different user');
          return await _getLocalSession(db, id, token);
        }

        await _runTestHook(beforeWriteTxnForTesting);
        if (!_sessionEpoch.isCurrent(token)) {
          throw const SessionStaleException();
        }

        // Update local cache (session AND exercises)
        await db.writeTxn(() async {
          await _runTestHook(insideWriteTxnForTesting);
          if (!_sessionEpoch.isCurrent(token)) return;

          final existingLocal =
              await db.localSessions
                  .filter()
                  .serverIdEqualTo(apiSession.id)
                  .findFirst();
          if (existingLocal != null && existingLocal.userId != token.userId) {
            return;
          }

          LocalSession savedSession;
          if (existingLocal != null) {
            final updated = ModelMapper.sessionToLocal(
              apiSession,
              localId: existingLocal.localId,
              isSynced: true,
            );
            await db.localSessions.put(updated);
            savedSession = updated;
          } else {
            final localSession = ModelMapper.sessionToLocal(apiSession);
            await db.localSessions.put(localSession);
            savedSession = localSession;
          }

          // Save exercises for this session
          for (final apiExercise in apiSession.exercises) {
            final existingExercise =
                await db.localExercises
                    .filter()
                    .serverIdEqualTo(apiExercise.id)
                    .findFirst();

            if (existingExercise != null) {
              final updated = ModelMapper.exerciseToLocal(
                apiExercise,
                sessionLocalId: savedSession.localId,
                localId: existingExercise.localId,
                isSynced: true,
              );
              await db.localExercises.put(updated);
            } else {
              final localExercise = ModelMapper.exerciseToLocal(
                apiExercise,
                sessionLocalId: savedSession.localId,
              );
              await db.localExercises.put(localExercise);
            }
          }
        });

        return apiSession;
      } on SessionStaleException {
        return await _getLocalSession(db, id, token);
      } on RequestCancelledException {
        return await _getLocalSession(db, id, token);
      } catch (e) {
        debugPrint('⚠️ API failed, falling back to local cache: $e');
        return await _getLocalSession(db, id, token);
      }
    } else {
      debugPrint('📴 Offline - returning cached session');
      return await _getLocalSession(db, id, token);
    }
  }

  /// Get session from local database by owned ID (server ID or local ID)
  /// with exercises
  Future<Session> _getLocalSession(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    final exercises = await _loadExercisesForSession(db, localSession.localId);

    debugPrint(
      '  📦 Loaded session ${localSession.serverId ?? localSession.localId} from cache with ${exercises.length} exercises',
    );

    return ModelMapper.localToSession(localSession, exercises: exercises);
  }

  /// Create new session
  /// Optimistic update: saves locally first, syncs to server if online
  Future<Session> createSession(Session session) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final db = _localDb.database;

    // ALWAYS create locally first for instant response, always owned by
    // the captured user regardless of what the caller-supplied [session]
    // claims.
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    final localResult = await _createLocalSession(
      session,
      db,
      token,
      isPending: true,
    );
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // Then sync to server in background if online (don't block). Bound to
    // the context captured at entry.
    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _syncCreateSessionToServer(session, db, localResult.id, context),
        'Created session on server',
      );
    } else {
      debugPrint('📴 Offline - session will sync later');
    }

    return localResult;
  }

  /// Helper method to convert LocalSession to Session with exercises
  Future<Session> _getSessionWithExercises(LocalSession localSession) async {
    final db = _localDb.database;
    return await _localSessionToSessionWithExercises(db, localSession);
  }

  /// Create a session from a program workout
  /// Links the session to the program and program workout
  /// Now works offline by parsing exercisesJson client-side
  Future<Session> createSessionFromProgramWorkout(
    int programWorkoutId,
    ProgramWorkout programWorkout,
    DateTime programStartDate,
    int programId, // Use actual programId instead of programWorkout.programId
  ) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final db = _localDb.database;
    final userId = token.userId;

    // Check if a session already exists for this program workout
    final existingSessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .programWorkoutIdEqualTo(programWorkoutId)
            .findAll();
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // Find existing draft, planned, in_progress, or paused session
    final existingActiveSession = existingSessions.firstWhere(
      (session) =>
          session.status == 'draft' ||
          session.status == 'planned' ||
          session.status == 'in_progress' ||
          session.status == 'paused',
      orElse:
          () => LocalSession(
            userId: 0,
            date: DateTime.now(),
            type: '',
            name: '',
            status: '',
            lastModifiedLocal: DateTime.now().toUtc(),
          ), // Dummy session
    );

    // If we found an existing active session, return it
    if (existingActiveSession.userId != 0) {
      debugPrint(
        '✅ Found existing ${existingActiveSession.status} session for program workout $programWorkoutId',
      );
      return await _getSessionWithExercises(existingActiveSession);
    }

    // Check if there's a completed session (can't restart completed workouts)
    final existingCompletedSession = existingSessions.firstWhere(
      (session) => session.status == 'completed',
      orElse:
          () => LocalSession(
            userId: 0,
            date: DateTime.now(),
            type: '',
            name: '',
            status: '',
            lastModifiedLocal: DateTime.now().toUtc(),
          ),
    );

    // If past workout is already completed, can't start it again
    if (existingCompletedSession.userId != 0) {
      debugPrint('⚠️ Cannot start completed program workout $programWorkoutId');
      throw Exception(
        'This workout is already completed. You cannot start it again.',
      );
    }

    debugPrint(
      '📝 No existing draft/planned session found, creating new session for program workout $programWorkoutId',
    );

    // Try to create on server if online
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.post<Map<String, dynamic>>(
          ApiConfig.sessionsFromProgramWorkout,
          data: {'programWorkoutId': programWorkoutId, 'programId': programId},
          sessionContext: context,
        );
        var apiSession = Session.fromJson(data);

        // Use scheduledDate from ProgramWorkout if available (single source of truth)
        DateTime correctScheduledDate;
        if (programWorkout.scheduledDate != null) {
          final sd = programWorkout.scheduledDate!;
          correctScheduledDate = DateTime(sd.year, sd.month, sd.day);
        } else {
          final localStartDate = programStartDate.toLocal();
          final startDate = DateTime(
            localStartDate.year,
            localStartDate.month,
            localStartDate.day,
          );
          correctScheduledDate = startDate.add(
            Duration(
              days:
                  (programWorkout.weekNumber - 1) * 7 +
                  (programWorkout.dayNumber - 1),
            ),
          );
        }

        final today = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        );

        final actualDate =
            correctScheduledDate.isBefore(today) ? today : correctScheduledDate;

        final apiDate = DateTime(
          apiSession.date.year,
          apiSession.date.month,
          apiSession.date.day,
        );

        if (apiDate != actualDate) {
          debugPrint(
            '📅 Using scheduledDate from program workout: $apiDate -> $actualDate',
          );
          apiSession = apiSession.copyWith(date: actualDate);
        }

        await _runTestHook(beforeWriteTxnForTesting);
        if (!_sessionEpoch.isCurrent(token)) {
          throw Exception(_unauthenticated);
        }

        // Cache the session locally with exercises
        await db.writeTxn(() async {
          await _runTestHook(insideWriteTxnForTesting);
          if (!_sessionEpoch.isCurrent(token)) return;

          final localSession = ModelMapper.sessionToLocal(
            apiSession,
            isSynced: true,
          );
          await db.localSessions.put(localSession);

          for (final apiExercise in apiSession.exercises) {
            final localExercise = ModelMapper.exerciseToLocal(
              apiExercise,
              sessionLocalId: localSession.localId,
              isSynced: true,
            );
            await db.localExercises.put(localExercise);
          }
        });

        debugPrint('✅ Created session from program workout: ${apiSession.id}');
        return apiSession;
      } on SessionStaleException {
        throw Exception(_unauthenticated);
      } on RequestCancelledException {
        throw Exception(_unauthenticated);
      } catch (e) {
        debugPrint(
          '⚠️ Failed to create session on server, creating locally: $e',
        );
        // Fall through to offline creation
      }
    }

    // Offline creation: Parse exercisesJson and create locally
    debugPrint('📴 Creating session from program workout offline');

    final exercisesData = programWorkout.exercises;
    final exercises = <Exercise>[];

    DateTime normalizedScheduledDate;
    if (programWorkout.scheduledDate != null) {
      final sd = programWorkout.scheduledDate!;
      normalizedScheduledDate = DateTime(sd.year, sd.month, sd.day);
    } else {
      final localStartDate = programStartDate.toLocal();
      final startDate = DateTime(
        localStartDate.year,
        localStartDate.month,
        localStartDate.day,
      );
      final scheduledDate = startDate.add(
        Duration(
          days:
              (programWorkout.weekNumber - 1) * 7 +
              (programWorkout.dayNumber - 1),
        ),
      );
      normalizedScheduledDate = DateTime(
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
      );
    }

    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    final actualDate =
        normalizedScheduledDate.isBefore(today)
            ? today
            : normalizedScheduledDate;

    final status = actualDate.isAfter(today) ? 'planned' : 'draft';

    final session = Session(
      id: 0,
      userId: userId,
      date: actualDate,
      name: programWorkout.workoutName,
      type: programWorkout.workoutType ?? 'Workout',
      status: status,
      programId: programId,
      programWorkoutId: programWorkoutId,
      exercises: exercises,
    );

    late int sessionLocalId;

    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final localSession = LocalSession(
        serverId: null,
        userId: userId,
        date: session.date,
        duration: session.duration,
        notes: session.notes,
        type: session.type,
        name: session.name,
        status: session.status,
        startedAt: session.startedAt,
        completedAt: session.completedAt,
        pausedAt: session.pausedAt,
        programId: session.programId,
        programWorkoutId: session.programWorkoutId,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );

      sessionLocalId = await db.localSessions.put(localSession);

      for (final exerciseData in exercisesData) {
        final exerciseName = exerciseData['name'] as String? ?? 'Exercise';
        final exerciseTemplateId = exerciseData['exerciseTemplateId'] as int?;
        final notes = exerciseData['notes'] as String?;
        final restTime = exerciseData['rest'] as int?;

        final exercise = Exercise(
          id: 0,
          sessionId: sessionLocalId,
          name: exerciseName,
          exerciseTemplateId: exerciseTemplateId,
          notes: notes,
          restTime: restTime,
          duration: null,
          exerciseSets: [],
        );

        final localExercise = ModelMapper.exerciseToLocal(
          exercise,
          sessionLocalId: sessionLocalId,
          isSynced: false,
        );
        final exerciseLocalId = await db.localExercises.put(localExercise);

        exercises.add(exercise.copyWith(id: exerciseLocalId));
      }
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    debugPrint(
      '💾 Created session offline with ${exercises.length} exercises (localId: $sessionLocalId)',
    );

    return Session(
      id: sessionLocalId,
      userId: userId,
      date: session.date,
      duration: session.duration,
      notes: session.notes,
      type: session.type,
      name: session.name,
      status: session.status,
      startedAt: session.startedAt,
      completedAt: session.completedAt,
      pausedAt: session.pausedAt,
      programId: session.programId,
      programWorkoutId: session.programWorkoutId,
      exercises: exercises,
    );
  }

  /// Background sync: Create session on server. Bound to [context]: the
  /// HTTP call carries its pinned JWT, and the resulting acknowledgment is
  /// gated behind the class doc comment's three-checkpoint shape plus a
  /// re-resolution of the target row by its stable local identity and
  /// direct ownership.
  Future<void> _syncCreateSessionToServer(
    Session session,
    Isar db,
    int localId,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    final data = await _dispatchBackgroundHttp(
      () => _apiService.post<Map<String, dynamic>>(
        ApiConfig.sessions,
        data: session.toJson(),
        sessionContext: context,
      ),
    );
    final apiSession = Session.fromJson(data);

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    // Re-resolve by stable local identity and direct ownership before
    // deciding whether to acknowledge.
    final target = await _ownedSessionByLocalId(db, localId, token);
    if (target == null) return;

    // Checkpoint: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(token)) return;

      final existing = await db.localSessions.get(localId);
      if (existing == null || existing.userId != token.userId) return;

      final updated = ModelMapper.sessionToLocal(
        apiSession,
        localId: localId,
        isSynced: true,
      );
      await db.localSessions.put(updated);
    });
  }

  /// Create session in local database, always owned by [token.userId]
  /// regardless of what [session] claims.
  Future<Session> _createLocalSession(
    Session session,
    Isar db,
    UserSessionToken token, {
    required bool isPending,
  }) async {
    final localSession = LocalSession(
      serverId: isPending ? null : session.id,
      userId: token.userId,
      date: session.date,
      duration: session.duration,
      notes: session.notes,
      type: session.type,
      name: session.name,
      status: session.status,
      startedAt: session.startedAt,
      completedAt: session.completedAt,
      pausedAt: session.pausedAt,
      programId: session.programId,
      programWorkoutId: session.programWorkoutId,
      isSynced: !isPending,
      syncStatus: isPending ? 'pending_create' : 'synced',
      lastModifiedLocal: DateTime.now().toUtc(),
    );

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      await db.localSessions.put(localSession);
    });

    debugPrint('💾 Saved session locally: ${localSession.localId}');

    return Session(
      id: localSession.localId,
      userId: localSession.userId,
      date: localSession.date,
      duration: localSession.duration,
      notes: localSession.notes,
      type: localSession.type,
      name: localSession.name,
      status: localSession.status,
      startedAt: localSession.startedAt,
      completedAt: localSession.completedAt,
      pausedAt: localSession.pausedAt,
      programId: localSession.programId,
      programWorkoutId: localSession.programWorkoutId,
    );
  }

  /// Update session status
  /// Optimistic update: updates locally first, syncs to server if online
  /// [startedAtUtc] optional timestamp for when starting workout (calculated by provider)
  Future<Session> updateSessionStatus(
    int id,
    String status, {
    int? duration,
    DateTime? startedAtUtc,
  }) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // ALWAYS update locally first for instant response
    await _updateLocalSessionStatus(
      db,
      localSession,
      status,
      token,
      duration: duration,
      startedAtUtc: startedAtUtc,
    );
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // Then sync to server in background if online (using helper), unless
    // the row has an unresolved conflict - it must not be pushed until
    // explicitly resolved.
    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _syncSessionStatusToServer(
          db,
          localSession.localId,
          localSession.serverId!,
          context,
        ),
        'Updated session status on server',
      );
    } else if (_isConflicted(localSession)) {
      debugPrint('⚠️ Session has an unresolved conflict - skipping sync');
    } else {
      debugPrint('📴 Offline - session status will sync later');
    }

    // Return session with exercises using helper
    return await _localSessionToSessionWithExercises(db, localSession);
  }

  /// Background sync: Update session status on server. Bound to [context]:
  /// the HTTP call carries its pinned JWT, and the resulting acknowledgment
  /// is gated behind the class doc comment's three-checkpoint shape plus a
  /// re-resolution of the target row by its STABLE LOCAL ID and direct
  /// ownership (never an unscoped `serverIdEqualTo` lookup).
  Future<void> _syncSessionStatusToServer(
    Isar db,
    int sessionLocalId,
    int serverId,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    // Snapshot the fields to send from the currently-owned row before
    // dispatching, so a concurrent edit mid-flight can't be lost.
    final source = await _ownedSessionByLocalId(db, sessionLocalId, token);
    if (source == null) return;

    String? toUtcIso8601(DateTime? dt) => dt?.toUtc().toIso8601String();

    final startedAtString = toUtcIso8601(source.startedAt);
    final pausedAtString = toUtcIso8601(source.pausedAt);

    final requestData = {
      'status': source.status,
      if (source.startedAt != null) 'startedAt': startedAtString,
      if (source.completedAt != null)
        'completedAt': toUtcIso8601(source.completedAt),
      if (source.pausedAt != null) 'pausedAt': pausedAtString,
      if (source.pausedAt == null) 'clearPausedAt': true,
      if (source.duration != null) 'duration': source.duration,
    };

    await _dispatchBackgroundHttp(
      () => _apiService.patch<void>(
        ApiConfig.sessionStatus(serverId),
        data: requestData,
        sessionContext: context,
      ),
    );

    debugPrint('✅ Synced session $serverId with timestamps');

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    // Re-resolve by stable local identity and direct ownership.
    final target = await _ownedSessionByLocalId(db, sessionLocalId, token);
    if (target == null) return;

    // Checkpoint: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(token)) return;

      final session = await db.localSessions.get(sessionLocalId);
      if (session == null || session.userId != token.userId) return;

      session.isSynced = true;
      session.syncStatus = 'synced';
      await db.localSessions.put(session);
    });
  }

  /// Update session status in local database
  /// [startedAtUtc] optional timestamp from provider (ensures UTC consistency)
  Future<void> _updateLocalSessionStatus(
    Isar db,
    LocalSession localSession,
    String status,
    UserSessionToken token, {
    int? duration,
    DateTime? startedAtUtc,
  }) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final now = DateTime.now();
      final conflicted = _isConflicted(localSession);
      localSession.status = status;
      localSession.lastModifiedLocal = now;
      if (!conflicted) {
        localSession.isSynced = false;
      }

      // Set startedAt when status changes to 'in_progress'
      if (status == 'in_progress' && localSession.startedAt == null) {
        final timestampToUse = startedAtUtc ?? DateTime.now().toUtc();
        localSession.startedAt = timestampToUse;
        localSession.pausedAt = null;
      }

      // Set completedAt when status changes to 'completed'
      if (status == 'completed' && localSession.completedAt == null) {
        final completedAtUtc = DateTime.now().toUtc();
        localSession.completedAt = completedAtUtc;
        await _updateWorkoutGoals(db, token.userId, completedAtUtc);
      }

      if (duration != null) {
        localSession.duration = duration;
      }

      if (!conflicted && localSession.serverId != null) {
        localSession.syncStatus = 'pending_update';
      }
      await db.localSessions.put(localSession);
    });

    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Update workout frequency goals when a workout is completed (Issue #11)
  ///
  /// NOTE: Currently goals are server-only (no LocalGoal model exists).
  /// This method documents the intended client-side goal update logic; see
  /// git history for the previous full commented-out implementation sketch.
  Future<void> _updateWorkoutGoals(
    Isar db,
    int userId,
    DateTime completedAt,
  ) async {
    debugPrint(
      '📊 Goal updates (Issue #11): Currently server-only. LocalGoal model needed for offline support.',
    );
  }

  /// Pause session timer
  /// Works offline by updating local database
  /// [pausedAt] timestamp from provider (to avoid time drift)
  Future<void> pauseSession(int id, DateTime pausedAt) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      localSession.pausedAt = pausedAt;
      _applyLocalEditBookkeeping(localSession);
      await db.localSessions.put(localSession);
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    debugPrint('⏸️ Session paused locally (pausedAt UTC: $pausedAt)');

    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _syncSessionStatusToServer(
          db,
          localSession.localId,
          localSession.serverId!,
          context,
        ),
        'Pause synced to server',
      );
    }
  }

  /// Resume session timer
  /// Works offline by updating local database
  /// [newStartedAt] adjusted timestamp from provider (to avoid time drift)
  Future<void> resumeSession(int id, DateTime newStartedAt) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      localSession.startedAt = newStartedAt;
      localSession.pausedAt = null;
      _applyLocalEditBookkeeping(localSession);
      await db.localSessions.put(localSession);
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    debugPrint('▶️ Session resumed locally');

    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _syncSessionStatusToServer(
          db,
          localSession.localId,
          localSession.serverId!,
          context,
        ),
        'Resume synced to server',
      );
    }
  }

  /// Archive a session (change status to 'archived')
  /// Archived sessions are hidden from main list but still count for programs
  Future<bool> archiveSession(int id) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    await _markSessionForSync(db, localSession, token, newStatus: 'archived');
    await _runTestHook(afterWriteTxnForTesting);

    debugPrint(
      '📦 Archived session: ${localSession.serverId ?? localSession.localId}',
    );
    return true;
  }

  /// Delete session
  /// Marks as pending_delete offline, deletes from server when online
  Future<bool> deleteSession(int id) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // Prevent deletion of completed program workouts
    if (localSession.status == 'completed' &&
        localSession.programWorkoutId != null) {
      throw Exception(
        'Cannot delete completed program workout. Archive it instead.',
      );
    }

    if (_connectivity.isOnline && localSession.serverId != null) {
      try {
        final success = await _apiService.delete(
          ApiConfig.sessionById(localSession.serverId!),
          sessionContext: context,
        );

        if (success) {
          if (!_sessionEpoch.isCurrent(token)) {
            throw Exception(_unauthenticated);
          }
          await _deleteSessionAndRelatedData(db, localSession, token);
          debugPrint('✅ Deleted session from server: ${localSession.serverId}');
          return true;
        }
        return false;
      } on SessionStaleException {
        await _markForDeletion(db, localSession, token);
        return true;
      } on RequestCancelledException {
        await _markForDeletion(db, localSession, token);
        return true;
      } catch (e) {
        debugPrint('⚠️ Delete API failed, marking as pending: $e');
        await _markForDeletion(db, localSession, token);
        return true;
      }
    } else {
      debugPrint('📴 Offline - marking session for deletion');
      await _markForDeletion(db, localSession, token);
      return true;
    }
  }

  /// Mark session for deletion (to be synced later)
  Future<void> _markForDeletion(
    Isar db,
    LocalSession localSession,
    UserSessionToken token,
  ) async {
    if (localSession.serverId == null) {
      await _deleteSessionAndRelatedData(db, localSession, token);
    } else {
      await _runTestHook(beforeWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      await db.writeTxn(() async {
        await _runTestHook(insideWriteTxnForTesting);
        if (!_sessionEpoch.isCurrent(token)) return;
        localSession.isSynced = false;
        localSession.syncStatus = 'pending_delete';
        localSession.lastModifiedLocal = DateTime.now().toUtc();
        await db.localSessions.put(localSession);
      });
      await _runTestHook(afterWriteTxnForTesting);
    }
  }

  /// Delete session and all related exercises and sets. Reverifies parent
  /// ownership as the first statement inside the transaction, per the class
  /// doc comment's session graph ownership section - this must never delete
  /// a session/its children that have been reassigned or replaced since
  /// [localSession] was resolved.
  Future<void> _deleteSessionAndRelatedData(
    Isar db,
    LocalSession localSession,
    UserSessionToken token,
  ) async {
    final localId = localSession.localId;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final current = await db.localSessions.get(localId);
      if (current == null || current.userId != token.userId) return;

      final exercises =
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(localId)
              .findAll();

      for (final exercise in exercises) {
        await _runTestHook(beforeChildDeleteForTesting);
        // Grandparent-ownership recheck: re-resolve the exercise by its
        // stable local identity and confirm it still belongs to the
        // session being deleted before touching its sets - closes the
        // window between the query above and this delete.
        final currentExercise = await db.localExercises.get(exercise.localId);
        if (currentExercise == null ||
            currentExercise.sessionLocalId != localId) {
          continue;
        }
        await db.localExerciseSets
            .filter()
            .exerciseLocalIdEqualTo(exercise.localId)
            .deleteAll();
        await db.localExercises.delete(exercise.localId);
      }

      await db.localSessions.delete(localId);
    });
    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Update session name
  /// Optimistic update: updates locally first, syncs to server if online
  Future<Session> updateSessionName(int id, String name) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      localSession.name = name;
      _applyLocalEditBookkeeping(localSession);
      await db.localSessions.put(localSession);
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    debugPrint('✏️ Session name updated locally to: $name');

    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _pushSessionUpdate(
          db,
          localSession.localId,
          'session name',
          context,
        ),
        'Updated session name on server',
      );
    } else if (_isConflicted(localSession)) {
      debugPrint('⚠️ Session has an unresolved conflict - skipping sync');
    } else {
      debugPrint('📴 Offline - session name will sync later');
    }

    return await _localSessionToSessionWithExercises(db, localSession);
  }

  /// Update workout date (used when starting future planned workout early)
  /// Optimistic update: updates locally first, syncs to server if online
  Future<void> updateWorkoutDate(int id, DateTime newDate) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      final dateOnly = DateTime(newDate.year, newDate.month, newDate.day);
      localSession.date = dateOnly;
      _applyLocalEditBookkeeping(localSession);
      await db.localSessions.put(localSession);
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    debugPrint('📅 Workout date updated locally to: $newDate');

    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _pushSessionUpdate(
          db,
          localSession.localId,
          'workout date',
          context,
        ),
        'Updated workout date on server',
      );
    } else if (_isConflicted(localSession)) {
      debugPrint('⚠️ Session has an unresolved conflict - skipping sync');
    } else {
      debugPrint('📴 Offline - workout date will sync later');
    }
  }

  /// Push a full-session PUT update via the centralized sync helper and log
  /// the outcome. Bound to [context]: the PUT (and, on a non-map success
  /// response, the helper's own recovery GET) carries the pinned JWT, and
  /// every write the helper may perform is additionally gated by
  /// `isSessionCurrent`/`scopeUserId` - see `SessionUpdateSyncHelper`'s own
  /// class doc comment. [sessionLocalId] is re-resolved by its stable local
  /// identity and ownership immediately before dispatch, so a stale target
  /// is never pushed.
  Future<void> _pushSessionUpdate(
    Isar db,
    int sessionLocalId,
    String what,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    final session = await _ownedSessionByLocalId(db, sessionLocalId, token);
    if (session == null) return;
    if (!_sessionEpoch.isCurrent(token)) return;

    final outcome = await _dispatchBackgroundHttp(
      () => SessionUpdateSyncHelper(_apiService).pushUpdate(
        db,
        session,
        sessionContext: context,
        isSessionCurrent: () => _sessionEpoch.isCurrent(token),
        scopeUserId: token.userId,
      ),
    );

    switch (outcome) {
      case SessionSyncOutcome.synced:
        debugPrint('✅ Synced $what to server');
        break;
      case SessionSyncOutcome.conflict:
        debugPrint(
          '⚠️ Conflict detected updating $what - stored for manual resolution',
        );
        break;
      case SessionSyncOutcome.conflictDataInvalid:
        debugPrint(
          '⚠️ Conflict response malformed updating $what - will retry later',
        );
        break;
      case SessionSyncOutcome.deferred:
        debugPrint('⚠️ Could not confirm $what update - will retry later');
        break;
    }
  }

  /// Watch sessions for reactive updates (Issue #7)
  /// Returns a stream that emits whenever sessions change in local DB
  /// This enables automatic UI updates when background sync completes
  Stream<List<Session>> watchSessions(int userId) {
    final db = _localDb.database;

    return db.localSessions
        .filter()
        .userIdEqualTo(userId)
        .watch(fireImmediately: true)
        .asyncMap((localSessions) async {
          final sessions = <Session>[];
          for (final localSession in localSessions) {
            if (localSession.syncStatus == 'pending_delete' ||
                localSession.status == 'archived') {
              continue;
            }
            sessions.add(
              await _localSessionToSessionWithExercises(db, localSession),
            );
          }

          sessions.sort((a, b) => b.date.compareTo(a.date));
          return sessions;
        });
  }

  /// Add exercise to session
  /// Works offline by creating locally and syncing later
  Future<Exercise> addExerciseToSession(
    int sessionId,
    int exerciseTemplateId,
  ) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(
      db,
      sessionId,
      token,
    );
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    if (_connectivity.isOnline && localSession.serverId != null) {
      try {
        final data = await _apiService.post<Map<String, dynamic>>(
          ApiConfig.sessionExercises(localSession.serverId!),
          data: {'exerciseTemplateId': exerciseTemplateId},
          sessionContext: context,
        );
        final apiExercise = Exercise.fromJson(data);

        if (!_sessionEpoch.isCurrent(token)) {
          throw const SessionStaleException();
        }
        if (!await _isSessionOwnedByLocalId(db, localSession.localId, token)) {
          throw const SessionStaleException();
        }

        await _runTestHook(beforeWriteTxnForTesting);
        await db.writeTxn(() async {
          await _runTestHook(insideWriteTxnForTesting);
          if (!_sessionEpoch.isCurrent(token)) {
            throw const SessionStaleException();
          }

          // Freshly reacquire the session by its stable local identity and
          // re-verify ownership as the first operation inside the
          // transaction - the pre-transaction check above (and the
          // `localSession` object it used) proves nothing about the state
          // at the moment this write actually happens, only about the
          // moment it was read. Never reuse that stale object as proof of
          // ownership here.
          final owningSession = await db.localSessions.get(
            localSession.localId,
          );
          if (owningSession == null || owningSession.userId != token.userId) {
            throw const SessionStaleException();
          }

          final localExercise = ModelMapper.exerciseToLocal(
            apiExercise,
            sessionLocalId: owningSession.localId,
            isSynced: true,
          );
          await db.localExercises.put(localExercise);
        });

        return apiExercise;
      } on SessionStaleException {
        // Fall through to offline creation below.
      } on RequestCancelledException {
        // Fall through to offline creation below.
      } catch (e) {
        debugPrint('⚠️ Add exercise API failed, creating locally: $e');
      }
    }

    // Create exercise locally (offline, API failed, or session no longer current)
    String exerciseName = 'Exercise';
    try {
      final templates =
          await db.collection<LocalExerciseTemplate>().where().findAll();
      final template = templates.firstWhere(
        (t) => t.serverId == exerciseTemplateId,
        orElse: () => templates.first,
      );
      exerciseName = template.name;
    } catch (e) {
      debugPrint('⚠️ Could not find exercise template $exerciseTemplateId: $e');
    }

    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    int localId = 0;

    await _runTestHook(beforeWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final current = await db.localSessions.get(localSession.localId);
      if (current == null || current.userId != token.userId) return;

      final tempExercise = Exercise(
        id: 0,
        sessionId: sessionId,
        name: exerciseName,
        exerciseTemplateId: exerciseTemplateId,
        duration: null,
        restTime: null,
        notes: null,
        exerciseSets: [],
      );

      final localExercise = ModelMapper.exerciseToLocal(
        tempExercise,
        sessionLocalId: localSession.localId,
        isSynced: false,
      );
      localId = await db.localExercises.put(localExercise);
    });

    final newExercise = Exercise(
      id: localId,
      sessionId: sessionId,
      name: exerciseName,
      exerciseTemplateId: exerciseTemplateId,
      duration: null,
      restTime: null,
      notes: null,
      exerciseSets: [],
    );

    debugPrint(
      '➕ Created exercise "$exerciseName" locally (offline), id=$localId, will sync later',
    );
    return newExercise;
  }
}
