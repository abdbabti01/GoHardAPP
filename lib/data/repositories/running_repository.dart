import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/run_session.dart';
import '../models/gps_point.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../local/services/local_database_service.dart';
import '../local/models/local_run_session.dart';

/// Repository for running session operations with offline-first support and
/// server sync.
///
/// ## Session/ownership model
///
/// Every public asynchronous operation below that touches authenticated run
/// data captures a [SessionRequestContext] via [_sessionCoordinator] at
/// operation entry (never after an internal `await`), and uses
/// `context.epochToken.userId` as the sole authoritative user for the
/// remainder of that operation - never a later, independently re-read user
/// ID. A `null` capture (logged out, or the session changed while the JWT
/// read was in flight) follows the same not-found/unauthenticated
/// convention each method already used before this fix (`null` for
/// [getRunSession]/list queries, `Exception('No authenticated user')` for
/// everything that previously required auth implicitly).
///
/// Every [ApiService] call this repository makes - foreground (awaited
/// inline, e.g. [deleteRun]'s server delete) or background (fire-and-forget,
/// [_syncFromServer]/[_syncRunToServer]) - is bound to that captured
/// context, so it carries the pinned JWT captured at entry rather than
/// whatever the live token happens to be, and can never be dispatched after
/// the session that started it has ended (see [ApiService]'s own class doc
/// comment). Every background push schedules with the context already
/// captured at the public entry point that scheduled it - never a context
/// (re)captured inside the closure itself - so a detached operation stays
/// bound to the session that scheduled it, not whichever session happens to
/// be active when it finally runs.
///
/// ## Local ID ownership
///
/// Unlike [SessionRepository]/`LocalSession`, [LocalRunSession] IDs have no
/// server/local ambiguity to resolve: every public method below that takes
/// an `int localId` parameter takes a genuine local Isar ID, never a server
/// ID - callers have never had a "resolve by either ID space" contract here,
/// so this fix does not invent one. Every such lookup and mutation is
/// instead scoped by direct ownership via [_ownedRunByLocalId] (reads) and
/// [_writeOwnedRun]/[_deleteOwnedRun] (writes/deletes): the row is resolved
/// AND verified to belong to `context.epochToken.userId` before anything
/// about it is returned or changed. A foreign or missing target is always
/// indistinguishable - the existing not-found convention (`null` return or
/// `Exception('Run session not found')`, matching each method's contract
/// from before this fix) never reveals whether a foreign row exists.
///
/// [LocalGpsPoint] route points are `@embedded` inside [LocalRunSession],
/// not a separate Isar collection, so they have no independent ownership
/// path to resolve or an orphan-child risk to guard against - they always
/// travel with, and are only ever reachable through, their owning
/// [LocalRunSession] row.
///
/// ## Transaction/logout race protection
///
/// [_writeOwnedRun] and [_deleteOwnedRun] are the SOLE way this repository
/// touches an existing row, and both apply the same four-checkpoint shape:
/// immediately before entering `writeTxn`, as the FIRST statement inside
/// `writeTxn`, a fresh re-read of the row (never the possibly-stale
/// reference a caller already resolved) with a repeated ownership check
/// immediately inside that same `writeTxn`, and once more by the caller
/// immediately after the transaction returns, before scheduling any
/// detached background work from the result. This guarantees a logout
/// landing anywhere in that window - including while Isar's write lock is
/// being awaited, and including a since-reused local ID after
/// `LocalDatabaseService.clearAll()` has already run - never lets a write
/// land against a foreign/replaced row, and never resurrects or overwrites
/// a since-cleared user's data. This is intentionally a single centralized
/// pair of helpers rather than SessionRepository's hand-copied checkpoints
/// per method - every local write in this file (foreground edits and
/// background acknowledgments alike) goes through the exact same path, so
/// there is only one place to get this right. See
/// `beforeWriteTxnForTesting`/`insideWriteTxnForTesting`/
/// `afterWriteTxnForTesting` below for how this is exercised
/// deterministically in tests.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures: for
/// background work they are classified by [_backgroundSync] as neither a
/// success nor an error, never surfaced to the user, and never grounds to
/// mark a row permanently failed or increment a retry counter. Every other
/// exception preserves this repository's existing "log and continue, retry
/// later" behavior.
///
/// ## GPS update conventions
///
/// [updateRoute]/[updateDistance] are called unawaited, fire-and-forget,
/// from a live GPS stream callback in `RunningProvider` for the lifetime of
/// every active run. Both catch every exception internally and resolve
/// their session context and row ownership through the exact same
/// [_writeOwnedRun] path as every other write - a logged-out, stale,
/// missing, or foreign outcome always resolves to a silent no-op, never an
/// unhandled Future rejection. Neither method pushes to the server (no
/// change from before this fix) - see `GoHardAPP/CLAUDE.md`'s definition of
/// done for why that remains a separate, explicitly deferred completeness
/// question.
class RunningRepository {
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;

  // Kept for constructor-shape consistency with this repository's existing
  // ProxyProvider4<LocalDatabaseService, ConnectivityService, AuthService,
  // ApiService, ...> wiring in main.dart. No longer read directly - every
  // userId lookup this repository needs now comes from the captured
  // SessionRequestContext/UserSessionToken instead, per the class doc
  // comment above.
  // ignore: unused_field
  final AuthService _authService;
  final ApiService _apiService;

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

  RunningRepository(
    this._localDb,
    this._connectivity,
    this._authService,
    this._apiService,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  static const String _unauthenticated = 'No authenticated user';
  static const String _notFound = 'Run session not found';

  // ============ Test-only session-race seams ============
  //
  // One hook per checkpoint, mirroring SessionRepository's identical seams.
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
  /// delay - see `running_repository_session_ownership_test.dart`.
  ///
  /// Each call passes its OWN distinct Future, so a test scheduling
  /// multiple overlapping background operations can tell them apart by call
  /// order rather than awaiting the wrong one. Defaults to null in
  /// production - a pure no-op that does not change scheduling, timing, or
  /// error handling.
  @visibleForTesting
  void Function(Future<void> operationSettled)?
  onBackgroundSyncScheduledForTesting;

  /// Schedules [operation] to run detached from the caller. [operation]
  /// must already be bound to a captured [SessionRequestContext]/
  /// [UserSessionToken] - this helper only handles the fire-and-forget
  /// execution and expected-lifecycle-outcome classification, mirroring
  /// SessionRepository's identical helper.
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

  // ============ Session/ownership helpers ============

  /// Resolves [localId] to a [LocalRunSession] owned by [token.userId], or
  /// `null` if it is missing OR belongs to a different user - the two cases
  /// are always indistinguishable to callers, per the class doc comment.
  Future<LocalRunSession?> _ownedRunByLocalId(
    Isar db,
    int localId,
    UserSessionToken token,
  ) async {
    final row = await db.localRunSessions.get(localId);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (row == null || row.userId != token.userId) return null;
    return row;
  }

  /// Applies [mutate] to the row identified by [localId], but only if it is
  /// still owned by [token.userId] at every checkpoint described in the
  /// class doc comment's "Transaction/logout race protection" section.
  /// Returns the freshly mutated+persisted row, or `null` if any checkpoint
  /// rejected the write (foreign/missing row, or the session ended) -
  /// callers convert `null` to their own not-found/unauthenticated
  /// convention. Never operates on a caller-held reference - always
  /// re-reads [localId] fresh, both before and inside the transaction.
  Future<LocalRunSession?> _writeOwnedRun(
    Isar db,
    int localId,
    UserSessionToken token,
    void Function(LocalRunSession row) mutate,
  ) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return null;

    LocalRunSession? result;
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final current = await db.localRunSessions.get(localId);
      if (current == null || current.userId != token.userId) return;

      mutate(current);
      await db.localRunSessions.put(current);
      result = current;
    });

    await _runTestHook(afterWriteTxnForTesting);
    return result;
  }

  /// Same checkpoint shape as [_writeOwnedRun], but deletes the row instead
  /// of mutating it. Returns `true` only if a row owned by [token.userId]
  /// was actually found and deleted.
  Future<bool> _deleteOwnedRun(
    Isar db,
    int localId,
    UserSessionToken token,
  ) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return false;

    var deleted = false;
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final current = await db.localRunSessions.get(localId);
      if (current == null || current.userId != token.userId) return;

      await db.localRunSessions.delete(localId);
      deleted = true;
    });

    await _runTestHook(afterWriteTxnForTesting);
    return deleted;
  }

  // ============ Public operations ============

  /// Get all run sessions for the current user.
  /// Offline-first: returns cached data immediately, syncs in background.
  Future<List<RunSession>> getRunSessions() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      debugPrint('⚠️ No authenticated session, returning empty list');
      return [];
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localRuns =
        await db.localRunSessions
            .filter()
            .userIdEqualTo(token.userId)
            .sortByDateDesc()
            .findAll();
    if (!_sessionEpoch.isCurrent(token)) return [];

    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _syncFromServer(db, context),
        'Runs synced from server',
      );
    }

    return localRuns.map((local) => _localToRunSession(local)).toList();
  }

  /// Get recent run sessions (last N runs).
  Future<List<RunSession>> getRecentRuns({int limit = 5}) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return [];
    final token = context.epochToken;
    final Isar db = _localDb.database;

    if (_connectivity.isOnline) {
      try {
        await _syncFromServer(db, context);
      } on SessionStaleException {
        // Expected lifecycle outcome.
      } on RequestCancelledException {
        // Expected lifecycle outcome.
      } catch (e) {
        debugPrint('Sync error: $e');
      }
      if (!_sessionEpoch.isCurrent(token)) return [];
    }

    final localRuns =
        await db.localRunSessions
            .filter()
            .userIdEqualTo(token.userId)
            .statusEqualTo('completed')
            .sortByDateDesc()
            .limit(limit)
            .findAll();
    if (!_sessionEpoch.isCurrent(token)) return [];

    return localRuns.map((local) => _localToRunSession(local)).toList();
  }

  /// Get run sessions for this week.
  Future<List<RunSession>> getThisWeekRuns() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return [];
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final now = DateTime.now().toUtc();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime.utc(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );

    final localRuns =
        await db.localRunSessions
            .filter()
            .userIdEqualTo(token.userId)
            .statusEqualTo('completed')
            .dateGreaterThan(weekStartDate.subtract(const Duration(seconds: 1)))
            .findAll();
    if (!_sessionEpoch.isCurrent(token)) return [];

    return localRuns.map((local) => _localToRunSession(local)).toList();
  }

  /// Get a single run session by ID. Returns `null` if it is missing or
  /// belongs to a different user - the two are always indistinguishable.
  Future<RunSession?> getRunSession(int localId) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return null;
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localRun = await _ownedRunByLocalId(db, localId, token);
    if (localRun == null) return null;
    return _localToRunSession(localRun);
  }

  /// Create a new run session, always owned by the captured user.
  Future<RunSession> createRunSession() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localRun = LocalRunSession.create(
      userId: token.userId,
      date: DateTime.now().toUtc(),
      status: 'draft',
      lastModifiedLocal: DateTime.now().toUtc(),
    );

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      await db.localRunSessions.put(localRun);
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    if (_connectivity.isOnline) {
      final stableLocalId = localRun.localId;
      _backgroundSync(
        () => _syncRunToServer(db, stableLocalId, context),
        'Created run on server',
      );
    }

    debugPrint('🏃 Created new run session: ${localRun.localId}');
    return _localToRunSession(localRun);
  }

  /// Start a run (update status to in_progress).
  Future<RunSession> startRun(int localId) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;
    final now = DateTime.now().toUtc();

    final updated = await _writeOwnedRun(db, localId, token, (row) {
      row.status = 'in_progress';
      row.startedAt = now;
      row.lastModifiedLocal = now;
      row.syncStatus = 'pending_update';
      row.isSynced = false;
    });

    if (updated == null || !_sessionEpoch.isCurrent(token)) {
      throw Exception(_notFound);
    }

    if (_connectivity.isOnline) {
      final stableLocalId = updated.localId;
      _backgroundSync(
        () => _syncRunToServer(db, stableLocalId, context),
        'Run start synced to server',
      );
    }

    debugPrint('🏃 Run started: ${updated.localId}');
    return _localToRunSession(updated);
  }

  /// Pause a run. Does not push to the server on its own - see the class
  /// doc comment's "GPS update conventions" section for why that remains
  /// out of scope for this fix.
  Future<RunSession> pauseRun(int localId, DateTime pausedAt) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final updated = await _writeOwnedRun(db, localId, token, (row) {
      row.pausedAt = pausedAt;
      row.lastModifiedLocal = DateTime.now().toUtc();
      row.syncStatus = 'pending_update';
      row.isSynced = false;
    });

    if (updated == null || !_sessionEpoch.isCurrent(token)) {
      throw Exception(_notFound);
    }

    debugPrint('⏸️ Run paused: ${updated.localId}');
    return _localToRunSession(updated);
  }

  /// Resume a run. Does not push to the server on its own (see [pauseRun]).
  Future<RunSession> resumeRun(int localId, DateTime newStartedAt) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final updated = await _writeOwnedRun(db, localId, token, (row) {
      row.startedAt = newStartedAt;
      row.pausedAt = null;
      row.lastModifiedLocal = DateTime.now().toUtc();
      row.syncStatus = 'pending_update';
      row.isSynced = false;
    });

    if (updated == null || !_sessionEpoch.isCurrent(token)) {
      throw Exception(_notFound);
    }

    debugPrint('▶️ Run resumed: ${updated.localId}');
    return _localToRunSession(updated);
  }

  /// Complete a run.
  Future<RunSession> completeRun(
    int localId, {
    required int duration,
    required double distance,
    double? averagePace,
    int? calories,
    List<GpsPoint>? route,
  }) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;
    final now = DateTime.now().toUtc();

    final localRoute =
        route
            ?.map(
              (gp) => LocalGpsPoint.create(
                latitude: gp.latitude,
                longitude: gp.longitude,
                altitude: gp.altitude,
                timestamp: gp.timestamp,
                speed: gp.speed,
                accuracy: gp.accuracy,
              ),
            )
            .toList();

    final updated = await _writeOwnedRun(db, localId, token, (row) {
      row.status = 'completed';
      row.completedAt = now;
      row.duration = duration;
      row.distance = distance;
      row.averagePace = averagePace;
      row.calories = calories;
      row.pausedAt = null;
      row.lastModifiedLocal = now;
      row.syncStatus = 'pending_update';
      row.isSynced = false;
      if (localRoute != null) {
        row.route = localRoute;
      }
    });

    if (updated == null || !_sessionEpoch.isCurrent(token)) {
      throw Exception(_notFound);
    }

    if (_connectivity.isOnline) {
      final stableLocalId = updated.localId;
      _backgroundSync(
        () => _syncRunToServer(db, stableLocalId, context),
        'Completed run synced to server',
      );
    }

    debugPrint(
      '🏁 Run completed: ${updated.localId} - ${distance.toStringAsFixed(2)} km in ${duration}s',
    );
    return _localToRunSession(updated);
  }

  /// Update GPS route during a run. Called unawaited from a live GPS
  /// callback - see the class doc comment's "GPS update conventions"
  /// section. Always resolves to a silent no-op rather than an unhandled
  /// Future rejection.
  Future<void> updateRoute(int localId, List<GpsPoint> route) async {
    try {
      final context = await _sessionCoordinator.captureContext();
      if (context == null) return;
      final token = context.epochToken;
      final Isar db = _localDb.database;

      final localRoute =
          route
              .map(
                (gp) => LocalGpsPoint.create(
                  latitude: gp.latitude,
                  longitude: gp.longitude,
                  altitude: gp.altitude,
                  timestamp: gp.timestamp,
                  speed: gp.speed,
                  accuracy: gp.accuracy,
                ),
              )
              .toList();

      await _writeOwnedRun(db, localId, token, (row) {
        row.route = localRoute;
        row.lastModifiedLocal = DateTime.now().toUtc();
      });
    } catch (e) {
      debugPrint('Failed to update route: $e');
    }
  }

  /// Update distance during a run. Same conventions as [updateRoute].
  Future<void> updateDistance(int localId, double distance) async {
    try {
      final context = await _sessionCoordinator.captureContext();
      if (context == null) return;
      final token = context.epochToken;
      final Isar db = _localDb.database;

      await _writeOwnedRun(db, localId, token, (row) {
        row.distance = distance;
        row.lastModifiedLocal = DateTime.now().toUtc();
      });
    } catch (e) {
      debugPrint('Failed to update distance: $e');
    }
  }

  /// Delete a run session. Returns `true` only if an owned row was actually
  /// deleted - a foreign or already-missing target safely no-ops and
  /// returns `false`, never deleting another user's row.
  Future<bool> deleteRun(int localId) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return false;
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localRun = await _ownedRunByLocalId(db, localId, token);
    if (localRun == null) return false;

    if (localRun.serverId != null && _connectivity.isOnline) {
      try {
        await _apiService.delete(
          ApiConfig.runSessionById(localRun.serverId!),
          sessionContext: context,
        );
      } on SessionStaleException {
        // Expected lifecycle outcome - fall through to the local delete
        // attempt below, which will itself no-op via the epoch check if
        // the session is genuinely stale by then.
      } on RequestCancelledException {
        // Same as above.
      } catch (e) {
        debugPrint('Failed to delete run from server: $e');
      }
    }

    if (!_sessionEpoch.isCurrent(token)) return false;

    final deleted = await _deleteOwnedRun(db, localId, token);
    if (deleted) {
      debugPrint('🗑️ Run deleted: $localId');
    }
    return deleted;
  }

  /// Calculate weekly stats.
  Future<Map<String, dynamic>> getWeeklyStats() async {
    final runs = await getThisWeekRuns();

    double totalDistance = 0;
    int totalDuration = 0;

    for (final run in runs) {
      totalDistance += run.distance ?? 0;
      totalDuration += run.duration ?? 0;
    }

    return {
      'runCount': runs.length,
      'totalDistance': totalDistance,
      'totalDuration': totalDuration,
    };
  }

  /// Background sync: fetch runs from server and update cache. Bound to
  /// [context]: the HTTP call carries its pinned JWT, and every cache write
  /// is gated behind the class doc comment's checkpoint shape plus a direct
  /// [LocalRunSession.userId] ownership check.
  Future<void> _syncFromServer(Isar db, SessionRequestContext context) async {
    final token = context.epochToken;

    final response = await _dispatchBackgroundHttp(
      () => _apiService.get<List<dynamic>>(
        ApiConfig.runSessions,
        sessionContext: context,
      ),
    );

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final currentUserId = token.userId;
    final serverRuns = response;

    // Checkpoint: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      // Checkpoint: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(token)) return;

      for (final serverRunJson in serverRuns) {
        final serverRun = serverRunJson as Map<String, dynamic>;
        final serverId = serverRun['id'] as int;

        final existingLocal =
            await db.localRunSessions
                .filter()
                .serverIdEqualTo(serverId)
                .findFirst();

        // Never overwrite a row that no longer belongs to the current
        // user - a serverId collision (or a foreign row somehow sharing
        // it) must never be silently claimed by this refresh.
        if (existingLocal != null && existingLocal.userId != currentUserId) {
          debugPrint(
            '  ⏭️ Skipping run $serverId - local row owned by a different user',
          );
          continue;
        }

        if (existingLocal != null) {
          _updateLocalFromServer(existingLocal, serverRun);
          await db.localRunSessions.put(existingLocal);
        } else {
          final newLocal = _serverToLocal(serverRun, currentUserId);
          await db.localRunSessions.put(newLocal);
        }
      }
    });

    debugPrint('🔄 Synced ${serverRuns.length} runs from server');
  }

  /// Background sync: sync a local run (create or update) to the server.
  /// Bound to [context]: the HTTP call carries its pinned JWT, and the
  /// resulting acknowledgment is gated behind the class doc comment's
  /// checkpoint shape plus a re-resolution of the target row by its stable
  /// local identity and direct ownership - never a mutation of a
  /// closure-captured object.
  Future<void> _syncRunToServer(
    Isar db,
    int localId,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    // Snapshot the fields to send from the currently-owned row before
    // dispatching, so nothing downstream ever mutates the row this
    // snapshot was taken from.
    final source = await _ownedRunByLocalId(db, localId, token);
    if (source == null) return;

    final isCreate = source.serverId == null;

    final routeJson =
        source.route.isNotEmpty
            ? jsonEncode(
              source.route
                  .map(
                    (p) => {
                      'latitude': p.latitude,
                      'longitude': p.longitude,
                      'altitude': p.altitude,
                      'timestamp': p.timestamp?.toIso8601String(),
                      'speed': p.speed,
                      'accuracy': p.accuracy,
                    },
                  )
                  .toList(),
            )
            : null;

    final data = {
      'userId': source.userId,
      'name': source.name,
      'date': source.date.toIso8601String(),
      'distance': source.distance,
      'duration': source.duration,
      'averagePace': source.averagePace,
      'calories': source.calories,
      'status': source.status,
      'startedAt': source.startedAt?.toIso8601String(),
      'completedAt': source.completedAt?.toIso8601String(),
      'pausedAt': source.pausedAt?.toIso8601String(),
      'routeJson': routeJson,
    };

    int? newServerId;
    if (isCreate) {
      final response = await _dispatchBackgroundHttp(
        () => _apiService.post(
          ApiConfig.runSessions,
          data: data,
          sessionContext: context,
        ),
      );
      if (response == null) return;
      newServerId = response['id'] as int;
    } else {
      await _dispatchBackgroundHttp(
        () => _apiService.put(
          ApiConfig.runSessionById(source.serverId!),
          data: {'id': source.serverId, ...data},
          sessionContext: context,
        ),
      );
    }

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    // Re-resolve by stable local identity and direct ownership, and only
    // then acknowledge - never touch [source] again.
    final updated = await _writeOwnedRun(db, localId, token, (row) {
      if (newServerId != null) {
        row.serverId = newServerId;
      }
      row.isSynced = true;
      row.syncStatus = 'synced';
    });

    if (updated != null) {
      debugPrint(
        isCreate
            ? '✅ Run synced to server with id: ${updated.serverId}'
            : '✅ Run updated on server: ${updated.serverId}',
      );
    }
  }

  /// Convert server JSON to LocalRunSession, always owned by [userId]
  /// regardless of what the server payload's own `userId` field says.
  LocalRunSession _serverToLocal(Map<String, dynamic> json, int userId) {
    List<LocalGpsPoint> route = [];
    if (json['routeJson'] != null && json['routeJson'].toString().isNotEmpty) {
      try {
        final routeList = jsonDecode(json['routeJson']) as List<dynamic>;
        route =
            routeList
                .map(
                  (p) => LocalGpsPoint.create(
                    latitude: (p['latitude'] as num).toDouble(),
                    longitude: (p['longitude'] as num).toDouble(),
                    altitude:
                        p['altitude'] != null
                            ? (p['altitude'] as num).toDouble()
                            : null,
                    timestamp:
                        p['timestamp'] != null
                            ? DateTime.parse(p['timestamp'])
                            : null,
                    speed:
                        p['speed'] != null
                            ? (p['speed'] as num).toDouble()
                            : null,
                    accuracy:
                        p['accuracy'] != null
                            ? (p['accuracy'] as num).toDouble()
                            : null,
                  ),
                )
                .toList();
      } catch (e) {
        debugPrint('Error parsing route JSON: $e');
      }
    }

    return LocalRunSession.create(
      serverId: json['id'] as int,
      userId: userId,
      name: json['name'] as String?,
      date: DateTime.parse(json['date']),
      distance:
          json['distance'] != null
              ? (json['distance'] as num).toDouble()
              : null,
      duration: json['duration'] as int?,
      averagePace:
          json['averagePace'] != null
              ? (json['averagePace'] as num).toDouble()
              : null,
      calories: json['calories'] as int?,
      status: json['status'] as String? ?? 'draft',
      startedAt:
          json['startedAt'] != null ? DateTime.parse(json['startedAt']) : null,
      completedAt:
          json['completedAt'] != null
              ? DateTime.parse(json['completedAt'])
              : null,
      pausedAt:
          json['pausedAt'] != null ? DateTime.parse(json['pausedAt']) : null,
      route: route,
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.now().toUtc(),
    );
  }

  /// Update local run from server data. Only updates if local is already
  /// synced (don't overwrite pending changes) - preserved unchanged from
  /// before this fix; the caller is now responsible for the ownership check
  /// this method itself never performed.
  void _updateLocalFromServer(
    LocalRunSession local,
    Map<String, dynamic> json,
  ) {
    if (local.syncStatus != 'synced') return;

    local.name = json['name'] as String?;
    local.date = DateTime.parse(json['date']);
    local.distance =
        json['distance'] != null ? (json['distance'] as num).toDouble() : null;
    local.duration = json['duration'] as int?;
    local.averagePace =
        json['averagePace'] != null
            ? (json['averagePace'] as num).toDouble()
            : null;
    local.calories = json['calories'] as int?;
    local.status = json['status'] as String? ?? 'draft';
    local.startedAt =
        json['startedAt'] != null ? DateTime.parse(json['startedAt']) : null;
    local.completedAt =
        json['completedAt'] != null
            ? DateTime.parse(json['completedAt'])
            : null;
    local.pausedAt =
        json['pausedAt'] != null ? DateTime.parse(json['pausedAt']) : null;

    if (json['routeJson'] != null && json['routeJson'].toString().isNotEmpty) {
      try {
        final routeList = jsonDecode(json['routeJson']) as List<dynamic>;
        local.route =
            routeList
                .map(
                  (p) => LocalGpsPoint.create(
                    latitude: (p['latitude'] as num).toDouble(),
                    longitude: (p['longitude'] as num).toDouble(),
                    altitude:
                        p['altitude'] != null
                            ? (p['altitude'] as num).toDouble()
                            : null,
                    timestamp:
                        p['timestamp'] != null
                            ? DateTime.parse(p['timestamp'])
                            : null,
                    speed:
                        p['speed'] != null
                            ? (p['speed'] as num).toDouble()
                            : null,
                    accuracy:
                        p['accuracy'] != null
                            ? (p['accuracy'] as num).toDouble()
                            : null,
                  ),
                )
                .toList();
      } catch (e) {
        debugPrint('Error parsing route JSON: $e');
      }
    }
  }

  /// Convert LocalRunSession to RunSession.
  RunSession _localToRunSession(LocalRunSession local) {
    return RunSession(
      id: local.localId,
      userId: local.userId,
      name: local.name,
      date: local.date,
      distance: local.distance,
      duration: local.duration,
      averagePace: local.averagePace,
      calories: local.calories,
      status: local.status,
      startedAt: local.startedAt,
      completedAt: local.completedAt,
      pausedAt: local.pausedAt,
      route:
          local.route
              .map(
                (lp) => GpsPoint(
                  latitude: lp.latitude,
                  longitude: lp.longitude,
                  altitude: lp.altitude,
                  timestamp: lp.timestamp ?? DateTime.now(),
                  speed: lp.speed,
                  accuracy: lp.accuracy,
                ),
              )
              .toList(),
    );
  }
}
