import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/lifted_weight_contract_migration.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_food_item.dart';
import 'package:go_hard_app/data/local/models/local_food_template.dart';
import 'package:go_hard_app/data/local/models/local_goal.dart';
import 'package:go_hard_app/data/local/models/local_meal_entry.dart';
import 'package:go_hard_app/data/local/models/local_meal_log.dart';
import 'package:go_hard_app/data/local/models/local_nutrition_goal.dart';
import 'package:go_hard_app/data/local/models/local_program.dart';
import 'package:go_hard_app/data/local/models/local_program_workout.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

/// Task 7: while the legacy purge is pending, a sync pass must never upload
/// session / exercise / set / program / programWorkout rows (they may be
/// legacy lb-semantic data and would now be sent with the kg header), but
/// the other phases keep running. Real [ApiService] over a fake transport so
/// every dispatched request is observable.
void main() {
  late Isar isar;
  late Directory tempDir;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late _FakeAuthService authService;
  String? state;
  late bool canonicalHistory;

  const userId = 1;
  final now = DateTime.utc(2026, 9, 1);

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_lifted_weight_gate_');
    isar = await Isar.open(
      [
        LocalSessionSchema,
        LocalExerciseSchema,
        LocalExerciseSetSchema,
        LocalProgramSchema,
        LocalProgramWorkoutSchema,
        LocalGoalSchema,
        LocalNutritionGoalSchema,
        LocalFoodTemplateSchema,
        LocalMealLogSchema,
        LocalMealEntrySchema,
        LocalFoodItemSchema,
      ],
      directory: tempDir.path,
      inspector: false,
    );
    authService = _FakeAuthService();
    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);
    sessionEpoch = UserSessionEpoch()..activate(userId);
    sessionCoordinator = SessionRequestCoordinator(sessionEpoch, authService);
    apiService = ApiService(authService, sessionEpoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
    state = null;
    canonicalHistory = false;
    adapter.responder = (options) async {
      if (options.path.endsWith(ApiConfig.liftedWeightContract)) {
        return _json({'canonicalHistory': canonicalHistory});
      }
      if (options.method == 'POST') return _json({'id': 900});
      return _json({});
    };
    SyncService.reset();
  });

  tearDown(() async {
    SyncService.reset();
    if (isar.isOpen) await isar.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  LiftedWeightContractMigration newMigration() => LiftedWeightContractMigration(
    database: () => isar,
    readState: () async => state,
    writeState: (json) async => state = json,
  );

  SyncService newSyncService(LiftedWeightContractMigration? migration) =>
      SyncService(
        apiService: apiService,
        authService: authService,
        localDb: localDb,
        connectivity: ConnectivityService.instance,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionCoordinator,
        liftedWeightMigration: migration,
      );

  /// One pending (unsynced) row in every workout collection plus a pending
  /// goal.
  Future<void> seedPendingWorkoutRowsAndGoal() async {
    await isar.writeTxn(() async {
      final session = LocalSession(
        userId: userId,
        date: now,
        lastModifiedLocal: now,
      );
      await isar.localSessions.put(session);
      final exercise = LocalExercise(
        sessionLocalId: session.localId,
        name: 'Bench',
        lastModifiedLocal: now,
      );
      await isar.localExercises.put(exercise);
      await isar.localExerciseSets.put(
        LocalExerciseSet(
          exerciseLocalId: exercise.localId,
          setNumber: 1,
          weight: 135,
          lastModifiedLocal: now,
        ),
      );
      final program = LocalProgram(
        userId: userId,
        title: 'P',
        totalWeeks: 4,
        currentWeek: 1,
        currentDay: 1,
        startDate: now,
        createdAt: now,
        lastModifiedLocal: now,
      );
      await isar.localPrograms.put(program);
      await isar.localProgramWorkouts.put(
        LocalProgramWorkout(
          programLocalId: program.localId,
          weekNumber: 1,
          dayNumber: 1,
          workoutName: 'W',
          exercisesJson: '[]',
          orderIndex: 0,
          lastModifiedLocal: now,
        ),
      );
      await isar.localGoals.put(
        LocalGoal(
          userId: userId,
          goalType: 'weight',
          targetValue: 1,
          currentValue: 0,
          startDate: now,
          createdAt: now,
          lastModifiedLocal: now,
        ),
      );
    });
  }

  bool isWorkoutPath(String path) => RegExp(
    r'(sessions|exercises|exercisesets|programs|programworkouts)',
    caseSensitive: false,
  ).hasMatch(path);

  List<String> dispatchedPaths() =>
      adapter.capturedRequests.map((r) => '${r.method} ${r.path}').toList();

  test('pending migration + server not canonical: no workout request is '
      'dispatched, goals still sync, nothing is purged', () async {
    await seedPendingWorkoutRowsAndGoal();
    final migration = newMigration();
    await migration.snapshotIfNeeded();

    await newSyncService(migration).sync();

    final paths = dispatchedPaths();
    expect(
      paths.where((p) => p.contains(ApiConfig.liftedWeightContract)),
      hasLength(1),
    );
    expect(paths.where(isWorkoutPath), isEmpty, reason: '$paths');
    expect(paths.where((p) => p.contains(ApiConfig.goals)), isNotEmpty);
    expect(await isar.localSessions.count(), 1);
    expect(await isar.localExerciseSets.count(), 1);
    expect(await isar.localPrograms.count(), 1);
    expect(await isar.localProgramWorkouts.count(), 1);
    expect(await migration.isComplete(), isFalse);
  });

  test('server reports canonical history: the same pass purges the legacy '
      'rows, completes, and then runs every phase', () async {
    await seedPendingWorkoutRowsAndGoal();
    final migration = newMigration();
    await migration.snapshotIfNeeded();
    // Created after the snapshot while gated: canonical, must be uploaded.
    final canonical = LocalSession(
      userId: userId,
      date: now,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localSessions.put(canonical));
    canonicalHistory = true;

    await newSyncService(migration).sync();

    expect(await migration.isComplete(), isTrue);
    final paths = dispatchedPaths();
    expect(paths.first, contains(ApiConfig.liftedWeightContract));
    // Legacy rows are gone before any upload; the canonical session uploads.
    expect(await isar.localExerciseSets.count(), 0);
    expect(await isar.localPrograms.count(), 0);
    expect(await isar.localProgramWorkouts.count(), 0);
    expect(
      paths.where((p) => p.startsWith('POST') && p.contains('sessions')),
      hasLength(1),
      reason: '$paths',
    );
    expect(paths.where((p) => p.contains(ApiConfig.goals)), isNotEmpty);
    final remaining = await isar.localSessions.where().findAll();
    expect(remaining.single.localId, canonical.localId);
  });

  test('without a migration the pass is unchanged: workout rows upload and '
      'no contract check is made', () async {
    await seedPendingWorkoutRowsAndGoal();

    await newSyncService(null).sync();

    final paths = dispatchedPaths();
    expect(
      paths.where((p) => p.contains(ApiConfig.liftedWeightContract)),
      isEmpty,
    );
    expect(paths.where(isWorkoutPath), isNotEmpty, reason: '$paths');
  });
}

ResponseBody _json(Object json) => ResponseBody.fromString(
  jsonEncode(json),
  200,
  headers: {
    'content-type': ['application/json'],
  },
);

class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];
  late Future<ResponseBody> Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuthService extends Mock implements AuthService {
  @override
  Future<int?> getUserId() async => 1;

  @override
  Future<String?> getToken() async => 'jwt-1';
}
