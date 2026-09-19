import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/daily_nutrition_progress.dart';
import 'package:go_hard_app/data/models/meal_log.dart';
import 'package:go_hard_app/data/models/nutrition_goal.dart';
import 'package:go_hard_app/data/models/nutrition_summary.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';
import 'package:go_hard_app/ui/screens/nutrition/nutrition_goals_screen.dart';

@GenerateMocks([NutritionRepository, ConnectivityService])
import 'nutrition_goals_screen_test.mocks.dart';

/// Rendered/interaction coverage for NutritionGoalsScreen's persistent
/// Save button (a `bottomNavigationBar`, deliberately kept outside the
/// scrollable form body so it survives scrolling and is never obscured by
/// the keyboard - Scaffold's default `resizeToAvoidBottomInset` handles
/// the keyboard-inset side of that automatically), and its scrollable
/// form body.
void main() {
  late MockNutritionRepository repo;
  late MockConnectivityService connectivity;
  late UserSessionEpoch epoch;
  late NutritionProvider provider;

  setUp(() {
    repo = MockNutritionRepository();
    connectivity = MockConnectivityService();
    epoch = UserSessionEpoch()..activate(1);
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => const Stream<bool>.empty());
    provider = NutritionProvider(repo, epoch, connectivity);
  });

  Future<void> pumpScreen(WidgetTester tester, {NutritionGoal? goal}) async {
    when(repo.getTodaysMealLog(date: anyNamed('date'))).thenAnswer(
      (_) async => MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );
    when(repo.getNutritionDashboard(date: anyNamed('date'))).thenAnswer(
      (_) async => NutritionDashboardData(
        date: DateTime.now(),
        goal: goal,
        progress: DailyNutritionProgress(
          id: 0,
          userId: 1,
          date: DateTime.now(),
          createdAt: DateTime.now(),
        ),
      ),
    );
    when(
      repo.getStreak(),
    ).thenAnswer((_) async => StreakInfo(currentStreak: 0, longestStreak: 0));
    await provider.loadTodaysData();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NutritionProvider>.value(value: provider),
          ChangeNotifierProvider<ConnectivityService>.value(
            value: connectivity,
          ),
        ],
        child: const MaterialApp(home: NutritionGoalsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the Save Goals button lives in bottomNavigationBar (persistent, '
      'outside the scrollable form body) and stays tappable after scrolling '
      'the form', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(Scaffold), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.bottomNavigationBar,
      isNotNull,
      reason:
          'Save Goals must be a persistent bottomNavigationBar, not '
          'part of the scrollable form body.',
    );
    expect(find.text('Save Goals'), findsOneWidget);

    // Scroll the form body downward and confirm the Save button is
    // still present and tappable - it lives outside the scroll view
    // entirely, so this should never dislodge it.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save Goals'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Save Goals'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
    'the Save Goals button disables and shows a spinner while a save is '
    'in flight',
    (tester) async {
      await pumpScreen(tester);

      final gate = Completer<NutritionGoal>();
      when(repo.createNutritionGoal(any)).thenAnswer((_) => gate.future);

      // Fill required fields so form validation passes.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Daily Calories'),
        '2200',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Daily Protein'),
        '150',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Daily Carbohydrates'),
        '250',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Daily Fat'),
        '70',
      );

      await tester.tap(find.text('Save Goals'));
      await tester.pump();

      // Now in flight: the button must be disabled and show a spinner
      // rather than accepting a second tap.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);

      gate.complete(
        NutritionGoal(
          id: 1,
          userId: 1,
          dailyCalories: 2200,
          dailyProtein: 150,
          dailyCarbohydrates: 250,
          dailyFat: 70,
          isActive: true,
          createdAt: DateTime.now(),
        ),
      );
      // A bounded pump, not pumpAndSettle: this screen is the test's sole
      // route, so Navigator.pop(context) is a no-op and the SnackBar's own
      // ~4s auto-dismiss timer would otherwise fully elapse under
      // pumpAndSettle before this assertion ever runs.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Goals saved successfully!'), findsOneWidget);
    },
  );

  testWidgets(
    'the form body scrolls independently of the persistent Save button',
    (tester) async {
      await pumpScreen(tester);

      final scrollable = find.byType(SingleChildScrollView);
      expect(scrollable, findsOneWidget);

      final before = tester.getTopLeft(
        find.text(
          'Calculate from your body '
          'metrics',
        ),
      );
      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(
        find.text(
          'Calculate from your body '
          'metrics',
        ),
      );

      expect(
        after.dy,
        lessThan(before.dy),
        reason: 'The form content should have scrolled upward.',
      );
      // The Save button's own position is unaffected by scrolling the form.
      expect(find.text('Save Goals'), findsOneWidget);
    },
  );
}
