import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/auth_response.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/providers/auth_provider.dart';

// Reuses the Mockito mocks generated for auth_provider_test.dart (same
// AuthRepository/AuthService/LocalDatabaseService/SessionRequestCoordinator
// surface, unchanged by this PR) - no new build_runner output.
import 'auth_provider_test.mocks.dart';

/// Proves the BLOCKER-2 fix: explicit logout and forced expiration share
/// ONE generation-owned termination arbiter for their shared terminal
/// effects (auth-state reset, notifyListeners, final message selection,
/// onLoggedOut navigation), so a race between them can never produce a
/// double navigation, a clobbered message, or a skipped destructive
/// cleanup - while remaining two distinct, independently-triggerable named
/// operations (`logout()` vs the 401-driven forced-expiration path), and
/// while never letting an OLD, still-finishing pass disturb a session that
/// has since superseded it (a different user, or the same user re
/// -authenticating).
///
/// Every ordering below is forced deterministically via a held
/// `Completer` inside `onSessionEnding` - the pass's step 1, reached AFTER
/// invalidate()/field-reset/cancellation (step 0) but BEFORE
/// FCM-unregister (step 1b - deliberately placed AFTER this await, not
/// before it, so a late-joining explicit logout that upgrades `pass.kind`
/// while suspended here still reaches it - see
/// `auth_provider_composition_proof_test.dart`'s ordering-pinning test),
/// credential clearing, background-service clearing, Isar clearing, and
/// the terminal step. No `Future.delayed`/`pumpEventQueue`-based timing is
/// used to force an interleaving - only to let an UNHELD pass run to
/// completion afterward.
void main() {
  late MockAuthRepository mockAuthRepository;
  late MockAuthService mockAuthService;
  late MockLocalDatabaseService mockLocalDb;
  late UserSessionEpoch sessionEpoch;
  late ApiService apiService;
  late SessionRequestCoordinator sessionRequestCoordinator;
  late AuthProvider authProvider;
  late List<String> calls;

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
    calls = [];

    when(mockAuthService.isAuthenticated()).thenAnswer((_) async => false);
    when(mockAuthService.getUserId()).thenAnswer((_) async => null);
    when(mockAuthService.getUserName()).thenAnswer((_) async => null);
    when(mockAuthService.getUserEmail()).thenAnswer((_) async => null);
    when(mockAuthService.clearSessionCredentials()).thenAnswer((_) async {
      calls.add('clearSessionCredentials');
    });
    when(mockLocalDb.clearAll()).thenAnswer((_) async {
      calls.add('clearAll');
    });

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
          AuthResponse(token: token, userId: userId, name: 'U', email: email),
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

  Future<void> waitForSettle() async {
    while (authProvider.isTerminating) {
      await Future.delayed(Duration.zero);
    }
  }

  group('race orderings - exact-once shared terminal effects', () {
    test('manual logout starts, then forced 401 arrives and harmlessly '
        'drops - exactly one onSessionEnding, one clearAll, one navigation, '
        'ending with the explicit-logout state', () async {
      await authenticate();
      var sessionEndingCalls = 0;
      final gate = Completer<void>();
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
        await gate.future;
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      final manualLogout = authProvider.logout();
      await pumpEventQueue();
      expect(authProvider.isTerminating, isTrue);

      // The 401 arrives while logout's pass is mid-flight, paused inside
      // onSessionEnding.
      apiService.onUnauthorized?.call();
      await pumpEventQueue();

      gate.complete();
      await manualLogout;
      await waitForSettle();

      expect(sessionEndingCalls, 1);
      expect(calls.where((c) => c == 'clearAll').length, 1);
      expect(calls.where((c) => c == 'clearSessionCredentials').length, 1);
      expect(loggedOutCalls, 1);
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.errorMessage, '');
    });

    test('forced 401 starts first, then manual logout joins and UPGRADES '
        'the pass - exactly one onSessionEnding, and the destructive Isar '
        'clear still runs exactly once even though the pass started as '
        'forced-expiration-only', () async {
      await authenticate();
      var sessionEndingCalls = 0;
      final gate = Completer<void>();
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
        await gate.future;
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      apiService.onUnauthorized?.call();
      await pumpEventQueue();
      expect(authProvider.isExpiringSession, isTrue);

      final manualLogout = authProvider.logout();
      await pumpEventQueue();
      expect(
        authProvider.isLoggingOut,
        isTrue,
        reason: 'the join must upgrade the pass\'s kind immediately',
      );

      gate.complete();
      await manualLogout;
      await waitForSettle();

      expect(sessionEndingCalls, 1);
      expect(
        calls.where((c) => c == 'clearAll').length,
        1,
        reason:
            'mutation target 9: explicit logout joining an already-running '
            'forced expiration must still perform its required local '
            'destructive cleanup exactly once',
      );
      expect(loggedOutCalls, 1);
      expect(
        authProvider.errorMessage,
        '',
        reason:
            'mutation target 8: explicit logout wins message precedence '
            'even though forced expiration started the pass first',
      );
    });

    test('both triggers begin in the same synchronous event turn (no await '
        'between them) - still exactly one shared pass', () async {
      await authenticate();
      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      // No await between these two calls - both fire in the same
      // synchronous turn.
      final manualLogout = authProvider.logout();
      apiService.onUnauthorized?.call();

      await manualLogout;
      await waitForSettle();

      expect(sessionEndingCalls, 1);
      expect(loggedOutCalls, 1);
      expect(calls.where((c) => c == 'clearAll').length, 1);
      expect(authProvider.errorMessage, '');
    });

    test('many concurrent 401s plus one manual logout still collapse into '
        'exactly one pass', () async {
      await authenticate();
      var sessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        sessionEndingCalls++;
      };
      var loggedOutCalls = 0;
      authProvider.onLoggedOut = () => loggedOutCalls++;

      apiService.onUnauthorized?.call();
      apiService.onUnauthorized?.call();
      final manualLogout = authProvider.logout();
      apiService.onUnauthorized?.call();
      apiService.onUnauthorized?.call();
      apiService.onUnauthorized?.call();

      await manualLogout;
      await waitForSettle();

      expect(sessionEndingCalls, 1);
      expect(loggedOutCalls, 1);
      expect(calls.where((c) => c == 'clearAll').length, 1);
      expect(
        calls.where((c) => c == 'clearSessionCredentials').length,
        1,
        reason:
            'mutation target: credentials are not cleared twice in a way '
            'that could erase a fresh login\'s freshly-saved credentials',
      );
    });
  });

  group('exact-once counts and precedence, in isolation', () {
    test(
      'onLoggedOut is called exactly once under a manual+forced race',
      () async {
        await authenticate();
        var loggedOutCalls = 0;
        authProvider.onLoggedOut = () => loggedOutCalls++;

        final manualLogout = authProvider.logout();
        apiService.onUnauthorized?.call();
        await manualLogout;
        await waitForSettle();

        expect(loggedOutCalls, 1);
      },
    );

    test('notifyListeners fires exactly once for the shared terminal '
        'transition under a manual+forced race', () async {
      await authenticate();
      var notifyCount = 0;
      authProvider.addListener(() => notifyCount++);

      final manualLogout = authProvider.logout();
      apiService.onUnauthorized?.call();
      await manualLogout;
      await waitForSettle();

      expect(
        notifyCount,
        1,
        reason:
            'exactly one notifyListeners() for the whole shared pass, not '
            'once per participating trigger',
      );
    });

    test(
      'clearAll() occurs exactly once when manual logout participates',
      () async {
        await authenticate();
        final manualLogout = authProvider.logout();
        apiService.onUnauthorized?.call();
        await manualLogout;
        await waitForSettle();

        expect(calls.where((c) => c == 'clearAll').length, 1);
      },
    );

    test('clearAll() occurs zero times for forced expiration alone (no '
        'logout ever participates)', () async {
      await authenticate();
      apiService.onUnauthorized?.call();
      await waitForSettle();

      verifyNever(mockLocalDb.clearAll());
    });

    test('a forced-expiration-only pass never attempts explicit-logout-only '
        'destructive local cleanup', () async {
      await authenticate();
      apiService.onUnauthorized?.call();
      await waitForSettle();

      verifyNever(mockLocalDb.clearAll());
    });
  });

  group('an old, still-finishing pass can never disturb a newer session', () {
    test('a stale forced-expiration pass, suspended in onSessionEnding, '
        'cannot clear credentials once B has logged in - the OLD pass must '
        'observe staleness and skip every remaining step, so B\'s freshly '
        'saved credentials are never touched', () async {
      await authenticate(userId: 1, email: 'a@example.com', token: 'tok-a');
      final gate = Completer<void>();
      authProvider.onSessionEnding = () async {
        await gate.future;
      };

      apiService.onUnauthorized?.call();
      await pumpEventQueue();
      expect(authProvider.isExpiringSession, isTrue);

      // B logs in while A's stale pass is still suspended.
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

      gate.complete();
      await waitForSettle();

      verifyNever(mockAuthService.clearSessionCredentials());
      verifyNever(mockLocalDb.clearAll());
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.currentUserId, 2);
      expect(authProvider.currentUserEmail, 'b@example.com');
    });

    test('a stale forced-expiration pass, suspended in onSessionEnding, '
        'cannot clear credentials once A has RE-authenticated with a fresh '
        'generation (same user, new session)', () async {
      await authenticate(userId: 1, email: 'a@example.com', token: 'tok-a');
      final gate = Completer<void>();
      authProvider.onSessionEnding = () async {
        await gate.future;
      };

      apiService.onUnauthorized?.call();
      await pumpEventQueue();
      expect(authProvider.isExpiringSession, isTrue);

      when(mockAuthRepository.login(any)).thenAnswer(
        (_) async => AuthResponse(
          token: 'tok-a-2',
          userId: 1,
          name: 'A',
          email: 'a@example.com',
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
      authProvider.updateEmail('a@example.com');
      authProvider.updatePassword('password123');
      final reLoginOk = await authProvider.login();
      expect(reLoginOk, isTrue);

      gate.complete();
      await waitForSettle();

      verifyNever(mockAuthService.clearSessionCredentials());
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.currentUserId, 1);
    });
  });

  group('no stale authenticated fields during an abandoned pass', () {
    test('the instant a pass begins (synchronously, before its first '
        'await), isAuthenticated/currentUserId are ALREADY reset - never '
        'observable as still-authenticated alongside an already-invalidated '
        'epoch', () async {
      await authenticate();
      final gate = Completer<void>();
      authProvider.onSessionEnding = () async {
        // By the time this runs, step 0 (invalidate + synchronous field
        // reset) has already completed - this is the assertion point.
        expect(authProvider.isAuthenticated, isFalse);
        expect(authProvider.currentUserId, isNull);
        expect(authProvider.currentUserEmail, isNull);
        await gate.future;
      };

      final pass = authProvider.logout();
      gate.complete();
      await pass;
    });

    test('isAuthenticated is false immediately after apiService.'
        'onUnauthorized?.call() returns, with NO await needed to observe '
        'it - proving the reset is synchronous, not merely eventual', () async {
      await authenticate();

      apiService.onUnauthorized?.call();

      expect(
        authProvider.isAuthenticated,
        isFalse,
        reason:
            'mutation target 13: if the identity reset were moved to '
            'after an await instead of staying synchronous, this '
            'assertion (made with NO await in between) would fail',
      );
    });
  });

  group('composition sanity: message precedence is exactly as specified', () {
    test('explicit logout alone (no forced expiration involved) ends with '
        'the empty logout message, never the expiration message', () async {
      await authenticate();
      await authProvider.logout();

      expect(authProvider.errorMessage, '');
    });

    test('forced expiration alone (no logout involved) ends with the '
        'generic expiration message', () async {
      await authenticate();
      apiService.onUnauthorized?.call();
      await waitForSettle();

      expect(
        authProvider.errorMessage,
        'Your session expired. Sign in again. Your offline changes are safe.',
      );
    });
  });
}
