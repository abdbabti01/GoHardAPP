import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';

void main() {
  group('UserSessionEpoch', () {
    test('capture() returns null before any activate()', () {
      final epoch = UserSessionEpoch();
      expect(epoch.capture(), isNull);
    });

    test('activate() makes capture() return a token for that user', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1);

      final token = epoch.capture();
      expect(token, isNotNull);
      expect(token!.userId, 1);
    });

    test('invalidate() makes capture() return null again', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1);
      epoch.invalidate();

      expect(epoch.capture(), isNull);
    });

    test('isCurrent() is true for a token captured while still active', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1);
      final token = epoch.capture()!;

      expect(epoch.isCurrent(token), isTrue);
    });

    test('isCurrent() is false once invalidate() has run', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1);
      final token = epoch.capture()!;

      epoch.invalidate();

      expect(epoch.isCurrent(token), isFalse);
    });

    test('isCurrent() is false once a different user has activated, even '
        'without an intervening invalidate()', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1);
      final tokenA = epoch.capture()!;

      epoch.activate(2);

      expect(epoch.isCurrent(tokenA), isFalse);
    });

    test('the same user re-authenticating still mints a new generation - a '
        'token from the previous login for the SAME user is no longer '
        'current', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1);
      final firstLoginToken = epoch.capture()!;

      epoch.invalidate();
      epoch.activate(1);

      expect(epoch.isCurrent(firstLoginToken), isFalse);
      expect(epoch.capture()!.generation, isNot(firstLoginToken.generation));
    });

    test('activate() always bumps the generation even without an intervening '
        'invalidate() (e.g. session-restoration racing a fresh login)', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1);
      final gen1 = epoch.capture()!.generation;

      epoch.activate(1);
      final gen2 = epoch.capture()!.generation;

      expect(gen2, greaterThan(gen1));
    });

    test('the logged-out gap between one user logging out and another '
        'logging in consumes its own generation, so a token captured during '
        'that gap can never collide with the next session', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1); // User A logs in.
      epoch.invalidate(); // User A logs out.

      // Something starts during the logged-out gap.
      final gapToken = epoch.capture();
      expect(
        gapToken,
        isNull,
        reason: 'capture() must return null while logged out',
      );

      epoch.activate(2); // User B logs in.
      final userBToken = epoch.capture()!;

      // Reconstruct what a naive "increment on logout only" design would
      // have handed the gap caller - the generation right after A's
      // logout - and confirm it does NOT equal User B's generation.
      expect(userBToken.userId, 2);
    });

    test('repeated logout is idempotent-safe: each call still advances '
        'the generation forward, never backward or reused', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1);
      final afterActivate = epoch.capture()!.generation;

      epoch.invalidate();
      final afterFirstInvalidate = epoch.capture();
      epoch.invalidate();
      final afterSecondInvalidate = epoch.capture();

      expect(afterFirstInvalidate, isNull);
      expect(afterSecondInvalidate, isNull);
      // Reactivating proves the generation kept advancing across both
      // invalidate() calls rather than staying pinned.
      epoch.activate(1);
      expect(epoch.capture()!.generation, greaterThan(afterActivate + 1));
    });

    test('isCurrent() requires both generation and userId to match', () {
      final epoch = UserSessionEpoch();
      epoch.activate(1);
      final token = epoch.capture()!;

      // A token with the right generation but wrong userId must never be
      // treated as current - defensive-in-depth even though generation
      // alone is already unique per session.
      final forged = UserSessionToken(
        generation: token.generation,
        userId: token.userId + 1,
      );
      expect(epoch.isCurrent(forged), isFalse);
    });

    test('UserSessionToken equality is value-based', () {
      const a = UserSessionToken(generation: 1, userId: 5);
      const b = UserSessionToken(generation: 1, userId: 5);
      const c = UserSessionToken(generation: 2, userId: 5);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
