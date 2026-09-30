import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/lifted_weight_contract_migration.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_program.dart';
import 'package:go_hard_app/data/local/models/local_program_workout.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/local/services/model_mapper.dart';
import 'package:go_hard_app/data/repositories/exercise_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

import 'session_repository_session_ownership_test.mocks.dart';

/// Phase 2D spec §3: previous performance is a local, offline, deterministic
/// query over completed canonical sessions, strict same-template ordinal
/// pairing, raw kg. Real Isar; any HTTP call fails the test.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService auth;
  late MockConnectivityService connectivity;
  late UserSessionEpoch epoch;

  const me = 1;
  const other = 2;

  setUpAll(() async => Isar.initializeIsarCore(download: true));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('prev_perf_');
    isar = await Isar.open(
      [
        LocalSessionSchema,
        LocalExerciseSchema,
        LocalExerciseSetSchema,
        LocalExerciseTemplateSchema,
        LocalProgramSchema,
        LocalProgramWorkoutSchema,
      ],
      directory: tempDir.path,
      inspector: false,
    );
    LocalDatabaseService.instance.setTestDatabase(isar);
    auth = MockAuthService();
    connectivity = MockConnectivityService();
    when(connectivity.isOnline).thenReturn(false); // offline by default
    when(auth.getUserId()).thenAnswer((_) async => me);
    when(auth.getToken()).thenAnswer((_) async => 'jwt');
    epoch = UserSessionEpoch()..activate(me);
  });

  tearDown(() async {
    await isar.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ExerciseRepository repo([LiftedWeightContractMigration? migration]) {
    final api = ApiService(auth, epoch)..testHttpClientAdapter = _NoNetwork();
    return ExerciseRepository(
      api,
      LocalDatabaseService.instance,
      connectivity,
      epoch,
      SessionRequestCoordinator(epoch, auth),
      migration,
    );
  }

  var clock = DateTime.utc(2026, 1, 1);
  DateTime next() => clock = clock.add(const Duration(days: 1));

  Future<int> session({
    int userId = me,
    String status = 'completed',
    DateTime? completedAt,
    int? serverId,
    String syncStatus = 'synced',
  }) async {
    final when_ = completedAt ?? next();
    final s = LocalSession(
      userId: userId,
      date: when_,
      name: 'W',
      type: 'Strength',
      status: status,
      completedAt: status == 'completed' ? when_ : null,
      serverId: serverId,
      syncStatus: syncStatus,
      isSynced: syncStatus == 'synced',
      lastModifiedLocal: when_,
    );
    return isar.writeTxn(() => isar.localSessions.put(s));
  }

  Future<int> exercise(
    int sessionLocalId, {
    int? templateId = 1,
    int sortOrder = 0,
    String syncStatus = 'synced',
    int? targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
  }) {
    final e = LocalExercise(
      sessionLocalId: sessionLocalId,
      name: 'Bench Press',
      sortOrder: sortOrder,
      exerciseTemplateId: templateId,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      syncStatus: syncStatus,
      isSynced: syncStatus == 'synced',
      lastModifiedLocal: clock,
    );
    return isar.writeTxn(() => isar.localExercises.put(e));
  }

  Future<void> sets(int exerciseLocalId, List<(int? reps, double? kg)> rows) =>
      isar.writeTxn(() async {
        for (var i = 0; i < rows.length; i++) {
          await isar.localExerciseSets.put(
            LocalExerciseSet(
              exerciseLocalId: exerciseLocalId,
              setNumber: i + 1,
              reps: rows[i].$1,
              weight: rows[i].$2,
              isCompleted: false,
              isSynced: true,
              syncStatus: 'synced',
              lastModifiedLocal: clock,
            ),
          );
        }
      });

  int publicId(int localId) =>
      ModelMapper.publicRowId(serverId: null, localId: localId);

  Future<List<(int?, double?)>?> lastTime(
    ExerciseRepository r,
    int exerciseLocalId,
  ) async {
    final g = await r.getExerciseGuidance(publicId(exerciseLocalId));
    return g?.previous?.sets.map((s) => (s.reps, s.weight)).toList();
  }

  test(
    'returns the most recent prior completed session, raw kg, setNumber order',
    () async {
      final old = await exercise(await session());
      await sets(old, [(10, 50.0)]);
      final recent = await exercise(await session());
      await sets(recent, [(10, 61.235), (9, 61.235), (8, 61.235)]);
      final current = await exercise(await session(status: 'in_progress'));

      expect(await lastTime(repo(), current), [
        (10, 61.235),
        (9, 61.235),
        (8, 61.235),
      ]);
    },
  );

  test(
    'ignores the current session, non-completed, pending_delete and other users',
    () async {
      final draft = await exercise(await session(status: 'in_progress'));
      await sets(draft, [(5, 100.0)]);
      final deleted = await exercise(
        await session(syncStatus: 'pending_delete'),
      );
      await sets(deleted, [(5, 100.0)]);
      final foreign = await exercise(await session(userId: other));
      await sets(foreign, [(5, 100.0)]);
      final currentSession = await session(status: 'in_progress');
      final current = await exercise(currentSession);
      await sets(current, [(1, 1.0)]);

      expect(await lastTime(repo(), current), isNull);
    },
  );

  test('authenticated-user isolation: another user\'s exercise id resolves to '
      'nothing, not that user\'s history', () async {
    final foreign = await exercise(await session(userId: other));
    await sets(foreign, [(5, 100.0)]);
    final g = await repo().getExerciseGuidance(publicId(foreign));
    expect(g, isNull);
  });

  test('a session invalidated before the call throws SessionStaleException - '
      'never a null/empty result for a stale session', () async {
    final current = await exercise(await session(status: 'in_progress'));
    epoch.invalidate();
    await expectLater(
      repo().getExerciseGuidance(publicId(current)),
      throwsA(isA<SessionStaleException>()),
    );
  });

  test('a completed current session never sees sessions completed after it, '
      'but still sees an older completed session', () async {
    final older = await exercise(await session());
    await sets(older, [(9, 55.0)]);
    final current = await exercise(await session());
    await sets(current, [(8, 60.0)]);
    final later = await exercise(await session());
    await sets(later, [(8, 70.0)]);
    expect(await lastTime(repo(), current), [(9, 55.0)]);
  });

  test('no history -> null previous; targets still returned', () async {
    final current = await exercise(
      await session(status: 'in_progress'),
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 10,
    );
    final g = await repo().getExerciseGuidance(publicId(current));
    expect(g!.previous, isNull);
    expect((g.targetSets, g.targetRepsMin, g.targetRepsMax), (3, 8, 10));
  });

  test('missing template id -> null previous (no name matching)', () async {
    final prior = await exercise(await session(), templateId: null);
    await sets(prior, [(10, 50.0)]);
    final current = await exercise(
      await session(status: 'in_progress'),
      templateId: null,
    );
    expect(await lastTime(repo(), current), isNull);
  });

  test(
    'prior occurrence without logged sets is skipped; older one used',
    () async {
      final older = await exercise(await session());
      await sets(older, [(10, 50.0)]);
      final emptyNewer = await exercise(await session());
      await sets(emptyNewer, [(null, null), (null, 0.0)]);
      final current = await exercise(await session(status: 'in_progress'));
      expect(await lastTime(repo(), current), [(10, 50.0)]);
    },
  );

  test('incomplete prior session returns only its logged sets', () async {
    final prior = await exercise(await session());
    await sets(prior, [(10, 50.0), (null, null)]);
    final current = await exercise(await session(status: 'in_progress'));
    expect(await lastTime(repo(), current), [(10, 50.0)]);
  });

  test('bodyweight: reps with null weight returned unchanged', () async {
    final prior = await exercise(await session());
    await sets(prior, [(12, null), (10, null)]);
    final current = await exercise(await session(status: 'in_progress'));
    expect(await lastTime(repo(), current), [(12, null), (10, null)]);
  });

  group('strict ordinal pairing', () {
    test(
      'current #2, previous session has only #1 -> skipped; older session #2 returned',
      () async {
        final olderSession = await session();
        final o1 = await exercise(olderSession, sortOrder: 0);
        await sets(o1, [(5, 100.0)]);
        final o2 = await exercise(olderSession, sortOrder: 2);
        await sets(o2, [(10, 70.0)]);
        final prev = await exercise(await session(), sortOrder: 0);
        await sets(prev, [(5, 105.0)]);

        final currentSession = await session(status: 'in_progress');
        final c1 = await exercise(currentSession, sortOrder: 0);
        final c2 = await exercise(currentSession, sortOrder: 3);

        expect(await lastTime(repo(), c1), [(5, 105.0)]);
        expect(await lastTime(repo(), c2), [(10, 70.0)]);
      },
    );

    test('no historical #2 -> null for #2, #1 still resolves', () async {
      final prev = await exercise(await session());
      await sets(prev, [(5, 105.0)]);
      final currentSession = await session(status: 'in_progress');
      final c1 = await exercise(currentSession, sortOrder: 0);
      final c2 = await exercise(currentSession, sortOrder: 1);
      expect(await lastTime(repo(), c1), [(5, 105.0)]);
      expect(await lastTime(repo(), c2), isNull);
    });

    test('unlogged #1 does not shift a logged #2 into slot #1', () async {
      final older = await exercise(await session());
      await sets(older, [(5, 90.0)]);
      final priorSession = await session();
      final p1 = await exercise(priorSession, sortOrder: 0);
      await sets(p1, [(null, null)]);
      final p2 = await exercise(priorSession, sortOrder: 1);
      await sets(p2, [(10, 70.0)]);

      final currentSession = await session(status: 'in_progress');
      final c1 = await exercise(currentSession, sortOrder: 0);
      final c2 = await exercise(currentSession, sortOrder: 1);
      expect(await lastTime(repo(), c1), [
        (5, 90.0),
      ]); // prior #1 unlogged -> older #1
      expect(await lastTime(repo(), c2), [(10, 70.0)]);
    });

    test('conflict / pending_delete exercises never occupy a slot; a '
        'pending_delete set is excluded even when it carries values', () async {
      final priorSession = await session();
      final ghost = await exercise(
        priorSession,
        sortOrder: 0,
        syncStatus: 'conflict',
      );
      await sets(ghost, [(1, 1.0)]);
      final deletedExercise = await exercise(
        priorSession,
        sortOrder: 1,
        syncStatus: 'pending_delete',
      );
      await sets(deletedExercise, [(2, 2.0)]);
      final real = await exercise(priorSession, sortOrder: 2);
      await sets(real, [(10, 70.0)]);
      // A pending_delete set WITH values on the real (counted) occurrence
      // must still be excluded from the result - isLoggedSet ignores
      // values entirely once syncStatus is pending_delete.
      await isar.writeTxn(
        () => isar.localExerciseSets.put(
          LocalExerciseSet(
            exerciseLocalId: real,
            setNumber: 2,
            reps: 5,
            weight: 999.0,
            isCompleted: false,
            isSynced: false,
            syncStatus: 'pending_delete',
            lastModifiedLocal: clock,
          ),
        ),
      );
      final current = await exercise(await session(status: 'in_progress'));
      expect(await lastTime(repo(), current), [(10, 70.0)]);
    });
  });

  group('lifted-weight migration gate', () {
    String? state;
    LiftedWeightContractMigration migration() => LiftedWeightContractMigration(
      database: () => isar,
      readState: () async => state,
      writeState: (j) async => state = j,
    );

    setUp(() => state = null);

    test(
      'pending: legacy (below cutoff) and server-backed sessions are excluded',
      () async {
        final legacy = await exercise(await session());
        await sets(legacy, [(10, 100.0)]);
        final m = migration();
        await m
            .snapshotIfNeeded(); // cutoff = current max ids -> everything above is canonical
        final serverBacked = await exercise(await session(serverId: 77));
        await sets(serverBacked, [(10, 110.0)]);
        final current = await exercise(await session(status: 'in_progress'));

        expect(await lastTime(repo(m), current), isNull);

        final canonical = await exercise(
          await session(completedAt: DateTime.utc(2025, 1, 1)),
        );
        await sets(canonical, [(8, 60.0)]);
        expect(await lastTime(repo(m), current), [(8, 60.0)]);
      },
    );

    test('complete: server-backed history is eligible', () async {
      state = '{"status":"complete"}';
      final m = migration();
      await m.snapshotIfNeeded();
      final prior = await exercise(await session(serverId: 77));
      await sets(prior, [(10, 110.0)]);
      final current = await exercise(await session(status: 'in_progress'));
      expect(await lastTime(repo(m), current), [(10, 110.0)]);
    });
  });

  test(
    'works offline and online identically: never touches the network',
    () async {
      final prior = await exercise(await session());
      await sets(prior, [(10, 50.0)]);
      final current = await exercise(await session(status: 'in_progress'));
      when(connectivity.isOnline).thenReturn(true);
      expect(await lastTime(repo(), current), [
        (10, 50.0),
      ]); // _NoNetwork would throw
    },
  );
}

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) =>
      throw StateError(
        'previous performance must never hit the network: ${o.path}',
      );
  @override
  void close({bool force = false}) {}
}
