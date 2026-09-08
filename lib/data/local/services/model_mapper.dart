import '../../../core/utils/datetime_helper.dart';
import '../../models/session.dart';
import '../../models/exercise.dart';
import '../../models/exercise_set.dart';
import '../../models/exercise_template.dart';
import '../../models/meal_log.dart';
import '../../models/meal_entry.dart';
import '../../models/food_item.dart';
import '../../models/nutrition_goal.dart';
import '../../models/food_template.dart';
import '../models/local_session.dart';
import '../models/local_exercise.dart';
import '../models/local_exercise_set.dart';
import '../models/local_exercise_template.dart';
import '../models/local_meal_log.dart';
import '../models/local_meal_entry.dart';
import '../models/local_food_item.dart';
import '../models/local_nutrition_goal.dart';
import '../models/local_food_template.dart';

/// Service for converting between API models and local database models
class ModelMapper {
  // ========== Session Mapping ==========

  /// Convert API Session to LocalSession
  /// Used when caching data from server
  ///
  /// [clientOperationId] is never sourced from [apiSession] - the API never
  /// echoes this key back (see `LocalSession.clientOperationId`'s doc
  /// comment). Every caller reconstructing an EXISTING row must pass the
  /// row's own current value explicitly so this rebuild does not silently
  /// drop it; a brand-new row (no [localId]) has none to preserve and
  /// correctly stays `null`.
  static LocalSession sessionToLocal(
    Session apiSession, {
    int? localId,
    bool isSynced = true,
    String? clientOperationId,
  }) {
    // Determine sync status:
    // - If synced: 'synced'
    // - If not synced and has serverId (exists on server): 'pending_update'
    // - If not synced and no serverId (new local): 'pending_create'
    String syncStatus;
    if (isSynced) {
      syncStatus = 'synced';
    } else if (apiSession.id > 0) {
      // Session exists on server, we're updating it
      syncStatus = 'pending_update';
    } else {
      // New session not yet on server
      syncStatus = 'pending_create';
    }

    final session = LocalSession(
      serverId: apiSession.id,
      userId: apiSession.userId,
      date: apiSession.date,
      duration: apiSession.duration,
      notes: apiSession.notes,
      type: apiSession.type,
      name: apiSession.name,
      status: apiSession.status,
      startedAt: apiSession.startedAt,
      completedAt: apiSession.completedAt,
      pausedAt: apiSession.pausedAt,
      programId: apiSession.programId, // Fix: preserve programId when caching
      programWorkoutId:
          apiSession
              .programWorkoutId, // Fix: preserve programWorkoutId when caching
      isSynced: isSynced,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: DateTime.now(),
      version: apiSession.version,
      clientOperationId: clientOperationId,
    );

    // Preserve existing localId if updating an existing session
    if (localId != null) {
      session.localId = localId;
    }

    return session;
  }

  /// Convert LocalSession to API Session
  /// Used when sending local data to server or displaying in UI
  static Session localToSession(
    LocalSession localSession, {
    List<Exercise> exercises = const [],
  }) {
    // Isar returns DateTime fields as local-flagged, but the absolute
    // instant is preserved correctly (verified against a real Isar
    // instance in model_mapper_isar_roundtrip_test.dart). A real .toUtc()
    // call relabels it as UTC without shifting the instant. Reconstructing
    // from wall-clock components instead would mislabel the already
    // locally-displayed digits as UTC, corrupting the instant by exactly
    // the local UTC offset.
    DateTime? toUtcTimestamp(DateTime? dt) => dt?.toUtc();

    return Session(
      id:
          localSession.serverId ??
          localSession.localId, // Use localId for unsynced items
      userId: localSession.userId,
      date: localSession.date,
      duration: localSession.duration,
      notes: localSession.notes,
      type: localSession.type,
      name: localSession.name,
      status: localSession.status,
      startedAt: toUtcTimestamp(localSession.startedAt),
      completedAt: toUtcTimestamp(localSession.completedAt),
      pausedAt: toUtcTimestamp(localSession.pausedAt),
      programId: localSession.programId,
      programWorkoutId: localSession.programWorkoutId,
      exercises: exercises,
      // Display-only fallback: the API Session model requires a
      // non-nullable version. This value must never be used to build a
      // network update request (use buildSessionUpdateRequest for that,
      // which reads localSession.version directly).
      version: localSession.version ?? 1,
    );
  }

  /// Build the request body for a full-session PUT update.
  ///
  /// Centralizes the mutable-field contract so the three call sites that
  /// push a full session update (periodic sync, date edits, name edits)
  /// cannot drift from each other. Sends the actual persisted version
  /// (which may be null) - never a guessed value - and omits id/userId,
  /// which the server no longer requires for a PUT. Also omits
  /// programId/programWorkoutId: SessionUpdateRequestDto doesn't accept
  /// them - program relationships are server-controlled, not editable
  /// through this endpoint.
  static Map<String, dynamic> buildSessionUpdateRequest(
    LocalSession localSession,
  ) {
    // See the identical fix and rationale in localToSession() above: Isar
    // preserves the absolute instant, so a real .toUtc() call is the
    // correct conversion.
    DateTime? toUtcTimestamp(DateTime? dt) => dt?.toUtc();

    final startedAtUtc = toUtcTimestamp(localSession.startedAt);
    final completedAtUtc = toUtcTimestamp(localSession.completedAt);
    final pausedAtUtc = toUtcTimestamp(localSession.pausedAt);

    return {
      'date': DateTimeHelper.formatDate(localSession.date),
      'duration': localSession.duration,
      'notes': localSession.notes,
      'type': localSession.type,
      'name': localSession.name,
      'status': localSession.status,
      'startedAt':
          startedAtUtc != null
              ? DateTimeHelper.formatTimestamp(startedAtUtc)
              : null,
      'completedAt':
          completedAtUtc != null
              ? DateTimeHelper.formatTimestamp(completedAtUtc)
              : null,
      'pausedAt':
          pausedAtUtc != null
              ? DateTimeHelper.formatTimestamp(pausedAtUtc)
              : null,
      'version': localSession.version,
    };
  }

  // ========== Exercise / ExerciseSet public-id namespace ==========

  /// The single collision-free public-id contract for [Exercise] / [ExerciseSet]
  /// DTOs produced from local rows:
  ///
  /// - a synced row (positive server id) is exposed as that positive server id;
  /// - an unsynced row (server id `null`, or the legacy sentinel `0`) is
  ///   exposed as the NEGATION of its always-positive Isar local id;
  /// - `0` is never a valid public id.
  ///
  /// A positive input therefore means "server id" unambiguously and a negative
  /// input means "the encoded local id" - the two namespaces never overlap, and
  /// an Isar local id (always positive internally) is never sent to the API.
  ///
  /// A row that has neither a positive server id nor a positive local id (an
  /// unpersisted / skipped-write placeholder) maps to `0` - the invalid /
  /// unset sentinel that every resolver rejects.
  static int publicRowId({required int? serverId, required int localId}) {
    if (serverId != null && serverId > 0) return serverId;
    return localId > 0 ? -localId : 0;
  }

  /// True if [publicId] denotes an unsynced (encoded-local-id) row.
  static bool isOfflinePublicId(int publicId) => publicId < 0;

  /// The Isar local id encoded in a negative [publicId] (see [publicRowId]).
  /// A non-negative [publicId] has no encoded local id and yields `0`.
  static int localIdFromPublicId(int publicId) => publicId < 0 ? -publicId : 0;

  // ========== Exercise Mapping ==========

  /// Convert API Exercise to LocalExercise
  /// Requires localSessionId for parent reference
  ///
  /// [apiExercise.occurrenceKey] is always copied verbatim (never invented,
  /// never dropped) - see `LocalExercise.occurrenceKey`'s doc comment.
  static LocalExercise exerciseToLocal(
    Exercise apiExercise, {
    required int sessionLocalId,
    int? sessionServerId,
    int? localId,
    bool isSynced = true,
  }) {
    final exercise = LocalExercise(
      // Only a positive id is a real server id; `0` / a negative encoded-local
      // id (see [publicRowId]) means "not yet synced".
      serverId: apiExercise.id > 0 ? apiExercise.id : null,
      sessionLocalId: sessionLocalId,
      sessionServerId: sessionServerId ?? apiExercise.sessionId,
      name: apiExercise.name,
      duration: apiExercise.duration,
      restTime: apiExercise.restTime,
      notes: apiExercise.notes,
      exerciseTemplateId: apiExercise.exerciseTemplateId,
      occurrenceKey: apiExercise.occurrenceKey,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: DateTime.now(),
    );

    // Preserve existing localId if updating an existing exercise
    if (localId != null) {
      exercise.localId = localId;
    }

    return exercise;
  }

  /// Convert LocalExercise to API Exercise
  static Exercise localToExercise(
    LocalExercise localExercise, {
    List<ExerciseSet> exerciseSets = const [],
  }) {
    return Exercise(
      id: publicRowId(
        serverId: localExercise.serverId,
        localId: localExercise.localId,
      ),
      sessionId: localExercise.sessionServerId ?? 0,
      name: localExercise.name,
      duration: localExercise.duration,
      restTime: localExercise.restTime,
      notes: localExercise.notes,
      exerciseTemplateId: localExercise.exerciseTemplateId,
      occurrenceKey: localExercise.occurrenceKey,
      exerciseSets: exerciseSets,
    );
  }

  /// Pairs a program-workout CREATE's local placeholder [localExercises]
  /// (materialized before dispatch - see
  /// `SessionRepository.createSessionFromProgramWorkout`) against the
  /// server's authoritative [serverExercises] list, for the acknowledgment's
  /// reconciliation. Both lists must already be scoped to the SAME captured
  /// owner and the SAME parent Session - the caller does this before calling
  /// (a session-scoped Isar query plus the epoch/ownership checks already
  /// established for every other write in this class's callers) - this
  /// method's own job is purely the pairing decision within that scope.
  ///
  /// ## `occurrenceKey`: the deployed contract's per-occurrence identity
  ///
  /// `GoHardAPI.Models.Exercise.OccurrenceKey` (mirrored client-side by
  /// `Exercise.occurrenceKey`/`LocalExercise.occurrenceKey`) identifies one
  /// exercise OCCURRENCE within a single `ProgramWorkout` - never the
  /// exercise type (`exerciseTemplateId` still means that), and never
  /// globally unique: the SAME key legitimately repeats across every
  /// Exercise materialized from the same `ProgramWorkout` into DIFFERENT
  /// Sessions (two intentional starts of the same workout both get Exercises
  /// keyed identically to their shared source template - see
  /// `ProgramWorkoutExerciseOccurrences`'s class doc comment on the deployed
  /// side). Uniqueness is enforced only WITHIN one workout's array, which is
  /// exactly the scope one CREATE materializes into one Session - so within
  /// the two lists this method receives, a non-null key legitimately
  /// appearing MORE than once on either side is a genuine contract
  /// violation, not a normal case, and is handled the same as any other
  /// unresolvable shape below (never partially assigned).
  ///
  /// Every server Exercise materialized through the KEYED
  /// `POST /sessions/from-program-workout` path carries a real, non-null
  /// `occurrenceKey` - the server self-heals a source template missing keys
  /// before materializing (`ProgramWorkoutExerciseOccurrences
  /// .EnsurePersistedAsync`, called from `SessionCreateService
  /// .ProgramWorkoutFirstWriteAsync` before `ProgramWorkoutSessionMaterializer
  /// .Build`), so [serverExercises] should never actually contain a
  /// `null`-keyed entry in practice; this method does not assume that,
  /// though - see the `null`-key handling below, which is defensive, not
  /// load-bearing on that assumption.
  ///
  /// ## Matching rule: exact one-to-one by `occurrenceKey`, nothing else
  ///
  /// Exercises are grouped by `occurrenceKey` on BOTH sides. A NON-NULL key's
  /// group pairs its members ONLY when it holds EXACTLY ONE local exercise
  /// and EXACTLY ONE server exercise - the one shape with no other candidate
  /// either could possibly mean, so attaching that identity is not a guess.
  /// Every other shape for a non-null key - more than one local exercise (a
  /// genuine contract violation per the paragraph above, since occurrence
  /// keys are unique per workout array), a local exercise whose key has no
  /// server counterpart at all (the occurrence was removed/replaced before
  /// materialization), or a server exercise whose key has zero or more than
  /// one local counterpart - is left AMBIGUOUS: no identity is assigned to
  /// any local exercise in that group, and no corresponding server exercise
  /// is inserted for it (inserting one anyway risks a second, duplicate-
  /// looking row alongside the untouched ambiguous local one(s)).
  ///
  /// This method NEVER falls back to `exerciseTemplateId`, array position,
  /// name, or prescription fields to resolve what `occurrenceKey` alone
  /// could not - those signals either identify the wrong thing (the exercise
  /// TYPE, not the occurrence) or are exactly the guesses this reconciliation
  /// exists to avoid (see the historical rationale preserved in this class's
  /// git history / the prior round's `SessionRepository` doc comment section
  /// for why a positional or `exerciseTemplateId` fallback was found unsafe).
  ///
  /// `occurrenceKey == null` (an ad-hoc/custom local placeholder, OR - the
  /// remaining real-world case - one materialized from a CACHED template
  /// that predates this field, before this client's own next routine
  /// program/workout refresh backfills it - see
  /// `SessionRepository.createSessionFromProgramWorkout`'s doc comment on the
  /// legacy-cache case) NEVER reaches the "exactly one and one" fast path,
  /// even when there is exactly one `null`-keyed exercise on each side:
  /// `null` carries no identity information at all, so "one on each side" is
  /// not proof they are the same occurrence. A `null`-keyed local exercise is
  /// ALWAYS ambiguous when the `null`-keyed group is non-empty on the local
  /// side; a `null`-keyed server exercise is only ever treated as genuinely
  /// new (returned in [unmatchedServer]) when there is NO local `null`-keyed
  /// exercise at all to potentially conflict with.
  ///
  /// An ambiguous local exercise is returned in [unmatchedLocal] UNCHANGED -
  /// the caller must not assign it a `serverId`, must not mark it synced,
  /// and must leave its `LocalExerciseSet` children exactly where they are
  /// (see the caller's own doc comment for what "unchanged" produces: the
  /// row is marked `conflict` so `SyncService._syncExercises` never
  /// independently re-creates it, and a later GET refresh can now RECOGNIZE
  /// it by `occurrenceKey` too instead of inserting a duplicate - see
  /// `SessionRepository._resolveExistingExerciseForRefresh`).
  ///
  /// The ONLY server exercises returned in [unmatchedServer] (safe to insert
  /// as brand-new, already-synced local rows) are ones whose key has ZERO
  /// local claimants at all - nothing local could be confused with them.
  ///
  /// ## Idempotency preface: an already-resolved identity is never revisited
  ///
  /// Before any `occurrenceKey` grouping happens, every local exercise that
  /// already carries a real (positive) `serverId` matching one of THIS
  /// response's exercise ids is paired immediately and removed from further
  /// consideration on both sides - unconditionally, regardless of its
  /// `occurrenceKey`. This is what makes a REDUNDANT/overlapping
  /// acknowledgment for the exact same operation idempotent even for a
  /// `null`-keyed exercise: a null-keyed occurrence a PRIOR pass already
  /// safely inserted (via the `unmatchedServer` "zero local claimants" path
  /// above) now genuinely IS a local claimant on the next pass - without this
  /// preface, the `null`-key group would see that previously-inserted row as
  /// a competing claimant and demote an already-correctly-synced exercise to
  /// `'conflict'` (a real regression a redundant ack must never cause; see
  /// this method's own test coverage for the exact scenario). A row can only
  /// reach this preface with a real `serverId` if some EARLIER reconciliation
  /// pass already attached it from THIS same session's own CREATE response
  /// history - it is never a coincidental match against unrelated data, for
  /// the same reason `SessionRepository._resolveExistingExerciseForRefresh`'s
  /// `serverId`-first lookup is safe: server exercise ids are assumed
  /// globally unique.
  static ({
    List<(LocalExercise, Exercise)> matched,
    List<LocalExercise> unmatchedLocal,
    List<Exercise> unmatchedServer,
  })
  pairProgramWorkoutCreateExercises(
    List<LocalExercise> localExercises,
    List<Exercise> serverExercises,
  ) {
    final matched = <(LocalExercise, Exercise)>[];
    final unmatchedLocal = <LocalExercise>[];
    final unmatchedServer = <Exercise>[];

    final serverById = <int, Exercise>{
      for (final server in serverExercises) server.id: server,
    };
    final alreadyResolvedLocalIds = <int>{};
    final alreadyResolvedServerIds = <int>{};
    for (final local in localExercises) {
      final serverId = local.serverId;
      if (serverId == null || serverId <= 0) continue;
      final server = serverById[serverId];
      if (server == null) continue;
      matched.add((local, server));
      alreadyResolvedLocalIds.add(local.localId);
      alreadyResolvedServerIds.add(server.id);
    }

    final remainingLocal = localExercises.where(
      (local) => !alreadyResolvedLocalIds.contains(local.localId),
    );
    final remainingServer = serverExercises.where(
      (server) => !alreadyResolvedServerIds.contains(server.id),
    );

    final localByKey = <String?, List<LocalExercise>>{};
    for (final local in remainingLocal) {
      (localByKey[local.occurrenceKey] ??= <LocalExercise>[]).add(local);
    }
    final serverByKey = <String?, List<Exercise>>{};
    for (final server in remainingServer) {
      (serverByKey[server.occurrenceKey] ??= <Exercise>[]).add(server);
    }

    final allKeys = <String?>{...localByKey.keys, ...serverByKey.keys};
    for (final key in allKeys) {
      final localGroup = localByKey[key] ?? const [];
      final serverGroup = serverByKey[key] ?? const [];

      if (localGroup.isEmpty) {
        // Nothing local claims this key - every server exercise in this
        // group is genuinely new, safe to insert. Holds for `null` too:
        // `null` carries no identity to conflict with, so an unclaimed
        // `null`-keyed server exercise is exactly as safe to insert as any
        // other unclaimed key.
        unmatchedServer.addAll(serverGroup);
      } else if (key != null &&
          localGroup.length == 1 &&
          serverGroup.length == 1) {
        // The only shape with no other candidate on either side - and only
        // meaningful for a REAL occurrenceKey. See this method's doc comment
        // for why `null` is excluded even at count 1-vs-1.
        matched.add((localGroup.single, serverGroup.single));
      } else {
        // Ambiguous (a genuine occurrenceKey contract violation - more than
        // one local/server exercise sharing a non-null key that is supposed
        // to be unique per workout array - a local/server count mismatch,
        // or an unresolvable `null` key) - never guess, never partially
        // assign an uncertain identity. Server exercises in this group are
        // dropped entirely, not inserted, so they cannot appear to
        // duplicate the untouched local occurrence(s).
        unmatchedLocal.addAll(localGroup);
      }
    }

    return (
      matched: matched,
      unmatchedLocal: unmatchedLocal,
      unmatchedServer: unmatchedServer,
    );
  }

  // ========== ExerciseSet Mapping ==========

  /// Convert API ExerciseSet to LocalExerciseSet
  /// Requires exerciseLocalId for parent reference
  static LocalExerciseSet exerciseSetToLocal(
    ExerciseSet apiSet, {
    required int exerciseLocalId,
    int? exerciseServerId,
    int? localId,
    bool isSynced = true,
  }) {
    final set = LocalExerciseSet(
      // Only a positive id is a real server id; `0` / a negative encoded-local
      // id (see [publicRowId]) means "not yet synced".
      serverId: apiSet.id > 0 ? apiSet.id : null,
      exerciseLocalId: exerciseLocalId,
      exerciseServerId: exerciseServerId ?? apiSet.exerciseId,
      setNumber: apiSet.setNumber,
      reps: apiSet.reps,
      weight: apiSet.weight,
      duration: apiSet.duration,
      isCompleted: apiSet.isCompleted,
      completedAt: apiSet.completedAt,
      notes: apiSet.notes,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: DateTime.now(),
    );

    // Preserve existing localId if updating an existing set
    if (localId != null) {
      set.localId = localId;
    }

    return set;
  }

  /// Convert LocalExerciseSet to API ExerciseSet
  static ExerciseSet localToExerciseSet(LocalExerciseSet localSet) {
    return ExerciseSet(
      id: publicRowId(serverId: localSet.serverId, localId: localSet.localId),
      exerciseId: publicRowId(
        serverId: localSet.exerciseServerId,
        localId: localSet.exerciseLocalId,
      ),
      setNumber: localSet.setNumber,
      reps: localSet.reps,
      weight: localSet.weight,
      duration: localSet.duration,
      isCompleted: localSet.isCompleted,
      completedAt: localSet.completedAt,
      notes: localSet.notes,
    );
  }

  // ========== ExerciseTemplate Mapping ==========

  /// Convert API ExerciseTemplate to LocalExerciseTemplate
  static LocalExerciseTemplate exerciseTemplateToLocal(
    ExerciseTemplate apiTemplate, {
    int? localId,
    bool isSynced = true,
  }) {
    return LocalExerciseTemplate(
      serverId: apiTemplate.id,
      name: apiTemplate.name,
      description: apiTemplate.description,
      category: apiTemplate.category,
      muscleGroup: apiTemplate.muscleGroup,
      equipment: apiTemplate.equipment,
      difficulty: apiTemplate.difficulty,
      videoUrl: apiTemplate.videoUrl,
      imageUrl: apiTemplate.imageUrl,
      instructions: apiTemplate.instructions,
      isCustom: apiTemplate.isCustom,
      createdByUserId: apiTemplate.createdByUserId,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: DateTime.now(),
    );
  }

  /// Convert LocalExerciseTemplate to API ExerciseTemplate
  static ExerciseTemplate localToExerciseTemplate(
    LocalExerciseTemplate localTemplate,
  ) {
    return ExerciseTemplate(
      id: localTemplate.serverId ?? 0,
      name: localTemplate.name,
      description: localTemplate.description,
      category: localTemplate.category,
      muscleGroup: localTemplate.muscleGroup,
      equipment: localTemplate.equipment,
      difficulty: localTemplate.difficulty,
      videoUrl: localTemplate.videoUrl,
      imageUrl: localTemplate.imageUrl,
      instructions: localTemplate.instructions,
      isCustom: localTemplate.isCustom,
      createdByUserId: localTemplate.createdByUserId,
    );
  }

  // ========== Batch Mapping Helpers ==========

  /// Convert a list of API Sessions to LocalSessions
  static List<LocalSession> sessionsToLocal(
    List<Session> apiSessions, {
    bool isSynced = true,
  }) {
    return apiSessions
        .map((session) => sessionToLocal(session, isSynced: isSynced))
        .toList();
  }

  /// Convert a list of LocalSessions to API Sessions
  static List<Session> localToSessions(List<LocalSession> localSessions) {
    return localSessions.map((session) => localToSession(session)).toList();
  }

  /// Convert a list of API Exercises to LocalExercises
  static List<LocalExercise> exercisesToLocal(
    List<Exercise> apiExercises, {
    required int sessionLocalId,
    int? sessionServerId,
    bool isSynced = true,
  }) {
    return apiExercises
        .map(
          (exercise) => exerciseToLocal(
            exercise,
            sessionLocalId: sessionLocalId,
            sessionServerId: sessionServerId,
            isSynced: isSynced,
          ),
        )
        .toList();
  }

  /// Convert a list of LocalExercises to API Exercises
  static List<Exercise> localToExercises(List<LocalExercise> localExercises) {
    return localExercises.map((exercise) => localToExercise(exercise)).toList();
  }

  /// Convert a list of API ExerciseSets to LocalExerciseSets
  static List<LocalExerciseSet> exerciseSetsToLocal(
    List<ExerciseSet> apiSets, {
    required int exerciseLocalId,
    int? exerciseServerId,
    bool isSynced = true,
  }) {
    return apiSets
        .map(
          (set) => exerciseSetToLocal(
            set,
            exerciseLocalId: exerciseLocalId,
            exerciseServerId: exerciseServerId,
            isSynced: isSynced,
          ),
        )
        .toList();
  }

  /// Convert a list of LocalExerciseSets to API ExerciseSets
  static List<ExerciseSet> localToExerciseSets(
    List<LocalExerciseSet> localSets,
  ) {
    return localSets.map((set) => localToExerciseSet(set)).toList();
  }

  /// Convert a list of API ExerciseTemplates to LocalExerciseTemplates
  static List<LocalExerciseTemplate> exerciseTemplatesToLocal(
    List<ExerciseTemplate> apiTemplates, {
    bool isSynced = true,
  }) {
    return apiTemplates
        .map(
          (template) => exerciseTemplateToLocal(template, isSynced: isSynced),
        )
        .toList();
  }

  /// Convert a list of LocalExerciseTemplates to API ExerciseTemplates
  static List<ExerciseTemplate> localToExerciseTemplates(
    List<LocalExerciseTemplate> localTemplates,
  ) {
    return localTemplates
        .map((template) => localToExerciseTemplate(template))
        .toList();
  }

  // ========== MealLog Mapping ==========

  /// Convert API MealLog to LocalMealLog
  static LocalMealLog mealLogToLocal(
    MealLog apiMealLog, {
    int? localId,
    bool isSynced = true,
  }) {
    String syncStatus;
    if (isSynced) {
      syncStatus = 'synced';
    } else if (apiMealLog.id > 0) {
      syncStatus = 'pending_update';
    } else {
      syncStatus = 'pending_create';
    }

    final mealLog = LocalMealLog(
      serverId: apiMealLog.id > 0 ? apiMealLog.id : null,
      userId: apiMealLog.userId,
      date: apiMealLog.date,
      notes: apiMealLog.notes,
      waterIntake: apiMealLog.waterIntake,
      totalCalories: apiMealLog.totalCalories,
      totalProtein: apiMealLog.totalProtein,
      totalCarbohydrates: apiMealLog.totalCarbohydrates,
      totalFat: apiMealLog.totalFat,
      totalFiber: apiMealLog.totalFiber,
      totalSodium: apiMealLog.totalSodium,
      createdAt: apiMealLog.createdAt,
      updatedAt: apiMealLog.updatedAt,
      isSynced: isSynced,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      mealLog.localId = localId;
    }

    return mealLog;
  }

  /// Convert LocalMealLog to API MealLog
  static MealLog localToMealLog(
    LocalMealLog localMealLog, {
    List<MealEntry>? mealEntries,
  }) {
    return MealLog(
      id: localMealLog.serverId ?? localMealLog.localId,
      userId: localMealLog.userId,
      date: localMealLog.date,
      notes: localMealLog.notes,
      waterIntake: localMealLog.waterIntake,
      totalCalories: localMealLog.totalCalories,
      totalProtein: localMealLog.totalProtein,
      totalCarbohydrates: localMealLog.totalCarbohydrates,
      totalFat: localMealLog.totalFat,
      totalFiber: localMealLog.totalFiber,
      totalSodium: localMealLog.totalSodium,
      createdAt: localMealLog.createdAt,
      updatedAt: localMealLog.updatedAt,
      mealEntries: mealEntries,
    );
  }

  // ========== MealEntry Mapping ==========

  /// Convert API MealEntry to LocalMealEntry
  static LocalMealEntry mealEntryToLocal(
    MealEntry apiMealEntry, {
    required int mealLogLocalId,
    int? mealLogServerId,
    int? localId,
    bool isSynced = true,
  }) {
    final mealEntry = LocalMealEntry(
      serverId: apiMealEntry.id > 0 ? apiMealEntry.id : null,
      mealLogLocalId: mealLogLocalId,
      mealLogServerId: mealLogServerId ?? apiMealEntry.mealLogId,
      mealType: apiMealEntry.mealType,
      name: apiMealEntry.name,
      scheduledTime: apiMealEntry.scheduledTime,
      isConsumed: apiMealEntry.isConsumed,
      consumedAt: apiMealEntry.consumedAt,
      notes: apiMealEntry.notes,
      totalCalories: apiMealEntry.totalCalories,
      totalProtein: apiMealEntry.totalProtein,
      totalCarbohydrates: apiMealEntry.totalCarbohydrates,
      totalFat: apiMealEntry.totalFat,
      totalFiber: apiMealEntry.totalFiber,
      totalSodium: apiMealEntry.totalSodium,
      createdAt: apiMealEntry.createdAt,
      updatedAt: apiMealEntry.updatedAt,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      mealEntry.localId = localId;
    }

    return mealEntry;
  }

  /// Convert LocalMealEntry to API MealEntry
  static MealEntry localToMealEntry(
    LocalMealEntry localMealEntry, {
    List<FoodItem>? foodItems,
  }) {
    return MealEntry(
      id: localMealEntry.serverId ?? localMealEntry.localId,
      mealLogId:
          localMealEntry.mealLogServerId ?? localMealEntry.mealLogLocalId,
      mealType: localMealEntry.mealType,
      name: localMealEntry.name,
      scheduledTime: localMealEntry.scheduledTime,
      isConsumed: localMealEntry.isConsumed,
      consumedAt: localMealEntry.consumedAt,
      notes: localMealEntry.notes,
      totalCalories: localMealEntry.totalCalories,
      totalProtein: localMealEntry.totalProtein,
      totalCarbohydrates: localMealEntry.totalCarbohydrates,
      totalFat: localMealEntry.totalFat,
      totalFiber: localMealEntry.totalFiber,
      totalSodium: localMealEntry.totalSodium,
      createdAt: localMealEntry.createdAt,
      updatedAt: localMealEntry.updatedAt,
      foodItems: foodItems,
    );
  }

  // ========== FoodItem Mapping ==========

  /// Convert API FoodItem to LocalFoodItem
  static LocalFoodItem foodItemToLocal(
    FoodItem apiFoodItem, {
    required int mealEntryLocalId,
    int? mealEntryServerId,
    int? localId,
    bool isSynced = true,
  }) {
    final foodItem = LocalFoodItem(
      serverId: apiFoodItem.id > 0 ? apiFoodItem.id : null,
      mealEntryLocalId: mealEntryLocalId,
      mealEntryServerId: mealEntryServerId ?? apiFoodItem.mealEntryId,
      foodTemplateId: apiFoodItem.foodTemplateId,
      name: apiFoodItem.name,
      brand: apiFoodItem.brand,
      quantity: apiFoodItem.quantity,
      servingSize: apiFoodItem.servingSize,
      servingUnit: apiFoodItem.servingUnit,
      calories: apiFoodItem.calories,
      protein: apiFoodItem.protein,
      carbohydrates: apiFoodItem.carbohydrates,
      fat: apiFoodItem.fat,
      fiber: apiFoodItem.fiber,
      sugar: apiFoodItem.sugar,
      sodium: apiFoodItem.sodium,
      createdAt: apiFoodItem.createdAt,
      updatedAt: apiFoodItem.updatedAt,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      foodItem.localId = localId;
    }

    return foodItem;
  }

  /// Convert LocalFoodItem to API FoodItem
  static FoodItem localToFoodItem(LocalFoodItem localFoodItem) {
    return FoodItem(
      id: localFoodItem.serverId ?? localFoodItem.localId,
      mealEntryId:
          localFoodItem.mealEntryServerId ?? localFoodItem.mealEntryLocalId,
      foodTemplateId: localFoodItem.foodTemplateId,
      name: localFoodItem.name,
      brand: localFoodItem.brand,
      quantity: localFoodItem.quantity,
      servingSize: localFoodItem.servingSize,
      servingUnit: localFoodItem.servingUnit,
      calories: localFoodItem.calories,
      protein: localFoodItem.protein,
      carbohydrates: localFoodItem.carbohydrates,
      fat: localFoodItem.fat,
      fiber: localFoodItem.fiber,
      sugar: localFoodItem.sugar,
      sodium: localFoodItem.sodium,
      createdAt: localFoodItem.createdAt,
      updatedAt: localFoodItem.updatedAt,
    );
  }

  // ========== NutritionGoal Mapping ==========

  /// Convert API NutritionGoal to LocalNutritionGoal
  static LocalNutritionGoal nutritionGoalToLocal(
    NutritionGoal apiGoal, {
    int? localId,
    bool isSynced = true,
  }) {
    String syncStatus;
    if (isSynced) {
      syncStatus = 'synced';
    } else if (apiGoal.id > 0) {
      syncStatus = 'pending_update';
    } else {
      syncStatus = 'pending_create';
    }

    final goal = LocalNutritionGoal(
      serverId: apiGoal.id > 0 ? apiGoal.id : null,
      userId: apiGoal.userId,
      name: apiGoal.name,
      dailyCalories: apiGoal.dailyCalories,
      dailyProtein: apiGoal.dailyProtein,
      dailyCarbohydrates: apiGoal.dailyCarbohydrates,
      dailyFat: apiGoal.dailyFat,
      dailyFiber: apiGoal.dailyFiber,
      dailySodium: apiGoal.dailySodium,
      dailySugar: apiGoal.dailySugar,
      dailyWater: apiGoal.dailyWater,
      proteinPercentage: apiGoal.proteinPercentage,
      carbohydratesPercentage: apiGoal.carbohydratesPercentage,
      fatPercentage: apiGoal.fatPercentage,
      isActive: apiGoal.isActive,
      createdAt: apiGoal.createdAt,
      updatedAt: apiGoal.updatedAt,
      explanation: apiGoal.explanation,
      bmr: apiGoal.bmr,
      tdee: apiGoal.tdee,
      calorieAdjustment: apiGoal.calorieAdjustment,
      isSynced: isSynced,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      goal.localId = localId;
    }

    return goal;
  }

  /// Convert LocalNutritionGoal to API NutritionGoal
  static NutritionGoal localToNutritionGoal(LocalNutritionGoal localGoal) {
    return NutritionGoal(
      id: localGoal.serverId ?? localGoal.localId,
      userId: localGoal.userId,
      name: localGoal.name,
      dailyCalories: localGoal.dailyCalories,
      dailyProtein: localGoal.dailyProtein,
      dailyCarbohydrates: localGoal.dailyCarbohydrates,
      dailyFat: localGoal.dailyFat,
      dailyFiber: localGoal.dailyFiber,
      dailySodium: localGoal.dailySodium,
      dailySugar: localGoal.dailySugar,
      dailyWater: localGoal.dailyWater,
      proteinPercentage: localGoal.proteinPercentage,
      carbohydratesPercentage: localGoal.carbohydratesPercentage,
      fatPercentage: localGoal.fatPercentage,
      isActive: localGoal.isActive,
      createdAt: localGoal.createdAt,
      updatedAt: localGoal.updatedAt,
      explanation: localGoal.explanation,
      bmr: localGoal.bmr,
      tdee: localGoal.tdee,
      calorieAdjustment: localGoal.calorieAdjustment,
    );
  }

  // ========== FoodTemplate Mapping ==========

  /// Convert API FoodTemplate to LocalFoodTemplate
  static LocalFoodTemplate foodTemplateToLocal(
    FoodTemplate apiTemplate, {
    int? localId,
    bool isSynced = true,
  }) {
    final template = LocalFoodTemplate(
      serverId: apiTemplate.id > 0 ? apiTemplate.id : null,
      name: apiTemplate.name,
      brand: apiTemplate.brand,
      category: apiTemplate.category,
      barcode: apiTemplate.barcode,
      servingSize: apiTemplate.servingSize,
      servingUnit: apiTemplate.servingUnit,
      calories: apiTemplate.calories,
      protein: apiTemplate.protein,
      carbohydrates: apiTemplate.carbohydrates,
      fat: apiTemplate.fat,
      fiber: apiTemplate.fiber,
      sugar: apiTemplate.sugar,
      sodium: apiTemplate.sodium,
      description: apiTemplate.description,
      imageUrl: apiTemplate.imageUrl,
      isCustom: apiTemplate.isCustom,
      createdByUserId: apiTemplate.createdByUserId,
      createdAt: apiTemplate.createdAt,
      updatedAt: apiTemplate.updatedAt,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      template.localId = localId;
    }

    return template;
  }

  /// Convert LocalFoodTemplate to API FoodTemplate
  static FoodTemplate localToFoodTemplate(LocalFoodTemplate localTemplate) {
    return FoodTemplate(
      id: localTemplate.serverId ?? localTemplate.localId,
      name: localTemplate.name,
      brand: localTemplate.brand,
      category: localTemplate.category,
      barcode: localTemplate.barcode,
      servingSize: localTemplate.servingSize,
      servingUnit: localTemplate.servingUnit,
      calories: localTemplate.calories,
      protein: localTemplate.protein,
      carbohydrates: localTemplate.carbohydrates,
      fat: localTemplate.fat,
      fiber: localTemplate.fiber,
      sugar: localTemplate.sugar,
      sodium: localTemplate.sodium,
      description: localTemplate.description,
      imageUrl: localTemplate.imageUrl,
      isCustom: localTemplate.isCustom,
      createdByUserId: localTemplate.createdByUserId,
      createdAt: localTemplate.createdAt,
      updatedAt: localTemplate.updatedAt,
    );
  }
}
