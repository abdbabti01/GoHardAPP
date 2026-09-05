import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:go_hard_app/data/local/models/local_session.dart' as current;
import 'legacy_schema_fixture/legacy_local_session.dart' as legacy;

/// Proves a REAL old-schema upgrade, not merely restart-persistence of a
/// database already created under the current schema.
///
/// `legacy/legacy_local_session.dart` is a frozen, byte-for-byte copy of the
/// `LocalSession` collection exactly as committed at this branch's base
/// commit, BEFORE `clientOperationId` existed - its own generated
/// `CollectionSchema.id` is verified below to be IDENTICAL to the current
/// production schema's id (Isar derives collection identity from the
/// collection NAME, hashed - it is independent of the field set), which is
/// what makes writing with one schema and reading with the other a
/// meaningful test of the SAME on-disk collection rather than two unrelated
/// databases that merely happen to share a directory.
///
/// No wall-clock waits anywhere in this file.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('legacy_schema_upgrade_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('the legacy fixture and current production schema share the SAME Isar '
      'collection id (proves this test exercises one real collection, not '
      'two coincidentally-adjacent databases)', () {
    expect(legacy.LocalSessionSchema.id, current.LocalSessionSchema.id);
  });

  test('a database created under the pre-clientOperationId schema opens '
      'successfully under the current schema, retains every field, reads '
      'clientOperationId==null on the legacy row, and a key written '
      'afterward survives a further close/reopen', () async {
    // ---- Phase 1: write real data using the OLD generated schema. ----
    final legacyIsar = await Isar.open(
      [legacy.LocalSessionSchema],
      directory: tempDir.path,
      inspector: false,
      name: 'legacyUpgrade',
    );

    final legacyRow = legacy.LocalSession(
      serverId: 555,
      userId: 42,
      date: DateTime(2025, 6, 15),
      duration: 3600,
      notes: 'Pre-existing note from before this field existed',
      type: 'strength',
      name: 'Leg Day (legacy)',
      status: 'completed',
      startedAt: DateTime.utc(2025, 6, 15, 8),
      completedAt: DateTime.utc(2025, 6, 15, 9),
      pausedAt: null,
      programId: 7,
      programWorkoutId: 21,
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.utc(2025, 6, 15, 9, 1),
      lastModifiedServer: DateTime.utc(2025, 6, 15, 9, 1),
      syncRetryCount: 0,
      lastSyncAttempt: null,
      syncError: null,
      version: 3,
      conflictServerSnapshotJson: null,
      conflictServerVersion: null,
      conflictDetectedAt: null,
    );
    late int legacyLocalId;
    await legacyIsar.writeTxn(() async {
      legacyLocalId = await legacyIsar.collection<legacy.LocalSession>().put(
        legacyRow,
      );
    });

    // A second legacy row, so the upgrade test also proves multi-row
    // integrity (no row lost, no id collision) - not just a single-row
    // coincidence.
    final legacyRow2 = legacy.LocalSession(
      serverId: null,
      userId: 42,
      date: DateTime(2025, 6, 16),
      name: 'Pull Day (legacy, still pending)',
      status: 'draft',
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime.utc(2025, 6, 16, 7),
    );
    late int legacyLocalId2;
    await legacyIsar.writeTxn(() async {
      legacyLocalId2 = await legacyIsar.collection<legacy.LocalSession>().put(
        legacyRow2,
      );
    });

    await legacyIsar.close();

    // ---- Phase 2: reopen the SAME on-disk directory with the CURRENT
    // (with clientOperationId) production schema. ----
    final upgradedIsar = await Isar.open(
      [current.LocalSessionSchema],
      directory: tempDir.path,
      inspector: false,
      name: 'legacyUpgrade',
    );

    final upgraded = await upgradedIsar.collection<current.LocalSession>().get(
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
    expect(upgraded!.serverId, 555);
    expect(upgraded.userId, 42);
    expect(upgraded.date, DateTime(2025, 6, 15));
    expect(upgraded.duration, 3600);
    expect(upgraded.notes, 'Pre-existing note from before this field existed');
    expect(upgraded.type, 'strength');
    expect(upgraded.name, 'Leg Day (legacy)');
    expect(upgraded.status, 'completed');
    // Isar returns DateTime fields as local-flagged, but the absolute
    // instant is preserved correctly (see the identical, already-documented
    // behavior in model_mapper.dart's toUtcTimestamp) - .toUtc() relabels
    // without shifting the instant, so this compares the true instant, not
    // the ambient label.
    expect(upgraded.startedAt!.toUtc(), DateTime.utc(2025, 6, 15, 8));
    expect(upgraded.completedAt!.toUtc(), DateTime.utc(2025, 6, 15, 9));
    expect(upgraded.pausedAt, isNull);
    // Child-link fields (program linkage) retain their exact values.
    expect(upgraded.programId, 7);
    expect(upgraded.programWorkoutId, 21);
    expect(upgraded.isSynced, isTrue);
    expect(upgraded.syncStatus, 'synced');
    expect(upgraded.lastModifiedLocal.toUtc(), DateTime.utc(2025, 6, 15, 9, 1));
    expect(
      upgraded.lastModifiedServer!.toUtc(),
      DateTime.utc(2025, 6, 15, 9, 1),
    );
    expect(upgraded.syncRetryCount, 0);
    expect(upgraded.version, 3);

    // The new field reads null for a row that predates it.
    expect(upgraded.clientOperationId, isNull);

    // The second legacy row is also present and correctly mapped - no
    // row was lost or mis-mapped by the property-id shift.
    final upgraded2 = await upgradedIsar.collection<current.LocalSession>().get(
      legacyLocalId2,
    );
    expect(upgraded2, isNotNull);
    expect(upgraded2!.name, 'Pull Day (legacy, still pending)');
    expect(upgraded2.syncStatus, 'pending_create');
    expect(upgraded2.clientOperationId, isNull);
    expect(upgraded2.localId, isNot(upgraded.localId));

    // Exactly two rows exist - the upgrade neither dropped nor duplicated
    // anything.
    expect(await upgradedIsar.collection<current.LocalSession>().count(), 2);

    // Writing a key afterward succeeds under the new schema.
    await upgradedIsar.writeTxn(() async {
      final row =
          (await upgradedIsar.collection<current.LocalSession>().get(
            legacyLocalId2,
          ))!;
      row.clientOperationId = 'upgraded-legacy-row-key';
      await upgradedIsar.collection<current.LocalSession>().put(row);
    });
    await upgradedIsar.close();

    // ---- Phase 3: close/reopen again (still under the new schema) - the
    // freshly-written key on the once-legacy row survives, exactly like
    // the restart-persistence property already proven for rows created
    // entirely under the new schema. ----
    final reopenedAgain = await Isar.open(
      [current.LocalSessionSchema],
      directory: tempDir.path,
      inspector: false,
      name: 'legacyUpgrade',
    );
    final finalRow = await reopenedAgain.collection<current.LocalSession>().get(
      legacyLocalId2,
    );
    expect(finalRow!.clientOperationId, 'upgraded-legacy-row-key');
    // The untouched legacy row's field values are still intact too.
    final finalRow1 = await reopenedAgain
        .collection<current.LocalSession>()
        .get(legacyLocalId);
    expect(finalRow1!.serverId, 555);
    expect(finalRow1.clientOperationId, isNull);

    await reopenedAgain.close();
  });
}
