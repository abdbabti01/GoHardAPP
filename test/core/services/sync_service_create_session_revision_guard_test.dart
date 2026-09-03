import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
import 'package:go_hard_app/core/services/connectivity_service.dart';
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
import 'package:go_hard_app/data/models/shared_workout.dart';
import 'package:go_hard_app/data/models/workout_template.dart';

// Reuses the Mockito mocks generated for sync_service_test.dart (same
// ApiService / AuthService surface, unchanged by this PR) so this suite adds
// no new build_runner output.
import 'sync_service_test.mocks.dart';

/// Proves the CREATE in-flight-edit revision guard added to
/// `SyncService._syncCreateSession` (mirroring the merged `_syncCreateSet`
/// guard): a local edit / completion that races the CREATE POST await is
/// preserved and re-queued as `pending_update` with the server id/version
/// attached, never overwritten by the stale create response.
///
/// Delete-during-CREATE compensation is NOT in scope here - a delete of a
/// still-server-id-less session hard-deletes the local row, and that
/// cross-operation orphan is deferred to the Session idempotency PR (see
/// `test/data/repositories/session_create_delete_cross_operation_race_test.dart`).
///
/// Real Isar, real `UserSessionEpoch`, real `SessionRequestCoordinator`;
/// `MockApiService` with `Completer`-gated responders for exact
/// dispatch/acknowledgment interleaving. No wall-clock waits.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late SyncService syncService;

  const userA = 1;
  const userB = 2;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sync_create_session_guard_',
    );
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

    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userA);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$userA');

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch()..activate(userA);
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );

    SyncService.reset();
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
    syncService.beforeAckWriteTxnForTesting = null;
    syncService.insideAckWriteTxnForTesting = null;
    syncService.beforePhaseCheckForTesting = null;
    SyncService.reset();
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LocalSession> insertPendingCreateSession({
    int uid = userA,
    String name = 'Draft workout',
    String status = 'draft',
    String syncStatus = 'pending_create',
    int? serverId,
    int? version,
    DateTime? lastModifiedLocal,
    DateTime? lastModifiedServer,
    DateTime? completedAt,
    int? duration,
  }) async {
    final session = LocalSession(
      serverId: serverId,
      userId: uid,
      date: DateTime(2026, 1, 1),
      name: name,
      status: status,
      duration: duration,
      completedAt: completedAt,
      isSynced: false,
      syncStatus: syncStatus,
      lastModifiedLocal: lastModifiedLocal ?? DateTime(2026, 1, 1, 8),
      lastModifiedServer: lastModifiedServer,
      version: version,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));
    return session;
  }

  Map<String, dynamic> serverSessionJson({
    required int id,
    int userId = userA,
    String name = 'Draft workout',
    String status = 'draft',
    int version = 1,
    String? completedAt,
    int? duration,
  }) => {
    'id': id,
    'userId': userId,
    'date': '2026-01-01',
    'duration': duration,
    'notes': null,
    'type': null,
    'name': name,
    'status': status,
    'startedAt': null,
    'completedAt': completedAt,
    'pausedAt': null,
    'exercises': <dynamic>[],
    'programId': null,
    'programWorkoutId': null,
    'version': version,
  };

  void stubPost(Map<String, dynamic> response) {
    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => response);
  }

  /// Applies a same-session local mutation to [localId] exactly like the
  /// repository's completion/edit paths: advances `lastModifiedLocal`, keeps
  /// `pending_create` (serverId still null). Runs as a direct writeTxn - the
  /// test drives it from inside a POST responder, where no repository
  /// writeTxn is active.
  Future<void> raceLocalEdit(
    int localId, {
    String? status,
    DateTime? completedAt,
    int? duration,
    String? name,
  }) async {
    await isar.writeTxn(() async {
      final row = await isar.localSessions.get(localId);
      if (row == null) return;
      if (status != null) row.status = status;
      if (completedAt != null) row.completedAt = completedAt;
      if (duration != null) row.duration = duration;
      if (name != null) row.name = name;
      row.isSynced = false;
      row.lastModifiedLocal = DateTime(2026, 1, 1, 9); // strictly after 08:00
      await isar.localSessions.put(row);
    });
  }

  group('SyncService._syncCreateSession - no race (tests 1, 2)', () {
    test('1. normal CREATE with no raced edit becomes synced with the '
        'server id and authoritative version', () async {
      final s = await insertPendingCreateSession();
      stubPost(serverSessionJson(id: 500, version: 1));

      await syncService.sync();

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
      expect(stored.serverId, 500);
      expect(stored.version, 1);
    });

    test('2. the POST body corresponds to the revision captured before '
        'dispatch, even if an edit lands during the await', () async {
      final s = await insertPendingCreateSession(
        name: 'Original name',
        status: 'draft',
      );

      final release = Completer<Map<String, dynamic>>();
      Map<dynamic, dynamic>? capturedBody;
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((inv) async {
        capturedBody = inv.namedArguments[#data] as Map<dynamic, dynamic>;
        await raceLocalEdit(
          s.localId,
          status: 'completed',
          name: 'Renamed after dispatch',
        );
        return release.future;
      });

      final f = syncService.sync();
      release.complete(serverSessionJson(id: 501));
      await f;

      expect(capturedBody!['name'], 'Original name');
      expect(capturedBody!['status'], 'draft');
      expect(
        capturedBody!.containsKey('id'),
        isFalse,
        reason: 'id/version/exercises/programId/programWorkoutId are stripped',
      );
      expect(capturedBody!.containsKey('version'), isFalse);
    });
  });

  group('SyncService._syncCreateSession - raced completion '
      '(tests 3-10, 16)', () {
    Future<LocalSession> runRacedCompletion({
      String? name,
      int returnedVersion = 1,
    }) async {
      final s = await insertPendingCreateSession(name: name ?? 'Draft workout');

      final release = Completer<Map<String, dynamic>>();
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async {
        await raceLocalEdit(
          s.localId,
          status: 'completed',
          completedAt: DateTime.utc(2026, 1, 1, 10, 30),
          duration: 3600,
          name: name == null ? null : 'Edited $name',
        );
        return release.future;
      });

      final f = syncService.sync();
      release.complete(serverSessionJson(id: 700, version: returnedVersion));
      await f;
      return s;
    }

    test(
      '3. completion during POST preserves local status/completedAt/'
      'duration - the row is NOT rebuilt from the stale create response',
      () async {
        final s = await runRacedCompletion();
        final stored = await isar.localSessions.get(s.localId);
        expect(stored!.status, 'completed');
        // Isar round-trips DateTime as local-flagged; assert the instant.
        expect(
          stored.completedAt!.isAtSameMomentAs(
            DateTime.utc(2026, 1, 1, 10, 30),
          ),
          isTrue,
        );
        expect(stored.duration, 3600);
      },
    );

    test('4. raced completion attaches the returned server id', () async {
      final s = await runRacedCompletion();
      expect((await isar.localSessions.get(s.localId))!.serverId, 700);
    });

    test('5. raced completion applies the authoritative server version so the '
        'next PUT sends the right base version', () async {
      final s = await runRacedCompletion(returnedVersion: 4);
      expect((await isar.localSessions.get(s.localId))!.version, 4);
    });

    test('6. raced completion leaves isSynced == false', () async {
      final s = await runRacedCompletion();
      expect((await isar.localSessions.get(s.localId))!.isSynced, isFalse);
    });

    test('7. raced completion becomes exactly pending_update', () async {
      final s = await runRacedCompletion();
      expect(
        (await isar.localSessions.get(s.localId))!.syncStatus,
        'pending_update',
      );
    });

    test('8/9. the next sync sends PUT (not a second POST) and converges to '
        'synced', () async {
      final s = await runRacedCompletion(returnedVersion: 2);

      clearInteractions(mockApiService);
      when(
        mockApiService.put<dynamic>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer(
        (_) async => serverSessionJson(
          id: 700,
          status: 'completed',
          version: 3,
          completedAt: '2026-01-01T10:30:00.000Z',
          duration: 3600,
        ),
      );

      await syncService.sync();

      verifyNever(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
      final captured =
          verify(
            mockApiService.put<dynamic>(
              captureAny,
              data: anyNamed('data'),
              sessionContext: anyNamed('sessionContext'),
            ),
          ).captured;
      expect(captured.single, ApiConfig.sessionById(700));

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.isSynced, isTrue);
      expect(stored.syncStatus, 'synced');
      expect(stored.status, 'completed');
    });

    test('10. a name/notes edit racing the POST is preserved', () async {
      final s = await runRacedCompletion(name: 'My workout');
      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.name, 'Edited My workout');
      expect(stored.syncStatus, 'pending_update');
    });

    test(
      '10b. the raced acknowledgment advances lastModifiedServer from its '
      'seeded value - it must record that the server accepted the CREATE, '
      'exactly as the unchanged-path ModelMapper.sessionToLocal does',
      () async {
        // A distinguishable prior server-confirmation instant, years in the
        // past so DateTime.now() in the ack is unambiguously after it (no
        // clock seam or wall-clock delay needed).
        final seededServerStamp = DateTime.utc(2020, 1, 1);
        final s = await insertPendingCreateSession(
          lastModifiedServer: seededServerStamp,
        );

        final release = Completer<Map<String, dynamic>>();
        when(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async {
          await raceLocalEdit(
            s.localId,
            status: 'completed',
            completedAt: DateTime.utc(2026, 1, 1, 10, 30),
            duration: 3600,
          );
          return release.future;
        });

        final f = syncService.sync();
        release.complete(serverSessionJson(id: 702, version: 5));
        await f;

        final stored = await isar.localSessions.get(s.localId);
        // Local edited fields survive the raced acknowledgment.
        expect(stored!.status, 'completed');
        expect(
          stored.completedAt!.isAtSameMomentAs(
            DateTime.utc(2026, 1, 1, 10, 30),
          ),
          isTrue,
        );
        expect(stored.duration, 3600);
        // Server identity + authoritative version are attached.
        expect(stored.serverId, 702);
        expect(stored.version, 5);
        // The row is re-queued for a follow-up PUT, not marked synced.
        expect(stored.isSynced, isFalse);
        expect(stored.syncStatus, 'pending_update');
        // The server-acceptance timestamp advanced from the seeded value.
        // isAfter compares the instant regardless of the isUtc flag, so the
        // Isar-local-flagged read still compares correctly against the UTC
        // seed.
        expect(stored.lastModifiedServer, isNotNull);
        expect(
          stored.lastModifiedServer!.isAfter(seededServerStamp),
          isTrue,
          reason:
              'the raced ack handled a successful server CREATE and must '
              'stamp lastModifiedServer, not leave the stale seeded value',
        );
      },
    );

    test(
      '16b. a completion landing AFTER the post-dispatch re-resolve but '
      'BEFORE the ack writeTxn is still caught by the in-transaction re-fetch',
      () async {
        final s = await insertPendingCreateSession();
        stubPost(serverSessionJson(id: 701));

        syncService.beforeAckWriteTxnForTesting = () async {
          await raceLocalEdit(
            s.localId,
            status: 'completed',
            completedAt: DateTime.utc(2026, 1, 1, 13),
          );
        };

        await syncService.sync();

        final stored = await isar.localSessions.get(s.localId);
        expect(stored!.serverId, 701);
        expect(stored.status, 'completed');
        expect(
          stored.completedAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 1, 13)),
          isTrue,
        );
        expect(stored.isSynced, isFalse);
        expect(stored.syncStatus, 'pending_update');
      },
    );

    test(
      '16. a failed CREATE whose response was lost while a completion '
      'raced keeps the completion and only bumps retry bookkeeping',
      () async {
        final s = await insertPendingCreateSession();

        when(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async {
          await raceLocalEdit(
            s.localId,
            status: 'completed',
            completedAt: DateTime.utc(2026, 1, 1, 11),
          );
          throw Exception('connection reset');
        });

        await syncService.sync();

        final stored = await isar.localSessions.get(s.localId);
        expect(stored!.status, 'completed');
        expect(
          stored.completedAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 1, 11)),
          isTrue,
        );
        expect(stored.serverId, isNull);
        expect(stored.syncStatus, 'pending_create');
        expect(stored.syncRetryCount, 1);
      },
    );
  });

  group('SyncService._syncCreateSession - lifecycle & ownership '
      '(tests 12-14)', () {
    test('12. logout during the POST produces no acknowledgment', () async {
      final s = await insertPendingCreateSession();
      final release = Completer<Map<String, dynamic>>();
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) {
        sessionEpoch.invalidate();
        return release.future;
      });

      final f = syncService.sync();
      release.complete(serverSessionJson(id: 900));
      await f;

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.serverId, isNull);
      expect(stored.isSynced, isFalse);
    });

    test('13. a response arriving after B is active cannot acknowledge A\'s '
        'row', () async {
      final s = await insertPendingCreateSession(uid: userA);
      final release = Completer<Map<String, dynamic>>();
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) {
        sessionEpoch.invalidate();
        sessionEpoch.activate(userB);
        return release.future;
      });

      final f = syncService.sync();
      release.complete(serverSessionJson(id: 901, userId: userA));
      await f;

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.serverId, isNull);
      expect(stored.syncStatus, 'pending_create');
    });

    test('12b. a logout landing INSIDE the ack writeTxn aborts the write - '
        'the row stays pending_create, not synced', () async {
      final s = await insertPendingCreateSession();
      stubPost(serverSessionJson(id: 903));
      syncService.insideAckWriteTxnForTesting =
          () async => sessionEpoch.invalidate();

      await syncService.sync();

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.syncStatus, 'pending_create');
      expect(stored.serverId, isNull);
      expect(stored.isSynced, isFalse);
    });

    test('13b. a reassignment landing INSIDE the ack writeTxn is rejected by '
        'the in-transaction owner recheck - no acknowledgment', () async {
      final s = await insertPendingCreateSession(uid: userA);
      stubPost(serverSessionJson(id: 904, userId: userA));
      syncService.insideAckWriteTxnForTesting = () async {
        // Direct write - already inside the ack's own writeTxn.
        final row = await isar.localSessions.get(s.localId);
        row!.userId = userB;
        await isar.localSessions.put(row);
      };

      await syncService.sync();

      final stored = await isar.localSessions.get(s.localId);
      expect(stored!.serverId, isNull);
      expect(stored.syncStatus, 'pending_create');
      expect(stored.userId, userB);
    });

    test('14. the row being deleted / reassigned during the POST causes no '
        'recreation', () async {
      final s = await insertPendingCreateSession();
      final release = Completer<Map<String, dynamic>>();
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async {
        await isar.writeTxn(() async {
          final row = await isar.localSessions.get(s.localId);
          row!.userId = userB; // reassigned away from A
          await isar.localSessions.put(row);
        });
        return release.future;
      });

      final f = syncService.sync();
      release.complete(serverSessionJson(id: 902));
      await f;

      final stored = await isar.localSessions.get(s.localId);
      expect(
        stored!.serverId,
        isNull,
        reason: 'the reacquire checkpoint rejects a since-reassigned row',
      );
      expect(stored.syncStatus, 'pending_create');
    });
  });

  group('SyncService._syncUpdateSession no-serverId CREATE fallback '
      '(test 15)', () {
    test(
      '15. a pending_update row with no serverId falls back to CREATE and '
      'inherits the revision guard: a completion racing the POST wins',
      () async {
        final s = await insertPendingCreateSession(
          status: 'draft',
          syncStatus: 'pending_update', // invalid: no serverId
        );

        final release = Completer<Map<String, dynamic>>();
        when(
          mockApiService.post<Map<String, dynamic>>(
            any,
            data: anyNamed('data'),
            sessionContext: anyNamed('sessionContext'),
          ),
        ).thenAnswer((_) async {
          await raceLocalEdit(
            s.localId,
            status: 'completed',
            completedAt: DateTime.utc(2026, 1, 1, 12),
          );
          return release.future;
        });

        final f = syncService.sync();
        release.complete(serverSessionJson(id: 950));
        await f;

        final stored = await isar.localSessions.get(s.localId);
        expect(stored!.serverId, 950);
        expect(stored.status, 'completed');
        expect(
          stored.completedAt!.isAtSameMomentAs(DateTime.utc(2026, 1, 1, 12)),
          isTrue,
        );
        expect(stored.isSynced, isFalse);
        expect(stored.syncStatus, 'pending_update');
      },
    );

    test('no duplicate POST once a positive server id is attached', () async {
      final s = await insertPendingCreateSession(syncStatus: 'pending_update');
      final release = Completer<Map<String, dynamic>>();
      when(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async {
        await raceLocalEdit(s.localId, status: 'completed');
        return release.future;
      });
      final f = syncService.sync();
      release.complete(serverSessionJson(id: 951));
      await f;
      clearInteractions(mockApiService);

      when(
        mockApiService.put<dynamic>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async => serverSessionJson(id: 951, version: 2));

      await syncService.sync();

      verifyNever(
        mockApiService.post<Map<String, dynamic>>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      );
    });
  });

  // Delete-during-CREATE compensation (tombstone + `_syncDeleteSession`
  // reconciliation) is NOT part of this PR. `SessionRepository._markForDeletion`
  // still hard-deletes a still-server-id-less row, and the detached foreground
  // CREATE and an independent `SyncService.sync()` pass share no coordination,
  // so a delete racing an in-flight CREATE can orphan a committed server row.
  // The reproducing cross-operation trace is in
  // `test/data/repositories/session_create_delete_cross_operation_race_test.dart`;
  // the fix (durable client operation identity) is deferred to the Session
  // idempotency PR.

  group('timestamp / revision proof (tests 33, 34, 35)', () {
    test('33. DateTime.now() and DateTime.now().toUtc() represent the same '
        'instant (magnitude), so a revision comparison never differs by the '
        'timezone offset', () {
      final now = DateTime(2026, 3, 4, 5, 6, 7, 8, 9);
      expect(now.toUtc().microsecondsSinceEpoch, now.microsecondsSinceEpoch);
      expect(now.toUtc().isAtSameMomentAs(now), isTrue);
      // Dart's DateTime.== is additionally isUtc-sensitive: toUtc() != local
      // even at the same instant. The guard is sound only because BOTH of its
      // operands are Isar reads (Isar returns DateTime consistently
      // local-flagged) - see test 34.
      expect(now.toUtc() == now, isFalse);
    });

    test('34. two Isar reads of an unmodified row yield lastModifiedLocal '
        'values that are == (same instant AND same isUtc flag), so the '
        'guard\'s != comparison never reports a false race', () async {
      final s = await insertPendingCreateSession(
        lastModifiedLocal: DateTime(2026, 1, 1, 8),
      );

      final firstRead = (await isar.localSessions.get(s.localId))!;
      final secondRead = (await isar.localSessions.get(s.localId))!;

      expect(
        firstRead.lastModifiedLocal == secondRead.lastModifiedLocal,
        isTrue,
        reason: 'dispatchedAt (an Isar read) and the ack re-read compare equal',
      );
      expect(
        firstRead.lastModifiedLocal != secondRead.lastModifiedLocal,
        isFalse,
      );
      expect(
        firstRead.lastModifiedLocal.isAtSameMomentAs(
          DateTime(2026, 1, 1, 8).toUtc(),
        ),
        isTrue,
      );
    });

    test(
      '35. a clean CREATE (dispatchedAt is an Isar read, no local edit) '
      'settles to synced - the guard never misfires on isUtc handling',
      () async {
        final s = await insertPendingCreateSession(
          lastModifiedLocal: DateTime(2026, 1, 1, 8),
        );
        stubPost(serverSessionJson(id: 555, version: 2));

        await syncService.sync();

        final stored = await isar.localSessions.get(s.localId);
        expect(stored!.syncStatus, 'synced');
        expect(stored.isSynced, isTrue);
        expect(stored.serverId, 555);
      },
    );
  });
}
