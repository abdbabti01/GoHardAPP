import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../services/api_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../models/workout_stats.dart';
import '../local/services/local_database_service.dart';
import '../local/models/local_session.dart';
import '../local/models/local_exercise.dart';
import '../local/models/local_exercise_set.dart';

/// Repository for workout analytics with offline-first fallbacks.
///
/// ## Session ownership
///
/// Every public method here reads authenticated, per-account data - all six
/// GET endpoints on the API's `AnalyticsController` carry `[Authorize]` and
/// filter strictly by the JWT user id; none is shared/reference data - and
/// three of them additionally fall back to a local Isar calculation. So each
/// method captures exactly one [SessionRequestContext] via
/// [_sessionCoordinator] at entry, before its first `await`, and:
///
/// - passes `sessionContext:` to every authenticated [ApiService] call, so
///   the request carries the JWT pinned at entry and the generation-scoped
///   `CancelToken` - never a live token, never dispatchable after logout;
/// - uses only `context.epochToken.userId` for local ownership - the live
///   `AuthService.getUserId()` is never read (this repository no longer
///   depends on `AuthService` at all);
/// - rechecks [UserSessionEpoch.isCurrent] after every network/Isar `await`
///   and immediately before returning any server- or locally-computed
///   result, so a value computed for user A can never be returned after
///   user B becomes current;
/// - treats every lifecycle outcome as typed: a `null` capture, a
///   repository-detected post-await staleness, and [ApiService]'s own
///   [SessionStaleException] / [RequestCancelledException] are always
///   (re)thrown - never converted to `[]` / a zero-value [WorkoutStats] /
///   silent success, never routed into the local fallback, never logged as a
///   generic API failure. `AnalyticsProvider`'s session/generation guards
///   drop them without publishing.
///
/// An ordinary network/server failure (not a lifecycle outcome) still uses
/// the existing local fallback, but only while the captured session is still
/// current; the fallback is computed for `context.epochToken.userId` and is
/// discarded (as [SessionStaleException]) if the session changes before it
/// can be returned.
///
/// ## Local ownership chain
///
/// The local calculations resolve owned sessions first
/// (`LocalSession.userId == token.userId`, status `completed`), then walk
/// children through stable local foreign keys
/// (`LocalExercise.sessionLocalId` -> `LocalExerciseSet.exerciseLocalId`).
/// Exercises/sets are only ever read under an already-owned session, so
/// foreign and orphaned child rows are structurally excluded without adding
/// an owner column to [LocalExercise] / [LocalExerciseSet]. This repository
/// performs no local writes.
class AnalyticsRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// `AuthProvider`, `ExerciseRepository`, `SessionRepository`, etc. (see
  /// main.dart). Only `AuthProvider` calls activate()/invalidate(); this
  /// repository only ever reads it via capture()/isCurrent().
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext]
  /// (pinned JWT + generation-scoped CancelToken) for every session-bound
  /// HTTP call. The SAME instance handed to every other consumer; never
  /// constructed privately.
  final SessionRequestCoordinator _sessionCoordinator;

  AnalyticsRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  /// Test-only session-race seam: awaited, if set, immediately before the
  /// post-read epoch recheck that follows the first owned-sessions Isar
  /// query in each local calculation. Lets a test land a logout in the gap
  /// between a local read and its ownership recheck without a real sleep.
  /// Defaults to null in production - control flow / performance unaffected.
  /// Mirrors the analogous hooks on `ExerciseRepository` /
  /// `SessionRepository` / `NutritionRepository`.
  @visibleForTesting
  Future<void> Function()? afterLocalReadForTesting;

  /// Test-only session-race seam: awaited, if set, immediately before the
  /// pre-return ownership recheck at the end of each local calculation. Lets
  /// a test land a logout strictly between the last local read and the
  /// return without a real sleep. Defaults to null in production.
  @visibleForTesting
  Future<void> Function()? beforeReturnForTesting;

  void _ensureCurrent(UserSessionToken token) {
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
  }

  /// Awaits [afterLocalReadForTesting] (a no-op in production) then rechecks
  /// ownership - used right after the first owned-sessions query in each
  /// local calculation.
  Future<void> _guardAfterLocalRead(UserSessionToken token) async {
    final hook = afterLocalReadForTesting;
    if (hook != null) await hook();
    _ensureCurrent(token);
  }

  /// Awaits [beforeReturnForTesting] (a no-op in production) then rechecks
  /// ownership - the terminal recheck before a locally computed aggregate is
  /// returned.
  Future<void> _guardBeforeReturn(UserSessionToken token) async {
    final hook = beforeReturnForTesting;
    if (hook != null) await hook();
    _ensureCurrent(token);
  }

  /// Get overall workout statistics.
  /// Offline-first: calculates from local DB when offline or on an ordinary
  /// API failure while the session is still current.
  Future<WorkoutStats> getWorkoutStats() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;

    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          'analytics/stats',
          sessionContext: context,
        );
        _ensureCurrent(token);
        return WorkoutStats.fromJson(data);
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        // Ordinary transport / server / malformed-response failure while the
        // session is still current: fall back to the owned local calculation.
        _ensureCurrent(token);
        debugPrint('⚠️ API failed, falling back to local calculation: $e');
        return await _calculateWorkoutStatsFromLocal(token);
      }
    }

    debugPrint('📴 Offline - calculating stats from local database');
    return await _calculateWorkoutStatsFromLocal(token);
  }

  /// Calculate workout stats from the local database for [token]'s user.
  Future<WorkoutStats> _calculateWorkoutStatsFromLocal(
    UserSessionToken token,
  ) async {
    final db = _localDb.database;
    final userId = token.userId;

    // Get all completed sessions for the captured user.
    final sessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .statusEqualTo('completed')
            .findAll();
    await _guardAfterLocalRead(token);

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

      // Sets, reps, and volume - children of an already-owned session,
      // reached only through stable local foreign keys.
      final exercises =
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(session.localId)
              .findAll();
      _ensureCurrent(token);

      for (final exercise in exercises) {
        final sets =
            await db.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(exercise.localId)
                .findAll();
        _ensureCurrent(token);

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

    await _guardBeforeReturn(token);
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

  /// Get progress for all exercises.
  /// Returns empty list when offline (online-only feature).
  Future<List<ExerciseProgress>> getExerciseProgress() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;

    if (!_connectivity.isOnline) {
      debugPrint('📴 Offline - exercise progress unavailable');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        'analytics/exercise-progress',
        sessionContext: context,
      );
      _ensureCurrent(token);
      return data
          .map(
            (json) => ExerciseProgress.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      _ensureCurrent(token);
      debugPrint('⚠️ Failed to load exercise progress: $e');
      return [];
    }
  }

  /// Get progress over time for specific exercise.
  /// Returns empty list when offline (online-only feature).
  Future<List<ProgressDataPoint>> getExerciseProgressOverTime(
    int exerciseTemplateId, {
    int days = 90,
  }) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;

    if (!_connectivity.isOnline) {
      debugPrint('📴 Offline - exercise progress over time unavailable');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        'analytics/exercise-progress/$exerciseTemplateId?days=$days',
        sessionContext: context,
      );
      _ensureCurrent(token);
      return data
          .map(
            (json) => ProgressDataPoint.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      _ensureCurrent(token);
      debugPrint('⚠️ Failed to load exercise progress over time: $e');
      return [];
    }
  }

  /// Get muscle group volume distribution.
  /// Returns empty list when offline (online-only feature).
  Future<List<MuscleGroupVolume>> getMuscleGroupVolume({int days = 30}) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;

    if (!_connectivity.isOnline) {
      debugPrint('📴 Offline - muscle group volume unavailable');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        'analytics/muscle-group-volume?days=$days',
        sessionContext: context,
      );
      _ensureCurrent(token);
      return data
          .map(
            (json) => MuscleGroupVolume.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      _ensureCurrent(token);
      debugPrint('⚠️ Failed to load muscle group volume: $e');
      return [];
    }
  }

  /// Get all personal records.
  /// Offline-first: calculates from local DB when offline or on an ordinary
  /// API failure while the session is still current.
  Future<List<PersonalRecord>> getPersonalRecords() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;

    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<List<dynamic>>(
          'analytics/personal-records',
          sessionContext: context,
        );
        _ensureCurrent(token);
        return data
            .map(
              (json) => PersonalRecord.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        // Ordinary transport / server / malformed-response failure while the
        // session is still current: fall back to the owned local calculation.
        _ensureCurrent(token);
        debugPrint('⚠️ API failed, falling back to local calculation: $e');
        return await _calculatePersonalRecordsFromLocal(token);
      }
    }

    debugPrint('📴 Offline - calculating personal records from local database');
    return await _calculatePersonalRecordsFromLocal(token);
  }

  /// Calculate personal records from the local database for [token]'s user.
  Future<List<PersonalRecord>> _calculatePersonalRecordsFromLocal(
    UserSessionToken token,
  ) async {
    final db = _localDb.database;
    final userId = token.userId;

    // Get all completed sessions for the captured user.
    final sessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .statusEqualTo('completed')
            .findAll();
    await _guardAfterLocalRead(token);

    // Map to track max weight per exercise template
    final Map<int, PersonalRecord> records = {};

    for (final session in sessions) {
      final exercises =
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(session.localId)
              .findAll();
      _ensureCurrent(token);

      for (final exercise in exercises) {
        // Skip exercises without template ID
        if (exercise.exerciseTemplateId == null) continue;

        final sets =
            await db.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(exercise.localId)
                .findAll();
        _ensureCurrent(token);

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

    await _guardBeforeReturn(token);
    return records.values.toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
  }

  /// Get volume over time.
  /// Offline-first: calculates from local DB when offline or on an ordinary
  /// API failure while the session is still current.
  Future<List<ProgressDataPoint>> getVolumeOverTime({int days = 90}) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;

    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<List<dynamic>>(
          'analytics/volume-over-time?days=$days',
          sessionContext: context,
        );
        _ensureCurrent(token);
        return data
            .map(
              (json) =>
                  ProgressDataPoint.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        // Ordinary transport / server / malformed-response failure while the
        // session is still current: fall back to the owned local calculation.
        _ensureCurrent(token);
        debugPrint('⚠️ API failed, falling back to local calculation: $e');
        return await _calculateVolumeOverTimeFromLocal(token, days: days);
      }
    }

    debugPrint('📴 Offline - calculating volume over time from local database');
    return await _calculateVolumeOverTimeFromLocal(token, days: days);
  }

  /// Calculate volume over time from the local database for [token]'s user.
  Future<List<ProgressDataPoint>> _calculateVolumeOverTimeFromLocal(
    UserSessionToken token, {
    int days = 90,
  }) async {
    final db = _localDb.database;
    final userId = token.userId;

    final startDate = DateTime.now().subtract(Duration(days: days));

    // Get all completed sessions in date range for the captured user.
    final sessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .statusEqualTo('completed')
            .dateBetween(startDate, DateTime.now())
            .sortByDate()
            .findAll();
    await _guardAfterLocalRead(token);

    final dataPoints = <ProgressDataPoint>[];

    for (final session in sessions) {
      // Get exercises for this session
      final exercises =
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(session.localId)
              .findAll();
      _ensureCurrent(token);

      double totalVolume = 0;

      for (final exercise in exercises) {
        final sets =
            await db.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(exercise.localId)
                .findAll();
        _ensureCurrent(token);

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

    await _guardBeforeReturn(token);
    return dataPoints;
  }
}
