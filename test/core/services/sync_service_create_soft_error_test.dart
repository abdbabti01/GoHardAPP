import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/core/utils/database_cleanup.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/session_create_error.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

// Reuses the Mockito mocks generated for sync_service_test.dart (same
// ApiService / AuthService surface, unchanged by this PR) so this suite adds
// no new build_runner output.
import 'sync_service_test.mocks.dart';

/// Proves `SyncService`'s safe handling of Session CREATE responses that only
/// signal throttling (429) or an API operation state today's client cannot
/// yet reconcile - a recognised `code` on its EXACT contract status
/// (404 `program_not_found`, 409 `operation_canceled`, 409
/// `operation_incomplete`, 410 `operation_target_deleted`): the
/// `pending_create` row and its unsynced children are preserved, never marked
/// synced, never deleted, and never advance the terminal retry /
/// `DatabaseCleanup` threshold - so the create stays retryable. A known code
/// on the WRONG status, an unknown code, and every ordinary 4xx/5xx/transport
/// failure keep their established fail-closed behavior; lifecycle exceptions
/// stay distinct.
///
/// `SessionCreateError.retryAfterHint` was considered and removed: nothing in
/// this PR consumes it (there is no persisted "retry not before" field and no
/// scheduler), and `DateTime.tryParse` only accepts ISO-8601, not the RFC
/// 1123 HTTP-date form a real `Retry-After` header uses - so shipping it
/// would have claimed HTTP `Retry-After` support it did not provide.
///
/// Real Isar, real `UserSessionEpoch`, real `SessionRequestCoordinator`;
/// `MockApiService` with synchronous throwing / `Completer`-gated responders.
/// No wall-clock timing.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late SyncService syncService;

  const userId = 1;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_create_soft_error_');
    isar = await Isar.open(
      [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
    );

    SyncService.reset();
    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userId);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$userId');

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch()..activate(userId);
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
  });

  tearDown(() async {
    SyncService.reset();
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ---- fixtures -------------------------------------------------------------

  Future<LocalSession> insertPendingCreateSession({
    String name = 'Draft workout',
  }) async {
    final session = LocalSession(
      serverId: null,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: name,
      status: 'draft',
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<(LocalExercise, LocalExerciseSet)> insertUnsyncedChildren(
    int sessionLocalId,
  ) async {
    final exercise = LocalExercise(
      sessionLocalId: sessionLocalId,
      name: 'Bench press',
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    late LocalExerciseSet set;
    await isar.writeTxn(() async {
      await isar.localExercises.put(exercise);
      set = LocalExerciseSet(
        exerciseLocalId: exercise.localId,
        setNumber: 1,
        reps: 5,
        weight: 100,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime(2026, 1, 1, 8),
      );
      await isar.localExerciseSets.put(set);
    });
    return (exercise, set);
  }

  Map<String, dynamic> serverSessionJson({
    required int id,
    int version = 1,
    String name = 'Draft workout',
    String status = 'draft',
  }) => {
    'id': id,
    'userId': userId,
    'date': '2026-01-01',
    'duration': null,
    'notes': null,
    'type': null,
    'name': name,
    'status': status,
    'startedAt': null,
    'completedAt': null,
    'pausedAt': null,
    'exercises': <dynamic>[],
    'programId': null,
    'programWorkoutId': null,
    'version': version,
  };

  void stubPostThrow(Object error) {
    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => throw error);
  }

  void stubPostReturn(Map<String, dynamic> response) {
    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => response);
  }

  ApiException apiError(int status, {Object? body}) {
    final requestOptions = RequestOptions(path: '/api/v1/sessions');
    return ApiException(
      'Error ($status)',
      statusCode: status,
      responseData: body,
      originalError: DioException(
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: status,
          data: body,
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }

  /// The deployed GoHardAPI `(status, code)` pairs for structured CREATE
  /// errors, mirroring `SessionCreateError._recognized`.
  const recognizedPairs =
      <({int status, String code, SessionCreateErrorKind kind})>[
        (
          status: 404,
          code: 'program_not_found',
          kind: SessionCreateErrorKind.programNotFound,
        ),
        (
          status: 409,
          code: 'operation_canceled',
          kind: SessionCreateErrorKind.operationCanceled,
        ),
        (
          status: 409,
          code: 'operation_incomplete',
          kind: SessionCreateErrorKind.operationIncomplete,
        ),
        (
          status: 410,
          code: 'operation_target_deleted',
          kind: SessionCreateErrorKind.operationTargetDeleted,
        ),
      ];

  Future<LocalSession?> reload(int localId) => isar.localSessions.get(localId);

  // ======================================================================
  // SessionCreateError classifier (unit) - the typed seam later stages use
  // instead of string-matching an error message.
  // ======================================================================

  group('SessionCreateError classifier', () {
    test('429 -> throttled / soft', () {
      final e = apiError(429);
      expect(SessionCreateError.classify(e), SessionCreateErrorKind.throttled);
      expect(SessionCreateError.isSoftRetryable(e), isTrue);
    });

    test(
      'each recognised (status, code) pair maps to its typed kind and is soft',
      () {
        for (final p in recognizedPairs) {
          final e = apiError(p.status, body: {'code': p.code});
          expect(
            SessionCreateError.classify(e),
            p.kind,
            reason: '${p.status} + ${p.code}',
          );
          expect(
            SessionCreateError.isSoftRetryable(e),
            isTrue,
            reason: '${p.code} must be preserved as retryable',
          );
        }
      },
    );

    test('a KNOWN code on the WRONG status -> unknownStructured, NOT soft '
        '(status/code pairing is enforced, not code alone)', () {
      // Every recognised code paired with each of the OTHER two structured
      // statuses it is never returned with.
      for (final p in recognizedPairs) {
        for (final wrongStatus in const [404, 409, 410]) {
          if (wrongStatus == p.status) continue;
          final e = apiError(wrongStatus, body: {'code': p.code});
          expect(
            SessionCreateError.classify(e),
            SessionCreateErrorKind.unknownStructured,
            reason: 'mismatched pair $wrongStatus + ${p.code}',
          );
          expect(
            SessionCreateError.isSoftRetryable(e),
            isFalse,
            reason: 'mismatched pair $wrongStatus + ${p.code} must fail closed',
          );
        }
      }
    });

    test('the four explicitly required mismatched pairs each fail closed', () {
      const mismatched = <(int, String)>[
        (404, 'operation_canceled'),
        (409, 'program_not_found'),
        (410, 'operation_incomplete'),
        (409, 'operation_target_deleted'),
      ];
      for (final (status, code) in mismatched) {
        final e = apiError(status, body: {'code': code});
        expect(
          SessionCreateError.classify(e),
          SessionCreateErrorKind.unknownStructured,
          reason: '$status + $code',
        );
        expect(
          SessionCreateError.isSoftRetryable(e),
          isFalse,
          reason: '$status + $code must not be soft-retryable',
        );
      }
    });

    test(
      'unknown 404/409/410 code -> unknownStructured, NOT soft (fail closed)',
      () {
        final e = apiError(409, body: {'code': 'brand_new_code'});
        expect(
          SessionCreateError.classify(e),
          SessionCreateErrorKind.unknownStructured,
        );
        expect(SessionCreateError.isSoftRetryable(e), isFalse);
      },
    );

    test('404/409/410 with no/!map body -> unknownStructured, NOT soft', () {
      for (final body in <Object?>[
        null,
        'nope',
        42,
        <int>[1],
      ]) {
        final e = apiError(410, body: body);
        expect(
          SessionCreateError.classify(e),
          SessionCreateErrorKind.unknownStructured,
        );
        expect(SessionCreateError.isSoftRetryable(e), isFalse);
      }
    });

    test(
      'ordinary 4xx / 5xx / transport / non-ApiException -> ordinary, NOT soft',
      () {
        for (final e in <Object>[
          apiError(400, body: {'code': 'operation_canceled'}), // wrong status
          apiError(403),
          apiError(500),
          ApiException('Network error - cannot connect to server'),
          Exception('connection reset'),
          'a bare string',
        ]) {
          expect(
            SessionCreateError.classify(e),
            SessionCreateErrorKind.ordinary,
            reason: 'unexpected classification for $e',
          );
          expect(SessionCreateError.isSoftRetryable(e), isFalse);
        }
      },
    );

    test('lifecycle exceptions classify as ordinary and are never soft - they '
        'must never be routed through the soft-error path', () {
      for (final e in <Object>[
        const SessionStaleException(),
        const RequestCancelledException(),
      ]) {
        expect(SessionCreateError.classify(e), SessionCreateErrorKind.ordinary);
        expect(SessionCreateError.isSoftRetryable(e), isFalse);
      }
    });

    test('429 is classified by status alone - a stray structured body does '
        'not change it (the endpoint returns an empty body on 429)', () {
      for (final body in <Object?>[
        null,
        {'code': 'program_not_found'},
        {'code': 'operation_target_deleted'},
      ]) {
        final e = apiError(429, body: body);
        expect(
          SessionCreateError.classify(e),
          SessionCreateErrorKind.throttled,
        );
        expect(SessionCreateError.isSoftRetryable(e), isTrue);
      }
    });
  });

  // ======================================================================
  // SyncService Session CREATE soft-error behavior (prompt items 1-3, 5-18;
  // item 4 - "Retry-After parsing is safe IF implemented" - is intentionally
  // not implemented: see the note on the removed helper below).
  // ======================================================================

  group('SyncService Session CREATE soft errors', () {
    test(
      '1. 429 preserves the pending Session and its unsynced children',
      () async {
        final s = await insertPendingCreateSession();
        final (ex, set) = await insertUnsyncedChildren(s.localId);
        stubPostThrow(apiError(429));

        await syncService.sync();

        final storedSession = await reload(s.localId);
        expect(storedSession, isNotNull);
        expect(storedSession!.syncStatus, 'pending_create');
        expect(storedSession.serverId, isNull);
        expect(await isar.localExercises.get(ex.localId), isNotNull);
        expect(await isar.localExerciseSets.get(set.localId), isNotNull);
        final storedEx = await isar.localExercises.get(ex.localId);
        expect(storedEx!.isSynced, isFalse);
        expect(storedEx.serverId, isNull);
      },
    );

    test('2. 429 does not mark the row synced', () async {
      final s = await insertPendingCreateSession();
      stubPostThrow(apiError(429));

      await syncService.sync();

      final stored = await reload(s.localId);
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_create');
      expect(stored.serverId, isNull);
      expect(stored.version, isNull);
    });

    test('3. 429 does not advance the terminal retry / cleanup counter, even '
        'across repeated passes, so DatabaseCleanup keeps the row', () async {
      final s = await insertPendingCreateSession();
      final (ex, set) = await insertUnsyncedChildren(s.localId);
      stubPostThrow(apiError(429));

      await syncService.sync();
      await syncService.sync();
      await syncService.sync();

      var stored = await reload(s.localId);
      expect(stored!.syncRetryCount, 0);
      // syncError / lastSyncAttempt still record the diagnostic.
      expect(stored.syncError, isNotNull);
      expect(stored.lastSyncAttempt, isNotNull);

      // The startup sweep only deletes rows with syncRetryCount > 2.
      await DatabaseCleanup.cleanupFailedSessions(isar);

      stored = await reload(s.localId);
      expect(
        stored,
        isNotNull,
        reason: '429 must never make the row sweepable',
      );
      expect(stored!.syncStatus, 'pending_create');
      expect(await isar.localExercises.get(ex.localId), isNotNull);
      expect(await isar.localExerciseSets.get(set.localId), isNotNull);
    });

    test('5. program_not_found (404) does not become success', () async {
      final s = await insertPendingCreateSession();
      stubPostThrow(apiError(404, body: {'code': 'program_not_found'}));

      await syncService.sync();

      final stored = await reload(s.localId);
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_create');
      expect(stored.serverId, isNull);
      expect(stored.syncRetryCount, 0);
    });

    test('6. operation_canceled (409) does not become success or delete local '
        'state', () async {
      final s = await insertPendingCreateSession();
      final (ex, set) = await insertUnsyncedChildren(s.localId);
      stubPostThrow(apiError(409, body: {'code': 'operation_canceled'}));

      await syncService.sync();

      final stored = await reload(s.localId);
      expect(stored, isNotNull);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.isSynced, isFalse);
      expect(stored.serverId, isNull);
      expect(stored.syncRetryCount, 0);
      expect(await isar.localExercises.get(ex.localId), isNotNull);
      expect(await isar.localExerciseSets.get(set.localId), isNotNull);
    });

    test('7. operation_incomplete (409) remains retryable - a later 201 '
        'converges', () async {
      final s = await insertPendingCreateSession();
      stubPostThrow(apiError(409, body: {'code': 'operation_incomplete'}));

      await syncService.sync();
      var stored = await reload(s.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.syncRetryCount, 0);

      stubPostReturn(serverSessionJson(id: 900, version: 1));
      await syncService.sync();

      stored = await reload(s.localId);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
      expect(stored.serverId, 900);
    });

    test('8. operation_target_deleted (410) does not silently recreate or '
        'delete local state and creates no duplicate row', () async {
      final s = await insertPendingCreateSession();
      stubPostThrow(apiError(410, body: {'code': 'operation_target_deleted'}));

      await syncService.sync();

      expect(await isar.localSessions.count(), 1);
      final stored = await reload(s.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.serverId, isNull);
      expect(stored.isSynced, isFalse);
      expect(stored.syncRetryCount, 0);
    });

    test('9. unknown 404/409/410 fails closed - retry counter advances exactly '
        'as for any hard failure', () async {
      final unknown = await insertPendingCreateSession(name: 'unknown-code');
      stubPostThrow(apiError(409, body: {'code': 'brand_new_code'}));
      await syncService.sync();
      expect((await reload(unknown.localId))!.syncRetryCount, 1);
      expect((await reload(unknown.localId))!.syncStatus, 'pending_create');

      // No structured body at all -> still fails closed.
      final noBody = await insertPendingCreateSession(name: 'no-body');
      stubPostThrow(apiError(409));
      await syncService.sync();
      // unknown row attempted again too; assert the fresh row incremented once.
      expect((await reload(noBody.localId))!.syncRetryCount, 1);
    });

    test('9b. a KNOWN code on the WRONG status is not soft - it advances the '
        'ordinary retry counter through _syncSessions like any hard failure '
        '(integration proof that pairing is enforced end to end)', () async {
      final s = await insertPendingCreateSession(name: 'mismatched-pair');
      // program_not_found is a 404 code; here it arrives on a 409.
      stubPostThrow(apiError(409, body: {'code': 'program_not_found'}));

      await syncService.sync();
      expect((await reload(s.localId))!.syncRetryCount, 1);
      await syncService.sync();
      expect((await reload(s.localId))!.syncRetryCount, 2);
      expect((await reload(s.localId))!.syncStatus, 'pending_create');
    });

    test('10. lifecycle exceptions stay typed - the row is left completely '
        'untouched (never routed through _markSyncError)', () async {
      for (final lifecycle in <Object>[
        const SessionStaleException(),
        const RequestCancelledException(),
      ]) {
        await isar.writeTxn(() => isar.localSessions.clear());
        final s = await insertPendingCreateSession();
        stubPostThrow(lifecycle);

        await syncService.sync(); // _startSyncPass swallows it silently

        final stored = await reload(s.localId);
        expect(stored!.syncStatus, 'pending_create');
        expect(stored.serverId, isNull);
        expect(stored.isSynced, isFalse);
        expect(stored.syncRetryCount, 0);
        expect(
          stored.syncError,
          isNull,
          reason: '$lifecycle must not be recorded as a sync error',
        );
        expect(stored.lastSyncAttempt, isNull);
      }
    });

    test(
      '11. lifecycle cancellation during CREATE writes no fallback/duplicate '
      'row',
      () async {
        final s = await insertPendingCreateSession();
        stubPostThrow(const RequestCancelledException());

        await syncService.sync();

        expect(await isar.localSessions.count(), 1);
        final stored = await reload(s.localId);
        expect(stored!.localId, s.localId);
        expect(stored.syncStatus, 'pending_create');
        expect(stored.serverId, isNull);
      },
    );

    test('12. recognised structured errors and cancellation never invoke '
        'unauthorized / logout handling', () async {
      final s = await insertPendingCreateSession();

      stubPostThrow(apiError(410, body: {'code': 'operation_target_deleted'}));
      await syncService.sync();
      stubPostThrow(const RequestCancelledException());
      await syncService.sync();

      verifyNever(mockAuthService.clearToken());
      verifyNever(mockAuthService.clearSessionCredentials());
      // The session epoch was never invalidated (logout bumps it and clears
      // the active user, making capture() return null).
      final token = sessionEpoch.capture();
      expect(token, isNotNull);
      expect(token!.userId, userId);
      expect(sessionEpoch.isCurrent(token), isTrue);
      // The context is still usable: a subsequent 201 converges normally.
      stubPostReturn(serverSessionJson(id: 910));
      await syncService.sync();
      expect((await reload(s.localId))!.syncStatus, 'synced');
    });

    test('13. 201 CREATE behavior is unchanged', () async {
      final s = await insertPendingCreateSession();
      stubPostReturn(serverSessionJson(id: 500, version: 3));

      await syncService.sync();

      final stored = await reload(s.localId);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
      expect(stored.serverId, 500);
      expect(stored.version, 3);
      expect(stored.syncRetryCount, 0);
    });

    test('14. a keyed 200 replay body is accepted through the ordinary success '
        'path (no status-string special-casing)', () async {
      final s = await insertPendingCreateSession();
      // The deployed 200 replay body has the SAME shape as the 201 body
      // (SessionResponseDto); the mock success path returns response.data
      // regardless of status, so this exercises exactly that acceptance.
      stubPostReturn(serverSessionJson(id: 777, version: 9));

      await syncService.sync();

      final stored = await reload(s.localId);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
      expect(stored.serverId, 777);
      expect(stored.version, 9);
    });

    test('15. 5xx and transport failures remain compatible (hard failure, '
        'retry counter advances)', () async {
      final a = await insertPendingCreateSession(name: '5xx');
      stubPostThrow(apiError(500));
      await syncService.sync();
      expect((await reload(a.localId))!.syncRetryCount, 1);
      expect((await reload(a.localId))!.syncStatus, 'pending_create');

      final b = await insertPendingCreateSession(name: 'transport');
      stubPostThrow(ApiException('Network error - cannot connect to server'));
      await syncService.sync();
      expect((await reload(b.localId))!.syncRetryCount, 1);
      expect((await reload(b.localId))!.syncStatus, 'pending_create');
    });

    test('16. children are not synchronized before the parent has a valid '
        'server ID - the throttled parent stays id-less and no child POST is '
        'attempted', () async {
      final s = await insertPendingCreateSession();
      final (ex, set) = await insertUnsyncedChildren(s.localId);
      stubPostThrow(apiError(429));

      await syncService.sync();

      // Exactly one POST: the session CREATE. The exercise phase saw a
      // server-id-less parent and skipped it.
      verify(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).called(1);
      final storedEx = await isar.localExercises.get(ex.localId);
      expect(storedEx!.isSynced, isFalse);
      expect(storedEx.serverId, isNull);
      expect(storedEx.sessionServerId, isNull);
      expect(storedEx.syncStatus, 'pending_create');
      expect(
        (await isar.localExerciseSets.get(set.localId))!.isSynced,
        isFalse,
      );
    });

    test('17. a later successful retry after a 429 converges normally with no '
        'residual retry debt', () async {
      final s = await insertPendingCreateSession();
      stubPostThrow(apiError(429));
      await syncService.sync();
      expect((await reload(s.localId))!.syncStatus, 'pending_create');

      stubPostReturn(serverSessionJson(id: 1234, version: 2));
      await syncService.sync();

      final stored = await reload(s.localId);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
      expect(stored.serverId, 1234);
      expect(stored.version, 2);
      expect(stored.syncRetryCount, 0);
      expect(stored.syncStatus, isNot('pending_create'));
    });

    test('18. the pending_update -> pending_create no-serverId CREATE fallback '
        'is also protected: a 429 there does not advance the terminal counter '
        '(the catch sees the stale pending_update snapshot; _markSyncError '
        're-checks the acknowledgment-time row)', () async {
      // A malformed row: pending_update but never acknowledged (serverId null).
      // _syncUpdateSession flips it to pending_create in its own writeTxn and
      // then runs the CREATE path.
      final s = LocalSession(
        serverId: null,
        userId: userId,
        date: DateTime(2026, 1, 1),
        name: 'stuck update',
        status: 'draft',
        isSynced: false,
        syncStatus: 'pending_update',
        lastModifiedLocal: DateTime(2026, 1, 1, 8),
      );
      await isar.writeTxn(() => isar.localSessions.put(s));
      final (ex, set) = await insertUnsyncedChildren(s.localId);
      stubPostThrow(apiError(429));

      await syncService.sync();
      await syncService.sync();
      await syncService.sync();

      var stored = await reload(s.localId);
      expect(stored, isNotNull);
      // The fallback conversion still happened...
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.serverId, isNull);
      expect(stored.isSynced, isFalse);
      // ...but the throttle never advanced the terminal counter.
      expect(stored.syncRetryCount, 0);

      await DatabaseCleanup.cleanupFailedSessions(isar);

      stored = await reload(s.localId);
      expect(
        stored,
        isNotNull,
        reason:
            'a throttled CREATE via the update fallback must not be '
            'sweepable either',
      );
      expect(await isar.localExercises.get(ex.localId), isNotNull);
      expect(await isar.localExerciseSets.get(set.localId), isNotNull);
    });

    test(
      '19. the soft-error suppression is CREATE-only: a 429 on a real '
      'pending_delete still advances the ordinary retry counter (the '
      'pending_create gate must not soften update/delete failures)',
      () async {
        final s = LocalSession(
          serverId: 4242,
          userId: userId,
          date: DateTime(2026, 1, 1),
          name: 'to delete',
          status: 'draft',
          isSynced: false,
          syncStatus: 'pending_delete',
          lastModifiedLocal: DateTime(2026, 1, 1, 8),
        );
        await isar.writeTxn(() => isar.localSessions.put(s));
        when(
          mockApiService.delete(
            any,
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async => throw apiError(429));

        await syncService.sync();
        expect((await reload(s.localId))!.syncRetryCount, 1);
        await syncService.sync();

        final stored = await reload(s.localId);
        expect(stored, isNotNull);
        expect(stored!.syncStatus, 'pending_delete');
        expect(
          stored.syncRetryCount,
          2,
          reason: 'a 429 on DELETE is not the CREATE soft path - it must count',
        );
      },
    );
  });
}
