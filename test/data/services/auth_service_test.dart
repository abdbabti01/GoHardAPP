import 'dart:convert';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

/// A fake [FlutterSecureStoragePlatform] that behaves like a real in-memory
/// secure store, but lets tests make specific keys fail on delete() while
/// every other key still succeeds - needed to prove
/// AuthService.clearSessionCredentials() genuinely attempts every key
/// independently rather than aborting on the first failure.
///
/// Swapped in via the platform's own swappable `instance` singleton (the
/// same pattern already used for `GeolocatorPlatform.instance` in
/// running_provider_test.dart / session_cleanup_coordinator_test.dart) -
/// `AuthService`'s `_storage` field is a single shared
/// `static const FlutterSecureStorage(...)`, and `FlutterSecureStorage`
/// itself delegates every read/write/delete to
/// `FlutterSecureStoragePlatform.instance` under the hood.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

  /// Keys whose next delete() call should throw. Not auto-cleared - stays
  /// in effect for every subsequent delete() of that key within a test.
  final Set<String> deleteFailuresFor = {};

  /// Every key delete() was called for, in call order - including ones
  /// that were made to fail, so tests can assert an attempt happened
  /// regardless of outcome.
  final List<String> deleteAttempts = [];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => data.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    deleteAttempts.add(key);
    if (deleteFailuresFor.contains(key)) {
      throw Exception('secure storage delete failed for "$key"');
    }
    data.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    data.clear();
  }

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

void main() {
  late _FakeSecureStoragePlatform fakePlatform;
  late AuthService authService;

  setUp(() {
    fakePlatform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakePlatform;
    authService = AuthService();
  });

  group('AuthService.clearSessionCredentials', () {
    test('attempts deletion of every session/user-identity key', () async {
      await authService.saveToken(
        token: 'jwt',
        userId: 1,
        name: 'Alice',
        email: 'alice@example.com',
      );
      await authService.saveCachedProfile('{"name":"Alice"}');

      await authService.clearSessionCredentials();

      expect(
        fakePlatform.deleteAttempts,
        containsAll(<String>[
          'jwt_token',
          'user_id',
          'user_name',
          'user_email',
          'cached_user_profile',
        ]),
      );
    });

    test('cached_user_profile is absent after successful logout', () async {
      await authService.saveCachedProfile('{"name":"Alice"}');

      await authService.clearSessionCredentials();

      expect(await authService.getCachedProfile(), isNull);
    });

    test("User A's cached profile cannot be returned after logout and User B "
        'login', () async {
      await authService.saveToken(
        token: 'a-token',
        userId: 1,
        name: 'Alice',
        email: 'alice@example.com',
      );
      await authService.saveCachedProfile('{"name":"Alice"}');

      await authService.clearSessionCredentials();

      // User B logs in on the same device, before their own profile has
      // been fetched/cached yet (e.g. still loading, or offline).
      await authService.saveToken(
        token: 'b-token',
        userId: 2,
        name: 'Bob',
        email: 'bob@example.com',
      );

      expect(
        await authService.getCachedProfile(),
        isNull,
        reason:
            "Alice's cached profile must never be readable as part of "
            "Bob's session",
      );
    });

    test('a failure deleting one key does not prevent deletion attempts for '
        'the remaining keys, which are still genuinely removed', () async {
      await authService.saveToken(
        token: 'jwt',
        userId: 1,
        name: 'Alice',
        email: 'alice@example.com',
      );
      await authService.saveCachedProfile('{"name":"Alice"}');
      // Fail a key in the middle of the deletion list, not the first or
      // last, so this genuinely proves the loop continues past a failure
      // rather than merely happening to reach the end.
      fakePlatform.deleteFailuresFor.add('user_id');

      await authService.clearSessionCredentials();

      expect(
        fakePlatform.deleteAttempts,
        containsAll(<String>[
          'jwt_token',
          'user_id',
          'user_name',
          'user_email',
          'cached_user_profile',
        ]),
        reason: 'every key must still be attempted despite the failure',
      );
      expect(
        await authService.getToken(),
        isNull,
        reason: 'keys after the failure must still be genuinely deleted',
      );
      expect(await authService.getUserName(), isNull);
      expect(await authService.getUserEmail(), isNull);
      expect(await authService.getCachedProfile(), isNull);
    });

    test('never throws even if every deletion fails', () async {
      fakePlatform.deleteFailuresFor.addAll(<String>[
        'jwt_token',
        'user_id',
        'user_name',
        'user_email',
        'cached_user_profile',
      ]);

      await expectLater(authService.clearSessionCredentials(), completes);
    });

    test('preserves the device-wide theme preference across logout', () async {
      await authService.saveThemePreference('dark');

      await authService.clearSessionCredentials();

      expect(
        await authService.getThemePreference(),
        'dark',
        reason:
            'theme preference is device-wide, not user-specific, and must '
            'survive logout',
      );
    });
  });

  group('owner-tagged profile cache', () {
    const profileJson = '{"id":1,"name":"Alice"}';

    test(
      'writeCachedProfile / readCachedProfile round-trip for the owner',
      () async {
        await authService.writeCachedProfile(profileJson, 1);

        final read = await authService.readCachedProfile(1);
        expect(read, isNotNull);
        expect((jsonDecode(read!) as Map)['name'], 'Alice');
      },
    );

    test('readCachedProfile fails closed for a different user', () async {
      await authService.writeCachedProfile(profileJson, 1);

      expect(await authService.readCachedProfile(2), isNull);
    });

    test('the owner id is stamped from the caller argument, never from the '
        'profile body', () async {
      const forged = '{"id":1,"cachedForUserId":999,"name":"Alice"}';
      await authService.writeCachedProfile(forged, 1);

      expect(await authService.readCachedProfile(999), isNull);
      expect(await authService.readCachedProfile(1), isNotNull);
    });

    test('a legacy unowned entry (written via saveCachedProfile) is rejected '
        'by readCachedProfile', () async {
      await authService.saveCachedProfile(profileJson);

      expect(await authService.readCachedProfile(1), isNull);
    });

    test('malformed envelope, missing owner, and non-int owner all fail '
        'closed', () async {
      final platform = _FakeSecureStoragePlatform();
      FlutterSecureStoragePlatform.instance = platform;
      final svc = AuthService();

      platform.data['cached_user_profile'] = 'definitely not json';
      expect(await svc.readCachedProfile(1), isNull);

      platform.data['cached_user_profile'] = jsonEncode({
        'profile': {'id': 1},
      });
      expect(await svc.readCachedProfile(1), isNull);

      platform.data['cached_user_profile'] = jsonEncode({
        'cachedForUserId': '1',
        'profile': {'id': 1},
      });
      expect(await svc.readCachedProfile(1), isNull);

      platform.data['cached_user_profile'] = jsonEncode({'cachedForUserId': 1});
      expect(await svc.readCachedProfile(1), isNull);
    });

    test('clearSessionCredentials removes the owner-tagged entry', () async {
      await authService.writeCachedProfile(profileJson, 1);

      await authService.clearSessionCredentials();

      expect(await authService.readCachedProfile(1), isNull);
    });

    test(
      'writeCachedProfile swallows an unparseable payload without throwing',
      () async {
        await expectLater(
          authService.writeCachedProfile('not json', 1),
          completes,
        );
        expect(await authService.readCachedProfile(1), isNull);
      },
    );
  });
}
