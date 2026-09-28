import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/local/services/model_mapper.dart';
import 'package:go_hard_app/data/models/exercise_set.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'sync_service_lifted_weight_passthrough_test.mocks.dart';

/// Task 5: a canonical-kg weight (e.g. `61.23496995`, what `135 lb` becomes
/// through `UnitConverter.liftedInputToKg`) must cross the sync boundary
/// EXACTLY - `SyncService`, `ExerciseRepository`, and `ModelMapper` never
/// convert; they are a pure pass-through below the UI's input/display
/// boundary. Uses the real [ApiService] (not a mock) against a fake
/// [HttpClientAdapter] so the request body AND the
/// `X-Lifted-Weight-Unit: kg` header can both be asserted against what the
/// real interceptor pipeline actually sends - mirroring the harness in
/// sync_service_operation_ownership_test.dart / analytics_repository_
/// session_ownership_test.dart.
@GenerateMocks([AuthService])
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService authService;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late SyncService syncService;

  const userId = 1;
  const canonicalWeight = 61.23496995;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sync_service_lifted_weight_',
    );
    isar = await Isar.open(
      [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
    );

    authService = MockAuthService();
    when(authService.getUserId()).thenAnswer((_) async => userId);
    when(authService.getToken()).thenAnswer((_) async => 'jwt-$userId');

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch()..activate(userId);
    sessionCoordinator = SessionRequestCoordinator(sessionEpoch, authService);
    apiService = ApiService(authService, sessionEpoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;

    SyncService.reset();
    syncService = SyncService(
      apiService: apiService,
      authService: authService,
      localDb: localDb,
      connectivity: ConnectivityService.instance,
      sessionEpoch: sessionEpoch,
      sessionCoordinator: sessionCoordinator,
    );
  });

  tearDown(() async {
    SyncService.reset();
    if (isar.isOpen) await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LocalSession> insertSyncedSession({int serverId = 100}) async {
    final session = LocalSession(
      serverId: serverId,
      userId: userId,
      date: DateTime(2026, 1, 1),
      status: 'in_progress',
      isSynced: true,
      syncStatus: 'synced',
      // A non-null version keeps this row out of the unrelated
      // version-reconciliation GET path (see sync_service_test.dart's
      // "version reconciliation" group) - that path is not what this test
      // is about and would otherwise add a second captured request.
      version: 1,
      lastModifiedLocal: DateTime.now().toUtc(),
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Future<LocalExercise> insertSyncedExercise({
    required int sessionLocalId,
    int serverId = 50,
  }) async {
    final exercise = LocalExercise(
      serverId: serverId,
      sessionLocalId: sessionLocalId,
      name: 'Bench Press',
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.now().toUtc(),
    );
    await isar.writeTxn(() => isar.localExercises.put(exercise));
    return exercise;
  }

  ResponseBody jsonBody(Object json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  RequestOptions onlyRequest() {
    expect(adapter.capturedRequests, hasLength(1));
    return adapter.capturedRequests.single;
  }

  test('a pending_create set sends the exact canonical kg weight and the '
      'X-Lifted-Weight-Unit: kg header on POST', () async {
    final session = await insertSyncedSession();
    final exercise = await insertSyncedExercise(
      sessionLocalId: session.localId,
    );
    await isar.writeTxn(
      () => isar.localExerciseSets.put(
        LocalExerciseSet(
          exerciseLocalId: exercise.localId,
          setNumber: 1,
          reps: 5,
          weight: canonicalWeight,
          isCompleted: false,
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime.now().toUtc(),
        ),
      ),
    );

    adapter.responder = (_) async => jsonBody({'id': 900});

    await syncService.sync();

    final sent = onlyRequest();
    expect(sent.method, 'POST');
    final body = sent.data as Map<String, dynamic>;
    expect(body['weight'], canonicalWeight);
    expect(
      sent.headers[ApiConfig.liftedWeightUnitHeader],
      ApiConfig.liftedWeightCanonicalUnit,
    );

    final stored =
        await isar.localExerciseSets
            .filter()
            .exerciseLocalIdEqualTo(exercise.localId)
            .findFirst();
    expect(stored!.syncStatus, 'synced');
    expect(stored.weight, canonicalWeight);
  });

  test('a pending_update set sends the exact canonical kg weight and the '
      'X-Lifted-Weight-Unit: kg header on PUT', () async {
    final session = await insertSyncedSession();
    final exercise = await insertSyncedExercise(
      sessionLocalId: session.localId,
    );
    await isar.writeTxn(
      () => isar.localExerciseSets.put(
        LocalExerciseSet(
          serverId: 900,
          exerciseServerId: exercise.serverId,
          exerciseLocalId: exercise.localId,
          setNumber: 1,
          reps: 5,
          weight: canonicalWeight,
          isCompleted: false,
          isSynced: false,
          syncStatus: 'pending_update',
          lastModifiedLocal: DateTime.now().toUtc(),
        ),
      ),
    );

    adapter.responder = (_) async => jsonBody('{}');

    await syncService.sync();

    final sent = onlyRequest();
    expect(sent.method, 'PUT');
    final body = sent.data as Map<String, dynamic>;
    expect(body['weight'], canonicalWeight);
    expect(
      sent.headers[ApiConfig.liftedWeightUnitHeader],
      ApiConfig.liftedWeightCanonicalUnit,
    );

    final stored =
        await isar.localExerciseSets
            .filter()
            .exerciseLocalIdEqualTo(exercise.localId)
            .findFirst();
    expect(stored!.syncStatus, 'synced');
    expect(stored.weight, canonicalWeight);
  });

  test('ModelMapper API->local download mapping keeps the canonical kg weight '
      'exactly (no conversion below the UI boundary)', () {
    final apiSet = ExerciseSet(
      id: 900,
      exerciseId: 50,
      setNumber: 1,
      reps: 5,
      weight: canonicalWeight,
      isCompleted: true,
    );

    final local = ModelMapper.exerciseSetToLocal(
      apiSet,
      exerciseLocalId: 1,
      exerciseServerId: 50,
    );

    expect(local.weight, canonicalWeight);
  });
}

/// Minimal fake Dio transport - records every dispatched [RequestOptions]
/// and answers with [responder]. Mirrors the fake adapter used in
/// analytics_repository_session_ownership_test.dart /
/// sync_service_operation_ownership_test.dart.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];
  Future<ResponseBody> Function(RequestOptions options)? responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
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
