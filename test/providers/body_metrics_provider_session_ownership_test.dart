import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/body_metric.dart';
import 'package:go_hard_app/data/repositories/body_metrics_repository.dart';
import 'package:go_hard_app/providers/body_metrics_provider.dart';

@GenerateMocks([BodyMetricsRepository, ConnectivityService])
import 'body_metrics_provider_session_ownership_test.mocks.dart';

/// Proves [BodyMetricsProvider] never lets a repository result, error, or
/// `finally` cleanup started under user A land on the state user B now sees
/// through this same app-scoped provider instance; that within one session an
/// older request/mutation can never overwrite a newer one on the same
/// resource; and that [BodyMetricsProvider.clear] invalidates every
/// generation before resetting state.
///
/// Real [UserSessionEpoch]; the repository is mocked so `Completer`s give
/// exact control over when each continuation resolves - no wall-clock delay,
/// no `Future.delayed`, no `Future.value()`/`pumpEventQueue`/`_settle` as a
/// pump, no `Timer`, no `sleep`. Ordering is synchronized only through
/// explicit `Completer.complete()` calls, awaiting the exact `Future` under
/// test, a `sync: true` broadcast `StreamController` (so `add()` delivers the
/// connectivity event synchronously), and the
/// `onConnectivityRefreshForTesting` seam (which hands back the real
/// `loadBodyMetrics()` `Future` the listener started).
void main() {
  late MockBodyMetricsRepository repo;
  late UserSessionEpoch epoch;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late BodyMetricsProvider provider;
  late int notifyCount;

  BodyMetric metric(int id, {double weight = 70.0}) => BodyMetric(
    id: id,
    userId: 1,
    recordedAt: DateTime(2026, 1, id),
    createdAt: DateTime(2026, 1, id),
    weight: weight,
  );

  // Captures the Future returned by the connectivity listener's own call to
  // loadBodyMetrics, so connectivity tests await the real ownership path to
  // completion deterministically - never an event-loop pump.
  Future<void>? connectivityRefresh;

  void stubDefaults() {
    when(
      repo.getBodyMetrics(days: anyNamed('days')),
    ).thenAnswer((_) async => <BodyMetric>[]);
    when(repo.getLatestMetric()).thenAnswer((_) async => null);
    when(repo.getBodyMetricById(any)).thenAnswer((_) async => metric(1));
    // Echo the submitted metric back (id preserved) so multi-metric tests
    // get distinct rows; a per-test `when` override still wins where needed.
    when(
      repo.createBodyMetric(any),
    ).thenAnswer((inv) async => inv.positionalArguments[0] as BodyMetric);
    // updateBodyMetric / deleteBodyMetric are intentionally NOT stubbed here:
    // the generated mock already supplies a completed void future for a
    // missing stub, and tests that care about timing install their own
    // Completer.
    when(
      repo.getChartData(metric: anyNamed('metric'), days: anyNamed('days')),
    ).thenAnswer((_) async => <Map<String, dynamic>>[]);
  }

  setUp(() {
    repo = MockBodyMetricsRepository();
    stubDefaults();
    epoch = UserSessionEpoch();
    connectivity = MockConnectivityService();
    // sync: true - `add()` synchronously invokes the real connectivity
    // listener (and its call into loadBodyMetrics) before `add()` returns,
    // so no event-loop pump is needed to observe that the listener ran.
    connectivityController = StreamController<bool>.broadcast(sync: true);
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    provider = BodyMetricsProvider(repo, epoch, connectivity);
    connectivityRefresh = null;
    provider.onConnectivityRefreshForTesting = (f) => connectivityRefresh = f;
    notifyCount = 0;
    provider.addListener(() => notifyCount++);
  });

  tearDown(() async {
    try {
      provider.dispose();
    } catch (_) {
      // Some tests dispose explicitly; a second dispose asserts.
    }
    await connectivityController.close();
  });

  // ================================================================
  // 11-22. Cross-session Provider state
  // ================================================================

  group('cross-session state', () {
    test('11: a slow loadBodyMetrics completing after clear() cannot '
        'repopulate the cleared list and does not notify', () async {
      epoch.activate(1);
      final c = Completer<List<BodyMetric>>();
      when(
        repo.getBodyMetrics(days: anyNamed('days')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadBodyMetrics();
      epoch.invalidate();
      provider.clear();
      final notifiesBefore = notifyCount;

      c.complete([metric(1, weight: 61.5)]); // A's sensitive weight history
      await f;

      expect(provider.metrics, isEmpty);
      expect(provider.latestMetric, isNull);
      expect(notifyCount, notifiesBefore);
    });

    test(
      '12: the same completion after user B logs in cannot overwrite B',
      () async {
        epoch.activate(1);
        final aC = Completer<List<BodyMetric>>();
        final bC = Completer<List<BodyMetric>>();
        var call = 0;
        when(
          repo.getBodyMetrics(days: anyNamed('days')),
        ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

        final aF = provider.loadBodyMetrics();
        epoch.invalidate();
        epoch.activate(2);
        final bF = provider.loadBodyMetrics();

        bC.complete([metric(9)]);
        await bF;
        expect(provider.metrics.single.id, 9);

        aC.complete([metric(1, weight: 61.5)]);
        await aF;

        expect(provider.metrics.single.id, 9);
      },
    );

    test('13: a stale loadLatestMetric cannot update B', () async {
      epoch.activate(1);
      final c = Completer<BodyMetric?>();
      when(repo.getLatestMetric()).thenAnswer((_) => c.future);

      final f = provider.loadLatestMetric();
      epoch.invalidate();
      epoch.activate(2);

      c.complete(metric(1, weight: 61.5));
      await f;

      expect(provider.latestMetric, isNull);
    });

    test('14: a stale getBodyMetricById result never reaches its caller once '
        'the session has ended', () async {
      epoch.activate(1);
      final c = Completer<BodyMetric>();
      when(repo.getBodyMetricById(1)).thenAnswer((_) => c.future);

      final f = provider.getBodyMetricById(1);
      epoch.invalidate();

      c.complete(metric(1, weight: 61.5));
      final result = await f;

      expect(result, isNull);
      expect(provider.errorMessage, isNull);
    });

    test('15: a stale getChartData result never reaches its caller once the '
        'session has ended', () async {
      epoch.activate(1);
      final c = Completer<List<Map<String, dynamic>>>();
      when(
        repo.getChartData(metric: anyNamed('metric'), days: anyNamed('days')),
      ).thenAnswer((_) => c.future);

      final f = provider.getChartData();
      epoch.invalidate();

      c.complete([
        {'weight': 61.5},
      ]);
      final result = await f;

      expect(result, isEmpty);
    });

    test('16: a stale createBodyMetric success cannot append into B', () async {
      epoch.activate(1);
      final c = Completer<BodyMetric>();
      when(repo.createBodyMetric(any)).thenAnswer((_) => c.future);

      final f = provider.createBodyMetric(metric(1));
      // Real logout always runs invalidate() then clear() (via
      // SessionCleanupCoordinator) before any new login.
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete(metric(1, weight: 61.5));
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.metrics, isEmpty);
      expect(provider.isCreating, isFalse);
    });

    test('17: a stale updateBodyMetric success cannot modify B', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      final c = Completer<void>();
      when(repo.updateBodyMetric(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateBodyMetric(1, metric(1, weight: 40));
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete();
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.metrics, isEmpty); // cleared; stale update cannot refill
      expect(provider.isUpdating, isFalse);
    });

    test('18: a stale deleteBodyMetric success cannot remove from B', () async {
      epoch.activate(1);
      final c = Completer<void>();
      when(repo.deleteBodyMetric(1)).thenAnswer((_) => c.future);

      final f = provider.deleteBodyMetric(1);
      epoch.invalidate();
      epoch.activate(2);
      await provider.createBodyMetric(metric(1)); // B creates their own id-1

      c.complete();
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.metrics, hasLength(1)); // B's row survives
    });

    test('19: a stale mutation failure cannot write an error into B', () async {
      epoch.activate(1);
      final c = Completer<void>();
      when(repo.updateBodyMetric(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateBodyMetric(1, metric(1));
      epoch.invalidate();
      epoch.activate(2);

      c.completeError(Exception('boom'));
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('20: a stale loadBodyMetrics catch cannot set B\'s error', () async {
      epoch.activate(1);
      final c = Completer<List<BodyMetric>>();
      when(
        repo.getBodyMetrics(days: anyNamed('days')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadBodyMetrics();
      epoch.invalidate();
      epoch.activate(2);

      c.completeError(Exception('network down'));
      await f;

      expect(provider.errorMessage, isNull);
    });

    test(
      '21: a stale finally cannot clear B\'s newer loading/mutation flag',
      () async {
        epoch.activate(1);
        final aC = Completer<List<BodyMetric>>();
        when(
          repo.getBodyMetrics(days: anyNamed('days')),
        ).thenAnswer((_) => aC.future);
        final aF = provider.loadBodyMetrics();

        epoch.invalidate();
        epoch.activate(2);
        final bC = Completer<List<BodyMetric>>();
        when(
          repo.getBodyMetrics(days: anyNamed('days')),
        ).thenAnswer((_) => bC.future);
        // ignore: unawaited_futures
        provider.loadBodyMetrics(); // B's own load - still spinning
        expect(provider.isLoading, isTrue);

        aC.complete([metric(1, weight: 61.5)]); // A's stale load resolves
        await aF;

        // B's spinner must still be up - A's finally must not have cleared it.
        expect(provider.isLoading, isTrue);
        bC.complete([]);
      },
    );

    test("21b: an older create's stale finally cannot clear a newer create's "
        '_isCreating flag', () async {
      epoch.activate(1);
      final firstC = Completer<BodyMetric>();
      final secondC = Completer<BodyMetric>();
      var call = 0;
      when(
        repo.createBodyMetric(any),
      ).thenAnswer((_) => (call++ == 0) ? firstC.future : secondC.future);

      // ignore: unawaited_futures
      final f1 = provider.createBodyMetric(metric(1)); // older
      // ignore: unawaited_futures
      provider.createBodyMetric(metric(2)); // newer - owns _isCreating now
      expect(provider.isCreating, isTrue);

      firstC.complete(metric(1)); // older resolves first
      await f1;

      // The newer create is still in flight; the older one's finally must
      // not have flipped _isCreating off.
      expect(provider.isCreating, isTrue);
      secondC.complete(metric(2));
    });

    test(
      '22: stale continuations never call notifyListeners() at all',
      () async {
        epoch.activate(1);
        final listC = Completer<List<BodyMetric>>();
        final latestC = Completer<BodyMetric?>();
        when(
          repo.getBodyMetrics(days: anyNamed('days')),
        ).thenAnswer((_) => listC.future);
        when(repo.getLatestMetric()).thenAnswer((_) => latestC.future);

        final listF = provider.loadBodyMetrics();
        final latestF = provider.loadLatestMetric();
        epoch.invalidate();
        final notifiesAtInvalidate = notifyCount;

        listC.complete([metric(1)]);
        latestC.complete(metric(1));
        await listF;
        await latestF;

        expect(notifyCount, notifiesAtInvalidate);
      },
    );
  });

  // ================================================================
  // 23-32. Same-session ordering
  // ================================================================

  group('same-session ordering', () {
    test('23: an older list request completing last loses', () async {
      epoch.activate(1);
      final first = Completer<List<BodyMetric>>();
      final second = Completer<List<BodyMetric>>();
      var call = 0;
      when(
        repo.getBodyMetrics(days: anyNamed('days')),
      ).thenAnswer((_) => (call++ == 0) ? first.future : second.future);

      final f1 = provider.loadBodyMetrics();
      final f2 = provider.loadBodyMetrics();

      second.complete([metric(2)]);
      await f2;
      first.complete([metric(1, weight: 61.5)]); // stale, resolves last
      await f1;

      expect(provider.metrics.map((m) => m.id), [2]);
    });

    test('24: an older latest-metric request completing last loses', () async {
      epoch.activate(1);
      final first = Completer<BodyMetric?>();
      final second = Completer<BodyMetric?>();
      var call = 0;
      when(
        repo.getLatestMetric(),
      ).thenAnswer((_) => (call++ == 0) ? first.future : second.future);

      final f1 = provider.loadLatestMetric();
      final f2 = provider.loadLatestMetric();

      second.complete(metric(2));
      await f2;
      first.complete(metric(1, weight: 61.5)); // stale, resolves last
      await f1;

      expect(provider.latestMetric!.id, 2);
    });

    test('25: an older detail request\'s error cannot overwrite a newer '
        'detail request\'s error', () async {
      epoch.activate(1);
      final first = Completer<BodyMetric>(); // detail for metric 5
      final second = Completer<BodyMetric>(); // detail for metric 7
      when(repo.getBodyMetricById(5)).thenAnswer((_) => first.future);
      when(repo.getBodyMetricById(7)).thenAnswer((_) => second.future);

      final f1 = provider.getBodyMetricById(5);
      final f2 = provider.getBodyMetricById(7);

      second.completeError(Exception('metric 7 not found'));
      await f2;
      expect(provider.errorMessage, contains('metric 7'));

      first.completeError(Exception('metric 5 stale error')); // resolves last
      await f1;

      // The newer (metric-7) error must survive; the older, later-resolving
      // metric-5 error must not overwrite it.
      expect(provider.errorMessage, contains('metric 7'));
    });

    test(
      '26: A -> B -> A resolves through generation identity, not id equality',
      () async {
        epoch.activate(1);
        final firstA = Completer<BodyMetric>(); // 1st call for metric 5
        final b = Completer<BodyMetric>(); // call for metric 7
        final secondA = Completer<BodyMetric>(); // 2nd call for metric 5
        var call = 0;
        when(
          repo.getBodyMetricById(5),
        ).thenAnswer((_) => (call++ == 0) ? firstA.future : secondA.future);
        when(repo.getBodyMetricById(7)).thenAnswer((_) => b.future);

        final f1 = provider.getBodyMetricById(5); // A
        final f2 = provider.getBodyMetricById(7); // B
        final f3 = provider.getBodyMetricById(5); // A again - newest owner

        secondA.completeError(Exception('third call, newest'));
        await f3;
        expect(provider.errorMessage, contains('newest'));

        b.completeError(Exception('second call, stale'));
        await f2;
        expect(provider.errorMessage, contains('newest')); // unchanged

        firstA.completeError(Exception('first call, stale, same id as f3'));
        await f1;
        // Same id (5) as the newest call, but an OLDER generation - must
        // still lose. Proves generation identity, not id equality, decides.
        expect(provider.errorMessage, contains('newest'));
      },
    );

    test('27: an older chart range completing last loses', () async {
      epoch.activate(1);
      final first = Completer<List<Map<String, dynamic>>>(); // weight/90d
      final second = Completer<List<Map<String, dynamic>>>(); // bodyfat/30d
      var call = 0;
      when(
        repo.getChartData(metric: anyNamed('metric'), days: anyNamed('days')),
      ).thenAnswer((_) => (call++ == 0) ? first.future : second.future);

      final f1 = provider.getChartData(metric: 'weight', days: 90);
      final f2 = provider.getChartData(metric: 'bodyfat', days: 30);

      second.completeError(Exception('newer range failed'));
      await f2;
      expect(provider.errorMessage, contains('newer range'));

      first.completeError(Exception('older range, resolves last'));
      await f1;

      expect(provider.errorMessage, contains('newer range'));
    });

    test('28: a connectivity-triggered refresh cannot overwrite a newer manual '
        'refresh', () async {
      epoch.activate(1);
      final connectivityLoad = Completer<List<BodyMetric>>();
      final manualLoad = Completer<List<BodyMetric>>();
      var call = 0;
      when(repo.getBodyMetrics(days: anyNamed('days'))).thenAnswer(
        (_) => (call++ == 0) ? connectivityLoad.future : manualLoad.future,
      );

      // sync delivery: the listener runs and calls loadBodyMetrics before
      // add() returns; connectivityRefresh is the real load's Future.
      connectivityController.add(true);
      expect(connectivityRefresh, isNotNull);
      final manualFuture = provider.loadBodyMetrics(); // newer, manual

      manualLoad.complete([metric(2)]);
      await manualFuture;
      connectivityLoad.complete([metric(1, weight: 61.5)]); // stale
      await connectivityRefresh; // the real stale continuation, to completion

      expect(provider.metrics.map((m) => m.id), [2]);
    });

    test(
      '29: a stale list refresh cannot overwrite a newer mutation',
      () async {
        epoch.activate(1);
        await provider.createBodyMetric(metric(1));
        final refresh = Completer<List<BodyMetric>>();
        when(
          repo.getBodyMetrics(days: anyNamed('days')),
        ).thenAnswer((_) => refresh.future);

        final refreshFuture = provider.loadBodyMetrics(); // slow refresh
        await provider.deleteBodyMetric(1); // fast mutation, completes first
        expect(provider.metrics, isEmpty);

        // The refresh's stale snapshot (still containing metric 1) resolves
        // after the delete.
        refresh.complete([metric(1)]);
        await refreshFuture;

        expect(provider.metrics, isEmpty); // delete's result must survive
      },
    );

    test('30: a late update cannot resurrect a metric whose newer delete '
        'completed', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      final updateC = Completer<void>();
      when(repo.updateBodyMetric(1, any)).thenAnswer((_) => updateC.future);

      final updateFuture = provider.updateBodyMetric(1, metric(1, weight: 40));
      await provider.deleteBodyMetric(1); // newer, completes first
      expect(provider.metrics, isEmpty);

      updateC.complete(); // the older update resolves after the delete
      final ok = await updateFuture;

      expect(ok, isFalse);
      expect(provider.metrics, isEmpty); // must not resurrect
    });

    test('31: a mutation failure is owned by its exact operation, not a newer '
        'one on the same metric', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      final failing = Completer<void>();
      final succeeding = Completer<void>();
      var call = 0;
      when(
        repo.updateBodyMetric(1, any),
      ).thenAnswer((_) => (call++ == 0) ? failing.future : succeeding.future);

      final f1 = provider.updateBodyMetric(1, metric(1, weight: 10)); // stale
      final f2 = provider.updateBodyMetric(1, metric(1, weight: 20)); // newest

      succeeding.complete();
      expect(await f2, isTrue);
      expect(provider.metrics.single.weight, 20);

      failing.completeError(Exception('stale failure'));
      expect(await f1, isFalse);

      // The stale failure must not overwrite the newer success already
      // applied, nor set an error over it.
      expect(provider.metrics.single.weight, 20);
      expect(provider.errorMessage, isNull);
    });

    test('32: concurrent mutations to different metrics remain independently '
        'ordered', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      await provider.createBodyMetric(metric(2));
      final c1 = Completer<void>();
      final c2 = Completer<void>();
      when(repo.updateBodyMetric(1, any)).thenAnswer((_) => c1.future);
      when(repo.updateBodyMetric(2, any)).thenAnswer((_) => c2.future);

      final f1 = provider.updateBodyMetric(1, metric(1, weight: 11));
      final f2 = provider.updateBodyMetric(2, metric(2, weight: 22));

      // Resolve metric 2 first - must not affect metric 1's still-pending
      // mutation or its own eventual success.
      c2.complete();
      expect(await f2, isTrue);
      c1.complete();
      expect(await f1, isTrue);

      expect(provider.metrics.firstWhere((m) => m.id == 1).weight, 11);
      expect(provider.metrics.firstWhere((m) => m.id == 2).weight, 22);
    });
  });

  // ================================================================
  // 33-39. Cleanup
  // ================================================================

  group('cleanup', () {
    test('33: clear() invalidates an in-flight list request without an epoch '
        'change', () async {
      epoch.activate(1);
      final c = Completer<List<BodyMetric>>();
      when(
        repo.getBodyMetrics(days: anyNamed('days')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadBodyMetrics();
      provider.clear(); // no epoch.invalidate() - same session stays active

      c.complete([metric(1, weight: 61.5)]);
      await f;

      expect(provider.metrics, isEmpty);
      expect(epoch.isCurrent(epoch.capture()!), isTrue); // epoch untouched
    });

    test('34: clear() invalidates an in-flight mutation without an epoch '
        'change', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      final c = Completer<void>();
      when(repo.updateBodyMetric(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateBodyMetric(1, metric(1, weight: 40));
      provider.clear();

      c.complete();
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.metrics, isEmpty);
    });

    test('35: a connectivity callback after logout is a no-op', () async {
      // No epoch.activate() at all - stays logged out throughout.
      // sync delivery: the listener runs synchronously inside add().
      connectivityController.add(true);

      expect(
        connectivityRefresh,
        isNull,
      ); // listener never entered loadBodyMetrics
      verifyNever(repo.getBodyMetrics(days: anyNamed('days')));
      expect(provider.isLoading, isFalse);
    });

    test('36: an in-flight connectivity refresh cannot repopulate state after '
        'clear()', () async {
      epoch.activate(1);
      final c = Completer<List<BodyMetric>>();
      when(
        repo.getBodyMetrics(days: anyNamed('days')),
      ).thenAnswer((_) => c.future);

      connectivityController.add(true); // sync: starts the connectivity refresh
      expect(connectivityRefresh, isNotNull);
      provider.clear();

      c.complete([metric(1, weight: 61.5)]);
      await connectivityRefresh; // the real stale continuation, to completion

      expect(provider.metrics, isEmpty);
    });

    test('37: dispose() prevents later callback publication', () async {
      epoch.activate(1);
      final c = Completer<List<BodyMetric>>();
      when(
        repo.getBodyMetrics(days: anyNamed('days')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadBodyMetrics();
      provider.dispose();

      c.complete([metric(1, weight: 61.5)]);
      await f;

      expect(provider.metrics, isEmpty);
    });

    test(
      '38: SessionCleanupCoordinator still clears BodyMetricsProvider state',
      () async {
        epoch.activate(1);
        await provider.createBodyMetric(metric(1));
        expect(provider.metrics, isNotEmpty);

        provider.clear();

        expect(provider.metrics, isEmpty);
        expect(provider.latestMetric, isNull);
        expect(provider.errorMessage, isNull);
        expect(provider.isLoading, isFalse);
        expect(provider.isCreating, isFalse);
        expect(provider.isUpdating, isFalse);
      },
    );

    test('39: clear() empties the SAME list instance a caller already holds a '
        'reference to (in-place clearing)', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      final held = provider.metrics; // caller holds this reference

      provider.clear();

      expect(held, isEmpty); // same reference, now empty
      expect(identical(held, provider.metrics), isTrue);
    });
  });

  // ================================================================
  // 40-48. Active-update flag ownership (Correction 1)
  // ================================================================

  group('active-update flag ownership', () {
    test(
      '40: isUpdating stays true while a second-metric update is still in '
      'flight after the first completes; false only once both are done',
      () async {
        epoch.activate(1);
        await provider.createBodyMetric(metric(1));
        await provider.createBodyMetric(metric(2));
        final cA = Completer<void>();
        final cB = Completer<void>();
        when(repo.updateBodyMetric(1, any)).thenAnswer((_) => cA.future);
        when(repo.updateBodyMetric(2, any)).thenAnswer((_) => cB.future);

        final fA = provider.updateBodyMetric(1, metric(1, weight: 11));
        final fB = provider.updateBodyMetric(2, metric(2, weight: 22));
        expect(provider.isUpdating, isTrue);

        cA.complete(); // A finishes first
        expect(await fA, isTrue);
        // B is still in flight - the shared flag must NOT have been cleared.
        expect(provider.isUpdating, isTrue);

        cB.complete();
        expect(await fB, isTrue);
        expect(provider.isUpdating, isFalse);
      },
    );

    test(
      "41: an older same-metric update's finally cannot unregister its newer "
      'replacement (isUpdating stays true until the replacement finishes)',
      () async {
        epoch.activate(1);
        await provider.createBodyMetric(metric(1));
        final older = Completer<void>();
        final newer = Completer<void>();
        var call = 0;
        when(
          repo.updateBodyMetric(1, any),
        ).thenAnswer((_) => (call++ == 0) ? older.future : newer.future);

        final fOld = provider.updateBodyMetric(1, metric(1, weight: 10));
        final fNew = provider.updateBodyMetric(1, metric(1, weight: 20));
        expect(provider.isUpdating, isTrue);

        older.complete(); // older resolves first, superseded
        expect(await fOld, isFalse);
        // The replacement is still running - its slot must survive.
        expect(provider.isUpdating, isTrue);

        newer.complete();
        expect(await fNew, isTrue);
        expect(provider.isUpdating, isFalse);
      },
    );

    test(
      "42: a stale user-A update's finally cannot unregister user-B's active "
      'update tracking',
      () async {
        epoch.activate(1);
        await provider.createBodyMetric(metric(1));
        final aC = Completer<void>();
        final bC = Completer<void>();
        var call = 0;
        when(
          repo.updateBodyMetric(1, any),
        ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

        final aF = provider.updateBodyMetric(1, metric(1, weight: 1)); // A
        // Real logout: invalidate() then clear() before B logs in.
        epoch.invalidate();
        provider.clear();
        epoch.activate(2);
        await provider.createBodyMetric(metric(1)); // B's own row

        final bF = provider.updateBodyMetric(1, metric(1, weight: 2)); // B
        expect(provider.isUpdating, isTrue); // B's update

        aC.complete(); // A's stale update resolves last
        expect(await aF, isFalse);
        // A must not have removed B's active-update identity.
        expect(provider.isUpdating, isTrue);

        bC.complete();
        expect(await bF, isTrue);
        expect(provider.isUpdating, isFalse);
      },
    );

    test('43: clear() empties active-update tracking (isUpdating -> false) '
        'even with an update still in flight', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      final c = Completer<void>();
      when(repo.updateBodyMetric(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateBodyMetric(1, metric(1, weight: 40));
      expect(provider.isUpdating, isTrue);

      provider.clear();
      expect(provider.isUpdating, isFalse); // tracking emptied by clear()

      c.complete();
      expect(await f, isFalse);
      expect(provider.isUpdating, isFalse); // stale finally cannot re-add
    });

    test('44: a stale update finally does not notify listeners; a current '
        'update notifies exactly on its real true/false transitions', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      final c = Completer<void>();
      when(repo.updateBodyMetric(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateBodyMetric(1, metric(1, weight: 5));
      // entry -> _errorMessage null + notify (isUpdating false->true here).
      final afterStart = notifyCount;

      epoch.invalidate();
      provider.clear();
      final afterClear = notifyCount; // clear() notifies once

      c.complete(); // stale finally: owns() false -> must not notify
      expect(await f, isFalse);

      expect(notifyCount, afterClear);
      expect(afterStart, greaterThan(0));
    });

    test(
      '44b: a normal successful update notifies on entry (false -> true) and '
      'again on completion (true -> false)',
      () async {
        epoch.activate(1);
        await provider.createBodyMetric(metric(1));
        final c = Completer<void>();
        when(repo.updateBodyMetric(1, any)).thenAnswer((_) => c.future);

        final before = notifyCount;
        final f = provider.updateBodyMetric(1, metric(1, weight: 3));
        expect(provider.isUpdating, isTrue);
        expect(notifyCount, greaterThan(before)); // entry notify

        final beforeFinish = notifyCount;
        c.complete();
        expect(await f, isTrue);
        expect(provider.isUpdating, isFalse);
        expect(notifyCount, greaterThan(beforeFinish)); // completion notify
      },
    );

    test(
      '50: an update superseded by a delete of the SAME id (delete completes '
      'first) still ANNOUNCES the isUpdating true -> false transition when its '
      'stale finally removes the last active-update record',
      () async {
        epoch.activate(1);
        await provider.createBodyMetric(metric(1));
        final updateC = Completer<void>();
        final deleteC = Completer<void>();
        when(repo.updateBodyMetric(1, any)).thenAnswer((_) => updateC.future);
        when(repo.deleteBodyMetric(1)).thenAnswer((_) => deleteC.future);

        final updF = provider.updateBodyMetric(1, metric(1, weight: 7));
        // Delete supersedes the update's metric generation.
        final delF = provider.deleteBodyMetric(1);
        expect(provider.isUpdating, isTrue);

        // Delete completes first: bumps _metricMutationGens[1], notifies for
        // its own list edit while the update record is still present.
        deleteC.complete();
        expect(await delF, isTrue);
        expect(provider.isUpdating, isTrue); // update record still present

        final notifiesBeforeUpdateFinally = notifyCount;

        // The superseded update reaches finally: owns() is false (delete
        // bumped the metric gen), but the session is unchanged and this
        // removal empties _activeUpdates -> it MUST notify the transition.
        updateC.complete();
        expect(await updF, isFalse);

        expect(provider.isUpdating, isFalse);
        expect(
          notifyCount,
          greaterThan(notifiesBeforeUpdateFinally),
          reason:
              'the isUpdating true -> false transition must be announced by '
              'the superseded update, since the delete notified BEFORE the '
              'update record was removed',
        );
      },
    );

    test(
      '52: an update whose SESSION ended (raw invalidate+activate, no clear) '
      'must NOT notify from its stale finally even though it removes the last '
      'active-update record - a cross-session notify would rebuild user B',
      () async {
        epoch.activate(1);
        await provider.createBodyMetric(metric(1));
        final c = Completer<void>();
        when(repo.updateBodyMetric(1, any)).thenAnswer((_) => c.future);

        final f = provider.updateBodyMetric(1, metric(1, weight: 8));
        expect(provider.isUpdating, isTrue);

        // Session ends and a different user logs in WITHOUT clear() running
        // (clear() would have emptied _activeUpdates; this exercises the
        // session-guard on the announce branch directly).
        epoch.invalidate();
        epoch.activate(2);
        final before = notifyCount;

        c.complete(); // stale finally: removes the last record, but !isCurrent
        expect(await f, isFalse);

        // The record IS gone (isUpdating false) but no notify was emitted -
        // user B must not be rebuilt by user A's abandoned update.
        expect(provider.isUpdating, isFalse);
        expect(notifyCount, before);
      },
    );

    test('51: a superseded update that is NOT the last active record does not '
        'notify (isUpdating stays true, no transition to announce)', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      await provider.createBodyMetric(metric(2));
      final c1a = Completer<void>();
      final c1b = Completer<void>();
      final c2 = Completer<void>();
      var call = 0;
      when(
        repo.updateBodyMetric(1, any),
      ).thenAnswer((_) => (call++ == 0) ? c1a.future : c1b.future);
      when(repo.updateBodyMetric(2, any)).thenAnswer((_) => c2.future);

      final f1a = provider.updateBodyMetric(1, metric(1)); // will be superseded
      final f1b = provider.updateBodyMetric(
        1,
        metric(1, weight: 9),
      ); // replacement for id 1
      final f2 = provider.updateBodyMetric(2, metric(2)); // id 2, still running

      final before = notifyCount;
      c1a.complete(); // the superseded id-1 update resolves
      expect(await f1a, isFalse);

      // _activeUpdates still holds (1, newGen) and (2, gen) -> not empty ->
      // no transition -> the superseded op must not notify.
      expect(provider.isUpdating, isTrue);
      expect(notifyCount, before);

      c1b.complete();
      c2.complete();
      await Future.wait([f1b, f2]);
    });

    test('45: dispose() empties active-update tracking', () async {
      epoch.activate(1);
      await provider.createBodyMetric(metric(1));
      final c = Completer<void>();
      when(repo.updateBodyMetric(1, any)).thenAnswer((_) => c.future);

      // ignore: unawaited_futures
      provider.updateBodyMetric(1, metric(1, weight: 9));
      expect(provider.isUpdating, isTrue);

      provider.dispose();
      expect(provider.isUpdating, isFalse);
      c.complete();
    });
  });

  // ================================================================
  // 46. Shared _errorMessage cross-axis ownership (re-review)
  // ================================================================

  group('shared error cross-axis ownership', () {
    test(
      '46: an older chart-request failure cannot overwrite the error a newer '
      'list-request failure already published (different axes, shared field)',
      () async {
        epoch.activate(1);
        final chartC = Completer<List<Map<String, dynamic>>>();
        final listC = Completer<List<BodyMetric>>();
        when(
          repo.getChartData(metric: anyNamed('metric'), days: anyNamed('days')),
        ).thenAnswer((_) => chartC.future);
        when(
          repo.getBodyMetrics(days: anyNamed('days')),
        ).thenAnswer((_) => listC.future);

        final chartF = provider.getChartData(); // older, axis = chart
        final listF = provider.loadBodyMetrics(); // newer, axis = list

        listC.completeError(Exception('list request failed'));
        await listF;
        expect(provider.errorMessage, contains('list request'));

        // Older chart request fails last. Its OWN axis generation
        // (_chartGen) is still current, so without a cross-axis guard it
        // would clobber the list error. It must not.
        chartC.completeError(Exception('stale chart failure'));
        await chartF;

        expect(provider.errorMessage, contains('list request'));
      },
    );

    test(
      '47: symmetric - an older list-request failure cannot overwrite a newer '
      "detail-request's published error",
      () async {
        epoch.activate(1);
        final listC = Completer<List<BodyMetric>>();
        final detailC = Completer<BodyMetric>();
        when(
          repo.getBodyMetrics(days: anyNamed('days')),
        ).thenAnswer((_) => listC.future);
        when(repo.getBodyMetricById(7)).thenAnswer((_) => detailC.future);

        final listF = provider.loadBodyMetrics(); // older, axis = list
        final detailF = provider.getBodyMetricById(7); // newer, axis = detail

        detailC.completeError(Exception('detail 7 failed'));
        await detailF;
        expect(provider.errorMessage, contains('detail 7'));

        listC.completeError(Exception('stale list failure'));
        await listF;

        expect(provider.errorMessage, contains('detail 7'));
      },
    );

    test('48: clearError() claims the error slot so an older in-flight failure '
        'cannot re-populate the dismissed error', () async {
      epoch.activate(1);
      final chartC = Completer<List<Map<String, dynamic>>>();
      when(
        repo.getChartData(metric: anyNamed('metric'), days: anyNamed('days')),
      ).thenAnswer((_) => chartC.future);

      final chartF = provider.getChartData();
      provider.clearError(); // user dismisses; newer slot claim

      chartC.completeError(Exception('stale chart failure'));
      await chartF;

      expect(provider.errorMessage, isNull);
    });

    test(
      '49: every error-capable axis is gated - each of detail, chart, create, '
      'update, delete failing AFTER a newer list failure cannot clobber the '
      "list's published error (proves the _errorGen gate on all six axes)",
      () async {
        epoch.activate(1);
        final detailC = Completer<BodyMetric>();
        final chartC = Completer<List<Map<String, dynamic>>>();
        final createC = Completer<BodyMetric>();
        final updateC = Completer<void>();
        final deleteC = Completer<void>();
        final listC = Completer<List<BodyMetric>>();
        when(repo.getBodyMetricById(7)).thenAnswer((_) => detailC.future);
        when(
          repo.getChartData(metric: anyNamed('metric'), days: anyNamed('days')),
        ).thenAnswer((_) => chartC.future);
        when(repo.createBodyMetric(any)).thenAnswer((_) => createC.future);
        when(repo.updateBodyMetric(5, any)).thenAnswer((_) => updateC.future);
        when(repo.deleteBodyMetric(6)).thenAnswer((_) => deleteC.future);
        when(
          repo.getBodyMetrics(days: anyNamed('days')),
        ).thenAnswer((_) => listC.future);

        // Start five error-capable ops on distinct axes, THEN the list load
        // last so it is the newest error-slot claimant.
        final dF = provider.getBodyMetricById(7);
        final chF = provider.getChartData();
        final crF = provider.createBodyMetric(metric(1));
        final upF = provider.updateBodyMetric(5, metric(5));
        final deF = provider.deleteBodyMetric(6);
        final liF = provider.loadBodyMetrics(); // newest

        listC.completeError(Exception('LIST error wins'));
        await liF;
        expect(provider.errorMessage, contains('LIST error wins'));

        // Every older op now fails. Each one's own axis generation is still
        // current (nothing bumped it), so only the _errorGen gate stops it
        // from clobbering the list's error.
        detailC.completeError(Exception('stale detail'));
        chartC.completeError(Exception('stale chart'));
        createC.completeError(Exception('stale create'));
        updateC.completeError(Exception('stale update'));
        deleteC.completeError(Exception('stale delete'));
        await Future.wait([dF, chF, crF, upF, deF]);

        expect(provider.errorMessage, contains('LIST error wins'));
      },
    );
  });
}
