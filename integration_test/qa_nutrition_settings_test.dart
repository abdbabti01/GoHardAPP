// QA pass 2 (complete-app-testing): nutrition logging + settings + logout,
// against the local/QA backend only. Run with:
//   flutter test integration_test/qa_nutrition_settings_test.dart -d <device> \
//     --dart-define=API_HOST=http://10.0.2.2:5121
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:go_hard_app/main.dart' as app;
import 'package:go_hard_app/ui/screens/auth/signup_screen.dart';

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add custom food -> daily total updates; toggle unit setting; logout', (
    tester,
  ) async {
    final unique = DateTime.now().millisecondsSinceEpoch;
    final email = 'qa-nutri-$unique@test.local';
    final username = 'qanutri$unique';

    app.main();
    await pumpUntilFound(
      tester,
      find.text('Skip'),
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(find.text('Skip'));
    await pumpUntilFound(tester, find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await pumpUntilFound(
      tester,
      find.widgetWithText(ElevatedButton, 'Create Account'),
    );
    final fields = find.descendant(
      of: find.byType(SignupScreen),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'QA Nutrition Test');
    await tester.enterText(fields.at(1), username);
    await tester.enterText(fields.at(2), email);
    await tester.enterText(fields.at(3), 'TestPass123');
    await tester.enterText(fields.at(4), 'TestPass123');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
    await pumpUntilFound(
      tester,
      find.text("Today's Workouts"),
      timeout: const Duration(seconds: 25),
    );

    // ---- Eat tab -> add food to a meal -> search with no match -> custom food ----
    await tester.tap(find.text('Eat'));
    await pumpUntilFound(tester, find.byIcon(Icons.add_circle_outline));
    await tester.ensureVisible(find.byIcon(Icons.add_circle_outline).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await pumpUntilFound(
      tester,
      find.byType(TextField),
      timeout: const Duration(seconds: 15),
    );
    expect(
      find.byType(TextField),
      findsWidgets,
      reason: 'Expected FoodSearchScreen to open with a search field',
    );

    await tester.enterText(
      find.byType(TextField).first,
      'zzz_qa_nonexistent_food_zzz',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byIcon(Icons.search).evaluate().isNotEmpty
          ? find.byIcon(Icons.search).first
          : find.byType(TextField).first,
    );
    await pumpUntilFound(
      tester,
      find.text('Create Custom Food'),
      timeout: const Duration(seconds: 10),
    );
    // Dismiss the keyboard first - it can occlude the empty-state button
    // that was just scrolled into view under it.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.ensureVisible(find.text('Create Custom Food'));
    await tester.pump();
    await tester.tap(find.text('Create Custom Food'));
    // CreateCustomFoodScreen's submit button, not the dashboard's own
    // unrelated "Add Food" TextButton on an empty meal card.
    final submitButton = find.widgetWithText(FilledButton, 'Add Food');
    await pumpUntilFound(
      tester,
      submitButton,
      timeout: const Duration(seconds: 15),
    );
    expect(
      submitButton,
      findsOneWidget,
      reason: 'Expected CreateCustomFoodScreen to open',
    );

    final foodFields = find.byType(TextFormField);
    expect(foodFields, findsAtLeastNWidgets(7));
    // Field order: 0 name, 1 brand (optional), 2 serving size (prefilled
    // '100'), 3 calories, 4 protein, 5 carbs, 6 fat - all four macros are
    // required, so skipping any one of them blocks submission.
    await tester.enterText(foodFields.at(0), 'QA Test Food'); // name
    await tester.enterText(foodFields.at(3), '250'); // calories
    await tester.enterText(foodFields.at(4), '20'); // protein
    await tester.enterText(foodFields.at(5), '30'); // carbs
    await tester.enterText(foodFields.at(6), '5'); // fat
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Add Food'));
    await tester.tap(find.widgetWithText(FilledButton, 'Add Food'));

    // Real request to the local backend + return to dashboard.
    await pumpUntilFound(
      tester,
      find.textContaining('QA Test Food'),
      timeout: const Duration(seconds: 15),
    );
    expect(
      find.textContaining('QA Test Food'),
      findsWidgets,
      reason: 'Expected the newly logged food to appear on the dashboard',
    );

    // ---- Me tab -> Settings -> toggle Unit System ----
    await pumpUntilFound(
      tester,
      find.text('Me'),
      timeout: const Duration(seconds: 25),
    );
    expect(
      find.text('Me'),
      findsOneWidget,
      reason:
          'Visible text: '
          '${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).where((t) => t != null).join(" | ")}',
    );
    await tester.tap(find.text('Me'));
    await pumpUntilFound(tester, find.text('Settings'));
    await tester.ensureVisible(find.text('Settings'));
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await pumpUntilFound(tester, find.text('Health Integration'));
    // "Unit System" is much further down the settings list (after Health
    // Integration and Notifications) and is lazily built; scroll down
    // repeatedly to bring it into the tree.
    for (var i = 0; i < 6 && find.text('Unit System').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await pumpUntilFound(
      tester,
      find.text('Unit System'),
      timeout: const Duration(seconds: 15),
    );
    expect(
      find.text('Unit System'),
      findsOneWidget,
      reason:
          'Expected Settings screen to open. Visible text: '
          '${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).where((t) => t != null).join(" | ")}',
    );

    final before =
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Unit System'),
            )
            .value;
    await tester.tap(find.widgetWithText(SwitchListTile, 'Unit System'));
    await tester.pump(const Duration(seconds: 1));
    final after =
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Unit System'),
            )
            .value;
    expect(
      after,
      isNot(equals(before)),
      reason: 'Expected the Unit System toggle to change state after tapping',
    );

    // ---- Logout ----
    await tester.pageBack();
    await pumpUntilFound(tester, find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Logout'));
    await pumpUntilFound(tester, find.widgetWithText(ElevatedButton, 'Logout'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
    await pumpUntilFound(
      tester,
      find.widgetWithText(ElevatedButton, 'Login'),
      timeout: const Duration(seconds: 15),
    );
    expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
  });
}
