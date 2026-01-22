import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_service.dart';
import '../../data/local/services/local_database_service.dart';
import '../../data/local/models/local_session.dart';
import '../../data/local/models/local_exercise.dart';
import '../../data/local/models/local_exercise_set.dart';
import '../../data/local/models/local_program.dart';
import '../../data/local/models/local_goal.dart';
import '../../data/local/models/local_program_workout.dart';
import '../../core/constants/api_config.dart';
import 'connectivity_service.dart';

/// Service for automatic background synchronization of offline data
class SyncService {
  static SyncService? _instance;
  final ApiService _apiService;
  final AuthService _authService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;

  Timer? _periodicSyncTimer;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isSyncing = false;
  bool _isInitialized = false;

  // Sync configuration
  static const Duration _syncInterval = Duration(minutes: 5);
  static const int _maxRetries = 3;
  static const Duration _syncDebounce = Duration(seconds: 3);

  Timer? _debounceTimer;

  /// Private constructor for singleton pattern
  SyncService._(
    this._apiService,
    this._authService,
    this._localDb,
    this._connectivity,
  );

  /// Factory constructor to create/get singleton instance
  factory SyncService({
    required ApiService apiService,
    required AuthService authService,
    required LocalDatabaseService localDb,
    required ConnectivityService connectivity,
  }) {
    _instance ??= SyncService._(apiService, authService, localDb, connectivity);
    return _instance!;
  }

  /// Get singleton instance (must be initialized first)
  static SyncService get instance {
    if (_instance == null) {
      throw Exception(
        'SyncService not initialized. Call factory constructor first.',
      );
    }
    return _instance!;
  }

  /// Initialize sync service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.connectivityStream.listen((
      isOnline,
    ) {
      if (isOnline) {
        debugPrint('🔄 Network connected - scheduling sync');
        _scheduleDebouncedSync();
      } else {
        debugPrint('📴 Network disconnected - canceling sync');
        _cancelDebouncedSync();
      }
    });

    // Start periodic sync timer (only syncs when online)
    _periodicSyncTimer = Timer.periodic(_syncInterval, (_) {
      if (_connectivity.isOnline && !_isSyncing) {
        debugPrint('⏰ Periodic sync triggered');
        sync();
      }
    });

    _isInitialized = true;
    debugPrint('✅ SyncService initialized');

    // Run initial sync if online
    if (_connectivity.isOnline) {
      _scheduleDebouncedSync();
    }
  }

  /// Schedule a debounced sync (prevents rapid sync attempts during network flapping)
  void _scheduleDebouncedSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_syncDebounce, () {
      if (_connectivity.isOnline && !_isSyncing) {
        sync();
      }
    });
  }

  /// Cancel pending debounced sync
  void _cancelDebouncedSync() {
    _debounceTimer?.cancel();
  }

  /// Manually trigger sync (public API)
  Future<void> sync() async {
    if (_isSyncing) {
      debugPrint('⏭️ Sync already in progress, skipping');
      return;
    }

    if (!_connectivity.isOnline) {
      debugPrint('📴 Offline, skipping sync');
      return;
    }

    _isSyncing = true;
    debugPrint('🔄 Starting sync...');

    try {
      final db = _localDb.database;

      // Sync in order: Sessions → Exercises → Sets → Programs → Goals → ProgramWorkouts
      await _syncSessions(db);
      await _syncExercises(db);
      await _syncExerciseSets(db);
      await _syncPrograms(db);
      await _syncGoals(db);
      await _syncProgramWorkouts(db);

      debugPrint('✅ Sync completed successfully');
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync all pending sessions
  Future<void> _syncSessions(Isar db) async {
    // Get current user ID
    final userId = await _authService.getUserId();
    if (userId == null) {
      debugPrint('  ⚠️ No authenticated user, skipping session sync');
      return;
    }

    // Only sync sessions belonging to current user
    final pendingSessions =
        await db.localSessions
            .filter()
            .isSyncedEqualTo(false)
            .userIdEqualTo(userId)
            .findAll();

    if (pendingSessions.isEmpty) {
      debugPrint('  No pending sessions to sync');
      return;
    }

    debugPrint('  Syncing ${pendingSessions.length} sessions...');

    for (final session in pendingSessions) {
      try {
        switch (session.syncStatus) {
          case 'pending_create':
            await _syncCreateSession(db, session);
            break;
          case 'pending_update':
            await _syncUpdateSession(db, session);
            break;
          case 'pending_delete':
            await _syncDeleteSession(db, session);
            break;
          default:
            debugPrint('  Unknown sync status: ${session.syncStatus}');
        }
      } catch (e) {
        await _markSyncError(db, session, e.toString());
      }
    }
  }

  /// Sync a session that needs to be created on the server
  Future<void> _syncCreateSession(Isar db, LocalSession localSession) async {
    debugPrint('  Creating session ${localSession.localId} on server...');

    try {
      // POST to server
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.sessions,
        data: {
          'userId': localSession.userId,
          'date': localSession.date.toIso8601String(),
          'duration': localSession.duration,
          'notes': localSession.notes,
          'type': localSession.type,
          'name': localSession.name,
          'status': localSession.status,
          'startedAt': localSession.startedAt?.toIso8601String(),
          'completedAt': localSession.completedAt?.toIso8601String(),
          'pausedAt': localSession.pausedAt?.toIso8601String(),
        },
      );

      // Update local session with server ID
      await db.writeTxn(() async {
        localSession.serverId = response['id'] as int;
        localSession.isSynced = true;
        localSession.syncStatus = 'synced';
        localSession.lastModifiedServer = DateTime.parse(
          response['date'] as String,
        );
        localSession.syncRetryCount = 0;
        localSession.syncError = null;
        localSession.lastSyncAttempt = DateTime.now();
        await db.localSessions.put(localSession);
      });

      debugPrint(
        '  ✅ Session created with server ID: ${localSession.serverId}',
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Sync a session that needs to be updated on the server
  Future<void> _syncUpdateSession(Isar db, LocalSession localSession) async {
    if (localSession.serverId == null) {
      debugPrint(
        '  ⚠️ Session has pending_update but no serverId - converting to pending_create',
      );
      // Fix invalid state: convert to pending_create
      await db.writeTxn(() async {
        localSession.syncStatus = 'pending_create';
        await db.localSessions.put(localSession);
      });
      // Now sync as create
      await _syncCreateSession(db, localSession);
      return;
    }

    debugPrint('  Updating session ${localSession.serverId} on server...');

    try {
      // Fetch current server version to check for conflicts
      final serverData = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.sessionById(localSession.serverId!),
      );

      final serverModified = DateTime.parse(serverData['date'] as String);

      // Server-wins conflict resolution
      if (localSession.lastModifiedServer != null &&
          serverModified.isAfter(localSession.lastModifiedServer!)) {
        debugPrint(
          '  ⚠️ Conflict detected - server has newer data, discarding local changes',
        );

        // Update local with server data (server wins)
        await db.writeTxn(() async {
          localSession.status = serverData['status'] as String;
          localSession.notes = serverData['notes'] as String?;
          localSession.duration = serverData['duration'] as int?;
          localSession.type = serverData['type'] as String?;
          localSession.name = serverData['name'] as String?;
          localSession.startedAt =
              serverData['startedAt'] != null
                  ? DateTime.parse(serverData['startedAt'] as String)
                  : null;
          localSession.completedAt =
              serverData['completedAt'] != null
                  ? DateTime.parse(serverData['completedAt'] as String)
                  : null;
          localSession.pausedAt =
              serverData['pausedAt'] != null
                  ? DateTime.parse(serverData['pausedAt'] as String)
                  : null;
          localSession.lastModifiedServer = serverModified;
          localSession.isSynced = true;
          localSession.syncStatus = 'synced';
          localSession.syncRetryCount = 0;
          localSession.syncError = null;
          localSession.lastSyncAttempt = DateTime.now();
          await db.localSessions.put(localSession);
        });

        debugPrint('  ✅ Local session updated from server (conflict resolved)');
        return;
      }

      // No conflict - update server with local changes (full PUT)
      await _apiService.put<void>(
        ApiConfig.sessionById(localSession.serverId!),
        data: {
          'id': localSession.serverId!,
          'userId': localSession.userId,
          'date': localSession.date.toIso8601String(),
          'duration': localSession.duration,
          'notes': localSession.notes,
          'type': localSession.type,
          'name': localSession.name,
          'status': localSession.status,
          'startedAt': localSession.startedAt?.toIso8601String(),
          'completedAt': localSession.completedAt?.toIso8601String(),
          'pausedAt': localSession.pausedAt?.toIso8601String(),
        },
      );

      // Mark as synced
      await db.writeTxn(() async {
        localSession.isSynced = true;
        localSession.syncStatus = 'synced';
        localSession.lastModifiedServer = DateTime.now();
        localSession.syncRetryCount = 0;
        localSession.syncError = null;
        localSession.lastSyncAttempt = DateTime.now();
        await db.localSessions.put(localSession);
      });

      debugPrint('  ✅ Session updated on server');
    } catch (e) {
      rethrow;
    }
  }

  /// Sync a session that needs to be deleted from the server
  Future<void> _syncDeleteSession(Isar db, LocalSession localSession) async {
    if (localSession.serverId == null) {
      // Never synced to server - just delete locally (with related data)
      await _deleteSessionAndRelatedData(db, localSession);
      debugPrint('  ✅ Local-only session deleted');
      return;
    }

    debugPrint('  Deleting session ${localSession.serverId} from server...');

    try {
      // DELETE from server
      await _apiService.delete(ApiConfig.sessionById(localSession.serverId!));

      // Delete from local database (including exercises and sets)
      await _deleteSessionAndRelatedData(db, localSession);

      debugPrint('  ✅ Session deleted from server and locally');
    } catch (e) {
      rethrow;
    }
  }

  /// Delete session and all related exercises and sets
  Future<void> _deleteSessionAndRelatedData(
    Isar db,
    LocalSession localSession,
  ) async {
    await db.writeTxn(() async {
      // Delete all exercises for this session
      final exercises =
          await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(localSession.localId)
              .findAll();

      for (final exercise in exercises) {
        // Delete all sets for this exercise
        await db.localExerciseSets
            .filter()
            .exerciseLocalIdEqualTo(exercise.localId)
            .deleteAll();
      }

      // Delete all exercises
      await db.localExercises
          .filter()
          .sessionLocalIdEqualTo(localSession.localId)
          .deleteAll();

      // Delete the session
      await db.localSessions.delete(localSession.localId);
    });
  }

  /// Mark sync error with exponential backoff
  Future<void> _markSyncError(
    Isar db,
    LocalSession session,
    String error,
  ) async {
    await db.writeTxn(() async {
      session.syncRetryCount += 1;
      session.syncError = error;
      session.lastSyncAttempt = DateTime.now();

      // Don't change syncStatus - keep it as pending_create/update/delete
      // so it can be retried. The syncError and syncRetryCount fields
      // already track the error state.

      if (session.syncRetryCount >= _maxRetries) {
        debugPrint(
          '  ❌ Session ${session.localId} failed after $_maxRetries attempts: $error',
        );
        debugPrint(
          '  Will keep retrying on next sync (status: ${session.syncStatus})',
        );
      } else {
        debugPrint(
          '  ⚠️ Session ${session.localId} sync failed (attempt ${session.syncRetryCount}/$_maxRetries): $error',
        );
      }

      await db.localSessions.put(session);
    });
  }

  /// Sync all pending exercises
  Future<void> _syncExercises(Isar db) async {
    final pendingExercises =
        await db.localExercises.filter().isSyncedEqualTo(false).findAll();

    if (pendingExercises.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingExercises.length} exercises...');

    for (final exercise in pendingExercises) {
      // Skip if parent session doesn't have serverId yet
      final parentSession = await db.localSessions.get(exercise.sessionLocalId);
      if (parentSession == null || parentSession.serverId == null) {
        debugPrint('    ! Skipping exercise - parent session not synced yet');
        continue;
      }

      // Update exercise's sessionServerId if not set
      if (exercise.sessionServerId != parentSession.serverId) {
        await db.writeTxn(() async {
          exercise.sessionServerId = parentSession.serverId;
          await db.localExercises.put(exercise);
        });
        debugPrint(
          '    Updated exercise sessionServerId to ${parentSession.serverId}',
        );
      }

      try {
        switch (exercise.syncStatus) {
          case 'pending_create':
            await _syncCreateExercise(db, exercise, parentSession);
            break;
          case 'pending_update':
            await _syncUpdateExercise(db, exercise);
            break;
          case 'pending_delete':
            await _syncDeleteExercise(db, exercise);
            break;
        }
      } catch (e) {
        debugPrint('    ⚠️ Exercise sync failed: $e');
      }
    }
  }

  Future<void> _syncCreateExercise(
    Isar db,
    LocalExercise exercise,
    LocalSession parentSession,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      '${ApiConfig.sessions}/${parentSession.serverId}/exercises',
      data: {
        'name': exercise.name,
        'duration': exercise.duration,
        'restTime': exercise.restTime,
        'notes': exercise.notes,
        'exerciseTemplateId': exercise.exerciseTemplateId,
      },
    );

    await db.writeTxn(() async {
      exercise.serverId = response['id'] as int;
      exercise.sessionServerId = parentSession.serverId;
      exercise.isSynced = true;
      exercise.syncStatus = 'synced';
      await db.localExercises.put(exercise);
    });

    debugPrint('    ✅ Created exercise ${exercise.serverId}');
  }

  Future<void> _syncUpdateExercise(Isar db, LocalExercise exercise) async {
    if (exercise.serverId == null) {
      // Convert to create
      final parentSession = await db.localSessions.get(exercise.sessionLocalId);
      if (parentSession != null && parentSession.serverId != null) {
        await _syncCreateExercise(db, exercise, parentSession);
      }
      return;
    }

    await _apiService.put<void>(
      '${ApiConfig.exercises}/${exercise.serverId}',
      data: {
        'name': exercise.name,
        'duration': exercise.duration,
        'restTime': exercise.restTime,
        'notes': exercise.notes,
      },
    );

    await db.writeTxn(() async {
      exercise.isSynced = true;
      exercise.syncStatus = 'synced';
      await db.localExercises.put(exercise);
    });

    debugPrint('    ✅ Updated exercise ${exercise.serverId}');
  }

  Future<void> _syncDeleteExercise(Isar db, LocalExercise exercise) async {
    if (exercise.serverId != null) {
      await _apiService.delete('${ApiConfig.exercises}/${exercise.serverId}');
    }

    await db.writeTxn(() async {
      await db.localExercises.delete(exercise.localId);
    });

    debugPrint('    ✅ Deleted exercise');
  }

  /// Sync all pending exercise sets
  Future<void> _syncExerciseSets(Isar db) async {
    final pendingSets =
        await db.localExerciseSets.filter().isSyncedEqualTo(false).findAll();

    if (pendingSets.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingSets.length} exercise sets...');

    for (final set in pendingSets) {
      // Skip if parent exercise doesn't have serverId yet
      final parentExercise = await db.localExercises.get(set.exerciseLocalId);
      if (parentExercise == null || parentExercise.serverId == null) {
        debugPrint('    ! Skipping set - parent exercise not synced yet');
        continue;
      }

      // Update set's exerciseServerId if not set
      if (set.exerciseServerId != parentExercise.serverId) {
        await db.writeTxn(() async {
          set.exerciseServerId = parentExercise.serverId;
          await db.localExerciseSets.put(set);
        });
        debugPrint(
          '    Updated set exerciseServerId to ${parentExercise.serverId}',
        );
      }

      try {
        switch (set.syncStatus) {
          case 'pending_create':
            await _syncCreateSet(db, set, parentExercise);
            break;
          case 'pending_update':
            await _syncUpdateSet(db, set);
            break;
          case 'pending_delete':
            await _syncDeleteSet(db, set);
            break;
        }
      } catch (e) {
        debugPrint('    ⚠️ Set sync failed: $e');
      }
    }
  }

  Future<void> _syncCreateSet(
    Isar db,
    LocalExerciseSet set,
    LocalExercise parentExercise,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.exerciseSets,
      data: {
        'exerciseId': parentExercise.serverId,
        'setNumber': set.setNumber,
        'reps': set.reps,
        'weight': set.weight,
        'duration': set.duration,
        'isCompleted': set.isCompleted,
        'completedAt': set.completedAt?.toIso8601String(),
        'notes': set.notes,
      },
    );

    await db.writeTxn(() async {
      set.serverId = response['id'] as int;
      set.exerciseServerId = parentExercise.serverId;
      set.isSynced = true;
      set.syncStatus = 'synced';
      await db.localExerciseSets.put(set);
    });

    debugPrint('    ✅ Created set ${set.serverId}');
  }

  Future<void> _syncUpdateSet(Isar db, LocalExerciseSet set) async {
    if (set.serverId == null) {
      // Convert to create
      final parentExercise = await db.localExercises.get(set.exerciseLocalId);
      if (parentExercise != null && parentExercise.serverId != null) {
        await _syncCreateSet(db, set, parentExercise);
      }
      return;
    }

    await _apiService.put<void>(
      '${ApiConfig.exerciseSets}/${set.serverId}',
      data: {
        'setNumber': set.setNumber,
        'reps': set.reps,
        'weight': set.weight,
        'duration': set.duration,
        'isCompleted': set.isCompleted,
        'completedAt': set.completedAt?.toIso8601String(),
        'notes': set.notes,
      },
    );

    await db.writeTxn(() async {
      set.isSynced = true;
      set.syncStatus = 'synced';
      await db.localExerciseSets.put(set);
    });

    debugPrint('    ✅ Updated set ${set.serverId}');
  }

  Future<void> _syncDeleteSet(Isar db, LocalExerciseSet set) async {
    if (set.serverId != null) {
      await _apiService.delete('${ApiConfig.exerciseSets}/${set.serverId}');
    }

    await db.writeTxn(() async {
      await db.localExerciseSets.delete(set.localId);
    });

    debugPrint('    ✅ Deleted set');
  }

  // ========== Program Sync Methods ==========

  /// Sync all pending programs
  Future<void> _syncPrograms(Isar db) async {
    final userId = await _authService.getUserId();
    if (userId == null) {
      debugPrint('  ⚠️ No authenticated user, skipping program sync');
      return;
    }

    final pendingPrograms =
        await db.localPrograms
            .filter()
            .isSyncedEqualTo(false)
            .userIdEqualTo(userId)
            .findAll();

    if (pendingPrograms.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingPrograms.length} programs...');

    for (final program in pendingPrograms) {
      try {
        switch (program.syncStatus) {
          case 'pending_create':
            await _syncCreateProgram(db, program);
            break;
          case 'pending_update':
            await _syncUpdateProgram(db, program);
            break;
          case 'pending_delete':
            await _syncDeleteProgram(db, program);
            break;
        }
      } catch (e) {
        debugPrint('    ⚠️ Program sync failed: $e');
        await _markProgramSyncError(db, program, e.toString());
      }
    }
  }

  Future<void> _syncCreateProgram(Isar db, LocalProgram program) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.programs,
      data: {
        'userId': program.userId,
        'title': program.title,
        'description': program.description,
        'goalId': program.goalId,
        'totalWeeks': program.totalWeeks,
        'currentWeek': program.currentWeek,
        'currentDay': program.currentDay,
        'startDate': program.startDate.toIso8601String(),
        'endDate': program.endDate?.toIso8601String(),
        'isActive': program.isActive,
        'isCompleted': program.isCompleted,
        'programStructure': program.programStructure,
      },
    );

    await db.writeTxn(() async {
      program.serverId = response['id'] as int;
      program.isSynced = true;
      program.syncStatus = 'synced';
      program.syncRetryCount = 0;
      program.syncError = null;
      program.lastSyncAttempt = DateTime.now();
      await db.localPrograms.put(program);
    });

    debugPrint('    ✅ Created program ${program.serverId}');
  }

  Future<void> _syncUpdateProgram(Isar db, LocalProgram program) async {
    if (program.serverId == null) {
      await _syncCreateProgram(db, program);
      return;
    }

    await _apiService.put<void>(
      '${ApiConfig.programs}/${program.serverId}',
      data: {
        'id': program.serverId!,
        'userId': program.userId,
        'title': program.title,
        'description': program.description,
        'goalId': program.goalId,
        'totalWeeks': program.totalWeeks,
        'currentWeek': program.currentWeek,
        'currentDay': program.currentDay,
        'startDate': program.startDate.toIso8601String(),
        'endDate': program.endDate?.toIso8601String(),
        'isActive': program.isActive,
        'isCompleted': program.isCompleted,
        'programStructure': program.programStructure,
      },
    );

    await db.writeTxn(() async {
      program.isSynced = true;
      program.syncStatus = 'synced';
      program.syncRetryCount = 0;
      program.syncError = null;
      program.lastSyncAttempt = DateTime.now();
      await db.localPrograms.put(program);
    });

    debugPrint('    ✅ Updated program ${program.serverId}');
  }

  Future<void> _syncDeleteProgram(Isar db, LocalProgram program) async {
    if (program.serverId != null) {
      await _apiService.delete('${ApiConfig.programs}/${program.serverId}');
    }

    await db.writeTxn(() async {
      // Delete related program workouts
      await db.localProgramWorkouts
          .filter()
          .programLocalIdEqualTo(program.localId)
          .deleteAll();
      // Delete the program
      await db.localPrograms.delete(program.localId);
    });

    debugPrint('    ✅ Deleted program');
  }

  Future<void> _markProgramSyncError(
    Isar db,
    LocalProgram program,
    String error,
  ) async {
    await db.writeTxn(() async {
      program.syncRetryCount += 1;
      program.syncError = error;
      program.lastSyncAttempt = DateTime.now();
      await db.localPrograms.put(program);
    });
  }

  // ========== Goal Sync Methods ==========

  /// Sync all pending goals
  Future<void> _syncGoals(Isar db) async {
    final userId = await _authService.getUserId();
    if (userId == null) {
      debugPrint('  ⚠️ No authenticated user, skipping goal sync');
      return;
    }

    final pendingGoals =
        await db.localGoals
            .filter()
            .isSyncedEqualTo(false)
            .userIdEqualTo(userId)
            .findAll();

    if (pendingGoals.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingGoals.length} goals...');

    for (final goal in pendingGoals) {
      try {
        switch (goal.syncStatus) {
          case 'pending_create':
            await _syncCreateGoal(db, goal);
            break;
          case 'pending_update':
            await _syncUpdateGoal(db, goal);
            break;
          case 'pending_delete':
            await _syncDeleteGoal(db, goal);
            break;
        }
      } catch (e) {
        debugPrint('    ⚠️ Goal sync failed: $e');
        await _markGoalSyncError(db, goal, e.toString());
      }
    }
  }

  Future<void> _syncCreateGoal(Isar db, LocalGoal goal) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.goals,
      data: {
        'userId': goal.userId,
        'goalType': goal.goalType,
        'targetValue': goal.targetValue,
        'currentValue': goal.currentValue,
        'unit': goal.unit,
        'timeFrame': goal.timeFrame,
        'startDate': goal.startDate.toIso8601String(),
        'targetDate': goal.targetDate?.toIso8601String(),
        'isActive': goal.isActive,
        'isCompleted': goal.isCompleted,
      },
    );

    await db.writeTxn(() async {
      goal.serverId = response['id'] as int;
      goal.isSynced = true;
      goal.syncStatus = 'synced';
      goal.syncRetryCount = 0;
      goal.syncError = null;
      goal.lastSyncAttempt = DateTime.now();
      await db.localGoals.put(goal);
    });

    debugPrint('    ✅ Created goal ${goal.serverId}');
  }

  Future<void> _syncUpdateGoal(Isar db, LocalGoal goal) async {
    if (goal.serverId == null) {
      await _syncCreateGoal(db, goal);
      return;
    }

    await _apiService.put<void>(
      '${ApiConfig.goals}/${goal.serverId}',
      data: {
        'id': goal.serverId!,
        'userId': goal.userId,
        'goalType': goal.goalType,
        'targetValue': goal.targetValue,
        'currentValue': goal.currentValue,
        'unit': goal.unit,
        'timeFrame': goal.timeFrame,
        'startDate': goal.startDate.toIso8601String(),
        'targetDate': goal.targetDate?.toIso8601String(),
        'isActive': goal.isActive,
        'isCompleted': goal.isCompleted,
      },
    );

    await db.writeTxn(() async {
      goal.isSynced = true;
      goal.syncStatus = 'synced';
      goal.syncRetryCount = 0;
      goal.syncError = null;
      goal.lastSyncAttempt = DateTime.now();
      await db.localGoals.put(goal);
    });

    debugPrint('    ✅ Updated goal ${goal.serverId}');
  }

  Future<void> _syncDeleteGoal(Isar db, LocalGoal goal) async {
    if (goal.serverId != null) {
      await _apiService.delete('${ApiConfig.goals}/${goal.serverId}');
    }

    await db.writeTxn(() async {
      await db.localGoals.delete(goal.localId);
    });

    debugPrint('    ✅ Deleted goal');
  }

  Future<void> _markGoalSyncError(Isar db, LocalGoal goal, String error) async {
    await db.writeTxn(() async {
      goal.syncRetryCount += 1;
      goal.syncError = error;
      goal.lastSyncAttempt = DateTime.now();
      await db.localGoals.put(goal);
    });
  }

  // ========== Program Workout Sync Methods ==========

  /// Sync all pending program workouts
  Future<void> _syncProgramWorkouts(Isar db) async {
    final pendingWorkouts =
        await db.localProgramWorkouts.filter().isSyncedEqualTo(false).findAll();

    if (pendingWorkouts.isEmpty) {
      return;
    }

    debugPrint('  Syncing ${pendingWorkouts.length} program workouts...');

    for (final workout in pendingWorkouts) {
      // Skip if parent program doesn't have serverId yet
      final parentProgram = await db.localPrograms.get(workout.programLocalId);
      if (parentProgram == null || parentProgram.serverId == null) {
        debugPrint('    ! Skipping workout - parent program not synced yet');
        continue;
      }

      // Update workout's programServerId if not set
      if (workout.programServerId != parentProgram.serverId) {
        await db.writeTxn(() async {
          workout.programServerId = parentProgram.serverId;
          await db.localProgramWorkouts.put(workout);
        });
      }

      try {
        switch (workout.syncStatus) {
          case 'pending_create':
            await _syncCreateProgramWorkout(db, workout, parentProgram);
            break;
          case 'pending_update':
            await _syncUpdateProgramWorkout(db, workout);
            break;
          case 'pending_delete':
            await _syncDeleteProgramWorkout(db, workout);
            break;
        }
      } catch (e) {
        debugPrint('    ⚠️ Program workout sync failed: $e');
      }
    }
  }

  Future<void> _syncCreateProgramWorkout(
    Isar db,
    LocalProgramWorkout workout,
    LocalProgram parentProgram,
  ) async {
    final response = await _apiService.post<Map<String, dynamic>>(
      '${ApiConfig.programs}/${parentProgram.serverId}/workouts',
      data: {
        'programId': parentProgram.serverId,
        'weekNumber': workout.weekNumber,
        'dayNumber': workout.dayNumber,
        'dayName': workout.dayName,
        'workoutName': workout.workoutName,
        'workoutType': workout.workoutType,
        'description': workout.description,
        'estimatedDuration': workout.estimatedDuration,
        'exercisesJson': workout.exercisesJson,
        'warmUp': workout.warmUp,
        'coolDown': workout.coolDown,
        'isCompleted': workout.isCompleted,
        'orderIndex': workout.orderIndex,
      },
    );

    await db.writeTxn(() async {
      workout.serverId = response['id'] as int;
      workout.programServerId = parentProgram.serverId;
      workout.isSynced = true;
      workout.syncStatus = 'synced';
      await db.localProgramWorkouts.put(workout);
    });

    debugPrint('    ✅ Created program workout ${workout.serverId}');
  }

  Future<void> _syncUpdateProgramWorkout(
    Isar db,
    LocalProgramWorkout workout,
  ) async {
    if (workout.serverId == null) {
      final parentProgram = await db.localPrograms.get(workout.programLocalId);
      if (parentProgram != null && parentProgram.serverId != null) {
        await _syncCreateProgramWorkout(db, workout, parentProgram);
      }
      return;
    }

    await _apiService.put<void>(
      '${ApiConfig.programs}/workouts/${workout.serverId}',
      data: {
        'id': workout.serverId!,
        'programId': workout.programServerId,
        'weekNumber': workout.weekNumber,
        'dayNumber': workout.dayNumber,
        'dayName': workout.dayName,
        'workoutName': workout.workoutName,
        'workoutType': workout.workoutType,
        'description': workout.description,
        'estimatedDuration': workout.estimatedDuration,
        'exercisesJson': workout.exercisesJson,
        'warmUp': workout.warmUp,
        'coolDown': workout.coolDown,
        'isCompleted': workout.isCompleted,
        'orderIndex': workout.orderIndex,
      },
    );

    await db.writeTxn(() async {
      workout.isSynced = true;
      workout.syncStatus = 'synced';
      await db.localProgramWorkouts.put(workout);
    });

    debugPrint('    ✅ Updated program workout ${workout.serverId}');
  }

  Future<void> _syncDeleteProgramWorkout(
    Isar db,
    LocalProgramWorkout workout,
  ) async {
    if (workout.serverId != null) {
      await _apiService.delete(
        '${ApiConfig.programs}/workouts/${workout.serverId}',
      );
    }

    await db.writeTxn(() async {
      await db.localProgramWorkouts.delete(workout.localId);
    });

    debugPrint('    ✅ Deleted program workout');
  }

  /// Get sync status summary
  Future<Map<String, dynamic>> getSyncStatus() async {
    final db = _localDb.database;

    final pendingCount =
        await db.localSessions.filter().isSyncedEqualTo(false).count();

    // Count sessions with sync errors (retry count >= 3)
    final errorCount =
        await db.localSessions
            .filter()
            .syncRetryCountGreaterThan(_maxRetries - 1)
            .count();

    final allSessions = await db.localSessions.where().findAll();
    final lastSyncAttempts =
        allSessions
            .where((s) => s.lastSyncAttempt != null)
            .map((s) => s.lastSyncAttempt!)
            .toList();

    final lastSyncTime =
        lastSyncAttempts.isEmpty
            ? null
            : lastSyncAttempts.reduce((a, b) => a.isAfter(b) ? a : b);

    return {
      'isSyncing': _isSyncing,
      'pendingCount': pendingCount,
      'errorCount': errorCount,
      'lastSyncTime': lastSyncTime,
      'isOnline': _connectivity.isOnline,
    };
  }

  /// Retry failed syncs
  Future<void> retryFailedSyncs() async {
    final db = _localDb.database;

    // Reset retry count for failed items (retry count >= 3)
    final failedSessions =
        await db.localSessions
            .filter()
            .syncRetryCountGreaterThan(_maxRetries - 1)
            .findAll();

    await db.writeTxn(() async {
      for (final session in failedSessions) {
        session.syncRetryCount = 0;
        // Keep original syncStatus (pending_create/update/delete)
        session.syncError = null;
        await db.localSessions.put(session);
      }
    });

    debugPrint('🔄 Retrying ${failedSessions.length} failed syncs');

    // Trigger immediate sync
    if (failedSessions.isNotEmpty) {
      await sync();
    }
  }

  /// Dispose resources
  void dispose() {
    _periodicSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _debounceTimer?.cancel();
    _isInitialized = false;
    debugPrint('🛑 SyncService disposed');
  }

  /// Reset singleton (useful for testing)
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
