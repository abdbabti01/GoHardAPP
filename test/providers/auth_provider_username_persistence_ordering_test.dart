import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/auth_response.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/providers/auth_provider.dart';

// Reuse the generated mocks from the sibling test (same directory) rather
// than regenerating a near-identical set.
import 'auth_provider_test.mocks.dart';

/// Deterministic held-write proof that a delayed `AuthService.saveUsername`
/// started by `AuthProvider.applyUpdatedUsername` cannot:
///   * recreate credential keys that logout cleared, or
///   * overwrite the next user's persisted username, or
///   * reappear after auth restoration.
///
/// Uses a REAL [AuthService] wired to an in-memory `flutter_secure_storage`
/// method-channel fake whose `write` to `user_username` can be gated, so the
/// exact "A's write completes last" interleaving is forced, not hoped for.
void main() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const usernameKey = 'user_username';
  const tokenKey = 'jwt_token';

  late Map<String, String> store;
  late List<String> ops;
  Completer<void>? heldUsernameWrite;

  late MockAuthRepository repo;
  late MockApiService api;
  late MockSessionRequestCoordinator coordinator;
  late UserSessionEpoch epoch;
  late AuthService authService;

  AuthProvider newProvider() =>
      AuthProvider(repo, authService, api, epoch, coordinator);

  AuthResponse authResponse({
    required String token,
    required int userId,
    required String username,
  }) => AuthResponse(
    token: token,
    userId: userId,
    name: 'User $userId',
    username: username,
    email: 'user$userId@example.com',
  );

  Future<void> loginAs(
    AuthProvider provider, {
    required String token,
    required int userId,
    required String username,
  }) async {
    when(repo.login(any)).thenAnswer(
      (_) async =>
          authResponse(token: token, userId: userId, username: username),
    );
    provider.updateEmail('user$userId@example.com');
    provider.updatePassword('secret12');
    final ok = await provider.login();
    expect(ok, isTrue);
  }

  setUp(() {
    store = {};
    ops = [];
    heldUsernameWrite = null;
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesTestHelper.setMockInitialValues();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args =
              (call.arguments as Map?)?.cast<String, Object?>() ??
              const <String, Object?>{};
          final key = args['key'] as String?;
          switch (call.method) {
            case 'write':
              final value = args['value'] as String;
              // Gate exactly one write to the username key.
              if (key == usernameKey && heldUsernameWrite != null) {
                final gate = heldUsernameWrite!;
                heldUsernameWrite = null;
                await gate.future;
              }
              store[key!] = value;
              ops.add('write:$key=$value');
              return null;
            case 'delete':
              store.remove(key);
              ops.add('delete:$key');
              return null;
            case 'deleteAll':
              store.clear();
              ops.add('deleteAll');
              return null;
            case 'read':
              return store[key];
            case 'readAll':
              return Map<String, String>.from(store);
            case 'containsKey':
              return store.containsKey(key);
            case 'isProtectedDataAvailable':
              return true;
          }
          return null;
        });

    repo = MockAuthRepository();
    api = MockApiService();
    coordinator = MockSessionRequestCoordinator();
    when(coordinator.cancelCurrentGeneration()).thenReturn(null);
    epoch = UserSessionEpoch();
    authService = AuthService();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('held stale username write lands BEFORE logout clears, then B\'s login '
      'is not overwritten, and restoration reads B', () async {
    final providerA = newProvider();
    await loginAs(providerA, token: 'jwtA', userId: 1, username: 'a_old');
    expect(store[usernameKey], 'a_old');

    final tokenA = providerA.captureSessionToken();

    // (1) A changes username; hold its secure-storage write.
    final gate = Completer<void>();
    heldUsernameWrite = gate;
    providerA.applyUpdatedUsername('a_new', tokenA);
    expect(providerA.currentUsername, 'a_new'); // in-memory reconciled
    expect(store[usernameKey], 'a_old'); // write is held - not landed

    // (2) A logs out. It must DRAIN the pending write before clearing.
    final logoutFuture = providerA.logout();
    var logoutDone = false;
    unawaited(logoutFuture.then((_) => logoutDone = true));
    await pumpEventQueue();

    expect(
      logoutDone,
      isFalse,
      reason: 'logout must be blocked on the in-flight username write',
    );
    expect(
      store.containsKey(tokenKey),
      isTrue,
      reason: 'credentials must not be cleared until the drain completes',
    );

    // Release the held write: it lands ('a_new'), THEN logout resumes.
    gate.complete();
    await logoutFuture;
    expect(logoutDone, isTrue);

    // Ordering proof: a_new was written, and only AFTER that were the
    // credentials deleted.
    final aNewWriteIdx = ops.indexOf('write:$usernameKey=a_new');
    final usernameDeleteIdx = ops.indexOf('delete:$usernameKey');
    expect(aNewWriteIdx, greaterThanOrEqualTo(0));
    expect(usernameDeleteIdx, greaterThan(aNewWriteIdx));

    expect(store.containsKey(usernameKey), isFalse); // cleared by logout
    expect(store.containsKey(tokenKey), isFalse);

    // (3) B logs in.
    final providerB = newProvider();
    await loginAs(providerB, token: 'jwtB', userId: 2, username: 'b_user');
    expect(store[usernameKey], 'b_user');

    // (4) A's write already completed during the drain - nothing can re-land
    // 'a_new' now.
    await pumpEventQueue();
    expect(store[usernameKey], 'b_user');

    // Auth restoration (app relaunch): a fresh provider reads storage.
    final restored = newProvider();
    await pumpEventQueue();
    expect(restored.isAuthenticated, isTrue);
    expect(restored.currentUsername, 'b_user');
  });

  test('logout with NO subsequent login: the drained stale write is cleared '
      'and cannot resurrect credentials on restoration', () async {
    final providerA = newProvider();
    await loginAs(providerA, token: 'jwtA', userId: 1, username: 'a_old');

    final tokenA = providerA.captureSessionToken();
    final gate = Completer<void>();
    heldUsernameWrite = gate;
    providerA.applyUpdatedUsername('a_new', tokenA);

    final logoutFuture = providerA.logout();
    await pumpEventQueue();
    gate.complete(); // stale write lands during the drain
    await logoutFuture;

    // Every session key gone, including the one the stale write just wrote.
    expect(store.containsKey(usernameKey), isFalse);
    expect(store.containsKey(tokenKey), isFalse);
    expect(store.containsKey('user_id'), isFalse);

    // Even after the microtask queue fully drains, nothing reappears.
    await pumpEventQueue();
    expect(store, isEmpty);

    final restored = newProvider();
    await pumpEventQueue();
    expect(restored.isAuthenticated, isFalse);
    expect(restored.currentUsername, isNull);
  });

  test('a username write that finishes normally before logout is unaffected '
      'by the drain (no regression)', () async {
    final providerA = newProvider();
    await loginAs(providerA, token: 'jwtA', userId: 1, username: 'a_old');
    final tokenA = providerA.captureSessionToken();

    providerA.applyUpdatedUsername('a_new', tokenA); // not held
    await pumpEventQueue();
    expect(store[usernameKey], 'a_new');

    await providerA.logout();
    expect(store.containsKey(usernameKey), isFalse);
  });

  test('TWO username edits in one session (first write stalled): BOTH drain '
      'before logout clears, and B is not overwritten', () async {
    final providerA = newProvider();
    await loginAs(providerA, token: 'jwtA', userId: 1, username: 'a_old');
    final tokenA = providerA.captureSessionToken();

    // First edit's write stalls; second edit chains behind it.
    final gate = Completer<void>();
    heldUsernameWrite = gate;
    providerA.applyUpdatedUsername('a_edit1', tokenA);
    providerA.applyUpdatedUsername('a_edit2', tokenA);
    await pumpEventQueue();
    expect(store[usernameKey], 'a_old'); // both writes still queued

    final logoutFuture = providerA.logout();
    var logoutDone = false;
    unawaited(logoutFuture.then((_) => logoutDone = true));
    await pumpEventQueue();
    expect(logoutDone, isFalse); // blocked on the whole chain

    gate.complete();
    await logoutFuture;

    // Ordering: both writes landed, THEN credentials were deleted.
    final w1 = ops.indexOf('write:$usernameKey=a_edit1');
    final w2 = ops.indexOf('write:$usernameKey=a_edit2');
    final del = ops.indexOf('delete:$usernameKey');
    expect(w1, greaterThanOrEqualTo(0));
    expect(w2, greaterThan(w1)); // call order preserved (last edit wins)
    expect(del, greaterThan(w2));
    expect(store.containsKey(usernameKey), isFalse);

    final providerB = newProvider();
    await loginAs(providerB, token: 'jwtB', userId: 2, username: 'b_user');
    await pumpEventQueue();
    expect(store[usernameKey], 'b_user'); // no stale A write re-lands
  });
}

/// SharedPreferences mock without pulling in the plugin's test package.
class SharedPreferencesTestHelper {
  static void setMockInitialValues() {
    const prefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(prefsChannel, (call) async {
          switch (call.method) {
            case 'getAll':
              return <String, Object>{};
            case 'setString':
            case 'setBool':
            case 'setInt':
            case 'setDouble':
            case 'setStringList':
            case 'remove':
            case 'clear':
              return true;
          }
          return null;
        });
  }
}
