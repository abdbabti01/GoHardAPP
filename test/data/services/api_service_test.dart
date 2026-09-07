import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/unauthorized_response_policy.dart';

/// Builds a 401 (or, with [statusCode], any other status) [DioException]
/// whose `requestOptions.extra` carries [dispatchToken] under
/// [ApiService.dispatchEpochExtraKey] and [policy] under
/// [ApiService.unauthorizedPolicyExtraKey] - exactly what the real dispatch
/// pipeline (`ApiService._requestOptions`) attaches to every request before
/// it is sent. Passing `dispatchToken: null` (the default) simulates a
/// request that had no authenticated session at dispatch time (e.g.
/// login/signup); passing `policy: UnauthorizedResponsePolicy.reportOnly`
/// (default stays [UnauthorizedResponsePolicy.expireCurrentSession])
/// simulates a request sent via `ApiService.postPublic`.
DioException _unauthorizedError({
  UserSessionToken? dispatchToken,
  int statusCode = 401,
  UnauthorizedResponsePolicy policy =
      UnauthorizedResponsePolicy.expireCurrentSession,
}) {
  final options = RequestOptions(
    path: '/sessions/1',
    extra: {
      ApiService.dispatchEpochExtraKey: dispatchToken,
      ApiService.unauthorizedPolicyExtraKey: policy,
    },
  );
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: statusCode,
      data: {'message': 'Unauthorized'},
    ),
  );
}

void main() {
  group('ApiService - 401 ownership and callback behavior', () {
    late UserSessionEpoch epoch;
    late ApiService apiService;

    setUp(() {
      epoch = UserSessionEpoch();
      apiService = ApiService(AuthService(), epoch);
    });

    test('a current-context 401 invokes onUnauthorized exactly once for '
        'repeated 401s', () {
      epoch.activate(1);
      final token = epoch.capture()!;
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      apiService.handleResponseError(_unauthorizedError(dispatchToken: token));
      apiService.handleResponseError(_unauthorizedError(dispatchToken: token));
      apiService.handleResponseError(_unauthorizedError(dispatchToken: token));

      expect(callCount, 1);
    });

    test('does not invoke onUnauthorized for non-401 errors', () {
      epoch.activate(1);
      final token = epoch.capture()!;
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      apiService.handleResponseError(
        _unauthorizedError(dispatchToken: token, statusCode: 500),
      );

      expect(callCount, 0);
    });

    test('4. a context-free 401 (no authenticated session existed when the '
        'request was dispatched - e.g. login/signup) never invokes '
        'onUnauthorized', () {
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      apiService.handleResponseError(_unauthorizedError(dispatchToken: null));

      expect(callCount, 0);
    });

    test('a reportOnly-policy 401 never invokes onUnauthorized, even if it '
        'somehow still carried a live, current dispatch token - the policy '
        'check is independent of and precedes the token check, never merely '
        'a side effect of it', () {
      epoch.activate(1);
      final token = epoch.capture()!;
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      apiService.handleResponseError(
        _unauthorizedError(
          dispatchToken: token,
          policy: UnauthorizedResponsePolicy.reportOnly,
        ),
      );

      expect(callCount, 0);
    });

    test('10. a stale-context 401 (the session that sent the request has since '
        'been superseded) is ignored as an ownership signal - never invokes '
        'onUnauthorized for whichever session is active now', () {
      epoch.activate(1);
      final staleToken = epoch.capture()!;
      epoch.invalidate();
      epoch.activate(2); // A different session (user B) is now active.
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      apiService.handleResponseError(
        _unauthorizedError(dispatchToken: staleToken),
      );

      expect(callCount, 0);
    });

    test('resetUnauthorizedFlag allows the callback to fire again for the SAME '
        'generation', () {
      epoch.activate(1);
      final token = epoch.capture()!;
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      apiService.handleResponseError(_unauthorizedError(dispatchToken: token));
      expect(callCount, 1);

      apiService.resetUnauthorizedFlag();
      apiService.handleResponseError(_unauthorizedError(dispatchToken: token));
      expect(callCount, 2);
    });

    test('a NEW generation (a fresh login) re-arms the claim automatically, '
        'with no explicit reset needed', () {
      epoch.activate(1);
      final tokenA = epoch.capture()!;
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      apiService.handleResponseError(_unauthorizedError(dispatchToken: tokenA));
      expect(callCount, 1);

      // A brand-new session - no resetUnauthorizedFlag() call at all.
      epoch.invalidate();
      epoch.activate(1);
      final tokenA2 = epoch.capture()!;

      apiService.handleResponseError(
        _unauthorizedError(dispatchToken: tokenA2),
      );
      expect(callCount, 2);
    });
  });
}
