import 'dart:async';

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
    when(
      mockRepository.getTodaysMealLog(date: anyNamed('date')),
    ).thenAnswer((_) async => mealLog());
    when(
      mockRepository.getNutritionDashboard(date: anyNamed('date')),
    ).thenAnswer(
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
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<NutritionProvider>.value(value: provider),
            ChangeNotifierProvider<ConnectivityService>.value(
              value: mockConnectivity,
            ),
          ],
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

    testWidgets(
      'a manually-saved goal (no AI explanation) is treated as configured, '
      'not the setup prompt',
      (tester) async {
        // Regression for a bug where a real, manually-entered goal (no
        // `explanation` because the user typed values directly rather than
        // using "Calculate from metrics") was misclassified as unconfigured
        // and the dashboard kept showing "Set Your Nutrition Goals" forever,
        // even though setup was already complete.
        await pumpDashboard(
          tester,
          mealLog: mixedMealLog,
          progress: staleProgress,
          activeGoal: goal(explanation: null),
        );

        expect(find.text('Set Your Nutrition Goals'), findsNothing);
        // The real calorie summary card renders instead, using the manually
        // saved goal's own values (2000 goal, 300 consumed, 1700 remaining).
        expect(find.text('2000'), findsWidgets);
        expect(find.text('300'), findsWidgets);
        expect(find.text('1700'), findsOneWidget);
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
            mockRepository.getTodaysMealLog(date: anyNamed('date')),
          ).thenAnswer((_) async => currentLog);
          when(
            mockRepository.getNutritionDashboard(date: anyNamed('date')),
          ).thenAnswer(
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
              home: MultiProvider(
                providers: [
                  ChangeNotifierProvider<NutritionProvider>.value(
                    value: provider,
                  ),
                  ChangeNotifierProvider<ConnectivityService>.value(
                    value: mockConnectivity,
                  ),
                ],
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
          // next getTodaysMealLog(date: anyNamed('date')) call returns - the mocked dailyProgress
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
            mockRepository.getTodaysMealLog(date: anyNamed('date')),
          ).thenAnswer((_) async => currentLog);
          when(
            mockRepository.getNutritionDashboard(date: anyNamed('date')),
          ).thenAnswer(
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
              home: MultiProvider(
                providers: [
                  ChangeNotifierProvider<NutritionProvider>.value(
                    value: provider,
                  ),
                  ChangeNotifierProvider<ConnectivityService>.value(
                    value: mockConnectivity,
                  ),
                ],
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

        when(
          mockRepository.getTodaysMealLog(date: anyNamed('date')),
        ).thenAnswer((_) async => log);
        when(
          mockRepository.getNutritionDashboard(date: anyNamed('date')),
        ).thenAnswer((_) async {
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
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider<NutritionProvider>.value(
                  value: provider,
                ),
                ChangeNotifierProvider<ConnectivityService>.value(
                  value: mockConnectivity,
                ),
              ],
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

  group('mutation-error feedback: distinguishes stale/superseded from genuine '
      'failure', () {
    // Regression for two Phase-4 mutation-feedback bugs on the failure
    // feedback added to
    // _buildWaterButton/_deleteFood/_showEditFoodDialog/_markMealConsumed:
    //
    // Bug 1: a synthesized generic snackbar ("Failed to log water", etc.)
    // showed whenever the mutation returned `false` - but NutritionProvider
    // returns `false` for TWO very different outcomes it deliberately
    // distinguishes via `errorMessage`: a genuine failure (message set) vs.
    // a stale/ended session (left untouched). `provider.errorMessage ??
    // 'generic fallback'` collapsed that distinction, so a late response
    // after logout/account switch showed a made-up failure snackbar.
    //
    // Bug 2: fixing Bug 1 by gating on `errorMessage != null` is still
    // wrong, because `errorMessage` is a single field SHARED across every
    // mutation the provider is handling - an old, already-displayed error
    // can sit there and get re-shown for an unrelated later operation that
    // also returns `false`. The fix is [NutritionProvider.onError]: a
    // synchronous, per-call callback fired if and only if THAT call's own
    // operation genuinely failed while the session was still current -
    // never read from the shared field - so a caller's feedback decision
    // cannot be confused by unrelated past or concurrent activity.
    //
    // The "prime" tests below seed the shared `errorMessage` field with an
    // unrelated, already-displayed failure first, specifically to prove
    // the next operation's feedback decision does not depend on it.
    Future<void> primeExistingWaterError(WidgetTester tester) async {
      when(
        mockRepository.updateWaterIntake(1, any),
      ).thenThrow(Exception('primed failure'));

      await tester.ensureVisible(find.text('250ml'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('250ml'));
      await tester.pumpAndSettle();

      expect(find.textContaining('primed failure'), findsOneWidget);
      // Outlive the SnackBar's default display duration.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      clearInteractions(mockRepository);
    }

    testWidgets(
      'an existing error followed by a stale (logout) addWater result '
      'shows no snackbar and does not resurface the old message',
      (tester) async {
        final provider = await pumpDashboard(
          tester,
          mealLog: mixedMealLog,
          progress: staleProgress,
          activeGoal: goal(),
        );

        await primeExistingWaterError(tester);

        final gate = Completer<void>();
        when(
          mockRepository.updateWaterIntake(1, any),
        ).thenAnswer((_) => gate.future);

        await tester.ensureVisible(find.text('250ml'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('250ml'));
        await tester.pump();

        // The session ends (logout / account switch) while this second,
        // unrelated water update is still in flight.
        sessionEpoch.invalidate();
        gate.complete();
        await tester.pumpAndSettle();

        // Confirms the tap genuinely reached the button and the mutation
        // ran, rather than this test passing merely because the tap
        // silently missed.
        verify(mockRepository.updateWaterIntake(1, any)).called(1);
        // The shared field still holds the OLD, already-displayed message
        // - proving that a UI which merely checked `errorMessage != null`
        // would incorrectly resurface it here. The onError-based call site
        // never reads this field, so nothing is shown regardless.
        expect(provider.errorMessage, contains('primed failure'));
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'an existing error followed by a genuine current-operation addWater '
      'failure still shows that new failure, not the old one',
      (tester) async {
        await pumpDashboard(
          tester,
          mealLog: mixedMealLog,
          progress: staleProgress,
          activeGoal: goal(),
        );

        await primeExistingWaterError(tester);

        when(
          mockRepository.updateWaterIntake(1, any),
        ).thenThrow(Exception('fresh failure'));

        await tester.ensureVisible(find.text('250ml'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('250ml'));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining('fresh failure'), findsOneWidget);
        expect(find.textContaining('primed failure'), findsNothing);
      },
    );

    // Not a widget test: NutritionProvider has no per-target mutation
    // generation (unlike ProgramsProvider), so two overlapping mutations
    // on this SAME provider instance race directly on the shared
    // `errorMessage` field with nothing to arbitrate between them. This
    // exercises NutritionProvider.onError directly on two concurrent
    // calls - updateFoodQuantity and addWater - using the exact callback
    // the UI relies on, proving neither call's feedback depends on or
    // contaminates the other's.
    test('overlapping operations (updateFoodQuantity, addWater): each '
        "call's own outcome surfaces via its own onError and never "
        "contaminates, or is contaminated by, the other's", () async {
      final provider = NutritionProvider(
        mockRepository,
        sessionEpoch,
        mockConnectivity,
      );
      // Give the provider a loaded meal log so addWater's null-guard
      // passes and it can compute a new water target.
      when(
        mockRepository.getTodaysMealLog(date: anyNamed('date')),
      ).thenAnswer((_) async => mixedMealLog());
      when(
        mockRepository.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer(
        (_) async => NutritionDashboardData(
          date: DateTime.now(),
          goal: goal(),
          progress: staleProgress(),
        ),
      );
      when(
        mockRepository.getStreak(),
      ).thenAnswer((_) async => StreakInfo(currentStreak: 0, longestStreak: 0));
      await provider.loadTodaysData();

      final gateFood = Completer<void>();
      final gateWater = Completer<void>();
      when(
        mockRepository.updateFoodQuantity(1, any),
      ).thenAnswer((_) => gateFood.future);
      when(
        mockRepository.updateWaterIntake(any, any),
      ).thenAnswer((_) => gateWater.future);

      String? foodError;
      String? waterError;

      final foodFuture = provider.updateFoodQuantity(
        1,
        2,
        onError: (m) => foodError = m,
      );
      final waterFuture = provider.addWater(
        250,
        onError: (m) => waterError = m,
      );

      // The food update fails genuinely.
      gateFood.completeError(Exception('food failed'));
      expect(await foodFuture, isFalse);
      expect(foodError, contains('food failed'));

      // The water update succeeds, and must never have received the
      // food call's message nor produced one of its own.
      gateWater.complete();
      expect(await waterFuture, isTrue);
      expect(waterError, isNull);
    });
  });
}
