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
import 'package:go_hard_app/data/models/workout_stats.dart';
import 'package:go_hard_app/data/repositories/analytics_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

import 'analytics_repository_session_ownership_test.mocks.dart';

@GenerateMocks([AuthService, ConnectivityService])
/// Proves [AnalyticsRepository] is fully session-bound:
///
/// - every one of the six authenticated GET calls carries the entry
///   [SessionRequestContext] (pinned JWT + generation CancelToken + epoch
///   metadata), proven against the real Dio interceptor via a fake
///   [HttpClientAdapter];
/// - a `null` capture, a repository-detected post-await staleness, and
///   [ApiService]'s own [SessionStaleException] / [RequestCancelledException]
///   are always typed and never converted to `[]` / a zero [WorkoutStats] /
///   silent success, and never routed into the local fallback;
/// - the three local fallbacks compute strictly for the captured user
///   through `LocalSession.userId -> LocalExercise.sessionLocalId ->
///   LocalExerciseSet.exerciseLocalId`, excluding foreign and orphan rows,
///   and are discarded if the session changes before they can be returned;
/// - the live `AuthService` user id is irrelevant after entry (the
///   repository no longer depends on it at all).
///
/// No wall-clock waits: held responses use [Completer]; a mid-calculation
/// logout uses [AnalyticsRepository.afterLocalReadForTesting].
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
  late AnalyticsRepository repository;
  late int unauthorizedCalls;

  const userA = 1;
  const userB = 2;

  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('analytics_repo_owner_');
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

    repository = AnalyticsRepository(
      apiService,
      localDb,
      mockConnectivity,
      sessionEpoch,
      sessionCoordinator,
    );
  });

  tearDown(() async {
    repository.afterLocalReadForTesting = null;
    repository.beforeReturnForTesting = null;
    apiService.beforeDispatchEpochCheckForTesting = null;
    if (isar.isOpen) await isar.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
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
    String status = 'completed',
    DateTime? date,
    int? duration,
  }) async {
    final now = DateTime.now();
    final session = LocalSession(
      serverId: serverId,
      userId: uid,
      date: date ?? DateTime(2026, 1, 1),
      status: status,
      duration: duration,
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
    int? exerciseTemplateId,
    String name = 'Bench Press',
  }) async {
    final now = DateTime.now();
    final exercise = LocalExercise(
      serverId: serverId,
      sessionLocalId: sessionLocalId,
      name: name,
      exerciseTemplateId: exerciseTemplateId,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localExercises.put(exercise));
    return exercise;
  }

  Future<LocalExerciseSet> insertSet({
    required int exerciseLocalId,
    int reps = 10,
    double weight = 100,
    int setNumber = 1,
  }) async {
    final now = DateTime.now();
    final set = LocalExerciseSet(
      exerciseLocalId: exerciseLocalId,
      setNumber: setNumber,
      reps: reps,
      weight: weight,
      isCompleted: true,
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localExerciseSets.put(set));
    return set;
  }

  /// A completed session -> exercise (with template) -> one set, all owned
  /// by [uid]. [weight]*[reps] is the whole graph's volume.
  Future<void> ownedGraph({
    int uid = userA,
    int templateId = 11,
    int reps = 10,
    double weight = 100,
    DateTime? date,
  }) async {
    final s = await insertSession(uid: uid, date: date);
    final e = await insertExercise(
      sessionLocalId: s.localId,
      exerciseTemplateId: templateId,
    );
    await insertSet(exerciseLocalId: e.localId, reps: reps, weight: weight);
  }

  ResponseBody jsonBody(Object json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  Map<String, dynamic> statsJson() => {
    'totalWorkouts': 3,
    'totalDuration': 3600,
    'averageDuration': 1200,
    'currentStreak': 1,
    'longestStreak': 2,
    'workoutsThisWeek': 1,
    'workoutsThisMonth': 3,
    'totalSets': 9,
    'totalReps': 90,
    'totalVolume': 9000.0,
  };

  RequestOptions onlyRequest() {
    expect(adapter.capturedRequests, hasLength(1));
    return adapter.capturedRequests.single;
  }

  // Every authenticated public method paired with a canned success body.
  final calls = <String, ({Future<Object?> Function() call, Object body})>{
    'getWorkoutStats': (
      call: () => repository.getWorkoutStats(),
      body: statsJson(),
    ),
    'getExerciseProgress': (
      call: () => repository.getExerciseProgress(),
      body: <dynamic>[],
    ),
    'getExerciseProgressOverTime': (
      call: () => repository.getExerciseProgressOverTime(5),
      body: <dynamic>[],
    ),
    'getMuscleGroupVolume': (
      call: () => repository.getMuscleGroupVolume(),
      body: <dynamic>[],
    ),
    'getPersonalRecords': (
      call: () => repository.getPersonalRecords(),
      body: <dynamic>[],
    ),
    'getVolumeOverTime': (
      call: () => repository.getVolumeOverTime(),
      body: <dynamic>[],
    ),
  };

  // ==================================================================
  // Context capture / HTTP binding / typed stale entry
  // ==================================================================

  group('context capture and HTTP binding', () {
    test('logged-out: every authenticated method throws SessionStaleException '
        'with no HTTP and no Isar read', () async {
      // No loginAs() - captureContext() returns null.
      await ownedGraph(uid: userA); // present, must never be read

      for (final entry in calls.entries) {
        await expectLater(
          entry.value.call(),
          throwsA(isA<SessionStaleException>()),
          reason: entry.key,
        );
      }
      expect(adapter.capturedRequests, isEmpty);
      expect(unauthorizedCalls, 0);
    });

    test('every authenticated call carries the entry context: pinned JWT + '
        'epoch metadata + generation CancelToken', () async {
      for (final entry in calls.entries) {
        loginAs(userA);
        adapter.capturedRequests.clear();
        adapter.responder = (_) async => jsonBody(entry.value.body);

        await entry.value.call();

        final sent = onlyRequest();
        expect(
          sent.headers['Authorization'],
          'Bearer jwt-$userA',
          reason: entry.key,
        );
        final epochToken =
            sent.extra[ApiService.sessionEpochExtraKey] as UserSessionToken;
        expect(epochToken.userId, userA, reason: entry.key);
        expect(sent.cancelToken, isNotNull, reason: entry.key);
        logout();
      }
    });

    test('JWT is pinned at operation entry, not at dispatch', () async {
      loginAs(userA);
      adapter.responder = (_) async => jsonBody(statsJson());

      final future = repository.getWorkoutStats();
      // Live token churns after entry - the pinned one must win.
      currentAuthUserId = 999;
      await future;

      expect(onlyRequest().headers['Authorization'], 'Bearer jwt-$userA');
    });

    test('stale before dispatch (wrapper checkpoint) -> SessionStaleException, '
        'zero network requests', () async {
      for (final entry in calls.entries) {
        loginAs(userA);
        adapter.capturedRequests.clear();
        apiService.beforeDispatchEpochCheckForTesting = null;
        // Log out synchronously between captureContext() and Dio: emulate by
        // making the wrapper-level check fail - invalidate right after the
        // call starts but before the interceptor runs is covered below; here
        // we log out before calling so the wrapper's _checkNotStale throws.
        logout();
        loginAs(userA);
        // Force staleness via the interceptor gap seam set to logout.
        apiService.beforeDispatchEpochCheckForTesting = () async => logout();
        await expectLater(
          entry.value.call(),
          throwsA(isA<SessionStaleException>()),
          reason: entry.key,
        );
        expect(adapter.capturedRequests, isEmpty, reason: entry.key);
        apiService.beforeDispatchEpochCheckForTesting = null;
      }
    });

    test('dispatch-gap staleness (interceptor checkpoint) -> '
        'SessionStaleException', () async {
      loginAs(userA);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        loginAs(userB); // A -> B in the gap between wrapper check and dispatch
      };

      await expectLater(
        repository.getWorkoutStats(),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'logout after the response arrives but before it is parsed -> '
      'SessionStaleException, no WorkoutStats returned (post-HTTP recheck)',
      () async {
        loginAs(userA);
        final respondGate = Completer<ResponseBody>();
        adapter.responder = (_) => respondGate.future;

        final future = repository.getWorkoutStats();
        await adapter.nextDispatch();
        respondGate.complete(jsonBody(statsJson()));
        logout(); // lands before the awaiting continuation resumes

        await expectLater(future, throwsA(isA<SessionStaleException>()));
      },
    );

    test('session change while the JWT read is in flight -> '
        'SessionStaleException, no request', () async {
      loginAs(userA);
      final tokenGate = Completer<String?>();
      when(mockAuthService.getToken()).thenAnswer((_) => tokenGate.future);

      final future = repository.getPersonalRecords();
      loginAs(userB);
      tokenGate.complete('jwt-late');

      await expectLater(future, throwsA(isA<SessionStaleException>()));
      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'in-flight cancellation -> RequestCancelledException, no onUnauthorized, '
      'no local fallback',
      () async {
        loginAs(userA);
        await ownedGraph(uid: userA);
        adapter.neverCompletes = true;

        final future = repository.getWorkoutStats();
        await adapter.nextDispatch();
        sessionCoordinator.cancelCurrentGeneration();

        await expectLater(future, throwsA(isA<RequestCancelledException>()));
        expect(unauthorizedCalls, 0);
      },
    );

    test("A's cancelled generation does not cancel B; B captures a fresh "
        'context and succeeds', () async {
      loginAs(userA);
      adapter.neverCompletes = true;
      final aFuture = repository.getExerciseProgress();
      await adapter.nextDispatch();

      logout();
      sessionCoordinator.cancelCurrentGeneration();
      await expectLater(aFuture, throwsA(isA<RequestCancelledException>()));

      loginAs(userB);
      adapter.neverCompletes = false;
      adapter.capturedRequests.clear();
      adapter.responder = (_) async => jsonBody(<dynamic>[]);

      final bResult = await repository.getExerciseProgress();
      expect(bResult, isEmpty);
      expect(onlyRequest().headers['Authorization'], 'Bearer jwt-$userB');
    });
  });

  // ==================================================================
  // Online-only methods: offline behavior
  // ==================================================================

  group('online-only methods offline', () {
    test('logged-in + offline -> empty list, no HTTP, no throw', () async {
      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);

      expect(await repository.getExerciseProgress(), isEmpty);
      expect(await repository.getExerciseProgressOverTime(5), isEmpty);
      expect(await repository.getMuscleGroupVolume(), isEmpty);
      expect(adapter.capturedRequests, isEmpty);
    });

    test('logged-out + offline -> SessionStaleException (null capture wins '
        'over the offline short-circuit)', () async {
      when(mockConnectivity.isOnline).thenReturn(false);
      await expectLater(
        repository.getMuscleGroupVolume(),
        throwsA(isA<SessionStaleException>()),
      );
    });
  });

  // ==================================================================
  // Local ownership (offline fallback + API-failure fallback)
  // ==================================================================

  group('local ownership', () {
    test('offline getWorkoutStats: only A-owned completed sessions/exercises/'
        'sets are aggregated', () async {
      // A: two completed sessions, one set each (vol 1000 + 1500).
      await ownedGraph(uid: userA, reps: 10, weight: 100);
      await ownedGraph(uid: userA, reps: 10, weight: 150);
      // B: a completed graph that must be excluded entirely.
      await ownedGraph(uid: userB, reps: 10, weight: 999);
      // A: an in_progress session (status filter must drop it).
      final open = await insertSession(uid: userA, status: 'in_progress');
      final openEx = await insertExercise(sessionLocalId: open.localId);
      await insertSet(exerciseLocalId: openEx.localId, reps: 10, weight: 500);

      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);

      final stats = await repository.getWorkoutStats();
      expect(stats.totalWorkouts, 2);
      expect(stats.totalSets, 2);
      expect(stats.totalReps, 20);
      expect(stats.totalVolume, 100 * 10 + 150 * 10);
    });

    test('offline getWorkoutStats: foreign child rows (exercise/set hanging '
        "off B's session) and orphans are excluded", () async {
      final aSession = await insertSession(uid: userA);
      // Foreign: exercise parented to a B session.
      final bSession = await insertSession(uid: userB);
      final bEx = await insertExercise(sessionLocalId: bSession.localId);
      await insertSet(exerciseLocalId: bEx.localId, reps: 5, weight: 200);
      // Orphan exercise: sessionLocalId points nowhere.
      final orphanEx = await insertExercise(sessionLocalId: 999999);
      await insertSet(exerciseLocalId: orphanEx.localId, reps: 5, weight: 300);
      // Orphan set: exerciseLocalId points nowhere.
      await insertSet(exerciseLocalId: 888888, reps: 5, weight: 400);
      // A's own real set.
      final aEx = await insertExercise(sessionLocalId: aSession.localId);
      await insertSet(exerciseLocalId: aEx.localId, reps: 10, weight: 100);

      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);

      final stats = await repository.getWorkoutStats();
      expect(stats.totalWorkouts, 1);
      expect(stats.totalSets, 1);
      expect(stats.totalVolume, 1000);
    });

    test(
      'offline getPersonalRecords: computed only within A\'s owned graph',
      () async {
        await ownedGraph(uid: userA, templateId: 11, reps: 1, weight: 120);
        await ownedGraph(uid: userB, templateId: 11, reps: 1, weight: 500);

        loginAs(userA);
        when(mockConnectivity.isOnline).thenReturn(false);

        final prs = await repository.getPersonalRecords();
        expect(prs, hasLength(1));
        expect(prs.single.weight, 120);
        expect(prs.single.exerciseTemplateId, 11);
      },
    );

    test(
      'offline getVolumeOverTime: date range + ownership applied to A only',
      () async {
        final now = DateTime.now();
        await ownedGraph(
          uid: userA,
          reps: 10,
          weight: 100,
          date: now.subtract(const Duration(days: 5)),
        );
        // Outside the 90-day window.
        await ownedGraph(
          uid: userA,
          reps: 10,
          weight: 100,
          date: now.subtract(const Duration(days: 400)),
        );
        // B, inside the window - excluded by ownership.
        await ownedGraph(
          uid: userB,
          reps: 10,
          weight: 100,
          date: now.subtract(const Duration(days: 5)),
        );

        loginAs(userA);
        when(mockConnectivity.isOnline).thenReturn(false);

        final points = await repository.getVolumeOverTime();
        expect(points, hasLength(1));
        expect(points.single.value, 1000);
      },
    );

    test('a live AuthService user-id change after entry cannot change the '
        'operation owner', () async {
      await ownedGraph(uid: userA, reps: 10, weight: 100);
      await ownedGraph(uid: userB, reps: 10, weight: 999);

      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);
      // AuthService now reports B - the repository must ignore it.
      when(mockAuthService.getUserId()).thenAnswer((_) async => userB);

      final stats = await repository.getWorkoutStats();
      expect(stats.totalVolume, 1000);
    });

    test('logout during the local-query await -> SessionStaleException, '
        'no A result returned', () async {
      await ownedGraph(uid: userA);
      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);
      repository.afterLocalReadForTesting = () async => logout();

      await expectLater(
        repository.getWorkoutStats(),
        throwsA(isA<SessionStaleException>()),
      );
    });

    test('a locally computed result cannot return after B login (post-await '
        'recheck before return)', () async {
      await ownedGraph(uid: userA);
      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);
      repository.afterLocalReadForTesting = () async => loginAs(userB);

      await expectLater(
        repository.getPersonalRecords(),
        throwsA(isA<SessionStaleException>()),
      );
    });

    test('logout strictly between the last local read and the return -> '
        'SessionStaleException (terminal pre-return recheck)', () async {
      await ownedGraph(uid: userA);
      when(mockConnectivity.isOnline).thenReturn(false);
      // No mid-calculation disruption; the change lands only at the very end,
      // after every loop recheck has already passed.
      repository.beforeReturnForTesting = () async {
        logout();
        loginAs(userB);
      };

      loginAs(userA);
      await expectLater(
        repository.getWorkoutStats(),
        throwsA(isA<SessionStaleException>()),
      );
      loginAs(userA);
      await expectLater(
        repository.getPersonalRecords(),
        throwsA(isA<SessionStaleException>()),
      );
      loginAs(userA);
      await expectLater(
        repository.getVolumeOverTime(),
        throwsA(isA<SessionStaleException>()),
      );
    });
  });

  // ==================================================================
  // Failure classification
  // ==================================================================

  group('failure classification', () {
    test(
      'ordinary HTTP failure while current -> A-owned local fallback',
      () async {
        final recent = DateTime.now().subtract(const Duration(days: 3));
        await ownedGraph(uid: userA, reps: 10, weight: 100, date: recent);
        await ownedGraph(uid: userB, reps: 10, weight: 999, date: recent);
        loginAs(userA);
        adapter.responder =
            (_) async => jsonBody({'error': 'boom'}, statusCode: 500);

        final stats = await repository.getWorkoutStats();
        expect(stats.totalVolume, 1000);
        final prs = await repository.getPersonalRecords();
        expect(prs.every((p) => p.weight == 100), isTrue);
        final vol = await repository.getVolumeOverTime();
        expect(vol.single.value, 1000);
      },
    );

    test(
      'a malformed / unparseable success body while current -> A-owned local '
      'fallback (parse failure is an ordinary failure, not thrown)',
      () async {
        final recent = DateTime.now().subtract(const Duration(days: 3));
        await ownedGraph(uid: userA, reps: 10, weight: 100, date: recent);
        await ownedGraph(uid: userB, reps: 10, weight: 999, date: recent);
        loginAs(userA);
        // 200 OK, but the body is not the shape the model parser expects.
        adapter.responder = (_) async => jsonBody('totally unexpected');

        final stats = await repository.getWorkoutStats();
        expect(stats.totalVolume, 1000);
        final prs = await repository.getPersonalRecords();
        expect(prs.single.weight, 100);
        final vol = await repository.getVolumeOverTime();
        expect(vol.single.value, 1000);
      },
    );

    test(
      'an ordinary HTTP failure whose session already changed to B -> '
      'SessionStaleException, never a B-computed fallback (no recapture)',
      () async {
        await ownedGraph(uid: userA, reps: 10, weight: 100);
        await ownedGraph(uid: userB, reps: 10, weight: 999);
        loginAs(userA);
        final gate = Completer<ResponseBody>();
        adapter.responder = (_) => gate.future;

        final future = repository.getWorkoutStats();
        await adapter.nextDispatch();
        gate.complete(jsonBody({'error': 'boom'}, statusCode: 500));
        loginAs(userB); // A -> B before the catch handler runs

        await expectLater(future, throwsA(isA<SessionStaleException>()));
      },
    );

    test(
      'SessionStaleException from ApiService never enters local fallback',
      () async {
        await ownedGraph(uid: userA);
        loginAs(userA);
        apiService.beforeDispatchEpochCheckForTesting = () async => logout();

        await expectLater(
          repository.getWorkoutStats(),
          throwsA(isA<SessionStaleException>()),
        );
        await expectLater(
          repository.getPersonalRecords(),
          throwsA(isA<SessionStaleException>()),
        );
        await expectLater(
          repository.getVolumeOverTime(),
          throwsA(isA<SessionStaleException>()),
        );
      },
    );

    test('RequestCancelledException never enters local fallback', () async {
      await ownedGraph(uid: userA);
      loginAs(userA);
      adapter.neverCompletes = true;

      final future = repository.getVolumeOverTime();
      await adapter.nextDispatch();
      sessionCoordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('fallback failure surfaces as an ordinary Exception, not a lifecycle '
        'type', () async {
      await ownedGraph(uid: userA);
      loginAs(userA);
      adapter.responder = (_) async => jsonBody({'e': 1}, statusCode: 500);
      await isar.close(); // the local calculation will now throw

      await expectLater(
        repository.getWorkoutStats(),
        throwsA(allOf(isA<Exception>(), isNot(isA<SessionStaleException>()))),
      );
    });
  });
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
