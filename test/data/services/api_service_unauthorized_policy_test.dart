import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/unauthorized_response_policy.dart';

/// A deterministic fake Dio transport that returns a configurable status
/// code - lets these tests exercise the REAL `ApiService` interceptor
/// pipeline (`_requestOptions`, `handleResponseError`) against a real HTTP
/// response shape, never a stub of the mapping logic itself. Also records
/// every dispatched [RequestOptions] so a test can inspect exactly what
/// `extra` a given call attached - the actual mechanism under test.
class _RecordingAdapter implements HttpClientAdapter {
  int statusCode = 200;
  final List<RequestOptions> dispatched = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    dispatched.add(options);
    return Future.value(
      ResponseBody.fromString(
        '{}',
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

/// A hand-written fake - not Mockito - so this file needs no new
/// `@GenerateMocks` entry/build_runner regeneration. Overrides only
/// [getToken], simulating a LIVE, currently-authenticated session's JWT
/// sitting in secure storage.
class _FakeAuthServiceWithLiveToken extends AuthService {
  @override
  Future<String?> getToken() async =>
      'live-jwt-belonging-to-a-different-session';
}

/// Proves the BLOCKER-1 fix for the non-destructive forced-401 feature: an
/// explicit, typed [UnauthorizedResponsePolicy] - stored in request
/// metadata AT DISPATCH TIME by which [ApiService] method the caller used,
/// never inferred from whether a session happened to be active, and never
/// decided by inspecting the request's URL - decides whether a 401 may ever
/// end the current session.
void main() {
  late UserSessionEpoch epoch;
  late ApiService apiService;
  late _RecordingAdapter adapter;

  setUp(() {
    epoch = UserSessionEpoch();
    apiService = ApiService(AuthService(), epoch);
    adapter = _RecordingAdapter();
    apiService.testHttpClientAdapter = adapter;
  });

  group('policy attachment at dispatch time', () {
    test('every protected (get/post/put/patch/delete) call attaches '
        'UnauthorizedResponsePolicy.expireCurrentSession, regardless of '
        'whether a session is active', () async {
      await apiService.get<Map<String, dynamic>>('/sessions');
      await apiService.post<Map<String, dynamic>>('/sessions', data: {});

      for (final options in adapter.dispatched) {
        expect(
          options.extra[ApiService.unauthorizedPolicyExtraKey],
          UnauthorizedResponsePolicy.expireCurrentSession,
        );
      }
    });

    test('postPublic attaches UnauthorizedResponsePolicy.reportOnly, even '
        'while a session IS active', () async {
      epoch.activate(1);

      await apiService.postPublic<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': 'a@example.com', 'password': 'wrong'},
      );

      expect(adapter.dispatched, hasLength(1));
      expect(
        adapter.dispatched.single.extra[ApiService.unauthorizedPolicyExtraKey],
        UnauthorizedResponsePolicy.reportOnly,
      );
    });

    test('postPublic NEVER captures/stores a dispatch-time session token, even '
        'while A is actively authenticated - the mechanism itself, not just '
        'the later policy check, makes ownership impossible', () async {
      epoch.activate(1);
      expect(epoch.capture(), isNotNull, reason: 'sanity check: A is active');

      await apiService.postPublic<Map<String, dynamic>>(
        '/auth/login',
        data: {},
      );

      expect(
        adapter.dispatched.single.extra[ApiService.dispatchEpochExtraKey],
        isNull,
        reason:
            'a public request must never carry ANY session token, even '
            'one that happens to be live at dispatch time',
      );
    });

    test('a protected call made with NO active session still attaches '
        'expireCurrentSession, but with a null dispatch token (nothing to '
        'own)', () async {
      await apiService.get<Map<String, dynamic>>('/sessions');

      final extra = adapter.dispatched.single.extra;
      expect(
        extra[ApiService.unauthorizedPolicyExtraKey],
        UnauthorizedResponsePolicy.expireCurrentSession,
      );
      expect(extra[ApiService.dispatchEpochExtraKey], isNull);
    });
  });

  group('postPublic never attaches an Authorization header', () {
    test('a postPublic request carries NO Authorization header even while a '
        'DIFFERENT session\'s JWT is genuinely live in secure storage - '
        'the interceptor must never read AuthService.getToken() at all for '
        'a reportOnly request, not just refrain from acting on what it '
        'would have found', () async {
      final liveTokenApiService = ApiService(
        _FakeAuthServiceWithLiveToken(),
        epoch,
      )..testHttpClientAdapter = adapter;
      epoch.activate(1);

      await liveTokenApiService.postPublic<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': 'other@example.com', 'password': 'x'},
      );

      expect(
        adapter.dispatched.single.headers.containsKey('Authorization'),
        isFalse,
        reason:
            'a public/unauthenticated endpoint must never receive an '
            'unrelated session\'s live credential, regardless of '
            'whether one happens to exist in secure storage',
      );
    });

    test('a protected (generic post()) request in the SAME situation DOES '
        'still carry the live Authorization header - unchanged, positive '
        'control case proving the fix is policy-scoped, not a blanket '
        'change to the interceptor', () async {
      final liveTokenApiService = ApiService(
        _FakeAuthServiceWithLiveToken(),
        epoch,
      )..testHttpClientAdapter = adapter;

      await liveTokenApiService.post<Map<String, dynamic>>(
        '/sessions',
        data: {},
      );

      expect(
        adapter.dispatched.single.headers['Authorization'],
        'Bearer live-jwt-belonging-to-a-different-session',
      );
    });
  });

  group('route-renaming cannot change unauthorized ownership behavior', () {
    test('a generic post() to a path that LOOKS like a public auth endpoint '
        '("/auth/login") still uses expireCurrentSession - policy is decided '
        'by which METHOD was called, never by inspecting the URL', () async {
      epoch.activate(1);

      await apiService.post<Map<String, dynamic>>('/auth/login', data: {});

      expect(
        adapter.dispatched.single.extra[ApiService.unauthorizedPolicyExtraKey],
        UnauthorizedResponsePolicy.expireCurrentSession,
        reason:
            'the URL string "/auth/login" must have zero influence - only '
            'postPublic() (a distinct method) can produce reportOnly',
      );
    });

    test('postPublic to an arbitrary, non-auth-looking path ("/anything/at/'
        'all") still uses reportOnly - policy is decided by which METHOD was '
        'called, never by inspecting the URL', () async {
      epoch.activate(1);

      await apiService.postPublic<Map<String, dynamic>>(
        '/anything/at/all',
        data: {},
      );

      expect(
        adapter.dispatched.single.extra[ApiService.unauthorizedPolicyExtraKey],
        UnauthorizedResponsePolicy.reportOnly,
      );
    });
  });

  group('end-to-end: a real 401 through the full dispatch pipeline', () {
    /// Awaits [future], returning the thrown error instead of letting it
    /// propagate. Fails the test if [future] completes successfully.
    Future<Object> captureError(Future<Object?> future) async {
      try {
        await future;
      } catch (e) {
        return e;
      }
      fail('Expected the future to throw, but it completed successfully.');
    }

    test('A is authenticated; a postPublic 401 (e.g. a "switch account" login '
        'attempt with the wrong password) never invokes onUnauthorized - A '
        'remains eligible for forced expiration only from A\'s OWN protected '
        'requests, never from this unrelated public one', () async {
      epoch.activate(1);
      var unauthorizedCalls = 0;
      apiService.onUnauthorized = () => unauthorizedCalls++;
      adapter.statusCode = 401;

      final error = await captureError(
        apiService.postPublic<Map<String, dynamic>>(
          '/auth/login',
          data: {'email': 'other@example.com', 'password': 'wrong'},
        ),
      );

      expect(error, isA<ApiException>());
      expect(unauthorizedCalls, 0);
      expect(
        epoch.isCurrent(epoch.capture()!),
        isTrue,
        reason: 'A\'s own session is completely untouched',
      );
    });

    test('A is authenticated; A\'s own protected request 401 DOES invoke '
        'onUnauthorized (unchanged, positive-control case)', () async {
      epoch.activate(1);
      var unauthorizedCalls = 0;
      apiService.onUnauthorized = () => unauthorizedCalls++;
      adapter.statusCode = 401;

      await captureError(apiService.get<Map<String, dynamic>>('/sessions'));

      expect(unauthorizedCalls, 1);
    });

    test('403 on a protected request never invokes onUnauthorized '
        '(unchanged by this policy addition)', () async {
      epoch.activate(1);
      var unauthorizedCalls = 0;
      apiService.onUnauthorized = () => unauthorizedCalls++;
      adapter.statusCode = 403;

      await captureError(apiService.get<Map<String, dynamic>>('/sessions'));

      expect(unauthorizedCalls, 0);
    });

    test('a postPublic 403 is reported as an ordinary ApiException, same as '
        'a protected 403', () async {
      adapter.statusCode = 403;

      final error = await captureError(
        apiService.postPublic<Map<String, dynamic>>('/auth/login', data: {}),
      );

      expect(error, isA<ApiException>());
    });
  });
}
