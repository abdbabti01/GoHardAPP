import 'dart:io';

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
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'session_repository_history_preservation_sync_test.mocks.dart';

/// Gap 2 evidence: proves the CURRENTLY-RELEASED Flutter client's own
/// post-delete reload call - `SessionsProvider.loadSessions(waitForSync:
/// true)`, which every one of `goals_screen.dart` / `programs_screen.dart` /
/// `program_detail_screen.dart`'s delete-success handlers already calls
/// unmodified from `main` - can never delete a locally-cached Session that
/// the server still returns from `GET /sessions`.
///
/// `SessionRepository._syncSessionsFromServer`'s cleanup sweep (the
/// "cascade delete cleanup" comment in that method) is a pure ID-set diff:
/// it removes a local Session only when its `serverId` is ABSENT from the
/// current `GET /sessions` response - it has no FK/programId-aware logic at
/// all. Since the backend's Goal/Program delete endpoints (both the original
/// Phase 1 detachment and the Gap 1 soft-delete redesign) never remove a
/// Session row nor exclude it from `GET /sessions`, this sweep cannot lose
/// history that the server preserves - old client + new server is safe by
/// construction, not by luck. This test exercises the real
/// `getSessions(waitForSync: true)` path exactly as the client calls it,
/// against a real on-disk Isar database and a mocked API response shaped
/// like the server's post-delete state (Session present, ProgramId cleared).
@GenerateMocks([ApiService, AuthService])
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late SessionRepository repository;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;

  const userId = 1;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'session_history_preservation_sync_',
    );
    isar = await Isar.open(
      [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
    );

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

    repository = SessionRepository(
      mockApiService,
      localDb,
      ConnectivityService.instance,
      mockAuthService,
      sessionEpoch,
      sessionCoordinator,
    );
  });

  tearDown(() async {
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('a Session the server still returns after a Goal/Program delete is '
      'NEVER removed locally by the post-delete waitForSync reload, even '
      'though its cached ProgramId is now stale', () async {
    // Locally cached exactly as it would be right before the user deletes
    // the Program it was linked to: still carrying the (about to be
    // stale) ProgramId, with a completed Exercise/Set under it.
    final local = LocalSession(
      serverId: 42,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: 'Leg Day',
      status: 'completed',
      programId: 7, // the program the user is about to delete
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime(2026, 1, 1),
    );
    await isar.writeTxn(() => isar.localSessions.put(local));

    final exercise = LocalExercise(
      sessionLocalId: local.localId,
      serverId: 100,
      name: 'Squat',
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime(2026, 1, 1),
    );
    await isar.writeTxn(() => isar.localExercises.put(exercise));

    final set = LocalExerciseSet(
      exerciseLocalId: exercise.localId,
      serverId: 500,
      setNumber: 1,
      reps: 5,
      weight: 100,
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime(2026, 1, 1),
    );
    await isar.writeTxn(() => isar.localExerciseSets.put(set));

    // The server's response to the reload the delete handler triggers:
    // the Session survives (soft-delete/detachment design), just with
    // ProgramId now null - exactly the shape ProgramsController.DeleteProgram
    // produces.
    when(
      mockApiService.get<List<dynamic>>(
        ApiConfig.sessions,
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer(
      (_) async => [
        {
          'id': 42,
          'userId': userId,
          'date': '2026-01-01',
          'status': 'completed',
          'programId': null,
          'programWorkoutId': null,
          'version': 1,
        },
      ],
    );

    // The exact call the currently-released client's delete-success
    // handlers make (goals_screen.dart / programs_screen.dart /
    // program_detail_screen.dart all call this unmodified from `main`).
    await repository.getSessions(waitForSync: true);

    final survivingSession = await isar.localSessions.get(local.localId);
    expect(
      survivingSession,
      isNotNull,
      reason:
          'the sync sweep must never delete a Session the server still '
          'returns, regardless of a stale local ProgramId',
    );
    expect(survivingSession!.serverId, 42);

    final survivingExercise = await isar.localExercises.get(exercise.localId);
    expect(
      survivingExercise,
      isNotNull,
      reason:
          'the sweep only ever diffs Session ids - it must not '
          'cascade-delete a surviving Session\'s own Exercises',
    );

    final survivingSet = await isar.localExerciseSets.get(set.localId);
    expect(survivingSet, isNotNull);
  });

  test('a Session genuinely absent from the server response IS still removed '
      'by the same sweep - confirms the preservation above is not simply a '
      'sweep that never deletes anything', () async {
    final local = LocalSession(
      serverId: 99,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: 'Old Session',
      status: 'completed',
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime(2026, 1, 1),
    );
    await isar.writeTxn(() => isar.localSessions.put(local));

    when(
      mockApiService.get<List<dynamic>>(
        ApiConfig.sessions,
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => <dynamic>[]);

    await repository.getSessions(waitForSync: true);

    final row = await isar.localSessions.get(local.localId);
    expect(row, isNull);
  });
}
