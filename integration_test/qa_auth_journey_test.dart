// QA pass 2 (complete-app-testing): authentication journey against the
// local/QA backend only (see api_config.dart's API_HOST dart-define).
// Run with:
//   flutter test integration_test/qa_auth_journey_test.dart -d <device> \
//     --dart-define=API_HOST=http://10.0.2.2:5121
// Covers: signup -> logout -> login with wrong password (error shown, stays
// on Login) -> login with correct password (session restored).
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
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signup -> logout -> invalid login -> valid login', (
    tester,
  ) async {
    final unique = DateTime.now().millisecondsSinceEpoch;
    final email = 'qa-auth-$unique@test.local';
    final username = 'qaauth$unique';
    const password = 'TestPass123';

    app.main();
    await pumpUntilFound(
      tester,
      find.text('Skip'),
      timeout: const Duration(seconds: 20),
    );

    // Onboarding -> signup.
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
    expect(fields, findsNWidgets(5));
    await tester.enterText(fields.at(0), 'QA Auth Test');
    await tester.enterText(fields.at(1), username);
    await tester.enterText(fields.at(2), email);
    await tester.enterText(fields.at(3), password);
    await tester.enterText(fields.at(4), password);
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));

    await pumpUntilFound(
      tester,
      find.text("Today's Workouts"),
      timeout: const Duration(seconds: 25),
    );
    expect(find.text("Today's Workouts"), findsOneWidget, reason: 'signup');

    // ---- Logout ----
    // Me tab is index 3 on the curved nav bar.
    await tester.tap(find.text('Me'));
    await pumpUntilFound(tester, find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Logout'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Logout'));
    await pumpUntilFound(
      tester,
      find.widgetWithText(ElevatedButton, 'Logout'),
    ); // confirm dialog
    await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));

    await pumpUntilFound(
      tester,
      find.widgetWithText(ElevatedButton, 'Login'),
      timeout: const Duration(seconds: 15),
    );
    expect(
      find.widgetWithText(ElevatedButton, 'Login'),
      findsOneWidget,
      reason: 'Expected to land back on Login screen after logout',
    );

    // ---- Invalid credentials ----
    final loginFields = find.byType(TextFormField);
    expect(loginFields, findsNWidgets(2));
    await tester.enterText(loginFields.at(0), email);
    await tester.enterText(loginFields.at(1), 'WrongPassword999');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));

    // Wait for the request to fail and an error message to render, rather
    // than a fixed sleep - poll for the error banner's icon.
    await pumpUntilFound(
      tester,
      find.byIcon(Icons.error_outline),
      timeout: const Duration(seconds: 15),
    );
    expect(
      find.byIcon(Icons.error_outline),
      findsOneWidget,
      reason: 'Expected an error message for invalid credentials',
    );
    expect(
      find.widgetWithText(ElevatedButton, 'Login'),
      findsOneWidget,
      reason: 'Invalid login must not navigate away from Login screen',
    );

    // ---- Valid login ----
    await tester.enterText(loginFields.at(1), password);
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));

    // Heavy background sync after login (meal logs, sessions, programs) can
    // delay the dashboard's own content rendering, so check for MainScreen
    // itself (its bottom nav) rather than a specific piece of its content.
    await pumpUntilFound(
      tester,
      find.byType(CurvedNavigationBar),
      timeout: const Duration(seconds: 30),
    );
    expect(
      find.byType(CurvedNavigationBar),
      findsOneWidget,
      reason:
          'Expected valid login to restore the session and reach MainScreen',
    );
  });
}
