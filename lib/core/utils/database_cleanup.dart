import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../data/local/models/local_session.dart';
import '../../data/local/models/local_exercise.dart';
import '../../data/local/models/local_exercise_set.dart';

/// Local-database maintenance helpers.
///
/// NOTE: this class intentionally holds NO routine "cleanup" pass. A Session
/// (and its Exercises / ExerciseSets) is never deleted because a sync retry
/// counter crossed a threshold, because it looks like a duplicate draft, or by
/// any pre-authentication scan. Sync failures are transient; `syncRetryCount`
/// is diagnostic only. Deletion happens only on an authoritative path - a
/// successful server DELETE or an explicit authenticated user action - which
/// runs owner-scoped after auth (see `SyncService` / `SessionRepository`).
class DatabaseCleanup {
  /// Delete ALL local data (nuclear option for a fresh start). Unconditional,
  /// not wired into startup, and NOT a per-row cleanup - a full wipe only.
  static Future<void> clearAllData(Isar db) async {
    debugPrint('🧹 Clearing ALL local data...');

    try {
      await db.writeTxn(() async {
        await db.localExerciseSets.clear();
        await db.localExercises.clear();
        await db.localSessions.clear();
        // Don't clear exercise templates as they're static data
      });

      debugPrint('✅ All data cleared');
    } catch (e) {
      debugPrint('❌ Clear failed: $e');
    }
  }
}
