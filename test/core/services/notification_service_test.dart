import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:go_hard_app/core/services/notification_service.dart';

/// A fake [PermissionHandlerPlatform] that lets tests control exactly what
/// the OS reports for the notification permission, and count how many times
/// each operation was actually invoked - swapped in via the platform's own
/// swappable `instance` singleton (the same pattern already used for
/// `FlutterSecureStoragePlatform.instance` in auth_service_test.dart and
/// `GeolocatorPlatform.instance` in running_provider_test.dart).
class _FakePermissionHandlerPlatform extends PermissionHandlerPlatform {
  PermissionStatus statusToReport = PermissionStatus.denied;
  PermissionStatus statusAfterRequest = PermissionStatus.granted;
  int checkPermissionStatusCalls = 0;
  int requestPermissionsCalls = 0;
  bool openAppSettingsCalled = false;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    checkPermissionStatusCalls++;
    return statusToReport;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    requestPermissionsCalls++;
    statusToReport = statusAfterRequest;
    return {for (final p in permissions) p: statusAfterRequest};
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalled = true;
    return true;
  }
}

void main() {
  late _FakePermissionHandlerPlatform fakePlatform;
  late NotificationService service;

  setUp(() {
    fakePlatform = _FakePermissionHandlerPlatform();
    PermissionHandlerPlatform.instance = fakePlatform;
    service = NotificationService();

    // NotificationService.requestPermissions() branches per-platform, and
    // its Android branch is the one that actually calls through
    // permission_handler (its iOS branch calls flutter_local_notifications'
    // own Darwin plugin channel directly - real OS-dialog behavior there
    // remains REAL-iOS VERIFICATION REQUIRED, not unit-testable here without
    // mocking a second platform channel). Force android so this suite
    // exercises that branch deterministically regardless of the host OS
    // `flutter test` happens to run on.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('NotificationService.hasPermission', () {
    test('is a pure status check - never requests', () async {
      fakePlatform.statusToReport = PermissionStatus.granted;

      final result = await service.hasPermission();

      expect(result, isTrue);
      expect(fakePlatform.requestPermissionsCalls, 0);
    });

    test('reflects a denied status without requesting', () async {
      fakePlatform.statusToReport = PermissionStatus.denied;

      final result = await service.hasPermission();

      expect(result, isFalse);
      expect(fakePlatform.requestPermissionsCalls, 0);
    });
  });

  group('NotificationService.ensurePermission', () {
    test(
      'already-granted: does not request again (no duplicate OS prompt)',
      () async {
        fakePlatform.statusToReport = PermissionStatus.granted;

        final result = await service.ensurePermission();

        expect(result, isTrue);
        expect(
          fakePlatform.requestPermissionsCalls,
          0,
          reason:
              'already authorized - requesting again would be a '
              'redundant, contextless prompt',
        );
      },
    );

    test('not yet determined: requests once and returns the outcome', () async {
      fakePlatform.statusToReport = PermissionStatus.denied;
      fakePlatform.statusAfterRequest = PermissionStatus.granted;

      final result = await service.ensurePermission();

      expect(result, isTrue);
      expect(fakePlatform.requestPermissionsCalls, 1);
    });

    test(
      'denied: returns false rather than throwing, safe to call from UI',
      () async {
        fakePlatform.statusToReport = PermissionStatus.denied;
        fakePlatform.statusAfterRequest = PermissionStatus.denied;

        final result = await service.ensurePermission();

        expect(result, isFalse);
        expect(fakePlatform.requestPermissionsCalls, 1);
      },
    );

    test('single-flight: two calls started before the first resolves only hit '
        'the platform once, both get the same result', () async {
      // Settings has multiple independent reminder toggles that can each
      // call ensurePermission(); on Android a second concurrent
      // requestPermissions() call throws natively, which would otherwise
      // surface as a false "denied" on whichever toggle loses the race.
      fakePlatform.statusToReport = PermissionStatus.denied;
      fakePlatform.statusAfterRequest = PermissionStatus.granted;

      // Both calls start before either awaits anything - Dart runs each
      // synchronously up to its first `await`, so the second call is
      // guaranteed to see the first's still-pending Future.
      final future1 = service.ensurePermission();
      final future2 = service.ensurePermission();

      final results = await Future.wait([future1, future2]);

      expect(results, [true, true]);
      expect(fakePlatform.checkPermissionStatusCalls, 1);
      expect(fakePlatform.requestPermissionsCalls, 1);
    });

    test('is not single-flight across separate, already-resolved calls - a '
        'later call after the first finished checks status again', () async {
      fakePlatform.statusToReport = PermissionStatus.granted;

      await service.ensurePermission();
      await service.ensurePermission();

      expect(fakePlatform.checkPermissionStatusCalls, 2);
    });
  });

  group('NotificationService.openSettings', () {
    test('routes to the OS Settings screen', () async {
      await service.openSettings();

      expect(fakePlatform.openAppSettingsCalled, isTrue);
    });
  });
}
