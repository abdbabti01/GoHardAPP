import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/notification_service.dart';
import 'package:go_hard_app/providers/settings_provider.dart';

@GenerateMocks([NotificationService])
import 'settings_provider_test.mocks.dart';

/// A minimal in-memory [FlutterSecureStoragePlatform] - swapped in via the
/// platform's own swappable `instance` singleton (the same pattern used in
/// auth_service_test.dart), so SettingsProvider can use a real
/// [FlutterSecureStorage] without touching an actual device keychain.
class _InMemorySecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => data.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => data.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      data.clear();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => data[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => data;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    data[key] = value;
  }
}

/// Proves the notification-permission-timing fix: SettingsProvider is
/// constructed unconditionally at app startup (see main.dart), so it must
/// never itself trigger the OS permission dialog - only an explicit
/// reminder-toggle action may do that, and only via
/// NotificationService.ensurePermission() (never a bare requestPermissions()
/// call, so an already-granted permission is never re-requested).
void main() {
  late MockNotificationService mockNotificationService;
  late FlutterSecureStorage storage;

  setUp(() {
    FlutterSecureStoragePlatform.instance = _InMemorySecureStoragePlatform();
    storage = const FlutterSecureStorage();
    mockNotificationService = MockNotificationService();

    when(
      mockNotificationService.scheduleMorningReminder(
        hour: anyNamed('hour'),
        minute: anyNamed('minute'),
      ),
    ).thenAnswer((_) async {});
    when(
      mockNotificationService.scheduleEveningReminder(
        hour: anyNamed('hour'),
        minute: anyNamed('minute'),
      ),
    ).thenAnswer((_) async {});
    when(
      mockNotificationService.cancelMorningReminder(),
    ).thenAnswer((_) async {});
    when(
      mockNotificationService.cancelEveningReminder(),
    ).thenAnswer((_) async {});
    when(
      mockNotificationService.cancelNutritionReminder(),
    ).thenAnswer((_) async {});
  });

  test('construction (cold-launch/provider-init) never checks or requests '
      'notification permission, even though morning/evening reminders are '
      'enabled by default and get scheduled', () async {
    SettingsProvider(storage, mockNotificationService);
    await pumpEventQueue();

    verifyNever(mockNotificationService.hasPermission());
    verifyNever(mockNotificationService.ensurePermission());
    verifyNever(mockNotificationService.requestPermissions());
    // Scheduling itself still happens - permission gating must never
    // block the (harmless, OS-suppressed-until-granted) schedule call.
    verify(
      mockNotificationService.scheduleMorningReminder(
        hour: anyNamed('hour'),
        minute: anyNamed('minute'),
      ),
    ).called(1);
  });

  test('turning a reminder on is the explicit user action that triggers the '
      'permission flow, via ensurePermission() - not a bare request', () async {
    when(
      mockNotificationService.ensurePermission(),
    ).thenAnswer((_) async => true);
    final provider = SettingsProvider(storage, mockNotificationService);
    await pumpEventQueue();
    // Evening reminder defaults to enabled, so start from a clean
    // off-to-on transition rather than an already-on no-op.
    await provider.setEveningReminderEnabled(false);
    clearInteractions(mockNotificationService);
    when(
      mockNotificationService.ensurePermission(),
    ).thenAnswer((_) async => true);

    final result = await provider.setEveningReminderEnabled(true);

    expect(result, isTrue);
    verify(mockNotificationService.ensurePermission()).called(1);
    verifyNever(mockNotificationService.requestPermissions());
    verify(
      mockNotificationService.scheduleEveningReminder(
        hour: anyNamed('hour'),
        minute: anyNamed('minute'),
      ),
    ).called(1);
  });

  test('denied permission: the reminder is not enabled, nothing is scheduled, '
      'and the caller is told so safely (no throw)', () async {
    when(
      mockNotificationService.ensurePermission(),
    ).thenAnswer((_) async => false);
    final provider = SettingsProvider(storage, mockNotificationService);
    await pumpEventQueue();
    // Turn the default-enabled morning reminder off first so the next
    // enable() call is a genuine off-to-on transition.
    await provider.setMorningReminderEnabled(false);
    clearInteractions(mockNotificationService);
    when(
      mockNotificationService.ensurePermission(),
    ).thenAnswer((_) async => false);

    final result = await provider.setMorningReminderEnabled(true);

    expect(result, isFalse);
    expect(provider.morningReminderEnabled, isFalse);
    verifyNever(
      mockNotificationService.scheduleMorningReminder(
        hour: anyNamed('hour'),
        minute: anyNamed('minute'),
      ),
    );
  });

  test('every enable() routes through ensurePermission() rather than a bare '
      'requestPermissions() - the gate itself skipping a redundant OS request '
      'once already granted is proven separately in '
      'notification_service_test.dart, not here', () async {
    when(
      mockNotificationService.ensurePermission(),
    ).thenAnswer((_) async => true);
    final provider = SettingsProvider(storage, mockNotificationService);
    await pumpEventQueue();

    await provider.setEveningReminderEnabled(true);
    await provider.setMorningReminderEnabled(false);
    await provider.setMorningReminderEnabled(true);

    // Each enable() calls ensurePermission() once - it is ensurePermission
    // itself (not this orchestration layer) that internally skips the OS
    // request when already granted, so 2 calls here is correct: this
    // proves the orchestration never bypasses the gate, while
    // notification_service_test.dart proves the gate itself is a no-op
    // once granted.
    verify(mockNotificationService.ensurePermission()).called(2);
    verifyNever(mockNotificationService.requestPermissions());
  });
}
