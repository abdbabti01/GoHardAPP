import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/workout_stats.dart';
import 'package:go_hard_app/data/repositories/analytics_repository.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';
import 'package:go_hard_app/providers/analytics_provider.dart';

@GenerateMocks([AnalyticsRepository])
import 'analytics_provider_session_ownership_test.mocks.dart';

/// Proves [AnalyticsProvider] never lets an aggregate load, error, or
/// `finally` cleanup started under user A land on the state user B now sees
/// through this same app-scoped instance, that within one session an older
/// load can never overwrite a newer one, and that `clear()`/`dispose()`
/// synchronously and permanently stop an in-flight continuation.
///
/// Real [UserSessionEpoch]; the repository is mocked so `Completer`s give
/// exact control over when each child call resolves. Nothing here waits on
/// wall-clock time.
void main() {
  late MockAnalyticsRepository repo;
  late UserSessionEpoch epoch;
  late AnalyticsProvider provider;
  late int notifyCount;

  WorkoutStats stats({int totalWorkouts = 5}) => WorkoutStats(
    totalWorkouts: totalWorkouts,
    totalDuration: 3600,
    averageDuration: 720,
    currentStreak: 1,
    longestStreak: 2,
    workoutsThisWeek: 1,
    workoutsThisMonth: 3,
    totalSets: 10,
    totalReps: 100,
    totalVolume: 1000,
  );

  ExerciseProgress progress(int id) => ExerciseProgress(
    exerciseTemplateId: id,
    exerciseName: 'Ex $id',
    timesPerformed: 3,
    totalVolume: 900,
  );

  PersonalRecord pr(int id) => PersonalRecord(
    exerciseName: 'Ex $id',
    exerciseTemplateId: id,
    weight: 100,
    reps: 5,
    dateAchieved: DateTime(2026, 1, 1),
    estimatedOneRepMax: 115,
    daysSincePR: 3,
  );

  MuscleGroupVolume mgv(String name) => MuscleGroupVolume(
    muscleGroup: name,
    volume: 500,
    exerciseCount: 2,
    percentage: 50,
  );

  /// Stub the four aggregate children with immediate canned results.
  void stubAggregate({
    WorkoutStats? workoutStats,
    List<ExerciseProgress>? exerciseProgress,
    List<PersonalRecord>? personalRecords,
    List<MuscleGroupVolume>? muscleGroups,
  }) {
    when(
      repo.getWorkoutStats(),
    ).thenAnswer((_) async => workoutStats ?? stats());
    when(
      repo.getExerciseProgress(),
    ).thenAnswer((_) async => exerciseProgress ?? [progress(1)]);
    when(
      repo.getPersonalRecords(),
    ).thenAnswer((_) async => personalRecords ?? [pr(1)]);
    when(
      repo.getMuscleGroupVolume(days: anyNamed('days')),
    ).thenAnswer((_) async => muscleGroups ?? [mgv('Chest')]);
  }

  setUp(() {
    repo = MockAnalyticsRepository();
    epoch = UserSessionEpoch();
    provider = AnalyticsProvider(repo, epoch);
    notifyCount = 0;
    provider.addListener(() => notifyCount++);
  });

  tearDown(() {
    try {
      provider.dispose();
    } catch (_) {
      // Some tests dispose explicitly.
    }
  });

  // ================================================================
  // Cross-session disclosure
  // ================================================================

  group('cross-session', () {
    test('1-2: a slow aggregate load started by A cannot repopulate cleared '
        'state after logout, nor after B login', () async {
      epoch.activate(1);
      final gate = Completer<WorkoutStats>();
      when(repo.getWorkoutStats()).thenAnswer((_) => gate.future);
      when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
      when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
      when(
        repo.getMuscleGroupVolume(days: anyNamed('days')),
      ).thenAnswer((_) async => [mgv('Chest')]);

      final future = provider.loadAnalytics();
      expect(provider.isLoading, isTrue);

      provider.clear(); // logout cleanup
      epoch.invalidate();
      epoch.activate(2); // user B

      gate.complete(stats(totalWorkouts: 99));
      await future;

      expect(provider.workoutStats, isNull);
      expect(provider.exerciseProgress, isEmpty);
      expect(provider.personalRecords, isEmpty);
      expect(provider.muscleGroupVolume, isEmpty);
      expect(provider.isLoading, isFalse);
    });

    test(
      '3: a slow success from A cannot overwrite B\'s newer aggregate',
      () async {
        epoch.activate(1);
        final aGate = Completer<WorkoutStats>();
        when(repo.getWorkoutStats()).thenAnswer((_) => aGate.future);
        when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
        when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
        when(
          repo.getMuscleGroupVolume(days: anyNamed('days')),
        ).thenAnswer((_) async => [mgv('Chest')]);

        final aFuture = provider.loadAnalytics();

        // B logs in and runs its own load to completion.
        epoch.invalidate();
        epoch.activate(2);
        stubAggregate(
          workoutStats: stats(totalWorkouts: 2),
          exerciseProgress: [progress(2)],
          personalRecords: [pr(2)],
          muscleGroups: [mgv('Back')],
        );
        await provider.loadAnalytics();
        expect(provider.workoutStats!.totalWorkouts, 2);

        // A's stale continuation resolves last.
        aGate.complete(stats(totalWorkouts: 99));
        await aFuture;

        expect(provider.workoutStats!.totalWorkouts, 2);
        expect(provider.personalRecords.single.exerciseTemplateId, 2);
      },
    );

    test('4-5: a stale lifecycle failure sets no error and clears no newer '
        'loading state', () async {
      epoch.activate(1);
      final aGate = Completer<WorkoutStats>();
      when(repo.getWorkoutStats()).thenAnswer((_) => aGate.future);
      when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
      when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
      when(
        repo.getMuscleGroupVolume(days: anyNamed('days')),
      ).thenAnswer((_) async => [mgv('Chest')]);

      final aFuture = provider.loadAnalytics();

      // B logs in, starts its own (still pending) load.
      epoch.invalidate();
      epoch.activate(2);
      final bGate = Completer<WorkoutStats>();
      when(repo.getWorkoutStats()).thenAnswer((_) => bGate.future);
      final bFuture = provider.loadAnalytics();
      expect(provider.isLoading, isTrue);

      // A's continuation fails with a lifecycle exception, last.
      final notifyBeforeStale = notifyCount;
      aGate.completeError(const SessionStaleException());
      await aFuture;

      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isTrue, reason: "B's spinner survives");
      expect(
        notifyCount,
        notifyBeforeStale,
        reason: 'a stale lifecycle continuation must not notify',
      );

      bGate.complete(stats(totalWorkouts: 7));
      await bFuture;
      expect(provider.isLoading, isFalse);
      expect(provider.workoutStats!.totalWorkouts, 7);
    });

    test('4b: an ORDINARY failure from a superseded A load does not set the '
        "current session's error (stale generic-catch guard)", () async {
      epoch.activate(1);
      final aGate = Completer<WorkoutStats>();
      when(repo.getWorkoutStats()).thenAnswer((_) => aGate.future);
      when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
      when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
      when(
        repo.getMuscleGroupVolume(days: anyNamed('days')),
      ).thenAnswer((_) async => [mgv('Chest')]);

      final aFuture = provider.loadAnalytics();

      epoch.invalidate();
      epoch.activate(2);
      stubAggregate(workoutStats: stats(totalWorkouts: 4));
      await provider.loadAnalytics();
      expect(provider.errorMessage, isNull);

      // A's superseded continuation fails with a plain (non-lifecycle) error.
      aGate.completeError(Exception('A transport boom'));
      await aFuture;

      expect(provider.errorMessage, isNull);
      expect(provider.workoutStats!.totalWorkouts, 4);
    });

    test('6: a stale continuation does not notify listeners', () async {
      epoch.activate(1);
      final gate = Completer<WorkoutStats>();
      when(repo.getWorkoutStats()).thenAnswer((_) => gate.future);
      when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
      when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
      when(
        repo.getMuscleGroupVolume(days: anyNamed('days')),
      ).thenAnswer((_) async => [mgv('Chest')]);

      final future = provider.loadAnalytics();
      provider.clear();
      final countAfterClear = notifyCount;

      gate.complete(stats());
      await future;

      expect(notifyCount, countAfterClear, reason: 'no notify from stale path');
    });

    test(
      '7: a lifecycle exception surfaces no generic user-visible error',
      () async {
        epoch.activate(1);
        when(
          repo.getWorkoutStats(),
        ).thenAnswer((_) async => throw const RequestCancelledException());
        when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
        when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
        when(
          repo.getMuscleGroupVolume(days: anyNamed('days')),
        ).thenAnswer((_) async => [mgv('Chest')]);

        await provider.loadAnalytics();

        expect(provider.errorMessage, isNull);
        expect(provider.workoutStats, isNull);
        expect(provider.isLoading, isFalse);
      },
    );

    test('an ordinary failure while current DOES surface an error', () async {
      epoch.activate(1);
      when(
        repo.getWorkoutStats(),
      ).thenAnswer((_) async => throw Exception('network down'));
      when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
      when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
      when(
        repo.getMuscleGroupVolume(days: anyNamed('days')),
      ).thenAnswer((_) async => [mgv('Chest')]);

      await provider.loadAnalytics();

      expect(provider.errorMessage, contains('network down'));
      expect(provider.isLoading, isFalse);
    });
  });

  // ================================================================
  // Same-session ordering
  // ================================================================

  group('same-session ordering', () {
    test(
      '8: an older aggregate load completing last loses to the newer one',
      () async {
        epoch.activate(1);
        final firstGate = Completer<WorkoutStats>();
        when(repo.getWorkoutStats()).thenAnswer((_) => firstGate.future);
        when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
        when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
        when(
          repo.getMuscleGroupVolume(days: anyNamed('days')),
        ).thenAnswer((_) async => [mgv('Chest')]);

        final first = provider.loadAnalytics();

        stubAggregate(workoutStats: stats(totalWorkouts: 2));
        await provider.loadAnalytics(); // newer, resolves now

        expect(provider.workoutStats!.totalWorkouts, 2);

        firstGate.complete(stats(totalWorkouts: 99));
        await first;

        expect(provider.workoutStats!.totalWorkouts, 2);
      },
    );

    test('10: an obsolete aggregate\'s child cannot overwrite a newer '
        'aggregate\'s fields', () async {
      epoch.activate(1);
      final oldProgressGate = Completer<List<ExerciseProgress>>();
      when(repo.getWorkoutStats()).thenAnswer((_) async => stats());
      when(
        repo.getExerciseProgress(),
      ).thenAnswer((_) => oldProgressGate.future);
      when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
      when(
        repo.getMuscleGroupVolume(days: anyNamed('days')),
      ).thenAnswer((_) async => [mgv('Chest')]);

      final old = provider.loadAnalytics();

      stubAggregate(exerciseProgress: [progress(42)]);
      await provider.loadAnalytics();
      expect(provider.exerciseProgress.single.exerciseTemplateId, 42);

      oldProgressGate.complete([progress(7)]);
      await old;
      expect(provider.exerciseProgress.single.exerciseTemplateId, 42);
    });

    test('11-12: a manual refresh supersedes an in-flight initialization; the '
        "old load's finally cannot clear the newer spinner", () async {
      epoch.activate(1);
      final initGate = Completer<WorkoutStats>();
      when(repo.getWorkoutStats()).thenAnswer((_) => initGate.future);
      when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
      when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
      when(
        repo.getMuscleGroupVolume(days: anyNamed('days')),
      ).thenAnswer((_) async => [mgv('Chest')]);

      final init = provider.loadAnalytics(); // initState path

      final refreshGate = Completer<WorkoutStats>();
      when(repo.getWorkoutStats()).thenAnswer((_) => refreshGate.future);
      final refresh = provider.refresh();
      expect(provider.isLoading, isTrue);

      initGate.complete(stats(totalWorkouts: 1));
      await init;
      expect(provider.isLoading, isTrue, reason: 'refresh still owns spinner');

      refreshGate.complete(stats(totalWorkouts: 2));
      await refresh;
      expect(provider.isLoading, isFalse);
      expect(provider.workoutStats!.totalWorkouts, 2);
    });

    test(
      '13: repeated identical loads still resolve by generation, not value',
      () async {
        epoch.activate(1);
        final g1 = Completer<WorkoutStats>();
        when(repo.getWorkoutStats()).thenAnswer((_) => g1.future);
        when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
        when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
        when(
          repo.getMuscleGroupVolume(days: anyNamed('days')),
        ).thenAnswer((_) async => [mgv('Chest')]);
        final first = provider.loadAnalytics();

        stubAggregate(workoutStats: stats(totalWorkouts: 55));
        await provider.loadAnalytics();

        g1.complete(stats(totalWorkouts: 55)); // same value, older generation
        await first;

        // The older one still must not have re-published or flipped the spinner.
        expect(provider.isLoading, isFalse);
        expect(provider.workoutStats!.totalWorkouts, 55);
      },
    );
  });

  // ================================================================
  // Cleanup
  // ================================================================

  group('cleanup', () {
    test('14-16: clear() synchronously empties every field and invalidates '
        'the generation before reset', () async {
      epoch.activate(1);
      stubAggregate();
      await provider.loadAnalytics();
      expect(provider.workoutStats, isNotNull);
      expect(provider.exerciseProgress, isNotEmpty);
      expect(provider.personalRecords, isNotEmpty);
      expect(provider.muscleGroupVolume, isNotEmpty);

      provider.clear();

      expect(provider.workoutStats, isNull);
      expect(provider.exerciseProgress, isEmpty);
      expect(provider.personalRecords, isEmpty);
      expect(provider.muscleGroupVolume, isEmpty);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('17: a bare clear() (no epoch invalidation) still blocks an '
        'already-running continuation', () async {
      epoch.activate(1);
      final gate = Completer<WorkoutStats>();
      when(repo.getWorkoutStats()).thenAnswer((_) => gate.future);
      when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
      when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
      when(
        repo.getMuscleGroupVolume(days: anyNamed('days')),
      ).thenAnswer((_) async => [mgv('Chest')]);

      final future = provider.loadAnalytics();
      provider.clear(); // session still current

      gate.complete(stats(totalWorkouts: 99));
      await future;

      expect(provider.workoutStats, isNull);
      expect(provider.isLoading, isFalse);
    });

    test(
      '18-19: repeated clear() is safe and the provider stays usable for B',
      () async {
        epoch.activate(1);
        stubAggregate();
        await provider.loadAnalytics();

        provider.clear();
        provider.clear();

        epoch.invalidate();
        epoch.activate(2);
        stubAggregate(workoutStats: stats(totalWorkouts: 3));
        await provider.loadAnalytics();
        expect(provider.workoutStats!.totalWorkouts, 3);
      },
    );

    test('20-21: a list reference captured before clear() observes the '
        'emptying and cannot be mutated externally', () async {
      epoch.activate(1);
      stubAggregate(personalRecords: [pr(1), pr(2)]);
      await provider.loadAnalytics();

      final live = provider.personalRecords;
      expect(live, hasLength(2));
      expect(() => (live as dynamic).add(pr(3)), throwsUnsupportedError);

      provider.clear();
      expect(live, isEmpty, reason: 'live unmodifiable view reflects clear()');
    });

    test('22: dispose() prevents any later publication', () async {
      epoch.activate(1);
      final gate = Completer<WorkoutStats>();
      when(repo.getWorkoutStats()).thenAnswer((_) => gate.future);
      when(repo.getExerciseProgress()).thenAnswer((_) async => [progress(1)]);
      when(repo.getPersonalRecords()).thenAnswer((_) async => [pr(1)]);
      when(
        repo.getMuscleGroupVolume(days: anyNamed('days')),
      ).thenAnswer((_) async => [mgv('Chest')]);

      final future = provider.loadAnalytics();
      provider.dispose();

      gate.complete(stats(totalWorkouts: 99));
      await future; // must not throw, must not notify

      expect(provider.workoutStats, isNull);
    });
  });

  // ================================================================
  // Non-publishing helpers
  // ================================================================

  group('progress-over-time / volume-over-time helpers', () {
    test('logged out -> empty list, repository not called', () async {
      final result = await provider.getVolumeOverTime();
      expect(result, isEmpty);
      verifyNever(repo.getVolumeOverTime(days: anyNamed('days')));
    });

    test('a result computed for A is not handed back after B login', () async {
      epoch.activate(1);
      final gate = Completer<List<ProgressDataPoint>>();
      when(
        repo.getVolumeOverTime(days: anyNamed('days')),
      ).thenAnswer((_) => gate.future);

      final future = provider.getVolumeOverTime();
      epoch.invalidate();
      epoch.activate(2);
      gate.complete([ProgressDataPoint(date: DateTime(2026), value: 123)]);

      expect(await future, isEmpty);
    });

    test('a lifecycle exception becomes an empty list, never rethrown to the '
        'FutureBuilder', () async {
      epoch.activate(1);
      when(
        repo.getExerciseProgressOverTime(any, days: anyNamed('days')),
      ).thenAnswer((_) async => throw const SessionStaleException());

      expect(await provider.getExerciseProgressOverTime(5), isEmpty);
    });
  });
}
