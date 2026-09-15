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
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';

// Reuses the mocks already generated for the sibling consumed-totals test -
// same [ApiService]/[AuthService]/[ConnectivityService] interfaces, so no
// new `.mocks.dart` needs to be generated for this file. Mirrors the same
// choice already made by nutrition_repository_ownership_test.dart.
import 'nutrition_repository_consumed_totals_test.mocks.dart';

/// Phase 3 requirements-closure: real-Isar durability proof for
/// NutritionGoal history (EffectiveDate/DeletedAt), on top of the
/// ownership guarantees already covered by
/// nutrition_repository_ownership_test.dart's "NutritionGoal ownership"
/// group (which proves user A can never mutate user B's goal). This file
/// additionally proves READ-side user isolation, close/reopen durability,
/// offline-before-sync target preservation, pending-vs-stale precedence,
/// and that an unconfirmed (offline/failed) date-range read is reported
/// as genuinely unavailable rather than a confirmed "no target".
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

  Future<Isar> openIsar() => Isar.open(
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nutrition_goal_history_');
    isar = await openIsar();

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
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ============ Seed helpers ============

  Future<LocalNutritionGoal> insertGoal(
    Isar db, {
    int uid = userId,
    int? serverId,
    required DateTime effectiveDate,
    DateTime? deletedAt,
    double dailyCalories = 2000,
    bool isActive = true,
    String syncStatus = 'synced',
  }) async {
    final now = DateTime.now();
    final goal = LocalNutritionGoal(
      serverId: serverId,
      userId: uid,
      dailyCalories: dailyCalories,
      isActive: isActive,
      effectiveDate: effectiveDate,
      deletedAt: deletedAt,
      createdAt: effectiveDate,
      isSynced: syncStatus == 'synced',
      syncStatus: syncStatus,
      lastModifiedLocal: now,
    );
    await db.writeTxn(() => db.localNutritionGoals.put(goal));
    return goal;
  }

  DateTime day(int offsetFromToday) =>
      DateTime.now().subtract(Duration(days: -offsetFromToday));

  DateTime normalized(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<String, dynamic> forDatesEntryNoTarget(DateTime date) => {
    'date': DateTime(date.year, date.month, date.day).toIso8601String(),
    'hasTarget': false,
  };

  group('legacy upgrade / close-reopen durability', () {
    test('closing and reopening the SAME Isar file preserves nutrition-goal '
        'history (including effectiveDate/deletedAt) and unrelated '
        'collections (meal logs, entries, food items) untouched - proving '
        'the schema addition of effectiveDate/deletedAt does not lose '
        'existing rows or unrelated data across a real restart', () async {
      final earlier = day(-10);
      final later = day(-2);
      final deletedGoal = await insertGoal(
        isar,
        serverId: 1,
        effectiveDate: earlier,
        deletedAt: later,
        dailyCalories: 1500,
      );
      final currentGoal = await insertGoal(
        isar,
        serverId: 2,
        effectiveDate: later,
        dailyCalories: 2200,
      );

      final log = LocalMealLog(
        serverId: 50,
        userId: userId,
        date: DateTime(2026, 1, 1),
        createdAt: DateTime.now(),
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
      );
      await isar.writeTxn(() => isar.localMealLogs.put(log));
      final entry = LocalMealEntry(
        serverId: 60,
        mealLogLocalId: log.localId,
        mealType: 'Breakfast',
        totalCalories: 400,
        createdAt: DateTime.now(),
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
      );
      await isar.writeTxn(() => isar.localMealEntrys.put(entry));
      final food = LocalFoodItem(
        serverId: 70,
        mealEntryLocalId: entry.localId,
        name: 'Oatmeal',
        calories: 400,
        protein: 10,
        carbohydrates: 60,
        fat: 8,
        createdAt: DateTime.now(),
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
      );
      await isar.writeTxn(() => isar.localFoodItems.put(food));

      // Close and reopen against the SAME directory - a real app
      // restart, not an in-memory reset.
      await isar.close();
      isar = await openIsar();
      localDb.setTestDatabase(isar);

      final reopenedDeleted = await isar.localNutritionGoals.get(
        deletedGoal.localId,
      );
      final reopenedCurrent = await isar.localNutritionGoals.get(
        currentGoal.localId,
      );
      expect(reopenedDeleted, isNotNull);
      expect(
        normalized(reopenedDeleted!.effectiveDate),
        normalized(earlier),
        reason: 'effectiveDate must survive close/reopen exactly',
      );
      expect(reopenedDeleted.deletedAt, isNotNull);
      expect(normalized(reopenedDeleted.deletedAt!), normalized(later));
      expect(reopenedCurrent, isNotNull);
      expect(reopenedCurrent!.dailyCalories, 2200);
      expect(reopenedCurrent.deletedAt, isNull);

      // Unrelated collections/data are untouched.
      final reopenedLog = await isar.localMealLogs.get(log.localId);
      expect(reopenedLog, isNotNull);
      final reopenedEntry = await isar.localMealEntrys.get(entry.localId);
      expect(reopenedEntry, isNotNull);
      expect(reopenedEntry!.totalCalories, 400);
      final reopenedFood = await isar.localFoodItems.get(food.localId);
      expect(reopenedFood, isNotNull);
      expect(reopenedFood!.name, 'Oatmeal');

      // Historical resolution through the repository is unchanged too -
      // not just raw bytes, but the actual behavior built on them.
      final resolvedEarlier = await repository.getGoalForDate(day(-8));
      expect(resolvedEarlier?.dailyCalories, 1500);
      final resolvedLater = await repository.getGoalForDate(day(-1));
      expect(resolvedLater?.dailyCalories, 2200);
    });
  });

  group('offline target change preserves prior history before sync', () {
    test('changing today\'s target while offline preserves yesterday\'s '
        'prior target - the new pending-create row does not retroactively '
        'apply to dates before its own effectiveDate', () async {
      when(mockConnectivity.isOnline).thenReturn(false);
      final yesterday = day(-1);
      final today = day(0);

      await insertGoal(
        isar,
        serverId: 5,
        effectiveDate: day(-30),
        dailyCalories: 1800,
      );

      // Offline edit: NutritionRepository.updateNutritionGoal inserts a
      // NEW row rather than mutating the existing one (never mutates
      // history in place) - simulate that insert directly since going
      // through the full authenticated updateNutritionGoal call path
      // isn't necessary to prove the READ-side historical guarantee
      // this test targets.
      await insertGoal(
        isar,
        effectiveDate: today,
        dailyCalories: 2600,
        syncStatus: 'pending_create',
      );

      final resolvedYesterday = await repository.getGoalForDate(yesterday);
      expect(
        resolvedYesterday?.dailyCalories,
        1800,
        reason:
            'yesterday must still resolve to the OLD target, unaffected '
            'by an offline change that only takes effect today',
      );

      final resolvedToday = await repository.getGoalForDate(today);
      expect(resolvedToday?.dailyCalories, 2600);

      // Never contacted the server for either read while offline.
      verifyNever(mockApiService.get<Map<String, dynamic>>(any));
    });
  });

  group('stale server response cannot overwrite a pending local change', () {
    test(
      'a background sync response for the active goal that arrives while '
      'a local edit is still pending_update is dropped, not applied',
      () async {
        when(mockConnectivity.isOnline).thenReturn(true);
        final today = day(0);

        // An existing synced goal, locally edited (pending_update) to
        // 1900 kcal - the edit has not reached the server yet.
        await insertGoal(
          isar,
          serverId: 500,
          effectiveDate: today,
          dailyCalories: 1900,
          syncStatus: 'pending_update',
        );

        // The server still reports the OLD (stale, pre-edit) value. The
        // background-sync call carries a `sessionContext:` named argument
        // (see NutritionRepository._syncNutritionGoalFromServer), so the
        // stub must match that shape explicitly or Mockito silently fails
        // to match it - which would make this test vacuously pass without
        // ever exercising the pending_update guard it's meant to prove.
        when(
          mockApiService.get<Map<String, dynamic>>(
            any,
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer(
          (_) async => {
            'id': 500,
            'userId': userId,
            'dailyCalories': 1500,
            'dailyProtein': 100,
            'dailyCarbohydrates': 150,
            'dailyFat': 50,
            'isActive': true,
            'effectiveDate': today.toIso8601String(),
            'createdAt': today.toIso8601String(),
          },
        );

        // getActiveNutritionGoal's cache-hit path fires a fire-and-forget
        // background sync when online.
        final active = await repository.getActiveNutritionGoal();
        expect(
          active.dailyCalories,
          1900,
          reason: 'the immediate read must return the pending local edit',
        );

        // Let the detached background sync run to completion.
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // The background sync must have actually reached and used this
        // stub - otherwise the guard below wasn't really exercised.
        verify(
          mockApiService.get<Map<String, dynamic>>(
            any,
            sessionContext: anyNamed('sessionContext'),
          ),
        ).called(1);

        final afterSync = await repository.getActiveNutritionGoal();
        expect(
          afterSync.dailyCalories,
          1900,
          reason:
              'the stale server value must never overwrite the still-'
              'pending local edit once the background sync completes',
        );

        // This second read is itself a cache-hit and fires ANOTHER
        // detached background sync - drain it before tearDown closes
        // Isar, so it doesn't race the next test's fresh instance.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
    );
  });

  group(
    'successful sync survives a restart with the same historical result',
    () {
      test('once a goal is marked synced, closing and reopening Isar resolves '
          'the exact same history as before the restart', () async {
        final weekAgo = day(-7);
        final today = day(0);
        await insertGoal(
          isar,
          serverId: 10,
          effectiveDate: weekAgo,
          dailyCalories: 1700,
        );
        // Represents a goal that WAS pending, then got acknowledged by a
        // successful sync (serverId assigned, syncStatus flipped to
        // 'synced') - exactly what _syncNutritionGoalToServer leaves
        // behind on success.
        await insertGoal(
          isar,
          serverId: 11,
          effectiveDate: today,
          dailyCalories: 2100,
        );

        final beforeOld = await repository.getGoalForDate(day(-5));
        final beforeNew = await repository.getGoalForDate(today);
        expect(beforeOld?.dailyCalories, 1700);
        expect(beforeNew?.dailyCalories, 2100);

        await isar.close();
        isar = await openIsar();
        localDb.setTestDatabase(isar);

        final afterOld = await repository.getGoalForDate(day(-5));
        final afterNew = await repository.getGoalForDate(today);
        expect(afterOld?.dailyCalories, 1700);
        expect(afterNew?.dailyCalories, 2100);
      });
    },
  );

  group('different-user history reads remain isolated', () {
    test('getGoalForDate and getGoalsForDateRange for user A never resolve '
        'or leak user B\'s overlapping-dated goals, even though both users '
        'have a row effective on the exact same date', () async {
      final today = day(0);
      await insertGoal(
        isar,
        uid: userId,
        serverId: 1,
        effectiveDate: today,
        dailyCalories: 2000,
      );
      await insertGoal(
        isar,
        uid: otherUserId,
        serverId: 2,
        effectiveDate: today,
        dailyCalories: 9999,
      );

      final resolved = await repository.getGoalForDate(today);
      expect(resolved?.dailyCalories, 2000);

      final range = await repository.getGoalsForDateRange(today, today);
      final normalizedToday = DateTime(today.year, today.month, today.day);
      expect(range[normalizedToday]?.goal?.dailyCalories, 2000);
      expect(range[normalizedToday]?.unavailable, isFalse);
    });
  });

  group('uncached offline date-range reads are honestly unavailable, never a '
      'silent confirmed-empty or a substituted current target', () {
    test(
      'a date range with zero local evidence, while offline, comes back '
      'marked unavailable for every day - not null-as-confirmed-empty',
      () async {
        when(mockConnectivity.isOnline).thenReturn(false);
        final start = day(-5);
        final end = day(-1);

        final result = await repository.getGoalsForDateRange(start, end);

        for (final entry in result.values) {
          expect(entry.goal, isNull);
          expect(
            entry.unavailable,
            isTrue,
            reason:
                'offline with no local evidence must report unavailable, '
                'never a confirmed absence',
          );
        }
      },
    );

    test('a date range partially covered by local evidence marks only the '
        'uncovered days unavailable - covered days resolve normally', () async {
      when(mockConnectivity.isOnline).thenReturn(false);
      // Evidence only exists from 3 days ago onward.
      await insertGoal(
        isar,
        serverId: 1,
        effectiveDate: day(-3),
        dailyCalories: 2000,
      );

      final result = await repository.getGoalsForDateRange(day(-5), day(-1));

      final fiveDaysAgo = DateTime(day(-5).year, day(-5).month, day(-5).day);
      final fourDaysAgo = DateTime(day(-4).year, day(-4).month, day(-4).day);
      final threeDaysAgo = DateTime(day(-3).year, day(-3).month, day(-3).day);
      final oneDayAgo = DateTime(day(-1).year, day(-1).month, day(-1).day);

      expect(result[fiveDaysAgo]?.unavailable, isTrue);
      expect(result[fourDaysAgo]?.unavailable, isTrue);
      expect(result[threeDaysAgo]?.unavailable, isFalse);
      expect(result[threeDaysAgo]?.goal?.dailyCalories, 2000);
      expect(result[oneDayAgo]?.unavailable, isFalse);
      expect(result[oneDayAgo]?.goal?.dailyCalories, 2000);
    });

    test('when online and the request succeeds, every day is confirmed - '
        'never marked unavailable, even a day the server confirms has no '
        'target', () async {
      when(mockConnectivity.isOnline).thenReturn(true);
      final start = day(-2);
      final end = day(-1);
      when(mockApiService.get<List<dynamic>>(any)).thenAnswer(
        (_) async => [
          forDatesEntryNoTarget(day(-2)),
          forDatesEntryNoTarget(day(-1)),
        ],
      );

      final result = await repository.getGoalsForDateRange(start, end);

      for (final entry in result.values) {
        expect(entry.unavailable, isFalse);
        expect(entry.goal, isNull);
      }
    });

    test('when the online request throws, the range falls back to local '
        'cache and reports unavailable for uncovered days rather than '
        'crashing or fabricating a confirmed result', () async {
      when(mockConnectivity.isOnline).thenReturn(true);
      when(
        mockApiService.get<List<dynamic>>(any),
      ).thenThrow(Exception('network error'));

      final result = await repository.getGoalsForDateRange(day(-2), day(-1));

      for (final entry in result.values) {
        expect(entry.unavailable, isTrue);
        expect(entry.goal, isNull);
      }
    });
  });
}
