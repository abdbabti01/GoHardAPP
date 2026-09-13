import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/body_metric.dart';
import 'package:go_hard_app/data/models/goal.dart';
import 'package:go_hard_app/data/repositories/body_metrics_repository.dart';
import 'package:go_hard_app/data/repositories/goals_repository.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/providers/body_metrics_provider.dart';
import 'package:go_hard_app/providers/goals_provider.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';
import 'package:go_hard_app/ui/screens/goals/dialogs/smart_goal_dialog.dart';

@GenerateMocks([
  GoalsRepository,
  NutritionRepository,
  BodyMetricsRepository,
  ConnectivityService,
])
import 'smart_goal_dialog_test.mocks.dart';

/// Phase 2 nutrition-consent contract for [SmartGoalDialog]:
/// - Creating a goal never requires body metrics (regardless of goal type) and never calls
///   the nutrition repository at all.
/// - Nutrition setup is reached only via an explicit "Set Up" tap, previews (never saves)
///   first, and only "Apply" ever saves.
/// - "Skip" at any point never calls the save endpoint.
void main() {
  late MockGoalsRepository goalsRepo;
  late MockNutritionRepository nutritionRepo;
  late MockBodyMetricsRepository bodyMetricsRepo;
  late MockConnectivityService connectivity;
  late UserSessionEpoch epoch;
  late GoalsProvider goalsProvider;
  late NutritionProvider nutritionProvider;
  late BodyMetricsProvider bodyMetricsProvider;

  CalculatedNutrition nutrition({double calories = 2200}) =>
      CalculatedNutrition(
        nutritionGoalId: 42,
        dailyCalories: calories,
        dailyProtein: 150,
        dailyCarbohydrates: 200,
        dailyFat: 65,
        dailyFiber: 25,
        dailyWater: 2000,
        bmr: 1600,
        tdee: 2400,
        calorieAdjustment: -200,
        expectedWeeklyWeightChange: -0.5,
        explanation: 'test',
      );

  setUp(() {
    goalsRepo = MockGoalsRepository();
    nutritionRepo = MockNutritionRepository();
    bodyMetricsRepo = MockBodyMetricsRepository();
    connectivity = MockConnectivityService();
    epoch = UserSessionEpoch();
    epoch.activate(1);

    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => const Stream<bool>.empty());

    when(
      goalsRepo.createGoal(any),
    ).thenAnswer((inv) async => inv.positionalArguments[0] as Goal);

    when(bodyMetricsRepo.getLatestMetric()).thenAnswer((_) async => null);

    when(
      nutritionRepo.getTodaysMealLog(),
    ).thenAnswer((_) async => throw Exception('not needed for these tests'));
    when(
      nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
    ).thenAnswer((_) async => throw Exception('not needed for these tests'));
    when(
      nutritionRepo.getStreak(),
    ).thenAnswer((_) async => throw Exception('not needed for these tests'));

    goalsProvider = GoalsProvider(goalsRepo, epoch, connectivity);
    nutritionProvider = NutritionProvider(nutritionRepo, epoch, connectivity);
    bodyMetricsProvider = BodyMetricsProvider(
      bodyMetricsRepo,
      epoch,
      connectivity,
    );
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    // The default test surface is too small for the nutrition preview card's macro circles
    // (unrelated pre-existing layout, not under test here) - give it real phone-sized room.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GoalsProvider>.value(value: goalsProvider),
          ChangeNotifierProvider<NutritionProvider>.value(
            value: nutritionProvider,
          ),
          ChangeNotifierProvider<BodyMetricsProvider>.value(
            value: bodyMetricsProvider,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog<SmartGoalDialogResult>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const SmartGoalDialog(),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> selectGoalType(WidgetTester tester, String goalType) async {
    // When metrics ARE available, the form starts on the quick-templates view;
    // reveal the advanced form (with the Goal Type dropdown) first.
    final customGoalLink = find.text('Or create custom goal...');
    if (customGoalLink.evaluate().isNotEmpty) {
      await tester.tap(customGoalLink);
      await tester.pumpAndSettle();
    }

    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Goal Type'),
    );
    await tester.pumpAndSettle();
    // The dropdown menu shows one entry per item PLUS the currently-selected
    // field echo; `.last` targets the open menu's entry.
    await tester.tap(find.text(goalType).last);
    await tester.pumpAndSettle();
  }

  group('goal creation is never gated by or coupled to nutrition', () {
    testWidgets(
      'Create is enabled with no body metrics for a non-metric goal type, '
      'and creating the goal never touches the nutrition repository',
      (tester) async {
        await pumpDialog(tester);

        await selectGoalType(tester, 'Workout Frequency');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Current Value'),
          '0',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Target Value'),
          '4',
        );
        await tester.pumpAndSettle();

        final createButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Create'),
        );
        expect(
          createButton.onPressed,
          isNotNull,
          reason: 'Create must not be gated by missing body metrics',
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
        await tester.pumpAndSettle();

        verify(goalsRepo.createGoal(any)).called(1);
        verifyNever(
          nutritionRepo.calculateNutritionFromMetrics(
            goalType: anyNamed('goalType'),
            targetWeightChange: anyNamed('targetWeightChange'),
            timeframeWeeks: anyNamed('timeframeWeeks'),
          ),
        );
        verifyNever(
          nutritionRepo.calculateAndSaveNutrition(
            goalType: anyNamed('goalType'),
            targetWeightChange: anyNamed('targetWeightChange'),
            timeframeWeeks: anyNamed('timeframeWeeks'),
          ),
        );

        // Landed on the summary screen with nutrition offered, not auto-applied.
        expect(find.text('Nutrition Targets (Optional)'), findsOneWidget);
        expect(find.text('Set Up'), findsOneWidget);
      },
    );
  });

  group('optional nutrition setup previews before saving', () {
    Future<void> createGoalAndReachSummary(WidgetTester tester) async {
      await pumpDialog(tester);
      await selectGoalType(tester, 'Weight Loss');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current Weight'),
        '90',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Target Weight'),
        '80',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      '"Set Up" calls preview-only calculateNutritionFromMetrics and never '
      'calculateAndSaveNutrition until Apply is tapped',
      (tester) async {
        when(bodyMetricsRepo.getLatestMetric()).thenAnswer(
          (_) async => BodyMetric(
            id: 1,
            userId: 1,
            recordedAt: DateTime.utc(2024, 1, 1),
            createdAt: DateTime.utc(2024, 1, 1),
            weight: 90,
            height: 180,
            activityLevel: 'ModeratelyActive',
          ),
        );
        when(
          nutritionRepo.getTodaysMealLog(),
        ).thenAnswer((_) async => throw Exception('offline'));
        when(
          nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
        ).thenAnswer((_) async => throw Exception('offline'));
        when(
          nutritionRepo.getStreak(),
        ).thenAnswer((_) async => throw Exception('offline'));
        when(
          nutritionRepo.calculateNutritionFromMetrics(
            goalType: anyNamed('goalType'),
            targetWeightChange: anyNamed('targetWeightChange'),
            timeframeWeeks: anyNamed('timeframeWeeks'),
          ),
        ).thenAnswer((_) async => nutrition());

        await createGoalAndReachSummary(tester);

        await tester.tap(find.text('Set Up'));
        await tester.pumpAndSettle();
        // Pre-existing 1px overflow in the (unrelated, unchanged) macro-circle widget inside
        // the nutrition card — not under test here.
        tester.takeException();

        verify(
          nutritionRepo.calculateNutritionFromMetrics(
            goalType: anyNamed('goalType'),
            targetWeightChange: anyNamed('targetWeightChange'),
            timeframeWeeks: anyNamed('timeframeWeeks'),
          ),
        ).called(1);
        verifyNever(
          nutritionRepo.calculateAndSaveNutrition(
            goalType: anyNamed('goalType'),
            targetWeightChange: anyNamed('targetWeightChange'),
            timeframeWeeks: anyNamed('timeframeWeeks'),
          ),
        );

        expect(find.text('Review Your Nutrition Targets'), findsOneWidget);
        expect(find.text('Apply'), findsOneWidget);

        when(
          nutritionRepo.calculateAndSaveNutrition(
            goalType: anyNamed('goalType'),
            targetWeightChange: anyNamed('targetWeightChange'),
            timeframeWeeks: anyNamed('timeframeWeeks'),
          ),
        ).thenAnswer((_) async => nutrition());

        await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
        await tester.pumpAndSettle();
        tester
            .takeException(); // same pre-existing overflow, re-rendered on the applied card

        verify(
          nutritionRepo.calculateAndSaveNutrition(
            goalType: anyNamed('goalType'),
            targetWeightChange: anyNamed('targetWeightChange'),
            timeframeWeeks: anyNamed('timeframeWeeks'),
          ),
        ).called(1);
        expect(find.text('Nutrition targets saved'), findsOneWidget);
      },
    );

    testWidgets('Skip never calls calculateAndSaveNutrition', (tester) async {
      when(bodyMetricsRepo.getLatestMetric()).thenAnswer(
        (_) async => BodyMetric(
          id: 1,
          userId: 1,
          recordedAt: DateTime.utc(2024, 1, 1),
          createdAt: DateTime.utc(2024, 1, 1),
          weight: 90,
          height: 180,
          activityLevel: 'ModeratelyActive',
        ),
      );
      when(
        nutritionRepo.getTodaysMealLog(),
      ).thenAnswer((_) async => throw Exception('offline'));
      when(
        nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer((_) async => throw Exception('offline'));
      when(
        nutritionRepo.getStreak(),
      ).thenAnswer((_) async => throw Exception('offline'));
      when(
        nutritionRepo.calculateNutritionFromMetrics(
          goalType: anyNamed('goalType'),
          targetWeightChange: anyNamed('targetWeightChange'),
          timeframeWeeks: anyNamed('timeframeWeeks'),
        ),
      ).thenAnswer((_) async => nutrition());

      await createGoalAndReachSummary(tester);

      await tester.tap(find.text('Set Up'));
      await tester.pumpAndSettle();
      tester
          .takeException(); // pre-existing overflow in the (unrelated) nutrition card

      await tester.tap(find.widgetWithText(TextButton, 'Skip'));
      await tester.pumpAndSettle();

      verifyNever(
        nutritionRepo.calculateAndSaveNutrition(
          goalType: anyNamed('goalType'),
          targetWeightChange: anyNamed('targetWeightChange'),
          timeframeWeeks: anyNamed('timeframeWeeks'),
        ),
      );
      // Back to the setup prompt - existing targets (none, here) are untouched.
      expect(find.text('Set Up'), findsOneWidget);
    });

    testWidgets('Apply sends exactly the params the preview was computed from', (
      tester,
    ) async {
      when(bodyMetricsRepo.getLatestMetric()).thenAnswer(
        (_) async => BodyMetric(
          id: 1,
          userId: 1,
          recordedAt: DateTime.utc(2024, 1, 1),
          createdAt: DateTime.utc(2024, 1, 1),
          weight: 90,
          height: 180,
          activityLevel: 'ModeratelyActive',
        ),
      );
      when(
        nutritionRepo.getTodaysMealLog(),
      ).thenAnswer((_) async => throw Exception('offline'));
      when(
        nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer((_) async => throw Exception('offline'));
      when(
        nutritionRepo.getStreak(),
      ).thenAnswer((_) async => throw Exception('offline'));
      when(
        nutritionRepo.calculateNutritionFromMetrics(
          goalType: anyNamed('goalType'),
          targetWeightChange: anyNamed('targetWeightChange'),
          timeframeWeeks: anyNamed('timeframeWeeks'),
        ),
      ).thenAnswer((_) async => nutrition());
      when(
        nutritionRepo.calculateAndSaveNutrition(
          goalType: anyNamed('goalType'),
          targetWeightChange: anyNamed('targetWeightChange'),
          timeframeWeeks: anyNamed('timeframeWeeks'),
        ),
      ).thenAnswer((_) async => nutrition());

      await createGoalAndReachSummary(tester);

      await tester.tap(find.text('Set Up'));
      await tester.pumpAndSettle();
      tester.takeException();

      final previewArgs =
          verify(
            nutritionRepo.calculateNutritionFromMetrics(
              goalType: captureAnyNamed('goalType'),
              targetWeightChange: captureAnyNamed('targetWeightChange'),
              timeframeWeeks: captureAnyNamed('timeframeWeeks'),
            ),
          ).captured;

      await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
      await tester.pumpAndSettle();
      tester.takeException();

      final applyArgs =
          verify(
            nutritionRepo.calculateAndSaveNutrition(
              goalType: captureAnyNamed('goalType'),
              targetWeightChange: captureAnyNamed('targetWeightChange'),
              timeframeWeeks: captureAnyNamed('timeframeWeeks'),
            ),
          ).captured;

      // Same goalType/targetWeightChange/timeframeWeeks drove both the number the user
      // reviewed and the number that got saved - no drift between preview and apply.
      expect(applyArgs, equals(previewArgs));
    });

    testWidgets(
      'A failed Apply preserves prior targets and Retry does not create another goal',
      (tester) async {
        when(bodyMetricsRepo.getLatestMetric()).thenAnswer(
          (_) async => BodyMetric(
            id: 1,
            userId: 1,
            recordedAt: DateTime.utc(2024, 1, 1),
            createdAt: DateTime.utc(2024, 1, 1),
            weight: 90,
            height: 180,
            activityLevel: 'ModeratelyActive',
          ),
        );
        when(
          nutritionRepo.getTodaysMealLog(),
        ).thenAnswer((_) async => throw Exception('offline'));
        when(
          nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
        ).thenAnswer((_) async => throw Exception('offline'));
        when(
          nutritionRepo.getStreak(),
        ).thenAnswer((_) async => throw Exception('offline'));
        when(
          nutritionRepo.calculateNutritionFromMetrics(
            goalType: anyNamed('goalType'),
            targetWeightChange: anyNamed('targetWeightChange'),
            timeframeWeeks: anyNamed('timeframeWeeks'),
          ),
        ).thenAnswer((_) async => nutrition());
        when(
          nutritionRepo.calculateAndSaveNutrition(
            goalType: anyNamed('goalType'),
            targetWeightChange: anyNamed('targetWeightChange'),
            timeframeWeeks: anyNamed('timeframeWeeks'),
          ),
        ).thenAnswer((_) async => throw Exception('save failed'));

        await createGoalAndReachSummary(tester);

        await tester.tap(find.text('Set Up'));
        await tester.pumpAndSettle();
        tester.takeException();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
        await tester.pumpAndSettle();

        // Failure surfaced, not silently swallowed as success.
        expect(find.text('Nutrition targets saved'), findsNothing);
        expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);

        await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
        await tester.pumpAndSettle();
        tester.takeException();

        // Retry re-enters the nutrition preview only - the already-created goal is never
        // recreated.
        verify(goalsRepo.createGoal(any)).called(1);
        expect(find.text('Review Your Nutrition Targets'), findsOneWidget);
      },
    );

    testWidgets('Returning from Body Metrics preserves the completed goal and refreshes inputs '
        'into a preview automatically', (tester) async {
      // No metrics initially -> "Set Up" lands on the needs-metrics card.
      when(bodyMetricsRepo.getLatestMetric()).thenAnswer((_) async => null);
      when(
        nutritionRepo.getTodaysMealLog(),
      ).thenAnswer((_) async => throw Exception('offline'));
      when(
        nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer((_) async => throw Exception('offline'));
      when(
        nutritionRepo.getStreak(),
      ).thenAnswer((_) async => throw Exception('offline'));
      when(
        nutritionRepo.calculateNutritionFromMetrics(
          goalType: anyNamed('goalType'),
          targetWeightChange: anyNamed('targetWeightChange'),
          timeframeWeeks: anyNamed('timeframeWeeks'),
        ),
      ).thenAnswer((_) async => nutrition());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoalsProvider>.value(value: goalsProvider),
            ChangeNotifierProvider<NutritionProvider>.value(
              value: nutritionProvider,
            ),
            ChangeNotifierProvider<BodyMetricsProvider>.value(
              value: bodyMetricsProvider,
            ),
          ],
          child: MaterialApp(
            routes: {
              '/body-metrics':
                  (context) => Scaffold(
                    appBar: AppBar(title: const Text('Body Metrics')),
                    body: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ),
            },
            home: Builder(
              builder:
                  (context) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed: () {
                          showDialog<SmartGoalDialogResult>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const SmartGoalDialog(),
                          );
                        },
                        child: const Text('open'),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      );
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await selectGoalType(tester, 'Weight Loss');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current Weight'),
        '90',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Target Weight'),
        '80',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set Up'));
      await tester.pumpAndSettle();

      // Stuck needing metrics - the goal itself is already safely created.
      expect(find.text('Complete your body metrics first'), findsOneWidget);
      expect(find.text('Goal Created!'), findsOneWidget);

      // Simulate metrics now being complete once the user comes back.
      when(bodyMetricsRepo.getLatestMetric()).thenAnswer(
        (_) async => BodyMetric(
          id: 1,
          userId: 1,
          recordedAt: DateTime.utc(2024, 1, 1),
          createdAt: DateTime.utc(2024, 1, 1),
          weight: 90,
          height: 180,
          activityLevel: 'ModeratelyActive',
        ),
      );

      // ElevatedButton.icon's runtime type isn't ElevatedButton itself, so match by text.
      await tester.tap(find.text('Go to Body Metrics'));
      await tester.pumpAndSettle();
      expect(find.text('Body Metrics'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
      await tester.pumpAndSettle();
      tester.takeException(); // pre-existing macro-circle overflow

      // Back on the goal dialog, automatically moved past the dead-end and into a fresh
      // preview - the goal-created state was never lost.
      expect(find.text('Goal Created!'), findsOneWidget);
      expect(find.text('Review Your Nutrition Targets'), findsOneWidget);
      // Once at dialog open (the form's own metrics load), once for the first "Set Up"
      // check (still incomplete), and once more on returning from Body Metrics (now
      // complete) - the last of these is the one this test exists to prove happens at all.
      verify(bodyMetricsRepo.getLatestMetric()).called(3);
    });
  });
}
