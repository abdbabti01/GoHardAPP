import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_food_item.dart';
import 'package:go_hard_app/data/local/models/local_food_template.dart';
import 'package:go_hard_app/data/local/models/local_meal_entry.dart';
import 'package:go_hard_app/data/local/models/local_meal_log.dart';
import 'package:go_hard_app/data/local/models/local_nutrition_goal.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/food_item.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'nutrition_repository_consumed_totals_test.mocks.dart';

@GenerateMocks([ApiService, AuthService, ConnectivityService])
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;
  late LocalDatabaseService localDb;
  late NutritionRepository repository;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;

  const userId = 1;
  const otherUserId = 2;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nutrition_repo_consumed_');
    isar = await Isar.open(
      [
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
    mockConnectivity = MockConnectivityService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userId);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'test-jwt');
    // Most mutation sites are exercised offline: this is where the bug
    // lived, and it keeps every test free of background-sync stubbing.
    when(mockConnectivity.isOnline).thenReturn(false);

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch()..activate(userId);
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );

    repository = NutritionRepository(
      mockApiService,
      localDb,
      mockConnectivity,
      mockAuthService,
      sessionEpoch,
      sessionCoordinator,
    );
  });

  tearDown(() async {
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LocalMealLog> insertMealLog({
    int uid = userId,
    DateTime? date,
    int? serverId,
    double totalCalories = 0,
    double totalProtein = 0,
    double totalCarbohydrates = 0,
    double totalFat = 0,
  }) async {
    final now = DateTime.now();
    final log = LocalMealLog(
      serverId: serverId,
      userId: uid,
      date: date ?? DateTime(2026, 1, 1),
      totalCalories: totalCalories,
      totalProtein: totalProtein,
      totalCarbohydrates: totalCarbohydrates,
      totalFat: totalFat,
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localMealLogs.put(log));
    return log;
  }

  Future<LocalMealEntry> insertMealEntry({
    required int mealLogLocalId,
    bool isConsumed = false,
    double totalCalories = 0,
    double totalProtein = 0,
    double totalCarbohydrates = 0,
    double totalFat = 0,
    String mealType = 'Breakfast',
  }) async {
    final now = DateTime.now();
    final entry = LocalMealEntry(
      mealLogLocalId: mealLogLocalId,
      mealType: mealType,
      isConsumed: isConsumed,
      totalCalories: totalCalories,
      totalProtein: totalProtein,
      totalCarbohydrates: totalCarbohydrates,
      totalFat: totalFat,
      createdAt: now,
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localMealEntrys.put(entry));
    return entry;
  }

  Future<LocalFoodItem> insertFoodItem({
    required int mealEntryLocalId,
    required double calories,
    required double protein,
    required double carbohydrates,
    required double fat,
    double quantity = 1,
  }) async {
    final now = DateTime.now();
    final food = LocalFoodItem(
      mealEntryLocalId: mealEntryLocalId,
      name: 'Test food',
      quantity: quantity,
      calories: calories,
      protein: protein,
      carbohydrates: carbohydrates,
      fat: fat,
      createdAt: now,
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localFoodItems.put(food));
    return food;
  }

  Future<LocalMealLog> storedMealLog(int localId) async {
    final log = await isar.localMealLogs.get(localId);
    expect(log, isNotNull, reason: 'meal log $localId should still exist');
    return log!;
  }

  Future<LocalMealEntry> storedMealEntry(int localId) async {
    final entry = await isar.localMealEntrys.get(localId);
    expect(entry, isNotNull, reason: 'meal entry $localId should still exist');
    return entry!;
  }

  group('addFoodItem - consumed reconciliation', () {
    test(
      'adding food to an unconsumed entry increases planned but not meal-log consumed totals',
      () async {
        final log = await insertMealLog();
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
        );

        await repository.addFoodItem(
          FoodItem(
            id: 0,
            mealEntryId: entry.localId,
            name: 'Toast',
            calories: 200,
            protein: 5,
            carbohydrates: 30,
            fat: 4,
            createdAt: DateTime.now(),
          ),
        );

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 0);
        expect(storedLog.totalProtein, 0);
        expect(storedLog.totalCarbohydrates, 0);
        expect(storedLog.totalFat, 0);

        final storedEntry = await storedMealEntry(entry.localId);
        expect(storedEntry.totalCalories, 200);
        expect(storedEntry.totalProtein, 5);
        expect(storedEntry.totalCarbohydrates, 30);
        expect(storedEntry.totalFat, 4);
      },
    );

    test(
      'adding food to a consumed entry increases both planned and meal-log consumed totals',
      () async {
        final log = await insertMealLog();
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
        );

        await repository.addFoodItem(
          FoodItem(
            id: 0,
            mealEntryId: entry.localId,
            name: 'Eggs',
            calories: 150,
            protein: 12,
            carbohydrates: 2,
            fat: 10,
            createdAt: DateTime.now(),
          ),
        );

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 150);
        expect(storedLog.totalProtein, 12);
        expect(storedLog.totalCarbohydrates, 2);
        expect(storedLog.totalFat, 10);
      },
    );
  });

  group('quickAddFood - consumed reconciliation', () {
    Future<LocalFoodTemplate> insertTemplate({int serverId = 500}) async {
      final now = DateTime.now();
      final template = LocalFoodTemplate(
        serverId: serverId,
        name: 'Banana',
        calories: 105,
        protein: 1.3,
        carbohydrates: 27,
        fat: 0.4,
        createdAt: now,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: now,
      );
      await isar.writeTxn(() => isar.localFoodTemplates.put(template));
      return template;
    }

    test(
      'quickAddFood to an unconsumed entry leaves meal-log consumed totals unchanged',
      () async {
        final log = await insertMealLog();
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
        );
        final template = await insertTemplate();

        await repository.quickAddFood(
          mealEntryId: entry.localId,
          foodTemplateId: template.serverId!,
        );

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 0);
        expect(storedLog.totalProtein, 0);
        expect(storedLog.totalCarbohydrates, 0);
        expect(storedLog.totalFat, 0);
      },
    );

    test(
      'quickAddFood to a consumed entry increases meal-log consumed totals',
      () async {
        final log = await insertMealLog();
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
        );
        final template = await insertTemplate();

        await repository.quickAddFood(
          mealEntryId: entry.localId,
          foodTemplateId: template.serverId!,
        );

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 105);
        expect(storedLog.totalProtein, closeTo(1.3, 1e-9));
        expect(storedLog.totalCarbohydrates, 27);
        expect(storedLog.totalFat, closeTo(0.4, 1e-9));
      },
    );
  });

  group('markMealAsConsumed reconciliation', () {
    test(
      'marking consumed adds the complete entry total exactly once',
      () async {
        final log = await insertMealLog();
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
          totalCalories: 300,
          totalProtein: 20,
          totalCarbohydrates: 40,
          totalFat: 8,
        );

        await repository.markMealAsConsumed(entry.localId, isConsumed: true);

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 300);
        expect(storedLog.totalProtein, 20);
        expect(storedLog.totalCarbohydrates, 40);
        expect(storedLog.totalFat, 8);
      },
    );

    test(
      'marking unconsumed removes the complete entry total exactly once',
      () async {
        final log = await insertMealLog(
          totalCalories: 300,
          totalProtein: 20,
          totalCarbohydrates: 40,
          totalFat: 8,
        );
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
          totalCalories: 300,
          totalProtein: 20,
          totalCarbohydrates: 40,
          totalFat: 8,
        );

        await repository.markMealAsConsumed(entry.localId, isConsumed: false);

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 0);
        expect(storedLog.totalProtein, 0);
        expect(storedLog.totalCarbohydrates, 0);
        expect(storedLog.totalFat, 0);
      },
    );

    test(
      'repeated consume/unconsume cycles do not drift or double-count',
      () async {
        final log = await insertMealLog();
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
          totalCalories: 300,
          totalProtein: 20,
          totalCarbohydrates: 40,
          totalFat: 8,
        );

        for (var i = 0; i < 3; i++) {
          await repository.markMealAsConsumed(entry.localId, isConsumed: true);
          await repository.markMealAsConsumed(entry.localId, isConsumed: false);
        }
        await repository.markMealAsConsumed(entry.localId, isConsumed: true);
        await repository.markMealAsConsumed(entry.localId, isConsumed: true);

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 300);
        expect(storedLog.totalProtein, 20);
        expect(storedLog.totalCarbohydrates, 40);
        expect(storedLog.totalFat, 8);
      },
    );
  });

  group('updateFoodQuantity reconciliation', () {
    test(
      'editing quantity in a consumed entry moves consumed totals by the delta',
      () async {
        final log = await insertMealLog(
          totalCalories: 100,
          totalProtein: 10,
          totalCarbohydrates: 20,
          totalFat: 5,
        );
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
          totalCalories: 100,
          totalProtein: 10,
          totalCarbohydrates: 20,
          totalFat: 5,
        );
        final food = await insertFoodItem(
          mealEntryLocalId: entry.localId,
          calories: 100,
          protein: 10,
          carbohydrates: 20,
          fat: 5,
          quantity: 1,
        );

        await repository.updateFoodQuantity(food.localId, 2);

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 200);
        expect(storedLog.totalProtein, 20);
        expect(storedLog.totalCarbohydrates, 40);
        expect(storedLog.totalFat, 10);
      },
    );

    test(
      'editing quantity in an unconsumed entry leaves consumed totals unchanged',
      () async {
        final log = await insertMealLog();
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
          totalCalories: 100,
          totalProtein: 10,
          totalCarbohydrates: 20,
          totalFat: 5,
        );
        final food = await insertFoodItem(
          mealEntryLocalId: entry.localId,
          calories: 100,
          protein: 10,
          carbohydrates: 20,
          fat: 5,
          quantity: 1,
        );

        await repository.updateFoodQuantity(food.localId, 3);

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 0);
        expect(storedLog.totalProtein, 0);
        expect(storedLog.totalCarbohydrates, 0);
        expect(storedLog.totalFat, 0);

        final storedEntry = await storedMealEntry(entry.localId);
        expect(storedEntry.totalCalories, 300);
      },
    );
  });

  group('deleteFoodItem reconciliation', () {
    test(
      'deleting food from a consumed entry decreases consumed totals',
      () async {
        final log = await insertMealLog(
          totalCalories: 250,
          totalProtein: 15,
          totalCarbohydrates: 30,
          totalFat: 9,
        );
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
          totalCalories: 250,
          totalProtein: 15,
          totalCarbohydrates: 30,
          totalFat: 9,
        );
        final food = await insertFoodItem(
          mealEntryLocalId: entry.localId,
          calories: 250,
          protein: 15,
          carbohydrates: 30,
          fat: 9,
        );

        await repository.deleteFoodItem(food.localId);

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 0);
        expect(storedLog.totalProtein, 0);
        expect(storedLog.totalCarbohydrates, 0);
        expect(storedLog.totalFat, 0);
      },
    );

    test(
      'deleting food from an unconsumed entry leaves consumed totals unchanged',
      () async {
        final log = await insertMealLog();
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
          totalCalories: 250,
          totalProtein: 15,
          totalCarbohydrates: 30,
          totalFat: 9,
        );
        final food = await insertFoodItem(
          mealEntryLocalId: entry.localId,
          calories: 250,
          protein: 15,
          carbohydrates: 30,
          fat: 9,
        );

        await repository.deleteFoodItem(food.localId);

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 0);
        expect(storedLog.totalProtein, 0);
        expect(storedLog.totalCarbohydrates, 0);
        expect(storedLog.totalFat, 0);

        final storedEntry = await storedMealEntry(entry.localId);
        expect(storedEntry.totalCalories, 0);
      },
    );
  });

  group('legacy-cache read repair', () {
    test(
      'offline read repairs a polluted LocalMealLog without any network call',
      () async {
        // Simulate the old bug's pollution: the stored log total includes
        // an unconsumed entry's food, which should never have happened.
        final log = await insertMealLog(
          totalCalories: 500,
          totalProtein: 40,
          totalCarbohydrates: 60,
          totalFat: 15,
        );
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
          totalCalories: 300,
          totalProtein: 25,
          totalCarbohydrates: 35,
          totalFat: 9,
        );
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
          totalCalories: 200,
          totalProtein: 15,
          totalCarbohydrates: 25,
          totalFat: 6,
        );

        final results = await repository.getMealLogs(
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 1),
        );

        expect(results, hasLength(1));
        expect(results.first.totalCalories, 300);
        expect(results.first.totalProtein, 25);
        expect(results.first.totalCarbohydrates, 35);
        expect(results.first.totalFat, 9);
        expect(results.first.consumedCalories, 300);
        expect(results.first.plannedCalories, 500);

        // Persisted, not just returned in-memory.
        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 300);
        expect(storedLog.totalProtein, 25);
        expect(storedLog.totalCarbohydrates, 35);
        expect(storedLog.totalFat, 9);

        verifyZeroInteractions(mockApiService);
      },
    );

    test(
      'repairing an already-synced polluted row re-queues it for sync',
      () async {
        // This log already reached the server (has a serverId and was
        // marked synced) before the repair runs - e.g. it was polluted by
        // the old bug, synced while still wrong, and only now gets read
        // again under the fixed code. The repair must not just correct the
        // local value silently: _syncMealLogs only ever picks up rows with
        // isSynced == false, so without re-flagging this row, the server's
        // copy would stay wrong forever, and a future server cache
        // replacement could even overwrite this repair right back to the
        // polluted value.
        final log = await insertMealLog(
          serverId: 42,
          totalCalories: 500,
          totalProtein: 40,
          totalCarbohydrates: 60,
          totalFat: 15,
        );
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
          totalCalories: 300,
          totalProtein: 25,
          totalCarbohydrates: 35,
          totalFat: 9,
        );
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
          totalCalories: 200,
          totalProtein: 15,
          totalCarbohydrates: 25,
          totalFat: 6,
        );

        final results = await repository.getMealLogs(
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 1),
        );

        expect(results.first.totalCalories, 300);

        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 300);
        expect(storedLog.isSynced, false);
        expect(storedLog.syncStatus, 'pending_update');

        verifyZeroInteractions(mockApiService);
      },
    );

    test(
      'an already-correct row is not rewritten (idempotent, no-op)',
      () async {
        final log = await insertMealLog(
          serverId: 99,
          totalCalories: 100,
          totalProtein: 10,
          totalCarbohydrates: 20,
          totalFat: 5,
        );
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
          totalCalories: 100,
          totalProtein: 10,
          totalCarbohydrates: 20,
          totalFat: 5,
        );

        final results = await repository.getMealLogs(
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 1),
        );

        expect(results.first.totalCalories, 100);
        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 100);
        // Nothing was stale, so the already-synced status must be left
        // alone - this proves the fix for the finding above doesn't
        // over-trigger and re-queue rows that never needed it.
        expect(storedLog.isSynced, true);
        expect(storedLog.syncStatus, 'synced');
      },
    );
  });

  group('isolation', () {
    test(
      'reconciliation only touches the target meal log - another date/user log is untouched',
      () async {
        final logA = await insertMealLog(
          uid: userId,
          date: DateTime(2026, 1, 1),
        );
        final entryA = await insertMealEntry(
          mealLogLocalId: logA.localId,
          isConsumed: false,
        );

        final logB = await insertMealLog(
          uid: otherUserId,
          date: DateTime(2026, 1, 1),
          totalCalories: 777,
          totalProtein: 44,
          totalCarbohydrates: 55,
          totalFat: 11,
        );

        final logC = await insertMealLog(
          uid: userId,
          date: DateTime(2026, 1, 2),
          totalCalories: 888,
          totalProtein: 33,
          totalCarbohydrates: 22,
          totalFat: 9,
        );

        await repository.addFoodItem(
          FoodItem(
            id: 0,
            mealEntryId: entryA.localId,
            name: 'X',
            calories: 50,
            protein: 1,
            carbohydrates: 1,
            fat: 1,
            createdAt: DateTime.now(),
          ),
        );

        final storedLogB = await storedMealLog(logB.localId);
        expect(storedLogB.totalCalories, 777);
        expect(storedLogB.totalProtein, 44);
        expect(storedLogB.totalCarbohydrates, 55);
        expect(storedLogB.totalFat, 11);

        final storedLogC = await storedMealLog(logC.localId);
        expect(storedLogC.totalCalories, 888);
        expect(storedLogC.totalProtein, 33);
        expect(storedLogC.totalCarbohydrates, 22);
        expect(storedLogC.totalFat, 9);
      },
    );
  });

  group('server cache replacement', () {
    test(
      'a fresh server fetch caches consumed-only totals and entries consistently',
      () async {
        when(mockConnectivity.isOnline).thenReturn(true);
        when(mockApiService.get<Map<String, dynamic>>(any)).thenAnswer(
          (_) async => {
            'id': 42,
            'userId': userId,
            'date': '2026-01-01T00:00:00.000Z',
            'waterIntake': 0,
            // Server-authoritative: consumed-only, matching
            // MealLog.RecalculateTotals(consumedOnly: true).
            'totalCalories': 300,
            'totalProtein': 25,
            'totalCarbohydrates': 35,
            'totalFat': 9,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'mealEntries': [
              {
                'id': 1,
                'mealLogId': 42,
                'mealType': 'Breakfast',
                'isConsumed': true,
                'totalCalories': 300,
                'totalProtein': 25,
                'totalCarbohydrates': 35,
                'totalFat': 9,
                'createdAt': '2026-01-01T00:00:00.000Z',
              },
              {
                'id': 2,
                'mealLogId': 42,
                'mealType': 'Lunch',
                'isConsumed': false,
                'totalCalories': 200,
                'totalProtein': 15,
                'totalCarbohydrates': 25,
                'totalFat': 6,
                'createdAt': '2026-01-01T00:00:00.000Z',
              },
            ],
          },
        );

        final mealLog = await repository.getTodaysMealLog();

        expect(mealLog.totalCalories, 300);
        expect(mealLog.consumedCalories, 300);
        expect(mealLog.plannedCalories, 500);

        final cachedLog =
            await isar.localMealLogs.filter().serverIdEqualTo(42).findFirst();
        expect(cachedLog, isNotNull);
        expect(cachedLog!.totalCalories, 300);

        final cachedEntries =
            await isar.localMealEntrys
                .filter()
                .mealLogLocalIdEqualTo(cachedLog.localId)
                .findAll();
        expect(cachedEntries, hasLength(2));
        expect(
          cachedEntries.where((e) => e.isConsumed).single.totalCalories,
          300,
        );
        expect(
          cachedEntries.where((e) => !e.isConsumed).single.totalCalories,
          200,
        );
      },
    );
  });

  group('server cache replacement does not clobber a pending repair', () {
    test(
      'a background refresh right after an online repair does not overwrite the corrected, still-pending row',
      () async {
        when(mockConnectivity.isOnline).thenReturn(true);

        // Seed exactly what the repair leaves behind: server-side total is
        // still the pre-repair, polluted value (500); locally the row has
        // just been corrected to 300 and re-queued (pending_update).
        final log = await insertMealLog(
          serverId: 42,
          totalCalories: 300,
          totalProtein: 25,
          totalCarbohydrates: 35,
          totalFat: 9,
        );
        await isar.writeTxn(() async {
          final stored = await isar.localMealLogs.get(log.localId);
          stored!.isSynced = false;
          stored.syncStatus = 'pending_update';
          await isar.localMealLogs.put(stored);
        });
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
          totalCalories: 300,
          totalProtein: 25,
          totalCarbohydrates: 35,
          totalFat: 9,
        );

        // The server hasn't received the corrective push yet - it still
        // returns the old, polluted total.
        when(
          mockApiService.get<List<dynamic>>(
            any,
            queryParameters: anyNamed('queryParameters'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer(
          (_) async => [
            {
              'id': 42,
              'userId': userId,
              'date': '2026-01-01T00:00:00.000Z',
              'waterIntake': 0,
              'totalCalories': 500,
              'totalProtein': 40,
              'totalCarbohydrates': 60,
              'totalFat': 15,
              'createdAt': '2026-01-01T00:00:00.000Z',
              'mealEntries': [],
            },
          ],
        );

        final results = await repository.getMealLogs(
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 1),
        );
        expect(results.first.totalCalories, 300);

        // Let the fire-and-forget background sync (triggered by the call
        // above) actually run and attempt its overwrite.
        await untilCalled(
          mockApiService.get<List<dynamic>>(
            any,
            queryParameters: anyNamed('queryParameters'),
            sessionContext: anyNamed('sessionContext'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Must still be the corrected, pending value - not reverted to the
        // server's stale 500, and not marked synced.
        final storedLog = await storedMealLog(log.localId);
        expect(storedLog.totalCalories, 300);
        expect(storedLog.isSynced, false);
        expect(storedLog.syncStatus, 'pending_update');
      },
    );
  });
}
