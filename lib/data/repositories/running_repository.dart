import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/services/connectivity_service.dart';
import '../models/run_session.dart';
import '../models/gps_point.dart';
import '../services/auth_service.dart';
import '../local/services/local_database_service.dart';
import '../local/models/local_run_session.dart';

/// Repository for running session operations with offline-first support
/// Local-only storage for MVP - server sync can be added later
class RunningRepository {
  final LocalDatabaseService _localDb;
  // ignore: unused_field - Reserved for future sync functionality
  final ConnectivityService _connectivity;
  final AuthService _authService;

  RunningRepository(this._localDb, this._connectivity, this._authService);

  /// Get all run sessions for the current user
  Future<List<RunSession>> getRunSessions() async {
    final Isar db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      debugPrint('⚠️ No authenticated user, returning empty list');
      return [];
    }

    final localRuns =
        await db.localRunSessions
            .filter()
            .userIdEqualTo(userId)
            .sortByDateDesc()
            .findAll();

    return localRuns.map((local) => _localToRunSession(local)).toList();
  }

  /// Get recent run sessions (last N runs)
  Future<List<RunSession>> getRecentRuns({int limit = 5}) async {
    final Isar db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) return [];

    final localRuns =
        await db.localRunSessions
            .filter()
            .userIdEqualTo(userId)
            .statusEqualTo('completed')
            .sortByDateDesc()
            .limit(limit)
            .findAll();

    return localRuns.map((local) => _localToRunSession(local)).toList();
  }

  /// Get run sessions for this week
  Future<List<RunSession>> getThisWeekRuns() async {
    final Isar db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) return [];

    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );

    final localRuns =
        await db.localRunSessions
            .filter()
            .userIdEqualTo(userId)
            .statusEqualTo('completed')
            .dateGreaterThan(weekStartDate.subtract(const Duration(seconds: 1)))
            .findAll();

    return localRuns.map((local) => _localToRunSession(local)).toList();
  }

  /// Get a single run session by ID
  Future<RunSession?> getRunSession(int localId) async {
    final Isar db = _localDb.database;
    final localRun = await db.localRunSessions.get(localId);

    if (localRun == null) return null;
    return _localToRunSession(localRun);
  }

  /// Create a new run session
  Future<RunSession> createRunSession() async {
    final Isar db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('No authenticated user');
    }

    final localRun = LocalRunSession.create(
      userId: userId,
      date: DateTime.now(),
      status: 'draft',
      lastModifiedLocal: DateTime.now(),
    );

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });

    debugPrint('🏃 Created new run session: ${localRun.localId}');
    return _localToRunSession(localRun);
  }

  /// Start a run (update status to in_progress)
  Future<RunSession> startRun(int localId) async {
    final Isar db = _localDb.database;
    final localRun = await db.localRunSessions.get(localId);

    if (localRun == null) {
      throw Exception('Run session not found');
    }

    final now = DateTime.now().toUtc();
    localRun.status = 'in_progress';
    localRun.startedAt = now;
    localRun.lastModifiedLocal = now;
    localRun.syncStatus = 'pending_update';
    localRun.isSynced = false;

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });

    debugPrint('🏃 Run started: ${localRun.localId}');
    return _localToRunSession(localRun);
  }

  /// Pause a run
  Future<RunSession> pauseRun(int localId, DateTime pausedAt) async {
    final Isar db = _localDb.database;
    final localRun = await db.localRunSessions.get(localId);

    if (localRun == null) {
      throw Exception('Run session not found');
    }

    localRun.pausedAt = pausedAt;
    localRun.lastModifiedLocal = DateTime.now();
    localRun.syncStatus = 'pending_update';
    localRun.isSynced = false;

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });

    debugPrint('⏸️ Run paused: ${localRun.localId}');
    return _localToRunSession(localRun);
  }

  /// Resume a run
  Future<RunSession> resumeRun(int localId, DateTime newStartedAt) async {
    final Isar db = _localDb.database;
    final localRun = await db.localRunSessions.get(localId);

    if (localRun == null) {
      throw Exception('Run session not found');
    }

    localRun.startedAt = newStartedAt;
    localRun.pausedAt = null;
    localRun.lastModifiedLocal = DateTime.now();
    localRun.syncStatus = 'pending_update';
    localRun.isSynced = false;

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });

    debugPrint('▶️ Run resumed: ${localRun.localId}');
    return _localToRunSession(localRun);
  }

  /// Complete a run
  Future<RunSession> completeRun(
    int localId, {
    required int duration,
    required double distance,
    double? averagePace,
    int? calories,
    List<GpsPoint>? route,
  }) async {
    final Isar db = _localDb.database;
    final localRun = await db.localRunSessions.get(localId);

    if (localRun == null) {
      throw Exception('Run session not found');
    }

    final now = DateTime.now().toUtc();
    localRun.status = 'completed';
    localRun.completedAt = now;
    localRun.duration = duration;
    localRun.distance = distance;
    localRun.averagePace = averagePace;
    localRun.calories = calories;
    localRun.pausedAt = null;
    localRun.lastModifiedLocal = now;
    localRun.syncStatus = 'pending_update';
    localRun.isSynced = false;

    // Store route if provided
    if (route != null) {
      localRun.route =
          route
              .map(
                (gp) => LocalGpsPoint.create(
                  latitude: gp.latitude,
                  longitude: gp.longitude,
                  altitude: gp.altitude,
                  timestamp: gp.timestamp,
                  speed: gp.speed,
                  accuracy: gp.accuracy,
                ),
              )
              .toList();
    }

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });

    debugPrint(
      '🏁 Run completed: ${localRun.localId} - ${distance.toStringAsFixed(2)} km in ${duration}s',
    );
    return _localToRunSession(localRun);
  }

  /// Update GPS route during run
  Future<void> updateRoute(int localId, List<GpsPoint> route) async {
    final Isar db = _localDb.database;
    final localRun = await db.localRunSessions.get(localId);

    if (localRun == null) return;

    localRun.route =
        route
            .map(
              (gp) => LocalGpsPoint.create(
                latitude: gp.latitude,
                longitude: gp.longitude,
                altitude: gp.altitude,
                timestamp: gp.timestamp,
                speed: gp.speed,
                accuracy: gp.accuracy,
              ),
            )
            .toList();
    localRun.lastModifiedLocal = DateTime.now();

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });
  }

  /// Update distance during run
  Future<void> updateDistance(int localId, double distance) async {
    final Isar db = _localDb.database;
    final localRun = await db.localRunSessions.get(localId);

    if (localRun == null) return;

    localRun.distance = distance;
    localRun.lastModifiedLocal = DateTime.now();

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });
  }

  /// Delete a run session
  Future<bool> deleteRun(int localId) async {
    final Isar db = _localDb.database;

    await db.writeTxn(() async {
      await db.localRunSessions.delete(localId);
    });

    debugPrint('🗑️ Run deleted: $localId');
    return true;
  }

  /// Calculate weekly stats
  Future<Map<String, dynamic>> getWeeklyStats() async {
    final runs = await getThisWeekRuns();

    double totalDistance = 0;
    int totalDuration = 0;

    for (final run in runs) {
      totalDistance += run.distance ?? 0;
      totalDuration += run.duration ?? 0;
    }

    return {
      'runCount': runs.length,
      'totalDistance': totalDistance,
      'totalDuration': totalDuration,
    };
  }

  /// Convert LocalRunSession to RunSession
  RunSession _localToRunSession(LocalRunSession local) {
    return RunSession(
      id: local.localId,
      userId: local.userId,
      name: local.name,
      date: local.date,
      distance: local.distance,
      duration: local.duration,
      averagePace: local.averagePace,
      calories: local.calories,
      status: local.status,
      startedAt: local.startedAt,
      completedAt: local.completedAt,
      pausedAt: local.pausedAt,
      route:
          local.route
              .map(
                (lp) => GpsPoint(
                  latitude: lp.latitude,
                  longitude: lp.longitude,
                  altitude: lp.altitude,
                  timestamp: lp.timestamp ?? DateTime.now(),
                  speed: lp.speed,
                  accuracy: lp.accuracy,
                ),
              )
              .toList(),
    );
  }
}
