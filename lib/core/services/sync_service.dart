import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../data/models/session.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/session_request_context.dart';
import '../../data/services/session_request_exceptions.dart';
import '../../data/services/session_update_sync_helper.dart';
import '../../data/local/services/local_database_service.dart';
import '../../data/local/services/model_mapper.dart';
import '../../data/local/services/local_nutrition_totals_calculator.dart';
import '../../data/local/models/local_session.dart';
import '../../data/local/models/local_exercise.dart';
import '../../data/local/models/local_exercise_set.dart';
import '../../data/local/models/local_program.dart';
import '../../data/local/models/local_goal.dart';
import '../../data/local/models/local_program_workout.dart';
import '../../data/local/models/local_meal_log.dart';
import '../../data/local/models/local_meal_entry.dart';
import '../../data/local/models/local_food_item.dart';
import '../../data/local/models/local_nutrition_goal.dart';
import '../../data/local/models/local_food_template.dart';
import '../../core/constants/api_config.dart';
import 'connectivity_service.dart';
import 'session_request_coordinator.dart';
import 'user_session_epoch.dart';

/// One sync pass's active-operation record: the [UserSessionToken] that
/// owns it and the (already-started) [Future] tracking its completion.
///
/// Compared by OBJECT IDENTITY, never by [token] equality or by comparing
/// generations directly - see [SyncService._activeOperation]'s doc comment
/// for why identity is the only safe way to guard the completion cleanup.
class _ActiveSyncOperation {
  _ActiveSyncOperation(this.token, this.future);

  final UserSessionToken token;
  final Future<void> future;
}

/// Service for automatic background synchronization of offline data.
///
/// ## Operation ownership
///
/// [sync] no longer uses a plain `bool` flag to decide whether a pass is
/// already running. Instead [_activeOperation] records BOTH the
/// [UserSessionToken] that started the current pass AND that pass's own
/// [Future] - installed synchronously (before any `await`) the moment a new
/// pass begins, so two [sync] calls arriving back-to-back for the SAME
/// session can never both start a physical pass: the second one finds
/// [_activeOperation] already installed and simply awaits its `future`
/// instead. A call for a DIFFERENT (newer) session is never blocked by an
/// older session's still-pending transport - it installs its OWN record
/// immediately, discarding the reference to the old one (whatever HTTP work
/// that old pass has in flight keeps running independently until it
/// self-completes or is cancelled by
/// `SessionRequestCoordinator.cancelCurrentGeneration()`, called from
/// `AuthProvider`'s logout pass).
///
/// When a pass finishes (success, error, or abort), its `whenComplete`
/// callback clears [_activeOperation] ONLY if it is STILL the object that
/// installed it - checked via [identical], never via token/generation
/// equality. This is deliberate: token equality would already be safe here
/// too (generations are globally unique - see [UserSessionEpoch]'s own doc
/// comment), but comparing object identity is the more directly-verifiable
/// invariant and is what this class relies on throughout, so a stale
/// operation's own cleanup can never clear a newer session's active record
/// even in a hypothetical future where two records could otherwise compare
/// equal.
///
/// [dispose] deliberately never touches [_activeOperation] - see its own
/// doc comment.
///
/// ## Session-owned sync entry
///
/// Every pass captures exactly ONE [SessionRequestContext] (via
/// [_sessionCoordinator]) and threads it through all eleven phases and
/// every row within them - never rereading [AuthService.getUserId] or
/// [AuthService.getToken] after that single capture. [UserSessionEpoch
/// .isCurrent] is rechecked before the pass starts, between every phase,
/// before every row, immediately after every awaited HTTP call, before
/// every local acknowledgment `writeTxn`, and again as the very first
/// statement inside that `writeTxn` - if any of those checks fails, the
/// pass aborts silently (no row is marked failed, no retry count is
/// incremented) via [SessionStaleException]/[RequestCancelledException],
/// which [_startSyncPass] treats as an expected lifecycle outcome, exactly
/// like `NutritionRepository._runDetachedSync` already does for its own
/// background pushes.
///
/// ## Session-owned scheduling
///
/// [initialize] captures the active [UserSessionToken] synchronously, once,
/// and closes over that SAME token in the periodic timer callback, the
/// connectivity listener, and every debounce timer it schedules - never
/// rereading "whichever session is active" when a callback fires. Each
/// callback rechecks [UserSessionEpoch.isCurrent] against its captured
/// token before doing anything else, so a timer/listener/debounce scheduled
/// under User A silently no-ops if it fires after User B has logged in,
/// rather than adopting B's session. [initialize] does not schedule
/// anything at all if there is no active session when it is called.
///
/// ## Child-entity ownership filtering
///
/// [_syncExercises], [_syncExerciseSets], [_syncProgramWorkouts],
/// [_syncMealEntries], and [_syncFoodItems] resolve each pending row's
/// owning user by walking its parent chain (cached per phase call via a
/// small `Map<int, int?>` keyed by parent local ID, so a phase with many
/// sibling rows under the same parent never re-resolves that parent more
/// than once) and skip - never upload, never mark synced or failed - any
/// row that is orphaned or belongs to a different user than the captured
/// session. The same ownership recheck runs again, by stable local ID,
/// immediately before every acknowledgment write, so a race that replaces
/// or reassigns a row between dispatch and acknowledgment can never let a
/// stale or foreign response land on it.
class SyncService {
  static SyncService? _instance;
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;
  final UserSessionEpoch _sessionEpoch;
  final SessionRequestCoordinator _sessionCoordinator;

  Timer? _periodicSyncTimer;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _debounceTimer;
  bool _isInitialized = false;

  /// The currently-running (or most recently completed and not-yet-cleared)
  /// sync pass, if any. See the class doc comment's "Operation ownership"
  /// section for the full invariants this field and its cleanup uphold.
  _ActiveSyncOperation? _activeOperation;

  // Sync configuration
  static const Duration _syncInterval = Duration(minutes: 5);
  static const int _maxRetries = 3;
  static const Duration _syncDebounce = Duration(seconds: 3);

  /// Private constructor for singleton pattern
  SyncService._(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  /// Factory constructor to create/get singleton instance.
  ///
  /// [authService] is accepted (and still constructed/injected by
  /// `main.dart` exactly as before) for wiring stability, but is not stored
  /// here - every phase now derives its authoritative user ID from the
  /// captured [SessionRequestContext] instead of rereading
  /// [AuthService.getUserId] (see the class doc comment's "Session-owned
  /// sync entry" section). [authService] remains the SAME shared instance
  /// [SessionRequestCoordinator] itself uses internally.
  factory SyncService({
    required ApiService apiService,
    required AuthService authService,
    required LocalDatabaseService localDb,
    required ConnectivityService connectivity,
    required UserSessionEpoch sessionEpoch,
    required SessionRequestCoordinator sessionCoordinator,
  }) {
    _instance ??= SyncService._(
      apiService,
      localDb,
      connectivity,
      sessionEpoch,
      sessionCoordinator,
    );
    return _instance!;
  }

  /// Get singleton instance (must be initialized first)
  static SyncService get instance {
    if (_instance == null) {
      throw Exception(
        'SyncService not initialized. Call factory constructor first.',
      );
    }
    return _instance!;
  }

  /// True while a sync pass owned by the CURRENTLY active session is
  /// running. A still-running pass left over from a PREVIOUS session
  /// (already superseded by logout/relogin) reports `false` here, even
  /// though [_activeOperation] still references it until its own cleanup
  /// runs - callers must only ever see "is my session syncing right now",
  /// never "is anything syncing at all".
  bool get isSyncing {
    final active = _activeOperation;
    if (active == null) return false;
    return _sessionEpoch.isCurrent(active.token);
  }

  /// Initialize sync service. No-ops if already initialized (idempotent -
  /// repeated calls under the same session never create duplicate timers or
  /// listeners) and if there is no active session (nothing is scheduled
  /// while logged out).
  Future<void> initialize() async {
    if (_isInitialized) return;

    final token = _sessionEpoch.capture();
    if (token == null) {
      debugPrint(
        '📴 SyncService.initialize() called with no active session - not scheduling',
      );
      return;
    }

    // Every callback below closes over this SAME `token` value, captured
    // synchronously right here - never re-reads "whichever session is
    // active" at fire time. See the class doc comment's "Session-owned
    // scheduling" section.
    _connectivitySubscription = _connectivity.connectivityStream.listen((
      isOnline,
    ) {
      if (isOnline) {
        debugPrint('🔄 Network connected - scheduling sync');
        _scheduleDebouncedSync(token);
      } else {
        debugPrint('📴 Network disconnected - canceling sync');
        _cancelDebouncedSync();
      }
    });

    _periodicSyncTimer = Timer.periodic(_syncInterval, (_) {
      debugPrint('⏰ Periodic sync triggered');
      unawaited(_runScheduledSync(token, 'periodic'));
    });

    _isInitialized = true;
    debugPrint('✅ SyncService initialized');

    // Run initial sync if online
    if (_connectivity.isOnline) {
      _scheduleDebouncedSync(token);
    }
  }

  /// Schedule a debounced sync bound to [token] (prevents rapid sync
  /// attempts during network flapping). Replacing a pending debounce always
  /// reschedules with the SAME token this [SyncService] was initialized
  /// with for its current session, so "the newest scheduled event" can
  /// never end up bound to a different session than the one before it.
  void _scheduleDebouncedSync(UserSessionToken token) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_syncDebounce, () {
      unawaited(_runScheduledSync(token, 'debounced'));
    });
  }

  /// Cancel pending debounced sync
  void _cancelDebouncedSync() {
    _debounceTimer?.cancel();
  }

  /// Common guard for every scheduled (non-manual) trigger: reject before
  /// even considering connectivity if [scheduledToken] - captured at
  /// scheduling time by [initialize] - is no longer the current session.
  Future<void> _runScheduledSync(
    UserSessionToken scheduledToken,
    String source,
  ) async {
    if (!_sessionEpoch.isCurrent(scheduledToken)) {
      debugPrint(
        '⏭️ Scheduled sync ($source) belongs to a superseded session - skipping',
      );
      return;
    }
    if (!_connectivity.isOnline) return;
    await sync();
  }

  /// Manually trigger sync (public API). Unlike the scheduled triggers
  /// above, this captures whichever session is active AT THE MOMENT IT IS
  /// CALLED - there is no earlier "scheduling time" for a direct call.
  Future<void> sync() async {
    final token = _sessionEpoch.capture();
    if (token == null) {
      debugPrint('📴 Not authenticated, skipping sync');
      return;
    }

    final existing = _activeOperation;
    if (existing != null && existing.token == token) {
      debugPrint('⏭️ Sync already in progress for this session, awaiting it');
      return existing.future;
    }

    if (!_connectivity.isOnline) {
      debugPrint('📴 Offline, skipping sync');
      return;
    }

    debugPrint('🔄 Starting sync...');
    late final _ActiveSyncOperation operation;
    final future = _startSyncPass(token).whenComplete(() {
      // Only clear this SPECIFIC operation record - see the class doc
      // comment's "Operation ownership" section for why identity, not
      // token/generation equality, is what guards this.
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
      }
    });
    operation = _ActiveSyncOperation(token, future);
    _activeOperation = operation;
    return future;
  }

  /// Captures the full [SessionRequestContext] for [token] and, if it is
  /// still valid, runs the full eleven-phase pass. Every expected
  /// lifecycle-termination outcome (logged out before the context capture
  /// resolves, session ended mid-pass) is swallowed here - never surfaced
  /// as an error, never leaves anything marked failed.
  Future<void> _startSyncPass(UserSessionToken token) async {
    try {
      final context = await _sessionCoordinator.captureContext();
      if (context == null || context.epochToken != token) {
        debugPrint(
          '⏭️ Sync aborted before starting - session no longer current',
        );
        return;
      }
      await _runSyncPhases(context);
    } on SessionStaleException {
      debugPrint('⏭️ Sync aborted - session ended');
    } on RequestCancelledException {
      debugPrint('⏭️ Sync aborted - request cancelled (session ended)');
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
    }
  }

  /// Throws [SessionStaleException] if [context]'s session is no longer
  /// current. Used as the "before starting / between every phase / before
  /// every row" checkpoint throughout this file - always allowed to
  /// propagate up to [_startSyncPass]'s catch clause, which is the single
  /// place that classifies it as an expected, silent abort.
  void _assertCurrent(SessionRequestContext context) {
    if (!_sessionEpoch.isCurrent(context.epochToken)) {
      throw const SessionStaleException();
    }
  }

  bool _isCurrent(SessionRequestContext context) =>
      _sessionEpoch.isCurrent(context.epochToken);

  // ============ Test-only acknowledgment-race seams ============
  //
  // Two hooks, one per checkpoint, let a test deterministically land a
  // session invalidation at each of the two points every acknowledging
  // `writeTxn` below re-checks `UserSessionEpoch.isCurrent` around: the
  // pre-writeTxn checkpoint (`beforeAckWriteTxnForTesting`) and the
  // first-statement-inside-writeTxn checkpoint
  // (`insideAckWriteTxnForTesting`) - mirroring the analogous hooks on
  // `NutritionRepository`. Both default to null in production; setting
  // them never affects production control flow or performance.
  @visibleForTesting
  Future<void> Function()? beforeAckWriteTxnForTesting;

  @visibleForTesting
  Future<void> Function()? insideAckWriteTxnForTesting;

  /// Test-only seam: awaited immediately before EVERY between-phase (and
  /// pass-start) epoch check in [_runSyncPhases], regardless of whether any
  /// row in the phase just completed needed one itself - lets a test land
  /// an invalidation at that exact boundary even when the phase(s)
  /// involved have no pending rows of their own (so none of the per-row/
  /// per-HTTP checkpoints inside them would otherwise have an opportunity
  /// to run at all).
  @visibleForTesting
  Future<void> Function()? beforePhaseCheckForTesting;

  Future<void> _runTestHook(Future<void> Function()? hook) async {
    if (hook != null) {
      await hook();
    }
  }

  Future<void> _runSyncPhases(SessionRequestContext context) async {
    final db = _localDb.database;

    // Sync in order: Sessions → Exercises → Sets → Programs → Goals →
    // ProgramWorkouts → NutritionGoals → FoodTemplates → MealLogs →
    // MealEntries → FoodItems. An epoch recheck gates the START of every
    // phase, including the first - "before starting" and "between every
    // phase" are the same check applied uniformly here.
    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncSessions(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncExercises(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncExerciseSets(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncPrograms(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncGoals(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncProgramWorkouts(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncNutritionGoals(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncFoodTemplates(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncMealLogs(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncMealEntries(db, context);

    await _runTestHook(beforePhaseCheckForTesting);
    _assertCurrent(context);
    await _syncFoodItems(db, context);

    debugPrint('✅ Sync completed successfully');
  }

  /// A real (positive) server id, or `null` for "no server identity" - `null`,
  /// `0` (the legacy pre-public-id-namespace sentinel written by app versions
  /// before `ModelMapper.publicRowId`), or any non-positive value.
  ///
  /// Used ONLY in the exercise / exercise-set sync phases below: a legacy row
  /// persisted with `serverId == 0` must be treated exactly like a
  /// never-synced (`serverId == null`) row - a `pending_update` becomes an
  /// initial CREATE carrying its latest state, a `pending_delete` is removed
  /// locally with no server call, and a non-positive id is never placed in a
  /// route or a server-identity request field. `ExerciseRepository`
  /// additionally canonicalizes `serverId <= 0` to `null` whenever it writes
  /// such a row, so this is defense in depth, not the only guard.
  static int? _positiveServerId(int? id) => (id != null && id > 0) ? id : null;

  // ============ Parent-chain ownership resolvers (cached) ============
  //
  // Each resolver takes a per-phase-call cache Map so a phase with many
  // sibling rows under the same parent (many exercises in one session, many
  // sets under one exercise, ...) never re-fetches that parent more than
  // once - bounded, cheap single-row `.get()` lookups, never a full
  // collection scan.

  Future<int?> _sessionOwner(
    Isar db,
    int sessionLocalId,
    Map<int, int?> cache,
  ) async {
    if (cache.containsKey(sessionLocalId)) return cache[sessionLocalId];
    final session = await db.localSessions.get(sessionLocalId);
    final owner = session?.userId;
    cache[sessionLocalId] = owner;
    return owner;
  }

  Future<int?> _exerciseOwner(
    Isar db,
    int exerciseLocalId,
    Map<int, int?> sessionCache,
    Map<int, int?> exerciseCache,
  ) async {
    if (exerciseCache.containsKey(exerciseLocalId)) {
      return exerciseCache[exerciseLocalId];
    }
    final exercise = await db.localExercises.get(exerciseLocalId);
    final owner =
        exercise == null
            ? null
            : await _sessionOwner(db, exercise.sessionLocalId, sessionCache);
    exerciseCache[exerciseLocalId] = owner;
    return owner;
  }

  Future<int?> _programOwner(
    Isar db,
    int programLocalId,
    Map<int, int?> cache,
  ) async {
    if (cache.containsKey(programLocalId)) return cache[programLocalId];
    final program = await db.localPrograms.get(programLocalId);
    final owner = program?.userId;
    cache[programLocalId] = owner;
    return owner;
  }

  Future<int?> _mealLogOwner(
    Isar db,
    int mealLogLocalId,
    Map<int, int?> cache,
  ) async {
    if (cache.containsKey(mealLogLocalId)) return cache[mealLogLocalId];
    final log = await db.localMealLogs.get(mealLogLocalId);
    final owner = log?.userId;
    cache[mealLogLocalId] = owner;
    return owner;
  }

  Future<int?> _mealEntryOwner(
    Isar db,
    int mealEntryLocalId,
    Map<int, int?> mealLogCache,
    Map<int, int?> mealEntryCache,
  ) async {
    if (mealEntryCache.containsKey(mealEntryLocalId)) {
      return mealEntryCache[mealEntryLocalId];
    }
    final entry = await db.localMealEntrys.get(mealEntryLocalId);
    final owner =
        entry == null
            ? null
            : await _mealLogOwner(db, entry.mealLogLocalId, mealLogCache);
    mealEntryCache[mealEntryLocalId] = owner;
    return owner;
  }

  // ========== Session Sync Methods ==========

  /// Sync all pending sessions
  Future<void> _syncSessions(Isar db, SessionRequestContext context) async {
    final userId = context.epochToken.userId;

    // Safely bring rows created before version tracking existed up to date
    // before running the normal pending-item sync below.
    await _reconcileUpgradedSessionVersions(db, context);
    _assertCurrent(context);

    // Only sync sessions belonging to current user. Conflict rows are
    // explicitly excluded here (not just via the switch's default branch)
    // so they can never enter the automatic retry loop - they stay stored
    // and queryable for the future resolution UI.
    final pendingSessions =
        await db.localSessions
            .filter()
            .isSyncedEqualTo(false)
            .userIdEqualTo(userId)
            .not()
            .syncStatusEqualTo('conflict')
            .findAll();

    if (pendingSessions.isEmpty) {
      debugPrint('  No pending sessions to sync');
      return;
    }

    debugPrint('  Syncing ${pendingSessions.length} sessions...');

    for (final session in pendingSessions) {
      _assertCurrent(context);
      try {
        switch (session.syncStatus) {
          case 'pending_create':
            await _syncCreateSession(db, session, context);
            break;
          case 'pending_update':
            await _syncUpdateSession(db, session, context);
            break;
          case 'pending_delete':
            await _syncDeleteSession(db, session, context);
            break;
          default:
            debugPrint('  Unknown sync status: ${session.syncStatus}');
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        await _markSyncError(db, session, e.toString(), context);
      }
    }
  }

  Future<LocalSession?> _reacquireOwnedSession(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localSessions.get(localId);
    if (row == null || row.userId != userId) return null;
    return row;
  }

  /// Sync a session that needs to be created on the server
  Future<void> _syncCreateSession(
    Isar db,
    LocalSession localSession,
    SessionRequestContext context,
  ) async {
    debugPrint('  Creating session ${localSession.localId} on server...');

    // localSession here is a fresh Isar read, so its DateTime fields are
    // local-flagged but instant-correct (see
    // model_mapper_isar_roundtrip_test.dart). Route through the
    // already-corrected ModelMapper.localToSession() + Session.toJson()
    // pipeline (which calls .toUtc() via toUtcTimestamp(), and formats
    // via DateTimeHelper) instead of calling .toIso8601String() directly
    // on those fields, which would silently drop the 'Z' suffix and the
    // correct instant. id/exercises/version/programId/programWorkoutId are
    // stripped to preserve the exact request shape this endpoint expected
    // before this fix - only the timestamp/date values change.
    final sessionJson =
        ModelMapper.localToSession(localSession).toJson()
          ..remove('id')
          ..remove('exercises')
          ..remove('version')
          ..remove('programId')
          ..remove('programWorkoutId');

    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.sessions,
      data: sessionJson,
      sessionContext: context,
    );
    _assertCurrent(context);
    final apiSession = Session.fromJson(response);

    final target = await _reacquireOwnedSession(
      db,
      localSession.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    // Persist the full authoritative response (including the
    // server-assigned version) rather than inventing one.
    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await _reacquireOwnedSession(
        db,
        localSession.localId,
        context.epochToken.userId,
      );
      if (reFetched == null) return;
      final updated = ModelMapper.sessionToLocal(
        apiSession,
        localId: localSession.localId,
        isSynced: true,
      );
      await db.localSessions.put(updated);
    });

    debugPrint('  ✅ Session created with server ID: ${apiSession.id}');
  }

  /// Sync a session that needs to be updated on the server
  Future<void> _syncUpdateSession(
    Isar db,
    LocalSession localSession,
    SessionRequestContext context,
  ) async {
    if (localSession.serverId == null) {
      debugPrint(
        '  ⚠️ Session has pending_update but no serverId - converting to pending_create',
      );
      final target = await _reacquireOwnedSession(
        db,
        localSession.localId,
        context.epochToken.userId,
      );
      _assertCurrent(context);
      if (target == null) return;
      // Fix invalid state: convert to pending_create
      await db.writeTxn(() async {
        _assertCurrent(context);
        final reFetched = await _reacquireOwnedSession(
          db,
          localSession.localId,
          context.epochToken.userId,
        );
        if (reFetched == null) return;
        reFetched.syncStatus = 'pending_create';
        await db.localSessions.put(reFetched);
      });
      _assertCurrent(context);
      // Now sync as create
      await _syncCreateSession(db, localSession, context);
      return;
    }

    debugPrint('  Updating session ${localSession.serverId} on server...');

    final userId = context.epochToken.userId;
    final outcome = await SessionUpdateSyncHelper(_apiService).pushUpdate(
      db,
      localSession,
      sessionContext: context,
      isSessionCurrent: () => _isCurrent(context),
      scopeUserId: userId,
    );

    switch (outcome) {
      case SessionSyncOutcome.synced:
        debugPrint('  ✅ Session updated on server');
        break;
      case SessionSyncOutcome.conflict:
        debugPrint('  ⚠️ Conflict detected - stored for manual resolution');
        break;
      case SessionSyncOutcome.conflictDataInvalid:
        debugPrint('  ⚠️ Conflict response malformed - will retry later');
        break;
      case SessionSyncOutcome.deferred:
        debugPrint(
          '  ⚠️ Update result could not be confirmed - will retry later',
        );
        break;
    }
  }

  /// Safely reconcile sessions synced before version tracking existed
  /// (serverId set, version still null) so they never trigger a blind PUT
  /// with a guessed version.
  ///
  /// - Clean rows ('synced'): hydrated read-only from the server.
  /// - Rows with a pending local edit ('pending_update'): the server is
  ///   snapshotted read-only and the row is marked 'conflict' - local
  ///   mutable fields are never touched or overwritten.
  /// - 'pending_delete' and 'pending_create' rows need no action here and
  ///   are left untouched; their existing sync paths handle them.
  ///
  /// Any GET failure leaves the original row and sync status untouched for
  /// a later retry - it never manufactures a resolved conflict.
  Future<void> _reconcileUpgradedSessionVersions(
    Isar db,
    SessionRequestContext context,
  ) async {
    final userId = context.epochToken.userId;

    final cleanUnversioned =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .versionIsNull()
            .serverIdIsNotNull()
            .syncStatusEqualTo('synced')
            .findAll();

    for (final session in cleanUnversioned) {
      _assertCurrent(context);
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.sessionById(session.serverId!),
          sessionContext: context,
        );
        _assertCurrent(context);
        final serverSession = Session.fromJson(data);

        final target = await _reacquireOwnedSession(
          db,
          session.localId,
          userId,
        );
        _assertCurrent(context);
        if (target == null) continue;

        await db.writeTxn(() async {
          _assertCurrent(context);
          final reFetched = await _reacquireOwnedSession(
            db,
            session.localId,
            userId,
          );
          if (reFetched == null) return;
          final refreshed = ModelMapper.sessionToLocal(
            serverSession,
            localId: session.localId,
            isSynced: true,
          );
          await db.localSessions.put(refreshed);
        });
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint(
          '  ⚠️ Could not refresh version for clean session ${session.serverId}, will retry later: $e',
        );
      }
    }

    final pendingUnversioned =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .versionIsNull()
            .serverIdIsNotNull()
            .syncStatusEqualTo('pending_update')
            .findAll();

    for (final session in pendingUnversioned) {
      _assertCurrent(context);
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.sessionById(session.serverId!),
          sessionContext: context,
        );
        _assertCurrent(context);

        final target = await _reacquireOwnedSession(
          db,
          session.localId,
          userId,
        );
        _assertCurrent(context);
        if (target == null) continue;

        await db.writeTxn(() async {
          _assertCurrent(context);
          final reFetched = await _reacquireOwnedSession(
            db,
            session.localId,
            userId,
          );
          if (reFetched == null) return;
          reFetched.conflictServerSnapshotJson = jsonEncode(data);
          reFetched.conflictServerVersion = data['version'] as int?;
          reFetched.conflictDetectedAt = DateTime.now().toUtc();
          reFetched.syncStatus = 'conflict';
          await db.localSessions.put(reFetched);
        });
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint(
          '  ⚠️ Could not reconcile pending session ${session.serverId}, will retry later: $e',
        );
      }
    }
  }

  /// Sync a session that needs to be deleted from the server
  Future<void> _syncDeleteSession(
    Isar db,
    LocalSession localSession,
    SessionRequestContext context,
  ) async {
    if (localSession.serverId == null) {
      // Never synced to server - just delete locally (with related data)
      await _deleteSessionAndRelatedData(db, localSession, context);
      debugPrint('  ✅ Local-only session deleted');
      return;
    }

    debugPrint('  Deleting session ${localSession.serverId} from server...');

    // DELETE from server
    await _apiService.delete(
      ApiConfig.sessionById(localSession.serverId!),
      sessionContext: context,
    );
    _assertCurrent(context);

    // Delete from local database (including exercises and sets)
    await _deleteSessionAndRelatedData(db, localSession, context);

    debugPrint('  ✅ Session deleted from server and locally');
  }

  /// Delete session and all related exercises and sets. Re-verifies both
  /// the epoch and the session's ownership immediately before, and as the
  /// first statement inside, the deleting `writeTxn` - a stale delete
  /// acknowledgment must never remove a foreign or already-replaced row.
  Future<void> _deleteSessionAndRelatedData(
    Isar db,
    LocalSession localSession,
    SessionRequestContext context,
  ) async {
    final target = await _reacquireOwnedSession(
      db,
      localSession.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await _reacquireOwnedSession(
        db,
        localSession.localId,
        context.epochToken.userId,
      );
      if (reFetched == null) return;

      // Delete all exercises for this session
      final exercises =
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(reFetched.localId)
              .findAll();

      for (final exercise in exercises) {
        // Delete all sets for this exercise
        await db.localExerciseSets
            .filter()
            .exerciseLocalIdEqualTo(exercise.localId)
            .deleteAll();
      }

      // Delete all exercises
      await db.localExercises
          .filter()
          .sessionLocalIdEqualTo(reFetched.localId)
          .deleteAll();

      // Delete the session
      await db.localSessions.delete(reFetched.localId);
    });
  }

  /// Mark sync error with exponential backoff. Only writes if the context
  /// is still current AND the row still belongs to the captured user -
  /// ordinary errors get the same acknowledgment-safety treatment as
  /// success does.
  Future<void> _markSyncError(
    Isar db,
    LocalSession session,
    String error,
    SessionRequestContext context,
  ) async {
    if (!_isCurrent(context)) return;
    final target = await _reacquireOwnedSession(
      db,
      session.localId,
      context.epochToken.userId,
    );
    if (target == null || !_isCurrent(context)) return;

    await db.writeTxn(() async {
      if (!_isCurrent(context)) return;
      final reFetched = await _reacquireOwnedSession(
        db,
        session.localId,
        context.epochToken.userId,
      );
      if (reFetched == null) return;

      reFetched.syncRetryCount += 1;
      reFetched.syncError = error;
      reFetched.lastSyncAttempt = DateTime.now().toUtc();

      // Don't change syncStatus - keep it as pending_create/update/delete
      // so it can be retried. The syncError and syncRetryCount fields
      // already track the error state.

      if (reFetched.syncRetryCount >= _maxRetries) {
        debugPrint(
          '  ❌ Session ${reFetched.localId} failed after $_maxRetries attempts: $error',
        );
        debugPrint(
          '  Will keep retrying on next sync (status: ${reFetched.syncStatus})',
        );
      } else {
        debugPrint(
          '  ⚠️ Session ${reFetched.localId} sync failed (attempt ${reFetched.syncRetryCount}/$_maxRetries): $error',
        );
      }

      await db.localSessions.put(reFetched);
    });
  }

  // ========== Exercise Sync Methods (child of Session) ==========

  /// Sync all pending exercises owned (via their parent session) by the
  /// captured user. Orphaned rows (parent session missing) and foreign
  /// rows (parent session belongs to a different user) are silently
  /// skipped - never uploaded, never marked synced or failed.
  Future<void> _syncExercises(Isar db, SessionRequestContext context) async {
    final userId = context.epochToken.userId;
    final pendingExercises =
        await db.localExercises.filter().isSyncedEqualTo(false).findAll();

    if (pendingExercises.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingExercises.length} exercises...');

    final sessionCache = <int, int?>{};

    for (final exercise in pendingExercises) {
      _assertCurrent(context);

      final parentSession = await db.localSessions.get(exercise.sessionLocalId);
      if (parentSession == null) {
        debugPrint('    ! Skipping exercise - orphaned (no parent session)');
        continue;
      }
      sessionCache[exercise.sessionLocalId] = parentSession.userId;
      if (parentSession.userId != userId) {
        debugPrint('    ! Skipping exercise - not owned by current user');
        continue;
      }
      if (_positiveServerId(parentSession.serverId) == null) {
        debugPrint('    ! Skipping exercise - parent session not synced yet');
        continue;
      }

      // Update exercise's sessionServerId if not set
      if (exercise.sessionServerId != parentSession.serverId) {
        await db.writeTxn(() async {
          _assertCurrent(context);
          final reFetched = await db.localExercises.get(exercise.localId);
          if (reFetched == null) return;
          reFetched.sessionServerId = parentSession.serverId;
          await db.localExercises.put(reFetched);
        });
        debugPrint(
          '    Updated exercise sessionServerId to ${parentSession.serverId}',
        );
      }

      try {
        switch (exercise.syncStatus) {
          case 'pending_create':
            await _syncCreateExercise(
              db,
              exercise,
              parentSession,
              context,
              sessionCache,
            );
            break;
          case 'pending_update':
            await _syncUpdateExercise(db, exercise, parentSession, context);
            break;
          case 'pending_delete':
            await _syncDeleteExercise(db, exercise, context);
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Exercise sync failed: $e');
      }
    }
  }

  /// Re-fetches [localId] and re-verifies its parent-chain ownership FRESH
  /// from Isar - deliberately using its own throwaway cache rather than the
  /// caller's phase-level one, so this acknowledgment-time recheck can
  /// never be satisfied by a value the earlier pre-filter pass already
  /// cached. A race that reassigns the row's parent (or the parent's
  /// owner) between dispatch and acknowledgment is caught here.
  Future<LocalExercise?> _reacquireOwnedExercise(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localExercises.get(localId);
    if (row == null) return null;
    final owner = await _sessionOwner(db, row.sessionLocalId, <int, int?>{});
    if (owner != userId) return null;
    return row;
  }

  Future<void> _syncCreateExercise(
    Isar db,
    LocalExercise exercise,
    LocalSession parentSession,
    SessionRequestContext context,
    Map<int, int?> sessionCache,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      '${ApiConfig.sessions}/${parentSession.serverId}/exercises',
      data: {
        'name': exercise.name,
        'duration': exercise.duration,
        'restTime': exercise.restTime,
        'notes': exercise.notes,
        'exerciseTemplateId': exercise.exerciseTemplateId,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedExercise(
      db,
      exercise.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localExercises.get(exercise.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.sessionServerId = parentSession.serverId;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      await db.localExercises.put(reFetched);
    });

    debugPrint('    ✅ Created exercise ${exercise.serverId}');
  }

  /// There is no `PUT /exercises/{id}` route on the API. A [LocalExercise] is
  /// only ever created locally - `ModelMapper.exerciseToLocal` emits `synced` or
  /// `pending_create`, and no repository path marks one `pending_update`. The
  /// single case still handled here is a legacy `serverId == 0` row that
  /// predates `ModelMapper.publicRowId`: it carries no server identity, so it is
  /// converted to an initial CREATE against its (already validated) parent
  /// session. A row that holds a real, positive server id has no update route -
  /// it is left pending and untouched rather than dispatched to a 404.
  Future<void> _syncUpdateExercise(
    Isar db,
    LocalExercise exercise,
    LocalSession parentSession,
    SessionRequestContext context,
  ) async {
    if (_positiveServerId(exercise.serverId) != null) {
      return;
    }

    // The caller (`_syncExercises`) has already gated on a positive parent
    // `serverId` and current-user ownership; re-assert defensively before
    // spending a CREATE.
    if (_positiveServerId(parentSession.serverId) != null &&
        parentSession.userId == context.epochToken.userId) {
      await _syncCreateExercise(
        db,
        exercise,
        parentSession,
        context,
        <int, int?>{},
      );
    }
  }

  /// There is no `DELETE /exercises/{id}` route on the API. As with
  /// [_syncUpdateExercise] the only real case is a legacy `serverId == 0` row:
  /// it has nothing on the server, so it is removed locally only - never
  /// `DELETE /exercises/0`. A row with a real, positive server id has no delete
  /// route and is left pending and untouched.
  Future<void> _syncDeleteExercise(
    Isar db,
    LocalExercise exercise,
    SessionRequestContext context,
  ) async {
    if (_positiveServerId(exercise.serverId) != null) {
      return;
    }

    final target = await _reacquireOwnedExercise(
      db,
      exercise.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localExercises.get(exercise.localId);
      if (reFetched == null) return;
      await db.localExercises.delete(reFetched.localId);
    });

    debugPrint('    ✅ Removed legacy unsynced exercise locally');
  }

  // ========== Exercise Set Sync Methods (grandchild of Session) ==========

  /// Sync all pending exercise sets owned (via exercise → session) by the
  /// captured user. Orphaned/foreign rows are silently skipped.
  Future<void> _syncExerciseSets(Isar db, SessionRequestContext context) async {
    final userId = context.epochToken.userId;
    final pendingSets =
        await db.localExerciseSets.filter().isSyncedEqualTo(false).findAll();

    if (pendingSets.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingSets.length} exercise sets...');

    final sessionCache = <int, int?>{};
    final exerciseCache = <int, int?>{};

    for (final set in pendingSets) {
      _assertCurrent(context);

      final parentExercise = await db.localExercises.get(set.exerciseLocalId);
      if (parentExercise == null) {
        debugPrint('    ! Skipping set - orphaned (no parent exercise)');
        continue;
      }
      final owner = await _sessionOwner(
        db,
        parentExercise.sessionLocalId,
        sessionCache,
      );
      exerciseCache[set.exerciseLocalId] = owner;
      if (owner != userId) {
        debugPrint('    ! Skipping set - not owned by current user');
        continue;
      }
      if (_positiveServerId(parentExercise.serverId) == null) {
        debugPrint('    ! Skipping set - parent exercise not synced yet');
        continue;
      }

      // Update set's exerciseServerId if not set
      if (set.exerciseServerId != parentExercise.serverId) {
        await db.writeTxn(() async {
          _assertCurrent(context);
          final reFetched = await db.localExerciseSets.get(set.localId);
          if (reFetched == null) return;
          reFetched.exerciseServerId = parentExercise.serverId;
          await db.localExerciseSets.put(reFetched);
        });
        debugPrint(
          '    Updated set exerciseServerId to ${parentExercise.serverId}',
        );
      }

      try {
        switch (set.syncStatus) {
          case 'pending_create':
            await _syncCreateSet(
              db,
              set,
              parentExercise,
              context,
              sessionCache,
              exerciseCache,
            );
            break;
          case 'pending_update':
            await _syncUpdateSet(
              db,
              set,
              parentExercise,
              context,
              sessionCache,
              exerciseCache,
            );
            break;
          case 'pending_delete':
            await _syncDeleteSet(db, set, context, sessionCache, exerciseCache);
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Set sync failed: $e');
      }
    }
  }

  /// Re-fetches [localId] and re-verifies its grandparent-chain ownership
  /// FRESH from Isar via throwaway caches - see [_reacquireOwnedExercise]'s
  /// doc comment for why this must never reuse the caller's phase-level
  /// cache.
  Future<LocalExerciseSet?> _reacquireOwnedSet(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localExerciseSets.get(localId);
    if (row == null) return null;
    final owner = await _exerciseOwner(
      db,
      row.exerciseLocalId,
      <int, int?>{},
      <int, int?>{},
    );
    if (owner != userId) return null;
    return row;
  }

  Future<void> _syncCreateSet(
    Isar db,
    LocalExerciseSet set,
    LocalExercise parentExercise,
    SessionRequestContext context,
    Map<int, int?> sessionCache,
    Map<int, int?> exerciseCache,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.exerciseSets,
      data: {
        'exerciseId': parentExercise.serverId,
        'setNumber': set.setNumber,
        'reps': set.reps,
        'weight': set.weight,
        'duration': set.duration,
        'isCompleted': set.isCompleted,
        'completedAt': set.completedAt?.toIso8601String(),
        'notes': set.notes,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedSet(
      db,
      set.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localExerciseSets.get(set.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.exerciseServerId = parentExercise.serverId;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      await db.localExerciseSets.put(reFetched);
    });

    debugPrint('    ✅ Created set ${set.serverId}');
  }

  Future<void> _syncUpdateSet(
    Isar db,
    LocalExerciseSet set,
    LocalExercise parentExercise,
    SessionRequestContext context,
    Map<int, int?> sessionCache,
    Map<int, int?> exerciseCache,
  ) async {
    if (_positiveServerId(set.serverId) == null) {
      // No server identity (never synced, or a legacy `serverId == 0`):
      // convert to an initial CREATE. `_syncCreateSet` sends the set's latest
      // `isCompleted` / `completedAt` / reps / weight, so a legacy pending row
      // completed offline before its first sync reaches the server with its
      // completed state. `_syncExerciseSets` has already gated on a positive
      // parent `serverId` and current-user ownership of the grandparent session.
      await _syncCreateSet(
        db,
        set,
        parentExercise,
        context,
        sessionCache,
        exerciseCache,
      );
      return;
    }

    // The API's `PUT /exercisesets/{id}` (ExerciseSetsController.UpdateExerciseSet)
    // requires `body.id == {route id}` - a mismatch is a deterministic 400 - and
    // requires the set's parent `exerciseId` so it is never reparented. Send the
    // resolved positive server ids for both; never a local id or `0`. Success is
    // 204 No Content and `put<void>` discards the (absent) body.
    //
    // `dispatchedAt` pins the exact local revision being synced so the
    // acknowledgment below can detect a same-session mutation that raced in
    // during the await.
    final dispatchedAt = set.lastModifiedLocal;
    await _apiService.put<void>(
      '${ApiConfig.exerciseSets}/${set.serverId}',
      data: {
        'id': set.serverId,
        'exerciseId': parentExercise.serverId,
        'setNumber': set.setNumber,
        'reps': set.reps,
        'weight': set.weight,
        'duration': set.duration,
        'isCompleted': set.isCompleted,
        'completedAt': set.completedAt?.toIso8601String(),
        'notes': set.notes,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedSet(
      db,
      set.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localExerciseSets.get(set.localId);
      if (reFetched == null) return;
      // Only acknowledge the exact local revision that was dispatched. Every
      // same-session mutation of a set (`_applyLocalComplete`,
      // `_markPendingDelete`) advances `lastModifiedLocal`, so a changed value
      // here means a newer edit or a queued delete raced in during the await -
      // leave it for the next pass rather than overwrite newer local intent.
      if (reFetched.lastModifiedLocal != dispatchedAt) return;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      await db.localExerciseSets.put(reFetched);
    });

    debugPrint('    ✅ Updated set ${set.serverId}');
  }

  Future<void> _syncDeleteSet(
    Isar db,
    LocalExerciseSet set,
    SessionRequestContext context,
    Map<int, int?> sessionCache,
    Map<int, int?> exerciseCache,
  ) async {
    // A never-synced row (or a legacy `serverId == 0`) has nothing on the
    // server: skip the DELETE, remove it locally only - no `DELETE /0`.
    if (_positiveServerId(set.serverId) != null) {
      await _apiService.delete(
        '${ApiConfig.exerciseSets}/${set.serverId}',
        sessionContext: context,
      );
      _assertCurrent(context);
    }

    final target = await _reacquireOwnedSet(
      db,
      set.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localExerciseSets.get(set.localId);
      if (reFetched == null) return;
      await db.localExerciseSets.delete(reFetched.localId);
    });

    debugPrint('    ✅ Deleted set');
  }

  // ========== Program Sync Methods ==========

  /// Sync all pending programs
  Future<void> _syncPrograms(Isar db, SessionRequestContext context) async {
    final userId = context.epochToken.userId;

    final pendingPrograms =
        await db.localPrograms
            .filter()
            .isSyncedEqualTo(false)
            .userIdEqualTo(userId)
            .findAll();

    if (pendingPrograms.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingPrograms.length} programs...');

    for (final program in pendingPrograms) {
      _assertCurrent(context);
      try {
        switch (program.syncStatus) {
          case 'pending_create':
            await _syncCreateProgram(db, program, context);
            break;
          case 'pending_update':
            await _syncUpdateProgram(db, program, context);
            break;
          case 'pending_delete':
            await _syncDeleteProgram(db, program, context);
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Program sync failed: $e');
        await _markProgramSyncError(db, program, e.toString(), context);
      }
    }
  }

  Future<LocalProgram?> _reacquireOwnedProgram(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localPrograms.get(localId);
    if (row == null || row.userId != userId) return null;
    return row;
  }

  Future<void> _syncCreateProgram(
    Isar db,
    LocalProgram program,
    SessionRequestContext context,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.programs,
      data: {
        'userId': program.userId,
        'title': program.title,
        'description': program.description,
        'goalId': program.goalId,
        'totalWeeks': program.totalWeeks,
        'currentWeek': program.currentWeek,
        'currentDay': program.currentDay,
        'startDate': program.startDate.toIso8601String(),
        'endDate': program.endDate?.toIso8601String(),
        'isActive': program.isActive,
        'isCompleted': program.isCompleted,
        'programStructure': program.programStructure,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedProgram(
      db,
      program.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localPrograms.get(program.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localPrograms.put(reFetched);
    });

    debugPrint('    ✅ Created program ${program.serverId}');
  }

  Future<void> _syncUpdateProgram(
    Isar db,
    LocalProgram program,
    SessionRequestContext context,
  ) async {
    if (program.serverId == null) {
      await _syncCreateProgram(db, program, context);
      return;
    }

    await _apiService.put<void>(
      '${ApiConfig.programs}/${program.serverId}',
      data: {
        'id': program.serverId!,
        'userId': program.userId,
        'title': program.title,
        'description': program.description,
        'goalId': program.goalId,
        'totalWeeks': program.totalWeeks,
        'currentWeek': program.currentWeek,
        'currentDay': program.currentDay,
        'startDate': program.startDate.toIso8601String(),
        'endDate': program.endDate?.toIso8601String(),
        'isActive': program.isActive,
        'isCompleted': program.isCompleted,
        'programStructure': program.programStructure,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedProgram(
      db,
      program.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localPrograms.get(program.localId);
      if (reFetched == null) return;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localPrograms.put(reFetched);
    });

    debugPrint('    ✅ Updated program ${program.serverId}');
  }

  Future<void> _syncDeleteProgram(
    Isar db,
    LocalProgram program,
    SessionRequestContext context,
  ) async {
    if (program.serverId != null) {
      await _apiService.delete(
        '${ApiConfig.programs}/${program.serverId}',
        sessionContext: context,
      );
      _assertCurrent(context);
    }

    final target = await _reacquireOwnedProgram(
      db,
      program.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localPrograms.get(program.localId);
      if (reFetched == null) return;
      // Delete related program workouts
      await db.localProgramWorkouts
          .filter()
          .programLocalIdEqualTo(reFetched.localId)
          .deleteAll();
      // Delete the program
      await db.localPrograms.delete(reFetched.localId);
    });

    debugPrint('    ✅ Deleted program');
  }

  Future<void> _markProgramSyncError(
    Isar db,
    LocalProgram program,
    String error,
    SessionRequestContext context,
  ) async {
    if (!_isCurrent(context)) return;
    final target = await _reacquireOwnedProgram(
      db,
      program.localId,
      context.epochToken.userId,
    );
    if (target == null || !_isCurrent(context)) return;

    await db.writeTxn(() async {
      if (!_isCurrent(context)) return;
      final reFetched = await db.localPrograms.get(program.localId);
      if (reFetched == null) return;
      reFetched.syncRetryCount += 1;
      reFetched.syncError = error;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localPrograms.put(reFetched);
    });
  }

  // ========== Goal Sync Methods ==========

  /// Sync all pending goals
  Future<void> _syncGoals(Isar db, SessionRequestContext context) async {
    final userId = context.epochToken.userId;

    final pendingGoals =
        await db.localGoals
            .filter()
            .isSyncedEqualTo(false)
            .userIdEqualTo(userId)
            .findAll();

    if (pendingGoals.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingGoals.length} goals...');

    for (final goal in pendingGoals) {
      _assertCurrent(context);
      try {
        switch (goal.syncStatus) {
          case 'pending_create':
            await _syncCreateGoal(db, goal, context);
            break;
          case 'pending_update':
            await _syncUpdateGoal(db, goal, context);
            break;
          case 'pending_delete':
            await _syncDeleteGoal(db, goal, context);
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Goal sync failed: $e');
        await _markGoalSyncError(db, goal, e.toString(), context);
      }
    }
  }

  Future<LocalGoal?> _reacquireOwnedGoal(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localGoals.get(localId);
    if (row == null || row.userId != userId) return null;
    return row;
  }

  Future<void> _syncCreateGoal(
    Isar db,
    LocalGoal goal,
    SessionRequestContext context,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.goals,
      data: {
        'userId': goal.userId,
        'goalType': goal.goalType,
        'targetValue': goal.targetValue,
        'currentValue': goal.currentValue,
        'unit': goal.unit,
        'timeFrame': goal.timeFrame,
        'startDate': goal.startDate.toIso8601String(),
        'targetDate': goal.targetDate?.toIso8601String(),
        'isActive': goal.isActive,
        'isCompleted': goal.isCompleted,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedGoal(
      db,
      goal.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localGoals.get(goal.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localGoals.put(reFetched);
    });

    debugPrint('    ✅ Created goal ${goal.serverId}');
  }

  Future<void> _syncUpdateGoal(
    Isar db,
    LocalGoal goal,
    SessionRequestContext context,
  ) async {
    if (goal.serverId == null) {
      await _syncCreateGoal(db, goal, context);
      return;
    }

    await _apiService.put<void>(
      '${ApiConfig.goals}/${goal.serverId}',
      data: {
        'id': goal.serverId!,
        'userId': goal.userId,
        'goalType': goal.goalType,
        'targetValue': goal.targetValue,
        'currentValue': goal.currentValue,
        'unit': goal.unit,
        'timeFrame': goal.timeFrame,
        'startDate': goal.startDate.toIso8601String(),
        'targetDate': goal.targetDate?.toIso8601String(),
        'isActive': goal.isActive,
        'isCompleted': goal.isCompleted,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedGoal(
      db,
      goal.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localGoals.get(goal.localId);
      if (reFetched == null) return;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localGoals.put(reFetched);
    });

    debugPrint('    ✅ Updated goal ${goal.serverId}');
  }

  Future<void> _syncDeleteGoal(
    Isar db,
    LocalGoal goal,
    SessionRequestContext context,
  ) async {
    if (goal.serverId != null) {
      await _apiService.delete(
        '${ApiConfig.goals}/${goal.serverId}',
        sessionContext: context,
      );
      _assertCurrent(context);
    }

    final target = await _reacquireOwnedGoal(
      db,
      goal.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localGoals.get(goal.localId);
      if (reFetched == null) return;
      await db.localGoals.delete(reFetched.localId);
    });

    debugPrint('    ✅ Deleted goal');
  }

  Future<void> _markGoalSyncError(
    Isar db,
    LocalGoal goal,
    String error,
    SessionRequestContext context,
  ) async {
    if (!_isCurrent(context)) return;
    final target = await _reacquireOwnedGoal(
      db,
      goal.localId,
      context.epochToken.userId,
    );
    if (target == null || !_isCurrent(context)) return;

    await db.writeTxn(() async {
      if (!_isCurrent(context)) return;
      final reFetched = await db.localGoals.get(goal.localId);
      if (reFetched == null) return;
      reFetched.syncRetryCount += 1;
      reFetched.syncError = error;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localGoals.put(reFetched);
    });
  }

  // ========== Program Workout Sync Methods (child of Program) ==========

  /// Sync all pending program workouts owned (via their parent program) by
  /// the captured user. Orphaned/foreign rows are silently skipped.
  Future<void> _syncProgramWorkouts(
    Isar db,
    SessionRequestContext context,
  ) async {
    final userId = context.epochToken.userId;
    final pendingWorkouts =
        await db.localProgramWorkouts.filter().isSyncedEqualTo(false).findAll();

    if (pendingWorkouts.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingWorkouts.length} program workouts...');

    final programCache = <int, int?>{};

    for (final workout in pendingWorkouts) {
      _assertCurrent(context);

      final parentProgram = await db.localPrograms.get(workout.programLocalId);
      if (parentProgram == null) {
        debugPrint('    ! Skipping workout - orphaned (no parent program)');
        continue;
      }
      programCache[workout.programLocalId] = parentProgram.userId;
      if (parentProgram.userId != userId) {
        debugPrint('    ! Skipping workout - not owned by current user');
        continue;
      }
      if (parentProgram.serverId == null) {
        debugPrint('    ! Skipping workout - parent program not synced yet');
        continue;
      }

      // Update workout's programServerId if not set
      if (workout.programServerId != parentProgram.serverId) {
        await db.writeTxn(() async {
          _assertCurrent(context);
          final reFetched = await db.localProgramWorkouts.get(workout.localId);
          if (reFetched == null) return;
          reFetched.programServerId = parentProgram.serverId;
          await db.localProgramWorkouts.put(reFetched);
        });
      }

      try {
        switch (workout.syncStatus) {
          case 'pending_create':
            await _syncCreateProgramWorkout(
              db,
              workout,
              parentProgram,
              context,
              programCache,
            );
            break;
          case 'pending_update':
            await _syncUpdateProgramWorkout(db, workout, context, programCache);
            break;
          case 'pending_delete':
            await _syncDeleteProgramWorkout(db, workout, context, programCache);
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Program workout sync failed: $e');
      }
    }
  }

  /// Re-fetches [localId] and re-verifies its parent-chain ownership FRESH
  /// from Isar - see [_reacquireOwnedExercise]'s doc comment.
  Future<LocalProgramWorkout?> _reacquireOwnedWorkout(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localProgramWorkouts.get(localId);
    if (row == null) return null;
    final owner = await _programOwner(db, row.programLocalId, <int, int?>{});
    if (owner != userId) return null;
    return row;
  }

  Future<void> _syncCreateProgramWorkout(
    Isar db,
    LocalProgramWorkout workout,
    LocalProgram parentProgram,
    SessionRequestContext context,
    Map<int, int?> programCache,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      '${ApiConfig.programs}/${parentProgram.serverId}/workouts',
      data: {
        'programId': parentProgram.serverId,
        'weekNumber': workout.weekNumber,
        'dayNumber': workout.dayNumber,
        'dayName': workout.dayName,
        'workoutName': workout.workoutName,
        'workoutType': workout.workoutType,
        'description': workout.description,
        'estimatedDuration': workout.estimatedDuration,
        'exercisesJson': workout.exercisesJson,
        'warmUp': workout.warmUp,
        'coolDown': workout.coolDown,
        'isCompleted': workout.isCompleted,
        'orderIndex': workout.orderIndex,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedWorkout(
      db,
      workout.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localProgramWorkouts.get(workout.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.programServerId = parentProgram.serverId;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      await db.localProgramWorkouts.put(reFetched);
    });

    debugPrint('    ✅ Created program workout ${workout.serverId}');
  }

  Future<void> _syncUpdateProgramWorkout(
    Isar db,
    LocalProgramWorkout workout,
    SessionRequestContext context,
    Map<int, int?> programCache,
  ) async {
    if (workout.serverId == null) {
      final parentProgram = await db.localPrograms.get(workout.programLocalId);
      if (parentProgram != null &&
          parentProgram.serverId != null &&
          parentProgram.userId == context.epochToken.userId) {
        await _syncCreateProgramWorkout(
          db,
          workout,
          parentProgram,
          context,
          programCache,
        );
      }
      return;
    }

    await _apiService.put<void>(
      '${ApiConfig.programs}/workouts/${workout.serverId}',
      data: {
        'id': workout.serverId!,
        'programId': workout.programServerId,
        'weekNumber': workout.weekNumber,
        'dayNumber': workout.dayNumber,
        'dayName': workout.dayName,
        'workoutName': workout.workoutName,
        'workoutType': workout.workoutType,
        'description': workout.description,
        'estimatedDuration': workout.estimatedDuration,
        'exercisesJson': workout.exercisesJson,
        'warmUp': workout.warmUp,
        'coolDown': workout.coolDown,
        'isCompleted': workout.isCompleted,
        'orderIndex': workout.orderIndex,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedWorkout(
      db,
      workout.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localProgramWorkouts.get(workout.localId);
      if (reFetched == null) return;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      await db.localProgramWorkouts.put(reFetched);
    });

    debugPrint('    ✅ Updated program workout ${workout.serverId}');
  }

  Future<void> _syncDeleteProgramWorkout(
    Isar db,
    LocalProgramWorkout workout,
    SessionRequestContext context,
    Map<int, int?> programCache,
  ) async {
    if (workout.serverId != null) {
      await _apiService.delete(
        '${ApiConfig.programs}/workouts/${workout.serverId}',
        sessionContext: context,
      );
      _assertCurrent(context);
    }

    final target = await _reacquireOwnedWorkout(
      db,
      workout.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localProgramWorkouts.get(workout.localId);
      if (reFetched == null) return;
      await db.localProgramWorkouts.delete(reFetched.localId);
    });

    debugPrint('    ✅ Deleted program workout');
  }

  // ========== Nutrition Goal Sync Methods ==========

  /// Sync all pending nutrition goals
  Future<void> _syncNutritionGoals(
    Isar db,
    SessionRequestContext context,
  ) async {
    final userId = context.epochToken.userId;

    final pendingGoals =
        await db.localNutritionGoals
            .filter()
            .isSyncedEqualTo(false)
            .userIdEqualTo(userId)
            .findAll();

    if (pendingGoals.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingGoals.length} nutrition goals...');

    for (final goal in pendingGoals) {
      _assertCurrent(context);
      try {
        switch (goal.syncStatus) {
          case 'pending_create':
            await _syncCreateNutritionGoal(db, goal, context);
            break;
          case 'pending_update':
            await _syncUpdateNutritionGoal(db, goal, context);
            break;
          case 'pending_delete':
            await _syncDeleteNutritionGoal(db, goal, context);
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Nutrition goal sync failed: $e');
        await _markNutritionGoalSyncError(db, goal, e.toString(), context);
      }
    }
  }

  Future<LocalNutritionGoal?> _reacquireOwnedNutritionGoal(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localNutritionGoals.get(localId);
    if (row == null || row.userId != userId) return null;
    return row;
  }

  Future<void> _syncCreateNutritionGoal(
    Isar db,
    LocalNutritionGoal goal,
    SessionRequestContext context,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.nutritionGoals,
      data: {
        'userId': goal.userId,
        'name': goal.name,
        'dailyCalories': goal.dailyCalories,
        'dailyProtein': goal.dailyProtein,
        'dailyCarbohydrates': goal.dailyCarbohydrates,
        'dailyFat': goal.dailyFat,
        'dailyFiber': goal.dailyFiber,
        'dailySodium': goal.dailySodium,
        'dailySugar': goal.dailySugar,
        'dailyWater': goal.dailyWater,
        'proteinPercentage': goal.proteinPercentage,
        'carbohydratesPercentage': goal.carbohydratesPercentage,
        'fatPercentage': goal.fatPercentage,
        'isActive': goal.isActive,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedNutritionGoal(
      db,
      goal.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localNutritionGoals.get(goal.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localNutritionGoals.put(reFetched);
    });

    debugPrint('    ✅ Created nutrition goal ${goal.serverId}');
  }

  Future<void> _syncUpdateNutritionGoal(
    Isar db,
    LocalNutritionGoal goal,
    SessionRequestContext context,
  ) async {
    if (goal.serverId == null) {
      await _syncCreateNutritionGoal(db, goal, context);
      return;
    }

    await _apiService.put<void>(
      ApiConfig.nutritionGoalById(goal.serverId!),
      data: {
        'id': goal.serverId!,
        'userId': goal.userId,
        'name': goal.name,
        'dailyCalories': goal.dailyCalories,
        'dailyProtein': goal.dailyProtein,
        'dailyCarbohydrates': goal.dailyCarbohydrates,
        'dailyFat': goal.dailyFat,
        'dailyFiber': goal.dailyFiber,
        'dailySodium': goal.dailySodium,
        'dailySugar': goal.dailySugar,
        'dailyWater': goal.dailyWater,
        'proteinPercentage': goal.proteinPercentage,
        'carbohydratesPercentage': goal.carbohydratesPercentage,
        'fatPercentage': goal.fatPercentage,
        'isActive': goal.isActive,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedNutritionGoal(
      db,
      goal.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localNutritionGoals.get(goal.localId);
      if (reFetched == null) return;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localNutritionGoals.put(reFetched);
    });

    debugPrint('    ✅ Updated nutrition goal ${goal.serverId}');
  }

  Future<void> _syncDeleteNutritionGoal(
    Isar db,
    LocalNutritionGoal goal,
    SessionRequestContext context,
  ) async {
    if (goal.serverId != null) {
      await _apiService.delete(
        ApiConfig.nutritionGoalById(goal.serverId!),
        sessionContext: context,
      );
      _assertCurrent(context);
    }

    final target = await _reacquireOwnedNutritionGoal(
      db,
      goal.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localNutritionGoals.get(goal.localId);
      if (reFetched == null) return;
      await db.localNutritionGoals.delete(reFetched.localId);
    });

    debugPrint('    ✅ Deleted nutrition goal');
  }

  Future<void> _markNutritionGoalSyncError(
    Isar db,
    LocalNutritionGoal goal,
    String error,
    SessionRequestContext context,
  ) async {
    if (!_isCurrent(context)) return;
    final target = await _reacquireOwnedNutritionGoal(
      db,
      goal.localId,
      context.epochToken.userId,
    );
    if (target == null || !_isCurrent(context)) return;

    await db.writeTxn(() async {
      if (!_isCurrent(context)) return;
      final reFetched = await db.localNutritionGoals.get(goal.localId);
      if (reFetched == null) return;
      reFetched.syncRetryCount += 1;
      reFetched.syncError = error;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localNutritionGoals.put(reFetched);
    });
  }

  // ========== Food Template Sync Methods ==========

  /// Sync all pending custom food templates
  Future<void> _syncFoodTemplates(
    Isar db,
    SessionRequestContext context,
  ) async {
    final userId = context.epochToken.userId;

    // Only sync custom food templates created by current user. Shared/
    // system templates (isCustom == false, or no createdByUserId) are
    // never queried here at all - this filter already excludes them.
    final pendingTemplates =
        await db.localFoodTemplates
            .filter()
            .isSyncedEqualTo(false)
            .isCustomEqualTo(true)
            .createdByUserIdEqualTo(userId)
            .findAll();

    if (pendingTemplates.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingTemplates.length} food templates...');

    for (final template in pendingTemplates) {
      _assertCurrent(context);
      try {
        switch (template.syncStatus) {
          case 'pending_create':
            await _syncCreateFoodTemplate(db, template, context);
            break;
          case 'pending_update':
            await _syncUpdateFoodTemplate(db, template, context);
            break;
          case 'pending_delete':
            await _syncDeleteFoodTemplate(db, template, context);
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Food template sync failed: $e');
        await _markFoodTemplateSyncError(db, template, e.toString(), context);
      }
    }
  }

  Future<LocalFoodTemplate?> _reacquireOwnedFoodTemplate(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localFoodTemplates.get(localId);
    if (row == null || row.createdByUserId != userId) return null;
    return row;
  }

  Future<void> _syncCreateFoodTemplate(
    Isar db,
    LocalFoodTemplate template,
    SessionRequestContext context,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.foodTemplates,
      data: {
        'name': template.name,
        'brand': template.brand,
        'category': template.category,
        'barcode': template.barcode,
        'servingSize': template.servingSize,
        'servingUnit': template.servingUnit,
        'calories': template.calories,
        'protein': template.protein,
        'carbohydrates': template.carbohydrates,
        'fat': template.fat,
        'fiber': template.fiber,
        'sugar': template.sugar,
        'sodium': template.sodium,
        'description': template.description,
        'imageUrl': template.imageUrl,
        'isCustom': template.isCustom,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedFoodTemplate(
      db,
      template.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localFoodTemplates.get(template.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localFoodTemplates.put(reFetched);
    });

    debugPrint('    ✅ Created food template ${template.serverId}');
  }

  Future<void> _syncUpdateFoodTemplate(
    Isar db,
    LocalFoodTemplate template,
    SessionRequestContext context,
  ) async {
    if (template.serverId == null) {
      await _syncCreateFoodTemplate(db, template, context);
      return;
    }

    await _apiService.put<void>(
      ApiConfig.foodTemplateById(template.serverId!),
      data: {
        'id': template.serverId!,
        'name': template.name,
        'brand': template.brand,
        'category': template.category,
        'barcode': template.barcode,
        'servingSize': template.servingSize,
        'servingUnit': template.servingUnit,
        'calories': template.calories,
        'protein': template.protein,
        'carbohydrates': template.carbohydrates,
        'fat': template.fat,
        'fiber': template.fiber,
        'sugar': template.sugar,
        'sodium': template.sodium,
        'description': template.description,
        'imageUrl': template.imageUrl,
        'isCustom': template.isCustom,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedFoodTemplate(
      db,
      template.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localFoodTemplates.get(template.localId);
      if (reFetched == null) return;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localFoodTemplates.put(reFetched);
    });

    debugPrint('    ✅ Updated food template ${template.serverId}');
  }

  Future<void> _syncDeleteFoodTemplate(
    Isar db,
    LocalFoodTemplate template,
    SessionRequestContext context,
  ) async {
    if (template.serverId != null) {
      await _apiService.delete(
        ApiConfig.foodTemplateById(template.serverId!),
        sessionContext: context,
      );
      _assertCurrent(context);
    }

    final target = await _reacquireOwnedFoodTemplate(
      db,
      template.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localFoodTemplates.get(template.localId);
      if (reFetched == null) return;
      await db.localFoodTemplates.delete(reFetched.localId);
    });

    debugPrint('    ✅ Deleted food template');
  }

  Future<void> _markFoodTemplateSyncError(
    Isar db,
    LocalFoodTemplate template,
    String error,
    SessionRequestContext context,
  ) async {
    if (!_isCurrent(context)) return;
    final target = await _reacquireOwnedFoodTemplate(
      db,
      template.localId,
      context.epochToken.userId,
    );
    if (target == null || !_isCurrent(context)) return;

    await db.writeTxn(() async {
      if (!_isCurrent(context)) return;
      final reFetched = await db.localFoodTemplates.get(template.localId);
      if (reFetched == null) return;
      reFetched.syncRetryCount += 1;
      reFetched.syncError = error;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localFoodTemplates.put(reFetched);
    });
  }

  // ========== Meal Log Sync Methods ==========

  /// Sync all pending meal logs
  Future<void> _syncMealLogs(Isar db, SessionRequestContext context) async {
    final userId = context.epochToken.userId;

    final pendingLogs =
        await db.localMealLogs
            .filter()
            .isSyncedEqualTo(false)
            .userIdEqualTo(userId)
            .findAll();

    if (pendingLogs.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingLogs.length} meal logs...');

    for (final log in pendingLogs) {
      _assertCurrent(context);
      try {
        switch (log.syncStatus) {
          case 'pending_create':
            await _syncCreateMealLog(db, log, context);
            break;
          case 'pending_update':
            await _syncUpdateMealLog(db, log, context);
            break;
          case 'pending_delete':
            await _syncDeleteMealLog(db, log, context);
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Meal log sync failed: $e');
        await _markMealLogSyncError(db, log, e.toString(), context);
      }
    }
  }

  Future<LocalMealLog?> _reacquireOwnedMealLog(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localMealLogs.get(localId);
    if (row == null || row.userId != userId) return null;
    return row;
  }

  /// Loads the entries belonging to [mealLogLocalId] and derives
  /// consumed-only totals via the shared [LocalNutritionTotalsCalculator] -
  /// the same formula the repository uses to reconcile
  /// `LocalMealLog.total*` and to repair legacy-polluted rows on read.
  /// Used at the sync-payload boundary so an unreconciled or stale stored
  /// aggregate can never be transmitted as "consumed".
  Future<LocalNutritionTotals> _consumedTotalsForMealLog(
    Isar db,
    int mealLogLocalId,
  ) async {
    final entries =
        await db.localMealEntrys
            .filter()
            .mealLogLocalIdEqualTo(mealLogLocalId)
            .findAll();
    return LocalNutritionTotalsCalculator.consumed(entries);
  }

  Future<void> _syncCreateMealLog(
    Isar db,
    LocalMealLog log,
    SessionRequestContext context,
  ) async {
    // Derive consumed totals fresh from this log's entries rather than
    // trusting LocalMealLog.total* - the stored aggregate may not yet be
    // reconciled (e.g. a log created entirely offline before its first
    // sync), and this is the network boundary: it must never transmit
    // planned/unconsumed food as consumed.
    final consumed = await _consumedTotalsForMealLog(db, log.localId);
    _assertCurrent(context);

    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.mealLogs,
      data: {
        'userId': log.userId,
        'date': log.date.toIso8601String(),
        'notes': log.notes,
        'waterIntake': log.waterIntake,
        'totalCalories': consumed.calories,
        'totalProtein': consumed.protein,
        'totalCarbohydrates': consumed.carbohydrates,
        'totalFat': consumed.fat,
        'totalFiber': consumed.fiber,
        'totalSodium': consumed.sodium,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedMealLog(
      db,
      log.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localMealLogs.get(log.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localMealLogs.put(reFetched);
    });

    debugPrint('    ✅ Created meal log ${log.serverId}');
  }

  Future<void> _syncUpdateMealLog(
    Isar db,
    LocalMealLog log,
    SessionRequestContext context,
  ) async {
    if (log.serverId == null) {
      await _syncCreateMealLog(db, log, context);
      return;
    }

    // Same derivation as _syncCreateMealLog: never trust the stored
    // aggregate at the network boundary, always recompute from entries.
    final consumed = await _consumedTotalsForMealLog(db, log.localId);
    _assertCurrent(context);

    await _apiService.put<void>(
      ApiConfig.mealLogById(log.serverId!),
      data: {
        'id': log.serverId!,
        'userId': log.userId,
        'date': log.date.toIso8601String(),
        'notes': log.notes,
        'waterIntake': log.waterIntake,
        'totalCalories': consumed.calories,
        'totalProtein': consumed.protein,
        'totalCarbohydrates': consumed.carbohydrates,
        'totalFat': consumed.fat,
        'totalFiber': consumed.fiber,
        'totalSodium': consumed.sodium,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedMealLog(
      db,
      log.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localMealLogs.get(log.localId);
      if (reFetched == null) return;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localMealLogs.put(reFetched);
    });

    debugPrint('    ✅ Updated meal log ${log.serverId}');
  }

  Future<void> _syncDeleteMealLog(
    Isar db,
    LocalMealLog log,
    SessionRequestContext context,
  ) async {
    if (log.serverId != null) {
      await _apiService.delete(
        ApiConfig.mealLogById(log.serverId!),
        sessionContext: context,
      );
      _assertCurrent(context);
    }

    final target = await _reacquireOwnedMealLog(
      db,
      log.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localMealLogs.get(log.localId);
      if (reFetched == null) return;

      // Delete related meal entries and food items
      final entries =
          await db.localMealEntrys
              .filter()
              .mealLogLocalIdEqualTo(reFetched.localId)
              .findAll();

      for (final entry in entries) {
        await db.localFoodItems
            .filter()
            .mealEntryLocalIdEqualTo(entry.localId)
            .deleteAll();
      }

      await db.localMealEntrys
          .filter()
          .mealLogLocalIdEqualTo(reFetched.localId)
          .deleteAll();

      await db.localMealLogs.delete(reFetched.localId);
    });

    debugPrint('    ✅ Deleted meal log');
  }

  Future<void> _markMealLogSyncError(
    Isar db,
    LocalMealLog log,
    String error,
    SessionRequestContext context,
  ) async {
    if (!_isCurrent(context)) return;
    final target = await _reacquireOwnedMealLog(
      db,
      log.localId,
      context.epochToken.userId,
    );
    if (target == null || !_isCurrent(context)) return;

    await db.writeTxn(() async {
      if (!_isCurrent(context)) return;
      final reFetched = await db.localMealLogs.get(log.localId);
      if (reFetched == null) return;
      reFetched.syncRetryCount += 1;
      reFetched.syncError = error;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localMealLogs.put(reFetched);
    });
  }

  // ========== Meal Entry Sync Methods (child of MealLog) ==========

  /// Sync all pending meal entries owned (via their parent meal log) by the
  /// captured user. Orphaned/foreign rows are silently skipped.
  Future<void> _syncMealEntries(Isar db, SessionRequestContext context) async {
    final userId = context.epochToken.userId;
    final pendingEntries =
        await db.localMealEntrys.filter().isSyncedEqualTo(false).findAll();

    if (pendingEntries.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingEntries.length} meal entries...');

    final mealLogCache = <int, int?>{};

    for (final entry in pendingEntries) {
      _assertCurrent(context);

      final parentLog = await db.localMealLogs.get(entry.mealLogLocalId);
      if (parentLog == null) {
        debugPrint('    ! Skipping meal entry - orphaned (no parent log)');
        continue;
      }
      mealLogCache[entry.mealLogLocalId] = parentLog.userId;
      if (parentLog.userId != userId) {
        debugPrint('    ! Skipping meal entry - not owned by current user');
        continue;
      }
      if (parentLog.serverId == null) {
        debugPrint(
          '    ! Skipping meal entry - parent meal log not synced yet',
        );
        continue;
      }

      // Update entry's mealLogServerId if not set
      if (entry.mealLogServerId != parentLog.serverId) {
        await db.writeTxn(() async {
          _assertCurrent(context);
          final reFetched = await db.localMealEntrys.get(entry.localId);
          if (reFetched == null) return;
          reFetched.mealLogServerId = parentLog.serverId;
          await db.localMealEntrys.put(reFetched);
        });
      }

      try {
        switch (entry.syncStatus) {
          case 'pending_create':
            await _syncCreateMealEntry(
              db,
              entry,
              parentLog,
              context,
              mealLogCache,
            );
            break;
          case 'pending_update':
            await _syncUpdateMealEntry(db, entry, context, mealLogCache);
            break;
          case 'pending_delete':
            await _syncDeleteMealEntry(db, entry, context, mealLogCache);
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Meal entry sync failed: $e');
        await _markMealEntrySyncError(
          db,
          entry,
          e.toString(),
          context,
          mealLogCache,
        );
      }
    }
  }

  /// Re-fetches [localId] and re-verifies its parent-chain ownership FRESH
  /// from Isar - see [_reacquireOwnedExercise]'s doc comment.
  Future<LocalMealEntry?> _reacquireOwnedMealEntry(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localMealEntrys.get(localId);
    if (row == null) return null;
    final owner = await _mealLogOwner(db, row.mealLogLocalId, <int, int?>{});
    if (owner != userId) return null;
    return row;
  }

  Future<void> _syncCreateMealEntry(
    Isar db,
    LocalMealEntry entry,
    LocalMealLog parentLog,
    SessionRequestContext context,
    Map<int, int?> mealLogCache,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.mealEntries,
      data: {
        'mealLogId': parentLog.serverId,
        'mealType': entry.mealType,
        'name': entry.name,
        'scheduledTime': entry.scheduledTime?.toIso8601String(),
        'isConsumed': entry.isConsumed,
        'consumedAt': entry.consumedAt?.toIso8601String(),
        'notes': entry.notes,
        'totalCalories': entry.totalCalories,
        'totalProtein': entry.totalProtein,
        'totalCarbohydrates': entry.totalCarbohydrates,
        'totalFat': entry.totalFat,
        'totalFiber': entry.totalFiber,
        'totalSodium': entry.totalSodium,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedMealEntry(
      db,
      entry.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localMealEntrys.get(entry.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.mealLogServerId = parentLog.serverId;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localMealEntrys.put(reFetched);
    });

    debugPrint('    ✅ Created meal entry ${entry.serverId}');
  }

  Future<void> _syncUpdateMealEntry(
    Isar db,
    LocalMealEntry entry,
    SessionRequestContext context,
    Map<int, int?> mealLogCache,
  ) async {
    if (entry.serverId == null) {
      final parentLog = await db.localMealLogs.get(entry.mealLogLocalId);
      if (parentLog != null &&
          parentLog.serverId != null &&
          parentLog.userId == context.epochToken.userId) {
        await _syncCreateMealEntry(db, entry, parentLog, context, mealLogCache);
      }
      return;
    }

    await _apiService.put<void>(
      ApiConfig.mealEntryById(entry.serverId!),
      data: {
        'id': entry.serverId!,
        'mealLogId': entry.mealLogServerId,
        'mealType': entry.mealType,
        'name': entry.name,
        'scheduledTime': entry.scheduledTime?.toIso8601String(),
        'isConsumed': entry.isConsumed,
        'consumedAt': entry.consumedAt?.toIso8601String(),
        'notes': entry.notes,
        'totalCalories': entry.totalCalories,
        'totalProtein': entry.totalProtein,
        'totalCarbohydrates': entry.totalCarbohydrates,
        'totalFat': entry.totalFat,
        'totalFiber': entry.totalFiber,
        'totalSodium': entry.totalSodium,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedMealEntry(
      db,
      entry.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localMealEntrys.get(entry.localId);
      if (reFetched == null) return;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localMealEntrys.put(reFetched);
    });

    debugPrint('    ✅ Updated meal entry ${entry.serverId}');
  }

  Future<void> _syncDeleteMealEntry(
    Isar db,
    LocalMealEntry entry,
    SessionRequestContext context,
    Map<int, int?> mealLogCache,
  ) async {
    if (entry.serverId != null) {
      await _apiService.delete(
        ApiConfig.mealEntryById(entry.serverId!),
        sessionContext: context,
      );
      _assertCurrent(context);
    }

    final target = await _reacquireOwnedMealEntry(
      db,
      entry.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localMealEntrys.get(entry.localId);
      if (reFetched == null) return;

      // Delete related food items
      await db.localFoodItems
          .filter()
          .mealEntryLocalIdEqualTo(reFetched.localId)
          .deleteAll();

      await db.localMealEntrys.delete(reFetched.localId);
    });

    debugPrint('    ✅ Deleted meal entry');
  }

  Future<void> _markMealEntrySyncError(
    Isar db,
    LocalMealEntry entry,
    String error,
    SessionRequestContext context,
    Map<int, int?> mealLogCache,
  ) async {
    if (!_isCurrent(context)) return;
    final target = await _reacquireOwnedMealEntry(
      db,
      entry.localId,
      context.epochToken.userId,
    );
    if (target == null || !_isCurrent(context)) return;

    await db.writeTxn(() async {
      if (!_isCurrent(context)) return;
      final reFetched = await db.localMealEntrys.get(entry.localId);
      if (reFetched == null) return;
      reFetched.syncRetryCount += 1;
      reFetched.syncError = error;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localMealEntrys.put(reFetched);
    });
  }

  // ========== Food Item Sync Methods (grandchild of MealLog) ==========

  /// Sync all pending food items owned (via meal entry → meal log) by the
  /// captured user. Orphaned/foreign rows are silently skipped.
  Future<void> _syncFoodItems(Isar db, SessionRequestContext context) async {
    final userId = context.epochToken.userId;
    final pendingItems =
        await db.localFoodItems.filter().isSyncedEqualTo(false).findAll();

    if (pendingItems.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingItems.length} food items...');

    final mealLogCache = <int, int?>{};
    final mealEntryCache = <int, int?>{};

    for (final item in pendingItems) {
      _assertCurrent(context);

      final parentEntry = await db.localMealEntrys.get(item.mealEntryLocalId);
      if (parentEntry == null) {
        debugPrint('    ! Skipping food item - orphaned (no parent entry)');
        continue;
      }
      final owner = await _mealLogOwner(
        db,
        parentEntry.mealLogLocalId,
        mealLogCache,
      );
      mealEntryCache[item.mealEntryLocalId] = owner;
      if (owner != userId) {
        debugPrint('    ! Skipping food item - not owned by current user');
        continue;
      }
      if (parentEntry.serverId == null) {
        debugPrint(
          '    ! Skipping food item - parent meal entry not synced yet',
        );
        continue;
      }

      // Update item's mealEntryServerId if not set
      if (item.mealEntryServerId != parentEntry.serverId) {
        await db.writeTxn(() async {
          _assertCurrent(context);
          final reFetched = await db.localFoodItems.get(item.localId);
          if (reFetched == null) return;
          reFetched.mealEntryServerId = parentEntry.serverId;
          await db.localFoodItems.put(reFetched);
        });
      }

      try {
        switch (item.syncStatus) {
          case 'pending_create':
            await _syncCreateFoodItem(
              db,
              item,
              parentEntry,
              context,
              mealLogCache,
              mealEntryCache,
            );
            break;
          case 'pending_update':
            await _syncUpdateFoodItem(
              db,
              item,
              context,
              mealLogCache,
              mealEntryCache,
            );
            break;
          case 'pending_delete':
            await _syncDeleteFoodItem(
              db,
              item,
              context,
              mealLogCache,
              mealEntryCache,
            );
            break;
        }
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('    ⚠️ Food item sync failed: $e');
        await _markFoodItemSyncError(
          db,
          item,
          e.toString(),
          context,
          mealLogCache,
          mealEntryCache,
        );
      }
    }
  }

  /// Re-fetches [localId] and re-verifies its grandparent-chain ownership
  /// FRESH from Isar via throwaway caches - see [_reacquireOwnedExercise]'s
  /// doc comment.
  Future<LocalFoodItem?> _reacquireOwnedFoodItem(
    Isar db,
    int localId,
    int userId,
  ) async {
    final row = await db.localFoodItems.get(localId);
    if (row == null) return null;
    final owner = await _mealEntryOwner(
      db,
      row.mealEntryLocalId,
      <int, int?>{},
      <int, int?>{},
    );
    if (owner != userId) return null;
    return row;
  }

  Future<void> _syncCreateFoodItem(
    Isar db,
    LocalFoodItem item,
    LocalMealEntry parentEntry,
    SessionRequestContext context,
    Map<int, int?> mealLogCache,
    Map<int, int?> mealEntryCache,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.foodItems,
      data: {
        'mealEntryId': parentEntry.serverId,
        'foodTemplateId': item.foodTemplateId,
        'name': item.name,
        'brand': item.brand,
        'quantity': item.quantity,
        'servingSize': item.servingSize,
        'servingUnit': item.servingUnit,
        'calories': item.calories,
        'protein': item.protein,
        'carbohydrates': item.carbohydrates,
        'fat': item.fat,
        'fiber': item.fiber,
        'sugar': item.sugar,
        'sodium': item.sodium,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedFoodItem(
      db,
      item.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localFoodItems.get(item.localId);
      if (reFetched == null) return;
      reFetched.serverId = response['id'] as int;
      reFetched.mealEntryServerId = parentEntry.serverId;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localFoodItems.put(reFetched);
    });

    debugPrint('    ✅ Created food item ${item.serverId}');
  }

  Future<void> _syncUpdateFoodItem(
    Isar db,
    LocalFoodItem item,
    SessionRequestContext context,
    Map<int, int?> mealLogCache,
    Map<int, int?> mealEntryCache,
  ) async {
    if (item.serverId == null) {
      final parentEntry = await db.localMealEntrys.get(item.mealEntryLocalId);
      if (parentEntry != null && parentEntry.serverId != null) {
        final owner = await _mealLogOwner(
          db,
          parentEntry.mealLogLocalId,
          mealLogCache,
        );
        if (owner == context.epochToken.userId) {
          await _syncCreateFoodItem(
            db,
            item,
            parentEntry,
            context,
            mealLogCache,
            mealEntryCache,
          );
        }
      }
      return;
    }

    await _apiService.put<void>(
      ApiConfig.foodItemById(item.serverId!),
      data: {
        'id': item.serverId!,
        'mealEntryId': item.mealEntryServerId,
        'foodTemplateId': item.foodTemplateId,
        'name': item.name,
        'brand': item.brand,
        'quantity': item.quantity,
        'servingSize': item.servingSize,
        'servingUnit': item.servingUnit,
        'calories': item.calories,
        'protein': item.protein,
        'carbohydrates': item.carbohydrates,
        'fat': item.fat,
        'fiber': item.fiber,
        'sugar': item.sugar,
        'sodium': item.sodium,
      },
      sessionContext: context,
    );
    _assertCurrent(context);

    final target = await _reacquireOwnedFoodItem(
      db,
      item.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localFoodItems.get(item.localId);
      if (reFetched == null) return;
      reFetched.isSynced = true;
      reFetched.syncStatus = 'synced';
      reFetched.syncRetryCount = 0;
      reFetched.syncError = null;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localFoodItems.put(reFetched);
    });

    debugPrint('    ✅ Updated food item ${item.serverId}');
  }

  Future<void> _syncDeleteFoodItem(
    Isar db,
    LocalFoodItem item,
    SessionRequestContext context,
    Map<int, int?> mealLogCache,
    Map<int, int?> mealEntryCache,
  ) async {
    if (item.serverId != null) {
      await _apiService.delete(
        ApiConfig.foodItemById(item.serverId!),
        sessionContext: context,
      );
      _assertCurrent(context);
    }

    final target = await _reacquireOwnedFoodItem(
      db,
      item.localId,
      context.epochToken.userId,
    );
    _assertCurrent(context);
    if (target == null) return;

    await _runTestHook(beforeAckWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideAckWriteTxnForTesting);
      _assertCurrent(context);
      final reFetched = await db.localFoodItems.get(item.localId);
      if (reFetched == null) return;
      await db.localFoodItems.delete(reFetched.localId);
    });

    debugPrint('    ✅ Deleted food item');
  }

  Future<void> _markFoodItemSyncError(
    Isar db,
    LocalFoodItem item,
    String error,
    SessionRequestContext context,
    Map<int, int?> mealLogCache,
    Map<int, int?> mealEntryCache,
  ) async {
    if (!_isCurrent(context)) return;
    final target = await _reacquireOwnedFoodItem(
      db,
      item.localId,
      context.epochToken.userId,
    );
    if (target == null || !_isCurrent(context)) return;

    await db.writeTxn(() async {
      if (!_isCurrent(context)) return;
      final reFetched = await db.localFoodItems.get(item.localId);
      if (reFetched == null) return;
      reFetched.syncRetryCount += 1;
      reFetched.syncError = error;
      reFetched.lastSyncAttempt = DateTime.now();
      await db.localFoodItems.put(reFetched);
    });
  }

  /// Get sync status summary
  Future<Map<String, dynamic>> getSyncStatus() async {
    final db = _localDb.database;

    final pendingCount =
        await db.localSessions.filter().isSyncedEqualTo(false).count();

    // Count sessions with sync errors (retry count >= 3)
    final errorCount =
        await db.localSessions
            .filter()
            .syncRetryCountGreaterThan(_maxRetries - 1)
            .count();

    final allSessions = await db.localSessions.where().findAll();
    final lastSyncAttempts =
        allSessions
            .where((s) => s.lastSyncAttempt != null)
            .map((s) => s.lastSyncAttempt!)
            .toList();

    final lastSyncTime =
        lastSyncAttempts.isEmpty
            ? null
            : lastSyncAttempts.reduce((a, b) => a.isAfter(b) ? a : b);

    return {
      'isSyncing': isSyncing,
      'pendingCount': pendingCount,
      'errorCount': errorCount,
      'lastSyncTime': lastSyncTime,
      'isOnline': _connectivity.isOnline,
    };
  }

  /// Retry failed syncs
  Future<void> retryFailedSyncs() async {
    final db = _localDb.database;

    // Reset retry count for failed items (retry count >= 3)
    final failedSessions =
        await db.localSessions
            .filter()
            .syncRetryCountGreaterThan(_maxRetries - 1)
            .findAll();

    await db.writeTxn(() async {
      for (final session in failedSessions) {
        session.syncRetryCount = 0;
        // Keep original syncStatus (pending_create/update/delete)
        session.syncError = null;
        await db.localSessions.put(session);
      }
    });

    debugPrint('🔄 Retrying ${failedSessions.length} failed syncs');

    // Trigger immediate sync
    if (failedSessions.isNotEmpty) {
      await sync();
    }
  }

  /// Dispose resources: cancels scheduling (timers/listener) as before.
  ///
  /// Deliberately does NOT touch [_activeOperation]. A still-running
  /// transport Future is not "completed" just because scheduling was torn
  /// down - and a logout-triggered dispose racing with a not-yet-installed
  /// new session's own sync() call must never clear that new session's
  /// active record. Whichever operation is (or isn't) active when dispose()
  /// runs continues to be governed exactly by its own `whenComplete`
  /// identity check (see the class doc comment's "Operation ownership"
  /// section) - dispose() has no special authority over it.
  void dispose() {
    _periodicSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _debounceTimer?.cancel();
    _periodicSyncTimer = null;
    _connectivitySubscription = null;
    _debounceTimer = null;
    _isInitialized = false;
    debugPrint('🛑 SyncService disposed');
  }

  /// Reset singleton (useful for testing)
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
