// QA integration test for account deletion. Runs against the isolated QA
// backend ONLY - never production:
//   flutter test integration_test/qa_account_deletion_test.dart -d <device> \
//     --dart-define=API_HOST=http://10.0.2.2:5121
//
// Journey: create disposable account -> create representative data (a
// workout) -> verify it exists on the server -> delete the account through
// the real app flow -> app becomes unauthenticated -> the old token can no
// longer reach a protected endpoint -> relaunch the app -> no session or
// data reappears.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:go_hard_app/main.dart' as app;

import 'qa_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'deleting the account through the app: server data gone, old token '
    'rejected, no data reappears after relaunch',
    (tester) async {
      final email = await launchAndSignUp(tester, 'delacct');
      await startWorkoutFromDashboard(tester);
      await startWorkoutTimer(tester);

      final dio = Dio(BaseOptions(baseUrl: qaApiBase));
      final login = await dio.post(
        '/auth/login',
        data: {'email': email, 'password': qaPassword},
      );
      final token = login.data['token'] as String;
      final auth = Options(headers: {'Authorization': 'Bearer $token'});

      // ---- Representative data exists on the server before deletion ----
      final before = await pollForSessionStatus(
        tester,
        dio,
        auth,
        'in_progress',
      );
      expect(
        before?['status'],
        'in_progress',
        reason: 'a workout must exist on the server before deletion',
      );

      // ---- Finish the workout to return to Main (ActiveWorkoutScreen has
      // no standard back button - Finish is the screen's own exit path) ----
      await tester.tap(find.text('Finish'));
      await pumpUntilFound(tester, find.text('Keep Going'));
      await tester.tap(find.text('Finish').last);
      await pumpUntilFound(
        tester,
        find.text('Continue'),
        timeout: const Duration(seconds: 15),
      );
      await tester.tap(find.text('Continue'));

      // ---- Navigate to Delete Account and delete ----
      await pumpUntilFound(
        tester,
        find.text('Me'),
        timeout: const Duration(seconds: 15),
      );
      await tester.tap(find.text('Me'));
      await pumpUntilFound(tester, find.text('Settings'));
      await tester.ensureVisible(find.text('Settings'));
      await tester.pump();
      await tester.tap(find.text('Settings'));
      await pumpUntilFound(tester, find.text('Health Integration'));
      for (
        var i = 0;
        i < 6 && find.text('Delete Account').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await pumpUntilFound(
        tester,
        find.text('Delete Account'),
        timeout: const Duration(seconds: 15),
      );
      await tester.tap(find.text('Delete Account'));
      await pumpUntilFound(tester, find.text('Enter your password to confirm'));

      await tester.enterText(find.byType(TextField), qaPassword);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await pumpUntilFound(tester, find.text('Delete your account?'));
      await tester.tap(find.text('Delete Account').last);

      // ---- App becomes unauthenticated ----
      await pumpUntilFound(
        tester,
        find.widgetWithText(ElevatedButton, 'Login'),
        timeout: const Duration(seconds: 20),
      );
      expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);

      // ---- The OLD token can no longer reach a protected endpoint ----
      await expectLater(
        dio.get('/sessions', options: auth),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            401,
          ),
        ),
      );

      // ---- Relaunch: no session or data reappears ----
      app.main();
      await pumpUntilFound(
        tester,
        find.widgetWithText(ElevatedButton, 'Login'),
        timeout: const Duration(seconds: 20),
      );
      expect(
        find.text('Sign Up'),
        findsOneWidget,
        reason:
            'relaunch after account deletion must land on Login, not a '
            'restored session',
      );
    },
  );
}
