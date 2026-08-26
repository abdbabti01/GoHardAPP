import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'session_repository_conflict_test.mocks.dart';

@GenerateMocks([ApiService, AuthService])
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late SessionRepository repository;

  const userId = 1;
  const serverId = 100;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_repo_conflict_');
    isar = await Isar.open(
      [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
    );

    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userId);

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    repository = SessionRepository(
      mockApiService,
      localDb,
      ConnectivityService.instance,
      mockAuthService,
    );
  });

  tearDown(() async {
    SyncService.reset();
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LocalSession> insertSession({
    required String syncStatus,
    bool isSynced = false,
    int? version = 5,
    String? conflictServerSnapshotJson,
    int? conflictServerVersion,
    DateTime? conflictDetectedAt,
    String name = 'Original name',
    String status = 'in_progress',
  }) async {
    final session = LocalSession(
      serverId: serverId,
      userId: userId,
      date: DateTime(2024, 1, 15),
      name: name,
      status: status,
      isSynced: isSynced,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now().toUtc(),
      version: version,
      conflictServerSnapshotJson: conflictServerSnapshotJson,
      conflictServerVersion: conflictServerVersion,
      conflictDetectedAt: conflictDetectedAt,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<LocalSession> storedSession() async {
    final s =
        await isar.localSessions.filter().serverIdEqualTo(serverId).findFirst();
    expect(s, isNotNull, reason: 'session $serverId should still exist');
    return s!;
  }

  Map<String, dynamic> serverSessionJson({int version = 6, String name = 'x'}) {
    return {
      'id': serverId,
      'userId': userId,
      'date': '2024-01-15',
      'duration': null,
      'notes': null,
      'type': null,
      'name': name,
      'status': 'in_progress',
      'startedAt': null,
      'completedAt': null,
      'pausedAt': null,
      'exercises': [],
      'programId': null,
      'programWorkoutId': null,
      'version': version,
    };
  }

  group('Conflict invariant - rename', () {
    test(
      'renaming a conflicted session changes the name but preserves conflict state and never PUTs',
      () async {
        final detectedAt = DateTime.utc(2024, 1, 1, 12);
        await insertSession(
          syncStatus: 'conflict',
          conflictServerSnapshotJson: '{"name":"Server name"}',
          conflictServerVersion: 9,
          conflictDetectedAt: detectedAt,
          name: 'My local name',
        );

        await repository.updateSessionName(serverId, 'Renamed locally');

        final stored = await storedSession();
        expect(stored.name, 'Renamed locally');
        expect(stored.syncStatus, 'conflict');
        expect(stored.isSynced, false);
        expect(stored.conflictServerSnapshotJson, '{"name":"Server name"}');
        expect(stored.conflictServerVersion, 9);
        // Isar round-trips DateTime by instant but drops the UTC flag, so
        // compare moments rather than exact DateTime equality.
        expect(stored.conflictDetectedAt!.isAtSameMomentAs(detectedAt), true);
        verifyNever(mockApiService.put<dynamic>(any, data: anyNamed('data')));
      },
    );
  });

  group('Conflict invariant - date edit', () {
    test(
      'editing the date of a conflicted session changes the date but preserves conflict state and never PUTs',
      () async {
        final detectedAt = DateTime.utc(2024, 1, 1, 12);
        await insertSession(
          syncStatus: 'conflict',
          conflictServerSnapshotJson: '{"date":"2024-02-01"}',
          conflictServerVersion: 4,
          conflictDetectedAt: detectedAt,
        );

        await repository.updateWorkoutDate(serverId, DateTime(2024, 3, 1));

        final stored = await storedSession();
        expect(stored.date, DateTime(2024, 3, 1));
        expect(stored.syncStatus, 'conflict');
        expect(stored.isSynced, false);
        expect(stored.conflictServerSnapshotJson, '{"date":"2024-02-01"}');
        expect(stored.conflictServerVersion, 4);
        // Isar round-trips DateTime by instant but drops the UTC flag, so
        // compare moments rather than exact DateTime equality.
        expect(stored.conflictDetectedAt!.isAtSameMomentAs(detectedAt), true);
        verifyNever(mockApiService.put<dynamic>(any, data: anyNamed('data')));
      },
    );
  });

  group('Conflict invariant - every other mutation path', () {
    test(
      'pauseSession on a conflicted session applies the pause but preserves conflict and never syncs',
      () async {
        final detectedAt = DateTime.utc(2024, 1, 1);
        await insertSession(
          syncStatus: 'conflict',
          conflictServerSnapshotJson: '{}',
          conflictServerVersion: 2,
          conflictDetectedAt: detectedAt,
          status: 'in_progress',
        );

        await repository.pauseSession(serverId, DateTime.utc(2024, 1, 2));

        final stored = await storedSession();
        expect(
          stored.pausedAt!.isAtSameMomentAs(DateTime.utc(2024, 1, 2)),
          true,
        );
        expect(stored.syncStatus, 'conflict');
        expect(stored.isSynced, false);
        expect(stored.conflictServerVersion, 2);
        // Isar round-trips DateTime by instant but drops the UTC flag, so
        // compare moments rather than exact DateTime equality.
        expect(stored.conflictDetectedAt!.isAtSameMomentAs(detectedAt), true);
        verifyNever(mockApiService.patch<void>(any, data: anyNamed('data')));
      },
    );

    test(
      'resumeSession on a conflicted session applies the resume but preserves conflict and never syncs',
      () async {
        final detectedAt = DateTime.utc(2024, 1, 1);
        await insertSession(
          syncStatus: 'conflict',
          conflictServerSnapshotJson: '{}',
          conflictServerVersion: 2,
          conflictDetectedAt: detectedAt,
          status: 'in_progress',
        );

        await repository.resumeSession(serverId, DateTime.utc(2024, 1, 3));

        final stored = await storedSession();
        expect(
          stored.startedAt!.isAtSameMomentAs(DateTime.utc(2024, 1, 3)),
          true,
        );
        expect(stored.pausedAt, isNull);
        expect(stored.syncStatus, 'conflict');
        expect(stored.isSynced, false);
        expect(stored.conflictServerVersion, 2);
        // Isar round-trips DateTime by instant but drops the UTC flag, so
        // compare moments rather than exact DateTime equality.
        expect(stored.conflictDetectedAt!.isAtSameMomentAs(detectedAt), true);
        verifyNever(mockApiService.patch<void>(any, data: anyNamed('data')));
      },
    );

    test(
      'updateSessionStatus on a conflicted session applies the status but preserves conflict and never syncs',
      () async {
        final detectedAt = DateTime.utc(2024, 1, 1);
        await insertSession(
          syncStatus: 'conflict',
          conflictServerSnapshotJson: '{}',
          conflictServerVersion: 2,
          conflictDetectedAt: detectedAt,
          status: 'draft',
        );

        await repository.updateSessionStatus(serverId, 'in_progress');

        final stored = await storedSession();
        expect(stored.status, 'in_progress');
        expect(stored.syncStatus, 'conflict');
        expect(stored.isSynced, false);
        expect(stored.conflictServerVersion, 2);
        // Isar round-trips DateTime by instant but drops the UTC flag, so
        // compare moments rather than exact DateTime equality.
        expect(stored.conflictDetectedAt!.isAtSameMomentAs(detectedAt), true);
        verifyNever(mockApiService.patch<void>(any, data: anyNamed('data')));
      },
    );

    test(
      'archiveSession on a conflicted session applies the archive but preserves conflict',
      () async {
        final detectedAt = DateTime.utc(2024, 1, 1);
        await insertSession(
          syncStatus: 'conflict',
          conflictServerSnapshotJson: '{}',
          conflictServerVersion: 2,
          conflictDetectedAt: detectedAt,
          status: 'draft',
        );

        await repository.archiveSession(serverId);

        final stored = await storedSession();
        expect(stored.status, 'archived');
        expect(stored.syncStatus, 'conflict');
        expect(stored.isSynced, false);
        expect(stored.conflictServerVersion, 2);
        // Isar round-trips DateTime by instant but drops the UTC flag, so
        // compare moments rather than exact DateTime equality.
        expect(stored.conflictDetectedAt!.isAtSameMomentAs(detectedAt), true);
        verifyNever(mockApiService.put<dynamic>(any, data: anyNamed('data')));
        verifyNever(mockApiService.patch<void>(any, data: anyNamed('data')));
      },
    );
  });

  group('Non-conflict rows keep normal synchronization behavior', () {
    test(
      'renaming a normal synced session sets pending_update and pushes',
      () async {
        when(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        ).thenAnswer(
          (_) async => serverSessionJson(version: 6, name: 'Renamed'),
        );
        await insertSession(syncStatus: 'synced', isSynced: true, version: 5);

        await repository.updateSessionName(serverId, 'Renamed');

        // The local write is synchronous with the call above; syncStatus
        // flips to pending_update immediately.
        final justEdited = await storedSession();
        expect(justEdited.name, 'Renamed');
        expect(justEdited.syncStatus, 'pending_update');
        expect(justEdited.isSynced, false);

        // The background push (fire-and-forget) should still fire.
        await untilCalled(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        );
        verify(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        ).called(1);
      },
    );

    test(
      'renaming an already pending_update session stays pending_update and pushes again',
      () async {
        when(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        ).thenAnswer((_) async => null);
        when(mockApiService.get<Map<String, dynamic>>(any)).thenAnswer(
          (_) async => serverSessionJson(version: 6, name: 'Renamed again'),
        );
        await insertSession(
          syncStatus: 'pending_update',
          isSynced: false,
          version: 5,
        );

        await repository.updateSessionName(serverId, 'Renamed again');

        final justEdited = await storedSession();
        expect(justEdited.name, 'Renamed again');
        expect(justEdited.syncStatus, 'pending_update');
        expect(justEdited.isSynced, false);

        await untilCalled(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        );
        verify(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        ).called(1);
      },
    );
  });

  group('Conflict rows stay excluded from periodic sync after local edits', () {
    test(
      'a conflict row edited locally is still excluded from SyncService.sync()',
      () async {
        final detectedAt = DateTime.utc(2024, 1, 1);
        await insertSession(
          syncStatus: 'conflict',
          conflictServerSnapshotJson: '{}',
          conflictServerVersion: 2,
          conflictDetectedAt: detectedAt,
        );

        await repository.updateSessionName(serverId, 'Edited while conflicted');

        SyncService.reset();
        final syncService = SyncService(
          apiService: mockApiService,
          authService: mockAuthService,
          localDb: localDb,
          connectivity: ConnectivityService.instance,
        );

        await syncService.sync();

        verifyNever(mockApiService.put<dynamic>(any, data: anyNamed('data')));

        final stored = await storedSession();
        expect(stored.name, 'Edited while conflicted');
        expect(stored.syncStatus, 'conflict');
        expect(stored.conflictServerVersion, 2);
        // Isar round-trips DateTime by instant but drops the UTC flag, so
        // compare moments rather than exact DateTime equality.
        expect(stored.conflictDetectedAt!.isAtSameMomentAs(detectedAt), true);
      },
    );
  });
}
