import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/data/models/daily_nutrition_progress.dart';
import 'package:go_hard_app/data/models/meal_entry.dart';
import 'package:go_hard_app/data/models/meal_log.dart';
import 'package:go_hard_app/data/models/nutrition_goal.dart';
import 'package:go_hard_app/data/models/nutrition_summary.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';
import 'package:go_hard_app/ui/widgets/nutrition/nutrition_summary_card.dart';

import 'nutrition_summary_card_test.mocks.dart';

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

  testWidgets(
    'displays consumed-only calories and macros for a mixed planned/consumed log',
    (tester) async {
      final now = DateTime.now();
      // One consumed entry (300 cal / 20g protein) + one unconsumed entry
      // (500 cal / 40g protein). The card must show only the consumed
      // entry's contribution, never the combined planned total of 800/60.
      final mealLog = MealLog(
        id: 1,
        userId: 1,
        date: now,
        createdAt: now,
        mealEntries: [
          MealEntry(
            id: 1,
            mealLogId: 1,
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
            mealLogId: 1,
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
      final activeGoal = NutritionGoal(
        id: 1,
        userId: 1,
        name: 'Goal',
        dailyCalories: 2000,
        dailyProtein: 150,
        dailyCarbohydrates: 200,
        dailyFat: 65,
        isActive: true,
        createdAt: now,
      );

      when(mockRepository.getTodaysMealLog()).thenAnswer((_) async => mealLog);
      when(mockRepository.getNutritionDashboard()).thenAnswer(
        (_) async => NutritionDashboardData(
          date: now,
          goal: activeGoal,
          progress: DailyNutritionProgress(
            id: 1,
            userId: 1,
            date: now,
            nutritionGoalId: activeGoal.id,
            plannedCalories: 800,
            consumedCalories: 300,
            createdAt: now,
          ),
        ),
      );
      when(
        mockRepository.getStreak(),
      ).thenAnswer((_) async => StreakInfo(currentStreak: 0, longestStreak: 0));

      final provider = NutritionProvider(mockRepository, mockConnectivity);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<NutritionProvider>.value(
            value: provider,
            child: const Scaffold(body: NutritionSummaryCard()),
          ),
        ),
      );

      // initState's postFrameCallback triggers loadTodaysData(); let the
      // mocked repository calls and the resulting notifyListeners() settle.
      await tester.pumpAndSettle();

      // Consumed-only calories (300), not the planned total (800).
      expect(find.text('300 / 2000 kcal'), findsOneWidget);
      expect(find.text('15%'), findsOneWidget);

      // Consumed-only protein (20g), not the planned total (60g).
      expect(find.text('20g'), findsOneWidget);
      expect(find.text('60g'), findsNothing);
      expect(find.text('800'), findsNothing);
    },
  );
}
