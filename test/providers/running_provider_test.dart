import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
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
/// Also covers Running Finding R2 (GPS subscription lifecycle, PR 1): the
/// explicit GpsTrackingState machine, generation/run-identity protection
/// against late callbacks, stream error/completion handling, awaited
/// cancellation, and lifecycle-driven recovery.
///
/// These tests never simulate real OS suspension or use real sleeps. They:
///   - dispatch AppLifecycleState.resumed/inactive/etc. directly via
///     provider.didChangeAppLifecycleState, mirroring
///     active_workout_provider_lifecycle_test.dart,
///   - use an injectable `nowUtc` clock (mirroring ActiveWorkoutProvider's
///     established pattern) so "time passed while suspended" is
///     deterministic, scoped only to lifecycle recalculation - pauseRun()/
///     resumeRun() intentionally still use the real wall clock, exactly as
///     in the ActiveWorkoutProvider precedent, since fixing that is out of
///     scope here,
///   - use fakeAsync to make Timer.periodic ticking deterministic,
///   - use _FakeGeolocatorPlatform/_FakePositionSubscription below, which
///     hand back a fully test-controlled fake StreamSubscription instead of
///     a real Stream. This is deliberate, not incidental: a real
///     StreamController's subscription synchronously stops delivering any
///     already-queued event the instant .cancel() is invoked on it (verified
///     empirically against this project's Dart SDK), which would make it
///     impossible to deliberately exercise "a late callback from an
///     obsolete generation arrives anyway" - exactly the scenario the
///     generation guard exists to protect against, mirroring a real
///     EventChannel where a native event already in flight can still reach
///     Dart just after local cancellation was requested but before the
///     platform side has honored it. The fake's deliverPosition/
///     deliverError/deliverDone methods invoke the callbacks
///     RunningProvider registered directly, unconditionally, independent of
///     the fake subscription's own cancelled/cancelGate state - the test,
///     not Dart's Stream machinery, decides when a "late" callback fires.
class _FakePositionSubscription implements StreamSubscription<Position> {
  void Function(Position)? _onData;
  Function? _onError;
  void Function()? _onDone;

  /// True once cancel() has been called on this subscription.
  bool cancelled = false;

  /// Controls when cancel()'s returned Future resolves. Null (the
  /// default) resolves immediately - set explicitly to test awaited
  /// cancellation with a controllable Future.
  Completer<void>? cancelGate;

  /// If set, cancel() throws this synchronously instead of returning a
  /// Future at all - simulates a StreamSubscription implementation that
  /// violates its own contract (cancel() is documented to always return a
  /// `Future<void>`), which RunningProvider must still not let escape.
  Object? throwSynchronouslyOnCancel;

  @override
  Future<void> cancel() {
    cancelled = true;
    final syncError = throwSynchronouslyOnCancel;
    if (syncError != null) throw syncError;
    final gate = cancelGate;
    return gate != null ? gate.future : Future<void>.value();
  }

  /// Simulates the plugin delivering a position update, bypassing any Dart
  /// Stream cancel/delivery suppression - the test decides unconditionally
  /// whether this fires, including "after" this subscription was told to
  /// cancel.
  void deliverPosition(Position position) => _onData?.call(position);

  /// Simulates the plugin delivering a stream error.
  void deliverError(Object error) {
    final handler = _onError;
    if (handler == null) return;
    if (handler is void Function(Object, StackTrace)) {
      handler(error, StackTrace.empty);
    } else if (handler is void Function(Object)) {
      handler(error);
    }
  }

  /// Simulates the plugin's stream completing.
  void deliverDone() => _onDone?.call();

  void bind({
    required void Function(Position)? onData,
    required Function? onError,
    required void Function()? onDone,
  }) {
    _onData = onData;
    _onError = onError;
    _onDone = onDone;
  }

  @override
  bool get isPaused => false;

  @override
  void pause([Future<void>? resumeSignal]) {
    throw UnimplementedError('pause() is not used by RunningProvider');
  }

  @override
  void resume() {
    throw UnimplementedError('resume() is not used by RunningProvider');
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) {
    throw UnimplementedError('asFuture() is not used by RunningProvider');
  }

  @override
  void onData(void Function(Position data)? handleData) {
    _onData = handleData;
  }

  @override
  void onError(Function? handleError) {
    _onError = handleError;
  }

  @override
  void onDone(void Function()? handleDone) {
    _onDone = handleDone;
  }
}

class _FakePositionStream extends Stream<Position> {
  _FakePositionStream(this.subscription, {this.throwOnListen});

  final _FakePositionSubscription subscription;

  /// If set, listen() throws this instead of returning a subscription -
  /// simulates a platform rejecting listen() synchronously (e.g. "already
  /// listening"), which RunningProvider must not let strand its state.
  final Object? throwOnListen;

  @override
  StreamSubscription<Position> listen(
    void Function(Position event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final error = throwOnListen;
    if (error != null) throw error;
    subscription.bind(onData: onData, onError: onError, onDone: onDone);
    return subscription;
  }
}

class _FakeGeolocatorPlatform extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  /// Every subscription ever handed out by getPositionStream(), in call
  /// order - lets tests assert exactly how many subscriptions were
  /// created (duplicate detection) and drive/inspect any of them
  /// individually, including ones superseded by a later call.
  final List<_FakePositionSubscription> subscriptions = [];

  /// The exact LocationSettings passed to each getPositionStream() call,
  /// in the same order as [subscriptions] - lets tests assert exactly
  /// which settings (AppleSettings vs. the plain LocationSettings) were
  /// used for a given subscription attempt.
  final List<LocationSettings?> locationSettingsPerCall = [];

  /// If set, the *next* getPositionStream().listen() call throws this
  /// instead of succeeding, then is cleared. See _FakePositionStream.
  Object? throwOnNextListen;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    final subscription = _FakePositionSubscription();
    subscriptions.add(subscription);
    locationSettingsPerCall.add(locationSettings);
    final error = throwOnNextListen;
    throwOnNextListen = null;
    return _FakePositionStream(subscription, throwOnListen: error);
  }
}

Position _fakePosition({double latitude = 37.0, double longitude = -122.0}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.now().toUtc(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
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

  late MockRunningRepository mockRepo;
  late DateTime fakeNow;
  late RunningProvider provider;
  late _FakeGeolocatorPlatform fakePlatform;

  setUp(() {
    fakePlatform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = fakePlatform;
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
    // Reset any per-test platform override so it can never leak into a
    // later test - safe to call even if a test never set one.
    debugDefaultTargetPlatformOverride = null;
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
        async.flushMicrotasks();

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
        async.flushMicrotasks();

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
          async.flushMicrotasks();
          expect(provider.currentRun!.pausedAt, isNull);
        }
      });
    });
  });

  group('resumeRun repository-failure behavior (unchanged by this fix)', () {
    test('resumeRun still clears pausedAt and keeps the ticker running even if '
        'persisting the resume to the repository fails (existing optimistic '
        'update behavior is locked down, not redesigned, by this fix), and '
        'GPS tracking still starts independently of the repository call', () {
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
        expect(
          provider.isGpsActive,
          isTrue,
          reason:
              'GPS start is independent of the repository resumeRun() call '
              '- the existing optimistic-update contract for GPS must be '
              'unaffected by a repository failure',
        );
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

  // ---------------------------------------------------------------------
  // Running Finding R2 (PR 1): GPS subscription lifecycle
  //
  // loadRun() alone never starts GPS (it only restores timer/route/distance
  // UI state for an existing run) - only startCurrentRun()/startNewRun()/
  // resumeRun() do. _startTrackedRun() below drives the same draft ->
  // startCurrentRun() flow ActiveRunScreen uses after the countdown, which
  // is the reliable way to get a genuinely GPS-tracking run in these tests.
  // ---------------------------------------------------------------------

  /// Loads run [id] as a draft, then starts it via startCurrentRun().
  /// Callers must stub mockRepo.getRunSession(id) to return a draft run and
  /// mockRepo.startRun(id) to return the started (in_progress) run before
  /// calling this.
  void startTrackedRun(FakeAsync async, {int id = 1}) {
    provider.loadRun(id);
    async.flushMicrotasks();
    provider.startCurrentRun();
    async.flushMicrotasks();
  }

  group('platform-specific location settings (iOS background delivery)', () {
    test('iOS uses AppleSettings with the exact required background-delivery '
        'values', () {
      fakeAsync((async) {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);

        expect(fakePlatform.locationSettingsPerCall.length, 1);
        final settings = fakePlatform.locationSettingsPerCall.single;
        expect(settings, isA<AppleSettings>());
        final apple = settings as AppleSettings;
        expect(
          apple.accuracy,
          LocationAccuracy.high,
          reason:
              'accuracy must be preserved at high, not raised to best - '
              'geolocator_apple 2.3.13 maps high to '
              'kCLLocationAccuracyNearestTenMeters and best to the '
              'materially higher-power kCLLocationAccuracyBest, and '
              'nothing about background delivery requires the increase',
        );
        expect(apple.distanceFilter, 5);
        expect(apple.activityType, ActivityType.fitness);
        expect(apple.pauseLocationUpdatesAutomatically, isFalse);
        expect(apple.showBackgroundLocationIndicator, isTrue);
        expect(apple.allowBackgroundLocationUpdates, isTrue);
      });
    });

    test('a lifecycle-triggered recovery on iOS also uses AppleSettings, not '
        'just the initial start', () {
      fakeAsync((async) {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(fakePlatform.locationSettingsPerCall.length, 2);
        expect(
          fakePlatform.locationSettingsPerCall.last,
          isA<AppleSettings>(),
          reason:
              'every subscription attempt must resolve settings fresh, '
              'not just the very first one',
        );
      });
    });

    test('a non-iOS platform (Android) keeps using the existing plain '
        'LocationSettings, unchanged by this PR', () {
      fakeAsync((async) {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);

        expect(fakePlatform.locationSettingsPerCall.length, 1);
        final settings = fakePlatform.locationSettingsPerCall.single;
        expect(
          settings,
          isNot(isA<AppleSettings>()),
          reason: 'Android must not receive iOS-specific settings',
        );
        expect(settings!.accuracy, LocationAccuracy.high);
        expect(settings.distanceFilter, 5);
      });
    });
  });

  group('GPS subscription ownership', () {
    test('starting a run creates exactly one subscription', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);

        expect(fakePlatform.subscriptions.length, 1);
        expect(provider.gpsTrackingState, GpsTrackingState.starting);
        expect(provider.isGpsActive, isTrue);
      });
    });

    test('repeated start calls do not create duplicate subscriptions', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        expect(fakePlatform.subscriptions.length, 1);

        // Calling startCurrentRun() again (e.g. a duplicate tap) must not
        // create a second subscription while the first is starting/active.
        provider.startCurrentRun();
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason: 'a duplicate start call must be a no-op for GPS',
        );
      });
    });

    test('a synchronous throw from getPositionStream().listen() marks '
        'tracking failed instead of leaving it stuck at starting', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        fakePlatform.throwOnNextListen = Exception('already listening');

        startTrackedRun(async);

        expect(
          provider.gpsTrackingState,
          GpsTrackingState.failed,
          reason:
              'a synchronous listen() failure must not strand the state '
              'at starting - nothing would ever move it out of starting '
              'since no callback was ever attached',
        );
        expect(provider.isGpsActive, isFalse);
        expect(provider.errorMessage, contains('already listening'));

        // A subsequent recovery attempt must still be able to try again
        // (starting is not a healthy state that blocks recovery).
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          2,
          reason: 'recovery must still be possible after the failed attempt',
        );
      });
    });

    test('user pause awaits cancellation before stopping tracking', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        expect(provider.isGpsActive, isTrue);

        final subscription = fakePlatform.subscriptions.single;
        final gate = Completer<void>();
        subscription.cancelGate = gate;

        var pauseCompleted = false;
        provider.pauseRun().then((_) => pauseCompleted = true);
        async.flushMicrotasks();

        expect(
          subscription.cancelled,
          isTrue,
          reason: 'cancel() must be requested synchronously by pauseRun()',
        );
        expect(
          pauseCompleted,
          isFalse,
          reason:
              'pauseRun() must not complete until cancellation actually '
              'finishes - it is genuinely awaited, not fire-and-forget',
        );
        expect(
          provider.currentRun!.pausedAt,
          isNull,
          reason:
              'pausedAt must not be set until the awaited cancellation '
              'has resolved',
        );

        gate.complete();
        async.flushMicrotasks();

        expect(pauseCompleted, isTrue);
        expect(provider.currentRun!.pausedAt, isNotNull);
        expect(provider.gpsTrackingState, GpsTrackingState.stopped);
        expect(provider.isGpsActive, isFalse);
      });
    });

    test('user resume creates exactly one new subscription', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.resumeRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        expect(fakePlatform.subscriptions.length, 1);

        provider.pauseRun();
        async.flushMicrotasks();

        provider.resumeRun();
        async.flushMicrotasks();

        expect(fakePlatform.subscriptions.length, 2);
        expect(provider.gpsTrackingState, GpsTrackingState.starting);
        expect(provider.isGpsActive, isTrue);
      });
    });

    test('repeated user resume does not duplicate a healthy subscription', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.resumeRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);

        provider.pauseRun();
        async.flushMicrotasks();
        provider.resumeRun();
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 2);

        // Tapping Resume again while already active must be a no-op.
        provider.resumeRun();
        async.flushMicrotasks();

        expect(fakePlatform.subscriptions.length, 2);
      });
    });
  });

  group('lifecycle behavior - background/resume', () {
    test(
      'background lifecycle events do not cancel a healthy subscription',
      () {
        fakeAsync((async) {
          when(
            mockRepo.getRunSession(1),
          ).thenAnswer((_) async => _run(status: 'draft'));
          when(
            mockRepo.startRun(1),
          ).thenAnswer((_) async => _run(startedAt: fakeNow));

          startTrackedRun(async);
          final subscription = fakePlatform.subscriptions.single;
          expect(provider.isGpsActive, isTrue);

          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.detached,
          ]) {
            provider.didChangeAppLifecycleState(state);
            async.flushMicrotasks();

            expect(
              subscription.cancelled,
              isFalse,
              reason: '$state must never cancel a healthy GPS subscription',
            );
            expect(fakePlatform.subscriptions.length, 1);
            expect(provider.currentRun!.pausedAt, isNull);
          }
        });
      },
    );

    test('lifecycle resume does not duplicate a healthy subscription', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        expect(fakePlatform.subscriptions.length, 1);

        // Feed one healthy position so the subscription is proven `active`,
        // not merely `starting`, before the resume event.
        fakePlatform.subscriptions.single.deliverPosition(_fakePosition());
        async.flushMicrotasks();
        expect(provider.gpsTrackingState, GpsTrackingState.active);

        provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
        async.flushMicrotasks();
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason: 'a routine resume over a healthy stream must not restart it',
        );
        expect(fakePlatform.subscriptions.single.cancelled, isFalse);
        expect(provider.gpsTrackingState, GpsTrackingState.active);
      });
    });

    test('stream error changes state, sets an error message, and permits '
        'exactly one recovery on the next lifecycle resume', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        expect(provider.gpsTrackingState, GpsTrackingState.failed);
        expect(provider.isGpsActive, isFalse);
        expect(provider.errorMessage, contains('gps hiccup'));
        expect(
          firstSubscription.cancelled,
          isTrue,
          reason:
              'the dead subscription must be released so a recovery is '
              'not rejected by the native side for "already listening"',
        );

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          2,
          reason: 'exactly one recovery subscription must be created',
        );
        expect(provider.gpsTrackingState, GpsTrackingState.starting);

        // A second resumed event must not create yet another one.
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 2);
      });
    });

    test(
      'stream completion changes state and permits exactly one recovery',
      () {
        fakeAsync((async) {
          when(
            mockRepo.getRunSession(1),
          ).thenAnswer((_) async => _run(status: 'draft'));
          when(
            mockRepo.startRun(1),
          ).thenAnswer((_) async => _run(startedAt: fakeNow));

          startTrackedRun(async);
          final firstSubscription = fakePlatform.subscriptions.single;

          firstSubscription.deliverDone();
          async.flushMicrotasks();

          expect(provider.gpsTrackingState, GpsTrackingState.failed);
          expect(provider.isGpsActive, isFalse);
          expect(provider.errorMessage, isNotNull);
          expect(firstSubscription.cancelled, isTrue);

          provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
          async.flushMicrotasks();

          expect(fakePlatform.subscriptions.length, 2);
          expect(provider.gpsTrackingState, GpsTrackingState.starting);

          provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
          async.flushMicrotasks();
          expect(
            fakePlatform.subscriptions.length,
            2,
            reason: 'repeated resumed events after recovery must not duplicate',
          );
        });
      },
    );

    test(
      'onDone does not overwrite a more specific preceding error message',
      () {
        fakeAsync((async) {
          when(
            mockRepo.getRunSession(1),
          ).thenAnswer((_) async => _run(status: 'draft'));
          when(
            mockRepo.startRun(1),
          ).thenAnswer((_) async => _run(startedAt: fakeNow));

          startTrackedRun(async);
          final subscription = fakePlatform.subscriptions.single;

          subscription.deliverError(Exception('specific failure'));
          async.flushMicrotasks();
          expect(provider.errorMessage, contains('specific failure'));

          // A trailing done for the same generation must not clobber it.
          subscription.deliverDone();
          async.flushMicrotasks();

          expect(provider.errorMessage, contains('specific failure'));
        });
      },
    );
  });

  group('recovery serializes against an in-flight cancellation', () {
    test('stream error: lifecycle resume does not create a replacement '
        'subscription until the old cancellation completes, then creates '
        'exactly one automatically without a second resumed event', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;

        // Hold the old subscription's cancellation open.
        final cancelGate = Completer<void>();
        firstSubscription.cancelGate = cancelGate;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();
        expect(provider.gpsTrackingState, GpsTrackingState.failed);
        expect(firstSubscription.cancelled, isTrue);

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason:
              'no replacement subscription must be created before the '
              'old cancellation completes',
        );
        expect(provider.gpsTrackingState, GpsTrackingState.failed);

        cancelGate.complete();
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          2,
          reason:
              'exactly one replacement must be created automatically '
              'once cancellation resolves, with no second resumed event',
        );
        expect(provider.gpsTrackingState, GpsTrackingState.starting);
      });
    });

    test('stream completion: lifecycle resume does not create a replacement '
        'subscription until the old cancellation completes, then creates '
        'exactly one automatically without a second resumed event', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;

        final cancelGate = Completer<void>();
        firstSubscription.cancelGate = cancelGate;

        firstSubscription.deliverDone();
        async.flushMicrotasks();
        expect(provider.gpsTrackingState, GpsTrackingState.failed);
        expect(firstSubscription.cancelled, isTrue);

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason:
              'no replacement subscription must be created before the '
              'old cancellation completes',
        );

        cancelGate.complete();
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          2,
          reason:
              'exactly one replacement must be created automatically '
              'once cancellation resolves, with no second resumed event',
        );
        expect(provider.gpsTrackingState, GpsTrackingState.starting);
      });
    });

    test('two resumed events while cancellation is pending still create only '
        'one replacement subscription', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;
        final cancelGate = Completer<void>();
        firstSubscription.cancelGate = cancelGate;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason:
              'still just awaiting - neither resumed event should '
              'have created anything yet',
        );

        cancelGate.complete();
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          2,
          reason:
              'both awaiters resolving together must still create only '
              'one replacement subscription',
        );
      });
    });

    test('user pauses while recovery is awaiting cancellation: completing '
        'cancellation must not start GPS', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow, pausedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;
        final cancelGate = Completer<void>();
        firstSubscription.cancelGate = cancelGate;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 1);

        provider.pauseRun();
        async.flushMicrotasks();
        expect(provider.currentRun!.pausedAt, isNotNull);

        cancelGate.complete();
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason:
              'a user pause during the awaited recovery must win - no '
              'replacement subscription may be created',
        );
        expect(provider.isGpsActive, isFalse);
      });
    });

    test('run finished while recovery is awaiting cancellation: completing '
        'cancellation must not start GPS', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
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
          (_) async => _run(startedAt: fakeNow, status: 'completed'),
        );

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;
        final cancelGate = Completer<void>();
        firstSubscription.cancelGate = cancelGate;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 1);

        provider.finishRun();
        async.flushMicrotasks();
        expect(provider.currentRun?.status, 'completed');

        cancelGate.complete();
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason:
              'finishing the run during the awaited recovery must win - '
              'no replacement subscription may be created',
        );
        expect(provider.isGpsActive, isFalse);
      });
    });

    test('run discarded while recovery is awaiting cancellation: completing '
        'cancellation must not start GPS', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(mockRepo.deleteRun(1)).thenAnswer((_) async => true);

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;
        final cancelGate = Completer<void>();
        firstSubscription.cancelGate = cancelGate;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 1);

        provider.discardRun();
        async.flushMicrotasks();
        expect(provider.currentRun, isNull);

        cancelGate.complete();
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason:
              'discarding the run during the awaited recovery must win - '
              'no replacement subscription may be created',
        );
        expect(provider.isGpsActive, isFalse);
      });
    });

    test('clear() occurs while recovery is awaiting cancellation: completing '
        'cancellation must not start GPS', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;
        final cancelGate = Completer<void>();
        firstSubscription.cancelGate = cancelGate;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 1);

        provider.clear();
        async.flushMicrotasks();
        expect(provider.currentRun, isNull);

        cancelGate.complete();
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason:
              'clear() during the awaited recovery must win - no '
              'replacement subscription may be created',
        );
        expect(provider.isGpsActive, isFalse);
      });
    });

    test('dispose() occurs while recovery is awaiting cancellation: '
        'completing cancellation must not start GPS or notify listeners', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;
        final cancelGate = Completer<void>();
        firstSubscription.cancelGate = cancelGate;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 1);

        var notifiedAfterDispose = false;
        provider.addListener(() => notifiedAfterDispose = true);

        provider.dispose();

        cancelGate.complete();
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason:
              'dispose() during the awaited recovery must win - no '
              'replacement subscription may be created',
        );
        expect(notifiedAfterDispose, isFalse);
      });
    });

    test(
      "current run changes from run A to run B while A's cancellation is "
      "pending: A's stale recovery cannot start tracking for B, and B's "
      'own legitimate start still succeeds once the cancellation resolves',
      () {
        fakeAsync((async) {
          when(
            mockRepo.getRunSession(1),
          ).thenAnswer((_) async => _run(id: 1, status: 'draft'));
          when(
            mockRepo.startRun(1),
          ).thenAnswer((_) async => _run(id: 1, startedAt: fakeNow));
          when(mockRepo.deleteRun(1)).thenAnswer((_) async => true);
          when(
            mockRepo.getRunSession(2),
          ).thenAnswer((_) async => _run(id: 2, status: 'draft'));
          when(
            mockRepo.startRun(2),
          ).thenAnswer((_) async => _run(id: 2, startedAt: fakeNow));

          // Run A.
          startTrackedRun(async, id: 1);
          final runASubscription = fakePlatform.subscriptions.single;
          final cancelGate = Completer<void>();
          runASubscription.cancelGate = cancelGate;

          runASubscription.deliverError(Exception('gps hiccup'));
          async.flushMicrotasks();

          // A lifecycle resume triggers a recovery attempt for run A,
          // which begins awaiting the still-gated cancellation.
          provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
          async.flushMicrotasks();
          expect(fakePlatform.subscriptions.length, 1);

          // Run A is discarded, and a different run B is started while
          // A's cancellation - and A's recovery attempt awaiting it - are
          // still pending. Starting B legitimately also serializes
          // against the same still-pending cancellation.
          provider.discardRun();
          async.flushMicrotasks();
          startTrackedRun(async, id: 2);
          expect(provider.currentRun!.id, 2);
          expect(
            fakePlatform.subscriptions.length,
            1,
            reason:
                "B's own start also serializes against A's still-pending "
                'cancellation - nothing has been created yet',
          );

          cancelGate.complete();
          async.flushMicrotasks();

          expect(
            fakePlatform.subscriptions.length,
            2,
            reason:
                "exactly one new subscription - B's own legitimate start, "
                "not a duplicate from A's stale recovery",
          );
          expect(provider.currentRun!.id, 2);
          expect(provider.gpsTrackingState, GpsTrackingState.starting);

          // Confirm the new subscription genuinely belongs to run B, not
          // to a resurrected run A: a position on it must be attributed
          // to B's route/distance.
          final newSubscription = fakePlatform.subscriptions.last;
          newSubscription.deliverPosition(
            _fakePosition(latitude: 5, longitude: 5),
          );
          async.flushMicrotasks();
          expect(provider.currentRun!.id, 2);
          expect(provider.routePoints.length, 1);
        });
      },
    );

    test('cancellation throwing while a recovery is pending does not leave '
        'the provider stuck: recovery still completes with exactly one '
        'replacement subscription, and a later failure/recovery cycle '
        'still works normally afterward', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;
        final cancelGate = Completer<void>();
        firstSubscription.cancelGate = cancelGate;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 1);

        // The cancellation itself fails.
        cancelGate.completeError(Exception('native cancel failed'));
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          2,
          reason:
              'a cancellation failure must not block the pending '
              'recovery from proceeding',
        );
        expect(provider.gpsTrackingState, GpsTrackingState.starting);

        // A later, independent failure/recovery cycle must still work -
        // proves the provider was not left in a permanently degraded
        // state by the earlier cancellation failure.
        final secondSubscription = fakePlatform.subscriptions.last;
        secondSubscription.deliverError(Exception('another hiccup'));
        async.flushMicrotasks();
        expect(provider.gpsTrackingState, GpsTrackingState.failed);

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          3,
          reason: 'a subsequent explicit valid recovery must still succeed',
        );
        expect(provider.gpsTrackingState, GpsTrackingState.starting);
      });
    });

    test('cancellation throwing synchronously (a StreamSubscription contract '
        'violation) does not escape _beginGpsCancellation and does not '
        'block the pending recovery', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;
        firstSubscription.throwSynchronouslyOnCancel = Exception(
          'native cancel threw synchronously',
        );

        // Triggers _onPositionError -> _beginGpsCancellation ->
        // subscription.cancel(), which throws synchronously here. Must
        // not propagate out of the onError stream callback.
        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        expect(provider.gpsTrackingState, GpsTrackingState.failed);
        expect(firstSubscription.cancelled, isTrue);

        // Recovery must still be able to proceed immediately - a
        // synchronously-throwing cancel() must not leave
        // _gpsCancellationFuture permanently set to a broken/unresolved
        // future.
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          fakePlatform.subscriptions.length,
          2,
          reason: 'a synchronously-throwing cancel() must not block recovery',
        );
        expect(provider.gpsTrackingState, GpsTrackingState.starting);
      });
    });

    test('a stale GPS error message is cleared once recovery successfully '
        'creates a replacement subscription', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();
        expect(provider.errorMessage, contains('gps hiccup'));

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          provider.errorMessage,
          isNull,
          reason:
              'a successful recovery attempt must clear the stale error '
              'from the failure it is recovering from',
        );
        expect(provider.gpsTrackingState, GpsTrackingState.starting);
      });
    });

    test('a stale GPS error message is cleared on a genuine self-heal - a '
        'position arriving on the same still-failed subscription, with no '
        'recovery attempt and no replacement subscription involved', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final subscription = fakePlatform.subscriptions.single;

        subscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();
        expect(provider.gpsTrackingState, GpsTrackingState.failed);
        expect(provider.errorMessage, contains('gps hiccup'));

        // cancelOnError: false means this exact subscription can still
        // deliver a position after erroring - no lifecycle event, no
        // recovery attempt, no replacement subscription.
        subscription.deliverPosition(_fakePosition());
        async.flushMicrotasks();

        expect(fakePlatform.subscriptions.length, 1);
        expect(provider.gpsTrackingState, GpsTrackingState.active);
        expect(
          provider.errorMessage,
          isNull,
          reason: 'a genuine self-heal must clear the error it healed from',
        );
      });
    });

    test('an unrelated error (from a different operation entirely) is not '
        'erased by a successful GPS recovery, nor by a genuine self-heal on '
        'the happy-path starting->active transition', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        // loadDashboardData() failure sets _errorMessage without
        // touching GPS state, _currentRun, or pausedAt at all - a
        // genuinely unrelated error, produced via real public API
        // rather than reaching into private state.
        when(
          mockRepo.getRecentRuns(limit: anyNamed('limit')),
        ).thenThrow(Exception('dashboard load failed'));

        startTrackedRun(async);
        final firstSubscription = fakePlatform.subscriptions.single;

        firstSubscription.deliverError(Exception('gps hiccup'));
        async.flushMicrotasks();

        // The unrelated error is set while GPS happens to be in its
        // failed state - must survive the recovery below.
        provider.loadDashboardData();
        async.flushMicrotasks();
        expect(provider.errorMessage, contains('dashboard load failed'));

        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          provider.errorMessage,
          contains('dashboard load failed'),
          reason:
              'a GPS recovery must only clear its own stale GPS error, '
              'never an unrelated error set by a different operation',
        );
        expect(provider.gpsTrackingState, GpsTrackingState.starting);

        // The happy-path starting->active transition (no prior GPS
        // failure involved) must likewise never touch an unrelated
        // error still standing from the same earlier dashboard failure.
        final newSubscription = fakePlatform.subscriptions.last;
        newSubscription.deliverPosition(_fakePosition());
        async.flushMicrotasks();

        expect(provider.gpsTrackingState, GpsTrackingState.active);
        expect(provider.errorMessage, contains('dashboard load failed'));
      });
    });
  });

  group('guards against restarting a run that should stay stopped', () {
    test('a user-paused run remains stopped through every lifecycle event', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow, pausedAt: fakeNow));

        startTrackedRun(async);

        provider.pauseRun();
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 1);
        expect(provider.isGpsActive, isFalse);

        for (final state in AppLifecycleState.values) {
          provider.didChangeAppLifecycleState(state);
          async.flushMicrotasks();
        }

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason: 'no lifecycle event may restart GPS for a user-paused run',
        );
        expect(provider.isGpsActive, isFalse);
      });
    });

    test('a completed run never restarts GPS from a lifecycle event', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
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
          (_) async => _run(startedAt: fakeNow, status: 'completed'),
        );

        startTrackedRun(async);

        provider.finishRun();
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.single.cancelled, isTrue);

        for (final state in AppLifecycleState.values) {
          provider.didChangeAppLifecycleState(state);
          async.flushMicrotasks();
        }

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason: 'a completed run must never restart GPS',
        );
      });
    });

    test('a discarded run never restarts GPS from a lifecycle event', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(mockRepo.deleteRun(1)).thenAnswer((_) async => true);

        startTrackedRun(async);

        provider.discardRun();
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.single.cancelled, isTrue);
        expect(provider.currentRun, isNull);

        for (final state in AppLifecycleState.values) {
          provider.didChangeAppLifecycleState(state);
          async.flushMicrotasks();
        }

        expect(
          fakePlatform.subscriptions.length,
          1,
          reason: 'a discarded run must never restart GPS',
        );
      });
    });
  });

  group('clear() and dispose()', () {
    test('clear() awaits cancellation and invalidates further callbacks', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final subscription = fakePlatform.subscriptions.single;

        provider.clear();
        async.flushMicrotasks();

        expect(subscription.cancelled, isTrue);
        expect(provider.gpsTrackingState, GpsTrackingState.stopped);
        expect(provider.currentRun, isNull);

        // A late position for the pre-clear generation must not resurrect
        // any state (no currentRun to attach it to, no crash).
        subscription.deliverPosition(_fakePosition());
        async.flushMicrotasks();

        expect(provider.currentRun, isNull);
        expect(provider.currentDistance, 0);
      });
    });

    test('dispose() invalidates callbacks synchronously and never notifies '
        'afterward, even once a stalled cancellation later resolves', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final subscription = fakePlatform.subscriptions.single;

        final gate = Completer<void>();
        subscription.cancelGate = gate;

        var notifiedAfterDispose = false;
        provider.addListener(() => notifiedAfterDispose = true);

        provider.dispose();

        // The cancellation is still pending (gate not completed) - a
        // late position/error/done delivered while it is pending must be
        // inert, and completing the gate afterward must not trigger any
        // notification either.
        subscription.deliverPosition(_fakePosition());
        subscription.deliverError(Exception('late error'));
        subscription.deliverDone();
        async.flushMicrotasks();

        expect(notifiedAfterDispose, isFalse);

        gate.complete();
        async.flushMicrotasks();

        expect(notifiedAfterDispose, isFalse);
      });
    });
  });

  group('late/obsolete-generation callback protection', () {
    test('a late position callback from a superseded generation is ignored '
        'even when the run is still in progress and unpaused - isolates the '
        'generation check itself from the run-identity/pausedAt checks, '
        'which independently guard the other tests in this group', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));

        startTrackedRun(async);
        final oldSubscription = fakePlatform.subscriptions.single;

        // Force a recovery so a new generation/subscription supersedes
        // the old one, without pausing or discarding the run - identity,
        // status, and pausedAt all remain exactly as they were.
        oldSubscription.deliverError(Exception('transient'));
        async.flushMicrotasks();
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(fakePlatform.subscriptions.length, 2);
        expect(provider.currentRun!.id, 1);
        expect(provider.currentRun!.status, 'in_progress');
        expect(provider.currentRun!.pausedAt, isNull);

        // A position from the superseded (generation 1) subscription
        // must still be rejected, purely because it is stale - nothing
        // else about the run's state would reject it.
        oldSubscription.deliverPosition(
          _fakePosition(latitude: 40, longitude: -70),
        );
        async.flushMicrotasks();

        expect(
          provider.currentDistance,
          0,
          reason:
              'only the generation check protects this scenario - run '
              'identity, status, and pausedAt are all unchanged',
        );
        expect(provider.routePoints, isEmpty);
      });
    });

    test('a late position callback from an obsolete generation is ignored', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow, pausedAt: fakeNow));

        startTrackedRun(async);
        final obsolete = fakePlatform.subscriptions.single;

        provider.pauseRun();
        async.flushMicrotasks();
        expect(provider.currentDistance, 0);

        // Deliver a position directly on the now-superseded subscription -
        // the generation guard, not real Stream delivery suppression, is
        // what must reject this (see the class doc comment above).
        obsolete.deliverPosition(_fakePosition(latitude: 40, longitude: -70));
        async.flushMicrotasks();

        expect(
          provider.currentDistance,
          0,
          reason:
              'a late position from an obsolete generation must not '
              'mutate distance/route for a paused run',
        );
        expect(provider.routePoints, isEmpty);
      });
    });

    test('a late error callback from an obsolete generation is ignored', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow, pausedAt: fakeNow));

        startTrackedRun(async);
        final obsolete = fakePlatform.subscriptions.single;

        provider.pauseRun();
        async.flushMicrotasks();
        expect(provider.gpsTrackingState, GpsTrackingState.stopped);

        obsolete.deliverError(Exception('obsolete generation error'));
        async.flushMicrotasks();

        expect(
          provider.gpsTrackingState,
          GpsTrackingState.stopped,
          reason:
              'a late error from an obsolete generation must not flip '
              'a deliberately-stopped (user-paused) run to failed',
        );
        expect(provider.errorMessage, isNot(contains('obsolete generation')));
      });
    });

    test('a late done callback from an obsolete generation is ignored', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(startedAt: fakeNow));
        when(
          mockRepo.pauseRun(1, any),
        ).thenAnswer((_) async => _run(startedAt: fakeNow, pausedAt: fakeNow));

        startTrackedRun(async);
        final obsolete = fakePlatform.subscriptions.single;

        provider.pauseRun();
        async.flushMicrotasks();
        expect(provider.gpsTrackingState, GpsTrackingState.stopped);

        obsolete.deliverDone();
        async.flushMicrotasks();

        expect(
          provider.gpsTrackingState,
          GpsTrackingState.stopped,
          reason:
              'a late done from an obsolete generation must not flip '
              'a deliberately-stopped (user-paused) run to failed',
        );
      });
    });

    test('a callback associated with run A cannot mutate run B after A is '
        'discarded and a new run B is started', () {
      fakeAsync((async) {
        when(
          mockRepo.getRunSession(1),
        ).thenAnswer((_) async => _run(id: 1, status: 'draft'));
        when(
          mockRepo.startRun(1),
        ).thenAnswer((_) async => _run(id: 1, startedAt: fakeNow));
        when(mockRepo.deleteRun(1)).thenAnswer((_) async => true);
        when(
          mockRepo.getRunSession(2),
        ).thenAnswer((_) async => _run(id: 2, status: 'draft'));
        when(
          mockRepo.startRun(2),
        ).thenAnswer((_) async => _run(id: 2, startedAt: fakeNow));

        // Run A.
        startTrackedRun(async, id: 1);
        final runASubscription = fakePlatform.subscriptions.single;
        expect(provider.currentRun!.id, 1);

        provider.discardRun();
        async.flushMicrotasks();
        expect(provider.currentRun, isNull);

        // Run B, a different run entirely.
        startTrackedRun(async, id: 2);
        expect(provider.currentRun!.id, 2);
        final runBSubscription = fakePlatform.subscriptions.last;
        expect(runBSubscription, isNot(same(runASubscription)));

        // A callback from run A's obsolete subscription must not be
        // attributed to run B, which is now current.
        runASubscription.deliverPosition(
          _fakePosition(latitude: 1, longitude: 1),
        );
        async.flushMicrotasks();

        expect(provider.currentRun!.id, 2);
        expect(
          provider.currentDistance,
          0,
          reason: "run A's late callback must not mutate run B's distance",
        );
        expect(provider.routePoints, isEmpty);

        // A genuine callback for run B's own subscription still works.
        runBSubscription.deliverPosition(
          _fakePosition(latitude: 2, longitude: 2),
        );
        async.flushMicrotasks();
        expect(provider.routePoints.length, 1);
      });
    });
  });
}
