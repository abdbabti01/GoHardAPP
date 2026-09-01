import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/exercise_template.dart';
import '../models/exercise_set.dart';
import '../services/api_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../local/services/local_database_service.dart';
import '../local/services/model_mapper.dart';
import '../local/models/local_session.dart';
import '../local/models/local_exercise_template.dart';
import '../local/models/local_exercise.dart';
import '../local/models/local_exercise_set.dart';

/// Repository for exercise and exercise template operations with offline
/// support.
///
/// ## Session ownership (exercise-set operations)
///
/// The four user-owned set operations - [getExerciseSets], [createExerciseSet],
/// [completeExerciseSet], [deleteExerciseSet] (and [updateExerciseSet]) -
/// capture exactly one [SessionRequestContext] via [_sessionCoordinator] at
/// method entry, before the first `await`, and:
///
/// - pass `sessionContext:` to every authenticated [ApiService] call they
///   make (including the nested refresh GET inside [getExerciseSets]), so the
///   request carries the JWT pinned at entry and the generation-scoped
///   `CancelToken` - never a live token, never dispatchable after logout;
/// - reuse that exact context for every follow-up call - the live token / user
///   id is never re-read;
/// - resolve the collision-free public id (see `ModelMapper.publicRowId` /
///   [_toApiSet]) through [_resolveOwnedSet] / [_resolveOwnedExercise]: a
///   POSITIVE input is interpreted ONLY as a server id (never a local id - no
///   positive-local fallback); a NEGATIVE input is decoded to `-localId` and
///   interpreted ONLY as a local id (server ids are never queried for it);
///   `0` is rejected. Only a match whose full parent chain
///   (`exerciseLocalId -> LocalExercise.sessionLocalId -> LocalSession.userId`)
///   is owned by the captured user is accepted; more than one owned server-id
///   match fails closed; a numerically-colliding foreign row is never returned;
/// - after resolution use `resolved.serverId` for every server endpoint and
///   `resolved.localId` for every Isar access - the raw numeric input is
///   never handed to `Isar.get()`, and a negative / local id is never sent to
///   the network;
/// - re-check [UserSessionEpoch.isCurrent] and re-walk the ownership chain
///   immediately before entering every acknowledgment `writeTxn`, as the first
///   statement inside it, immediately before the mutating call, and by
///   re-fetching the target fresh by its stable local id;
/// - treat every stale state - whether raised by [ApiService] or detected by
///   this repository itself (a post-await check, a pre-transaction check, the
///   first in-transaction check, a testing-hook gap) - as a typed
///   [SessionStaleException]: never returned as `[]` / `false` / an API object
///   / a local object / silent success, never entering the offline fallback,
///   never creating pending state. [RequestCancelledException] is likewise
///   always rethrown. `LogSetsProvider`'s session/generation guards drop both
///   without publishing;
/// - distinguish lifecycle staleness from same-session disappearance: if the
///   SAME still-valid session's target/parent is deleted or reassigned between
///   the server acknowledgment and the local write, the operation fails closed
///   with the repository's ordinary `Exception('Exercise[ set] not found')` and
///   never returns a publishable success object - EXCEPT that a DELETE whose
///   server call already succeeded treats a since-gone local row as
///   convergence and reports success.
///
/// A `null` capture (logged out / raced during the JWT read) is itself a stale
/// state -> [SessionStaleException], no HTTP, no Isar mutation.
///
/// This is deliberately the lightest correct mechanism: no `userId` column is
/// added to [LocalExercise] / [LocalExerciseSet] (ownership is already
/// resolvable through the stable parent chain), and `SyncService` /
/// `SessionRepository` are unchanged except for the shared collision-free
/// public-id encoding of offline exercises (`ModelMapper.publicRowId`).
///
/// ## Reference-data operations (intentionally unbound)
///
/// [getExerciseTemplates], [getExerciseTemplate], [getCategories] and
/// [getMuscleGroups] are left exactly as they were. The API's
/// `ExerciseTemplatesController` GET endpoints carry no `[Authorize]`
/// attribute, take no user identity, and return the same shared catalog for
/// every account; the only local rows they write are `LocalExerciseTemplate`
/// (unowned shared reference content that `SessionCleanupCoordinator`
/// deliberately preserves across logout). Binding them would only force a
/// wasted re-fetch of the same catalog for the next session.
///
/// ## Deferred
///
/// Uncertain-response create duplication (a POST that succeeds server-side but
/// whose response is lost -> local pending row -> `SyncService` re-POST) is
/// NOT solved here - it is an app-wide gap with no client operation id / no
/// server idempotency key, tracked as a separate investigation.
class ExerciseRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// `AuthProvider`, `SessionRepository`, `SyncService`, `LogSetsProvider`,
  /// etc. (see main.dart). Only `AuthProvider` calls activate()/invalidate();
  /// this repository only ever reads it via capture()/isCurrent().
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext]
  /// (pinned JWT + generation-scoped CancelToken) for every session-bound HTTP
  /// call. The SAME instance handed to every other consumer; never constructed
  /// privately.
  final SessionRequestCoordinator _sessionCoordinator;

  ExerciseRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  // ============ Test-only session-race seams ============
  //
  // Each is @visibleForTesting, defaults to null, and is never assigned
  // outside test code - production control flow / performance are unaffected.
  // They mirror the analogous hooks on SessionRepository / NutritionRepository.

  /// Awaited immediately before every acknowledgment `writeTxn` below (after
  /// the pre-txn epoch/owner recheck has already passed) - lets a test land a
  /// logout / parent deletion in the gap before Isar's write lock is taken.
  @visibleForTesting
  Future<void> Function()? beforeWriteTxnForTesting;

  /// Awaited as the first statement inside every acknowledgment `writeTxn`.
  @visibleForTesting
  Future<void> Function()? insideWriteTxnForTesting;

  Future<void> _runHook(Future<void> Function()? hook) async {
    if (hook != null) await hook();
  }

  // ============ Ownership resolution helpers ============

  Future<int?> _sessionOwnerOf(Isar db, int sessionLocalId) async {
    final session = await db.localSessions.get(sessionLocalId);
    return session?.userId;
  }

  Future<int?> _exerciseOwnerOf(Isar db, LocalExercise exercise) =>
      _sessionOwnerOf(db, exercise.sessionLocalId);

  Future<int?> _setOwnerOf(Isar db, LocalExerciseSet set) async {
    final exercise = await db.localExercises.get(set.exerciseLocalId);
    if (exercise == null) return null;
    return _exerciseOwnerOf(db, exercise);
  }

  /// Resolves a collision-free public exercise id (see `ModelMapper.publicRowId`)
  /// to a [LocalExercise] whose session parent is owned by [token.userId], or
  /// `null` if it cannot be resolved to an owned row.
  ///
  /// - `id == 0` -> `null` (never a valid public id).
  /// - `id < 0` -> decoded to `-id` and looked up ONLY by Isar local id; a
  ///   foreign or missing row -> `null`. Server ids are never queried.
  /// - `id > 0` -> looked up ONLY by server id; more than one owned match, or
  ///   none, -> `null`. There is NO fallback to a positive local id.
  Future<LocalExercise?> _resolveOwnedExercise(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    if (id == 0) return null;

    if (id < 0) {
      final row = await db.localExercises.get(
        ModelMapper.localIdFromPublicId(id),
      );
      if (!_sessionEpoch.isCurrent(token)) return null;
      if (row == null) return null;
      if (await _exerciseOwnerOf(db, row) != token.userId) return null;
      return row;
    }

    final byServerId =
        await db.localExercises.filter().serverIdEqualTo(id).findAll();
    if (!_sessionEpoch.isCurrent(token)) return null;
    final owned = <LocalExercise>[];
    for (final exercise in byServerId) {
      if (await _exerciseOwnerOf(db, exercise) == token.userId) {
        owned.add(exercise);
      }
    }
    return owned.length == 1 ? owned.first : null;
  }

  /// Same contract as [_resolveOwnedExercise], for a [LocalExerciseSet]
  /// through the full grandparent chain.
  Future<LocalExerciseSet?> _resolveOwnedSet(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    if (id == 0) return null;

    if (id < 0) {
      final row = await db.localExerciseSets.get(
        ModelMapper.localIdFromPublicId(id),
      );
      if (!_sessionEpoch.isCurrent(token)) return null;
      if (row == null) return null;
      if (await _setOwnerOf(db, row) != token.userId) return null;
      return row;
    }

    final byServerId =
        await db.localExerciseSets.filter().serverIdEqualTo(id).findAll();
    if (!_sessionEpoch.isCurrent(token)) return null;
    final owned = <LocalExerciseSet>[];
    for (final set in byServerId) {
      if (await _setOwnerOf(db, set) == token.userId) owned.add(set);
    }
    return owned.length == 1 ? owned.first : null;
  }

  /// Re-fetches [exerciseLocalId] fresh and confirms it is still owned by
  /// [token.userId] - used at acknowledgment time so a race that reassigns or
  /// deletes the parent between dispatch and write is caught.
  Future<LocalExercise?> _reacquireOwnedExercise(
    Isar db,
    int exerciseLocalId,
    UserSessionToken token,
  ) async {
    final exercise = await db.localExercises.get(exerciseLocalId);
    if (exercise == null) return null;
    if (await _exerciseOwnerOf(db, exercise) != token.userId) return null;
    return exercise;
  }

  int _publicExerciseId(LocalExercise e) =>
      ModelMapper.publicRowId(serverId: e.serverId, localId: e.localId);

  /// True only if [serverId] is a real (positive) server id. A legacy `0`
  /// sentinel or `null` means "not yet synced" - never sent to the server,
  /// never a PUT/PATCH/DELETE target.
  bool _hasServerId(int? serverId) => serverId != null && serverId > 0;

  /// Canonicalizes a legacy non-positive `serverId` / `exerciseServerId` (the
  /// pre-`ModelMapper.publicRowId` `0` sentinel) to `null` on a row this
  /// repository is about to persist, so a touched legacy row never keeps a
  /// non-positive server id: its `_toApiSet` public id stays `-localId`, its
  /// pending state stays `pending_create` (not `pending_update`), and
  /// `SyncService` treats it as a fresh CREATE rather than a `PUT /0`.
  void _canonicalizeLegacyServerIds(LocalExerciseSet s) {
    if (s.serverId != null && s.serverId! <= 0) s.serverId = null;
    if (s.exerciseServerId != null && s.exerciseServerId! <= 0) {
      s.exerciseServerId = null;
    }
  }

  // ============ Exercise Templates (reference data - unbound) ============

  /// Get all exercise templates with optional filtering.
  /// Offline-first: returns local cache, then tries to sync with server.
  Future<List<ExerciseTemplate>> getExerciseTemplates({
    String? category,
    String? muscleGroup,
    bool? isCustom,
  }) async {
    final Isar db = _localDb.database;

    if (_connectivity.isOnline) {
      try {
        final queryParams = <String, dynamic>{};
        if (category != null) queryParams['category'] = category;
        if (muscleGroup != null) queryParams['muscleGroup'] = muscleGroup;
        if (isCustom != null) queryParams['isCustom'] = isCustom;

        final data = await _apiService.get<List<dynamic>>(
          ApiConfig.exerciseTemplates,
          queryParameters: queryParams.isNotEmpty ? queryParams : null,
        );
        final apiTemplates =
            data
                .map(
                  (json) =>
                      ExerciseTemplate.fromJson(json as Map<String, dynamic>),
                )
                .toList();

        // Update local cache
        await db.writeTxn(() async {
          for (final apiTemplate in apiTemplates) {
            final localTemplate = ModelMapper.exerciseTemplateToLocal(
              apiTemplate,
              isSynced: true,
            );
            await db.localExerciseTemplates.put(localTemplate);
          }
        });

        debugPrint('✅ Cached ${apiTemplates.length} exercise templates');
        return apiTemplates;
      } catch (e) {
        debugPrint('⚠️ API failed, falling back to local cache: $e');
        return await _getLocalExerciseTemplates(
          db,
          category: category,
          muscleGroup: muscleGroup,
          isCustom: isCustom,
        );
      }
    } else {
      debugPrint('📴 Offline - returning cached exercise templates');
      return await _getLocalExerciseTemplates(
        db,
        category: category,
        muscleGroup: muscleGroup,
        isCustom: isCustom,
      );
    }
  }

  /// Get exercise templates from local database with optional filtering
  Future<List<ExerciseTemplate>> _getLocalExerciseTemplates(
    Isar db, {
    String? category,
    String? muscleGroup,
    bool? isCustom,
  }) async {
    // Get all local templates first
    List<LocalExerciseTemplate> localTemplates =
        await db.localExerciseTemplates.where().findAll();

    // Apply filters in memory
    if (category != null) {
      localTemplates =
          localTemplates.where((t) => t.category == category).toList();
    }
    if (muscleGroup != null) {
      localTemplates =
          localTemplates.where((t) => t.muscleGroup == muscleGroup).toList();
    }
    if (isCustom != null) {
      localTemplates =
          localTemplates.where((t) => t.isCustom == isCustom).toList();
    }

    return localTemplates
        .map((local) => ModelMapper.localToExerciseTemplate(local))
        .toList();
  }

  /// Get exercise template by ID
  Future<ExerciseTemplate> getExerciseTemplate(int id) async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.exerciseTemplateById(id),
    );
    return ExerciseTemplate.fromJson(data);
  }

  /// Get all available categories.
  /// Offline-first: returns distinct categories from local cache.
  Future<List<String>> getCategories() async {
    final Isar db = _localDb.database;

    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<List<dynamic>>(
          ApiConfig.exerciseTemplateCategories,
        );
        return data.map((e) => e.toString()).toList();
      } catch (e) {
        debugPrint('⚠️ API failed, using local categories: $e');
        return await _getLocalCategories(db);
      }
    } else {
      debugPrint('📴 Offline - returning cached categories');
      return await _getLocalCategories(db);
    }
  }

  Future<List<String>> _getLocalCategories(Isar db) async {
    final templates = await db.localExerciseTemplates.where().findAll();
    return templates
        .map((t) => t.category)
        .where((c) => c != null)
        .cast<String>()
        .toSet()
        .toList();
  }

  /// Get all available muscle groups.
  /// Offline-first: returns distinct muscle groups from local cache.
  Future<List<String>> getMuscleGroups() async {
    final Isar db = _localDb.database;

    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<List<dynamic>>(
          ApiConfig.exerciseTemplateMuscleGroups,
        );
        return data.map((e) => e.toString()).toList();
      } catch (e) {
        debugPrint('⚠️ API failed, using local muscle groups: $e');
        return await _getLocalMuscleGroups(db);
      }
    } else {
      debugPrint('📴 Offline - returning cached muscle groups');
      return await _getLocalMuscleGroups(db);
    }
  }

  Future<List<String>> _getLocalMuscleGroups(Isar db) async {
    final templates = await db.localExerciseTemplates.where().findAll();
    return templates
        .map((t) => t.muscleGroup)
        .where((m) => m != null)
        .cast<String>()
        .toSet()
        .toList();
  }

  // ============ Exercise Sets (user-owned - session bound) ============

  /// Maps a local set to the API [ExerciseSet], using `ModelMapper.publicRowId`
  /// for the collision-free public-id contract: a synced row -> its positive
  /// server id; an unsynced row -> `-localId`; never `0`.
  ExerciseSet _toApiSet(LocalExerciseSet s) => ExerciseSet(
    id: ModelMapper.publicRowId(serverId: s.serverId, localId: s.localId),
    exerciseId: ModelMapper.publicRowId(
      serverId: s.exerciseServerId,
      localId: s.exerciseLocalId,
    ),
    setNumber: s.setNumber,
    reps: s.reps,
    weight: s.weight,
    duration: s.duration,
    isCompleted: s.isCompleted,
    completedAt: s.completedAt,
    notes: s.notes,
  );

  List<ExerciseSet> _mapAndSort(Iterable<LocalExerciseSet> localSets) {
    final sets =
        localSets
            .where((s) => s.syncStatus != 'pending_delete')
            .map(_toApiSet)
            .toList();
    sets.sort((a, b) => a.setNumber.compareTo(b.setNumber));
    return sets;
  }

  Future<List<ExerciseSet>> _ownedLocalSets(
    Isar db,
    int exerciseLocalId,
  ) async {
    final localSets =
        await db.localExerciseSets
            .filter()
            .exerciseLocalIdEqualTo(exerciseLocalId)
            .findAll();
    return _mapAndSort(localSets);
  }

  /// Get exercise sets for an exercise.
  ///
  /// Offline-first: returns the owned local cache, then merges a server refresh
  /// when online. The refresh is non-destructive - it inserts server sets that
  /// are missing locally and updates rows that are already `synced`, but never
  /// overwrites a row carrying an unsynced local mutation and never deletes a
  /// row. Any repository-detected staleness throws [SessionStaleException]; a
  /// genuinely unresolvable / since-lost exercise fails closed with
  /// `Exception('Exercise not found')`; only an ordinary transport failure
  /// falls back to the local cache.
  Future<List<ExerciseSet>> getExerciseSets(int exerciseId) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final exercise = await _resolveOwnedExercise(db, exerciseId, token);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    if (exercise == null) {
      throw Exception('Exercise not found: $exerciseId');
    }

    final localView = await _ownedLocalSets(db, exercise.localId);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();

    if (!_connectivity.isOnline || !_hasServerId(exercise.serverId)) {
      return localView;
    }

    List<dynamic> data;
    try {
      data = await _apiService.get<List<dynamic>>(
        ApiConfig.exerciseSetsByExerciseId(exercise.serverId!),
        sessionContext: context,
      );
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      // Ordinary transport / server failure while the session is still
      // current: fall back to the owned local cache.
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      debugPrint('⚠️ API failed, using local sets: $e');
      return localView;
    }
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();

    final apiSets =
        data
            .map((json) => ExerciseSet.fromJson(json as Map<String, dynamic>))
            .toList();

    final owned = await _reacquireOwnedExercise(db, exercise.localId, token);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    if (owned == null) {
      // Parent vanished / reassigned mid-refresh while the session stayed
      // current - its cached sets are now orphaned; fail closed.
      throw Exception('Exercise not found: $exerciseId');
    }

    final ack = await _refreshCache(db, exercise.localId, apiSets, token);
    switch (ack) {
      case _Ack.applied:
        break;
      case _Ack.targetGone:
      case _Ack.ownershipLost:
        throw Exception('Exercise not found: $exerciseId');
    }

    final published = await _reacquireOwnedExercise(
      db,
      exercise.localId,
      token,
    );
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    if (published == null) throw Exception('Exercise not found: $exerciseId');
    return await _ownedLocalSets(db, exercise.localId);
  }

  Future<_Ack> _refreshCache(
    Isar db,
    int exerciseLocalId,
    List<ExerciseSet> apiSets,
    UserSessionToken token,
  ) async {
    await _runHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    late _Ack ack;
    await db.writeTxn(() async {
      await _runHook(insideWriteTxnForTesting);
      // Single mandated first-in-transaction epoch check; the parent is
      // re-fetched and re-owner-verified once here, then the loop only writes.
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      final reExercise = await db.localExercises.get(exerciseLocalId);
      if (reExercise == null) {
        ack = _Ack.targetGone;
        return;
      }
      if (await _exerciseOwnerOf(db, reExercise) != token.userId) {
        ack = _Ack.ownershipLost;
        return;
      }

      for (final apiSet in apiSets) {
        final existing =
            await db.localExerciseSets
                .filter()
                .serverIdEqualTo(apiSet.id)
                .findFirst();

        if (existing == null) {
          await db.localExerciseSets.put(
            ModelMapper.exerciseSetToLocal(
              apiSet,
              exerciseLocalId: reExercise.localId,
            ),
          );
          continue;
        }

        // Never reparent an existing row into this exercise.
        if (existing.exerciseLocalId != reExercise.localId) continue;
        // Preserve a row that carries an unsynced local mutation - a stale
        // refresh must not clobber a newer add/complete/delete.
        if (!existing.isSynced || existing.syncStatus != 'synced') continue;

        await db.localExerciseSets.put(
          ModelMapper.exerciseSetToLocal(
            apiSet,
            exerciseLocalId: reExercise.localId,
            localId: existing.localId,
          ),
        );
      }
      ack = _Ack.applied;
    });
    return ack;
  }

  /// Create a new exercise set.
  /// Offline-first: saves locally, syncs to server when online.
  Future<ExerciseSet> createExerciseSet(ExerciseSet exerciseSet) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final exercise = await _resolveOwnedExercise(
      db,
      exerciseSet.exerciseId,
      token,
    );
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    if (exercise == null) {
      throw Exception('Exercise not found: ${exerciseSet.exerciseId}');
    }

    if (_connectivity.isOnline && _hasServerId(exercise.serverId)) {
      Map<String, dynamic> data;
      try {
        // Normalize the parent id to the resolved exercise's server id - never
        // forward the ambiguous public/local input.
        final body = exerciseSet.toJson()..['exerciseId'] = exercise.serverId;
        data = await _apiService.post<Map<String, dynamic>>(
          ApiConfig.exerciseSets,
          data: body,
          sessionContext: context,
        );
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        if (!_sessionEpoch.isCurrent(token)) {
          throw const SessionStaleException();
        }
        debugPrint('⚠️ API failed, saving set locally: $e');
        return await _createLocalSet(db, exerciseSet, exercise, context);
      }
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();

      final apiSet = ExerciseSet.fromJson(data);
      final owned = await _reacquireOwnedExercise(db, exercise.localId, token);
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      if (owned == null) {
        // The server row was created, but the parent is gone / reassigned
        // while the session stayed current: fail closed - never return a
        // publishable set tied to a lost local parent.
        throw Exception('Exercise not found: ${_publicExerciseId(exercise)}');
      }

      final ack = await _cacheCreatedSet(db, exercise.localId, apiSet, token);
      switch (ack) {
        case _Ack.applied:
          debugPrint('✅ Created set on server');
          return apiSet;
        case _Ack.targetGone:
        case _Ack.ownershipLost:
          throw Exception('Exercise not found: ${_publicExerciseId(exercise)}');
      }
    }

    debugPrint('📴 Offline - saving set locally');
    return await _createLocalSet(db, exerciseSet, exercise, context);
  }

  Future<_Ack> _cacheCreatedSet(
    Isar db,
    int exerciseLocalId,
    ExerciseSet apiSet,
    UserSessionToken token,
  ) async {
    await _runHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    late _Ack ack;
    await db.writeTxn(() async {
      await _runHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      final reExercise = await db.localExercises.get(exerciseLocalId);
      if (reExercise == null) {
        ack = _Ack.targetGone;
        return;
      }
      if (await _exerciseOwnerOf(db, reExercise) != token.userId) {
        ack = _Ack.ownershipLost;
        return;
      }
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      await db.localExerciseSets.put(
        ModelMapper.exerciseSetToLocal(
          apiSet,
          exerciseLocalId: reExercise.localId,
        ),
      );
      ack = _Ack.applied;
    });
    return ack;
  }

  /// Create an exercise set in the local database under the resolved owned
  /// parent, re-verifying session/ownership before, inside, and immediately
  /// before the write.
  Future<ExerciseSet> _createLocalSet(
    Isar db,
    ExerciseSet exerciseSet,
    LocalExercise exercise,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    // ModelMapper.exerciseSetToLocal maps the caller's `id: 0` to a null
    // serverId, so the row's not-yet-synced state is unambiguous and
    // `_toApiSet` exposes `id == -localId`. Pass a positive parent server id
    // only - a legacy `serverId == 0` parent must not leak `exerciseServerId:
    // 0` onto the new child.
    final localSet = ModelMapper.exerciseSetToLocal(
      exerciseSet,
      exerciseLocalId: exercise.localId,
      exerciseServerId:
          _hasServerId(exercise.serverId) ? exercise.serverId : null,
      isSynced: false,
    );
    // `exerciseSetToLocal` falls back to `apiSet.exerciseId` when the explicit
    // `exerciseServerId` is null, so an offline / legacy-`0` parent leaves the
    // caller's negative public id (or `0`) on the row - canonicalize it away so
    // the child carries no bogus non-positive parent server id.
    _canonicalizeLegacyServerIds(localSet);

    int localId = 0;
    await _runHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    await db.writeTxn(() async {
      await _runHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      final reExercise = await db.localExercises.get(exercise.localId);
      if (reExercise == null) return; // parent gone -> localId stays 0
      if (await _exerciseOwnerOf(db, reExercise) != token.userId) return;
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      localId = await db.localExerciseSets.put(localSet);
    });

    if (localId == 0) {
      // Staleness always throws above, so this is a genuine parent-gone /
      // parent-reassigned while the session stayed current.
      throw Exception('Exercise not found: ${_publicExerciseId(exercise)}');
    }

    return _toApiSet(localSet);
  }

  /// Update an exercise set on the server (no local cache path today - the UI
  /// mutates sets only through [completeExerciseSet] / [deleteExerciseSet]).
  /// Still session-bound and owner-verified so it can never be an unbound
  /// authenticated mutation.
  Future<ExerciseSet> updateExerciseSet(int id, ExerciseSet exerciseSet) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSet = await _resolveOwnedSet(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    // Require both server ids: the row's own (the PUT target) and its parent's
    // (the FK the full-entity update would otherwise overwrite). Both are
    // present once a set is synced; a not-yet-synced set is not updatable here.
    if (localSet == null ||
        !_hasServerId(localSet.serverId) ||
        !_hasServerId(localSet.exerciseServerId)) {
      throw Exception('Exercise set not found: $id');
    }

    // The server's PUT requires `body.id == {path id}` and returns 204 No
    // Content on success (see ExerciseSetsController). Normalize the body ids
    // to the resolved row's server ids and do not parse a response body.
    final body =
        exerciseSet.toJson()
          ..['id'] = localSet.serverId
          ..['exerciseId'] = localSet.exerciseServerId;
    await _apiService.put<void>(
      ApiConfig.exerciseSetById(localSet.serverId!),
      data: body,
      sessionContext: context,
    );
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();

    // 204 carries no body: echo the requested state with the server ids.
    return ExerciseSet(
      id: localSet.serverId!,
      exerciseId: localSet.exerciseServerId!,
      setNumber: exerciseSet.setNumber,
      reps: exerciseSet.reps,
      weight: exerciseSet.weight,
      duration: exerciseSet.duration,
      isCompleted: exerciseSet.isCompleted,
      completedAt: exerciseSet.completedAt,
      notes: exerciseSet.notes,
    );
  }

  /// Mark an exercise set as complete.
  /// Offline-first: updates locally, syncs to server when online.
  Future<ExerciseSet> completeExerciseSet(int id) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSet = await _resolveOwnedSet(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    if (localSet == null) throw Exception('Exercise set not found: $id');
    final setLocalId = localSet.localId;

    if (_connectivity.isOnline && _hasServerId(localSet.serverId)) {
      try {
        // The server returns 204 No Content on success - `patch` maps that to
        // `null`. A null/empty body is SUCCESS here, never an error.
        await _apiService.patch<Map<String, dynamic>>(
          ApiConfig.exerciseSetComplete(localSet.serverId!),
          data: <String, dynamic>{},
          sessionContext: context,
        );
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        if (!_sessionEpoch.isCurrent(token)) {
          throw const SessionStaleException();
        }
        debugPrint('⚠️ Complete API failed, will sync later: $e');
        return _viewForAck(
          await _applyLocalComplete(db, setLocalId, token, markSynced: false),
          db,
          setLocalId,
          id,
        );
      }
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      return _viewForAck(
        await _applyLocalComplete(db, setLocalId, token, markSynced: true),
        db,
        setLocalId,
        id,
      );
    }

    debugPrint('✅ Set marked as complete locally');
    return _viewForAck(
      await _applyLocalComplete(db, setLocalId, token, markSynced: false),
      db,
      setLocalId,
      id,
    );
  }

  Future<ExerciseSet> _viewForAck(
    _Ack ack,
    Isar db,
    int setLocalId,
    int publicId,
  ) async {
    switch (ack) {
      case _Ack.applied:
        final row = await db.localExerciseSets.get(setLocalId);
        if (row == null) throw Exception('Exercise set not found: $publicId');
        return _toApiSet(row);
      case _Ack.targetGone:
      case _Ack.ownershipLost:
        throw Exception('Exercise set not found: $publicId');
    }
  }

  Future<_Ack> _applyLocalComplete(
    Isar db,
    int setLocalId,
    UserSessionToken token, {
    required bool markSynced,
  }) async {
    await _runHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    late _Ack ack;
    await db.writeTxn(() async {
      await _runHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      final set = await db.localExerciseSets.get(setLocalId);
      if (set == null) {
        ack = _Ack.targetGone;
        return;
      }
      if (await _setOwnerOf(db, set) != token.userId) {
        ack = _Ack.ownershipLost;
        return;
      }
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();

      _canonicalizeLegacyServerIds(set);
      final now = DateTime.now().toUtc();
      set.isCompleted = true;
      set.completedAt = now;
      set.lastModifiedLocal = now;
      if (markSynced) {
        set.isSynced = true;
        set.syncStatus = 'synced';
      } else {
        set.isSynced = false;
        // A real server id -> the completion is an update to sync; no server id
        // (never synced, or a canonicalized legacy `0`) -> it must remain an
        // initial CREATE so `SyncService._syncCreateSet` carries the completed
        // state. Never silently leave it `synced`, which no sync phase handles.
        if (_hasServerId(set.serverId)) {
          set.syncStatus = 'pending_update';
        } else if (set.syncStatus != 'pending_delete') {
          set.syncStatus = 'pending_create';
        }
      }
      await db.localExerciseSets.put(set);
      ack = _Ack.applied;
    });
    return ack;
  }

  /// Delete an exercise set.
  /// Offline-first: marks as pending_delete (or hard-deletes a never-synced
  /// row), deletes from the server when online.
  Future<bool> deleteExerciseSet(int id) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSet = await _resolveOwnedSet(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    if (localSet == null) throw Exception('Exercise set not found: $id');
    final setLocalId = localSet.localId;
    final hadServerId = _hasServerId(localSet.serverId);

    if (_connectivity.isOnline && hadServerId) {
      bool serverDeleted;
      try {
        serverDeleted = await _apiService.delete(
          ApiConfig.exerciseSetById(localSet.serverId!),
          sessionContext: context,
        );
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        if (!_sessionEpoch.isCurrent(token)) {
          throw const SessionStaleException();
        }
        debugPrint('⚠️ Delete API failed, marking for deletion: $e');
        return _deleteResult(
          await _markPendingDelete(db, setLocalId, token),
          id,
        );
      }
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      if (!serverDeleted) return false;
      // Server delete succeeded: a since-gone local row is convergence.
      debugPrint('✅ Set deleted from server and locally');
      return _deleteResult(await _deleteLocalSet(db, setLocalId, token), id);
    }

    if (!hadServerId) {
      debugPrint('✅ Local-only set deleted');
      return _deleteResult(await _deleteLocalSet(db, setLocalId, token), id);
    }
    debugPrint('✅ Set marked for deletion, will sync when online');
    return _deleteResult(await _markPendingDelete(db, setLocalId, token), id);
  }

  /// Maps a delete acknowledgment to the public `bool` result. A gone target
  /// is convergence (the delete goal is met); a since-reassigned target fails
  /// closed.
  bool _deleteResult(_Ack ack, int publicId) {
    switch (ack) {
      case _Ack.applied:
      case _Ack.targetGone:
        return true;
      case _Ack.ownershipLost:
        throw Exception('Exercise set not found: $publicId');
    }
  }

  Future<_Ack> _deleteLocalSet(
    Isar db,
    int setLocalId,
    UserSessionToken token,
  ) async {
    await _runHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    late _Ack ack;
    await db.writeTxn(() async {
      await _runHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      final set = await db.localExerciseSets.get(setLocalId);
      if (set == null) {
        ack = _Ack.targetGone;
        return;
      }
      if (await _setOwnerOf(db, set) != token.userId) {
        ack = _Ack.ownershipLost;
        return;
      }
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      await db.localExerciseSets.delete(setLocalId);
      ack = _Ack.applied;
    });
    return ack;
  }

  Future<_Ack> _markPendingDelete(
    Isar db,
    int setLocalId,
    UserSessionToken token,
  ) async {
    await _runHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    late _Ack ack;
    await db.writeTxn(() async {
      await _runHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      final set = await db.localExerciseSets.get(setLocalId);
      if (set == null) {
        ack = _Ack.targetGone;
        return;
      }
      if (await _setOwnerOf(db, set) != token.userId) {
        ack = _Ack.ownershipLost;
        return;
      }
      if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
      _canonicalizeLegacyServerIds(set);
      set.isSynced = false;
      set.syncStatus = 'pending_delete';
      set.lastModifiedLocal = DateTime.now().toUtc();
      await db.localExerciseSets.put(set);
      ack = _Ack.applied;
    });
    return ack;
  }
}

/// Outcome of a guarded local acknowledgment `writeTxn`. Session staleness is
/// never represented here - it is always thrown as [SessionStaleException].
enum _Ack {
  /// The write landed.
  applied,

  /// The target row no longer exists (deleted while the SAME session stayed
  /// current).
  targetGone,

  /// The target row exists but its parent chain is no longer owned by the
  /// captured user (reassigned while the SAME session stayed current).
  ownershipLost,
}
