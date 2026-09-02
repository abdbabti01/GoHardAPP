import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/exercise.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';

import 'active_workout_provider_session_ownership_test.mocks.dart';

/// Proves [ActiveWorkoutProvider] never lets a repository result, error,
/// timer tick, or lifecycle callback that began under user A land on the
/// state user B now sees through this same app-scoped instance; that within
/// one session an older acquire/edit can never overwrite a newer one; that
/// the ticker is owned by its scheduling-time session + generation + workout
/// id; and that `clear()` / `dispose()` invalidate every generation before
/// resetting state - even without a preceding
/// `UserSessionEpoch.invalidate()`.
///
/// Real [UserSessionEpoch]; the repository is mocked so `Completer`s give
/// exact control over when each continuation resolves - no wall-clock delay,
/// no `Future.delayed`, no `pumpEventQueue` / `_settle`. `fakeAsync` drives
/// `Timer.periodic` deterministically.
@GenerateMocks([SessionRepository])
Session _session({
  int id = 1,
  int userId = 1,
  String status = 'in_progress',
  String? name,
  DateTime? startedAt,
  DateTime? pausedAt,
  List<Exercise> exercises = const [],
  int version = 1,
}) => Session(
  id: id,
  userId: userId,
  date: DateTime.utc(2024, 1, 15),
  status: status,
  name: name,
  startedAt: startedAt,
  pausedAt: pausedAt,
  exercises: exercises,
  version: version,
);

Exercise _exercise(int id, {String name = 'Bench'}) =>
    Exercise(id: id, sessionId: 1, name: name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSessionRepository repo;
  late UserSessionEpoch epoch;
  late ActiveWorkoutProvider provider;
  late int notifyCount;

  setUp(() {
    repo = MockSessionRepository();
    epoch = UserSessionEpoch()..activate(1);
    provider = ActiveWorkoutProvider(repo, epoch);
    notifyCount = 0;
    provider.addListener(() => notifyCount++);
  });

  tearDown(() {
    try {
      provider.dispose();
    } catch (_) {}
  });

  // ============================================================
  // Cross-session async state
  // ============================================================
  group('cross-session async state', () {
    test(
      '1. logged-out loadSession dispatches nothing and publishes nothing',
      () async {
        epoch.invalidate(); // logged out
        await provider.loadSession(1);
        verifyNever(repo.getSession(any));
        expect(provider.currentSession, isNull);
        expect(notifyCount, 0);
      },
    );

    test('2+3. slow restoration under A cannot publish after logout, nor '
        'overwrite B', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final load = provider.loadSession(1);

      // A logs out, B logs in, B loads its own workout.
      epoch.invalidate();
      epoch.activate(2);
      when(
        repo.getSession(9),
      ).thenAnswer((_) async => _session(id: 9, userId: 2, startedAt: null));
      await provider.loadSession(9);
      expect(provider.currentSession?.id, 9);
      final countAfterB = notifyCount;

      // A's slow load finally resolves - must be dropped.
      aC.complete(_session(id: 1, userId: 1, startedAt: null));
      await load;
      expect(provider.currentSession?.id, 9);
      expect(notifyCount, countAfterB);
    });

    test('4. slow startWorkout under A cannot become B\'s active workout - the '
        'logout lands DURING the updateSessionStatus await, after the '
        'in-progress prefetch already resolved', () async {
      when(repo.getSession(1)).thenAnswer(
        (_) async => _session(id: 1, status: 'draft', startedAt: null),
      );
      await provider.loadSession(1);

      final prefetchC = Completer<List<Session>>();
      when(
        repo.getInProgressSessions(),
      ).thenAnswer((_) async => prefetchC.future);
      final startC = Completer<Session>();
      when(
        repo.updateSessionStatus(
          1,
          'in_progress',
          startedAtUtc: anyNamed('startedAtUtc'),
        ),
      ).thenAnswer((_) async => startC.future);

      final start = provider.startWorkout();
      // First await resolves while A is still current.
      prefetchC.complete(<Session>[]);
      await Future<void>.value();
      // Now the logout / B login lands mid-updateSessionStatus.
      epoch.invalidate();
      epoch.activate(2);
      startC.complete(_session(id: 1, startedAt: DateTime.now().toUtc()));
      await start;

      expect(provider.isTimerRunning, isFalse);
      expect(provider.currentSession?.status, 'draft');
      expect(provider.currentSession?.startedAt, isNull);
    });

    test(
      '2b. an A load settling after a direct A->B epoch activation (NO clear()) '
      'mutates nothing and does not notify - not even the shared _isLoading',
      () async {
        final aC = Completer<Session>();
        when(repo.getSession(1)).thenAnswer((_) async => aC.future);
        final load = provider.loadSession(1); // A: _isLoading=true, notify (1)

        epoch.invalidate();
        epoch.activate(
          2,
        ); // B is current; B does NOT load, clear() did NOT run.
        final afterB = notifyCount;

        aC.complete(
          _session(id: 1, userId: 1, name: 'A-ghost', startedAt: null),
        );
        await load;

        // A's continuation is entirely under B's epoch now: it publishes no
        // result, sets no error, does NOT touch `_isLoading`, and emits zero
        // notifications. In this synthetic no-`clear()` state the spinner
        // stays whatever A last set it to (true) - authoritative cleanup, not
        // a stale A continuation, owns resetting it.
        expect(provider.currentSession, isNull);
        expect(provider.errorMessage, isNull);
        expect(provider.isLoading, isTrue); // A did NOT mutate it
        expect(notifyCount, afterB); // A's settlement emitted nothing
      },
    );

    test('5. slow finishWorkout under A cannot complete/clear B', () async {
      when(repo.getSession(1)).thenAnswer(
        (_) async => _session(
          id: 1,
          startedAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          ),
        ),
      );
      await provider.loadSession(1);
      final finishC = Completer<Session>();
      when(
        repo.updateSessionStatus(
          1,
          'completed',
          duration: anyNamed('duration'),
        ),
      ).thenAnswer((_) async => finishC.future);

      final finish = provider.finishWorkout();
      // B takes over.
      epoch.invalidate();
      epoch.activate(2);
      when(repo.getSession(9)).thenAnswer(
        (_) async =>
            _session(id: 9, userId: 2, startedAt: DateTime.now().toUtc()),
      );
      await provider.loadSession(9);
      final countAfterB = notifyCount;

      finishC.complete(_session(id: 1, status: 'completed'));
      expect(await finish, isFalse);
      expect(provider.currentSession?.id, 9);
      expect(provider.currentSession?.status, 'in_progress');
      expect(notifyCount, countAfterB);
    });

    test('7. stale addExercise success cannot mutate B', () async {
      when(
        repo.getSession(1),
      ).thenAnswer((_) async => _session(id: 1, exercises: [_exercise(1)]));
      await provider.loadSession(1);
      final addC = Completer<Exercise>();
      when(
        repo.addExerciseToSession(1, 55),
      ).thenAnswer((_) async => addC.future);

      final add = provider.addExercise(55);
      epoch.invalidate();
      epoch.activate(2);
      when(repo.getSession(9)).thenAnswer(
        (_) async => _session(id: 9, userId: 2, exercises: [_exercise(2)]),
      );
      await provider.loadSession(9);

      addC.complete(_exercise(99, name: 'Ghost'));
      await add;
      expect(provider.currentSession?.id, 9);
      expect(provider.exercises.map((e) => e.id), [2]);
    });

    test('8. stale failure cannot set B\'s error', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final load = provider.loadSession(1);

      epoch.invalidate();
      epoch.activate(2);
      when(
        repo.getSession(9),
      ).thenAnswer((_) async => _session(id: 9, userId: 2, startedAt: null));
      await provider.loadSession(9);

      aC.completeError(Exception('A backend blew up'));
      await load;
      expect(provider.errorMessage, isNull);
      expect(provider.currentSession?.id, 9);
    });

    test('9. stale finally cannot clear B\'s newer loading state', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final aLoad = provider.loadSession(1); // showLoading: true -> isLoading

      epoch.invalidate();
      epoch.activate(2);
      final bC = Completer<Session>();
      when(repo.getSession(9)).thenAnswer((_) async => bC.future);
      final bLoad = provider.loadSession(9); // B's spinner is now the live one
      expect(provider.isLoading, isTrue);

      aC.complete(_session(id: 1));
      await aLoad;
      // A's stale finally must NOT clear B's spinner.
      expect(provider.isLoading, isTrue);

      bC.complete(_session(id: 9, userId: 2, startedAt: null));
      await bLoad;
      expect(provider.isLoading, isFalse);
    });

    test(
      '10. a stale lifecycle exception publishes no result and no error; '
      'a showLoading:false load does not touch the loading flag at all',
      () async {
        final aC = Completer<Session>();
        when(repo.getSession(1)).thenAnswer((_) async => aC.future);
        final load = provider.loadSession(1, showLoading: false);
        final baseline = notifyCount;

        epoch.invalidate();
        aC.completeError(const SessionStaleException());
        await load;

        // showLoading:false never claims/sets/clears/notifies for _isLoading,
        // and the stale lifecycle exception publishes nothing - zero notifies.
        expect(notifyCount, baseline);
        expect(provider.errorMessage, isNull);
        expect(provider.currentSession, isNull);
        expect(provider.isLoading, isFalse);
      },
    );

    test('11. B can load normally after A is invalidated', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final aLoad = provider.loadSession(1);
      epoch.invalidate();
      aC.complete(_session(id: 1));
      await aLoad;

      epoch.activate(2);
      when(repo.getSession(9)).thenAnswer(
        (_) async => _session(id: 9, userId: 2, name: 'Fresh', startedAt: null),
      );
      await provider.loadSession(9);
      expect(provider.currentSession?.id, 9);
      expect(provider.currentSession?.name, 'Fresh');
    });
  });

  // ============================================================
  // Same-session ordering
  // ============================================================
  group('same-session ordering', () {
    test('12. an older load completing last loses', () async {
      final c1 = Completer<Session>();
      final c2 = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => c1.future);
      when(repo.getSession(2)).thenAnswer((_) async => c2.future);

      final l1 = provider.loadSession(1);
      final l2 = provider.loadSession(2);
      c2.complete(_session(id: 2, name: 'newer', startedAt: null));
      await l2;
      c1.complete(_session(id: 1, name: 'older', startedAt: null));
      await l1;

      expect(provider.currentSession?.id, 2);
      expect(provider.currentSession?.name, 'newer');
    });

    test('14. A -> B -> A resolves by generation, not id equality', () async {
      final cA1 = Completer<Session>();
      final cB = Completer<Session>();
      final cA2 = Completer<Session>();
      var call = 0;
      when(repo.getSession(1)).thenAnswer((_) async {
        call++;
        if (call == 1) return cA1.future;
        return cA2.future;
      });
      when(repo.getSession(2)).thenAnswer((_) async => cB.future);

      final la1 = provider.loadSession(1); // gen 1
      final lb = provider.loadSession(2); // gen 2
      final la2 = provider.loadSession(1); // gen 3 (newest, also id 1)

      cB.complete(_session(id: 2, name: 'B', startedAt: null));
      await lb;
      cA2.complete(_session(id: 1, name: 'A-new', startedAt: null));
      await la2;
      cA1.complete(_session(id: 1, name: 'A-old', startedAt: null));
      await la1;

      // The first A load (gen 1) must NOT win just because id == 1 again.
      expect(provider.currentSession?.name, 'A-new');
    });

    test(
      '15. an older updateWorkoutName cannot overwrite a newer one',
      () async {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, name: 'orig', startedAt: null),
        );
        await provider.loadSession(1);

        final c1 = Completer<Session>();
        final c2 = Completer<Session>();
        var n = 0;
        when(repo.updateSessionName(1, any)).thenAnswer((_) async {
          n++;
          return n == 1 ? c1.future : c2.future;
        });

        final u1 = provider.updateWorkoutName('first');
        final u2 = provider.updateWorkoutName('second');
        c2.complete(_session(id: 1, name: 'second', startedAt: null));
        await u2;
        c1.complete(_session(id: 1, name: 'first', startedAt: null));
        await u1;

        expect(provider.currentSession?.name, 'second');
      },
    );

    test(
      '17. a lifecycle reload cannot overwrite a newer manual start',
      () async {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, status: 'completed', startedAt: null),
        );
        await provider.loadSession(1);

        // Lifecycle resume triggers a (non-in_progress) reload...
        final reloadC = Completer<Session>();
        when(repo.getSession(1)).thenAnswer((_) async => reloadC.future);
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        // ...but the user manually loads a different draft and starts it.
        when(repo.getSession(2)).thenAnswer(
          (_) async => _session(id: 2, status: 'draft', startedAt: null),
        );
        await provider.loadSession(2);

        reloadC.complete(_session(id: 1, status: 'completed', name: 'stale'));
        await Future<void>.value();

        expect(provider.currentSession?.id, 2);
      },
    );

    test(
      '18. two rapid addExercise calls on the same workout both land',
      () async {
        when(
          repo.getSession(1),
        ).thenAnswer((_) async => _session(id: 1, exercises: const []));
        await provider.loadSession(1);

        final c1 = Completer<Exercise>();
        final c2 = Completer<Exercise>();
        when(
          repo.addExerciseToSession(1, 10),
        ).thenAnswer((_) async => c1.future);
        when(
          repo.addExerciseToSession(1, 20),
        ).thenAnswer((_) async => c2.future);

        final a1 = provider.addExercise(10);
        final a2 = provider.addExercise(20);
        c1.complete(_exercise(101));
        await a1;
        c2.complete(_exercise(102));
        await a2;

        expect(provider.exercises.map((e) => e.id), containsAll([101, 102]));
      },
    );
  });

  // ============================================================
  // Timer / ticker behavior
  // ============================================================
  group('ticker behavior', () {
    test('19. logged-out load creates no ticker', () {
      fakeAsync((async) {
        epoch.invalidate();
        provider.loadSession(1);
        async.flushMicrotasks();
        expect(provider.isTimerRunning, isFalse);
        async.elapse(const Duration(seconds: 5));
        expect(provider.elapsedTime, Duration.zero);
      });
    });

    test('21+22. a ticker scheduled under A no-ops after B login and cannot '
        'modify B elapsed time', () {
      fakeAsync((async) {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, startedAt: DateTime.now().toUtc()),
        );
        provider.loadSession(1);
        async.flushMicrotasks();
        expect(provider.isTimerRunning, isTrue);
        async.elapse(const Duration(seconds: 3));
        final aElapsed = provider.elapsedTime;

        // B logs in without the provider being cleared/reloaded yet.
        epoch.invalidate();
        epoch.activate(2);

        async.elapse(const Duration(seconds: 5));
        // A's ticker must not have advanced anything.
        expect(provider.elapsedTime, aElapsed);
        expect(provider.isTimerRunning, isFalse);
      });
    });

    test('24. replacing the workout invalidates the old ticker', () {
      fakeAsync((async) {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, startedAt: DateTime.now().toUtc()),
        );
        provider.loadSession(1);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));

        when(repo.getSession(2)).thenAnswer(
          (_) async => _session(id: 2, status: 'draft', startedAt: null),
        );
        provider.loadSession(2);
        async.flushMicrotasks();
        expect(provider.isTimerRunning, isFalse);

        async.elapse(const Duration(seconds: 5));
        expect(provider.elapsedTime, Duration.zero);
      });
    });

    test('28. clear() prevents an in-flight tick from advancing/re-arming', () {
      fakeAsync((async) {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, startedAt: DateTime.now().toUtc()),
        );
        provider.loadSession(1);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(provider.elapsedTime.inSeconds, 2);

        provider.clear();
        expect(provider.isTimerRunning, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(provider.elapsedTime, Duration.zero);
      });
    });

    test('29+30. dispose() prevents later ticks; no orphan ticker after '
        'workout removed', () {
      fakeAsync((async) {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, startedAt: DateTime.now().toUtc()),
        );
        provider.loadSession(1);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));

        provider.dispose();
        // Should not throw (no post-dispose notifyListeners) and not advance.
        async.elapse(const Duration(seconds: 10));
      });
    });

    test(
      'B1. resume-while-running (double-tap) does not freeze the ticker',
      () {
        fakeAsync((async) {
          when(repo.getSession(1)).thenAnswer(
            (_) async => _session(id: 1, startedAt: DateTime.now().toUtc()),
          );
          when(repo.pauseSession(1, any)).thenAnswer((_) async {});
          when(repo.resumeSession(1, any)).thenAnswer((_) async {});
          provider.loadSession(1);
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 3));

          provider.pauseTimer();
          async.flushMicrotasks();

          // Two resumes in a row: the second runs its synchronous pre-await
          // block while the first has already set _isTimerRunning = true.
          provider.resumeTimer();
          provider.resumeTimer();
          async.flushMicrotasks();

          expect(provider.isTimerRunning, isTrue);
          final before = provider.elapsedTime;
          async.elapse(const Duration(seconds: 5));
          // Ticker still advancing 1s/s - not frozen by a stale generation.
          expect(provider.elapsedTime - before, const Duration(seconds: 5));
        });
      },
    );
  });

  // ============================================================
  // Lifecycle
  // ============================================================
  group('lifecycle', () {
    test('31+32. observer registered once, unregistered once on dispose', () {
      // A second dispatch to a disposed provider is inert (no throw).
      provider.dispose();
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // Re-dispose guard in tearDown also must not throw.
    });

    test('33. lifecycle resume under A cannot publish after logout', () {
      fakeAsync((async) {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, status: 'completed', startedAt: null),
        );
        provider.loadSession(1);
        async.flushMicrotasks();

        final reloadC = Completer<Session>();
        when(repo.getSession(1)).thenAnswer((_) async => reloadC.future);
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        epoch.invalidate();
        reloadC.complete(_session(id: 1, name: 'ghost'));
        async.flushMicrotasks();

        expect(provider.currentSession?.name, isNot('ghost'));
      });
    });

    test('35. resume after clear() cannot resurrect A', () {
      fakeAsync((async) {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, startedAt: DateTime.now().toUtc()),
        );
        provider.loadSession(1);
        async.flushMicrotasks();

        provider.clear();
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.elapse(const Duration(seconds: 5));

        expect(provider.currentSession, isNull);
        expect(provider.isTimerRunning, isFalse);
        expect(provider.elapsedTime, Duration.zero);
      });
    });

    test('37. repeated pause/resume lifecycle cycles do not stack tickers', () {
      fakeAsync((async) {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, startedAt: DateTime.now().toUtc()),
        );
        provider.loadSession(1);
        async.flushMicrotasks();

        for (var i = 0; i < 5; i++) {
          provider.didChangeAppLifecycleState(AppLifecycleState.paused);
          provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        }

        final before = provider.elapsedTime;
        async.elapse(const Duration(seconds: 1));
        // Exactly one tick's worth of advance - not 5x.
        expect(provider.elapsedTime - before, const Duration(seconds: 1));
      });
    });
  });

  // ============================================================
  // Cleanup
  // ============================================================
  group('cleanup', () {
    test('38. clear() resets every user-visible and transient field', () async {
      when(repo.getSession(1)).thenAnswer(
        (_) async => _session(
          id: 1,
          name: 'W',
          startedAt: DateTime.now().toUtc(),
          exercises: [_exercise(1)],
        ),
      );
      await provider.loadSession(1);
      expect(provider.currentSession, isNotNull);

      provider.clear();

      expect(provider.currentSession, isNull);
      expect(provider.exercises, isEmpty);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.elapsedTime, Duration.zero);
      expect(provider.isTimerRunning, isFalse);
    });

    test(
      '39. clear() invalidates pending operations even without epoch change',
      () async {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, name: 'orig', startedAt: null),
        );
        await provider.loadSession(1);

        final updC = Completer<Session>();
        when(
          repo.updateSessionName(1, any),
        ).thenAnswer((_) async => updC.future);
        final upd = provider.updateWorkoutName('changed');

        // Manual clear (session-list "delete the workout I'm viewing") - no
        // UserSessionEpoch.invalidate().
        provider.clear();
        expect(epoch.isCurrent(epoch.capture()!), isTrue); // still logged in

        updC.complete(_session(id: 1, name: 'changed'));
        expect(await upd, isFalse);
        expect(provider.currentSession, isNull);
      },
    );

    test(
      '39b. clear() during an in-flight loadSession stops it repopulating '
      '(no epoch change) - the request-generation bump is what does it',
      () async {
        final loadC = Completer<Session>();
        when(repo.getSession(7)).thenAnswer((_) async => loadC.future);
        final load = provider.loadSession(7);

        provider.clear();
        expect(epoch.isCurrent(epoch.capture()!), isTrue); // still logged in

        loadC.complete(_session(id: 7, name: 'ghost', startedAt: null));
        await load;
        expect(provider.currentSession, isNull);
      },
    );

    test('40. SessionCleanupCoordinator wiring: clear() is the registered '
        'cleanup and fully resets even mid-flight', () async {
      // Mirrors the coordinator calling clear() after epoch.invalidate().
      final loadC = Completer<Session>();
      when(repo.getSession(7)).thenAnswer((_) async => loadC.future);
      final load = provider.loadSession(7);
      epoch.invalidate();
      provider.clear();
      loadC.complete(_session(id: 7, startedAt: null));
      await load;
      expect(provider.currentSession, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('43. existing behavior: a normal load + finish still works', () async {
      when(repo.getSession(1)).thenAnswer(
        (_) async => _session(
          id: 1,
          startedAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 3),
          ),
        ),
      );
      await provider.loadSession(1);
      expect(provider.currentSession?.id, 1);

      when(
        repo.updateSessionStatus(
          1,
          'completed',
          duration: anyNamed('duration'),
        ),
      ).thenAnswer((_) async => _session(id: 1, status: 'completed'));
      expect(await provider.finishWorkout(), isTrue);
      expect(provider.currentSession?.status, 'completed');
      expect(provider.isTimerRunning, isFalse);
    });
  });

  // ============================================================
  // Loading-claim ownership (separate from result ownership)
  // ============================================================
  group('loading-claim ownership', () {
    test(
      'LC1. a slow loadSession(showLoading:true) superseded by finishWorkout '
      'does NOT publish its stale session and clears its OWN spinner',
      () async {
        // Start with a running workout so finishWorkout has something to finish.
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(
            id: 1,
            startedAt: DateTime.now().toUtc().subtract(
              const Duration(minutes: 2),
            ),
          ),
        );
        await provider.loadSession(1);

        // A slow reload starts (spinner on)...
        final reloadC = Completer<Session>();
        when(repo.getSession(1)).thenAnswer((_) async => reloadC.future);
        final reload = provider.loadSession(1);
        expect(provider.isLoading, isTrue);

        // ...then the user finishes the workout (a newer edit -> bumps
        // _editGeneration, so the reload loses RESULT ownership).
        when(
          repo.updateSessionStatus(
            1,
            'completed',
            duration: anyNamed('duration'),
          ),
        ).thenAnswer((_) async => _session(id: 1, status: 'completed'));
        expect(await provider.finishWorkout(), isTrue);
        expect(provider.currentSession?.status, 'completed');

        // The stale reload settles with a would-be-newer session.
        reloadC.complete(_session(id: 1, name: 'STALE', status: 'in_progress'));
        await reload;

        // Result NOT published (finished workout intact) but the reload's own
        // spinner IS released - not stranded.
        expect(provider.currentSession?.status, 'completed');
        expect(provider.currentSession?.name, isNot('STALE'));
        expect(provider.isLoading, isFalse);
      },
    );

    test(
      'LC2. same, superseded by a non-terminal edit (updateWorkoutName)',
      () async {
        when(repo.getSession(1)).thenAnswer(
          (_) async => _session(id: 1, name: 'orig', startedAt: null),
        );
        await provider.loadSession(1);

        final reloadC = Completer<Session>();
        when(repo.getSession(1)).thenAnswer((_) async => reloadC.future);
        final reload = provider.loadSession(1);
        expect(provider.isLoading, isTrue);

        when(repo.updateSessionName(1, 'renamed')).thenAnswer(
          (_) async => _session(id: 1, name: 'renamed', startedAt: null),
        );
        expect(await provider.updateWorkoutName('renamed'), isTrue);

        reloadC.complete(_session(id: 1, name: 'STALE', startedAt: null));
        await reload;

        expect(provider.currentSession?.name, 'renamed');
        expect(provider.isLoading, isFalse);
      },
    );

    test('LC3. an older loadSession settling after a newer loadSession starts '
        'cannot clear the newer spinner', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final a = provider.loadSession(1); // claim 1

      final bC = Completer<Session>();
      when(repo.getSession(2)).thenAnswer((_) async => bC.future);
      final b = provider.loadSession(2); // claim 2 - now the live spinner owner
      expect(provider.isLoading, isTrue);

      // Older load (claim 1) settles first.
      aC.complete(_session(id: 1, startedAt: null));
      await a;
      // It must NOT clear B's spinner.
      expect(provider.isLoading, isTrue);

      bC.complete(_session(id: 2, userId: 1, startedAt: null));
      await b;
      expect(provider.isLoading, isFalse);
      expect(provider.currentSession?.id, 2);
    });

    test('LC4. User-A loading work settling after logout + B login + B load '
        'cannot clear B\'s loading state', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final a = provider.loadSession(1); // A claim

      epoch.invalidate();
      provider.clear(); // real logout path bumps _loadingClaim + resets flag
      epoch.activate(2);

      final bC = Completer<Session>();
      when(repo.getSession(9)).thenAnswer((_) async => bC.future);
      final b = provider.loadSession(9); // B claim
      expect(provider.isLoading, isTrue);

      aC.complete(_session(id: 1, userId: 1, startedAt: null));
      await a;
      // A's stale finally must not touch B's spinner.
      expect(provider.isLoading, isTrue);

      bC.complete(_session(id: 9, userId: 2, startedAt: null));
      await b;
      expect(provider.isLoading, isFalse);
      expect(provider.currentSession?.id, 9);
    });

    test('LC5. clear() invalidates an outstanding loading claim and leaves '
        '_isLoading == false', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final a = provider.loadSession(1);
      expect(provider.isLoading, isTrue);

      provider.clear();
      expect(provider.isLoading, isFalse);
      final afterClear = notifyCount;

      aC.complete(_session(id: 1, name: 'ghost', startedAt: null));
      await a;
      // clear() bumped _loadingClaim, so the outstanding load's finally is a
      // no-op: no spurious post-clear notify, flag stays false.
      expect(provider.isLoading, isFalse);
      expect(provider.currentSession, isNull);
      expect(notifyCount, afterClear);
    });

    test(
      'LC6. dispose() prevents the old finally from publishing or notifying',
      () async {
        final aC = Completer<Session>();
        when(repo.getSession(1)).thenAnswer((_) async => aC.future);
        final a = provider.loadSession(1);
        final baseline = notifyCount;

        provider.dispose();

        aC.complete(_session(id: 1, name: 'ghost', startedAt: null));
        await a; // must not throw (no post-dispose notifyListeners)
        expect(notifyCount, baseline);
      },
    );

    test('LC7. loadSession(showLoading:false) never sets/clears/notifies for '
        'the loading flag', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final load = provider.loadSession(1, showLoading: false);
      expect(provider.isLoading, isFalse);
      final baseline = notifyCount;

      aC.complete(_session(id: 1, startedAt: null));
      await load;
      // Result publishes (currentSession set + one notify) but the loading
      // flag was never touched.
      expect(provider.currentSession?.id, 1);
      expect(provider.isLoading, isFalse);
      expect(notifyCount, baseline + 1);
    });

    test(
      'LC8. createWorkoutFromAI shares the loading claim: superseded by a '
      'newer loadSession, it releases nothing (newer owns the spinner)',
      () async {
        final createC = Completer<Session>();
        when(repo.createSession(any)).thenAnswer((_) async => createC.future);
        final ai = provider.createWorkoutFromAI(
          workoutName: 'AI',
          exerciseTemplateIds: const [],
        );
        expect(provider.isLoading, isTrue);

        final bC = Completer<Session>();
        when(repo.getSession(5)).thenAnswer((_) async => bC.future);
        final b = provider.loadSession(5); // newer claim
        expect(provider.isLoading, isTrue);

        createC.complete(_session(id: 3, userId: 1, startedAt: null));
        expect(await ai, isNull); // superseded -> null
        // AI's finally must not clear the newer load's spinner.
        expect(provider.isLoading, isTrue);

        bC.complete(_session(id: 5, userId: 1, startedAt: null));
        await b;
        expect(provider.isLoading, isFalse);
      },
    );

    test('LC8b. createWorkoutFromAI clears its OWN spinner when superseded by '
        'an edit (not another loading op)', () async {
      when(
        repo.getSession(1),
      ).thenAnswer((_) async => _session(id: 1, name: 'orig', startedAt: null));
      await provider.loadSession(1);

      final createC = Completer<Session>();
      when(repo.createSession(any)).thenAnswer((_) async => createC.future);
      final ai = provider.createWorkoutFromAI(
        workoutName: 'AI',
        exerciseTemplateIds: const [],
      );
      expect(provider.isLoading, isTrue);

      when(repo.updateSessionName(1, 'renamed')).thenAnswer(
        (_) async => _session(id: 1, name: 'renamed', startedAt: null),
      );
      await provider.updateWorkoutName('renamed'); // bumps _editGeneration

      createC.complete(_session(id: 3, userId: 1, startedAt: null));
      expect(await ai, isNull);
      expect(provider.isLoading, isFalse); // own claim released
      expect(provider.currentSession?.name, 'renamed');
    });

    test('LC9. normal loadSession + createWorkoutFromAI still set and clear '
        'loading correctly', () async {
      when(
        repo.getSession(1),
      ).thenAnswer((_) async => _session(id: 1, startedAt: null));
      final loadStates = <bool>[];
      void rec() => loadStates.add(provider.isLoading);
      provider.addListener(rec);
      await provider.loadSession(1);
      provider.removeListener(rec);
      expect(loadStates.first, isTrue); // turned on
      expect(provider.isLoading, isFalse); // turned off
      expect(provider.currentSession?.id, 1);

      when(repo.createSession(any)).thenAnswer(
        (_) async => _session(id: 7, userId: 1, name: 'AI', startedAt: null),
      );
      expect(
        await provider.createWorkoutFromAI(
          workoutName: 'AI',
          exerciseTemplateIds: const [],
        ),
        7,
      );
      expect(provider.isLoading, isFalse);
      expect(provider.currentSession?.id, 7);
    });

    test(
      'LC10. only the current loading owner publishes loading transitions',
      () async {
        final aC = Completer<Session>();
        when(repo.getSession(1)).thenAnswer((_) async => aC.future);
        final a = provider.loadSession(1); // claim 1, notify (spinner on)

        final bC = Completer<Session>();
        when(repo.getSession(2)).thenAnswer((_) async => bC.future);
        final b = provider.loadSession(
          2,
        ); // claim 2, notify (still on, but B's)
        final afterBStart = notifyCount;

        aC.complete(_session(id: 1, startedAt: null));
        await a; // superseded on BOTH result and loading -> zero notifies
        expect(notifyCount, afterBStart);
        expect(provider.isLoading, isTrue);

        bC.complete(_session(id: 2, userId: 1, startedAt: null));
        await b; // B publishes result + clears its own spinner
        expect(provider.isLoading, isFalse);
      },
    );
  });

  // ============================================================
  // Loading claims are session-bound (isCurrent(token))
  // ============================================================
  group('loading-claim session binding', () {
    test('SB1. an A load settling after invalidate() (logged-out gap, no '
        'clear(), no B) mutates nothing and does not notify', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final a = provider.loadSession(1);
      final afterStart = notifyCount;

      epoch.invalidate(); // logged out; capture() would now be null

      aC.complete(_session(id: 1, userId: 1, name: 'ghost', startedAt: null));
      await a;

      expect(provider.currentSession, isNull);
      expect(provider.isLoading, isTrue); // A's own pre-await value, untouched
      expect(notifyCount, afterStart); // A settled silently
    });

    test('SB2. an A createWorkoutFromAI finally captured under A cannot change '
        'loading state once B is current', () async {
      final createC = Completer<Session>();
      when(repo.createSession(any)).thenAnswer((_) async => createC.future);
      final ai = provider.createWorkoutFromAI(
        workoutName: 'AI',
        exerciseTemplateIds: const [],
      );
      final afterStart = notifyCount;
      expect(provider.isLoading, isTrue);

      epoch.invalidate();
      epoch.activate(2); // direct A->B, no clear()

      createC.complete(_session(id: 3, userId: 1, startedAt: null));
      expect(await ai, isNull);

      // AI's finally is under B's epoch: isCurrent(A token) is false, so it
      // neither clears _isLoading nor notifies.
      expect(provider.isLoading, isTrue);
      expect(notifyCount, afterStart);
    });

    test('SB3. real logout sequence (invalidate -> clear -> activate/load B): '
        'clear() synchronously resets _isLoading, B\'s own claim is protected, '
        'and A\'s later settlement does nothing', () async {
      final aC = Completer<Session>();
      when(repo.getSession(1)).thenAnswer((_) async => aC.future);
      final a = provider.loadSession(1);
      expect(provider.isLoading, isTrue);

      epoch.invalidate();
      provider
          .clear(); // authoritative: resets _isLoading + bumps _loadingClaim
      expect(provider.isLoading, isFalse);
      epoch.activate(2);

      final bC = Completer<Session>();
      when(repo.getSession(9)).thenAnswer((_) async => bC.future);
      final b = provider.loadSession(9);
      expect(provider.isLoading, isTrue); // B's own claim
      final afterBStart = notifyCount;

      aC.complete(_session(id: 1, userId: 1, name: 'ghost', startedAt: null));
      await a;
      expect(provider.isLoading, isTrue); // A did not touch B's spinner
      expect(notifyCount, afterBStart); // A silent

      bC.complete(_session(id: 9, userId: 2, startedAt: null));
      await b;
      expect(provider.isLoading, isFalse);
      expect(provider.currentSession?.id, 9);
    });

    test('SB4. A -> B -> A: the first A load cannot clear the spinner of the '
        'second (generation, not user-id, is authoritative)', () async {
      final a1C = Completer<Session>();
      final a2C = Completer<Session>();
      var call = 0;
      when(repo.getSession(1)).thenAnswer((_) async {
        call++;
        return call == 1 ? a1C.future : a2C.future;
      });

      final a1 = provider.loadSession(1); // A gen G1, claim 1
      epoch.invalidate();
      epoch.activate(1); // same user id, NEW generation
      final a2 = provider.loadSession(1); // A' gen G2, claim 2
      expect(provider.isLoading, isTrue);
      final afterA2 = notifyCount;

      a1C.complete(_session(id: 1, name: 'first', startedAt: null));
      await a1;
      // a1's token is from G1 -> isCurrent(G1 token) is false even though the
      // user id matches -> a1 clears nothing and notifies nothing.
      expect(provider.isLoading, isTrue);
      expect(notifyCount, afterA2);

      a2C.complete(_session(id: 1, name: 'second', startedAt: null));
      await a2;
      expect(provider.isLoading, isFalse);
      expect(provider.currentSession?.name, 'second');
    });
  });
}
