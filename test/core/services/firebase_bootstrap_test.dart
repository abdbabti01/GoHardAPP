import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/services/firebase_availability.dart';
import 'package:go_hard_app/core/services/firebase_bootstrap.dart';

void main() {
  group('initializeFirebaseSafely', () {
    test('returns true and permits later work when the initializer '
        'succeeds', () async {
      var initializerCalled = false;

      final available = await initializeFirebaseSafely(() async {
        initializerCalled = true;
      });

      expect(available, isTrue);
      expect(initializerCalled, isTrue);
    });

    test(
      'returns false without rethrowing when the initializer fails',
      () async {
        final available = await initializeFirebaseSafely(() {
          throw Exception('no default Firebase app');
        });

        expect(available, isFalse);
      },
    );

    test('a later startup step still executes after initialization '
        'fails - the failure never propagates past this call', () async {
      var laterStepRan = false;

      final available = await initializeFirebaseSafely(() {
        throw Exception('no default Firebase app');
      });
      // Simulates the next line of main() running unconditionally.
      laterStepRan = true;

      expect(available, isFalse);
      expect(laterStepRan, isTrue);
    });

    test('does not swallow the initializer entirely - success is not '
        'accidentally reported as failure', () async {
      final available = await initializeFirebaseSafely(() async {});

      expect(available, isTrue);
    });

    test('propagates an async (not just synchronous) initializer failure '
        'without rethrowing', () async {
      final available = await initializeFirebaseSafely(
        () => Future<void>.error(Exception('platform channel unavailable')),
      );

      expect(available, isFalse);
    });
  });

  group('runFirebaseAwareStartup', () {
    test('success: invokes the continuation exactly once with available '
        'state', () async {
      var callCount = 0;
      FirebaseAvailability? received;

      await runFirebaseAwareStartup(
        initializer: () async {},
        continuation: (availability) async {
          callCount++;
          received = availability;
        },
      );

      expect(callCount, 1, reason: 'the continuation must run exactly once');
      expect(received!.isAvailable, isTrue);
    });

    test('failure: invokes the continuation exactly once with unavailable '
        'state, and the Firebase exception does not escape', () async {
      var callCount = 0;
      FirebaseAvailability? received;

      await expectLater(
        runFirebaseAwareStartup(
          initializer: () => throw Exception('no default Firebase app'),
          continuation: (availability) async {
            callCount++;
            received = availability;
          },
        ),
        completes,
      );

      expect(
        callCount,
        1,
        reason:
            'startup must always continue exactly once, even when '
            'Firebase initialization fails',
      );
      expect(received!.isAvailable, isFalse);
    });

    test('a continuation exception propagates and is not converted into '
        'Firebase-unavailable success', () async {
      await expectLater(
        runFirebaseAwareStartup(
          initializer: () async {},
          continuation: (_) async => throw StateError('runApp blew up'),
        ),
        throwsStateError,
      );
    });

    test('a continuation exception still propagates even when Firebase '
        'initialization itself failed - the Firebase catch must not '
        'swallow it', () async {
      await expectLater(
        runFirebaseAwareStartup(
          initializer: () => throw Exception('no default Firebase app'),
          continuation: (_) async => throw StateError('database init blew up'),
        ),
        throwsStateError,
      );
    });

    test('the continuation is never invoked twice', () async {
      var callCount = 0;

      await runFirebaseAwareStartup(
        initializer: () async {},
        continuation: (_) async {
          callCount++;
        },
      );

      expect(callCount, 1);
    });
  });
}
