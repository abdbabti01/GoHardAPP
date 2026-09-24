// Shared helpers for the QA integration tests. All of them target the
// isolated QA backend only (--dart-define=API_HOST=http://10.0.2.2:5121).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_hard_app/main.dart' as app;
import 'package:go_hard_app/ui/screens/auth/signup_screen.dart';
import 'package:go_hard_app/ui/widgets/common/curved_navigation_bar.dart';

const qaApiBase = 'http://10.0.2.2:5121/api/v1';
const qaPassword = 'TestPass123';

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

/// Launches the app on a clean install, skips onboarding and signs up a new
/// unique user. Returns that user's email. Ends on the Today dashboard.
Future<String> launchAndSignUp(WidgetTester tester, String prefix) async {
  final unique = DateTime.now().millisecondsSinceEpoch;
  final email = 'qa-$prefix-$unique@test.local';

  app.main();
  await pumpUntilFound(tester, find.text('Skip'));
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
  await tester.enterText(fields.at(0), 'QA $prefix');
  await tester.enterText(fields.at(1), 'qa$prefix$unique');
  await tester.enterText(fields.at(2), email);
  await tester.enterText(fields.at(3), qaPassword);
  await tester.enterText(fields.at(4), qaPassword);
  await tester.pump();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
  await pumpUntilFound(
    tester,
    find.text("Today's Workouts"),
    timeout: const Duration(seconds: 25),
  );
  return email;
}

/// From the Today dashboard: Quick Actions -> Start Workout -> first workout
/// type -> confirm. Ends on ActiveWorkoutScreen with a freshly created DRAFT
/// session - the session does not become `in_progress` (locally or on the
/// server) until [startWorkoutTimer] taps the screen's own "Start Workout"
/// control (see ActiveWorkoutScreen._buildControlButton). Most callers that
/// only need to add/log exercises can stop here; callers that need the
/// session actually running (status/startedAt, on the server too) must call
/// [startWorkoutTimer] as well.
Future<void> startWorkoutFromDashboard(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(CurvedNavigationBar),
      matching: find.byIcon(Icons.add_rounded),
    ),
  );
  await pumpUntilFound(tester, find.text('Start Workout'));
  await tester.tap(find.text('Start Workout'));
  await pumpUntilFound(tester, find.text('Choose Workout Type'));
  await tester.tap(find.byType(RadioListTile<String>).first);
  await tester.pump();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Start Workout'));
  await pumpUntilFound(
    tester,
    find.text('Add Exercise'),
    timeout: const Duration(seconds: 20),
  );
  expect(find.text('Add Exercise'), findsOneWidget);
}

/// From ActiveWorkoutScreen with a DRAFT session (i.e. right after
/// [startWorkoutFromDashboard]): taps the screen's own "Start Workout"
/// control, which is the ONLY thing that transitions the session to
/// `in_progress` (sets `startedAt`, flips `isDraft` false). This is the sole
/// occurrence of the text "Start Workout" on this screen.
Future<void> startWorkoutTimer(WidgetTester tester) async {
  // The timer card (and its Start Workout control) is wrapped in a staggered
  // entrance FadeSlideAnimation and is not present in the tree immediately
  // after ActiveWorkoutScreen builds.
  await pumpUntilFound(
    tester,
    find.text('Start Workout'),
    timeout: const Duration(seconds: 10),
  );
  await tester.tap(find.text('Start Workout'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Polls `GET /sessions` (this account's most-recent-first list) until its
/// first entry reaches [wantedStatus] or [timeout] elapses, returning
/// whatever the last poll saw either way - callers assert on the result.
Future<Map<String, dynamic>?> pollForSessionStatus(
  WidgetTester tester,
  Dio dio,
  Options auth,
  String wantedStatus, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  Map<String, dynamic>? session;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final list = await dio.get('/sessions', options: auth);
    final sessions = (list.data as List).cast<Map<String, dynamic>>();
    session = sessions.isEmpty ? null : sessions.first;
    if (session != null && session['status'] == wantedStatus) break;
    await tester.pump(const Duration(seconds: 2));
  }
  return session;
}
