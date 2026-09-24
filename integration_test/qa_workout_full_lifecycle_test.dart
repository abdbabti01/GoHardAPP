// QA regression for BUG-11: starting, adding an exercise mid-workout, and
// finishing must all still converge on the server - i.e. the in_progress ->
// completed bridge (see qa_workout_finish_without_start_test.dart) is not
// disturbed by an intervening operation. Exercise persistence itself is
// covered separately and more precisely by qa_workout_lifecycle_test.dart
// (BUG-5), so this does not re-assert it.
// QA backend only:
//   flutter test integration_test/qa_workout_full_lifecycle_test.dart \
//     -d <device> --dart-define=API_HOST=http://10.0.2.2:5121
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:go_hard_app/ui/widgets/exercises/exercise_card.dart';

import 'qa_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'full lifecycle: start, add exercise, finish - all converge on the '
    'server',
    (tester) async {
      final email = await launchAndSignUp(tester, 'wsyncfull');
      await startWorkoutFromDashboard(tester);
      await startWorkoutTimer(tester);
      // Let the timer card's switch to its running layout fully settle
      // before tapping - otherwise the tap can land mid-transition.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Once running, both the AppBar and the empty-state action render
      // "Add Exercise" - use .first for the empty-state one.
      await tester.ensureVisible(find.text('Add Exercise').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Add Exercise').first, warnIfMissed: false);
      await pumpUntilFound(tester, find.byType(ExerciseCard));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(ExerciseCard).first);
      await tester.pump(const Duration(milliseconds: 300));
      final addFab = find.byWidgetPredicate(
        (w) =>
            w is Text && w.data != null && RegExp(r'^Add \d').hasMatch(w.data!),
      );
      await pumpUntilFound(
        tester,
        addFab,
        timeout: const Duration(seconds: 10),
      );
      await tester.pump(const Duration(milliseconds: 400)); // FAB entrance anim
      await tester.tap(addFab);
      await pumpUntilFound(tester, find.text('Tap to log sets'));
      // Return from the exercise picker to the active workout screen.
      await tester.pump(const Duration(milliseconds: 400));

      final dio = Dio(BaseOptions(baseUrl: qaApiBase));
      final login = await dio.post(
        '/auth/login',
        data: {'email': email, 'password': qaPassword},
      );
      final auth = Options(
        headers: {'Authorization': 'Bearer ${login.data['token']}'},
      );

      final started = await pollForSessionStatus(
        tester,
        dio,
        auth,
        'in_progress',
      );
      expect(started?['status'], 'in_progress');

      await tester.tap(find.text('Finish'));
      await pumpUntilFound(tester, find.text('Keep Going'));
      await tester.tap(find.text('Finish').last);
      await tester.pump(const Duration(seconds: 1));

      final finished = await pollForSessionStatus(
        tester,
        dio,
        auth,
        'completed',
      );
      expect(finished?['status'], 'completed');
      expect(finished!['startedAt'], isNotNull);
      expect(finished['completedAt'], isNotNull);
    },
  );
}
