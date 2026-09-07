import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
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
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/models/shared_workout.dart';
import 'package:go_hard_app/data/models/workout_template.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';

import 'session_repository_session_ownership_test.mocks.dart';

/// CONVERGENCE PROOF (formerly a characterization test for a KNOWN,
/// unresolved orphan defect - see git history for the original
/// "REPRODUCER" version). Durable cancellation
/// (`DELETE /api/v1/sessions/by-operation/{clientOperationId}`) closes the
/// delete-during-CREATE race this file drives: `SessionRepository
/// ._markForDeletion` no longer hard-deletes a still-server-id-less row, and
/// a late CREATE acknowledgment never resurrects a `pending_delete` row (see
/// both classes' doc comments). This file now proves the SAFE converged
/// outcome instead of demonstrating the orphan.
///
/// A detached foreground `SessionRepository._syncCreateSessionToServer` POST
/// and an independent `SyncService.sync()` pass share only Isar,
/// `UserSessionEpoch`, and `SessionRequestCoordinator` - none of which
/// serialize them, so every interleaving below is driven deterministically:
/// a held `Completer` per response, the fake adapter's `nextDispatch()`
/// signal for "the request reached the transport", and
/// `scheduledBackgroundSyncs` for detached-op settlement. No wall-clock
/// waits, `Future.delayed`, `Timer`, `sleep`, `pumpEventQueue`, `_settle`, or
/// mock-call polling as a sync primitive.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _RaceHttpAdapter adapter;
  late SessionRepository repository;
  late SyncService syncService;
  late List<Future<void>> scheduledBackgroundSyncs;

  const userA = 1;
  const userB = 2;
  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_create_del_race_');
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
    adapter = _RaceHttpAdapter();
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

    SyncService.reset();
    syncService = SyncService(
      apiService: apiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: mockConnectivity,
      sessionEpoch: sessionEpoch,
      sessionCoordinator: sessionCoordinator,
    );
  });

  tearDown(() async {
    repository.onBackgroundSyncScheduledForTesting = null;
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

  Session sessionModel(String name) =>
      Session(id: 0, userId: userA, date: DateTime(2026, 1, 1), name: name);

  ResponseBody jsonResponse(Object? json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  Map<String, dynamic> serverSessionJson(int id, {String? clientOperationId}) =>
      {
        'id': id,
        'userId': userA,
        'date': '2026-01-01',
        'duration': null,
        'notes': null,
        'type': null,
        'name': 'Fresh',
        'status': 'draft',
        'startedAt': null,
        'completedAt': null,
        'pausedAt': null,
        'exercises': <dynamic>[],
        'programId': null,
        'programWorkoutId': null,
        'version': 1,
        // GET /sessions (and GET /sessions/{id}) serialize the raw server
        // entity, which - unlike the POST/PUT SessionResponseDto - DOES carry
        // this back (see Session.clientOperationId's doc comment).
        'clientOperationId': clientOperationId,
      };

  String cancelPathFor(String? opId) =>
      ApiConfig.sessionCancelByOperation(opId!);

  test('A. cancellation resolves BEFORE the delayed CREATE POST responds - a '
      'late CREATE acknowledgment cannot resurrect the row, and no '
      'compensating DELETE-by-id is ever needed', () async {
    loginAs(userA);

    final heldPost = Completer<ResponseBody>();
    adapter.responder = (opts) {
      if (opts.method == 'POST' && opts.path == ApiConfig.sessions) {
        return heldPost.future;
      }
      // Any other call (the cancel-by-operation DELETE) succeeds fast.
      return Future.value(jsonResponse(null, statusCode: 204));
    };

    final dispatched = adapter.nextDispatch();
    final created = await repository.createSession(sessionModel('Fresh'));
    await dispatched;

    final opId = (await isar.localSessions.get(created.id))!.clientOperationId;
    expect(opId, isNotNull);

    // t2: delete the still-server-id-less local row. It is now dispatched
    // to cancel-by-operation (not hard-deleted), and resolves immediately
    // since the fake adapter answers non-POST calls right away.
    final deleteOk = await repository.deleteSession(created.id);
    expect(deleteOk, isTrue);
    expect(
      adapter.captured.any(
        (r) => r.method == 'DELETE' && r.path == cancelPathFor(opId),
      ),
      isTrue,
      reason:
          'deletion dispatched cancel-by-operation-key, not a hard '
          'local delete',
    );
    expect(
      await isar.localSessions.get(created.id),
      isNull,
      reason: 'cancellation already succeeded - the row is fully gone',
    );

    // t3/t4: an independent SyncService pass runs while the foreground
    // CREATE POST is still held. There is no row for it to find.
    await syncService.sync();
    expect(heldPost.isCompleted, isFalse);

    // t5: the foreground CREATE now "succeeds" - the server claims it
    // committed a row (defense-in-depth: the real API's tombstone would
    // make this response 409 operation_canceled instead, but the client
    // must independently refuse to resurrect even if a stale success
    // slips through).
    heldPost.complete(jsonResponse(serverSessionJson(777)));
    await scheduledBackgroundSyncs.single;

    // t6: the acknowledgment re-resolved by localId, found nothing, and
    // returned - no resurrection, no duplicate/compensating call.
    expect(await isar.localSessions.get(created.id), isNull);
    expect(
      adapter.captured.where((r) => r.method == 'DELETE'),
      hasLength(1),
      reason:
          'exactly the one cancel-by-operation call - never a second '
          'DELETE for the same logical operation',
    );
  });

  test('B. the CREATE acknowledgment arrives WHILE cancellation is still '
      'pending - the row stays hidden pending_delete (never resurrected) and '
      'gains the confirmed serverId; releasing the cancel afterward still '
      'converges to full local removal', () async {
    loginAs(userA);

    final heldPost = Completer<ResponseBody>();
    final heldCancel = Completer<ResponseBody>();
    adapter.responder = (opts) {
      if (opts.method == 'POST' && opts.path == ApiConfig.sessions) {
        return heldPost.future;
      }
      if (opts.method == 'DELETE' &&
          opts.path.startsWith('${ApiConfig.sessions}/by-operation/')) {
        return heldCancel.future;
      }
      return Future.value(jsonResponse(const <dynamic>[]));
    };

    final dispatched = adapter.nextDispatch();
    final created = await repository.createSession(sessionModel('Fresh'));
    await dispatched;
    final opId = (await isar.localSessions.get(created.id))!.clientOperationId;

    // Delete: dispatches cancel-by-operation, held.
    final cancelDispatched = adapter.nextDispatch();
    final deleteFuture = repository.deleteSession(created.id);
    await cancelDispatched;
    expect(
      (await isar.localSessions.get(created.id))!.syncStatus,
      'pending_delete',
      reason: 'marked durably pending_delete before any HTTP result',
    );

    // The CREATE POST now resolves, WHILE cancellation is still pending.
    heldPost.complete(jsonResponse(serverSessionJson(777)));
    await scheduledBackgroundSyncs.single;

    final afterCreateAck = await isar.localSessions.get(created.id);
    expect(
      afterCreateAck,
      isNotNull,
      reason: 'deletion intent must win - the row is not resurrected away',
    );
    expect(afterCreateAck!.syncStatus, 'pending_delete');
    expect(
      afterCreateAck.serverId,
      777,
      reason: 'the confirmed identity is attached even while hidden',
    );

    // Now release the cancellation.
    heldCancel.complete(jsonResponse(null, statusCode: 204));
    final deleteOk = await deleteFuture;

    expect(deleteOk, isTrue);
    expect(await isar.localSessions.get(created.id), isNull);
    expect(
      adapter.captured
          .where((r) => r.method == 'DELETE' && r.path == cancelPathFor(opId))
          .length,
      1,
      reason:
          'exactly one cancel-by-operation call, regardless of the '
          'CREATE ack racing in ahead of its response',
    );
  });

  test(
    'B2. server reconciliation cannot republish a pending deletion: once the '
    'CREATE ack has attached the confirmed serverId to a still-pending_delete '
    'row, a full server-list refresh that still lists that Session matches it '
    'by serverId and skips it - never inserting a second, visible, resurrected '
    'row',
    () async {
      loginAs(userA);

      final heldPost = Completer<ResponseBody>();
      final heldCancel = Completer<ResponseBody>();
      adapter.responder = (opts) {
        if (opts.method == 'POST' && opts.path == ApiConfig.sessions) {
          return heldPost.future;
        }
        if (opts.method == 'DELETE' &&
            opts.path.startsWith('${ApiConfig.sessions}/by-operation/')) {
          return heldCancel.future;
        }
        if (opts.method == 'GET' && opts.path == ApiConfig.sessions) {
          // The server still lists the Session - cancellation has not yet
          // been dispatched/accepted.
          return Future.value(jsonResponse([serverSessionJson(777)]));
        }
        return Future.value(jsonResponse(const <dynamic>[]));
      };

      final dispatched = adapter.nextDispatch();
      final created = await repository.createSession(sessionModel('Fresh'));
      await dispatched;

      final cancelDispatched = adapter.nextDispatch();
      final deleteFuture = repository.deleteSession(created.id);
      await cancelDispatched;

      // The CREATE ack lands while cancellation is still held pending -
      // attaches serverId 777, stays hidden pending_delete (see test B).
      heldPost.complete(jsonResponse(serverSessionJson(777)));
      await scheduledBackgroundSyncs.single;
      expect((await isar.localSessions.get(created.id))!.serverId, 777);

      // A full server-list refresh now runs (e.g. the user opens the
      // Sessions screen) WHILE cancellation is still pending. The server's
      // response still includes Session 777.
      final visible = await repository.getSessions(waitForSync: true);

      expect(
        visible,
        isEmpty,
        reason:
            'the pending_delete row must stay hidden - never republished '
            'as a visible session',
      );
      final allRowsForServerId =
          await isar.localSessions
              .filter()
              .serverIdEqualTo(777)
              .userIdEqualTo(userA)
              .findAll();
      expect(
        allRowsForServerId,
        hasLength(1),
        reason:
            'exactly the ORIGINAL row - no second, resurrected row was '
            'inserted for the same server Session',
      );
      expect(allRowsForServerId.single.localId, created.id);
      expect(allRowsForServerId.single.syncStatus, 'pending_delete');

      // Cleanup: release the cancellation so the row finally converges.
      heldCancel.complete(jsonResponse(null, statusCode: 204));
      expect(await deleteFuture, isTrue);
      expect(await isar.localSessions.get(created.id), isNull);
    },
  );

  test(
    'B3. server reconciliation cannot resurrect a pending deletion when the '
    "CREATE's own response was PERMANENTLY lost (never an ack this client "
    'ever received, not merely delayed): the server committed the Session, '
    'this client only ever learns of it through a GET/list refresh, and it '
    'is matched and skipped by the retained operation key alone - never by '
    'a serverId this client never had. After the pending cancellation '
    'converges, exactly one local row (and no orphan children) remain.',
    () async {
      loginAs(userA);

      // t0/t1: the foreground CREATE POST is dispatched and then fails
      // outright (simulating "response permanently lost" - e.g. the
      // connection dropped after the server committed but before any bytes
      // came back) - NOT held/delayed. The local row never learns a
      // serverId from this call at all.
      adapter.responder = (opts) {
        if (opts.method == 'POST' && opts.path == ApiConfig.sessions) {
          return Future.error(
            DioException(
              requestOptions: opts,
              type: DioExceptionType.connectionError,
            ),
          );
        }
        return Future.value(jsonResponse(const <dynamic>[]));
      };
      final created = await repository.createSession(sessionModel('Fresh'));
      await scheduledBackgroundSyncs.single;
      final opId =
          (await isar.localSessions.get(created.id))!.clientOperationId;
      expect(opId, isNotNull);
      expect(
        (await isar.localSessions.get(created.id))!.serverId,
        isNull,
        reason: 'the lost response never attached any identity',
      );

      // t2: delete OFFLINE - persists pending_delete with the retained key,
      // no cancellation dispatched yet.
      when(mockConnectivity.isOnline).thenReturn(false);
      expect(await repository.deleteSession(created.id), isTrue);
      expect(
        (await isar.localSessions.get(created.id))!.syncStatus,
        'pending_delete',
      );
      when(mockConnectivity.isOnline).thenReturn(true);

      // t3: a full server-list refresh now runs. The server DID commit the
      // CREATE (this client just never learned its id) - the response
      // includes the committed Session, with its serverId (777, unknown to
      // this client) AND the SAME clientOperationId this client retained.
      adapter.responder = (opts) {
        if (opts.method == 'GET' && opts.path == ApiConfig.sessions) {
          return Future.value(
            jsonResponse([serverSessionJson(777, clientOperationId: opId)]),
          );
        }
        if (opts.method == 'DELETE' &&
            opts.path == ApiConfig.sessionById(777)) {
          return Future.value(jsonResponse(null, statusCode: 204));
        }
        return Future.value(jsonResponse(const <dynamic>[]));
      };

      final visible = await repository.getSessions(waitForSync: true);

      expect(
        visible,
        isEmpty,
        reason: 'matched by operation key - never resurrected as visible',
      );
      final allLocalForUser =
          await isar.localSessions.filter().userIdEqualTo(userA).findAll();
      expect(
        allLocalForUser,
        hasLength(1),
        reason:
            'no duplicate/second local Session was inserted for the '
            'server-committed row',
      );
      expect(allLocalForUser.single.localId, created.id);
      expect(allLocalForUser.single.syncStatus, 'pending_delete');
      expect(
        allLocalForUser.single.serverId,
        777,
        reason:
            'the identity learned ONLY via the operation-key match is '
            'attached to the existing hidden row',
      );

      // t4: the pending cancellation now converges - identity is known, so
      // the next sync pass uses ordinary DELETE-by-id (see this suite's
      // Point-2 finding: an ordinary DELETE can never let a same-key CREATE
      // retry recreate the Session either).
      await syncService.sync();

      expect(
        await isar.localSessions.filter().userIdEqualTo(userA).findAll(),
        isEmpty,
        reason: 'fully converged - no local row, no duplicate, no orphan',
      );
      expect(await isar.localExercises.where().findAll(), isEmpty);
      expect(await isar.localExerciseSets.where().findAll(), isEmpty);
    },
  );

  test('B4. the operation-key correlation is scoped to the CURRENT user: a '
      "different user's own committed Session sharing (implausibly) the same "
      "clientOperationId as user A's pending cancellation is never matched "
      "against A's row, never touches it, and is cached normally as B's own "
      'session', () async {
    // A has a pending cancellation, keyed by opId, with no serverId.
    loginAs(userA);
    final aRow = LocalSession(
      userId: userA,
      date: DateTime(2026, 1, 1),
      name: 'A-fresh',
      status: 'draft',
      isSynced: false,
      syncStatus: 'pending_delete',
      lastModifiedLocal: DateTime.now().toUtc(),
      clientOperationId: 'shared-op-key',
    );
    await isar.writeTxn(() => isar.localSessions.put(aRow));

    // B logs in and refreshes; B's OWN committed Session happens to carry
    // the SAME clientOperationId value (a real UUID collision is
    // practically impossible - this isolates the userId scope itself).
    loginAs(userB);
    adapter.responder = (opts) {
      if (opts.method == 'GET' && opts.path == ApiConfig.sessions) {
        return Future.value(
          jsonResponse([
            {
              'id': 900,
              'userId': userB,
              'date': '2026-01-01',
              'duration': null,
              'notes': null,
              'type': null,
              'name': 'B-own',
              'status': 'draft',
              'startedAt': null,
              'completedAt': null,
              'pausedAt': null,
              'exercises': <dynamic>[],
              'programId': null,
              'programWorkoutId': null,
              'version': 1,
              'clientOperationId': 'shared-op-key',
            },
          ]),
        );
      }
      return Future.value(jsonResponse(const <dynamic>[]));
    };

    final visibleForB = await repository.getSessions(waitForSync: true);

    expect(
      visibleForB.map((s) => s.name),
      ['B-own'],
      reason:
          "B's own session is cached and visible normally - the "
          "shared key never suppressed it",
    );
    final untouchedA = await isar.localSessions.get(aRow.localId);
    expect(untouchedA!.userId, userA);
    expect(untouchedA.syncStatus, 'pending_delete');
    expect(
      untouchedA.serverId,
      isNull,
      reason: "B's refresh must never attach an identity to A's row",
    );
  });

  test(
    'B5. a GET snapshot captured BEFORE cancellation commits, reconciled '
    "AFTER the cancellation's own acknowledgment already removed the local "
    'tombstone, must not resurrect the Session - the pre-dispatch operation-'
    'key snapshot protects this even with no live row left to match',
    () async {
      loginAs(userA);
      const opId = 'pre-dispatch-op-id';
      final row = LocalSession(
        userId: userA,
        date: DateTime(2026, 1, 1),
        name: 'Fresh',
        status: 'draft',
        isSynced: false,
        syncStatus: 'pending_delete',
        lastModifiedLocal: DateTime.now().toUtc(),
        clientOperationId: opId,
      );
      await isar.writeTxn(() => isar.localSessions.put(row));

      final heldGet = Completer<ResponseBody>();
      adapter.responder = (opts) {
        if (opts.method == 'GET' && opts.path == ApiConfig.sessions) {
          return heldGet.future;
        }
        if (opts.method == 'DELETE' && opts.path == cancelPathFor(opId)) {
          return Future.value(jsonResponse(null, statusCode: 204));
        }
        return Future.value(jsonResponse(const <dynamic>[]));
      };

      // t0: dispatch the GET-all refresh and hold its response - the
      // pre-dispatch operation-key snapshot is captured before this point.
      final getDispatched = adapter.nextDispatch();
      final getFuture = repository.getSessions(waitForSync: true);
      await getDispatched;

      // t1: WHILE the GET is still held, the cancellation completes fully -
      // dispatch, 204, and local acknowledgment all finish, removing the
      // tombstone entirely.
      final cancelOk = await repository.deleteSession(row.localId);
      expect(cancelOk, isTrue);
      expect(
        await isar.localSessions.get(row.localId),
        isNull,
        reason: 'the tombstone is fully gone before the GET response lands',
      );

      // t2: release the held GET response - a stale snapshot taken BEFORE
      // the cancellation committed, still listing the Session.
      heldGet.complete(
        jsonResponse([serverSessionJson(777, clientOperationId: opId)]),
      );
      final visible = await getFuture;

      expect(
        visible,
        isEmpty,
        reason:
            'must not resurrect - the key was pending cancellation as '
            'of dispatch time, live tombstone or not',
      );
      expect(
        await isar.localSessions.filter().userIdEqualTo(userA).findAll(),
        isEmpty,
        reason: 'no phantom row was inserted for the stale snapshot',
      );
    },
  );

  test(
    'C. background/background: an independent SyncService pass converges a '
    'row left pending_delete-with-confirmed-serverId (from a CREATE ack that '
    'raced a prior OFFLINE delete) via ordinary ordinary DELETE-by-serverId',
    () async {
      loginAs(userA);

      final heldPost = Completer<ResponseBody>();
      adapter.responder = (opts) {
        if (opts.method == 'POST' && opts.path == ApiConfig.sessions) {
          return heldPost.future;
        }
        return Future.value(jsonResponse(null, statusCode: 204));
      };

      final dispatched = adapter.nextDispatch();
      final created = await repository.createSession(sessionModel('Fresh'));
      await dispatched;

      // Delete OFFLINE: marks pending_delete with no HTTP call at all.
      when(mockConnectivity.isOnline).thenReturn(false);
      final deleteOk = await repository.deleteSession(created.id);
      expect(deleteOk, isTrue);
      expect(
        (await isar.localSessions.get(created.id))!.syncStatus,
        'pending_delete',
      );
      when(mockConnectivity.isOnline).thenReturn(true);

      // The original CREATE POST resolves with a committed server row.
      heldPost.complete(jsonResponse(serverSessionJson(777)));
      await scheduledBackgroundSyncs.single;

      final afterAck = await isar.localSessions.get(created.id);
      expect(afterAck!.syncStatus, 'pending_delete');
      expect(afterAck.serverId, 777);

      // A later, fully independent SyncService pass now finds a row with a
      // known serverId and finishes it through the ordinary DELETE-by-id
      // path - never the cancel-by-operation endpoint.
      await syncService.sync();

      expect(await isar.localSessions.get(created.id), isNull);
      expect(
        adapter.captured.where(
          (r) => r.method == 'DELETE' && r.path == ApiConfig.sessionById(777),
        ),
        hasLength(1),
      );
      expect(
        adapter.captured.any(
          (r) => r.method == 'DELETE' && r.path.contains('by-operation'),
        ),
        isFalse,
        reason:
            'identity was already known - no cancel-by-operation call '
            'was ever needed',
      );
    },
  );

  test('D. a 409 operation_canceled CREATE response converts a still-'
      'pending_create row to pending_delete with the SAME key, which then '
      'converges through the ordinary cancel-by-operation path', () async {
    loginAs(userA);

    final heldPost = Completer<ResponseBody>();
    adapter.responder = (opts) {
      if (opts.method == 'POST' && opts.path == ApiConfig.sessions) {
        return heldPost.future;
      }
      return Future.value(jsonResponse(null, statusCode: 204));
    };

    final dispatched = adapter.nextDispatch();
    final created = await repository.createSession(sessionModel('Fresh'));
    await dispatched;
    final opId = (await isar.localSessions.get(created.id))!.clientOperationId;
    expect(opId, isNotNull);

    // The server reports this exact operation was already canceled
    // out-of-band (e.g. by another device, or a prior attempt this client
    // never learned the outcome of).
    heldPost.complete(
      jsonResponse({'code': 'operation_canceled'}, statusCode: 409),
    );
    await scheduledBackgroundSyncs.single;

    final afterCanceled = await isar.localSessions.get(created.id);
    expect(afterCanceled, isNotNull);
    expect(afterCanceled!.syncStatus, 'pending_delete');
    expect(
      afterCanceled.clientOperationId,
      opId,
      reason: 'never rotates to a new key',
    );
    expect(afterCanceled.serverId, isNull);

    // A later sync pass dispatches cancel-by-operation for the SAME key -
    // idempotent on the server, and finishes local removal here.
    await syncService.sync();

    expect(await isar.localSessions.get(created.id), isNull);
    expect(
      adapter.captured.where(
        (r) => r.method == 'DELETE' && r.path == cancelPathFor(opId),
      ),
      hasLength(1),
    );
  });
}

/// Fake Dio transport: records every request and lets a test hold a
/// specific response via a `responder` returning a pending `Future`.
class _RaceHttpAdapter implements HttpClientAdapter {
  final List<RequestOptions> captured = [];
  Future<ResponseBody> Function(RequestOptions options)? responder;
  Completer<void>? _dispatchSignal;

  Future<void> nextDispatch() {
    final c = Completer<void>();
    _dispatchSignal = c;
    return c.future;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    captured.add(options);
    _dispatchSignal?.complete();
    _dispatchSignal = null;
    final r = responder;
    if (r != null) return r(options);
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
