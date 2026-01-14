import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../data/local/models/local_session.dart';
import '../../data/local/models/local_exercise.dart';
import '../../data/local/models/local_exercise_set.dart';

/// Utility class for cleaning up corrupted database records
class DatabaseCleanup {
  /// Delete all sessions that have failed sync attempts
  /// and don't exist on the server (404 errors)
  static Future<void> cleanupFailedSessions(Isar db) async {
    debugPrint('🧹 Starting database cleanup...');

    try {
      // Get all sessions with sync errors (retry count >= 3)
      final failedSessions =
          await db.localSessions
              .filter()
              .syncRetryCountGreaterThan(2)
              .findAll();

      if (failedSessions.isEmpty) {
        debugPrint('✅ No failed sessions to clean up');
        return;
      }

      debugPrint(
        '🗑️ Found ${failedSessions.length} failed sessions to delete',
      );

      // Delete each failed session and its exercises
      for (final session in failedSessions) {
        await db.writeTxn(() async {
          // Delete exercises for this session
          final exercises =
              await db.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(session.localId)
                  .findAll();

          for (final exercise in exercises) {
            // Delete sets for this exercise
            await db.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(exercise.localId)
                .deleteAll();
          }

          // Delete exercises
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(session.localId)
              .deleteAll();

          // Delete session
          await db.localSessions.delete(session.localId);

          debugPrint(
            '  🗑️ Deleted session ${session.serverId ?? session.localId} with ${exercises.length} exercises',
          );
        });
      }

      debugPrint('✅ Cleanup completed');
    } catch (e) {
      debugPrint('❌ Cleanup failed: $e');
    }
  }

  /// Delete duplicate draft/planned program workouts
  /// Keeps only the most recent draft/planned session for each programWorkoutId
  static Future<void> cleanupDuplicateProgramWorkouts(Isar db) async {
    debugPrint('🧹 Cleaning up duplicate program workouts...');

    try {
      // Get all draft and planned sessions with programWorkoutId
      final draftSessions =
          await db.localSessions
              .filter()
              .statusEqualTo('draft')
              .or()
              .statusEqualTo('planned')
              .findAll();

      // Group by programWorkoutId
      final Map<int, List<LocalSession>> groupedSessions = {};
      for (final session in draftSessions) {
        if (session.programWorkoutId != null) {
          groupedSessions.putIfAbsent(session.programWorkoutId!, () => []);
          groupedSessions[session.programWorkoutId!]!.add(session);
        }
      }

      int deletedCount = 0;

      // For each group with duplicates, keep only the most recent
      for (final entry in groupedSessions.entries) {
        final sessions = entry.value;
        if (sessions.length > 1) {
          // Sort by lastModifiedLocal (most recent first)
          sessions.sort(
            (a, b) => b.lastModifiedLocal.compareTo(a.lastModifiedLocal),
          );

          // Keep the first (most recent), delete the rest
          final toDelete = sessions.skip(1).toList();

          for (final session in toDelete) {
            await db.writeTxn(() async {
              // Delete exercises and sets
              final exercises =
                  await db.localExercises
                      .filter()
                      .sessionLocalIdEqualTo(session.localId)
                      .findAll();

              for (final exercise in exercises) {
                await db.localExerciseSets
                    .filter()
                    .exerciseLocalIdEqualTo(exercise.localId)
                    .deleteAll();
              }

              await db.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(session.localId)
                  .deleteAll();

              await db.localSessions.delete(session.localId);

              deletedCount++;
              debugPrint(
                '  🗑️ Deleted duplicate ${session.status} session for program workout ${session.programWorkoutId}',
              );
            });
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint(
          '✅ Cleanup completed: deleted $deletedCount duplicate sessions',
        );
      } else {
        debugPrint('✅ No duplicate program workouts found');
      }
    } catch (e) {
      debugPrint('❌ Duplicate cleanup failed: $e');
    }
  }

  /// Delete ALL local data (nuclear option for fresh start)
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
