import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_chat_conversation.dart';
import 'package:go_hard_app/data/local/models/local_chat_message.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_food_item.dart';
import 'package:go_hard_app/data/local/models/local_food_template.dart';
import 'package:go_hard_app/data/local/models/local_goal.dart';
import 'package:go_hard_app/data/local/models/local_meal_entry.dart';
import 'package:go_hard_app/data/local/models/local_meal_log.dart';
import 'package:go_hard_app/data/local/models/local_nutrition_goal.dart';
import 'package:go_hard_app/data/local/models/local_program.dart';
import 'package:go_hard_app/data/local/models/local_program_workout.dart';
import 'package:go_hard_app/data/local/models/local_run_session.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/models/achievement.dart';
import 'package:go_hard_app/data/models/shared_workout.dart';
import 'package:go_hard_app/data/models/workout_template.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/auth_response.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/providers/auth_provider.dart';

// Reuses the Mockito mocks generated for auth_provider_test.dart
// (AuthRepository/AuthService/ApiService/LocalDatabaseService/
// SessionRequestCoordinator - the same GenerateMocks list SyncService and
// SessionRepository need too, since they share the AuthService/ApiService
// interfaces) - no new build_runner output.
import 'auth_provider_test.mocks.dart';

/// Proves the NON-DESTRUCTIVE explicit logout contract end to end, with a
/// REAL on-disk Isar database (never a mock of the database itself):
/// explicit `logout()` clears authentication and in-memory state, but every
/// durable, user-owned record - across every offline-mutation shape
/// (pending_create/update/delete, a conflict snapshot), every feature area,
/// and a real Isar close+reopen - survives untouched. Signing back in as
/// the SAME account restores full access and lets a retained pending
/// operation synchronize normally; signing in as a DIFFERENT account never
/// sees, syncs, or disturbs the retained data, even under colliding
/// server/local IDs.
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

  final fixedTime = DateTime.utc(2026, 1, 1, 12);

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  // The FULL schema list from LocalDatabaseService.initialize() - matching
  // it exactly avoids a "Missing TypeSchema" error from SyncService.sync()
  // (item C/D), which enumerates every collection, not just the ones this
  // file happens to seed.
  Future<Isar> openIsar() => Isar.open(
    [
      LocalSessionSchema,
      LocalExerciseSchema,
      LocalExerciseSetSchema,
      LocalExerciseTemplateSchema,
      LocalChatConversationSchema,
      LocalChatMessageSchema,
      LocalRunSessionSchema,
      LocalProgramSchema,
      LocalGoalSchema,
      LocalProgramWorkoutSchema,
      SharedWorkoutSchema,
      WorkoutTemplateSchema,
      AchievementSchema,
      LocalMealLogSchema,
      LocalMealEntrySchema,
      LocalFoodItemSchema,
      LocalNutritionGoalSchema,
      LocalFoodTemplateSchema,
    ],
    directory: tempDir.path,
    inspector: false,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('non_destructive_logout_');
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
    // Default for any unbound/session-bound request path that reads the
    // live token (e.g. SessionRequestCoordinator.captureContext()) -
    // individual tests override this when they need a specific value.
    when(mockAuthService.getToken()).thenAnswer((_) async => 'default-token');

    authProvider = AuthProvider(
      mockAuthRepository,
      mockAuthService,
      apiService,
      sessionEpoch,
      sessionRequestCoordinator,
    );
  });

  tearDown(() async {
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<bool> loginAs({
    required int userId,
    required String email,
    required String token,
  }) async {
    when(mockAuthRepository.login(any)).thenAnswer(
      (_) async => AuthResponse(
        token: token,
        userId: userId,
        name: 'U$userId',
        email: email,
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
    authProvider.updateEmail(email);
    authProvider.updatePassword('password123');
    final ok = await authProvider.login();
    return ok;
  }

  Future<void> waitForSettle() async {
    while (authProvider.isTerminating) {
      await Future.delayed(Duration.zero);
    }
  }

  // ---- Group A fixtures: every offline-mutation shape for Sessions -------

  Future<LocalSession> insertPendingCreateSession(int userId) async {
    final session = LocalSession(
      userId: userId,
      date: fixedTime,
      status: 'draft',
      syncStatus: 'pending_create',
      lastModifiedLocal: fixedTime,
      clientOperationId: 'op-create-${userId}_1',
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<LocalSession> insertPendingUpdateSession(int userId) async {
    final session = LocalSession(
      serverId: 501,
      userId: userId,
      date: fixedTime,
      status: 'completed',
      notes: 'unsynced local edit',
      syncStatus: 'pending_update',
      lastModifiedLocal: fixedTime,
      version: 3,
      syncRetryCount: 2,
      syncError: 'timeout on last attempt',
      lastSyncAttempt: fixedTime,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<LocalSession> insertPendingDeleteSession(int userId) async {
    final session = LocalSession(
      serverId: 777,
      userId: userId,
      date: fixedTime,
      status: 'completed',
      syncStatus: 'pending_delete',
      lastModifiedLocal: fixedTime,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<LocalSession> insertConflictSession(int userId) async {
    final session = LocalSession(
      serverId: 888,
      userId: userId,
      date: fixedTime,
      status: 'completed',
      notes: 'my local version',
      syncStatus: 'synced',
      lastModifiedLocal: fixedTime,
      version: 5,
      conflictServerSnapshotJson: '{"notes":"server version"}',
      conflictServerVersion: 6,
      conflictDetectedAt: fixedTime,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<(int exerciseId, int setId)> insertChildExerciseAndSet(
    int sessionLocalId,
  ) async {
    final exerciseId = await isar.writeTxn(
      () => isar.localExercises.put(
        LocalExercise(
          sessionLocalId: sessionLocalId,
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
    return (exerciseId, setId);
  }

  group('A. explicit logout preserves every Session mutation shape', () {
    test('pending_create, pending_update, pending_delete, and conflict '
        'Sessions - plus a child Exercise/Set - all survive byte-identical, '
        'with operation keys, server IDs, versions, timestamps, and '
        'diagnostics intact', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 't'),
        isTrue,
      );

      final created = await insertPendingCreateSession(1);
      final updated = await insertPendingUpdateSession(1);
      final tombstoned = await insertPendingDeleteSession(1);
      final conflicted = await insertConflictSession(1);
      final (exerciseId, setId) = await insertChildExerciseAndSet(
        created.localId,
      );

      await authProvider.logout();

      final afterCreate = (await isar.localSessions.get(created.localId))!;
      expect(afterCreate.syncStatus, 'pending_create');
      expect(afterCreate.clientOperationId, 'op-create-1_1');
      expect(afterCreate.userId, 1);

      final afterUpdate = (await isar.localSessions.get(updated.localId))!;
      expect(afterUpdate.syncStatus, 'pending_update');
      expect(afterUpdate.serverId, 501);
      expect(afterUpdate.version, 3);
      expect(afterUpdate.notes, 'unsynced local edit');
      expect(afterUpdate.syncRetryCount, 2);
      expect(afterUpdate.syncError, 'timeout on last attempt');
      expect(afterUpdate.lastSyncAttempt!.isAtSameMomentAs(fixedTime), isTrue);

      final afterDelete = (await isar.localSessions.get(tombstoned.localId))!;
      expect(
        afterDelete.syncStatus,
        'pending_delete',
        reason:
            'a pending_delete row is a delete INTENT, not a delete - '
            'logout must never turn it into an actual delete',
      );
      expect(afterDelete.serverId, 777);

      final afterConflict = (await isar.localSessions.get(conflicted.localId))!;
      expect(
        afterConflict.conflictServerSnapshotJson,
        '{"notes":"server version"}',
      );
      expect(afterConflict.conflictServerVersion, 6);
      expect(
        afterConflict.conflictDetectedAt!.isAtSameMomentAs(fixedTime),
        isTrue,
      );
      expect(afterConflict.version, 5);

      final afterExercise = (await isar.localExercises.get(exerciseId))!;
      expect(afterExercise.syncStatus, 'pending_create');
      expect(afterExercise.name, 'Bench Press');

      final afterSet = (await isar.localExerciseSets.get(setId))!;
      expect(afterSet.reps, 8);
      expect(afterSet.weight, 100);
      expect(afterSet.syncStatus, 'pending_create');

      expect(await isar.localSessions.count(), 4);
      expect(await isar.localExercises.count(), 1);
      expect(await isar.localExerciseSets.count(), 1);
    });
  });

  group('B. retained records survive a real Isar close/reopen', () {
    test('every seeded row is still present, with the same field values, '
        'after logout AND a subsequent app restart (Isar close + reopen) '
        'while signed out', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 't'),
        isTrue,
      );
      final created = await insertPendingCreateSession(1);
      final updated = await insertPendingUpdateSession(1);

      await authProvider.logout();

      await isar.close();
      isar = await openIsar();
      localDb.setTestDatabase(isar);

      final afterRestartCreate = await isar.localSessions.get(created.localId);
      final afterRestartUpdate = await isar.localSessions.get(updated.localId);
      expect(afterRestartCreate, isNotNull);
      expect(afterRestartCreate!.clientOperationId, 'op-create-1_1');
      expect(afterRestartUpdate, isNotNull);
      expect(afterRestartUpdate!.version, 3);
      expect(afterRestartUpdate.notes, 'unsynced local edit');
    });
  });

  group(
    'C. same-user login restores access and lets a retained operation sync',
    () {
      test(
        'A logs back in as the SAME account; a retained pending_create '
        'Session, seeded with an existing clientOperationId, synchronizes '
        'via SyncService using that EXACT key and A\'s new session context',
        () async {
          expect(
            await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a'),
            isTrue,
          );
          final created = await insertPendingCreateSession(1);
          final knownKey = created.clientOperationId!;

          await authProvider.logout();
          expect(authProvider.isAuthenticated, isFalse);

          // Same account, fresh session.
          expect(
            await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a-2'),
            isTrue,
          );
          expect(authProvider.currentUserId, 1);

          SyncService.reset();
          final mockApiService = MockApiService();
          when(
            mockApiService.post<Map<String, dynamic>>(
              any,
              data: anyNamed('data'),
              sessionContext: anyNamed('sessionContext'),
            ),
          ).thenAnswer(
            (_) async => {
              'id': 900,
              'userId': 1,
              'date': '2026-01-01',
              'duration': null,
              'notes': null,
              'type': null,
              'name': null,
              'status': 'draft',
              'startedAt': null,
              'completedAt': null,
              'pausedAt': null,
              'exercises': <dynamic>[],
              'programId': null,
              'programWorkoutId': null,
              'version': 1,
            },
          );
          when(mockAuthService.getToken()).thenAnswer((_) async => 'tok-a-2');
          final syncService = SyncService(
            apiService: mockApiService,
            authService: mockAuthService,
            localDb: localDb,
            connectivity: ConnectivityService.instance,
            sessionEpoch: sessionEpoch,
            sessionCoordinator: sessionRequestCoordinator,
          );

          await syncService.sync();

          final captured =
              verify(
                mockApiService.post<Map<String, dynamic>>(
                  any,
                  data: captureAnyNamed('data'),
                  sessionContext: anyNamed('sessionContext'),
                ),
              ).captured;
          final body = captured.last as Map<String, dynamic>;
          expect(
            body['clientOperationId'],
            knownKey,
            reason:
                'the retry must reuse the EXACT key persisted before '
                'logout, never mint a new one - this is what makes it safe '
                'against duplicate server-side creation',
          );

          final afterSync = (await isar.localSessions.get(created.localId))!;
          expect(afterSync.syncStatus, 'synced');
          expect(afterSync.serverId, 900);
          expect(afterSync.clientOperationId, knownKey);

          SyncService.reset();
        },
      );
    },
  );

  group('D. different-user login never sees or syncs A\'s retained data', () {
    test('A logs out; B logs in with a COLLIDING server ID on B\'s own '
        'session; SessionRepository.getSessions() (B\'s context) returns '
        'ONLY B\'s row - A\'s row (same numeric serverId, different owner) '
        'is never exposed, and remains completely unchanged in Isar', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a'),
        isTrue,
      );
      final aSession = LocalSession(
        serverId: 700,
        userId: 1,
        date: fixedTime,
        name: 'A\'s private session',
        status: 'completed',
        syncStatus: 'synced',
        lastModifiedLocal: fixedTime,
      );
      final aLocalId = await isar.writeTxn(
        () => isar.localSessions.put(aSession),
      );

      await authProvider.logout();

      expect(
        await loginAs(userId: 2, email: 'b@example.com', token: 'tok-b'),
        isTrue,
      );
      final bSession = LocalSession(
        serverId: 700, // Deliberately colliding with A's serverId.
        userId: 2,
        date: fixedTime,
        name: 'B\'s own session',
        status: 'draft',
        syncStatus: 'synced',
        lastModifiedLocal: fixedTime,
      );
      final bLocalId = await isar.writeTxn(
        () => isar.localSessions.put(bSession),
      );

      final sessionRepository = SessionRepository(
        apiService,
        localDb,
        ConnectivityService.instance,
        mockAuthService,
        sessionEpoch,
        sessionRequestCoordinator,
      );

      final visibleToB = await sessionRepository.getSessions();

      expect(
        visibleToB.any((s) => s.name == 'A\'s private session'),
        isFalse,
        reason: 'A\'s row must never be exposed through B\'s read path',
      );
      expect(visibleToB.any((s) => s.name == 'B\'s own session'), isTrue);

      // A's row is completely untouched, still present, still owned by A.
      final aRowAfter = (await isar.localSessions.get(aLocalId))!;
      expect(aRowAfter.userId, 1);
      expect(aRowAfter.name, 'A\'s private session');
      expect(aRowAfter.serverId, 700);

      final bRowAfter = (await isar.localSessions.get(bLocalId))!;
      expect(bRowAfter.userId, 2);
      expect(bRowAfter.name, 'B\'s own session');

      expect(
        await isar.localSessions.count(),
        2,
        reason: 'both rows retained, distinctly owned',
      );
    });

    test('B never triggers a sync request for A\'s retained pending work - '
        'SyncService.sync() under B\'s context only ever dispatches for '
        'rows B owns', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a'),
        isTrue,
      );
      await insertPendingCreateSession(1);
      await authProvider.logout();

      expect(
        await loginAs(userId: 2, email: 'b@example.com', token: 'tok-b'),
        isTrue,
      );

      SyncService.reset();
      final mockApiService = MockApiService();
      // No stub configured for post() - MockApiService throws on any
      // missing stub (throwOnMissingStub), so if SyncService ever tried
      // to sync A's row under B's context, this test would fail loudly
      // via an unstubbed-call exception rather than silently passing.
      when(mockAuthService.getToken()).thenAnswer((_) async => 'tok-b');
      final syncService = SyncService(
        apiService: mockApiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: ConnectivityService.instance,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionRequestCoordinator,
      );

      await syncService.sync();

      verifyNever(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );

      SyncService.reset();
    });

    test('B never triggers a server DELETE for A\'s retained pending_delete '
        'tombstone - _syncDeleteSession dispatches straight from the '
        'enumeration query with no further per-row ownership re-check, so '
        'this is the one Session sync path where that query is the ONLY '
        'protection against cross-user enumeration', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a'),
        isTrue,
      );
      await insertPendingDeleteSession(1);
      await authProvider.logout();

      expect(
        await loginAs(userId: 2, email: 'b@example.com', token: 'tok-b'),
        isTrue,
      );

      SyncService.reset();
      final mockApiService = MockApiService();
      when(mockAuthService.getToken()).thenAnswer((_) async => 'tok-b');
      final syncService = SyncService(
        apiService: mockApiService,
        authService: mockAuthService,
        localDb: localDb,
        connectivity: ConnectivityService.instance,
        sessionEpoch: sessionEpoch,
        sessionCoordinator: sessionRequestCoordinator,
      );

      await syncService.sync();

      verifyNever(
        mockApiService.delete(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );

      SyncService.reset();
    });
  });

  group('E. other retained user-owned collections', () {
    test('Programs and nested ProgramWorkouts survive logout', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 't'),
        isTrue,
      );
      final programId = await isar.writeTxn(
        () => isar.localPrograms.put(
          LocalProgram(
            userId: 1,
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

      await authProvider.logout();

      expect(await isar.localPrograms.get(programId), isNotNull);
      final workout = await isar.localProgramWorkouts.get(workoutId);
      expect(workout, isNotNull);
      expect(workout!.workoutName, 'Day 1');
    });

    test('Goals survive logout', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 't'),
        isTrue,
      );
      final goalId = await isar.writeTxn(
        () => isar.localGoals.put(
          LocalGoal(
            userId: 1,
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

      await authProvider.logout();

      final goal = await isar.localGoals.get(goalId);
      expect(goal, isNotNull);
      expect(goal!.targetValue, 70);
    });

    test('nutrition (meal log) data survives logout', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 't'),
        isTrue,
      );
      final mealLogId = await isar.writeTxn(
        () => isar.localMealLogs.put(
          LocalMealLog(
            userId: 1,
            date: fixedTime,
            totalCalories: 2200,
            createdAt: fixedTime,
            syncStatus: 'pending_create',
            lastModifiedLocal: fixedTime,
          ),
        ),
      );

      await authProvider.logout();

      final mealLog = await isar.localMealLogs.get(mealLogId);
      expect(mealLog, isNotNull);
      expect(mealLog!.totalCalories, 2200);
    });

    test('running data survives logout', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 't'),
        isTrue,
      );
      final runId = await isar.writeTxn(
        () => isar.localRunSessions.put(
          LocalRunSession.create(
            userId: 1,
            date: fixedTime,
            distance: 5.2,
            syncStatus: 'pending_create',
            lastModifiedLocal: fixedTime,
          ),
        ),
      );

      await authProvider.logout();

      final run = await isar.localRunSessions.get(runId);
      expect(run, isNotNull);
      expect(run!.distance, 5.2);
    });

    test('coverage boundary: body metrics and Friends have no local Isar '
        'cache at all, so retention is not applicable to them - this is a '
        'documented boundary, not a skipped/deferred gap. Proven by reading '
        'the REAL production source of both repositories (never a "trust '
        'me" comment): neither file imports package:isar, holds a '
        'LocalDatabaseService, or references any Isar collection anywhere - '
        'there is no local row either repository could ever retain across '
        'a logout for this suite to seed or observe in the first place.', () {
      for (final relativePath in [
        'data/repositories/body_metrics_repository.dart',
        'data/repositories/friends_repository.dart',
      ]) {
        // Code only - both files' doc comments legitimately DISCUSS the
        // word "Isar" while asserting its absence, so a raw substring
        // search would false-positive on the very sentences proving the
        // boundary. Mirrors `auth_provider_composition_proof_test.dart`'s
        // identical comment-stripping approach.
        final codeOnly = _stripCommentsForBoundaryCheck(
          _readLibSource(relativePath),
        );
        for (final forbidden in [
          "import 'package:isar",
          'LocalDatabaseService',
          'Isar(',
          'Isar.',
          '.writeTxn',
        ]) {
          expect(
            codeOnly.contains(forbidden),
            isFalse,
            reason:
                '$relativePath must never reference "$forbidden" in '
                'actual code - if it ever gained a local Isar cache, '
                "this suite's retention coverage would need a REAL "
                'test seeding and observing that cache across logout, '
                'not this boundary note',
          );
        }
      }
    });
  });

  group('F. race orderings preserve data and navigate exactly once', () {
    test(
      'manual logout racing a forced 401 still preserves durable data and '
      'produces exactly one terminal notification/navigation - see '
      'auth_provider_termination_race_test.dart for the full concurrency '
      'matrix; this test ties that guarantee to REAL Isar retention',
      () async {
        expect(
          await loginAs(userId: 1, email: 'a@example.com', token: 't'),
          isTrue,
        );
        final created = await insertPendingCreateSession(1);

        var notifyCount = 0;
        authProvider.addListener(() => notifyCount++);
        var loggedOutCalls = 0;
        authProvider.onLoggedOut = () => loggedOutCalls++;

        final manualLogout = authProvider.logout();
        apiService.onUnauthorized?.call();
        await manualLogout;
        await waitForSettle();

        expect(loggedOutCalls, 1);
        expect(notifyCount, 1);
        final after = await isar.localSessions.get(created.localId);
        expect(after, isNotNull);
        expect(after!.syncStatus, 'pending_create');
      },
    );

    test('the REVERSE ordering - forced 401 starts first, then explicit '
        'logout JOINS and upgrades the pass - also preserves durable data '
        'and navigates exactly once. This is the specific ordering under '
        'which a mutation that gates destructive cleanup on "was this pass '
        'upgraded from forced expiration" would only show up - a mutation '
        'not caught by the "logout starts first" test above', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 't'),
        isTrue,
      );
      final created = await insertPendingCreateSession(1);

      final gate = Completer<void>();
      authProvider.onSessionEnding = () async {
        await gate.future;
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      apiService.onUnauthorized?.call();
      await pumpEventQueue();
      expect(authProvider.isExpiringSession, isTrue);

      final manualLogout = authProvider.logout();
      await pumpEventQueue();
      expect(authProvider.isLoggingOut, isTrue);

      gate.complete();
      await manualLogout;
      await waitForSettle();

      expect(loggedOutCalls, 1);
      expect(authProvider.errorMessage, '');
      final after = await isar.localSessions.get(created.localId);
      expect(after, isNotNull);
      expect(after!.syncStatus, 'pending_create');
      expect(await isar.localSessions.count(), 1);
    });
  });

  group(
    'G. a delayed old termination pass cannot clear newer credentials/state',
    () {
      test('A\'s forced-expiration pass, suspended in onSessionEnding, does '
          'not clear B\'s credentials once B has logged in - and A\'s '
          'retained data remains intact throughout', () async {
        expect(
          await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a'),
          isTrue,
        );
        final created = await insertPendingCreateSession(1);

        final gate = Completer<void>();
        authProvider.onSessionEnding = () async {
          await gate.future;
        };

        apiService.onUnauthorized?.call();
        await pumpEventQueue();
        expect(authProvider.isExpiringSession, isTrue);

        expect(
          await loginAs(userId: 2, email: 'b@example.com', token: 'tok-b'),
          isTrue,
        );

        gate.complete();
        await waitForSettle();

        verifyNever(mockAuthService.clearSessionCredentials());
        expect(authProvider.isAuthenticated, isTrue);
        expect(authProvider.currentUserId, 2);

        final aRow = await isar.localSessions.get(created.localId);
        expect(aRow, isNotNull);
        expect(aRow!.syncStatus, 'pending_create');
      });

      test(
        'same-user re-login during an old, still-finishing pass remains '
        'intact - a fresh generation, not disturbed by the stale pass',
        () async {
          expect(
            await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a'),
            isTrue,
          );
          final gate = Completer<void>();
          authProvider.onSessionEnding = () async {
            await gate.future;
          };

          apiService.onUnauthorized?.call();
          await pumpEventQueue();
          expect(authProvider.isExpiringSession, isTrue);

          expect(
            await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a-2'),
            isTrue,
          );

          gate.complete();
          await waitForSettle();

          verifyNever(mockAuthService.clearSessionCredentials());
          expect(authProvider.isAuthenticated, isTrue);
          expect(authProvider.currentUserId, 1);
        },
      );

      test('B\'s OWN logout() call, made while A\'s stale pass is still '
          'suspended in onSessionEnding, must start its OWN fresh pass - '
          'never join A\'s already-doomed one (a pass for a superseded '
          'generation that will abort via stillOwnsThisGeneration before '
          'ever reaching the terminal step) - or B\'s logout would silently '
          'never actually complete B\'s termination', () async {
        expect(
          await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a'),
          isTrue,
        );
        final gate = Completer<void>();
        authProvider.onSessionEnding = () async {
          await gate.future;
        };

        apiService.onUnauthorized?.call();
        await pumpEventQueue();
        expect(authProvider.isExpiringSession, isTrue);

        expect(
          await loginAs(userId: 2, email: 'b@example.com', token: 'tok-b'),
          isTrue,
        );

        // B calls logout() WHILE A's stale pass is still suspended on
        // the gate - this must start B's own independent pass, not join
        // A's.
        final bLogout = authProvider.logout();

        gate.complete();
        await bLogout;
        await waitForSettle();

        expect(
          authProvider.isAuthenticated,
          isFalse,
          reason:
              'B\'s own logout() must actually complete B\'s '
              'termination - if it had incorrectly joined A\'s stale '
              'pass, that pass would abort via stillOwnsThisGeneration '
              '(A\'s generation was superseded by B\'s login) before '
              'ever resetting B\'s identity fields, silently leaving B '
              'stuck authenticated',
        );
      });

      test('A\'s eventual stale-pass completion - after B has logged '
          'BACK out via a THIRD call that correctly joined B\'s own '
          'still-in-flight pass instead of duplicating it - can neither '
          'clear the reference to B\'s pass, cause a duplicate '
          'credential-clear/navigation, nor disturb B\'s already-settled '
          'terminal state. Exact call counts throughout, via held '
          'Completers - no wall-clock timing.', () async {
        expect(
          await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a'),
          isTrue,
        );

        final aGate = Completer<void>();
        final bGate = Completer<void>();
        var onSessionEndingCalls = 0;
        authProvider.onSessionEnding = () async {
          onSessionEndingCalls++;
          if (onSessionEndingCalls == 1) {
            await aGate.future;
          } else if (onSessionEndingCalls == 2) {
            await bGate.future;
          }
        };
        var navigateCalls = 0;
        authProvider.onLoggedOut = () {
          navigateCalls++;
        };
        var notifyCalls = 0;
        authProvider.addListener(() => notifyCalls++);

        // A's forced-expiration pass starts and suspends on its OWN
        // (first) onSessionEnding call.
        apiService.onUnauthorized?.call();
        await pumpEventQueue();
        expect(authProvider.isExpiringSession, isTrue);
        expect(onSessionEndingCalls, 1);

        expect(
          await loginAs(userId: 2, email: 'b@example.com', token: 'tok-b'),
          isTrue,
        );

        // B's own logout() call: A's endedGeneration no longer matches
        // the current generation (B's login bumped it), so this
        // correctly starts B's OWN fresh pass rather than joining A's -
        // which immediately suspends on its OWN (second) onSessionEnding
        // call.
        final bLogout1 = authProvider.logout();
        await pumpEventQueue();
        expect(
          onSessionEndingCalls,
          2,
          reason:
              "both A's stale pass and B's fresh pass reached "
              'onSessionEnding',
        );
        expect(authProvider.isTerminating, isTrue);

        // A THIRD logout() call, made while B's OWN pass is STILL
        // suspended on bGate, must JOIN B's in-flight pass - proven by
        // returning the literal SAME Future, not merely an
        // equal-looking one - rather than starting a duplicate pass for
        // B.
        final bLogout2 = authProvider.logout();
        expect(
          identical(bLogout1, bLogout2),
          isTrue,
          reason:
              'a logout() call arriving while B\'s own pass is still '
              'in flight must join that exact pass (returning its '
              'existing Future) - never start a second, duplicate '
              'pass for the same (B\'s) generation',
        );
        expect(
          onSessionEndingCalls,
          2,
          reason:
              'joining must never re-invoke onSessionEnding a '
              'third time',
        );

        bGate.complete();
        await bLogout1;
        await bLogout2;

        verify(mockAuthService.clearSessionCredentials()).called(1);
        expect(navigateCalls, 1);
        expect(authProvider.isAuthenticated, isFalse);
        expect(authProvider.isTerminating, isFalse);
        final notifyCallsAfterB = notifyCalls;

        // NOW release A's long-stale pass. Its generation snapshot was
        // superseded first by B's login, then again by B's own logout
        // pass - stillOwnsThisGeneration() must make its resumption a
        // total no-op: no additional credential clear, no additional
        // navigation, no change to the already-settled logged-out
        // state, and it must not disturb the (already-null)
        // _activeTermination reference B's own pass already cleared.
        aGate.complete();
        await waitForSettle();

        // mockito's verify().called(n) only counts invocations since the
        // PREVIOUS verify call, not a cumulative total - so "no NEW call"
        // here is the correct way to prove the credential clear above
        // stays the only one that ever happened.
        verifyNever(mockAuthService.clearSessionCredentials());
        expect(
          navigateCalls,
          1,
          reason: "A's stale-pass completion must never navigate again",
        );
        expect(authProvider.isAuthenticated, isFalse);
        expect(authProvider.isTerminating, isFalse);
        expect(
          notifyCalls,
          notifyCallsAfterB,
          reason:
              "A's stale-pass completion must fire no further "
              'notifyListeners() call once B\'s own pass has already '
              'settled',
        );
      });
    },
  );

  group('H. logout succeeds when push unregister/Firebase is unavailable', () {
    test('logout() completes and reaches the unauthenticated state even '
        'though PushNotificationService was never initialized in this test '
        'environment (its internal ApiService reference is null, exactly '
        'simulating Firebase/FCM being unavailable) - the best-effort '
        'unregister attempt never blocks or fails local logout', () async {
      expect(
        await loginAs(userId: 1, email: 'a@example.com', token: 't'),
        isTrue,
      );

      await expectLater(authProvider.logout(), completes);

      expect(authProvider.isAuthenticated, isFalse);
    });
  });

  group(
    'I. in-memory feature state is cleared despite durable data retention',
    () {
      test(
        'onSessionEnding (the seam SessionCleanupCoordinator is wired '
        'through in production) still runs exactly once on logout, even '
        'though the durable data it does NOT touch survives untouched',
        () async {
          expect(
            await loginAs(userId: 1, email: 'a@example.com', token: 't'),
            isTrue,
          );
          final created = await insertPendingCreateSession(1);

          var sessionEndingCalls = 0;
          authProvider.onSessionEnding = () async {
            sessionEndingCalls++;
          };

          await authProvider.logout();

          expect(
            sessionEndingCalls,
            1,
            reason:
                'in-memory feature-provider cleanup (GPS/timers/polling/'
                'Isar watcher cancellation/settled-state reset) must still '
                'run exactly once - only durable data is exempt',
          );
          final after = await isar.localSessions.get(created.localId);
          expect(after, isNotNull, reason: 'durable data is unaffected by it');
        },
      );
    },
  );
}

/// Locates the repository root by walking up from the current working
/// directory until a `pubspec.yaml` is found - works regardless of exactly
/// where `flutter test` happens to be invoked from. Mirrors
/// `auth_provider_composition_proof_test.dart`'s identical helper.
Directory _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('Could not locate repository root (no pubspec.yaml found).');
    }
    dir = parent;
  }
  return dir;
}

String _readLibSource(String relativePath) {
  final file = File('${_repoRoot().path}/lib/$relativePath');
  expect(file.existsSync(), isTrue, reason: '${file.path} must exist');
  return file.readAsStringSync();
}

/// Strips `//` line comments and `/* */` block comments so a plain
/// substring search doesn't false-positive on prose that legitimately
/// DISCUSSES a forbidden word while asserting its absence (e.g. a doc
/// comment saying "no local Isar cache"). Mirrors
/// `auth_provider_composition_proof_test.dart`'s identical helper.
String _stripCommentsForBoundaryCheck(String source) {
  final noBlockComments = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final lines = noBlockComments.split('\n');
  final buffer = StringBuffer();
  for (final line in lines) {
    final commentIndex = line.indexOf('//');
    buffer.writeln(commentIndex == -1 ? line : line.substring(0, commentIndex));
  }
  return buffer.toString();
}
