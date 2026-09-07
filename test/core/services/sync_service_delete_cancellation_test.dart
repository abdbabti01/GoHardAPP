import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/rate_limited_exception.dart';

import 'sync_service_test.mocks.dart';

/// Deterministic coverage for `SyncService`'s background delete phase
/// (`_syncDeleteSession`) dispatch rule and acknowledgment safety for a
/// Session whose generic keyed CREATE may be pending or already in flight on
/// the server. See `session_durable_cancellation_test.dart` for the
/// foreground [SessionRepository] equivalent and
/// `session_create_delete_cross_operation_race_test.dart` for CREATE/delete
/// ORDERING races across both layers.
///
/// `MockApiService` (no real Dio/HTTP adapter needed at this layer - see
/// sibling `sync_service_*` suites for the same pattern); real Isar, real
/// `UserSessionEpoch`, real `SessionRequestCoordinator`. No wall-clock
/// waits.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late SyncService syncService;

  const userA = 1;
  const userB = 2;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_delete_cancel_');
    isar = await Isar.open(
      [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
    );

    SyncService.reset();
    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userA);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$userA');

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch()..activate(userA);
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );

    syncService = SyncService(
      apiService: mockApiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: ConnectivityService.instance,
      sessionEpoch: sessionEpoch,
      sessionCoordinator: sessionCoordinator,
    );
  });

  tearDown(() async {
    SyncService.reset();
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LocalSession> insertPendingDeleteSession({
    int uid = userA,
    int? serverId,
    String? clientOperationId,
  }) async {
    final session = LocalSession(
      serverId: serverId,
      userId: uid,
      date: DateTime(2026, 1, 1),
      name: 'Fresh',
      status: 'draft',
      isSynced: false,
      syncStatus: 'pending_delete',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
      clientOperationId: clientOperationId,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  void stubDeleteReturn(bool value) {
    when(
      mockApiService.delete(any, sessionContext: anyNamed('sessionContext')),
    ).thenAnswer((_) async => value);
  }

  void stubDeleteThrow(Object error) {
    when(
      mockApiService.delete(any, sessionContext: anyNamed('sessionContext')),
    ).thenThrow(error);
  }

  List<String> capturedDeletePaths() =>
      verify(
        mockApiService.delete(
          captureAny,
          sessionContext: anyNamed('sessionContext'),
        ),
      ).captured.cast<String>();

  Future<LocalSession?> reload(int localId) => isar.localSessions.get(localId);

  const opId = 'bb0e8400-e29b-41d4-a716-446655440000';

  test('1. serverId null + retained operation key -> dispatches '
      'DELETE /sessions/by-operation/{key}, NOT DELETE-by-id; 204 removes the '
      'row and its exercise/set children', () async {
    final row = await insertPendingDeleteSession(clientOperationId: opId);
    final exercise = LocalExercise(
      sessionLocalId: row.localId,
      name: 'Bench',
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime(2026, 1, 1),
    );
    await isar.writeTxn(() => isar.localExercises.put(exercise));
    final set = LocalExerciseSet(
      exerciseLocalId: exercise.localId,
      setNumber: 1,
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime(2026, 1, 1),
    );
    await isar.writeTxn(() => isar.localExerciseSets.put(set));

    stubDeleteReturn(true);

    await syncService.sync();

    final paths = capturedDeletePaths();
    expect(paths, [ApiConfig.sessionCancelByOperation(opId)]);
    expect(await reload(row.localId), isNull);
    expect(await isar.localExercises.get(exercise.localId), isNull);
    expect(await isar.localExerciseSets.get(set.localId), isNull);
  });

  test('2. serverId known (legacy) -> ordinary DELETE-by-id, even though a '
      'retained operation key is ALSO present', () async {
    final row = await insertPendingDeleteSession(
      serverId: 555,
      clientOperationId: opId,
    );
    stubDeleteReturn(true);

    await syncService.sync();

    final paths = capturedDeletePaths();
    expect(paths, [ApiConfig.sessionById(555)]);
    expect(await reload(row.localId), isNull);
  });

  test('3. neither serverId nor operation key -> removed locally with ZERO '
      'HTTP calls (nothing was ever dispatched to cancel)', () async {
    final row = await insertPendingDeleteSession();

    await syncService.sync();

    verifyNever(
      mockApiService.delete(any, sessionContext: anyNamed('sessionContext')),
    );
    expect(await reload(row.localId), isNull);
  });

  test('4. a 429 on the cancel dispatch preserves durable intent (row stays '
      'pending_delete with the SAME key), aborts the WHOLE remaining pass, '
      'and arms the existing rate-limit cooldown', () async {
    final row = await insertPendingDeleteSession(clientOperationId: opId);
    stubDeleteThrow(
      const RateLimitedException(retryAfter: Duration(seconds: 30)),
    );

    await syncService.sync();

    final after = await reload(row.localId);
    expect(after!.syncStatus, 'pending_delete');
    expect(after.clientOperationId, opId);
    expect(after.serverId, isNull);

    // Cooldown armed: an immediate second sync() call dispatches nothing
    // more, even though the row is still eligible.
    await syncService.sync();
    verify(
      mockApiService.delete(any, sessionContext: anyNamed('sessionContext')),
    ).called(1);
  });

  test(
    '5. cancel dispatch fails with an ordinary error -> durable intent '
    'preserved; a later pass retries the SAME key and converges on success',
    () async {
      final row = await insertPendingDeleteSession(clientOperationId: opId);
      stubDeleteThrow(ApiException('Server error', statusCode: 500));

      await syncService.sync();
      expect((await reload(row.localId))!.syncStatus, 'pending_delete');

      stubDeleteReturn(true);
      await syncService.sync();

      expect(await reload(row.localId), isNull);
      final paths = capturedDeletePaths();
      expect(
        paths,
        List.filled(2, ApiConfig.sessionCancelByOperation(opId)),
        reason: 'both attempts dispatched the SAME retained key',
      );
    },
  );

  test("6. cross-user isolation: user B's sync pass never enumerates or "
      "dispatches anything for A's pending cancellation", () async {
    final rowA = await insertPendingDeleteSession(
      uid: userA,
      clientOperationId: opId,
    );

    // Switch the active session to B without ever touching A's row.
    when(mockAuthService.getUserId()).thenAnswer((_) async => userB);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$userB');
    sessionEpoch.activate(userB);

    await syncService.sync();

    verifyNever(
      mockApiService.delete(any, sessionContext: anyNamed('sessionContext')),
    );
    final after = await reload(rowA.localId);
    expect(after!.userId, userA);
    expect(after.syncStatus, 'pending_delete');
    expect(after.clientOperationId, opId);
  });

  test('7. acknowledgment recheck: the epoch is rechecked as the FIRST '
      'statement inside the deleting write transaction - a session ending '
      'there must not remove the row despite the accepted 204', () async {
    final row = await insertPendingDeleteSession(clientOperationId: opId);
    stubDeleteReturn(true);
    syncService.insideAckWriteTxnForTesting = () async {
      sessionEpoch.invalidate();
    };

    await syncService.sync();

    final after = await reload(row.localId);
    expect(
      after,
      isNotNull,
      reason:
          'a session that ended before the ack write ran must never '
          'have its row removed',
    );
    expect(after!.syncStatus, 'pending_delete');
  });
}
