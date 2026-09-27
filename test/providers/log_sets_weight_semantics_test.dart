import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/exercise_set.dart';
import 'package:go_hard_app/providers/log_sets_provider.dart';
import 'package:go_hard_app/ui/screens/exercises/log_sets_screen.dart';

import 'log_sets_provider_session_cleanup_test.mocks.dart';

/// Pins the interim (Phase 2A) Log Sets contract: entry is labelled lbs and the
/// typed number is persisted exactly as typed. No kg<->lb conversion happens on
/// the write path; changing that is a storage-semantics decision, not a copy fix.
void main() {
  late MockExerciseRepository repo;
  late UserSessionEpoch epoch;
  late LogSetsProvider provider;

  setUp(() {
    repo = MockExerciseRepository();
    when(repo.getExerciseSets(any)).thenAnswer((_) async => <ExerciseSet>[]);
    when(
      repo.createExerciseSet(any),
    ).thenAnswer((inv) async => inv.positionalArguments.first as ExerciseSet);
    epoch = UserSessionEpoch()..activate(1);
    provider = LogSetsProvider(repo, epoch);
  });

  tearDown(() => provider.dispose());

  for (final typed in [135.0, 102.5, 0.0]) {
    test('addSet persists the typed weight $typed unchanged', () async {
      expect(
        await provider.addSet(exerciseId: 1, reps: 5, weight: typed),
        isTrue,
      );

      final sent =
          verify(repo.createExerciseSet(captureAny)).captured.single
              as ExerciseSet;
      expect(sent.weight, typed);
    });
  }

  testWidgets('entry field is still labelled lbs', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<LogSetsProvider>.value(
        value: provider,
        child: const MaterialApp(home: LogSetsScreen(exerciseId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Weight (lbs)'), findsOneWidget);
  });
}
