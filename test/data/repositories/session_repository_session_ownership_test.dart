import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'session_repository_session_ownership_test.mocks.dart';

@GenerateMocks([AuthService, ConnectivityService])
/// Proves that SessionRepository is fully session-bound (every HTTP call,
/// foreground and background, carries the session that started the
/// operation) and locally ownership-safe (every ID-based lookup, and every
/// Exercise/ExerciseSet graph write, is scoped to the calling user).
///
/// Uses a REAL [ApiService] wired to a fake [HttpClientAdapter] - mirrors
/// `nutrition_repository_background_session_test.dart` - so credential
/// pinning and dispatch-time staleness rejection are proven against the
/// real production interceptor pipeline, not a stub of it.
///
/// ## Deterministic synchronization
///
/// No test in this file uses a wall-clock delay to prove detached work has
/// finished. Two precise signals replace that:
///
/// - [_FakeHttpClientAdapter.nextDispatch] completes the instant the fake
///   transport's `fetch()` is actually invoked - "the request reached the
///   transport," distinct from "the response has been produced/consumed."
///   Used when a test needs to act (assert, mutate state, complete a
///   manually-held response) while a response is still pending.
/// - `scheduledBackgroundSyncs` collects the exact `Future<void>` each
///   [SessionRepository._backgroundSync] call hands back via the
///   `onBackgroundSyncScheduledForTesting` seam - it completes only once
///   that specific detached operation's HTTP dispatch, success/error
///   handling, and any acknowledgment writeTxn or guarded stale/cancelled
///   exit have ALL finished. Awaiting `scheduledBackgroundSyncs.single`
///   is both the completion wait and an implicit assertion that exactly
///   one background operation was scheduled.
///
/// A handful of tests need neither: `addExerciseToSession` has no detached
/// path of its own (both its online attempt and its offline fallback are
/// awaited sequentially inside the method body), so directly awaiting the
/// call already is complete, deterministic synchronization; and any call
/// that throws before ever reaching `_backgroundSync` leaves
/// `scheduledBackgroundSyncs` empty, which is itself the deterministic
/// proof that nothing was scheduled.
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
  late SessionRepository repository;
  late List<Future<void>> scheduledBackgroundSyncs;

  const userA = 1;
  const userB = 2;

  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_repo_owner_');
    isar = await Isar.open(
      [
        LocalSessionSchema,
        LocalExerciseSchema,
        LocalExerciseSetSchema,
        LocalExerciseTemplateSchema,
      ],
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

    repository = SessionRepository(
      apiService,
      localDb,
      mockConnectivity,
      mockAuthService,
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
    repository.insideBackgroundWriteTxnForTesting = null;
    repository.beforeChildDeleteForTesting = null;
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

  Future<LocalSession> insertSession({
    int uid = userA,
    int? serverId,
    int? explicitLocalId,
    String status = 'draft',
    String name = 'Original',
    DateTime? date,
    bool? isSynced,
    String? syncStatus,
    int? version,
    int? programWorkoutId,
    DateTime? pausedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    int? duration,
  }) async {
    final session = LocalSession(
      serverId: serverId,
      userId: uid,
      date: date ?? DateTime(2026, 1, 1),
      name: name,
      status: status,
      isSynced: isSynced ?? (serverId != null),
      syncStatus:
          syncStatus ?? (serverId != null ? 'synced' : 'pending_create'),
      lastModifiedLocal: DateTime.now().toUtc(),
      version: version,
      programWorkoutId: programWorkoutId,
      pausedAt: pausedAt,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
    );
    if (explicitLocalId != null) {
      session.localId = explicitLocalId;
    }
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<LocalExercise> insertExercise({
    required int sessionLocalId,
    int? serverId,
    int? explicitLocalId,
    String name = 'Bench Press',
  }) async {
    final exercise = LocalExercise(
      serverId: serverId,
      sessionLocalId: sessionLocalId,
      name: name,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now().toUtc(),
    );
    if (explicitLocalId != null) {
      exercise.localId = explicitLocalId;
    }
    await isar.writeTxn(() => isar.localExercises.put(exercise));
    return exercise;
  }

  Future<LocalExerciseSet> insertExerciseSet({
    required int exerciseLocalId,
    int? serverId,
  }) async {
    final set = LocalExerciseSet(
      serverId: serverId,
      exerciseLocalId: exerciseLocalId,
      setNumber: 1,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now().toUtc(),
    );
    await isar.writeTxn(() => isar.localExerciseSets.put(set));
    return set;
  }

  Map<String, dynamic> sessionJson({
    required int id,
    required int userId,
    String name = 'Server session',
    String status = 'draft',
    DateTime? date,
    List<Map<String, dynamic>> exercises = const [],
    int version = 1,
  }) => {
    'id': id,
    'userId': userId,
    'date':
        '${(date ?? DateTime(2026, 1, 1)).year.toString().padLeft(4, '0')}-'
        '${(date ?? DateTime(2026, 1, 1)).month.toString().padLeft(2, '0')}-'
        '${(date ?? DateTime(2026, 1, 1)).day.toString().padLeft(2, '0')}',
    'duration': null,
    'notes': null,
    'type': null,
    'name': name,
    'status': status,
    'startedAt': null,
    'completedAt': null,
    'pausedAt': null,
    'exercises': exercises,
    'programId': null,
    'programWorkoutId': null,
    'version': version,
  };

  Map<String, dynamic> exerciseJson({
    required int id,
    required int sessionId,
    String name = 'Bench Press',
  }) => {
    'id': id,
    'sessionId': sessionId,
    'name': name,
    'sortOrder': 0,
    'duration': null,
    'restTime': null,
    'notes': null,
    'exerciseTemplateId': null,
    'exerciseSets': <dynamic>[],
    'version': 1,
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
      contains('User not authenticated'),
    ),
  );

  Matcher throwsNotFound(int id) => throwsA(
    isA<Exception>().having(
      (e) => e.toString(),
      'message',
      contains('Session not found: $id'),
    ),
  );

  // ============ 1-5. Context and credentials ============

  group('context and credentials', () {
    test(
      'logged-out operations perform no HTTP/local mutation (test 1)',
      () async {
        final s = await insertSession(serverId: 10);

        await expectLater(
          () => repository.updateSessionName(10, 'Renamed'),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.pauseSession(10, DateTime.now().toUtc()),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.resumeSession(10, DateTime.now().toUtc()),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.updateSessionStatus(10, 'in_progress'),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.archiveSession(10),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.deleteSession(10),
          throwsNotAuthenticated(),
        );
        await expectLater(
          () => repository.updateWorkoutDate(10, DateTime(2026, 2, 1)),
          throwsNotAuthenticated(),
        );
        expect(await repository.getSessions(), isEmpty);
        expect(await repository.getInProgressSessions(), isEmpty);

        expect(scheduledBackgroundSyncs, isEmpty);
        expect(adapter.capturedRequests, isEmpty);
        final stored = await isar.localSessions.get(s.localId);
        expect(stored!.name, 'Original');
        expect(stored.syncStatus, 'synced');
      },
    );

    test(
      'the JWT is captured exactly once, at operation entry, and reused for '
      'the background dispatch - never re-read from storage later (test 2)',
      () async {
        loginAs(userA);
        await insertSession(uid: userA, serverId: 20);

        // Each call to getToken() returns a DISTINCT value, so a second,
        // later read (e.g. a background closure lazily recapturing its own
        // context instead of reusing the one from operation entry) would be
        // caught red-handed by a mismatching header.
        var tokenCallCount = 0;
        when(mockAuthService.getToken()).thenAnswer((_) async {
          tokenCallCount++;
          return 'jwt-call-$tokenCallCount';
        });

        await repository.pauseSession(20, DateTime.now().toUtc());
        await scheduledBackgroundSyncs.single;

        expect(adapter.capturedRequests, hasLength(1));
        expect(
          adapter.capturedRequests.single.headers['Authorization'],
          'Bearer jwt-call-1',
          reason:
              'the background dispatch must carry the JWT captured at '
              'operation entry, not a fresh read taken later',
        );
        expect(
          tokenCallCount,
          1,
          reason: 'getToken() must be read exactly once for this operation',
        );
        final epochToken =
            adapter.capturedRequests.single.extra[ApiService
                    .sessionEpochExtraKey]
                as UserSessionToken;
        expect(epochToken.userId, userA);
      },
    );

    test('A stale before dispatch sends no request (test 3)', () async {
      loginAs(userA);
      await insertSession(uid: userA, serverId: 21);

      repository.beforeBackgroundHttpDispatchForTesting = () async {
        logout();
      };

      await repository.pauseSession(21, DateTime.now().toUtc());
      await scheduledBackgroundSyncs.single;

      expect(adapter.capturedRequests, isEmpty);
    });

    test('B logging in (not logging out) between scheduling and dispatch never '
        'lets the background push adopt B\'s session (test 3b)', () async {
      loginAs(userA);
      await insertSession(uid: userA, serverId: 24);

      // If the background push captured its context lazily at dispatch
      // time instead of reusing the one captured at operation entry, this
      // would wrongly succeed under B instead of being rejected as stale
      // for A.
      repository.beforeBackgroundHttpDispatchForTesting = () async {
        loginAs(userB);
      };

      await repository.pauseSession(24, DateTime.now().toUtc());
      await scheduledBackgroundSyncs.single;

      expect(
        adapter.capturedRequests,
        isEmpty,
        reason:
            'A\'s pinned context is stale once B is active, so ApiService '
            'must reject dispatch outright rather than a lazily-recaptured '
            'context silently sending the request under B',
      );
    });

    test(
      'a HTTP success after B login cannot acknowledge locally (test 4)',
      () async {
        loginAs(userA);
        final s = await insertSession(uid: userA, serverId: 22);
        final logB = await insertSession(uid: userB, serverId: 999);

        final responseCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => responseCompleter.future;

        final dispatched = adapter.nextDispatch();
        await repository.pauseSession(22, DateTime.now().toUtc());
        await dispatched;
        expect(adapter.capturedRequests, hasLength(1));

        loginAs(userB);
        responseCompleter.complete(jsonResponse({}));
        await scheduledBackgroundSyncs.single;

        final stored = await isar.localSessions.get(s.localId);
        expect(stored!.isSynced, isFalse);
        expect(stored.syncStatus, 'pending_update');

        final storedB = await isar.localSessions.get(logB.localId);
        expect(storedB, isNotNull);
      },
    );

    test('the post-HTTP checkpoint rejects before ever running the '
        'after-response hook, not relying on a later redundant check '
        '(test 4b)', () async {
      loginAs(userA);
      await insertSession(uid: userA, serverId: 25);

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;
      var hookFired = false;
      repository.afterBackgroundHttpResponseForTesting = () async {
        hookFired = true;
      };

      final dispatched = adapter.nextDispatch();
      await repository.pauseSession(25, DateTime.now().toUtc());
      await dispatched;
      expect(adapter.capturedRequests, hasLength(1));

      logout();
      responseCompleter.complete(jsonResponse({}));
      await scheduledBackgroundSyncs.single;

      expect(
        hookFired,
        isFalse,
        reason:
            'the post-HTTP checkpoint must reject and return immediately '
            'once the response arrives under a stale session, before ever '
            'reaching the re-resolve step (whose own internal epoch check '
            'would otherwise mask a missing post-HTTP checkpoint)',
      );
    });

    test('cancellation is an expected lifecycle outcome: pending state intact, '
        'nothing logged as a failure (test 5)', () async {
      loginAs(userA);
      await insertSession(uid: userA, serverId: 23);

      adapter.responder = (_) => Completer<ResponseBody>().future;

      final captured = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };

      try {
        final dispatched = adapter.nextDispatch();
        await repository.pauseSession(23, DateTime.now().toUtc());
        await dispatched;
        expect(adapter.capturedRequests, hasLength(1));

        sessionCoordinator.cancelCurrentGeneration();
        await scheduledBackgroundSyncs.single;
      } finally {
        debugPrint = originalDebugPrint;
      }

      final stored =
          await isar.localSessions.filter().serverIdEqualTo(23).findFirst();
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_update');
      expect(
        captured.any((line) => line.contains('Background sync failed')),
        isFalse,
      );
    });
  });

  // ============ 6-10. ID ownership ============

  group('ID ownership', () {
    test(
      'User A cannot mutate User B\'s session via server ID (test 6)',
      () async {
        loginAs(userA);
        final b = await insertSession(uid: userB, serverId: 50);

        await expectLater(
          () => repository.updateSessionName(50, 'Hijacked'),
          throwsNotFound(50),
        );

        final stored = await isar.localSessions.get(b.localId);
        expect(stored!.name, 'Original');
      },
    );

    test(
      'User A cannot mutate User B\'s session via local ID (test 7)',
      () async {
        loginAs(userA);
        final b = await insertSession(uid: userB);

        await expectLater(
          () => repository.updateSessionName(b.localId, 'Hijacked'),
          throwsNotFound(b.localId),
        );

        final stored = await isar.localSessions.get(b.localId);
        expect(stored!.name, 'Original');
      },
    );

    test('a foreign server-ID candidate does not block an owned local-ID '
        'fallback (test 8)', () async {
      loginAs(userA);
      // A foreign row whose serverId happens to equal 42.
      await insertSession(uid: userB, serverId: 42);
      // An owned, never-synced row whose LOCAL Isar id also happens to be 42.
      final ownedLocal = await insertSession(uid: userA, explicitLocalId: 42);

      await repository.updateSessionName(42, 'Mine now');

      final stored = await isar.localSessions.get(ownedLocal.localId);
      expect(stored!.userId, userA);
      expect(stored.name, 'Mine now');

      final foreign =
          await isar.localSessions
              .filter()
              .serverIdEqualTo(42)
              .userIdEqualTo(userB)
              .findFirst();
      expect(foreign!.name, 'Original');
    });

    test(
      'a same-user local-only session still works offline (test 9)',
      () async {
        loginAs(userA);
        when(mockConnectivity.isOnline).thenReturn(false);
        final s = await insertSession(uid: userA);

        await repository.updateSessionName(s.localId, 'Local edit');

        final stored = await isar.localSessions.get(s.localId);
        expect(stored!.name, 'Local edit');
        expect(stored.syncStatus, 'pending_create');
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test(
      'a missing target preserves the existing not-found convention (test 10)',
      () async {
        loginAs(userA);

        await expectLater(
          () => repository.updateSessionName(123456, 'X'),
          throwsNotFound(123456),
        );
      },
    );
  });

  // ============ 11-16. Mutation ownership ============

  group('mutation ownership', () {
    test('updateSessionStatus ownership (test 11)', () async {
      loginAs(userA);
      final b = await insertSession(uid: userB, serverId: 60, status: 'draft');

      await expectLater(
        () => repository.updateSessionStatus(60, 'in_progress'),
        throwsNotFound(60),
      );

      final stored = await isar.localSessions.get(b.localId);
      expect(stored!.status, 'draft');
    });

    test('pauseSession ownership and pausedAt behavior (test 12)', () async {
      loginAs(userA);
      final b = await insertSession(
        uid: userB,
        serverId: 61,
        status: 'in_progress',
      );

      await expectLater(
        () => repository.pauseSession(61, DateTime.utc(2026, 1, 1)),
        throwsNotFound(61),
      );

      final stored = await isar.localSessions.get(b.localId);
      expect(stored!.pausedAt, isNull);

      final own = await insertSession(
        uid: userA,
        serverId: 62,
        status: 'in_progress',
      );
      await repository.pauseSession(62, DateTime.utc(2026, 1, 2));
      final storedOwn = await isar.localSessions.get(own.localId);
      expect(
        storedOwn!.pausedAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 2)),
        isTrue,
      );
      // Let the fire-and-forget background push settle before tearDown
      // closes Isar out from under it.
      await scheduledBackgroundSyncs.single;
    });

    test(
      'resumeSession ownership and clearPausedAt behavior (test 13)',
      () async {
        loginAs(userA);
        final b = await insertSession(
          uid: userB,
          serverId: 63,
          status: 'in_progress',
          pausedAt: DateTime.utc(2026, 1, 1),
        );

        await expectLater(
          () => repository.resumeSession(63, DateTime.utc(2026, 1, 3)),
          throwsNotFound(63),
        );

        final stored = await isar.localSessions.get(b.localId);
        expect(stored!.pausedAt, isNotNull);

        final own = await insertSession(
          uid: userA,
          serverId: 64,
          status: 'in_progress',
          pausedAt: DateTime.utc(2026, 1, 1),
        );
        await repository.resumeSession(64, DateTime.utc(2026, 1, 4));
        final storedOwn = await isar.localSessions.get(own.localId);
        expect(storedOwn!.pausedAt, isNull);
        expect(
          storedOwn.startedAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 4)),
          isTrue,
        );
        // Let the fire-and-forget background push settle before tearDown
        // closes Isar out from under it.
        await scheduledBackgroundSyncs.single;
      },
    );

    test('updateSessionName ownership (test 14)', () async {
      loginAs(userA);
      final b = await insertSession(uid: userB, serverId: 65);

      await expectLater(
        () => repository.updateSessionName(65, 'Hijacked'),
        throwsNotFound(65),
      );

      final stored = await isar.localSessions.get(b.localId);
      expect(stored!.name, 'Original');
    });

    test('updateWorkoutDate ownership (test 15)', () async {
      loginAs(userA);
      final b = await insertSession(uid: userB, serverId: 66);

      await expectLater(
        () => repository.updateWorkoutDate(66, DateTime(2026, 5, 5)),
        throwsNotFound(66),
      );

      final stored = await isar.localSessions.get(b.localId);
      expect(stored!.date, DateTime(2026, 1, 1));
    });

    test('deleteSession, archiveSession, addExerciseToSession ownership '
        '(test 16)', () async {
      loginAs(userA);
      final bDelete = await insertSession(uid: userB, serverId: 67);
      final bArchive = await insertSession(uid: userB, serverId: 68);
      final bExercise = await insertSession(uid: userB, serverId: 69);

      await expectLater(() => repository.deleteSession(67), throwsNotFound(67));
      await expectLater(
        () => repository.archiveSession(68),
        throwsNotFound(68),
      );
      await expectLater(
        () => repository.addExerciseToSession(69, 1),
        throwsNotFound(69),
      );

      expect(await isar.localSessions.get(bDelete.localId), isNotNull);
      expect((await isar.localSessions.get(bArchive.localId))!.status, 'draft');
      expect(
        await isar.localExercises
            .filter()
            .sessionLocalIdEqualTo(bExercise.localId)
            .count(),
        0,
      );
    });
  });

  // ============ 17-23. Background behavior ============

  group('background behavior', () {
    test('getSessions refresh scheduled by A cannot cache after B login '
        '(test 17)', () async {
      loginAs(userA);
      await insertSession(uid: userA, serverId: 70, name: 'A session');

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      await repository.getSessions();
      await dispatched;
      expect(adapter.capturedRequests, hasLength(1));

      loginAs(userB);
      responseCompleter.complete(
        jsonResponse([
          sessionJson(id: 70, userId: userA, name: 'Server renamed A'),
        ]),
      );
      await scheduledBackgroundSyncs.single;

      final stored =
          await isar.localSessions.filter().serverIdEqualTo(70).findFirst();
      expect(stored!.name, 'A session');
    });

    test(
      'a refresh does not overwrite a pending/conflict local row (test 18)',
      () async {
        loginAs(userA);
        await insertSession(
          uid: userA,
          serverId: 71,
          name: 'Locally edited',
          isSynced: false,
          syncStatus: 'pending_update',
        );
        adapter.responder =
            (_) async => jsonResponse([
              sessionJson(id: 71, userId: userA, name: 'Server value'),
            ]);

        await repository.getSessions();
        await scheduledBackgroundSyncs.single;

        final stored =
            await isar.localSessions.filter().serverIdEqualTo(71).findFirst();
        expect(stored!.name, 'Locally edited');
      },
    );

    test('createSession success acknowledges only A\'s stable local row '
        '(test 19)', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse(sessionJson(id: 900, userId: userA));

      final created = await repository.createSession(
        _sessionModel(userId: userA, name: 'New workout'),
      );
      await scheduledBackgroundSyncs.single;

      final stored = await isar.localSessions.get(created.id);
      expect(stored!.serverId, 900);
      expect(stored.isSynced, isTrue);
    });

    test(
      'a stale create success cannot set serverId/isSynced (test 20)',
      () async {
        loginAs(userA);
        final responseCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => responseCompleter.future;

        final dispatched = adapter.nextDispatch();
        final created = await repository.createSession(
          _sessionModel(userId: userA, name: 'New workout'),
        );
        await dispatched;
        expect(adapter.capturedRequests, hasLength(1));

        logout();
        responseCompleter.complete(
          jsonResponse(sessionJson(id: 901, userId: userA)),
        );
        await scheduledBackgroundSyncs.single;

        final stored = await isar.localSessions.get(created.id);
        expect(stored!.serverId, isNull);
        expect(stored.isSynced, isFalse);
      },
    );

    test('SessionUpdateSyncHelper PUT and its recovery GET use the identical '
        'context (test 21)', () async {
      loginAs(userA);
      final s = await insertSession(uid: userA, serverId: 72, version: 5);

      adapter.responder = (options) async {
        if (options.method == 'PUT') {
          // Non-map success body forces the helper's recovery GET path.
          return jsonResponse(null);
        }
        return jsonResponse(
          sessionJson(id: 72, userId: userA, name: 'Renamed', version: 6),
        );
      };

      await repository.updateSessionName(72, 'Renamed');
      await scheduledBackgroundSyncs.single;

      expect(adapter.capturedRequests, hasLength(2));
      final putToken =
          adapter.capturedRequests[0].extra[ApiService.sessionEpochExtraKey]
              as UserSessionToken;
      final getToken =
          adapter.capturedRequests[1].extra[ApiService.sessionEpochExtraKey]
              as UserSessionToken;
      expect(putToken, getToken);

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.isSynced, isTrue);
      expect(stored.version, 6);
    });

    test('a stale helper result cannot acknowledge (test 22)', () async {
      loginAs(userA);
      final s = await insertSession(uid: userA, serverId: 73, version: 5);

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      await repository.updateSessionName(73, 'Renamed');
      await dispatched;
      expect(adapter.capturedRequests, hasLength(1));

      logout();
      responseCompleter.complete(
        jsonResponse(
          sessionJson(id: 73, userId: userA, name: 'Renamed', version: 6),
        ),
      );
      await scheduledBackgroundSyncs.single;

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.version, 5);
      expect(stored.isSynced, isFalse);
    });

    test('an ordinary 409 conflict is still recorded, not silently dropped '
        '(test 23)', () async {
      loginAs(userA);
      final s = await insertSession(uid: userA, serverId: 74, version: 5);

      adapter.responder =
          (_) async => jsonResponse({
            'serverData': {'name': 'Server wins'},
            'currentVersion': 9,
          }, statusCode: 409);

      await repository.updateSessionName(74, 'My rename');
      await scheduledBackgroundSyncs.single;

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.syncStatus, 'conflict');
      expect(stored.conflictServerVersion, 9);
      expect(stored.name, 'My rename');
    });
  });

  // ============ 24-27. Session graph ownership ============

  group('session graph ownership', () {
    test('a foreign local row sharing a server ID is never overwritten by a '
        'refresh cascade (test 24)', () async {
      loginAs(userA);
      // A row with serverId 80 already exists, but owned by B (e.g. an
      // extremely unlikely ID collision/replay). A's own refresh must
      // never claim it.
      final foreign = await insertSession(
        uid: userB,
        serverId: 80,
        name: 'Belongs to B',
      );
      adapter.responder =
          (_) async => jsonResponse([
            sessionJson(id: 80, userId: userA, name: 'A tries to claim'),
          ]);

      await repository.getSessions();
      await scheduledBackgroundSyncs.single;

      final stored = await isar.localSessions.get(foreign.localId);
      expect(stored!.userId, userB);
      expect(stored.name, 'Belongs to B');
    });

    test('cascade-delete cleanup never touches another user\'s Session/'
        'Exercise/ExerciseSet rows (test 25)', () async {
      loginAs(userA);
      // Owned by A, will be reported as removed by the empty server list.
      final aSession = await insertSession(uid: userA, serverId: 81);
      final aExercise = await insertExercise(
        sessionLocalId: aSession.localId,
        serverId: 810,
      );
      await insertExerciseSet(
        exerciseLocalId: aExercise.localId,
        serverId: 8100,
      );

      // Completely unrelated, owned by B - must survive untouched.
      final bSession = await insertSession(uid: userB, serverId: 82);
      final bExercise = await insertExercise(
        sessionLocalId: bSession.localId,
        serverId: 820,
      );
      final bSet = await insertExerciseSet(
        exerciseLocalId: bExercise.localId,
        serverId: 8200,
      );

      adapter.responder = (_) async => jsonResponse(<dynamic>[]);

      await repository.getSessions();
      await scheduledBackgroundSyncs.single;

      expect(await isar.localSessions.get(aSession.localId), isNull);
      expect(await isar.localExercises.get(aExercise.localId), isNull);

      expect(await isar.localSessions.get(bSession.localId), isNotNull);
      expect(await isar.localExercises.get(bExercise.localId), isNotNull);
      expect(await isar.localExerciseSets.get(bSet.localId), isNotNull);
    });

    test('an exercise reparented away from the session mid-deletion keeps its '
        'sets (grandparent-ownership recheck, test 25b)', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA);
      final exercise = await insertExercise(sessionLocalId: session.localId);
      final set = await insertExerciseSet(exerciseLocalId: exercise.localId);

      // A foreign session the exercise gets reassigned to right as the
      // deletion transaction reaches it - simulates the exact race the
      // grandparent recheck exists to close.
      final foreignSession = await insertSession(uid: userB);
      repository.beforeChildDeleteForTesting = () async {
        // Already running inside the repository's own active writeTxn (same
        // Isar instance) - write directly, no nested writeTxn.
        final reparented = await isar.localExercises.get(exercise.localId);
        reparented!.sessionLocalId = foreignSession.localId;
        await isar.localExercises.put(reparented);
      };

      // deleteSession has no detached path either - it's fully awaited,
      // foreground, all the way through.
      await repository.deleteSession(session.localId);

      expect(
        await isar.localExerciseSets.get(set.localId),
        isNotNull,
        reason:
            'the set must survive because its exercise no longer belongs '
            'to the session being deleted by the time the delete runs',
      );
      expect(await isar.localExercises.get(exercise.localId), isNotNull);
    });

    test('a stale graph response cannot replace B\'s cache after A\'s session '
        'ends (test 26)', () async {
      loginAs(userA);
      await insertSession(uid: userA, serverId: 83, name: 'A original');

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      await repository.getSessions();
      await dispatched;

      loginAs(userB);
      final bLocal = await insertSession(uid: userB, name: 'B local');

      responseCompleter.complete(
        jsonResponse([sessionJson(id: 83, userId: userA, name: 'A refreshed')]),
      );
      await scheduledBackgroundSyncs.single;

      final stored =
          await isar.localSessions.filter().serverIdEqualTo(83).findFirst();
      expect(stored!.name, 'A original');
      final bStored = await isar.localSessions.get(bLocal.localId);
      expect(bStored!.name, 'B local');
    });

    test('parent reassignment between HTTP dispatch and acknowledgment is '
        'detected for addExerciseToSession (test 27)', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 84);

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      final future = repository.addExerciseToSession(84, 1);
      await dispatched;
      expect(adapter.capturedRequests, hasLength(1));

      // Simulate the parent session being reassigned to a different user
      // while the request is in flight.
      final reassigned = await isar.localSessions.get(session.localId);
      reassigned!.userId = userB;
      await isar.writeTxn(() => isar.localSessions.put(reassigned));

      responseCompleter.complete(
        jsonResponse(exerciseJson(id: 950, sessionId: 84)),
      );
      // addExerciseToSession has no detached/background path of its own -
      // both the online write attempt and the offline fallback it falls
      // through to on SessionStaleException are awaited sequentially
      // inside the method body, so awaiting `future` is complete,
      // deterministic synchronization on its own.
      await future; // falls through to offline creation

      final exercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(session.localId)
              .findAll();
      expect(
        exercises.any((e) => e.serverId == 950),
        isFalse,
        reason:
            'the exercise must not be cached under a session that was '
            'reassigned to a different user between dispatch and response',
      );
    });

    test('a session reassigned between the pre-transaction ownership check '
        'and the write is rejected by the inside-writeTxn recheck, not the '
        'pre-transaction check (test 27b)', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 91);
      final foreignSession = await insertSession(uid: userB);

      adapter.responder =
          (_) async => jsonResponse(exerciseJson(id: 961, sessionId: 91));

      // Fires as the FIRST statement inside the online-success writeTxn -
      // i.e. strictly after the pre-transaction _isSessionOwnedByLocalId
      // check has already passed - to prove the inside-transaction check
      // is what catches this, not a coincidence of the earlier one.
      repository.insideWriteTxnForTesting = () async {
        final reassigned = await isar.localSessions.get(session.localId);
        reassigned!.userId = userB;
        await isar.localSessions.put(reassigned);
      };

      // addExerciseToSession has no detached/background path of its own -
      // both the online write attempt and the offline fallback it falls
      // through to on SessionStaleException are awaited sequentially
      // inside the method body, so this single await is a complete,
      // deterministic synchronization point: every operation capable of
      // writing a LocalExercise has already run its course (write or
      // guarded no-op) by the time it resolves. No delay is needed or used.
      await repository.addExerciseToSession(91, 1);

      final ownExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(session.localId)
              .findAll();
      expect(
        ownExercises,
        isEmpty,
        reason:
            'no Exercise may be inserted once the session no longer '
            'belongs to the caller at the moment of the write',
      );

      final foreignExercises =
          await isar.localExercises
              .filter()
              .sessionLocalIdEqualTo(foreignSession.localId)
              .findAll();
      expect(
        foreignExercises,
        isEmpty,
        reason:
            'nothing may be attached to the replacement/foreign '
            'session either',
      );

      // No unrelated row changed - both sessions still exist exactly as
      // before, only their ownership relationship changed by the test
      // itself.
      expect(await isar.localSessions.get(session.localId), isNotNull);
      expect(await isar.localSessions.get(foreignSession.localId), isNotNull);
    });
  });

  // ============ 28-31. Transaction race protection ============

  group('transaction race protection', () {
    test(
      'invalidation before writeTxn prevents the mutation (test 28)',
      () async {
        loginAs(userA);
        final s = await insertSession(uid: userA);
        var enteredTxn = false;

        repository.beforeWriteTxnForTesting = () async {
          sessionEpoch.invalidate();
        };
        repository.insideWriteTxnForTesting = () async {
          enteredTxn = true;
        };

        await expectLater(
          () => repository.updateSessionName(s.localId, 'Too late'),
          throwsNotAuthenticated(),
        );

        expect(enteredTxn, isFalse);
        final stored = await isar.localSessions.get(s.localId);
        expect(stored!.name, 'Original');
      },
    );

    test('invalidation after the write transaction commits prevents scheduling '
        'the background push (test 28b)', () async {
      loginAs(userA);
      final s = await insertSession(uid: userA, serverId: 87);

      repository.afterWriteTxnForTesting = () async {
        sessionEpoch.invalidate();
      };

      await expectLater(
        () => repository.pauseSession(87, DateTime.utc(2026, 1, 1)),
        throwsNotAuthenticated(),
      );

      // The write itself already committed before staleness was
      // introduced.
      final stored = await isar.localSessions.get(s.localId);
      expect(
        stored!.pausedAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 1)),
        isTrue,
      );

      // Nothing should have been scheduled to sync it - the throw above
      // happens before pauseSession ever reaches _backgroundSync, so
      // scheduledBackgroundSyncs stays empty. That emptiness is itself the
      // deterministic proof: there is nothing async left pending to wait
      // for, so there is nothing to await before asserting.
      expect(scheduledBackgroundSyncs, isEmpty);
      expect(adapter.capturedRequests, isEmpty);
    });

    test('invalidation while writeTxn waits prevents resurrection after '
        'clearAll (test 29)', () async {
      loginAs(userA);
      final s = await insertSession(uid: userA);

      repository.insideWriteTxnForTesting = () async {
        sessionEpoch.invalidate();
        await isar.clear();
      };

      try {
        await repository.updateSessionName(s.localId, 'Too late');
      } catch (_) {
        // Covered by the "after writeTxn" checkpoint separately.
      }

      final stored = await isar.localSessions.get(s.localId);
      expect(
        stored,
        isNull,
        reason:
            'the in-transaction check must prevent put() from '
            'resurrecting the row clearAll() just removed',
      );
    });

    test('a response cannot acknowledge a row reassigned to a different user '
        '(test 30)', () async {
      loginAs(userA);
      final s = await insertSession(uid: userA, serverId: 85, version: 1);

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      await repository.pauseSession(85, DateTime.now().toUtc());
      await dispatched;

      // Row reassigned to a different user - epoch is still current for A.
      final reassigned = await isar.localSessions.get(s.localId);
      reassigned!.userId = userB;
      await isar.writeTxn(() => isar.localSessions.put(reassigned));

      responseCompleter.complete(jsonResponse({}));
      await scheduledBackgroundSyncs.single;

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_update');
    });

    test('an ordinary current-session server failure preserves existing retry '
        'behavior (test 31)', () async {
      loginAs(userA);
      final s = await insertSession(uid: userA, serverId: 86);
      adapter.responder =
          (_) async => jsonResponse({'message': 'boom'}, statusCode: 500);

      await repository.pauseSession(86, DateTime.now().toUtc());
      await scheduledBackgroundSyncs.single;

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_update');
    });
  });

  // ============ Foreground CREATE in-flight-edit revision guard ============
  //
  // _syncCreateSessionToServer must not overwrite a local edit / completion /
  // queued delete that raced its POST await, and must never re-create a row
  // once a positive serverId is attached. dispatchedAt is pinned by
  // createSession from the owned row it just persisted, BEFORE scheduling.
  group('foreground CREATE revision guard', () {
    test(
      '17. online createSession schedules exactly one CREATE POST',
      () async {
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse(sessionJson(id: 300, userId: userA));

        await repository.createSession(
          _sessionModel(userId: userA, name: 'Fresh'),
        );
        await scheduledBackgroundSyncs.single;

        expect(adapter.capturedRequests, hasLength(1));
        expect(adapter.capturedRequests.single.method, 'POST');
        expect(adapter.capturedRequests.single.path, ApiConfig.sessions);
      },
    );

    test('18. a normal foreground acknowledgment becomes synced with the '
        'server id and version', () async {
      loginAs(userA);
      adapter.responder =
          (_) async =>
              jsonResponse(sessionJson(id: 301, userId: userA, version: 3));

      final created = await repository.createSession(
        _sessionModel(userId: userA, name: 'Fresh'),
      );
      await scheduledBackgroundSyncs.single;

      final stored = await isar.localSessions.get(created.id);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
      expect(stored.serverId, 301);
      expect(stored.version, 3);
    });

    test(
      '19/20. a completion racing the foreground POST is preserved; the '
      'server id/version are attached and the row stays pending_update',
      () async {
        loginAs(userA);
        final responseCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => responseCompleter.future;

        final dispatched = adapter.nextDispatch();
        final created = await repository.createSession(
          _sessionModel(userId: userA, name: 'Fresh'),
        );
        await dispatched;

        // Completion lands while the CREATE POST is outstanding.
        await repository.updateSessionStatus(
          created.id,
          'completed',
          duration: 3600,
        );

        responseCompleter.complete(
          jsonResponse(sessionJson(id: 302, userId: userA, version: 1)),
        );
        await scheduledBackgroundSyncs.single;

        final stored = await isar.localSessions.get(created.id);
        expect(stored!.serverId, 302);
        expect(stored.version, 1);
        expect(stored.isSynced, isFalse);
        expect(stored.syncStatus, 'pending_update');
        expect(stored.status, 'completed');
        expect(stored.duration, 3600);
      },
    );

    test('21. after the raced ack the next edit issues a PUT, never a second '
        'CREATE POST', () async {
      loginAs(userA);
      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (options) {
        if (options.method == 'PUT') {
          return Future.value(
            jsonResponse(
              sessionJson(
                id: 303,
                userId: userA,
                name: 'Renamed',
                status: 'completed',
                version: 2,
              ),
            ),
          );
        }
        return responseCompleter.future;
      };

      final dispatched = adapter.nextDispatch();
      final created = await repository.createSession(
        _sessionModel(userId: userA, name: 'Fresh'),
      );
      await dispatched;
      await repository.updateSessionStatus(created.id, 'completed');
      responseCompleter.complete(
        jsonResponse(sessionJson(id: 303, userId: userA)),
      );
      await scheduledBackgroundSyncs.single;

      adapter.capturedRequests.clear();
      await repository.updateSessionName(created.id, 'Renamed');
      await scheduledBackgroundSyncs.last;

      expect(
        adapter.capturedRequests.any((r) => r.method == 'POST'),
        isFalse,
        reason: 'the row already carries serverId 303 - never re-create it',
      );
      expect(
        adapter.capturedRequests.any(
          (r) => r.method == 'PUT' && r.path == ApiConfig.sessionById(303),
        ),
        isTrue,
      );
      final stored = await isar.localSessions.get(created.id);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
    });

    test('22. B logging in during the detached CREATE POST causes no '
        'cross-session write', () async {
      loginAs(userA);
      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      final dispatched = adapter.nextDispatch();
      final created = await repository.createSession(
        _sessionModel(userId: userA, name: 'Fresh'),
      );
      await dispatched;

      logout();
      loginAs(userB);
      responseCompleter.complete(
        jsonResponse(sessionJson(id: 304, userId: userA)),
      );
      await scheduledBackgroundSyncs.single;

      final stored = await isar.localSessions.get(created.id);
      expect(stored!.serverId, isNull);
      expect(stored.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_create');
      expect(stored.userId, userA);
    });

    test('23. a foreground CREATE HTTP failure leaves the row pending_create '
        'with no serverId', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse({'message': 'boom'}, statusCode: 500);

      final created = await repository.createSession(
        _sessionModel(userId: userA, name: 'Fresh'),
      );
      await scheduledBackgroundSyncs.single;

      final stored = await isar.localSessions.get(created.id);
      expect(stored!.serverId, isNull);
      expect(stored.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_create');
    });

    test(
      '35. every routine local Session edit advances lastModifiedLocal',
      () async {
        loginAs(userA);
        // Offline so each edit is purely local (no serverId, no push).
        when(mockConnectivity.isOnline).thenReturn(false);
        final created = await repository.createSession(
          _sessionModel(userId: userA, name: 'Fresh'),
        );

        Future<DateTime> rev(int id) async =>
            (await isar.localSessions.get(id))!.lastModifiedLocal;

        final r0 = await rev(created.id);
        await repository.updateSessionStatus(created.id, 'in_progress');
        final r1 = await rev(created.id);
        await repository.updateSessionName(created.id, 'Renamed');
        final r2 = await rev(created.id);
        await repository.pauseSession(created.id, DateTime.now().toUtc());
        final r3 = await rev(created.id);

        expect(r1.isAfter(r0) || r1.isAtSameMomentAs(r0), isTrue);
        expect(r2.isAfter(r1) || r2.isAtSameMomentAs(r1), isTrue);
        expect(r3.isAfter(r2) || r3.isAtSameMomentAs(r2), isTrue);
        // And at least one strictly advanced (edits are not all same-instant).
        expect(r3.isAfter(r0), isTrue);
      },
    );
  });

  // Delete-during-CREATE compensation is NOT part of this PR - the
  // foreground CREATE POST and an independent SyncService pass share no
  // coordination, so a delete of a still-server-id-less session while its
  // CREATE is in flight can orphan a committed server row. That is a
  // pre-existing gap (unchanged `_markForDeletion` hard-deletes the local
  // row) and is deferred to the Session idempotency / operation-identity PR.
  // The reproducing trace lives in
  // `session_create_delete_cross_operation_race_test.dart`.
}

/// Minimal Session-model builder for [SessionRepository.createSession].
/// [userId] is deliberately overridden by the repository regardless of what
/// is passed here - see the class doc comment - but is still required by
/// [Session]'s constructor.
Session _sessionModel({required int userId, required String name}) {
  return Session(
    id: 0,
    userId: userId,
    date: DateTime(2026, 1, 1),
    name: name,
    status: 'draft',
  );
}

/// A deterministic fake Dio transport. Records every [RequestOptions] Dio
/// actually attempts to send, so tests can assert on the real
/// headers/extra/cancelToken the real interceptor pipeline produced - never
/// a stub of the interceptor itself. Mirrors the fake adapter used in
/// nutrition_repository_background_session_test.dart.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  Future<ResponseBody> Function(RequestOptions options)? responder;

  Completer<void>? _dispatchSignal;

  /// Returns a Future that completes deterministically the next time
  /// [fetch] is invoked - i.e. the moment a request actually reaches this
  /// fake transport - distinct from the response being produced or
  /// consumed. Lets a test act (assert, mutate state, complete a
  /// manually-held response) exactly when a request is in flight, without
  /// guessing with a delay. Must be called before the operation that will
  /// trigger the dispatch, so the signal can never be missed.
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
