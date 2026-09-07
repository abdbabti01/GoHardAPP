import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/login_request.dart';
import 'package:go_hard_app/data/models/signup_request.dart';
import 'package:go_hard_app/data/repositories/auth_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/unauthorized_response_policy.dart';

/// Records every dispatched [RequestOptions] and always answers 200 with an
/// empty-enough JSON body for [AuthResponse.fromJson] to parse.
class _RecordingAdapter implements HttpClientAdapter {
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
        '{"token":"t","userId":1,"name":"n","username":"u","email":"e@x.com"}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

/// GUARD TEST (per BLOCKER 1, item 10 of the required design): enumerates
/// every public authentication call site in `AuthRepository` - today
/// exactly `login()` and `signup()`, the app's only two public,
/// unauthenticated endpoints (see `ApiConfig` - there is no password-reset
/// endpoint yet) - and asserts each one is dispatched through
/// `ApiService.postPublic`, never the generic `ApiService.post`. A future
/// call site added here without going through `postPublic` fails this test
/// immediately, rather than silently inheriting the dangerous
/// `expireCurrentSession` default the generic methods use.
void main() {
  late UserSessionEpoch epoch;
  late ApiService apiService;
  late _RecordingAdapter adapter;
  late AuthRepository authRepository;

  setUp(() {
    epoch = UserSessionEpoch();
    apiService = ApiService(AuthService(), epoch);
    adapter = _RecordingAdapter();
    apiService.testHttpClientAdapter = adapter;
    authRepository = AuthRepository(apiService);
  });

  test(
    'login() dispatches under UnauthorizedResponsePolicy.reportOnly '
    '(via postPublic) and never captures a dispatch-time session token',
    () async {
      await authRepository.login(
        LoginRequest(email: 'a@example.com', password: 'x'),
      );

      expect(adapter.dispatched, hasLength(1));
      final extra = adapter.dispatched.single.extra;
      expect(
        extra[ApiService.unauthorizedPolicyExtraKey],
        UnauthorizedResponsePolicy.reportOnly,
      );
      expect(extra[ApiService.dispatchEpochExtraKey], isNull);
    },
  );

  test(
    'signup() dispatches under UnauthorizedResponsePolicy.reportOnly '
    '(via postPublic) and never captures a dispatch-time session token',
    () async {
      await authRepository.signup(
        SignupRequest(
          name: 'A',
          username: 'auser',
          email: 'a@example.com',
          password: 'x',
        ),
      );

      expect(adapter.dispatched, hasLength(1));
      final extra = adapter.dispatched.single.extra;
      expect(
        extra[ApiService.unauthorizedPolicyExtraKey],
        UnauthorizedResponsePolicy.reportOnly,
      );
      expect(extra[ApiService.dispatchEpochExtraKey], isNull);
    },
  );

  test('login() called while a DIFFERENT session (A) is already active still '
      'dispatches under reportOnly - an active session never leaks into a '
      'public call\'s policy', () async {
    epoch.activate(1);

    await authRepository.login(
      LoginRequest(email: 'b@example.com', password: 'x'),
    );

    expect(
      adapter.dispatched.single.extra[ApiService.unauthorizedPolicyExtraKey],
      UnauthorizedResponsePolicy.reportOnly,
    );
  });
}
