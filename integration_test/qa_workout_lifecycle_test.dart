// QA regression for BUG-5 (added exercise not shown in the active workout).
// Runs against the isolated QA backend only:
//   flutter test integration_test/qa_workout_lifecycle_test.dart -d <device> \
//     --dart-define=API_HOST=http://10.0.2.2:5121
// Journey: start workout -> add exercise -> exercise is listed -> it is
// persisted on the server exactly once -> log a set -> finish -> leave.
// (Server-side start/finish/set sync is covered separately by
// qa_workout_sync_test.dart, which documents BUG-11.)
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:go_hard_app/ui/widgets/exercises/exercise_card.dart';

import 'qa_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add exercise is listed and persisted once; log set; finish', (
    tester,
  ) async {
    final email = await launchAndSignUp(tester, 'workout');
    await startWorkoutFromDashboard(tester);

    // ---- Add an exercise from the seeded library ----
    await tester.tap(find.text('Add Exercise'));
    await pumpUntilFound(tester, find.byType(ExerciseCard));
    expect(find.byType(ExerciseCard), findsWidgets);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(ExerciseCard).first);
    await tester.pump(const Duration(milliseconds: 300));
    final addFab = find.byWidgetPredicate(
      (w) =>
          w is Text && w.data != null && RegExp(r'^Add \d').hasMatch(w.data!),
    );
    await pumpUntilFound(tester, addFab, timeout: const Duration(seconds: 10));
    expect(addFab, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400)); // FAB entrance anim
    await tester.tap(addFab);

    // ---- BUG-5: the added exercise must be listed on the workout screen ----
    await pumpUntilFound(
      tester,
      find.text('Tap to log sets'),
      timeout: const Duration(seconds: 20),
    );
    expect(
      find.text('No Exercises Yet'),
      findsNothing,
      reason: 'BUG-5: added exercise must appear in the active workout',
    );
    expect(find.text('Tap to log sets'), findsOneWidget);

    // ---- ...and persisted on the server exactly once ----
    final dio = Dio(BaseOptions(baseUrl: qaApiBase));
    final login = await dio.post(
      '/auth/login',
      data: {'email': email, 'password': qaPassword},
    );
    final auth = Options(
      headers: {'Authorization': 'Bearer ${login.data['token']}'},
    );
    var exerciseCount = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final list = await dio.get('/sessions', options: auth);
      final sessions = (list.data as List).cast<Map<String, dynamic>>();
      exerciseCount = sessions.fold<int>(
        0,
        (n, s) => n + (s['exercises'] as List).length,
      );
      if (exerciseCount >= 1) break;
      await tester.pump(const Duration(seconds: 2));
    }
    expect(exerciseCount, 1, reason: 'exercise persisted exactly once');

    // ---- Log a set, finish, leave ----
    await tester.pump(const Duration(milliseconds: 800)); // list item anim
    await tester.tap(find.text('Tap to log sets'));
    await pumpUntilFound(
      tester,
      find.widgetWithText(ElevatedButton, 'Add Set'),
      timeout: const Duration(seconds: 25),
    );
    final setFields = find.byType(TextField);
    expect(setFields, findsAtLeastNWidgets(2));
    await tester.enterText(setFields.at(0), '10'); // reps
    await tester.enterText(setFields.at(1), '50'); // weight
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Set'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pageBack();
    await pumpUntilFound(tester, find.text('Add Exercise'));

    await tester.tap(find.text('Finish'));
    await pumpUntilFound(tester, find.text('Keep Going'));
    await tester.tap(find.text('Finish').last);
    await pumpUntilFound(
      tester,
      find.text('Continue'),
      timeout: const Duration(seconds: 15),
    );
    await tester.tap(find.text('Continue'));

    final gone = DateTime.now().add(const Duration(seconds: 15));
    while (find.text('Add Exercise').evaluate().isNotEmpty &&
        DateTime.now().isBefore(gone)) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(
      find.text('Add Exercise'),
      findsNothing,
      reason: 'Expected to leave ActiveWorkoutScreen after finishing',
    );
  });
}
