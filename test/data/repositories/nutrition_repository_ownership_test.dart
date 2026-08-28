import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_food_item.dart';
import 'package:go_hard_app/data/local/models/local_food_template.dart';
import 'package:go_hard_app/data/local/models/local_meal_entry.dart';
import 'package:go_hard_app/data/local/models/local_meal_log.dart';
import 'package:go_hard_app/data/local/models/local_nutrition_goal.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/food_item.dart';
import 'package:go_hard_app/data/models/nutrition_goal.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';

// Reuses the mocks already generated for the sibling consumed-totals test -
// same [ApiService]/[AuthService]/[ConnectivityService] interfaces, so no
// new `.mocks.dart` needs to be generated for this file.
import 'nutrition_repository_consumed_totals_test.mocks.dart';

/// Tests that NutritionRepository mutations enforce BOTH row ownership
/// (does the resolved Isar row actually belong to the calling user) and
/// operation/session ownership (is the calling session still current at
/// every checkpoint) - see the class doc on NutritionRepository.
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
    tempDir = await Directory.systemTemp.createTemp('nutrition_repo_owner_');
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
    repository.beforeWriteTxnForTesting = null;
    repository.insideWriteTxnForTesting = null;
    repository.afterWriteTxnForTesting = null;
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ============ Seed helpers ============

  Future<LocalMealLog> insertMealLog({
    int uid = userId,
    DateTime? date,
    int? serverId,
    int? explicitLocalId,
    double waterIntake = 0,
  }) async {
    final now = DateTime.now();
    final log = LocalMealLog(
      serverId: serverId,
      userId: uid,
      date: date ?? DateTime(2026, 1, 1),
      waterIntake: waterIntake,
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    if (explicitLocalId != null) {
      log.localId = explicitLocalId;
    }
    await isar.writeTxn(() => isar.localMealLogs.put(log));
    return log;
  }

  Future<LocalMealEntry> insertMealEntry({
    required int mealLogLocalId,
    int? serverId,
    int? explicitLocalId,
    bool isConsumed = false,
    double totalCalories = 0,
    double totalProtein = 0,
    double totalCarbohydrates = 0,
    double totalFat = 0,
    String mealType = 'Breakfast',
  }) async {
    final now = DateTime.now();
    final entry = LocalMealEntry(
      serverId: serverId,
      mealLogLocalId: mealLogLocalId,
      mealType: mealType,
      isConsumed: isConsumed,
      totalCalories: totalCalories,
      totalProtein: totalProtein,
      totalCarbohydrates: totalCarbohydrates,
      totalFat: totalFat,
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    if (explicitLocalId != null) {
      entry.localId = explicitLocalId;
    }
    await isar.writeTxn(() => isar.localMealEntrys.put(entry));
    return entry;
  }

  Future<LocalFoodItem> insertFoodItem({
    required int mealEntryLocalId,
    int? serverId,
    int? explicitLocalId,
    double quantity = 1,
    double calories = 100,
    double protein = 5,
    double carbohydrates = 10,
    double fat = 2,
  }) async {
    final now = DateTime.now();
    final food = LocalFoodItem(
      serverId: serverId,
      mealEntryLocalId: mealEntryLocalId,
      name: 'Test food',
      quantity: quantity,
      calories: calories,
      protein: protein,
      carbohydrates: carbohydrates,
      fat: fat,
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    if (explicitLocalId != null) {
      food.localId = explicitLocalId;
    }
    await isar.writeTxn(() => isar.localFoodItems.put(food));
    return food;
  }

  Future<LocalNutritionGoal> insertNutritionGoal({
    int uid = userId,
    int? serverId,
    int? explicitLocalId,
    bool isActive = true,
    double dailyCalories = 2000,
  }) async {
    final now = DateTime.now();
    final goal = LocalNutritionGoal(
      serverId: serverId,
      userId: uid,
      dailyCalories: dailyCalories,
      isActive: isActive,
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    if (explicitLocalId != null) {
      goal.localId = explicitLocalId;
    }
    await isar.writeTxn(() => isar.localNutritionGoals.put(goal));
    return goal;
  }

  NutritionGoal goalPayload({double dailyCalories = 2500}) => NutritionGoal(
    id: 0,
    userId: userId,
    dailyCalories: dailyCalories,
    createdAt: DateTime.now(),
  );

  Matcher throwsNotAuthenticated() => throwsA(
    isA<Exception>().having(
      (e) => e.toString(),
      'message',
      contains('User not authenticated'),
    ),
  );

  Matcher throwsNotFound(String message) => throwsA(
    isA<Exception>().having((e) => e.toString(), 'message', contains(message)),
  );

  // ============ 1. Logged out ============

  group('logged out', () {
    test(
      'every protected method rejects without touching Isar or the API',
      () async {
        sessionEpoch.invalidate(); // no active session

        final log = await insertMealLog(serverId: 10);
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          serverId: 20,
        );
        await insertFoodItem(mealEntryLocalId: entry.localId, serverId: 30);
        final goal = await insertNutritionGoal(serverId: 40);

        await expectLater(
          () => repository.updateWaterIntake(10, 500),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.quickAddFood(mealEntryId: 20, foodTemplateId: 1),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.deleteFoodItem(30),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.updateNutritionGoal(40, goalPayload()),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.markMealAsConsumed(20),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.clearAllFood(10),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.addFoodItem(
            FoodItem(
              id: 0,
              mealEntryId: 20,
              name: 'X',
              calories: 1,
              protein: 1,
              carbohydrates: 1,
              fat: 1,
              createdAt: DateTime.now(),
            ),
          ),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.updateFoodQuantity(30, 2),
          throwsNotAuthenticated(),
        );

        // Nothing was ever read from AuthService or sent to the API - the
        // unauthenticated check happens before any Isar/API access.
        verifyNever(mockAuthService.getUserId());
        verifyZeroInteractions(mockApiService);

        // Nothing was mutated.
        final storedLog = await isar.localMealLogs.get(log.localId);
        expect(storedLog!.waterIntake, 0);
        final storedGoal = await isar.localNutritionGoals.get(goal.localId);
        expect(storedGoal!.dailyCalories, 2000);
      },
    );
  });

  // ============ 2. NutritionGoal ownership ============

  group('NutritionGoal ownership', () {
    test('User A cannot update User B\'s goal via server-ID', () async {
      final goalB = await insertNutritionGoal(uid: otherUserId, serverId: 99);

      await expectLater(
        () => repository.updateNutritionGoal(99, goalPayload()),
        throwsNotFound('Nutrition goal not found'),
      );

      final stored = await isar.localNutritionGoals.get(goalB.localId);
      expect(stored!.dailyCalories, 2000);
      verifyZeroInteractions(mockApiService);
    });

    test('User A cannot update User B\'s goal via local-ID fallback', () async {
      final goalB = await insertNutritionGoal(uid: otherUserId);

      await expectLater(
        () => repository.updateNutritionGoal(goalB.localId, goalPayload()),
        throwsNotFound('Nutrition goal not found'),
      );

      final stored = await isar.localNutritionGoals.get(goalB.localId);
      expect(stored!.dailyCalories, 2000);
    });
  });

  // ============ 3. MealLog ownership ============

  group('MealLog ownership', () {
    test('User A cannot update water on User B\'s log via server-ID', () async {
      final logB = await insertMealLog(uid: otherUserId, serverId: 77);

      await expectLater(
        () => repository.updateWaterIntake(77, 999),
        throwsNotFound('Meal log not found'),
      );

      final stored = await isar.localMealLogs.get(logB.localId);
      expect(stored!.waterIntake, 0);
    });

    test(
      'User A cannot update water on User B\'s log via local-ID fallback',
      () async {
        final logB = await insertMealLog(uid: otherUserId);

        await expectLater(
          () => repository.updateWaterIntake(logB.localId, 999),
          throwsNotFound('Meal log not found'),
        );

        final stored = await isar.localMealLogs.get(logB.localId);
        expect(stored!.waterIntake, 0);
      },
    );

    test('User A cannot clearAllFood on User B\'s log via server-ID', () async {
      final logB = await insertMealLog(uid: otherUserId, serverId: 78);
      final entryB = await insertMealEntry(
        mealLogLocalId: logB.localId,
        totalCalories: 400,
      );
      await insertFoodItem(mealEntryLocalId: entryB.localId, calories: 400);

      await expectLater(
        () => repository.clearAllFood(78),
        throwsNotFound('Meal log not found'),
      );

      final storedEntry = await isar.localMealEntrys.get(entryB.localId);
      expect(storedEntry!.totalCalories, 400);
      final remainingFood =
          await isar.localFoodItems
              .filter()
              .mealEntryLocalIdEqualTo(entryB.localId)
              .count();
      expect(remainingFood, 1);
    });

    test(
      'User A cannot clearAllFood on User B\'s log via local-ID fallback',
      () async {
        final logB = await insertMealLog(uid: otherUserId);

        await expectLater(
          () => repository.clearAllFood(logB.localId),
          throwsNotFound('Meal log not found'),
        );
      },
    );
  });

  // ============ 4. MealEntry ownership ============

  group('MealEntry ownership', () {
    test(
      'User A cannot mark User B\'s meal entry as consumed (server-ID)',
      () async {
        final logB = await insertMealLog(uid: otherUserId, serverId: 80);
        final entryB = await insertMealEntry(
          mealLogLocalId: logB.localId,
          serverId: 81,
          isConsumed: false,
        );

        await expectLater(
          () => repository.markMealAsConsumed(81),
          throwsNotFound('Meal entry not found'),
        );

        final stored = await isar.localMealEntrys.get(entryB.localId);
        expect(stored!.isConsumed, false);
      },
    );

    test(
      'User A cannot mark User B\'s meal entry as consumed (local-ID fallback)',
      () async {
        final logB = await insertMealLog(uid: otherUserId);
        final entryB = await insertMealEntry(
          mealLogLocalId: logB.localId,
          isConsumed: false,
        );

        await expectLater(
          () => repository.markMealAsConsumed(entryB.localId),
          throwsNotFound('Meal entry not found'),
        );

        final stored = await isar.localMealEntrys.get(entryB.localId);
        expect(stored!.isConsumed, false);
      },
    );

    test('User A cannot addFoodItem into User B\'s meal entry', () async {
      final logB = await insertMealLog(uid: otherUserId);
      final entryB = await insertMealEntry(mealLogLocalId: logB.localId);

      await expectLater(
        () => repository.addFoodItem(
          FoodItem(
            id: 0,
            mealEntryId: entryB.localId,
            name: 'Intruder food',
            calories: 100,
            protein: 1,
            carbohydrates: 1,
            fat: 1,
            createdAt: DateTime.now(),
          ),
        ),
        throwsNotFound('Meal entry not found'),
      );

      final remaining =
          await isar.localFoodItems
              .filter()
              .mealEntryLocalIdEqualTo(entryB.localId)
              .count();
      expect(remaining, 0);
    });

    test('User A cannot quickAddFood into User B\'s meal entry', () async {
      final logB = await insertMealLog(uid: otherUserId);
      final entryB = await insertMealEntry(mealLogLocalId: logB.localId);
      final template = LocalFoodTemplate(
        serverId: 500,
        name: 'Banana',
        calories: 105,
        protein: 1.3,
        carbohydrates: 27,
        fat: 0.4,
        createdAt: DateTime.now(),
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
      );
      await isar.writeTxn(() => isar.localFoodTemplates.put(template));

      await expectLater(
        () => repository.quickAddFood(
          mealEntryId: entryB.localId,
          foodTemplateId: 500,
        ),
        throwsNotFound('Meal entry not found'),
      );

      final remaining =
          await isar.localFoodItems
              .filter()
              .mealEntryLocalIdEqualTo(entryB.localId)
              .count();
      expect(remaining, 0);
    });
  });

  // ============ 5. FoodItem ownership ============

  group('FoodItem ownership', () {
    test('User A cannot delete User B\'s food item (server-ID)', () async {
      final logB = await insertMealLog(uid: otherUserId);
      final entryB = await insertMealEntry(mealLogLocalId: logB.localId);
      final foodB = await insertFoodItem(
        mealEntryLocalId: entryB.localId,
        serverId: 90,
        calories: 250,
      );

      await expectLater(
        () => repository.deleteFoodItem(90),
        throwsNotFound('Food item not found'),
      );

      final stored = await isar.localFoodItems.get(foodB.localId);
      expect(stored, isNotNull);
    });

    test(
      'User A cannot delete User B\'s food item (local-ID fallback)',
      () async {
        final logB = await insertMealLog(uid: otherUserId);
        final entryB = await insertMealEntry(mealLogLocalId: logB.localId);
        final foodB = await insertFoodItem(mealEntryLocalId: entryB.localId);

        await expectLater(
          () => repository.deleteFoodItem(foodB.localId),
          throwsNotFound('Food item not found'),
        );

        final stored = await isar.localFoodItems.get(foodB.localId);
        expect(stored, isNotNull);
      },
    );

    test(
      'User A cannot update quantity on User B\'s food item (server-ID)',
      () async {
        final logB = await insertMealLog(uid: otherUserId);
        final entryB = await insertMealEntry(mealLogLocalId: logB.localId);
        final foodB = await insertFoodItem(
          mealEntryLocalId: entryB.localId,
          serverId: 91,
          quantity: 1,
        );

        await expectLater(
          () => repository.updateFoodQuantity(91, 5),
          throwsNotFound('Food item not found'),
        );

        final stored = await isar.localFoodItems.get(foodB.localId);
        expect(stored!.quantity, 1);
      },
    );

    test(
      'User A cannot update quantity on User B\'s food item (local-ID fallback)',
      () async {
        final logB = await insertMealLog(uid: otherUserId);
        final entryB = await insertMealEntry(mealLogLocalId: logB.localId);
        final foodB = await insertFoodItem(
          mealEntryLocalId: entryB.localId,
          quantity: 1,
        );

        await expectLater(
          () => repository.updateFoodQuantity(foodB.localId, 5),
          throwsNotFound('Food item not found'),
        );

        final stored = await isar.localFoodItems.get(foodB.localId);
        expect(stored!.quantity, 1);
      },
    );
  });

  // ============ 6/7. Orphaned rows ============

  group('orphaned rows', () {
    test(
      'a meal entry whose parent log is missing rejects markMealAsConsumed',
      () async {
        // Entry references a mealLogLocalId that doesn't exist - simulates a
        // parent deleted out from under a child row.
        final orphan = await insertMealEntry(mealLogLocalId: 999999);

        await expectLater(
          () => repository.markMealAsConsumed(orphan.localId),
          throwsNotFound('Meal entry not found'),
        );

        final stored = await isar.localMealEntrys.get(orphan.localId);
        expect(stored!.isConsumed, false);
      },
    );

    test(
      'a food item whose parent meal entry is missing rejects deleteFoodItem',
      () async {
        final orphan = await insertFoodItem(mealEntryLocalId: 999999);

        await expectLater(
          () => repository.deleteFoodItem(orphan.localId),
          throwsNotFound('Food item not found'),
        );

        final stored = await isar.localFoodItems.get(orphan.localId);
        expect(stored, isNotNull);
      },
    );

    test(
      'a food item whose grandparent meal log is missing rejects updateFoodQuantity',
      () async {
        // Entry exists, but ITS parent log does not.
        final danglingEntry = await insertMealEntry(mealLogLocalId: 999999);
        final food = await insertFoodItem(
          mealEntryLocalId: danglingEntry.localId,
          quantity: 1,
        );

        await expectLater(
          () => repository.updateFoodQuantity(food.localId, 3),
          throwsNotFound('Food item not found'),
        );

        final stored = await isar.localFoodItems.get(food.localId);
        expect(stored!.quantity, 1);
      },
    );
  });

  // ============ 8/9. Same-user records still work ============

  group('same-user records still work', () {
    test(
      'a local-only record with null serverId can be updated (offline)',
      () async {
        final log = await insertMealLog(); // no serverId

        await repository.updateWaterIntake(log.localId, 750);

        final stored = await isar.localMealLogs.get(log.localId);
        expect(stored!.waterIntake, 750);
        expect(stored.syncStatus, 'pending_create');
      },
    );

    test('a server-backed record can be updated via its server ID', () async {
      final goal = await insertNutritionGoal(serverId: 55, dailyCalories: 2000);

      await repository.updateNutritionGoal(
        55,
        goalPayload(dailyCalories: 2600),
      );

      final stored = await isar.localNutritionGoals.get(goal.localId);
      expect(stored!.dailyCalories, 2600);
      expect(stored.syncStatus, 'pending_update');
    });

    test(
      'a server-backed food item can have its quantity updated via server ID',
      () async {
        final log = await insertMealLog();
        final entry = await insertMealEntry(mealLogLocalId: log.localId);
        await insertFoodItem(
          mealEntryLocalId: entry.localId,
          serverId: 61,
          quantity: 2,
          calories: 200,
          protein: 10,
          carbohydrates: 20,
          fat: 4,
        );

        await repository.updateFoodQuantity(61, 4);

        final stored =
            await isar.localFoodItems.filter().serverIdEqualTo(61).findFirst();
        expect(stored!.quantity, 4);
        expect(stored.calories, 400);
      },
    );
  });

  // ============ 10. Numeric collision ============

  group(
    'numeric collision between a foreign server ID and an owned local ID',
    () {
      test(
        'the owned local record is selected, not the foreign server-ID match',
        () async {
          // A foreign row whose serverId happens to equal 42.
          await insertMealLog(uid: otherUserId, serverId: 42);
          // An owned, never-synced row whose LOCAL Isar id also happens to be 42.
          final ownedLocal = await insertMealLog(explicitLocalId: 42);

          await repository.updateWaterIntake(42, 1234);

          final stored = await isar.localMealLogs.get(ownedLocal.localId);
          expect(stored!.userId, userId);
          expect(stored.waterIntake, 1234);

          // The foreign row (matched only by the ambiguous server ID) must be
          // untouched.
          final foreign =
              await isar.localMealLogs
                  .filter()
                  .serverIdEqualTo(42)
                  .userIdEqualTo(otherUserId)
                  .findFirst();
          expect(foreign!.waterIntake, 0);
        },
      );

      test(
        'same collision for FoodItem (grandparent-chain ownership)',
        () async {
          final foreignLog = await insertMealLog(uid: otherUserId);
          final foreignEntry = await insertMealEntry(
            mealLogLocalId: foreignLog.localId,
          );
          await insertFoodItem(
            mealEntryLocalId: foreignEntry.localId,
            serverId: 77,
          );

          final ownedLog = await insertMealLog();
          final ownedEntry = await insertMealEntry(
            mealLogLocalId: ownedLog.localId,
          );
          final ownedFood = await insertFoodItem(
            mealEntryLocalId: ownedEntry.localId,
            explicitLocalId: 77,
            quantity: 1,
          );

          await repository.updateFoodQuantity(77, 9);

          final stored = await isar.localFoodItems.get(ownedFood.localId);
          expect(stored!.quantity, 9);
        },
      );
    },
  );

  // ============ 11. Rejected targets leave no trace ============

  group('rejected foreign/orphaned targets leave no trace', () {
    test(
      'no API call and no background sync is scheduled for a rejected target',
      () async {
        when(mockConnectivity.isOnline).thenReturn(true);
        final goalB = await insertNutritionGoal(uid: otherUserId, serverId: 12);

        await expectLater(
          () => repository.updateNutritionGoal(12, goalPayload()),
          throwsNotFound('Nutrition goal not found'),
        );

        // Give any errantly-scheduled fire-and-forget background task a
        // chance to run before asserting it never happened.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        verifyZeroInteractions(mockApiService);

        final stored = await isar.localNutritionGoals.get(goalB.localId);
        expect(stored!.dailyCalories, 2000);
        expect(stored.syncStatus, 'synced');
      },
    );
  });

  // ============ 12. Not-found messages unchanged ============

  group('not-found messages are unchanged', () {
    test('missing meal log still throws "Meal log not found"', () async {
      await expectLater(
        () => repository.updateWaterIntake(123456, 1),
        throwsNotFound('Meal log not found'),
      );
    });

    test('missing food item still throws "Food item not found"', () async {
      await expectLater(
        () => repository.deleteFoodItem(123456),
        throwsNotFound('Food item not found'),
      );
    });

    test('missing meal entry still throws "Meal entry not found"', () async {
      await expectLater(
        () => repository.markMealAsConsumed(123456),
        throwsNotFound('Meal entry not found'),
      );
    });

    test(
      'missing nutrition goal still throws "Nutrition goal not found"',
      () async {
        await expectLater(
          () => repository.updateNutritionGoal(123456, goalPayload()),
          throwsNotFound('Nutrition goal not found'),
        );
      },
    );
  });

  // ============ 13. Session invalidated before writeTxn is entered ============

  group('session invalidated between lookup and writeTxn', () {
    test('the write transaction is never entered', () async {
      final log = await insertMealLog();
      var enteredTxnCallback = false;

      repository.beforeWriteTxnForTesting = () async {
        sessionEpoch.invalidate();
      };
      repository.insideWriteTxnForTesting = () async {
        enteredTxnCallback = true;
      };

      await expectLater(
        () => repository.updateWaterIntake(log.localId, 999),
        throwsNotAuthenticated(),
      );

      expect(
        enteredTxnCallback,
        isFalse,
        reason:
            'the pre-writeTxn session check should reject before ever '
            'calling db.writeTxn, not rely on the in-transaction check',
      );

      final stored = await isar.localMealLogs.get(log.localId);
      expect(stored!.waterIntake, 0);
    });
  });

  // ============ 14. Session invalidated + clearAll while writeTxn waits ============

  group('session invalidated and Isar cleared while writeTxn is entered', () {
    test('no row is resurrected after clearAll', () async {
      final log = await insertMealLog();

      repository.insideWriteTxnForTesting = () async {
        // Simulates: user logs out (epoch invalidated) and
        // LocalDatabaseService.clearAll() empties Isar, both landing
        // exactly as this delayed write transaction begins executing.
        sessionEpoch.invalidate();
        await isar.clear();
      };

      // This test isolates the in-transaction checkpoint specifically -
      // whether the call throws afterward is covered separately (that's
      // the post-transaction checkpoint's job), so any exception here is
      // deliberately swallowed rather than asserted on.
      try {
        await repository.updateWaterIntake(log.localId, 999);
      } catch (_) {
        // Covered by the "session invalidated after the write transaction
        // commits" group.
      }

      final stored = await isar.localMealLogs.get(log.localId);
      expect(
        stored,
        isNull,
        reason:
            'the in-transaction session check must prevent put() from '
            'resurrecting the row clearAll() just removed',
      );
    });

    test(
      'no food item is resurrected after clearAll during addFoodItem',
      () async {
        final entry = await insertMealEntry(
          mealLogLocalId: (await insertMealLog()).localId,
        );

        repository.insideWriteTxnForTesting = () async {
          sessionEpoch.invalidate();
          await isar.clear();
        };

        try {
          await repository.addFoodItem(
            FoodItem(
              id: 0,
              mealEntryId: entry.localId,
              name: 'Late food',
              calories: 100,
              protein: 1,
              carbohydrates: 1,
              fat: 1,
              createdAt: DateTime.now(),
            ),
          );
        } catch (_) {
          // Covered by the "session invalidated after the write transaction
          // commits" group.
        }

        final remaining = await isar.localFoodItems.where().count();
        expect(remaining, 0);
      },
    );
  });

  // ============ 15. Session invalidated after writeTxn, before background scheduling ============

  group('session invalidated after the write transaction commits', () {
    test(
      'no background API task is scheduled even though the write succeeded',
      () async {
        when(mockConnectivity.isOnline).thenReturn(true);
        final log = await insertMealLog(serverId: 15);

        repository.afterWriteTxnForTesting = () async {
          sessionEpoch.invalidate();
        };

        await expectLater(
          () => repository.updateWaterIntake(15, 555),
          throwsNotAuthenticated(),
        );

        // The write itself completed before staleness was introduced.
        final stored = await isar.localMealLogs.get(log.localId);
        expect(stored!.waterIntake, 555);

        // But nothing should have been scheduled to sync it, since the
        // session was already stale by the time scheduling was considered.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        verifyZeroInteractions(mockApiService);
      },
    );
  });

  // ============ 16. Legitimate payloads/totals unchanged ============

  group('legitimate same-user behavior is unchanged', () {
    test(
      'updateNutritionGoal still PUTs the correct payload when online',
      () async {
        when(mockConnectivity.isOnline).thenReturn(true);
        when(
          mockApiService.put<void>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async {});
        final goal = await insertNutritionGoal(
          serverId: 71,
          dailyCalories: 2000,
        );

        await repository.updateNutritionGoal(
          71,
          goalPayload(dailyCalories: 3000),
        );

        await untilCalled(
          mockApiService.put<void>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final captured =
            verify(
              mockApiService.put<void>(
                captureAny,
                data: captureAnyNamed('data'),
                sessionContext: anyNamed('sessionContext'),
              ),
            ).captured;
        expect(captured[0], 'nutritiongoals/71');
        final payload = captured[1] as Map<String, dynamic>;
        expect(payload['dailyCalories'], 3000);

        final stored = await isar.localNutritionGoals.get(goal.localId);
        expect(stored!.dailyCalories, 3000);
      },
    );

    test(
      'updateWaterIntake still PUTs the raw water value when online',
      () async {
        when(mockConnectivity.isOnline).thenReturn(true);
        when(
          mockApiService.put<void>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async {});
        await insertMealLog(serverId: 72);

        await repository.updateWaterIntake(72, 1500);

        await untilCalled(
          mockApiService.put<void>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final captured =
            verify(
              mockApiService.put<void>(
                captureAny,
                data: captureAnyNamed('data'),
                sessionContext: anyNamed('sessionContext'),
              ),
            ).captured;
        expect(captured[0], 'meallogs/72/water');
        expect(captured[1], 1500);
      },
    );
  });
}
