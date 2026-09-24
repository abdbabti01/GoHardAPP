// QA regression for BUG-11: ActiveWorkoutScreen's AppBar "Finish" action is
// reachable on a still-draft session (unlike the mutually-exclusive
// Start/Pause/Resume control, it is never gated on the session having
// actually started). The server's SessionStatus.IsValidTransition correctly
// rejects a direct draft -> completed PATCH, so the client must bridge
// through in_progress first - see SessionRepository.updateSessionStatus's
// `needsBridgeThroughInProgress`.
// QA backend only:
//   flutter test integration_test/qa_workout_finish_without_start_test.dart \
//     -d <device> --dart-define=API_HOST=http://10.0.2.2:5121
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'qa_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a workout finished WITHOUT ever tapping Start still converges to '
    'completed on the server',
    (tester) async {
      final email = await launchAndSignUp(tester, 'wsyncnostart');
      await startWorkoutFromDashboard(tester);
      // Deliberately do NOT tap the in-screen Start Workout control - Finish
      // is reachable directly from the AppBar regardless of draft state.
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Finish').first);
      await pumpUntilFound(tester, find.text('Keep Going'));
      await tester.tap(find.text('Finish').last);
      await tester.pump(const Duration(seconds: 1));

      final dio = Dio(BaseOptions(baseUrl: qaApiBase));
      final login = await dio.post(
        '/auth/login',
        data: {'email': email, 'password': qaPassword},
      );
      final auth = Options(
        headers: {'Authorization': 'Bearer ${login.data['token']}'},
      );

      final session = await pollForSessionStatus(
        tester,
        dio,
        auth,
        'completed',
      );
      expect(
        session?['status'],
        'completed',
        reason:
            'BUG-11: server session never left '
            '"${session?['status']}" after Finish',
      );
      expect(session!['startedAt'], isNotNull);
      expect(session['completedAt'], isNotNull);
    },
  );
}
