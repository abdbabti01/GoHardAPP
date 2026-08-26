import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/models/exercise.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';

import 'active_workout_provider_navigation_test.mocks.dart';

@GenerateMocks([SessionRepository])
Session _session({
  int id = 1,
  String status = 'in_progress',
  DateTime? startedAt,
  DateTime? pausedAt,
  List<Exercise> exercises = const [],
  int version = 1,
}) {
  return Session(
    id: id,
    userId: 1,
    date: DateTime.utc(2024, 1, 15),
    status: status,
    startedAt: startedAt,
    pausedAt: pausedAt,
    exercises: exercises,
    version: version,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSessionRepository mockRepo;
  late ActiveWorkoutProvider provider;

  setUp(() {
    mockRepo = MockSessionRepository();
    provider = ActiveWorkoutProvider(mockRepo);
  });

  tearDown(() {
    provider.dispose();
  });

  group('Timer advancement (requirement 1)', () {
    test('elapsed time advances normally while running', () {
      fakeAsync((async) {
        final startedAt = DateTime.now().toUtc();
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: startedAt));

        provider.loadSession(1);
        async.flushMicrotasks();

        expect(provider.isTimerRunning, true);
        // ActiveWorkoutProvider uses the real wall clock (not package:clock),
        // so fakeAsync cannot freeze DateTime.now() itself - only Timer
        // scheduling is faked. Compare at second granularity, which is the
        // timer's actual display/tick resolution.
        expect(provider.elapsedTime.inSeconds, 0);

        async.elapse(const Duration(seconds: 5));
        expect(provider.elapsedTime.inSeconds, 5);
      });
    });
  });

  group('Add Exercise preserves timing (requirements 2-4)', () {
    test('addExercise preserves startedAt, pausedAt, status and does not touch '
        'the repository session-read path', () async {
      final startedAt = DateTime.utc(2024, 1, 15, 10, 0, 0);
      final initialSession = _session(startedAt: startedAt, version: 7);
      final newExercise = Exercise(id: 99, sessionId: 1, name: 'Bench Press');

      when(mockRepo.getSession(1)).thenAnswer((_) async => initialSession);
      when(
        mockRepo.addExerciseToSession(1, 42),
      ).thenAnswer((_) async => newExercise);

      await provider.loadSession(1);
      expect(provider.currentSession!.startedAt, startedAt);

      await provider.addExercise(42);

      // Timing/version fields must be exactly what they were before -
      // addExercise must never re-derive them from a fresh repository read.
      expect(provider.currentSession!.startedAt, startedAt);
      expect(provider.currentSession!.pausedAt, isNull);
      expect(provider.currentSession!.status, 'in_progress');
      expect(provider.currentSession!.version, 7);
      expect(provider.currentSession!.exercises, contains(newExercise));

      // addExercise must never call getSession - if it did, that would be
      // exactly the redundant-reload bug this fix removes.
      verify(mockRepo.getSession(1)).called(1);
      verifyNever(mockRepo.getSession(any));
    });

    test(
      'time spent with Add Exercise "open" counts for a running workout',
      () {
        fakeAsync((async) {
          final startedAt = DateTime.now().toUtc();
          final newExercise = Exercise(id: 99, sessionId: 1, name: 'Squat');

          when(
            mockRepo.getSession(1),
          ).thenAnswer((_) async => _session(startedAt: startedAt));
          when(
            mockRepo.addExerciseToSession(1, 7),
          ).thenAnswer((_) async => newExercise);

          provider.loadSession(1);
          async.flushMicrotasks();

          // Simulate 90 seconds "spent" on the Add Exercise screen while the
          // workout keeps running in the background.
          async.elapse(const Duration(seconds: 90));
          expect(provider.elapsedTime.inSeconds, 90);

          // Simulate AddExerciseScreen calling provider.addExercise().
          provider.addExercise(7);
          async.flushMicrotasks();

          // Elapsed time must reflect the 90 seconds that passed, not reset
          // to zero and not be recalculated from a stale reload.
          expect(provider.elapsedTime.inSeconds, 90);
          expect(provider.isTimerRunning, true);
        });
      },
    );

    test('a paused workout does not advance while Add Exercise is open', () {
      fakeAsync((async) {
        final startedAt = DateTime.utc(2024, 1, 15, 10, 0, 0);
        final pausedAt = DateTime.utc(2024, 1, 15, 10, 5, 0); // 5 min in
        final newExercise = Exercise(id: 5, sessionId: 1, name: 'Deadlift');

        when(mockRepo.getSession(1)).thenAnswer(
          (_) async => _session(startedAt: startedAt, pausedAt: pausedAt),
        );
        when(
          mockRepo.addExerciseToSession(1, 3),
        ).thenAnswer((_) async => newExercise);

        provider.loadSession(1);
        async.flushMicrotasks();

        expect(provider.isTimerRunning, false);
        expect(provider.elapsedTime, const Duration(minutes: 5));

        // Time passes while the (fake) Add Exercise screen is open.
        async.elapse(const Duration(minutes: 3));

        // Still paused: no tick should have advanced elapsedTime.
        expect(provider.isTimerRunning, false);
        expect(provider.elapsedTime, const Duration(minutes: 5));

        provider.addExercise(3);
        async.flushMicrotasks();

        expect(provider.isTimerRunning, false);
        expect(provider.elapsedTime, const Duration(minutes: 5));
      });
    });
  });

  group('No duplicate timers or reloads (requirements 5-6)', () {
    test('repeated addExercise calls never create more than one active timer '
        'and never re-read the session', () {
      fakeAsync((async) {
        final startedAt = DateTime.utc(2024, 1, 15, 10, 0, 0);
        final exercise = Exercise(id: 1, sessionId: 1, name: 'Row');

        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: startedAt));
        when(
          mockRepo.addExerciseToSession(1, any),
        ).thenAnswer((_) async => exercise);

        provider.loadSession(1);
        async.flushMicrotasks();

        for (var i = 0; i < 5; i++) {
          provider.addExercise(i);
          async.flushMicrotasks();
        }

        // Only the initial loadSession() read the session; five
        // "navigations" to Add Exercise triggered zero additional reads.
        verify(mockRepo.getSession(1)).called(1);

        // A single 10-second elapse should advance elapsed time by
        // exactly 10 seconds - if a duplicate timer existed, it would
        // advance by a multiple of that.
        final before = provider.elapsedTime;
        async.elapse(const Duration(seconds: 10));
        expect(provider.elapsedTime - before, const Duration(seconds: 10));
      });
    });
  });

  group('Rebuild / provider-recreation resilience (requirement 7)', () {
    test('reading provider state repeatedly (simulating widget rebuilds) does '
        'not reset elapsed time', () {
      fakeAsync((async) {
        final startedAt = DateTime.now().toUtc();
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: startedAt));

        provider.loadSession(1);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 20));

        // Simulate several widget rebuilds just reading provider state.
        for (var i = 0; i < 10; i++) {
          // ignore: unused_local_variable
          final snapshot = provider.elapsedTime;
        }

        expect(provider.elapsedTime.inSeconds, 20);
        expect(provider.isTimerRunning, true);
      });
    });
  });

  group('Resume continues from correct elapsed duration', () {
    test('resumeTimer continues counting from the paused elapsed time', () {
      fakeAsync((async) {
        final startedAt = DateTime.utc(2024, 1, 15, 10, 0, 0);
        final pausedAt = DateTime.utc(2024, 1, 15, 10, 10, 0); // 10 min in

        when(mockRepo.getSession(1)).thenAnswer(
          (_) async => _session(startedAt: startedAt, pausedAt: pausedAt),
        );
        when(mockRepo.resumeSession(1, any)).thenAnswer((_) async {});

        provider.loadSession(1);
        async.flushMicrotasks();
        expect(provider.elapsedTime, const Duration(minutes: 10));

        provider.resumeTimer();
        async.flushMicrotasks();

        expect(provider.isTimerRunning, true);
        // Resuming immediately must not jump the elapsed time.
        expect(provider.elapsedTime.inMinutes, 10);

        async.elapse(const Duration(minutes: 2));
        expect(provider.elapsedTime.inMinutes, 12);
      });
    });
  });
}
