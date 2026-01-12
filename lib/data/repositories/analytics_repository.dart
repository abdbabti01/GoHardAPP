import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../services/api_service.dart';
import '../models/workout_stats.dart';
import '../local/services/local_database_service.dart';
import '../local/models/local_session.dart';
import '../local/models/local_exercise.dart';
import '../local/models/local_exercise_set.dart';
import '../../core/services/connectivity_service.dart';
import '../services/auth_service.dart';

class AnalyticsRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;
  final AuthService _authService;

  AnalyticsRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._authService,
  );

  /// Get overall workout statistics
  /// Offline-first: calculates from local DB when offline
  Future<WorkoutStats> getWorkoutStats() async {
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          'analytics/stats',
        );
        return WorkoutStats.fromJson(data);
      } catch (e) {
        debugPrint('⚠️ API failed, falling back to local calculation: $e');
        return await _calculateWorkoutStatsFromLocal();
      }
    } else {
      debugPrint('📴 Offline - calculating stats from local database');
      return await _calculateWorkoutStatsFromLocal();
    }
  }

  /// Calculate workout stats from local database
  Future<WorkoutStats> _calculateWorkoutStatsFromLocal() async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('No authenticated user');
    }

    // Get all completed sessions for current user
    final sessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .statusEqualTo('completed')
            .findAll();

    // Sort by date descending
    sessions.sort((a, b) => b.date.compareTo(a.date));

    // Calculate basic stats
    final totalWorkouts = sessions.length;
    int totalDuration = 0;
    int totalSets = 0;
    int totalReps = 0;
    double totalVolume = 0;

    // Calculate weekly/monthly counts
    final now = DateTime.now();
    final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final thisMonthStart = DateTime(now.year, now.month, 1);
    int workoutsThisWeek = 0;
    int workoutsThisMonth = 0;

    for (final session in sessions) {
      // Duration
      if (session.duration != null) {
        totalDuration += session.duration!;
      }

      // Weekly/monthly counts
      if (session.date.isAfter(thisWeekStart)) workoutsThisWeek++;
      if (session.date.isAfter(thisMonthStart)) workoutsThisMonth++;

      // Sets, reps, and volume
      final exercises =
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(session.localId)
              .findAll();

      for (final exercise in exercises) {
        final sets =
            await db.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(exercise.localId)
                .findAll();

        totalSets += sets.length;
        for (final set in sets) {
          if (set.reps != null) totalReps += set.reps!;
          if (set.weight != null && set.reps != null) {
            totalVolume += set.weight! * set.reps!;
          }
        }
      }
    }

    // Calculate streaks
    int currentStreak = 0;
    int longestStreak = 0;
    if (sessions.isNotEmpty) {
      final today = DateTime(now.year, now.month, now.day);
      var checkDate = today;
      int streak = 0;

      for (final session in sessions) {
        final sessionDate = DateTime(
          session.date.year,
          session.date.month,
          session.date.day,
        );

        if (sessionDate == checkDate) {
          streak++;
          if (streak > longestStreak) longestStreak = streak;
          if (currentStreak == 0 || checkDate == today) currentStreak = streak;
          checkDate = checkDate.subtract(const Duration(days: 1));
        } else if (sessionDate.isBefore(checkDate)) {
          // Gap in streak
          if (streak > longestStreak) longestStreak = streak;
          streak = 0;
          checkDate = sessionDate;
        }
      }
    }

    final averageDuration =
        totalWorkouts > 0 ? (totalDuration / totalWorkouts).round() : 0;

    return WorkoutStats(
      totalWorkouts: totalWorkouts,
      totalDuration: totalDuration,
      averageDuration: averageDuration,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      workoutsThisWeek: workoutsThisWeek,
      workoutsThisMonth: workoutsThisMonth,
      totalSets: totalSets,
      totalReps: totalReps,
      totalVolume: totalVolume,
      firstWorkoutDate: sessions.isNotEmpty ? sessions.last.date : null,
      lastWorkoutDate: sessions.isNotEmpty ? sessions.first.date : null,
    );
  }

  /// Get progress for all exercises
  /// Returns empty list when offline (online-only feature)
  Future<List<ExerciseProgress>> getExerciseProgress() async {
    if (!_connectivity.isOnline) {
      debugPrint('📴 Offline - exercise progress unavailable');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        'analytics/exercise-progress',
      );
      return data
          .map(
            (json) => ExerciseProgress.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to load exercise progress: $e');
      return [];
    }
  }

  /// Get progress over time for specific exercise
  /// Returns empty list when offline (online-only feature)
  Future<List<ProgressDataPoint>> getExerciseProgressOverTime(
    int exerciseTemplateId, {
    int days = 90,
  }) async {
    if (!_connectivity.isOnline) {
      debugPrint('📴 Offline - exercise progress over time unavailable');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        'analytics/exercise-progress/$exerciseTemplateId?days=$days',
      );
      return data
          .map(
            (json) => ProgressDataPoint.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to load exercise progress over time: $e');
      return [];
    }
  }

  /// Get muscle group volume distribution
  /// Returns empty list when offline (online-only feature)
  Future<List<MuscleGroupVolume>> getMuscleGroupVolume({int days = 30}) async {
    if (!_connectivity.isOnline) {
      debugPrint('📴 Offline - muscle group volume unavailable');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        'analytics/muscle-group-volume?days=$days',
      );
      return data
          .map(
            (json) => MuscleGroupVolume.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to load muscle group volume: $e');
      return [];
    }
  }

  /// Get all personal records
  /// Offline-first: calculates from local DB when offline
  Future<List<PersonalRecord>> getPersonalRecords() async {
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<List<dynamic>>(
          'analytics/personal-records',
        );
        return data
            .map(
              (json) => PersonalRecord.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      } catch (e) {
        debugPrint('⚠️ API failed, falling back to local calculation: $e');
        return await _calculatePersonalRecordsFromLocal();
      }
    } else {
      debugPrint(
        '📴 Offline - calculating personal records from local database',
      );
      return await _calculatePersonalRecordsFromLocal();
    }
  }

  /// Calculate personal records from local database
  Future<List<PersonalRecord>> _calculatePersonalRecordsFromLocal() async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('No authenticated user');
    }

    // Get all completed sessions
    final sessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .statusEqualTo('completed')
            .findAll();

    // Map to track max weight per exercise template
    final Map<int, PersonalRecord> records = {};

    for (final session in sessions) {
      final exercises =
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(session.localId)
              .findAll();

      for (final exercise in exercises) {
        // Skip exercises without template ID
        if (exercise.exerciseTemplateId == null) continue;

        final sets =
            await db.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(exercise.localId)
                .findAll();

        for (final set in sets) {
          if (set.weight == null || set.weight! <= 0) continue;

          final templateId = exercise.exerciseTemplateId!;
          final currentRecord = records[templateId];

          // Update if this is a new PR
          if (currentRecord == null || set.weight! > currentRecord.weight) {
            // Calculate 1RM using Brzycki formula
            final reps = set.reps ?? 1;
            final oneRepMax =
                reps == 1
                    ? set.weight!
                    : set.weight! / (1.0278 - (0.0278 * reps));

            records[templateId] = PersonalRecord(
              exerciseName: exercise.name,
              exerciseTemplateId: templateId,
              weight: set.weight!,
              reps: reps,
              dateAchieved: session.date,
              estimatedOneRepMax: oneRepMax,
              daysSincePR: DateTime.now().difference(session.date).inDays,
            );
          }
        }
      }
    }

    return records.values.toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
  }

  /// Get volume over time
  /// Offline-first: calculates from local DB when offline
  Future<List<ProgressDataPoint>> getVolumeOverTime({int days = 90}) async {
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<List<dynamic>>(
          'analytics/volume-over-time?days=$days',
        );
        return data
            .map(
              (json) =>
                  ProgressDataPoint.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      } catch (e) {
        debugPrint('⚠️ API failed, falling back to local calculation: $e');
        return await _calculateVolumeOverTimeFromLocal(days: days);
      }
    } else {
      debugPrint(
        '📴 Offline - calculating volume over time from local database',
      );
      return await _calculateVolumeOverTimeFromLocal(days: days);
    }
  }

  /// Calculate volume over time from local database
  Future<List<ProgressDataPoint>> _calculateVolumeOverTimeFromLocal({
    int days = 90,
  }) async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('No authenticated user');
    }

    final startDate = DateTime.now().subtract(Duration(days: days));

    // Get all completed sessions in date range
    final sessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .statusEqualTo('completed')
            .dateBetween(startDate, DateTime.now())
            .sortByDate()
            .findAll();

    final dataPoints = <ProgressDataPoint>[];

    for (final session in sessions) {
      // Get exercises for this session
      final exercises =
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(session.localId)
              .findAll();

      double totalVolume = 0;

      for (final exercise in exercises) {
        final sets =
            await db.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(exercise.localId)
                .findAll();

        for (final set in sets) {
          if (set.weight != null && set.reps != null) {
            totalVolume += set.weight! * set.reps!;
          }
        }
      }

      if (totalVolume > 0) {
        dataPoints.add(
          ProgressDataPoint(
            date: session.date,
            value: totalVolume,
            label: '${totalVolume.toStringAsFixed(0)} kg',
          ),
        );
      }
    }

    return dataPoints;
  }
}
