import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/services/push_notification_service.dart';

void main() {
  group('handleBackgroundFirebaseMessage', () {
    test('completes safely without propagating when Firebase '
        'initialization fails in the background isolate', () async {
      await expectLater(
        handleBackgroundFirebaseMessage(
          'msg-1',
          initializer: () => throw Exception('no default Firebase app'),
        ),
        completes,
      );
    });

    test('completes normally when Firebase initialization succeeds', () async {
      var initializerCalled = false;

      await expectLater(
        handleBackgroundFirebaseMessage(
          'msg-2',
          initializer: () async {
            initializerCalled = true;
          },
        ),
        completes,
      );

      expect(initializerCalled, isTrue);
    });
  });
}
