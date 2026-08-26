import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/session_update_sync_helper.dart';

import 'session_update_sync_helper_test.mocks.dart';

@GenerateMocks([ApiService])
void main() {
  late Isar isar;
  late MockApiService mockApiService;
  late Directory tempDir;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_sync_helper_');
    isar = await Isar.open(
      [LocalSessionSchema],
      directory: tempDir.path,
      inspector: false,
    );
    mockApiService = MockApiService();
  });

  tearDown(() async {
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LocalSession> insertSession({
    int serverId = 100,
    int? version = 3,
    String syncStatus = 'pending_update',
    String name = 'Local edit',
  }) async {
    final session = LocalSession(
      serverId: serverId,
      userId: 1,
      date: DateTime(2024, 1, 15),
      name: name,
      status: 'in_progress',
      isSynced: false,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now().toUtc(),
      version: version,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Map<String, dynamic> serverSessionJson({
    int id = 100,
    int version = 4,
    String name = 'Server name',
  }) {
    return {
      'id': id,
      'userId': 1,
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

  group('SessionUpdateSyncHelper - outgoing payload', () {
    test('sends the persisted version, not a guessed one', () async {
      final session = await insertSession(version: 7);
      when(mockApiService.put<dynamic>(any, data: anyNamed('data'))).thenAnswer(
        (invocation) async {
          final body = invocation.namedArguments[#data] as Map<String, dynamic>;
          expect(body['version'], 7);
          expect(body.containsKey('id'), false);
          expect(body.containsKey('userId'), false);
          return serverSessionJson(version: 8);
        },
      );

      final outcome = await SessionUpdateSyncHelper(
        mockApiService,
      ).pushUpdate(isar, session);

      expect(outcome, SessionSyncOutcome.synced);
    });

    test(
      'sends null version for a row that never learned its version',
      () async {
        final session = await insertSession(version: null);
        when(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        ).thenAnswer((invocation) async {
          final body = invocation.namedArguments[#data] as Map<String, dynamic>;
          expect(body['version'], isNull);
          return serverSessionJson(version: 1);
        });

        await SessionUpdateSyncHelper(mockApiService).pushUpdate(isar, session);
      },
    );
  });

  group('SessionUpdateSyncHelper - successful response', () {
    test('200 response persists the returned incremented version', () async {
      final session = await insertSession(version: 3);
      when(
        mockApiService.put<dynamic>(any, data: anyNamed('data')),
      ).thenAnswer((_) async => serverSessionJson(version: 4));

      final outcome = await SessionUpdateSyncHelper(
        mockApiService,
      ).pushUpdate(isar, session);

      expect(outcome, SessionSyncOutcome.synced);
      final stored = await isar.localSessions.get(session.localId);
      expect(stored!.version, 4);
      expect(stored.isSynced, true);
      expect(stored.syncStatus, 'synced');
    });

    test(
      'empty/204 success body recovers authoritative state via GET',
      () async {
        final session = await insertSession(version: 3);
        when(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        ).thenAnswer((_) async => null);
        when(
          mockApiService.get<Map<String, dynamic>>(any),
        ).thenAnswer((_) async => serverSessionJson(version: 5));

        final outcome = await SessionUpdateSyncHelper(
          mockApiService,
        ).pushUpdate(isar, session);

        expect(outcome, SessionSyncOutcome.synced);
        final stored = await isar.localSessions.get(session.localId);
        expect(stored!.version, 5);
        expect(stored.isSynced, true);
      },
    );

    test('failed rollback recovery leaves the pending edit unsynced', () async {
      final session = await insertSession(version: 3, name: 'Mine');
      when(
        mockApiService.put<dynamic>(any, data: anyNamed('data')),
      ).thenAnswer((_) async => null);
      when(
        mockApiService.get<Map<String, dynamic>>(any),
      ).thenThrow(ApiException('Network error - cannot connect to server'));

      final outcome = await SessionUpdateSyncHelper(
        mockApiService,
      ).pushUpdate(isar, session);

      expect(outcome, SessionSyncOutcome.deferred);
      final stored = await isar.localSessions.get(session.localId);
      expect(stored!.isSynced, false);
      expect(stored.name, 'Mine');
      expect(stored.version, 3);
    });
  });

  group('SessionUpdateSyncHelper - 409 conflict handling', () {
    test('well-formed 409 stores local data and server snapshot', () async {
      final session = await insertSession(version: 3, name: 'My local edit');
      final serverSnapshot = serverSessionJson(
        version: 9,
        name: 'Someone else',
      );

      when(mockApiService.put<dynamic>(any, data: anyNamed('data'))).thenThrow(
        ApiException(
          'Conflict',
          statusCode: 409,
          responseData: {
            'message': 'Conflict',
            'currentVersion': 9,
            'serverData': serverSnapshot,
          },
        ),
      );

      final outcome = await SessionUpdateSyncHelper(
        mockApiService,
      ).pushUpdate(isar, session);

      expect(outcome, SessionSyncOutcome.conflict);
      final stored = await isar.localSessions.get(session.localId);
      // Local mutable data must be preserved, not overwritten by the server.
      expect(stored!.name, 'My local edit');
      expect(stored.syncStatus, 'conflict');
      expect(stored.isSynced, false);
      expect(stored.conflictServerVersion, 9);
      expect(stored.conflictServerSnapshotJson, isNotNull);
      expect(stored.conflictServerSnapshotJson, contains('Someone else'));
      expect(stored.conflictDetectedAt, isNotNull);
    });

    test(
      'malformed 409 payload preserves the pending row without overwriting it',
      () async {
        final session = await insertSession(version: 3, name: 'My local edit');

        when(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        ).thenThrow(
          ApiException(
            'Conflict',
            statusCode: 409,
            responseData: {
              'message': 'Conflict',
            }, // missing serverData/currentVersion
          ),
        );

        final outcome = await SessionUpdateSyncHelper(
          mockApiService,
        ).pushUpdate(isar, session);

        expect(outcome, SessionSyncOutcome.conflictDataInvalid);
        final stored = await isar.localSessions.get(session.localId);
        expect(stored!.name, 'My local edit');
        expect(stored.syncStatus, 'pending_update');
        expect(stored.conflictServerSnapshotJson, isNull);
        expect(stored.syncError, isNotNull);
      },
    );

    test('non-409 errors propagate instead of being swallowed', () async {
      final session = await insertSession();
      when(
        mockApiService.put<dynamic>(any, data: anyNamed('data')),
      ).thenThrow(ApiException('Server error: boom', statusCode: 500));

      expect(
        () => SessionUpdateSyncHelper(mockApiService).pushUpdate(isar, session),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
