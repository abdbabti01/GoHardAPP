// QA pass (complete-app-testing skill): real-device journey against the
// production API using a disposable, uniquely-named throwaway account.
// Covers: onboarding skip -> signup -> start-workout -> add-exercise entry.
// This test intentionally creates one real account on the production
// backend (approved for this QA pass); no other users' data is touched.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:go_hard_app/main.dart' as app;
import 'package:go_hard_app/ui/screens/auth/signup_screen.dart';
import 'package:go_hard_app/ui/widgets/common/curved_navigation_bar.dart';

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
  // Final attempt so the caller's expect() gives a normal failure message.
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signup -> main screen -> start workout -> add exercise entry', (
    tester,
  ) async {
    final unique = DateTime.now().millisecondsSinceEpoch;
    final email = 'qa-test-$unique@example.com';
    final username = 'qatest$unique';

    app.main();
    await pumpUntilFound(tester, find.text('Skip'));

    // Onboarding: skip straight to auth gate.
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await pumpUntilFound(tester, find.text('Sign Up'));

    // Login screen -> Sign Up.
    await tester.tap(find.text('Sign Up'));
    await pumpUntilFound(
      tester,
      find.widgetWithText(ElevatedButton, 'Create Account'),
    );

    // Fill signup form. Scope to the Signup screen's own subtree: the
    // previous (Login) route stays mounted underneath in the Navigator
    // stack, so an unscoped find.byType(TextFormField) also picks up its
    // fields.
    final signupScreen = find.byType(SignupScreen);
    expect(signupScreen, findsOneWidget);
    final fields = find.descendant(
      of: signupScreen,
      matching: find.byType(TextFormField),
    );
    expect(fields, findsNWidgets(5));
    await tester.enterText(fields.at(0), 'QA Test User');
    await tester.enterText(fields.at(1), username);
    await tester.enterText(fields.at(2), email);
    await tester.enterText(fields.at(3), 'TestPass123');
    await tester.enterText(fields.at(4), 'TestPass123');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));

    // Real network call to production auth/signup - poll rather than
    // pumpAndSettle (the loading spinner animates continuously).
    await pumpUntilFound(
      tester,
      find.text("Today's Workouts"),
      timeout: const Duration(seconds: 25),
    );
    expect(
      find.text("Today's Workouts"),
      findsOneWidget,
      reason:
          'Expected to land on MainScreen (Today tab) after signup. '
          'AuthProvider error (if any): '
          '${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).where((t) => t != null).join(" | ")}',
    );

    // Open Quick Actions via the curved-nav FAB and start a workout now.
    await tester.tap(
      find.descendant(
        of: find.byType(CurvedNavigationBar),
        matching: find.byIcon(Icons.add_rounded),
      ),
    );
    await pumpUntilFound(tester, find.text('Start Workout'));
    await tester.tap(find.text('Start Workout'));
    await pumpUntilFound(tester, find.text('Choose Workout Type'));

    // Pick the first available workout name and confirm.
    final radios = find.byType(RadioListTile<String>);
    expect(radios, findsWidgets);
    await tester.tap(radios.first);
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Start Workout'));

    // Real network call to create the session.
    await pumpUntilFound(
      tester,
      find.text('Add Exercise'),
      timeout: const Duration(seconds: 20),
    );
    expect(
      find.text('Add Exercise'),
      findsOneWidget,
      reason: 'Expected ActiveWorkoutScreen with Add Exercise FAB visible',
    );
  });
}
