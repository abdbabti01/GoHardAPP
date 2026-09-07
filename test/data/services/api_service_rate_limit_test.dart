import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/rate_limited_exception.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

/// A hand-written fake - not Mockito - so this file needs no new
/// `@GenerateMocks` entry/build_runner regeneration. Overrides only
/// [getToken]; every other member keeps `AuthService`'s real (harmless in
/// the test binding) behavior.
class _FakeAuthService extends AuthService {
  @override
  Future<String?> getToken() async => 'fake-jwt';
}

/// A deterministic fake Dio transport that returns a configurable status
/// code, body, and header set - lets these tests exercise the REAL
/// `ApiService` interceptor/`_mapError` pipeline against a real HTTP
/// response shape, never a stub of the mapping logic itself.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  int statusCode = 200;
  String body = '{}';
  Map<String, List<String>> extraHeaders = const {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return Future.value(
      ResponseBody.fromString(
        body,
        statusCode,
        headers: {
          'content-type': ['application/json'],
          ...extraHeaders,
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Proves `ApiService`'s centralized HTTP 429 classification: detected
/// before the ordinary `ApiException` mapping, carries a safely-parsed
/// `Retry-After` and a sanitized `code`, is never confused with 401/403/5xx,
/// cancellation, or session-staleness, and never triggers
/// `onUnauthorized`/logout.
void main() {
  late UserSessionEpoch epoch;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;

  setUp(() {
    epoch = UserSessionEpoch();
    apiService = ApiService(AuthService(), epoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
  });

  /// Awaits [future], returning the thrown error instead of letting it
  /// propagate. Fails the test if [future] completes successfully instead.
  Future<Object> captureError(Future<Object?> future) async {
    try {
      await future;
    } catch (e) {
      return e;
    }
    fail('Expected the future to throw, but it completed successfully.');
  }

  group('HTTP 429 classification', () {
    test('1. a bare 429 (empty body, no Retry-After) throws '
        'RateLimitedException', () async {
      adapter.statusCode = 429;
      adapter.body = '';

      await expectLater(
        apiService.get<Map<String, dynamic>>('/sessions'),
        throwsA(isA<RateLimitedException>()),
      );
    });

    test('2. a 429 with {"code":"rate_limited"} throws the SAME typed '
        'exception, with the code attached', () async {
      adapter.statusCode = 429;
      adapter.body = '{"code":"rate_limited"}';

      final error = await captureError(
        apiService.get<Map<String, dynamic>>('/sessions'),
      );

      expect(error, isA<RateLimitedException>());
      expect((error as RateLimitedException).code, 'rate_limited');
    });

    test('3. an integer Retry-After parses correctly', () async {
      adapter.statusCode = 429;
      adapter.body = '';
      adapter.extraHeaders = {
        'retry-after': ['42'],
      };

      final error = await captureError(
        apiService.get<Map<String, dynamic>>('/sessions'),
      );

      expect(
        (error as RateLimitedException).retryAfter,
        const Duration(seconds: 42),
      );
    });

    test('5. header lookup is case-insensitive', () async {
      adapter.statusCode = 429;
      adapter.body = '';
      adapter.extraHeaders = {
        'Retry-After': ['15'],
      };

      final error = await captureError(
        apiService.get<Map<String, dynamic>>('/sessions'),
      );

      expect(
        (error as RateLimitedException).retryAfter,
        const Duration(seconds: 15),
      );
    });

    test(
      '6. a missing Retry-After header produces no trusted duration',
      () async {
        adapter.statusCode = 429;
        adapter.body = '';

        final error = await captureError(
          apiService.get<Map<String, dynamic>>('/sessions'),
        );

        expect((error as RateLimitedException).retryAfter, isNull);
      },
    );

    test('7. a negative Retry-After is safely rejected (no trusted '
        'duration)', () async {
      adapter.statusCode = 429;
      adapter.body = '';
      adapter.extraHeaders = {
        'retry-after': ['-30'],
      };

      final error = await captureError(
        apiService.get<Map<String, dynamic>>('/sessions'),
      );

      expect((error as RateLimitedException).retryAfter, isNull);
    });

    test(
      '7. an extreme Retry-After is clamped, never applied verbatim',
      () async {
        adapter.statusCode = 429;
        adapter.body = '';
        adapter.extraHeaders = {
          'retry-after': ['999999999'],
        };

        final error = await captureError(
          apiService.get<Map<String, dynamic>>('/sessions'),
        );

        expect(
          (error as RateLimitedException).retryAfter,
          const Duration(minutes: 15),
        );
      },
    );

    test('a non-string/oversized/unsafe "code" is dropped rather than '
        'passed through raw', () async {
      adapter.statusCode = 429;
      adapter.body =
          '{"code":"<script>not safe & way too long..............."}';

      final error = await captureError(
        apiService.get<Map<String, dynamic>>('/sessions'),
      );

      expect((error as RateLimitedException).code, isNull);
    });

    test('8. 401 still classifies as unauthorized (ApiException), not '
        'rate-limited', () async {
      epoch.activate(1); // Forced-expiration ownership needs a live session.
      adapter.statusCode = 401;
      adapter.body = '{"message":"Unauthorized"}';
      var unauthorizedCalls = 0;
      apiService.onUnauthorized = () => unauthorizedCalls++;

      await expectLater(
        apiService.get<Map<String, dynamic>>('/sessions'),
        throwsA(isA<ApiException>()),
      );
      expect(unauthorizedCalls, 1);
    });

    test('9. 403 remains ordinary ApiException (current behavior)', () async {
      adapter.statusCode = 403;
      adapter.body = '{"message":"Forbidden"}';

      await expectLater(
        apiService.get<Map<String, dynamic>>('/sessions'),
        throwsA(isA<ApiException>()),
      );
    });

    test('10. 5xx remains ordinary ApiException (current behavior)', () async {
      adapter.statusCode = 500;
      adapter.body = '{"message":"boom"}';

      await expectLater(
        apiService.get<Map<String, dynamic>>('/sessions'),
        throwsA(isA<ApiException>()),
      );
    });

    test('11. a 429 never invokes onUnauthorized / triggers logout', () async {
      adapter.statusCode = 429;
      adapter.body = '{"code":"rate_limited"}';
      var unauthorizedCalls = 0;
      apiService.onUnauthorized = () => unauthorizedCalls++;

      await expectLater(
        apiService.get<Map<String, dynamic>>('/sessions'),
        throwsA(isA<RateLimitedException>()),
      );
      expect(unauthorizedCalls, 0);
    });

    test('27. a login-shaped POST (email/password body, Authorization header) '
        'hitting a 429 never exposes any of that through the resulting '
        'exception\'s fields or toString()', () async {
      adapter.statusCode = 429;
      adapter.body = '{"code":"rate_limited"}';
      adapter.extraHeaders = {
        'retry-after': ['30'],
      };

      final error = await captureError(
        apiService.post<Map<String, dynamic>>(
          '/auth/login',
          data: {
            'email': 'victim@example.com',
            'password': 'hunter2-super-secret',
          },
        ),
      );

      expect(error, isA<RateLimitedException>());
      final e = error as RateLimitedException;
      expect(e.retryAfter, const Duration(seconds: 30));
      expect(e.code, 'rate_limited');

      final rendered = e.toString();
      expect(rendered, isNot(contains('victim@example.com')));
      expect(rendered, isNot(contains('hunter2')));
      expect(rendered, isNot(contains('/auth/login')));
      expect(rendered, 'Too many requests. Please wait and try again.');
    });

    test('23. a genuinely cancelled request throws RequestCancelledException, '
        'never RateLimitedException - the transport is configured to '
        'return 429, but a pre-cancelled CancelToken makes Dio reject '
        'before that response is ever read', () async {
      adapter.statusCode = 429;
      adapter.body = '{"code":"rate_limited"}';

      final epoch = UserSessionEpoch()..activate(1);
      final authService = _FakeAuthService();
      final coordinator = SessionRequestCoordinator(epoch, authService);
      final boundApiService = ApiService(authService, epoch)
        ..testHttpClientAdapter = adapter;

      final context = await coordinator.captureContext();
      coordinator.cancelCurrentGeneration();

      await expectLater(
        boundApiService.get<Map<String, dynamic>>(
          '/sessions',
          sessionContext: context,
        ),
        throwsA(isA<RequestCancelledException>()),
      );
    });

    test('24. a stale session throws SessionStaleException, never '
        'RateLimitedException - even with a 429 status configured on the '
        'transport, staleness is detected first', () async {
      adapter.statusCode = 429;
      adapter.body = '{"code":"rate_limited"}';

      final epoch = UserSessionEpoch()..activate(1);
      final authService = _FakeAuthService();
      final coordinator = SessionRequestCoordinator(epoch, authService);
      final boundApiService = ApiService(authService, epoch)
        ..testHttpClientAdapter = adapter;

      final context = await coordinator.captureContext();
      epoch.invalidate(); // Logout - the captured context is now stale.

      await expectLater(
        boundApiService.get<Map<String, dynamic>>(
          '/sessions',
          sessionContext: context,
        ),
        throwsA(isA<SessionStaleException>()),
      );
    });
  });
}
