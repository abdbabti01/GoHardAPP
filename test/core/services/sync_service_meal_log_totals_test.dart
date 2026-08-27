import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
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
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/models/achievement.dart';
import 'package:go_hard_app/data/models/shared_workout.dart';
import 'package:go_hard_app/data/models/workout_template.dart';

import 'sync_service_meal_log_totals_test.mocks.dart';

@GenerateMocks([ApiService, AuthService])
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late SyncService syncService;

  const userId = 1;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sync_service_meal_log_totals_',
    );
    // The full schema set the app registers at startup (see
    // LocalDatabaseService.initialize()) is required here: SyncService.sync()
    // walks every collection in one sequence inside a single try/catch, so
    // an unregistered schema earlier in that sequence (sessions, goals, ...)
    // would throw and prevent the meal-log sync steps under test from ever
    // running, even though this test doesn't seed any data in those tables.
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

    SyncService.reset();
    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userId);

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    syncService = SyncService(
      apiService: mockApiService,
      authService: mockAuthService,
      localDb: localDb,
      // Real singleton, defaults to online - required for sync() to
      // proceed past its connectivity gate at all.
      connectivity: ConnectivityService.instance,
    );
  });

  tearDown(() async {
    SyncService.reset();
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LocalMealLog> insertMealLog({
    int? serverId,
    required String syncStatus,
    double totalCalories = 0,
    double totalProtein = 0,
    double totalCarbohydrates = 0,
    double totalFat = 0,
  }) async {
    final now = DateTime.now();
    final log = LocalMealLog(
      serverId: serverId,
      userId: userId,
      date: DateTime(2026, 1, 1),
      totalCalories: totalCalories,
      totalProtein: totalProtein,
      totalCarbohydrates: totalCarbohydrates,
      totalFat: totalFat,
      createdAt: now,
      isSynced: false,
      syncStatus: syncStatus,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localMealLogs.put(log));
    return log;
  }

  Future<LocalMealEntry> insertMealEntry({
    required int mealLogLocalId,
    required bool isConsumed,
    required double totalCalories,
    required double totalProtein,
    required double totalCarbohydrates,
    required double totalFat,
  }) async {
    final now = DateTime.now();
    final entry = LocalMealEntry(
      mealLogLocalId: mealLogLocalId,
      mealType: 'Breakfast',
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

  group('sync-create payload', () {
    test(
      'an offline-created log containing only unconsumed food sends zero consumed calories/macros on first sync',
      () async {
        // Simulates the exact leak scenario: created entirely offline, then
        // food added to an unconsumed entry before ever reaching the
        // server. The stored aggregate is deliberately polluted (as the old
        // bug would have left it) to prove the payload does not trust it.
        final log = await insertMealLog(
          syncStatus: 'pending_create',
          totalCalories: 400,
          totalProtein: 30,
          totalCarbohydrates: 50,
          totalFat: 12,
        );
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
          totalCalories: 400,
          totalProtein: 30,
          totalCarbohydrates: 50,
          totalFat: 12,
        );

        // The meal-log POST is what's under test; meal-entry POSTs happen
        // afterward in the same sync() call (_syncMealEntries) and are
        // stubbed permissively so they don't fail with MissingStubError -
        // they are not what this test is verifying.
        when(
          mockApiService.post<Map<String, dynamic>>(
            ApiConfig.mealLogs,
            data: anyNamed('data'),
          ),
        ).thenAnswer((_) async => {'id': 999});
        when(
          mockApiService.post<Map<String, dynamic>>(
            ApiConfig.mealEntries,
            data: anyNamed('data'),
          ),
        ).thenAnswer((_) async => {'id': 1});

        await syncService.sync();

        final captured =
            verify(
                  mockApiService.post<Map<String, dynamic>>(
                    ApiConfig.mealLogs,
                    data: captureAnyNamed('data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;

        expect(captured['totalCalories'], 0);
        expect(captured['totalProtein'], 0);
        expect(captured['totalCarbohydrates'], 0);
        expect(captured['totalFat'], 0);
      },
    );

    test(
      'an offline-created log with a consumed entry sends only that entry\'s totals',
      () async {
        final log = await insertMealLog(syncStatus: 'pending_create');
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
          totalCalories: 250,
          totalProtein: 20,
          totalCarbohydrates: 30,
          totalFat: 8,
        );
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
          totalCalories: 500,
          totalProtein: 40,
          totalCarbohydrates: 60,
          totalFat: 15,
        );

        when(
          mockApiService.post<Map<String, dynamic>>(
            ApiConfig.mealLogs,
            data: anyNamed('data'),
          ),
        ).thenAnswer((_) async => {'id': 999});
        when(
          mockApiService.post<Map<String, dynamic>>(
            ApiConfig.mealEntries,
            data: anyNamed('data'),
          ),
        ).thenAnswer((_) async => {'id': 1});

        await syncService.sync();

        final captured =
            verify(
                  mockApiService.post<Map<String, dynamic>>(
                    ApiConfig.mealLogs,
                    data: captureAnyNamed('data'),
                  ),
                ).captured.single
                as Map<String, dynamic>;

        expect(captured['totalCalories'], 250);
        expect(captured['totalProtein'], 20);
        expect(captured['totalCarbohydrates'], 30);
        expect(captured['totalFat'], 8);
      },
    );
  });

  group('sync-update payload', () {
    test(
      'derives totals from entries rather than trusting a deliberately stale stored aggregate',
      () async {
        final log = await insertMealLog(
          serverId: 42,
          syncStatus: 'pending_update',
          // Deliberately wrong/stale: neither the consumed-only value (100)
          // nor the planned value (150) - proves the payload is recomputed,
          // not merely "happens to still be right".
          totalCalories: 999,
          totalProtein: 999,
          totalCarbohydrates: 999,
          totalFat: 999,
        );
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: true,
          totalCalories: 100,
          totalProtein: 8,
          totalCarbohydrates: 12,
          totalFat: 3,
        );
        await insertMealEntry(
          mealLogLocalId: log.localId,
          isConsumed: false,
          totalCalories: 50,
          totalProtein: 4,
          totalCarbohydrates: 6,
          totalFat: 1,
        );

        when(
          mockApiService.put<void>(any, data: anyNamed('data')),
        ).thenAnswer((_) => Future<void>.value());
        // The two entries seeded above default to pending_create and are
        // synced afterward in the same sync() call; stub that permissively
        // so it doesn't fail with MissingStubError - it isn't what this
        // test is verifying.
        when(
          mockApiService.post<Map<String, dynamic>>(
            ApiConfig.mealEntries,
            data: anyNamed('data'),
          ),
        ).thenAnswer((_) async => {'id': 1});

        await syncService.sync();

        final captured =
            verify(
                  mockApiService.put<void>(any, data: captureAnyNamed('data')),
                ).captured.single
                as Map<String, dynamic>;

        expect(captured['totalCalories'], 100);
        expect(captured['totalProtein'], 8);
        expect(captured['totalCarbohydrates'], 12);
        expect(captured['totalFat'], 3);
      },
    );
  });
}
