import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/models/exercise.dart';
import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';
import 'package:go_hard_app/providers/music_player_provider.dart';
import 'package:go_hard_app/routes/route_names.dart';
import 'package:go_hard_app/ui/screens/sessions/active_workout_screen.dart';

import 'active_workout_screen_navigation_test.mocks.dart';

@GenerateMocks([SessionRepository])
Session _runningSession({DateTime? startedAt}) {
  return Session(
    id: 1,
    userId: 1,
    date: DateTime.utc(2024, 1, 15),
    status: 'in_progress',
    startedAt: startedAt ?? DateTime.utc(2024, 1, 15, 10, 0, 0),
    // Non-empty so the screen renders the exercise list rather than the
    // empty-state widget, which has its own "Add Exercise" button and
    // would make the FAB's "Add Exercise" text ambiguous to find/tap.
    exercises: [Exercise(id: 1, sessionId: 1, name: 'Warm-up')],
    version: 1,
  );
}

/// A stand-in for AddExerciseScreen that pops `true` as soon as it is
/// pushed - mirroring the real screen's "exercise added" success path
/// without needing to render the actual exercise picker UI.
class _FakeAddExerciseScreenThatPopsTrue extends StatefulWidget {
  const _FakeAddExerciseScreenThatPopsTrue();

  @override
  State<_FakeAddExerciseScreenThatPopsTrue> createState() =>
      _FakeAddExerciseScreenThatPopsTrueState();
}

class _FakeAddExerciseScreenThatPopsTrueState
    extends State<_FakeAddExerciseScreenThatPopsTrue> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

Future<void> _pumpActiveWorkoutScreen(
  WidgetTester tester,
  MockSessionRepository mockRepo,
) async {
  // The default 800x600 test surface overflows this screen's layout; this
  // is a test-viewport concern, unrelated to the timer logic under test.
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ActiveWorkoutProvider>(
          create:
              (_) => ActiveWorkoutProvider(
                mockRepo,
                UserSessionEpoch()..activate(1),
              ),
        ),
        ChangeNotifierProvider<MusicPlayerProvider>(
          create: (_) => MusicPlayerProvider(),
        ),
        // OfflineBanner (rendered by ActiveWorkoutScreen) watches this;
        // ConnectivityService.instance defaults to online and never touches
        // the platform connectivity plugin unless initialize() is called.
        ChangeNotifierProvider<ConnectivityService>.value(
          value: ConnectivityService.instance,
        ),
      ],
      child: MaterialApp(
        home: const ActiveWorkoutScreen(sessionId: 1),
        onGenerateRoute: (settings) {
          if (settings.name == RouteNames.addExercise) {
            return MaterialPageRoute(
              builder: (_) => const _FakeAddExerciseScreenThatPopsTrue(),
              settings: settings,
            );
          }
          return null;
        },
      ),
    ),
  );
}

void main() {
  late MockSessionRepository mockRepo;

  setUp(() {
    mockRepo = MockSessionRepository();
    when(mockRepo.getSession(1)).thenAnswer((_) async => _runningSession());
  });

  testWidgets(
    'returning from Add Exercise with a successful pop does not reload the '
    'active session (requirement: no redundant loadSession call)',
    (tester) async {
      await _pumpActiveWorkoutScreen(tester, mockRepo);
      await tester.pumpAndSettle();

      // initState() triggers exactly one loadSession() -> getSession() call.
      verify(mockRepo.getSession(1)).called(1);

      // Tap the "Add Exercise" FAB, which pushes AddExerciseScreen. The fake
      // screen pops `true` on its next frame, simulating a successful add.
      await tester.tap(find.text('Add Exercise'));
      await tester.pumpAndSettle();

      // The screen must be back on ActiveWorkoutScreen...
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);

      // ...and must NOT have called getSession() again. verify() above
      // already consumed the one legitimate call, so any further call - the
      // redundant-reload bug this fix removes - would show up here.
      verifyNever(mockRepo.getSession(any));
    },
  );

  testWidgets(
    'repeated Add Exercise navigation never triggers additional reloads',
    (tester) async {
      await _pumpActiveWorkoutScreen(tester, mockRepo);
      await tester.pumpAndSettle();
      verify(mockRepo.getSession(1)).called(1);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Add Exercise'));
        await tester.pumpAndSettle();
      }

      // Three round trips through Add Exercise; still only the original
      // initState() load ever happened - verify() above already consumed
      // it, so zero further calls should exist.
      verifyNever(mockRepo.getSession(any));
    },
  );
}
