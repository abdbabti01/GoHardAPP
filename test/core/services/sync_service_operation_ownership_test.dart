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
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_chat_conversation.dart';
import 'package:go_hard_app/data/local/models/local_chat_message.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_food_item.dart';
import 'package:go_hard_app/data/local/models/local_food_template.dart';
import 'package:go_hard_app/data/local/models/local_goal.dart';
import 'package:go_hard_app/data/local/models/local_meal_entry.dart';
import 'package:go_hard_app/data/local/models/local_meal_log.dart';
import 'package:go_hard_app/data/local/models/local_nutrition_goal.dart';
import 'package:go_hard_app/data/local/models/local_program.dart';
import 'package:go_hard_app/data/local/models/local_program_workout.dart';
import 'package:go_hard_app/data/local/models/local_run_session.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/achievement.dart';
import 'package:go_hard_app/data/models/shared_workout.dart';
import 'package:go_hard_app/data/models/workout_template.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'sync_service_operation_ownership_test.mocks.dart';

/// A [UserSessionEpoch] that counts every [isCurrent] call. Used to prove
/// that a full, successful session-create pass performs a specific,
/// known number of epoch-currency checks - a redundant, defense-in-depth
/// design (the class doc comment on `SyncService` lists checkpoints
/// "before every row", "after every awaited HTTP call", "before every
/// local acknowledgment transaction", and "as the first statement inside
/// every acknowledgment transaction" for a SINGLE row). Because later
/// checkpoints already re-validate whatever an earlier one would have
/// caught, removing any ONE of them is invisible to "was the row
/// acknowledged" assertions alone - but it always removes exactly one
/// [isCurrent] call from this count, which is what
/// `sync_service_operation_ownership_test.dart`'s post-HTTP/in-writeTxn
/// checkpoint-removal mutation tests rely on.
class _CountingSessionEpoch extends UserSessionEpoch {
  int isCurrentCallCount = 0;

  @override
  bool isCurrent(UserSessionToken token) {
    isCurrentCallCount++;
    return super.isCurrent(token);
  }
}

/// A deterministic fake Dio transport. Records every [RequestOptions] Dio
/// actually attempts to send, so tests can assert on the real headers/extra
/// the real interceptor pipeline produced - never a stub of it. Mirrors the
/// fake adapter used in api_service_session_context_test.dart and
/// nutrition_repository_background_session_test.dart.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  /// Called for every request; return a Future that resolves (or never
  /// resolves, for pending/cancellation scenarios) with the response to
  /// hand back. Defaults to an immediate empty 200 JSON body.
  Future<ResponseBody> Function(RequestOptions options)? responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
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

@GenerateMocks([AuthService])
/// Proves SyncService's token-owned active-operation design, session-bound
/// HTTP dispatch, and acknowledgment-race safety - see the class doc
/// comment on `SyncService` itself for the full design this exercises.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late SyncService syncService;

  const userA = 1;
  const userB = 2;

  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sync_service_operation_ownership_',
    );
    isar = await Isar.open(
      [
        LocalSessionSchema,
        LocalExerciseSchema,
        LocalExerciseSetSchema,
        LocalExerciseTemplateSchema,
        LocalChatConversationSchema,
        LocalChatMessageSchema,
        LocalRunSessionSchema,
        LocalProgramSchema,
        LocalGoalSchema,
        LocalProgramWorkoutSchema,
        SharedWorkoutSchema,
        WorkoutTemplateSchema,
        AchievementSchema,
        LocalMealLogSchema,
        LocalMealEntrySchema,
        LocalFoodItemSchema,
        LocalNutritionGoalSchema,
        LocalFoodTemplateSchema,
      ],
      directory: tempDir.path,
      inspector: false,
    );

    currentAuthUserId = null;
    mockAuthService = MockAuthService();
    when(
      mockAuthService.getUserId(),
    ).thenAnswer((_) async => currentAuthUserId);
    when(mockAuthService.getToken()).thenAnswer(
      (_) async =>
          currentAuthUserId == null ? null : 'jwt-user-$currentAuthUserId',
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

    SyncService.reset();
    syncService = SyncService(
      apiService: apiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: ConnectivityService.instance,
      sessionEpoch: sessionEpoch,
      sessionCoordinator: sessionCoordinator,
    );
  });

  tearDown(() async {
    syncService.beforeAckWriteTxnForTesting = null;
    syncService.insideAckWriteTxnForTesting = null;
    syncService.beforePhaseCheckForTesting = null;
    SyncService.reset();
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

  Future<LocalSession> insertSession({
    required int uid,
    int? serverId,
    String syncStatus = 'pending_create',
    bool isSynced = false,
    String name = 'Session',
  }) async {
    final session = LocalSession(
      serverId: serverId,
      userId: uid,
      date: DateTime(2026, 1, 1),
      name: name,
      status: 'in_progress',
      isSynced: isSynced,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now().toUtc(),
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  ResponseBody jsonResponse(Object json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  Map<String, dynamic> sessionJson({
    required int id,
    required int userId,
    String name = 'Server session',
  }) => {
    'id': id,
    'userId': userId,
    'date': '2026-01-01',
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
    'version': 1,
  };

  // ============ Operation ownership (tests 1-6) ============

  group('operation ownership', () {
    test('logged-out sync performs no query or HTTP (test 1)', () async {
      final captured = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };

      try {
        await syncService.sync();
      } finally {
        debugPrint = originalDebugPrint;
      }

      expect(adapter.capturedRequests, isEmpty);
      expect(syncService.isSyncing, isFalse);
      // "Starting sync..." is only ever printed once a session has been
      // captured and the pass is about to begin - its absence proves the
      // logged-out short-circuit happened before any Isar/HTTP work.
      expect(captured.any((l) => l.contains('Starting sync')), isFalse);
    });

    test('a same-session concurrent call awaits the same physical pass, not a '
        'second one (test 2)', () async {
      loginAs(userA);
      await insertSession(uid: userA, name: 'Only');

      final completer = Completer<ResponseBody>();
      adapter.responder = (_) => completer.future;

      final first = syncService.sync();
      await pumpEventQueue();
      expect(adapter.capturedRequests, hasLength(1));

      final second = syncService.sync();
      await pumpEventQueue();
      // No second dispatch was made for the concurrent call.
      expect(adapter.capturedRequests, hasLength(1));

      completer.complete(jsonResponse(sessionJson(id: 500, userId: userA)));
      await first;
      await second;

      final stored = await isar.localSessions.get(
        (await isar.localSessions.where().findFirst())!.localId,
      );
      expect(stored!.isSynced, isTrue);
      expect(stored.serverId, 500);
    });

    test('B starts while A\'s HTTP future is still pending, and A\'s finally '
        'cannot clear B\'s active-operation record (tests 3, 4)', () async {
      loginAs(userA);
      await insertSession(uid: userA, name: 'A session');

      final aCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => aCompleter.future;

      final aFuture = syncService.sync();
      await pumpEventQueue();
      expect(adapter.capturedRequests, hasLength(1));
      expect(syncService.isSyncing, isTrue);

      // Logout invalidates A's epoch; B logs in and starts a NEW pass
      // without waiting for A's still-pending transport.
      logout();
      loginAs(userB);
      await insertSession(uid: userB, name: 'B session');

      final bCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => bCompleter.future;

      final bFuture = syncService.sync();
      await pumpEventQueue();
      expect(
        adapter.capturedRequests,
        hasLength(2),
        reason: 'B\'s dispatch does not wait for A\'s pending transport',
      );
      expect(syncService.isSyncing, isTrue);

      // A's transport finally completes - but A is stale now, so it must
      // not acknowledge anything, and its finally must not clear B's
      // still-active operation record.
      aCompleter.complete(jsonResponse(sessionJson(id: 900, userId: userA)));
      await aFuture;

      expect(
        syncService.isSyncing,
        isTrue,
        reason: 'A\'s finally must not have cleared B\'s active record',
      );

      bCompleter.complete(jsonResponse(sessionJson(id: 901, userId: userB)));
      await bFuture;
      expect(syncService.isSyncing, isFalse);

      final aRow =
          await isar.localSessions.filter().userIdEqualTo(userA).findFirst();
      expect(
        aRow!.syncStatus,
        'pending_create',
        reason: 'A\'s stale response must never acknowledge its row',
      );
      expect(aRow.serverId, isNull);

      final bRow =
          await isar.localSessions.filter().userIdEqualTo(userB).findFirst();
      expect(bRow!.syncStatus, 'synced');
      expect(bRow.serverId, 901);
    });

    test(
      'A cannot continue to a later phase after invalidation (test 5)',
      () async {
        loginAs(userA);
        await insertSession(uid: userA, name: 'A session');
        // A pending program - phase 4, well after the session phase (1).
        final program = LocalProgram(
          userId: userA,
          title: 'A program',
          totalWeeks: 4,
          currentWeek: 1,
          currentDay: 1,
          startDate: DateTime(2026, 1, 1),
          createdAt: DateTime.now(),
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime.now(),
        );
        await isar.writeTxn(() => isar.localPrograms.put(program));

        final completer = Completer<ResponseBody>();
        adapter.responder = (_) => completer.future;

        final future = syncService.sync();
        await pumpEventQueue();
        expect(adapter.capturedRequests, hasLength(1));

        // Invalidate while the session-create HTTP call is still pending -
        // the post-HTTP checkpoint must abort the whole pass before phase 4
        // (programs) is ever reached.
        logout();
        completer.complete(jsonResponse(sessionJson(id: 950, userId: userA)));
        await future;

        expect(
          adapter.capturedRequests,
          hasLength(1),
          reason: 'the program phase must never have been reached',
        );
        final storedProgram = await isar.localPrograms.get(program.localId);
        expect(storedProgram!.syncStatus, 'pending_create');
        expect(storedProgram.serverId, isNull);
      },
    );

    test('the between-phase epoch check itself aborts the pass, independent '
        'of any per-row/per-HTTP checkpoint (test 5, isolated)', () async {
      loginAs(userA);
      // A pending program - phase 4 - with nothing pending in any
      // earlier phase, so no per-row/post-HTTP/writeTxn checkpoint ever
      // runs before phase 4 would be reached; only the between-phase
      // gate itself can catch the invalidation below.
      final program = LocalProgram(
        userId: userA,
        title: 'A program',
        totalWeeks: 4,
        currentWeek: 1,
        currentDay: 1,
        startDate: DateTime(2026, 1, 1),
        createdAt: DateTime.now(),
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now(),
      );
      await isar.writeTxn(() => isar.localPrograms.put(program));

      var hookRuns = 0;
      syncService.beforePhaseCheckForTesting = () async {
        hookRuns++;
        // Fire once, right before the programs phase's own gate check -
        // by then sessions/exercises/exerciseSets have already run (and
        // found nothing pending) with no HTTP/writeTxn ever touched.
        if (hookRuns == 4) {
          logout();
        }
      };

      final captured = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };
      try {
        await syncService.sync();
      } finally {
        debugPrint = originalDebugPrint;
      }

      // The programs phase's OWN per-row checkpoint would also catch a
      // stale context - but only after entering the phase function and
      // printing this line. Its absence proves the BETWEEN-PHASE gate
      // itself stopped the pass before _syncPrograms was ever called,
      // independent of that later, redundant per-row checkpoint.
      expect(
        captured.any((l) => l.contains('Syncing 1 programs')),
        isFalse,
        reason:
            'the between-phase check must abort before the programs '
            'phase function is even entered',
      );

      final storedProgram = await isar.localPrograms.get(program.localId);
      expect(storedProgram!.syncStatus, 'pending_create');
      expect(storedProgram.serverId, isNull);
      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'isSyncing reflects only the current session\'s operation (test 6)',
      () async {
        expect(syncService.isSyncing, isFalse);

        loginAs(userA);
        await insertSession(uid: userA);
        final completer = Completer<ResponseBody>();
        adapter.responder = (_) => completer.future;

        final future = syncService.sync();
        await pumpEventQueue();
        expect(syncService.isSyncing, isTrue);

        // A superseded session must never see isSyncing as true for its own
        // stale operation once a new session is active.
        logout();
        expect(
          syncService.isSyncing,
          isFalse,
          reason: 'logged out - no session owns the (still-pending) op',
        );

        loginAs(userB);
        expect(
          syncService.isSyncing,
          isFalse,
          reason: 'B has not started anything yet',
        );

        completer.complete(jsonResponse(sessionJson(id: 1, userId: userA)));
        await future;
        expect(syncService.isSyncing, isFalse);
      },
    );
  });

  // ============ Credential/session binding (tests 12-15) ============

  group('credential and session binding', () {
    test(
      'every SyncService HTTP request is session-bound and carries its own '
      'captured JWT - A\'s payload never uses B\'s JWT (tests 12, 13)',
      () async {
        loginAs(userA);
        await insertSession(uid: userA, name: 'A session');
        adapter.responder =
            (_) async => jsonResponse(sessionJson(id: 1, userId: userA));

        await syncService.sync();

        expect(adapter.capturedRequests, hasLength(1));
        final sent = adapter.capturedRequests.single;
        expect(sent.headers['Authorization'], 'Bearer jwt-user-$userA');
        expect(
          sent.extra.containsKey(ApiService.sessionEpochExtraKey),
          isTrue,
          reason: 'every SyncService HTTP call must be session-bound',
        );
        final epochToken =
            sent.extra[ApiService.sessionEpochExtraKey] as UserSessionToken;
        expect(epochToken.userId, userA);
      },
    );

    test('cancellation/staleness at dispatch does not create a retry failure '
        '(test 14)', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, name: 'A session');

      apiService.beforeDispatchEpochCheckForTesting = () async {
        logout();
      };

      await syncService.sync();
      apiService.beforeDispatchEpochCheckForTesting = null;

      final stored = await isar.localSessions.get(session.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.syncRetryCount, 0);
      expect(stored.syncError, isNull);
    });

    test('a real 401 during a current, bound sync pass still triggers the '
        'existing onUnauthorized flow (test 15)', () async {
      loginAs(userA);
      await insertSession(uid: userA, name: 'A session');

      var unauthorizedCalls = 0;
      apiService.onUnauthorized = () => unauthorizedCalls++;
      adapter.responder =
          (_) async => jsonResponse({'message': 'nope'}, statusCode: 401);

      await syncService.sync();

      expect(unauthorizedCalls, 1);
    });
  });

  // ============ Acknowledgment races (tests 24-30) ============

  group('acknowledgment races', () {
    test(
      'server success then logout before acknowledgment: no write (test 24)',
      () async {
        loginAs(userA);
        final session = await insertSession(uid: userA, name: 'A session');

        syncService.beforeAckWriteTxnForTesting = () async {
          logout();
        };

        adapter.responder =
            (_) async => jsonResponse(sessionJson(id: 700, userId: userA));

        await syncService.sync();

        final stored = await isar.localSessions.get(session.localId);
        expect(stored!.syncStatus, 'pending_create');
        expect(stored.serverId, isNull);
      },
    );

    test('invalidation while the acknowledgment writeTxn is waiting: no write '
        '(test 25)', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, name: 'A session');

      syncService.insideAckWriteTxnForTesting = () async {
        logout();
      };

      adapter.responder =
          (_) async => jsonResponse(sessionJson(id: 701, userId: userA));

      await syncService.sync();

      final stored = await isar.localSessions.get(session.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.serverId, isNull);
    });

    test('a response arriving after B has logged in cannot mark B\'s '
        'pre-existing row synced (test 26)', () async {
      loginAs(userA);
      await insertSession(uid: userA, name: 'A session');

      final completer = Completer<ResponseBody>();
      adapter.responder = (_) => completer.future;

      final future = syncService.sync();
      await pumpEventQueue();

      logout();
      loginAs(userB);
      // A pre-existing row genuinely owned by B, to prove the stale
      // response cannot land on ANY row, not just the one it named.
      final bRow = await insertSession(
        uid: userB,
        serverId: 800,
        syncStatus: 'synced',
        isSynced: true,
        name: 'B\'s own row',
      );

      completer.complete(jsonResponse(sessionJson(id: 800, userId: userA)));
      await future;

      final bAfter = await isar.localSessions.get(bRow.localId);
      expect(bAfter!.name, 'B\'s own row');
      expect(bAfter.syncStatus, 'synced');
    });

    test('a replaced/deleted local row is not incorrectly acknowledged (test '
        '27)', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, name: 'A session');
      final staleLocalId = session.localId;

      final completer = Completer<ResponseBody>();
      adapter.responder = (_) => completer.future;

      final future = syncService.sync();
      await pumpEventQueue();

      // Replace the row at the exact same local ID before the response
      // arrives, simulating Isar reissuing an ID after a clearAll() wipe
      // reset its auto-increment counter for a new user.
      await isar.writeTxn(() async {
        await isar.localSessions.delete(staleLocalId);
      });
      final replacement = LocalSession(
        userId: userB,
        date: DateTime(2026, 2, 2),
        name: 'Replacement',
        status: 'in_progress',
        serverId: 950,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localSessions.put(replacement));

      completer.complete(jsonResponse(sessionJson(id: 950, userId: userA)));
      await future;

      final replacementAfter = await isar.localSessions.get(
        replacement.localId,
      );
      expect(
        replacementAfter!.name,
        'Replacement',
        reason: 'the replacement row must be completely untouched',
      );
      expect(replacementAfter.userId, userB);
    });

    test('cancellation leaves pending status and retry count unchanged (test '
        '28)', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, name: 'A session');

      adapter.responder = (_) => Completer<ResponseBody>().future;

      final future = syncService.sync();
      await pumpEventQueue();
      expect(adapter.capturedRequests, hasLength(1));

      sessionCoordinator.cancelCurrentGeneration();
      await future;

      final stored = await isar.localSessions.get(session.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.syncRetryCount, 0);
      expect(stored.serverId, isNull);
    });

    test('normal failure preserves existing retry behavior for a current '
        'owned row (test 29)', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, name: 'A session');
      adapter.responder =
          (_) async => jsonResponse({'message': 'boom'}, statusCode: 500);

      await syncService.sync();

      final stored = await isar.localSessions.get(session.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.syncRetryCount, 1);
      expect(stored.syncError, isNotNull);
    });

    test('delete acknowledgment cannot delete a foreign/replacement row (test '
        '30)', () async {
      loginAs(userA);
      final session = await insertSession(
        uid: userA,
        serverId: 600,
        syncStatus: 'pending_delete',
        isSynced: false,
        name: 'To delete',
      );
      final staleLocalId = session.localId;

      final completer = Completer<ResponseBody>();
      adapter.responder = (_) => completer.future;

      final future = syncService.sync();
      await pumpEventQueue();

      // Replace the row at the same local ID with one owned by B before
      // the DELETE response arrives.
      await isar.writeTxn(() async {
        await isar.localSessions.delete(staleLocalId);
      });
      final replacement = LocalSession(
        userId: userB,
        date: DateTime(2026, 3, 3),
        name: 'B\'s replacement',
        status: 'in_progress',
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await isar.writeTxn(() => isar.localSessions.put(replacement));

      completer.complete(jsonResponse({}));
      await future;

      final replacementAfter = await isar.localSessions.get(
        replacement.localId,
      );
      expect(
        replacementAfter,
        isNotNull,
        reason: 'the foreign replacement row must never be deleted',
      );
    });
  });

  // ============ A -> logout -> B execution guarantee ============

  group('A -> logout -> B execution guarantee', () {
    test(
      'A starts, logout invalidates and cancels A, B starts and completes '
      'independently, A later completes but performs no acknowledgment',
      () async {
        loginAs(userA);
        await insertSession(uid: userA, name: 'A session');

        final aCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => aCompleter.future;

        // 1 & 2. A starts sync and owns operation A, waiting on HTTP.
        final aFuture = syncService.sync();
        await pumpEventQueue();
        expect(adapter.capturedRequests, hasLength(1));
        expect(syncService.isSyncing, isTrue);

        // 3. Logout invalidates epoch and cancels A's request scope -
        // exactly what AuthProvider's logout pass does.
        logout();
        sessionCoordinator.cancelCurrentGeneration();

        // 4/5. B logs in and starts a fresh operation without waiting for A.
        loginAs(userB);
        await insertSession(uid: userB, name: 'B session');
        adapter.responder =
            (_) async => jsonResponse(sessionJson(id: 42, userId: userB));

        final bFuture = syncService.sync();
        await pumpEventQueue();

        // 6. B is active without waiting for A.
        expect(syncService.isSyncing, isTrue);

        // 7. A's transport still completes despite cancellation - resolve
        // it directly (its own CancelToken firing is exercised by
        // `SessionRequestCoordinator.cancelCurrentGeneration()` above; this
        // proves the case is ALSO safe if the fake transport still hands
        // back a body rather than throwing).
        if (!aCompleter.isCompleted) {
          aCompleter.complete(jsonResponse(sessionJson(id: 1, userId: userA)));
        }
        await aFuture;

        // 8/9. A performed no acknowledgment and did not clear B's record.
        final aRow =
            await isar.localSessions.filter().userIdEqualTo(userA).findFirst();
        expect(aRow!.syncStatus, 'pending_create');
        expect(aRow.serverId, isNull);
        expect(syncService.isSyncing, isTrue);

        // 10. B remains active and completes normally.
        await bFuture;
        expect(syncService.isSyncing, isFalse);
        final bRow =
            await isar.localSessions.filter().userIdEqualTo(userB).findFirst();
        expect(bRow!.syncStatus, 'synced');
        expect(bRow.serverId, 42);
      },
    );
  });

  // ============ Regression: no duplicate upload (test 34) ============

  test('no duplicate upload within one current session (test 34)', () async {
    loginAs(userA);
    await insertSession(uid: userA, name: 'Only');
    adapter.responder =
        (_) async => jsonResponse(sessionJson(id: 1, userId: userA));

    await syncService.sync();
    await syncService.sync();

    expect(
      adapter.capturedRequests,
      hasLength(1),
      reason: 'the second sync() finds nothing pending after the first',
    );
  });

  // ============ Checkpoint-count instrumentation ============
  //
  // Proves each individually-redundant epoch checkpoint (post-HTTP,
  // in-writeTxn first-statement) exists as its own `isCurrent` call, not by
  // observing an acknowledgment outcome (a later checkpoint already
  // protects that regardless of any ONE earlier checkpoint's presence) but
  // by counting `UserSessionEpoch.isCurrent` invocations during a single,
  // fully-successful, never-invalidated session-create pass with nothing
  // else pending anywhere. Removing any one `_assertCurrent`/`isCurrent`
  // call site in that path reduces this exact count by one.
  test('a single successful session-create pass performs exactly the '
      'expected number of epoch-currency checks', () async {
    SyncService.reset();
    currentAuthUserId = userA;
    final countingEpoch = _CountingSessionEpoch();
    countingEpoch.activate(userA);
    final countingCoordinator = SessionRequestCoordinator(
      countingEpoch,
      mockAuthService,
    );
    // A fresh ApiService bound to countingEpoch - reusing the outer
    // `apiService` (bound to the outer `sessionEpoch`) would make its own
    // dispatch-time epoch check reject every request as stale, since the
    // two epochs' generations are unrelated.
    final countingApiService = ApiService(mockAuthService, countingEpoch);
    final countingAdapter = _FakeHttpClientAdapter();
    countingApiService.testHttpClientAdapter = countingAdapter;
    final countingSyncService = SyncService(
      apiService: countingApiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: ConnectivityService.instance,
      sessionEpoch: countingEpoch,
      sessionCoordinator: countingCoordinator,
    );

    await insertSession(uid: userA, name: 'Only');
    countingAdapter.responder =
        (_) async => jsonResponse(sessionJson(id: 1, userId: userA));

    await countingSyncService.sync();

    // Empirically 19 for this exact scenario (SessionRequestCoordinator's
    // own post-JWT-read recheck; one gate per phase in _runSyncPhases;
    // ApiService's own wrapper + dispatch-time interceptor rechecks
    // around the single POST; the per-row, post-HTTP, before-writeTxn,
    // and first-statement-in-writeTxn checkpoints in _syncCreateSession).
    // The exact figure isn't the point - what matters is that removing
    // any ONE `isCurrent`/`_assertCurrent` call site in this pass's path
    // reduces it by exactly one, which the mutation tests below rely on.
    expect(countingEpoch.isCurrentCallCount, 19);
  });
}
