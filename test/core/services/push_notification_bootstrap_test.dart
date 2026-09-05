import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/services/push_notification_bootstrap.dart';

void main() {
  group('bootstrapPushNotifications', () {
    test('does not invoke attempt() when Firebase is unavailable', () async {
      var attemptCalled = false;

      await bootstrapPushNotifications(
        firebaseAvailable: false,
        attempt: () async {
          attemptCalled = true;
        },
      );

      expect(
        attemptCalled,
        isFalse,
        reason:
            'push initialization must be skipped entirely - no token '
            'retrieval or server registration should even be attempted',
      );
    });

    test('completes without throwing when Firebase is unavailable', () async {
      await expectLater(
        bootstrapPushNotifications(
          firebaseAvailable: false,
          attempt: () async => throw StateError('must never run'),
        ),
        completes,
      );
    });

    test('invokes attempt() when Firebase is available', () async {
      var attemptCalled = false;

      await bootstrapPushNotifications(
        firebaseAvailable: true,
        attempt: () async {
          attemptCalled = true;
        },
      );

      expect(
        attemptCalled,
        isTrue,
        reason: 'the success path must not be accidentally disabled',
      );
    });

    test('propagates attempt() failures rather than masking them', () async {
      await expectLater(
        bootstrapPushNotifications(
          firebaseAvailable: true,
          attempt: () async => throw StateError('boom'),
        ),
        throwsStateError,
      );
    });
  });
}
