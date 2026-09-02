import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/repositories/profile_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

@GenerateMocks([ConnectivityService])
import 'profile_repository_cache_ownership_test.mocks.dart';

/// End-to-end proof that the profile offline cache cannot leak one user's
/// profile to another, even when User A's cache write completes *after* A has
/// logged out (or after User B has logged in).
///
/// Uses a REAL [AuthService] over a fake [FlutterSecureStoragePlatform] whose
/// `write` for the profile-cache key can be paused on a [Completer], plus a
/// REAL [ApiService] + [SessionRequestCoordinator] + [UserSessionEpoch] over a
/// fake [HttpClientAdapter]. No wall-clock delay, `Future.delayed`, `Timer`,
/// or `pumpEventQueue` - the write ordering is driven entirely by the
/// storage `write` gate and the adapter's dispatch `Completer`.
class _GatedSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};
  final List<String> writeLog = [];
  final List<String> readLog = [];

  /// When [gateKey] is set, the next `write` for that key awaits [gate]
  /// before storing. Both are cleared once that write is entered; [gateReached]
  /// fires at that same moment, so a test can know the caller is parked inside
  /// the write (i.e. it has already passed every pre-write check) before it
  /// perturbs the session.
  String? gateKey;
  Completer<void>? gate;
  final Completer<void> gateReached = Completer<void>();

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
  }) async {
    readLog.add(key);
    return data[key];
  }

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
    if (key == gateKey && gate != null) {
      final g = gate!;
      gateKey = null;
      gate = null;
      if (!gateReached.isCompleted) gateReached.complete();
      await g.future;
    }
    writeLog.add(key);
    data[key] = value;
  }
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  Completer<void> dispatched = Completer<void>();
  int statusCode = 200;
  String body = '{}';

  /// When set, `fetch` waits on this before returning the response, so a test
  /// can land a session change in the window between dispatch and the
  /// response reaching the repository's post-response check.
  Completer<void>? responseGate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!dispatched.isCompleted) dispatched.complete();
    if (responseGate != null) await responseGate!.future;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const cacheKey = 'cached_user_profile';

  late _GatedSecureStoragePlatform storage;
  late UserSessionEpoch epoch;
  late AuthService authService;
  late MockConnectivityService connectivity;
  late SessionRequestCoordinator coordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late ProfileRepository repository;

  String profileJson(int id) =>
      '{"id":$id,"name":"User $id","username":"u$id","email":"u$id@x.com",'
      '"dateCreated":"2024-01-01T00:00:00Z"}';

  setUp(() {
    storage = _GatedSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = storage;

    epoch = UserSessionEpoch();
    authService = AuthService();
    connectivity = MockConnectivityService();
    when(connectivity.isOnline).thenReturn(true);
    coordinator = SessionRequestCoordinator(epoch, authService);
    apiService = ApiService(authService, epoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
    repository = ProfileRepository(
      apiService,
      authService,
      epoch,
      coordinator,
      connectivity,
    );
  });

  Future<void> login(int id) async {
    storage.data['jwt_token'] = 'jwt-$id';
    storage.data['user_id'] = '$id';
    epoch.activate(id);
  }

  // A user-scoped cache miss surfaces as this exact message (from
  // _getCachedProfile), never as a returned User of another user.
  final throwsNoProfileOffline = throwsA(
    isA<Exception>().having(
      (e) => e.toString(),
      'message',
      contains('No profile available offline'),
    ),
  );

  int? ownerOfStoredCache() {
    final raw = storage.data[cacheKey];
    if (raw == null) return null;
    return (jsonDecode(raw) as Map)['cachedForUserId'] as int?;
  }

  group('legacy / unowned entries fail closed', () {
    test(
      'a legacy bare-profile entry (no owner) is not returned to anyone',
      () async {
        // Simulate a pre-migration entry written by the legacy API.
        await authService.saveCachedProfile(profileJson(1));

        expect(await authService.readCachedProfile(1), isNull);
        expect(await authService.readCachedProfile(2), isNull);
      },
    );

    test(
      'an owner-tagged entry is returned to its owner and only its owner',
      () async {
        await authService.writeCachedProfile(profileJson(1), 1);

        final forOwner = await authService.readCachedProfile(1);
        expect(forOwner, isNotNull);
        expect((jsonDecode(forOwner!) as Map)['id'], 1);

        expect(await authService.readCachedProfile(2), isNull);
      },
    );

    test(
      'malformed / missing-owner / non-int-owner metadata fails closed',
      () async {
        storage.data[cacheKey] = 'not json at all';
        expect(await authService.readCachedProfile(1), isNull);

        storage.data[cacheKey] = jsonEncode({'profile': profileJson(1)});
        expect(await authService.readCachedProfile(1), isNull);

        storage.data[cacheKey] = jsonEncode({
          'cachedForUserId': '1',
          'profile': jsonDecode(profileJson(1)),
        });
        expect(await authService.readCachedProfile(1), isNull);

        storage.data[cacheKey] = jsonEncode({'cachedForUserId': 1});
        expect(await authService.readCachedProfile(1), isNull);
      },
    );

    test('a forged cachedForUserId inside the profile body cannot grant '
        'ownership', () async {
      // The profile JSON itself claims to belong to user 999.
      const forged =
          '{"id":1,"cachedForUserId":999,"name":"A","username":"a",'
          '"email":"a@x.com","dateCreated":"2024-01-01T00:00:00Z"}';
      await authService.writeCachedProfile(
        forged,
        1,
      ); // stamped for 1 by caller

      expect(await authService.readCachedProfile(999), isNull);
      expect(await authService.readCachedProfile(1), isNotNull);
    });
  });

  group('repository fallback is user-scoped', () {
    test('logged out: getProfile throws, no HTTP, no cache read', () async {
      await authService.writeCachedProfile(profileJson(1), 1);

      await expectLater(
        repository.getProfile(),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.dispatched.isCompleted, isFalse);
      expect(storage.readLog.contains(cacheKey), isFalse);
    });

    test('offline: A gets A\'s cached profile', () async {
      await login(1);
      await authService.writeCachedProfile(profileJson(1), 1);
      when(connectivity.isOnline).thenReturn(false);

      final user = await repository.getProfile();
      expect(user.id, 1);
    });

    test('offline: B cannot read A\'s cached profile', () async {
      await authService.writeCachedProfile(profileJson(1), 1);
      await login(2);
      when(connectivity.isOnline).thenReturn(false);

      await expectLater(repository.getProfile(), throwsNoProfileOffline);
    });

    test('a normal online success writes an entry owned by the captured '
        'user - not by any id in the response body', () async {
      await login(7);
      // Response body lies about the id / embeds a bogus owner field.
      adapter.body =
          '{"id":999,"cachedForUserId":999,"name":"x","username":"x",'
          '"email":"x@x.com","dateCreated":"2024-01-01T00:00:00Z"}';

      await repository.getProfile();

      expect(ownerOfStoredCache(), 7);
    });
  });

  group(
    'response-to-write TOCTOU: stale write cannot disclose to another user',
    () {
      test('A\'s cache write is paused, A logs out (cache deleted), then the '
          'write is released - B still cannot read A\'s profile', () async {
        await login(1);
        adapter.body = profileJson(1);
        final gate = Completer<void>();
        storage
          ..gateKey = cacheKey
          ..gate = gate;

        final aFuture = repository.getProfile();
        // Wait until getProfile is parked inside the cache write - it has
        // passed the post-response isCurrent() check by this point.
        await storage.gateReached.future;

        // A logs out: epoch invalidated + cache key deleted (mirrors
        // AuthService.clearSessionCredentials).
        epoch.invalidate();
        await authService.clearSessionCredentials();
        expect(storage.data[cacheKey], isNull);

        // Release A's paused write - it lands post-logout and recreates the key.
        gate.complete();
        await aFuture;
        expect(storage.data[cacheKey], isNotNull);
        expect(ownerOfStoredCache(), 1);

        // B logs in and hits an API failure -> user-scoped offline fallback.
        await login(2);
        expect(await authService.readCachedProfile(2), isNull);
        adapter.statusCode = 500;
        await expectLater(repository.getProfile(), throwsNoProfileOffline);
      });

      test(
        'B is activated before A\'s paused write completes - the write still '
        'lands tagged for A and is invisible to B',
        () async {
          await login(1);
          adapter.body = profileJson(1);
          final gate = Completer<void>();
          storage
            ..gateKey = cacheKey
            ..gate = gate;

          final aFuture = repository.getProfile();
          await storage.gateReached.future;

          epoch.invalidate();
          await login(2); // B active now

          gate.complete();
          await aFuture;

          expect(ownerOfStoredCache(), 1);
          expect(await authService.readCachedProfile(2), isNull);
        },
      );

      test('A\'s stale write overwriting a B-owned entry produces a B cache '
          'miss, never readable A data', () async {
        await login(1);
        adapter.body = profileJson(1);
        final gate = Completer<void>();
        storage
          ..gateKey = cacheKey
          ..gate = gate;

        final aFuture = repository.getProfile();
        await storage.gateReached.future;

        // B logs in and caches its own profile.
        epoch.invalidate();
        await login(2);
        await authService.writeCachedProfile(profileJson(2), 2);
        expect(await authService.readCachedProfile(2), isNotNull);

        // A's stale write lands, overwriting the key with A's envelope.
        gate.complete();
        await aFuture;

        expect(await authService.readCachedProfile(2), isNull); // miss, not A
        final asOne = await authService.readCachedProfile(1);
        expect((jsonDecode(asOne!) as Map)['id'], 1); // only A can read it
      });
    },
  );

  group('lifecycle exceptions never fall back to cache', () {
    test('invalidation before dispatch surfaces SessionStaleException, not a '
        'cached profile', () async {
      await login(1);
      await authService.writeCachedProfile(profileJson(1), 1);
      adapter.body = profileJson(1);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };

      await expectLater(
        repository.getProfile(),
        throwsA(isA<SessionStaleException>()),
      );
    });

    test('logout landing AFTER dispatch but before the response is processed: '
        'the post-response check throws and no envelope is written to real '
        'storage', () async {
      await login(1);
      adapter
        ..body = profileJson(1)
        ..responseGate = Completer<void>();

      final future = repository.getProfile();
      await adapter.dispatched.future; // request sent; response still gated

      epoch.invalidate();
      adapter.responseGate!.complete(); // response now reaches getProfile

      await expectLater(future, throwsA(isA<SessionStaleException>()));
      expect(
        storage.writeLog.contains(cacheKey),
        isFalse,
        reason: 'the post-response isCurrent() check must skip the cache write',
      );
    });
  });

  group('logout cleanup still removes the entry', () {
    test('clearSessionCredentials deletes the owner-tagged envelope', () async {
      await login(1);
      await authService.writeCachedProfile(profileJson(1), 1);
      expect(storage.data[cacheKey], isNotNull);

      await authService.clearSessionCredentials();

      expect(storage.data[cacheKey], isNull);
      expect(await authService.readCachedProfile(1), isNull);
    });
  });
}
