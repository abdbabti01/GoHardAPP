import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/core/constants/api_config.dart';
import 'package:go_hard_app/data/repositories/account_repository.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/unauthorized_response_policy.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  final List<RequestOptions> dispatched = [];
  int statusCode = 204;
  String body = '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    dispatched.add(options);
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

/// Unlike AuthRepository's login/signup (public, unauthenticated),
/// account deletion IS authenticated by the caller's live session - a
/// genuine 401 here (e.g. the token expired mid-request) should trigger the
/// app's normal forced-session-expiration handling, not be suppressed. So,
/// unlike auth_repository_public_policy_test.dart, this asserts the
/// GENERIC (expireCurrentSession) dispatch policy, not reportOnly.
void main() {
  late UserSessionEpoch epoch;
  late ApiService apiService;
  late _ScriptedAdapter adapter;
  late AccountRepository accountRepository;

  setUp(() {
    epoch = UserSessionEpoch();
    epoch.activate(1);
    apiService = ApiService(AuthService(), epoch);
    adapter = _ScriptedAdapter();
    apiService.testHttpClientAdapter = adapter;
    accountRepository = AccountRepository(apiService);
  });

  test('deleteAccount() sends the password and targets the account route - '
      'no user id anywhere in the request', () async {
    await accountRepository.deleteAccount('s3cret');

    expect(adapter.dispatched, hasLength(1));
    final request = adapter.dispatched.single;
    expect(request.path, contains(ApiConfig.account));
    expect(request.data, {'password': 's3cret'});
  });

  test('deleteAccount() dispatches under the GENERIC (expireCurrentSession) '
      'policy - a real 401 must still end the session normally', () async {
    await accountRepository.deleteAccount('s3cret');

    expect(
      adapter.dispatched.single.extra[ApiService.unauthorizedPolicyExtraKey],
      UnauthorizedResponsePolicy.expireCurrentSession,
    );
  });

  test('a 400 (wrong password) maps to AccountDeletionOutcome.invalidPassword, '
      'never an uncaught exception', () async {
    adapter.statusCode = 400;
    adapter.body = '{"message":"Incorrect password"}';

    final result = await accountRepository.deleteAccount('wrong');

    expect(result, AccountDeletionOutcome.invalidPassword);
  });

  test('a 500 propagates as an ApiException, not invalidPassword', () async {
    adapter.statusCode = 500;
    adapter.body = '{"message":"boom"}';

    await expectLater(
      accountRepository.deleteAccount('s3cret'),
      throwsA(isA<ApiException>()),
    );
  });

  test('a successful 204 returns AccountDeletionOutcome.success', () async {
    adapter.statusCode = 204;

    final result = await accountRepository.deleteAccount('s3cret');

    expect(result, AccountDeletionOutcome.success);
  });
}
