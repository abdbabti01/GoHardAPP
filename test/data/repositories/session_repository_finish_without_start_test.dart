import 'dart:async';
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
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'session_repository_finish_without_start_test.mocks.dart';

/// BUG-11: ActiveWorkoutScreen's AppBar "Finish" action is reachable on a
/// still-`draft` session (unlike the mutually-exclusive Start/Pause/Resume
/// control, it is never gated on `isDraft`), so `finishWorkout()` can ask to
/// go straight from `draft`/`planned` to `completed`. The server's
/// `SessionStatus.IsValidTransition` correctly rejects that direct jump
/// (`(Draft, Completed) => false`, GoHardAPI Models/Session.cs) - reproduced
/// live against the local QA backend: the server session stayed `draft`
/// forever while the client had already navigated away showing success.
///
/// The fix bridges the session through a real `in_progress` PATCH first,
/// awaited, before the `completed` PATCH - both inside ONE background-sync
/// operation, so the two HTTP calls are strictly ordered (two independently
/// fire-and-forgotten `_backgroundSync` calls would have no such guarantee,
/// and could reach the server as completed-before-in_progress).
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
  const serverId = 500;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_finish_no_start_');
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

  Future<LocalSession> insertDraftSession() async {
    final s = LocalSession(
      serverId: serverId,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: 'Chest Day',
      status: 'draft',
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime(2026, 1, 1),
    );
    await isar.writeTxn(() => isar.localSessions.put(s));
    return s;
  }

  test('finishing a never-started (draft) session sends in_progress THEN '
      'completed, in that order, as two separate PATCHes', () async {
    await insertDraftSession();

    final calls = <Map<String, dynamic>>[];
    when(
      mockApiService.patch<void>(
        ApiConfig.sessionStatus(serverId),
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((invocation) async {
      calls.add(invocation.namedArguments[#data] as Map<String, dynamic>);
    });

    final result = await repository.updateSessionStatus(
      1,
      'completed',
      duration: 5,
    );

    // Give the fire-and-forget background sync a chance to run.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(result.status, 'completed');
    expect(
      calls.length,
      2,
      reason: 'expected exactly two PATCHes (bridge + completed)',
    );
    expect(
      calls[0]['status'],
      'in_progress',
      reason: 'the server must see in_progress before completed',
    );
    expect(calls[0]['startedAt'], isNotNull);
    expect(calls[1]['status'], 'completed');
  });

  test('the local row gets a non-null startedAt when finished directly from '
      'draft, even offline', () async {
    when(
      mockApiService.patch<void>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async {});
    final inserted = await insertDraftSession();
    // Force the offline branch: no serverId push attempted, only the
    // local write matters here.
    await isar.writeTxn(() async {
      inserted.serverId = null;
      inserted.syncStatus = 'pending_create';
      inserted.isSynced = false;
      await isar.localSessions.put(inserted);
    });

    final result = await repository.updateSessionStatus(
      1,
      'completed',
      duration: 5,
    );

    expect(result.status, 'completed');
    expect(
      result.startedAt,
      isNotNull,
      reason:
          'a session completed directly from draft must still record a '
          'real startedAt locally, not leave it null forever',
    );
  });

  test('a normal in_progress -> completed finish still sends exactly one PATCH '
      '(no unnecessary bridging)', () async {
    final s = await insertDraftSession();
    await isar.writeTxn(() async {
      s.status = 'in_progress';
      s.startedAt = DateTime.utc(2026, 1, 1, 10);
      await isar.localSessions.put(s);
    });

    final calls = <Map<String, dynamic>>[];
    when(
      mockApiService.patch<void>(
        ApiConfig.sessionStatus(serverId),
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((invocation) async {
      calls.add(invocation.namedArguments[#data] as Map<String, dynamic>);
    });

    await repository.updateSessionStatus(1, 'completed', duration: 5);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(calls.length, 1);
    expect(calls.single['status'], 'completed');
  });

  test(
    'a Finish that races the still-in-flight CREATE is pushed immediately '
    'once the CREATE acknowledges - not left for the periodic sync pass',
    () async {
      final postGate = Completer<Map<String, dynamic>>();
      when(
        mockApiService.post<Map<String, dynamic>>(
          ApiConfig.sessions,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) => postGate.future);

      final patchCalls = <Map<String, dynamic>>[];
      when(
        mockApiService.patch<void>(
          ApiConfig.sessionStatus(serverId),
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((invocation) async {
        patchCalls.add(
          invocation.namedArguments[#data] as Map<String, dynamic>,
        );
      });

      // Collects every `_backgroundSync` future as it is scheduled - draining
      // this deterministically (instead of a wall-clock delay) also catches
      // the SECOND background sync the CREATE acknowledgment schedules
      // synchronously from within the first, once it detects the race.
      final scheduled = <Future<void>>[];
      repository.onBackgroundSyncScheduledForTesting = scheduled.add;

      final created = await repository.createSession(
        Session(
          id: 0,
          userId: userId,
          date: DateTime(2026, 1, 1),
          duration: 0,
          name: 'Chest Day',
          type: 'Workout',
          status: 'draft',
          exercises: const [],
        ),
      );

      // Finish locally BEFORE the CREATE POST resolves - no serverId yet, so
      // updateSessionStatus cannot push immediately.
      await repository.updateSessionStatus(
        created.id,
        'completed',
        duration: 5,
      );
      expect(patchCalls, isEmpty, reason: 'no serverId yet - nothing to push');

      // Now the CREATE POST resolves, echoing the ORIGINAL (stale) 'draft'
      // status the request actually carried.
      postGate.complete({
        'id': serverId,
        'userId': userId,
        'date': '2026-01-01T00:00:00.000Z',
        'name': 'Chest Day',
        'type': 'Workout',
        'status': 'draft',
        'version': 1,
      });

      var i = 0;
      while (i < scheduled.length) {
        await scheduled[i];
        i++;
      }
      repository.onBackgroundSyncScheduledForTesting = null;

      expect(
        patchCalls.length,
        2,
        reason:
            'expected the bridge (in_progress) + completed PATCH, fired '
            'immediately after the CREATE acknowledgment detects the race',
      );
      expect(patchCalls[0]['status'], 'in_progress');
      expect(patchCalls[1]['status'], 'completed');
    },
  );
}
