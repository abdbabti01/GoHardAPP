import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
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
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/achievement.dart';
import 'package:go_hard_app/data/models/shared_workout.dart';
import 'package:go_hard_app/data/models/workout_template.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'sync_service_child_ownership_test.mocks.dart';

@GenerateMocks([ApiService, AuthService])
/// Proves the five previously-unfiltered child-entity sync phases
/// (Exercise, ExerciseSet, ProgramWorkout, MealEntry, FoodItem) now filter
/// by parent-chain ownership, and that directly-owned entities remain
/// correctly scoped by user ID - see the "Child-entity ownership
/// filtering" section of `SyncService`'s class doc comment.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late SyncService syncService;

  const userA = 1;
  const userB = 2;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sync_service_child_ownership_',
    );
    isar = await Isar.open(
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

    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userA);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$userA');

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch()..activate(userA);
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );

    SyncService.reset();
    syncService = SyncService(
      apiService: mockApiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: ConnectivityService.instance,
      sessionEpoch: sessionEpoch,
      sessionCoordinator: sessionCoordinator,
    );
  });

  tearDown(() async {
    SyncService.reset();
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LocalSession> insertSession({
    required int uid,
    int? serverId,
    String syncStatus = 'synced',
  }) async {
    final now = DateTime.now();
    final session = LocalSession(
      serverId: serverId,
      userId: uid,
      date: DateTime(2026, 1, 1),
      status: 'in_progress',
      isSynced: serverId != null,
      syncStatus: syncStatus,
      lastModifiedLocal: now,
      // A non-null version keeps a 'synced' row with a serverId out of
      // `_reconcileUpgradedSessionVersions`'s "clean unversioned" sweep -
      // this file's sessions exist only to parent exercises/sets, not to
      // exercise the reconciliation path.
      version: serverId != null ? 1 : null,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<LocalProgram> insertProgram({
    required int uid,
    int? serverId,
    String syncStatus = 'synced',
  }) async {
    final now = DateTime.now();
    final program = LocalProgram(
      serverId: serverId,
      userId: uid,
      title: 'Program',
      totalWeeks: 4,
      currentWeek: 1,
      currentDay: 1,
      startDate: DateTime(2026, 1, 1),
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: syncStatus,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localPrograms.put(program));
    return program;
  }

  Future<LocalMealLog> insertMealLog({
    required int uid,
    int? serverId,
    String syncStatus = 'synced',
  }) async {
    final now = DateTime.now();
    final log = LocalMealLog(
      serverId: serverId,
      userId: uid,
      date: DateTime(2026, 1, 1),
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: syncStatus,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localMealLogs.put(log));
    return log;
  }

  Future<LocalMealEntry> insertMealEntry({
    required int mealLogLocalId,
    int? serverId,
    String syncStatus = 'synced',
  }) async {
    final now = DateTime.now();
    final entry = LocalMealEntry(
      serverId: serverId,
      mealLogLocalId: mealLogLocalId,
      mealType: 'Breakfast',
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: syncStatus,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localMealEntrys.put(entry));
    return entry;
  }

  // ============ Directly-owned entities (tests 16, 17) ============

  group('directly-owned entities', () {
    test('A\'s pending program syncs normally; B\'s is excluded from A\'s pass '
        '(tests 16, 17)', () async {
      final programA = await insertProgram(
        uid: userA,
        syncStatus: 'pending_create',
      );
      final programB = await insertProgram(
        uid: userB,
        syncStatus: 'pending_create',
      );

      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async => {'id': 4242});

      await syncService.sync();

      final storedA = await isar.localPrograms.get(programA.localId);
      expect(storedA!.isSynced, isTrue);
      expect(storedA.serverId, 4242);

      final storedB = await isar.localPrograms.get(programB.localId);
      expect(
        storedB!.syncStatus,
        'pending_create',
        reason: 'B\'s program must never be touched by A\'s pass',
      );
      expect(storedB.serverId, isNull);

      verify(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).called(1);
    });
  });

  // ============ Child ownership (tests 18-23) ============

  group('child ownership - Exercise (test 18)', () {
    test(
      'A-owned exercise syncs; B-owned and orphaned exercises do not',
      () async {
        final sessionA = await insertSession(uid: userA, serverId: 10);
        final sessionB = await insertSession(uid: userB, serverId: 20);

        final ownedExercise = LocalExercise(
          sessionLocalId: sessionA.localId,
          sessionServerId: sessionA.serverId,
          name: 'Owned',
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        final foreignExercise = LocalExercise(
          sessionLocalId: sessionB.localId,
          sessionServerId: sessionB.serverId,
          name: 'Foreign',
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        final orphanExercise = LocalExercise(
          sessionLocalId: 999999,
          name: 'Orphan',
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        await isar.writeTxn(() async {
          await isar.localExercises.putAll([
            ownedExercise,
            foreignExercise,
            orphanExercise,
          ]);
        });

        when(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async => {'id': 5001});

        await syncService.sync();

        final storedOwned = await isar.localExercises.get(
          ownedExercise.localId,
        );
        expect(storedOwned!.isSynced, isTrue);
        expect(storedOwned.serverId, 5001);

        final storedForeign = await isar.localExercises.get(
          foreignExercise.localId,
        );
        expect(storedForeign!.syncStatus, 'pending_create');
        expect(storedForeign.serverId, isNull);
        expect(storedForeign.syncRetryCount, 0);

        final storedOrphan = await isar.localExercises.get(
          orphanExercise.localId,
        );
        expect(storedOrphan!.syncStatus, 'pending_create');
        expect(storedOrphan.serverId, isNull);

        verify(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).called(1);
      },
    );

    test('reassigning the parent session\'s owner between dispatch and '
        'acknowledgment blocks acknowledgment - the reacquire checkpoint '
        'reads the parent fresh, never a cached owner from the pre-dispatch '
        'filter', () async {
      final sessionA = await insertSession(uid: userA, serverId: 11);
      final exercise = LocalExercise(
        sessionLocalId: sessionA.localId,
        sessionServerId: sessionA.serverId,
        name: 'Reassigned mid-flight',
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_create',
      );
      await isar.writeTxn(() => isar.localExercises.put(exercise));

      // The POST answer runs the instant `sync()` dispatches it - i.e. after
      // the pre-dispatch owner filter has already cached the parent as
      // A-owned. It reassigns the parent session to B, then hands back the
      // test-released response, so the acknowledgment path (which runs after
      // the response) sees the reassigned owner - exactly a mid-flight
      // reassignment, with no event-queue pumping.
      final release = Completer<Map<String, dynamic>>();
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async {
        await isar.writeTxn(() async {
          final s = await isar.localSessions.get(sessionA.localId);
          s!.userId = userB;
          await isar.localSessions.put(s);
        });
        return release.future;
      });

      final syncFuture = syncService.sync();
      release.complete({'id': 5050});
      await syncFuture;

      final stored = await isar.localExercises.get(exercise.localId);
      expect(
        stored!.syncStatus,
        'pending_create',
        reason:
            'the reacquire checkpoint must re-read the parent session '
            'fresh and reject, not trust a cached A-owned result',
      );
      expect(stored.serverId, isNull);
    });
  });

  group('child ownership - ExerciseSet (test 19)', () {
    test('A-owned set syncs; B-owned (via grandparent session) and orphaned '
        'sets do not', () async {
      final sessionA = await insertSession(uid: userA, serverId: 10);
      final sessionB = await insertSession(uid: userB, serverId: 20);

      final exerciseA = LocalExercise(
        sessionLocalId: sessionA.localId,
        sessionServerId: sessionA.serverId,
        serverId: 100,
        name: 'A exercise',
        lastModifiedLocal: DateTime.now(),
        isSynced: true,
        syncStatus: 'synced',
      );
      final exerciseB = LocalExercise(
        sessionLocalId: sessionB.localId,
        sessionServerId: sessionB.serverId,
        serverId: 200,
        name: 'B exercise',
        lastModifiedLocal: DateTime.now(),
        isSynced: true,
        syncStatus: 'synced',
      );
      await isar.writeTxn(() async {
        await isar.localExercises.putAll([exerciseA, exerciseB]);
      });

      final ownedSet = LocalExerciseSet(
        exerciseLocalId: exerciseA.localId,
        exerciseServerId: exerciseA.serverId,
        setNumber: 1,
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_create',
      );
      final foreignSet = LocalExerciseSet(
        exerciseLocalId: exerciseB.localId,
        exerciseServerId: exerciseB.serverId,
        setNumber: 1,
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_create',
      );
      final orphanSet = LocalExerciseSet(
        exerciseLocalId: 999999,
        setNumber: 1,
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_create',
      );
      await isar.writeTxn(() async {
        await isar.localExerciseSets.putAll([ownedSet, foreignSet, orphanSet]);
      });

      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async => {'id': 6001});

      await syncService.sync();

      final storedOwned = await isar.localExerciseSets.get(ownedSet.localId);
      expect(storedOwned!.isSynced, isTrue);
      expect(storedOwned.serverId, 6001);

      final storedForeign = await isar.localExerciseSets.get(
        foreignSet.localId,
      );
      expect(storedForeign!.syncStatus, 'pending_create');
      expect(storedForeign.serverId, isNull);

      final storedOrphan = await isar.localExerciseSets.get(orphanSet.localId);
      expect(storedOrphan!.syncStatus, 'pending_create');
      expect(storedOrphan.serverId, isNull);

      verify(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).called(1);
    });
  });

  group('child ownership - ProgramWorkout (test 20)', () {
    test(
      'A-owned workout syncs; B-owned and orphaned workouts do not',
      () async {
        final programA = await insertProgram(uid: userA, serverId: 30);
        final programB = await insertProgram(uid: userB, serverId: 40);

        final ownedWorkout = LocalProgramWorkout(
          programLocalId: programA.localId,
          programServerId: programA.serverId,
          weekNumber: 1,
          dayNumber: 1,
          workoutName: 'Owned',
          exercisesJson: '[]',
          orderIndex: 0,
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        final foreignWorkout = LocalProgramWorkout(
          programLocalId: programB.localId,
          programServerId: programB.serverId,
          weekNumber: 1,
          dayNumber: 1,
          workoutName: 'Foreign',
          exercisesJson: '[]',
          orderIndex: 0,
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        final orphanWorkout = LocalProgramWorkout(
          programLocalId: 999999,
          weekNumber: 1,
          dayNumber: 1,
          workoutName: 'Orphan',
          exercisesJson: '[]',
          orderIndex: 0,
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        await isar.writeTxn(() async {
          await isar.localProgramWorkouts.putAll([
            ownedWorkout,
            foreignWorkout,
            orphanWorkout,
          ]);
        });

        when(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async => {'id': 7001});

        await syncService.sync();

        final storedOwned = await isar.localProgramWorkouts.get(
          ownedWorkout.localId,
        );
        expect(storedOwned!.isSynced, isTrue);
        expect(storedOwned.serverId, 7001);

        final storedForeign = await isar.localProgramWorkouts.get(
          foreignWorkout.localId,
        );
        expect(storedForeign!.syncStatus, 'pending_create');
        expect(storedForeign.serverId, isNull);

        final storedOrphan = await isar.localProgramWorkouts.get(
          orphanWorkout.localId,
        );
        expect(storedOrphan!.syncStatus, 'pending_create');
        expect(storedOrphan.serverId, isNull);

        verify(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).called(1);
      },
    );
  });

  group('child ownership - MealEntry (test 21)', () {
    test(
      'A-owned meal entry syncs; B-owned and orphaned entries do not',
      () async {
        final logA = await insertMealLog(uid: userA, serverId: 50);
        final logB = await insertMealLog(uid: userB, serverId: 60);

        final ownedEntry = LocalMealEntry(
          mealLogLocalId: logA.localId,
          mealLogServerId: logA.serverId,
          mealType: 'Breakfast',
          createdAt: DateTime.now(),
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        final foreignEntry = LocalMealEntry(
          mealLogLocalId: logB.localId,
          mealLogServerId: logB.serverId,
          mealType: 'Breakfast',
          createdAt: DateTime.now(),
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        final orphanEntry = LocalMealEntry(
          mealLogLocalId: 999999,
          mealType: 'Breakfast',
          createdAt: DateTime.now(),
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        await isar.writeTxn(() async {
          await isar.localMealEntrys.putAll([
            ownedEntry,
            foreignEntry,
            orphanEntry,
          ]);
        });

        when(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async => {'id': 8001});

        await syncService.sync();

        final storedOwned = await isar.localMealEntrys.get(ownedEntry.localId);
        expect(storedOwned!.isSynced, isTrue);
        expect(storedOwned.serverId, 8001);

        final storedForeign = await isar.localMealEntrys.get(
          foreignEntry.localId,
        );
        expect(storedForeign!.syncStatus, 'pending_create');
        expect(storedForeign.serverId, isNull);

        final storedOrphan = await isar.localMealEntrys.get(
          orphanEntry.localId,
        );
        expect(storedOrphan!.syncStatus, 'pending_create');
        expect(storedOrphan.serverId, isNull);

        verify(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).called(1);
      },
    );
  });

  group('child ownership - FoodItem (test 22)', () {
    test('A-owned food item syncs; B-owned (via grandparent meal log) and '
        'orphaned items do not', () async {
      final logA = await insertMealLog(uid: userA, serverId: 70);
      final logB = await insertMealLog(uid: userB, serverId: 80);

      final entryA = await insertMealEntry(
        mealLogLocalId: logA.localId,
        serverId: 700,
      );
      final entryB = await insertMealEntry(
        mealLogLocalId: logB.localId,
        serverId: 800,
      );

      final ownedItem = LocalFoodItem(
        mealEntryLocalId: entryA.localId,
        mealEntryServerId: entryA.serverId,
        name: 'Owned food',
        calories: 100,
        protein: 1,
        carbohydrates: 1,
        fat: 1,
        createdAt: DateTime.now(),
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_create',
      );
      final foreignItem = LocalFoodItem(
        mealEntryLocalId: entryB.localId,
        mealEntryServerId: entryB.serverId,
        name: 'Foreign food',
        calories: 100,
        protein: 1,
        carbohydrates: 1,
        fat: 1,
        createdAt: DateTime.now(),
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_create',
      );
      final orphanItem = LocalFoodItem(
        mealEntryLocalId: 999999,
        name: 'Orphan food',
        calories: 100,
        protein: 1,
        carbohydrates: 1,
        fat: 1,
        createdAt: DateTime.now(),
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_create',
      );
      await isar.writeTxn(() async {
        await isar.localFoodItems.putAll([ownedItem, foreignItem, orphanItem]);
      });

      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async => {'id': 9001});

      await syncService.sync();

      final storedOwned = await isar.localFoodItems.get(ownedItem.localId);
      expect(storedOwned!.isSynced, isTrue);
      expect(storedOwned.serverId, 9001);

      final storedForeign = await isar.localFoodItems.get(foreignItem.localId);
      expect(storedForeign!.syncStatus, 'pending_create');
      expect(storedForeign.serverId, isNull);

      final storedOrphan = await isar.localFoodItems.get(orphanItem.localId);
      expect(storedOrphan!.syncStatus, 'pending_create');
      expect(storedOrphan.serverId, isNull);

      // Exactly one create call - for the owned item only. No rejected
      // row caused any HTTP dispatch, success acknowledgment, or error
      // acknowledgment (test 23).
      verify(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).called(1);
    });

    test(
      'reassigning the grandparent meal log\'s owner between dispatch and '
      'acknowledgment blocks acknowledgment - the two-level reacquire '
      'checkpoint reads the whole chain fresh, never a cached owner',
      () async {
        final logA = await insertMealLog(uid: userA, serverId: 71);
        final entryA = await insertMealEntry(
          mealLogLocalId: logA.localId,
          serverId: 701,
        );
        final item = LocalFoodItem(
          mealEntryLocalId: entryA.localId,
          mealEntryServerId: entryA.serverId,
          name: 'Reassigned mid-flight',
          calories: 100,
          protein: 1,
          carbohydrates: 1,
          fat: 1,
          createdAt: DateTime.now(),
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        await isar.writeTxn(() => isar.localFoodItems.put(item));

        // The POST answer runs the instant `sync()` dispatches it - after the
        // pre-dispatch owner filter has cached the grandparent as A-owned. It
        // reassigns the grandparent meal log to B, then hands back the
        // test-released response, so the two-level reacquire checkpoint (which
        // runs after the response) reads the reassigned owner - a mid-flight
        // reassignment with no event-queue pumping.
        final release = Completer<Map<String, dynamic>>();
        when(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async {
          await isar.writeTxn(() async {
            final l = await isar.localMealLogs.get(logA.localId);
            l!.userId = userB;
            await isar.localMealLogs.put(l);
          });
          return release.future;
        });

        final syncFuture = syncService.sync();
        release.complete({'id': 9101});
        await syncFuture;

        final stored = await isar.localFoodItems.get(item.localId);
        expect(
          stored!.syncStatus,
          'pending_create',
          reason:
              'the reacquire checkpoint must re-read the full parent '
              'chain fresh and reject, not trust a cached A-owned result',
        );
        expect(stored.serverId, isNull);
      },
    );
  });

  // ================================================================
  // Legacy `serverId == 0` compatibility (exercise / set sync phases)
  // ================================================================
  //
  // App versions before `ModelMapper.publicRowId` persisted offline-created
  // LocalExercise / LocalExerciseSet rows with `serverId == 0` (the raw
  // `apiSet.id` of a `ExerciseSet(id: 0, ...)`). After upgrading, such a row
  // can also transition into `pending_update` (completed offline) or
  // `pending_delete` (deleted offline). SyncService must treat `serverId == 0`
  // exactly like `serverId == null` in these phases and never emit a
  // `/exercises/0` or `/exercisesets/0` route or a `exerciseId: 0` body.

  group('legacy serverId == 0 - exercise sets', () {
    Future<LocalExercise> insertSyncedExercise({
      required int sessionLocalId,
      required int? sessionServerId,
      required int serverId,
    }) async {
      final ex = LocalExercise(
        sessionLocalId: sessionLocalId,
        sessionServerId: sessionServerId,
        serverId: serverId,
        name: 'Bench',
        lastModifiedLocal: DateTime.now(),
        isSynced: true,
        syncStatus: 'synced',
      );
      await isar.writeTxn(() => isar.localExercises.put(ex));
      return ex;
    }

    Future<LocalExerciseSet> insertLegacyZeroSet({
      required int exerciseLocalId,
      int? exerciseServerId,
      required String syncStatus,
      bool isCompleted = false,
      DateTime? completedAt,
    }) async {
      final s = LocalExerciseSet(
        serverId: 0, // legacy sentinel
        exerciseLocalId: exerciseLocalId,
        exerciseServerId: exerciseServerId,
        setNumber: 1,
        reps: 10,
        weight: 100,
        isCompleted: isCompleted,
        completedAt: completedAt,
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: syncStatus,
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(s));
      return s;
    }

    void stubPost(int returnedId) {
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async => {'id': returnedId});
    }

    void expectNoZeroRoute() {
      verifyNever(
        mockApiService.put<void>(
          argThat(contains('/0')),
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      verifyNever(
        mockApiService.delete(
          argThat(contains('/0')),
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
    }

    test('legacy serverId==0, pending_create: sends CREATE (no /0), assigns '
        'the returned positive server id, marks synced', () async {
      final session = await insertSession(uid: userA, serverId: 10);
      final ex = await insertSyncedExercise(
        sessionLocalId: session.localId,
        sessionServerId: 10,
        serverId: 100,
      );
      final set = await insertLegacyZeroSet(
        exerciseLocalId: ex.localId,
        exerciseServerId: 100,
        syncStatus: 'pending_create',
      );
      stubPost(6001);

      await syncService.sync();

      expectNoZeroRoute();
      final captured =
          verify(
            mockApiService.post<Map<String, dynamic>>(
              captureAny,
              data: captureAnyNamed('data'),
              sessionContext: anyNamed('sessionContext'),
            ),
          ).captured;
      expect(captured[0], ApiConfig.exerciseSets);
      expect((captured[1] as Map)['exerciseId'], 100);

      final stored = await isar.localExerciseSets.get(set.localId);
      expect(stored!.serverId, 6001);
      expect(stored.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
    });

    test('legacy serverId==0, completed offline (pending_update): sends CREATE '
        'with isCompleted, NOT PUT /exercisesets/0', () async {
      final session = await insertSession(uid: userA, serverId: 10);
      final ex = await insertSyncedExercise(
        sessionLocalId: session.localId,
        sessionServerId: 10,
        serverId: 100,
      );
      final completedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final set = await insertLegacyZeroSet(
        exerciseLocalId: ex.localId,
        exerciseServerId: 100,
        syncStatus: 'pending_update',
        isCompleted: true,
        completedAt: completedAt,
      );
      stubPost(6002);

      await syncService.sync();

      expectNoZeroRoute();
      final captured =
          verify(
            mockApiService.post<Map<String, dynamic>>(
              captureAny,
              data: captureAnyNamed('data'),
              sessionContext: anyNamed('sessionContext'),
            ),
          ).captured;
      expect(captured[0], ApiConfig.exerciseSets);
      final body = captured[1] as Map;
      expect(body['exerciseId'], 100);
      // The CREATE carries the latest completed state (Isar returns the
      // timestamp local-flagged but instant-correct; the point is it is sent).
      expect(body['isCompleted'], isTrue);
      expect(body['completedAt'], isA<String>());
      expect(
        DateTime.parse(body['completedAt'] as String).microsecondsSinceEpoch,
        completedAt.microsecondsSinceEpoch,
      );

      final stored = await isar.localExerciseSets.get(set.localId);
      expect(stored!.serverId, 6002);
      expect(stored.isCompleted, isTrue);
      expect(stored.syncStatus, 'synced');
    });

    test('legacy serverId==0, deleted offline (pending_delete): NO DELETE /0, '
        'the row is removed locally and not left stuck', () async {
      final session = await insertSession(uid: userA, serverId: 10);
      final ex = await insertSyncedExercise(
        sessionLocalId: session.localId,
        sessionServerId: 10,
        serverId: 100,
      );
      final set = await insertLegacyZeroSet(
        exerciseLocalId: ex.localId,
        exerciseServerId: 100,
        syncStatus: 'pending_delete',
      );

      await syncService.sync();

      expectNoZeroRoute();
      verifyNever(
        mockApiService.delete(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      expect(await isar.localExerciseSets.get(set.localId), isNull);
    });

    test(
      'legacy parent exercise serverId==0: parent CREATEs first, then the '
      'child set CREATEs against the REAL parent id, never exerciseId 0',
      () async {
        final session = await insertSession(uid: userA, serverId: 10);
        final legacyEx = LocalExercise(
          sessionLocalId: session.localId,
          sessionServerId: 10,
          serverId: 0, // legacy
          name: 'Legacy',
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
        );
        await isar.writeTxn(() => isar.localExercises.put(legacyEx));
        final set = await insertLegacyZeroSet(
          exerciseLocalId: legacyEx.localId,
          exerciseServerId: 0,
          syncStatus: 'pending_create',
        );
        // The exercise phase runs before the set phase: the legacy-0 parent is
        // resolved to a real positive id (111) first, so the child set CREATE
        // then carries exerciseId 111 - never 0.
        var call = 0;
        when(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async {
          call++;
          return {'id': call == 1 ? 111 : 6003};
        });

        await syncService.sync();

        expectNoZeroRoute();
        final storedEx = await isar.localExercises.get(legacyEx.localId);
        expect(storedEx!.serverId, 111);
        final storedSet = await isar.localExerciseSets.get(set.localId);
        expect(storedSet!.serverId, 6003);
        expect(storedSet.syncStatus, 'synced');
        final captured =
            verify(
              mockApiService.post<Map<String, dynamic>>(
                captureAny,
                data: captureAnyNamed('data'),
                sessionContext: anyNamed('sessionContext'),
              ),
            ).captured;
        for (var i = 0; i + 1 < captured.length; i += 2) {
          expect(captured[i], isNot(contains('/0')));
          final body = captured[i + 1];
          if (body is Map && body.containsKey('exerciseId')) {
            expect(
              body['exerciseId'],
              111,
              reason: 'child never posts exerciseId 0',
            );
          }
        }
      },
    );

    test(
      'valid serverId 42 pending_update still PUTs /exercisesets/42',
      () async {
        final session = await insertSession(uid: userA, serverId: 10);
        final ex = await insertSyncedExercise(
          sessionLocalId: session.localId,
          sessionServerId: 10,
          serverId: 100,
        );
        final set = LocalExerciseSet(
          serverId: 42,
          exerciseLocalId: ex.localId,
          exerciseServerId: 100,
          setNumber: 1,
          reps: 8,
          weight: 90,
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_update',
        );
        await isar.writeTxn(() => isar.localExerciseSets.put(set));
        when(
          mockApiService.put<void>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async {});

        await syncService.sync();

        final captured =
            verify(
              mockApiService.put<void>(
                captureAny,
                data: anyNamed('data'),
                sessionContext: anyNamed('sessionContext'),
              ),
            ).captured;
        expect(captured.single, '${ApiConfig.exerciseSets}/42');
        verifyNever(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        );
      },
    );

    test(
      'valid serverId 42 pending_delete still DELETEs /exercisesets/42',
      () async {
        final session = await insertSession(uid: userA, serverId: 10);
        final ex = await insertSyncedExercise(
          sessionLocalId: session.localId,
          sessionServerId: 10,
          serverId: 100,
        );
        final set = LocalExerciseSet(
          serverId: 42,
          exerciseLocalId: ex.localId,
          exerciseServerId: 100,
          setNumber: 1,
          lastModifiedLocal: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_delete',
        );
        await isar.writeTxn(() => isar.localExerciseSets.put(set));
        when(
          mockApiService.delete(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async => true);

        await syncService.sync();

        final captured =
            verify(
              mockApiService.delete(
                captureAny,
                data: anyNamed('data'),
                sessionContext: anyNamed('sessionContext'),
              ),
            ).captured;
        expect(captured.single, '${ApiConfig.exerciseSets}/42');
        expect(await isar.localExerciseSets.get(set.localId), isNull);
      },
    );

    test('foreign-owner legacy zero set is skipped (never uploaded)', () async {
      final sessionB = await insertSession(uid: userB, serverId: 20);
      final exB = await insertSyncedExercise(
        sessionLocalId: sessionB.localId,
        sessionServerId: 20,
        serverId: 200,
      );
      final set = await insertLegacyZeroSet(
        exerciseLocalId: exB.localId,
        exerciseServerId: 200,
        syncStatus: 'pending_update',
        isCompleted: true,
      );

      await syncService.sync();

      verifyNever(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      expectNoZeroRoute();
      final stored = await isar.localExerciseSets.get(set.localId);
      expect(stored!.syncStatus, 'pending_update');
      expect(stored.serverId, 0);
    });

    test('orphan legacy zero set (no parent exercise) is skipped', () async {
      final set = await insertLegacyZeroSet(
        exerciseLocalId: 999999,
        syncStatus: 'pending_update',
        isCompleted: true,
      );

      await syncService.sync();

      verifyNever(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      expectNoZeroRoute();
      expect(
        (await isar.localExerciseSets.get(set.localId))!.syncStatus,
        'pending_update',
      );
    });

    test('logout during the legacy-zero create pass writes nothing '
        'afterward', () async {
      final session = await insertSession(uid: userA, serverId: 10);
      final ex = await insertSyncedExercise(
        sessionLocalId: session.localId,
        sessionServerId: 10,
        serverId: 100,
      );
      final set = await insertLegacyZeroSet(
        exerciseLocalId: ex.localId,
        exerciseServerId: 100,
        syncStatus: 'pending_update',
        isCompleted: true,
      );

      // The POST answer runs the instant `sync()` dispatches the (converted)
      // CREATE - after all pre-dispatch filtering. It logs out, then hands
      // back the test-released response, so the post-dispatch `_assertCurrent`
      // sees the ended session and aborts the acknowledgment write - a
      // mid-flight logout with no event-queue pumping.
      final release = Completer<Map<String, dynamic>>();
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) {
        sessionEpoch.invalidate();
        return release.future;
      });

      final syncFuture = syncService.sync();
      release.complete({'id': 6004});
      await syncFuture;

      final stored = await isar.localExerciseSets.get(set.localId);
      expect(stored!.syncStatus, 'pending_update');
      expect(stored.serverId, 0);
    });
  });

  group('legacy serverId == 0 - exercises', () {
    test('legacy exercise serverId==0 pending_update converts to CREATE, '
        'no PUT /exercises/0', () async {
      final session = await insertSession(uid: userA, serverId: 10);
      final ex = LocalExercise(
        sessionLocalId: session.localId,
        sessionServerId: 10,
        serverId: 0, // legacy
        name: 'Legacy edited',
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_update',
      );
      await isar.writeTxn(() => isar.localExercises.put(ex));
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async => {'id': 500});

      await syncService.sync();

      verifyNever(
        mockApiService.put<void>(
          argThat(contains('/0')),
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      final captured =
          verify(
            mockApiService.post<Map<String, dynamic>>(
              captureAny,
              data: anyNamed('data'),
              sessionContext: anyNamed('sessionContext'),
            ),
          ).captured;
      expect(captured.single, '${ApiConfig.sessions}/10/exercises');
      final stored = await isar.localExercises.get(ex.localId);
      expect(stored!.serverId, 500);
      expect(stored.syncStatus, 'synced');
    });

    test('legacy exercise serverId==0 pending_delete: NO DELETE /exercises/0, '
        'removed locally', () async {
      final session = await insertSession(uid: userA, serverId: 10);
      final ex = LocalExercise(
        sessionLocalId: session.localId,
        sessionServerId: 10,
        serverId: 0,
        name: 'Legacy deleted',
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_delete',
      );
      await isar.writeTxn(() => isar.localExercises.put(ex));

      await syncService.sync();

      verifyNever(
        mockApiService.delete(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      expect(await isar.localExercises.get(ex.localId), isNull);
    });
  });

  group('legacy serverId == 0 - parent-chain gates', () {
    Future<LocalExerciseSet> insertLegacyZeroSet({
      required int exerciseLocalId,
      int? exerciseServerId,
      required String syncStatus,
      bool isCompleted = false,
    }) async {
      final s = LocalExerciseSet(
        serverId: 0,
        exerciseLocalId: exerciseLocalId,
        exerciseServerId: exerciseServerId,
        setNumber: 1,
        reps: 10,
        weight: 100,
        isCompleted: isCompleted,
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: syncStatus,
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(s));
      return s;
    }

    void stubPost(int returnedId) {
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async => {'id': returnedId});
    }

    void expectNoZeroRoute() {
      verifyNever(
        mockApiService.put<void>(
          argThat(contains('/0')),
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      verifyNever(
        mockApiService.delete(
          argThat(contains('/0')),
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
    }

    Future<LocalExercise> insertSyncedLegacyZeroExercise({
      required int sessionLocalId,
      int? sessionServerId,
    }) async {
      final ex = LocalExercise(
        sessionLocalId: sessionLocalId,
        sessionServerId: sessionServerId,
        serverId: 0, // legacy sentinel, but the row is marked synced
        name: 'LegacyParent',
        lastModifiedLocal: DateTime.now(),
        isSynced: true,
        syncStatus: 'synced',
      );
      await isar.writeTxn(() => isar.localExercises.put(ex));
      return ex;
    }

    void expectNoZeroSessionRoute() {
      verifyNever(
        mockApiService.post<Map<String, dynamic>>(
          argThat(contains('/0/')),
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
    }

    test('legacy session serverId==0: a pending_create child exercise waits, '
        'never POSTs /sessions/0/exercises', () async {
      final session = await insertSession(uid: userA, serverId: 0);
      final ex = LocalExercise(
        sessionLocalId: session.localId,
        sessionServerId: 0,
        name: 'Child',
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_create',
      );
      await isar.writeTxn(() => isar.localExercises.put(ex));
      stubPost(777);

      await syncService.sync();

      expectNoZeroSessionRoute();
      final stored = await isar.localExercises.get(ex.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.serverId, anyOf(isNull, 0));
    });

    test('legacy session serverId==0: a pending_update child exercise with no '
        'server id is NOT converted to a CREATE against /sessions/0', () async {
      final session = await insertSession(uid: userA, serverId: 0);
      final ex = LocalExercise(
        sessionLocalId: session.localId,
        sessionServerId: 0,
        serverId: 0,
        name: 'Child edited',
        lastModifiedLocal: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_update',
      );
      await isar.writeTxn(() => isar.localExercises.put(ex));
      stubPost(778);

      await syncService.sync();

      expectNoZeroSessionRoute();
      verifyNever(
        mockApiService.put<void>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      expect(
        (await isar.localExercises.get(ex.localId))!.syncStatus,
        'pending_update',
      );
    });

    test('legacy parent exercise serverId==0 (marked synced): a pending_create '
        'child set waits, never POSTs a set with exerciseId 0', () async {
      final session = await insertSession(uid: userA, serverId: 10);
      final parent = await insertSyncedLegacyZeroExercise(
        sessionLocalId: session.localId,
        sessionServerId: 10,
      );
      final set = await insertLegacyZeroSet(
        exerciseLocalId: parent.localId,
        exerciseServerId: 0,
        syncStatus: 'pending_create',
      );
      stubPost(9001);

      await syncService.sync();

      expectNoZeroRoute();
      verifyNever(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: argThat(containsPair('exerciseId', 0), named: 'data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      final stored = await isar.localExerciseSets.get(set.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.serverId, anyOf(isNull, 0));
    });

    test(
      'legacy parent exercise serverId==0 (marked synced): a pending_update '
      'child set with no server id is NOT created against exerciseId 0',
      () async {
        final session = await insertSession(uid: userA, serverId: 10);
        final parent = await insertSyncedLegacyZeroExercise(
          sessionLocalId: session.localId,
          sessionServerId: 10,
        );
        final set = await insertLegacyZeroSet(
          exerciseLocalId: parent.localId,
          exerciseServerId: 0,
          syncStatus: 'pending_update',
          isCompleted: true,
        );
        stubPost(9002);

        await syncService.sync();

        expectNoZeroRoute();
        verifyNever(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: argThat(containsPair('exerciseId', 0), named: 'data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        );
        final stored = await isar.localExerciseSets.get(set.localId);
        expect(stored!.syncStatus, 'pending_update');
      },
    );

    test(
      '_syncCreateSet: a logout landing inside the acknowledgment writeTxn '
      'aborts the write - the set stays pending_create, not synced',
      () async {
        final session = await insertSession(uid: userA, serverId: 10);
        final ex = LocalExercise(
          sessionLocalId: session.localId,
          sessionServerId: 10,
          serverId: 100,
          name: 'Bench',
          lastModifiedLocal: DateTime.now(),
          isSynced: true,
          syncStatus: 'synced',
        );
        await isar.writeTxn(() => isar.localExercises.put(ex));
        final set = await insertLegacyZeroSet(
          exerciseLocalId: ex.localId,
          exerciseServerId: 100,
          syncStatus: 'pending_create',
        );
        stubPost(7777);
        syncService.insideAckWriteTxnForTesting =
            () async => sessionEpoch.invalidate();

        await syncService.sync();

        final stored = await isar.localExerciseSets.get(set.localId);
        expect(stored!.syncStatus, 'pending_create');
        expect(stored.isSynced, isFalse);
        expect(stored.serverId, anyOf(isNull, 0));
      },
    );
  });
}
