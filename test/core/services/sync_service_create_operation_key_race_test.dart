import 'dart:io';

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

import 'sync_service_test.mocks.dart';

/// CORRECTION CAMPAIGN (separate from the original durable-key feature's
/// mutation/test campaign): deterministic coverage that the
/// `_ensureCreateOperationKey` / `_syncCreateSession` boundary can NEVER fall
/// back to a stale batch snapshot and dispatch an unkeyed generic
/// `POST /api/v1/sessions`.
///
/// The architecture-review finding this fixes: `_syncSessions` reads a
/// `pending_create` batch snapshot; before `_ensureCreateOperationKey`
/// finishes for a given row, another path can acknowledge, transition, or
/// delete that exact row; the old code let `_syncCreateSession` fall back to
/// the stale snapshot and dispatch anyway - possibly unkeyed, possibly
/// duplicating a Session if the other path's own POST already committed.
///
/// Every race here is landed deterministically via
/// `beforeCreateOperationKeyPreCheckForTesting` (fires before
/// `_ensureCreateOperationKey`'s very first read) or
/// `beforeCreateOperationKeyWriteTxnForTesting` (fires after candidate
/// generation, before its guarded write transaction) - never a wall-clock
/// wait, `Future.delayed`, or polling loop.
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
  const otherUserId = 2;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('opkey_race_');
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
  }) async {
    final session = LocalSession(
      serverId: null,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: name,
      status: 'draft',
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
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

  void stubPostReturn(Map<String, dynamic> response) {
    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => response);
  }

  // Mockito's verify() consumes/marks matched invocations - call this ONCE
  // per test and read both the count and the bodies off the single result,
  // never call verify() a second time against the same invocations.
  List<Map<String, dynamic>> capturedPostBodies() {
    final captured =
        verify(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: captureAnyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).captured;
    return captured.cast<Map<String, dynamic>>();
  }

  Future<LocalSession?> reload(int localId) => isar.localSessions.get(localId);

  test('1. row acknowledged to synced by another path before key assurance '
      'continues -> zero POSTs, row untouched', () async {
    final row = await insertPendingCreateSession();
    stubPostReturn(serverSessionJson(id: 900));

    syncService.beforeCreateOperationKeyPreCheckForTesting = () async {
      await isar.writeTxn(() async {
        final current = (await isar.localSessions.get(row.localId))!;
        current.serverId = 999;
        current.syncStatus = 'synced';
        current.isSynced = true;
        current.clientOperationId = 'already-acknowledged-key';
        await isar.localSessions.put(current);
      });
    };

    await syncService.sync();

    verifyNever(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    );
    final after = await reload(row.localId);
    expect(after!.syncStatus, 'synced');
    expect(after.serverId, 999);
    expect(after.clientOperationId, 'already-acknowledged-key');
  });

  test('2. row transitions to pending_update before key assurance continues -> '
      'zero CREATE POSTs', () async {
    final row = await insertPendingCreateSession();
    stubPostReturn(serverSessionJson(id: 901));

    syncService.beforeCreateOperationKeyPreCheckForTesting = () async {
      await isar.writeTxn(() async {
        final current = (await isar.localSessions.get(row.localId))!;
        current.serverId = 501;
        current.syncStatus = 'pending_update';
        await isar.localSessions.put(current);
      });
    };

    await syncService.sync();

    verifyNever(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    );
  });

  test('3. row transitions to pending_delete before key assurance continues -> '
      'zero CREATE POSTs', () async {
    final row = await insertPendingCreateSession();
    stubPostReturn(serverSessionJson(id: 902));

    syncService.beforeCreateOperationKeyPreCheckForTesting = () async {
      await isar.writeTxn(() async {
        final current = (await isar.localSessions.get(row.localId))!;
        current.syncStatus = 'pending_delete';
        await isar.localSessions.put(current);
      });
    };

    await syncService.sync();

    verifyNever(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    );
  });

  test('4. row deleted before key assurance continues -> zero POSTs and no '
      'resurrection', () async {
    final row = await insertPendingCreateSession();
    stubPostReturn(serverSessionJson(id: 903));

    syncService.beforeCreateOperationKeyPreCheckForTesting = () async {
      await isar.writeTxn(() => isar.localSessions.delete(row.localId));
    };

    await syncService.sync();

    verifyNever(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    );
    expect(
      await reload(row.localId),
      isNull,
      reason: 'the row must not be resurrected by the aborted CREATE pass',
    );
  });

  test('5. ownership changes (row reassigned to a different user) before key '
      'assurance continues -> zero POSTs', () async {
    final row = await insertPendingCreateSession();
    stubPostReturn(serverSessionJson(id: 904));

    syncService.beforeCreateOperationKeyPreCheckForTesting = () async {
      await isar.writeTxn(() async {
        final current = (await isar.localSessions.get(row.localId))!;
        current.userId = otherUserId;
        await isar.localSessions.put(current);
      });
    };

    await syncService.sync();

    verifyNever(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    );
    final after = await reload(row.localId);
    expect(after!.userId, otherUserId);
    expect(
      after.clientOperationId,
      isNull,
      reason: 'a foreign-owned row must never be keyed by this session',
    );
  });

  test('6. epoch invalidates before key assurance continues -> typed lifecycle '
      'termination swallowed by sync(), zero POSTs', () async {
    final row = await insertPendingCreateSession();
    stubPostReturn(serverSessionJson(id: 905));

    syncService.beforeCreateOperationKeyPreCheckForTesting = () async {
      sessionEpoch.invalidate();
    };

    // sync() must complete without throwing to the caller - lifecycle
    // termination is swallowed exactly like every other expected abort.
    await syncService.sync();

    verifyNever(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    );
    final after = await reload(row.localId);
    expect(after!.syncStatus, 'pending_create');
    expect(after.clientOperationId, isNull);
  });

  test(
    '6b. epoch invalidates for an ALREADY-KEYED row -> the typed lifecycle '
    'exception must propagate and block dispatch, not be caught and '
    'continue (isolates exception-propagation from the separate '
    'unkeyed-body guard, which an already-keyed row would not trip)',
    () async {
      final row = await insertPendingCreateSession(
        clientOperationId: 'already-persisted-key',
      );
      stubPostReturn(serverSessionJson(id: 911));

      syncService.beforeCreateOperationKeyPreCheckForTesting = () async {
        sessionEpoch.invalidate();
      };

      await syncService.sync();

      verifyNever(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      final after = await reload(row.localId);
      expect(after!.syncStatus, 'pending_create');
      expect(after.clientOperationId, 'already-persisted-key');
    },
  );

  test('7. row remains eligible (no race) -> exactly one keyed POST using the '
      'canonical stored key', () async {
    final row = await insertPendingCreateSession();
    stubPostReturn(serverSessionJson(id: 906));

    await syncService.sync();

    final bodies = capturedPostBodies();
    expect(bodies, hasLength(1));
    final after = await reload(row.localId);
    expect(after!.syncStatus, 'synced');
    expect(after.clientOperationId, isNotNull);
    expect(bodies.single['clientOperationId'], after.clientOperationId);
  });

  test('7b. the dispatched body reflects the CANONICAL row re-read by '
      'assurance, not the stale batch snapshot - a field changed between the '
      'batch read and assurance is what actually gets sent', () async {
    final row = await insertPendingCreateSession(name: 'Stale name');
    stubPostReturn(serverSessionJson(id: 910, name: 'Fresh name'));

    // Lands exactly at "before key assurance begins" - the row's content
    // changes here, AFTER _syncSessions' batch read already captured the
    // stale `localSession` snapshot with the OLD name.
    syncService.beforeCreateOperationKeyPreCheckForTesting = () async {
      await isar.writeTxn(() async {
        final current = (await isar.localSessions.get(row.localId))!;
        current.name = 'Fresh name';
        await isar.localSessions.put(current);
      });
    };

    await syncService.sync();

    final bodies = capturedPostBodies();
    expect(bodies, hasLength(1));
    expect(
      bodies.single['name'],
      'Fresh name',
      reason:
          'dispatch must use the canonical re-read row, never the '
          'stale pre-assurance snapshot, for ANY field - not just the key',
    );
  });

  test(
    '8. a concurrent candidate collision during assurance never produces two '
    'different keys - every POST that occurs carries the same non-null key',
    () async {
      final row = await insertPendingCreateSession();
      stubPostReturn(serverSessionJson(id: 907));

      syncService.beforeCreateOperationKeyWriteTxnForTesting = () async {
        await isar.writeTxn(() async {
          final current = await isar.localSessions.get(row.localId);
          if (current != null && current.clientOperationId == null) {
            current.clientOperationId = 'concurrent-winner-key';
            await isar.localSessions.put(current);
          }
        });
      };

      await syncService.sync();

      final bodies = capturedPostBodies();
      expect(bodies, hasLength(1));
      expect(bodies.single['clientOperationId'], 'concurrent-winner-key');
      final after = await reload(row.localId);
      expect(after!.clientOperationId, 'concurrent-winner-key');
    },
  );

  test('9. the no-serverId UPDATE fallback still reaches the eligible keyed '
      'path under the corrected contract', () async {
    final row = LocalSession(
      serverId: null,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: 'Fallback',
      status: 'draft',
      isSynced: false,
      syncStatus: 'pending_update',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localSessions.put(row));
    stubPostReturn(serverSessionJson(id: 908, name: 'Fallback'));

    await syncService.sync();

    final bodies = capturedPostBodies();
    expect(bodies, hasLength(1));
    final after = await reload(row.localId);
    expect(after!.syncStatus, 'synced');
    expect(after.clientOperationId, isNotNull);
    expect(bodies.single['clientOperationId'], after.clientOperationId);
  });

  test('10. existing 200/201 acknowledgment convergence is unchanged under the '
      'corrected contract - both accepted identically, one row, canonical '
      'server body wins', () async {
    await insertPendingCreateSession(name: 'Original');
    stubPostReturn(serverSessionJson(id: 909, name: 'Canonical from server'));

    await syncService.sync();

    final rows =
        await isar.localSessions.filter().userIdEqualTo(userId).findAll();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Canonical from server');
    expect(rows.single.serverId, 909);
    expect(rows.single.syncStatus, 'synced');
  });
}
