import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/food_template.dart';
import '../models/meal_log.dart';
import '../models/meal_entry.dart';
import '../models/food_item.dart';
import '../models/nutrition_goal.dart';
import '../models/nutrition_summary.dart';
import '../models/daily_nutrition_progress.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../local/services/local_database_service.dart';
import '../local/services/model_mapper.dart';
import '../local/services/local_nutrition_totals_calculator.dart';
import '../local/models/local_meal_log.dart';
import '../local/models/local_meal_entry.dart';
import '../local/models/local_food_item.dart';
import '../local/models/local_nutrition_goal.dart';
import '../local/models/local_food_template.dart';

/// Repository for nutrition operations with offline-first support
///
/// ## Local ownership enforcement
///
/// Every mutation below that resolves its target by an externally-supplied
/// ID (`updateWaterIntake`, `quickAddFood`, `deleteFoodItem`,
/// `updateNutritionGoal`, `markMealAsConsumed`, `clearAllFood`,
/// `addFoodItem`, `updateFoodQuantity`) enforces two independent things
/// before it is allowed to touch a row:
///
/// 1. **Row ownership** - the resolved [LocalMealLog]/[LocalNutritionGoal]
///    (direct `userId`) or [LocalMealEntry]/[LocalFoodItem] (owned
///    transitively through their parent [LocalMealLog]) must belong to the
///    calling [UserSessionToken.userId]. See `_resolveOwnedMealLog` et al.
/// 2. **Operation/session ownership** - the [_sessionEpoch] token captured
///    at method entry must still be [UserSessionEpoch.isCurrent] at every
///    checkpoint the method passes through. Row ownership alone is not
///    enough: a method can resolve a perfectly-owned row, have its user
///    log out (which invalidates the epoch and empties Isar via
///    `LocalDatabaseService.clearAll`), and only then reach its
///    `writeTxn` - without the epoch recheck placed as the FIRST statement
///    inside that `writeTxn` callback, that write would silently
///    reinsert/resurrect the logged-out user's row into a database that
///    was just cleared. See the `beforeWriteTxnForTesting` /
///    `insideWriteTxnForTesting` / `afterWriteTxnForTesting` test seams
///    below for how this exact race is exercised deterministically.
///
/// ## Detached/background session ownership
///
/// Every fire-and-forget push or refresh this repository schedules (via
/// [_backgroundSync]) captures its own [SessionRequestContext] from
/// [_sessionCoordinator] SYNCHRONOUSLY at the moment it is scheduled - not
/// inside the detached callback itself - so a callback that started under
/// User A can never silently adopt whichever session happens to be active
/// when it finally runs. Every migrated background HTTP call is bound to
/// that captured context (pinned JWT, dispatch-time epoch recheck,
/// generation-scoped cancellation - see [ApiService]'s class doc comment),
/// and every acknowledging local write it may perform (setting `serverId`,
/// `isSynced`, `syncStatus`, or replacing cached rows) is re-guarded with
/// [UserSessionEpoch.isCurrent] immediately after the HTTP response,
/// immediately before its `writeTxn`, and again as the first statement
/// inside that `writeTxn` - the same three-checkpoint shape the
/// synchronous mutations below already use, plus a re-resolution of the
/// target row by its stable local identity so a stale acknowledgment can
/// never land on a row that no longer belongs to the captured session. See
/// `beforeBackgroundHttpDispatchForTesting` /
/// `afterBackgroundHttpResponseForTesting` /
/// `insideBackgroundWriteTxnForTesting` for how this is exercised
/// deterministically in tests.
///
/// This repository does not itself solve `SyncService` session ownership
/// or `AuthProvider` logout-triggered cancellation (`_sessionCoordinator`
/// is only used here to capture contexts, never to cancel a generation);
/// both remain explicitly out of scope for this class and are tracked as
/// separate follow-ups.
class NutritionRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;
  final AuthService _authService;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// every other Provider/repository that needs it (see main.dart). Only
  /// AuthProvider ever calls activate()/invalidate() on it; this
  /// repository only ever reads it via capture()/isCurrent().
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext]
  /// (pinned JWT + generation-scoped [CancelToken]) for every detached
  /// background HTTP call this repository schedules. The SAME instance
  /// handed to every other consumer (see main.dart); never constructed
  /// privately.
  final SessionRequestCoordinator _sessionCoordinator;

  NutritionRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._authService,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  // ============ Test-only session-race seams ============
  //
  // Three hooks, one per checkpoint, let tests deterministically land a
  // session invalidation (and, where relevant, a clearAll() wipe) at each
  // of the three points every protected mutation re-checks
  // `_sessionEpoch.isCurrent(token)` around its writeTxn: immediately
  // before entering it, as the very first statement inside it (the
  // checkpoint that specifically closes the "waiting for Isar's write
  // lock" race described on this class), and immediately after it
  // returns. Each is `@visibleForTesting`, defaults to null, and is never
  // assigned outside test code - production control flow and performance
  // are unaffected.
  @visibleForTesting
  Future<void> Function()? beforeWriteTxnForTesting;

  @visibleForTesting
  Future<void> Function()? insideWriteTxnForTesting;

  @visibleForTesting
  Future<void> Function()? afterWriteTxnForTesting;

  // ============ Test-only background-race seams ============
  //
  // Same idea as the three hooks above, but for the detached/background
  // path: [beforeBackgroundHttpDispatchForTesting] runs immediately before
  // a migrated background HTTP call. [afterBackgroundHttpResponseForTesting]
  // runs AFTER each acknowledging call site's own post-HTTP epoch check has
  // already run (not before it) - deliberately, so a test using it to
  // invalidate exercises the pre-writeTxn checkpoint specifically, rather
  // than being masked by the post-HTTP checkpoint independently catching
  // the exact same, already-current-at-that-point invalidation. [
  // insideBackgroundWriteTxnForTesting] runs as the first statement inside
  // an acknowledging background `writeTxn`, mirroring the analogous
  // foreground hook above.
  @visibleForTesting
  Future<void> Function()? beforeBackgroundHttpDispatchForTesting;

  @visibleForTesting
  Future<void> Function()? afterBackgroundHttpResponseForTesting;

  @visibleForTesting
  Future<void> Function()? insideBackgroundWriteTxnForTesting;

  Future<void> _runTestHook(Future<void> Function()? hook) async {
    if (hook != null) {
      await hook();
    }
  }

  // ============ Session/ownership Helpers ============

  /// Captures the caller's session token and validates it hasn't changed
  /// by the time [AuthService.getUserId] resolves. Returns null if there
  /// is no active session (logged out), if the session changed while the
  /// userId read was in flight (a logout/relogin race), or if the
  /// resolved userId doesn't match the captured token's userId. Callers
  /// must treat null exactly like "no authenticated user" - the same
  /// failure every other unauthenticated check in this file already uses
  /// - and must not perform any Isar query or API call in that case.
  ///
  /// Deliberately never rereads/adopts a later userId: the single
  /// [AuthService.getUserId] read below is compared back against the
  /// SAME token captured before it, never used to silently swap identity.
  Future<UserSessionToken?> _captureOwnedSessionToken() async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;

    final userId = await _authService.getUserId();

    if (!_sessionEpoch.isCurrent(token)) return null;
    if (userId == null || userId != token.userId) return null;

    return token;
  }

  /// Resolves a [LocalMealLog] identified ambiguously by [id] (server ID
  /// or local Isar ID - every public model ID is `serverId ?? localId`,
  /// see `ModelMapper.localToMealLog`) to a row owned by [token.userId],
  /// or null if neither interpretation yields an owned row.
  ///
  /// Tries the server-ID interpretation first, but only accepts a match
  /// owned by the caller - a foreign server-ID match (same numeric [id],
  /// different owner) never prevents falling through to the local-ID
  /// interpretation, since server IDs and Isar auto-increment local IDs
  /// are independent sequences that can collide on the same number.
  Future<LocalMealLog?> _resolveOwnedMealLog(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final byServerId =
        await db.localMealLogs
            .filter()
            .serverIdEqualTo(id)
            .userIdEqualTo(token.userId)
            .findFirst();
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byServerId != null) return byServerId;

    final byLocalId = await db.localMealLogs.get(id);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byLocalId != null && byLocalId.userId == token.userId) {
      return byLocalId;
    }

    return null;
  }

  /// Same contract as [_resolveOwnedMealLog], for [LocalNutritionGoal].
  Future<LocalNutritionGoal?> _resolveOwnedNutritionGoal(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final byServerId =
        await db.localNutritionGoals
            .filter()
            .serverIdEqualTo(id)
            .userIdEqualTo(token.userId)
            .findFirst();
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byServerId != null) return byServerId;

    final byLocalId = await db.localNutritionGoals.get(id);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byLocalId != null && byLocalId.userId == token.userId) {
      return byLocalId;
    }

    return null;
  }

  /// True if [mealLogLocalId] resolves to a [LocalMealLog] owned by
  /// [token.userId]. False (never throws) for a missing/orphaned parent,
  /// so an orphaned child row is treated the same as a foreign one - never
  /// mutated.
  Future<bool> _isMealLogOwnedBy(
    Isar db,
    int mealLogLocalId,
    UserSessionToken token,
  ) async {
    final parentLog = await db.localMealLogs.get(mealLogLocalId);
    if (!_sessionEpoch.isCurrent(token)) return false;
    return parentLog != null && parentLog.userId == token.userId;
  }

  /// Resolves a [LocalMealEntry] identified ambiguously by [id] to a row
  /// whose parent [LocalMealLog] is owned by [token.userId] - entries have
  /// no direct `userId` field, so ownership is only reachable by walking
  /// `mealLogLocalId`. Same server-ID-first-but-not-exclusive strategy as
  /// [_resolveOwnedMealLog]: a foreign or orphaned server-ID candidate
  /// falls through to the local-ID interpretation, which is independently
  /// validated through its own parent.
  Future<LocalMealEntry?> _resolveOwnedMealEntry(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final byServerId =
        await db.localMealEntrys.filter().serverIdEqualTo(id).findFirst();
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byServerId != null &&
        await _isMealLogOwnedBy(db, byServerId.mealLogLocalId, token)) {
      return byServerId;
    }

    final byLocalId = await db.localMealEntrys.get(id);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byLocalId != null &&
        await _isMealLogOwnedBy(db, byLocalId.mealLogLocalId, token)) {
      return byLocalId;
    }

    return null;
  }

  /// True if [mealEntryLocalId] resolves to a [LocalMealEntry] whose
  /// parent [LocalMealLog] is owned by [token.userId]. False for a missing
  /// entry or a missing/foreign grandparent log - an orphaned food item is
  /// never mutated.
  Future<bool> _isMealEntryOwnedBy(
    Isar db,
    int mealEntryLocalId,
    UserSessionToken token,
  ) async {
    final parentEntry = await db.localMealEntrys.get(mealEntryLocalId);
    if (!_sessionEpoch.isCurrent(token)) return false;
    if (parentEntry == null) return false;
    return _isMealLogOwnedBy(db, parentEntry.mealLogLocalId, token);
  }

  /// Resolves a [LocalFoodItem] identified ambiguously by [id] to a row
  /// whose full grandparent chain (`mealEntryLocalId` ->
  /// `LocalMealEntry.mealLogLocalId` -> `LocalMealLog.userId`) is owned by
  /// [token.userId]. Same server-ID-first-but-not-exclusive strategy as
  /// [_resolveOwnedMealLog].
  Future<LocalFoodItem?> _resolveOwnedFoodItem(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final byServerId =
        await db.localFoodItems.filter().serverIdEqualTo(id).findFirst();
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byServerId != null &&
        await _isMealEntryOwnedBy(db, byServerId.mealEntryLocalId, token)) {
      return byServerId;
    }

    final byLocalId = await db.localFoodItems.get(id);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byLocalId != null &&
        await _isMealEntryOwnedBy(db, byLocalId.mealEntryLocalId, token)) {
      return byLocalId;
    }

    return null;
  }

  // ============ Helper Methods ============

  /// Schedules [operation] to run detached from the caller, bound to the
  /// session that is current RIGHT NOW - not whichever session happens to
  /// be active when the detached work finally runs.
  ///
  /// [SessionRequestCoordinator.captureContext] is invoked synchronously,
  /// before this method returns, so the capture itself always happens at
  /// scheduling time even though [operation] only runs after the returned
  /// context Future resolves. If capture fails (logged out, or the session
  /// changed while the JWT read was in flight), [operation] never runs -
  /// nothing is sent to the API and nothing is acknowledged.
  ///
  /// [SessionStaleException] and [RequestCancelledException] are expected
  /// lifecycle outcomes of a session ending mid-flight - logged as neither
  /// a success nor a failure, never surfaced as a user-visible error, and
  /// never treated as grounds to mark anything permanently failed. Every
  /// other exception preserves the exact "log and continue" behavior this
  /// method always had.
  void _backgroundSync(
    Future<void> Function(SessionRequestContext context) operation,
    String successMessage,
  ) {
    final contextFuture = _sessionCoordinator.captureContext();
    _runDetachedSync(contextFuture, operation, successMessage);
  }

  Future<void> _runDetachedSync(
    Future<SessionRequestContext?> contextFuture,
    Future<void> Function(SessionRequestContext context) operation,
    String successMessage,
  ) async {
    final context = await contextFuture;
    if (context == null) return;

    try {
      await operation(context);
      debugPrint('✅ Background sync: $successMessage');
    } on SessionStaleException {
      // Expected lifecycle outcome - the session ended before this
      // completed. Not a failure; nothing to log or retry differently.
    } on RequestCancelledException {
      // Expected lifecycle outcome - the request was cancelled because the
      // session ended. Same treatment as SessionStaleException.
    } catch (e) {
      debugPrint('⚠️ Background sync failed: $e');
    }
  }

  /// Wraps a single migrated background HTTP call with the before-dispatch
  /// test seam so every call site gets it without repeating the
  /// boilerplate. Staleness AT dispatch time is already enforced by
  /// [ApiService] itself via [context]'s pinned
  /// [SessionRequestContext.epochToken].
  ///
  /// Deliberately does NOT also run [afterBackgroundHttpResponseForTesting]
  /// - every acknowledging call site below runs that hook itself,
  /// positioned AFTER its own post-HTTP checkpoint (not before it), so a
  /// test using that hook to invalidate exercises the pre-writeTxn
  /// checkpoint specifically rather than being masked by the post-HTTP one
  /// catching the exact same, already-current-at-that-point invalidation.
  Future<T> _dispatchBackgroundHttp<T>(Future<T> Function() call) async {
    await _runTestHook(beforeBackgroundHttpDispatchForTesting);
    return call();
  }

  /// Recompute and persist [LocalMealLog.totalCalories]/etc. as the
  /// consumed-only sum of its current [LocalMealEntry] rows.
  ///
  /// Must be called after any write that could change what counts as
  /// "consumed" for this log (food added/edited/deleted on an entry, or a
  /// consumed-status toggle), from inside the same [Isar.writeTxn] as that
  /// write so the recompute sees the just-written entry state rather than a
  /// stale snapshot. Always re-derives from source entries instead of
  /// applying a delta, so repeated calls (e.g. consume/unconsume toggled
  /// back and forth) are idempotent by construction.
  Future<void> _reconcileMealLogConsumedTotals(
    Isar db,
    int mealLogLocalId,
  ) async {
    final localLog = await db.localMealLogs.get(mealLogLocalId);
    if (localLog == null) return;

    final entries =
        await db.localMealEntrys
            .filter()
            .mealLogLocalIdEqualTo(mealLogLocalId)
            .findAll();

    final consumed = LocalNutritionTotalsCalculator.consumed(entries);

    localLog.totalCalories = consumed.calories;
    localLog.totalProtein = consumed.protein;
    localLog.totalCarbohydrates = consumed.carbohydrates;
    localLog.totalFat = consumed.fat;
    localLog.totalFiber = consumed.fiber;
    localLog.totalSodium = consumed.sodium;
    localLog.lastModifiedLocal = DateTime.now().toUtc();
    localLog.isSynced = false;
    if (localLog.serverId != null) {
      localLog.syncStatus = 'pending_update';
    }

    await db.localMealLogs.put(localLog);
  }

  // ============ Meal Logs - Offline First ============

  /// Get today's meal log - offline-first
  /// Creates locally if not exists, syncs in background
  Future<MealLog> getTodaysMealLog() async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Normalize today's date (strip time component)
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    // 1. Check local cache first
    var localLog =
        await db.localMealLogs
            .filter()
            .userIdEqualTo(userId)
            .dateEqualTo(today)
            .findFirst();

    // 2. If found locally, return immediately and sync in background
    if (localLog != null) {
      debugPrint('📦 Found today\'s meal log in cache');

      if (_connectivity.isOnline) {
        _backgroundSync(
          (context) => _syncMealLogFromServer(db, context),
          'Synced today\'s meal log',
        );
      }

      return await _localMealLogToMealLogWithEntries(db, localLog);
    }

    // 3. If not found and online, fetch from server
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.mealLogToday,
        );
        final mealLog = MealLog.fromJson(data);

        // Cache locally with entries
        await _cacheMealLogWithEntries(db, mealLog);
        debugPrint('✅ Fetched and cached today\'s meal log from server');

        return mealLog;
      } catch (e) {
        debugPrint('⚠️ API failed, creating local meal log: $e');
        // Fall through to create locally
      }
    }

    // 4. Create locally (offline or API failed)
    debugPrint('📴 Creating meal log locally');
    return await _createLocalMealLog(db, userId, today);
  }

  /// Sync meal log from server - background refresh triggered by
  /// [getTodaysMealLog]'s cache-hit path. Bound to [context]: the HTTP
  /// call carries its pinned JWT, and the resulting cache write is fully
  /// gated by [_cacheMealLogWithEntries]'s [UserSessionToken] scoping.
  Future<void> _syncMealLogFromServer(
    Isar db,
    SessionRequestContext context,
  ) async {
    final data = await _dispatchBackgroundHttp(
      () => _apiService.get<Map<String, dynamic>>(
        ApiConfig.mealLogToday,
        sessionContext: context,
      ),
    );
    final serverMealLog = MealLog.fromJson(data);
    await _cacheMealLogWithEntries(
      db,
      serverMealLog,
      scopeToken: context.epochToken,
    );
  }

  /// Cache a MealLog with all its entries and food items.
  ///
  /// [scopeToken] is non-null only when called from a background refresh
  /// (see the class doc comment's "Detached/background session ownership"
  /// section) and gates the entire write behind three checkpoints -
  /// immediately on entry (the post-HTTP checkpoint, from the caller's
  /// perspective), immediately before the write transaction (after
  /// re-resolving the target by its stable server identity), and again as
  /// the very first statement inside the transaction - plus a direct
  /// ownership check against [MealLog.userId], so a stale or foreign
  /// response can never reach local storage. `null` (every foreground
  /// call site, unchanged) preserves this method's original unconditional
  /// behavior.
  Future<void> _cacheMealLogWithEntries(
    Isar db,
    MealLog mealLog, {
    UserSessionToken? scopeToken,
  }) async {
    if (scopeToken != null) {
      // Checkpoint 1: post-HTTP, before touching Isar at all.
      if (!_sessionEpoch.isCurrent(scopeToken)) return;
      if (mealLog.userId != scopeToken.userId) return;

      await _runTestHook(afterBackgroundHttpResponseForTesting);

      // Re-resolve the target by its stable server identity before
      // deciding whether to acknowledge - never assume the row this
      // response names is still the right one to touch.
      final target =
          await db.localMealLogs
              .filter()
              .serverIdEqualTo(mealLog.id)
              .findFirst();
      // Checkpoint 2: immediately before entering the write transaction.
      if (!_sessionEpoch.isCurrent(scopeToken)) return;
      if (target != null && target.userId != scopeToken.userId) return;
    }

    await db.writeTxn(() async {
      if (scopeToken != null) {
        await _runTestHook(insideBackgroundWriteTxnForTesting);
        // Checkpoint 3: first statement inside the write transaction.
        if (!_sessionEpoch.isCurrent(scopeToken)) return;
      }

      // Find or create local meal log
      var existingLog =
          await db.localMealLogs
              .filter()
              .serverIdEqualTo(mealLog.id)
              .findFirst();

      // Skip caching over a row with pending local changes - a background
      // refresh (including the one getTodaysMealLog()/getMealLogs() fire
      // right after a legacy-totals repair) must never silently discard a
      // local edit that hasn't reached the server yet, otherwise a
      // pending_update repair could be overwritten back to the pre-repair,
      // still-polluted server value before the corrective sync push ever
      // runs. Mirrors the same guard in session_repository.dart. Entries
      // are protected transitively: every local mutation that flags an
      // entry pending_update also reconciles and flags its parent log
      // pending_update, so returning here before the entries loop below
      // leaves them untouched too.
      if (existingLog != null &&
          (existingLog.syncStatus == 'pending_update' ||
              existingLog.syncStatus == 'pending_delete')) {
        debugPrint(
          '⏭️ Skipping meal log cache update for ${mealLog.id} - has '
          'pending local changes (${existingLog.syncStatus})',
        );
        return;
      }

      LocalMealLog savedLog;
      if (existingLog != null) {
        // Update existing
        savedLog = ModelMapper.mealLogToLocal(
          mealLog,
          localId: existingLog.localId,
          isSynced: true,
        );
      } else {
        savedLog = ModelMapper.mealLogToLocal(mealLog, isSynced: true);
      }
      await db.localMealLogs.put(savedLog);

      // Cache meal entries
      for (final entry in mealLog.mealEntries ?? <MealEntry>[]) {
        var existingEntry =
            await db.localMealEntrys
                .filter()
                .serverIdEqualTo(entry.id)
                .findFirst();

        LocalMealEntry savedEntry;
        if (existingEntry != null) {
          savedEntry = ModelMapper.mealEntryToLocal(
            entry,
            mealLogLocalId: savedLog.localId,
            mealLogServerId: savedLog.serverId,
            localId: existingEntry.localId,
            isSynced: true,
          );
        } else {
          savedEntry = ModelMapper.mealEntryToLocal(
            entry,
            mealLogLocalId: savedLog.localId,
            mealLogServerId: savedLog.serverId,
            isSynced: true,
          );
        }
        await db.localMealEntrys.put(savedEntry);

        // Cache food items
        for (final food in entry.foodItems ?? <FoodItem>[]) {
          var existingFood =
              await db.localFoodItems
                  .filter()
                  .serverIdEqualTo(food.id)
                  .findFirst();

          LocalFoodItem savedFood;
          if (existingFood != null) {
            savedFood = ModelMapper.foodItemToLocal(
              food,
              mealEntryLocalId: savedEntry.localId,
              mealEntryServerId: savedEntry.serverId,
              localId: existingFood.localId,
              isSynced: true,
            );
          } else {
            savedFood = ModelMapper.foodItemToLocal(
              food,
              mealEntryLocalId: savedEntry.localId,
              mealEntryServerId: savedEntry.serverId,
              isSynced: true,
            );
          }
          await db.localFoodItems.put(savedFood);
        }
      }
    });
  }

  /// Create a local meal log with default entries
  Future<MealLog> _createLocalMealLog(
    Isar db,
    int userId,
    DateTime date,
  ) async {
    final now = DateTime.now();

    late LocalMealLog savedLog;
    final entries = <MealEntry>[];

    await db.writeTxn(() async {
      // Create meal log
      final localLog = LocalMealLog(
        userId: userId,
        date: date,
        waterIntake: 0,
        totalCalories: 0,
        totalProtein: 0,
        totalCarbohydrates: 0,
        totalFat: 0,
        createdAt: now,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: now,
      );
      await db.localMealLogs.put(localLog);
      savedLog = localLog;

      // Create default meal entries
      for (final mealType in ['Breakfast', 'Lunch', 'Dinner', 'Snack']) {
        final localEntry = LocalMealEntry(
          mealLogLocalId: savedLog.localId,
          mealType: mealType,
          isConsumed: false,
          totalCalories: 0,
          totalProtein: 0,
          totalCarbohydrates: 0,
          totalFat: 0,
          createdAt: now,
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: now,
        );
        await db.localMealEntrys.put(localEntry);

        entries.add(
          MealEntry(
            id: localEntry.localId,
            mealLogId: savedLog.localId,
            mealType: mealType,
            isConsumed: false,
            totalCalories: 0,
            totalProtein: 0,
            totalCarbohydrates: 0,
            totalFat: 0,
            createdAt: now,
          ),
        );
      }
    });

    debugPrint('💾 Created local meal log for $date');

    return MealLog(
      id: savedLog.localId,
      userId: userId,
      date: date,
      waterIntake: 0,
      totalCalories: 0,
      totalProtein: 0,
      totalCarbohydrates: 0,
      totalFat: 0,
      createdAt: now,
      mealEntries: entries,
    );
  }

  /// Convert LocalMealLog to MealLog with entries loaded.
  ///
  /// Also repairs legacy-polluted `LocalMealLog.total*` rows: consumed
  /// totals are re-derived from the just-loaded entries (the source of
  /// truth) on every call, entirely from local data, no network required.
  /// If the stored value differs from the recomputed one, the correction is
  /// persisted; either way the returned [MealLog] always carries the
  /// corrected values immediately, even if the persist step below fails.
  Future<MealLog> _localMealLogToMealLogWithEntries(
    Isar db,
    LocalMealLog localLog,
  ) async {
    // Load meal entries
    final localEntries =
        await db.localMealEntrys
            .filter()
            .mealLogLocalIdEqualTo(localLog.localId)
            .findAll();

    final entries = <MealEntry>[];
    for (final localEntry in localEntries) {
      // Load food items for this entry
      final localFoods =
          await db.localFoodItems
              .filter()
              .mealEntryLocalIdEqualTo(localEntry.localId)
              .findAll();

      final foods =
          localFoods.map((f) => ModelMapper.localToFoodItem(f)).toList();

      entries.add(ModelMapper.localToMealEntry(localEntry, foodItems: foods));
    }

    await _repairConsumedTotalsIfStale(db, localLog, localEntries);

    return ModelMapper.localToMealLog(localLog, mealEntries: entries);
  }

  /// Compares [localLog]'s stored consumed totals against a fresh
  /// recomputation from [localEntries]; corrects the in-memory object
  /// unconditionally (so the caller's read is always right this frame) and
  /// persists the correction only when it actually differs and only when
  /// the write succeeds. A repair-write failure never fails the read - it
  /// is logged and retried on the next read of this log, matching this
  /// repository's existing "local write best-effort, log and continue"
  /// pattern used elsewhere (e.g. background sync failures).
  Future<void> _repairConsumedTotalsIfStale(
    Isar db,
    LocalMealLog localLog,
    List<LocalMealEntry> localEntries,
  ) async {
    const epsilon = 1e-9;
    bool differs(double a, double b) => (a - b).abs() > epsilon;

    final consumed = LocalNutritionTotalsCalculator.consumed(localEntries);

    final isStale =
        differs(localLog.totalCalories, consumed.calories) ||
        differs(localLog.totalProtein, consumed.protein) ||
        differs(localLog.totalCarbohydrates, consumed.carbohydrates) ||
        differs(localLog.totalFat, consumed.fat) ||
        differs(localLog.totalFiber ?? 0, consumed.fiber) ||
        differs(localLog.totalSodium ?? 0, consumed.sodium);

    if (!isStale) return;

    // Correct the in-memory object immediately, independent of whether the
    // persist below succeeds.
    localLog.totalCalories = consumed.calories;
    localLog.totalProtein = consumed.protein;
    localLog.totalCarbohydrates = consumed.carbohydrates;
    localLog.totalFat = consumed.fat;
    localLog.totalFiber = consumed.fiber;
    localLog.totalSodium = consumed.sodium;
    // Mirror every other mutation site in this file: a corrected value is a
    // local change that hasn't reached the server yet. Without this, a row
    // that was already synced before this repair ran would never be picked
    // up by _syncMealLogs (which only selects isSynced == false), so the
    // server would keep serving the pre-repair, polluted total forever -
    // and a later server cache-replacement could silently overwrite this
    // repair with that still-wrong value.
    localLog.isSynced = false;
    if (localLog.serverId != null) {
      localLog.syncStatus = 'pending_update';
    }

    try {
      await db.writeTxn(() async {
        await db.localMealLogs.put(localLog);
      });
      debugPrint(
        '🩹 Repaired stale consumed totals for meal log ${localLog.localId}',
      );
    } catch (e) {
      debugPrint(
        '⚠️ Failed to persist consumed-totals repair for meal log '
        '${localLog.localId}: $e',
      );
    }
  }

  /// Get meal logs for date range - offline-first
  Future<List<MealLog>> getMealLogs({
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 30,
  }) async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) return [];

    // Get from local cache first
    var query = db.localMealLogs.filter().userIdEqualTo(userId);

    if (startDate != null) {
      // Normalize to start of day for inclusive start boundary
      final startDay = DateTime(startDate.year, startDate.month, startDate.day);
      query = query.dateGreaterThan(startDay.subtract(const Duration(days: 1)));
    }
    if (endDate != null) {
      // Normalize to start of NEXT day for inclusive end boundary
      // This ensures we include all of endDate but exclude the next day
      final nextDay = DateTime(endDate.year, endDate.month, endDate.day + 1);
      query = query.dateLessThan(nextDay);
    }

    final localLogs = await query.sortByDateDesc().findAll();

    // Convert to MealLog models
    final logs = <MealLog>[];
    for (final localLog in localLogs) {
      logs.add(await _localMealLogToMealLogWithEntries(db, localLog));
    }

    // Sync in background if online
    if (_connectivity.isOnline) {
      _backgroundSync(
        (context) => _syncMealLogsFromServer(startDate, endDate, context),
        'Synced meal logs history',
      );
    }

    return logs;
  }

  /// Sync meal logs from server. Bound to [context]: the HTTP call carries
  /// its pinned JWT, and each cached row is independently gated by
  /// [_cacheMealLogWithEntries]'s [UserSessionToken] scoping - a session
  /// change mid-loop stops acknowledging further rows without discarding
  /// ones already safely cached under the still-current session.
  Future<void> _syncMealLogsFromServer(
    DateTime? startDate,
    DateTime? endDate,
    SessionRequestContext context,
  ) async {
    final queryParams = <String, String>{};
    if (startDate != null) {
      queryParams['startDate'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      queryParams['endDate'] = endDate.toIso8601String();
    }

    final data = await _dispatchBackgroundHttp(
      () => _apiService.get<List<dynamic>>(
        ApiConfig.mealLogs,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
        sessionContext: context,
      ),
    );

    final db = _localDb.database;
    for (final json in data) {
      final mealLog = MealLog.fromJson(json as Map<String, dynamic>);
      await _cacheMealLogWithEntries(
        db,
        mealLog,
        scopeToken: context.epochToken,
      );
    }
  }

  /// Update water intake - offline-first
  Future<void> updateWaterIntake(int mealLogId, double waterIntake) async {
    final token = await _captureOwnedSessionToken();
    if (token == null) {
      throw Exception('User not authenticated');
    }

    final db = _localDb.database;

    // Find local meal log, owned by the captured user
    final localLog = await _resolveOwnedMealLog(db, mealLogId, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }
    if (localLog == null) {
      throw Exception('Meal log not found');
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    // Update locally first
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      localLog.waterIntake = waterIntake;
      localLog.lastModifiedLocal = DateTime.now().toUtc();
      localLog.isSynced = false;
      if (localLog.serverId != null) {
        localLog.syncStatus = 'pending_update';
      }
      await db.localMealLogs.put(localLog);
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    debugPrint('💧 Updated water intake locally: $waterIntake ml');

    // Sync in background if online
    if (_connectivity.isOnline && localLog.serverId != null) {
      _backgroundSync(
        (context) => _dispatchBackgroundHttp(
          () => _apiService.put<void>(
            ApiConfig.mealLogWater(localLog.serverId!),
            data: waterIntake,
            sessionContext: context,
          ),
        ),
        'Synced water intake',
      );
    }
  }

  // ============ Food Items - Offline First ============

  /// Quick add food from template - offline-first
  Future<FoodItem> quickAddFood({
    required int mealEntryId,
    required int foodTemplateId,
    double quantity = 1,
  }) async {
    final token = await _captureOwnedSessionToken();
    if (token == null) {
      throw Exception('User not authenticated');
    }

    final db = _localDb.database;

    // Find local meal entry, owned by the captured user
    final localEntry = await _resolveOwnedMealEntry(db, mealEntryId, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }
    if (localEntry == null) {
      throw Exception('Meal entry not found');
    }

    // Get food template from cache or API
    final template = await _getFoodTemplateById(foodTemplateId);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }
    if (template == null) {
      throw Exception('Food template not found');
    }

    // Capture non-nullable references for use in closure
    final entry = localEntry;
    final foodTemplate = template;

    // Create food item locally
    final now = DateTime.now();
    late LocalFoodItem savedFood;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final localFood = LocalFoodItem(
        mealEntryLocalId: entry.localId,
        mealEntryServerId: entry.serverId,
        foodTemplateId: foodTemplateId,
        name: foodTemplate.name,
        brand: foodTemplate.brand,
        quantity: quantity,
        servingSize: foodTemplate.servingSize,
        servingUnit: foodTemplate.servingUnit,
        calories: foodTemplate.calories * quantity,
        protein: foodTemplate.protein * quantity,
        carbohydrates: foodTemplate.carbohydrates * quantity,
        fat: foodTemplate.fat * quantity,
        fiber:
            foodTemplate.fiber != null ? foodTemplate.fiber! * quantity : null,
        sugar:
            foodTemplate.sugar != null ? foodTemplate.sugar! * quantity : null,
        sodium:
            foodTemplate.sodium != null
                ? foodTemplate.sodium! * quantity
                : null,
        createdAt: now,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: now,
      );
      await db.localFoodItems.put(localFood);
      savedFood = localFood;

      // Update meal entry totals (status-independent: this entry's own
      // food sum, regardless of isConsumed)
      entry.totalCalories += localFood.calories;
      entry.totalProtein += localFood.protein;
      entry.totalCarbohydrates += localFood.carbohydrates;
      entry.totalFat += localFood.fat;
      entry.lastModifiedLocal = now;
      entry.isSynced = false;
      if (entry.serverId != null) {
        entry.syncStatus = 'pending_update';
      }
      await db.localMealEntrys.put(entry);

      // Reconcile the parent meal log's consumed-only totals from all
      // current entries (recompute, not delta) - only includes this food
      // if the entry is actually consumed.
      await _reconcileMealLogConsumedTotals(db, entry.mealLogLocalId);
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    debugPrint('➕ Added food "${foodTemplate.name}" locally');

    // Sync in background if online and entry has server ID
    if (_connectivity.isOnline && entry.serverId != null) {
      _backgroundSync(
        (context) => _syncFoodItemToServer(savedFood, entry.serverId!, context),
        'Synced food item to server',
      );
    }

    return ModelMapper.localToFoodItem(savedFood);
  }

  /// Sync food item to server. Bound to [context]: the HTTP call carries
  /// its pinned JWT, and the resulting serverId/isSynced acknowledgment is
  /// gated behind three checkpoints (post-HTTP, pre-writeTxn, and
  /// first-statement-inside-writeTxn) plus a re-resolution of
  /// [localFood]'s row by its stable local identity and parent-chain
  /// ownership, so a stale response can never acknowledge a row that no
  /// longer belongs to the captured session.
  Future<void> _syncFoodItemToServer(
    LocalFoodItem localFood,
    int mealEntryServerId,
    SessionRequestContext context,
  ) async {
    final data = await _dispatchBackgroundHttp(
      () => _apiService.post<Map<String, dynamic>>(
        ApiConfig.foodItemQuickAdd,
        data: {
          'mealEntryId': mealEntryServerId,
          'foodTemplateId': localFood.foodTemplateId,
          'quantity': localFood.quantity,
        },
        sessionContext: context,
      ),
    );
    final serverFood = FoodItem.fromJson(data);

    // Checkpoint 1: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final db = _localDb.database;

    // Re-resolve by stable local identity and validate the full
    // parent-chain ownership before deciding whether to acknowledge.
    final target = await db.localFoodItems.get(localFood.localId);
    if (target == null ||
        !await _isMealEntryOwnedBy(
          db,
          target.mealEntryLocalId,
          context.epochToken,
        )) {
      return;
    }

    // Checkpoint 2: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint 3: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(context.epochToken)) return;

      target.serverId = serverFood.id;
      target.isSynced = true;
      target.syncStatus = 'synced';
      await db.localFoodItems.put(target);
    });
  }

  /// Delete food item - offline-first
  Future<void> deleteFoodItem(int id) async {
    final token = await _captureOwnedSessionToken();
    if (token == null) {
      throw Exception('User not authenticated');
    }

    final db = _localDb.database;

    // Find local food item, owned by the captured user
    final localFood = await _resolveOwnedFoodItem(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }
    if (localFood == null) {
      throw Exception('Food item not found');
    }

    final serverId = localFood.serverId;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      // Update meal entry totals
      final localEntry = await db.localMealEntrys.get(
        localFood.mealEntryLocalId,
      );
      if (localEntry != null) {
        localEntry.totalCalories -= localFood.calories;
        localEntry.totalProtein -= localFood.protein;
        localEntry.totalCarbohydrates -= localFood.carbohydrates;
        localEntry.totalFat -= localFood.fat;
        localEntry.lastModifiedLocal = DateTime.now().toUtc();
        localEntry.isSynced = false;
        if (localEntry.serverId != null) {
          localEntry.syncStatus = 'pending_update';
        }
        await db.localMealEntrys.put(localEntry);
      }

      await db.localFoodItems.delete(localFood.localId);

      // Reconcile the parent meal log's consumed-only totals from the
      // just-updated entry (put() above), not a stale snapshot.
      if (localEntry != null) {
        await _reconcileMealLogConsumedTotals(db, localEntry.mealLogLocalId);
      }
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    debugPrint('🗑️ Deleted food item locally');

    // Sync in background if online and had server ID
    if (_connectivity.isOnline && serverId != null) {
      _backgroundSync(
        (context) => _dispatchBackgroundHttp(
          () => _apiService.delete(
            ApiConfig.foodItemById(serverId),
            sessionContext: context,
          ),
        ),
        'Deleted food item on server',
      );
    }
  }

  // ============ Food Templates ============

  /// Get food template by ID - checks cache first
  Future<FoodTemplate?> _getFoodTemplateById(int id) async {
    final db = _localDb.database;

    // Check local cache first
    final localTemplate =
        await db.localFoodTemplates.filter().serverIdEqualTo(id).findFirst();

    if (localTemplate != null) {
      return ModelMapper.localToFoodTemplate(localTemplate);
    }

    // Fetch from API if online
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.foodTemplateById(id),
        );
        final template = FoodTemplate.fromJson(data);

        // Cache locally
        await db.writeTxn(() async {
          final local = ModelMapper.foodTemplateToLocal(template);
          await db.localFoodTemplates.put(local);
        });

        return template;
      } catch (e) {
        debugPrint('⚠️ Failed to fetch food template: $e');
      }
    }

    return null;
  }

  /// Get all food templates with optional filtering
  Future<List<FoodTemplate>> getFoodTemplates({
    String? category,
    bool? isCustom,
    int page = 1,
    int pageSize = 50,
  }) async {
    final db = _localDb.database;

    // Get from local cache first
    var query = db.localFoodTemplates.where();
    final localTemplates = await query.findAll();

    // Filter locally
    var filtered =
        localTemplates.where((t) {
          if (category != null && t.category != category) return false;
          if (isCustom != null && t.isCustom != isCustom) return false;
          return true;
        }).toList();

    // Sync in background if online
    if (_connectivity.isOnline) {
      _backgroundSync(
        (context) => _syncFoodTemplatesFromServer(category, isCustom, context),
        'Synced food templates',
      );
    }

    return filtered.map((t) => ModelMapper.localToFoodTemplate(t)).toList();
  }

  /// Sync food templates from server. Bound to [context]: the HTTP call
  /// carries its pinned JWT. Food templates are a shared catalog (not
  /// per-user data - see the class doc comment's ownership section), so
  /// the cache write is gated only by session-currency, never by a
  /// per-row userId restriction that would incorrectly treat this shared
  /// data as owned by one user.
  Future<void> _syncFoodTemplatesFromServer(
    String? category,
    bool? isCustom,
    SessionRequestContext context,
  ) async {
    final queryParams = <String, String>{};
    if (category != null) queryParams['category'] = category;
    if (isCustom != null) queryParams['isCustom'] = isCustom.toString();

    final data = await _dispatchBackgroundHttp(
      () => _apiService.get<List<dynamic>>(
        ApiConfig.foodTemplates,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
        sessionContext: context,
      ),
    );

    // Checkpoint 1: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final db = _localDb.database;

    // Checkpoint 2: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint 3: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(context.epochToken)) return;

      for (final json in data) {
        final template = FoodTemplate.fromJson(json as Map<String, dynamic>);

        var existing =
            await db.localFoodTemplates
                .filter()
                .serverIdEqualTo(template.id)
                .findFirst();

        if (existing != null) {
          final updated = ModelMapper.foodTemplateToLocal(
            template,
            localId: existing.localId,
          );
          await db.localFoodTemplates.put(updated);
        } else {
          final local = ModelMapper.foodTemplateToLocal(template);
          await db.localFoodTemplates.put(local);
        }
      }
    });
  }

  /// Search foods
  Future<List<FoodTemplate>> searchFoods(
    String query, {
    String? category,
    int limit = 20,
  }) async {
    final db = _localDb.database;

    // Search local cache first
    final localTemplates =
        await db.localFoodTemplates
            .filter()
            .nameContains(query, caseSensitive: false)
            .findAll();

    var results =
        localTemplates
            .where((t) => category == null || t.category == category)
            .take(limit)
            .map((t) => ModelMapper.localToFoodTemplate(t))
            .toList();

    // If online and few local results, also search server
    if (_connectivity.isOnline && results.length < limit) {
      try {
        final queryParams = <String, String>{
          'query': query,
          'limit': limit.toString(),
        };
        if (category != null) queryParams['category'] = category;

        final data = await _apiService.get<List<dynamic>>(
          '${ApiConfig.foodTemplates}/search',
          queryParameters: queryParams,
        );

        final serverResults =
            data
                .map(
                  (json) => FoodTemplate.fromJson(json as Map<String, dynamic>),
                )
                .toList();

        // Cache new results
        await db.writeTxn(() async {
          for (final template in serverResults) {
            var existing =
                await db.localFoodTemplates
                    .filter()
                    .serverIdEqualTo(template.id)
                    .findFirst();

            if (existing == null) {
              await db.localFoodTemplates.put(
                ModelMapper.foodTemplateToLocal(template),
              );
            }
          }
        });

        // Merge results (avoid duplicates)
        final existingIds = results.map((r) => r.id).toSet();
        for (final template in serverResults) {
          if (!existingIds.contains(template.id)) {
            results.add(template);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Server search failed, using local results: $e');
      }
    }

    return results.take(limit).toList();
  }

  /// Get food categories
  Future<List<String>> getFoodCategories() async {
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<List<dynamic>>(
          ApiConfig.foodTemplateCategories,
        );
        return data.cast<String>();
      } catch (e) {
        debugPrint('⚠️ Failed to fetch categories: $e');
      }
    }

    // Fallback to local categories
    final db = _localDb.database;
    final templates = await db.localFoodTemplates.where().findAll();
    final categories =
        templates.map((t) => t.category).whereType<String>().toSet().toList();
    categories.sort();
    return categories;
  }

  /// Get food by barcode
  Future<FoodTemplate?> getFoodByBarcode(String barcode) async {
    final db = _localDb.database;

    // Check local cache first
    final local =
        await db.localFoodTemplates
            .filter()
            .barcodeEqualTo(barcode)
            .findFirst();

    if (local != null) {
      return ModelMapper.localToFoodTemplate(local);
    }

    // Fetch from API if online
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.foodTemplateByBarcode(barcode),
        );
        final template = FoodTemplate.fromJson(data);

        // Cache locally
        await db.writeTxn(() async {
          await db.localFoodTemplates.put(
            ModelMapper.foodTemplateToLocal(template),
          );
        });

        return template;
      } catch (e) {
        debugPrint('Food not found for barcode: $barcode');
      }
    }

    return null;
  }

  /// Create custom food template
  Future<FoodTemplate> createFoodTemplate(FoodTemplate template) async {
    final db = _localDb.database;
    final now = DateTime.now();

    // Create locally first
    late LocalFoodTemplate savedTemplate;
    await db.writeTxn(() async {
      final local = LocalFoodTemplate(
        name: template.name,
        brand: template.brand,
        category: template.category,
        barcode: template.barcode,
        servingSize: template.servingSize,
        servingUnit: template.servingUnit,
        calories: template.calories,
        protein: template.protein,
        carbohydrates: template.carbohydrates,
        fat: template.fat,
        fiber: template.fiber,
        sugar: template.sugar,
        sodium: template.sodium,
        description: template.description,
        imageUrl: template.imageUrl,
        isCustom: true,
        createdByUserId: await _authService.getUserId(),
        createdAt: now,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: now,
      );
      await db.localFoodTemplates.put(local);
      savedTemplate = local;
    });

    debugPrint('💾 Created custom food template locally: ${template.name}');

    // Sync in background if online
    if (_connectivity.isOnline) {
      _backgroundSync(
        (context) => _syncFoodTemplateToServer(savedTemplate, context),
        'Synced custom food template',
      );
    }

    return ModelMapper.localToFoodTemplate(savedTemplate);
  }

  /// Sync a newly-created custom food template to server. Bound to
  /// [context]: the HTTP call carries its pinned JWT, and the resulting
  /// serverId/isSynced acknowledgment is gated behind three checkpoints
  /// plus a re-resolution of [local]'s row by its stable local identity
  /// and direct `createdByUserId` ownership - this push only ever
  /// acknowledges a template this session itself created.
  Future<void> _syncFoodTemplateToServer(
    LocalFoodTemplate local,
    SessionRequestContext context,
  ) async {
    final template = ModelMapper.localToFoodTemplate(local);
    final data = await _dispatchBackgroundHttp(
      () => _apiService.post<Map<String, dynamic>>(
        ApiConfig.foodTemplates,
        data: template.toJson(),
        sessionContext: context,
      ),
    );
    final serverTemplate = FoodTemplate.fromJson(data);

    // Checkpoint 1: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final db = _localDb.database;

    // Re-resolve by stable local identity and validate direct ownership
    // before deciding whether to acknowledge.
    final target = await db.localFoodTemplates.get(local.localId);
    if (target == null || target.createdByUserId != context.epochToken.userId) {
      return;
    }

    // Checkpoint 2: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint 3: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(context.epochToken)) return;

      target.serverId = serverTemplate.id;
      target.isSynced = true;
      target.syncStatus = 'synced';
      await db.localFoodTemplates.put(target);
    });
  }

  // ============ Nutrition Goals - Offline First ============

  /// Get active nutrition goal - offline-first
  Future<NutritionGoal> getActiveNutritionGoal() async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Check local cache first
    final localGoal =
        await db.localNutritionGoals
            .filter()
            .userIdEqualTo(userId)
            .isActiveEqualTo(true)
            .findFirst();

    if (localGoal != null) {
      debugPrint('📦 Found active nutrition goal in cache');

      if (_connectivity.isOnline) {
        _backgroundSync(
          (context) => _syncNutritionGoalFromServer(db, context),
          'Synced nutrition goal',
        );
      }

      return ModelMapper.localToNutritionGoal(localGoal);
    }

    // Fetch from API if online
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.nutritionGoalActive,
        );
        final goal = NutritionGoal.fromJson(data);

        // Cache locally
        await db.writeTxn(() async {
          final local = ModelMapper.nutritionGoalToLocal(goal);
          await db.localNutritionGoals.put(local);
        });

        return goal;
      } catch (e) {
        debugPrint('⚠️ Failed to fetch nutrition goal: $e');
      }
    }

    // Return default goal
    return NutritionGoal.defaultGoal(userId);
  }

  /// Sync nutrition goal from server. Bound to [context]: the HTTP call
  /// carries its pinned JWT, and the resulting cache write is gated
  /// behind three checkpoints plus a direct [NutritionGoal.userId]
  /// ownership check, so a stale or foreign response can never replace
  /// this session's cached goal. Also skips a row with pending local
  /// changes, mirroring the same guard in [_cacheMealLogWithEntries] -
  /// otherwise a background refresh could silently discard a local edit
  /// that hasn't reached the server yet.
  Future<void> _syncNutritionGoalFromServer(
    Isar db,
    SessionRequestContext context,
  ) async {
    final data = await _dispatchBackgroundHttp(
      () => _apiService.get<Map<String, dynamic>>(
        ApiConfig.nutritionGoalActive,
        sessionContext: context,
      ),
    );
    final goal = NutritionGoal.fromJson(data);

    // Checkpoint 1: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;
    if (goal.userId != context.epochToken.userId) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    // Checkpoint 2: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint 3: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(context.epochToken)) return;

      var existing =
          await db.localNutritionGoals
              .filter()
              .serverIdEqualTo(goal.id)
              .findFirst();

      // Skip caching over a row with pending local changes - mirrors the
      // identical guard in _cacheMealLogWithEntries.
      if (existing != null &&
          (existing.syncStatus == 'pending_update' ||
              existing.syncStatus == 'pending_delete')) {
        return;
      }

      if (existing != null) {
        final updated = ModelMapper.nutritionGoalToLocal(
          goal,
          localId: existing.localId,
        );
        await db.localNutritionGoals.put(updated);
      } else {
        await db.localNutritionGoals.put(
          ModelMapper.nutritionGoalToLocal(goal),
        );
      }
    });
  }

  /// Update nutrition goal - offline-first
  Future<void> updateNutritionGoal(int id, NutritionGoal goal) async {
    final token = await _captureOwnedSessionToken();
    if (token == null) {
      throw Exception('User not authenticated');
    }

    final db = _localDb.database;

    // Find local goal, owned by the captured user
    final localGoal = await _resolveOwnedNutritionGoal(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }
    if (localGoal == null) {
      throw Exception('Nutrition goal not found');
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    // Update locally first
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      localGoal.dailyCalories = goal.dailyCalories;
      localGoal.dailyProtein = goal.dailyProtein;
      localGoal.dailyCarbohydrates = goal.dailyCarbohydrates;
      localGoal.dailyFat = goal.dailyFat;
      localGoal.dailyFiber = goal.dailyFiber;
      localGoal.dailyWater = goal.dailyWater;
      localGoal.name = goal.name;
      localGoal.updatedAt = DateTime.now();
      localGoal.lastModifiedLocal = DateTime.now().toUtc();
      localGoal.isSynced = false;
      if (localGoal.serverId != null) {
        localGoal.syncStatus = 'pending_update';
      }
      await db.localNutritionGoals.put(localGoal);
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    debugPrint('✅ Updated nutrition goal locally');

    // Sync in background if online
    if (_connectivity.isOnline && localGoal.serverId != null) {
      _backgroundSync(
        (context) => _dispatchBackgroundHttp(
          () => _apiService.put<void>(
            ApiConfig.nutritionGoalById(localGoal.serverId!),
            data: goal.toJson(),
            sessionContext: context,
          ),
        ),
        'Synced nutrition goal update',
      );
    }
  }

  /// Create nutrition goal - offline-first
  Future<NutritionGoal> createNutritionGoal(NutritionGoal goal) async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final now = DateTime.now();
    late LocalNutritionGoal savedGoal;

    await db.writeTxn(() async {
      // Deactivate other goals
      final activeGoals =
          await db.localNutritionGoals
              .filter()
              .userIdEqualTo(userId)
              .isActiveEqualTo(true)
              .findAll();

      for (final g in activeGoals) {
        g.isActive = false;
        g.lastModifiedLocal = now;
        g.isSynced = false;
        if (g.serverId != null) {
          g.syncStatus = 'pending_update';
        }
        await db.localNutritionGoals.put(g);
      }

      // Create new goal
      final local = LocalNutritionGoal(
        userId: userId,
        name: goal.name,
        dailyCalories: goal.dailyCalories,
        dailyProtein: goal.dailyProtein,
        dailyCarbohydrates: goal.dailyCarbohydrates,
        dailyFat: goal.dailyFat,
        dailyFiber: goal.dailyFiber,
        dailySodium: goal.dailySodium,
        dailySugar: goal.dailySugar,
        dailyWater: goal.dailyWater,
        isActive: true,
        createdAt: now,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: now,
      );
      await db.localNutritionGoals.put(local);
      savedGoal = local;
    });

    debugPrint('💾 Created nutrition goal locally');

    // Sync in background if online
    if (_connectivity.isOnline) {
      _backgroundSync(
        (context) => _syncNutritionGoalToServer(savedGoal, context),
        'Synced new nutrition goal',
      );
    }

    return ModelMapper.localToNutritionGoal(savedGoal);
  }

  /// Sync a newly-created nutrition goal to server. Bound to [context]:
  /// the HTTP call carries its pinned JWT, and the resulting
  /// serverId/isSynced acknowledgment is gated behind three checkpoints
  /// plus a re-resolution of [local]'s row by its stable local identity
  /// and direct `userId` ownership.
  Future<void> _syncNutritionGoalToServer(
    LocalNutritionGoal local,
    SessionRequestContext context,
  ) async {
    final goal = ModelMapper.localToNutritionGoal(local);
    final data = await _dispatchBackgroundHttp(
      () => _apiService.post<Map<String, dynamic>>(
        ApiConfig.nutritionGoals,
        data: goal.toJson(),
        sessionContext: context,
      ),
    );
    final serverGoal = NutritionGoal.fromJson(data);

    // Checkpoint 1: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final db = _localDb.database;

    // Re-resolve by stable local identity and validate direct ownership
    // before deciding whether to acknowledge.
    final target = await db.localNutritionGoals.get(local.localId);
    if (target == null || target.userId != context.epochToken.userId) return;

    // Checkpoint 2: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(context.epochToken)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint 3: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(context.epochToken)) return;

      target.serverId = serverGoal.id;
      target.isSynced = true;
      target.syncStatus = 'synced';
      await db.localNutritionGoals.put(target);
    });
  }

  // ============ Analytics (Server-only) ============

  /// Get nutrition progress
  Future<NutritionProgress> getNutritionProgress({DateTime? date}) async {
    if (_connectivity.isOnline) {
      final queryParams =
          date != null ? {'date': date.toIso8601String().split('T')[0]} : null;

      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.nutritionGoalProgress,
        queryParameters: queryParams,
      );
      return NutritionProgress.fromJson(data);
    }

    // Calculate locally if offline
    final db = _localDb.database;
    final userId = await _authService.getUserId();
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final targetDate = date ?? DateTime.now();
    final normalizedDate = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );

    final localLog =
        await db.localMealLogs
            .filter()
            .userIdEqualTo(userId)
            .dateEqualTo(normalizedDate)
            .findFirst();

    final localGoal =
        await db.localNutritionGoals
            .filter()
            .userIdEqualTo(userId)
            .isActiveEqualTo(true)
            .findFirst();

    final goal =
        localGoal != null
            ? ModelMapper.localToNutritionGoal(localGoal)
            : NutritionGoal.defaultGoal(userId);

    // Derive consumed totals directly from entries rather than trusting
    // LocalMealLog.total* - keeps this in lockstep with the same
    // consumed-only invariant used everywhere else, even if this log's
    // stored aggregate hasn't been reconciled/repaired yet.
    final localEntries =
        localLog != null
            ? await db.localMealEntrys
                .filter()
                .mealLogLocalIdEqualTo(localLog.localId)
                .findAll()
            : <LocalMealEntry>[];
    final consumedTotals = LocalNutritionTotalsCalculator.consumed(
      localEntries,
    );

    final consumed = NutritionTotals(
      calories: consumedTotals.calories,
      protein: consumedTotals.protein,
      carbohydrates: consumedTotals.carbohydrates,
      fat: consumedTotals.fat,
    );

    final remaining = NutritionTotals(
      calories: (goal.dailyCalories - consumed.calories).clamp(
        0,
        double.infinity,
      ),
      protein: (goal.dailyProtein - consumed.protein).clamp(0, double.infinity),
      carbohydrates: (goal.dailyCarbohydrates - consumed.carbohydrates).clamp(
        0,
        double.infinity,
      ),
      fat: (goal.dailyFat - consumed.fat).clamp(0, double.infinity),
    );

    final percentageConsumed = NutritionPercentages(
      calories:
          goal.dailyCalories > 0
              ? (consumed.calories / goal.dailyCalories) * 100
              : 0,
      protein:
          goal.dailyProtein > 0
              ? (consumed.protein / goal.dailyProtein) * 100
              : 0,
      carbohydrates:
          goal.dailyCarbohydrates > 0
              ? (consumed.carbohydrates / goal.dailyCarbohydrates) * 100
              : 0,
      fat: goal.dailyFat > 0 ? (consumed.fat / goal.dailyFat) * 100 : 0,
    );

    return NutritionProgress(
      date: normalizedDate,
      goal: goal,
      consumed: consumed,
      remaining: remaining,
      percentageConsumed: percentageConsumed,
    );
  }

  /// Get nutrition dashboard data (goal + progress for a date)
  /// This is the primary method for dashboard display
  Future<NutritionDashboardData> getNutritionDashboard({DateTime? date}) async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    if (_connectivity.isOnline) {
      try {
        final queryParams =
            date != null
                ? {'date': date.toIso8601String().split('T')[0]}
                : null;

        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.nutritionGoalDashboard,
          queryParameters: queryParams,
        );

        final goal =
            data['goal'] != null
                ? NutritionGoal.fromJson(data['goal'] as Map<String, dynamic>)
                : null;

        final progress = DailyNutritionProgress.fromJson(
          data['progress'] as Map<String, dynamic>,
        );

        debugPrint(
          '✅ Fetched nutrition dashboard - planned: ${progress.plannedCalories}, consumed: ${progress.consumedCalories}',
        );

        return NutritionDashboardData(
          date: date ?? DateTime.now(),
          goal: goal,
          progress: progress,
        );
      } catch (e) {
        debugPrint('⚠️ Failed to fetch nutrition dashboard: $e');
        // Fall through to offline calculation
      }
    }

    // Offline: calculate from local data
    final targetDate = date ?? DateTime.now();
    final normalizedDate = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );

    final localGoal =
        await db.localNutritionGoals
            .filter()
            .userIdEqualTo(userId)
            .isActiveEqualTo(true)
            .findFirst();

    final goal =
        localGoal != null
            ? ModelMapper.localToNutritionGoal(localGoal)
            : NutritionGoal.defaultGoal(userId);

    // Get meal log for the date to calculate planned/consumed
    final localLog =
        await db.localMealLogs
            .filter()
            .userIdEqualTo(userId)
            .dateEqualTo(normalizedDate)
            .findFirst();

    double plannedCalories = 0;
    double plannedProtein = 0;
    double plannedCarbs = 0;
    double plannedFat = 0;
    double consumedCalories = 0;
    double consumedProtein = 0;
    double consumedCarbs = 0;
    double consumedFat = 0;

    if (localLog != null) {
      final entries =
          await db.localMealEntrys
              .filter()
              .mealLogLocalIdEqualTo(localLog.localId)
              .findAll();

      for (final entry in entries) {
        plannedCalories += entry.totalCalories;
        plannedProtein += entry.totalProtein;
        plannedCarbs += entry.totalCarbohydrates;
        plannedFat += entry.totalFat;

        if (entry.isConsumed) {
          consumedCalories += entry.totalCalories;
          consumedProtein += entry.totalProtein;
          consumedCarbs += entry.totalCarbohydrates;
          consumedFat += entry.totalFat;
        }
      }
    }

    final progress = DailyNutritionProgress(
      id: 0,
      userId: userId,
      date: normalizedDate,
      nutritionGoalId: goal.id,
      plannedCalories: plannedCalories,
      plannedProtein: plannedProtein,
      plannedCarbohydrates: plannedCarbs,
      plannedFat: plannedFat,
      consumedCalories: consumedCalories,
      consumedProtein: consumedProtein,
      consumedCarbohydrates: consumedCarbs,
      consumedFat: consumedFat,
      createdAt: DateTime.now(),
    );

    return NutritionDashboardData(
      date: normalizedDate,
      goal: goal,
      progress: progress,
    );
  }

  /// Get streak info
  Future<StreakInfo> getStreak() async {
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.nutritionAnalyticsStreak,
        );
        return StreakInfo.fromJson(data);
      } catch (e) {
        debugPrint('⚠️ Failed to fetch streak: $e');
      }
    }

    // Return default if offline
    return StreakInfo(currentStreak: 0, longestStreak: 0);
  }

  // ============ Meal Entries ============

  /// Mark meal as consumed - offline-first
  Future<void> markMealAsConsumed(
    int entryId, {
    bool isConsumed = true,
    DateTime? consumedAt,
  }) async {
    final token = await _captureOwnedSessionToken();
    if (token == null) {
      throw Exception('User not authenticated');
    }

    final db = _localDb.database;

    final localEntry = await _resolveOwnedMealEntry(db, entryId, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }
    if (localEntry == null) {
      throw Exception('Meal entry not found');
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      localEntry.isConsumed = isConsumed;
      localEntry.consumedAt =
          isConsumed ? (consumedAt ?? DateTime.now()) : null;
      localEntry.lastModifiedLocal = DateTime.now().toUtc();
      localEntry.isSynced = false;
      if (localEntry.serverId != null) {
        localEntry.syncStatus = 'pending_update';
      }
      await db.localMealEntrys.put(localEntry);

      // The entry's inclusion in the meal log's consumed totals just
      // changed - reconcile from source entries so the full entry total is
      // included/removed exactly once, regardless of how many times
      // consumed is toggled.
      await _reconcileMealLogConsumedTotals(db, localEntry.mealLogLocalId);
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    // Sync to API immediately (not background) so dashboard refresh gets updated data
    if (_connectivity.isOnline && localEntry.serverId != null) {
      // Captured fresh, right here, rather than reusing the earlier
      // `token` - this call happens after the writeTxn's own await gap,
      // and a full SessionRequestContext (pinned JWT + cancel token) is
      // needed to bind the HTTP call, not just the UserSessionToken.
      final context = await _sessionCoordinator.captureContext();
      if (context != null) {
        try {
          await _apiService.put<void>(
            ApiConfig.mealEntryConsume(localEntry.serverId!),
            data: {
              'isConsumed': isConsumed,
              if (consumedAt != null)
                'consumedAt': consumedAt.toIso8601String(),
            },
            sessionContext: context,
          );
          debugPrint('✅ Synced meal consumed status to API');
        } on SessionStaleException {
          // Expected lifecycle outcome - local change is saved, will sync
          // later under whichever session is current then.
        } on RequestCancelledException {
          // Same treatment as SessionStaleException.
        } catch (e) {
          debugPrint('⚠️ Failed to sync meal consumed status: $e');
          // Local change is saved, will sync later
        }
      }
    }
  }

  /// Clear all food for today
  Future<MealLog> clearAllFood(int mealLogId) async {
    final token = await _captureOwnedSessionToken();
    if (token == null) {
      throw Exception('User not authenticated');
    }

    final db = _localDb.database;

    final localLog = await _resolveOwnedMealLog(db, mealLogId, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }
    if (localLog == null) {
      throw Exception('Meal log not found');
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      // Get all entries for this log
      final entries =
          await db.localMealEntrys
              .filter()
              .mealLogLocalIdEqualTo(localLog.localId)
              .findAll();

      for (final entry in entries) {
        // Delete all food items
        await db.localFoodItems
            .filter()
            .mealEntryLocalIdEqualTo(entry.localId)
            .deleteAll();

        // Reset entry totals
        entry.totalCalories = 0;
        entry.totalProtein = 0;
        entry.totalCarbohydrates = 0;
        entry.totalFat = 0;
        entry.isConsumed = false;
        entry.consumedAt = null;
        entry.lastModifiedLocal = DateTime.now().toUtc();
        entry.isSynced = false;
        if (entry.serverId != null) {
          entry.syncStatus = 'pending_update';
        }
        await db.localMealEntrys.put(entry);
      }

      // Reset log totals
      localLog.totalCalories = 0;
      localLog.totalProtein = 0;
      localLog.totalCarbohydrates = 0;
      localLog.totalFat = 0;
      localLog.lastModifiedLocal = DateTime.now().toUtc();
      localLog.isSynced = false;
      if (localLog.serverId != null) {
        localLog.syncStatus = 'pending_update';
      }
      await db.localMealLogs.put(localLog);
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    debugPrint('🗑️ Cleared all food locally');

    if (_connectivity.isOnline && localLog.serverId != null) {
      _backgroundSync(
        (context) => _dispatchBackgroundHttp(
          () => _apiService.post<Map<String, dynamic>>(
            ApiConfig.mealLogClear(localLog.serverId!),
            sessionContext: context,
          ),
        ),
        'Synced clear all food',
      );
    }

    return await _localMealLogToMealLogWithEntries(db, localLog);
  }

  // ============ Food Item Operations ============

  /// Add a food item to a meal entry - offline-first
  Future<FoodItem> addFoodItem(FoodItem foodItem) async {
    final token = await _captureOwnedSessionToken();
    if (token == null) {
      throw Exception('User not authenticated');
    }

    final db = _localDb.database;

    // Find the parent meal entry, owned by the captured user
    final parentEntry = await _resolveOwnedMealEntry(
      db,
      foodItem.mealEntryId,
      token,
    );
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }
    if (parentEntry == null) {
      throw Exception('Meal entry not found');
    }

    // Create local food item
    final localFoodItem = LocalFoodItem(
      serverId: null,
      mealEntryLocalId: parentEntry.localId,
      mealEntryServerId: parentEntry.serverId,
      foodTemplateId: foodItem.foodTemplateId,
      name: foodItem.name,
      brand: foodItem.brand,
      quantity: foodItem.quantity,
      servingSize: foodItem.servingSize,
      servingUnit: foodItem.servingUnit,
      calories: foodItem.calories,
      protein: foodItem.protein,
      carbohydrates: foodItem.carbohydrates,
      fat: foodItem.fat,
      fiber: foodItem.fiber,
      sugar: foodItem.sugar,
      sodium: foodItem.sodium,
      createdAt: DateTime.now().toUtc(),
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime.now().toUtc(),
    );

    int insertedId = 0;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      insertedId = await db.localFoodItems.put(localFoodItem);

      // Update entry totals (status-independent)
      parentEntry.totalCalories += foodItem.calories;
      parentEntry.totalProtein += foodItem.protein;
      parentEntry.totalCarbohydrates += foodItem.carbohydrates;
      parentEntry.totalFat += foodItem.fat;
      parentEntry.lastModifiedLocal = DateTime.now().toUtc();
      parentEntry.isSynced = false;
      if (parentEntry.serverId != null) {
        parentEntry.syncStatus = 'pending_update';
      }
      await db.localMealEntrys.put(parentEntry);

      // Reconcile the parent meal log's consumed-only totals from all
      // current entries.
      await _reconcileMealLogConsumedTotals(db, parentEntry.mealLogLocalId);
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    debugPrint('✅ Added food item locally: ${foodItem.name}');

    // Background sync if online
    if (_connectivity.isOnline && parentEntry.serverId != null) {
      _backgroundSync(
        (context) => _dispatchBackgroundHttp(
          () => _apiService.post<Map<String, dynamic>>(
            ApiConfig.foodItems,
            data: {
              'mealEntryId': parentEntry.serverId,
              'foodTemplateId': foodItem.foodTemplateId,
              'name': foodItem.name,
              'brand': foodItem.brand,
              'quantity': foodItem.quantity,
              'servingSize': foodItem.servingSize,
              'servingUnit': foodItem.servingUnit,
              'calories': foodItem.calories,
              'protein': foodItem.protein,
              'carbohydrates': foodItem.carbohydrates,
              'fat': foodItem.fat,
              'fiber': foodItem.fiber,
              'sugar': foodItem.sugar,
              'sodium': foodItem.sodium,
            },
            sessionContext: context,
          ),
        ),
        'Synced new food item',
      );
    }

    return FoodItem(
      id: insertedId,
      mealEntryId: parentEntry.localId,
      foodTemplateId: foodItem.foodTemplateId,
      name: foodItem.name,
      brand: foodItem.brand,
      quantity: foodItem.quantity,
      servingSize: foodItem.servingSize,
      servingUnit: foodItem.servingUnit,
      calories: foodItem.calories,
      protein: foodItem.protein,
      carbohydrates: foodItem.carbohydrates,
      fat: foodItem.fat,
      fiber: foodItem.fiber,
      sugar: foodItem.sugar,
      sodium: foodItem.sodium,
      createdAt: localFoodItem.createdAt,
    );
  }

  /// Update food item quantity - offline-first
  Future<void> updateFoodQuantity(int foodItemId, double quantity) async {
    final token = await _captureOwnedSessionToken();
    if (token == null) {
      throw Exception('User not authenticated');
    }

    final db = _localDb.database;

    final localItem = await _resolveOwnedFoodItem(db, foodItemId, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }
    if (localItem == null) {
      throw Exception('Food item not found');
    }

    // Calculate the difference for updating totals
    final oldQuantity = localItem.quantity;
    final quantityRatio = quantity / oldQuantity;

    final oldCalories = localItem.calories;
    final oldProtein = localItem.protein;
    final oldCarbs = localItem.carbohydrates;
    final oldFat = localItem.fat;

    final newCalories = oldCalories * quantityRatio;
    final newProtein = oldProtein * quantityRatio;
    final newCarbs = oldCarbs * quantityRatio;
    final newFat = oldFat * quantityRatio;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      // Update item
      localItem.quantity = quantity;
      localItem.calories = newCalories;
      localItem.protein = newProtein;
      localItem.carbohydrates = newCarbs;
      localItem.fat = newFat;
      localItem.lastModifiedLocal = DateTime.now().toUtc();
      localItem.isSynced = false;
      if (localItem.serverId != null) {
        localItem.syncStatus = 'pending_update';
      }
      await db.localFoodItems.put(localItem);

      // Update entry totals (status-independent)
      final parentEntry = await db.localMealEntrys.get(
        localItem.mealEntryLocalId,
      );
      if (parentEntry != null) {
        parentEntry.totalCalories += (newCalories - oldCalories);
        parentEntry.totalProtein += (newProtein - oldProtein);
        parentEntry.totalCarbohydrates += (newCarbs - oldCarbs);
        parentEntry.totalFat += (newFat - oldFat);
        parentEntry.lastModifiedLocal = DateTime.now().toUtc();
        parentEntry.isSynced = false;
        if (parentEntry.serverId != null) {
          parentEntry.syncStatus = 'pending_update';
        }
        await db.localMealEntrys.put(parentEntry);

        // Reconcile the parent meal log's consumed-only totals from all
        // current entries.
        await _reconcileMealLogConsumedTotals(db, parentEntry.mealLogLocalId);
      }
    });

    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception('User not authenticated');
    }

    debugPrint('✅ Updated food quantity locally');

    // Background sync if online
    if (_connectivity.isOnline && localItem.serverId != null) {
      _backgroundSync(
        (context) => _dispatchBackgroundHttp(
          () => _apiService.patch<void>(
            ApiConfig.foodItemQuantity(localItem.serverId!),
            data: {'quantity': quantity},
            sessionContext: context,
          ),
        ),
        'Synced food quantity update',
      );
    }
  }

  // ============ Nutrition Calculator ============

  /// Calculate personalized nutrition targets from user metrics and goal
  Future<CalculatedNutrition?> calculateNutritionFromMetrics({
    required String goalType,
    double? targetWeightChange,
    int? timeframeWeeks,
  }) async {
    if (!_connectivity.isOnline) {
      return null;
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.nutritionCalculate,
        data: {
          'goalType': goalType,
          if (targetWeightChange != null)
            'targetWeightChange': targetWeightChange,
          if (timeframeWeeks != null) 'timeframeWeeks': timeframeWeeks,
        },
      );

      return CalculatedNutrition.fromJson(response);
    } catch (e) {
      debugPrint('Failed to calculate nutrition: $e');
      return null;
    }
  }

  /// Calculate and save nutrition targets as active goal
  /// Throws [OfflineException] if not connected to internet
  Future<CalculatedNutrition?> calculateAndSaveNutrition({
    required String goalType,
    double? targetWeightChange,
    int? timeframeWeeks,
  }) async {
    if (!_connectivity.isOnline) {
      throw OfflineNutritionException(
        'Nutrition calculation requires an internet connection. '
        'Your goal has been saved and nutrition targets will be calculated when you\'re back online.',
      );
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.nutritionCalculateAndSave,
        data: {
          'goalType': goalType,
          if (targetWeightChange != null)
            'targetWeightChange': targetWeightChange,
          if (timeframeWeeks != null) 'timeframeWeeks': timeframeWeeks,
        },
      );

      final result = CalculatedNutrition.fromJson(response);

      // Update local cache with new goal. Best-effort: the goal was
      // already created successfully above, so a failure here (including
      // an expected SessionStaleException/RequestCancelledException from
      // a session change mid-refresh) must never turn this method's
      // overall success into a failure.
      if (result.nutritionGoalId != null) {
        try {
          final db = _localDb.database;
          final context = await _sessionCoordinator.captureContext();
          if (context != null) {
            await _syncNutritionGoalFromServer(db, context);
          }
        } on SessionStaleException {
          // Expected lifecycle outcome - not a failure, nothing to log.
        } on RequestCancelledException {
          // Same treatment as SessionStaleException.
        } catch (e) {
          debugPrint('⚠️ Failed to refresh cached nutrition goal: $e');
        }
      }

      return result;
    } on DioException catch (e) {
      // Check for missing metrics error (400 with specific code)
      if (e.response?.statusCode == 400) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> &&
            (data['code'] == 'MISSING_WEIGHT' ||
                data['code'] == 'MISSING_HEIGHT')) {
          throw MissingMetricsException.fromJson(data);
        }
      }
      debugPrint('Failed to calculate and save nutrition: $e');
      return null;
    } catch (e) {
      debugPrint('Failed to calculate and save nutrition: $e');
      return null;
    }
  }

  /// Get available activity levels
  Future<List<ActivityLevelOption>> getActivityLevels() async {
    if (_connectivity.isOnline) {
      try {
        final response = await _apiService.get<List<dynamic>>(
          ApiConfig.activityLevels,
        );
        return response
            .map(
              (json) =>
                  ActivityLevelOption.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      } catch (e) {
        debugPrint('Failed to fetch activity levels: $e');
      }
    }

    // Return default activity levels if offline
    return [
      ActivityLevelOption(
        value: 'Sedentary',
        label: 'Sedentary',
        description: 'Little or no exercise, desk job',
      ),
      ActivityLevelOption(
        value: 'LightlyActive',
        label: 'Lightly Active',
        description: 'Light exercise 1-3 days/week',
      ),
      ActivityLevelOption(
        value: 'ModeratelyActive',
        label: 'Moderately Active',
        description: 'Moderate exercise 3-5 days/week',
      ),
      ActivityLevelOption(
        value: 'VeryActive',
        label: 'Very Active',
        description: 'Hard exercise 6-7 days/week',
      ),
      ActivityLevelOption(
        value: 'ExtremelyActive',
        label: 'Extremely Active',
        description: 'Very hard exercise, physical job',
      ),
    ];
  }

  // ============ AI Food Alternatives ============

  /// Get AI-powered food alternatives
  Future<List<FoodAlternative>> getFoodAlternatives({
    required String foodName,
    required double calories,
    required double protein,
    required double carbohydrates,
    required double fat,
  }) async {
    if (!_connectivity.isOnline) {
      return [];
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatFoodSuggestion,
        data: {
          'foodName': foodName,
          'calories': calories,
          'protein': protein,
          'carbohydrates': carbohydrates,
          'fat': fat,
        },
      );

      final alternatives = response['alternatives'] as List<dynamic>? ?? [];
      return alternatives
          .map((alt) => FoodAlternative.fromJson(alt as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Failed to get food alternatives: $e');
      return [];
    }
  }
}

/// Model for AI-suggested food alternatives
class FoodAlternative {
  final String name;
  final String? brand;
  final double servingSize;
  final String servingUnit;
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;
  final String? reason;
  final String? category;

  FoodAlternative({
    required this.name,
    this.brand,
    required this.servingSize,
    required this.servingUnit,
    required this.calories,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
    this.reason,
    this.category,
  });

  factory FoodAlternative.fromJson(Map<String, dynamic> json) {
    return FoodAlternative(
      name: json['name'] as String,
      brand: json['brand'] as String?,
      servingSize: (json['servingSize'] as num?)?.toDouble() ?? 100,
      servingUnit: json['servingUnit'] as String? ?? 'g',
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbohydrates: (json['carbohydrates'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      reason: json['reason'] as String?,
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'brand': brand,
    'servingSize': servingSize,
    'servingUnit': servingUnit,
    'calories': calories,
    'protein': protein,
    'carbohydrates': carbohydrates,
    'fat': fat,
    'reason': reason,
    'category': category,
  };
}

/// Model for calculated nutrition targets
class CalculatedNutrition {
  final int? nutritionGoalId;
  final double dailyCalories;
  final double dailyProtein;
  final double dailyCarbohydrates;
  final double dailyFat;
  final double dailyFiber;
  final double dailyWater;
  final double bmr;
  final double tdee;
  final double calorieAdjustment;
  final double expectedWeeklyWeightChange;
  final String explanation;
  final String? warning;
  final String? recommendation;
  final UserMetricsSummary? userMetrics;

  CalculatedNutrition({
    this.nutritionGoalId,
    required this.dailyCalories,
    required this.dailyProtein,
    required this.dailyCarbohydrates,
    required this.dailyFat,
    required this.dailyFiber,
    required this.dailyWater,
    required this.bmr,
    required this.tdee,
    required this.calorieAdjustment,
    required this.expectedWeeklyWeightChange,
    required this.explanation,
    this.warning,
    this.recommendation,
    this.userMetrics,
  });

  /// Returns true if there's a warning about aggressive targets
  bool get hasWarning => warning != null && warning!.isNotEmpty;

  factory CalculatedNutrition.fromJson(Map<String, dynamic> json) {
    return CalculatedNutrition(
      nutritionGoalId: json['nutritionGoalId'] as int?,
      dailyCalories: (json['dailyCalories'] as num).toDouble(),
      dailyProtein: (json['dailyProtein'] as num).toDouble(),
      dailyCarbohydrates: (json['dailyCarbohydrates'] as num).toDouble(),
      dailyFat: (json['dailyFat'] as num).toDouble(),
      dailyFiber: (json['dailyFiber'] as num?)?.toDouble() ?? 25,
      dailyWater: (json['dailyWater'] as num?)?.toDouble() ?? 2000,
      bmr: (json['bmr'] as num).toDouble(),
      tdee: (json['tdee'] as num).toDouble(),
      calorieAdjustment: (json['calorieAdjustment'] as num).toDouble(),
      expectedWeeklyWeightChange:
          (json['expectedWeeklyWeightChange'] as num).toDouble(),
      explanation: json['explanation'] as String? ?? '',
      warning: json['warning'] as String?,
      recommendation: json['recommendation'] as String?,
      userMetrics:
          json['userMetrics'] != null
              ? UserMetricsSummary.fromJson(
                json['userMetrics'] as Map<String, dynamic>,
              )
              : null,
    );
  }
}

/// Summary of user metrics used in calculation
class UserMetricsSummary {
  final double weightKg;
  final double weightLbs;
  final double heightCm;
  final int age;
  final String gender;
  final String activityLevel;

  UserMetricsSummary({
    required this.weightKg,
    required this.weightLbs,
    required this.heightCm,
    required this.age,
    required this.gender,
    required this.activityLevel,
  });

  factory UserMetricsSummary.fromJson(Map<String, dynamic> json) {
    return UserMetricsSummary(
      weightKg: (json['weightKg'] as num).toDouble(),
      weightLbs: (json['weightLbs'] as num).toDouble(),
      heightCm: (json['heightCm'] as num).toDouble(),
      age: json['age'] as int,
      gender: json['gender'] as String? ?? '',
      activityLevel: json['activityLevel'] as String? ?? '',
    );
  }
}

/// Activity level option for dropdown
class ActivityLevelOption {
  final String value;
  final String label;
  final String description;

  ActivityLevelOption({
    required this.value,
    required this.label,
    required this.description,
  });

  factory ActivityLevelOption.fromJson(Map<String, dynamic> json) {
    return ActivityLevelOption(
      value: json['value'] as String,
      label: json['label'] as String,
      description: json['description'] as String? ?? '',
    );
  }
}

/// Exception thrown when nutrition calculation is attempted offline
class OfflineNutritionException implements Exception {
  final String message;

  OfflineNutritionException(this.message);

  @override
  String toString() => message;
}

/// Exception thrown when required body metrics are missing
class MissingMetricsException implements Exception {
  final String message;
  final String code;
  final String action;
  final List<String> missingFields;

  MissingMetricsException({
    required this.message,
    required this.code,
    this.action = 'GO_TO_BODY_METRICS',
    this.missingFields = const [],
  });

  @override
  String toString() => message;

  factory MissingMetricsException.fromJson(Map<String, dynamic> json) {
    return MissingMetricsException(
      message: json['message'] as String? ?? 'Missing required body metrics',
      code: json['code'] as String? ?? 'MISSING_METRICS',
      action: json['action'] as String? ?? 'GO_TO_BODY_METRICS',
      missingFields:
          (json['missingFields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

/// Combined dashboard data with goal and progress
class NutritionDashboardData {
  final DateTime date;
  final NutritionGoal? goal;
  final DailyNutritionProgress progress;

  NutritionDashboardData({
    required this.date,
    this.goal,
    required this.progress,
  });
}
