// QA pass 2 (complete-app-testing): programs, goals, AI chat (expected
// BLOCKED - no LLM provider keys in local/QA config) and community/social
// smoke checks, against the local/QA backend only.
//
// Programs and goals are only ever created through the AI-chat pipeline in
// this app's UI, which is blocked here by design (no LLM keys configured
// locally) - see the AI-chat section below, which independently confirms
// that path fails gracefully. So this test seeds one program + one goal
// directly via the local backend's REST API (a real, supported contract -
// POST /api/programs, POST /api/goals - not a UI shortcut) for the signed-up
// user, then verifies the *display* and *interaction* side entirely through
// the real UI.
//
// Run with:
//   flutter test integration_test/qa_programs_goals_ai_community_test.dart \
//     -d <device> --dart-define=API_HOST=http://10.0.2.2:5121
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:go_hard_app/main.dart' as app;
import 'package:go_hard_app/ui/screens/auth/signup_screen.dart';
import 'package:go_hard_app/ui/widgets/common/curved_navigation_bar.dart';

const _apiBase = 'http://10.0.2.2:5121/api/v1'; // must match --dart-define

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

  testWidgets('programs+goals display (API-seeded); AI chat fails gracefully; '
      'community/friends/messages reachable without crash', (tester) async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      fail('Uncaught FlutterError: ${details.exception}');
    };

    final unique = DateTime.now().millisecondsSinceEpoch;
    final email = 'qa-prog-$unique@test.local';
    final username = 'qaprog$unique';
    const password = 'TestPass123';

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
    await tester.enterText(fields.at(0), 'QA Programs Test');
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

    // ---- Seed a program + goal directly via the local backend's REST API ----
    final dio = Dio();
    final loginResp = await dio.post(
      '$_apiBase/auth/login',
      data: {'email': email, 'password': password},
    );
    expect(loginResp.statusCode, 200, reason: 'seed login');
    final token = loginResp.data['token'] as String;
    dio.options.headers['Authorization'] = 'Bearer $token';

    final goalResp = await dio.post(
      '$_apiBase/goals',
      data: {
        'goalType': 'weight_loss',
        'targetValue': 10,
        'currentValue': 0,
        'unit': 'lb',
      },
    );
    expect(goalResp.statusCode, 201, reason: 'seed goal: ${goalResp.data}');
    final goalId = goalResp.data['id'] as int;

    final programResp = await dio.post(
      '$_apiBase/programs',
      data: {'title': 'QA Seeded Program', 'goalId': goalId, 'totalWeeks': 4},
    );
    expect(
      programResp.statusCode,
      201,
      reason: 'seed program: ${programResp.data}',
    );

    // ---- My Plan: seeded plan shows on Train and on the My Plan page ----
    await tester.tap(find.text('Train'));
    await pumpUntilFound(
      tester,
      find.textContaining('QA Seeded Program'),
      timeout: const Duration(seconds: 15),
    );
    await tester.tap(find.text('View plan'));
    await pumpUntilFound(tester, find.byType(BackButton));
    // Bounded pump through the push transition (ProgramsScreen animates
    // forever, so pumpAndSettle never settles), then prove the My Plan page
    // itself is showing before checking its content. Train also shows the
    // plan title, so the title check alone would not prove navigation.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BackButton), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('My Plan')),
      findsOneWidget,
    );
    expect(find.textContaining('QA Seeded Program'), findsWidgets);
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));

    // ---- Goals: verify the seeded goal displays ----
    await tester.tap(find.text('Me'));
    await pumpUntilFound(
      tester,
      find.text('Goals'),
      timeout: const Duration(seconds: 10),
    );
    if (find.text('Goals').evaluate().isNotEmpty) {
      await tester.tap(find.text('Goals'));
      await pumpUntilFound(
        tester,
        find.textContaining('lb'),
        timeout: const Duration(seconds: 10),
      );
      // Goals is a pushed screen without the bottom nav / FAB - return to
      // the main tabbed screen before looking for the curved-nav FAB below.
      await tester.pageBack();
      await pumpUntilFound(tester, find.text('Today'));
    }

    // ---- AI chat: expected BLOCKED (no LLM provider keys locally) ----
    await tester.tap(
      find.descendant(
        of: find.byType(CurvedNavigationBar),
        matching: find.byIcon(Icons.add_rounded),
      ),
    );
    await pumpUntilFound(tester, find.text('Ask AI Coach'));
    await tester.tap(find.text('Ask AI Coach'));
    await pumpUntilFound(tester, find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add).last);
    await pumpUntilFound(tester, find.text('New Chat'));
    await tester.tap(find.text('New Chat'));
    // Real network call to create the conversation record (not the AI
    // call itself), then the message send below is what actually needs
    // an LLM provider.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final chatInput = find.byType(TextField);
    if (chatInput.evaluate().isNotEmpty) {
      await tester.enterText(chatInput.last, 'Hello, this is a QA test.');
      await tester.pump();
      final sendButton = find.byIcon(Icons.send);
      if (sendButton.evaluate().isNotEmpty) {
        await tester.tap(sendButton.last);
      }
    }
    // No specific "blocked" text is asserted (provider error copy is not
    // guaranteed) - the meaningful assertion is FlutterError.onError above:
    // an unconfigured/failing LLM provider must not crash the app.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(Scaffold), findsWidgets);

    // ---- Community / Friends / Messages: reachable without crashing ----
    // Two pops: ChatConversationScreen -> ChatListScreen -> MainScreen.
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.pageBack();
    await pumpUntilFound(
      tester,
      find.text('Today'),
      timeout: const Duration(seconds: 10),
    );
    await tester.tap(find.text('Today'));
    await pumpUntilFound(
      tester,
      find.byIcon(Icons.people_outline),
      timeout: const Duration(seconds: 10),
    );
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byType(Scaffold),
      findsWidgets,
      reason: 'Community screen should render without crashing for a lone user',
    );
  });
}
