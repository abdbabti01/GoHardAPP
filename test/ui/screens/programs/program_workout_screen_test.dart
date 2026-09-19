import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/program.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/data/repositories/programs_repository.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/providers/programs_provider.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';
import 'package:go_hard_app/ui/screens/programs/program_workout_screen.dart';

@GenerateMocks([ProgramsRepository, SessionRepository, ConnectivityService])
import 'program_workout_screen_test.mocks.dart';

/// Rendered/interaction coverage for ProgramWorkoutScreen's action-menu
/// mutation feedback (Skip), including regression coverage for the same
/// Phase-4 mutation-feedback ownership bug fixed elsewhere in this branch:
/// reading `provider.errorMessage` after `skipWorkout` returned a failed
/// result couldn't distinguish a genuine failure from a stale/cancelled
/// one. The fix is [ProgramsProvider.skipWorkout]'s `onError` callback.
void main() {
  late MockProgramsRepository programsRepo;
  late MockSessionRepository sessionRepo;
  late MockConnectivityService connectivity;
  late UserSessionEpoch epoch;
  late ProgramsProvider programsProvider;
  late SessionsProvider sessionsProvider;

  ProgramWorkout workout({
    int id = 1,
    bool isCompleted = false,
    bool isSkipped = false,
  }) => ProgramWorkout(
    id: id,
    programId: 1,
    weekNumber: 1,
    dayNumber: 1,
    workoutName: 'Push Day',
    exercisesJson: jsonEncode([]),
    isCompleted: isCompleted,
    isSkipped: isSkipped,
    orderIndex: 0,
  );

  Program program(ProgramWorkout w) => Program(
    id: 1,
    userId: 1,
    title: 'Push Pull Legs',
    totalWeeks: 4,
    currentWeek: 1,
    currentDay: 1,
    startDate: DateTime(2024, 1, 1),
    isActive: true,
    isCompleted: false,
    status: 'active',
    createdAt: DateTime(2024, 1, 1),
    workouts: [w],
  );

  setUp(() {
    programsRepo = MockProgramsRepository();
    sessionRepo = MockSessionRepository();
    connectivity = MockConnectivityService();
    epoch = UserSessionEpoch()..activate(1);
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => const Stream<bool>.empty());
    programsProvider = ProgramsProvider(programsRepo, epoch);
    sessionsProvider = SessionsProvider(sessionRepo, epoch, connectivity);
  });

  Future<void> pumpScreen(WidgetTester tester, ProgramWorkout w) async {
    when(programsRepo.getProgramById(1)).thenAnswer((_) async => program(w));

    await tester.pumpWidget(
      MultiProvider(
        // Wraps MaterialApp itself, not just `home:` - a dialog opened via
        // showDialog is inserted at the Navigator's Overlay level, which is
        // a SIBLING of the `home` route's subtree, not a descendant of it.
        // A provider scoped only inside `home` is invisible to a dialog's
        // own BuildContext.
        providers: [
          ChangeNotifierProvider<ProgramsProvider>.value(
            value: programsProvider,
          ),
          ChangeNotifierProvider<SessionsProvider>.value(
            value: sessionsProvider,
          ),
        ],
        child: const MaterialApp(
          home: ProgramWorkoutScreen(workoutId: 1, programId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSkipAndConfirm(WidgetTester tester) async {
    // Only one "Skip" exists before the confirmation dialog opens.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    // Once the dialog is open, the underlying screen's own "Skip" button
    // is still in the tree (just behind the barrier), so scope to the
    // dialog's own action button specifically.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Skip'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders the workout header, exercises section, and Start/Skip actions '
    'for an incomplete workout',
    (tester) async {
      await pumpScreen(tester, workout());

      // Shown both in the AppBar title and the workout header body.
      expect(find.text('Push Day'), findsNWidgets(2));
      // ElevatedButton.icon/OutlinedButton.icon return private subclasses,
      // so find.byType(ElevatedButton) (an exact-type match) would not
      // match them - find.text is sufficient here since there is exactly
      // one of each label on screen at this point.
      expect(find.text('Start Workout'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    },
  );

  testWidgets('a genuine skipWorkout failure shows that exact message', (
    tester,
  ) async {
    await pumpScreen(tester, workout());

    when(programsRepo.skipWorkout(1)).thenThrow(Exception('network error'));

    await tapSkipAndConfirm(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Failed to skip workout'), findsOneWidget);
    expect(find.textContaining('network error'), findsOneWidget);
  });

  testWidgets('a stale (logout) skipWorkout result shows no snackbar', (
    tester,
  ) async {
    await pumpScreen(tester, workout());

    when(programsRepo.skipWorkout(1)).thenAnswer((_) async {
      epoch.invalidate();
      return Future.value();
    });

    await tapSkipAndConfirm(tester);

    verify(programsRepo.skipWorkout(1)).called(1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'a successful skip shows the success snackbar and pops the screen',
    (tester) async {
      when(programsRepo.skipWorkout(1)).thenAnswer((_) async {});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProgramsProvider>.value(
              value: programsProvider,
            ),
            ChangeNotifierProvider<SessionsProvider>.value(
              value: sessionsProvider,
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder:
                  (context) => Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        onPressed:
                            () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) => const ProgramWorkoutScreen(
                                      workoutId: 1,
                                      programId: 1,
                                    ),
                              ),
                            ),
                        child: const Text('open'),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      );

      when(
        programsRepo.getProgramById(1),
      ).thenAnswer((_) async => program(workout()));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tapSkipAndConfirm(tester);

      expect(find.text('Workout skipped'), findsOneWidget);
      // The screen pops back to the "open" button after a successful skip.
      expect(find.text('open'), findsOneWidget);
    },
  );
}
