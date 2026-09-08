import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';

import 'session_repository_session_ownership_test.mocks.dart';

/// Deterministic coverage for durable, idempotent `POST
/// /sessions/from-program-workout` CREATE - the fix that closes the
/// previously-accepted "unkeyed" gap documented on
/// [SessionRepository.createSessionFromProgramWorkout] before this change.
///
/// Companion coverage lives in `session_create_client_operation_id_test.dart`
/// (tests 31/32: key persisted before dispatch, SyncService retry reuses the
/// same endpoint/key) and `session_durable_cancellation_test.dart` (test 13:
/// delete-before-identity-known reuses by-operation cancellation). This file
/// covers what those do not: foreground/background dispatch overlap, Exercise
/// reconciliation (matching, surplus, edit-preservation), template-edit
/// isolation, restart durability, and the 409/410/programNotFound typed
/// contracts specific to this entry point.
///
/// The "exercise identity safety" group specifically proves
/// `ModelMapper.pairProgramWorkoutCreateExercises` never guesses a server
/// parent from position or from `exerciseTemplateId` - matching is by
/// `occurrenceKey` only: a template entry replaced between dispatch and
/// server materialization (Case A), two local occurrences sharing an
/// `exerciseTemplateId` but carrying DISTINCT occurrenceKeys, matched
/// unambiguously despite the shared template id (Case B), the SAME pair
/// instead sharing a genuinely duplicate/invalid occurrenceKey - a contract
/// error, never guessed (Case B2), and a redundant second acknowledgment
/// with local Set activity in between (Case C) - see that method's own doc
/// comment for the full rationale. Further down, the same group also covers
/// ad-hoc (templateless) exercises distinguished purely by occurrenceKey,
/// legacy/keyless rows (where `null` never establishes identity, matching
/// the pre-occurrenceKey behavior this branch preserves for old cached
/// templates), pure occurrence removal, two independent Sessions
/// legitimately sharing the same occurrenceKey values, CREATE-response-loss
/// + replay, and the refresh-duplication gap this round closes (plus the
/// one legacy-keyless case it still cannot close).
///
/// Real Isar, real [UserSessionEpoch], real [SessionRequestCoordinator], a
/// real [ApiService] wired to a fake [HttpClientAdapter] - never a
/// wall-clock wait, `Future.delayed`, or polling loop; every race is driven
/// by held [Completer]s.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _CapturingHttpAdapter adapter;
  late SessionRepository repository;

  const userA = 1;
  const userB = 2;
  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  Future<Isar> openIsar(String dir) => Isar.open(
    [
      LocalSessionSchema,
      LocalExerciseSchema,
      LocalExerciseSetSchema,
      LocalExerciseTemplateSchema,
    ],
    directory: dir,
    inspector: false,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('program_workout_create_');
    isar = await openIsar(tempDir.path);

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
    adapter = _CapturingHttpAdapter();
    apiService.testHttpClientAdapter = adapter;

    repository = SessionRepository(
      apiService,
      localDb,
      mockConnectivity,
      mockAuthService,
      sessionEpoch,
      sessionCoordinator,
    );
  });

  tearDown(() async {
    repository.onBackgroundSyncScheduledForTesting = null;
    repository.operationIdGeneratorForTesting = null;
    SyncService.reset();
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

  ProgramWorkout workout({
    int id = 10,
    int programId = 5,
    String name = 'Leg Day',
    String exercisesJson = '[]',
    DateTime? scheduledDate,
  }) => ProgramWorkout(
    id: id,
    programId: programId,
    weekNumber: 1,
    dayNumber: 1,
    workoutName: name,
    workoutType: 'Strength',
    exercisesJson: exercisesJson,
    isCompleted: false,
    orderIndex: 0,
    // Far enough in the future that "clamp to today" never engages,
    // regardless of what day this suite actually runs on.
    scheduledDate: scheduledDate ?? DateTime(2031, 6, 15),
  );

  const twoExercisesJson =
      '[{"name":"Squat","exerciseTemplateId":1,"occurrenceKey":"squat-key","rest":90},'
      '{"name":"Lunge","exerciseTemplateId":2,"occurrenceKey":"lunge-key","rest":60}]';

  Map<String, dynamic> exerciseJson(
    int id, {
    required int sessionId,
    String name = 'Squat',
    int? exerciseTemplateId = 1,
    String? occurrenceKey = 'squat-key',
    int? restTime = 90,
  }) => {
    'id': id,
    'sessionId': sessionId,
    'name': name,
    'sortOrder': 0,
    'duration': null,
    'restTime': restTime,
    'notes': null,
    'exerciseTemplateId': exerciseTemplateId,
    'occurrenceKey': occurrenceKey,
    'exerciseSets': <dynamic>[],
    'version': 1,
  };

  Map<String, dynamic> sessionJson({
    required int id,
    int userId = userA,
    String name = 'Leg Day',
    String status = 'planned',
    String date = '2031-06-15',
    int programId = 5,
    int programWorkoutId = 10,
    List<Map<String, dynamic>> exercises = const [],
    String? clientOperationId,
  }) => {
    'id': id,
    'userId': userId,
    'date': date,
    'duration': null,
    'notes': null,
    'type': 'Strength',
    'name': name,
    'status': status,
    'startedAt': null,
    'completedAt': null,
    'pausedAt': null,
    'exercises': exercises,
    'programId': programId,
    'programWorkoutId': programWorkoutId,
    'version': 1,
    if (clientOperationId != null) 'clientOperationId': clientOperationId,
  };

  ResponseBody jsonResponse(Object? json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  ResponseBody errorBody(int status, Map<String, dynamic> body) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          'content-type': ['application/json'],
        },
      );

  Future<void> awaitBackgroundCreate(Future<void> Function() start) async {
    Future<void>? settled;
    repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
    await start();
    await settled;
    repository.onBackgroundSyncScheduledForTesting = null;
  }

  // ==========================================================================
  // 4/6/16. Duplicate-guard and correct-Session-for-navigation
  // ==========================================================================

  group('dedup / distinct-intent / navigation', () {
    test('6. a separate intentional start (after the prior one fully converged '
        'away, e.g. via cancellation) gets its OWN operation key - not '
        'derived from programWorkoutId alone', () async {
      loginAs(userA);
      adapter.responder =
          (o) => Future.value(jsonResponse(sessionJson(id: 900)));
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          10,
          workout(),
          DateTime(2031, 1, 1),
          5,
        ),
      );
      final first =
          await isar.localSessions
              .filter()
              .programWorkoutIdEqualTo(10)
              .findFirst();
      expect(first, isNotNull);
      final firstOperationId = first!.clientOperationId;

      // The first intent fully converges away (e.g. the user canceled it,
      // or it was archived) - no trace of it remains for this
      // programWorkoutId.
      await isar.writeTxn(() => isar.localSessions.delete(first.localId));

      adapter.captured.clear();
      adapter.responder =
          (o) => Future.value(jsonResponse(sessionJson(id: 901)));
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          10,
          workout(),
          DateTime(2031, 1, 1),
          5,
        ),
      );

      final rows =
          await isar.localSessions
              .filter()
              .programWorkoutIdEqualTo(10)
              .findAll();
      expect(rows.length, 1, reason: 'the first row is truly gone');
      expect(rows.single.clientOperationId, isNot(firstOperationId));
      expect(rows.single.serverId, 901);
    });

    test('16. the returned Session (used for navigation) matches the persisted '
        'local row exactly, immediately, before any HTTP resolves', () async {
      loginAs(userA);
      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;

      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(name: 'Leg Day', exercisesJson: twoExercisesJson),
        DateTime(2031, 1, 1),
        5,
      );

      expect(created.name, 'Leg Day');
      expect(created.programId, 5);
      expect(created.programWorkoutId, 10);
      expect(created.exercises.length, 2);
      expect(created.exercises[0].name, 'Squat');
      expect(created.exercises[1].name, 'Lunge');

      final row = await isar.localSessions.get(created.id);
      expect(row, isNotNull);
      expect(row!.name, created.name);
      expect(row.programWorkoutId, created.programWorkoutId);

      // Deliberately left held/uncompleted - this test only asserts the
      // synchronous return value, and never awaits the background
      // dispatch, so its HTTP call must never resolve or touch Isar
      // again.
    });
  });

  // ==========================================================================
  // 4. Foreground/background dispatch overlap cannot duplicate
  // ==========================================================================

  group('foreground/background overlap', () {
    test(
      '4. a SyncService retry racing the repository\'s OWN still-in-flight '
      'background dispatch never creates two Sessions or duplicate children '
      '- both carry the identical key, and reconciliation is idempotent',
      () async {
        loginAs(userA);
        final held = Completer<ResponseBody>();
        var postCount = 0;
        adapter.responder = (o) {
          if (o.method == 'POST' &&
              o.path == ApiConfig.sessionsFromProgramWorkout) {
            postCount++;
          }
          return held.future;
        };

        Future<void>? fgSettled;
        repository.onBackgroundSyncScheduledForTesting = (s) => fgSettled = s;
        final created = await repository.createSessionFromProgramWorkout(
          10,
          workout(exercisesJson: twoExercisesJson),
          DateTime(2031, 1, 1),
          5,
        );
        repository.onBackgroundSyncScheduledForTesting = null;

        // Wait for the repository's OWN background dispatch to actually
        // reach the adapter (POST sent, response held) before starting a
        // second, independent SyncService pass "concurrently" - it
        // re-reads the SAME canonical pending_create row and dispatches
        // its OWN POST with the IDENTICAL key/body while the first is
        // still held.
        await adapter.waitForCaptureCount(1);
        final syncService = SyncService(
          apiService: apiService,
          authService: mockAuthService,
          localDb: localDb,
          connectivity: mockConnectivity,
          sessionEpoch: sessionEpoch,
          sessionCoordinator: sessionCoordinator,
        );
        final syncFuture = syncService.sync();

        // Let both HTTP dispatches actually reach the adapter before
        // responding.
        await adapter.waitForCaptureCount(2);
        expect(postCount, 2, reason: 'both dispatches reached the adapter');

        held.complete(
          jsonResponse(
            sessionJson(
              id: 900,
              exercises: [
                exerciseJson(9001, sessionId: 900, name: 'Squat'),
                exerciseJson(
                  9002,
                  sessionId: 900,
                  name: 'Lunge',
                  exerciseTemplateId: 2,
                  occurrenceKey: 'lunge-key',
                  restTime: 60,
                ),
              ],
            ),
          ),
        );

        await fgSettled;
        await syncFuture;
        SyncService.reset();

        final sessions =
            await isar.localSessions
                .filter()
                .programWorkoutIdEqualTo(10)
                .findAll();
        expect(sessions.length, 1, reason: 'no duplicate Session row');
        expect(sessions.single.serverId, 900);
        expect(sessions.single.syncStatus, 'synced');

        final exercises =
            await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(sessions.single.localId)
                .findAll();
        expect(exercises.length, 2, reason: 'no duplicate Exercise rows');
        expect(exercises.map((e) => e.serverId).toSet(), {9001, 9002});

        expect(created.id, sessions.single.localId);
      },
    );
  });

  // ==========================================================================
  // 3. Close/reopen retries the original request unchanged
  // ==========================================================================

  test('3. after close/reopen, SyncService retries the SAME endpoint with the '
      'SAME key and identifiers - with NO in-memory ProgramWorkout available '
      'at all', () async {
    loginAs(userA);
    adapter.responder =
        (o) => Future<ResponseBody>.error(
          DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
          ),
        );
    await awaitBackgroundCreate(
      () => repository.createSessionFromProgramWorkout(
        10,
        workout(exercisesJson: twoExercisesJson),
        DateTime(2031, 1, 1),
        5,
      ),
    );
    final rowBeforeRestart =
        await isar.localSessions
            .filter()
            .programWorkoutIdEqualTo(10)
            .findFirst();
    expect(rowBeforeRestart!.syncStatus, 'pending_create');
    final operationId = rowBeforeRestart.clientOperationId;

    // Simulate app restart: close and reopen the SAME on-disk Isar file,
    // rebuild every collaborator, never touching the original
    // ProgramWorkout object again.
    await isar.close();
    isar = await openIsar(tempDir.path);
    localDb.setTestDatabase(isar);
    sessionEpoch = UserSessionEpoch();
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );
    apiService = ApiService(mockAuthService, sessionEpoch);
    apiService.testHttpClientAdapter = adapter;
    loginAs(userA);

    adapter.captured.clear();
    adapter.responder =
        (o) => Future.value(
          jsonResponse(sessionJson(id: 900, exercises: const [])),
        );

    final syncService = SyncService(
      apiService: apiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: mockConnectivity,
      sessionEpoch: sessionEpoch,
      sessionCoordinator: sessionCoordinator,
    );
    await syncService.sync();
    SyncService.reset();

    final post = adapter.captured.singleWhere(
      (r) =>
          r.method == 'POST' && r.path == ApiConfig.sessionsFromProgramWorkout,
    );
    final body = post.data as Map<String, dynamic>;
    expect(body['clientOperationId'], operationId);
    expect(body['programWorkoutId'], 10);
    expect(body['programId'], 5);
    expect(body.keys, {
      'programWorkoutId',
      'programId',
      'clientOperationId',
    }, reason: 'the retry body never resends exercise/template data');

    final rowAfter = await isar.localSessions.get(rowBeforeRestart.localId);
    expect(rowAfter!.serverId, 900);
    expect(rowAfter.syncStatus, 'synced');
  });

  // ==========================================================================
  // 9. Template edits after dispatch never change the retry request
  // ==========================================================================

  test(
    '9. editing the ProgramWorkout template after the first attempt does '
    'not change what a later retry sends - the request is identifiers only',
    () async {
      loginAs(userA);
      adapter.responder =
          (o) => Future<ResponseBody>.error(
            DioException(
              requestOptions: o,
              type: DioExceptionType.connectionError,
            ),
          );
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          10,
          workout(name: 'Original Name', exercisesJson: '[{"name":"Squat"}]'),
          DateTime(2031, 1, 1),
          5,
        ),
      );

      // The caller's ProgramWorkout object is edited/replaced entirely -
      // the repository never retains a reference to it.
      final editedWorkout = workout(
        name: 'Renamed',
        exercisesJson: '[{"name":"Deadlift"},{"name":"Bench"}]',
      );
      expect(editedWorkout.workoutName, 'Renamed');

      adapter.captured.clear();
      adapter.responder =
          (o) => Future.value(jsonResponse(sessionJson(id: 900)));
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await syncService.sync();
      SyncService.reset();

      final post = adapter.captured.singleWhere(
        (r) =>
            r.method == 'POST' &&
            r.path == ApiConfig.sessionsFromProgramWorkout,
      );
      final body = post.data as Map<String, dynamic>;
      expect(body.containsKey('exercisesJson'), isFalse);
      expect(body.containsKey('workoutName'), isFalse);
      expect(body['programWorkoutId'], 10);
    },
  );

  // ==========================================================================
  // 8. Newer local edits survive acknowledgment (Session AND Exercise level)
  // ==========================================================================

  test('8. a status change made to the Session while CREATE is in flight '
      'survives the acknowledgment, and a Set a user logs on an Exercise '
      'while CREATE is in flight survives reconciliation untouched', () async {
    loginAs(userA);
    final held = Completer<ResponseBody>();
    adapter.responder = (o) => held.future;

    Future<void>? settled;
    repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
    final created = await repository.createSessionFromProgramWorkout(
      10,
      workout(exercisesJson: twoExercisesJson),
      DateTime(2031, 1, 1),
      5,
    );
    repository.onBackgroundSyncScheduledForTesting = null;

    // Race in a local edit while the POST is held: the user starts the
    // workout (a real, ordinary status change) and logs a completed Set
    // on the first exercise (also real and ordinary - logging reps/weight
    // while a workout is starting is core functionality). There is no UI
    // path that edits an Exercise's own name/notes/rest before it syncs,
    // so that is not exercised here - see
    // `_reconcileProgramWorkoutCreateExercises`'s doc comment for why.
    final sessionRow = (await isar.localSessions.get(created.id))!;
    sessionRow.status = 'in_progress';
    sessionRow.startedAt = DateTime(2031, 1, 1, 8);
    sessionRow.lastModifiedLocal = DateTime.now().toUtc();
    final exerciseRows =
        await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll()
          ..sort((a, b) => a.localId.compareTo(b.localId));
    final loggedSet = LocalExerciseSet(
      exerciseLocalId: exerciseRows[0].localId,
      setNumber: 1,
      reps: 8,
      weight: 60,
      isCompleted: true,
      completedAt: DateTime(2031, 1, 1, 8, 5),
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime.now().toUtc(),
    );
    await isar.writeTxn(() async {
      await isar.localSessions.put(sessionRow);
      await isar.localExerciseSets.put(loggedSet);
    });

    held.complete(
      jsonResponse(
        sessionJson(
          id: 900,
          status: 'draft',
          exercises: [
            exerciseJson(9001, sessionId: 900, name: 'Squat'),
            exerciseJson(
              9002,
              sessionId: 900,
              name: 'Lunge',
              exerciseTemplateId: 2,
              occurrenceKey: 'lunge-key',
              restTime: 60,
            ),
          ],
        ),
      ),
    );
    await settled;

    final rowAfter = (await isar.localSessions.get(created.id))!;
    expect(rowAfter.serverId, 900, reason: 'identity is still attached');
    expect(
      rowAfter.status,
      'in_progress',
      reason:
          'the local status change is never overwritten by the stale '
          'draft response',
    );
    expect(rowAfter.syncStatus, 'pending_update');

    final exAfter =
        await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll()
          ..sort((a, b) => a.localId.compareTo(b.localId));
    // Both exercises reconcile normally (unconditionally) to the server's
    // response - matched by occurrenceKey, so this holds regardless of the
    // pair's original position.
    expect(exAfter[0].name, 'Squat');
    expect(exAfter[0].serverId, 9001);
    expect(exAfter[0].syncStatus, 'synced');
    expect(exAfter[1].name, 'Lunge');
    expect(exAfter[1].serverId, 9002);
    expect(exAfter[1].syncStatus, 'synced');

    // The logged Set survives untouched under its exercise's STABLE
    // localId - reconciliation never rebuilt that row.
    final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
    expect(setAfter, isNotNull);
    expect(setAfter!.exerciseLocalId, exerciseRows[0].localId);
    expect(setAfter.reps, 8);
    expect(setAfter.isCompleted, isTrue);
    expect(setAfter.syncStatus, 'pending_create');
  });

  test('exercise reconciliation pairs by occurrenceKey, not position: a '
      'Set logged on one exercise stays attached to it even though the '
      'server returned the two exercises in the OPPOSITE order from how '
      'they were locally materialized', () async {
    loginAs(userA);
    final held = Completer<ResponseBody>();
    adapter.responder = (o) => held.future;

    Future<void>? settled;
    repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
    // Locally materialized in JSON order: Squat (squat-key), then Lunge
    // (lunge-key).
    final created = await repository.createSessionFromProgramWorkout(
      10,
      workout(exercisesJson: twoExercisesJson),
      DateTime(2031, 1, 1),
      5,
    );
    repository.onBackgroundSyncScheduledForTesting = null;

    final localExercises =
        await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll()
          ..sort((a, b) => a.localId.compareTo(b.localId));
    final squatLocalId = localExercises[0].localId; // squat-key
    final loggedSet = LocalExerciseSet(
      exerciseLocalId: squatLocalId,
      setNumber: 1,
      reps: 5,
      weight: 100,
      isCompleted: true,
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime.now().toUtc(),
    );
    await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

    // The server returns them in the OPPOSITE order (lunge-key first) -
    // simulating a template reorder between dispatch and acceptance. Both
    // exercises also happen to share the SAME exerciseTemplateId here
    // (deliberately, both defaulted to 1 unless overridden) to prove
    // matching is driven by occurrenceKey, not exerciseTemplateId.
    held.complete(
      jsonResponse(
        sessionJson(
          id: 900,
          exercises: [
            exerciseJson(
              9002,
              sessionId: 900,
              name: 'Lunge',
              occurrenceKey: 'lunge-key',
              restTime: 60,
            ),
            exerciseJson(9001, sessionId: 900, name: 'Squat'),
          ],
        ),
      ),
    );
    await settled;

    final squatAfter = await isar.localExercises.get(squatLocalId);
    expect(
      squatAfter!.serverId,
      9001,
      reason: 'matched by occurrenceKey, not the server\'s position',
    );
    expect(squatAfter.name, 'Squat');

    final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
    expect(
      setAfter!.exerciseLocalId,
      squatLocalId,
      reason: 'still attached to the Squat exercise it was logged under',
    );
  });

  // ==========================================================================
  // Identity safety: unmatched/ambiguous exercises never get a guessed
  // server parent, and a redundant re-acknowledgment never reassigns one.
  // ==========================================================================

  group('exercise identity safety (no positional fallback)', () {
    test('Case A: the template replaces one exercise (A -> C) between dispatch '
        'and server materialization - A\'s Set stays on the untouched, still '
        '-unsynced A; C is inserted as a genuinely new exercise; B (unchanged) '
        'matches normally', () async {
      loginAs(userA);
      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;

      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      // Locally materialized: A (key "a-key"), B (key "b-key").
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"A","exerciseTemplateId":1,"occurrenceKey":"a-key"},'
              '{"name":"B","exerciseTemplateId":2,"occurrenceKey":"b-key"}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;

      final localExercises =
          await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(created.id)
                .findAll()
            ..sort((a, b) => a.localId.compareTo(b.localId));
      final aLocalId = localExercises[0].localId; // a-key
      final loggedSet = LocalExerciseSet(
        exerciseLocalId: aLocalId,
        setNumber: 1,
        reps: 10,
        weight: 40,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

      // The server materializes from the template's CURRENT state: A
      // (a-key) was replaced by C (a freshly-minted, unrelated key
      // "c-key" - see this file's own doc comment / Task 4's finding on
      // how a replacement mints a fresh key); B (b-key) is unchanged.
      held.complete(
        jsonResponse(
          sessionJson(
            id: 900,
            exercises: [
              exerciseJson(
                9003,
                sessionId: 900,
                name: 'C',
                exerciseTemplateId: 3,
                occurrenceKey: 'c-key',
              ),
              exerciseJson(
                9002,
                sessionId: 900,
                name: 'B',
                exerciseTemplateId: 2,
                occurrenceKey: 'b-key',
              ),
            ],
          ),
        ),
      );
      await settled;

      // A is never given a guessed server parent, and is marked 'conflict'
      // so it can never independently re-create itself either (see
      // `_reconcileProgramWorkoutCreateExercises`'s doc comment) - its own
      // key ("a-key") simply never appears anywhere in the server's
      // response.
      final aAfter = await isar.localExercises.get(aLocalId);
      expect(aAfter, isNotNull);
      expect(aAfter!.name, 'A');
      expect(
        aAfter.serverId,
        isNull,
        reason: 'never assign an uncertain server parent to A',
      );
      expect(aAfter.syncStatus, 'conflict');
      expect(aAfter.isSynced, isFalse);

      // A's Set is still attached to A, untouched.
      final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
      expect(setAfter!.exerciseLocalId, aLocalId);
      expect(setAfter.reps, 10);

      // B matched normally (1 local, 1 server, same occurrenceKey).
      final bAfter = await isar.localExercises.get(localExercises[1].localId);
      expect(bAfter!.serverId, 9002);
      expect(bAfter.syncStatus, 'synced');

      // C is a genuinely new exercise (no local claimant for "c-key")
      // - inserted fresh, distinct from A.
      final allExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(allExercises.length, 3, reason: 'A, B, and the new C');
      final cRow = allExercises.singleWhere((e) => e.name == 'C');
      expect(cRow.serverId, 9003);
      expect(cRow.syncStatus, 'synced');
      expect(cRow.occurrenceKey, 'c-key');
      expect(cRow.localId, isNot(aLocalId));
    });

    test('Case B: two local occurrences share the same exerciseTemplateId but '
        'have DISTINCT occurrenceKeys - each is matched to its own server '
        'occurrence unambiguously, exactly like Task 7\'s "duplicate '
        'exerciseTemplateIds distinguished by occurrenceKey" requirement, '
        'even when the server also returns them in the OPPOSITE order', () async {
      loginAs(userA);
      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;

      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      // Two occurrences of the SAME template (a deliberate superset/
      // drop-set style entry), each with its OWN occurrenceKey, plus one
      // unrelated exercise.
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"Curl A","exerciseTemplateId":7,"occurrenceKey":"curl-a"},'
              '{"name":"Curl B","exerciseTemplateId":7,"occurrenceKey":"curl-b"},'
              '{"name":"Row","exerciseTemplateId":9,"occurrenceKey":"row-key"}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;

      final localExercises =
          await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(created.id)
                .findAll()
            ..sort((a, b) => a.localId.compareTo(b.localId));
      final curlALocalId = localExercises[0].localId;
      final curlBLocalId = localExercises[1].localId;
      final rowLocalId = localExercises[2].localId;

      final setOnA = LocalExerciseSet(
        exerciseLocalId: curlALocalId,
        setNumber: 1,
        reps: 12,
        weight: 15,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      final setOnB = LocalExerciseSet(
        exerciseLocalId: curlBLocalId,
        setNumber: 1,
        reps: 8,
        weight: 25,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() async {
        await isar.localExerciseSets.put(setOnA);
        await isar.localExerciseSets.put(setOnB);
      });

      // Server returns them in a DIFFERENT order, and Row unchanged - but
      // each still carries its own distinct occurrenceKey, so there is
      // nothing ambiguous about it.
      held.complete(
        jsonResponse(
          sessionJson(
            id: 900,
            exercises: [
              exerciseJson(
                9102,
                sessionId: 900,
                name: 'Curl',
                exerciseTemplateId: 7,
                occurrenceKey: 'curl-b',
              ),
              exerciseJson(
                9101,
                sessionId: 900,
                name: 'Curl',
                exerciseTemplateId: 7,
                occurrenceKey: 'curl-a',
              ),
              exerciseJson(
                9009,
                sessionId: 900,
                name: 'Row',
                exerciseTemplateId: 9,
                occurrenceKey: 'row-key',
              ),
            ],
          ),
        ),
      );
      await settled;

      // Both Curl occurrences match unambiguously by their own key, NOT by
      // the shared exerciseTemplateId and NOT by server response position.
      final curlAAfter = await isar.localExercises.get(curlALocalId);
      final curlBAfter = await isar.localExercises.get(curlBLocalId);
      expect(curlAAfter!.serverId, 9101, reason: 'matched by "curl-a"');
      expect(curlAAfter.syncStatus, 'synced');
      expect(curlBAfter!.serverId, 9102, reason: 'matched by "curl-b"');
      expect(curlBAfter.syncStatus, 'synced');

      // Each Set stays on its OWN, correctly-matched occurrence.
      final setOnAAfter = await isar.localExerciseSets.get(setOnA.localId);
      final setOnBAfter = await isar.localExerciseSets.get(setOnB.localId);
      expect(setOnAAfter!.exerciseLocalId, curlALocalId);
      expect(setOnAAfter.reps, 12);
      expect(setOnBAfter!.exerciseLocalId, curlBLocalId);
      expect(setOnBAfter.reps, 8);

      // No duplicate/extra rows.
      final allExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(
        allExercises.where((e) => e.exerciseTemplateId == 7).length,
        2,
        reason: 'still exactly Curl A and Curl B - no inserted duplicates',
      );

      // Row (unambiguous 1-to-1) matches normally.
      final rowAfter = await isar.localExercises.get(rowLocalId);
      expect(rowAfter!.serverId, 9009);
      expect(rowAfter.syncStatus, 'synced');
    });

    test('Case B2: two local occurrences GENUINELY ambiguous - same '
        'exerciseTemplateId AND the same occurrenceKey (a contract violation '
        'a malformed/legacy template could still produce) - the server '
        'returning matching duplicate keys is treated as a contract error: '
        'NEITHER gets a guessed identity and each Set stays on its own '
        'occurrence', () async {
      loginAs(userA);
      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;

      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      // Two occurrences that (invalidly) share the exact SAME occurrenceKey.
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"Curl A","exerciseTemplateId":7,"occurrenceKey":"dup-key"},'
              '{"name":"Curl B","exerciseTemplateId":7,"occurrenceKey":"dup-key"},'
              '{"name":"Row","exerciseTemplateId":9,"occurrenceKey":"row-key"}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;

      final localExercises =
          await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(created.id)
                .findAll()
            ..sort((a, b) => a.localId.compareTo(b.localId));
      final curlALocalId = localExercises[0].localId;
      final curlBLocalId = localExercises[1].localId;
      final rowLocalId = localExercises[2].localId;

      final setOnA = LocalExerciseSet(
        exerciseLocalId: curlALocalId,
        setNumber: 1,
        reps: 12,
        weight: 15,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      final setOnB = LocalExerciseSet(
        exerciseLocalId: curlBLocalId,
        setNumber: 1,
        reps: 8,
        weight: 25,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() async {
        await isar.localExerciseSets.put(setOnA);
        await isar.localExerciseSets.put(setOnB);
      });

      // Server returns the SAME duplicate-key pair back (the contract says
      // this shouldn't normally happen post-normalization, but this
      // reconciliation must still fail closed rather than guess).
      held.complete(
        jsonResponse(
          sessionJson(
            id: 900,
            exercises: [
              exerciseJson(
                9101,
                sessionId: 900,
                name: 'Curl',
                exerciseTemplateId: 7,
                occurrenceKey: 'dup-key',
              ),
              exerciseJson(
                9102,
                sessionId: 900,
                name: 'Curl',
                exerciseTemplateId: 7,
                occurrenceKey: 'dup-key',
              ),
              exerciseJson(
                9009,
                sessionId: 900,
                name: 'Row',
                exerciseTemplateId: 9,
                occurrenceKey: 'row-key',
              ),
            ],
          ),
        ),
      );
      await settled;

      // Neither Curl occurrence gets a guessed identity, and both are
      // marked 'conflict' so `_syncExercises` can never independently
      // re-create them (which would add MORE Curl exercises server-side on
      // top of the 2 that already exist there from this same CREATE).
      final curlAAfter = await isar.localExercises.get(curlALocalId);
      final curlBAfter = await isar.localExercises.get(curlBLocalId);
      expect(curlAAfter!.serverId, isNull);
      expect(curlAAfter.syncStatus, 'conflict');
      expect(curlBAfter!.serverId, isNull);
      expect(curlBAfter.syncStatus, 'conflict');

      // Each Set stays on its OWN, still-distinguishable local occurrence.
      final setOnAAfter = await isar.localExerciseSets.get(setOnA.localId);
      final setOnBAfter = await isar.localExerciseSets.get(setOnB.localId);
      expect(setOnAAfter!.exerciseLocalId, curlALocalId);
      expect(setOnAAfter.reps, 12);
      expect(setOnBAfter!.exerciseLocalId, curlBLocalId);
      expect(setOnBAfter.reps, 8);

      // The two ambiguous server "Curl" exercises are NOT inserted as new
      // rows either (that would look like a third/fourth duplicate).
      final allExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(
        allExercises.where((e) => e.exerciseTemplateId == 7).length,
        2,
        reason: 'still exactly Curl A and Curl B - no inserted duplicates',
      );

      // Row (unambiguous 1-to-1) matches normally.
      final rowAfter = await isar.localExercises.get(rowLocalId);
      expect(rowAfter!.serverId, 9009);
      expect(rowAfter.syncStatus, 'synced');
    });

    test(
      'Case C: TWO CREATE acknowledgments for the same operation - the '
      'repository\'s own foreground dispatch and an overlapping SyncService '
      'pass - arrive at different times, with a Set logged on the '
      'still-ambiguous exercise BETWEEN them. The second, redundant ack '
      'never reverts the matched exercise, never guesses the ambiguous '
      'one\'s identity, and the Set is never reassigned or duplicated',
      () async {
        loginAs(userA);
        final heldFirst = Completer<ResponseBody>();
        final heldSecond = Completer<ResponseBody>();
        var postCount = 0;
        adapter.responder = (o) {
          if (o.method != 'POST' ||
              o.path != ApiConfig.sessionsFromProgramWorkout) {
            return Future.value(jsonResponse(const <dynamic>[]));
          }
          postCount++;
          return postCount == 1 ? heldFirst.future : heldSecond.future;
        };

        // A and A2 both lack an occurrenceKey (a legacy cached template
        // that predates this field - null establishes no identity, so both
        // stay ambiguous no matter what the server returns); B ("b-key")
        // is unambiguous.
        Future<void>? fgSettled;
        repository.onBackgroundSyncScheduledForTesting = (s) => fgSettled = s;
        final created = await repository.createSessionFromProgramWorkout(
          10,
          workout(
            exercisesJson:
                '[{"name":"A","exerciseTemplateId":1},'
                '{"name":"A2","exerciseTemplateId":1},'
                '{"name":"B","exerciseTemplateId":2,"occurrenceKey":"b-key"}]',
          ),
          DateTime(2031, 1, 1),
          5,
        );
        repository.onBackgroundSyncScheduledForTesting = null;

        final localExercises =
            await isar.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(created.id)
                  .findAll()
              ..sort((a, b) => a.localId.compareTo(b.localId));
        final aLocalId = localExercises[0].localId;
        final a2LocalId = localExercises[1].localId;
        final bLocalId = localExercises[2].localId;

        // The repository's own background dispatch is in flight (held).
        // Start a second, independent SyncService pass for the SAME
        // still-pending_create row before either resolves.
        await adapter.waitForCaptureCount(1);
        final syncService = SyncService(
          apiService: apiService,
          authService: mockAuthService,
          localDb: localDb,
          connectivity: mockConnectivity,
          sessionEpoch: sessionEpoch,
          sessionCoordinator: sessionCoordinator,
        );
        final syncFuture = syncService.sync();
        await adapter.waitForCaptureCount(2);

        final response = sessionJson(
          id: 900,
          exercises: [
            exerciseJson(
              9002,
              sessionId: 900,
              name: 'B',
              exerciseTemplateId: 2,
              occurrenceKey: 'b-key',
            ),
          ],
        );

        // FIRST acknowledgment resolves: B matches, A/A2 stay ambiguous.
        heldFirst.complete(jsonResponse(response));
        await fgSettled;

        final bAfterFirst = await isar.localExercises.get(bLocalId);
        expect(
          bAfterFirst!.serverId,
          9002,
          reason: 'B matched on the first ack',
        );
        final aAfterFirst = await isar.localExercises.get(aLocalId);
        expect(
          aAfterFirst!.serverId,
          isNull,
          reason: 'A ambiguous on first ack',
        );

        // Local activity BETWEEN the two acknowledgments: a Set logged on
        // the still-ambiguous A.
        final newSetOnA = LocalExerciseSet(
          exerciseLocalId: aLocalId,
          setNumber: 1,
          reps: 6,
          weight: 20,
          isCompleted: true,
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime.now().toUtc(),
        );
        await isar.writeTxn(() => isar.localExerciseSets.put(newSetOnA));

        // SECOND, redundant acknowledgment resolves - the SAME response,
        // for the SAME operation key.
        heldSecond.complete(jsonResponse(response));
        await syncFuture;
        SyncService.reset();

        final bAfterSecond = await isar.localExercises.get(bLocalId);
        expect(
          bAfterSecond!.serverId,
          9002,
          reason: 'unchanged - idempotent overwrite with identical data',
        );
        expect(bAfterSecond.syncStatus, 'synced');

        final aAfterSecond = await isar.localExercises.get(aLocalId);
        expect(
          aAfterSecond!.serverId,
          isNull,
          reason: 'still never assigned a guessed parent on the redundant ack',
        );
        expect(
          aAfterSecond.syncStatus,
          'conflict',
          reason:
              'still parked, never independently re-created, on the '
              'redundant ack either',
        );

        final a2AfterSecond = await isar.localExercises.get(a2LocalId);
        expect(a2AfterSecond!.serverId, isNull);
        expect(a2AfterSecond.syncStatus, 'conflict');

        // The Set added between acks is still attached to A specifically,
        // never reassigned or duplicated.
        final setsOnA =
            await isar.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(aLocalId)
                .findAll();
        expect(setsOnA.length, 1);
        expect(setsOnA.single.localId, newSetOnA.localId);

        // No duplicate/extra exercise rows were created by either ack.
        final allExercises =
            await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(created.id)
                .findAll();
        expect(allExercises.length, 3, reason: 'still exactly A, A2, B');
      },
    );

    test('a redundant SECOND acknowledgment never recreates a Set the user '
        'already deleted between the two acks', () async {
      loginAs(userA);
      final heldFirst = Completer<ResponseBody>();
      final heldSecond = Completer<ResponseBody>();
      var postCount = 0;
      adapter.responder = (o) {
        if (o.method != 'POST' ||
            o.path != ApiConfig.sessionsFromProgramWorkout) {
          return Future.value(jsonResponse(const <dynamic>[]));
        }
        postCount++;
        return postCount == 1 ? heldFirst.future : heldSecond.future;
      };

      Future<void>? fgSettled;
      repository.onBackgroundSyncScheduledForTesting = (s) => fgSettled = s;
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"Squat","exerciseTemplateId":1,"occurrenceKey":"squat-key"}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;

      final squatLocalId =
          (await isar.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(created.id)
                  .findFirst())!
              .localId;
      final loggedSet = LocalExerciseSet(
        exerciseLocalId: squatLocalId,
        setNumber: 1,
        reps: 5,
        weight: 50,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

      await adapter.waitForCaptureCount(1);
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      final syncFuture = syncService.sync();
      await adapter.waitForCaptureCount(2);

      final response = sessionJson(
        id: 900,
        exercises: [
          exerciseJson(9001, sessionId: 900, name: 'Squat', restTime: 90),
        ],
      );

      heldFirst.complete(jsonResponse(response));
      await fgSettled;

      final exAfterFirst = await isar.localExercises.get(squatLocalId);
      expect(exAfterFirst!.serverId, 9001, reason: 'matched on first ack');
      expect(
        await isar.localExerciseSets.get(loggedSet.localId),
        isNotNull,
        reason: 'Set still present after the first ack',
      );

      // Between acks, the user deletes the Set.
      await isar.writeTxn(
        () => isar.localExerciseSets.delete(loggedSet.localId),
      );

      // Redundant second acknowledgment for the SAME operation.
      heldSecond.complete(jsonResponse(response));
      await syncFuture;
      SyncService.reset();

      expect(
        await isar.localExerciseSets.get(loggedSet.localId),
        isNull,
        reason: 'the deleted Set must never be resurrected',
      );
      final allSets =
          await isar.localExerciseSets
              .filter()
              .exerciseLocalIdEqualTo(squatLocalId)
              .findAll();
      expect(allSets, isEmpty);
    });

    test('a redundant SECOND acknowledgment never demotes an already-synced '
        'null-occurrenceKey exercise (inserted fresh by the FIRST ack, with '
        'zero local claimants at the time) back to \'conflict\' - the row is '
        'recognized as already-resolved by its own serverId before '
        'occurrenceKey grouping ever runs again', () async {
      loginAs(userA);
      final heldFirst = Completer<ResponseBody>();
      final heldSecond = Completer<ResponseBody>();
      var postCount = 0;
      adapter.responder = (o) {
        if (o.method != 'POST' ||
            o.path != ApiConfig.sessionsFromProgramWorkout) {
          return Future.value(jsonResponse(const <dynamic>[]));
        }
        postCount++;
        return postCount == 1 ? heldFirst.future : heldSecond.future;
      };

      // Only a real-keyed local exercise - no unkeyed one at all, so the
      // server's unkeyed "Custom" exercise below has zero local claimants
      // on the FIRST ack.
      Future<void>? fgSettled;
      repository.onBackgroundSyncScheduledForTesting = (s) => fgSettled = s;
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"Squat","exerciseTemplateId":1,"occurrenceKey":"squat-key"}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;

      await adapter.waitForCaptureCount(1);
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      final syncFuture = syncService.sync();
      await adapter.waitForCaptureCount(2);

      final response = sessionJson(
        id: 900,
        exercises: [
          exerciseJson(9001, sessionId: 900, name: 'Squat'),
          exerciseJson(
            9002,
            sessionId: 900,
            name: 'Custom',
            exerciseTemplateId: null,
            occurrenceKey: null,
          ),
        ],
      );

      // FIRST acknowledgment: Squat matches by key; Custom (null-keyed, no
      // local claimant) is inserted fresh, already synced.
      heldFirst.complete(jsonResponse(response));
      await fgSettled;

      final afterFirst =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(afterFirst.length, 2);
      final customAfterFirst = afterFirst.singleWhere(
        (e) => e.name == 'Custom',
      );
      expect(customAfterFirst.serverId, 9002);
      expect(customAfterFirst.syncStatus, 'synced');
      expect(customAfterFirst.isSynced, isTrue);

      // SECOND, redundant acknowledgment for the SAME operation - the
      // IDENTICAL response. Without the already-resolved-by-serverId
      // preface, Custom would now be seen as a local claimant of the
      // null-occurrenceKey group and demoted to 'conflict'.
      heldSecond.complete(jsonResponse(response));
      await syncFuture;
      SyncService.reset();

      final afterSecond =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(
        afterSecond.length,
        2,
        reason: 'no duplicate inserted on the redundant ack either',
      );
      final customAfterSecond = afterSecond.singleWhere(
        (e) => e.name == 'Custom',
      );
      expect(
        customAfterSecond.serverId,
        9002,
        reason: 'identity retained across the redundant ack',
      );
      expect(
        customAfterSecond.syncStatus,
        'synced',
        reason:
            'never demoted to conflict - the redundant ack must be a safe '
            'no-op for an already-resolved identity, even a null-keyed one',
      );
      expect(customAfterSecond.isSynced, isTrue);
      final squatAfterSecond = afterSecond.singleWhere(
        (e) => e.name == 'Squat',
      );
      expect(squatAfterSecond.serverId, 9001);
      expect(squatAfterSecond.syncStatus, 'synced');
    });

    test('null occurrenceKey establishes NO identity: a local exercise from a '
        'legacy cached template (no occurrenceKey at all) with a recorded Set '
        'is never paired with a DIFFERENT exercise the server returns, even '
        'though both have a null key and there is exactly one on each side '
        '- this is Task 5\'s legacy-cache handling', () async {
      loginAs(userA);
      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;

      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      // A single local placeholder "A" materialized from a cached template
      // entry that predates occurrenceKey entirely (no field in the JSON
      // at all, not even explicitly null).
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(exercisesJson: '[{"name":"A","exerciseTemplateId":1}]'),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;

      final aLocalId =
          (await isar.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(created.id)
                  .findFirst())!
              .localId;
      expect(
        (await isar.localExercises.get(aLocalId))!.occurrenceKey,
        isNull,
        reason: 'sanity check: the legacy template entry carried no key',
      );
      final loggedSet = LocalExerciseSet(
        exerciseLocalId: aLocalId,
        setNumber: 1,
        reps: 12,
        weight: 30,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

      // Server materializes a DIFFERENT exercise "C" - also null-keyed
      // (self-healing only fills in a key when the SOURCE template lacked
      // one; here the source is simulated as still missing it at
      // materialization time). Count is exactly 1-vs-1, but `null` carries
      // no identity - this must NOT be treated the same as a genuine
      // `occurrenceKey` match.
      held.complete(
        jsonResponse(
          sessionJson(
            id: 900,
            exercises: [
              exerciseJson(
                9001,
                sessionId: 900,
                name: 'C',
                exerciseTemplateId: 1,
                occurrenceKey: null,
              ),
            ],
          ),
        ),
      );
      await settled;

      final aAfter = await isar.localExercises.get(aLocalId);
      expect(aAfter, isNotNull);
      expect(aAfter!.name, 'A', reason: "never overwritten with C's name");
      expect(
        aAfter.serverId,
        isNull,
        reason:
            'null identity is not proof A and C are the same '
            'occurrence - never assign an uncertain server parent to A',
      );
      expect(aAfter.syncStatus, 'conflict');

      final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
      expect(setAfter, isNotNull);
      expect(
        setAfter!.exerciseLocalId,
        aLocalId,
        reason: "A's Set is never re-pointed to C or C's serverId",
      );
      expect(setAfter.reps, 12);

      // C is likewise left unresolved (never inserted) - a null-keyed
      // group is ambiguous the moment ANY local exercise claims it,
      // exactly like a non-null ambiguous group's server exercises are
      // dropped rather than inserted (see
      // `ModelMapper.pairProgramWorkoutCreateExercises`'s doc comment):
      // there is no way to tell whether C is a genuinely new exercise or
      // actually IS "A", renamed. C is not permanently lost - a later GET
      // refresh (matching by serverId, then by occurrenceKey via
      // `_resolveExistingExerciseForRefresh`, neither of which a null key
      // can satisfy) would still discover and cache it as a new row,
      // exactly like it would for any other exercise this session doesn't
      // yet know about locally - but this reconciliation itself never
      // guesses. This is the disclosed, unresolvable-without-a-key case
      // Task 5 asks to define explicitly rather than paper over.
      final allExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(
        allExercises.length,
        1,
        reason: 'only A - C is never substituted in nor duplicated',
      );
      expect(allExercises.single.localId, aLocalId);
    });

    test('null occurrenceKey, but NO local unkeyed exercise at all: the '
        "server's unkeyed exercise is safely inserted as new - nothing local "
        'claims a null-keyed identity for it to conflict with', () async {
      loginAs(userA);
      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;

      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      // Only a real-keyed local exercise - no unkeyed one at all.
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"Squat","exerciseTemplateId":1,"occurrenceKey":"squat-key"}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;

      // Server also materializes an unkeyed exercise - e.g. the template
      // gained a custom entry between dispatch and accept, and that entry
      // itself has no key either.
      held.complete(
        jsonResponse(
          sessionJson(
            id: 900,
            exercises: [
              exerciseJson(9001, sessionId: 900, name: 'Squat'),
              exerciseJson(
                9002,
                sessionId: 900,
                name: 'Custom',
                exerciseTemplateId: null,
                occurrenceKey: null,
              ),
            ],
          ),
        ),
      );
      await settled;

      final allExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(allExercises.length, 2, reason: 'Squat (matched) + Custom (new)');
      final customRow = allExercises.singleWhere((e) => e.name == 'Custom');
      expect(
        customRow.serverId,
        9002,
        reason:
            'safely inserted - no local null-keyed exercise to '
            'possibly conflict with',
      );
      expect(customRow.syncStatus, 'synced');
      expect(customRow.exerciseTemplateId, isNull);
      expect(customRow.occurrenceKey, isNull);
    });

    test("'conflict' marking prevents the ambiguous exercise from being "
        'independently re-created by a later SyncService pass - resolving '
        'ambiguity without automatically duplicating exercises', () async {
      loginAs(userA);
      adapter.responder =
          (o) => Future.value(
            jsonResponse(
              sessionJson(
                id: 900,
                exercises: [
                  exerciseJson(
                    9101,
                    sessionId: 900,
                    name: 'Curl',
                    exerciseTemplateId: 7,
                    occurrenceKey: null,
                  ),
                  exerciseJson(
                    9102,
                    sessionId: 900,
                    name: 'Curl',
                    exerciseTemplateId: 7,
                    occurrenceKey: null,
                  ),
                ],
              ),
            ),
          );
      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      // Both local occurrences are unkeyed (legacy cached template) and
      // share the same exerciseTemplateId - the classic pre-occurrenceKey
      // ambiguous pair.
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"Curl A","exerciseTemplateId":7},'
              '{"name":"Curl B","exerciseTemplateId":7}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;
      await settled;

      final ambiguous =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(ambiguous.length, 2);
      for (final e in ambiguous) {
        expect(e.syncStatus, 'conflict');
        expect(e.serverId, isNull);
      }

      adapter.captured.clear();
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await syncService.sync();
      SyncService.reset();

      expect(
        adapter.captured.any((r) => r.path.contains('/exercises')),
        isFalse,
        reason:
            "'conflict' rows are never independently dispatched via "
            '_syncExercises - no NEW exercise is created server-side on '
            'top of the 2 that already exist there',
      );
      final stillAmbiguous =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(stillAmbiguous.length, 2, reason: 'no duplicate rows created');
      for (final e in stillAmbiguous) {
        expect(e.syncStatus, 'conflict');
        expect(e.serverId, isNull);
      }
    });

    test(
      'CLOSED gap: a subsequent GET refresh of the SAME session, once the '
      'ambiguous occurrences carry real, distinct occurrenceKeys, matches '
      'them by key via `_resolveExistingExerciseForRefresh` instead of '
      'inserting duplicate rows - the previously-disclosed refresh-'
      'duplication gap is closed by the deployed occurrenceKey contract',
      () async {
        loginAs(userA);
        adapter.responder =
            (o) => Future.value(
              jsonResponse(
                sessionJson(
                  id: 900,
                  exercises: [
                    exerciseJson(
                      9101,
                      sessionId: 900,
                      name: 'Curl',
                      exerciseTemplateId: 7,
                      occurrenceKey: 'curl-a',
                    ),
                    exerciseJson(
                      9102,
                      sessionId: 900,
                      name: 'Curl',
                      exerciseTemplateId: 7,
                      occurrenceKey: 'curl-b',
                    ),
                  ],
                ),
              ),
            );
        Future<void>? settled;
        repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
        final created = await repository.createSessionFromProgramWorkout(
          10,
          workout(
            exercisesJson:
                '[{"name":"Curl A","exerciseTemplateId":7,"occurrenceKey":"curl-a"},'
                '{"name":"Curl B","exerciseTemplateId":7,"occurrenceKey":"curl-b"}]',
          ),
          DateTime(2031, 1, 1),
          5,
        );
        repository.onBackgroundSyncScheduledForTesting = null;
        await settled;

        final matchedBefore =
            await isar.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(created.id)
                  .findAll()
              ..sort((a, b) => a.localId.compareTo(b.localId));
        expect(matchedBefore.length, 2);
        final curlALocalId = matchedBefore[0].localId;
        expect(matchedBefore[0].serverId, 9101);
        expect(matchedBefore[1].serverId, 9102);
        final loggedSet = LocalExerciseSet(
          exerciseLocalId: curlALocalId,
          setNumber: 1,
          reps: 10,
          weight: 20,
          isCompleted: true,
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime.now().toUtc(),
        );
        await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

        // A subsequent GET /sessions/{id} refresh of the SAME session, same
        // two exercises.
        adapter.responder =
            (o) => Future.value(
              jsonResponse(
                sessionJson(
                  id: 900,
                  exercises: [
                    exerciseJson(
                      9101,
                      sessionId: 900,
                      name: 'Curl',
                      exerciseTemplateId: 7,
                      occurrenceKey: 'curl-a',
                    ),
                    exerciseJson(
                      9102,
                      sessionId: 900,
                      name: 'Curl',
                      exerciseTemplateId: 7,
                      occurrenceKey: 'curl-b',
                    ),
                  ],
                ),
              ),
            );
        await repository.getSession(created.id);

        final afterRefresh =
            await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(created.id)
                .findAll();
        // No duplicate rows: `_resolveExistingExerciseForRefresh` finds each
        // exercise first by serverId (already attached from the CREATE
        // ack), so both simply update the SAME two existing rows in place.
        expect(
          afterRefresh.length,
          2,
          reason: 'refresh converges onto the SAME two rows, no duplicates',
        );
        expect(afterRefresh.map((e) => e.serverId).toSet(), {9101, 9102});

        // The Set logged in between is never misattached.
        final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
        expect(setAfter, isNotNull);
        expect(setAfter!.exerciseLocalId, curlALocalId);
      },
    );

    test(
      'CLOSED gap, still-conflicted case: a refresh recognizes a still-'
      '`conflict`-marked ambiguous occurrence by occurrenceKey once the '
      'server later serves it as a genuinely unique key (e.g. the '
      'ambiguity was between local rows only, not the server side), '
      'converging onto the existing row instead of inserting a duplicate',
      () async {
        loginAs(userA);
        // The CREATE ack response has NO occurrenceKey on its single
        // exercise (server-side legacy/self-heal timing edge case), so with
        // 2 local occurrences sharing a null key, both stay unresolved
        // ('conflict').
        adapter.responder =
            (o) => Future.value(
              jsonResponse(sessionJson(id: 900, exercises: const [])),
            );
        Future<void>? settled;
        repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
        final created = await repository.createSessionFromProgramWorkout(
          10,
          workout(
            exercisesJson:
                '[{"name":"Curl A","exerciseTemplateId":7,"occurrenceKey":"curl-a"}]',
          ),
          DateTime(2031, 1, 1),
          5,
        );
        repository.onBackgroundSyncScheduledForTesting = null;
        await settled;

        final before =
            (await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(created.id)
                .findFirst())!;
        // The CREATE response carried zero exercises at all (e.g. lost in
        // transit / a degenerate ack) - the local placeholder is left
        // unmatched, marked 'conflict'.
        expect(before.syncStatus, 'conflict');
        expect(before.serverId, isNull);

        // A LATER GET refresh of the same session now returns the real
        // server exercise, carrying the SAME occurrenceKey the local row was
        // always holding.
        adapter.responder =
            (o) => Future.value(
              jsonResponse(
                sessionJson(
                  id: 900,
                  exercises: [
                    exerciseJson(
                      9101,
                      sessionId: 900,
                      name: 'Curl A',
                      exerciseTemplateId: 7,
                      occurrenceKey: 'curl-a',
                    ),
                  ],
                ),
              ),
            );
        await repository.getSession(created.id);

        final afterRefresh =
            await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(created.id)
                .findAll();
        expect(
          afterRefresh.length,
          1,
          reason:
              'the refresh recognized the previously-conflicted row by its '
              'occurrenceKey and converged onto it, rather than inserting a '
              'second row',
        );
        expect(afterRefresh.single.localId, before.localId);
        expect(afterRefresh.single.serverId, 9101);
        expect(afterRefresh.single.syncStatus, 'synced');
      },
    );

    test('STILL DISCLOSED for a keyless legacy row: a subsequent GET refresh '
        "cannot recognize an already-conflicted null-keyed occurrence "
        '(no occurrenceKey to match by at all) and inserts an additional '
        'local row for the server\'s real occurrence - proven here rather '
        'than merely claimed, and confirmed to never misattach the original '
        'Set', () async {
      loginAs(userA);
      adapter.responder =
          (o) => Future.value(
            jsonResponse(
              sessionJson(
                id: 900,
                exercises: [
                  exerciseJson(
                    9101,
                    sessionId: 900,
                    name: 'Curl',
                    exerciseTemplateId: 7,
                    occurrenceKey: null,
                  ),
                  exerciseJson(
                    9102,
                    sessionId: 900,
                    name: 'Curl',
                    exerciseTemplateId: 7,
                    occurrenceKey: null,
                  ),
                ],
              ),
            ),
          );
      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"Curl A","exerciseTemplateId":7},'
              '{"name":"Curl B","exerciseTemplateId":7}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;
      await settled;

      final ambiguousBefore =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      final curlALocalId = ambiguousBefore[0].localId;
      final loggedSet = LocalExerciseSet(
        exerciseLocalId: curlALocalId,
        setNumber: 1,
        reps: 10,
        weight: 20,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

      // A subsequent GET /sessions/{id} refresh of the SAME session - still
      // no occurrenceKey on either server exercise (a legacy/unhealed
      // response).
      adapter.responder =
          (o) => Future.value(
            jsonResponse(
              sessionJson(
                id: 900,
                exercises: [
                  exerciseJson(
                    9101,
                    sessionId: 900,
                    name: 'Curl',
                    exerciseTemplateId: 7,
                    occurrenceKey: null,
                  ),
                  exerciseJson(
                    9102,
                    sessionId: 900,
                    name: 'Curl',
                    exerciseTemplateId: 7,
                    occurrenceKey: null,
                  ),
                ],
              ),
            ),
          );
      await repository.getSession(created.id);

      final afterRefresh =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      // DISCLOSED gap: with no occurrenceKey to match by,
      // `_resolveExistingExerciseForRefresh` cannot recognize 9101/9102 as
      // possibly corresponding to the conflicted local pair, so it caches
      // them as two ADDITIONAL, separately-synced rows - this branch does
      // not claim full convergence for a keyless occurrence.
      expect(
        afterRefresh.length,
        4,
        reason:
            '2 conflicted local rows + 2 newly-inserted synced rows from '
            'the refresh - a real, disclosed duplication in the LOCAL '
            'exercise list for a legacy occurrence with no key at all',
      );
      expect(
        afterRefresh.where((e) => e.syncStatus == 'conflict').length,
        2,
        reason: 'the original conflicted pair is untouched by the refresh',
      );
      expect(
        afterRefresh.where((e) => e.syncStatus == 'synced').length,
        2,
        reason: 'the refresh-inserted pair',
      );

      // Critically: even with this disclosed local-list duplication, the
      // ORIGINAL Set is never misattached - it stays on the SAME,
      // untouched, still-conflicted local exercise it was always on.
      final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
      expect(setAfter, isNotNull);
      expect(setAfter!.exerciseLocalId, curlALocalId);
      final curlAAfter = await isar.localExercises.get(curlALocalId);
      expect(curlAAfter!.syncStatus, 'conflict');
      expect(curlAAfter.serverId, isNull);
    });

    test('ad-hoc exercises (no exerciseTemplateId at all) are distinguished '
        'by occurrenceKey exactly like templated ones - two custom entries '
        'each match their own server occurrence unambiguously', () async {
      loginAs(userA);
      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;

      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"Custom A","occurrenceKey":"custom-a"},'
              '{"name":"Custom B","occurrenceKey":"custom-b"}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;

      final localExercises =
          await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(created.id)
                .findAll()
            ..sort((a, b) => a.localId.compareTo(b.localId));
      expect(localExercises.every((e) => e.exerciseTemplateId == null), isTrue);
      final customALocalId = localExercises[0].localId;
      final customBLocalId = localExercises[1].localId;

      final setOnA = LocalExerciseSet(
        exerciseLocalId: customALocalId,
        setNumber: 1,
        reps: 15,
        weight: 0,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(setOnA));

      // Server returns them in the OPPOSITE order.
      held.complete(
        jsonResponse(
          sessionJson(
            id: 900,
            exercises: [
              exerciseJson(
                9002,
                sessionId: 900,
                name: 'Custom B',
                exerciseTemplateId: null,
                occurrenceKey: 'custom-b',
              ),
              exerciseJson(
                9001,
                sessionId: 900,
                name: 'Custom A',
                exerciseTemplateId: null,
                occurrenceKey: 'custom-a',
              ),
            ],
          ),
        ),
      );
      await settled;

      final customAAfter = await isar.localExercises.get(customALocalId);
      final customBAfter = await isar.localExercises.get(customBLocalId);
      expect(customAAfter!.serverId, 9001, reason: 'matched by "custom-a"');
      expect(customAAfter.syncStatus, 'synced');
      expect(customBAfter!.serverId, 9002, reason: 'matched by "custom-b"');
      expect(customBAfter.syncStatus, 'synced');

      final setAfter = await isar.localExerciseSets.get(setOnA.localId);
      expect(setAfter!.exerciseLocalId, customALocalId);

      final allExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(allExercises.length, 2, reason: 'no duplicates inserted');
    });

    test('an occurrence removed entirely (not replaced) before server '
        'materialization: the local placeholder is left unresolved, marked '
        '\'conflict\', and NOTHING is inserted to fill the gap - the '
        'occurrence is simply gone from the server\'s response', () async {
      loginAs(userA);
      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;

      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(
          exercisesJson:
              '[{"name":"A","exerciseTemplateId":1,"occurrenceKey":"a-key"},'
              '{"name":"B","exerciseTemplateId":2,"occurrenceKey":"b-key"}]',
        ),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;

      final localExercises =
          await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(created.id)
                .findAll()
            ..sort((a, b) => a.localId.compareTo(b.localId));
      final aLocalId = localExercises[0].localId;
      final loggedSet = LocalExerciseSet(
        exerciseLocalId: aLocalId,
        setNumber: 1,
        reps: 8,
        weight: 30,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

      // The template's "A" entry was deleted (not replaced) before the
      // server materialized - only "B" comes back.
      held.complete(
        jsonResponse(
          sessionJson(
            id: 900,
            exercises: [
              exerciseJson(
                9002,
                sessionId: 900,
                name: 'B',
                exerciseTemplateId: 2,
                occurrenceKey: 'b-key',
              ),
            ],
          ),
        ),
      );
      await settled;

      final aAfter = await isar.localExercises.get(aLocalId);
      expect(aAfter, isNotNull, reason: 'preserved, never discarded');
      expect(aAfter!.syncStatus, 'conflict');
      expect(aAfter.serverId, isNull);
      final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
      expect(setAfter!.exerciseLocalId, aLocalId, reason: 'Set preserved');

      final bAfter = await isar.localExercises.get(localExercises[1].localId);
      expect(bAfter!.serverId, 9002);
      expect(bAfter.syncStatus, 'synced');

      final allExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(created.id)
              .findAll();
      expect(
        allExercises.length,
        2,
        reason:
            'still exactly A (conflicted) and B (synced) - nothing '
            'invented to fill the removed occurrence',
      );
    });

    test('two intentional Sessions - from separate ProgramWorkout rows that '
        'happen to carry the exact SAME occurrenceKey values (e.g. the same '
        'weekly template reused for two different weeks, each its own '
        'ProgramWorkout row per the API\'s weekNumber/dayNumber shape) - '
        'never cross-match: each Session\'s reconciliation is scoped to its '
        'own children only', () async {
      loginAs(userA);

      // First Session, from programWorkout 10: dispatched and acknowledged.
      adapter.responder =
          (o) => Future.value(
            jsonResponse(
              sessionJson(
                id: 900,
                programWorkoutId: 10,
                exercises: [
                  exerciseJson(9001, sessionId: 900, name: 'Squat'),
                  exerciseJson(
                    9002,
                    sessionId: 900,
                    name: 'Lunge',
                    exerciseTemplateId: 2,
                    occurrenceKey: 'lunge-key',
                    restTime: 60,
                  ),
                ],
              ),
            ),
          );
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          10,
          workout(id: 10, exercisesJson: twoExercisesJson),
          DateTime(2031, 6, 15),
          5,
        ),
      );
      final firstSessionRow =
          (await isar.localSessions.filter().serverIdEqualTo(900).findFirst())!;

      // Second, entirely separate intentional Session, from a DIFFERENT
      // ProgramWorkout row (week 2's copy of the same "Leg Day" template) -
      // carrying the exact SAME occurrenceKey values, since it is
      // materialized from the same cached template content.
      adapter.captured.clear();
      adapter.responder =
          (o) => Future.value(
            jsonResponse(
              sessionJson(
                id: 901,
                programWorkoutId: 11,
                date: '2031-06-22',
                exercises: [
                  exerciseJson(9101, sessionId: 901, name: 'Squat'),
                  exerciseJson(
                    9102,
                    sessionId: 901,
                    name: 'Lunge',
                    exerciseTemplateId: 2,
                    occurrenceKey: 'lunge-key',
                    restTime: 60,
                  ),
                ],
              ),
            ),
          );
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          11,
          workout(id: 11, exercisesJson: twoExercisesJson),
          DateTime(2031, 6, 22),
          5,
        ),
      );
      final secondSessionRow =
          (await isar.localSessions.filter().serverIdEqualTo(901).findFirst())!;
      expect(secondSessionRow.localId, isNot(firstSessionRow.localId));

      // Each Session's own exercises matched to ITS OWN server response,
      // never the other Session's - even though both share "squat-key" /
      // "lunge-key".
      final firstExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(firstSessionRow.localId)
              .findAll();
      final secondExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(secondSessionRow.localId)
              .findAll();
      expect(firstExercises.length, 2);
      expect(secondExercises.length, 2);
      expect(
        firstExercises.map((e) => e.serverId).toSet(),
        {9001, 9002},
        reason: 'first Session\'s exercises attached to the FIRST server ids',
      );
      expect(
        secondExercises.map((e) => e.serverId).toSet(),
        {9101, 9102},
        reason:
            'second Session\'s exercises attached to the SECOND server ids '
            '- never cross-matched with the first Session\'s, despite '
            'sharing the same occurrenceKey values',
      );
      // Both Sessions' "lunge-key" exercises kept the SAME key locally, but
      // each points to its own, distinct parent session/serverId.
      final firstLunge = firstExercises.singleWhere((e) => e.name == 'Lunge');
      final secondLunge = secondExercises.singleWhere((e) => e.name == 'Lunge');
      expect(firstLunge.occurrenceKey, 'lunge-key');
      expect(secondLunge.occurrenceKey, 'lunge-key');
      expect(firstLunge.sessionLocalId, firstSessionRow.localId);
      expect(secondLunge.sessionLocalId, secondSessionRow.localId);
    });

    test('CREATE response lost (network error), then a later SyncService '
        'replay succeeds and matches the replayed Exercises by occurrenceKey '
        '- the retry\'s acknowledgment reconciliation behaves identically to '
        'the original dispatch\'s', () async {
      loginAs(userA);
      adapter.responder =
          (o) => Future<ResponseBody>.error(
            DioException(
              requestOptions: o,
              type: DioExceptionType.connectionError,
            ),
          );
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          10,
          workout(exercisesJson: twoExercisesJson),
          DateTime(2031, 1, 1),
          5,
        ),
      );
      final rowBefore =
          await isar.localSessions
              .filter()
              .programWorkoutIdEqualTo(10)
              .findFirst();
      expect(rowBefore!.syncStatus, 'pending_create');
      final localExercisesBefore =
          await isar.localExercises
                .filter()
                .sessionLocalIdEqualTo(rowBefore.localId)
                .findAll()
            ..sort((a, b) => a.localId.compareTo(b.localId));
      expect(localExercisesBefore.length, 2);
      final squatLocalId = localExercisesBefore[0].localId;
      final lungeLocalId = localExercisesBefore[1].localId;
      final loggedSet = LocalExerciseSet(
        exerciseLocalId: squatLocalId,
        setNumber: 1,
        reps: 5,
        weight: 100,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

      // A later SyncService pass replays the SAME CREATE (server never
      // materialized a Session for the lost request) - this time it
      // succeeds, and the replayed Exercises carry the SAME occurrenceKeys
      // the original dispatch's did (the server never re-reads the source
      // workout on replay - see GoHardAPI's `ProgramWorkoutSessionMaterializer`
      // doc comment).
      adapter.responder =
          (o) => Future.value(
            jsonResponse(
              sessionJson(
                id: 900,
                exercises: [
                  exerciseJson(9001, sessionId: 900, name: 'Squat'),
                  exerciseJson(
                    9002,
                    sessionId: 900,
                    name: 'Lunge',
                    exerciseTemplateId: 2,
                    occurrenceKey: 'lunge-key',
                    restTime: 60,
                  ),
                ],
              ),
            ),
          );
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await syncService.sync();
      SyncService.reset();

      final sessionAfter = await isar.localSessions.get(rowBefore.localId);
      expect(sessionAfter!.serverId, 900);
      expect(sessionAfter.syncStatus, 'synced');

      final squatAfter = await isar.localExercises.get(squatLocalId);
      final lungeAfter = await isar.localExercises.get(lungeLocalId);
      expect(squatAfter!.serverId, 9001, reason: 'matched by "squat-key"');
      expect(squatAfter.syncStatus, 'synced');
      expect(lungeAfter!.serverId, 9002, reason: 'matched by "lunge-key"');
      expect(lungeAfter.syncStatus, 'synced');

      // The Set logged before the replay is still attached to the SAME
      // stable local exercise row.
      final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
      expect(setAfter!.exerciseLocalId, squatLocalId);
      expect(setAfter.reps, 5);

      final allExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(rowBefore.localId)
              .findAll();
      expect(allExercises.length, 2, reason: 'no duplicates from the replay');
    });
  });

  // ==========================================================================
  // 10. Delete before/during CREATE converges without resurrection
  // ==========================================================================

  group('delete before/during CREATE', () {
    test(
      '10a. deleting before server identity is known dispatches '
      'cancel-by-operation, which resolves BEFORE the delayed CREATE POST '
      'responds - a late CREATE acknowledgment cannot resurrect the row',
      () async {
        loginAs(userA);
        final held = Completer<ResponseBody>();
        adapter.responder = (o) {
          if (o.path == ApiConfig.sessionsFromProgramWorkout) {
            return held.future;
          }
          return Future.value(ResponseBody.fromString('', 204, headers: {}));
        };

        Future<void>? settled;
        repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
        final created = await repository.createSessionFromProgramWorkout(
          10,
          workout(exercisesJson: twoExercisesJson),
          DateTime(2031, 1, 1),
          5,
        );
        repository.onBackgroundSyncScheduledForTesting = null;

        // The cancel-by-operation DELETE resolves immediately (204, not
        // held) - deleteSession awaits it synchronously, so cancellation
        // fully completes (hard-deleting the row) before this call returns.
        final result = await repository.deleteSession(created.id);
        expect(result, isTrue);

        final cancelCall = adapter.captured.lastWhere(
          (r) => r.method == 'DELETE',
        );
        expect(
          cancelCall.path.contains('by-operation'),
          isTrue,
          reason: 'cancellation, not DELETE-by-id (no serverId existed)',
        );
        expect(
          await isar.localSessions.get(created.id),
          isNull,
          reason: 'cancellation already converged - fully removed',
        );

        // NOW the CREATE ack arrives, late - the row is already gone, so
        // this must be a pure no-op: no resurrection, no orphaned Session
        // ever left dangling server-side under this key (the cancel already
        // took care of that).
        held.complete(jsonResponse(sessionJson(id: 900)));
        await settled;

        expect(
          await isar.localSessions.get(created.id),
          isNull,
          reason: 'still gone - the late ack neither resurrects nor errors',
        );
      },
    );
  });

  // ==========================================================================
  // Ownership recheck at acknowledgment time
  // ==========================================================================

  test('ownership recheck: a row reassigned to a DIFFERENT user at the same '
      'local id, exactly as the CREATE acknowledgment write begins, is never '
      'touched by it', () async {
    loginAs(userA);
    adapter.responder = (o) => Future.value(jsonResponse(sessionJson(id: 900)));

    Future<void>? settled;
    repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
    repository.insideBackgroundWriteTxnForTesting = () async {
      final current = (await isar.localSessions.get(1))!;
      current.userId = userB;
      await isar.localSessions.put(current);
    };

    final created = await repository.createSessionFromProgramWorkout(
      10,
      workout(),
      DateTime(2031, 1, 1),
      5,
    );
    await settled;
    repository.insideBackgroundWriteTxnForTesting = null;

    final after = await isar.localSessions.get(created.id);
    expect(after, isNotNull);
    expect(after!.userId, userB);
    expect(
      after.serverId,
      isNull,
      reason:
          'a row reassigned to a different user must never be '
          "acknowledged by A's stale CREATE",
    );
    expect(after.syncStatus, 'pending_create');
  });

  test('ownership recheck (SyncService path): a row reassigned to a DIFFERENT '
      'user at the same local id, exactly as the SyncService retry\'s own '
      'acknowledgment write begins, is never touched by it', () async {
    loginAs(userA);
    // Offline, so the repository never dispatches its own background
    // CREATE - only SyncService's retry pass will.
    when(mockConnectivity.isOnline).thenReturn(false);
    final created = await repository.createSessionFromProgramWorkout(
      10,
      workout(),
      DateTime(2031, 1, 1),
      5,
    );
    when(mockConnectivity.isOnline).thenReturn(true);
    adapter.responder = (o) => Future.value(jsonResponse(sessionJson(id: 900)));

    final syncService = SyncService(
      apiService: apiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: mockConnectivity,
      sessionEpoch: sessionEpoch,
      sessionCoordinator: sessionCoordinator,
    );
    syncService.insideAckWriteTxnForTesting = () async {
      final current = (await isar.localSessions.get(created.id))!;
      current.userId = userB;
      await isar.localSessions.put(current);
    };

    await syncService.sync();
    SyncService.reset();

    final after = await isar.localSessions.get(created.id);
    expect(after, isNotNull);
    expect(after!.userId, userB);
    expect(
      after.serverId,
      isNull,
      reason:
          'a row reassigned to a different user must never be '
          "acknowledged by A's stale SyncService retry",
    );
    expect(after.syncStatus, 'pending_create');
  });

  // ==========================================================================
  // 12/13. Failure/cancellation typed contracts
  // ==========================================================================

  group('failure and cancellation contracts', () {
    test('12. 401/429/5xx all retain the durable intent and the SAME key - '
        'never rotated, never converted', () async {
      for (final status in [401, 429, 500]) {
        loginAs(userA);
        adapter.responder =
            (o) => Future.value(errorBody(status, {'code': 'server_error'}));
        await awaitBackgroundCreate(
          () => repository.createSessionFromProgramWorkout(
            10 + status,
            workout(id: 10 + status),
            DateTime(2031, 1, 1),
            5,
          ),
        );
        final row =
            await isar.localSessions
                .filter()
                .programWorkoutIdEqualTo(10 + status)
                .findFirst();
        expect(row!.syncStatus, 'pending_create', reason: '$status');
        expect(row.serverId, isNull, reason: '$status');
        expect(row.clientOperationId, isNotNull, reason: '$status');
      }
    });

    test('13a. 409 operation_canceled converts the row to pending_delete with '
        'the SAME key - never recreated on a later pass', () async {
      loginAs(userA);
      adapter.responder =
          (o) => Future.value(errorBody(409, {'code': 'operation_canceled'}));
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          10,
          workout(exercisesJson: twoExercisesJson),
          DateTime(2031, 1, 1),
          5,
        ),
      );

      final row =
          await isar.localSessions
              .filter()
              .programWorkoutIdEqualTo(10)
              .findFirst();
      expect(row!.syncStatus, 'pending_delete');
      final operationId = row.clientOperationId;
      expect(operationId, isNotNull);

      // A later cancel-by-operation pass converges it away, using the
      // SAME key.
      adapter.captured.clear();
      adapter.responder =
          (o) => Future.value(ResponseBody.fromString('', 204, headers: {}));
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await syncService.sync();
      SyncService.reset();

      final cancelCall = adapter.captured.singleWhere(
        (r) => r.method == 'DELETE',
      );
      expect(cancelCall.path, ApiConfig.sessionCancelByOperation(operationId!));
      expect(await isar.localSessions.get(row.localId), isNull);
    });

    test('13b. 410 operation_target_deleted retains the row (soft-retryable) '
        'without creating a duplicate Session on the next pass', () async {
      loginAs(userA);
      adapter.responder =
          (o) => Future.value(
            errorBody(410, {'code': 'operation_target_deleted'}),
          );
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          10,
          workout(),
          DateTime(2031, 1, 1),
          5,
        ),
      );

      final row =
          await isar.localSessions
              .filter()
              .programWorkoutIdEqualTo(10)
              .findFirst();
      expect(row!.syncStatus, 'pending_create');
      final operationId = row.clientOperationId;

      // A later retry (still 410, server holds the same tombstone) must
      // reuse the SAME key and never fork a second local row.
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await syncService.sync();
      SyncService.reset();

      final rows =
          await isar.localSessions
              .filter()
              .programWorkoutIdEqualTo(10)
              .findAll();
      expect(rows.length, 1);
      expect(rows.single.clientOperationId, operationId);
      expect(rows.single.syncStatus, 'pending_create');
    });

    test('13c. 404 program_not_found retains the durable intent - never '
        'silently discarded, never rotated', () async {
      loginAs(userA);
      adapter.responder =
          (o) => Future.value(errorBody(404, {'code': 'program_not_found'}));
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          10,
          workout(),
          DateTime(2031, 1, 1),
          5,
        ),
      );
      final row =
          await isar.localSessions
              .filter()
              .programWorkoutIdEqualTo(10)
              .findFirst();
      expect(row!.syncStatus, 'pending_create');
      expect(row.clientOperationId, isNotNull);
    });
  });

  // ==========================================================================
  // 14. Logout/relogin resumes; A/B isolation
  // ==========================================================================

  test(
    '14. logout preserves the intent; the SAME user logging back in resumes '
    'it with the SAME key; user B\'s sync pass never dispatches it',
    () async {
      loginAs(userA);
      adapter.responder =
          (o) => Future<ResponseBody>.error(
            DioException(
              requestOptions: o,
              type: DioExceptionType.connectionError,
            ),
          );
      await awaitBackgroundCreate(
        () => repository.createSessionFromProgramWorkout(
          10,
          workout(),
          DateTime(2031, 1, 1),
          5,
        ),
      );
      final rowBefore =
          await isar.localSessions
              .filter()
              .programWorkoutIdEqualTo(10)
              .findFirst();
      final operationId = rowBefore!.clientOperationId;

      logout();

      // User B logs in - B's sync pass must never see or dispatch A's row.
      loginAs(userB);
      adapter.captured.clear();
      final bSync = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await bSync.sync();
      SyncService.reset();
      expect(
        adapter.captured.any(
          (r) => r.path == ApiConfig.sessionsFromProgramWorkout,
        ),
        isFalse,
        reason: 'B must never dispatch A\'s pending create',
      );
      final stillA = await isar.localSessions.get(rowBefore.localId);
      expect(stillA!.userId, userA);
      expect(stillA.syncStatus, 'pending_create');

      logout();
      loginAs(userA);
      adapter.responder =
          (o) => Future.value(jsonResponse(sessionJson(id: 900)));
      final aSync = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await aSync.sync();
      SyncService.reset();

      final post = adapter.captured.singleWhere(
        (r) =>
            r.method == 'POST' &&
            r.path == ApiConfig.sessionsFromProgramWorkout,
      );
      expect(
        (post.data as Map<String, dynamic>)['clientOperationId'],
        operationId,
      );
      final rowAfter = await isar.localSessions.get(rowBefore.localId);
      expect(rowAfter!.serverId, 900);
      expect(rowAfter.syncStatus, 'synced');
    },
  );

  // ==========================================================================
  // Child (Exercise) dispatch guarded during Session deletion.
  //
  // The underlying mechanism (`SyncService._syncExercises`/
  // `_syncCreateExercise`) is generic - shared by every session in the app,
  // not specific to program-workout creation - but this branch's own
  // ambiguous-exercise handling (marking `unmatchedLocal` rows 'conflict')
  // made it newly possible to reach this interaction via a REGULAR
  // `pending_create` child added through `addExerciseToSession` (the
  // ordinary "add exercise mid-workout" entry point) on a program-workout
  // session already synced, so it is covered here rather than only in the
  // separately-existing generic delete-cancellation suites.
  // ==========================================================================

  group('child dispatch guarded during Session deletion', () {
    Future<int> createSyncedProgramWorkoutSession() async {
      adapter.responder =
          (o) => Future.value(jsonResponse(sessionJson(id: 900)));
      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      final created = await repository.createSessionFromProgramWorkout(
        10,
        workout(),
        DateTime(2031, 1, 1),
        5,
      );
      repository.onBackgroundSyncScheduledForTesting = null;
      await settled;
      final row = await isar.localSessions.get(created.id);
      expect(row!.serverId, 900, reason: 'test setup: session must be synced');
      expect(row.syncStatus, 'synced');
      return created.id;
    }

    /// Adds an ad-hoc exercise to [sessionId] and drives it fully synced
    /// (real `serverId`) via one SyncService pass - a prerequisite for any
    /// test that needs `_syncExerciseSets` to actually consider dispatching
    /// a CREATE for a Set under it (`_syncExerciseSets` skips a set whose
    /// parent exercise has no positive `serverId` yet).
    Future<int> addSyncedExercise(int sessionId, int exerciseServerId) async {
      adapter.captured.clear();
      adapter.responder =
          (o) => Future.value(jsonResponse({'id': exerciseServerId}));
      when(mockConnectivity.isOnline).thenReturn(false);
      await repository.addExerciseToSession(sessionId, 1);
      when(mockConnectivity.isOnline).thenReturn(true);
      final exLocalId =
          (await isar.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(sessionId)
                  .findFirst())!
              .localId;
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await syncService.sync();
      SyncService.reset();
      final exRow = await isar.localExercises.get(exLocalId);
      expect(
        exRow!.serverId,
        exerciseServerId,
        reason: 'test setup: exercise must be synced',
      );
      return exLocalId;
    }

    test('a Session already pending_delete never has a NEW child CREATE '
        'started against it - checked fresh at enumeration time', () async {
      loginAs(userA);
      final sessionId = await createSyncedProgramWorkoutSession();

      // Add a genuine pending_create child through the ordinary
      // "add exercise mid-workout" entry point, offline so it stays
      // local-only.
      when(mockConnectivity.isOnline).thenReturn(false);
      await repository.addExerciseToSession(sessionId, 1);
      when(mockConnectivity.isOnline).thenReturn(true);

      final childBefore =
          (await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(sessionId)
              .findFirst())!;
      expect(childBefore.syncStatus, 'pending_create');

      // The session is marked pending_delete (offline, so this is a pure
      // local write, no HTTP) BEFORE any sync pass ever runs.
      when(mockConnectivity.isOnline).thenReturn(false);
      final deleted = await repository.deleteSession(sessionId);
      expect(deleted, isTrue);
      when(mockConnectivity.isOnline).thenReturn(true);

      final sessionRow = await isar.localSessions.get(sessionId);
      expect(sessionRow!.syncStatus, 'pending_delete');

      // The session's OWN delete-by-id also fails this pass, so it stays
      // pending_delete (not yet hard-deleted/cascaded away) - isolating
      // whether the EXERCISE phase, on its own, ever dispatches the child.
      adapter.captured.clear();
      adapter.responder = (o) {
        if (o.method == 'DELETE') {
          return Future<ResponseBody>.error(
            DioException(
              requestOptions: o,
              type: DioExceptionType.connectionError,
            ),
          );
        }
        return Future.value(jsonResponse(const <dynamic>[]));
      };
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await syncService.sync();
      SyncService.reset();

      expect(
        await isar.localSessions.get(sessionId),
        isNotNull,
        reason:
            'the session itself is still only pending_delete, not yet '
            'converged, for this assertion to be meaningful',
      );
      expect(
        adapter.captured.any((r) => r.path.contains('/exercises')),
        isFalse,
        reason:
            'no new child CREATE work must start under a Session '
            'already pending_delete',
      );
      final childAfter = await isar.localExercises.get(childBefore.localId);
      expect(childAfter, isNotNull, reason: 'not lost - still local');
      expect(childAfter!.syncStatus, 'pending_create');
      expect(childAfter.serverId, isNull);
    });

    test('deletion racing an ALREADY-in-flight child CREATE: a late response '
        'converges without resurrecting the child - the deletion still '
        'converges on its own separate pass', () async {
      loginAs(userA);
      final sessionId = await createSyncedProgramWorkoutSession();

      when(mockConnectivity.isOnline).thenReturn(false);
      await repository.addExerciseToSession(sessionId, 1);
      when(mockConnectivity.isOnline).thenReturn(true);
      final childLocalId =
          (await isar.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(sessionId)
                  .findFirst())!
              .localId;

      // Reset the adapter's capture count - `createSyncedProgramWorkoutSession`
      // and `addExerciseToSession` already left entries behind, and
      // `waitForCaptureCount` below must wait for THIS exercise's own POST,
      // not resolve immediately against stale leftover captures.
      adapter.captured.clear();
      final held = Completer<ResponseBody>();
      adapter.responder = (o) {
        if (o.path.contains('/exercises')) return held.future;
        return Future.value(jsonResponse(const <dynamic>[]));
      };

      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      final syncFuture = syncService.sync();
      await adapter.waitForCaptureCount(1);
      expect(
        adapter.captured.single.path.contains('/exercises'),
        isTrue,
        reason:
            'sanity check: the captured request really is the child '
            'exercise CREATE, not some other call',
      );

      // WHILE the child's CREATE POST is held in flight, an independent
      // actor (e.g. the user tapping delete, or another sync pass)
      // converges the session to pending_delete.
      final sessionRowMidFlight = (await isar.localSessions.get(sessionId))!;
      sessionRowMidFlight.syncStatus = 'pending_delete';
      sessionRowMidFlight.lastModifiedLocal = DateTime.now().toUtc();
      await isar.writeTxn(() => isar.localSessions.put(sessionRowMidFlight));

      // NOW the late response arrives - the child's server row WAS
      // actually created.
      held.complete(jsonResponse({'id': 9999}));
      await syncFuture;
      SyncService.reset();

      final childAfter = await isar.localExercises.get(childLocalId);
      expect(childAfter, isNotNull, reason: 'not lost');
      expect(
        childAfter!.serverId,
        isNull,
        reason:
            'the late ack must never resurrect/mark this child synced '
            'once its parent has converged to pending_delete',
      );
      expect(childAfter.syncStatus, 'pending_create');
      expect(childAfter.isSynced, isFalse);
    });

    test(
      'retained local data when the Session\'s own cancellation/delete HTTP '
      'call fails: the pending_delete intent AND the still-unsynced child '
      'both survive, and the child is still never independently dispatched',
      () async {
        loginAs(userA);
        final sessionId = await createSyncedProgramWorkoutSession();

        when(mockConnectivity.isOnline).thenReturn(false);
        await repository.addExerciseToSession(sessionId, 1);
        when(mockConnectivity.isOnline).thenReturn(true);
        final childLocalId =
            (await isar.localExercises
                    .filter()
                    .sessionLocalIdEqualTo(sessionId)
                    .findFirst())!
                .localId;
        final loggedSet = LocalExerciseSet(
          exerciseLocalId: childLocalId,
          setNumber: 1,
          reps: 5,
          weight: 10,
          isCompleted: false,
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime.now().toUtc(),
        );
        await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

        // The session's own ordinary DELETE-by-id fails (network error).
        adapter.responder = (o) {
          if (o.method == 'DELETE' && !o.path.contains('by-operation')) {
            return Future<ResponseBody>.error(
              DioException(
                requestOptions: o,
                type: DioExceptionType.connectionError,
              ),
            );
          }
          return Future.value(jsonResponse(const <dynamic>[]));
        };
        final deleted = await repository.deleteSession(sessionId);
        expect(
          deleted,
          isTrue,
          reason: 'intent is durable regardless of the failed HTTP call',
        );

        final sessionRow = await isar.localSessions.get(sessionId);
        expect(sessionRow, isNotNull, reason: 'not lost despite the failure');
        expect(sessionRow!.syncStatus, 'pending_delete');

        // The still-unsynced child and its Set both survive untouched.
        final childRow = await isar.localExercises.get(childLocalId);
        expect(childRow, isNotNull);
        expect(childRow!.syncStatus, 'pending_create');
        expect(childRow.serverId, isNull);
        expect(await isar.localExerciseSets.get(loggedSet.localId), isNotNull);

        // A later sync pass retries the session's OWN delete and must
        // still never dispatch the child in the meantime.
        adapter.captured.clear();
        adapter.responder =
            (o) => Future.value(ResponseBody.fromString('', 204, headers: {}));
        final syncService = SyncService(
          apiService: apiService,
          authService: mockAuthService,
          localDb: localDb,
          connectivity: mockConnectivity,
          sessionEpoch: sessionEpoch,
          sessionCoordinator: sessionCoordinator,
        );
        await syncService.sync();
        SyncService.reset();

        expect(
          adapter.captured.any((r) => r.path.contains('/exercises')),
          isFalse,
          reason: 'still never dispatched, even once the retry pass runs',
        );
      },
    );

    // ========================================================================
    // Task 6: the SAME dispatch-guard protection, but for the ExerciseSet
    // path (`_syncExerciseSets`/`_syncCreateSet`) - a grandchild of the
    // Session, not a direct child. An acknowledgment guard alone does not
    // prove dispatch was prevented, so both tests below assert on the
    // actual captured HTTP traffic, not merely on the row's final state.
    // ========================================================================

    test('a Session already pending_delete never has a NEW ExerciseSet '
        'CREATE started against it either - checked fresh at enumeration '
        'time, with an explicit zero-HTTP-request assertion for the '
        'exercisesets endpoint specifically', () async {
      loginAs(userA);
      final sessionId = await createSyncedProgramWorkoutSession();
      final exerciseLocalId = await addSyncedExercise(sessionId, 8001);

      final loggedSet = LocalExerciseSet(
        exerciseLocalId: exerciseLocalId,
        setNumber: 1,
        reps: 5,
        weight: 40,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

      // The session is marked pending_delete (offline, pure local write)
      // BEFORE any sync pass ever runs.
      when(mockConnectivity.isOnline).thenReturn(false);
      final deleted = await repository.deleteSession(sessionId);
      expect(deleted, isTrue);
      when(mockConnectivity.isOnline).thenReturn(true);
      final sessionRow = await isar.localSessions.get(sessionId);
      expect(sessionRow!.syncStatus, 'pending_delete');

      // The session's own delete-by-id also fails this pass, so it stays
      // pending_delete - isolating whether the SET phase, on its own, ever
      // dispatches the child.
      adapter.captured.clear();
      adapter.responder = (o) {
        if (o.method == 'DELETE') {
          return Future<ResponseBody>.error(
            DioException(
              requestOptions: o,
              type: DioExceptionType.connectionError,
            ),
          );
        }
        return Future.value(jsonResponse(const <dynamic>[]));
      };
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      await syncService.sync();
      SyncService.reset();

      expect(
        await isar.localSessions.get(sessionId),
        isNotNull,
        reason:
            'the session itself is still only pending_delete, not yet '
            'converged, for this assertion to be meaningful',
      );
      expect(
        adapter.captured.any((r) => r.path.contains(ApiConfig.exerciseSets)),
        isFalse,
        reason:
            'zero HTTP requests to the exercisesets endpoint - no new '
            'child CREATE work must start under a Session already '
            'pending_delete',
      );
      final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
      expect(setAfter, isNotNull, reason: 'not lost - still local');
      expect(setAfter!.syncStatus, 'pending_create');
      expect(setAfter.serverId, isNull);
    });

    test('deletion racing an ALREADY-in-flight ExerciseSet CREATE: a late '
        'response converges without resurrecting the Set - the deletion '
        'still converges on its own separate pass', () async {
      loginAs(userA);
      final sessionId = await createSyncedProgramWorkoutSession();
      final exerciseLocalId = await addSyncedExercise(sessionId, 8001);

      final loggedSet = LocalExerciseSet(
        exerciseLocalId: exerciseLocalId,
        setNumber: 1,
        reps: 5,
        weight: 40,
        isCompleted: true,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(loggedSet));

      adapter.captured.clear();
      final held = Completer<ResponseBody>();
      adapter.responder = (o) {
        if (o.path.contains(ApiConfig.exerciseSets)) return held.future;
        return Future.value(jsonResponse(const <dynamic>[]));
      };
      final syncService = SyncService(
        apiService: apiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: mockConnectivity,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
      );
      final syncFuture = syncService.sync();
      await adapter.waitForCaptureCount(1);
      expect(
        adapter.captured.single.path.contains(ApiConfig.exerciseSets),
        isTrue,
        reason:
            'sanity check: the captured request really is the Set CREATE, '
            'not some other call',
      );

      // WHILE the Set's CREATE POST is held in flight, an independent actor
      // converges the session to pending_delete.
      final sessionRowMidFlight = (await isar.localSessions.get(sessionId))!;
      sessionRowMidFlight.syncStatus = 'pending_delete';
      sessionRowMidFlight.lastModifiedLocal = DateTime.now().toUtc();
      await isar.writeTxn(() => isar.localSessions.put(sessionRowMidFlight));

      // NOW the late response arrives - the Set's server row WAS actually
      // created.
      held.complete(jsonResponse({'id': 9999}));
      await syncFuture;
      SyncService.reset();

      final setAfter = await isar.localExerciseSets.get(loggedSet.localId);
      expect(setAfter, isNotNull, reason: 'not lost');
      expect(
        setAfter!.serverId,
        isNull,
        reason:
            'the late ack must never resurrect/mark this Set synced once '
            'its grandparent Session has converged to pending_delete',
      );
      expect(setAfter.syncStatus, 'pending_create');
      expect(setAfter.isSynced, isFalse);
    });
  });
}

/// Fake Dio transport: records every request and lets a test answer via a
/// `responder`. Mirrors the identical helper in
/// `session_create_client_operation_id_test.dart` /
/// `session_durable_cancellation_test.dart`.
class _CapturingHttpAdapter implements HttpClientAdapter {
  final List<RequestOptions> captured = [];
  Future<ResponseBody> Function(RequestOptions options)? responder;
  int? _awaitedCount;
  Completer<void>? _countSignal;

  /// Resolves once [captured] reaches [count] entries - lets a test await
  /// two concurrent dispatches actually reaching the adapter with no
  /// wall-clock wait or `Future.delayed` guess.
  Future<void> waitForCaptureCount(int count) {
    if (captured.length >= count) return Future.value();
    _awaitedCount = count;
    final c = Completer<void>();
    _countSignal = c;
    return c.future;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    captured.add(options);
    if (_awaitedCount != null && captured.length >= _awaitedCount!) {
      _countSignal?.complete();
      _countSignal = null;
      _awaitedCount = null;
    }
    final r = responder;
    if (r != null) return r(options);
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
