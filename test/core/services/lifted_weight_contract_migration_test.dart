import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:go_hard_app/core/services/lifted_weight_contract_migration.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_program.dart';
import 'package:go_hard_app/data/local/models/local_program_workout.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

/// Task 7: the versioned, one-time legacy workout purge. Real Isar in a temp
/// dir; the secure-storage state is an in-memory string.
void main() {
  late Isar isar;
  late Directory tempDir;
  String? state;
  late int writeCount;
  late bool failNextWrite;
  late LiftedWeightContractMigration migration;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lifted_weight_purge_');
    isar = await Isar.open(
      [
        LocalSessionSchema,
        LocalExerciseSchema,
        LocalExerciseSetSchema,
        LocalProgramSchema,
        LocalProgramWorkoutSchema,
      ],
      directory: tempDir.path,
      inspector: false,
    );
    state = null;
    writeCount = 0;
    failNextWrite = false;
    migration = LiftedWeightContractMigration(
      database: () => isar,
      readState: () async => state,
      writeState: (json) async {
        if (failNextWrite) {
          failNextWrite = false;
          throw Exception('simulated crash before state write');
        }
        writeCount++;
        state = json;
      },
    );
  });

  tearDown(() async {
    if (isar.isOpen) await isar.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final now = DateTime.utc(2026, 9, 1);

  Future<LocalSession> session({int? serverId, String sync = 'synced'}) async {
    final row = LocalSession(
      serverId: serverId,
      userId: 1,
      date: now,
      isSynced: sync == 'synced',
      syncStatus: sync,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localSessions.put(row));
    return row;
  }

  Future<LocalExercise> exercise(
    int sessionLocalId, {
    int? serverId,
    String sync = 'synced',
  }) async {
    final row = LocalExercise(
      serverId: serverId,
      sessionLocalId: sessionLocalId,
      name: 'Bench',
      isSynced: sync == 'synced',
      syncStatus: sync,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localExercises.put(row));
    return row;
  }

  Future<LocalExerciseSet> set(
    int exerciseLocalId, {
    int? serverId,
    String sync = 'synced',
    double? weight = 100,
  }) async {
    final row = LocalExerciseSet(
      serverId: serverId,
      exerciseLocalId: exerciseLocalId,
      setNumber: 1,
      weight: weight,
      isSynced: sync == 'synced',
      syncStatus: sync,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localExerciseSets.put(row));
    return row;
  }

  Future<LocalProgram> program({int? serverId, String sync = 'synced'}) async {
    final row = LocalProgram(
      serverId: serverId,
      userId: 1,
      title: 'P',
      totalWeeks: 4,
      currentWeek: 1,
      currentDay: 1,
      startDate: now,
      createdAt: now,
      isSynced: sync == 'synced',
      syncStatus: sync,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localPrograms.put(row));
    return row;
  }

  Future<LocalProgramWorkout> programWorkout(
    int programLocalId, {
    int? serverId,
    String sync = 'synced',
  }) async {
    final row = LocalProgramWorkout(
      serverId: serverId,
      programLocalId: programLocalId,
      weekNumber: 1,
      dayNumber: 1,
      workoutName: 'W',
      exercisesJson: '[]',
      orderIndex: 0,
      isSynced: sync == 'synced',
      syncStatus: sync,
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localProgramWorkouts.put(row));
    return row;
  }

  Map<String, dynamic> decoded() => jsonDecode(state!) as Map<String, dynamic>;

  Future<List<int>> ids<T>(IsarCollection<T> c, int Function(T) id) async =>
      (await c.where().findAll()).map(id).toList();

  Future<void> seedLegacy() async {
    final s1 = await session(serverId: 10);
    final e1 = await exercise(s1.localId, serverId: 20);
    await set(e1.localId, serverId: 30);
    final s2 = await session(sync: 'pending_create');
    final e2 = await exercise(s2.localId, sync: 'pending_create');
    await set(e2.localId, sync: 'pending_update', serverId: 31);
    await set(e2.localId, sync: 'pending_delete');
    final p1 = await program(serverId: 40);
    await programWorkout(p1.localId, serverId: 50);
    final p2 = await program(sync: 'pending_create');
    await programWorkout(p2.localId, sync: 'pending_create');
  }

  test('snapshotIfNeeded records max localIds once; later calls and a '
      'complete state are never changed', () async {
    await seedLegacy();
    await migration.snapshotIfNeeded();

    expect(decoded(), {
      'status': 'pending',
      'cutoffs': {
        'sessions': 2,
        'exercises': 2,
        'sets': 3,
        'programs': 2,
        'programWorkouts': 2,
      },
    });
    final first = state;

    await session();
    await migration.snapshotIfNeeded();
    expect(state, first);
    expect(writeCount, 1);

    state = jsonEncode({...decoded(), 'status': 'complete'});
    final complete = state;
    await migration.snapshotIfNeeded();
    expect(state, complete);
    expect(writeCount, 1);
  });

  test('fresh install (empty DB) snapshots zero cutoffs', () async {
    await migration.snapshotIfNeeded();
    expect(decoded(), {
      'status': 'pending',
      'cutoffs': {
        'sessions': 0,
        'exercises': 0,
        'sets': 0,
        'programs': 0,
        'programWorkouts': 0,
      },
    });
    expect(await migration.isComplete(), isFalse);
  });

  test(
    'fetch -> false: returns false, deletes nothing, stays pending',
    () async {
      await seedLegacy();
      await migration.snapshotIfNeeded();

      expect(await migration.ensureMigrated(() async => false), isFalse);

      expect(await isar.localSessions.count(), 2);
      expect(await isar.localExerciseSets.count(), 3);
      expect(await isar.localPrograms.count(), 2);
      expect(decoded()['status'], 'pending');
      expect(await migration.isComplete(), isFalse);
    },
  );

  test('fetch throws: returns false, deletes nothing, stays pending', () async {
    await seedLegacy();
    await migration.snapshotIfNeeded();

    expect(
      await migration.ensureMigrated(() async => throw Exception('offline')),
      isFalse,
    );

    expect(await isar.localSessions.count(), 2);
    expect(await isar.localExerciseSets.count(), 3);
    expect(decoded()['status'], 'pending');
  });

  test('fetch throwing a session-lifecycle exception propagates unchanged '
      '(the sync pass aborts exactly as other phases would)', () async {
    await migration.snapshotIfNeeded();

    await expectLater(
      migration.ensureMigrated(() async => throw const SessionStaleException()),
      throwsA(isA<SessionStaleException>()),
    );
    await expectLater(
      migration.ensureMigrated(
        () async => throw const RequestCancelledException(),
      ),
      throwsA(isA<RequestCancelledException>()),
    );
    expect(decoded()['status'], 'pending');
  });

  test('no snapshot state: stays gated without calling fetch', () async {
    var called = false;
    expect(await migration.ensureMigrated(() async => called = true), isFalse);
    expect(called, isFalse);
    expect(state, isNull);
  });

  group('canonical server history', () {
    late LocalSession keptSession;
    late LocalExercise keptExercise;
    late LocalExerciseSet keptSet;
    late LocalProgram keptProgram;
    late LocalProgramWorkout keptProgramWorkout;

    Future<void> seedAndSnapshotThenGatedActivity() async {
      await seedLegacy();
      await migration.snapshotIfNeeded();

      // Created after the snapshot, while gated:
      // - an unsynced canonical chain (kept, weight preserved exactly)
      keptSession = await session(sync: 'pending_create');
      keptExercise = await exercise(
        keptSession.localId,
        sync: 'pending_create',
      );
      keptSet = await set(
        keptExercise.localId,
        sync: 'pending_create',
        weight: 61.23496995,
      );
      keptProgram = await program(sync: 'pending_create');
      keptProgramWorkout = await programWorkout(
        keptProgram.localId,
        sync: 'pending_create',
      );
      // - server-backed rows downloaded from the not-yet-reset server
      //   (purged regardless of localId), plus their unsynced children
      final downloaded = await session(serverId: 11);
      final downloadedEx = await exercise(downloaded.localId, serverId: 21);
      await set(downloadedEx.localId, sync: 'pending_create');
      await exercise(downloaded.localId, sync: 'pending_create');
      final downloadedProgram = await program(serverId: 41);
      await programWorkout(downloadedProgram.localId, sync: 'pending_create');
      // - an unsynced set added to a legacy (pre-snapshot) exercise
      await set(1, sync: 'pending_create');
    }

    Future<void> expectOnlyCanonicalRowsRemain() async {
      expect(await ids(isar.localSessions, (r) => r.localId), [
        keptSession.localId,
      ]);
      expect(await ids(isar.localExercises, (r) => r.localId), [
        keptExercise.localId,
      ]);
      expect(await ids(isar.localExerciseSets, (r) => r.localId), [
        keptSet.localId,
      ]);
      expect(await ids(isar.localPrograms, (r) => r.localId), [
        keptProgram.localId,
      ]);
      expect(await ids(isar.localProgramWorkouts, (r) => r.localId), [
        keptProgramWorkout.localId,
      ]);
      final stored = await isar.localExerciseSets.get(keptSet.localId);
      expect(stored!.weight, 61.23496995);
      expect(stored.syncStatus, 'pending_create');
    }

    test(
      'fetch -> true purges legacy + server-backed rows and their '
      'descendants, keeps the post-snapshot unsynced chain, completes',
      () async {
        await seedAndSnapshotThenGatedActivity();

        expect(await migration.ensureMigrated(() async => true), isTrue);

        await expectOnlyCanonicalRowsRemain();
        expect(decoded()['status'], 'complete');
        expect(decoded()['cutoffs'], isA<Map<String, dynamic>>());
        expect(await migration.isComplete(), isTrue);
      },
    );

    test('interrupted after the Isar purge but before the state write: next '
        'call re-purges idempotently and completes', () async {
      await seedAndSnapshotThenGatedActivity();

      failNextWrite = true;
      expect(await migration.ensureMigrated(() async => true), isFalse);
      await expectOnlyCanonicalRowsRemain();
      expect(decoded()['status'], 'pending');

      expect(await migration.ensureMigrated(() async => true), isTrue);
      await expectOnlyCanonicalRowsRemain();
      expect(decoded()['status'], 'complete');
    });

    test('complete is terminal: later server-backed rows are never purged '
        'and fetch is not called', () async {
      await seedAndSnapshotThenGatedActivity();
      expect(await migration.ensureMigrated(() async => true), isTrue);

      final redownloaded = await session(serverId: 12);
      await exercise(redownloaded.localId, serverId: 22);
      await program(serverId: 42);

      var fetchCalls = 0;
      expect(
        await migration.ensureMigrated(() async {
          fetchCalls++;
          return true;
        }),
        isTrue,
      );
      // Simulated restart: a fresh instance over the same state.
      final restarted = LiftedWeightContractMigration(
        database: () => isar,
        readState: () async => state,
        writeState: (json) async => state = json,
      );
      await restarted.snapshotIfNeeded();
      expect(
        await restarted.ensureMigrated(() async {
          fetchCalls++;
          return true;
        }),
        isTrue,
      );

      expect(fetchCalls, 0);
      expect(await isar.localSessions.count(), 2);
      expect(await isar.localExercises.count(), 2);
      expect(await isar.localPrograms.count(), 2);
      expect(decoded()['status'], 'complete');
    });
  });
}
