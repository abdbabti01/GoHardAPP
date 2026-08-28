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
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';
import 'package:go_hard_app/ui/screens/nutrition/nutrition_dashboard_screen.dart';

import 'nutrition_dashboard_screen_test.mocks.dart';

/// Regression coverage for the TodayScreen vs Eat/Nutrition-screen split
/// state bug: NutritionDashboardScreen's headline calorie card and macro
/// bars used to read `NutritionProvider.dailyProgress`, a server-fetched
/// snapshot that can lag behind a local mutation until background/periodic
/// sync reaches the server. They now read `NutritionProvider.todaysMealLog`
/// - the same locally-computed, always-current source TodayScreen already
/// used. Every test here deliberately makes `dailyProgress` wrong/stale to
/// prove the screen no longer depends on it for today's totals.
@GenerateMocks([NutritionRepository, ConnectivityService])
void main() {
  late MockNutritionRepository mockRepository;
  late MockConnectivityService mockConnectivity;
  late UserSessionEpoch sessionEpoch;

  setUp(() {
    mockRepository = MockNutritionRepository();
    mockConnectivity = MockConnectivityService();
    sessionEpoch = UserSessionEpoch()..activate(1);
    when(mockConnectivity.isOnline).thenReturn(true);
    when(
      mockConnectivity.connectivityStream,
    ).thenAnswer((_) => const Stream<bool>.empty());
  });

  NutritionGoal goal({
    double dailyCalories = 2000,
    double dailyProtein = 150,
    double dailyCarbohydrates = 200,
    double dailyFat = 65,
    String? explanation = 'calculated from body metrics',
  }) {
    return NutritionGoal(
      id: 1,
      userId: 1,
      name: 'Goal',
      dailyCalories: dailyCalories,
      dailyProtein: dailyProtein,
      dailyCarbohydrates: dailyCarbohydrates,
      dailyFat: dailyFat,
      isActive: true,
      createdAt: DateTime.now(),
      explanation: explanation,
    );
  }

  // One consumed entry (300 cal / 20g P / 35g C / 9g F) + one unconsumed
  // entry (500 cal / 40g P / 60g C / 15g F). Consumed totals must reflect
  // only the first; planned must reflect both (800 cal).
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

  // A DailyNutritionProgress that is deliberately wrong relative to the
  // MealLog above - stands in for a stale/lagging server snapshot.
  DailyNutritionProgress staleProgress({
    double consumedCalories = 0,
    double plannedCalories = 0,
    double consumedProtein = 0,
    double consumedCarbohydrates = 0,
    double consumedFat = 0,
  }) {
    final now = DateTime.now();
    return DailyNutritionProgress(
      id: 1,
      userId: 1,
      date: now,
      createdAt: now,
      consumedCalories: consumedCalories,
      plannedCalories: plannedCalories,
      consumedProtein: consumedProtein,
      consumedCarbohydrates: consumedCarbohydrates,
      consumedFat: consumedFat,
    );
  }

  Future<NutritionProvider> pumpDashboard(
    WidgetTester tester, {
    required MealLog Function() mealLog,
    required DailyNutritionProgress Function() progress,
    NutritionGoal? activeGoal,
  }) async {
    when(mockRepository.getTodaysMealLog()).thenAnswer((_) async => mealLog());
    when(mockRepository.getNutritionDashboard()).thenAnswer(
      (_) async => NutritionDashboardData(
        date: DateTime.now(),
        goal: activeGoal,
        progress: progress(),
      ),
    );
    when(
      mockRepository.getStreak(),
    ).thenAnswer((_) async => StreakInfo(currentStreak: 0, longestStreak: 0));
    when(
      mockRepository.getMealLogs(
        startDate: anyNamed('startDate'),
        endDate: anyNamed('endDate'),
      ),
    ).thenAnswer((_) async => []);

    final provider = NutritionProvider(
      mockRepository,
      sessionEpoch,
      mockConnectivity,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<NutritionProvider>.value(
          value: provider,
          child: const Scaffold(body: NutritionDashboardScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  group('calories: sourced from todaysMealLog, not dailyProgress', () {
    testWidgets(
      'consumed/planned/remaining render from MealLog while dailyProgress is stale-zero',
      (tester) async {
        await pumpDashboard(
          tester,
          mealLog: mixedMealLog,
          progress: staleProgress,
          activeGoal: goal(),
        );

        // Consumed (300, from the one consumed entry) - not the stale 0.
        expect(find.text('300'), findsWidgets); // "Consumed" row + ring
        // Planned (800, both entries) - not the stale 0.
        expect(find.text('800'), findsOneWidget);
        // Remaining = goal(2000) - consumed(300) = 1700, not goal - planned
        // (1200) and not goal - stale-consumed (2000).
        expect(find.text('1700'), findsOneWidget);
      },
    );

    testWidgets(
      'unconsumed entries count toward planned but not consumed/remaining',
      (tester) async {
        await pumpDashboard(
          tester,
          mealLog: mixedMealLog,
          progress: staleProgress,
          activeGoal: goal(),
        );

        // The 500-cal unconsumed entry inflates Planned (800)...
        expect(find.text('800'), findsOneWidget);
        // ...but must not appear in Consumed (300) or leak into Remaining.
        expect(find.text('1200'), findsNothing); // goal - planned (wrong)
        expect(find.text('1700'), findsOneWidget); // goal - consumed (right)
      },
    );

    testWidgets('no MealLog entries renders zero totals without crashing', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpDashboard(
        tester,
        mealLog: () => MealLog(id: 1, userId: 1, date: now, createdAt: now),
        progress: staleProgress,
        activeGoal: goal(),
      );

      expect(find.text('0'), findsWidgets); // consumed + planned + ring
      expect(find.text('2000'), findsWidgets); // goal + remaining (2000-0)
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'no active goal falls back to setup prompt using MealLog consumed',
      (tester) async {
        await pumpDashboard(
          tester,
          mealLog: mixedMealLog,
          progress: () => staleProgress(consumedCalories: 0),
          activeGoal: null,
        );

        expect(find.text('Set Your Nutrition Goals'), findsOneWidget);
        // "Eaten" in the setup prompt must show the real consumed total (300)
        // from MealLog, not the stale dailyProgress value (0).
        expect(find.text('300'), findsOneWidget);
      },
    );

    testWidgets('zero-calorie goal does not divide by zero or crash', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        mealLog: mixedMealLog,
        progress: staleProgress,
        activeGoal: goal(
          dailyCalories: 0,
          dailyProtein: 0,
          dailyCarbohydrates: 0,
          dailyFat: 0,
        ),
      );

      expect(tester.takeException(), isNull);
      // Over goal by (consumed - goal) = 300 - 0 = 300.
      expect(find.text('Over goal by 300 cal'), findsOneWidget);
      expect(find.text('+300'), findsOneWidget); // remaining = 0 - 300
    });

    testWidgets(
      'consumed exceeding goal preserves over-goal styling with correct value',
      (tester) async {
        final now = DateTime.now();
        await pumpDashboard(
          tester,
          mealLog:
              () => MealLog(
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
                    totalCalories: 2500,
                    totalProtein: 20,
                    totalCarbohydrates: 35,
                    totalFat: 9,
                    createdAt: now,
                  ),
                ],
              ),
          progress: () => staleProgress(consumedCalories: 100), // under goal
          activeGoal: goal(dailyCalories: 2000),
        );

        // If the stale dailyProgress (100) were used, no "over goal" banner
        // would render. The real MealLog consumed value (2500) must drive it.
        expect(find.text('Over goal by 500 cal'), findsOneWidget);
        expect(find.text('+500'), findsOneWidget); // remaining = 2000 - 2500
      },
    );
  });

  group('macros: sourced from todaysMealLog, not dailyProgress', () {
    testWidgets('protein/carbs/fat render consumed-only values from MealLog', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        mealLog: mixedMealLog,
        progress: staleProgress,
        activeGoal: goal(),
      );

      // Consumed-only (from the one consumed entry), not the stale 0 and
      // not the combined planned total (60/95/24).
      expect(find.text('20 / 150 g'), findsOneWidget); // protein
      expect(find.text('35 / 200 g'), findsOneWidget); // carbs
      expect(find.text('9 / 65 g'), findsOneWidget); // fat
      expect(find.text('60 / 150 g'), findsNothing);
      expect(find.text('0 / 150 g'), findsNothing);
    });
  });

  group(
    'mark consumed / unconsumed: matches TodayScreen source, ignores stale dailyProgress',
    () {
      testWidgets(
        'marking a meal consumed updates Eat-screen totals though dailyProgress mock never changes',
        (tester) async {
          final now = DateTime.now();
          MealLog currentLog = MealLog(
            id: 1,
            userId: 1,
            date: now,
            createdAt: now,
            mealEntries: [
              MealEntry(
                id: 10,
                mealLogId: 1,
                mealType: 'Breakfast',
                isConsumed: false,
                totalCalories: 300,
                totalProtein: 20,
                totalCarbohydrates: 35,
                totalFat: 9,
                createdAt: now,
              ),
            ],
          );
          final activeGoal = goal();
          // dailyProgress is stubbed once, to an all-zero snapshot, and never
          // changes for the rest of the test.
          final frozenStaleProgress = staleProgress();

          when(
            mockRepository.getTodaysMealLog(),
          ).thenAnswer((_) async => currentLog);
          when(mockRepository.getNutritionDashboard()).thenAnswer(
            (_) async => NutritionDashboardData(
              date: now,
              goal: activeGoal,
              progress: frozenStaleProgress,
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
          ).thenAnswer((_) async => []);
          when(
            mockRepository.markMealAsConsumed(
              any,
              isConsumed: anyNamed('isConsumed'),
              consumedAt: anyNamed('consumedAt'),
            ),
          ).thenAnswer((_) async {});

          final provider = NutritionProvider(
            mockRepository,
            sessionEpoch,
            mockConnectivity,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: ChangeNotifierProvider<NutritionProvider>.value(
                value: provider,
                child: const Scaffold(body: NutritionDashboardScreen()),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Before: unconsumed, so Consumed=0 but Planned=300; Goal and
          // Remaining both show 2000 (nothing consumed yet).
          expect(find.text('2000'), findsNWidgets(2)); // Goal + Remaining
          expect(find.text('0 / 150 g'), findsOneWidget); // protein consumed

          // Simulate the repository's local write completing (production
          // writes Isar synchronously before returning) by updating what the
          // next getTodaysMealLog() call returns - the mocked dailyProgress
          // is left untouched throughout.
          currentLog = currentLog.copyWith(
            mealEntries: [
              currentLog.mealEntries!.first.copyWith(
                isConsumed: true,
                consumedAt: now,
              ),
            ],
          );

          await provider.markMealAsConsumed(10);
          await tester.pumpAndSettle();

          // After: Consumed=300, Remaining=1700; Goal(2000) now appears once.
          expect(find.text('2000'), findsOneWidget); // Goal only
          expect(find.text('1700'), findsOneWidget); // Remaining
          expect(find.text('20 / 150 g'), findsOneWidget); // protein consumed
        },
      );

      testWidgets(
        'marking a meal unconsumed returns Eat-screen totals to the lower value',
        (tester) async {
          final now = DateTime.now();
          MealLog currentLog = MealLog(
            id: 1,
            userId: 1,
            date: now,
            createdAt: now,
            mealEntries: [
              MealEntry(
                id: 10,
                mealLogId: 1,
                mealType: 'Breakfast',
                isConsumed: true,
                consumedAt: now,
                totalCalories: 300,
                totalProtein: 20,
                totalCarbohydrates: 35,
                totalFat: 9,
                createdAt: now,
              ),
            ],
          );
          final activeGoal = goal();
          final frozenStaleProgress = staleProgress(
            consumedCalories: 9999, // deliberately wrong in the other direction
            consumedProtein: 9999,
          );

          when(
            mockRepository.getTodaysMealLog(),
          ).thenAnswer((_) async => currentLog);
          when(mockRepository.getNutritionDashboard()).thenAnswer(
            (_) async => NutritionDashboardData(
              date: now,
              goal: activeGoal,
              progress: frozenStaleProgress,
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
          ).thenAnswer((_) async => []);
          when(
            mockRepository.markMealAsConsumed(
              any,
              isConsumed: anyNamed('isConsumed'),
              consumedAt: anyNamed('consumedAt'),
            ),
          ).thenAnswer((_) async {});

          final provider = NutritionProvider(
            mockRepository,
            sessionEpoch,
            mockConnectivity,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: ChangeNotifierProvider<NutritionProvider>.value(
                value: provider,
                child: const Scaffold(body: NutritionDashboardScreen()),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Before: consumed - never the stale 9999.
          expect(find.text('20 / 150 g'), findsOneWidget);
          expect(find.text('9999'), findsNothing);

          currentLog = currentLog.copyWith(
            mealEntries: [
              currentLog.mealEntries!.first.copyWith(
                isConsumed: false,
                consumedAt: null,
              ),
            ],
          );

          await provider.markMealAsConsumed(10, isConsumed: false);
          await tester.pumpAndSettle();

          // After: back to zero consumed, plan (300) unaffected since planned
          // counts all entries regardless of consumption status.
          expect(find.text('0 / 150 g'), findsOneWidget);
          expect(find.text('300'), findsOneWidget); // Planned only now
          expect(find.text('9999'), findsNothing);
        },
      );
    },
  );

  group('stale-server regression', () {
    testWidgets(
      'changing dailyProgress between two different stale snapshots does not change rendered totals',
      (tester) async {
        final log = mixedMealLog(); // consumed 300, planned 800
        final activeGoal = goal();
        var callCount = 0;

        when(mockRepository.getTodaysMealLog()).thenAnswer((_) async => log);
        when(mockRepository.getNutritionDashboard()).thenAnswer((_) async {
          callCount++;
          final wrong = callCount == 1 ? 111.0 : 9999.0;
          return NutritionDashboardData(
            date: DateTime.now(),
            goal: activeGoal,
            progress: staleProgress(
              consumedCalories: wrong,
              plannedCalories: wrong,
              consumedProtein: wrong,
            ),
          );
        });
        when(mockRepository.getStreak()).thenAnswer(
          (_) async => StreakInfo(currentStreak: 0, longestStreak: 0),
        );
        when(
          mockRepository.getMealLogs(
            startDate: anyNamed('startDate'),
            endDate: anyNamed('endDate'),
          ),
        ).thenAnswer((_) async => []);

        final provider = NutritionProvider(
          mockRepository,
          sessionEpoch,
          mockConnectivity,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<NutritionProvider>.value(
              value: provider,
              child: const Scaffold(body: NutritionDashboardScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('300'), findsWidgets);
        expect(find.text('111'), findsNothing);
        expect(find.text('9999'), findsNothing);

        // Second, still-wrong dailyProgress snapshot; MealLog is unchanged.
        await provider.loadTodaysData();
        await tester.pumpAndSettle();

        expect(find.text('300'), findsWidgets);
        expect(find.text('9999'), findsNothing);
        expect(find.text('111'), findsNothing);
      },
    );
  });
}
