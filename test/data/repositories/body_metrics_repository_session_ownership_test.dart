import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/body_metric.dart';
import 'package:go_hard_app/data/repositories/body_metrics_repository.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_context.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

@GenerateMocks([AuthService, ConnectivityService])
import 'body_metrics_repository_session_ownership_test.mocks.dart';

/// Proves [BodyMetricsRepository] is fully session-bound: every authenticated
/// HTTP call carries the [SessionRequestContext] captured at operation entry
/// (pinned JWT + generation `CancelToken`), a logged-out call dispatches
/// nothing (matching each method's pre-existing empty/exception convention),
/// mid-flight session invalidation surfaces as [SessionStaleException], and
/// cancellation surfaces as [RequestCancelledException] - never as a generic
/// error and never through `onUnauthorized`.
///
/// Uses a REAL [ApiService] + [SessionRequestCoordinator] + [UserSessionEpoch]
/// wired to a deterministic fake [HttpClientAdapter], so binding is proven
/// against the real production interceptor pipeline, not a stub of it. No
/// test uses a wall-clock delay, `Future.delayed`, `Timer`, or event-queue
/// pumping - synchronization is via `Completer`s tied to the fake adapter's
/// actual dispatch.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  /// Completes the instant the fake transport's [fetch] is actually
  /// invoked - lets a test act deterministically once a request is truly in
  /// flight, with no sleep.
  Completer<void> dispatched = Completer<void>();

  bool holdForever = false;
  int statusCode = 200;
  String body = '{}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
    if (!dispatched.isCompleted) dispatched.complete();
    if (holdForever) {
      return Completer<ResponseBody>().future;
    }
    return Future.value(
      ResponseBody.fromString(
        body,
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late UserSessionEpoch epoch;
  late MockAuthService authService;
  late MockConnectivityService connectivity;
  late SessionRequestCoordinator coordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late BodyMetricsRepository repository;

  setUp(() {
    epoch = UserSessionEpoch();
    authService = MockAuthService();
    connectivity = MockConnectivityService();
    when(connectivity.isOnline).thenReturn(true);
    coordinator = SessionRequestCoordinator(epoch, authService);
    apiService = ApiService(authService, epoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
    repository = BodyMetricsRepository(
      apiService,
      epoch,
      coordinator,
      connectivity,
    );
  });

  /// Activates user [id] and points `getToken()` at that user's JWT.
  void login(int id) {
    epoch.activate(id);
    when(authService.getToken()).thenAnswer((_) async => 'jwt-$id');
  }

  UserSessionToken? extraToken(RequestOptions o) =>
      o.extra[ApiService.sessionEpochExtraKey] as UserSessionToken?;

  BodyMetric metric(int id) => BodyMetric(
    id: id,
    userId: 1,
    recordedAt: DateTime.utc(2024, 1, 1),
    createdAt: DateTime.utc(2024, 1, 1),
    weight: 70.0,
  );

  group('1. logged-out calls dispatch no HTTP', () {
    test('no session: reads return the empty result, single-record ops '
        'throw SessionStaleException, adapter never touched', () async {
      when(authService.getToken()).thenAnswer((_) async => null);

      expect(await repository.getBodyMetrics(), isEmpty);
      expect(await repository.getLatestMetric(), isNull);
      expect(await repository.getChartData(), isEmpty);
      await expectLater(
        repository.getBodyMetricById(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.createBodyMetric(metric(1)),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.updateBodyMetric(1, metric(1)),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.deleteBodyMetric(1),
        throwsA(isA<SessionStaleException>()),
      );

      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'session invalidated before the call: same empty result, no HTTP',
      () async {
        login(1);
        epoch.invalidate();

        expect(await repository.getBodyMetrics(), isEmpty);
        expect(adapter.capturedRequests, isEmpty);
      },
    );
  });

  group('2-3. every authenticated call carries the captured context', () {
    test(
      'getBodyMetrics: pinned JWT, epoch token, generation CancelToken',
      () async {
        login(1);
        adapter.body = '[]';
        final probe = await coordinator.captureContext();

        await repository.getBodyMetrics();

        final sent = adapter.capturedRequests.single;
        expect(sent.headers['Authorization'], 'Bearer jwt-1');
        expect(extraToken(sent)!.userId, 1);
        expect(identical(sent.cancelToken, probe!.cancelToken), isTrue);
      },
    );

    test(
      'getLatestMetric, getBodyMetricById, createBodyMetric, updateBodyMetric, '
      'deleteBodyMetric, getChartData are all bound',
      () async {
        login(1);
        adapter.body =
            '{"id":1,"userId":1,"recordedAt":"2024-01-01T00:00:00Z",'
            '"createdAt":"2024-01-01T00:00:00Z"}';
        await repository.getLatestMetric();
        await repository.getBodyMetricById(1);
        await repository.createBodyMetric(metric(1));
        adapter.body = '';
        await repository.updateBodyMetric(1, metric(1));
        await repository.deleteBodyMetric(1);
        adapter.body = '[]';
        await repository.getChartData();

        expect(adapter.capturedRequests, hasLength(6));
        for (final sent in adapter.capturedRequests) {
          expect(sent.headers['Authorization'], 'Bearer jwt-1');
          expect(extraToken(sent), isNotNull);
          expect(sent.cancelToken, isNotNull);
        }
      },
    );

    test(
      'the JWT sent is the one captured at entry, not a later live token',
      () async {
        login(1);
        adapter.body = '[]';
        // Storage flips to user 2 in the gap between the wrapper check and the
        // interceptor's dispatch - the pinned jwt-1 must still be sent.
        apiService.beforeDispatchEpochCheckForTesting = () async {
          when(authService.getToken()).thenAnswer((_) async => 'jwt-2');
        };

        await repository.getBodyMetrics();

        expect(
          adapter.capturedRequests.single.headers['Authorization'],
          'Bearer jwt-1',
        );
      },
    );
  });

  group('4. invalidation before dispatch -> SessionStaleException', () {
    test(
      'getBodyMetrics rethrows SessionStaleException, no request sent',
      () async {
        login(1);
        apiService.beforeDispatchEpochCheckForTesting = () async {
          epoch.invalidate();
        };

        await expectLater(
          repository.getBodyMetrics(),
          throwsA(isA<SessionStaleException>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test(
      'getLatestMetric rethrows SessionStaleException (not swallowed to null)',
      () async {
        login(1);
        apiService.beforeDispatchEpochCheckForTesting = () async {
          epoch.invalidate();
        };

        await expectLater(
          repository.getLatestMetric(),
          throwsA(isA<SessionStaleException>()),
        );
      },
    );

    test('createBodyMetric rethrows SessionStaleException', () async {
      login(1);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };

      await expectLater(
        repository.createBodyMetric(metric(1)),
        throwsA(isA<SessionStaleException>()),
      );
    });

    test(
      'getChartData rethrows SessionStaleException, not an empty list',
      () async {
        login(1);
        apiService.beforeDispatchEpochCheckForTesting = () async {
          epoch.invalidate();
        };

        await expectLater(
          repository.getChartData(),
          throwsA(isA<SessionStaleException>()),
        );
      },
    );
  });

  group('5-6. in-flight cancellation -> RequestCancelledException', () {
    test('cancelling the generation surfaces RequestCancelledException, '
        'distinct from ApiException', () async {
      login(1);
      adapter.holdForever = true;

      final future = repository.getBodyMetrics();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('cancellation does not invoke onUnauthorized', () async {
      login(1);
      adapter.holdForever = true;
      var unauthorized = 0;
      apiService.onUnauthorized = () => unauthorized++;

      final future = repository.getBodyMetricById(1);
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
      expect(unauthorized, 0);
    });

    test('getLatestMetric surfaces RequestCancelledException, never swallowed '
        'to null', () async {
      login(1);
      adapter.holdForever = true;

      final future = repository.getLatestMetric();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });
  });

  group('7-8. user B is unaffected by user A', () {
    test('after A logs out and B logs in, B captures a fresh context and '
        'completes normally', () async {
      login(1);
      epoch.invalidate();
      login(2);
      adapter.body = '[]';

      await repository.getBodyMetrics();

      final sent = adapter.capturedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer jwt-2');
      expect(extraToken(sent)!.userId, 2);
    });

    test("A's cancelled generation cannot cancel B's later request", () async {
      login(1);
      adapter.holdForever = true;
      final aFuture = repository.getBodyMetrics();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();
      await expectLater(aFuture, throwsA(isA<RequestCancelledException>()));

      // B logs in; a brand new generation CancelToken is minted.
      epoch.invalidate();
      login(2);
      adapter
        ..holdForever = false
        ..dispatched = Completer<void>()
        ..body = '[]';

      final bResult = await repository.getBodyMetrics();
      expect(bResult, isEmpty);
      expect(
        adapter.capturedRequests.last.headers['Authorization'],
        'Bearer jwt-2',
      );
    });
  });

  group('9. no nested/follow-up requests', () {
    test('getBodyMetrics is a single bound request (days query param, no '
        'follow-up call)', () async {
      login(1);
      adapter.body = '[]';

      await repository.getBodyMetrics(days: 30);

      expect(adapter.capturedRequests, hasLength(1));
      final sent = adapter.capturedRequests.single;
      expect(sent.uri.queryParameters['days'], '30');
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
      expect(extraToken(sent), isNotNull);
    });

    test('getChartData is a single bound request (metric+days query params, no '
        'follow-up call)', () async {
      login(1);
      adapter.body = '[]';

      await repository.getChartData(metric: 'bodyfat', days: 30);

      expect(adapter.capturedRequests, hasLength(1));
      final sent = adapter.capturedRequests.single;
      expect(sent.uri.queryParameters['metric'], 'bodyfat');
      expect(sent.uri.queryParameters['days'], '30');
    });
  });

  group('10. ordinary failures preserve existing public behavior', () {
    test('getBodyMetrics: a 500 rethrows an ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(
        repository.getBodyMetrics(),
        throwsA(isA<ApiException>()),
      );
    });

    test('getLatestMetric: an ordinary failure still returns null', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      expect(await repository.getLatestMetric(), isNull);
    });

    test('getChartData: a 500 rethrows an ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(
        repository.getChartData(),
        throwsA(isA<ApiException>()),
      );
    });

    test('getBodyMetricById: a 500 propagates as ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(
        repository.getBodyMetricById(1),
        throwsA(isA<ApiException>()),
      );
    });

    test('offline: getBodyMetrics returns empty, no HTTP', () async {
      login(1);
      when(connectivity.isOnline).thenReturn(false);

      expect(await repository.getBodyMetrics(), isEmpty);
      expect(adapter.capturedRequests, isEmpty);
    });
  });
}
