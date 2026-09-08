import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:go_hard_app/data/local/models/local_exercise.dart' as current;
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'legacy_schema_fixture/legacy_local_exercise.dart' as legacy;

/// Proves a REAL old-schema upgrade, not merely restart-persistence of a
/// database already created under the current schema.
///
/// `legacy_schema_fixture/legacy_local_exercise.dart` is a frozen,
/// byte-for-byte copy of the `LocalExercise` collection exactly as committed
/// at this branch's base commit, BEFORE `occurrenceKey` existed - its own
/// generated `CollectionSchema.id` is verified below to be IDENTICAL to the
/// current production schema's id (Isar derives collection identity from the
/// collection NAME, hashed - it is independent of the field set), which is
/// what makes writing with one schema and reading with the other a
/// meaningful test of the SAME on-disk collection rather than two unrelated
/// databases that merely happen to share a directory.
///
/// `LocalExerciseSet` is untouched by this schema change - it is opened
/// under its own current (unmodified) schema in BOTH phases, so this test
/// also proves a legacy Exercise's already-recorded Sets survive the parent
/// collection's upgrade intact (Task 2's "existing rows must survive with
/// their data and Sets intact" requirement).
///
/// No wall-clock waits anywhere in this file.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'legacy_exercise_schema_upgrade_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('the legacy fixture and current production schema share the SAME '
      'Isar collection id (proves this test exercises one real collection, '
      'not two coincidentally-adjacent databases)', () {
    expect(legacy.LocalExerciseSchema.id, current.LocalExerciseSchema.id);
  });

  test('a database created under the pre-occurrenceKey schema opens '
      'successfully under the current schema, retains every field and its '
      'child Sets, reads occurrenceKey==null on the legacy row, and a key '
      'written afterward survives a further close/reopen', () async {
    // ---- Phase 1: write real data using the OLD generated schema. ----
    final legacyIsar = await Isar.open(
      [legacy.LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
      name: 'legacyExerciseUpgrade',
    );

    final legacyRow = legacy.LocalExercise(
      serverId: 900,
      sessionLocalId: 1,
      sessionServerId: 100,
      name: 'Bench Press (legacy)',
      sortOrder: 0,
      duration: null,
      restTime: 90,
      notes: 'Pre-existing note from before occurrenceKey existed',
      exerciseTemplateId: 12,
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.utc(2025, 6, 15, 9),
      lastModifiedServer: DateTime.utc(2025, 6, 15, 9),
      syncRetryCount: 0,
      lastSyncAttempt: null,
      syncError: null,
    );
    late int legacyLocalId;
    await legacyIsar.writeTxn(() async {
      legacyLocalId = await legacyIsar.collection<legacy.LocalExercise>().put(
        legacyRow,
      );
    });

    // A second legacy row - proves multi-row integrity across the upgrade,
    // not just a single-row coincidence, and that a duplicate
    // `exerciseTemplateId` (legitimate before occurrenceKey existed) is
    // preserved as-is rather than altered by the upgrade.
    final legacyRow2 = legacy.LocalExercise(
      serverId: 901,
      sessionLocalId: 1,
      sessionServerId: 100,
      name: 'Bench Press (legacy, second occurrence)',
      sortOrder: 1,
      exerciseTemplateId: 12,
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.utc(2025, 6, 15, 9, 1),
      lastModifiedServer: DateTime.utc(2025, 6, 15, 9, 1),
    );
    late int legacyLocalId2;
    await legacyIsar.writeTxn(() async {
      legacyLocalId2 = await legacyIsar.collection<legacy.LocalExercise>().put(
        legacyRow2,
      );
    });

    // The first legacy exercise already has a recorded Set - proves the
    // parent's schema upgrade never touches or loses child Set data.
    final legacySet = LocalExerciseSet(
      serverId: 5000,
      exerciseLocalId: legacyLocalId,
      exerciseServerId: 900,
      setNumber: 1,
      reps: 8,
      weight: 60,
      isCompleted: true,
      completedAt: DateTime.utc(2025, 6, 15, 9),
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.utc(2025, 6, 15, 9),
      lastModifiedServer: DateTime.utc(2025, 6, 15, 9),
    );
    late int legacySetLocalId;
    await legacyIsar.writeTxn(() async {
      legacySetLocalId = await legacyIsar.collection<LocalExerciseSet>().put(
        legacySet,
      );
    });

    await legacyIsar.close();

    // ---- Phase 2: reopen the SAME on-disk directory with the CURRENT
    // (with occurrenceKey) production schema for LocalExercise, and the
    // unmodified current schema for LocalExerciseSet. ----
    final upgradedIsar = await Isar.open(
      [current.LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
      name: 'legacyExerciseUpgrade',
    );

    final upgraded = await upgradedIsar.collection<current.LocalExercise>().get(
      legacyLocalId,
    );
    expect(
      upgraded,
      isNotNull,
      reason:
          'database must open successfully '
          'and the legacy row must still be found by its stable localId',
    );

    // Every pre-existing field retains its exact value.
    expect(upgraded!.serverId, 900);
    expect(upgraded.sessionLocalId, 1);
    expect(upgraded.sessionServerId, 100);
    expect(upgraded.name, 'Bench Press (legacy)');
    expect(upgraded.sortOrder, 0);
    expect(upgraded.duration, isNull);
    expect(upgraded.restTime, 90);
    expect(
      upgraded.notes,
      'Pre-existing note from before occurrenceKey existed',
    );
    expect(upgraded.exerciseTemplateId, 12);
    expect(upgraded.isSynced, isTrue);
    expect(upgraded.syncStatus, 'synced');
    expect(upgraded.lastModifiedLocal.toUtc(), DateTime.utc(2025, 6, 15, 9));

    // The new field reads null for a row that predates it.
    expect(upgraded.occurrenceKey, isNull);

    // The second legacy row is also present, still sharing the same
    // exerciseTemplateId (legitimate pre-occurrenceKey duplication) - the
    // upgrade does not invent or collapse anything.
    final upgraded2 = await upgradedIsar
        .collection<current.LocalExercise>()
        .get(legacyLocalId2);
    expect(upgraded2, isNotNull);
    expect(upgraded2!.name, 'Bench Press (legacy, second occurrence)');
    expect(upgraded2.exerciseTemplateId, 12);
    expect(upgraded2.occurrenceKey, isNull);
    expect(upgraded2.localId, isNot(upgraded.localId));

    // Exactly two rows exist - the upgrade neither dropped nor duplicated
    // anything.
    expect(await upgradedIsar.collection<current.LocalExercise>().count(), 2);

    // The child Set survives the parent's schema upgrade fully intact.
    final upgradedSet = await upgradedIsar.collection<LocalExerciseSet>().get(
      legacySetLocalId,
    );
    expect(upgradedSet, isNotNull);
    expect(upgradedSet!.exerciseLocalId, legacyLocalId);
    expect(upgradedSet.serverId, 5000);
    expect(upgradedSet.reps, 8);
    expect(upgradedSet.weight, 60);
    expect(upgradedSet.isCompleted, isTrue);
    expect(upgradedSet.syncStatus, 'synced');

    // Writing an occurrenceKey afterward succeeds under the new schema.
    await upgradedIsar.writeTxn(() async {
      final row =
          (await upgradedIsar.collection<current.LocalExercise>().get(
            legacyLocalId2,
          ))!;
      row.occurrenceKey = 'upgraded-legacy-row-key';
      await upgradedIsar.collection<current.LocalExercise>().put(row);
    });
    await upgradedIsar.close();

    // ---- Phase 3: close/reopen again (still under the new schema) - the
    // freshly-written key on the once-legacy row survives, exactly like the
    // restart-persistence property already proven for rows created entirely
    // under the new schema, and the untouched legacy row + its Set are still
    // intact. ----
    final reopenedAgain = await Isar.open(
      [current.LocalExerciseSchema, LocalExerciseSetSchema],
      directory: tempDir.path,
      inspector: false,
      name: 'legacyExerciseUpgrade',
    );
    final finalRow = await reopenedAgain
        .collection<current.LocalExercise>()
        .get(legacyLocalId2);
    expect(finalRow!.occurrenceKey, 'upgraded-legacy-row-key');

    final finalRow1 = await reopenedAgain
        .collection<current.LocalExercise>()
        .get(legacyLocalId);
    expect(finalRow1!.serverId, 900);
    expect(finalRow1.occurrenceKey, isNull);

    final finalSet = await reopenedAgain.collection<LocalExerciseSet>().get(
      legacySetLocalId,
    );
    expect(finalSet!.exerciseLocalId, legacyLocalId);
    expect(finalSet.reps, 8);

    await reopenedAgain.close();
  });
}
