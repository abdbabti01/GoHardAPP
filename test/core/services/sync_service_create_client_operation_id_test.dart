import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/services/api_exception.dart';

import 'sync_service_test.mocks.dart';

/// Deterministic coverage for durable `clientOperationId` on generic
/// `POST /api/v1/sessions` CREATE, at the [SyncService] (background retry /
/// legacy backfill) layer. Real Isar, real [UserSessionEpoch], real
/// [SessionRequestCoordinator]; `MockApiService` with synchronous throwing /
/// returning responders and `verify(...).captured` to inspect the exact
/// request body map. No wall-clock waits - every ordering is driven by
/// `Completer`s and test-only hooks already established on [SyncService]
/// (mirroring `sync_service_create_soft_error_test.dart`, which is re-run
/// unmodified as regression proof that `SessionCreateError.isSoftRetryable`
/// is unchanged by this PR).
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late SyncService syncService;

  const userId = 1;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_create_opid_');
    isar = await Isar.open(
      [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
    );

    SyncService.reset();
    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userId);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$userId');

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch()..activate(userId);
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

  Future<LocalSession> insertPendingCreateSession({
    String name = 'Draft workout',
    String? clientOperationId,
    DateTime? lastModifiedLocal,
  }) async {
    final session = LocalSession(
      serverId: null,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: name,
      status: 'draft',
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: lastModifiedLocal ?? DateTime(2026, 1, 1, 8),
      clientOperationId: clientOperationId,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Map<String, dynamic> serverSessionJson({
    required int id,
    int version = 1,
    String name = 'Draft workout',
    String status = 'draft',
  }) => {
    'id': id,
    'userId': userId,
    'date': '2026-01-01',
    'duration': null,
    'notes': null,
    'type': null,
    'name': name,
    'status': status,
    'startedAt': null,
    'completedAt': null,
    'pausedAt': null,
    'exercises': <dynamic>[],
    'programId': null,
    'programWorkoutId': null,
    'version': version,
  };

  void stubPostThrow(Object error) {
    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => throw error);
  }

  void stubPostReturn(Map<String, dynamic> response) {
    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => response);
  }

  ApiException apiError(int status, {Object? body}) {
    final requestOptions = RequestOptions(path: '/api/v1/sessions');
    return ApiException(
      'Error ($status)',
      statusCode: status,
      responseData: body,
      originalError: DioException(
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: status,
          data: body,
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }

  Future<Map<String, dynamic>> capturedLastPostBody() async {
    final captured =
        verify(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: captureAnyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).captured;
    return captured.last as Map<String, dynamic>;
  }

  Future<LocalSession?> reload(int localId) => isar.localSessions.get(localId);

  group('14. legacy-key assignment', () {
    test('a legacy null-key row is assigned a durable key BEFORE dispatch, and '
        'that key is sent', () async {
      final row = await insertPendingCreateSession();
      stubPostReturn(serverSessionJson(id: 500));

      await syncService.sync();

      final after = await reload(row.localId);
      expect(after!.clientOperationId, isNotNull);
      expect(after.syncStatus, 'synced');

      final body = await capturedLastPostBody();
      expect(body['clientOperationId'], after.clientOperationId);
    });

    test('6/18. an already-keyed row (assigned by the foreground path) is '
        'resent with the IDENTICAL key on a SyncService retry', () async {
      final row = await insertPendingCreateSession(
        clientOperationId: 'preexisting-key-123',
      );
      stubPostReturn(serverSessionJson(id: 501));

      await syncService.sync();

      final body = await capturedLastPostBody();
      expect(body['clientOperationId'], 'preexisting-key-123');
      final after = await reload(row.localId);
      expect(after!.clientOperationId, 'preexisting-key-123');
    });

    test('27. a malformed existing non-null key is never rotated', () async {
      final row = await insertPendingCreateSession(
        clientOperationId: 'not-a-valid-uuid',
      );
      stubPostReturn(serverSessionJson(id: 502));

      await syncService.sync();

      final body = await capturedLastPostBody();
      expect(body['clientOperationId'], 'not-a-valid-uuid');
      final after = await reload(row.localId);
      expect(after!.clientOperationId, 'not-a-valid-uuid');
    });

    test('17. a concurrent candidate assignment never replaces an '
        'already-committed winning key', () async {
      final row = await insertPendingCreateSession();
      stubPostReturn(serverSessionJson(id: 503));

      // Land a "concurrent winner" write in the exact window between
      // candidate generation and this pass's guarded write transaction.
      syncService.beforeCreateOperationKeyWriteTxnForTesting = () async {
        await isar.writeTxn(() async {
          final current = await isar.localSessions.get(row.localId);
          if (current != null && current.clientOperationId == null) {
            current.clientOperationId = 'winner-key';
            await isar.localSessions.put(current);
          }
        });
      };

      await syncService.sync();

      final body = await capturedLastPostBody();
      expect(
        body['clientOperationId'],
        'winner-key',
        reason: 'the losing candidate must be discarded, not dispatched',
      );
      final after = await reload(row.localId);
      expect(after!.clientOperationId, 'winner-key');
    });
  });

  test('19. the no-serverId UPDATE fallback uses exactly one persisted key, '
      'never a different one generated separately', () async {
    final row = LocalSession(
      serverId: null,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: 'Fallback',
      status: 'draft',
      isSynced: false,
      syncStatus: 'pending_update', // invalid state: no serverId
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localSessions.put(row));
    stubPostReturn(serverSessionJson(id: 504, name: 'Fallback'));

    var generatorCalls = 0;
    syncService.operationIdGeneratorForTesting = () {
      generatorCalls++;
      return 'fallback-key-$generatorCalls';
    };
    var keyAssignmentTxnFired = false;
    syncService.beforeCreateOperationKeyWriteTxnForTesting = () async {
      keyAssignmentTxnFired = true;
      // The row must STILL be keyless at this exact point - proving the
      // status-flip step itself never assigned one.
      final stillKeyless = await isar.localSessions.get(row.localId);
      expect(stillKeyless!.clientOperationId, isNull);
    };

    await syncService.sync();

    expect(
      keyAssignmentTxnFired,
      isTrue,
      reason:
          'the ONE key assignment for this operation must happen inside '
          "_ensureCreateOperationKey's own guarded transaction, never as a "
          'side effect of the status-flip step',
    );
    expect(
      generatorCalls,
      1,
      reason:
          'the fallback status-flip and _syncCreateSession must never each '
          'generate their own key - exactly one candidate for one logical '
          'operation',
    );

    final after = await reload(row.localId);
    expect(after!.syncStatus, 'synced');
    expect(after.clientOperationId, isNotNull);

    final body = await capturedLastPostBody();
    expect(body['clientOperationId'], after.clientOperationId);
  });

  group('8/9/10. 200 replay convergence', () {
    test('8/9/10. a 200 replay converges the SAME row by localId, its '
        'canonical body wins over a differing retry payload, and no second '
        'row is inserted', () async {
      final row = await insertPendingCreateSession(name: 'Original name');
      // The server's canonical replay response differs from what THIS
      // client attempt would have sent (name changed elsewhere by the
      // first, already-committed keyed request).
      stubPostReturn(serverSessionJson(id: 600, name: 'Canonical server name'));

      await syncService.sync();

      final rows =
          await isar.localSessions.filter().userIdEqualTo(userId).findAll();
      expect(rows, hasLength(1));
      expect(rows.single.localId, row.localId);
      expect(rows.single.name, 'Canonical server name');
      expect(rows.single.serverId, 600);
      expect(rows.single.syncStatus, 'synced');
    });
  });

  group('24/25/26. structured soft outcomes reuse the identical key', () {
    const recognizedPairs = <({int status, String? code})>[
      (status: 429, code: null),
      (status: 404, code: 'program_not_found'),
      (status: 409, code: 'operation_canceled'),
      (status: 409, code: 'operation_incomplete'),
      (status: 410, code: 'operation_target_deleted'),
    ];

    for (final p in recognizedPairs) {
      test('${p.status} ${p.code ?? '(throttled)'} preserves the key across a '
          'later successful retry', () async {
        final row = await insertPendingCreateSession();
        stubPostThrow(
          apiError(p.status, body: p.code == null ? null : {'code': p.code}),
        );

        await syncService.sync();

        final afterFailure = await reload(row.localId);
        expect(afterFailure!.syncStatus, 'pending_create');
        expect(afterFailure.clientOperationId, isNotNull);
        final keyAfterFailure = afterFailure.clientOperationId;

        stubPostReturn(serverSessionJson(id: 700 + p.status));
        await syncService.sync();

        final body = await capturedLastPostBody();
        expect(body['clientOperationId'], keyAfterFailure);
        final afterSuccess = await reload(row.localId);
        expect(afterSuccess!.syncStatus, 'synced');
        expect(afterSuccess.clientOperationId, keyAfterFailure);
      });
    }

    test('26. a 5xx / ordinary transport failure preserves and reuses the key '
        'as well', () async {
      final row = await insertPendingCreateSession();
      stubPostThrow(apiError(500));

      await syncService.sync();
      final afterFailure = await reload(row.localId);
      expect(afterFailure!.clientOperationId, isNotNull);

      stubPostReturn(serverSessionJson(id: 800));
      await syncService.sync();

      final body = await capturedLastPostBody();
      expect(body['clientOperationId'], afterFailure.clientOperationId);
    });
  });

  test('20/21/22/23. a stale (superseded-epoch) pass writes no key and no '
      'acknowledgment', () async {
    final row = await insertPendingCreateSession();
    stubPostReturn(serverSessionJson(id: 900));

    // Invalidate the epoch mid-flight via the pre-write-txn test hook so
    // the guarded key-assignment transaction's context check fires.
    syncService.beforeCreateOperationKeyWriteTxnForTesting = () async {
      sessionEpoch.invalidate();
    };

    await syncService.sync();

    final after = await reload(row.localId);
    expect(after!.clientOperationId, isNull);
    expect(after.syncStatus, 'pending_create');
    verifyNever(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    );
  });
}
