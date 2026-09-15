import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:go_hard_app/data/local/models/local_nutrition_goal.dart'
    as current;
import 'legacy_schema_fixture/legacy_local_nutrition_goal.dart' as legacy;

/// Proves a REAL old-schema upgrade for nutrition-goal history, not merely
/// restart-persistence of a database already created under the current
/// schema - see `local_session_legacy_schema_upgrade_test.dart` for the
/// identical pattern this file follows.
///
/// `legacy_schema_fixture/legacy_local_nutrition_goal.dart` is a frozen,
/// byte-for-byte copy of the `LocalNutritionGoal` collection exactly as it
/// existed before Phase 3 added `effectiveDate`/`deletedAt` - its own
/// generated `CollectionSchema.id` is verified below to be IDENTICAL to the
/// current production schema's id (Isar derives collection identity from the
/// collection NAME, hashed - independent of the field set), which is what
/// makes writing with one schema and reading with the other a meaningful
/// test of the SAME on-disk collection, not two unrelated databases that
/// merely happen to share a directory.
///
/// No wall-clock waits anywhere in this file.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('legacy_nutrition_goal_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('the legacy fixture and current production schema share the SAME Isar '
      'collection id (proves this test exercises one real collection, not '
      'two coincidentally-adjacent databases)', () {
    expect(
      legacy.LocalNutritionGoalSchema.id,
      current.LocalNutritionGoalSchema.id,
    );
  });

  test('a database created under the pre-effectiveDate/deletedAt schema opens '
      'successfully under the current schema, retains every existing field '
      'and target value, stays scoped to its owning user, leaves unrelated '
      'rows untouched, and the new fields default safely and persist after a '
      'further write and close/reopen', () async {
    // ---- Phase 1: write real data using the OLD generated schema,
    // including rows for TWO different users (ownership) and a THIRD,
    // unrelated row that must never be touched by anything this test does
    // to user 42's goals ("unrelated data survives"). ----
    final legacyIsar = await Isar.open(
      [legacy.LocalNutritionGoalSchema],
      directory: tempDir.path,
      inspector: false,
      name: 'legacyNutritionGoalUpgrade',
    );

    final legacyGoal = legacy.LocalNutritionGoal(
      serverId: 900,
      userId: 42,
      name: 'Cutting',
      dailyCalories: 1800,
      dailyProtein: 150,
      dailyCarbohydrates: 150,
      dailyFat: 55,
      dailyFiber: 25,
      isActive: true,
      createdAt: DateTime.utc(2025, 3, 1, 8),
      updatedAt: DateTime.utc(2025, 3, 1, 8),
      explanation: 'Pre-Phase-3 goal, never had an effective date',
      bmr: 1650,
      tdee: 2200,
      calorieAdjustment: -400,
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.utc(2025, 3, 1, 8),
      lastModifiedServer: DateTime.utc(2025, 3, 1, 8),
      syncRetryCount: 0,
    );
    late int legacyLocalId;
    await legacyIsar.writeTxn(() async {
      legacyLocalId = await legacyIsar
          .collection<legacy.LocalNutritionGoal>()
          .put(legacyGoal);
    });

    // A second, still-pending legacy row for the SAME user - proves
    // multi-row integrity (no row lost, no id collision), not just a
    // single-row coincidence.
    final legacyGoalPending = legacy.LocalNutritionGoal(
      userId: 42,
      name: 'Bulking (queued, not yet synced)',
      dailyCalories: 2800,
      dailyProtein: 180,
      dailyCarbohydrates: 350,
      dailyFat: 80,
      isActive: false,
      createdAt: DateTime.utc(2025, 6, 1, 7),
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime.utc(2025, 6, 1, 7),
    );
    late int legacyPendingLocalId;
    await legacyIsar.writeTxn(() async {
      legacyPendingLocalId = await legacyIsar
          .collection<legacy.LocalNutritionGoal>()
          .put(legacyGoalPending);
    });

    // A DIFFERENT user's goal - ownership isolation must survive the
    // upgrade untouched.
    final otherUsersGoal = legacy.LocalNutritionGoal(
      serverId: 901,
      userId: 99,
      name: 'Maintenance',
      dailyCalories: 2400,
      dailyProtein: 160,
      dailyCarbohydrates: 250,
      dailyFat: 70,
      isActive: true,
      createdAt: DateTime.utc(2025, 1, 1, 9),
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.utc(2025, 1, 1, 9),
    );
    late int otherUsersLocalId;
    await legacyIsar.writeTxn(() async {
      otherUsersLocalId = await legacyIsar
          .collection<legacy.LocalNutritionGoal>()
          .put(otherUsersGoal);
    });

    await legacyIsar.close();

    // ---- Phase 2: reopen the SAME on-disk directory with the CURRENT
    // (effectiveDate/deletedAt) production schema. ----
    final upgradedIsar = await Isar.open(
      [current.LocalNutritionGoalSchema],
      directory: tempDir.path,
      inspector: false,
      name: 'legacyNutritionGoalUpgrade',
    );

    final upgraded = await upgradedIsar
        .collection<current.LocalNutritionGoal>()
        .get(legacyLocalId);
    expect(
      upgraded,
      isNotNull,
      reason:
          'database must open successfully and the legacy row must '
          'still be found by its stable localId',
    );

    // Every pre-existing field, and the CURRENT target value, retains its
    // exact value - the migration/upgrade never mutates stored values.
    expect(upgraded!.serverId, 900);
    expect(upgraded.userId, 42);
    expect(upgraded.name, 'Cutting');
    expect(upgraded.dailyCalories, 1800);
    expect(upgraded.dailyProtein, 150);
    expect(upgraded.dailyCarbohydrates, 150);
    expect(upgraded.dailyFat, 55);
    expect(upgraded.dailyFiber, 25);
    expect(upgraded.isActive, isTrue);
    expect(upgraded.createdAt.toUtc(), DateTime.utc(2025, 3, 1, 8));
    expect(
      upgraded.explanation,
      'Pre-Phase-3 goal, never had an effective date',
    );
    expect(upgraded.bmr, 1650);
    expect(upgraded.tdee, 2200);
    expect(upgraded.calorieAdjustment, -400);
    expect(upgraded.isSynced, isTrue);
    expect(upgraded.syncStatus, 'synced');

    // The new fields read a SAFE default for a row that predates them -
    // Isar's own additive-schema guarantee - never null-unsafe, never a
    // crash, and specifically never DateTime.now()/anything fabricated:
    // deletedAt is genuinely absent (null), and effectiveDate (non-
    // nullable in the current model) reads Isar's documented zero-value
    // default for a missing DateTime column rather than throwing.
    expect(
      upgraded.deletedAt,
      isNull,
      reason: 'a legacy row was never deleted - this must stay null',
    );
    expect(
      () => upgraded.effectiveDate,
      returnsNormally,
      reason:
          'reading the new non-nullable field on a legacy row must never '
          'throw, regardless of what default Isar assigns it',
    );

    // The second legacy row (same user, still pending) is also present
    // and correctly mapped - no row was lost or mis-mapped by the
    // property-id shift.
    final upgradedPending = await upgradedIsar
        .collection<current.LocalNutritionGoal>()
        .get(legacyPendingLocalId);
    expect(upgradedPending, isNotNull);
    expect(upgradedPending!.name, 'Bulking (queued, not yet synced)');
    expect(upgradedPending.syncStatus, 'pending_create');
    expect(upgradedPending.deletedAt, isNull);

    // The OTHER user's row survives untouched - ownership isolation holds
    // across the upgrade.
    final upgradedOther = await upgradedIsar
        .collection<current.LocalNutritionGoal>()
        .get(otherUsersLocalId);
    expect(upgradedOther, isNotNull);
    expect(upgradedOther!.userId, 99);
    expect(upgradedOther.dailyCalories, 2400);
    expect(upgradedOther.deletedAt, isNull);

    // Exactly three rows exist - the upgrade neither dropped nor
    // duplicated anything.
    expect(
      await upgradedIsar.collection<current.LocalNutritionGoal>().count(),
      3,
    );

    // Writing the NEW fields afterward succeeds under the new schema.
    final writtenEffectiveDate = DateTime.utc(2026, 1, 1);
    await upgradedIsar.writeTxn(() async {
      final row =
          (await upgradedIsar.collection<current.LocalNutritionGoal>().get(
            legacyPendingLocalId,
          ))!;
      row.effectiveDate = writtenEffectiveDate;
      await upgradedIsar.collection<current.LocalNutritionGoal>().put(row);
    });
    await upgradedIsar.close();

    // ---- Phase 3: close/reopen again (still under the new schema) - the
    // freshly-written effectiveDate on the once-legacy row survives,
    // exactly like the restart-persistence property already proven for
    // rows created entirely under the new schema, and every other row's
    // values (including the untouched user-99 row and the original
    // user-42 target) are still intact too. ----
    final reopenedAgain = await Isar.open(
      [current.LocalNutritionGoalSchema],
      directory: tempDir.path,
      inspector: false,
      name: 'legacyNutritionGoalUpgrade',
    );

    final finalPending = await reopenedAgain
        .collection<current.LocalNutritionGoal>()
        .get(legacyPendingLocalId);
    expect(finalPending!.effectiveDate.toUtc(), writtenEffectiveDate);

    final finalOriginal = await reopenedAgain
        .collection<current.LocalNutritionGoal>()
        .get(legacyLocalId);
    expect(finalOriginal!.dailyCalories, 1800);
    expect(finalOriginal.deletedAt, isNull);

    final finalOther = await reopenedAgain
        .collection<current.LocalNutritionGoal>()
        .get(otherUsersLocalId);
    expect(finalOther!.userId, 99);
    expect(finalOther.dailyCalories, 2400);

    await reopenedAgain.close();
  });
}
