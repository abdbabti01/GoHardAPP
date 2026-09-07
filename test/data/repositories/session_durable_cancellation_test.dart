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
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';

import 'session_repository_session_ownership_test.mocks.dart';

/// Deterministic coverage for durable cancellation of a Session whose
/// generic keyed CREATE (`POST /api/v1/sessions`) may be pending or already
/// in flight on the server, at the [SessionRepository] (foreground) layer -
/// `DELETE /api/v1/sessions/by-operation/{clientOperationId}`.
///
/// See `session_create_delete_cross_operation_race_test.dart` for the
/// CREATE/delete ORDERING races (foreground and background), and
/// `sync_service_delete_cancellation_test.dart` for the background
/// `SyncService` delete-phase dispatch. This file covers: the dispatch rule
/// itself (serverId vs. operation key vs. neither), acknowledgment safety
/// (epoch / ownership / operation-key / intent rechecks), durability across
/// restart and logout, cross-user isolation, and error/retry convergence.
///
/// Real Isar, real [UserSessionEpoch], real [SessionRequestCoordinator], a
/// real [ApiService] wired to a fake [HttpClientAdapter] that records every
/// outgoing request - never a wall-clock wait, `Future.delayed`, or polling
/// loop.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _FakeAdapter adapter;
  late SessionRepository repository;

  const userA = 1;
  const userB = 2;
  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  Future<Isar> openIsar(String dir) => Isar.open(
    [
      LocalSessionSchema,
      LocalExerciseSchema,
      LocalExerciseSetSchema,
      LocalExerciseTemplateSchema,
    ],
    directory: dir,
    inspector: false,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_durable_cancel_');
    isar = await openIsar(tempDir.path);

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
    adapter = _FakeAdapter();
    apiService.testHttpClientAdapter = adapter;

    repository = SessionRepository(
      apiService,
      localDb,
      mockConnectivity,
      mockAuthService,
      sessionEpoch,
      sessionCoordinator,
    );
  });

  tearDown(() async {
    repository.beforeWriteTxnForTesting = null;
    repository.insideWriteTxnForTesting = null;
    repository.afterWriteTxnForTesting = null;
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

  Future<LocalSession> insertSession(
    Isar db, {
    int uid = userA,
    int? serverId,
    String? clientOperationId,
    String syncStatus = 'pending_create',
  }) async {
    final session = LocalSession(
      serverId: serverId,
      userId: uid,
      date: DateTime(2026, 1, 1),
      name: 'Fresh',
      status: 'draft',
      isSynced: false,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now().toUtc(),
      clientOperationId: clientOperationId,
    );
    await db.writeTxn(() => db.localSessions.put(session));
    return session;
  }

  const opId = 'op-aaaa-1111';
  String cancelPath = ApiConfig.sessionCancelByOperation(opId);

  test(
    '1. serverId known -> ordinary DELETE-by-id, cancellation endpoint never '
    'touched (legacy path unaffected)',
    () async {
      loginAs(userA);
      final row = await insertSession(
        isar,
        serverId: 42,
        clientOperationId: opId, // retained even after a successful sync
        syncStatus: 'synced',
      );
      adapter.responder = (o) => Future.value(_ok204());

      final result = await repository.deleteSession(row.localId);

      expect(result, isTrue);
      expect(adapter.captured, hasLength(1));
      expect(adapter.captured.single.method, 'DELETE');
      expect(adapter.captured.single.path, ApiConfig.sessionById(42));
      expect(await isar.localSessions.get(row.localId), isNull);
    },
  );

  test('2. serverId null + retained operation key + online -> dispatches '
      'cancel-by-operation, NOT DELETE-by-id; 204 removes the row', () async {
    loginAs(userA);
    final row = await insertSession(isar, clientOperationId: opId);
    adapter.responder = (o) => Future.value(_ok204());

    final result = await repository.deleteSession(row.localId);

    expect(result, isTrue);
    expect(adapter.captured, hasLength(1));
    expect(adapter.captured.single.method, 'DELETE');
    expect(adapter.captured.single.path, cancelPath);
    expect(await isar.localSessions.get(row.localId), isNull);
  });

  test('3. serverId null + NO operation key -> nothing was ever dispatched, '
      'removed immediately with zero HTTP calls', () async {
    loginAs(userA);
    final row = await insertSession(isar, clientOperationId: null);

    final result = await repository.deleteSession(row.localId);

    expect(result, isTrue);
    expect(adapter.captured, isEmpty);
    expect(await isar.localSessions.get(row.localId), isNull);
  });

  test(
    '4. offline with a retained operation key -> no HTTP call, row persists '
    'as pending_delete with the SAME key (durable intent, not hard-deleted)',
    () async {
      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);
      final row = await insertSession(isar, clientOperationId: opId);

      final result = await repository.deleteSession(row.localId);

      expect(result, isTrue);
      expect(adapter.captured, isEmpty);
      final after = await isar.localSessions.get(row.localId);
      expect(after, isNotNull);
      expect(after!.syncStatus, 'pending_delete');
      expect(after.clientOperationId, opId);
      expect(after.serverId, isNull);
    },
  );

  test('4b. cancellation intent is persisted BEFORE the HTTP attempt, not only '
      'as a failure fallback: while the cancel call is still held in flight, '
      'the row is ALREADY durably pending_delete', () async {
    loginAs(userA);
    final row = await insertSession(isar, clientOperationId: opId);
    final held = Completer<ResponseBody>();
    adapter.responder = (o) => held.future;

    final dispatched = adapter.nextDispatch();
    final deleteFuture = repository.deleteSession(row.localId);

    // Deterministic: the write that marks pending_delete happens
    // synchronously (awaited) before the HTTP call is ever dispatched, so
    // by the time the adapter signals the request reached the transport,
    // the row is already durable. Inspect state WHILE the response is
    // still withheld.
    await dispatched;
    final duringFlight = await isar.localSessions.get(row.localId);
    expect(
      duringFlight,
      isNotNull,
      reason: 'a crash/restart here must not silently revert to visible',
    );
    expect(duringFlight!.syncStatus, 'pending_delete');
    expect(duringFlight.clientOperationId, opId);

    held.complete(_ok204());
    await deleteFuture;
    expect(await isar.localSessions.get(row.localId), isNull);
  });

  for (final failure
      in <String, Future<ResponseBody> Function(RequestOptions)>{
        'network error':
            (o) => Future.error(
              DioException(
                requestOptions: o,
                type: DioExceptionType.connectionError,
              ),
            ),
        '429 rate limited':
            (o) => Future.error(
              DioException(
                requestOptions: o,
                response: Response(
                  requestOptions: o,
                  statusCode: 429,
                  headers: Headers.fromMap({
                    'retry-after': ['30'],
                  }),
                ),
                type: DioExceptionType.badResponse,
              ),
            ),
        'unexpected 5xx':
            (o) => Future.error(
              DioException(
                requestOptions: o,
                response: Response(requestOptions: o, statusCode: 500),
                type: DioExceptionType.badResponse,
              ),
            ),
      }.entries) {
    test(
      '5. cancel dispatch fails (${failure.key}) -> durable intent preserved, '
      'same operation key retained, row stays hidden pending_delete',
      () async {
        loginAs(userA);
        final row = await insertSession(isar, clientOperationId: opId);
        adapter.responder = failure.value;

        final result = await repository.deleteSession(row.localId);

        expect(result, isTrue);
        final after = await isar.localSessions.get(row.localId);
        expect(after, isNotNull);
        expect(after!.syncStatus, 'pending_delete');
        expect(after.clientOperationId, opId);
      },
    );
  }

  test('6. repeated cancellation converges: retrying deleteSession after a '
      'failed attempt dispatches the SAME operation key again, and a second '
      "204 (server's idempotent success) still only removes one row", () async {
    loginAs(userA);
    final row = await insertSession(isar, clientOperationId: opId);
    adapter.responder =
        (o) => Future.error(
          DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
          ),
        );
    await repository.deleteSession(row.localId);
    expect(
      (await isar.localSessions.get(row.localId))!.syncStatus,
      'pending_delete',
    );

    adapter.responder = (o) => Future.value(_ok204());
    final second = await repository.deleteSession(row.localId);

    expect(second, isTrue);
    expect(
      adapter.captured.where((r) => r.path == cancelPath),
      hasLength(2),
      reason: 'both attempts dispatched the SAME retained key',
    );
    expect(await isar.localSessions.get(row.localId), isNull);
  });

  test('7. close/reopen preserves the pending_delete row and its operation key '
      '(durable across restart - no in-memory-only state)', () async {
    loginAs(userA);
    when(mockConnectivity.isOnline).thenReturn(false);
    final row = await insertSession(isar, clientOperationId: opId);
    await repository.deleteSession(row.localId);
    final localId = row.localId;

    await isar.close();
    final reopened = await openIsar(tempDir.path);
    isar = reopened;
    localDb.setTestDatabase(reopened);

    final after = await reopened.localSessions.get(localId);
    expect(after, isNotNull);
    expect(after!.syncStatus, 'pending_delete');
    expect(after.clientOperationId, opId);
  });

  test('8. ordinary logout preserves cancellation intent; same-user login '
      'resumes it (dispatches the SAME key)', () async {
    loginAs(userA);
    when(mockConnectivity.isOnline).thenReturn(false);
    final row = await insertSession(isar, clientOperationId: opId);
    await repository.deleteSession(row.localId);

    // Non-destructive logout: never calls LocalDatabaseService.clearAll().
    logout();
    final duringLogout = await isar.localSessions.get(row.localId);
    expect(duringLogout, isNotNull);
    expect(duringLogout!.syncStatus, 'pending_delete');
    expect(duringLogout.clientOperationId, opId);

    // Same user logs back in - the row (and its key) is exactly as left.
    loginAs(userA);
    when(mockConnectivity.isOnline).thenReturn(true);
    adapter.responder = (o) => Future.value(_ok204());

    // Resume is normally driven by SyncService picking the row back up;
    // here we drive it directly through the same dispatch rule to prove
    // the retained state is what a resumed pass would act on.
    final result = await repository.deleteSession(row.localId);
    expect(result, isTrue);
    expect(adapter.captured.single.path, cancelPath);
  });

  test("9. cross-user isolation: user B's deleteSession call can neither see "
      "nor dispatch anything for A's pending cancellation", () async {
    loginAs(userA);
    final row = await insertSession(isar, clientOperationId: opId);

    loginAs(userB);
    await expectLater(
      () => repository.deleteSession(row.localId),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Session not found'),
        ),
      ),
      reason: "B's localId lookup must not resolve A's row",
    );
    expect(adapter.captured, isEmpty);

    // A's row is completely untouched by B's attempt.
    final after = await isar.localSessions.get(row.localId);
    expect(after!.userId, userA);
    expect(after.clientOperationId, opId);
    expect(after.syncStatus, 'pending_create');
  });

  test('10. acknowledgment recheck: the session epoch is rechecked as the '
      'FIRST statement inside the write transaction - a logout landing there '
      'must not remove the row even though the server already accepted the '
      'cancellation', () async {
    loginAs(userA);
    final row = await insertSession(isar, clientOperationId: opId);
    when(mockConnectivity.isOnline).thenReturn(false);
    await repository.deleteSession(row.localId); // -> pending_delete
    when(mockConnectivity.isOnline).thenReturn(true);
    adapter.responder = (o) => Future.value(_ok204());

    repository.insideWriteTxnForTesting = () async {
      sessionEpoch.invalidate();
    };

    final result = await repository.deleteSession(row.localId);

    expect(result, isTrue, reason: 'the server call itself still succeeded');
    final after = await isar.localSessions.get(row.localId);
    expect(
      after,
      isNotNull,
      reason:
          'a session that ended before the ack write actually ran must '
          'never have its row removed',
    );
    expect(after!.syncStatus, 'pending_delete');
  });

  test('11. a concurrent operation-key backfill racing a keyless-row delete is '
      'never lost: _markForDeletion re-verifies fresh INSIDE its own write '
      "transaction, never hard-deleting a row that just gained an identity "
      "from a race it read as keyless", () async {
    loginAs(userA);
    // Legacy / from-program-workout-fallback shape: pending_create with NO
    // key yet - the exact row class SyncService._ensureCreateOperationKey
    // backfills.
    final row = await insertSession(isar, clientOperationId: null);
    const backfilledKey = 'backfilled-key-9999';

    // Lands exactly in the gap between deleteSession's earlier resolution
    // (which read clientOperationId == null) and _markForDeletion's own
    // write transaction - simulating a concurrent SyncService pass
    // committing a key (and possibly dispatching CREATE) for this exact
    // row in the interim.
    repository.beforeWriteTxnForTesting = () async {
      await isar.writeTxn(() async {
        final current = (await isar.localSessions.get(row.localId))!;
        current.clientOperationId = backfilledKey;
        await isar.localSessions.put(current);
      });
    };

    final result = await repository.deleteSession(row.localId);

    expect(result, isTrue);
    expect(
      adapter.captured,
      isEmpty,
      reason: 'no identity was known at dispatch-decision time',
    );
    final after = await isar.localSessions.get(row.localId);
    expect(
      after,
      isNotNull,
      reason:
          'must never be silently hard-deleted once it has gained an '
          'identity, even one this call never itself observed',
    );
    expect(after!.syncStatus, 'pending_delete');
    expect(
      after.clientOperationId,
      backfilledKey,
      reason:
          'the concurrently-backfilled key is preserved, never '
          'discarded - a later pass can still cancel-by-operation with it',
    );
  });

  test('12. acknowledgment ownership recheck: a row reassigned to a DIFFERENT '
      'user at the same local id, exactly as the ack write begins, is never '
      'removed by this accepted cancellation', () async {
    loginAs(userA);
    final row = await insertSession(isar, clientOperationId: opId);
    when(mockConnectivity.isOnline).thenReturn(false);
    await repository.deleteSession(row.localId); // -> pending_delete
    when(mockConnectivity.isOnline).thenReturn(true);
    adapter.responder = (o) => Future.value(_ok204());

    repository.insideWriteTxnForTesting = () async {
      final current = (await isar.localSessions.get(row.localId))!;
      current.userId = userB;
      await isar.localSessions.put(current);
    };

    final result = await repository.deleteSession(row.localId);

    expect(result, isTrue, reason: 'the server call itself still succeeded');
    final after = await isar.localSessions.get(row.localId);
    expect(
      after,
      isNotNull,
      reason:
          'a row reassigned to a different user must never be removed '
          "by A's ack",
    );
    expect(after!.userId, userB);
  });

  test('13. legacy entry point trace: createSessionFromProgramWorkout\'s '
      'UNKEYED online request fails and falls back to an offline-created row '
      'with NEITHER identity - deleting it immediately (before any sync pass '
      'could ever backfill a key) is safe local-only removal with zero HTTP '
      'calls. The ORIGINAL unkeyed POST, if it actually committed server-side '
      'with its response lost, cannot be correlated or canceled by this or '
      'any later client action - an accepted, pre-existing limitation this '
      'feature does not claim to close (see createSessionFromProgramWorkout\'s '
      'own doc comment).', () async {
    loginAs(userA);
    adapter.responder = (o) {
      if (o.method == 'POST' &&
          o.path == ApiConfig.sessionsFromProgramWorkout) {
        return Future.error(
          DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
          ),
        );
      }
      return Future.value(_ok204());
    };
    final workout = ProgramWorkout(
      id: 1,
      programId: 1,
      weekNumber: 1,
      dayNumber: 1,
      workoutName: 'Leg Day',
      exercisesJson: '[]',
      isCompleted: false,
      orderIndex: 0,
    );

    final created = await repository.createSessionFromProgramWorkout(
      1,
      workout,
      DateTime(2026, 1, 1),
      1,
    );

    final row = await isar.localSessions.get(created.id);
    expect(row, isNotNull);
    expect(row!.serverId, isNull);
    expect(
      row.clientOperationId,
      isNull,
      reason:
          'the from-program-workout offline fallback never assigns a '
          'key - only a later generic sync pass would backfill one',
    );
    adapter.captured.clear();

    final result = await repository.deleteSession(created.id);

    expect(result, isTrue);
    expect(
      adapter.captured,
      isEmpty,
      reason:
          'neither identity existed yet - nothing to cancel or delete '
          'remotely',
    );
    expect(await isar.localSessions.get(created.id), isNull);
  });

  test('14. getSession strips the internal clientOperationId correlation id '
      'before returning to a caller outside the repository layer, even '
      'though the raw GET /sessions/{id} response carries it back', () async {
    loginAs(userA);
    adapter.responder =
        (o) => Future.value(
          jsonResponse({
            'id': 777,
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
            'clientOperationId': 'server-side-op-id',
          }),
        );

    final session = await repository.getSession(777);

    expect(
      session.clientOperationId,
      isNull,
      reason:
          'internal correlation id must never reach code outside the '
          'repository layer',
    );
  });
}

ResponseBody jsonResponse(Object? json, {int statusCode = 200}) =>
    ResponseBody.fromString(
      jsonEncode(json),
      statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );

ResponseBody _ok204() => ResponseBody.fromString(
  '',
  204,
  headers: {
    'content-type': ['application/json'],
  },
);

/// Fake Dio transport: records every request and answers via [responder]
/// (defaults to a 200 empty-array success, matching sibling suites).
class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> captured = [];
  Future<ResponseBody> Function(RequestOptions options)? responder;
  Completer<void>? _dispatchSignal;

  /// Completes deterministically the next time [fetch] is invoked - "the
  /// request reached the transport," distinct from the response being
  /// produced/consumed. Must be called before the operation that triggers
  /// the dispatch.
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
    final respond = responder;
    if (respond != null) return respond(options);
    return Future.value(
      ResponseBody.fromString(
        jsonEncode(<dynamic>[]),
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
