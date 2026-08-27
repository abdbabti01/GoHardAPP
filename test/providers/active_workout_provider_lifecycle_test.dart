import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';

import 'active_workout_provider_navigation_test.mocks.dart';

/// Lifecycle behavior tests for the app-suspend/resume workout timer fix.
///
/// iOS suspends the process while the screen is locked or the app is
/// backgrounded - Timer.periodic cannot be relied on to keep ticking (or
/// even to exist reliably) across that window, so these tests never try to
/// simulate real OS suspension. Instead they:
///   - dispatch the exact same AppLifecycleState values the OS would
///     (via provider.didChangeAppLifecycleState, or via
///     WidgetsBinding.instance for the disposal test, which is the only
///     way to prove observer removal rather than assuming it),
///   - use an injectable `nowUtc` clock to make "time passed while
///     suspended" deterministic without any real waiting,
///   - use fakeAsync to make Timer.periodic ticking deterministic and to
///     detect duplicate tickers (an unexpected 2x/3x rate).
Session _session({
  int id = 1,
  String status = 'in_progress',
  DateTime? startedAt,
  DateTime? pausedAt,
  int version = 1,
}) {
  return Session(
    id: id,
    userId: 1,
    date: DateTime.utc(2024, 1, 15),
    status: status,
    startedAt: startedAt,
    pausedAt: pausedAt,
    version: version,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSessionRepository mockRepo;
  late DateTime fakeNow;
  late ActiveWorkoutProvider provider;

  setUp(() {
    mockRepo = MockSessionRepository();
    // loadSession() intentionally still uses the real wall clock (out of
    // scope for this narrowly-targeted fix - only lifecycle recalculation
    // uses the injectable clock). Anchor fakeNow to the real "now" at
    // setup so the initial load's elapsed time starts at ~0, then advance
    // it deterministically from there to represent time passing while the
    // app is suspended.
    fakeNow = DateTime.now().toUtc();
    provider = ActiveWorkoutProvider(mockRepo, null, () => fakeNow);
  });

  tearDown(() {
    // The disposal tests below dispose the provider themselves mid-test to
    // observe post-dispose behavior; guard against disposing it twice.
    try {
      provider.dispose();
    } catch (_) {
      // Already disposed by the test body - nothing further to clean up.
    }
  });

  group('Running workout - suspend and resume', () {
    test('timer is initially active, paused/hidden lifecycle stops the ticker, '
        'suspended fake time produces no ticks, and resumed recalculates '
        'immediately then a fresh ticker advances normally', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: startedAt));

        provider.loadSession(1);
        async.flushMicrotasks();

        expect(provider.isTimerRunning, true);
        expect(provider.elapsedTime.inSeconds, 0);

        // A few real ticks before the phone is locked.
        async.elapse(const Duration(seconds: 30));
        expect(provider.elapsedTime.inSeconds, 30);

        // Lock the screen.
        provider.didChangeAppLifecycleState(AppLifecycleState.paused);
        expect(
          provider.isTimerRunning,
          false,
          reason: 'the UI ticker must stop as soon as the app suspends',
        );

        // The phone stays locked for 10 minutes. No wall-clock time
        // passes for fakeAsync's Timer scheduling (iOS gives the
        // process no CPU time at all while suspended), but the
        // injectable clock advances to represent the real time that
        // passed - this is the deterministic stand-in for "time spent
        // locked" without a real OS suspension or a real sleep.
        fakeNow = fakeNow.add(
          const Duration(seconds: 30) + const Duration(minutes: 10),
        );

        // Even if something were to elapse fake Timer time while
        // "suspended", no ticks should occur because the ticker is
        // stopped - elapsedTime must stay exactly where it was.
        async.elapse(const Duration(seconds: 5));
        expect(
          provider.elapsedTime.inSeconds,
          30,
          reason:
              'elapsedTime must not advance via Timer.periodic while '
              'the app is suspended',
        );

        // Unlock and return to the app.
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        expect(
          provider.elapsedTime,
          const Duration(minutes: 10, seconds: 30),
          reason:
              'resumed must recalculate elapsed time from timestamps '
              'immediately, including the time spent locked',
        );
        expect(provider.isTimerRunning, true);

        // A fresh ticker must now advance normally, at exactly 1x.
        async.elapse(const Duration(seconds: 5));
        expect(provider.elapsedTime, const Duration(minutes: 10, seconds: 35));
      });
    });

    test('hidden also stops the ticker (not just paused)', () {
      fakeAsync((async) {
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: fakeNow));
        provider.loadSession(1);
        async.flushMicrotasks();
        expect(provider.isTimerRunning, true);

        provider.didChangeAppLifecycleState(AppLifecycleState.hidden);
        expect(provider.isTimerRunning, false);
      });
    });

    test('inactive also stops the ticker', () {
      fakeAsync((async) {
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: fakeNow));
        provider.loadSession(1);
        async.flushMicrotasks();
        expect(provider.isTimerRunning, true);

        provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
        expect(provider.isTimerRunning, false);
      });
    });
  });

  group('Paused workout - suspend and resume', () {
    test('lifecycle transitions never advance elapsed time, and resumed does '
        'not start a ticker', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        final pausedAt = fakeNow.add(const Duration(minutes: 5));
        when(mockRepo.getSession(1)).thenAnswer(
          (_) async => _session(startedAt: startedAt, pausedAt: pausedAt),
        );

        provider.loadSession(1);
        async.flushMicrotasks();

        expect(provider.isTimerRunning, false);
        expect(provider.elapsedTime, const Duration(minutes: 5));

        // Time passes while the phone is locked, paused.
        fakeNow = fakeNow.add(const Duration(hours: 2));

        provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
        expect(provider.elapsedTime, const Duration(minutes: 5));
        expect(provider.isTimerRunning, false);

        provider.didChangeAppLifecycleState(AppLifecycleState.hidden);
        expect(provider.elapsedTime, const Duration(minutes: 5));

        provider.didChangeAppLifecycleState(AppLifecycleState.paused);
        expect(provider.elapsedTime, const Duration(minutes: 5));

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        // Still exactly the paused duration - the 2 "locked" hours must
        // never be added to a paused workout.
        expect(provider.elapsedTime, const Duration(minutes: 5));
        expect(
          provider.isTimerRunning,
          false,
          reason: 'resuming a paused workout must not start a ticker',
        );

        // And no ticks occur afterward either.
        async.elapse(const Duration(seconds: 10));
        expect(provider.elapsedTime, const Duration(minutes: 5));
      });
    });
  });

  group('Repeated lifecycle cycles', () {
    test('inactive -> paused -> resumed, then hidden -> resumed, then multiple '
        'resumed events in a row: elapsed time stays correct and the ticker '
        'never duplicates (fake time always advances at exactly 1x)', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: startedAt));

        provider.loadSession(1);
        async.flushMicrotasks();
        expect(provider.isTimerRunning, true);

        // Cycle 1: inactive -> paused -> resumed.
        provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
        provider.didChangeAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 3));
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(provider.elapsedTime, const Duration(minutes: 3));
        expect(provider.isTimerRunning, true);

        // Cycle 2: hidden -> resumed.
        provider.didChangeAppLifecycleState(AppLifecycleState.hidden);
        fakeNow = fakeNow.add(const Duration(minutes: 2));
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(provider.elapsedTime, const Duration(minutes: 5));
        expect(provider.isTimerRunning, true);

        // Cycle 3: multiple resumed events in a row with no suspend in
        // between (e.g. duplicate platform callbacks) must not create a
        // second ticker.
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(provider.elapsedTime, const Duration(minutes: 5));
        expect(provider.isTimerRunning, true);

        // If a duplicate ticker existed, this would advance by 2x/3x
        // instead of exactly 1x.
        final before = provider.elapsedTime;
        async.elapse(const Duration(seconds: 10));
        expect(provider.elapsedTime - before, const Duration(seconds: 10));
      });
    });
  });

  group('No reload on resume', () {
    test('a full suspend/resume cycle for an in-progress session never calls '
        'the repository again after the initial load', () {
      fakeAsync((async) {
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: fakeNow));

        provider.loadSession(1);
        async.flushMicrotasks();
        verify(mockRepo.getSession(1)).called(1);
        clearInteractions(mockRepo);

        provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
        provider.didChangeAppLifecycleState(AppLifecycleState.hidden);
        provider.didChangeAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 20));
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        // Zero repository interactions of any kind - the strongest
        // available proof that startedAt/pausedAt/status/version and any
        // sync/conflict metadata (which live only in the repository/Isar
        // layer, not on the in-memory Session model) cannot have been
        // touched, since nothing was ever read from or written to it.
        verifyZeroInteractions(mockRepo);
      });
    });
  });

  group('State preservation across suspend/resume', () {
    test('startedAt, pausedAt, status and version are unchanged after a full '
        'suspend/resume cycle (running workout)', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(mockRepo.getSession(1)).thenAnswer(
          (_) async =>
              _session(startedAt: startedAt, status: 'in_progress', version: 7),
        );

        provider.loadSession(1);
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.paused);
        fakeNow = fakeNow.add(const Duration(minutes: 15));
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        expect(provider.currentSession!.startedAt, startedAt);
        expect(provider.currentSession!.pausedAt, isNull);
        expect(provider.currentSession!.status, 'in_progress');
        expect(provider.currentSession!.version, 7);
      });
    });

    test('startedAt, pausedAt, status and version are unchanged after a full '
        'suspend/resume cycle (paused workout)', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        final pausedAt = fakeNow.add(const Duration(minutes: 1));
        when(mockRepo.getSession(1)).thenAnswer(
          (_) async =>
              _session(startedAt: startedAt, pausedAt: pausedAt, version: 4),
        );

        provider.loadSession(1);
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
        fakeNow = fakeNow.add(const Duration(hours: 1));
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        expect(provider.currentSession!.startedAt, startedAt);
        expect(provider.currentSession!.pausedAt, pausedAt);
        expect(provider.currentSession!.status, 'in_progress');
        expect(provider.currentSession!.version, 4);
      });
    });
  });

  group('Manual pause/resume interacting with app suspend/resume '
      '(regression: pausedAt must actually clear)', () {
    test('pauseTimer -> resumeTimer actually clears pausedAt, and the '
        'workout correctly recovers across a subsequent lock/unlock cycle', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: startedAt));
        when(mockRepo.pauseSession(1, any)).thenAnswer((_) async {});
        when(mockRepo.resumeSession(1, any)).thenAnswer((_) async {});

        provider.loadSession(1);
        async.flushMicrotasks();
        expect(provider.isTimerRunning, true);

        // Run for a bit before pausing.
        async.elapse(const Duration(seconds: 20));
        expect(provider.elapsedTime.inSeconds, 20);

        // pauseTimer()/resumeTimer() intentionally still use the real
        // wall clock (out of scope for this fix) - only the
        // subsequent lifecycle recalculation below uses fakeNow.
        provider.pauseTimer();
        async.flushMicrotasks();
        expect(
          provider.currentSession!.pausedAt,
          isNotNull,
          reason: 'pauseTimer() must record a pausedAt timestamp',
        );
        expect(provider.isTimerRunning, false);

        // While paused, no ticks occur even if fake timer time elapses.
        async.elapse(const Duration(seconds: 30));
        expect(provider.elapsedTime.inSeconds, 20);

        // Resume via the button. THIS is the regression: before the
        // fix, copyWith(pausedAt: null) silently kept the old pausedAt.
        provider.resumeTimer();
        async.flushMicrotasks();
        expect(
          provider.currentSession!.pausedAt,
          isNull,
          reason:
              'resumeTimer() must actually clear pausedAt via '
              'clearPausedAt: true, not the no-op pausedAt: null',
        );
        expect(provider.isTimerRunning, true);
        verify(mockRepo.pauseSession(1, any)).called(1);
        verify(mockRepo.resumeSession(1, any)).called(1);

        // Now lock the phone.
        provider.didChangeAppLifecycleState(AppLifecycleState.paused);
        expect(
          provider.isTimerRunning,
          false,
          reason:
              'if pausedAt had not been cleared, _shouldHaveRunningTicker '
              'would already be permanently false regardless of this '
              'suspend - but suspending must stop the ticker either way',
        );

        // Time passes while locked - represented via the injected
        // clock, which only _recalculateElapsedTime() consults.
        fakeNow = fakeNow.add(const Duration(minutes: 5));

        // Unlock.
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        // Bounded rather than exact: resumeTimer() shifts startedAt
        // forward by the REAL pause duration between the
        // pauseTimer()/resumeTimer() calls above (both real-clock
        // based, out of this fix's scope), which is a few
        // microseconds in a fast-executing test - just under the 5
        // fakeNow-minutes added below. A tight bound here still fails
        // hard on the actual regression (a stuck pausedAt would give
        // ~0 or a wildly different value, not "4:59.999ish").
        expect(
          provider.elapsedTime,
          greaterThan(const Duration(minutes: 4, seconds: 59)),
          reason:
              'THE key proof: if pausedAt were still stuck non-null '
              '(the pre-fix bug), _shouldHaveRunningTicker would be '
              'false and the ticker would never restart, and/or '
              '_recalculateElapsedTime would compute a stale '
              'pausedAt-vs-startedAt difference instead of the correct '
              'nowUtc-vs-startedAt one',
        );
        expect(
          provider.elapsedTime,
          lessThanOrEqualTo(const Duration(minutes: 5)),
        );
        expect(provider.isTimerRunning, true);

        // Exactly one ticker afterward.
        final before = provider.elapsedTime;
        async.elapse(const Duration(seconds: 10));
        expect(provider.elapsedTime - before, const Duration(seconds: 10));
      });
    });

    test('repeated pause/resume/lock/unlock cycles never freeze or '
        'duplicate the ticker, and elapsed time remains monotonic', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: startedAt));
        when(mockRepo.pauseSession(1, any)).thenAnswer((_) async {});
        when(mockRepo.resumeSession(1, any)).thenAnswer((_) async {});

        provider.loadSession(1);
        async.flushMicrotasks();

        var previousElapsed = provider.elapsedTime;

        for (var cycle = 0; cycle < 3; cycle++) {
          async.elapse(const Duration(seconds: 5));
          expect(
            provider.elapsedTime,
            greaterThan(previousElapsed),
            reason: 'cycle $cycle: ticker must still be advancing',
          );
          previousElapsed = provider.elapsedTime;

          provider.pauseTimer();
          async.flushMicrotasks();
          expect(provider.currentSession!.pausedAt, isNotNull);

          provider.resumeTimer();
          async.flushMicrotasks();
          expect(
            provider.currentSession!.pausedAt,
            isNull,
            reason: 'cycle $cycle: pausedAt must clear every time',
          );
          expect(provider.isTimerRunning, true);

          provider.didChangeAppLifecycleState(AppLifecycleState.paused);
          expect(provider.isTimerRunning, false);

          fakeNow = fakeNow.add(const Duration(minutes: 1));
          provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
          expect(
            provider.isTimerRunning,
            true,
            reason: 'cycle $cycle: ticker must not be permanently frozen',
          );
          expect(
            provider.elapsedTime,
            greaterThan(previousElapsed),
            reason: 'cycle $cycle: elapsed time must remain monotonic',
          );
          previousElapsed = provider.elapsedTime;
        }

        // No duplicate ticker after all these cycles: exactly 1x rate.
        final before = provider.elapsedTime;
        async.elapse(const Duration(seconds: 10));
        expect(provider.elapsedTime - before, const Duration(seconds: 10));
      });
    });
  });

  group('Full recovery for a single suspend state alone (not just paused)', () {
    test('inactive alone -> resumed: full recovery (value + ticker)', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: startedAt));
        provider.loadSession(1);
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
        expect(provider.isTimerRunning, false);

        fakeNow = fakeNow.add(const Duration(minutes: 4));
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        expect(provider.elapsedTime.inMinutes, 4);
        expect(provider.isTimerRunning, true);

        async.elapse(const Duration(seconds: 5));
        expect(provider.elapsedTime, const Duration(minutes: 4, seconds: 5));
      });
    });

    test('hidden alone -> resumed: full recovery (value + ticker)', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: startedAt));
        provider.loadSession(1);
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.hidden);
        expect(provider.isTimerRunning, false);

        fakeNow = fakeNow.add(const Duration(minutes: 7));
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        expect(provider.elapsedTime.inMinutes, 7);
        expect(provider.isTimerRunning, true);

        async.elapse(const Duration(seconds: 5));
        expect(provider.elapsedTime, const Duration(minutes: 7, seconds: 5));
      });
    });
  });

  group('resumeTimer repository interaction', () {
    test(
      'resumeTimer calls resumeSession exactly once with this session\'s id',
      () {
        fakeAsync((async) {
          final startedAt = fakeNow;
          final pausedAt = fakeNow.add(const Duration(minutes: 2));
          when(mockRepo.getSession(1)).thenAnswer(
            (_) async => _session(startedAt: startedAt, pausedAt: pausedAt),
          );
          when(mockRepo.resumeSession(1, any)).thenAnswer((_) async {});

          provider.loadSession(1);
          async.flushMicrotasks();

          provider.resumeTimer();
          async.flushMicrotasks();

          verify(mockRepo.resumeSession(1, any)).called(1);
        });
      },
    );

    test('resumeTimer still clears pausedAt and starts the ticker even if '
        'persisting the resume to the repository fails (optimistic UI update '
        'behavior is unchanged by this fix)', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        final pausedAt = fakeNow.add(const Duration(minutes: 2));
        when(mockRepo.getSession(1)).thenAnswer(
          (_) async => _session(startedAt: startedAt, pausedAt: pausedAt),
        );
        when(
          mockRepo.resumeSession(1, any),
        ).thenThrow(Exception('network error'));

        provider.loadSession(1);
        async.flushMicrotasks();

        provider.resumeTimer();
        async.flushMicrotasks();

        expect(provider.currentSession!.pausedAt, isNull);
        expect(provider.isTimerRunning, true);
        expect(provider.errorMessage, isNotNull);
      });
    });
  });

  group('Disposal', () {
    test('dispose() cancels the active ticker', () {
      fakeAsync((async) {
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: fakeNow));
        provider.loadSession(1);
        async.flushMicrotasks();
        expect(provider.isTimerRunning, true);

        provider.dispose();

        expect(provider.isTimerRunning, false);
      });
    });

    test('dispose() unregisters the lifecycle observer: a resumed event '
        'dispatched through WidgetsBinding afterward must not reach it', () {
      fakeAsync((async) {
        when(
          mockRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: fakeNow));
        provider.loadSession(1);
        async.flushMicrotasks();
        expect(provider.isTimerRunning, true);

        provider.dispose();

        // Dispatch through WidgetsBinding's real observer registry -
        // not a direct call on the disposed provider. If dispose() had
        // failed to call removeObserver(this), this would reach the
        // disposed provider's didChangeAppLifecycleState ->
        // _recalculateElapsedTime() -> notifyListeners(), which throws
        // on a disposed ChangeNotifier. A clean pass here is only
        // possible if the observer was actually removed.
        expect(
          () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
          returnsNormally,
        );
      });
    });
  });
}
