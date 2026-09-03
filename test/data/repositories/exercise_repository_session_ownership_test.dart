import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/exercise_set.dart';
import 'package:go_hard_app/data/repositories/exercise_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';
import 'package:go_hard_app/providers/log_sets_provider.dart';

import 'exercise_repository_session_ownership_test.mocks.dart';

@GenerateMocks([AuthService, ConnectivityService])
/// Proves [ExerciseRepository]'s user-owned set operations are:
///
/// - fully session-bound (every authenticated call carries the entry
///   [SessionRequestContext], proven against the real Dio interceptor via a
///   fake [HttpClientAdapter]);
/// - resolved through a **collision-free public-id namespace**: a positive
///   input is ONLY a server id (no positive-local fallback), a negative input
///   is ONLY the encoded local id `-localId` (server ids never queried for
///   it), `0` is rejected. An offline set/exercise and a synced sibling that
///   share a numeric local/server id are independently addressable;
/// - typed on every stale path - `null` capture, post-await, pre-transaction,
///   first-in-transaction, testing-hook gap - all surface as
///   [SessionStaleException]; never `[]` / `false` / a value / silent success;
/// - fail-closed on same-session ownership loss - a skipped acknowledgment
///   never returns a publishable object (create/complete/update throw
///   not-found); a DELETE whose server call succeeded treats a since-gone
///   local row as convergence.
///
/// No wall-clock waits: dispatch is observed via
/// [_FakeHttpClientAdapter.nextDispatch] and held responses via [Completer].
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
  late ExerciseRepository repository;
  late int unauthorizedCalls;

  const userA = 1;
  const userB = 2;

  int? currentAuthUserId;

  /// The encoded public id of an offline (not-yet-synced) row.
  int offline(int localId) => -localId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('exercise_repo_owner_');
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
    unauthorizedCalls = 0;
    apiService.onUnauthorized = () => unauthorizedCalls++;

    repository = ExerciseRepository(
      apiService,
      localDb,
      mockConnectivity,
      sessionEpoch,
      sessionCoordinator,
    );
  });

  tearDown(() async {
    repository.beforeWriteTxnForTesting = null;
    repository.insideWriteTxnForTesting = null;
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

  Future<LocalSession> insertSession({int uid = userA, int? serverId}) async {
    final now = DateTime.now();
    final session = LocalSession(
      serverId: serverId,
      userId: uid,
      date: DateTime(2026, 1, 1),
      status: 'in_progress',
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<LocalExercise> insertExercise({
    required int sessionLocalId,
    int? serverId,
    int? sessionServerId,
    int? explicitLocalId,
  }) async {
    final now = DateTime.now();
    final exercise = LocalExercise(
      serverId: serverId,
      sessionLocalId: sessionLocalId,
      sessionServerId: sessionServerId,
      name: 'Bench Press',
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    if (explicitLocalId != null) exercise.localId = explicitLocalId;
    await isar.writeTxn(() => isar.localExercises.put(exercise));
    return exercise;
  }

  Future<LocalExerciseSet> insertSet({
    required int exerciseLocalId,
    int? serverId,
    int? exerciseServerId,
    int? explicitLocalId,
    int setNumber = 1,
    int reps = 10,
    double weight = 100,
    bool isCompleted = false,
    bool synced = true,
    String? syncStatus,
  }) async {
    final now = DateTime.now();
    final set = LocalExerciseSet(
      serverId: serverId,
      exerciseLocalId: exerciseLocalId,
      exerciseServerId: exerciseServerId,
      setNumber: setNumber,
      reps: reps,
      weight: weight,
      isCompleted: isCompleted,
      isSynced: synced,
      syncStatus: syncStatus ?? (synced ? 'synced' : 'pending_create'),
      lastModifiedLocal: now,
    );
    if (explicitLocalId != null) set.localId = explicitLocalId;
    await isar.writeTxn(() => isar.localExerciseSets.put(set));
    return set;
  }

  /// Seed a fully-owned graph: session -> exercise (synced) -> nothing.
  Future<LocalExercise> ownedExercise({
    int uid = userA,
    int sessionServerId = 500,
    int exerciseServerId = 200,
  }) async {
    final session = await insertSession(uid: uid, serverId: sessionServerId);
    return insertExercise(
      sessionLocalId: session.localId,
      serverId: exerciseServerId,
      sessionServerId: sessionServerId,
    );
  }

  ResponseBody jsonBody(Object json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  Map<String, dynamic> setJson({
    required int id,
    required int exerciseId,
    int setNumber = 1,
    int reps = 10,
    double weight = 100,
    bool isCompleted = false,
  }) => {
    'id': id,
    'exerciseId': exerciseId,
    'setNumber': setNumber,
    'reps': reps,
    'weight': weight,
    'isCompleted': isCompleted,
  };

  RequestOptions onlyRequest() {
    expect(adapter.capturedRequests, hasLength(1));
    return adapter.capturedRequests.single;
  }

  // ==================================================================
  // Context capture / HTTP binding / typed stale entry
  // ==================================================================

  group('context capture and HTTP binding', () {
    test('logged-out user-owned operations throw SessionStaleException with '
        'no HTTP and no Isar write', () async {
      // No loginAs() - captureContext() returns null.
      final ex = await insertExercise(sessionLocalId: 1, serverId: 200);

      await expectLater(
        repository.getExerciseSets(200),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.createExerciseSet(
          ExerciseSet(id: 0, exerciseId: 200, setNumber: 1),
        ),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.completeExerciseSet(7),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.deleteExerciseSet(7),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.updateExerciseSet(
          7,
          ExerciseSet(id: 7, exerciseId: 200, setNumber: 1),
        ),
        throwsA(isA<SessionStaleException>()),
      );

      expect(adapter.capturedRequests, isEmpty);
      expect(await isar.localExerciseSets.count(), 0);
      expect((await isar.localExercises.get(ex.localId))!.serverId, 200);
      expect(unauthorizedCalls, 0);
    });

    test(
      'session change while the JWT read is in flight -> SessionStaleException, '
      'no request',
      () async {
        loginAs(userA);
        await ownedExercise();

        final tokenGate = Completer<String?>();
        when(mockAuthService.getToken()).thenAnswer((_) => tokenGate.future);

        final future = repository.getExerciseSets(200);
        loginAs(userB); // A -> B while getToken() is suspended
        tokenGate.complete('jwt-late');

        await expectLater(future, throwsA(isA<SessionStaleException>()));
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('every in-scope HTTP call carries the entry context: pinned JWT + '
        'epoch metadata + generation CancelToken', () async {
      loginAs(userA);
      await ownedExercise();
      adapter.responder = (_) async => jsonBody(<dynamic>[]);

      await repository.getExerciseSets(200);

      final sent = onlyRequest();
      expect(sent.headers['Authorization'], 'Bearer jwt-$userA');
      final epochToken =
          sent.extra[ApiService.sessionEpochExtraKey] as UserSessionToken;
      expect(epochToken.userId, userA);
      expect(sent.cancelToken, isNotNull);
    });

    test('the create POST and the delete DELETE each carry the entry context '
        '(pinned JWT + epoch metadata)', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 55,
        exerciseServerId: 200,
        explicitLocalId: 4,
      );

      adapter.responder =
          (_) async => jsonBody(setJson(id: 900, exerciseId: 200));
      await repository.createExerciseSet(
        ExerciseSet(id: 0, exerciseId: 200, setNumber: 1, reps: 10, weight: 30),
      );
      var sent = onlyRequest();
      expect(sent.method, 'POST');
      expect(sent.headers['Authorization'], 'Bearer jwt-$userA');
      expect(sent.extra[ApiService.sessionEpochExtraKey], isNotNull);

      adapter.capturedRequests.clear();
      adapter.responder = (_) async => ResponseBody.fromString('', 204);
      await repository.deleteExerciseSet(55);
      sent = onlyRequest();
      expect(sent.method, 'DELETE');
      expect(sent.headers['Authorization'], 'Bearer jwt-$userA');
      expect(sent.extra[ApiService.sessionEpochExtraKey], isNotNull);
    });

    test('create POST / delete DELETE: stale before dispatch -> '
        'SessionStaleException, zero network requests', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 55,
        exerciseServerId: 200,
      );
      apiService.beforeDispatchEpochCheckForTesting = () async => logout();

      await expectLater(
        repository.createExerciseSet(
          ExerciseSet(id: 0, exerciseId: 200, setNumber: 1),
        ),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);

      loginAs(userA);
      apiService.beforeDispatchEpochCheckForTesting = () async => logout();
      await expectLater(
        repository.deleteExerciseSet(55),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });

    test('the single refresh GET carries the entry epoch token', () async {
      loginAs(userA);
      await ownedExercise();
      await insertSet(exerciseLocalId: 1, serverId: 7, exerciseServerId: 200);
      adapter.responder =
          (_) async =>
              jsonBody([setJson(id: 7, exerciseId: 200, isCompleted: true)]);

      await repository.getExerciseSets(200);

      expect(adapter.capturedRequests, hasLength(1));
      final token =
          adapter.capturedRequests.single.extra[ApiService.sessionEpochExtraKey]
              as UserSessionToken;
      expect(token.generation, sessionEpoch.capture()!.generation);
    });

    test('stale before dispatch -> SessionStaleException, zero requests, '
        'onUnauthorized not called', () async {
      loginAs(userA);
      final ex = await ownedExercise();
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
      );
      apiService.beforeDispatchEpochCheckForTesting = () async => logout();

      await expectLater(
        repository.completeExerciseSet(7),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);
      expect(unauthorizedCalls, 0);
    });

    test('in-flight logout cancellation -> RequestCancelledException, '
        'onUnauthorized not called, no local write', () async {
      loginAs(userA);
      final ex = await ownedExercise();
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
      );
      adapter.neverCompletes = true;

      final future = repository.completeExerciseSet(7);
      await adapter.nextDispatch();
      sessionCoordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
      expect(unauthorizedCalls, 0);
      final set =
          await isar.localExerciseSets.filter().serverIdEqualTo(7).findFirst();
      expect(set!.isCompleted, isFalse);
    });

    test('user B captures a fresh context; A\'s cancelled generation cannot '
        'cancel B', () async {
      loginAs(userA);
      final aEx = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: aEx.localId,
        serverId: 7,
        exerciseServerId: 200,
      );
      adapter.neverCompletes = true;

      final aFuture = repository.completeExerciseSet(7);
      await adapter.nextDispatch();
      sessionCoordinator.cancelCurrentGeneration();
      await expectLater(aFuture, throwsA(isA<RequestCancelledException>()));

      logout();
      loginAs(userB);
      adapter.neverCompletes = false;
      final bSession = await insertSession(uid: userB, serverId: 600);
      final bEx = await insertExercise(
        sessionLocalId: bSession.localId,
        serverId: 300,
        sessionServerId: 600,
      );
      await insertSet(
        exerciseLocalId: bEx.localId,
        serverId: 8,
        exerciseServerId: 300,
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      await repository.completeExerciseSet(8);
      final bSet =
          await isar.localExerciseSets.filter().serverIdEqualTo(8).findFirst();
      expect(bSet!.isCompleted, isTrue);
    });
  });

  // ==================================================================
  // Collision-free identity namespace (Blocker 1)
  // ==================================================================

  group('collision-free public-id namespace', () {
    test('offline set localId 7 and synced sibling serverId 7 are '
        'independently addressable, and complete/delete of the offline set '
        'dispatch no HTTP', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      // Synced sibling: serverId 7, localId 3.
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
        setNumber: 1,
      );
      // Offline set: serverId null, localId 7 -> public id -7.
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: null,
        explicitLocalId: 7,
        synced: false,
        syncStatus: 'pending_create',
        setNumber: 2,
      );

      // Complete the OFFLINE set via its negative public id: no HTTP, only it.
      await repository.completeExerciseSet(offline(7));
      expect(adapter.capturedRequests, isEmpty);
      expect((await isar.localExerciseSets.get(7))!.isCompleted, isTrue);
      expect((await isar.localExerciseSets.get(3))!.isCompleted, isFalse);

      // Delete the OFFLINE set via its negative public id: no HTTP, and it
      // leaves a serverId-less pending_delete tombstone (its CREATE may be
      // mid-flight in SyncService while online) - never touching the synced
      // sibling.
      final ok = await repository.deleteExerciseSet(offline(7));
      expect(ok, isTrue);
      expect(adapter.capturedRequests, isEmpty);
      final tombstone = await isar.localExerciseSets.get(7);
      expect(tombstone, isNotNull);
      expect(tombstone!.syncStatus, 'pending_delete');
      expect(tombstone.serverId, isNull);
      expect(tombstone.isSynced, isFalse);
      expect((await isar.localExerciseSets.get(3))!.serverId, 7);
    });

    test('completing / deleting POSITIVE id 7 targets only the synced '
        'serverId-7 row', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
      );
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: null,
        explicitLocalId: 7,
        synced: false,
        syncStatus: 'pending_create',
        setNumber: 2,
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      await repository.completeExerciseSet(7);
      expect(onlyRequest().path, endsWith('exercisesets/7/complete'));
      expect((await isar.localExerciseSets.get(3))!.isCompleted, isTrue);
      expect((await isar.localExerciseSets.get(7))!.isCompleted, isFalse);

      adapter.capturedRequests.clear();
      await repository.deleteExerciseSet(7);
      expect(onlyRequest().path, endsWith('exercisesets/7'));
      expect(await isar.localExerciseSets.get(3), isNull);
      expect(await isar.localExerciseSets.get(7), isNotNull);
    });

    test(
      'offline exercise localId 7 and synced exercise serverId 7 resolve '
      'independently; the negative offline id never dispatches /exercise/7',
      () async {
        loginAs(userA);
        final session = await insertSession(uid: userA, serverId: 500);
        // Synced exercise: serverId 7, localId 3.
        await insertExercise(
          sessionLocalId: session.localId,
          serverId: 7,
          sessionServerId: 500,
          explicitLocalId: 3,
        );
        // Offline exercise: serverId null, localId 7 -> public id -7.
        await insertExercise(
          sessionLocalId: session.localId,
          serverId: null,
          explicitLocalId: 7,
        );
        await insertSet(
          exerciseLocalId: 7,
          serverId: null,
          synced: false,
          setNumber: 1,
          reps: 5,
        );
        adapter.responder =
            (_) async => jsonBody([setJson(id: 55, exerciseId: 7)]);

        // Loading sets for the OFFLINE exercise: no HTTP, returns its local set.
        final offlineSets = await repository.getExerciseSets(offline(7));
        expect(adapter.capturedRequests, isEmpty);
        expect(offlineSets, hasLength(1));

        // Loading sets for the SYNCED exercise (positive 7): dispatches
        // /exercise/7 exactly once.
        final syncedSets = await repository.getExerciseSets(7);
        expect(adapter.capturedRequests, hasLength(1));
        expect(onlyRequest().path, endsWith('exercisesets/exercise/7'));
        expect(syncedSets.map((s) => s.id), contains(55));
      },
    );

    test('creating a set for the negative offline exercise id writes a pending '
        'row and dispatches no HTTP', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 500);
      final ex = await insertExercise(
        sessionLocalId: session.localId,
        serverId: null,
        explicitLocalId: 7,
      );

      final created = await repository.createExerciseSet(
        ExerciseSet(
          id: 0,
          exerciseId: offline(ex.localId),
          setNumber: 1,
          reps: 10,
          weight: 40,
        ),
      );

      expect(adapter.capturedRequests, isEmpty);
      expect(created.id, lessThan(0)); // encoded local id
      final row = await isar.localExerciseSets.get(-created.id);
      expect(row!.syncStatus, 'pending_create');
      expect(row.serverId, isNull);
      expect(row.exerciseLocalId, ex.localId);
    });

    test('zero is rejected even when a legacy serverId==0 row exists - it is '
        'never resolved as a server id', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      // A legacy row physically carrying serverId == 0.
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 0,
        exerciseServerId: 200,
        explicitLocalId: 5,
        synced: false,
        syncStatus: 'pending_create',
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      await expectLater(
        repository.getExerciseSets(0),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.completeExerciseSet(0),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.deleteExerciseSet(0),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.createExerciseSet(
          ExerciseSet(id: 0, exerciseId: 0, setNumber: 1),
        ),
        throwsA(isA<Exception>()),
      );
      expect(adapter.capturedRequests, isEmpty);
      expect((await isar.localExerciseSets.get(5))!.isCompleted, isFalse);
    });

    test(
      'a legacy row persisted with serverId == 0: exposed as a negative id, '
      'and complete/delete of it NEVER dispatches /exercisesets/0 even online',
      () async {
        loginAs(userA);
        final ex = await ownedExercise(exerciseServerId: 200);
        await insertSet(
          exerciseLocalId: ex.localId,
          serverId: 0, // legacy sentinel
          exerciseServerId: 200,
          explicitLocalId: 5,
          synced: false,
          syncStatus: 'pending_create',
        );
        // Online, but a legacy-0 set must be treated as not-yet-synced.
        adapter.responder = (_) async {
          // The refresh GET is the only allowed request; a PATCH/DELETE to
          // /exercisesets/0 is a bug.
          return jsonBody(<dynamic>[]);
        };

        final sets = await repository.getExerciseSets(200);
        expect(sets.single.id, offline(5));
        adapter.capturedRequests.clear();

        await repository.completeExerciseSet(offline(5));
        final ok = await repository.deleteExerciseSet(offline(5));
        expect(ok, isTrue);

        expect(
          adapter.capturedRequests.where(
            (r) => r.path.contains('exercisesets/0'),
          ),
          isEmpty,
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('after sync assigns a positive server id, the mapped public id '
        'changes from -localId to that server id', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      final set = await insertSet(
        exerciseLocalId: ex.localId,
        serverId: null,
        exerciseServerId: 200,
        explicitLocalId: 5,
        synced: false,
        syncStatus: 'pending_create',
      );
      when(mockConnectivity.isOnline).thenReturn(false);
      expect((await repository.getExerciseSets(200)).single.id, offline(5));

      // Simulate SyncService assigning a server id.
      await isar.writeTxn(() async {
        set.serverId = 900;
        set.isSynced = true;
        set.syncStatus = 'synced';
        await isar.localExerciseSets.put(set);
      });

      expect((await repository.getExerciseSets(200)).single.id, 900);
    });

    test('a foreign local-id collision: A\'s server id equals B\'s local id - '
        'A\'s POSITIVE operation never touches B\'s row', () async {
      // B owns a set: localId 50, serverId 999.
      final bSession = await insertSession(uid: userB, serverId: 600);
      final bEx = await insertExercise(
        sessionLocalId: bSession.localId,
        serverId: 300,
        sessionServerId: 600,
      );
      await insertSet(
        exerciseLocalId: bEx.localId,
        serverId: 999,
        exerciseServerId: 300,
        explicitLocalId: 50,
        isCompleted: false,
      );

      loginAs(userA);
      await expectLater(
        repository.completeExerciseSet(50), // positive -> server id 50
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.deleteExerciseSet(50),
        throwsA(isA<Exception>()),
      );
      expect(adapter.capturedRequests, isEmpty);
      final bSet = await isar.localExerciseSets.get(50);
      expect(bSet, isNotNull);
      expect(bSet!.isCompleted, isFalse);
    });

    test(
      'a negative offline id belonging to another user resolves nothing',
      () async {
        final bSession = await insertSession(uid: userB, serverId: 600);
        final bEx = await insertExercise(
          sessionLocalId: bSession.localId,
          serverId: 300,
          sessionServerId: 600,
        );
        await insertSet(
          exerciseLocalId: bEx.localId,
          serverId: null,
          explicitLocalId: 7,
          synced: false,
          syncStatus: 'pending_create',
        );

        loginAs(userA);
        await expectLater(
          repository.completeExerciseSet(offline(7)),
          throwsA(isA<Exception>()),
        );
        expect(adapter.capturedRequests, isEmpty);
        expect((await isar.localExerciseSets.get(7))!.isCompleted, isFalse);
      },
    );

    test('no positive public id falls back to an Isar local id', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      // A synced set whose LOCAL id is 9 and SERVER id is 900.
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 900,
        exerciseServerId: 200,
        explicitLocalId: 9,
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      // Positive 9 must be interpreted as a server id (none) -> not found,
      // NOT as the local id of the serverId-900 row.
      await expectLater(
        repository.completeExerciseSet(9),
        throwsA(isA<Exception>()),
      );
      expect(adapter.capturedRequests, isEmpty);
      expect((await isar.localExerciseSets.get(9))!.isCompleted, isFalse);
    });

    test('an offline-created set survives a getExerciseSets reload with a '
        'negative id and stays mutable through complete/delete', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 500);
      await insertExercise(
        sessionLocalId: session.localId,
        serverId: 200,
        sessionServerId: 500,
      );
      when(mockConnectivity.isOnline).thenReturn(false);

      final created = await repository.createExerciseSet(
        ExerciseSet(id: 0, exerciseId: 200, setNumber: 1, reps: 10, weight: 50),
      );
      expect(created.id, lessThan(0));

      final reloaded = await repository.getExerciseSets(200);
      expect(reloaded, hasLength(1));
      expect(reloaded.single.id, created.id);

      await repository.completeExerciseSet(reloaded.single.id);
      expect(
        (await isar.localExerciseSets.get(-created.id))!.isCompleted,
        true,
      );

      // Delete leaves a serverId-less `pending_delete` tombstone (not a hard
      // delete): connectivity cannot prove a CREATE was not already dispatched.
      // The row stays queryable for the CREATE ack; `_syncDeleteSet` reaps it
      // on the next pass with no HTTP while it has no server id.
      final ok = await repository.deleteExerciseSet(reloaded.single.id);
      expect(ok, isTrue);
      final tombstone = await isar.localExerciseSets.get(-created.id);
      expect(tombstone, isNotNull);
      expect(tombstone!.syncStatus, 'pending_delete');
      expect(tombstone.serverId, isNull);
      expect(tombstone.isSynced, isFalse);
      expect(adapter.capturedRequests, isEmpty);
    });
  });

  // ==================================================================
  // Legacy serverId == 0 rows: canonicalized to null whenever touched
  // ==================================================================

  group('legacy serverId == 0 - repository canonicalizes on touch', () {
    test('completeExerciseSet on a legacy serverId-0 set nulls the serverId, '
        'keeps syncStatus pending_create, never touches /0, and the reloaded '
        'row still maps to the negative public id', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 0, // legacy sentinel
        exerciseServerId: 200,
        explicitLocalId: 5,
        synced: false,
        syncStatus: 'pending_create',
      );
      adapter.responder = (_) async => jsonBody(<dynamic>[]);

      final view = await repository.completeExerciseSet(offline(5));
      expect(view.id, offline(5));

      final row = await isar.localExerciseSets.get(5);
      expect(row!.serverId, isNull, reason: 'legacy 0 canonicalized to null');
      expect(row.isCompleted, isTrue);
      expect(
        row.syncStatus,
        'pending_create',
        reason: 'no server identity -> stays an initial CREATE, not an update',
      );
      expect(
        adapter.capturedRequests.where((r) => r.path.contains('/0')),
        isEmpty,
      );

      final reloaded = await repository.getExerciseSets(200);
      expect(reloaded.single.id, offline(5));
    });

    test('completeExerciseSet on a legacy serverId-0 row wrongly marked '
        'synced drops it to pending_create (not left as an unsyncable '
        'synced row)', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 0,
        exerciseServerId: 200,
        explicitLocalId: 5,
        synced: true,
        syncStatus: 'synced',
      );
      adapter.responder = (_) async => jsonBody(<dynamic>[]);

      await repository.completeExerciseSet(offline(5));

      final row = await isar.localExerciseSets.get(5);
      expect(row!.serverId, isNull);
      expect(row.isCompleted, isTrue);
      expect(row.isSynced, isFalse);
      expect(row.syncStatus, 'pending_create');
      expect(
        adapter.capturedRequests.where((r) => r.path.contains('/0')),
        isEmpty,
      );
    });

    test('deleteExerciseSet on a legacy serverId-0 set removes it locally with '
        'no DELETE call at all', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 0,
        exerciseServerId: 200,
        explicitLocalId: 5,
        synced: true,
        syncStatus: 'synced',
      );

      final ok = await repository.deleteExerciseSet(offline(5));
      expect(ok, isTrue);
      expect(await isar.localExerciseSets.get(5), isNull);
      expect(
        adapter.capturedRequests.where((r) => r.method == 'DELETE'),
        isEmpty,
      );

      adapter.responder = (_) async => jsonBody(<dynamic>[]);
      expect(await repository.getExerciseSets(200), isEmpty);
    });

    test(
      'createExerciseSet under a legacy serverId-0 exercise writes a pending '
      'row whose parent id is null (never 0) and dispatches no HTTP',
      () async {
        loginAs(userA);
        final session = await insertSession(uid: userA, serverId: 500);
        await insertExercise(
          sessionLocalId: session.localId,
          serverId: 0, // legacy parent
          sessionServerId: 500,
          explicitLocalId: 9,
        );

        final created = await repository.createExerciseSet(
          ExerciseSet(
            id: 0,
            exerciseId: offline(9),
            setNumber: 1,
            reps: 8,
            weight: 60,
          ),
        );

        expect(created.id, lessThan(0));
        expect(adapter.capturedRequests, isEmpty);
        final row = await isar.localExerciseSets.get(-created.id);
        expect(row!.syncStatus, 'pending_create');
        expect(row.serverId, isNull);
        expect(
          row.exerciseServerId,
          isNull,
          reason: 'legacy 0 not copied across',
        );
        expect(row.exerciseLocalId, 9);

        final reloaded = await repository.getExerciseSets(offline(9));
        expect(reloaded.single.id, created.id);
      },
    );
  });

  // ==================================================================
  // Typed stale-path (Blocker 2)
  // ==================================================================

  group('every repository-detected stale state is typed', () {
    Future<LocalExerciseSet> ownedSet() async {
      final ex = await ownedExercise(exerciseServerId: 200);
      return insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
        synced: true,
        syncStatus: 'synced',
      );
    }

    test(
      'stale AFTER HTTP completion but before the repository continuation: '
      'getExerciseSets throws SessionStaleException, writes nothing',
      () async {
        loginAs(userA);
        await ownedExercise();
        await insertSet(exerciseLocalId: 1, serverId: 7, exerciseServerId: 200);
        final gate = Completer<ResponseBody>();
        adapter.responder = (_) async => gate.future;

        final future = repository.getExerciseSets(200);
        await adapter.nextDispatch();
        logout();
        gate.complete(
          jsonBody([setJson(id: 7, exerciseId: 200, isCompleted: true)]),
        );

        await expectLater(future, throwsA(isA<SessionStaleException>()));
        expect((await isar.localExerciseSets.get(1))!.isCompleted, isFalse);
      },
    );

    test('stale AFTER PATCH completion: completeExerciseSet throws '
        'SessionStaleException, no pending row, no local write', () async {
      loginAs(userA);
      await ownedSet();
      final gate = Completer<ResponseBody>();
      adapter.responder = (_) async => gate.future;

      final future = repository.completeExerciseSet(7);
      await adapter.nextDispatch();
      logout();
      gate.complete(ResponseBody.fromString('', 204));

      await expectLater(future, throwsA(isA<SessionStaleException>()));
      final row = await isar.localExerciseSets.get(3);
      expect(row!.isCompleted, isFalse);
      expect(row.syncStatus, 'synced'); // never touched
    });

    test('stale in the pre-transaction hook gap: throws SessionStaleException, '
        'the writeTxn body is never entered', () async {
      loginAs(userA);
      await ownedSet();
      adapter.responder = (_) async => ResponseBody.fromString('', 204);
      var insideTxn = 0;
      repository.insideWriteTxnForTesting = () async => insideTxn++;
      repository.beforeWriteTxnForTesting = () async => logout();

      await expectLater(
        repository.completeExerciseSet(7),
        throwsA(isA<SessionStaleException>()),
      );
      expect(insideTxn, 0);
      expect((await isar.localExerciseSets.get(3))!.isCompleted, isFalse);
    });

    test(
      'stale as the first transaction action: throws SessionStaleException, '
      'nothing is written even though row + owner are unchanged in Isar',
      () async {
        loginAs(userA);
        await ownedSet();
        adapter.responder = (_) async => ResponseBody.fromString('', 204);
        repository.insideWriteTxnForTesting = () async => logout();

        await expectLater(
          repository.completeExerciseSet(7),
          throwsA(isA<SessionStaleException>()),
        );
        final row = await isar.localExerciseSets.get(3);
        expect(row!.isCompleted, isFalse);
        expect(row.isSynced, isTrue);
      },
    );

    test('getExerciseSets refresh, logout in the pre-transaction gap: throws '
        'SessionStaleException, writeTxn body never entered', () async {
      loginAs(userA);
      await ownedExercise();
      adapter.responder =
          (_) async => jsonBody([setJson(id: 72, exerciseId: 200)]);
      var insideTxn = 0;
      repository.insideWriteTxnForTesting = () async => insideTxn++;
      repository.beforeWriteTxnForTesting = () async => logout();

      await expectLater(
        repository.getExerciseSets(200),
        throwsA(isA<SessionStaleException>()),
      );
      expect(insideTxn, 0);
      expect(await isar.localExerciseSets.count(), 0);
    });

    test('getExerciseSets refresh, logout as the FIRST transaction action: '
        'throws SessionStaleException and writes nothing', () async {
      loginAs(userA);
      await ownedExercise();
      adapter.responder =
          (_) async => jsonBody([
            setJson(id: 72, exerciseId: 200),
            setJson(id: 73, exerciseId: 200),
          ]);
      repository.insideWriteTxnForTesting = () async => logout();

      await expectLater(
        repository.getExerciseSets(200),
        throwsA(isA<SessionStaleException>()),
      );
      expect(await isar.localExerciseSets.count(), 0);
    });

    test('every user-owned op: LogSetsProvider drops the typed stale exception '
        'without publishing error or data; user B still succeeds', () async {
      final provider = LogSetsProvider(repository, sessionEpoch);
      addTearDown(provider.dispose);

      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
        setNumber: 1,
      );
      await provider.loadSets(200);
      expect(provider.sets.map((s) => s.id), [7]);

      final gate = Completer<ResponseBody>();
      adapter.responder = (_) async => gate.future;
      final completion = provider.completeSet(
        ExerciseSet(id: 7, exerciseId: 200, setNumber: 1),
      );
      await adapter.nextDispatch();
      logout();
      provider.clear();
      loginAs(userB);
      gate.complete(ResponseBody.fromString('', 204));
      await completion;

      expect(provider.errorMessage, isNull);
      expect(provider.sets, isEmpty);

      // B's own operation still works.
      final bSession = await insertSession(uid: userB, serverId: 600);
      final bEx = await insertExercise(
        sessionLocalId: bSession.localId,
        serverId: 300,
        sessionServerId: 600,
      );
      await insertSet(
        exerciseLocalId: bEx.localId,
        serverId: 8,
        exerciseServerId: 300,
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);
      await provider.loadSets(300);
      final ok = await provider.deleteSet(
        ExerciseSet(id: 8, exerciseId: 300, setNumber: 1),
      );
      expect(ok, isTrue);
    });

    test(
      'LogSetsProvider.loadSets for an exercise deleted under the open '
      'screen surfaces a "not found" error (fail-closed, not an empty list)',
      () async {
        final provider = LogSetsProvider(repository, sessionEpoch);
        addTearDown(provider.dispose);

        loginAs(userA);
        final ex = await ownedExercise(exerciseServerId: 200);
        adapter.responder = (_) async => jsonBody(<dynamic>[]);
        await provider.loadSets(200);
        expect(provider.errorMessage, isNull);

        await isar.writeTxn(() => isar.localExercises.delete(ex.localId));
        await provider.loadSets(200);

        expect(provider.errorMessage, contains('not found'));
        expect(provider.sets, isEmpty);
      },
    );
  });

  // ==================================================================
  // Same-session ownership loss fails closed (Blocker 3)
  // ==================================================================

  group('same-session ownership loss never returns publishable success', () {
    test(
      'create: parent deleted after POST dispatch but before response - no '
      'local row, no ExerciseSet returned, provider does not append',
      () async {
        final provider = LogSetsProvider(repository, sessionEpoch);
        addTearDown(provider.dispose);
        loginAs(userA);
        final ex = await ownedExercise(exerciseServerId: 200);
        await provider.loadSets(200);

        final gate = Completer<ResponseBody>();
        adapter.responder = (_) async => gate.future;
        final add = provider.addSet(exerciseId: 200, reps: 10, weight: 30);
        await adapter.nextDispatch();
        await isar.writeTxn(() => isar.localExercises.delete(ex.localId));
        gate.complete(jsonBody(setJson(id: 901, exerciseId: 200)));

        expect(await add, isFalse);
        expect(provider.sets, isEmpty);
        expect(await isar.localExerciseSets.count(), 0);
      },
    );

    test('create (direct): parent deleted after POST - repository throws '
        'not-found, no local write', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      final gate = Completer<ResponseBody>();
      adapter.responder = (_) async => gate.future;

      final future = repository.createExerciseSet(
        ExerciseSet(id: 0, exerciseId: 200, setNumber: 1, reps: 10, weight: 30),
      );
      await adapter.nextDispatch();
      await isar.writeTxn(() => isar.localExercises.delete(ex.localId));
      gate.complete(jsonBody(setJson(id: 902, exerciseId: 200)));

      Object? error;
      try {
        await future;
      } catch (e) {
        error = e;
      }
      expect(error, isA<Exception>());
      expect(error, isNot(isA<SessionStaleException>()));
      expect(await isar.localExerciseSets.count(), 0);
    });

    test('create: parent reassigned to B inside the ack writeTxn - no local '
        'write, no publishable success', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 500);
      final ex = await insertExercise(
        sessionLocalId: session.localId,
        serverId: 200,
        sessionServerId: 500,
      );
      adapter.responder =
          (_) async => jsonBody(setJson(id: 903, exerciseId: 200));
      repository.insideWriteTxnForTesting = () async {
        final s = await isar.localSessions.get(session.localId);
        s!.userId = userB;
        await isar.localSessions.put(s);
      };

      await expectLater(
        repository.createExerciseSet(
          ExerciseSet(
            id: 0,
            exerciseId: 200,
            setNumber: 1,
            reps: 10,
            weight: 30,
          ),
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        await isar.localExerciseSets
            .filter()
            .exerciseLocalIdEqualTo(ex.localId)
            .count(),
        0,
      );
    });

    test('complete: target set deleted before acknowledgment - throws '
        'not-found, no resurrection, no completed object', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
      );
      final gate = Completer<ResponseBody>();
      adapter.responder = (_) async => gate.future;

      final future = repository.completeExerciseSet(7);
      await adapter.nextDispatch();
      await isar.writeTxn(() => isar.localExerciseSets.delete(3));
      gate.complete(ResponseBody.fromString('', 204));

      await expectLater(future, throwsA(isA<Exception>()));
      expect(await isar.localExerciseSets.get(3), isNull);
      expect(await isar.localExerciseSets.count(), 0);
    });

    test('complete: parent ownership changes inside the ack writeTxn - no '
        'local update, throws not-found', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 500);
      final ex = await insertExercise(
        sessionLocalId: session.localId,
        serverId: 200,
        sessionServerId: 500,
      );
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
        synced: true,
        syncStatus: 'synced',
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);
      repository.insideWriteTxnForTesting = () async {
        final s = await isar.localSessions.get(session.localId);
        s!.userId = userB;
        await isar.localSessions.put(s);
      };

      await expectLater(
        repository.completeExerciseSet(7),
        throwsA(isA<Exception>()),
      );
      expect((await isar.localExerciseSets.get(3))!.isCompleted, isFalse);
    });

    test('getExerciseSets refresh: parent deleted/reassigned mid-refresh - '
        'throws not-found, no orphan sets written', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 500);
      final ex = await insertExercise(
        sessionLocalId: session.localId,
        serverId: 200,
        sessionServerId: 500,
      );
      adapter.responder =
          (_) async => jsonBody([setJson(id: 61, exerciseId: 200)]);
      repository.insideWriteTxnForTesting = () async {
        final s = await isar.localSessions.get(session.localId);
        s!.userId = userB;
        await isar.localSessions.put(s);
      };

      await expectLater(
        repository.getExerciseSets(200),
        throwsA(isA<Exception>()),
      );
      expect(
        await isar.localExerciseSets
            .filter()
            .exerciseLocalIdEqualTo(ex.localId)
            .count(),
        0,
      );
    });

    test(
      'getExerciseSets refresh: parent deleted in the pre-transaction gap - '
      'the writeTxn re-fetch blocks the orphan write, throws not-found',
      () async {
        loginAs(userA);
        final ex = await ownedExercise();
        adapter.responder =
            (_) async => jsonBody([setJson(id: 71, exerciseId: 200)]);
        repository.beforeWriteTxnForTesting =
            () async =>
                isar.writeTxn(() => isar.localExercises.delete(ex.localId));

        await expectLater(
          repository.getExerciseSets(200),
          throwsA(isA<Exception>()),
        );
        expect(await isar.localExerciseSets.count(), 0);
      },
    );

    test('delete convergence: target already gone after a successful server '
        'DELETE - returns true, no other row affected', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
        setNumber: 1,
      );
      final sibling = await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 9,
        exerciseServerId: 200,
        explicitLocalId: 5,
        setNumber: 2,
      );
      final gate = Completer<ResponseBody>();
      adapter.responder = (_) async => gate.future;

      final future = repository.deleteExerciseSet(7);
      await adapter.nextDispatch();
      await isar.writeTxn(() => isar.localExerciseSets.delete(3));
      gate.complete(ResponseBody.fromString('', 204));

      expect(await future, isTrue); // convergence
      expect(await isar.localExerciseSets.get(sibling.localId), isNotNull);
    });

    test(
      'delete (pending-delete path): parent reassigned to B inside the '
      'writeTxn after an ordinary DELETE failure - NOT marked, fails closed',
      () async {
        loginAs(userA);
        final session = await insertSession(uid: userA, serverId: 500);
        final ex = await insertExercise(
          sessionLocalId: session.localId,
          serverId: 200,
          sessionServerId: 500,
        );
        await insertSet(
          exerciseLocalId: ex.localId,
          serverId: 7,
          exerciseServerId: 200,
          explicitLocalId: 3,
        );
        // Ordinary DELETE failure -> the pending-delete (_markPendingDelete) path.
        adapter.responder = (_) async => ResponseBody.fromString('err', 500);
        repository.insideWriteTxnForTesting = () async {
          final s = await isar.localSessions.get(session.localId);
          s!.userId = userB;
          await isar.localSessions.put(s);
        };

        await expectLater(
          repository.deleteExerciseSet(7),
          throwsA(isA<Exception>()),
        );
        final row = await isar.localExerciseSets.get(3);
        expect(row!.syncStatus, isNot('pending_delete'));
      },
    );

    test('delete: parent reassigned to B inside the ack writeTxn - the row is '
        'NOT deleted, fails closed', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 500);
      final ex = await insertExercise(
        sessionLocalId: session.localId,
        serverId: 200,
        sessionServerId: 500,
      );
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);
      repository.insideWriteTxnForTesting = () async {
        final s = await isar.localSessions.get(session.localId);
        s!.userId = userB;
        await isar.localSessions.put(s);
      };

      await expectLater(
        repository.deleteExerciseSet(7),
        throwsA(isA<Exception>()),
      );
      expect(await isar.localExerciseSets.get(3), isNotNull);
    });

    test('staleness takes precedence over same-session not-found', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
      );
      final gate = Completer<ResponseBody>();
      adapter.responder = (_) async => gate.future;

      final future = repository.completeExerciseSet(7);
      await adapter.nextDispatch();
      // Both: the row is deleted AND the session ends.
      await isar.writeTxn(() => isar.localExerciseSets.delete(3));
      logout();
      gate.complete(ResponseBody.fromString('', 204));

      await expectLater(future, throwsA(isA<SessionStaleException>()));
    });
  });

  // ==================================================================
  // Owner resolution / fail-safe
  // ==================================================================

  group('owner-verified resolution', () {
    test('same-user complete collision by SERVER ids: completeExerciseSet(7) '
        'updates serverId==7, never localId==7', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
        setNumber: 1,
      );
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 12,
        exerciseServerId: 200,
        explicitLocalId: 7,
        setNumber: 2,
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      await repository.completeExerciseSet(7);
      expect(onlyRequest().path, endsWith('exercisesets/7/complete'));
      expect((await isar.localExerciseSets.get(3))!.isCompleted, isTrue);
      expect((await isar.localExerciseSets.get(7))!.isCompleted, isFalse);
    });

    test('orphan set (no parent exercise) is unowned', () async {
      loginAs(userA);
      await insertSet(
        exerciseLocalId: 9999,
        serverId: 7,
        exerciseServerId: 200,
      );
      await expectLater(
        repository.completeExerciseSet(7),
        throwsA(isA<Exception>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'set whose exercise parent belongs to another user is unowned',
      () async {
        final bSession = await insertSession(uid: userB, serverId: 600);
        final bEx = await insertExercise(
          sessionLocalId: bSession.localId,
          serverId: 300,
          sessionServerId: 600,
        );
        await insertSet(
          exerciseLocalId: bEx.localId,
          serverId: 7,
          exerciseServerId: 300,
        );
        loginAs(userA);
        await expectLater(
          repository.deleteExerciseSet(7),
          throwsA(isA<Exception>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('duplicate owned rows sharing a server id fail closed - no HTTP, '
        'nothing mutated', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
      );
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 4,
      );
      await expectLater(
        repository.completeExerciseSet(7),
        throwsA(isA<Exception>()),
      );
      expect(adapter.capturedRequests, isEmpty);
      expect((await isar.localExerciseSets.get(3))!.isCompleted, isFalse);
      expect((await isar.localExerciseSets.get(4))!.isCompleted, isFalse);
    });

    test(
      'B using A\'s server id resolves nothing and dispatches no HTTP',
      () async {
        final aSession = await insertSession(uid: userA, serverId: 500);
        final aEx = await insertExercise(
          sessionLocalId: aSession.localId,
          serverId: 200,
          sessionServerId: 500,
        );
        await insertSet(
          exerciseLocalId: aEx.localId,
          serverId: 7,
          exerciseServerId: 200,
        );
        loginAs(userB);
        await expectLater(
          repository.completeExerciseSet(7),
          throwsA(isA<Exception>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );
  });

  // ==================================================================
  // Endpoint identity / offline paths
  // ==================================================================

  group('post-resolution endpoint identity', () {
    test('server-backed complete/delete send the resolved serverId; local-only '
        'send no HTTP', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 77,
        exerciseServerId: 200,
        explicitLocalId: 4,
        setNumber: 1,
      );
      final localOnly = await insertSet(
        exerciseLocalId: ex.localId,
        serverId: null,
        explicitLocalId: 8,
        synced: false,
        syncStatus: 'pending_create',
        setNumber: 2,
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      await repository.completeExerciseSet(77);
      expect(onlyRequest().path, endsWith('exercisesets/77/complete'));

      adapter.capturedRequests.clear();
      await repository.deleteExerciseSet(77);
      expect(onlyRequest().path, endsWith('exercisesets/77'));

      adapter.capturedRequests.clear();
      await repository.completeExerciseSet(offline(localOnly.localId));
      expect(adapter.capturedRequests, isEmpty);
      final ok = await repository.deleteExerciseSet(offline(localOnly.localId));
      expect(ok, isTrue);
      expect(adapter.capturedRequests, isEmpty);
    });

    test('online create normalizes the request body exerciseId to the resolved '
        'parent serverId (never a negative / local id)', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 500);
      final ex = await insertExercise(
        sessionLocalId: session.localId,
        serverId: 200,
        sessionServerId: 500,
        explicitLocalId: 5,
      );
      adapter.responder =
          (_) async => jsonBody(setJson(id: 900, exerciseId: 200));

      // Positive public id 200 (the parent's server id).
      await repository.createExerciseSet(
        ExerciseSet(id: 0, exerciseId: 200, setNumber: 1, reps: 10, weight: 50),
      );
      final body = onlyRequest().data as Map<String, dynamic>;
      expect(body['exerciseId'], 200);
      expect(body['exerciseId'], isPositive);
      expect(ex.serverId, 200);
    });

    test('updateExerciseSet: resolved serverId endpoint + normalized body ids, '
        '204 treated as success', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 42,
        exerciseServerId: 200,
        explicitLocalId: 4,
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      // Public id 42 (server id); a stale body id 999.
      final result = await repository.updateExerciseSet(
        42,
        ExerciseSet(
          id: 999,
          exerciseId: 200,
          setNumber: 1,
          reps: 12,
          weight: 80,
        ),
      );

      final sent = onlyRequest();
      expect(sent.path, endsWith('exercisesets/42'));
      expect(sent.headers['Authorization'], 'Bearer jwt-$userA');
      expect(sent.extra[ApiService.sessionEpochExtraKey], isNotNull);
      final body = sent.data as Map<String, dynamic>;
      expect(body['id'], 42);
      expect(body['exerciseId'], 200);
      expect(result.id, 42);
      expect(result.reps, 12);
    });

    test(
      'updateExerciseSet: a negative offline id is rejected (a not-yet-synced '
      'set is not updatable), no HTTP',
      () async {
        loginAs(userA);
        final ex = await ownedExercise(exerciseServerId: 200);
        final s = await insertSet(
          exerciseLocalId: ex.localId,
          serverId: null,
          synced: false,
          syncStatus: 'pending_create',
        );
        await expectLater(
          repository.updateExerciseSet(
            offline(s.localId),
            ExerciseSet(id: 0, exerciseId: 200, setNumber: 1),
          ),
          throwsA(isA<Exception>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('updateExerciseSet: stale-before-dispatch -> SessionStaleException, '
        'no HTTP', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 42,
        exerciseServerId: 200,
      );
      apiService.beforeDispatchEpochCheckForTesting = () async => logout();
      await expectLater(
        repository.updateExerciseSet(
          42,
          ExerciseSet(id: 42, exerciseId: 200, setNumber: 1),
        ),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });
  });

  // ==================================================================
  // Regression / non-destructive refresh / PATCH 204 / reference data
  // ==================================================================

  group('regression', () {
    test('offline create writes pending_create; ordinary server failure while '
        'current also falls back to a pending row', () async {
      loginAs(userA);
      await ownedExercise(exerciseServerId: 200);

      when(mockConnectivity.isOnline).thenReturn(false);
      final offlineRes = await repository.createExerciseSet(
        ExerciseSet(id: 0, exerciseId: 200, setNumber: 2, reps: 8, weight: 60),
      );
      expect(adapter.capturedRequests, isEmpty);
      expect(
        (await isar.localExerciseSets.get(-offlineRes.id))!.syncStatus,
        'pending_create',
      );

      when(mockConnectivity.isOnline).thenReturn(true);
      adapter.responder = (_) async => ResponseBody.fromString('boom', 500);
      final failRes = await repository.createExerciseSet(
        ExerciseSet(id: 0, exerciseId: 200, setNumber: 3, reps: 3, weight: 90),
      );
      expect(
        (await isar.localExerciseSets.get(-failRes.id))!.syncStatus,
        'pending_create',
      );
    });

    test('offline complete of a synced set -> pending_update; offline delete '
        '-> pending_delete and hidden from getExerciseSets', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
        synced: true,
        syncStatus: 'synced',
        setNumber: 1,
      );
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 9,
        exerciseServerId: 200,
        explicitLocalId: 5,
        setNumber: 2,
      );
      when(mockConnectivity.isOnline).thenReturn(false);

      await repository.completeExerciseSet(7);
      final row = await isar.localExerciseSets.get(3);
      expect(row!.isCompleted, isTrue);
      expect(row.syncStatus, 'pending_update');

      final ok = await repository.deleteExerciseSet(9);
      expect(ok, isTrue);
      expect(
        (await isar.localExerciseSets.get(5))!.syncStatus,
        'pending_delete',
      );

      final visible = await repository.getExerciseSets(200);
      expect(visible.map((s) => s.id), [7]);
      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'getExerciseSets returns owned local sets sorted by setNumber, '
      'excluding pending_delete; unresolvable exercise fails closed',
      () async {
        loginAs(userA);
        final session = await insertSession(uid: userA, serverId: 500);
        final ex = await insertExercise(
          sessionLocalId: session.localId,
          serverId: null, // local-only -> no server refresh
        );
        await insertSet(
          exerciseLocalId: ex.localId,
          serverId: null,
          synced: false,
          setNumber: 3,
        );
        await insertSet(
          exerciseLocalId: ex.localId,
          serverId: null,
          synced: false,
          setNumber: 1,
        );
        await insertSet(
          exerciseLocalId: ex.localId,
          serverId: null,
          synced: false,
          setNumber: 2,
          syncStatus: 'pending_delete',
        );

        final sets = await repository.getExerciseSets(offline(ex.localId));
        expect(sets.map((s) => s.setNumber), [1, 3]);
        expect(adapter.capturedRequests, isEmpty);

        // A genuinely unresolvable exercise fails closed.
        await expectLater(
          repository.getExerciseSets(999999),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'getExerciseSets refresh is non-destructive: updates synced rows, '
      'preserves rows with an unsynced local mutation, inserts missing',
      () async {
        loginAs(userA);
        final ex = await ownedExercise(exerciseServerId: 200);
        await insertSet(
          exerciseLocalId: ex.localId,
          serverId: 8,
          exerciseServerId: 200,
          explicitLocalId: 4,
          isCompleted: false,
          synced: true,
          syncStatus: 'synced',
        );
        await insertSet(
          exerciseLocalId: ex.localId,
          serverId: 7,
          exerciseServerId: 200,
          explicitLocalId: 3,
          isCompleted: true,
          synced: false,
          syncStatus: 'pending_update',
        );
        adapter.responder =
            (_) async => jsonBody([
              setJson(id: 8, exerciseId: 200, isCompleted: true),
              setJson(id: 7, exerciseId: 200, isCompleted: false),
              setJson(id: 55, exerciseId: 200),
            ]);

        final result = await repository.getExerciseSets(200);

        expect((await isar.localExerciseSets.get(4))!.isCompleted, isTrue);
        final pending = await isar.localExerciseSets.get(3);
        expect(pending!.isCompleted, isTrue);
        expect(pending.syncStatus, 'pending_update');
        expect(result.map((s) => s.id), containsAll([8, 7, 55]));
      },
    );

    test('PATCH 204/null is treated as successful completion; exact resolved '
        'row completed + marked synced; no exception', () async {
      loginAs(userA);
      final ex = await ownedExercise(exerciseServerId: 200);
      await insertSet(
        exerciseLocalId: ex.localId,
        serverId: 7,
        exerciseServerId: 200,
        explicitLocalId: 3,
        isCompleted: false,
        synced: true,
        syncStatus: 'synced',
      );
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      final result = await repository.completeExerciseSet(7);
      expect(result.isCompleted, isTrue);
      final row = await isar.localExerciseSets.get(3);
      expect(row!.isCompleted, isTrue);
      expect(row.isSynced, isTrue);
      expect(row.syncStatus, 'synced');
      expect(row.completedAt, isNotNull);
    });

    test('reference-data getExerciseTemplates is unchanged: unbound, still '
        'caches', () async {
      adapter.responder =
          (_) async => jsonBody([
            {'id': 1, 'name': 'Squat', 'category': 'Legs', 'isCustom': false},
          ]);

      final templates = await repository.getExerciseTemplates();
      expect(templates, hasLength(1));
      final sent = onlyRequest();
      expect(sent.extra[ApiService.sessionEpochExtraKey], isNull);
      expect(sent.headers.containsKey('Authorization'), isFalse);
      expect(await isar.localExerciseTemplates.count(), 1);
    });
  });

  // ==================================================================
  // Mutation-campaign coverage: exercise resolution + refresh isolation
  // (production already correct - these pin behaviours the prior suite
  //  did not individually exercise).
  // ==================================================================

  group('exercise resolution & refresh isolation', () {
    test(
      'getExerciseSets: a cancelled refresh GET propagates '
      'RequestCancelledException, never returns the stale local view',
      () async {
        loginAs(userA);
        final ex = await ownedExercise(exerciseServerId: 200);
        await insertSet(
          exerciseLocalId: ex.localId,
          serverId: 7,
          exerciseServerId: 200,
        );
        adapter.neverCompletes = true;

        final future = repository.getExerciseSets(200);
        await adapter.nextDispatch();
        sessionCoordinator.cancelCurrentGeneration();

        await expectLater(future, throwsA(isA<RequestCancelledException>()));
      },
    );

    test(
      'getExerciseSets: a positive id that matches ONLY an exercise local '
      'id (no server id) is not-found - no positive-local fallback',
      () async {
        loginAs(userA);
        final session = await insertSession(uid: userA, serverId: 500);
        // Exercise with localId 30, NO server id.
        await insertExercise(
          sessionLocalId: session.localId,
          serverId: null,
          sessionServerId: 500,
          explicitLocalId: 30,
        );
        when(mockConnectivity.isOnline).thenReturn(false);

        await expectLater(
          repository.getExerciseSets(30), // positive -> server id only
          throwsA(isA<Exception>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('getExerciseSets: a positive id owned by another user resolves '
        'nothing - not-found, no HTTP', () async {
      final bSession = await insertSession(uid: userB, serverId: 600);
      await insertExercise(
        sessionLocalId: bSession.localId,
        serverId: 321,
        sessionServerId: 600,
      );
      loginAs(userA);

      await expectLater(
        repository.getExerciseSets(321),
        throwsA(isA<Exception>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });

    test('getExerciseSets: a negative offline id belonging to another user '
        'resolves nothing - not-found, no HTTP', () async {
      final bSession = await insertSession(uid: userB, serverId: 600);
      await insertExercise(
        sessionLocalId: bSession.localId,
        serverId: null,
        sessionServerId: 600,
        explicitLocalId: 44,
      );
      loginAs(userA);

      await expectLater(
        repository.getExerciseSets(offline(44)),
        throwsA(isA<Exception>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });

    test('getExerciseSets(A) returns ONLY exercise A\'s sets even when a '
        'sibling exercise B (same user) also has sets', () async {
      loginAs(userA);
      final session = await insertSession(uid: userA, serverId: 500);
      final exA = await insertExercise(
        sessionLocalId: session.localId,
        serverId: 200,
        sessionServerId: 500,
        explicitLocalId: 10,
      );
      final exB = await insertExercise(
        sessionLocalId: session.localId,
        serverId: 300,
        sessionServerId: 500,
        explicitLocalId: 11,
      );
      await insertSet(
        exerciseLocalId: exA.localId,
        serverId: 1001,
        exerciseServerId: 200,
        setNumber: 1,
      );
      await insertSet(
        exerciseLocalId: exB.localId,
        serverId: 2002,
        exerciseServerId: 300,
        setNumber: 1,
      );
      when(mockConnectivity.isOnline).thenReturn(false);

      final aSets = await repository.getExerciseSets(200);
      expect(aSets.map((s) => s.id), [1001]);
      final bSets = await repository.getExerciseSets(300);
      expect(bSets.map((s) => s.id), [2002]);
    });

    test(
      'online createExerciseSet normalizes a STALE / negative DTO '
      'exerciseId in the POST body to the resolved parent server id',
      () async {
        loginAs(userA);
        final session = await insertSession(uid: userA, serverId: 500);
        await insertExercise(
          sessionLocalId: session.localId,
          serverId: 200,
          sessionServerId: 500,
          explicitLocalId: 5,
        );
        adapter.responder =
            (_) async => jsonBody(setJson(id: 900, exerciseId: 200));

        // Caller passes the negative offline public id for the SAME parent.
        await repository.createExerciseSet(
          ExerciseSet(
            id: 0,
            exerciseId: offline(5),
            setNumber: 1,
            reps: 10,
            weight: 50,
          ),
        );

        final body = onlyRequest().data as Map<String, dynamic>;
        expect(body['exerciseId'], 200);
        expect(body['exerciseId'], isPositive);
      },
    );
  });

  // ==================================================================
  // fix/sync-create-set-revision-guard - connectivity-independent tombstone
  // ==================================================================
  //
  // `_connectivity.isOnline` at delete time does NOT prove whether
  // SyncService already dispatched a CREATE POST for a not-yet-synced set
  // (the network can drop AFTER dispatch). So deleting an owned set with no
  // positive server id must leave a serverId-less `pending_delete` tombstone
  // whenever the row is unsynced (or already a tombstone) - regardless of
  // connectivity - so an in-flight `_syncCreateSet` acknowledgment can still
  // find the row and attach the returned id. Only a contradictory
  // `isSynced == true` no-id row (never in the `isSyncedEqualTo(false)` sync
  // queue) is removed immediately. `SyncService._syncDeleteSet` reaps the
  // tombstone later: no HTTP while it has no positive id, DELETE + removal
  // once a CREATE ack attached one.
  group(
    'deleteExerciseSet - connectivity-independent no-server-id tombstone',
    () {
      Future<LocalExerciseSet> seedNoId({
        required int exerciseLocalId,
        required String syncStatus,
        int? serverId,
        bool synced = false,
        DateTime? lastModifiedLocal,
      }) async {
        final s = await insertSet(
          exerciseLocalId: exerciseLocalId,
          serverId: serverId,
          explicitLocalId: 7,
          synced: synced,
          syncStatus: syncStatus,
        );
        if (lastModifiedLocal != null) {
          await isar.writeTxn(() async {
            final row = await isar.localExerciseSets.get(s.localId);
            row!.lastModifiedLocal = lastModifiedLocal;
            await isar.localExerciseSets.put(row);
          });
        }
        return s;
      }

      void expectNoHttp() => expect(adapter.capturedRequests, isEmpty);

      for (final online in [true, false]) {
        test(
          'pending_create + serverId null, isOnline=$online -> serverId-less '
          'pending_delete tombstone, no HTTP',
          () async {
            loginAs(userA);
            when(mockConnectivity.isOnline).thenReturn(online);
            final ex = await ownedExercise(exerciseServerId: 200);
            final before = DateTime.utc(2020, 1, 1);
            await seedNoId(
              exerciseLocalId: ex.localId,
              syncStatus: 'pending_create',
              lastModifiedLocal: before,
            );

            final ok = await repository.deleteExerciseSet(offline(7));

            expect(ok, isTrue);
            expectNoHttp();
            final row = await isar.localExerciseSets.get(7);
            expect(row, isNotNull);
            expect(row!.syncStatus, 'pending_delete');
            expect(row.serverId, isNull);
            expect(row.isSynced, isFalse);
            expect(row.lastModifiedLocal.isAfter(before), isTrue);
          },
        );
      }

      test(
        'pending_create + serverId 0 -> tombstone, id canonicalized to null, '
        'never /exercisesets/0',
        () async {
          loginAs(userA);
          final ex = await ownedExercise(exerciseServerId: 200);
          await seedNoId(
            exerciseLocalId: ex.localId,
            syncStatus: 'pending_create',
            serverId: 0,
          );

          final ok = await repository.deleteExerciseSet(offline(7));

          expect(ok, isTrue);
          expect(
            adapter.capturedRequests.where(
              (r) => r.path.contains('exercisesets/0'),
            ),
            isEmpty,
          );
          expectNoHttp();
          final row = await isar.localExerciseSets.get(7);
          expect(row!.syncStatus, 'pending_delete');
          expect(row.serverId, isNull);
        },
      );

      test(
        'legacy pending_update + serverId 0 (routed to CREATE by _syncUpdateSet) '
        '-> tombstone, no /0',
        () async {
          loginAs(userA);
          when(mockConnectivity.isOnline).thenReturn(false);
          final ex = await ownedExercise(exerciseServerId: 200);
          await seedNoId(
            exerciseLocalId: ex.localId,
            syncStatus: 'pending_update',
            serverId: 0,
          );

          final ok = await repository.deleteExerciseSet(offline(7));

          expect(ok, isTrue);
          expectNoHttp();
          final row = await isar.localExerciseSets.get(7);
          expect(row!.syncStatus, 'pending_delete');
          expect(row.serverId, isNull);
          expect(row.isSynced, isFalse);
        },
      );

      test('isSynced == false with an unexpected status -> tombstone (fail '
          'closed)', () async {
        loginAs(userA);
        final ex = await ownedExercise(exerciseServerId: 200);
        await seedNoId(exerciseLocalId: ex.localId, syncStatus: 'weird_state');

        final ok = await repository.deleteExerciseSet(offline(7));

        expect(ok, isTrue);
        expectNoHttp();
        final row = await isar.localExerciseSets.get(7);
        expect(row, isNotNull);
        expect(row!.syncStatus, 'pending_delete');
        expect(row.serverId, isNull);
      });

      test('contradictory isSynced == true + serverId 0 + status synced -> '
          'immediate local delete (not in the sync queue, no CREATE possible), '
          'no /0', () async {
        loginAs(userA);
        final ex = await ownedExercise(exerciseServerId: 200);
        await insertSet(
          exerciseLocalId: ex.localId,
          serverId: 0,
          explicitLocalId: 7,
          synced: true,
          syncStatus: 'synced',
        );

        final ok = await repository.deleteExerciseSet(offline(7));

        expect(ok, isTrue);
        expect(await isar.localExerciseSets.get(7), isNull);
        expect(
          adapter.capturedRequests.where(
            (r) => r.path.contains('exercisesets/0'),
          ),
          isEmpty,
        );
        expectNoHttp();
      });

      test('repeated delete of a serverId-less pending_delete tombstone is a '
          'no-op: the row is never removed, its revision never churns, no HTTP '
          '(so an in-flight CREATE ack can never find null)', () async {
        loginAs(userA);
        final ex = await ownedExercise(exerciseServerId: 200);
        final r0 = DateTime.utc(2021, 1, 1);
        await seedNoId(
          exerciseLocalId: ex.localId,
          syncStatus: 'pending_create',
          lastModifiedLocal: r0,
        );

        final ok1 = await repository.deleteExerciseSet(offline(7));
        final afterFirst = await isar.localExerciseSets.get(7);
        expect(ok1, isTrue);
        expect(afterFirst!.syncStatus, 'pending_delete');
        final tombstoneRev = afterFirst.lastModifiedLocal;

        when(mockConnectivity.isOnline).thenReturn(false);
        final ok2 = await repository.deleteExerciseSet(offline(7));
        final ok3 = await repository.deleteExerciseSet(offline(7));

        expect(ok2, isTrue);
        expect(ok3, isTrue);
        final afterRepeats = await isar.localExerciseSets.get(7);
        expect(
          afterRepeats,
          isNotNull,
          reason: 'CREATE ack must still find it',
        );
        expect(afterRepeats!.syncStatus, 'pending_delete');
        expect(afterRepeats.serverId, isNull);
        expect(
          afterRepeats.lastModifiedLocal,
          tombstoneRev,
          reason: 'no revision churn on repeat delete',
        );
        expectNoHttp();
      });
    },
  );
}

/// Fake Dio transport. [nextDispatch] fires the instant a request reaches
/// [fetch]; [responder] produces (or holds) the response; [neverCompletes]
/// makes a request hang so a test can cancel a genuinely in-flight call.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];
  Future<ResponseBody> Function(RequestOptions options)? responder;
  bool neverCompletes = false;
  Completer<void>? _dispatchSignal;

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
    if (neverCompletes) return Completer<ResponseBody>().future;
    final respond = responder;
    if (respond != null) return respond(options);
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
