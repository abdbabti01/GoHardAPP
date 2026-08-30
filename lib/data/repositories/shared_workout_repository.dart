import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/shared_workout.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../local/services/local_database_service.dart';

/// Repository for community shared workouts with offline caching.
///
/// ## Session/ownership model
///
/// Every public asynchronous operation below captures a
/// [SessionRequestContext] via [_sessionCoordinator] at operation entry
/// (never after an internal `await`), and uses `context.epochToken.userId`
/// as the sole authoritative user for the remainder of that operation -
/// never a later, independently re-read `AuthService.getUserId()`. A `null`
/// capture (logged out, or the session changed while the JWT read was in
/// flight) follows the not-found/unauthenticated convention each method
/// already used: `[]` for the list reads, `Exception('No authenticated
/// user')` for the mutations that previously threw unconditionally on
/// failure.
///
/// Every [ApiService] call this repository makes - all seven of them, every
/// one a foreground call - is bound to that captured context via
/// `sessionContext:`, so it carries the pinned JWT captured at entry rather
/// than the live token, and can never be dispatched after the session that
/// started it has ended (see [ApiService]'s own class doc comment). The
/// detached feed-cache write scheduled by [getSharedWorkouts] receives the
/// exact context captured at that public entry point - never a context
/// (re)captured inside the closure - so it stays bound to the session that
/// scheduled it.
///
/// ## Cache ownership
///
/// [SharedWorkout.sharedByUserId] is the workout's author and is identical
/// on every device that caches the row; it can never identify the
/// authenticated device user a personalized response ([isLikedByCurrentUser]
/// / [isSavedByCurrentUser]) was built for. [SharedWorkout.cachedForUserId]
/// carries that, always stamped from `context.epochToken.userId` -
/// never from response JSON, never from a live `AuthService` read.
///
/// Every local read is scoped to `cachedForUserId == context.userId`, so a
/// legacy (`null`-owner) row and another user's row are both invisible to
/// an authenticated reader. The collection is keyed by the server ID, so a
/// valid full response for the current user atomically replaces a legacy or
/// foreign-owned row rather than coexisting with it; a stale response for a
/// prior session never reaches the write because every write is preceded by
/// the checkpoint sequence below. A partial toggle acknowledgment
/// ([toggleLike] / [toggleSave]) only ever mutates a row already owned by
/// the captured user, and never creates one.
///
/// ## Transaction/logout race protection
///
/// [_writeFullResponse], [_persistFeedCache], [_applyToggleAck] and the
/// inline delete transaction are the only ways this repository writes to
/// Isar, and all apply the same checkpoint shape: an epoch recheck
/// immediately after the HTTP response, again immediately before entering
/// `writeTxn`, again as the first statement inside `writeTxn`, a fresh
/// re-read of the target row(s) by stable server ID inside that same
/// transaction, and once more by the caller immediately after the
/// transaction returns before reporting success. This guarantees a logout
/// landing anywhere in that window - including while Isar's write lock is
/// being awaited, and including after `LocalDatabaseService.clearAll()` has
/// already run - never lets a write land against a foreign/replaced row and
/// never resurrects a since-cleared user's data.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures: reads
/// convert them to their empty result, mutations convert them to a silent
/// no-op (toggles/delete) or this repository's [_unauthenticated] outcome
/// (share), and none are logged as an ordinary failure or retried.
class SharedWorkoutRepository {
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

  SharedWorkoutRepository(
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
  // One hook per checkpoint, mirroring ChatRepository/RunningRepository's
  // identical seams. Each is @visibleForTesting, defaults to null, and is
  // never assigned outside test code - production control flow/performance
  // are unaffected.
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

  /// Fired immediately after a FOREGROUND HTTP call's own post-response
  /// epoch checkpoint passes, right before touching Isar. Lets a test prove
  /// that checkpoint rejects and returns before ever reaching the write,
  /// rather than relying on a later, structurally-shadowing check inside
  /// the write helper to produce the same externally-observable outcome.
  @visibleForTesting
  Future<void> Function()? afterForegroundHttpResponseForTesting;

  Future<void> _runTestHook(Future<void> Function()? hook) async {
    if (hook != null) {
      await hook();
    }
  }

  /// Fired synchronously, exactly once per [_backgroundSync] call, with the
  /// Future that completes once THAT SPECIFIC detached operation has fully
  /// settled - after its cache write and any guarded stale exit inside
  /// [operation] have all finished (it never rejects: the same
  /// success/error handling [_backgroundSync] always applies runs first, so
  /// this always completes, never throws). Tests use it to await
  /// deterministic completion of detached work instead of guessing with a
  /// delay.
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
  /// ChatRepository/RunningRepository's identical helper.
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

  // ============ Public operations ============

  /// Get all shared workouts from the community (friends only by default).
  ///
  /// Online: fetches fresh data from the server (bound to the captured
  /// session) and returns it directly, exactly as before this fix, while
  /// persisting it to the current user's cache on a detached, deterministic
  /// background operation. Offline / on error: returns this user's own
  /// cached rows only.
  Future<List<SharedWorkout>> getSharedWorkouts({
    String? category,
    String? difficulty,
    bool friendsOnly = true,
    int? limit = 50,
  }) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return [];
    final token = context.epochToken;
    final Isar db = _localDb.database;

    if (_connectivity.isOnline) {
      try {
        final workouts = await _fetchSharedWorkoutsFromServer(
          context,
          category: category,
          difficulty: difficulty,
          friendsOnly: friendsOnly,
          limit: limit,
        );

        // Checkpoint: post-HTTP, before scheduling any follow-up work.
        if (!_sessionEpoch.isCurrent(token)) return [];

        _backgroundSync(
          () => _persistFeedCache(db, context, workouts),
          'Shared workout cache updated',
        );

        return workouts;
      } on SessionStaleException {
        return [];
      } on RequestCancelledException {
        return [];
      } catch (e) {
        debugPrint('⚠️ Server fetch failed, using cache: $e');
        // Fall through to this same user's cache below.
      }
    }

    if (!_sessionEpoch.isCurrent(token)) return [];
    return _getLocalSharedWorkouts(
      db,
      token.userId,
      category: category,
      difficulty: difficulty,
      limit: limit,
    );
  }

  /// Get shared workouts created by a specific user.
  Future<List<SharedWorkout>> getSharedWorkoutsByUser(int userId) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return [];
    return _sharedWorkoutsByUser(context, userId);
  }

  /// Get shared workouts created by the current authenticated user. Uses
  /// the captured `context.epochToken.userId` for BOTH the request target
  /// and the cache-owner scope - never a fresh `AuthService.getUserId()`
  /// after the capture - and passes that same context into the shared
  /// helper rather than letting it recapture.
  Future<List<SharedWorkout>> getMySharedWorkouts() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      debugPrint('⚠️ Cannot get my shared workouts: not authenticated');
      return [];
    }
    return _sharedWorkoutsByUser(context, context.epochToken.userId);
  }

  /// Share a workout to the community.
  Future<SharedWorkout> shareWorkout({
    required int originalId,
    required String type, // 'session' or 'template'
    required String workoutName,
    String? description,
    required String exercisesJson,
    required int duration,
    required String category,
    String? difficulty,
  }) async {
    final context = await _requireOnlineContext(
      'Cannot share workout while offline',
    );
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final payload = SharedWorkout(
      originalId: originalId,
      type: type,
      // Author identity. The server overwrites SharedByUserId from the JWT
      // and derives the display name from the loaded User navigation
      // property (see GoHardAPI SharedWorkoutsController.ShareWorkout), so
      // neither field in the request body is trusted - the placeholder
      // name is never persisted or shown.
      sharedByUserId: token.userId,
      sharedByUserName: 'Unknown',
      workoutName: workoutName,
      description: description,
      exercisesJson: exercisesJson,
      duration: duration,
      category: category,
      difficulty: difficulty,
      sharedAt: DateTime.now(),
    );

    final Map<String, dynamic> data;
    try {
      data = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.sharedWorkouts,
        data: payload.toJson(),
        sessionContext: context,
      );
    } on SessionStaleException {
      throw Exception(_unauthenticated);
    } on RequestCancelledException {
      throw Exception(_unauthenticated);
    } catch (e) {
      debugPrint('Error sharing workout: $e');
      rethrow;
    }

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    await _runTestHook(afterForegroundHttpResponseForTesting);

    final created = SharedWorkoutJson.fromJson(data);
    await _writeFullResponse(db, context, [created]);

    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    return created;
  }

  /// Toggle like on a shared workout.
  Future<void> toggleLike(int sharedWorkoutId, bool isLiked) async {
    final context = await _requireOnlineContext(
      'Cannot like/unlike while offline',
    );
    final token = context.epochToken;
    final Isar db = _localDb.database;

    try {
      await _apiService.post(
        '${ApiConfig.sharedWorkouts}/$sharedWorkoutId/like',
        data: {},
        sessionContext: context,
      );
    } on SessionStaleException {
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      debugPrint('Error toggling like: $e');
      rethrow;
    }

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;
    await _runTestHook(afterForegroundHttpResponseForTesting);

    await _applyToggleAck(db, context, sharedWorkoutId, (row) {
      row.isLikedByCurrentUser = isLiked;
      row.likeCount += isLiked ? 1 : -1;
    });
  }

  /// Toggle save on a shared workout.
  Future<void> toggleSave(int sharedWorkoutId, bool isSaved) async {
    final context = await _requireOnlineContext(
      'Cannot save/unsave while offline',
    );
    final token = context.epochToken;
    final Isar db = _localDb.database;

    try {
      await _apiService.post(
        '${ApiConfig.sharedWorkouts}/$sharedWorkoutId/save',
        data: {},
        sessionContext: context,
      );
    } on SessionStaleException {
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      debugPrint('Error toggling save: $e');
      rethrow;
    }

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;
    await _runTestHook(afterForegroundHttpResponseForTesting);

    await _applyToggleAck(db, context, sharedWorkoutId, (row) {
      row.isSavedByCurrentUser = isSaved;
      row.saveCount += isSaved ? 1 : -1;
    });
  }

  /// Get saved workouts for the current user.
  Future<List<SharedWorkout>> getSavedWorkouts() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) return [];
    final token = context.epochToken;
    final Isar db = _localDb.database;

    if (!_connectivity.isOnline) {
      final rows =
          await db.sharedWorkouts
              .filter()
              .cachedForUserIdEqualTo(token.userId)
              .and()
              .isSavedByCurrentUserEqualTo(true)
              .findAll();
      if (!_sessionEpoch.isCurrent(token)) return [];
      rows.sort((a, b) => b.sharedAt.compareTo(a.sharedAt));
      return rows;
    }

    final List<dynamic> data;
    try {
      data = await _apiService.get<List<dynamic>>(
        '${ApiConfig.sharedWorkouts}/saved',
        sessionContext: context,
      );
    } on SessionStaleException {
      return [];
    } on RequestCancelledException {
      return [];
    } catch (e) {
      debugPrint('Error fetching saved workouts: $e');
      rethrow;
    }

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return [];
    await _runTestHook(afterForegroundHttpResponseForTesting);

    final workouts =
        data
            .map(
              (json) =>
                  SharedWorkoutJson.fromJson(json as Map<String, dynamic>),
            )
            .toList();

    await _writeFullResponse(db, context, workouts);
    if (!_sessionEpoch.isCurrent(token)) return [];
    return workouts;
  }

  /// Delete a shared workout (only if created by the current user).
  Future<void> deleteSharedWorkout(int sharedWorkoutId) async {
    final context = await _requireOnlineContext('Cannot delete while offline');
    final token = context.epochToken;
    final Isar db = _localDb.database;

    try {
      await _apiService.delete(
        '${ApiConfig.sharedWorkouts}/$sharedWorkoutId',
        sessionContext: context,
      );
    } on SessionStaleException {
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      debugPrint('Error deleting shared workout: $e');
      rethrow;
    }

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;
    await _runTestHook(afterForegroundHttpResponseForTesting);

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final row = await db.sharedWorkouts.get(sharedWorkoutId);
      // Never delete a legacy (null-owner) or another cache owner's row.
      if (row == null || row.cachedForUserId != token.userId) return;
      await db.sharedWorkouts.delete(sharedWorkoutId);
    });

    await _runTestHook(afterWriteTxnForTesting);
  }

  // === PRIVATE HELPERS ===

  /// Shared implementation for [getSharedWorkoutsByUser] and
  /// [getMySharedWorkouts]. Never recaptures a context - it uses the one
  /// passed in, and the offline branch scopes the cache read to
  /// `cachedForUserId == context.userId` AND `sharedByUserId == userId`.
  Future<List<SharedWorkout>> _sharedWorkoutsByUser(
    SessionRequestContext context,
    int userId,
  ) async {
    final token = context.epochToken;
    final Isar db = _localDb.database;

    if (!_connectivity.isOnline) {
      final workouts =
          await db.sharedWorkouts
              .filter()
              .cachedForUserIdEqualTo(token.userId)
              .and()
              .sharedByUserIdEqualTo(userId)
              .findAll();
      if (!_sessionEpoch.isCurrent(token)) return [];
      workouts.sort((a, b) => b.sharedAt.compareTo(a.sharedAt));
      return workouts;
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        '${ApiConfig.sharedWorkouts}/user/$userId',
        sessionContext: context,
      );
      if (!_sessionEpoch.isCurrent(token)) return [];
      return data
          .map(
            (json) => SharedWorkoutJson.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on SessionStaleException {
      return [];
    } on RequestCancelledException {
      return [];
    } catch (e) {
      debugPrint('Error fetching user shared workouts: $e');
      rethrow;
    }
  }

  /// Fetch shared workouts directly from the server, bound to [context].
  Future<List<SharedWorkout>> _fetchSharedWorkoutsFromServer(
    SessionRequestContext context, {
    String? category,
    String? difficulty,
    bool friendsOnly = true,
    int? limit,
  }) async {
    await _runTestHook(beforeBackgroundHttpDispatchForTesting);

    var endpoint = ApiConfig.sharedWorkouts;
    final queryParams = <String>[];

    if (category != null) queryParams.add('category=$category');
    if (difficulty != null) queryParams.add('difficulty=$difficulty');
    queryParams.add('friendsOnly=$friendsOnly');
    if (limit != null) queryParams.add('limit=$limit');

    if (queryParams.isNotEmpty) {
      endpoint += '?${queryParams.join('&')}';
    }

    final data = await _apiService.get<List<dynamic>>(
      endpoint,
      sessionContext: context,
    );
    return data
        .map((json) => SharedWorkoutJson.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Detached feed-cache write. Receives the exact [context] captured by
  /// [getSharedWorkouts] - never recaptures - and applies the class doc
  /// comment's checkpoint shape. The sweep of rows no longer present on the
  /// server is scoped to `cachedForUserId == token.userId`, so a stale
  /// operation can neither delete another user's rows nor resurrect a
  /// since-cleared user's rows.
  Future<void> _persistFeedCache(
    Isar db,
    SessionRequestContext context,
    List<SharedWorkout> workouts,
  ) async {
    final token = context.epochToken;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    // Checkpoint: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      // Checkpoint: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(token)) return;

      final serverIds = workouts.map((w) => w.id).toSet();

      // Sweep: only this cache owner's own non-saved rows that dropped off
      // the server response. Saved rows are retained (they may have left
      // the friend feed but the user still saved them) - within this same
      // cachedForUserId scope only.
      final cached =
          await db.sharedWorkouts
              .filter()
              .cachedForUserIdEqualTo(token.userId)
              .and()
              .isSavedByCurrentUserEqualTo(false)
              .findAll();
      for (final row in cached) {
        if (!serverIds.contains(row.id)) {
          await db.sharedWorkouts.delete(row.id);
        }
      }

      // Upsert every row from this user's complete response, stamped with
      // the captured cache owner. Fresh-reread by stable server ID: a
      // legacy (null) or foreign-owned row under the same ID is replaced,
      // because the collection holds only one row per server ID and this
      // is the current user's authoritative representation.
      for (final w in workouts) {
        final existing = await db.sharedWorkouts.get(w.id);
        if (existing != null &&
            existing.cachedForUserId != null &&
            existing.cachedForUserId != token.userId) {
          debugPrint(
            '♻️ Replacing shared workout ${w.id} cache row - previously '
            'owned by a different user',
          );
        }
        w.cachedForUserId = token.userId;
        await db.sharedWorkouts.put(w);
      }
    });

    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Writes a complete server representation (from the share or saved
  /// endpoints) into this user's cache, stamping every row with the
  /// captured cache owner. Same checkpoint shape as [_persistFeedCache],
  /// minus the sweep - these endpoints do not define the full feed.
  Future<void> _writeFullResponse(
    Isar db,
    SessionRequestContext context,
    List<SharedWorkout> workouts,
  ) async {
    final token = context.epochToken;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      for (final w in workouts) {
        final existing = await db.sharedWorkouts.get(w.id);
        if (existing != null &&
            existing.cachedForUserId != null &&
            existing.cachedForUserId != token.userId) {
          debugPrint(
            '♻️ Replacing shared workout ${w.id} cache row - previously '
            'owned by a different user',
          );
        }
        w.cachedForUserId = token.userId;
        await db.sharedWorkouts.put(w);
      }
    });

    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Applies a partial toggle acknowledgment to a single cached row. Only
  /// ever mutates a row whose `cachedForUserId` already matches the
  /// captured user; a missing, legacy, or foreign-owned row is left
  /// untouched (never created, never overwritten). Same checkpoint shape as
  /// every other write.
  Future<void> _applyToggleAck(
    Isar db,
    SessionRequestContext context,
    int sharedWorkoutId,
    void Function(SharedWorkout row) mutate,
  ) async {
    final token = context.epochToken;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final row = await db.sharedWorkouts.get(sharedWorkoutId);
      if (row == null || row.cachedForUserId != token.userId) return;
      mutate(row);
      await db.sharedWorkouts.put(row);
    });

    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Get shared workouts from this user's local cache, scoped to
  /// `cachedForUserId == userId`. Legacy null-owner rows and other users'
  /// rows are invisible. Category/difficulty filters are unchanged.
  Future<List<SharedWorkout>> _getLocalSharedWorkouts(
    Isar db,
    int userId, {
    String? category,
    String? difficulty,
    int? limit,
  }) async {
    List<SharedWorkout> results;

    if (category != null && difficulty != null) {
      results =
          await db.sharedWorkouts
              .filter()
              .cachedForUserIdEqualTo(userId)
              .and()
              .categoryEqualTo(category)
              .and()
              .difficultyEqualTo(difficulty)
              .findAll();
    } else if (category != null) {
      results =
          await db.sharedWorkouts
              .filter()
              .cachedForUserIdEqualTo(userId)
              .and()
              .categoryEqualTo(category)
              .findAll();
    } else if (difficulty != null) {
      results =
          await db.sharedWorkouts
              .filter()
              .cachedForUserIdEqualTo(userId)
              .and()
              .difficultyEqualTo(difficulty)
              .findAll();
    } else {
      results =
          await db.sharedWorkouts
              .filter()
              .cachedForUserIdEqualTo(userId)
              .findAll();
    }

    results.sort((a, b) => b.sharedAt.compareTo(a.sharedAt));

    if (limit != null && results.length > limit) {
      return results.sublist(0, limit);
    }

    return results;
  }
}

// Extension for SharedWorkout JSON serialization
extension SharedWorkoutJson on SharedWorkout {
  Map<String, dynamic> toJson() {
    return {
      'originalId': originalId,
      'type': type,
      'sharedByUserId': sharedByUserId,
      'sharedByUserName': sharedByUserName,
      'workoutName': workoutName,
      'description': description,
      'exercisesJson': exercisesJson,
      'duration': duration,
      'category': category,
      'difficulty': difficulty,
      'sharedAt': sharedAt.toIso8601String(),
    };
  }

  static SharedWorkout fromJson(Map<String, dynamic> json) {
    return SharedWorkout(
      id: json['id'] as int? ?? Isar.autoIncrement,
      originalId: json['originalId'] as int,
      type: json['type'] as String,
      sharedByUserId: json['sharedByUserId'] as int,
      sharedByUserName: json['sharedByUserName'] as String,
      workoutName: json['workoutName'] as String,
      description: json['description'] as String?,
      exercisesJson: json['exercisesJson'] as String,
      duration: json['duration'] as int,
      category: json['category'] as String,
      difficulty: json['difficulty'] as String?,
      likeCount: json['likeCount'] as int? ?? 0,
      saveCount: json['saveCount'] as int? ?? 0,
      commentCount: json['commentCount'] as int? ?? 0,
      isLikedByCurrentUser: json['isLikedByCurrentUser'] as bool? ?? false,
      isSavedByCurrentUser: json['isSavedByCurrentUser'] as bool? ?? false,
      sharedAt: DateTime.parse(json['sharedAt'] as String),
    );
  }
}
