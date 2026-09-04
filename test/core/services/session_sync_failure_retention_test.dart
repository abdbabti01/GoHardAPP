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
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

// Reuses the Mockito mocks generated for sync_service_test.dart (same
// ApiService / AuthService surface) - no new build_runner output.
import 'sync_service_test.mocks.dart';

/// Proves the non-destructive sync-failure contract:
///
/// * no Session / Exercise / ExerciseSet is ever hard-deleted because a retry
///   counter crossed a threshold - there is no startup cleanup pass at all, so
///   every unsynchronized row survives an app restart regardless of how the
///   sync failed (5xx, transport, unknown 4xx, malformed body, 429);
/// * a `pending_delete` stays pending until the server actually acknowledges
///   the delete;
/// * `syncRetryCount` is a bounded diagnostic - it saturates at `_maxRetries`,
///   never stops automatic retries, and is reset to zero by a successful sync
///   or by `retryFailedSyncs()`;
/// * lifecycle cancellation never counts as a failure;
/// * authoritative deletion (a successful server DELETE) still removes exactly
///   the owned row and its children.
///
/// Real Isar (close/reopen = "restart"), real `UserSessionEpoch`, deterministic
/// `MockApiService` responders. No wall-clock timing.
void main() {
  const maxRetries = 3; // SyncService._maxRetries

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

  Future<Isar> openIsar() => Isar.open(
    [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
    directory: tempDir.path,
    inspector: false,
  );

  void buildSyncServiceFor(int uid) {
    SyncService.reset();
    when(mockAuthService.getUserId()).thenAnswer((_) async => uid);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$uid');
    sessionEpoch = UserSessionEpoch()..activate(uid);
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
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_sync_retention_');
    isar = await openIsar();
    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);
    buildSyncServiceFor(userA);
  });

  tearDown(() async {
    SyncService.reset();
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Simulates an app restart: close + reopen the SAME on-disk Isar. There is
  /// no startup cleanup, so every row must persist. Rebuilds SyncService so a
  /// post-restart `sync()` runs against the reopened database.
  Future<void> restartApp({int asUser = userA}) async {
    await isar.close();
    isar = await openIsar();
    localDb.setTestDatabase(isar);
    buildSyncServiceFor(asUser);
  }

  // ---- fixtures -----------------------------------------------------------

  Future<LocalSession> insertSession({
    int uid = userA,
    int? serverId,
    int? version,
    required String syncStatus,
    String status = 'draft',
    int? programWorkoutId,
    int syncRetryCount = 0,
    String name = 'Workout',
  }) async {
    final s = LocalSession(
      serverId: serverId,
      userId: uid,
      date: DateTime(2026, 1, 1),
      name: name,
      status: status,
      isSynced: false,
      syncStatus: syncStatus,
      version: version,
      programWorkoutId: programWorkoutId,
      syncRetryCount: syncRetryCount,
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localSessions.put(s));
    return s;
  }

  Future<(LocalExercise, LocalExerciseSet)> insertChildren(
    int sessionLocalId, {
    int? sessionServerId,
  }) async {
    final ex = LocalExercise(
      sessionLocalId: sessionLocalId,
      sessionServerId: sessionServerId,
      name: 'Bench press',
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    late LocalExerciseSet set;
    await isar.writeTxn(() async {
      await isar.localExercises.put(ex);
      set = LocalExerciseSet(
        exerciseLocalId: ex.localId,
        setNumber: 1,
        reps: 5,
        weight: 100,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime(2026, 1, 1, 8),
      );
      await isar.localExerciseSets.put(set);
    });
    return (ex, set);
  }

  Map<String, dynamic> serverSessionJson({
    required int id,
    int uid = userA,
    int version = 1,
    String status = 'draft',
  }) => {
    'id': id,
    'userId': uid,
    'date': '2026-01-01',
    'duration': null,
    'notes': null,
    'type': null,
    'name': 'Workout',
    'status': status,
    'startedAt': null,
    'completedAt': null,
    'pausedAt': null,
    'exercises': <dynamic>[],
    'programId': null,
    'programWorkoutId': null,
    'version': version,
  };

  ApiException apiError(int status, {Object? body}) {
    final ro = RequestOptions(path: '/api/v1/sessions');
    return ApiException(
      'Error ($status)',
      statusCode: status,
      responseData: body,
      originalError: DioException(
        requestOptions: ro,
        response: Response<dynamic>(
          requestOptions: ro,
          statusCode: status,
          data: body,
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }

  final transportError = ApiException(
    'Network error - cannot connect to server',
  );

  void stubPost({Object? throws, Map<String, dynamic>? returns}) {
    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => throws != null ? throw throws : returns!);
  }

  void stubPut({Object? throws, Object? returns}) {
    when(
      mockApiService.put<dynamic>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => throws != null ? throw throws : returns);
  }

  void stubDelete({Object? throws, bool returns = true}) {
    when(
      mockApiService.delete(any, sessionContext: anyNamed('sessionContext')),
    ).thenAnswer((_) async => throws != null ? throw throws : returns);
  }

  Future<LocalSession?> reload(int localId) => isar.localSessions.get(localId);
  Future<int> sessionCount() => isar.localSessions.count();

  Future<void> syncTimes(int n) async {
    for (var i = 0; i < n; i++) {
      await syncService.sync();
    }
  }

  // ======================================================================
  // 1-3: transient CREATE failures never delete anything across a restart
  // ======================================================================

  test(
    '1. three 500s on pending_create -> Session + children survive restart',
    () async {
      final s = await insertSession(syncStatus: 'pending_create');
      final (ex, set) = await insertChildren(s.localId);
      stubPost(throws: apiError(500));

      await syncTimes(3);
      await restartApp();

      final stored = await reload(s.localId);
      expect(stored, isNotNull);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.isSynced, isFalse);
      expect(stored.syncRetryCount, maxRetries);
      expect(await isar.localExercises.get(ex.localId), isNotNull);
      expect(await isar.localExerciseSets.get(set.localId), isNotNull);
    },
  );

  test('2. three transport failures on pending_create -> everything survives '
      'restart', () async {
    final s = await insertSession(syncStatus: 'pending_create');
    final (ex, set) = await insertChildren(s.localId);
    stubPost(throws: transportError);

    await syncTimes(3);
    await restartApp();

    expect(await reload(s.localId), isNotNull);
    expect((await reload(s.localId))!.syncStatus, 'pending_create');
    expect(await isar.localExercises.get(ex.localId), isNotNull);
    expect(await isar.localExerciseSets.get(set.localId), isNotNull);
  });

  test('3. unknown 4xx and a malformed success body -> everything survives '
      'restart', () async {
    final unknown = await insertSession(
      syncStatus: 'pending_create',
      name: 'u',
    );
    final (ux, us) = await insertChildren(unknown.localId);
    stubPost(throws: apiError(422));
    await syncTimes(3);

    final malformed = await insertSession(
      syncStatus: 'pending_create',
      name: 'm',
    );
    final (mx, ms) = await insertChildren(malformed.localId);
    stubPost(
      returns: <String, dynamic>{'nope': true},
    ); // Session.fromJson throws
    await syncTimes(3);

    await restartApp();

    for (final s in [unknown, malformed]) {
      final stored = await reload(s.localId);
      expect(stored, isNotNull, reason: 'row ${s.name} deleted');
      expect(stored!.syncStatus, 'pending_create');
    }
    for (final id in [ux.localId, mx.localId]) {
      expect(await isar.localExercises.get(id), isNotNull);
    }
    for (final id in [us.localId, ms.localId]) {
      expect(await isar.localExerciseSets.get(id), isNotNull);
    }
  });

  // ======================================================================
  // 4-5: transient UPDATE / DELETE failures never delete anything
  // ======================================================================

  test('4. repeated 429 on pending_update preserves the Session, the '
      'pending_update state, and all children', () async {
    final s = await insertSession(
      serverId: 500,
      version: 5,
      syncStatus: 'pending_update',
    );
    final (ex, set) = await insertChildren(s.localId, sessionServerId: 500);
    stubPut(throws: apiError(429));

    await syncTimes(4);
    await restartApp();

    final stored = await reload(s.localId);
    expect(stored, isNotNull);
    expect(stored!.syncStatus, 'pending_update');
    expect(stored.serverId, 500);
    expect(stored.isSynced, isFalse);
    // The counter advanced on the pending_update path too, and saturated -
    // 4 failing passes, pinned at _maxRetries, never higher.
    expect(stored.syncRetryCount, maxRetries);
    expect(await isar.localExercises.get(ex.localId), isNotNull);
    expect(await isar.localExerciseSets.get(set.localId), isNotNull);
  });

  test(
    '5. repeated 429 on pending_delete preserves the deletion intent',
    () async {
      final s = await insertSession(
        serverId: 700,
        syncStatus: 'pending_delete',
      );
      await insertChildren(s.localId, sessionServerId: 700);
      stubDelete(throws: apiError(429));

      await syncTimes(4);
      await restartApp();

      final stored = await reload(s.localId);
      expect(stored, isNotNull);
      expect(stored!.syncStatus, 'pending_delete');
      expect(stored.serverId, 700);
      expect(stored.isSynced, isFalse);
      // Same saturating diagnostic on the pending_delete path.
      expect(stored.syncRetryCount, maxRetries);
    },
  );

  // ======================================================================
  // 6-8: authoritative convergence still works and resets diagnostics
  // ======================================================================

  test('6. a later successful DELETE removes the Session and children '
      'authoritatively', () async {
    final s = await insertSession(serverId: 700, syncStatus: 'pending_delete');
    final (ex, set) = await insertChildren(s.localId, sessionServerId: 700);

    stubDelete(throws: apiError(429));
    await syncTimes(2);
    expect(await reload(s.localId), isNotNull);

    stubDelete(returns: true);
    await syncService.sync();

    expect(await reload(s.localId), isNull);
    expect(await isar.localExercises.get(ex.localId), isNull);
    expect(await isar.localExerciseSets.get(set.localId), isNull);
  });

  test(
    '7. a later successful CREATE resets retry diagnostics and syncs',
    () async {
      final s = await insertSession(syncStatus: 'pending_create');
      stubPost(throws: apiError(500));
      await syncTimes(3);
      expect((await reload(s.localId))!.syncRetryCount, maxRetries);
      expect((await reload(s.localId))!.syncError, isNotNull);

      stubPost(returns: serverSessionJson(id: 900, version: 1));
      await syncService.sync();

      final stored = await reload(s.localId);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
      expect(stored.serverId, 900);
      expect(stored.syncRetryCount, 0);
      expect(stored.syncError, isNull);
    },
  );

  test('8. a later successful UPDATE resets diagnostics and syncs', () async {
    final s = await insertSession(
      serverId: 500,
      version: 5,
      syncStatus: 'pending_update',
    );
    stubPut(throws: apiError(429));
    await syncTimes(3);
    expect((await reload(s.localId))!.syncRetryCount, maxRetries);
    expect((await reload(s.localId))!.syncError, isNotNull);

    stubPut(returns: serverSessionJson(id: 500, version: 6));
    await syncService.sync();

    final stored = await reload(s.localId);
    expect(stored!.isSynced, isTrue);
    expect(stored.syncStatus, 'synced');
    expect(stored.syncRetryCount, 0);
    expect(stored.syncError, isNull);
  });

  // ======================================================================
  // 9-11: retry-counter saturation
  // ======================================================================

  test('9. syncRetryCount saturates exactly at _maxRetries', () async {
    final s = await insertSession(syncStatus: 'pending_create');
    stubPost(throws: apiError(500));

    for (var pass = 1; pass <= 8; pass++) {
      await syncService.sync();
      final c = (await reload(s.localId))!.syncRetryCount;
      expect(
        c,
        pass < maxRetries ? pass : maxRetries,
        reason: 'after $pass failing passes',
      );
      expect(c, lessThanOrEqualTo(maxRetries));
    }
  });

  test(
    '10. failures after saturation still trigger real retry attempts',
    () async {
      final s = await insertSession(syncStatus: 'pending_create');
      stubPost(throws: apiError(500));

      await syncTimes(6);

      // Every pass dispatched a real POST - the counter being pinned at
      // _maxRetries did not stop the retry loop.
      verify(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).called(6);
      expect((await reload(s.localId))!.syncRetryCount, maxRetries);
      expect((await reload(s.localId))!.syncStatus, 'pending_create');
    },
  );

  test('11. retryFailedSyncs() clears the saturated counter (then its own '
      'triggered pass runs); a later success converges to zero', () async {
    final s = await insertSession(syncStatus: 'pending_create');
    stubPost(throws: apiError(500));
    await syncTimes(3);
    expect((await reload(s.localId))!.syncRetryCount, maxRetries);
    expect((await reload(s.localId))!.syncError, isNotNull);

    // retryFailedSyncs resets to 0 and immediately re-syncs. The POST is still
    // failing, so the one triggered pass brings the counter back to exactly 1
    // (0 after the reset, +1 for that one attempt) - NOT the saturated 3, which
    // is what proves the reset happened.
    await syncService.retryFailedSyncs();
    final afterRetry = await reload(s.localId);
    expect(afterRetry!.syncRetryCount, 1);
    expect(afterRetry.syncStatus, 'pending_create');

    stubPost(returns: serverSessionJson(id: 901, version: 1));
    await syncService.sync();
    final done = await reload(s.localId);
    expect(done!.syncRetryCount, 0);
    expect(done.syncError, isNull);
    expect(done.syncStatus, 'synced');
  });

  // ======================================================================
  // 12: lifecycle cancellation never counts
  // ======================================================================

  test('12. SessionStaleException / RequestCancelledException never increment '
      'the counter (create, update, delete)', () async {
    for (final lifecycle in <Object>[
      const SessionStaleException(),
      const RequestCancelledException(),
    ]) {
      await isar.writeTxn(() => isar.localSessions.clear());

      final create = await insertSession(syncStatus: 'pending_create');
      final update = await insertSession(
        serverId: 10,
        version: 2,
        syncStatus: 'pending_update',
      );
      final del = await insertSession(
        serverId: 11,
        syncStatus: 'pending_delete',
      );
      stubPost(throws: lifecycle);
      stubPut(throws: lifecycle);
      stubDelete(throws: lifecycle);

      await syncTimes(3);

      for (final s in [create, update, del]) {
        final stored = await reload(s.localId);
        expect(stored, isNotNull, reason: '$lifecycle deleted ${s.syncStatus}');
        expect(
          stored!.syncRetryCount,
          0,
          reason: '$lifecycle counted on ${s.syncStatus}',
        );
        expect(stored.syncError, isNull);
      }
    }
  });

  // ======================================================================
  // 13-15: cross-user + duplicate-draft protection
  // ======================================================================

  test('13. a User-A failed row (+ children) is not deleted when User B '
      'starts / restores a session', () async {
    final aSession = await insertSession(
      uid: userA,
      syncStatus: 'pending_create',
      syncRetryCount: maxRetries,
      name: 'A workout',
    );
    final (aEx, aSet) = await insertChildren(aSession.localId);
    await insertSession(uid: userB, syncStatus: 'pending_create', name: 'B');

    // User B's session is restored and a sync pass runs as User B.
    await restartApp(asUser: userB);
    stubPost(throws: apiError(500));
    await syncService.sync();
    await restartApp(asUser: userB);

    final storedA = await reload(aSession.localId);
    expect(storedA, isNotNull, reason: "User A's row was deleted");
    expect(storedA!.userId, userA);
    expect(storedA.syncRetryCount, maxRetries);
    expect(await isar.localExercises.get(aEx.localId), isNotNull);
    expect(await isar.localExerciseSets.get(aSet.localId), isNotNull);
  });

  test('14. two users with the same programWorkoutId keep both rows across a '
      'restart', () async {
    final a = await insertSession(
      uid: userA,
      syncStatus: 'pending_create',
      programWorkoutId: 77,
      name: 'A draft',
    );
    final b = await insertSession(
      uid: userB,
      syncStatus: 'pending_create',
      programWorkoutId: 77,
      name: 'B draft',
    );

    await restartApp();

    expect(await reload(a.localId), isNotNull);
    expect(await reload(b.localId), isNotNull);
  });

  test('15. same-user duplicate drafts are not deleted merely because the app '
      'restarts', () async {
    final first = await insertSession(
      syncStatus: 'pending_create',
      status: 'draft',
      programWorkoutId: 88,
      name: 'draft 1',
    );
    final second = await insertSession(
      syncStatus: 'pending_create',
      status: 'draft',
      programWorkoutId: 88,
      name: 'draft 2',
    );

    await restartApp();
    await restartApp();

    expect(await reload(first.localId), isNotNull);
    expect(await reload(second.localId), isNotNull);
    expect(await sessionCount(), 2);
  });

  // ======================================================================
  // 16: version-conflict behaviour unchanged
  // ======================================================================

  test('16. a well-formed 409 version conflict still parks the row as '
      "'conflict' with its edit preserved and out of the retry loop", () async {
    final s = await insertSession(
      serverId: 500,
      version: 5,
      syncStatus: 'pending_update',
    );
    stubPut(
      throws: apiError(
        409,
        body: {
          'serverData': serverSessionJson(id: 500, version: 7),
          'currentVersion': 7,
        },
      ),
    );

    await syncService.sync();

    var stored = await reload(s.localId);
    expect(stored!.syncStatus, 'conflict');
    expect(stored.isSynced, isFalse);
    expect(stored.syncRetryCount, 0);
    expect(stored.conflictServerVersion, 7);
    expect(stored.conflictServerSnapshotJson, isNotNull);

    // Excluded from the auto-retry loop - a second pass issues no PUT.
    clearInteractions(mockApiService);
    await syncService.sync();
    verifyNever(
      mockApiService.put<dynamic>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    );
    stored = await reload(s.localId);
    expect(stored!.syncStatus, 'conflict');

    await restartApp();
    expect((await reload(s.localId))!.syncStatus, 'conflict');
  });

  // ======================================================================
  // 17: startup persistence is idempotent across multiple restarts
  // ======================================================================

  test('17. multiple close/reopen cycles leave every row unchanged', () async {
    final create = await insertSession(syncStatus: 'pending_create', name: 'c');
    final update = await insertSession(
      serverId: 1,
      version: 2,
      syncStatus: 'pending_update',
      name: 'u',
    );
    final del = await insertSession(
      serverId: 2,
      syncStatus: 'pending_delete',
      name: 'd',
    );
    await insertChildren(create.localId);

    for (var i = 0; i < 4; i++) {
      await restartApp();
      expect(await sessionCount(), 3, reason: 'after restart #${i + 1}');
      expect(await isar.localExercises.count(), 1);
      expect(await isar.localExerciseSets.count(), 1);
      expect((await reload(create.localId))!.syncStatus, 'pending_create');
      expect((await reload(update.localId))!.syncStatus, 'pending_update');
      expect((await reload(del.localId))!.syncStatus, 'pending_delete');
    }
  });

  // ======================================================================
  // 18: authoritative owned delete still targets exactly the owned row
  // ======================================================================

  test('18. a server-acknowledged DELETE removes exactly the owned Session + '
      'children and never a foreign row', () async {
    final owned = await insertSession(
      uid: userA,
      serverId: 700,
      syncStatus: 'pending_delete',
    );
    final (ex, set) = await insertChildren(owned.localId, sessionServerId: 700);
    final foreign = await insertSession(
      uid: userB,
      serverId: 701,
      syncStatus: 'pending_create',
      name: 'foreign',
    );

    stubDelete(returns: true);
    await syncService.sync(); // runs as User A

    expect(await reload(owned.localId), isNull);
    expect(await isar.localExercises.get(ex.localId), isNull);
    expect(await isar.localExerciseSets.get(set.localId), isNull);

    final storedForeign = await reload(foreign.localId);
    expect(storedForeign, isNotNull, reason: "User B's row was deleted");
    expect(storedForeign!.userId, userB);
  });

  // ======================================================================
  // 19: the authoritative delete's in-transaction ownership / currency
  //     guard - a DELETE that the server accepts but whose local
  //     acknowledgment lands after the session has ended must NOT remove
  //     the row; the deletion intent is retried under the next
  //     authenticated session instead of being silently lost.
  // ======================================================================

  test('19. a server-accepted DELETE whose local ack races the session '
      'ending keeps the pending_delete row and its children', () async {
    final s = await insertSession(serverId: 700, syncStatus: 'pending_delete');
    final (ex, set) = await insertChildren(s.localId, sessionServerId: 700);
    stubDelete(returns: true);

    // The server DELETE succeeds, but the session ends (logout) in the
    // window between the response and the local acknowledging writeTxn.
    syncService.beforeAckWriteTxnForTesting = () async {
      sessionEpoch.invalidate();
    };

    try {
      await syncService.sync();
    } on SessionStaleException {
      // Expected: the guard aborts the acknowledgment for a since-ended
      // session by rethrowing out of the pass.
    }
    syncService.beforeAckWriteTxnForTesting = null;

    final stored = await reload(s.localId);
    expect(stored, isNotNull, reason: 'deletion intent was lost');
    expect(stored!.syncStatus, 'pending_delete');
    expect(await isar.localExercises.get(ex.localId), isNotNull);
    expect(await isar.localExerciseSets.get(set.localId), isNotNull);
  });

  // ======================================================================
  // 20: getSyncStatus() / retryFailedSyncs() still see a saturated row
  //     (the counter pins at exactly _maxRetries, and their
  //     `syncRetryCountGreaterThan(_maxRetries - 1)` predicate still
  //     matches it - a bounded counter must not fall out of the
  //     error/retry accounting).
  // ======================================================================

  test('20. a saturated row is still counted by getSyncStatus() and still '
      'picked up by retryFailedSyncs()', () async {
    final s = await insertSession(syncStatus: 'pending_create');
    stubPost(throws: apiError(500));
    await syncTimes(5); // saturates at _maxRetries

    expect((await reload(s.localId))!.syncRetryCount, maxRetries);

    final status = await syncService.getSyncStatus();
    expect(status['errorCount'], greaterThanOrEqualTo(1));
    expect(status['pendingCount'], greaterThanOrEqualTo(1));

    await syncService.retryFailedSyncs(); // finds it, resets, one failing pass
    expect((await reload(s.localId))!.syncRetryCount, 1);
  });
}
