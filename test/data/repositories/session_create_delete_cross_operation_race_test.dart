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

/// CHARACTERIZATION TEST for a KNOWN, UNRESOLVED defect - delete-during-CREATE
/// orphans a committed server row. It is NOT a fix and NOT safety coverage:
/// it passes by *demonstrating* the orphan. It exists to pin the exact
/// failure so the Session idempotency / operation-identity PR has a red
/// anchor to flip; that PR is expected to rewrite this test to assert a
/// safe converged outcome once durable `ClientRequestId` + API uniqueness +
/// client reconciliation exist.
///
/// A detached foreground `SessionRepository._syncCreateSessionToServer` POST
/// and an independent `SyncService.sync()` pass share only Isar,
/// `UserSessionEpoch`, and `SessionRequestCoordinator` - none of which
/// serialize them. This suite drives the exact interleaving:
///
///   t0 createSession schedules the foreground CREATE POST
///   t1 hold the POST response after dispatch
///   t2 deleteSession marks the row (serverId == null)
///   t3 an independent SyncService.sync() runs while the POST is still held
///   t4 SyncService processes the row
///   t5 release the POST with a committed server Session
///   t6 inspect local + (fake) server state
///
/// Deterministic: a held `Completer` for the POST response, the fake
/// adapter's `nextDispatch()` signal for "the request reached the
/// transport", and `scheduledBackgroundSyncs` for detached-op settlement.
/// No wall-clock waits, `Future.delayed`, `Timer`, `sleep`, `pumpEventQueue`
/// or `_settle`, and no mock-call polling as a sync primitive.
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

  Map<String, dynamic> serverSessionJson(int id) => {
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
  };

  test(
    'REPRODUCER: an independent SyncService pass that runs while the '
    'foreground CREATE POST is still in flight can leave a server row with '
    'no local record (delete-during-CREATE is NOT compensated by this PR)',
    () async {
      loginAs(userA);

      // t1: hold the POST /sessions response; everything else answers now.
      final heldPost = Completer<ResponseBody>();
      adapter.responder = (opts) {
        if (opts.method == 'POST' && opts.path == ApiConfig.sessions) {
          return heldPost.future;
        }
        return Future.value(jsonResponse(const <dynamic>[]));
      };

      // t0: schedule the foreground CREATE and wait until the POST has
      // genuinely reached the transport.
      final dispatched = adapter.nextDispatch();
      final created = await repository.createSession(sessionModel('Fresh'));
      await dispatched;

      expect(
        adapter.captured.where(
          (r) => r.method == 'POST' && r.path == ApiConfig.sessions,
        ),
        hasLength(1),
        reason: 't0/t1: the CREATE POST dispatched before any delete/sync',
      );
      expect(heldPost.isCompleted, isFalse);

      // t2: delete the still-server-id-less local row. `_markForDeletion`
      // hard-deletes it immediately (no tombstone in this PR's scope).
      final deleteOk = await repository.deleteSession(created.id);
      expect(deleteOk, isTrue);
      expect(
        await isar.localSessions.get(created.id),
        isNull,
        reason: 't2: the local row is already gone before the CREATE settles',
      );

      // t3/t4: an independent SyncService pass runs while the foreground POST
      // is still held. There is no row for it to find and no coordination
      // that would make it wait for the CREATE.
      await syncService.sync();
      expect(
        heldPost.isCompleted,
        isFalse,
        reason:
            't3/t4: nothing serializes the SyncService pass against the '
            'in-flight foreground CREATE',
      );

      // t5: the foreground CREATE now succeeds - the server committed a row.
      heldPost.complete(jsonResponse(serverSessionJson(777)));
      await scheduledBackgroundSyncs.single;

      // t6: the foreground acknowledgment re-resolved by localId, found
      // nothing, and returned. No compensating DELETE was or can be issued.
      expect(await isar.localSessions.get(created.id), isNull);
      expect(
        adapter.captured.any((r) => r.method == 'DELETE'),
        isFalse,
        reason: 'no compensating DELETE /sessions/{id} was ever sent',
      );

      // FAILURE STATE (documented, deferred to the Session idempotency PR):
      // server has Session 777, local has no row and no tombstone. This is a
      // characterization test for a KNOWN, UNRESOLVED orphan race - NOT
      // safety coverage and NOT proof that deletion is protected. It is
      // expected to be rewritten (to assert a safe converged outcome) when
      // durable client operation identity (`ClientRequestId`) + API
      // uniqueness + client reconciliation land in that PR.
      final serverGotCreate = adapter.captured.any(
        (r) => r.method == 'POST' && r.path == ApiConfig.sessions,
      );
      expect(serverGotCreate, isTrue);
      // This assertion documents the unresolved outcome rather than a fix:
      // there is no client-side state left that could reconcile Session 777.
    },
  );
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
