import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../models/run_session.dart';
import '../models/gps_point.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../local/services/local_database_service.dart';
import '../local/models/local_run_session.dart';

/// Repository for running session operations with offline-first support and server sync
class RunningRepository {
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;
  final AuthService _authService;
  final ApiService _apiService;

  RunningRepository(
    this._localDb,
    this._connectivity,
    this._authService,
    this._apiService,
  );

  /// Get all run sessions for the current user
  /// Offline-first: returns cached data immediately, syncs in background
  Future<List<RunSession>> getRunSessions() async {
    final Isar db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      debugPrint('\u26a0\ufe0f No authenticated user, returning empty list');
      return [];
    }

    // Return cached data first
    final localRuns =
        await db.localRunSessions
            .filter()
            .userIdEqualTo(userId)
            .sortByDateDesc()
            .findAll();

    // Background sync if online
    if (_connectivity.isOnline) {
      _syncFromServer().catchError((e) => debugPrint('Sync error: $e'));
    }

    return localRuns.map((local) => _localToRunSession(local)).toList();
  }

  /// Get recent run sessions (last N runs)
  Future<List<RunSession>> getRecentRuns({int limit = 5}) async {
    final Isar db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) return [];

    // Try to sync first if online
    if (_connectivity.isOnline) {
      await _syncFromServer().catchError((e) => debugPrint('Sync error: $e'));
    }

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

    final now = DateTime.now().toUtc();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDate = DateTime.utc(
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
      date: DateTime.now().toUtc(),
      status: 'draft',
      lastModifiedLocal: DateTime.now().toUtc(),
    );

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });

    // Try to sync to server immediately if online
    if (_connectivity.isOnline) {
      _syncRunToServer(localRun).catchError((e) {
        debugPrint('Failed to sync new run to server: $e');
      });
    }

    debugPrint('\ud83c\udfc3 Created new run session: ${localRun.localId}');
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

    // Sync to server
    if (_connectivity.isOnline) {
      _syncRunToServer(localRun).catchError((e) {
        debugPrint('Failed to sync run start to server: $e');
      });
    }

    debugPrint('\ud83c\udfc3 Run started: ${localRun.localId}');
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
    localRun.lastModifiedLocal = DateTime.now().toUtc();
    localRun.syncStatus = 'pending_update';
    localRun.isSynced = false;

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });

    debugPrint('\u23f8\ufe0f Run paused: ${localRun.localId}');
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
    localRun.lastModifiedLocal = DateTime.now().toUtc();
    localRun.syncStatus = 'pending_update';
    localRun.isSynced = false;

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });

    debugPrint('\u25b6\ufe0f Run resumed: ${localRun.localId}');
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

    // Sync completed run to server
    if (_connectivity.isOnline) {
      _syncRunToServer(localRun).catchError((e) {
        debugPrint('Failed to sync completed run to server: $e');
      });
    }

    debugPrint(
      '\ud83c\udfc1 Run completed: ${localRun.localId} - ${distance.toStringAsFixed(2)} km in ${duration}s',
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
    localRun.lastModifiedLocal = DateTime.now().toUtc();

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
    localRun.lastModifiedLocal = DateTime.now().toUtc();

    await db.writeTxn(() async {
      await db.localRunSessions.put(localRun);
    });
  }

  /// Delete a run session
  Future<bool> deleteRun(int localId) async {
    final Isar db = _localDb.database;
    final localRun = await db.localRunSessions.get(localId);

    if (localRun != null &&
        localRun.serverId != null &&
        _connectivity.isOnline) {
      // Delete from server first
      try {
        await _apiService.delete(ApiConfig.runSessionById(localRun.serverId!));
      } catch (e) {
        debugPrint('Failed to delete run from server: $e');
      }
    }

    await db.writeTxn(() async {
      await db.localRunSessions.delete(localId);
    });

    debugPrint('\ud83d\uddd1\ufe0f Run deleted: $localId');
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

  /// Sync runs from server to local database
  Future<void> _syncFromServer() async {
    final userId = await _authService.getUserId();
    if (userId == null) return;

    try {
      final response = await _apiService.get(ApiConfig.runSessions);
      if (response == null) return;

      final List<dynamic> serverRuns = response as List<dynamic>;
      final Isar db = _localDb.database;

      for (final serverRunJson in serverRuns) {
        final serverRun = serverRunJson as Map<String, dynamic>;
        final serverId = serverRun['id'] as int;

        // Check if we already have this run locally
        final existingLocal =
            await db.localRunSessions
                .filter()
                .serverIdEqualTo(serverId)
                .findFirst();

        if (existingLocal != null) {
          // Update existing local run with server data
          _updateLocalFromServer(existingLocal, serverRun);
          await db.writeTxn(() async {
            await db.localRunSessions.put(existingLocal);
          });
        } else {
          // Create new local run from server data
          final newLocal = _serverToLocal(serverRun, userId);
          await db.writeTxn(() async {
            await db.localRunSessions.put(newLocal);
          });
        }
      }

      debugPrint('\ud83d\udd04 Synced ${serverRuns.length} runs from server');
    } catch (e) {
      debugPrint('Error syncing from server: $e');
    }
  }

  /// Sync a local run to server
  Future<void> _syncRunToServer(LocalRunSession localRun) async {
    try {
      final routeJson =
          localRun.route.isNotEmpty
              ? jsonEncode(
                localRun.route
                    .map(
                      (p) => {
                        'latitude': p.latitude,
                        'longitude': p.longitude,
                        'altitude': p.altitude,
                        'timestamp': p.timestamp?.toIso8601String(),
                        'speed': p.speed,
                        'accuracy': p.accuracy,
                      },
                    )
                    .toList(),
              )
              : null;

      final data = {
        'userId': localRun.userId,
        'name': localRun.name,
        'date': localRun.date.toIso8601String(),
        'distance': localRun.distance,
        'duration': localRun.duration,
        'averagePace': localRun.averagePace,
        'calories': localRun.calories,
        'status': localRun.status,
        'startedAt': localRun.startedAt?.toIso8601String(),
        'completedAt': localRun.completedAt?.toIso8601String(),
        'pausedAt': localRun.pausedAt?.toIso8601String(),
        'routeJson': routeJson,
      };

      if (localRun.serverId == null) {
        // Create on server
        final response = await _apiService.post(
          ApiConfig.runSessions,
          data: data,
        );
        if (response != null) {
          final Isar db = _localDb.database;
          localRun.serverId = response['id'] as int;
          localRun.isSynced = true;
          localRun.syncStatus = 'synced';
          await db.writeTxn(() async {
            await db.localRunSessions.put(localRun);
          });
          debugPrint(
            '\u2705 Run synced to server with id: ${localRun.serverId}',
          );
        }
      } else {
        // Update on server
        await _apiService.put(
          ApiConfig.runSessionById(localRun.serverId!),
          data: {'id': localRun.serverId, ...data},
        );
        final Isar db = _localDb.database;
        localRun.isSynced = true;
        localRun.syncStatus = 'synced';
        await db.writeTxn(() async {
          await db.localRunSessions.put(localRun);
        });
        debugPrint('\u2705 Run updated on server: ${localRun.serverId}');
      }
    } catch (e) {
      debugPrint('Error syncing run to server: $e');
      rethrow;
    }
  }

  /// Convert server JSON to LocalRunSession
  LocalRunSession _serverToLocal(Map<String, dynamic> json, int userId) {
    List<LocalGpsPoint> route = [];
    if (json['routeJson'] != null && json['routeJson'].toString().isNotEmpty) {
      try {
        final routeList = jsonDecode(json['routeJson']) as List<dynamic>;
        route =
            routeList
                .map(
                  (p) => LocalGpsPoint.create(
                    latitude: (p['latitude'] as num).toDouble(),
                    longitude: (p['longitude'] as num).toDouble(),
                    altitude:
                        p['altitude'] != null
                            ? (p['altitude'] as num).toDouble()
                            : null,
                    timestamp:
                        p['timestamp'] != null
                            ? DateTime.parse(p['timestamp'])
                            : null,
                    speed:
                        p['speed'] != null
                            ? (p['speed'] as num).toDouble()
                            : null,
                    accuracy:
                        p['accuracy'] != null
                            ? (p['accuracy'] as num).toDouble()
                            : null,
                  ),
                )
                .toList();
      } catch (e) {
        debugPrint('Error parsing route JSON: $e');
      }
    }

    return LocalRunSession.create(
      serverId: json['id'] as int,
      userId: userId,
      name: json['name'] as String?,
      date: DateTime.parse(json['date']),
      distance:
          json['distance'] != null
              ? (json['distance'] as num).toDouble()
              : null,
      duration: json['duration'] as int?,
      averagePace:
          json['averagePace'] != null
              ? (json['averagePace'] as num).toDouble()
              : null,
      calories: json['calories'] as int?,
      status: json['status'] as String? ?? 'draft',
      startedAt:
          json['startedAt'] != null ? DateTime.parse(json['startedAt']) : null,
      completedAt:
          json['completedAt'] != null
              ? DateTime.parse(json['completedAt'])
              : null,
      pausedAt:
          json['pausedAt'] != null ? DateTime.parse(json['pausedAt']) : null,
      route: route,
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: DateTime.now().toUtc(),
    );
  }

  /// Update local run from server data
  void _updateLocalFromServer(
    LocalRunSession local,
    Map<String, dynamic> json,
  ) {
    // Only update if local is already synced (don't overwrite pending changes)
    if (local.syncStatus != 'synced') return;

    local.name = json['name'] as String?;
    local.date = DateTime.parse(json['date']);
    local.distance =
        json['distance'] != null ? (json['distance'] as num).toDouble() : null;
    local.duration = json['duration'] as int?;
    local.averagePace =
        json['averagePace'] != null
            ? (json['averagePace'] as num).toDouble()
            : null;
    local.calories = json['calories'] as int?;
    local.status = json['status'] as String? ?? 'draft';
    local.startedAt =
        json['startedAt'] != null ? DateTime.parse(json['startedAt']) : null;
    local.completedAt =
        json['completedAt'] != null
            ? DateTime.parse(json['completedAt'])
            : null;
    local.pausedAt =
        json['pausedAt'] != null ? DateTime.parse(json['pausedAt']) : null;

    if (json['routeJson'] != null && json['routeJson'].toString().isNotEmpty) {
      try {
        final routeList = jsonDecode(json['routeJson']) as List<dynamic>;
        local.route =
            routeList
                .map(
                  (p) => LocalGpsPoint.create(
                    latitude: (p['latitude'] as num).toDouble(),
                    longitude: (p['longitude'] as num).toDouble(),
                    altitude:
                        p['altitude'] != null
                            ? (p['altitude'] as num).toDouble()
                            : null,
                    timestamp:
                        p['timestamp'] != null
                            ? DateTime.parse(p['timestamp'])
                            : null,
                    speed:
                        p['speed'] != null
                            ? (p['speed'] as num).toDouble()
                            : null,
                    accuracy:
                        p['accuracy'] != null
                            ? (p['accuracy'] as num).toDouble()
                            : null,
                  ),
                )
                .toList();
      } catch (e) {
        debugPrint('Error parsing route JSON: $e');
      }
    }
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
