import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_goal.dart';
import 'package:go_hard_app/data/local/models/local_program.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/services/rate_limited_exception.dart';

// Reuses the Mockito mocks generated for sync_service_test.dart (same
// ApiService / AuthService surface, unchanged by this PR) - no new
// build_runner output.
import 'sync_service_test.mocks.dart';

/// Proves `SyncService`'s whole-PASS abort on a `RateLimitedException`: the
/// deployed API's GlobalLimiter can return 429 from ANY endpoint - session
/// writes, the session-version reconciliation GETs, exercises, sets,
/// programs, goals, or any later phase - and wherever it originates, the
/// remaining sync pass must stop immediately: no more rows in the throwing
/// phase, and no later phase at all. Every phase (and the reconciliation
/// sub-phase) now rethrows `RateLimitedException` past its own generic catch
/// instead of absorbing it - `_startSyncPass` is the ONE place that catches
/// it, so this is exercised end-to-end here, not via a private-method unit
/// test.
///
/// Real Isar (Session/Exercise/ExerciseSet/Program/Goal schemas), real
/// `UserSessionEpoch`, real `SessionRequestCoordinator`; `MockApiService`
/// with synchronous throwing responders counted by phase. No wall-clock
/// timing.
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
    tempDir = await Directory.systemTemp.createTemp('sync_rate_limit_abort_');
    isar = await Isar.open(
      [
        LocalSessionSchema,
        LocalExerciseSchema,
        LocalExerciseSetSchema,
        LocalProgramSchema,
        LocalGoalSchema,
      ],
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

  // ---- counting stubs ---------------------------------------------------

  var postCalls = 0;
  var getCalls = 0;

  void resetCounters() {
    postCalls = 0;
    getCalls = 0;
  }

  void stubPostThrows(Object error) {
    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async {
      postCalls++;
      throw error;
    });
  }

  void stubGetThrows(Object error) {
    when(
      mockApiService.get<Map<String, dynamic>>(
        any,
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async {
      getCalls++;
      throw error;
    });
  }

  // ---- fixtures -----------------------------------------------------------

  Future<LocalSession> insertPendingSession() async {
    final s = LocalSession(
      serverId: null,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: 'Workout',
      status: 'draft',
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localSessions.put(s));
    return s;
  }

  /// A "clean unversioned" session - synced, has a serverId, but no
  /// `version` recorded yet - this is exactly what
  /// `_reconcileUpgradedSessionVersions`'s FIRST loop (a GET, before the
  /// main pending-row loop even starts) targets.
  Future<LocalSession> insertCleanUnversionedSession() async {
    final s = LocalSession(
      serverId: 111,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: 'Synced workout',
      status: 'draft',
      isSynced: true,
      syncStatus: 'synced',
      version: null,
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localSessions.put(s));
    return s;
  }

  Future<LocalSession> insertSyncedParentSession() async {
    final s = LocalSession(
      serverId: 500,
      userId: userId,
      date: DateTime(2026, 1, 1),
      name: 'Parent session',
      status: 'draft',
      isSynced: true,
      syncStatus: 'synced',
      version: 1,
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localSessions.put(s));
    return s;
  }

  Future<LocalExercise> insertPendingExercise(
    int sessionLocalId, {
    int? sessionServerId,
  }) async {
    final ex = LocalExercise(
      sessionLocalId: sessionLocalId,
      sessionServerId: sessionServerId,
      name: 'Bench press',
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localExercises.put(ex));
    return ex;
  }

  Future<LocalExercise> insertSyncedParentExercise(int sessionLocalId) async {
    final ex = LocalExercise(
      sessionLocalId: sessionLocalId,
      serverId: 900,
      sessionServerId: 500,
      name: 'Squat',
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localExercises.put(ex));
    return ex;
  }

  Future<LocalExerciseSet> insertPendingSet(int exerciseLocalId) async {
    final set = LocalExerciseSet(
      exerciseLocalId: exerciseLocalId,
      setNumber: 1,
      reps: 5,
      weight: 100,
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localExerciseSets.put(set));
    return set;
  }

  Future<LocalProgram> insertPendingProgram() async {
    final now = DateTime(2026, 1, 1, 8);
    final program = LocalProgram(
      userId: userId,
      title: 'Program',
      totalWeeks: 4,
      currentWeek: 1,
      currentDay: 1,
      startDate: now,
      createdAt: now,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localPrograms.put(program));
    return program;
  }

  Future<LocalGoal> insertPendingGoal() async {
    final now = DateTime(2026, 1, 1, 8);
    final goal = LocalGoal(
      userId: userId,
      goalType: 'weight',
      targetValue: 80,
      currentValue: 90,
      startDate: now,
      createdAt: now,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localGoals.put(goal));
    return goal;
  }

  group('SyncService whole-pass abort on RateLimitedException', () {
    test('1. a session-phase 429 aborts the complete pass - a later, '
        'independently-pending exercise never dispatches', () async {
      await insertPendingSession(); // 429s.
      final parent = await insertSyncedParentSession();
      await insertPendingExercise(
        parent.localId,
        sessionServerId: parent.serverId,
      );

      resetCounters();
      stubPostThrows(const RateLimitedException());
      stubGetThrows(const RateLimitedException()); // Should never be hit.

      await syncService.sync();

      expect(
        postCalls,
        1,
        reason: 'only the session CREATE should ever be attempted',
      );
      expect(getCalls, 0);
    });

    test('2. a reconciliation GET 429 aborts the complete pass - even the '
        'REST of the sessions phase\'s own main loop never runs', () async {
      await insertCleanUnversionedSession(); // Reconciliation GET 429s.
      await insertPendingSession(); // Would be in the SAME phase's main
      // loop, dispatched AFTER reconciliation - must never be reached.

      resetCounters();
      stubGetThrows(
        const RateLimitedException(retryAfter: Duration(seconds: 30)),
      );
      stubPostThrows(const RateLimitedException()); // Should never be hit.

      await syncService.sync();

      expect(getCalls, 1, reason: 'the reconciliation GET is attempted once');
      expect(
        postCalls,
        0,
        reason:
            'the main pending-sessions loop (same phase, but AFTER '
            'reconciliation) must never run once the GET 429s',
      );
    });

    test('3. an exercise-phase 429 prevents the set/program/goal phases (and '
        'every phase after) from running at all', () async {
      final parent = await insertSyncedParentSession();
      await insertPendingExercise(
        parent.localId,
        sessionServerId: parent.serverId,
      );
      final parentEx = await insertSyncedParentExercise(parent.localId);
      await insertPendingSet(parentEx.localId);
      await insertPendingProgram();
      await insertPendingGoal();

      resetCounters();
      stubPostThrows(const RateLimitedException());

      await syncService.sync();

      expect(
        postCalls,
        1,
        reason:
            'only the exercise CREATE should be attempted - the set, '
            'program, and goal phases must never dispatch',
      );
    });

    test('4. an exercise-set 429 prevents later phases (programs, goals) from '
        'running', () async {
      final parent = await insertSyncedParentSession();
      final parentEx = await insertSyncedParentExercise(parent.localId);
      await insertPendingSet(parentEx.localId);
      await insertPendingProgram();
      await insertPendingGoal();

      resetCounters();
      stubPostThrows(const RateLimitedException());

      await syncService.sync();

      expect(
        postCalls,
        1,
        reason:
            'only the set CREATE should be attempted - programs and '
            'goals must never dispatch',
      );
    });

    test('5. a representative LATER-phase 429 (Goals, phase 5 of 11) is '
        'propagated all the way to the orchestration-level handler and arms '
        'the SAME cooldown a session-phase 429 would', () async {
      await insertPendingGoal();

      resetCounters();
      stubPostThrows(
        const RateLimitedException(retryAfter: Duration(seconds: 45)),
      );

      await syncService.sync();
      expect(postCalls, 1);

      // The cooldown armed by a Goals-phase 429 must gate the NEXT
      // sync() call exactly like a session-phase one would - proving the
      // handler is genuinely orchestration-level, not session-specific.
      await syncService.sync();
      expect(
        postCalls,
        1,
        reason:
            'a later-phase 429 must arm the same session-owned cooldown '
            'as any other phase',
      );
    });
  });
}
