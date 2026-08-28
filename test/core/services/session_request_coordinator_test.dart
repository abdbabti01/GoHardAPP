import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

@GenerateMocks([AuthService])
import 'session_request_coordinator_test.mocks.dart';

/// A [CancelToken] whose [cancel] always throws, so tests can prove
/// [SessionRequestCoordinator.cancelCurrentGeneration] swallows a failure
/// from the underlying cancellation machinery rather than propagating it -
/// something the real [CancelToken] never does on its own (double-cancel is
/// a safe no-op), so this is the only way to exercise that guard.
class _ThrowingCancelToken extends CancelToken {
  @override
  void cancel([Object? reason]) {
    throw StateError('cancellation machinery failed');
  }
}

void main() {
  late UserSessionEpoch epoch;
  late MockAuthService authService;
  late SessionRequestCoordinator coordinator;

  setUp(() {
    epoch = UserSessionEpoch();
    authService = MockAuthService();
    coordinator = SessionRequestCoordinator(epoch, authService);
  });

  group('captureContext', () {
    test('returns null when logged out', () async {
      final context = await coordinator.captureContext();
      expect(context, isNull);
      verifyNever(authService.getToken());
    });

    test('captures the JWT exactly once', () async {
      epoch.activate(1);
      when(authService.getToken()).thenAnswer((_) async => 'jwt-a');

      final context = await coordinator.captureContext();

      expect(context, isNotNull);
      verify(authService.getToken()).called(1);
    });

    test('returns null if the JWT is null', () async {
      epoch.activate(1);
      when(authService.getToken()).thenAnswer((_) async => null);

      expect(await coordinator.captureContext(), isNull);
    });

    test('returns null if the JWT is empty', () async {
      epoch.activate(1);
      when(authService.getToken()).thenAnswer((_) async => '');

      expect(await coordinator.captureContext(), isNull);
    });

    test('returns null if the session changed while the JWT read was in '
        'flight', () async {
      epoch.activate(1);
      final tokenCompleter = Completer<String?>();
      when(authService.getToken()).thenAnswer((_) => tokenCompleter.future);

      final future = coordinator.captureContext();
      epoch.invalidate();
      tokenCompleter.complete('jwt-a');

      expect(await future, isNull);
    });

    test('a context captured for User A is rejected once User A logs out '
        'and back in - the generation differs even for the same user '
        '(test 7)', () async {
      epoch.activate(1);
      when(authService.getToken()).thenAnswer((_) async => 'jwt-a-1');
      final firstLogin = await coordinator.captureContext();
      expect(firstLogin, isNotNull);

      epoch.invalidate();
      epoch.activate(1);

      expect(epoch.isCurrent(firstLogin!.epochToken), isFalse);
    });

    test('a context captured for User A is rejected once User B logs in '
        '(test 8)', () async {
      epoch.activate(1);
      when(authService.getToken()).thenAnswer((_) async => 'jwt-a');
      final contextA = await coordinator.captureContext();
      expect(contextA, isNotNull);

      epoch.activate(2);

      expect(epoch.isCurrent(contextA!.epochToken), isFalse);
    });

    test(
      'the CancelToken for a generation is created BEFORE the JWT read '
      'is awaited - cancelling the generation while getToken() is still '
      'pending still cancels the SAME token the eventually-returned '
      'context carries (mutation: creating the token only after the '
      'await would leave this cancellation with nothing to cancel)',
      () async {
        epoch.activate(1);
        final tokenCompleter = Completer<String?>();
        when(authService.getToken()).thenAnswer((_) => tokenCompleter.future);

        final future = coordinator.captureContext();

        // Nothing has awaited yet from this test's perspective, but
        // captureContext() has already suspended at `await getToken()` -
        // everything before that point (capture() + minting the CancelToken)
        // already ran synchronously. Cancelling now must find a real token.
        coordinator.cancelCurrentGeneration();

        tokenCompleter.complete('jwt-a');
        final context = await future;

        expect(context, isNotNull);
        expect(
          context!.cancelToken.isCancelled,
          isTrue,
          reason:
              'the token minted before the await and the token returned in '
              'the context must be the same object',
        );
      },
    );
  });

  group('cancelCurrentGeneration', () {
    test('is a safe no-op when nothing has been captured yet', () {
      expect(() => coordinator.cancelCurrentGeneration(), returnsNormally);
    });

    test('cancels the CancelToken carried by a captured context', () async {
      epoch.activate(1);
      when(authService.getToken()).thenAnswer((_) async => 'jwt-a');
      final context = await coordinator.captureContext();

      coordinator.cancelCurrentGeneration();

      expect(context!.cancelToken.isCancelled, isTrue);
    });

    test(
      'cancelling generation A does not cancel generation B (test 14)',
      () async {
        epoch.activate(1);
        when(authService.getToken()).thenAnswer((_) async => 'jwt-a');
        final contextA = await coordinator.captureContext();

        coordinator.cancelCurrentGeneration();
        expect(contextA!.cancelToken.isCancelled, isTrue);

        epoch.activate(2);
        when(authService.getToken()).thenAnswer((_) async => 'jwt-b');
        final contextB = await coordinator.captureContext();

        expect(
          contextB!.cancelToken.isCancelled,
          isFalse,
          reason: "B's token must be a fresh, uncancelled object",
        );
        expect(identical(contextA.cancelToken, contextB.cancelToken), isFalse);
      },
    );

    test(
      'a cancelled generation never reuses its CancelToken - the next '
      'capture for the SAME still-active generation gets the same live '
      'token, and a NEW generation always gets a distinct one (test 15)',
      () async {
        epoch.activate(1);
        when(authService.getToken()).thenAnswer((_) async => 'jwt-a-1');
        final first = await coordinator.captureContext();

        // A second capture for the SAME generation reuses the same
        // (still-uncancelled) token - this is expected and correct; the
        // "never reuse a CANCELLED token" guarantee only applies once that
        // generation has actually ended.
        when(authService.getToken()).thenAnswer((_) async => 'jwt-a-2');
        final second = await coordinator.captureContext();
        expect(identical(first!.cancelToken, second!.cancelToken), isTrue);

        coordinator.cancelCurrentGeneration();
        expect(first.cancelToken.isCancelled, isTrue);

        epoch.invalidate();
        epoch.activate(1); // same user, new generation
        when(authService.getToken()).thenAnswer((_) async => 'jwt-a-3');
        final third = await coordinator.captureContext();

        expect(
          identical(first.cancelToken, third!.cancelToken),
          isFalse,
          reason: 'a same-user relogin must never reuse a cancelled token',
        );
        expect(third.cancelToken.isCancelled, isFalse);
      },
    );

    test('never throws even when the cancellation machinery itself fails '
        '(test 16)', () async {
      coordinator.cancelTokenFactoryForTesting = () => _ThrowingCancelToken();
      epoch.activate(1);
      when(authService.getToken()).thenAnswer((_) async => 'jwt-a');
      await coordinator.captureContext();

      expect(() => coordinator.cancelCurrentGeneration(), returnsNormally);
    });
  });
}
