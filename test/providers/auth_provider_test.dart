import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:go_hard_app/providers/auth_provider.dart';
import 'package:go_hard_app/data/repositories/auth_repository.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/auth_response.dart';
import 'package:go_hard_app/data/services/rate_limited_exception.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';

@GenerateMocks([
  AuthRepository,
  AuthService,
  ApiService,
  LocalDatabaseService,
  SessionRequestCoordinator,
])
import 'auth_provider_test.mocks.dart';

/// A deterministic fake Dio transport for the real end-to-end
/// session-bound cancellation test below (PR C). Mirrors the fake used in
/// api_service_session_context_test.dart: it can hang forever so a test
/// can cancel a genuinely in-flight request and observe Dio's own
/// cancellation race, rather than one that raced to completion on its own.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  bool holdForever = false;
  int statusCode = 200;
  String body = '{}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
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
  late AuthProvider authProvider;
  late MockAuthRepository mockAuthRepository;
  late MockAuthService mockAuthService;
  late MockApiService mockApiService;
  // A real UserSessionEpoch instance (not a mock) - it's a plain,
  // dependency-free value service, so tests exercise its actual
  // activate()/invalidate()/capture()/isCurrent() behavior rather than
  // stubbing it.
  late UserSessionEpoch sessionEpoch;
  // A Mockito mock by default for tests unrelated to cancellation
  // (cancelCurrentGeneration() is void, so no stubbing is required for it
  // to be a safe no-op here). Tests that specifically exercise
  // cancellation ordering/counting/real-request behavior construct their
  // own coordinator (mocked or real) locally instead of relying on this
  // shared instance.
  late MockSessionRequestCoordinator mockSessionRequestCoordinator;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockAuthService = MockAuthService();
    mockApiService = MockApiService();
    sessionEpoch = UserSessionEpoch();
    mockSessionRequestCoordinator = MockSessionRequestCoordinator();
    // MockSessionRequestCoordinator throws on any unstubbed call
    // (throwOnMissingStub) - give the void cancelCurrentGeneration() a
    // default no-op stub since most tests in this file don't care about
    // cancellation behavior at all.
    when(
      mockSessionRequestCoordinator.cancelCurrentGeneration(),
    ).thenReturn(null);

    // Stub the auth check methods called in constructor
    when(mockAuthService.isAuthenticated()).thenAnswer((_) async => false);
    when(mockAuthService.getUserId()).thenAnswer((_) async => null);
    when(mockAuthService.getUserName()).thenAnswer((_) async => null);
    when(mockAuthService.getUsername()).thenAnswer((_) async => null);
    when(mockAuthService.getUserEmail()).thenAnswer((_) async => null);
    when(mockAuthService.saveUsername(any)).thenAnswer((_) async {});

    authProvider = AuthProvider(
      mockAuthRepository,
      mockAuthService,
      mockApiService,
      sessionEpoch,
      mockSessionRequestCoordinator,
    );
  });

  group('AuthProvider - Login Tests', () {
    test('login() should succeed with valid credentials', () async {
      // Arrange
      const email = 'test@example.com';
      const password = 'password123';
      final authResponse = AuthResponse(
        token: 'fake-jwt-token',
        userId: 1,
        name: 'Test User',
        email: email,
      );

      when(mockAuthRepository.login(any)).thenAnswer((_) async => authResponse);
      when(
        mockAuthService.saveToken(
          token: anyNamed('token'),
          userId: anyNamed('userId'),
          name: anyNamed('name'),
          email: anyNamed('email'),
        ),
      ).thenAnswer((_) async => {});

      authProvider.updateEmail(email);
      authProvider.updatePassword(password);

      // Act
      final result = await authProvider.login();

      // Assert
      expect(result, true);
      expect(authProvider.isAuthenticated, true);
      expect(authProvider.currentUserId, 1);
      expect(authProvider.currentUserName, 'Test User');
      expect(authProvider.currentUserEmail, email);
      expect(authProvider.errorMessage, '');
      verify(mockAuthRepository.login(any)).called(1);
      verify(
        mockAuthService.saveToken(
          token: 'fake-jwt-token',
          userId: 1,
          name: 'Test User',
          email: email,
        ),
      ).called(1);
    });

    test('login() should fail with empty email', () async {
      // Arrange
      authProvider.updateEmail('');
      authProvider.updatePassword('password123');

      // Act
      final result = await authProvider.login();

      // Assert
      expect(result, false);
      expect(authProvider.isAuthenticated, false);
      expect(authProvider.errorMessage, 'Please enter both email and password');
      verifyNever(mockAuthRepository.login(any));
    });

    test('login() should fail with empty password', () async {
      // Arrange
      authProvider.updateEmail('test@example.com');
      authProvider.updatePassword('');

      // Act
      final result = await authProvider.login();

      // Assert
      expect(result, false);
      expect(authProvider.isAuthenticated, false);
      expect(authProvider.errorMessage, 'Please enter both email and password');
      verifyNever(mockAuthRepository.login(any));
    });

    test('login() should handle repository errors', () async {
      // Arrange
      authProvider.updateEmail('test@example.com');
      authProvider.updatePassword('password123');

      when(
        mockAuthRepository.login(any),
      ).thenThrow(Exception('Invalid credentials'));

      // Act
      final result = await authProvider.login();

      // Assert
      expect(result, false);
      expect(authProvider.isAuthenticated, false);
      expect(authProvider.errorMessage, contains('Login failed'));
      verify(mockAuthRepository.login(any)).called(1);
    });

    test('26. login() 429 shows the friendly generic message, does not log '
        'out, does not disclose account existence, and preserves entered '
        'credentials', () async {
      // Arrange
      authProvider.updateEmail('test@example.com');
      authProvider.updatePassword('password123');

      when(mockAuthRepository.login(any)).thenThrow(
        const RateLimitedException(retryAfter: Duration(seconds: 30)),
      );

      // Act
      final result = await authProvider.login();

      // Assert
      expect(result, false);
      expect(authProvider.isAuthenticated, false);
      expect(
        authProvider.errorMessage,
        'Too many attempts. Please wait and try again.',
      );
      // No raw header/body/duration/class-name text reaches the message.
      expect(authProvider.errorMessage, isNot(contains('RateLimited')));
      expect(authProvider.errorMessage, isNot(contains('30')));
      // Entered credentials survive - only the SUCCESS path clears them.
      expect(authProvider.email, 'test@example.com');
      expect(authProvider.password, 'password123');
      verify(mockAuthRepository.login(any)).called(1);
    });

    test('28. login() never automatically retries after a 429', () async {
      authProvider.updateEmail('test@example.com');
      authProvider.updatePassword('password123');
      when(
        mockAuthRepository.login(any),
      ).thenThrow(const RateLimitedException());

      await authProvider.login();

      verify(mockAuthRepository.login(any)).called(1);
    });
  });

  group('AuthProvider - Signup Tests', () {
    test('signup() should succeed with valid data', () async {
      // Arrange
      const name = 'Test User';
      const email = 'test@example.com';
      const password = 'password123';
      final authResponse = AuthResponse(
        token: 'fake-jwt-token',
        userId: 1,
        name: name,
        email: email,
      );

      when(
        mockAuthRepository.signup(any),
      ).thenAnswer((_) async => authResponse);
      when(
        mockAuthService.saveToken(
          token: anyNamed('token'),
          userId: anyNamed('userId'),
          name: anyNamed('name'),
          email: anyNamed('email'),
        ),
      ).thenAnswer((_) async => {});

      authProvider.setSignupName(name);
      authProvider.setSignupUsername('testuser');
      authProvider.setSignupEmail(email);
      authProvider.setSignupPassword(password);
      authProvider.setSignupConfirmPassword(password); // Must match password

      // Act
      final result = await authProvider.signup();

      // Assert
      expect(result, true);
      expect(authProvider.isAuthenticated, true);
      expect(authProvider.currentUserId, 1);
      verify(mockAuthRepository.signup(any)).called(1);
    });

    test('signup() should fail with short password', () async {
      // Arrange
      authProvider.setSignupName('Test User');
      authProvider.setSignupUsername('testuser');
      authProvider.setSignupEmail('test@example.com');
      authProvider.setSignupPassword('123'); // Too short
      authProvider.setSignupConfirmPassword('123');

      // Act
      final result = await authProvider.signup();

      // Assert
      expect(result, false);
      expect(
        authProvider.errorMessage,
        'Password must be at least 6 characters',
      );
      verifyNever(mockAuthRepository.signup(any));
    });

    test('27. signup() 429 behaves identically to login() - friendly generic '
        'message, no account-existence disclosure, no logout, entered fields '
        'preserved', () async {
      const name = 'Test User';
      const email = 'test@example.com';
      const password = 'password123';
      authProvider.setSignupName(name);
      authProvider.setSignupUsername('testuser');
      authProvider.setSignupEmail(email);
      authProvider.setSignupPassword(password);
      authProvider.setSignupConfirmPassword(password);

      when(
        mockAuthRepository.signup(any),
      ).thenThrow(const RateLimitedException(code: 'rate_limited'));

      final result = await authProvider.signup();

      expect(result, false);
      expect(authProvider.isAuthenticated, false);
      expect(
        authProvider.errorMessage,
        'Too many attempts. Please wait and try again.',
      );
      expect(authProvider.errorMessage, isNot(contains('rate_limited')));
      expect(authProvider.signupEmail, email);
      expect(authProvider.signupPassword, password);
      verify(mockAuthRepository.signup(any)).called(1);
    });

    test('28. signup() never automatically retries after a 429', () async {
      authProvider.setSignupName('Test User');
      authProvider.setSignupUsername('testuser');
      authProvider.setSignupEmail('test@example.com');
      authProvider.setSignupPassword('password123');
      authProvider.setSignupConfirmPassword('password123');
      when(
        mockAuthRepository.signup(any),
      ).thenThrow(const RateLimitedException());

      await authProvider.signup();

      verify(mockAuthRepository.signup(any)).called(1);
    });
  });

  group('AuthProvider - Logout Tests', () {
    test('logout() should clear all auth data', () async {
      // Arrange
      when(
        mockAuthService.clearSessionCredentials(),
      ).thenAnswer((_) async => {});

      // Act
      await authProvider.logout();

      // Assert
      expect(authProvider.isAuthenticated, false);
      expect(authProvider.currentUserId, null);
      expect(authProvider.currentUserName, null);
      expect(authProvider.currentUserEmail, null);
      verify(mockAuthService.clearSessionCredentials()).called(1);
    });
  });

  group('AuthProvider - Error Handling', () {
    test('clearError() should clear error message', () {
      // Arrange
      authProvider.setError('Test error');
      expect(authProvider.errorMessage, 'Test error');

      // Act
      authProvider.clearError();

      // Assert
      expect(authProvider.errorMessage, '');
    });

    test('setError() should set error message', () {
      // Act
      authProvider.setError('Custom error');

      // Assert
      expect(authProvider.errorMessage, 'Custom error');
    });
  });

  // -------------------------------------------------------------------
  // Logout PR 1: centralized active-resource teardown and reliable
  // navigation for every logout trigger.
  //
  // These tests use a REAL ApiService (constructed with the same
  // mockAuthService already used elsewhere in this file) rather than a
  // Mockito mock of ApiService, specifically so that `onUnauthorized` -
  // a plain settable field, not a method - genuinely round-trips the
  // closure AuthProvider's constructor assigns to it. A Mockito mock's
  // field accessors are intercepted the same way method calls are, and an
  // unstubbed getter would not reliably return what the constructor's
  // setter call had "stored" - so simulating a real 401 by invoking
  // `apiService.onUnauthorized?.call()` needs the real object here.
  // Constructing a real ApiService is safe in this environment: its
  // constructor only builds a Dio instance and registers interceptors, no
  // network or platform-channel call happens until a request is actually
  // made, which these tests never do.
  // -------------------------------------------------------------------
  group('AuthProvider - Logout coordination (Logout PR 1)', () {
    late ApiService apiService;
    late SessionRequestCoordinator sessionRequestCoordinator;
    late List<String> calls;

    Future<void> authenticate() async {
      when(mockAuthRepository.login(any)).thenAnswer(
        (_) async => AuthResponse(
          token: 'tok',
          userId: 1,
          name: 'Test User',
          email: 'test@example.com',
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
      authProvider.updateEmail('test@example.com');
      authProvider.updatePassword('password123');
      final ok = await authProvider.login();
      expect(ok, isTrue, reason: 'test setup: login must succeed');
    }

    setUp(() {
      sessionEpoch = UserSessionEpoch();
      apiService = ApiService(mockAuthService, sessionEpoch);
      sessionRequestCoordinator = SessionRequestCoordinator(
        sessionEpoch,
        mockAuthService,
      );
      calls = [];

      authProvider = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        sessionEpoch,
        sessionRequestCoordinator,
      );

      when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {
        calls.add('clearSessionCredentials');
      });
    });

    test('manual logout awaits onSessionEnding before clearing credentials, '
        'and never touches durable local data', () async {
      authProvider.onSessionEnding = () async {
        calls.add('onSessionEnding');
      };
      authProvider.onLoggedOut = () => calls.add('onLoggedOut');

      await authProvider.logout();

      expect(calls, [
        'onSessionEnding',
        'clearSessionCredentials',
        'onLoggedOut',
      ]);
      expect(
        calls.indexOf('onSessionEnding') <
            calls.indexOf('clearSessionCredentials'),
        isTrue,
      );
    });

    test(
      'forced 401 logout invokes the same onSessionEnding/onLoggedOut hooks',
      () async {
        await authenticate();

        authProvider.onSessionEnding = () async {
          calls.add('onSessionEnding');
        };
        var loggedOutCalls = 0;
        authProvider.onLoggedOut = () => loggedOutCalls++;

        apiService.onUnauthorized?.call();
        await pumpEventQueue();

        expect(calls, contains('onSessionEnding'));
        expect(calls, contains('clearSessionCredentials'));
        expect(
          calls.indexOf('onSessionEnding') <
              calls.indexOf('clearSessionCredentials'),
          isTrue,
        );
        expect(loggedOutCalls, 1);
        expect(authProvider.isAuthenticated, isFalse);
        expect(
          authProvider.errorMessage,
          'Your session expired. Sign in again. Your offline changes are safe.',
        );
      },
    );

    test('manual logout and a concurrent forced 401 share ONE termination '
        'pass via the generation-owned arbiter - exactly one onSessionEnding '
        'call, one credential clear, and one navigation, with the end state '
        'consistently logged-out and durable data untouched. See '
        'auth_provider_termination_race_test.dart for the full precedence '
        'and ordering matrix.', () async {
      await authenticate();

      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      // Fire both triggers before either can complete.
      final manualLogout = authProvider.logout();
      apiService.onUnauthorized?.call();
      await manualLogout;
      while (authProvider.isTerminating) {
        await Future.delayed(Duration.zero);
      }

      expect(
        sessionEndingCalls,
        1,
        reason:
            'the forced-401 trigger joins the already-running manual-logout '
            'pass instead of starting its own - see '
            'AuthProvider._beginOrJoinTermination',
      );
      expect(calls.where((c) => c == 'clearSessionCredentials').length, 1);
      expect(loggedOutCalls, 1);
      expect(authProvider.isAuthenticated, isFalse);
      expect(
        authProvider.errorMessage,
        '',
        reason:
            'explicit logout participated, so its (empty) message wins '
            'precedence over the generic expiration message',
      );
    });

    test(
      'repeated manual logout calls are idempotent: one cleanup pass, one '
      'navigation, and the guard resets for a later authenticated session',
      () async {
        var sessionEndingCalls = 0;
        authProvider.onSessionEnding = () async {
          sessionEndingCalls++;
        };
        var loggedOutCalls = 0;
        authProvider.onLoggedOut = () => loggedOutCalls++;

        final first = authProvider.logout();
        final second = authProvider.logout();
        await Future.wait([first, second]);

        expect(
          sessionEndingCalls,
          1,
          reason: 'two concurrent calls must produce exactly one cleanup pass',
        );
        expect(loggedOutCalls, 1);
        expect(
          authProvider.isLoggingOut,
          isFalse,
          reason:
              'the guard must release once the pass completes, so a later '
              'authenticated session can log out again',
        );

        // A later, separate logout call (simulating a subsequent
        // authenticated session) must start a genuinely fresh pass, not be
        // silently swallowed by a stale guard.
        await authProvider.logout();
        expect(sessionEndingCalls, 2);
        expect(loggedOutCalls, 2);
      },
    );

    test('a session-cleanup failure does not block credential clearing or '
        'navigation', () async {
      authProvider.onSessionEnding = () async {
        throw Exception('coordinator boom');
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      await authProvider.logout();

      expect(calls, contains('clearSessionCredentials'));
      expect(authProvider.isAuthenticated, isFalse);
      expect(loggedOutCalls, 1);
    });

    test('clearSessionCredentials throwing does not prevent state reset or '
        'navigation, and logout() itself does not throw', () async {
      when(
        mockAuthService.clearSessionCredentials(),
      ).thenThrow(Exception('secure storage unavailable'));
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      await expectLater(authProvider.logout(), completes);

      expect(authProvider.isAuthenticated, isFalse);
      expect(loggedOutCalls, 1);
    });

    test('a real BackgroundService failure (no platform bindings set up in '
        'this test file) does not prevent state reset or navigation', () async {
      // BackgroundService.clearAuthToken() genuinely throws here -
      // SharedPreferences.getInstance() has no platform binding in this
      // test file (no TestWidgetsFlutterBinding.ensureInitialized()).
      // This is a real, naturally-occurring failure, not a simulated
      // one - exactly what proves later steps survive it.
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      await expectLater(authProvider.logout(), completes);

      expect(authProvider.isAuthenticated, isFalse);
      expect(loggedOutCalls, 1);
    });

    test('multiple simultaneous failures (coordinator, credentials) still '
        'result in every step being attempted exactly once, with state '
        'reset and navigation completing', () async {
      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
        throw Exception('coordinator boom');
      };
      when(
        mockAuthService.clearSessionCredentials(),
      ).thenThrow(Exception('secure storage boom'));
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      await expectLater(authProvider.logout(), completes);

      expect(sessionEndingCalls, 1, reason: 'attempted exactly once');
      expect(authProvider.isAuthenticated, isFalse);
      expect(loggedOutCalls, 1);
    });

    test('forced 401 logout with a clearSessionCredentials failure produces '
        'no uncaught asynchronous error, reaches the logged-out state, and '
        'still navigates', () async {
      await authenticate();
      when(
        mockAuthService.clearSessionCredentials(),
      ).thenThrow(Exception('secure storage boom'));
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      Object? uncaughtError;
      await runZonedGuarded(
        () async {
          apiService.onUnauthorized?.call();
          await pumpEventQueue();
        },
        (error, stackTrace) {
          uncaughtError = error;
        },
      );

      expect(
        uncaughtError,
        isNull,
        reason: 'no uncaught async error may escape the forced-logout path',
      );
      expect(authProvider.isAuthenticated, isFalse);
      expect(loggedOutCalls, 1);
    });

    // -----------------------------------------------------------------
    // onLoggedOut is now guarded by its own try/catch inside
    // _performLogout (step 6) - the same first line of defense every
    // other step already had. This is what makes manual logout and
    // forced/401 logout share identical failure behavior for a throwing
    // navigation callback: previously only the forced-401 trigger had an
    // outer backstop (_handleSessionExpired's catchError on the unawaited
    // Future), so a throwing onLoggedOut would complete forced logout
    // cleanly but propagate uncaught out of manual logout's `await
    // context.read<AuthProvider>().logout()` in MeScreen. The outer catch
    // on the forced/401 path remains as a last-resort backstop for
    // anything that could somehow escape the inner guard itself, but is
    // no longer the only thing standing between a throwing callback and
    // an uncaught error.
    // -----------------------------------------------------------------
    test('manual logout with a throwing onLoggedOut callback completes '
        'without throwing, remains unauthenticated, still performs '
        'credential cleanup, and attempts the callback exactly once', () async {
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () {
        loggedOutCalls++;
        throw Exception('nav boom');
      };

      await expectLater(authProvider.logout(), completes);

      expect(authProvider.isAuthenticated, isFalse);
      expect(calls, contains('clearSessionCredentials'));
      expect(loggedOutCalls, 1);
    });

    test('forced 401 logout with the same throwing onLoggedOut callback '
        'produces no uncaught asynchronous error, reaches the same final '
        'state, and attempts the callback exactly once', () async {
      await authenticate();
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () {
        loggedOutCalls++;
        throw Exception('nav boom');
      };

      Object? uncaughtError;
      await runZonedGuarded(
        () async {
          apiService.onUnauthorized?.call();
          await pumpEventQueue();
        },
        (error, stackTrace) {
          uncaughtError = error;
        },
      );

      expect(uncaughtError, isNull);
      expect(authProvider.isAuthenticated, isFalse);
      expect(loggedOutCalls, 1);
    });

    test('concurrent manual logout + forced 401, both with a throwing '
        'onLoggedOut callback, produce no uncaught error - they share ONE '
        'termination pass, so the callback is attempted exactly once, not '
        'once per trigger', () async {
      await authenticate();
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () {
        loggedOutCalls++;
        throw Exception('nav boom');
      };

      Object? uncaughtError;
      await runZonedGuarded(
        () async {
          final manualLogout = authProvider.logout();
          apiService.onUnauthorized?.call();
          await manualLogout;
          while (authProvider.isTerminating) {
            await Future.delayed(Duration.zero);
          }
        },
        (error, stackTrace) {
          uncaughtError = error;
        },
      );

      expect(
        uncaughtError,
        isNull,
        reason: 'a throwing onLoggedOut must never escape the shared pass',
      );
      expect(loggedOutCalls, 1);
      expect(authProvider.isAuthenticated, isFalse);
    });

    test('a later authenticated session can perform a fresh logout after an '
        'earlier onLoggedOut callback failure', () async {
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () {
        loggedOutCalls++;
        throw Exception('nav boom');
      };

      await authProvider.logout();
      expect(loggedOutCalls, 1);
      expect(
        authProvider.isLoggingOut,
        isFalse,
        reason: 'the guard must release even though the callback threw',
      );

      // A later, separate logout call (simulating a subsequent
      // authenticated session) must start a genuinely fresh pass, not
      // be silently swallowed by a stale guard left over from the
      // earlier callback failure.
      await authProvider.logout();
      expect(loggedOutCalls, 2);
    });
  });

  // -------------------------------------------------------------------
  // Logout PR 2A: AuthProvider is the exclusive owner of
  // UserSessionEpoch.activate()/invalidate(). These tests prove every live
  // authentication-success path activates exactly once with the
  // authoritative user ID, every logout trigger invalidates exactly once
  // per logical pass, and the generation never resets, decrements, or gets
  // reused across a logout -> login cycle.
  // -------------------------------------------------------------------
  group('AuthProvider - Session epoch ownership (Logout PR 2A)', () {
    Future<void> pumpUntilInitialized(AuthProvider provider) async {
      while (provider.isInitializing) {
        await Future.delayed(Duration.zero);
      }
    }

    test('a failed startup restoration (isAuthenticated() == false) never '
        'activates the epoch', () async {
      // The top-level setUp() already stubs isAuthenticated() -> false
      // and constructs `authProvider` against `sessionEpoch`.
      await pumpUntilInitialized(authProvider);

      expect(authProvider.isAuthenticated, isFalse);
      expect(sessionEpoch.capture(), isNull);
    });

    test('a valid stored session restored at startup activates the epoch '
        'exactly once with the authoritative user ID, before it becomes '
        'observable', () async {
      final freshEpoch = UserSessionEpoch();
      when(mockAuthService.isAuthenticated()).thenAnswer((_) async => true);
      when(mockAuthService.getUserId()).thenAnswer((_) async => 42);
      when(
        mockAuthService.getUserName(),
      ).thenAnswer((_) async => 'Restored User');
      when(
        mockAuthService.getUserEmail(),
      ).thenAnswer((_) async => 'restored@example.com');

      final restored = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        mockApiService,
        freshEpoch,
        SessionRequestCoordinator(freshEpoch, mockAuthService),
      );
      await pumpUntilInitialized(restored);

      expect(restored.isAuthenticated, isTrue);
      final token = freshEpoch.capture();
      expect(token, isNotNull);
      expect(token!.userId, 42);
      expect(
        token.generation,
        1,
        reason: 'exactly one activate() call on a fresh epoch',
      );
    });

    test(
      'a stored session with isAuthenticated() == true but a missing user '
      'ID is treated as not authenticated and never activates the epoch',
      () async {
        final freshEpoch = UserSessionEpoch();
        when(mockAuthService.isAuthenticated()).thenAnswer((_) async => true);
        when(mockAuthService.getUserId()).thenAnswer((_) async => null);
        when(mockAuthService.getUserName()).thenAnswer((_) async => null);
        when(mockAuthService.getUserEmail()).thenAnswer((_) async => null);

        final broken = AuthProvider(
          mockAuthRepository,
          mockAuthService,
          mockApiService,
          freshEpoch,
          SessionRequestCoordinator(freshEpoch, mockAuthService),
        );
        await pumpUntilInitialized(broken);

        expect(broken.isAuthenticated, isFalse);
        expect(freshEpoch.capture(), isNull);
      },
    );

    test('login() activates the epoch exactly once with the response '
        'user ID on success, and never on failure', () async {
      when(
        mockAuthRepository.login(any),
      ).thenThrow(Exception('bad credentials'));
      authProvider.updateEmail('test@example.com');
      authProvider.updatePassword('password123');

      final failed = await authProvider.login();
      expect(failed, isFalse);
      expect(
        sessionEpoch.capture(),
        isNull,
        reason: 'a failed login must never activate the epoch',
      );

      when(mockAuthRepository.login(any)).thenAnswer(
        (_) async => AuthResponse(
          token: 'tok',
          userId: 9,
          name: 'Test User',
          email: 'test@example.com',
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

      final ok = await authProvider.login();
      expect(ok, isTrue);
      final token = sessionEpoch.capture();
      expect(token, isNotNull);
      expect(token!.userId, 9);
    });

    test('signup() activates the epoch exactly once with the response '
        'user ID on success', () async {
      when(mockAuthRepository.signup(any)).thenAnswer(
        (_) async => AuthResponse(
          token: 'tok',
          userId: 3,
          name: 'New User',
          email: 'new@example.com',
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

      authProvider.setSignupName('New User');
      authProvider.setSignupUsername('newuser');
      authProvider.setSignupEmail('new@example.com');
      authProvider.setSignupPassword('password123');
      authProvider.setSignupConfirmPassword('password123');

      final ok = await authProvider.signup();
      expect(ok, isTrue);
      final token = sessionEpoch.capture();
      expect(token, isNotNull);
      expect(token!.userId, 3);
    });

    test(
      'manual logout invalidates the epoch synchronously, on a bare '
      'AuthProvider with no onSessionEnding/onLoggedOut wired at all',
      () async {
        when(mockAuthRepository.login(any)).thenAnswer(
          (_) async => AuthResponse(
            token: 'tok',
            userId: 1,
            name: 'Test User',
            email: 'test@example.com',
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
        when(
          mockAuthService.clearSessionCredentials(),
        ).thenAnswer((_) async {});

        authProvider.updateEmail('test@example.com');
        authProvider.updatePassword('password123');
        await authProvider.login();
        expect(sessionEpoch.capture(), isNotNull);

        // authProvider.onSessionEnding / onLoggedOut are never set in this
        // test - proving invalidate() does not depend on that wiring.
        await authProvider.logout();

        expect(sessionEpoch.capture(), isNull);
      },
    );

    test('repeated sequential logout calls are safe: the epoch stays '
        'invalidated and no error is thrown', () async {
      when(mockAuthRepository.login(any)).thenAnswer(
        (_) async => AuthResponse(
          token: 'tok',
          userId: 1,
          name: 'Test User',
          email: 'test@example.com',
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
      when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {});

      authProvider.updateEmail('test@example.com');
      authProvider.updatePassword('password123');
      await authProvider.login();

      await authProvider.logout();
      expect(sessionEpoch.capture(), isNull);

      await authProvider.logout();
      expect(sessionEpoch.capture(), isNull);
    });

    test('the generation strictly increases and old tokens never become '
        'current again across a full logout -> login cycle', () async {
      when(mockAuthRepository.login(any)).thenAnswer(
        (_) async => AuthResponse(
          token: 'tok',
          userId: 1,
          name: 'Test User',
          email: 'test@example.com',
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
      when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {});

      authProvider.updateEmail('test@example.com');
      authProvider.updatePassword('password123');

      await authProvider.login();
      final firstToken = sessionEpoch.capture()!;

      await authProvider.logout();
      expect(sessionEpoch.isCurrent(firstToken), isFalse);

      // logout() resets both the email and password fields, so they must
      // be re-entered before logging back in.
      authProvider.updateEmail('test@example.com');
      authProvider.updatePassword('password123');
      await authProvider.login();
      final secondToken = sessionEpoch.capture()!;

      expect(secondToken.generation, greaterThan(firstToken.generation));
      expect(
        sessionEpoch.isCurrent(firstToken),
        isFalse,
        reason:
            'a token from the first login must never become current '
            'again',
      );
    });

    test('a forced logout from a 401 invalidates the epoch at the same point '
        'as a manual logout', () async {
      final coordinationEpoch = UserSessionEpoch();
      final apiService = ApiService(mockAuthService, coordinationEpoch);
      final forced = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        coordinationEpoch,
        SessionRequestCoordinator(coordinationEpoch, mockAuthService),
      );

      when(mockAuthRepository.login(any)).thenAnswer(
        (_) async => AuthResponse(
          token: 'tok',
          userId: 1,
          name: 'Test User',
          email: 'test@example.com',
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
      when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {});

      forced.updateEmail('test@example.com');
      forced.updatePassword('password123');
      await forced.login();
      expect(coordinationEpoch.capture(), isNotNull);

      // Simulate the API interceptor detecting a 401. _handleSessionExpired
      // fires an unawaited forced-expiration pass, so poll until it
      // settles. Epoch invalidation itself is synchronous (happens before
      // this call even returns), but waiting for the full pass to settle
      // keeps this test symmetric with its manual-logout sibling.
      apiService.onUnauthorized?.call();
      while (forced.isExpiringSession) {
        await Future.delayed(Duration.zero);
      }

      expect(coordinationEpoch.capture(), isNull);
    });
  });

  // -------------------------------------------------------------------
  // Logout PR C: cancel the active session-bound HTTP request generation
  // during logout, immediately after epoch invalidation (SessionRequestCoordinator
  // and its capture/cancel primitives already exist from PRs A/B - this PR
  // only wires AuthProvider's logout pass to call
  // SessionRequestCoordinator.cancelCurrentGeneration()).
  // -------------------------------------------------------------------
  group('AuthProvider - Logout cancels session-bound requests (PR C)', () {
    late ApiService apiService;
    late SessionRequestCoordinator realCoordinator;
    late MockSessionRequestCoordinator mockCoordinator;
    late List<String> calls;

    Future<void> authenticate(
      AuthProvider provider, {
      String email = 'test@example.com',
      int userId = 1,
      String token = 'tok',
    }) async {
      when(mockAuthRepository.login(any)).thenAnswer(
        (_) async => AuthResponse(
          token: token,
          userId: userId,
          name: 'Test User',
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
      provider.updateEmail(email);
      provider.updatePassword('password123');
      final ok = await provider.login();
      expect(ok, isTrue, reason: 'test setup: login must succeed');
    }

    setUp(() {
      sessionEpoch = UserSessionEpoch();
      apiService = ApiService(mockAuthService, sessionEpoch);
      realCoordinator = SessionRequestCoordinator(
        sessionEpoch,
        mockAuthService,
      );
      mockCoordinator = MockSessionRequestCoordinator();
      // MockSessionRequestCoordinator throws on any unstubbed call
      // (throwOnMissingStub), so give the void cancelCurrentGeneration() a
      // default no-op stub here - tests that specifically want it to throw
      // (see the failure-resilience test below) override this with their
      // own when(...).thenThrow(...) afterward.
      when(mockCoordinator.cancelCurrentGeneration()).thenReturn(null);
      calls = [];

      when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {
        calls.add('clearSessionCredentials');
      });
    });

    test(
      'epoch invalidation happens before cancellation is attempted',
      () async {
        bool? epochAlreadyInvalidWhenCancelled;
        when(mockCoordinator.cancelCurrentGeneration()).thenAnswer((_) {
          epochAlreadyInvalidWhenCancelled = sessionEpoch.capture() == null;
        });
        final provider = AuthProvider(
          mockAuthRepository,
          mockAuthService,
          apiService,
          sessionEpoch,
          mockCoordinator,
        );
        await authenticate(provider);

        await provider.logout();

        expect(epochAlreadyInvalidWhenCancelled, isTrue);
      },
    );

    test('manual logout attempts cancellation exactly once', () async {
      final provider = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        sessionEpoch,
        mockCoordinator,
      );
      await authenticate(provider);

      await provider.logout();

      verify(mockCoordinator.cancelCurrentGeneration()).called(1);
    });

    test('forced 401 logout attempts cancellation exactly once', () async {
      final provider = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        sessionEpoch,
        mockCoordinator,
      );
      await authenticate(provider);

      apiService.onUnauthorized?.call();
      while (provider.isExpiringSession) {
        await Future.delayed(Duration.zero);
      }

      verify(mockCoordinator.cancelCurrentGeneration()).called(1);
    });

    test('concurrent manual logout + manual logout collapses into one '
        'cancellation attempt', () async {
      final provider = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        sessionEpoch,
        mockCoordinator,
      );
      await authenticate(provider);

      final first = provider.logout();
      final second = provider.logout();
      await Future.wait([first, second]);

      verify(mockCoordinator.cancelCurrentGeneration()).called(1);
    });

    test('concurrent manual logout + forced 401 share ONE termination pass, '
        'so cancellation is attempted exactly once - the forced-401 trigger '
        'joins the already-running manual-logout pass rather than starting '
        'its own', () async {
      final provider = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        sessionEpoch,
        mockCoordinator,
      );
      await authenticate(provider);

      final manualLogout = provider.logout();
      apiService.onUnauthorized?.call();
      await manualLogout;
      while (provider.isTerminating) {
        await Future.delayed(Duration.zero);
      }

      verify(mockCoordinator.cancelCurrentGeneration()).called(1);
    });

    test('concurrent forced 401 + forced 401 collapses into one cancellation '
        'attempt', () async {
      final provider = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        sessionEpoch,
        mockCoordinator,
      );
      await authenticate(provider);

      final gate = Completer<void>();
      provider.onSessionEnding = () async {
        await gate.future;
      };

      // Both forced triggers fire before either can complete - the
      // second must find _logoutInFlight already set and await the same
      // pass rather than starting a second one.
      apiService.onUnauthorized?.call();
      apiService.onUnauthorized?.call();

      gate.complete();
      await pumpEventQueue();
      while (provider.isExpiringSession) {
        await Future.delayed(Duration.zero);
      }

      verify(mockCoordinator.cancelCurrentGeneration()).called(1);
    });

    test('_logoutInFlight resets so a later session logout performs a fresh '
        'cancellation attempt', () async {
      final provider = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        sessionEpoch,
        mockCoordinator,
      );
      await authenticate(provider);

      await provider.logout();
      verify(mockCoordinator.cancelCurrentGeneration()).called(1);

      await authenticate(provider, email: 'second@example.com', userId: 2);
      await provider.logout();
      verify(mockCoordinator.cancelCurrentGeneration()).called(1);
    });

    test(
      'cancellation throwing does not prevent SessionCleanupCoordinator '
      'execution, credential clearing, reaching the unauthenticated '
      'state, navigation exactly once, or normal Future completion',
      () async {
        when(
          mockCoordinator.cancelCurrentGeneration(),
        ).thenThrow(StateError('cancellation machinery boom'));
        final provider = AuthProvider(
          mockAuthRepository,
          mockAuthService,
          apiService,
          sessionEpoch,
          mockCoordinator,
        );
        await authenticate(provider);

        var sessionEndingCalls = 0;
        provider.onSessionEnding = () async {
          sessionEndingCalls++;
        };
        var loggedOutCalls = 0;
        provider.onLoggedOut = () => loggedOutCalls++;

        await expectLater(provider.logout(), completes);

        expect(
          sessionEndingCalls,
          1,
          reason: 'SessionCleanupCoordinator must still run',
        );
        expect(calls, contains('clearSessionCredentials'));
        expect(provider.isAuthenticated, isFalse);
        expect(loggedOutCalls, 1);
      },
    );

    test('a real session-bound ApiService request held by a Completer-backed '
        'adapter is cancelled with RequestCancelledException when logout '
        'begins, triggers no unauthorized/logout loop, and a later session '
        'captures a fresh, unaffected scope', () async {
      final adapter = _FakeHttpClientAdapter();
      apiService.testHttpClientAdapter = adapter;
      final provider = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        sessionEpoch,
        realCoordinator,
      );

      var unauthorizedCalls = 0;
      apiService.onUnauthorized = () => unauthorizedCalls++;
      var loggedOutCalls = 0;
      provider.onLoggedOut = () => loggedOutCalls++;

      // --- User A captures a session-bound context and starts a
      // request that never completes on its own. ---
      await authenticate(provider, email: 'a@example.com', userId: 1);
      when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-a');
      final contextA = await realCoordinator.captureContext();
      expect(contextA, isNotNull);

      adapter.holdForever = true;
      final requestA = apiService.get<Map<String, dynamic>>(
        '/nutrition',
        sessionContext: contextA,
      );

      // Logging out cancels A's in-flight request as an early step of
      // the same pass.
      await provider.logout();

      await expectLater(requestA, throwsA(isA<RequestCancelledException>()));
      expect(contextA!.cancelToken.isCancelled, isTrue);
      expect(
        unauthorizedCalls,
        0,
        reason:
            'a cancelled request must never be mistaken for a 401 and '
            'trigger another logout pass',
      );
      expect(loggedOutCalls, 1, reason: 'navigation happens exactly once');

      // --- User B logs in afterward and captures a fresh scope. ---
      adapter.holdForever = false;
      await authenticate(provider, email: 'b@example.com', userId: 2);
      when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-b');
      final contextB = await realCoordinator.captureContext();
      expect(contextB, isNotNull);
      expect(
        contextB!.cancelToken.isCancelled,
        isFalse,
        reason: "A's cancelled scope must never carry over to B",
      );
      expect(identical(contextA.cancelToken, contextB.cancelToken), isFalse);

      final resultB = await apiService.get<Map<String, dynamic>>(
        '/nutrition',
        sessionContext: contextB,
      );
      expect(resultB, isA<Map<String, dynamic>>());

      // A's stale scope can never reach into B's: cancelling it again
      // (a no-op on an already-cancelled token) leaves B untouched.
      contextA.cancelToken.cancel();
      expect(contextB.cancelToken.isCancelled, isFalse);
    });
  });

  group('AuthProvider - Username identity', () {
    AuthResponse response({String username = 'bob01'}) => AuthResponse(
      token: 'jwt',
      userId: 7,
      name: 'Bob Roberts',
      username: username,
      email: 'bob@example.com',
    );

    setUp(() {
      when(
        mockAuthService.saveToken(
          token: anyNamed('token'),
          userId: anyNamed('userId'),
          name: anyNamed('name'),
          email: anyNamed('email'),
        ),
      ).thenAnswer((_) async {});
    });

    test('login() persists the auth-response username and exposes it via '
        'currentUsername (never the email)', () async {
      when(mockAuthRepository.login(any)).thenAnswer((_) async => response());
      authProvider.updateEmail('bob@example.com');
      authProvider.updatePassword('secret12');

      final ok = await authProvider.login();

      expect(ok, isTrue);
      expect(authProvider.currentUsername, 'bob01');
      expect(authProvider.currentUserName, 'Bob Roberts');
      verify(mockAuthService.saveUsername('bob01')).called(1);
    });

    test('signup() persists the auth-response username', () async {
      when(mockAuthRepository.signup(any)).thenAnswer((_) async => response());
      authProvider.setSignupName('Bob Roberts');
      authProvider.setSignupUsername('bob01');
      authProvider.setSignupEmail('bob@example.com');
      authProvider.setSignupPassword('secret12');
      authProvider.setSignupConfirmPassword('secret12');

      final ok = await authProvider.signup();

      expect(ok, isTrue);
      expect(authProvider.currentUsername, 'bob01');
      verify(mockAuthService.saveUsername('bob01')).called(1);
    });

    test('a session restored at startup rehydrates currentUsername from '
        'secure storage', () async {
      when(mockAuthService.isAuthenticated()).thenAnswer((_) async => true);
      when(mockAuthService.getUserId()).thenAnswer((_) async => 7);
      when(
        mockAuthService.getUserName(),
      ).thenAnswer((_) async => 'Bob Roberts');
      when(mockAuthService.getUsername()).thenAnswer((_) async => 'bob01');
      when(
        mockAuthService.getUserEmail(),
      ).thenAnswer((_) async => 'bob@example.com');

      final restored = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        mockApiService,
        sessionEpoch,
        mockSessionRequestCoordinator,
      );
      await pumpEventQueue();

      expect(restored.currentUsername, 'bob01');
    });

    test('explicit logout clears currentUsername and routes credential '
        'wiping through clearSessionCredentials (which now includes the '
        'username key)', () async {
      when(mockAuthRepository.login(any)).thenAnswer((_) async => response());
      when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {});
      authProvider.updateEmail('bob@example.com');
      authProvider.updatePassword('secret12');
      await authProvider.login();
      expect(authProvider.currentUsername, 'bob01');

      await authProvider.logout();

      expect(authProvider.currentUsername, isNull);
      verify(mockAuthService.clearSessionCredentials()).called(1);
    });

    test('an empty username in the auth response yields an empty '
        'currentUsername (UI hides the @handle), never a fallback', () async {
      when(
        mockAuthRepository.login(any),
      ).thenAnswer((_) async => response(username: ''));
      authProvider.updateEmail('bob@example.com');
      authProvider.updatePassword('secret12');

      await authProvider.login();

      expect(authProvider.currentUsername, '');
    });

    group('applyUpdatedUsername (post-profile-edit reconciliation)', () {
      Future<void> loginAs(String username) async {
        when(
          mockAuthRepository.login(any),
        ).thenAnswer((_) async => response(username: username));
        authProvider.updateEmail('bob@example.com');
        authProvider.updatePassword('secret12');
        await authProvider.login();
      }

      test('updates currentUsername, notifies, and persists to secure '
          'storage', () async {
        await loginAs('bob01');
        final token = authProvider.captureSessionToken();
        var notified = 0;
        authProvider.addListener(() => notified++);

        authProvider.applyUpdatedUsername('bob_v2', token);

        expect(authProvider.currentUsername, 'bob_v2');
        expect(notified, 1);
        await pumpEventQueue();
        verify(mockAuthService.saveUsername('bob_v2')).called(1);
      });

      test('is a no-op when the value is unchanged', () async {
        await loginAs('bob01');
        final token = authProvider.captureSessionToken();
        var notified = 0;
        authProvider.addListener(() => notified++);

        authProvider.applyUpdatedUsername('bob01', token);

        expect(notified, 0);
      });

      test('is a no-op when the captured session is no longer current '
          '(a different account took over mid-save)', () async {
        await loginAs('bob01');
        final staleToken = authProvider.captureSessionToken();

        // Another session supersedes the one the token was captured under.
        sessionEpoch.activate(999);

        authProvider.applyUpdatedUsername('bob_v2', staleToken);

        expect(authProvider.currentUsername, 'bob01');
        verifyNever(mockAuthService.saveUsername('bob_v2'));
      });

      test('is a no-op when not authenticated (never resurrects identity for '
          'a logged-out provider)', () async {
        expect(authProvider.isAuthenticated, isFalse);

        authProvider.applyUpdatedUsername(
          'someone',
          authProvider.captureSessionToken(),
        );

        expect(authProvider.currentUsername, isNull);
        verifyNever(mockAuthService.saveUsername(any));
      });
    });
  });
}
