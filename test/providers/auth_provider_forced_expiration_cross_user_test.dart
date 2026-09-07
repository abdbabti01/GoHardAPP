import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/auth_response.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/providers/auth_provider.dart';

// Reuses the Mockito mocks generated for auth_provider_test.dart (same
// AuthRepository/AuthService/LocalDatabaseService surface, unchanged by
// this PR) - no new build_runner output.
import 'auth_provider_test.mocks.dart';

/// Builds a 401 [DioException] whose `requestOptions.extra` carries
/// [dispatchToken] under [ApiService.dispatchEpochExtraKey] - exactly what
/// the real dispatch pipeline (`ApiService._requestOptions`) attaches to
/// every request before it is sent. Mirrors the identical helper in
/// `api_service_test.dart`.
DioException _unauthorizedError(UserSessionToken? dispatchToken) {
  final options = RequestOptions(
    path: '/sessions/1',
    extra: {ApiService.dispatchEpochExtraKey: dispatchToken},
  );
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: 401,
      data: {'message': 'Unauthorized'},
    ),
  );
}

/// Proves cross-user isolation and reauthentication specifically for the
/// NEW ownership surface this PR introduces: the dispatch-time-token-based
/// forced-401 path (`ApiService.handleResponseError` +
/// `AuthProvider._performForcedExpiration`).
///
/// Cross-user isolation of actual DATA (repository/provider queries staying
/// scoped to the active user's ID, a previous user's rows remaining stored
/// but invisible, pending operations never syncing under the wrong token)
/// is already proven end-to-end by the dedicated, pre-existing
/// session-ownership suites for each repository/provider (Sessions,
/// Exercises, Goals, Programs, Friends, Direct Messages, ...), none of
/// which this PR touches. This file's job is narrower and specific to
/// this change: proving that a 401 belonging to a PREVIOUS user's request
/// can never masquerade as belonging to the CURRENT user and trigger any
/// part of the forced-expiration pass against them, and that
/// reauthentication (same user or a different one) always starts from a
/// clean, correctly re-armed slate.
void main() {
  late MockAuthRepository mockAuthRepository;
  late MockAuthService mockAuthService;
  late MockLocalDatabaseService mockLocalDb;
  late UserSessionEpoch sessionEpoch;
  late ApiService apiService;
  late SessionRequestCoordinator sessionRequestCoordinator;
  late AuthProvider authProvider;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockAuthService = MockAuthService();
    mockLocalDb = MockLocalDatabaseService();
    sessionEpoch = UserSessionEpoch();
    apiService = ApiService(mockAuthService, sessionEpoch);
    sessionRequestCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );

    when(mockAuthService.isAuthenticated()).thenAnswer((_) async => false);
    when(mockAuthService.getUserId()).thenAnswer((_) async => null);
    when(mockAuthService.getUserName()).thenAnswer((_) async => null);
    when(mockAuthService.getUserEmail()).thenAnswer((_) async => null);
    when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {});
    when(mockLocalDb.clearAll()).thenAnswer((_) async {});

    authProvider = AuthProvider(
      mockAuthRepository,
      mockAuthService,
      apiService,
      mockLocalDb,
      sessionEpoch,
      sessionRequestCoordinator,
    );
  });

  Future<void> loginAs({
    required int userId,
    required String email,
    required String token,
  }) async {
    when(mockAuthRepository.login(any)).thenAnswer(
      (_) async => AuthResponse(
        token: token,
        userId: userId,
        name: 'U$userId',
        email: email,
      ),
    );
    when(
      mockAuthService.saveToken(
        token: anyNamed('token'),
        userId: anyNamed('userId'),
        name: anyNamed('name'),
        email: anyNamed('email'),
      ),
    ).thenAnswer((_) async {});
    authProvider.updateEmail(email);
    authProvider.updatePassword('password123');
    final ok = await authProvider.login();
    expect(ok, isTrue, reason: 'test setup: login as $email must succeed');
  }

  Future<void> waitForExpirationToSettle() async {
    while (authProvider.isExpiringSession) {
      await Future.delayed(Duration.zero);
    }
  }

  test('10/30. a late 401 belonging to A\'s OLD (dispatch-time) session, '
      'delivered after B has since signed in, does not log out B, clear '
      'B\'s credentials, cancel B\'s requests, or show A\'s expiration '
      'message', () async {
    await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a');

    // Capture the exact dispatch-time token A's now-late request went
    // out with, mirroring what ApiService._requestOptions stamps onto
    // every real request at dispatch time.
    final staleToken = sessionEpoch.capture()!;

    // A's session ends and B signs in - a fresh generation.
    await loginAs(userId: 2, email: 'b@example.com', token: 'tok-b');
    final freshErrorMessage = authProvider.errorMessage;
    var sessionEndingCalls = 0;
    authProvider.onSessionEnding = () async {
      sessionEndingCalls++;
    };
    var loggedOutCalls = 0;
    authProvider.onLoggedOut = () => loggedOutCalls++;

    expect(
      sessionEpoch.isCurrent(staleToken),
      isFalse,
      reason: 'sanity check: the token must actually be stale now',
    );

    // A's late 401 finally arrives, still carrying A's stale dispatch
    // token - driven through the REAL ApiService.handleResponseError
    // ownership check (not AuthProvider's callback directly), exactly
    // as the real Dio error interceptor would deliver it.
    apiService.handleResponseError(_unauthorizedError(staleToken));
    await pumpEventQueue();

    expect(authProvider.isAuthenticated, isTrue);
    expect(authProvider.currentUserId, 2);
    expect(authProvider.currentUserEmail, 'b@example.com');
    expect(authProvider.errorMessage, freshErrorMessage);
    expect(sessionEndingCalls, 0);
    expect(loggedOutCalls, 0);
    verifyNever(mockAuthService.clearSessionCredentials());

    await waitForExpirationToSettle();
    expect(authProvider.isAuthenticated, isTrue);
    expect(authProvider.currentUserId, 2);
  });

  test(
    'same-user mirror of 10/30: a late 401 belonging to A\'s OLD '
    '(pre-re-login) session, delivered after A has re-authenticated with a '
    'fresh generation, does not log out the NEW session, clear its '
    'credentials, or show the expiration message - ownership is '
    'generation-scoped, not user-ID-scoped, so a same-user re-login must '
    'be just as immune to a stale 401 as a different user signing in',
    () async {
      await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a');
      final staleToken = sessionEpoch.capture()!;

      // A signs out and back in AS THE SAME USER - a fresh generation, same
      // userId. If ownership were ever (incorrectly) keyed by userId alone
      // instead of by generation, this stale token would wrongly look
      // "current" again since userId still matches.
      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();
      await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a-2');
      final freshErrorMessage = authProvider.errorMessage;
      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
      };
      // Reset the mock's call log now that setup (the first forced
      // expiration + the re-login) is done, so the verifyNever below
      // checks only what happens from the stale 401 onward.
      clearInteractions(mockAuthService);

      expect(
        sessionEpoch.isCurrent(staleToken),
        isFalse,
        reason:
            'sanity check: the OLD token must not describe the NEW '
            'same-user session, despite sharing a userId',
      );

      apiService.handleResponseError(_unauthorizedError(staleToken));
      await pumpEventQueue();

      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.currentUserId, 1);
      expect(authProvider.errorMessage, freshErrorMessage);
      expect(sessionEndingCalls, 0);
      verifyNever(mockAuthService.clearSessionCredentials());
    },
  );

  test('26. after forced expiration, no retained user data is published - '
      'the provider reports a fully signed-out, empty identity', () async {
    await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a');

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    expect(authProvider.isAuthenticated, isFalse);
    expect(authProvider.currentUserId, isNull);
    expect(authProvider.currentUserEmail, isNull);
  });

  test('31/32. after forced expiration, the SAME user (A) can sign in again - '
      'a fresh epoch generation is minted and the provider reports A\'s '
      'identity again', () async {
    await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a');
    final generationBeforeExpiry = sessionEpoch.generation;

    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();
    expect(authProvider.isAuthenticated, isFalse);

    await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a-2');

    expect(authProvider.isAuthenticated, isTrue);
    expect(authProvider.currentUserId, 1);
    expect(
      sessionEpoch.generation,
      greaterThan(generationBeforeExpiry),
      reason: 'reauthentication must mint a strictly newer generation',
    );
  });

  test('31. after forced expiration, a DIFFERENT user (B) can sign in and '
      'sees only B\'s identity', () async {
    await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a');
    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    await loginAs(userId: 2, email: 'b@example.com', token: 'tok-b');

    expect(authProvider.isAuthenticated, isTrue);
    expect(authProvider.currentUserId, 2);
    expect(authProvider.currentUserEmail, 'b@example.com');
  });

  test('34. a genuine, current-context 401 after reauthentication is not '
      'suppressed by anything left over from the previous forced-expiration '
      'pass - the claim is generation-scoped and self-rearms', () async {
    await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a');
    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    await loginAs(userId: 1, email: 'a@example.com', token: 'tok-a-2');
    var sessionEndingCalls = 0;
    authProvider.onSessionEnding = () async {
      sessionEndingCalls++;
    };

    // A brand-new, current-generation 401 for the new session.
    apiService.onUnauthorized?.call();
    await waitForExpirationToSettle();

    expect(
      sessionEndingCalls,
      1,
      reason:
          'the new session\'s own 401 must still be able to trigger a '
          'forced-expiration pass - nothing about the PREVIOUS pass may '
          'leave the claim permanently armed',
    );
    expect(authProvider.isAuthenticated, isFalse);
  });
}
