// BUG-5 regression: a successfully-written exercise must never vanish from
// ActiveWorkoutProvider state because a concurrent loadSession() for the same
// workout (e.g. the one ActiveWorkoutScreen.initState schedules on arrival)
// supersedes the add's generation guard or publishes an older snapshot.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/exercise.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';

import 'active_workout_provider_navigation_test.mocks.dart';

Session _session({List<Exercise> exercises = const []}) => Session(
  id: 1,
  userId: 1,
  date: DateTime.utc(2024, 1, 15),
  status: 'in_progress',
  startedAt: DateTime.utc(2024, 1, 15, 10),
  exercises: exercises,
  version: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSessionRepository repo;
  late UserSessionEpoch epoch;
  late ActiveWorkoutProvider provider;
  final added = Exercise(id: 99, sessionId: 1, name: 'Bench Press');

  setUp(() async {
    repo = MockSessionRepository();
    epoch = UserSessionEpoch()..activate(1);
    provider = ActiveWorkoutProvider(repo, epoch);
    when(repo.getSession(1)).thenAnswer((_) async => _session());
    await provider.loadSession(1);
  });

  tearDown(() => provider.dispose());

  test('stale in-flight load that completes AFTER a successful add does not '
      'erase the added exercise', () async {
    final staleLoad = Completer<Session>();
    when(repo.getSession(1)).thenAnswer((_) => staleLoad.future);
    when(repo.addExerciseToSession(1, 42)).thenAnswer((_) async => added);

    final load = provider.loadSession(1, showLoading: false);
    await provider.addExercise(42);
    expect(provider.currentSession!.exercises, contains(added));

    staleLoad.complete(_session()); // snapshot read before the write
    await load;

    expect(provider.currentSession!.exercises, contains(added));
  });

  test('a load that starts while the add write is in flight does not cause '
      'the add to be dropped', () async {
    final write = Completer<Exercise>();
    when(repo.addExerciseToSession(1, 42)).thenAnswer((_) => write.future);
    when(repo.getSession(1)).thenAnswer((_) async => _session());

    final add = provider.addExercise(42);
    await provider.loadSession(1, showLoading: false); // bumps generation
    write.complete(added);
    await add;

    expect(provider.currentSession!.exercises, contains(added));
  });

  test('when the fresh snapshot already contains the added exercise it is not '
      'duplicated', () async {
    final write = Completer<Exercise>();
    when(repo.addExerciseToSession(1, 42)).thenAnswer((_) => write.future);
    when(
      repo.getSession(1),
    ).thenAnswer((_) async => _session(exercises: [added]));

    final add = provider.addExercise(42);
    await provider.loadSession(1, showLoading: false);
    write.complete(added);
    await add;

    expect(
      provider.currentSession!.exercises.where((e) => e.id == 99).length,
      1,
    );
  });

  test(
    'an add that completes after logout never publishes into the next user',
    () async {
      final write = Completer<Exercise>();
      when(repo.addExerciseToSession(1, 42)).thenAnswer((_) => write.future);

      final add = provider.addExercise(42);
      provider.clear();
      epoch.invalidate();
      epoch.activate(2);
      write.complete(added);
      await add;

      expect(provider.currentSession, isNull);
    },
  );
}
