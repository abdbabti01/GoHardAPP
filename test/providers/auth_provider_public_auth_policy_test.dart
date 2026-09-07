import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/repositories/auth_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/providers/auth_provider.dart';

// Reuses the Mockito mocks generated for auth_provider_test.dart (same
// AuthService/LocalDatabaseService/SessionRequestCoordinator surface,
// unchanged by this PR) - no new build_runner output.
import 'auth_provider_test.mocks.dart';

/// A deterministic fake Dio transport whose status code/body can be
/// reconfigured between calls - lets a single test simulate "A's login
/// succeeds" followed later by "a login ATTEMPT (A's own retry, or a
/// completely different 'switch account' attempt) fails with 401" against
/// the REAL Dio interceptor/ApiService/AuthRepository/AuthProvider
/// pipeline, never a stub of any layer in between.
class _ConfigurableAdapter implements HttpClientAdapter {
  int statusCode = 200;
  Map<String, dynamic> body = const {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return Future.value(
      ResponseBody.fromString(
        jsonEncode(body),
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

/// Proves the BLOCKER-1 scenario end to end, through the REAL
/// AuthProvider -> AuthRepository -> ApiService -> Dio pipeline (never a
/// mocked AuthRepository): a user (A) who is ALREADY authenticated attempts
/// another login or signup (e.g. testing a "switch account" flow, or simply
/// mistyping a password on the same screen while still signed in elsewhere
/// in the app) that fails with 401 - A's own, unrelated, already-valid
/// session must never be forced to expire because of it.
void main() {
  late MockAuthService mockAuthService;
  late UserSessionEpoch sessionEpoch;
  late ApiService apiService;
  late _ConfigurableAdapter adapter;
  late AuthRepository authRepository;
  late SessionRequestCoordinator sessionRequestCoordinator;
  late AuthProvider authProvider;

  setUp(() {
    mockAuthService = MockAuthService();
    sessionEpoch = UserSessionEpoch();
    adapter = _ConfigurableAdapter();
    apiService = ApiService(mockAuthService, sessionEpoch)
      ..testHttpClientAdapter = adapter;
    authRepository = AuthRepository(apiService);
    sessionRequestCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );

    when(mockAuthService.isAuthenticated()).thenAnswer((_) async => false);
    when(mockAuthService.getUserId()).thenAnswer((_) async => null);
    when(mockAuthService.getUserName()).thenAnswer((_) async => null);
    when(mockAuthService.getUserEmail()).thenAnswer((_) async => null);
    when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {});
    // Every unbound request (postPublic never carries a sessionEpochToken,
    // so it always falls into the interceptor's legacy/unbound branch)
    // reads this fresh - stubbed so login()/signup() can dispatch at all.
    when(mockAuthService.getToken()).thenAnswer((_) async => null);
    when(
      mockAuthService.saveToken(
        token: anyNamed('token'),
        userId: anyNamed('userId'),
        name: anyNamed('name'),
        email: anyNamed('email'),
      ),
    ).thenAnswer((_) async {});

    authProvider = AuthProvider(
      authRepository,
      mockAuthService,
      apiService,
      sessionEpoch,
      sessionRequestCoordinator,
    );
  });

  Future<void> waitForExpirationToSettle() async {
    while (authProvider.isTerminating) {
      await Future.delayed(Duration.zero);
    }
  }

  test(
    'A is authenticated; a second login() call with a wrong password '
    'returns 401 through the REAL pipeline; A remains fully active - no '
    'forced expiration, credentials untouched, no expiration message',
    () async {
      adapter.statusCode = 200;
      adapter.body = {
        'token': 'tok-a',
        'userId': 1,
        'name': 'A',
        'username': 'a',
        'email': 'a@example.com',
      };
      authProvider.updateEmail('a@example.com');
      authProvider.updatePassword('correct-password');
      final firstLoginOk = await authProvider.login();
      expect(firstLoginOk, isTrue, reason: 'test setup: first login succeeds');
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.currentUserId, 1);

      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      adapter.statusCode = 401;
      adapter.body = {'message': 'Invalid credentials'};
      authProvider.updateEmail('a@example.com');
      authProvider.updatePassword('wrong-password');
      final secondLoginOk = await authProvider.login();
      await waitForExpirationToSettle();

      expect(secondLoginOk, isFalse);
      expect(
        authProvider.errorMessage,
        contains('Login failed'),
        reason: 'this is an ordinary login failure message',
      );
      expect(authProvider.errorMessage, isNot(contains('session expired')));
      expect(
        authProvider.isAuthenticated,
        isTrue,
        reason:
            'A\'s existing, unrelated, already-valid session must remain '
            'fully active - this login ATTEMPT failing must never end it',
      );
      expect(authProvider.currentUserId, 1);
      expect(sessionEndingCalls, 0);
      expect(loggedOutCalls, 0);
      verifyNever(mockAuthService.clearSessionCredentials());
    },
  );

  test('A is authenticated; a signup() call that fails with 401 through the '
      'REAL pipeline never expires A either', () async {
    adapter.statusCode = 200;
    adapter.body = {
      'token': 'tok-a',
      'userId': 1,
      'name': 'A',
      'username': 'a',
      'email': 'a@example.com',
    };
    authProvider.updateEmail('a@example.com');
    authProvider.updatePassword('correct-password');
    final firstLoginOk = await authProvider.login();
    expect(firstLoginOk, isTrue, reason: 'test setup: first login succeeds');

    var sessionEndingCalls = 0;
    authProvider.onSessionEnding = () async {
      sessionEndingCalls++;
    };

    adapter.statusCode = 401;
    adapter.body = {'message': 'Unauthorized'};
    authProvider.setSignupName('New');
    authProvider.setSignupUsername('newuser');
    authProvider.setSignupEmail('new@example.com');
    authProvider.setSignupPassword('password123');
    authProvider.setSignupConfirmPassword('password123');
    final signupOk = await authProvider.signup();
    await waitForExpirationToSettle();

    expect(signupOk, isFalse);
    expect(authProvider.isAuthenticated, isTrue);
    expect(authProvider.currentUserId, 1);
    expect(sessionEndingCalls, 0);
    verifyNever(mockAuthService.clearSessionCredentials());
  });
}
