// QA regression documenting BUG-11's explicit-Start path: starting a
// workout must sync in_progress + startedAt to the server. See
// qa_workout_finish_without_start_test.dart and
// qa_workout_full_lifecycle_test.dart for the other two BUG-11 scenarios
// (each its own file/process - see integration_test/README.md).
// QA backend only:
//   flutter test integration_test/qa_workout_sync_test.dart -d <device> \
//     --dart-define=API_HOST=http://10.0.2.2:5121
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'qa_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starting a workout syncs in_progress + startedAt to server', (
    tester,
  ) async {
    final email = await launchAndSignUp(tester, 'wsync');
    await startWorkoutFromDashboard(tester);
    await startWorkoutTimer(tester);

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
      'in_progress',
    );
    expect(session, isNotNull, reason: 'session must exist on the server');
    expect(
      session!['status'],
      'in_progress',
      reason: 'BUG-11: server session stayed "${session['status']}"',
    );
    expect(session['startedAt'], isNotNull);
  });
}
