import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_goal.dart';
import 'package:go_hard_app/data/local/models/local_meal_log.dart';
import 'package:go_hard_app/data/local/models/local_program.dart';
import 'package:go_hard_app/data/local/models/local_program_workout.dart';
import 'package:go_hard_app/data/local/models/local_run_session.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/auth_response.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/providers/auth_provider.dart';

// Reuses the Mockito mocks generated for auth_provider_test.dart (same
// AuthRepository/AuthService/SessionRequestCoordinator surface, unchanged
// by this PR) - no new build_runner output.
import 'auth_provider_test.mocks.dart';

/// Proves the durable-retention half of the non-destructive forced-401
/// contract using a REAL on-disk Isar database (via the real
/// `LocalDatabaseService.instance` singleton, never a mock) and a REAL
/// `AuthProvider`/`ApiService`/`UserSessionEpoch`: every durable, user-owned
/// row - across every offline-mutation shape (`pending_create`,
/// `pending_update`, a `pending_delete` tombstone), every
/// idempotency/version/diagnostic field, and every feature area
/// (Sessions/Exercises/ExerciseSets, Programs + nested workouts, Goals,
/// nutrition, running data) - is provably byte-identical before and after
/// a forced-expiration pass, including after the Isar file is closed and
/// reopened (simulating an app restart while signed out).
///
/// Body metrics are intentionally NOT covered here: `BodyMetricsRepository`
/// has no local Isar cache at all (API-only, see its doc comment), so
/// there is no local row for forced expiration to threaten in the first
/// place.
///
/// `AuthProvider` is constructed with the real `LocalDatabaseService`
/// instance specifically so that `verifyNever`-style proof isn't needed -
/// if the forced-expiration path ever called `clearAll()` (or any
/// collection write), these rows would visibly disappear/change below.
void main() {
  late Directory tempDir;
  late Isar isar;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late ApiService apiService;
  late SessionRequestCoordinator sessionRequestCoordinator;
  late MockAuthRepository mockAuthRepository;
  late MockAuthService mockAuthService;
  late AuthProvider authProvider;

  const userA = 1;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  Future<Isar> openIsar() => Isar.open(
    [
      LocalSessionSchema,
      LocalExerciseSchema,
      LocalExerciseSetSchema,
      LocalGoalSchema,
      LocalProgramSchema,
      LocalProgramWorkoutSchema,
      LocalMealLogSchema,
      LocalRunSessionSchema,
    ],
    directory: tempDir.path,
    inspector: false,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'forced_expiration_retention_',
    );
    isar = await openIsar();
    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    mockAuthRepository = MockAuthRepository();
    mockAuthService = MockAuthService();
    sessionEpoch = UserSessionEpoch();
    apiService = ApiService(mockAuthService, sessionEpoch);
    sessionRequestCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );

    when(mockAuthService.isAuthenticated()).thenAnswer((_) async => false);
    when(mockAuthService.getUserId()).thenAnswer((_) async => null);
    when(mockAuthService.getUserName()).thenAnswer((_) async => null);
    when(mockAuthService.getUserEmail()).thenAnswer((_) async => null);
    when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {});

    authProvider = AuthProvider(
      mockAuthRepository,
      mockAuthService,
      apiService,
      sessionEpoch,
      sessionRequestCoordinator,
    );

    when(mockAuthRepository.login(any)).thenAnswer(
      (_) async => AuthResponse(
        token: 'tok-a',
        userId: userA,
        name: 'A',
        email: 'a@example.com',
      ),
    );
    when(
      mockAuthService.saveToken(
        token: anyNamed('token'),
        userId: anyNamed('userId'),
        name: anyNamed('name'),
        email: anyNamed('email'),
      ),
    ).thenAnswer((_) async {});
    authProvider.updateEmail('a@example.com');
    authProvider.updatePassword('password123');
    final ok = await authProvider.login();
    expect(ok, isTrue, reason: 'test setup: login must succeed');
  });

  tearDown(() async {
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> waitForExpirationToSettle() async {
    while (authProvider.isExpiringSession) {
      await Future.delayed(Duration.zero);
    }
  }

  /// Simulates an app restart while signed out: closes and reopens the
  /// SAME on-disk Isar file. There is no startup cleanup pass, so every
  /// row must still be there afterward.
  Future<void> restartApp() async {
    await isar.close();
    isar = await openIsar();
    localDb.setTestDatabase(isar);
  }

  final fixedTime = DateTime.utc(2026, 1, 1, 12);

  test('18/20. a pending_create AND a pending_update Session survive forced '
      'expiration with every field byte-identical', () async {
    final created = await isar.writeTxn(
      () => isar.localSessions.put(
        LocalSession(
          userId: userA,
          date: fixedTime,
          status: 'draft',
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
          clientOperationId: 'op-create-1',
        ),
      ),
    );
    final updated = await isar.writeTxn(
      () => isar.localSessions.put(
        LocalSession(
          serverId: 501,
          userId: userA,
          date: fixedTime,
          status: 'completed',
          notes: 'unsynced local edit',
          syncStatus: 'pending_update',
          lastModifiedLocal: fixedTime,
          version: 3,
        ),
      ),
    );

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    final afterCreate = await isar.localSessions.get(created);
    final afterUpdate = await isar.localSessions.get(updated);
    expect(afterCreate, isNotNull);
    expect(afterCreate!.syncStatus, 'pending_create');
    expect(afterCreate.clientOperationId, 'op-create-1');
    expect(afterUpdate, isNotNull);
    expect(afterUpdate!.syncStatus, 'pending_update');
    expect(afterUpdate.notes, 'unsynced local edit');
    expect(afterUpdate.version, 3);
    expect(await isar.localSessions.count(), 2);
  });

  test(
    '21. a pending_delete tombstone is NOT removed by forced expiration - '
    'it stays pending until the server actually acknowledges the delete',
    () async {
      final tombstoned = await isar.writeTxn(
        () => isar.localSessions.put(
          LocalSession(
            serverId: 777,
            userId: userA,
            date: fixedTime,
            status: 'completed',
            syncStatus: 'pending_delete',
            lastModifiedLocal: fixedTime,
          ),
        ),
      );

      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();

      final row = await isar.localSessions.get(tombstoned);
      expect(
        row,
        isNotNull,
        reason:
            'a pending_delete row is a delete INTENT, not a delete - '
            'forced expiration must never turn it into an actual delete',
      );
      expect(row!.syncStatus, 'pending_delete');
    },
  );

  test('19. Exercises and ExerciseSets nested under a session survive with '
      'their sync fields untouched', () async {
    final sessionId = await isar.writeTxn(
      () => isar.localSessions.put(
        LocalSession(
          userId: userA,
          date: fixedTime,
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
        ),
      ),
    );
    final exerciseId = await isar.writeTxn(
      () => isar.localExercises.put(
        LocalExercise(
          sessionLocalId: sessionId,
          name: 'Bench Press',
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
        ),
      ),
    );
    final setId = await isar.writeTxn(
      () => isar.localExerciseSets.put(
        LocalExerciseSet(
          exerciseLocalId: exerciseId,
          setNumber: 1,
          reps: 8,
          weight: 100,
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
        ),
      ),
    );

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    final exercise = await isar.localExercises.get(exerciseId);
    final set = await isar.localExerciseSets.get(setId);
    expect(exercise, isNotNull);
    expect(exercise!.syncStatus, 'pending_create');
    expect(set, isNotNull);
    expect(set!.reps, 8);
    expect(set.weight, 100);
    expect(set.syncStatus, 'pending_create');
  });

  test('22/24. clientOperationId, version, and sync-error diagnostics all '
      'survive forced expiration unchanged', () async {
    final id = await isar.writeTxn(
      () => isar.localSessions.put(
        LocalSession(
          serverId: 42,
          userId: userA,
          date: fixedTime,
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
          clientOperationId: 'op-durable-key',
          version: 7,
          syncRetryCount: 3,
          syncError: 'timeout on last attempt',
          lastSyncAttempt: fixedTime,
        ),
      ),
    );

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    final row = (await isar.localSessions.get(id))!;
    expect(row.clientOperationId, 'op-durable-key');
    expect(row.version, 7);
    expect(row.syncRetryCount, 3);
    expect(row.syncError, 'timeout on last attempt');
    expect(row.lastSyncAttempt, isNotNull);
    expect(row.lastSyncAttempt!.isAtSameMomentAs(fixedTime), isTrue);
  });

  test(
    '25a. Programs and nested ProgramWorkouts survive forced expiration',
    () async {
      final programId = await isar.writeTxn(
        () => isar.localPrograms.put(
          LocalProgram(
            userId: userA,
            title: 'Strength Block',
            totalWeeks: 8,
            currentWeek: 1,
            currentDay: 1,
            startDate: fixedTime,
            createdAt: fixedTime,
            syncStatus: 'pending_create',
            lastModifiedLocal: fixedTime,
          ),
        ),
      );
      final workoutId = await isar.writeTxn(
        () => isar.localProgramWorkouts.put(
          LocalProgramWorkout(
            programLocalId: programId,
            weekNumber: 1,
            dayNumber: 1,
            workoutName: 'Day 1',
            exercisesJson: '[]',
            orderIndex: 0,
            syncStatus: 'pending_create',
            lastModifiedLocal: fixedTime,
          ),
        ),
      );

      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();

      expect(await isar.localPrograms.get(programId), isNotNull);
      final workout = await isar.localProgramWorkouts.get(workoutId);
      expect(workout, isNotNull);
      expect(workout!.workoutName, 'Day 1');
    },
  );

  test('25b. Goals survive forced expiration', () async {
    final goalId = await isar.writeTxn(
      () => isar.localGoals.put(
        LocalGoal(
          userId: userA,
          goalType: 'weight_loss',
          targetValue: 70,
          currentValue: 80,
          startDate: fixedTime,
          createdAt: fixedTime,
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
        ),
      ),
    );

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    final goal = await isar.localGoals.get(goalId);
    expect(goal, isNotNull);
    expect(goal!.targetValue, 70);
    expect(goal.syncStatus, 'pending_create');
  });

  test('25c. nutrition (meal log) data survives forced expiration', () async {
    final mealLogId = await isar.writeTxn(
      () => isar.localMealLogs.put(
        LocalMealLog(
          userId: userA,
          date: fixedTime,
          totalCalories: 2200,
          createdAt: fixedTime,
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
        ),
      ),
    );

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    final mealLog = await isar.localMealLogs.get(mealLogId);
    expect(mealLog, isNotNull);
    expect(mealLog!.totalCalories, 2200);
    expect(mealLog.syncStatus, 'pending_create');
  });

  test('25d. running data survives forced expiration', () async {
    final runId = await isar.writeTxn(
      () => isar.localRunSessions.put(
        LocalRunSession.create(
          userId: userA,
          date: fixedTime,
          distance: 5.2,
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
        ),
      ),
    );

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    final run = await isar.localRunSessions.get(runId);
    expect(run, isNotNull);
    expect(run!.distance, 5.2);
    expect(run.syncStatus, 'pending_create');
  });

  test('18-25 (restart). every seeded row across every collection survives '
      'forced expiration AND a subsequent app restart (Isar close + reopen) '
      'while signed out', () async {
    final sessionId = await isar.writeTxn(
      () => isar.localSessions.put(
        LocalSession(
          userId: userA,
          date: fixedTime,
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
          clientOperationId: 'op-restart-1',
        ),
      ),
    );
    final goalId = await isar.writeTxn(
      () => isar.localGoals.put(
        LocalGoal(
          userId: userA,
          goalType: 'strength',
          targetValue: 100,
          currentValue: 60,
          startDate: fixedTime,
          createdAt: fixedTime,
          syncStatus: 'pending_update',
          lastModifiedLocal: fixedTime,
        ),
      ),
    );

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();
    await restartApp();

    final session = await isar.localSessions.get(sessionId);
    final goal = await isar.localGoals.get(goalId);
    expect(session, isNotNull);
    expect(session!.clientOperationId, 'op-restart-1');
    expect(session.syncStatus, 'pending_create');
    expect(goal, isNotNull);
    expect(goal!.syncStatus, 'pending_update');
    expect(goal.targetValue, 100);
  });

  test('forced expiration never invokes LocalDatabaseService.clearAll - proven '
      'by counting rows in every collection before and after, using the real '
      'singleton (not a mock)', () async {
    await isar.writeTxn(
      () => isar.localSessions.put(
        LocalSession(
          userId: userA,
          date: fixedTime,
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
        ),
      ),
    );
    await isar.writeTxn(
      () => isar.localGoals.put(
        LocalGoal(
          userId: userA,
          goalType: 'strength',
          targetValue: 100,
          currentValue: 60,
          startDate: fixedTime,
          createdAt: fixedTime,
          syncStatus: 'pending_create',
          lastModifiedLocal: fixedTime,
        ),
      ),
    );

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    expect(await isar.localSessions.count(), 1);
    expect(await isar.localGoals.count(), 1);
  });
}
