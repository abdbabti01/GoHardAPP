import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'session_repository_sync_snapshot_test.mocks.dart';

/// Proves `SessionRepository.watchSessionSyncSnapshot` - the SINGLE Isar
/// watch `SessionsProvider` installs - joins the visible session list with
/// derived sync diagnostics for the SAME rows, scoped to the caller's user,
/// without ever attaching diagnostics via the ambiguous
/// `serverId ?? localId` id. Real Isar; no mock stream, no `Future.delayed`
/// - `.watch(fireImmediately: true)` delivers synchronously against a real
/// on-disk database.
@GenerateMocks([ApiService, AuthService])
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late SessionRepository repository;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;

  const userA = 1;
  const userB = 2;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_sync_snapshot_');
    isar = await Isar.open(
      [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
    );

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

    repository = SessionRepository(
      mockApiService,
      localDb,
      ConnectivityService.instance,
      mockAuthService,
      sessionEpoch,
      sessionCoordinator,
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
    int uid = userA,
    int? localId,
    int? serverId,
    required String syncStatus,
    String status = 'draft',
    String? syncError,
    String name = 'Workout',
    DateTime? date,
  }) async {
    final s = LocalSession(
      serverId: serverId,
      userId: uid,
      date: date ?? DateTime(2026, 1, 1),
      name: name,
      status: status,
      isSynced: false,
      syncStatus: syncStatus,
      syncError: syncError,
      lastModifiedLocal: DateTime(2026, 1, 1),
    );
    await isar.writeTxn(() => isar.localSessions.put(s));
    return s;
  }

  test('diagnostics are scoped to the requested user - a healthy user-B row '
      'never appears in user-A\'s snapshot', () async {
    await insertSession(
      uid: userA,
      syncStatus: 'pending_create',
      syncError: 'boom',
    );
    await insertSession(uid: userB, syncStatus: 'pending_create');

    final snapshot = await repository.watchSessionSyncSnapshot(userA).first;

    expect(snapshot.visibleEntries, hasLength(1));
    expect(snapshot.visibleEntries.single.session.userId, userA);
    expect(snapshot.retryingFailureCount, 1);
  });

  test('a failing pending_delete contributes to the aggregate count despite '
      'being absent from the visible list (same exclusion as the legacy '
      'watchSessions list)', () async {
    await insertSession(
      syncStatus: 'pending_delete',
      serverId: 700,
      syncError: 'Exception: 429',
    );
    await insertSession(syncStatus: 'synced', name: 'healthy');

    final snapshot = await repository.watchSessionSyncSnapshot(userA).first;

    expect(snapshot.visibleEntries, hasLength(1));
    expect(snapshot.visibleEntries.single.session.name, 'healthy');
    expect(snapshot.retryingFailureCount, 1);
  });

  test('conflict and retrying failures are counted separately', () async {
    await insertSession(syncStatus: 'conflict', name: 'conflicted');
    await insertSession(
      syncStatus: 'pending_update',
      syncError: 'boom',
      name: 'retrying',
    );
    await insertSession(syncStatus: 'synced', name: 'healthy');

    final snapshot = await repository.watchSessionSyncSnapshot(userA).first;

    expect(snapshot.conflictCount, 1);
    expect(snapshot.retryingFailureCount, 1);
    expect(snapshot.visibleEntries, hasLength(3));
  });

  test('the id-collision regression: an unsynced row with localId N and a '
      'synced row with serverId N each receive only their OWN diagnostics - '
      'never the other\'s', () async {
    // Insert the synced/serverId row FIRST so its Isar-assigned localId is
    // smaller than the unsynced row's - we then pick serverId to exactly
    // equal the unsynced row's localId, constructing a genuine collision in
    // the ambiguous `serverId ?? localId` id space.
    final unsynced = await insertSession(
      syncStatus: 'pending_create',
      syncError: 'boom',
      name: 'unsynced (should show the badge)',
    );
    final collidingServerId = unsynced.localId;
    await insertSession(
      syncStatus: 'synced',
      serverId: collidingServerId,
      name: 'synced (must NOT show the badge)',
    );

    final snapshot = await repository.watchSessionSyncSnapshot(userA).first;
    expect(snapshot.visibleEntries, hasLength(2));

    // Both entries resolve to the SAME ambiguous public id...
    final unsyncedEntry = snapshot.visibleEntries.firstWhere(
      (e) => e.session.name == 'unsynced (should show the badge)',
    );
    final syncedEntry = snapshot.visibleEntries.firstWhere(
      (e) => e.session.name == 'synced (must NOT show the badge)',
    );
    expect(unsyncedEntry.session.id, syncedEntry.session.id);

    // ...but each entry carries its OWN diagnostics, keyed by the
    // unambiguous localId built in the same pass - never mis-attributed.
    expect(unsyncedEntry.localId, unsynced.localId);
    expect(unsyncedEntry.diagnostics, isNotNull);
    expect(unsyncedEntry.diagnostics!.state, SessionSyncState.retryingFailure);
    expect(syncedEntry.diagnostics, isNull);
  });

  test('sorting and the pending_delete/archived visible-list exclusion are '
      'unchanged from the legacy watchSessions behavior', () async {
    await insertSession(
      syncStatus: 'synced',
      name: 'older',
      date: DateTime(2026, 1, 1),
    );
    await insertSession(
      syncStatus: 'synced',
      name: 'newer',
      date: DateTime(2026, 1, 5),
    );
    await insertSession(syncStatus: 'pending_delete', name: 'deleting');
    await insertSession(
      status: 'archived',
      syncStatus: 'synced',
      name: 'old-archived',
    );

    final viaSnapshot =
        (await repository.watchSessionSyncSnapshot(userA).first).visibleEntries
            .map((e) => e.session.name)
            .toList();
    final viaLegacyList =
        (await repository.watchSessions(userA).first)
            .map((s) => s.name)
            .toList();

    expect(viaSnapshot, ['newer', 'older']); // date desc
    expect(viaLegacyList, viaSnapshot);
  });

  test('watchSessions() (legacy) still returns exactly the visible sessions, '
      'unaffected by diagnostics, proving the single-watch delegation is '
      'behavior-preserving', () async {
    await insertSession(syncStatus: 'pending_create', syncError: 'boom');
    await insertSession(syncStatus: 'synced');

    final list = await repository.watchSessions(userA).first;
    expect(list, hasLength(2));
  });
}
