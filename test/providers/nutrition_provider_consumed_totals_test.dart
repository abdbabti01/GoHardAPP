import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/data/models/daily_nutrition_progress.dart';
import 'package:go_hard_app/data/models/meal_entry.dart';
import 'package:go_hard_app/data/models/meal_log.dart';
import 'package:go_hard_app/data/models/nutrition_goal.dart';
import 'package:go_hard_app/data/models/nutrition_summary.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';

import 'nutrition_provider_consumed_totals_test.mocks.dart';

@GenerateMocks([NutritionRepository, ConnectivityService])
void main() {
  late MockNutritionRepository mockRepository;
  late MockConnectivityService mockConnectivity;

  setUp(() {
    mockRepository = MockNutritionRepository();
    mockConnectivity = MockConnectivityService();
    when(mockConnectivity.isOnline).thenReturn(true);
    when(
      mockConnectivity.connectivityStream,
    ).thenAnswer((_) => const Stream<bool>.empty());
  });

  NutritionGoal goal() {
    return NutritionGoal(
      id: 1,
      userId: 1,
      name: 'Goal',
      dailyCalories: 2000,
      dailyProtein: 150,
      dailyCarbohydrates: 200,
      dailyFat: 65,
      isActive: true,
      createdAt: DateTime.now(),
    );
  }

  // One consumed entry (300/20/35/9) + one unconsumed entry (500/40/60/15).
  // Consumed totals must reflect only the first; planned must reflect both.
  MealLog mixedMealLog({int id = 1}) {
    final now = DateTime.now();
    return MealLog(
      id: id,
      userId: 1,
      date: now,
      createdAt: now,
      mealEntries: [
        MealEntry(
          id: 1,
          mealLogId: id,
          mealType: 'Breakfast',
          isConsumed: true,
          totalCalories: 300,
          totalProtein: 20,
          totalCarbohydrates: 35,
          totalFat: 9,
          createdAt: now,
        ),
        MealEntry(
          id: 2,
          mealLogId: id,
          mealType: 'Lunch',
          isConsumed: false,
          totalCalories: 500,
          totalProtein: 40,
          totalCarbohydrates: 60,
          totalFat: 15,
          createdAt: now,
        ),
      ],
    );
  }

  DailyNutritionProgress progressFor(MealLog log, NutritionGoal activeGoal) {
    return DailyNutritionProgress(
      id: 1,
      userId: 1,
      date: DateTime.now(),
      nutritionGoalId: activeGoal.id,
      plannedCalories: log.plannedCalories,
      plannedProtein: log.plannedProtein,
      plannedCarbohydrates: log.plannedCarbohydrates,
      plannedFat: log.plannedFat,
      consumedCalories: log.consumedCalories,
      consumedProtein: log.consumedProtein,
      consumedCarbohydrates: log.consumedCarbohydrates,
      consumedFat: log.consumedFat,
      createdAt: DateTime.now(),
    );
  }

  Future<NutritionProvider> loadedProvider(MealLog mealLog) async {
    final activeGoal = goal();
    when(mockRepository.getTodaysMealLog()).thenAnswer((_) async => mealLog);
    when(mockRepository.getNutritionDashboard()).thenAnswer(
      (_) async => NutritionDashboardData(
        date: DateTime.now(),
        goal: activeGoal,
        progress: progressFor(mealLog, activeGoal),
      ),
    );
    when(
      mockRepository.getStreak(),
    ).thenAnswer((_) async => StreakInfo(currentStreak: 0, longestStreak: 0));

    final provider = NutritionProvider(mockRepository, mockConnectivity);
    await provider.loadTodaysData();
    return provider;
  }

  group('NutritionProvider consumed-only getters (TodayScreen data source)', () {
    test(
      'caloriesRemaining and calorieProgressPercentage use consumed, not planned',
      () async {
        final provider = await loadedProvider(mixedMealLog());

        expect(provider.todaysMealLog!.consumedCalories, 300);
        expect(provider.todaysMealLog!.plannedCalories, 800);

        expect(provider.caloriesRemaining, 2000 - 300);
        expect(
          provider.calorieProgressPercentage,
          closeTo(300 / 2000 * 100, 1e-9),
        );
      },
    );

    test(
      'proteinRemaining and proteinProgressPercentage use consumed, not planned',
      () async {
        final provider = await loadedProvider(mixedMealLog());

        expect(provider.todaysMealLog!.consumedProtein, 20);
        expect(provider.proteinRemaining, 150 - 20);
        expect(
          provider.proteinProgressPercentage,
          closeTo(20 / 150 * 100, 1e-9),
        );
      },
    );

    test(
      'consumed-only getters return zero when nothing has been marked consumed',
      () async {
        final now = DateTime.now();
        final allPlannedLog = MealLog(
          id: 3,
          userId: 1,
          date: now,
          createdAt: now,
          mealEntries: [
            MealEntry(
              id: 1,
              mealLogId: 3,
              mealType: 'Breakfast',
              isConsumed: false,
              totalCalories: 400,
              totalProtein: 30,
              totalCarbohydrates: 50,
              totalFat: 12,
              createdAt: now,
            ),
          ],
        );

        final provider = await loadedProvider(allPlannedLog);

        expect(provider.todaysMealLog!.consumedCalories, 0);
        expect(provider.caloriesRemaining, 2000);
        expect(provider.calorieProgressPercentage, 0);
      },
    );
  });

  group('nutrition history exclusion (Yesterday teaser / history cards)', () {
    test(
      'history MealLog objects expose consumed* getters that exclude unconsumed entries',
      () async {
        final activeGoal = goal();
        final historyLog = mixedMealLog(id: 2);

        when(mockRepository.getTodaysMealLog()).thenAnswer(
          (_) async => MealLog(
            id: 4,
            userId: 1,
            date: DateTime.now(),
            createdAt: DateTime.now(),
            mealEntries: const [],
          ),
        );
        when(mockRepository.getNutritionDashboard()).thenAnswer(
          (_) async => NutritionDashboardData(
            date: DateTime.now(),
            goal: activeGoal,
            progress: DailyNutritionProgress(
              id: 1,
              userId: 1,
              date: DateTime.now(),
              nutritionGoalId: activeGoal.id,
              createdAt: DateTime.now(),
            ),
          ),
        );
        when(mockRepository.getStreak()).thenAnswer(
          (_) async => StreakInfo(currentStreak: 0, longestStreak: 0),
        );
        when(
          mockRepository.getMealLogs(
            startDate: anyNamed('startDate'),
            endDate: anyNamed('endDate'),
          ),
        ).thenAnswer((_) async => [historyLog]);

        final provider = NutritionProvider(mockRepository, mockConnectivity);
        await provider.loadNutritionHistory();

        expect(provider.nutritionHistory, hasLength(1));
        // This is exactly what today_screen.dart's "Yesterday" teaser and
        // nutrition_dashboard_screen.dart's history cards read.
        expect(provider.nutritionHistory.first.consumedCalories, 300);
        expect(provider.nutritionHistory.first.consumedProtein, 20);
        expect(provider.nutritionHistory.first.consumedCarbohydrates, 35);
        expect(provider.nutritionHistory.first.consumedFat, 9);
        expect(provider.nutritionHistory.first.plannedCalories, 800);
      },
    );
  });
}
