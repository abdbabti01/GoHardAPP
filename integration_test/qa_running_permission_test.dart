// QA pass 2 (complete-app-testing): running feature reachability and
// location-permission handling against the local/QA backend only. The
// emulator has no location permission granted by default, so this exercises
// the "permission unavailable" path. Run with:
//   flutter test integration_test/qa_running_permission_test.dart -d <device> \
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

  testWidgets('start run without location permission does not crash the app', (
    tester,
  ) async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      fail(
        'Uncaught FlutterError while exercising Start Run: ${details.exception}',
      );
    };

    final unique = DateTime.now().millisecondsSinceEpoch;
    final email = 'qa-run-$unique@test.local';
    final username = 'qarun$unique';

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
    await tester.enterText(fields.at(0), 'QA Run Test');
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

    await tester.tap(
      find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.add_rounded),
      warnIfMissed: false,
    );
    await pumpUntilFound(tester, find.text('Start Run'));
    await tester.tap(find.text('Start Run'));

    // Give the permission flow (and any resulting error state) time to
    // settle without pumpAndSettle, since a location-tracking screen may
    // have a continuously-animating map/timer widget.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }

    // The real assertion is FlutterError.onError above (no crash). As a
    // sanity floor, some Scaffold must still be rendered - i.e. we didn't
    // fall through to a blank/dead screen.
    expect(
      find.byType(Scaffold),
      findsWidgets,
      reason:
          'Expected the app to still be rendering *something* after '
          'attempting to start a run without location permission',
    );
  });
}
