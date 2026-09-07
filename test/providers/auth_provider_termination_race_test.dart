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
/// Neither kind ever touches durable local (Isar) data - explicit logout
/// and forced expiration are BOTH non-destructive; see
/// `AuthProvider._runTerminationPass`'s class doc comment and
/// `auth_provider_non_destructive_logout_test.dart` for the real-Isar
/// behavioral proof. This file focuses on the concurrency/arbitration
/// properties only.
///
/// Every ordering below is forced deterministically via a held
/// `Completer` inside `onSessionEnding` - the pass's step 1, reached AFTER
/// invalidate()/field-reset/cancellation (step 0) but BEFORE
/// FCM-unregister (step 1b - deliberately placed AFTER this await, not
/// before it, so a late-joining explicit logout that upgrades `pass.kind`
/// while suspended here still reaches it - see
/// `auth_provider_composition_proof_test.dart`'s ordering-pinning test),
/// credential clearing, and background-service clearing, and the terminal
/// step. No `Future.delayed`/`pumpEventQueue`-based timing is used to
/// force an interleaving - only to let an UNHELD pass run to completion
/// afterward.
void main() {
  late MockAuthRepository mockAuthRepository;
  late MockAuthService mockAuthService;
  late UserSessionEpoch sessionEpoch;
  late ApiService apiService;
  late SessionRequestCoordinator sessionRequestCoordinator;
  late AuthProvider authProvider;
  late List<String> calls;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockAuthService = MockAuthService();
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

    authProvider = AuthProvider(
      mockAuthRepository,
      mockAuthService,
      apiService,
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
        'drops - exactly one onSessionEnding, one navigation, ending with '
        'the explicit-logout state', () async {
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
      expect(calls.where((c) => c == 'clearSessionCredentials').length, 1);
      expect(loggedOutCalls, 1);
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.errorMessage, '');
    });

    test('forced 401 starts first, then manual logout joins and UPGRADES '
        'the pass - exactly one onSessionEnding, even though the pass '
        'started as forced-expiration-only', () async {
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

    // clearAll() reachability (never, for either kind, under any race
    // ordering) is proven with a REAL Isar-backed AuthProvider in
    // `auth_provider_non_destructive_logout_test.dart` - AuthProvider no
    // longer holds any `LocalDatabaseService` reference at all after this
    // change (see its constructor), so a mock-based `verifyNever` here
    // would be vacuously true regardless of production behavior and is
    // deliberately not duplicated in this concurrency-focused file.
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

    test('A held, B activated, B logout held, A released and settled '
        'FIRST while B remains suspended, THEN a third logout() call '
        'joins B\'s still-in-flight pass (not A\'s already-settled one) '
        '- B then completes credential cleanup/notification/navigation '
        'exactly once and A\'s settled pass causes no additional effect '
        'or message overwrite', () async {
      // 1. Hold A's termination pass.
      await authenticate(userId: 1, email: 'a@example.com', token: 'tok-a');
      final aGate = Completer<void>();
      final bGate = Completer<void>();
      var onSessionEndingCalls = 0;
      authProvider.onSessionEnding = () async {
        onSessionEndingCalls++;
        if (onSessionEndingCalls == 1) {
          await aGate.future;
        } else if (onSessionEndingCalls == 2) {
          await bGate.future;
        }
      };
      var navigateCalls = 0;
      authProvider.onLoggedOut = () => navigateCalls++;

      apiService.onUnauthorized?.call();
      await pumpEventQueue();
      expect(authProvider.isExpiringSession, isTrue);
      expect(onSessionEndingCalls, 1);

      // 2. Activate B.
      await authenticate(userId: 2, email: 'b@example.com', token: 'tok-b');

      // Attached only now - login() itself calls notifyListeners() for
      // its own loading/success state changes, which are irrelevant to
      // the termination pass's exactly-once guarantee this test is
      // proving.
      var notifyCalls = 0;
      authProvider.addListener(() => notifyCalls++);

      // 3. Start B logout and hold B's termination pass.
      final bLogout1 = authProvider.logout();
      await pumpEventQueue();
      expect(onSessionEndingCalls, 2);
      expect(authProvider.isTerminating, isTrue);

      // 4. Release and await A while B remains suspended. A's own
      // `whenComplete` runs as part of this - it must find
      // `_activeTermination` pointing at B's pass (not itself, since
      // B's own fresh pass overwrote that field in step 3) and
      // correctly no-op via the `identical()` guard, never clearing
      // B's active reference.
      aGate.complete();
      await pumpEventQueue();
      expect(
        authProvider.isTerminating,
        isTrue,
        reason:
            "B's own pass must still be the active one - A's settling "
            'must not have cleared it',
      );

      // 5. Call logout again - a THIRD call, made AFTER A has already
      // fully settled, while B is STILL suspended.
      final bLogout2 = authProvider.logout();

      // 6. Prove the call joins B's existing Future.
      expect(
        identical(bLogout1, bLogout2),
        isTrue,
        reason:
            "the third call must join B's still-in-flight pass by "
            "returning its exact Future - proving A's earlier "
            'settling left _activeTermination correctly pointing at '
            "B's pass, not cleared or corrupted",
      );
      expect(
        onSessionEndingCalls,
        2,
        reason:
            'joining must never re-invoke onSessionEnding a third '
            'time',
      );

      // 7. Release B.
      bGate.complete();
      await bLogout1;
      await bLogout2;
      await waitForSettle();

      // 8. Prove B performs credential cleanup, terminal
      // notification, listener notification, and navigation exactly
      // once. 9. These same TOTAL counts - taken after BOTH A's and
      // B's passes have fully settled - also prove stale A caused no
      // ADDITIONAL cleanup, state change, or navigation: had A's
      // settled pass incorrectly re-run any of these, the count
      // would be 2, not 1.
      expect(calls.where((c) => c == 'clearSessionCredentials').length, 1);
      expect(navigateCalls, 1);
      expect(notifyCalls, 1);
      expect(authProvider.isAuthenticated, isFalse);
      expect(
        authProvider.errorMessage,
        '',
        reason:
            "B's own explicit-logout message must not be overwritten "
            "by A's stale forced-expiration pass settling after it",
      );
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
