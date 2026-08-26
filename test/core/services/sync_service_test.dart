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
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'sync_service_test.mocks.dart';

@GenerateMocks([ApiService, AuthService])
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late SyncService syncService;

  const userId = 1;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_service_test_');
    // Session deletion cascades into exercises/sets, so those schemas must
    // be registered too. Every other collection SyncService.sync() touches
    // (programs, goals, nutrition, ...) throws on a not-registered schema,
    // but the outer sync() wraps everything in a single try/catch that
    // just logs it - that happens after the session-sync assertions below
    // have already completed, so it doesn't affect them.
    isar = await Isar.open(
      [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
    );

    SyncService.reset();
    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userId);

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    syncService = SyncService(
      apiService: mockApiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: ConnectivityService.instance,
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
    int? serverId,
    int? version,
    required String syncStatus,
    bool isSynced = false,
    String name = 'Session',
  }) async {
    final session = LocalSession(
      serverId: serverId,
      userId: userId,
      date: DateTime(2024, 1, 15),
      name: name,
      status: 'in_progress',
      isSynced: isSynced,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now().toUtc(),
      version: version,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Map<String, dynamic> serverSessionJson({
    int id = 100,
    int version = 2,
    String name = 'Server session',
    String date = '2024-01-15',
  }) {
    return {
      'id': id,
      'userId': userId,
      'date': date,
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

  group('SyncService - conflict rows excluded from automatic retries', () {
    test('a conflict row is never PUT again by sync()', () async {
      await insertSession(
        serverId: 100,
        version: 5,
        syncStatus: 'conflict',
        name: 'Conflicted',
      );

      await syncService.sync();

      verifyNever(mockApiService.put<dynamic>(any, data: anyNamed('data')));
    });
  });

  group('SyncService - version reconciliation for upgraded installations', () {
    test('clean version-null rows hydrate safely from the server', () async {
      final session = await insertSession(
        serverId: 100,
        version: null,
        syncStatus: 'synced',
        isSynced: true,
        name: 'Old clean row',
      );
      when(mockApiService.get<Map<String, dynamic>>(any)).thenAnswer(
        (_) async => serverSessionJson(version: 3, name: 'From server'),
      );

      await syncService.sync();

      final stored = await isar.localSessions.get(session.localId);
      expect(stored!.version, 3);
      expect(stored.name, 'From server');
      expect(stored.isSynced, true);
      expect(stored.syncStatus, 'synced');
    });

    test('reconciliation is idempotent: a second sync() does not re-GET or '
        'mutate an already-hydrated row', () async {
      final session = await insertSession(
        serverId: 100,
        version: null,
        syncStatus: 'synced',
        isSynced: true,
        name: 'Old clean row',
      );
      when(mockApiService.get<Map<String, dynamic>>(any)).thenAnswer(
        (_) async => serverSessionJson(version: 3, name: 'From server'),
      );

      await syncService.sync();

      final afterFirst = await isar.localSessions.get(session.localId);
      expect(afterFirst!.version, 3);
      expect(afterFirst.name, 'From server');
      expect(afterFirst.isSynced, true);
      expect(afterFirst.syncStatus, 'synced');
      verify(mockApiService.get<Map<String, dynamic>>(any)).called(1);

      await syncService.sync();

      // The row now has a non-null version, so the versionIsNull() filter
      // excludes it from reconciliation on the second pass - no second
      // GET, and the hydrated row is untouched.
      verifyNever(mockApiService.get<Map<String, dynamic>>(any));
      verifyNever(mockApiService.put<dynamic>(any, data: anyNamed('data')));
      verifyNever(mockApiService.patch<void>(any, data: anyNamed('data')));

      final afterSecond = await isar.localSessions.get(session.localId);
      expect(afterSecond!.version, 3);
      expect(afterSecond.name, 'From server');
      expect(afterSecond.isSynced, true);
      expect(afterSecond.syncStatus, 'synced');
      expect(
        afterSecond.lastModifiedServer!.isAtSameMomentAs(
          afterFirst.lastModifiedServer!,
        ),
        true,
      );
    });

    test(
      'pending-update version-null rows become a conflict without losing local data',
      () async {
        final session = await insertSession(
          serverId: 100,
          version: null,
          syncStatus: 'pending_update',
          name: 'My unsynced edit',
        );
        when(mockApiService.get<Map<String, dynamic>>(any)).thenAnswer(
          (_) async => serverSessionJson(version: 4, name: 'Someone else edit'),
        );

        await syncService.sync();

        final stored = await isar.localSessions.get(session.localId);
        // Local edit must never be silently overwritten.
        expect(stored!.name, 'My unsynced edit');
        expect(stored.syncStatus, 'conflict');
        expect(stored.conflictServerVersion, 4);
        expect(
          stored.conflictServerSnapshotJson,
          contains('Someone else edit'),
        );
        // The row must never have been PUT with a guessed version.
        verifyNever(mockApiService.put<dynamic>(any, data: anyNamed('data')));
      },
    );

    test('pending-delete rows are left untouched by reconciliation', () async {
      final session = await insertSession(
        serverId: 100,
        version: null,
        syncStatus: 'pending_delete',
        name: 'To delete',
      );
      when(
        mockApiService.delete(any, data: anyNamed('data')),
      ).thenAnswer((_) async => true);

      await syncService.sync();

      // Reconciliation must not have hydrated or converted this row - it
      // should proceed through the normal delete path and be removed.
      final stored = await isar.localSessions.get(session.localId);
      expect(stored, isNull);
      verifyNever(mockApiService.get<Map<String, dynamic>>(any));
    });

    test(
      'pending-create rows (no serverId) stay pending-create until POST succeeds',
      () async {
        await insertSession(
          serverId: null,
          version: null,
          syncStatus: 'pending_create',
          name: 'Brand new',
        );
        when(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
          ),
        ).thenThrow(ApiException('Network error - cannot connect to server'));

        await syncService.sync();

        final all = await isar.localSessions.where().findAll();
        expect(all, hasLength(1));
        expect(all.first.syncStatus, 'pending_create');
        expect(all.first.serverId, isNull);
        verifyNever(mockApiService.get<Map<String, dynamic>>(any));
      },
    );

    test(
      'a failed reconciliation GET preserves the original row and status',
      () async {
        final session = await insertSession(
          serverId: 100,
          version: null,
          syncStatus: 'pending_update',
          name: 'Still mine',
        );
        when(
          mockApiService.get<Map<String, dynamic>>(any),
        ).thenThrow(ApiException('Network error - cannot connect to server'));
        // Reconciliation leaves this row as pending_update, so the normal
        // pending-sync loop will also attempt a PUT on it in the same
        // sync() call; make that fail too rather than leaving it unstubbed.
        when(
          mockApiService.put<dynamic>(any, data: anyNamed('data')),
        ).thenThrow(ApiException('Network error - cannot connect to server'));

        await syncService.sync();

        final stored = await isar.localSessions.get(session.localId);
        expect(stored!.name, 'Still mine');
        expect(stored.syncStatus, 'pending_update');
        expect(stored.version, isNull);
        expect(stored.conflictServerSnapshotJson, isNull);
      },
    );
  });

  group(
    'SyncService - creation and update no longer use Session.date as a timestamp',
    () {
      test(
        'successful create does not derive lastModifiedServer from date',
        () async {
          final session = await insertSession(
            serverId: null,
            version: null,
            syncStatus: 'pending_create',
          );
          when(
            mockApiService.post<Map<String, dynamic>>(
              any,
              data: anyNamed('data'),
            ),
          ).thenAnswer(
            (_) async =>
                serverSessionJson(id: 200, version: 1, date: '2024-01-15'),
          );

          final before = DateTime.now().toUtc();
          await syncService.sync();
          final after = DateTime.now().toUtc();

          final stored = await isar.localSessions.get(session.localId);
          expect(stored!.serverId, 200);
          expect(stored.version, 1);
          // lastModifiedServer must reflect wall-clock sync time, not a parse
          // of the session's `date` field.
          expect(
            stored.lastModifiedServer!.isAfter(
              before.subtract(const Duration(seconds: 1)),
            ),
            true,
          );
          expect(
            stored.lastModifiedServer!.isBefore(
              after.add(const Duration(seconds: 1)),
            ),
            true,
          );
        },
      );
    },
  );

  group('SyncService - offline-created session timestamps survive sync '
      '(regression: absolute instant must be preserved)', () {
    test('a session created, started and paused entirely offline sends the '
        'correct absolute-instant timestamps on first sync, not shifted by '
        'the local timezone', () async {
      // These simulate a workout that was created, started, and paused
      // while offline: the row is written directly to Isar and never
      // touched again until sync() reads it fresh (Isar returns
      // DateTime fields local-flagged but instant-correct - see
      // model_mapper_isar_roundtrip_test.dart - which is exactly what
      // _syncCreateSession must handle correctly).
      final startedAtUtc = DateTime.utc(2024, 1, 15, 10, 0, 0);
      final pausedAtUtc = DateTime.utc(2024, 1, 15, 10, 30, 0);

      await isar.writeTxn(
        () => isar.localSessions.put(
          LocalSession(
            serverId: null,
            userId: userId,
            date: DateTime.utc(2024, 1, 15),
            status: 'in_progress',
            startedAt: startedAtUtc,
            pausedAt: pausedAtUtc,
            isSynced: false,
            syncStatus: 'pending_create',
            lastModifiedLocal: DateTime.now().toUtc(),
          ),
        ),
      );

      when(
        mockApiService.post<Map<String, dynamic>>(any, data: anyNamed('data')),
      ).thenAnswer((_) async => serverSessionJson(id: 300, version: 1));

      await syncService.sync();

      final captured =
          verify(
            mockApiService.post<Map<String, dynamic>>(
              any,
              data: captureAnyNamed('data'),
            ),
          ).captured;
      expect(captured, hasLength(1));
      final payload = captured.single as Map<String, dynamic>;

      // The absolute instant must be preserved exactly - not merely
      // "some UTC-looking string". Parsing the captured string back and
      // comparing microsecondsSinceEpoch is the only assertion that
      // cannot be satisfied by a component-copy bug that happens to
      // produce a plausible-looking but wrong string.
      final sentStartedAt = DateTime.parse(payload['startedAt'] as String);
      expect(sentStartedAt.isUtc, true);
      expect(
        sentStartedAt.microsecondsSinceEpoch,
        startedAtUtc.microsecondsSinceEpoch,
      );
      expect(payload['startedAt'], startedAtUtc.toIso8601String());

      final sentPausedAt = DateTime.parse(payload['pausedAt'] as String);
      expect(sentPausedAt.isUtc, true);
      expect(
        sentPausedAt.microsecondsSinceEpoch,
        pausedAtUtc.microsecondsSinceEpoch,
      );
      expect(payload['pausedAt'], pausedAtUtc.toIso8601String());

      // The request shape itself must be untouched: no id/exercises/
      // version/programId/programWorkoutId, matching what this endpoint
      // received before this fix.
      expect(payload.containsKey('id'), false);
      expect(payload.containsKey('exercises'), false);
      expect(payload.containsKey('version'), false);
      expect(payload.containsKey('programId'), false);
      expect(payload.containsKey('programWorkoutId'), false);
      expect(payload['userId'], userId);
      expect(payload['status'], 'in_progress');

      // A successful create must still store the authoritative
      // server-assigned id and version and transition out of
      // pending_create.
      final all = await isar.localSessions.where().findAll();
      expect(all, hasLength(1));
      expect(all.first.serverId, 300);
      expect(all.first.version, 1);
      expect(all.first.isSynced, true);
      expect(all.first.syncStatus, 'synced');
    });

    test('a failed sync of an offline-created, started-and-paused session '
        'leaves it pending_create for retry (timestamps do not affect the '
        'retry contract)', () async {
      await isar.writeTxn(
        () => isar.localSessions.put(
          LocalSession(
            serverId: null,
            userId: userId,
            date: DateTime.utc(2024, 1, 15),
            status: 'in_progress',
            startedAt: DateTime.utc(2024, 1, 15, 10, 0, 0),
            pausedAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
            isSynced: false,
            syncStatus: 'pending_create',
            lastModifiedLocal: DateTime.now().toUtc(),
          ),
        ),
      );

      when(
        mockApiService.post<Map<String, dynamic>>(any, data: anyNamed('data')),
      ).thenThrow(ApiException('Network error - cannot connect to server'));

      await syncService.sync();

      final all = await isar.localSessions.where().findAll();
      expect(all, hasLength(1));
      expect(all.first.syncStatus, 'pending_create');
      expect(all.first.serverId, isNull);
      expect(all.first.startedAt, isNotNull);
      expect(all.first.pausedAt, isNotNull);
    });
  });
}
