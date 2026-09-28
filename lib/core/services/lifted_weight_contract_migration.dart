import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import '../../data/local/models/local_exercise.dart';
import '../../data/local/models/local_exercise_set.dart';
import '../../data/local/models/local_program.dart';
import '../../data/local/models/local_program_workout.dart';
import '../../data/local/models/local_session.dart';
import '../../data/services/rate_limited_exception.dart';
import '../../data/services/session_request_exceptions.dart';

/// One-time purge of legacy local workout data at the legacy -> canonical-kg
/// lifted-weight transition (spec §7).
///
/// Builds before canonical kg stored set weights typed under an "lbs" label
/// with no conversion. This build sends `X-Lifted-Weight-Unit: kg` on every
/// request, so a pending legacy row uploaded by it would be silently accepted
/// as kg. Therefore:
///
/// 1. [snapshotIfNeeded] (startup, before `runApp`, offline) records the max
///    Isar `localId` of sessions / exercises / sets / programs /
///    programWorkouts once, as `status: pending`. Rows at or below a cutoff
///    predate this build.
/// 2. While pending, `SyncService` skips the five workout upload phases
///    (other phases run), and `SessionRepository` / `ExerciseRepository`
///    withhold their direct online workout write uploads
///    ([workoutUploadsAllowed] is false), leaving those rows pending exactly
///    as if offline. Local logging keeps working in kg.
/// 3. [ensureMigrated], at sync-pass start, asks the server whether its
///    history has been reset to canonical kg. Only on `true` it deletes, in
///    one Isar transaction, every row at or below its cutoff (including
///    pending creates/updates/deletes), every row with a server identity
///    (nothing canonical can have been uploaded while gated, so any
///    server-backed row is legacy or will be re-downloaded from the reset
///    server), and every descendant of a deleted parent - then writes
///    `status: complete`.
///
/// **Owner decision: unsynced legacy workout history is intentionally
/// discarded at the legacy -> canonical-kg transition.** This runs once
/// (versioned key [storageKey]; `complete` is terminal and never cleared by
/// logout) and is NOT a generic "clear workouts on startup". A crash between
/// the Isar commit and the state write simply repeats the (idempotent) purge
/// on the next pass.
///
/// `LocalSession.programId` / `programWorkoutId` hold SERVER ids (sent
/// verbatim to `POST sessions/from-program-workout`), never program localIds,
/// so surviving sessions keep no dangling reference to purged program rows.
class LiftedWeightContractMigration {
  LiftedWeightContractMigration({
    required Isar Function() database,
    required Future<String?> Function() readState,
    required Future<void> Function(String json) writeState,
  }) : _database = database,
       _readState = readState,
       _writeState = writeState;

  static const storageKey = 'lifted_weight_contract_v1';

  final Isar Function() _database;
  final Future<String?> Function() _readState;
  final Future<void> Function(String json) _writeState;

  bool _workoutUploadsAllowed = false;

  /// Synchronous gate for the repositories' direct (online, non-SyncService)
  /// workout write uploads: `false` until the purge has completed, `true`
  /// once the state is `complete` (read by [snapshotIfNeeded] at startup,
  /// set by [ensureMigrated]). A gated repository keeps the row pending
  /// locally exactly as if offline; `SyncService` uploads it after the purge.
  bool get workoutUploadsAllowed => _workoutUploadsAllowed;

  /// Startup, offline-safe. Records cutoffs once (as `pending`); a `complete`
  /// state is never modified (beyond initialising [workoutUploadsAllowed]
  /// from it). Must run with no workout writes in flight (before `runApp`,
  /// or right after `LocalDatabaseService.clearAll`).
  ///
  /// **Isar reuses localIds**: its id counter is `max(existing id) + 1` when
  /// the database is opened, so after the top rows are deleted (user delete,
  /// download reconciliation) and the app restarts, or after `clear()` /
  /// an iOS reinstall that wipes Isar but keeps this Keychain state, new
  /// canonical rows can get ids at or below a stored cutoff and would be
  /// purged as legacy. So while `pending`, each cutoff is tightened to
  /// `min(storedCutoff, currentMaxLocalId)` and persisted. This is correct:
  /// rows created after the snapshot always receive ids above the stored
  /// cutoff (the counter cannot drop below existing rows), so if any such
  /// row exists the current max is not below the cutoff and nothing
  /// changes; if the max did drop below the cutoff, every surviving row is
  /// at or below it and is therefore legacy.
  ///
  /// Never throws: a failure leaves no state, which keeps workouts gated
  /// ([ensureMigrated] returns false) until a later startup snapshots.
  Future<void> snapshotIfNeeded() async {
    try {
      final existing = await _readJson();
      if (existing != null && existing['status'] == 'complete') {
        _workoutUploadsAllowed = true;
        return;
      }
      _workoutUploadsAllowed = false;
      final current = await _maxLocalIds();
      if (existing == null) {
        await _writeState(
          jsonEncode({'status': 'pending', 'cutoffs': current}),
        );
        return;
      }
      final stored = Map<String, dynamic>.from(existing['cutoffs'] as Map);
      final tightened = {
        for (final e in current.entries)
          e.key: e.value < (stored[e.key] as int) ? e.value : stored[e.key],
      };
      if (tightened.entries.any((e) => e.value != stored[e.key])) {
        await _writeState(jsonEncode({...existing, 'cutoffs': tightened}));
      }
    } catch (e) {
      debugPrint('⚠️ Lifted-weight snapshot failed (workouts stay gated): $e');
    }
  }

  /// True once the purge has completed (terminal).
  Future<bool> isComplete() async =>
      (await _readJson())?['status'] == 'complete';

  /// Call at sync-pass start. If pending: asks [fetchCanonicalHistory];
  /// purges and returns true only when it reports true. Never throws for a
  /// failed/negative check (returns false, stays pending) - except the
  /// session-lifecycle [SessionStaleException] / [RequestCancelledException]
  /// and [RateLimitedException], which propagate so the sync pass aborts
  /// (and arms its cooldown) exactly as any phase would.
  Future<bool> ensureMigrated(
    Future<bool> Function() fetchCanonicalHistory,
  ) async {
    try {
      final state = await _readJson();
      if (state == null) return false;
      if (state['status'] != 'complete') {
        if (!await fetchCanonicalHistory()) return false;
        await _purge(Map<String, dynamic>.from(state['cutoffs'] as Map));
        await _writeState(jsonEncode({...state, 'status': 'complete'}));
      }
      return _workoutUploadsAllowed = true;
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } on RateLimitedException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Lifted-weight migration not completed (stays gated): $e');
      return false;
    }
  }

  Future<Map<String, int>> _maxLocalIds() async {
    final db = _database();
    return {
      'sessions':
          await db.localSessions
              .where(sort: Sort.desc)
              .anyLocalId()
              .localIdProperty()
              .findFirst() ??
          0,
      'exercises':
          await db.localExercises
              .where(sort: Sort.desc)
              .anyLocalId()
              .localIdProperty()
              .findFirst() ??
          0,
      'sets':
          await db.localExerciseSets
              .where(sort: Sort.desc)
              .anyLocalId()
              .localIdProperty()
              .findFirst() ??
          0,
      'programs':
          await db.localPrograms
              .where(sort: Sort.desc)
              .anyLocalId()
              .localIdProperty()
              .findFirst() ??
          0,
      'programWorkouts':
          await db.localProgramWorkouts
              .where(sort: Sort.desc)
              .anyLocalId()
              .localIdProperty()
              .findFirst() ??
          0,
    };
  }

  Future<Map<String, dynamic>?> _readJson() async {
    final raw = await _readState();
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  // ponytail: loads each collection fully once; fine for a one-time purge.
  Future<void> _purge(Map<String, dynamic> c) async {
    final db = _database();
    await db.writeTxn(() async {
      bool legacy(int localId, int? serverId, String key) =>
          localId <= (c[key] as int) || serverId != null;

      final sessions = {
        for (final r in await db.localSessions.where().findAll())
          if (legacy(r.localId, r.serverId, 'sessions')) r.localId,
      };
      final exercises = {
        for (final r in await db.localExercises.where().findAll())
          if (legacy(r.localId, r.serverId, 'exercises') ||
              sessions.contains(r.sessionLocalId))
            r.localId,
      };
      final sets = [
        for (final r in await db.localExerciseSets.where().findAll())
          if (legacy(r.localId, r.serverId, 'sets') ||
              exercises.contains(r.exerciseLocalId))
            r.localId,
      ];
      final programs = {
        for (final r in await db.localPrograms.where().findAll())
          if (legacy(r.localId, r.serverId, 'programs')) r.localId,
      };
      final programWorkouts = [
        for (final r in await db.localProgramWorkouts.where().findAll())
          if (legacy(r.localId, r.serverId, 'programWorkouts') ||
              programs.contains(r.programLocalId))
            r.localId,
      ];

      await db.localSessions.deleteAll(sessions.toList());
      await db.localExercises.deleteAll(exercises.toList());
      await db.localExerciseSets.deleteAll(sets);
      await db.localPrograms.deleteAll(programs.toList());
      await db.localProgramWorkouts.deleteAll(programWorkouts);
    });
  }
}
