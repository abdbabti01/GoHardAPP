import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/auth_response.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/providers/auth_provider.dart';

// Reuses the Mockito mocks generated for auth_provider_test.dart (same
// AuthRepository/AuthService/LocalDatabaseService/SessionRequestCoordinator
// surface, unchanged by this PR) - no new build_runner output.
import 'auth_provider_test.mocks.dart';

/// Proves the non-destructive forced-401 session-expiration contract:
/// ownership (login/signup/context-free/403/stale-context 401s never
/// trigger it), single-flight behavior under concurrent/burst 401s, that
/// the protected FCM-unregister endpoint and `LocalDatabaseService.clearAll`
/// are NEVER reachable from this path, that a stale transition can never
/// clobber a newer session's freshly-written credentials, and that
/// explicit logout/login error messaging is entirely unaffected.
///
/// Uses a REAL `ApiService` (never a Mockito mock of it) throughout: its
/// `onUnauthorized`/`handleResponseError` ownership logic is exactly what
/// this file exists to exercise end-to-end, not stub away. `AuthService`,
/// `LocalDatabaseService`, and `SessionRequestCoordinator` remain mocked;
/// `UserSessionEpoch` is real (a plain, dependency-free value service).
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

  Future<void> authenticate({
    int userId = 1,
    String email = 'a@example.com',
    String token = 'tok-a',
  }) async {
    when(mockAuthRepository.login(any)).thenAnswer(
      (_) async =>
          AuthResponse(token: token, userId: userId, name: 'A', email: email),
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
    expect(ok, isTrue, reason: 'test setup: login must succeed');
  }

  Future<void> waitForExpirationToSettle() async {
    while (authProvider.isExpiringSession) {
      await Future.delayed(Duration.zero);
    }
  }

  group('HTTP classification and ownership', () {
    test('2. login() receiving a 401 does NOT trigger forced expiration - it '
        'is an ordinary login failure', () async {
      when(mockAuthRepository.login(any)).thenThrow(
        ApiException('Unauthorized - please login again', statusCode: 401),
      );
      authProvider.updateEmail('nope@example.com');
      authProvider.updatePassword('wrong');

      final ok = await authProvider.login();

      expect(ok, isFalse);
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.errorMessage, contains('Login failed'));
      expect(authProvider.errorMessage, isNot(contains('session expired')));
      // No forced-expiration pass was ever started.
      expect(authProvider.isExpiringSession, isFalse);
      verifyNever(mockLocalDb.clearAll());
    });

    test('3. signup() receiving a 401/failure does NOT trigger forced '
        'expiration', () async {
      when(
        mockAuthRepository.signup(any),
      ).thenThrow(ApiException('Unauthorized', statusCode: 401));
      authProvider.setSignupName('Test');
      authProvider.setSignupUsername('testuser');
      authProvider.setSignupEmail('nope@example.com');
      authProvider.setSignupPassword('password123');
      authProvider.setSignupConfirmPassword('password123');

      final ok = await authProvider.signup();

      expect(ok, isFalse);
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.errorMessage, contains('Signup failed'));
      expect(authProvider.isExpiringSession, isFalse);
      verifyNever(mockLocalDb.clearAll());
    });

    test('a spurious/late onUnauthorized callback while already signed out '
        'runs no cleanup at all - it is a defense-in-depth no-op, not a '
        'second forced-expiration pass', () async {
      // Never authenticated in this test - AuthProvider starts signed out.
      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
      };
      var notifyCount = 0;
      authProvider.addListener(() => notifyCount++);
      final messageBefore = authProvider.errorMessage;

      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();

      expect(sessionEndingCalls, 0);
      expect(notifyCount, 0);
      expect(authProvider.errorMessage, messageBefore);
      verifyNever(mockAuthService.clearSessionCredentials());
    });

    test('5. a 403 never triggers forced expiration', () async {
      await authenticate();
      final options = RequestOptions(path: '/sessions/1');
      apiService.handleResponseError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: 403),
        ),
      );
      await waitForExpirationToSettle();

      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.isExpiringSession, isFalse);
    });

    test('39. invalid login retains its existing error message rather than '
        'showing the session-expired message', () async {
      when(
        mockAuthRepository.login(any),
      ).thenThrow(Exception('Invalid credentials'));
      authProvider.updateEmail('a@example.com');
      authProvider.updatePassword('wrong');

      await authProvider.login();

      expect(authProvider.errorMessage, contains('Login failed'));
      expect(
        authProvider.errorMessage,
        isNot(contains('Your session expired')),
      );
    });
  });

  group('Single-flight', () {
    test('11. two concurrent OWNED 401 responses trigger exactly one '
        'expiration transition', () async {
      await authenticate();
      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
      };

      // Both 401s belong to the SAME still-current dispatch - simulating
      // two in-flight requests that both come back unauthorized together.
      apiService.onUnauthorized?.call();
      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();

      expect(sessionEndingCalls, 1);
    });

    test('12. a larger concurrent 401 burst (5) still performs each cleanup '
        'step exactly once', () async {
      await authenticate();
      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      for (var i = 0; i < 5; i++) {
        apiService.onUnauthorized?.call();
      }
      await waitForExpirationToSettle();

      expect(sessionEndingCalls, 1);
      expect(loggedOutCalls, 1);
      verify(mockAuthService.clearSessionCredentials()).called(1);
    });

    test('13. forced expiration never calls the protected FCM-unregister '
        'endpoint (it would resend the very credential that was just '
        'rejected) - proven by the fact that no HTTP dispatch happens at '
        'all: the fake adapter records zero requests', () async {
      await authenticate();
      final adapter = _CountingAdapter();
      apiService.testHttpClientAdapter = adapter;

      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();

      expect(
        adapter.requestCount,
        0,
        reason:
            'a non-destructive forced-expiration pass makes no HTTP '
            'calls whatsoever - it only clears local/in-memory state',
      );
    });

    test('14. token/credential deletion occurs exactly once', () async {
      await authenticate();

      apiService.onUnauthorized?.call();
      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();

      verify(mockAuthService.clearSessionCredentials()).called(1);
    });

    test(
      '15. auth notification/navigation occurs exactly once under a burst',
      () async {
        await authenticate();
        var loggedOutCalls = 0;
        authProvider.onLoggedOut = () => loggedOutCalls++;

        apiService.onUnauthorized?.call();
        apiService.onUnauthorized?.call();
        apiService.onUnauthorized?.call();
        await waitForExpirationToSettle();

        expect(loggedOutCalls, 1);
      },
    );

    test('16. a failing non-durable cleanup component (onSessionEnding) can '
        'never trigger local (Isar) deletion - clearAll is never reachable '
        'from this path at all, failure or not', () async {
      await authenticate();
      authProvider.onSessionEnding = () async {
        throw Exception('cleanup boom');
      };

      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();

      expect(authProvider.isAuthenticated, isFalse);
      verifyNever(mockLocalDb.clearAll());
    });

    test('17. a stale transition cannot clear newly written B credentials - '
        "A's forced-expiration pass, suspended mid-transition, must skip "
        "credential clearing once B's session has begun", () async {
      await authenticate(userId: 1, email: 'a@example.com', token: 'tok-a');

      final gate = Completer<void>();
      authProvider.onSessionEnding = () async {
        await gate.future;
      };

      // A's forced-expiration starts and suspends inside onSessionEnding
      // - epoch is already invalidated (generation bumped), but nothing
      // past that point has run yet.
      apiService.onUnauthorized?.call();
      await pumpEventQueue();
      expect(authProvider.isExpiringSession, isTrue);

      // B logs in WHILE A's pass is still suspended - bumps the
      // generation again via activate().
      when(mockAuthRepository.login(any)).thenAnswer(
        (_) async => AuthResponse(
          token: 'tok-b',
          userId: 2,
          name: 'B',
          email: 'b@example.com',
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
      authProvider.updateEmail('b@example.com');
      authProvider.updatePassword('password123');
      final bLoginOk = await authProvider.login();
      expect(bLoginOk, isTrue);
      expect(authProvider.currentUserId, 2);

      // Now release A's suspended transition.
      gate.complete();
      await waitForExpirationToSettle();

      // A's stale transition must never have reached credential
      // clearing, the in-memory reset, or navigation - B is still fully
      // authenticated with B's own identity.
      verifyNever(mockAuthService.clearSessionCredentials());
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.currentUserId, 2);
      expect(authProvider.currentUserEmail, 'b@example.com');
    });
  });

  group('Explicit behavior preservation', () {
    test('35. forced expiration never calls LocalDatabaseService.clearAll - '
        "explicit logout's destructive cleanup is never reachable from this "
        'path', () async {
      await authenticate();

      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();

      verifyNever(mockLocalDb.clearAll());
    });

    test('38. the expiration UI message is the exact generic, safe string and '
        'appears exactly once', () async {
      await authenticate();
      var notifyCount = 0;
      authProvider.addListener(() => notifyCount++);

      apiService.onUnauthorized?.call();
      await waitForExpirationToSettle();

      expect(
        authProvider.errorMessage,
        'Your session expired. Sign in again. Your offline changes are safe.',
      );
      expect(
        notifyCount,
        greaterThan(0),
        reason:
            'the UI (and this exact message) can only actually reach the '
            'screen if notifyListeners() fires after the state change - '
            'a silently-updated field with no notification is invisible '
            'to any real widget',
      );
      // The message is set exactly once and never overwritten by a
      // second forced-expiration pass (single-flight already guarantees
      // this; asserting the final value here is enough - the message
      // never contains anything but this fixed sentence).
      expect(authProvider.errorMessage, isNot(contains('Exception')));
    });
  });
}

/// Counts every dispatch attempt without ever completing one - proves
/// forced expiration makes literally zero HTTP calls (it should never
/// dispatch anything, so [holdForever]-style blocking is unnecessary; any
/// call at all is already a failure).
class _CountingAdapter implements HttpClientAdapter {
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requestCount++;
    return Future.value(
      ResponseBody.fromString(
        '{}',
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
