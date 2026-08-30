import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_run_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/gps_point.dart';
import 'package:go_hard_app/data/repositories/running_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'running_repository_session_ownership_test.mocks.dart';

@GenerateMocks([AuthService, ConnectivityService])
/// Proves that RunningRepository is fully session-bound (every HTTP call,
/// foreground and background, carries the session that started the
/// operation) and locally ownership-safe (every local-ID lookup and write
/// is scoped to the calling user), mirroring
/// `session_repository_session_ownership_test.dart`.
///
/// Uses a REAL [ApiService] wired to a fake [HttpClientAdapter] so
/// credential pinning and dispatch-time staleness rejection are proven
/// against the real production interceptor pipeline, not a stub of it.
///
/// ## Deterministic synchronization
///
/// No test in this file uses a wall-clock delay to prove detached work has
/// finished:
///
/// - [_FakeHttpClientAdapter.nextDispatch] completes the instant the fake
///   transport's `fetch()` is actually invoked.
/// - `scheduledBackgroundSyncs` collects the exact `Future<void>` each
///   [RunningRepository._backgroundSync] call hands back via the
///   `onBackgroundSyncScheduledForTesting` seam - it completes only once
///   that specific detached operation has fully settled. Awaiting
///   `scheduledBackgroundSyncs.single` is both the completion wait and an
///   implicit assertion that exactly one background operation was
///   scheduled.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late RunningRepository repository;
  late List<Future<void>> scheduledBackgroundSyncs;

  const userA = 1;
  const userB = 2;

  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('running_repo_owner_');
    isar = await Isar.open(
      [LocalRunSessionSchema],
      directory: tempDir.path,
      inspector: false,
    );

    currentAuthUserId = null;
    mockAuthService = MockAuthService();
    mockConnectivity = MockConnectivityService();
    when(mockConnectivity.isOnline).thenReturn(true);
    when(
      mockAuthService.getUserId(),
    ).thenAnswer((_) async => currentAuthUserId);
    when(mockAuthService.getToken()).thenAnswer(
      (_) async => currentAuthUserId == null ? null : 'jwt-$currentAuthUserId',
    );

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch();
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );
    apiService = ApiService(mockAuthService, sessionEpoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;

    repository = RunningRepository(
      localDb,
      mockConnectivity,
      mockAuthService,
      apiService,
      sessionEpoch,
      sessionCoordinator,
    );

    scheduledBackgroundSyncs = [];
    repository.onBackgroundSyncScheduledForTesting =
        scheduledBackgroundSyncs.add;
  });

  tearDown(() async {
    repository.beforeWriteTxnForTesting = null;
    repository.insideWriteTxnForTesting = null;
    repository.afterWriteTxnForTesting = null;
    repository.beforeBackgroundHttpDispatchForTesting = null;
    repository.afterBackgroundHttpResponseForTesting = null;
    repository.onBackgroundSyncScheduledForTesting = null;
    apiService.beforeDispatchEpochCheckForTesting = null;
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  void loginAs(int userId) {
    currentAuthUserId = userId;
    sessionEpoch.activate(userId);
  }

  void logout() {
    currentAuthUserId = null;
    sessionEpoch.invalidate();
  }

  // ============ Seed helpers ============

  Future<LocalRunSession> insertRun({
    int uid = userA,
    int? serverId,
    int? explicitLocalId,
    String status = 'draft',
    String name = 'Original',
    DateTime? date,
    bool? isSynced,
    String? syncStatus,
    DateTime? pausedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    int? duration,
    double? distance,
    List<LocalGpsPoint>? route,
  }) async {
    final run = LocalRunSession.create(
      serverId: serverId,
      userId: uid,
      name: name,
      date: date ?? DateTime(2026, 1, 1),
      status: status,
      isSynced: isSynced ?? (serverId != null),
      syncStatus:
          syncStatus ?? (serverId != null ? 'synced' : 'pending_create'),
      lastModifiedLocal: DateTime.now().toUtc(),
      pausedAt: pausedAt,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      distance: distance,
      route: route ?? const [],
    );
    if (explicitLocalId != null) {
      run.localId = explicitLocalId;
    }
    await isar.writeTxn(() => isar.localRunSessions.put(run));
    return run;
  }

  Map<String, dynamic> runJson({
    required int id,
    required int userId,
    String name = 'Server run',
    String status = 'completed',
    DateTime? date,
    double? distance,
    int? duration,
  }) => {
    'id': id,
    'userId': userId,
    'name': name,
    'date': (date ?? DateTime(2026, 1, 1)).toIso8601String(),
    'distance': distance,
    'duration': duration,
    'averagePace': null,
    'calories': null,
    'status': status,
    'startedAt': null,
    'completedAt': null,
    'pausedAt': null,
    'routeJson': null,
  };

  ResponseBody jsonResponse(Object? json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  Matcher throwsNotAuthenticated() => throwsA(
    isA<Exception>().having(
      (e) => e.toString(),
      'message',
      contains('No authenticated user'),
    ),
  );

  Matcher throwsNotFound() => throwsA(
    isA<Exception>().having(
      (e) => e.toString(),
      'message',
      contains('Run session not found'),
    ),
  );

  // ============ 1. Logged out ============

  group('logged out', () {
    test(
      'every method performs no Isar mutation and no HTTP when logged out (req 1)',
      () async {
        final run = await insertRun(uid: userA);

        expect(await repository.getRunSessions(), isEmpty);
        expect(await repository.getRecentRuns(), isEmpty);
        expect(await repository.getThisWeekRuns(), isEmpty);
        expect(await repository.getRunSession(run.localId), isNull);
        await expectLater(
          () => repository.createRunSession(),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.startRun(run.localId),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.pauseRun(run.localId, DateTime.now().toUtc()),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.resumeRun(run.localId, DateTime.now().toUtc()),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.completeRun(run.localId, duration: 1, distance: 1),
          throwsNotAuthenticated(),
        );

        // updateRoute/updateDistance never throw - they silently no-op.
        await repository.updateRoute(run.localId, const []);
        await repository.updateDistance(run.localId, 5);

        expect(await repository.deleteRun(run.localId), isFalse);

        expect(adapter.capturedRequests, isEmpty);
        final stored = await isar.localRunSessions.get(run.localId);
        expect(
          stored,
          isNotNull,
          reason: 'nothing above should have deleted it',
        );
        expect(stored!.name, 'Original');
        expect(stored.route, isEmpty);
        expect(stored.distance, isNull);
      },
    );
  });

  // ============ 2-4. Context and credentials ============

  group('context and credentials', () {
    test(
      "context pins A's JWT even if storage flips to B before dispatch (req 2)",
      () async {
        loginAs(userA);
        final responseCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => responseCompleter.future;

        final dispatched = adapter.nextDispatch();
        final created = repository.createRunSession();

        // Simulate secure storage now holding B's token, WITHOUT going
        // through logout()/loginAs() (the real epoch is untouched) - and
        // WITHOUT awaiting anything first, so this runs before any of
        // createRunSession()'s own internal awaits (context capture,
        // writeTxn, scheduling the background sync) have had a chance to
        // resolve. Proves the pinned context captured at operation entry,
        // not a live re-read at dispatch time, is what determines the
        // header - a repository that (re)captured its context lazily
        // inside the background closure would pick up 'jwt-$userB' here
        // instead.
        currentAuthUserId = userB;

        await dispatched;

        expect(
          adapter.capturedRequests.single.headers['Authorization'],
          'Bearer jwt-$userA',
        );

        responseCompleter.complete(jsonResponse({'id': 1}));
        await created;
        await scheduledBackgroundSyncs.single;
      },
    );

    test('stale before dispatch sends no request (req 3)', () async {
      loginAs(userA);
      final run = await insertRun(uid: userA, status: 'draft');

      repository.beforeBackgroundHttpDispatchForTesting = () async {
        logout();
      };

      await repository.startRun(run.localId);
      await scheduledBackgroundSyncs.single;

      expect(
        adapter.capturedRequests,
        isEmpty,
        reason:
            'the wrapper-level staleness checkpoint must reject dispatch '
            'outright once the session captured at entry is no longer '
            'current',
      );
    });

    test(
      'a HTTP success after B login cannot cache/acknowledge (req 4)',
      () async {
        loginAs(userA);
        final run = await insertRun(uid: userA, status: 'draft');

        final responseCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => responseCompleter.future;

        final dispatched = adapter.nextDispatch();
        await repository.startRun(run.localId);
        await dispatched;
        expect(adapter.capturedRequests, hasLength(1));

        loginAs(userB);
        responseCompleter.complete(jsonResponse({'id': 500}));
        await scheduledBackgroundSyncs.single;

        final stored = await isar.localRunSessions.get(run.localId);
        expect(stored!.serverId, isNull);
        expect(stored.isSynced, isFalse);
        expect(stored.syncStatus, 'pending_update');
      },
    );

    test('the post-HTTP checkpoint in _syncRunToServer rejects before ever '
        'running the after-response hook, not relying on a later redundant '
        'check', () async {
      loginAs(userA);
      final run = await insertRun(uid: userA, status: 'draft');

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;
      var hookFired = false;
      repository.afterBackgroundHttpResponseForTesting = () async {
        hookFired = true;
      };

      final dispatched = adapter.nextDispatch();
      await repository.startRun(run.localId);
      await dispatched;

      logout();
      responseCompleter.complete(jsonResponse({'id': 1}));
      await scheduledBackgroundSyncs.single;

      expect(
        hookFired,
        isFalse,
        reason:
            'the post-HTTP checkpoint must reject and return immediately '
            'once the response arrives under a stale session, before '
            'ever reaching the after-response hook - _writeOwnedRun '
            'catching the same staleness later is not a substitute for '
            'this earlier exit',
      );
    });

    test('the first-statement-inside-writeTxn checkpoint prevents a write when '
        'the session goes stale mid-transaction, not just before it', () async {
      loginAs(userA);
      final run = await insertRun(uid: userA, status: 'draft');

      repository.insideWriteTxnForTesting = () async {
        logout();
      };

      await expectLater(
        () => repository.startRun(run.localId),
        throwsNotFound(),
      );

      final stored = await isar.localRunSessions.get(run.localId);
      expect(
        stored!.status,
        'draft',
        reason:
            'a session that goes stale after entering the write '
            'transaction must still block the write - the '
            'before-entering-the-transaction check alone is not '
            'sufficient, since the session can end while Isar\'s write '
            'lock is being awaited',
      );
    });
  });

  // ============ 5-6. Local ownership ============

  group('local ownership', () {
    test(
      'foreign local run rejected for every mutation shape (req 5)',
      () async {
        loginAs(userA);
        final b = await insertRun(
          uid: userB,
          status: 'in_progress',
          startedAt: DateTime.utc(2026, 1, 1),
        );

        expect(await repository.getRunSession(b.localId), isNull);
        await expectLater(
          () => repository.startRun(b.localId),
          throwsNotFound(),
        );
        await expectLater(
          () => repository.pauseRun(b.localId, DateTime.utc(2026, 1, 1, 1)),
          throwsNotFound(),
        );
        await expectLater(
          () => repository.resumeRun(b.localId, DateTime.utc(2026, 1, 1, 1)),
          throwsNotFound(),
        );
        await expectLater(
          () => repository.completeRun(b.localId, duration: 1, distance: 1),
          throwsNotFound(),
        );
        await repository.updateRoute(b.localId, [
          GpsPoint(latitude: 1, longitude: 1, timestamp: DateTime.utc(2026)),
        ]);
        await repository.updateDistance(b.localId, 42);
        expect(await repository.deleteRun(b.localId), isFalse);

        final stillThere = await isar.localRunSessions.get(b.localId);
        expect(stillThere, isNotNull);
        expect(stillThere!.status, 'in_progress');
        expect(stillThere.route, isEmpty);
        expect(stillThere.distance, isNull);
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test(
      'a same-user local run succeeds through the full lifecycle (req 6)',
      () async {
        loginAs(userA);
        adapter.responder = (_) async => jsonResponse({'id': 1});
        final run = await insertRun(uid: userA, status: 'draft');

        final started = await repository.startRun(run.localId);
        expect(started.status, 'in_progress');

        final paused = await repository.pauseRun(
          run.localId,
          DateTime.utc(2026, 1, 1, 1),
        );
        expect(paused.pausedAt, isNotNull);

        final resumed = await repository.resumeRun(
          run.localId,
          DateTime.utc(2026, 1, 1, 1, 1),
        );
        expect(resumed.pausedAt, isNull);

        await repository.updateDistance(run.localId, 1.5);
        await repository.updateRoute(run.localId, [
          GpsPoint(latitude: 1, longitude: 1, timestamp: DateTime.utc(2026)),
        ]);

        final completed = await repository.completeRun(
          run.localId,
          duration: 60,
          distance: 0.5,
        );
        expect(completed.status, 'completed');

        await Future.wait(scheduledBackgroundSyncs);

        final deleted = await repository.deleteRun(run.localId);
        expect(deleted, isTrue);
        expect(await isar.localRunSessions.get(run.localId), isNull);
      },
    );
  });

  // ============ 7. Reused local ID after clearAll ============

  test('reused local ID after clearAll cannot be touched by stale background '
      'work (req 7)', () async {
    loginAs(userA);
    final run = await insertRun(uid: userA, explicitLocalId: 5);

    final responseCompleter = Completer<ResponseBody>();
    adapter.responder = (_) => responseCompleter.future;

    final dispatched = adapter.nextDispatch();
    await repository.startRun(run.localId);
    await dispatched;

    // Simulate logout's clearAll() wiping the database (which resets
    // Isar's auto-increment counter) and User B logging in and creating
    // a fresh row that happens to reuse local ID 5.
    await isar.writeTxn(() => isar.localRunSessions.clear());
    logout();
    loginAs(userB);
    await insertRun(uid: userB, explicitLocalId: 5, name: 'B fresh run');

    responseCompleter.complete(jsonResponse({'id': 999}));
    await scheduledBackgroundSyncs.single;

    final stored = await isar.localRunSessions.get(5);
    expect(stored!.userId, userB);
    expect(stored.name, 'B fresh run');
    expect(
      stored.serverId,
      isNull,
      reason:
          "A's stale background acknowledgment must never write onto "
          "B's row, even though it reused the same local ID",
    );
  });

  test(
    'discarding a run while its create-sync is in flight must not '
    'resurrect it once the response arrives (still the SAME session)',
    () async {
      loginAs(userA);
      final run = await insertRun(uid: userA, status: 'draft');

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      await repository.startRun(run.localId);
      await dispatched;

      // Discard the run mid-flight, still as the SAME user/session - no
      // epoch invalidation here, so only the identity-based re-fetch (not
      // a staleness checkpoint) can catch this.
      expect(await repository.deleteRun(run.localId), isTrue);
      expect(await isar.localRunSessions.get(run.localId), isNull);

      responseCompleter.complete(jsonResponse({'id': 999}));
      await scheduledBackgroundSyncs.single;

      expect(
        await isar.localRunSessions.get(run.localId),
        isNull,
        reason:
            'a stale create acknowledgment must re-fetch by local identity '
            'rather than writing a closure-captured reference back, or a '
            'deleted row would be silently resurrected',
      );
    },
  );

  // ============ 8-9. _syncFromServer ownership ============

  group('_syncFromServer ownership', () {
    test(
      '_syncFromServer cannot overwrite a foreign server-ID row (req 8)',
      () async {
        final foreign = await insertRun(
          uid: userB,
          serverId: 42,
          name: 'B run',
        );
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse([
              runJson(id: 42, userId: userA, name: 'Hijacked'),
            ]);

        await repository.getRecentRuns();

        final stored = await isar.localRunSessions.get(foreign.localId);
        expect(stored!.name, 'B run');
        expect(stored.userId, userB);
      },
    );

    test('_syncFromServer cannot cache after session change (req 9)', () async {
      loginAs(userA);
      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      // getRunSessions() triggers _syncFromServer detached.
      await repository.getRunSessions();
      await dispatched;

      loginAs(userB);
      responseCompleter.complete(
        jsonResponse([runJson(id: 999, userId: userA)]),
      );
      await scheduledBackgroundSyncs.single;

      final stored =
          await isar.localRunSessions.filter().serverIdEqualTo(999).findFirst();
      expect(stored, isNull);
    });
  });

  // ============ 10-12. Sync acknowledgment ============

  group('sync acknowledgment', () {
    test(
      "create POST success under A acknowledges only A's stable row (req 10)",
      () async {
        loginAs(userA);
        adapter.responder = (_) async => jsonResponse({'id': 55});

        final created = await repository.createRunSession();
        await scheduledBackgroundSyncs.single;

        final stored = await isar.localRunSessions.get(created.id);
        expect(stored!.serverId, 55);
        expect(stored.isSynced, isTrue);
        expect(stored.syncStatus, 'synced');
        expect(stored.userId, userA);
      },
    );

    test(
      'a create success after B login does not set serverId/isSynced (req 11)',
      () async {
        loginAs(userA);
        final responseCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => responseCompleter.future;

        final dispatched = adapter.nextDispatch();
        final created = await repository.createRunSession();
        await dispatched;
        expect(adapter.capturedRequests, hasLength(1));

        loginAs(userB);
        responseCompleter.complete(jsonResponse({'id': 777}));
        await scheduledBackgroundSyncs.single;

        final stored = await isar.localRunSessions.get(created.id);
        expect(stored!.serverId, isNull);
        expect(stored.isSynced, isFalse);
        expect(stored.userId, userA);
      },
    );

    test('update PUT success reacquires stable owned row (req 12)', () async {
      loginAs(userA);
      final run = await insertRun(
        uid: userA,
        serverId: 88,
        status: 'in_progress',
        syncStatus: 'pending_update',
        isSynced: false,
      );

      adapter.responder = (_) async => jsonResponse({});

      final dispatched = adapter.nextDispatch();
      await repository.completeRun(run.localId, duration: 100, distance: 1);
      await dispatched;
      expect(adapter.capturedRequests.single.method, 'PUT');

      await scheduledBackgroundSyncs.single;

      final stored = await isar.localRunSessions.get(run.localId);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
      expect(stored.serverId, 88);
    });
  });

  // ============ 13. Delete ============

  group('delete', () {
    test(
      'delete uses bound context and cannot delete a foreign row (req 13)',
      () async {
        loginAs(userA);
        final foreign = await insertRun(uid: userB, serverId: 10);

        final result = await repository.deleteRun(foreign.localId);

        expect(result, isFalse);
        expect(adapter.capturedRequests, isEmpty);
        expect(await isar.localRunSessions.get(foreign.localId), isNotNull);
      },
    );

    test('delete sends a bound DELETE for an owned synced row', () async {
      loginAs(userA);
      final run = await insertRun(uid: userA, serverId: 20);
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      final result = await repository.deleteRun(run.localId);

      expect(result, isTrue);
      expect(adapter.capturedRequests, hasLength(1));
      expect(
        adapter.capturedRequests.single.headers['Authorization'],
        'Bearer jwt-$userA',
      );
      expect(await isar.localRunSessions.get(run.localId), isNull);
    });

    test(
      'delete DELETE call is session-bound, not a legacy/unbound request',
      () async {
        loginAs(userA);
        final run = await insertRun(uid: userA, serverId: 30);

        // beforeDispatchEpochCheckForTesting only fires for a SESSION-BOUND
        // request (see ApiService's interceptor) - a legacy/unbound request
        // would skip straight past this hook and still dispatch.
        apiService.beforeDispatchEpochCheckForTesting = () async {
          sessionEpoch.invalidate();
        };

        final result = await repository.deleteRun(run.localId);

        expect(
          adapter.capturedRequests,
          isEmpty,
          reason:
              'a session-bound DELETE must be rejected at the interceptor '
              'checkpoint once invalidated there, never reaching the '
              'transport',
        );
        expect(result, isFalse);
      },
    );
  });

  // ============ 14-15. Field-preservation regression coverage ============

  group('field preservation', () {
    test(
      'pause/resume preserve pausedAt/startedAt behavior (req 14)',
      () async {
        loginAs(userA);
        final run = await insertRun(
          uid: userA,
          status: 'in_progress',
          startedAt: DateTime.utc(2026, 1, 1, 10),
        );

        final pausedAt = DateTime.utc(2026, 1, 1, 10, 30);
        final paused = await repository.pauseRun(run.localId, pausedAt);
        expect(paused.pausedAt, pausedAt);
        // startedAt was persisted by insertRun() in a prior transaction and
        // re-read fresh from Isar by _writeOwnedRun - unlike pausedAt/
        // newStartedAt above (set directly on the in-memory row within this
        // same call), it has round-tripped through Isar's DateTime storage,
        // so compare by instant rather than by exact object equality,
        // mirroring session_repository_session_ownership_test.dart.
        expect(
          paused.startedAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 1, 10)),
          isTrue,
        );

        final newStartedAt = DateTime.utc(2026, 1, 1, 10, 31);
        final resumed = await repository.resumeRun(run.localId, newStartedAt);
        expect(resumed.pausedAt, isNull);
        expect(resumed.startedAt, newStartedAt);
      },
    );

    test(
      'complete preserves duration/distance/route behavior (req 15)',
      () async {
        loginAs(userA);
        adapter.responder = (_) async => jsonResponse({'id': 1});
        final run = await insertRun(uid: userA, status: 'in_progress');
        final route = [
          GpsPoint(latitude: 1, longitude: 2, timestamp: DateTime.utc(2026)),
        ];

        final completed = await repository.completeRun(
          run.localId,
          duration: 500,
          distance: 3.2,
          averagePace: 2.6,
          calories: 250,
          route: route,
        );

        expect(completed.status, 'completed');
        expect(completed.duration, 500);
        expect(completed.distance, 3.2);
        expect(completed.averagePace, 2.6);
        expect(completed.calories, 250);
        expect(completed.route, hasLength(1));
        expect(completed.route.single.latitude, 1);
        expect(completed.route.single.longitude, 2);

        await Future.wait(scheduledBackgroundSyncs);
      },
    );
  });

  // ============ 16. GPS update conventions ============

  group('GPS update conventions', () {
    test(
      'updateRoute/updateDistance stale calls silently no-op (req 16)',
      () async {
        loginAs(userA);
        final run = await insertRun(uid: userA, status: 'in_progress');
        logout();

        await repository.updateRoute(run.localId, [
          GpsPoint(latitude: 9, longitude: 9, timestamp: DateTime.utc(2026)),
        ]);
        await repository.updateDistance(run.localId, 99);

        final stored = await isar.localRunSessions.get(run.localId);
        expect(stored!.route, isEmpty);
        expect(stored.distance, isNull);
      },
    );

    test('updateRoute/updateDistance on a current owned row still apply '
        'normally', () async {
      loginAs(userA);
      final run = await insertRun(uid: userA, status: 'in_progress');

      await repository.updateRoute(run.localId, [
        GpsPoint(latitude: 9, longitude: 9, timestamp: DateTime.utc(2026)),
      ]);
      await repository.updateDistance(run.localId, 2.5);

      final stored = await isar.localRunSessions.get(run.localId);
      expect(stored!.route, hasLength(1));
      expect(stored.distance, 2.5);
    });
  });

  // ============ 17-18. Cancellation and ordinary failures ============

  group('cancellation and ordinary failures', () {
    test('cancellation is an expected lifecycle outcome: pending state intact, '
        'nothing logged as a failure (req 17)', () async {
      loginAs(userA);
      final run = await insertRun(uid: userA, status: 'draft');

      adapter.responder = (_) => Completer<ResponseBody>().future;

      final captured = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };

      try {
        final dispatched = adapter.nextDispatch();
        await repository.startRun(run.localId);
        await dispatched;
        expect(adapter.capturedRequests, hasLength(1));

        sessionCoordinator.cancelCurrentGeneration();
        await scheduledBackgroundSyncs.single;
      } finally {
        debugPrint = originalDebugPrint;
      }

      final stored = await isar.localRunSessions.get(run.localId);
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_update');
      expect(
        captured.any((line) => line.contains('Background sync failed')),
        isFalse,
      );
    });

    test('an ordinary network failure logs and preserves pending state without '
        'throwing to the caller (req 18)', () async {
      loginAs(userA);
      final run = await insertRun(uid: userA, status: 'draft');
      adapter.responder =
          (_) async => ResponseBody.fromString('{"error":"boom"}', 500);

      final started = await repository.startRun(run.localId);
      expect(started.status, 'in_progress');

      await scheduledBackgroundSyncs.single;

      final stored = await isar.localRunSessions.get(run.localId);
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_update');
    });
  });

  // ============ 19. Background determinism sanity ============

  test('exactly one background operation is scheduled per online mutating call '
      '(req 19)', () async {
    loginAs(userA);
    adapter.responder = (_) async => jsonResponse({'id': 1});

    await repository.createRunSession();

    expect(
      scheduledBackgroundSyncs,
      hasLength(1),
      reason:
          'awaiting scheduledBackgroundSyncs.single elsewhere in this '
          'file is only a valid completion signal if exactly one '
          'background operation is ever scheduled per call - this pins '
          'that invariant explicitly',
    );
    await scheduledBackgroundSyncs.single;
  });

  // ============ 20. Direct UI compatibility (run_detail_screen.dart) ============

  group('direct UI compatibility (run_detail_screen.dart)', () {
    test('getRunSession returns null for a missing or foreign id, matching the '
        'existing "not found" UI state (req 20)', () async {
      loginAs(userA);
      final foreign = await insertRun(uid: userB);

      expect(await repository.getRunSession(999999), isNull);
      expect(await repository.getRunSession(foreign.localId), isNull);
    });

    test('deleteRun returns a bool without throwing for a foreign id, matching '
        "run_detail_screen's ignored-return-value usage (req 20)", () async {
      loginAs(userA);
      final foreign = await insertRun(uid: userB, serverId: 5);

      expect(await repository.deleteRun(foreign.localId), isFalse);
    });
  });
}

/// A deterministic fake Dio transport. Records every [RequestOptions] Dio
/// actually attempts to send, so tests can assert on the real
/// headers/extra/cancelToken the real interceptor pipeline produced - never
/// a stub of the interceptor itself. Mirrors the fake adapter used in
/// session_repository_session_ownership_test.dart.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  Future<ResponseBody> Function(RequestOptions options)? responder;

  Completer<void>? _dispatchSignal;

  /// Returns a Future that completes deterministically the next time
  /// [fetch] is invoked - i.e. the moment a request actually reaches this
  /// fake transport - distinct from the response being produced or
  /// consumed. Must be called before the operation that will trigger the
  /// dispatch, so the signal can never be missed.
  Future<void> nextDispatch() {
    final completer = Completer<void>();
    _dispatchSignal = completer;
    return completer.future;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
    _dispatchSignal?.complete();
    _dispatchSignal = null;
    final respond = responder;
    if (respond != null) {
      return respond(options);
    }
    return Future.value(
      ResponseBody.fromString(
        '{}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}
