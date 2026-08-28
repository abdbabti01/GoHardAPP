import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:go_hard_app/providers/auth_provider.dart';
import 'package:go_hard_app/data/repositories/auth_repository.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/auth_response.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';

@GenerateMocks([AuthRepository, AuthService, ApiService, LocalDatabaseService])
import 'auth_provider_test.mocks.dart';

void main() {
  late AuthProvider authProvider;
  late MockAuthRepository mockAuthRepository;
  late MockAuthService mockAuthService;
  late MockApiService mockApiService;
  late MockLocalDatabaseService mockLocalDb;
  // A real UserSessionEpoch instance (not a mock) - it's a plain,
  // dependency-free value service, so tests exercise its actual
  // activate()/invalidate()/capture()/isCurrent() behavior rather than
  // stubbing it.
  late UserSessionEpoch sessionEpoch;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockAuthService = MockAuthService();
    mockApiService = MockApiService();
    mockLocalDb = MockLocalDatabaseService();
    sessionEpoch = UserSessionEpoch();

    // Stub the auth check methods called in constructor
    when(mockAuthService.isAuthenticated()).thenAnswer((_) async => false);
    when(mockAuthService.getUserId()).thenAnswer((_) async => null);
    when(mockAuthService.getUserName()).thenAnswer((_) async => null);
    when(mockAuthService.getUserEmail()).thenAnswer((_) async => null);

    authProvider = AuthProvider(
      mockAuthRepository,
      mockAuthService,
      mockApiService,
      mockLocalDb,
      sessionEpoch,
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
      apiService = ApiService(mockAuthService);
      calls = [];
      sessionEpoch = UserSessionEpoch();

      authProvider = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        mockLocalDb,
        sessionEpoch,
      );

      when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {
        calls.add('clearSessionCredentials');
      });
      when(mockLocalDb.clearAll()).thenAnswer((_) async {
        calls.add('clearAll');
      });
    });

    test(
      'manual logout awaits onSessionEnding before clearing credentials',
      () async {
        authProvider.onSessionEnding = () async {
          calls.add('onSessionEnding');
        };
        authProvider.onLoggedOut = () => calls.add('onLoggedOut');

        await authProvider.logout();

        expect(calls, [
          'onSessionEnding',
          'clearSessionCredentials',
          'clearAll',
          'onLoggedOut',
        ]);
        expect(
          calls.indexOf('onSessionEnding') <
              calls.indexOf('clearSessionCredentials'),
          isTrue,
        );
      },
    );

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
        expect(authProvider.errorMessage, contains('Session expired'));
      },
    );

    test('manual logout and a concurrent forced 401 collapse into one cleanup '
        'pass, one credential/Isar clear, and one navigation call', () async {
      await authenticate();

      var sessionEndingCalls = 0;
      final gate = Completer<void>();
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
        await gate.future;
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      // Fire both triggers before either can complete.
      final manualLogout = authProvider.logout();
      apiService.onUnauthorized?.call();
      await pumpEventQueue();

      expect(
        sessionEndingCalls,
        1,
        reason:
            'a concurrent 401 must await the SAME in-flight logout, not '
            'start a second cleanup pass',
      );
      expect(
        authProvider.isLoggingOut,
        isTrue,
        reason: 'still gated - neither trigger has completed yet',
      );

      gate.complete();
      await manualLogout;
      await pumpEventQueue();

      expect(sessionEndingCalls, 1);
      expect(calls.where((c) => c == 'clearSessionCredentials').length, 1);
      expect(calls.where((c) => c == 'clearAll').length, 1);
      expect(loggedOutCalls, 1);
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

    test('a session-cleanup failure does not block credential/Isar clearing '
        'or navigation', () async {
      authProvider.onSessionEnding = () async {
        throw Exception('coordinator boom');
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      await authProvider.logout();

      expect(calls, contains('clearSessionCredentials'));
      expect(calls, contains('clearAll'));
      expect(authProvider.isAuthenticated, isFalse);
      expect(loggedOutCalls, 1);
    });

    test(
      'clearSessionCredentials throwing does not prevent Isar clearing, '
      'state reset, or navigation, and logout() itself does not throw',
      () async {
        when(
          mockAuthService.clearSessionCredentials(),
        ).thenThrow(Exception('secure storage unavailable'));
        var loggedOutCalls = 0;
        authProvider.onLoggedOut = () => loggedOutCalls++;

        await expectLater(authProvider.logout(), completes);

        expect(
          calls,
          contains('clearAll'),
          reason: 'Isar clearing must still be attempted',
        );
        expect(authProvider.isAuthenticated, isFalse);
        expect(loggedOutCalls, 1);
      },
    );

    test('a real BackgroundService failure (no platform bindings set up in '
        'this test file) does not prevent Isar clearing, state reset, or '
        'navigation', () async {
      // BackgroundService.clearAuthToken() genuinely throws here -
      // SharedPreferences.getInstance() has no platform binding in this
      // test file (no TestWidgetsFlutterBinding.ensureInitialized()).
      // This is a real, naturally-occurring failure, not a simulated
      // one - exactly what proves later steps survive it.
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      await expectLater(authProvider.logout(), completes);

      expect(calls, contains('clearAll'));
      expect(authProvider.isAuthenticated, isFalse);
      expect(loggedOutCalls, 1);
    });

    test('Isar clearAll() throwing does not prevent state reset or '
        'navigation, and logout() itself does not throw', () async {
      when(mockLocalDb.clearAll()).thenThrow(Exception('isar closed'));
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      await expectLater(authProvider.logout(), completes);

      expect(authProvider.isAuthenticated, isFalse);
      expect(loggedOutCalls, 1);
    });

    test('multiple simultaneous failures (coordinator, credentials, Isar) '
        'still result in every step being attempted exactly once, with '
        'state reset and navigation completing', () async {
      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
        throw Exception('coordinator boom');
      };
      when(
        mockAuthService.clearSessionCredentials(),
      ).thenThrow(Exception('secure storage boom'));
      when(mockLocalDb.clearAll()).thenThrow(Exception('isar boom'));
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
    test(
      'manual logout with a throwing onLoggedOut callback completes '
      'without throwing, remains unauthenticated, still performs '
      'credential/Isar cleanup, and attempts the callback exactly once',
      () async {
        var loggedOutCalls = 0;
        authProvider.onLoggedOut = () {
          loggedOutCalls++;
          throw Exception('nav boom');
        };

        await expectLater(authProvider.logout(), completes);

        expect(authProvider.isAuthenticated, isFalse);
        expect(calls, contains('clearSessionCredentials'));
        expect(calls, contains('clearAll'));
        expect(loggedOutCalls, 1);
      },
    );

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
        'onLoggedOut callback, still collapse into one cleanup pass and one '
        'callback attempt, with no uncaught error', () async {
      await authenticate();
      var loggedOutCalls = 0;
      var sessionEndingCalls = 0;
      final gate = Completer<void>();
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
        await gate.future;
      };
      authProvider.onLoggedOut = () {
        loggedOutCalls++;
        throw Exception('nav boom');
      };

      Object? uncaughtError;
      await runZonedGuarded(
        () async {
          final manualLogout = authProvider.logout();
          apiService.onUnauthorized?.call();
          await pumpEventQueue();

          expect(
            sessionEndingCalls,
            1,
            reason: 'a concurrent 401 must await the same in-flight logout',
          );

          gate.complete();
          await manualLogout;
          await pumpEventQueue();
        },
        (error, stackTrace) {
          uncaughtError = error;
        },
      );

      expect(uncaughtError, isNull);
      expect(sessionEndingCalls, 1);
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
        mockLocalDb,
        freshEpoch,
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
          mockLocalDb,
          freshEpoch,
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
      final apiService = ApiService(mockAuthService);
      final coordinationEpoch = UserSessionEpoch();
      final forced = AuthProvider(
        mockAuthRepository,
        mockAuthService,
        apiService,
        mockLocalDb,
        coordinationEpoch,
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
      // fires an unawaited logout pass, so poll until it settles.
      apiService.onUnauthorized?.call();
      while (forced.isLoggingOut) {
        await Future.delayed(Duration.zero);
      }

      expect(coordinationEpoch.capture(), isNull);
    });
  });
}
