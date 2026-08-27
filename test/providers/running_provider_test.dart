import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:go_hard_app/data/models/run_session.dart';
import 'package:go_hard_app/data/repositories/running_repository.dart';
import 'package:go_hard_app/providers/running_provider.dart';

import 'running_provider_test.mocks.dart';

/// Regression coverage for Running Finding R1: RunSession.copyWith could not
/// explicitly clear pausedAt, so RunningProvider.resumeRun() left a stale
/// in-memory pausedAt after resuming. _recalculateElapsedTime() (invoked on
/// app-lifecycle resume) then treated the run as still paused, freezing
/// elapsed time at the original pause point and discarding all time since
/// the actual resume - including into a persisted finishRun() duration.
///
/// These tests never simulate real OS suspension or use real sleeps. They:
///   - dispatch AppLifecycleState.resumed directly via
///     provider.didChangeAppLifecycleState, mirroring
///     active_workout_provider_lifecycle_test.dart,
///   - use an injectable `nowUtc` clock (mirroring ActiveWorkoutProvider's
///     established pattern) so "time passed while suspended" is
///     deterministic, scoped only to lifecycle recalculation - pauseRun()/
///     resumeRun() intentionally still use the real wall clock, exactly as
///     in the ActiveWorkoutProvider precedent, since fixing that is out of
///     this PR's scope,
///   - use fakeAsync to make Timer.periodic ticking deterministic.
///
/// GPS suspend/resume handling (Finding R2) is explicitly NOT implemented or
/// tested here. _FakeGeolocatorPlatform below exists only to neutralize the
/// real location plugin so resumeRun()'s existing _startGpsTracking() call
/// does not throw a MissingPluginException in a unit-test environment - it
/// asserts nothing about GPS behavior itself.
class _FakeGeolocatorPlatform extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    return const Stream<Position>.empty();
  }
}

@GenerateMocks([RunningRepository])
RunSession _run({
  int id = 1,
  String status = 'in_progress',
  DateTime? startedAt,
  DateTime? pausedAt,
}) {
  return RunSession(
    id: id,
    userId: 1,
    date: DateTime.utc(2024, 1, 15),
    status: status,
    startedAt: startedAt,
    pausedAt: pausedAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GeolocatorPlatform.instance = _FakeGeolocatorPlatform();

  late MockRunningRepository mockRepo;
  late DateTime fakeNow;
  late RunningProvider provider;

  setUp(() {
    mockRepo = MockRunningRepository();
    // loadRun() intentionally still uses the real wall clock (out of scope
    // for this fix - only lifecycle recalculation uses the injectable
    // clock). Anchor fakeNow to the real "now" at setup so the initial
    // load's elapsed time starts at ~0, then advance it deterministically
    // to represent time passing while the app is suspended.
    fakeNow = DateTime.now().toUtc();
    provider = RunningProvider(mockRepo, null, () => fakeNow);
  });

  tearDown(() {
    try {
      provider.dispose();
    } catch (_) {
      // Already disposed by the test body.
    }
  });

  group('pauseRun', () {
    test('sets an in-memory pausedAt and stops the ticker', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));

        provider.loadRun(1);
        async.flushMicrotasks();
        expect(provider.currentRun!.pausedAt, isNull);
        expect(provider.isTimerRunning, true);

        provider.pauseRun();
        async.flushMicrotasks();

        expect(provider.currentRun!.pausedAt, isNotNull);
        expect(provider.isTimerRunning, false);
        verify(mockRepo.pauseRun(1, any)).called(1);
      });
    });
  });

  group('resumeRun - clears stale pausedAt (the R1 regression)', () {
    test('clears in-memory pausedAt', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.resumeRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));

        provider.loadRun(1);
        async.flushMicrotasks();

        provider.pauseRun();
        async.flushMicrotasks();
        expect(provider.currentRun!.pausedAt, isNotNull);

        // THIS is the regression: before the fix,
        // copyWith(pausedAt: null) silently kept the old pausedAt.
        provider.resumeRun();
        async.flushMicrotasks();

        expect(
          provider.currentRun!.pausedAt,
          isNull,
          reason:
              'resumeRun() must actually clear pausedAt via '
              'clearPausedAt: true, not the no-op pausedAt: null',
        );
        expect(provider.isTimerRunning, true);
      });
    });

    test('shifts startedAt forward to exclude the user-paused duration', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.resumeRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));

        provider.loadRun(1);
        async.flushMicrotasks();

        provider.pauseRun();
        async.flushMicrotasks();

        provider.resumeRun();
        async.flushMicrotasks();

        // pauseRun()/resumeRun() intentionally still use the real wall
        // clock (out of scope for this fix), so the actual pause duration
        // in a fast-executing test is a few microseconds - bounded rather
        // than exact, but still fails hard against the pre-fix bug (which
        // left startedAt unchanged from copyWith's own perspective on
        // pausedAt, not startedAt directly - this asserts the adjustment
        // this fix must not disturb).
        expect(
          provider.currentRun!.startedAt!.isAfter(startedAt) ||
              provider.currentRun!.startedAt!.isAtSameMomentAs(startedAt),
          isTrue,
          reason:
              'startedAt must be shifted forward by the pause duration, '
              'never backward',
        );

        final captured =
            verify(mockRepo.resumeRun(1, captureAny)).captured.single
                as DateTime;
        expect(captured, provider.currentRun!.startedAt);
        expect(
          captured.isAfter(startedAt) || captured.isAtSameMomentAs(startedAt),
          isTrue,
        );
      });
    });

    test('plain pause/resume (no app suspend) excludes the paused duration '
        'from elapsed time - the ticker does not advance while paused', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.resumeRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));

        provider.loadRun(1);
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 10));
        expect(provider.elapsedTime.inSeconds, 10);

        provider.pauseRun();
        async.flushMicrotasks();

        // Fake timer time elapses while paused - must produce zero ticks.
        async.elapse(const Duration(minutes: 3));
        expect(
          provider.elapsedTime.inSeconds,
          10,
          reason: 'elapsed time must not advance while explicitly paused',
        );

        provider.resumeRun();
        async.flushMicrotasks();

        // Immediately after resume, elapsed time picks up exactly where
        // it left off - the paused 3 minutes contributed nothing.
        expect(provider.elapsedTime.inSeconds, 10);

        async.elapse(const Duration(seconds: 5));
        expect(provider.elapsedTime.inSeconds, 15);
      });
    });
  });

  group('pause -> resume -> app-lifecycle resumed '
      '(the exact regression scenario)', () {
    test('elapsed time does not jump backward, includes time since resume, '
        'and the run is no longer treated as paused', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.resumeRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));

        provider.loadRun(1);
        async.flushMicrotasks();

        // Run for a bit, then pause.
        async.elapse(const Duration(seconds: 30));
        provider.pauseRun();
        async.flushMicrotasks();

        // Resume via the button.
        provider.resumeRun();
        async.flushMicrotasks();
        expect(provider.currentRun!.pausedAt, isNull);
        expect(provider.isTimerRunning, true);

        // Now the app is backgrounded and foregrounded - represented
        // via the injected clock, which only _recalculateElapsedTime()
        // consults.
        fakeNow = fakeNow.add(const Duration(minutes: 10));
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        // THE key proof: if pausedAt were still stuck non-null (the
        // pre-fix bug), _recalculateElapsedTime() would compute a
        // stale pausedAt-vs-startedAt difference (frozen at the
        // original ~30s pause point) instead of the correct
        // nowUtc-vs-startedAt one, and elapsed time would jump
        // BACKWARD from whatever the ticker had reached.
        expect(
          provider.elapsedTime,
          greaterThan(const Duration(minutes: 9, seconds: 59)),
          reason:
              'elapsed time must reflect time since the actual resume, '
              'not freeze at the pre-resume pause point',
        );
        expect(
          provider.elapsedTime,
          lessThanOrEqualTo(const Duration(minutes: 10, seconds: 1)),
        );

        // A fresh ticker still advances normally afterward - proves
        // the run is not misclassified as paused going forward.
        final before = provider.elapsedTime;
        async.elapse(const Duration(seconds: 5));
        expect(provider.elapsedTime - before, const Duration(seconds: 5));
      });
    });

    test('finishRun persists the correct duration, not the stale '
        'pre-resume duration', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.resumeRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.getRecentRuns(limit: anyNamed('limit')),
        ).thenAnswer((_) async => <RunSession>[]);
        when(
          mockRepo.getWeeklyStats(),
        ).thenAnswer((_) async => <String, dynamic>{});
        when(
          mockRepo.completeRun(
            1,
            duration: anyNamed('duration'),
            distance: anyNamed('distance'),
            averagePace: anyNamed('averagePace'),
            calories: anyNamed('calories'),
            route: anyNamed('route'),
          ),
        ).thenAnswer(
          (_) async => _run(startedAt: startedAt, status: 'completed'),
        );

        provider.loadRun(1);
        async.flushMicrotasks();

        provider.pauseRun();
        async.flushMicrotasks();
        provider.resumeRun();
        async.flushMicrotasks();

        fakeNow = fakeNow.add(const Duration(minutes: 10));
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

        final elapsedBeforeFinish = provider.elapsedTime;
        expect(
          elapsedBeforeFinish,
          greaterThan(const Duration(minutes: 9, seconds: 59)),
          reason:
              'sanity check: the pre-finish elapsed time must '
              'already reflect the corrected (post-fix) value',
        );

        provider.finishRun();
        async.flushMicrotasks();

        final capturedDuration =
            verify(
                  mockRepo.completeRun(
                    1,
                    duration: captureAnyNamed('duration'),
                    distance: anyNamed('distance'),
                    averagePace: anyNamed('averagePace'),
                    calories: anyNamed('calories'),
                    route: anyNamed('route'),
                  ),
                ).captured.single
                as int;

        expect(
          capturedDuration,
          elapsedBeforeFinish.inSeconds,
          reason:
              'finishRun() must persist the elapsed time that was '
              'already corrected by _recalculateElapsedTime(), not a '
              'stale pre-resume duration frozen by the R1 bug',
        );
      });
    });
  });

  group('repeated pause/resume cycles', () {
    test('do not accumulate stale pausedAt state across cycles', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.resumeRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));

        provider.loadRun(1);
        async.flushMicrotasks();

        for (var cycle = 0; cycle < 4; cycle++) {
          provider.pauseRun();
          async.flushMicrotasks();
          expect(
            provider.currentRun!.pausedAt,
            isNotNull,
            reason: 'cycle $cycle: pauseRun must record pausedAt',
          );

          provider.resumeRun();
          async.flushMicrotasks();
          expect(
            provider.currentRun!.pausedAt,
            isNull,
            reason:
                'cycle $cycle: pausedAt must clear every time, not just '
                'the first',
          );
          expect(provider.isTimerRunning, true);

          // A lifecycle resume in between each cycle must never re-freeze
          // elapsed time via a stale pausedAt from a previous cycle.
          fakeNow = fakeNow.add(const Duration(seconds: 30));
          provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
          expect(provider.currentRun!.pausedAt, isNull);
        }
      });
    });
  });

  group('resumeRun repository-failure behavior (unchanged by this fix)', () {
    test('resumeRun still clears pausedAt and keeps the ticker running even if '
        'persisting the resume to the repository fails (existing optimistic '
        'update behavior is locked down, not redesigned, by this fix)', () {
      fakeAsync((async) {
        final startedAt = fakeNow;
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: startedAt));
        when(mockRepo.resumeRun(1, any)).thenThrow(Exception('network error'));

        provider.loadRun(1);
        async.flushMicrotasks();

        provider.pauseRun();
        async.flushMicrotasks();

        provider.resumeRun();
        async.flushMicrotasks();

        expect(provider.currentRun!.pausedAt, isNull);
        expect(provider.isTimerRunning, true);
        expect(provider.errorMessage, isNotNull);
      });
    });
  });

  group('constructor compatibility', () {
    test('existing call sites (repository-only, and repository + '
        'connectivity) remain valid with no clock argument', () {
      final p1 = RunningProvider(mockRepo);
      p1.dispose();

      final p2 = RunningProvider(mockRepo, null);
      p2.dispose();
    });
  });
}
