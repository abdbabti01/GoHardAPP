import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_context.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

@GenerateMocks([AuthService])
import 'api_service_session_context_test.mocks.dart';

/// A deterministic fake Dio transport. Records every [RequestOptions] Dio
/// actually attempts to send, so tests can assert on the real headers/extra
/// /cancelToken the real interceptor pipeline produced - never a stub of
/// the interceptor itself.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  /// When true, [fetch] never completes on its own - lets a test cancel a
  /// genuinely in-flight request and observe Dio's own cancellation race
  /// (CancelableOperation vs CancelToken.whenCancel) rather than this fake
  /// needing to implement cancellation itself.
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
  late SessionRequestCoordinator coordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;

  setUp(() {
    epoch = UserSessionEpoch();
    authService = MockAuthService();
    coordinator = SessionRequestCoordinator(epoch, authService);
    apiService = ApiService(authService, epoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
  });

  Future<SessionRequestContext> captureA() async {
    epoch.activate(1);
    when(authService.getToken()).thenAnswer((_) async => 'jwt-a-secret');
    final context = await coordinator.captureContext();
    return context!;
  }

  group('legacy/unbound requests are unaffected (test 9)', () {
    test('still reads the live token and dispatches normally', () async {
      when(authService.getToken()).thenAnswer((_) async => 'live-token');

      final result = await apiService.get<Map<String, dynamic>>('/sessions');

      expect(result, isA<Map<String, dynamic>>());
      expect(
        adapter.capturedRequests.single.headers['Authorization'],
        'Bearer live-token',
      );
      verify(authService.getToken()).called(1);
    });

    test(
      'omits the Authorization header when there is no live token',
      () async {
        when(authService.getToken()).thenAnswer((_) async => null);

        await apiService.get<Map<String, dynamic>>('/sessions');

        expect(
          adapter.capturedRequests.single.headers.containsKey('Authorization'),
          isFalse,
        );
      },
    );

    test('a real 401 still invokes onUnauthorized exactly as before '
        '(test 13)', () async {
      when(authService.getToken()).thenAnswer((_) async => 'live-token');
      adapter.statusCode = 401;
      adapter.body = '{"message":"Unauthorized"}';
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      await expectLater(
        apiService.get<Map<String, dynamic>>('/sessions'),
        throwsA(isA<ApiException>()),
      );

      expect(callCount, 1);
    });
  });

  group('session-bound dispatch: credential pinning', () {
    test('storage changing to User B BEFORE the wrapper call still sends '
        "User A's JWT (test 3)", () async {
      final context = await captureA();

      when(authService.getToken()).thenAnswer((_) async => 'jwt-b-secret');

      await apiService.get<Map<String, dynamic>>(
        '/nutrition',
        sessionContext: context,
      );

      expect(
        adapter.capturedRequests.single.headers['Authorization'],
        'Bearer jwt-a-secret',
      );
    });

    test('storage changing to User B BETWEEN wrapper entry and interceptor '
        "execution still sends User A's JWT, and getToken() is not called "
        'again (test 4)', () async {
      final context = await captureA();
      clearInteractions(authService);

      apiService.beforeDispatchEpochCheckForTesting = () async {
        when(authService.getToken()).thenAnswer((_) async => 'jwt-b-secret');
      };

      await apiService.get<Map<String, dynamic>>(
        '/nutrition',
        sessionContext: context,
      );

      expect(
        adapter.capturedRequests.single.headers['Authorization'],
        'Bearer jwt-a-secret',
      );
      verifyNever(authService.getToken());
    });
  });

  group('session-bound dispatch: staleness rejection', () {
    test('epoch invalidated BEFORE the wrapper call: SessionStaleException, '
        'zero requests reach the adapter (test 5)', () async {
      final context = await captureA();
      epoch.invalidate();

      await expectLater(
        apiService.get<Map<String, dynamic>>(
          '/nutrition',
          sessionContext: context,
        ),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });

    test('epoch invalidated AFTER the wrapper check but BEFORE the '
        'interceptor runs: the SAME SessionStaleException type, zero '
        'requests reach the adapter (test 6)', () async {
      final context = await captureA();
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };

      await expectLater(
        apiService.get<Map<String, dynamic>>(
          '/nutrition',
          sessionContext: context,
        ),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });

    test('stale-before-wrapper and stale-inside-interceptor throw the '
        'exact same exception type', () async {
      final contextForWrapperCheck = await captureA();
      epoch.invalidate();
      Object? beforeWrapperError;
      try {
        await apiService.get<Map<String, dynamic>>(
          '/nutrition',
          sessionContext: contextForWrapperCheck,
        );
      } catch (e) {
        beforeWrapperError = e;
      }

      final contextForInterceptorCheck = await captureA();
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };
      Object? insideInterceptorError;
      try {
        await apiService.get<Map<String, dynamic>>(
          '/nutrition',
          sessionContext: contextForInterceptorCheck,
        );
      } catch (e) {
        insideInterceptorError = e;
      }

      expect(beforeWrapperError, isA<SessionStaleException>());
      expect(insideInterceptorError, isA<SessionStaleException>());
      expect(
        beforeWrapperError.runtimeType,
        insideInterceptorError.runtimeType,
      );
    });

    test('stale rejection does not invoke onUnauthorized (test 12)', () async {
      final context = await captureA();
      epoch.invalidate();
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      await expectLater(
        apiService.get<Map<String, dynamic>>(
          '/nutrition',
          sessionContext: context,
        ),
        throwsA(isA<SessionStaleException>()),
      );

      expect(callCount, 0);
    });
  });

  group('session-bound dispatch: cancellation', () {
    test('cancelling the context produces a distinct RequestCancelledException '
        '(test 10)', () async {
      final context = await captureA();
      adapter.holdForever = true;

      final future = apiService.get<Map<String, dynamic>>(
        '/nutrition',
        sessionContext: context,
      );
      context.cancelToken.cancel();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('cancellation does not invoke onUnauthorized (test 11)', () async {
      final context = await captureA();
      adapter.holdForever = true;
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      final future = apiService.get<Map<String, dynamic>>(
        '/nutrition',
        sessionContext: context,
      );
      context.cancelToken.cancel();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
      expect(callCount, 0);
    });
  });

  test('the JWT never appears in a stale or cancellation exception string '
      '(test 17)', () async {
    final staleContext = await captureA();
    epoch.invalidate();
    Object? staleError;
    try {
      await apiService.get<Map<String, dynamic>>(
        '/nutrition',
        sessionContext: staleContext,
      );
    } catch (e) {
      staleError = e;
    }

    final cancelContext = await captureA();
    adapter.holdForever = true;
    final future = apiService.get<Map<String, dynamic>>(
      '/nutrition',
      sessionContext: cancelContext,
    );
    cancelContext.cancelToken.cancel();
    Object? cancelError;
    try {
      await future;
    } catch (e) {
      cancelError = e;
    }

    expect(staleError.toString(), isNot(contains('jwt-a-secret')));
    expect(cancelError.toString(), isNot(contains('jwt-a-secret')));
    expect(cancelContext.toString(), isNot(contains('jwt-a-secret')));
    expect(staleContext.toString(), isNot(contains('jwt-a-secret')));
  });

  group('all five wrappers (test 18)', () {
    test('get: pinned Authorization, epoch metadata, CancelToken, query '
        'params preserved', () async {
      final context = await captureA();

      await apiService.get<Map<String, dynamic>>(
        '/nutrition',
        queryParameters: {'date': '2026-08-28'},
        sessionContext: context,
      );

      final sent = adapter.capturedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer jwt-a-secret');
      expect(sent.extra[ApiService.sessionEpochExtraKey], context.epochToken);
      expect(identical(sent.cancelToken, context.cancelToken), isTrue);
      expect(sent.queryParameters['date'], '2026-08-28');
    });

    test('post: pinned Authorization, epoch metadata, CancelToken, data '
        'preserved', () async {
      final context = await captureA();

      await apiService.post<Map<String, dynamic>>(
        '/nutrition',
        data: {'foo': 'bar'},
        sessionContext: context,
      );

      final sent = adapter.capturedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer jwt-a-secret');
      expect(sent.extra[ApiService.sessionEpochExtraKey], context.epochToken);
      expect(identical(sent.cancelToken, context.cancelToken), isTrue);
      expect(sent.data, {'foo': 'bar'});
    });

    test('put: pinned Authorization, epoch metadata, CancelToken, data '
        'preserved', () async {
      final context = await captureA();

      await apiService.put<Map<String, dynamic>>(
        '/nutrition/1',
        data: {'foo': 'baz'},
        sessionContext: context,
      );

      final sent = adapter.capturedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer jwt-a-secret');
      expect(sent.extra[ApiService.sessionEpochExtraKey], context.epochToken);
      expect(identical(sent.cancelToken, context.cancelToken), isTrue);
      expect(sent.data, {'foo': 'baz'});
    });

    test(
      'patch: pinned Authorization, epoch metadata, CancelToken, data '
      'preserved, and the existing 204-as-null handling is unchanged',
      () async {
        final context = await captureA();
        adapter.statusCode = 204;
        adapter.body = '';

        final result = await apiService.patch<Map<String, dynamic>>(
          '/sessions/1/status',
          data: {'status': 'completed'},
          sessionContext: context,
        );

        expect(result, isNull);
        final sent = adapter.capturedRequests.single;
        expect(sent.headers['Authorization'], 'Bearer jwt-a-secret');
        expect(sent.extra[ApiService.sessionEpochExtraKey], context.epochToken);
        expect(identical(sent.cancelToken, context.cancelToken), isTrue);
        expect(sent.data, {'status': 'completed'});
      },
    );

    test('delete: pinned Authorization, epoch metadata, CancelToken, and '
        'the existing status-code-based bool result is unchanged', () async {
      final context = await captureA();

      final result = await apiService.delete(
        '/nutrition/1',
        sessionContext: context,
      );

      expect(result, isTrue);
      final sent = adapter.capturedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer jwt-a-secret');
      expect(sent.extra[ApiService.sessionEpochExtraKey], context.epochToken);
      expect(identical(sent.cancelToken, context.cancelToken), isTrue);
    });
  });
}
