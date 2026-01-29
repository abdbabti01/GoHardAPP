import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:dio/dio.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../models/session.dart';
import '../models/exercise.dart';
import '../models/program_workout.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../local/services/local_database_service.dart';
import '../local/services/model_mapper.dart';
import '../local/models/local_session.dart';
import '../local/models/local_exercise.dart';
import '../local/models/local_exercise_set.dart';
import '../local/models/local_exercise_template.dart';

/// Repository for session (workout) operations with offline support
class SessionRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;
  final AuthService _authService;

  SessionRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._authService,
  );

  // ========== Helper Methods (Refactored - Issue #18) ==========

  /// Find a local session by ID (tries server ID first, then local ID)
  Future<LocalSession?> _findLocalSession(Isar db, int id) async {
    return await db.localSessions.filter().serverIdEqualTo(id).findFirst() ??
        await db.localSessions.get(id);
  }

  /// Find a local session by ID or throw if not found
  Future<LocalSession> _findLocalSessionOrThrow(Isar db, int id) async {
    final session = await _findLocalSession(db, id);
    if (session == null) {
      throw Exception('Session not found: $id');
    }
    return session;
  }

  /// Load exercises for a session from local database
  Future<List<Exercise>> _loadExercisesForSession(
    Isar db,
    int sessionLocalId,
  ) async {
    final localExercises =
        await db.localExercises
            .filter()
            .sessionLocalIdEqualTo(sessionLocalId)
            .findAll();

    return localExercises
        .map((localEx) => ModelMapper.localToExercise(localEx))
        .toList();
  }

  /// Convert a LocalSession to Session with exercises loaded
  Future<Session> _localSessionToSessionWithExercises(
    Isar db,
    LocalSession localSession,
  ) async {
    final exercises = await _loadExercisesForSession(db, localSession.localId);
    return ModelMapper.localToSession(localSession, exercises: exercises);
  }

  /// Execute a background sync operation with standard logging
  void _backgroundSync(
    Future<void> Function() syncOperation,
    String successMessage,
  ) {
    syncOperation()
        .then((_) {
          debugPrint('✅ Background sync: $successMessage');
        })
        .catchError((e) {
          debugPrint('⚠️ Background sync failed, will retry later: $e');
        });
  }

  /// Mark a local session as needing sync (pending_update if server ID exists)
  Future<void> _markSessionForSync(
    Isar db,
    LocalSession localSession, {
    String? newStatus,
  }) async {
    await db.writeTxn(() async {
      if (newStatus != null) {
        localSession.status = newStatus;
      }
      localSession.lastModifiedLocal = DateTime.now();
      localSession.isSynced = false;
      if (localSession.serverId != null) {
        localSession.syncStatus = 'pending_update';
      }
      await db.localSessions.put(localSession);
    });
  }

  /// Get all sessions for the current user
  /// Offline-first: returns local cache immediately, syncs with server in background
  /// Set [waitForSync] to true to wait for server sync before returning (useful after login)
  Future<List<Session>> getSessions({bool waitForSync = false}) async {
    final Isar db = _localDb.database;

    // If waitForSync is true and we're online, sync first then return fresh data
    if (waitForSync && _connectivity.isOnline) {
      debugPrint('⏳ Waiting for server sync before returning sessions...');
      await _syncSessionsFromServer(db);
      final freshSessions = await _getLocalSessions(db);
      return freshSessions;
    }

    // Otherwise, use offline-first approach: load from cache first for instant response
    final cachedSessions = await _getLocalSessions(db);

    // Then sync with server in background if online (don't block)
    if (_connectivity.isOnline) {
      _syncSessionsFromServer(db)
          .then((_) {
            debugPrint('✅ Background sync: Sessions synced from server');
          })
          .catchError((e) {
            debugPrint('⚠️ Background sync failed: $e');
          });
    }

    return cachedSessions;
  }

  /// Get all in-progress sessions for the current user
  /// Used to ensure only one workout is active at a time
  Future<List<Session>> getInProgressSessions() async {
    final Isar db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      debugPrint('⚠️ No authenticated user, returning empty list');
      return [];
    }

    // Get all in-progress sessions from local DB
    final localSessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .statusEqualTo('in_progress')
            .findAll();

    // Convert to Session models with exercises (using helper)
    final sessions = <Session>[];
    for (final localSession in localSessions) {
      sessions.add(await _localSessionToSessionWithExercises(db, localSession));
    }

    return sessions;
  }

  /// Background sync: Fetch sessions from server and update cache
  Future<void> _syncSessionsFromServer(Isar db) async {
    try {
      // Fetch from API
      final data = await _apiService.get<List<dynamic>>(ApiConfig.sessions);

      // Debug: Log raw JSON to check programId
      debugPrint('📥 Received ${data.length} sessions from API');
      for (final sessionJson in data.take(3)) {
        debugPrint(
          '  Session JSON: programId=${sessionJson['programId']}, programWorkoutId=${sessionJson['programWorkoutId']}, name=${sessionJson['name']}',
        );
      }

      final apiSessions =
          data
              .map((json) => Session.fromJson(json as Map<String, dynamic>))
              .toList();

      // Get current user ID for filtering
      final currentUserId = await _authService.getUserId();
      if (currentUserId == null) {
        debugPrint('⚠️ No authenticated user, skipping cache update');
        return; // Exit background sync, cache already returned to caller
      }

      // Update local cache (sessions AND their exercises)
      await db.writeTxn(() async {
        for (final apiSession in apiSessions) {
          // Only cache sessions belonging to current user
          if (apiSession.userId != currentUserId) {
            debugPrint(
              '  ⏭️ Skipping session ${apiSession.id} - belongs to different user (${apiSession.userId} != $currentUserId)',
            );
            continue;
          }

          // Check if session already exists locally
          final existingLocal =
              await db.localSessions
                  .filter()
                  .serverIdEqualTo(apiSession.id)
                  .findFirst();

          // Skip sessions with pending local changes - don't overwrite with server data
          if (existingLocal != null &&
              (existingLocal.syncStatus == 'pending_delete' ||
                  existingLocal.syncStatus == 'pending_update')) {
            debugPrint(
              '  ⏭️ Skipping session ${apiSession.id} - has pending local changes (${existingLocal.syncStatus})',
            );
            continue;
          }

          // CRITICAL FIX: Never overwrite in-progress sessions from server!
          // This prevents the 5-hour timer bug caused by server returning incorrect timestamps.
          // Local state is authoritative for active workouts.
          if (existingLocal != null && existingLocal.status == 'in_progress') {
            debugPrint(
              '  ⏭️ Skipping session ${apiSession.id} - in_progress workout, keeping local timestamps',
            );
            continue;
          }

          LocalSession savedSession;
          if (existingLocal != null) {
            // Update existing local session
            final updated = ModelMapper.sessionToLocal(
              apiSession,
              localId: existingLocal.localId,
              isSynced: true,
            );
            await db.localSessions.put(updated);
            savedSession = updated;
          } else {
            // Create new local session
            final localSession = ModelMapper.sessionToLocal(apiSession);
            await db.localSessions.put(localSession);
            savedSession = localSession;
          }

          // Save exercises for this session
          int exerciseCount = 0;
          for (final apiExercise in apiSession.exercises) {
            // Check if exercise already exists locally
            final existingExercise =
                await db.localExercises
                    .filter()
                    .serverIdEqualTo(apiExercise.id)
                    .findFirst();

            if (existingExercise != null) {
              // Update existing
              final updated = ModelMapper.exerciseToLocal(
                apiExercise,
                sessionLocalId: savedSession.localId,
                localId: existingExercise.localId,
                isSynced: true,
              );
              await db.localExercises.put(updated);
              debugPrint(
                '    ✏️ Updated exercise ${updated.serverId}, sessionLocalId=${updated.sessionLocalId}',
              );
            } else {
              // Create new
              final localExercise = ModelMapper.exerciseToLocal(
                apiExercise,
                sessionLocalId: savedSession.localId,
              );
              final savedExerciseId = await db.localExercises.put(
                localExercise,
              );
              debugPrint(
                '    ➕ Created exercise ${localExercise.serverId}, localId=$savedExerciseId, sessionLocalId=${localExercise.sessionLocalId}',
              );
            }
            exerciseCount++;
          }
          debugPrint(
            '  📝 Cached $exerciseCount exercises for session ${apiSession.id}',
          );
        }

        // Remove sessions that were deleted on the server (cascade delete cleanup)
        final serverSessionIds = apiSessions.map((s) => s.id).toSet();
        final allLocalSessions =
            await db.localSessions
                .filter()
                .userIdEqualTo(currentUserId)
                .serverIdIsNotNull()
                .findAll();

        for (final localSession in allLocalSessions) {
          if (!serverSessionIds.contains(localSession.serverId)) {
            // Session exists locally but not on server - it was deleted (cascade)
            debugPrint(
              '  🗑️ Removing session ${localSession.serverId} (deleted on server)',
            );

            // Delete associated exercises first
            final exercisesToDelete =
                await db.localExercises
                    .filter()
                    .sessionLocalIdEqualTo(localSession.localId)
                    .findAll();

            for (final exercise in exercisesToDelete) {
              await db.localExercises.delete(exercise.localId);
            }

            // Delete the session
            await db.localSessions.delete(localSession.localId);
          }
        }
      });

      debugPrint('✅ Synced ${apiSessions.length} sessions from server');
    } catch (e) {
      // Sync failed - but that's okay, we already returned cached data
      rethrow; // Let the caller handle the error
    }
  }

  /// Get sessions from local database with exercises
  Future<List<Session>> _getLocalSessions(Isar db) async {
    // Get current user ID to filter sessions
    final userId = await _authService.getUserId();
    if (userId == null) {
      debugPrint('⚠️ No authenticated user, returning empty list');
      return [];
    }

    // Filter sessions by current user only
    final localSessions =
        await db.localSessions.filter().userIdEqualTo(userId).findAll();

    // Convert to Session models, skipping deleted/archived (using helper)
    final sessions = <Session>[];
    for (final localSession in localSessions) {
      // Skip sessions marked for deletion or archived
      if (localSession.syncStatus == 'pending_delete' ||
          localSession.status == 'archived') {
        continue;
      }

      sessions.add(await _localSessionToSessionWithExercises(db, localSession));
    }

    return sessions;
  }

  /// Get session by ID
  /// Offline-first: returns local cache, then tries to sync with server
  Future<Session> getSession(int id) async {
    final Isar db = _localDb.database;

    // Check if there's a local version with pending changes
    var localSession =
        await db.localSessions.filter().serverIdEqualTo(id).findFirst();
    localSession ??= await db.localSessions.get(id);

    // If local session has pending changes, return it instead of fetching from server
    if (localSession != null && !localSession.isSynced) {
      debugPrint('📝 Session has pending changes, returning local version');
      return await _getLocalSession(db, id);
    }

    // CRITICAL FIX: Always use local data for in-progress sessions!
    // This prevents the 5-hour timer bug caused by server returning incorrect timestamps.
    // Local timestamps are authoritative during active workouts.
    if (localSession != null && localSession.status == 'in_progress') {
      debugPrint(
        '🏋️ In-progress session - using local timestamps (startedAt: ${localSession.startedAt})',
      );
      return await _getLocalSession(db, id);
    }

    if (_connectivity.isOnline) {
      try {
        // Fetch from API
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.sessionById(id),
        );

        // DEBUG: Log what the server returns
        debugPrint('🔽 SERVER RESPONSE for session $id:');
        debugPrint('   Raw startedAt from API: ${data['startedAt']}');
        debugPrint('   Raw pausedAt from API: ${data['pausedAt']}');

        final apiSession = Session.fromJson(data);

        // DEBUG: Log what fromJson produces
        debugPrint('   Parsed startedAt: ${apiSession.startedAt}');
        debugPrint('   Parsed startedAt.isUtc: ${apiSession.startedAt?.isUtc}');
        debugPrint('   Parsed startedAt.hour: ${apiSession.startedAt?.hour}');
        debugPrint('   Parsed pausedAt: ${apiSession.pausedAt}');
        debugPrint('   Parsed pausedAt.isUtc: ${apiSession.pausedAt?.isUtc}');

        // Update local cache (session AND exercises)
        await db.writeTxn(() async {
          final existingLocal =
              await db.localSessions
                  .filter()
                  .serverIdEqualTo(apiSession.id)
                  .findFirst();

          LocalSession savedSession;
          if (existingLocal != null) {
            final updated = ModelMapper.sessionToLocal(
              apiSession,
              localId: existingLocal.localId,
              isSynced: true,
            );
            await db.localSessions.put(updated);
            savedSession = updated;
          } else {
            final localSession = ModelMapper.sessionToLocal(apiSession);
            await db.localSessions.put(localSession);
            savedSession = localSession;
          }

          // Save exercises for this session
          for (final apiExercise in apiSession.exercises) {
            final existingExercise =
                await db.localExercises
                    .filter()
                    .serverIdEqualTo(apiExercise.id)
                    .findFirst();

            if (existingExercise != null) {
              final updated = ModelMapper.exerciseToLocal(
                apiExercise,
                sessionLocalId: savedSession.localId,
                localId: existingExercise.localId,
                isSynced: true,
              );
              await db.localExercises.put(updated);
            } else {
              final localExercise = ModelMapper.exerciseToLocal(
                apiExercise,
                sessionLocalId: savedSession.localId,
              );
              await db.localExercises.put(localExercise);
            }
          }
        });

        return apiSession;
      } catch (e) {
        debugPrint('⚠️ API failed, falling back to local cache: $e');
        return await _getLocalSession(db, id);
      }
    } else {
      debugPrint('📴 Offline - returning cached session');
      return await _getLocalSession(db, id);
    }
  }

  /// Get session from local database by ID (server ID or local ID) with exercises
  Future<Session> _getLocalSession(Isar db, int id) async {
    // Find local session using helper
    final localSession = await _findLocalSessionOrThrow(db, id);

    // Load exercises using helper
    final exercises = await _loadExercisesForSession(db, localSession.localId);

    debugPrint(
      '  📦 Loaded session ${localSession.serverId ?? localSession.localId} from cache with ${exercises.length} exercises',
    );
    debugPrint('  📦 LocalSession startedAt: ${localSession.startedAt}');
    debugPrint('  📦 LocalSession pausedAt: ${localSession.pausedAt}');
    debugPrint('  📦 LocalSession status: ${localSession.status}');

    final session = ModelMapper.localToSession(
      localSession,
      exercises: exercises,
    );
    debugPrint('  📦 Mapped Session startedAt: ${session.startedAt}');
    debugPrint('  📦 Mapped Session pausedAt: ${session.pausedAt}');

    return session;
  }

  /// Create new session
  /// Optimistic update: saves locally first, syncs to server if online
  Future<Session> createSession(Session session) async {
    final db = _localDb.database;

    // ALWAYS create locally first for instant response
    final localResult = await _createLocalSession(session, db, isPending: true);

    // Then sync to server in background if online (don't block)
    if (_connectivity.isOnline) {
      _syncCreateSessionToServer(session, db, localResult.id)
          .then((_) {
            debugPrint('✅ Background sync: Created session on server');
          })
          .catchError((e) {
            debugPrint('⚠️ Background sync failed, will retry later: $e');
          });
    } else {
      debugPrint('📴 Offline - session will sync later');
    }

    return localResult;
  }

  /// Helper method to convert LocalSession to Session with exercises
  /// Note: Uses _localSessionToSessionWithExercises helper for consistency
  Future<Session> _getSessionWithExercises(LocalSession localSession) async {
    final db = _localDb.database;
    return await _localSessionToSessionWithExercises(db, localSession);
  }

  /// Create a session from a program workout
  /// Links the session to the program and program workout
  /// Now works offline by parsing exercisesJson client-side
  Future<Session> createSessionFromProgramWorkout(
    int programWorkoutId,
    ProgramWorkout programWorkout,
    DateTime programStartDate,
    int programId, // Use actual programId instead of programWorkout.programId
  ) async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Check if a session already exists for this program workout
    final existingSessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .programWorkoutIdEqualTo(programWorkoutId)
            .findAll();

    // Find existing draft, planned, in_progress, or paused session
    final existingActiveSession = existingSessions.firstWhere(
      (session) =>
          session.status == 'draft' ||
          session.status == 'planned' ||
          session.status == 'in_progress' ||
          session.status == 'paused',
      orElse:
          () => LocalSession(
            userId: 0,
            date: DateTime.now(),
            type: '',
            name: '',
            status: '',
            lastModifiedLocal: DateTime.now(),
          ), // Dummy session
    );

    // If we found an existing active session, return it
    if (existingActiveSession.userId != 0) {
      debugPrint(
        '✅ Found existing ${existingActiveSession.status} session for program workout $programWorkoutId',
      );
      return await _getSessionWithExercises(existingActiveSession);
    }

    // Check if there's a completed session (can't restart completed workouts)
    final existingCompletedSession = existingSessions.firstWhere(
      (session) => session.status == 'completed',
      orElse:
          () => LocalSession(
            userId: 0,
            date: DateTime.now(),
            type: '',
            name: '',
            status: '',
            lastModifiedLocal: DateTime.now(),
          ),
    );

    // If past workout is already completed, can't start it again
    if (existingCompletedSession.userId != 0) {
      debugPrint('⚠️ Cannot start completed program workout $programWorkoutId');
      throw Exception(
        'This workout is already completed. You cannot start it again.',
      );
    }

    debugPrint(
      '📝 No existing draft/planned session found, creating new session for program workout $programWorkoutId',
    );

    // Try to create on server if online
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.post<Map<String, dynamic>>(
          ApiConfig.sessionsFromProgramWorkout,
          data: {
            'programWorkoutId': programWorkoutId,
            'programId': programId, // Send programId to backend
          },
        );
        var apiSession = Session.fromJson(data);

        // Use scheduledDate from ProgramWorkout if available (single source of truth)
        // This avoids timezone calculation issues - the date is stored on the server
        DateTime correctScheduledDate;
        if (programWorkout.scheduledDate != null) {
          final sd = programWorkout.scheduledDate!;
          correctScheduledDate = DateTime(sd.year, sd.month, sd.day);
        } else {
          // Fallback for old data: calculate using local time
          final localStartDate = programStartDate.toLocal();
          final startDate = DateTime(
            localStartDate.year,
            localStartDate.month,
            localStartDate.day,
          );
          correctScheduledDate = startDate.add(
            Duration(
              days:
                  (programWorkout.weekNumber - 1) * 7 +
                  (programWorkout.dayNumber - 1),
            ),
          );
        }

        final today = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        );

        // If scheduled date is in the past, reschedule to today
        final actualDate =
            correctScheduledDate.isBefore(today) ? today : correctScheduledDate;

        // Use the correct date from ProgramWorkout, not the API-calculated one
        final apiDate = DateTime(
          apiSession.date.year,
          apiSession.date.month,
          apiSession.date.day,
        );

        if (apiDate != actualDate) {
          debugPrint(
            '📅 Using scheduledDate from program workout: $apiDate -> $actualDate',
          );
          apiSession = apiSession.copyWith(date: actualDate);
        }

        // Cache the session locally with exercises
        await db.writeTxn(() async {
          final localSession = ModelMapper.sessionToLocal(
            apiSession,
            isSynced: true, // Session from server with correct date
          );
          await db.localSessions.put(localSession);

          // Cache exercises
          for (final apiExercise in apiSession.exercises) {
            final localExercise = ModelMapper.exerciseToLocal(
              apiExercise,
              sessionLocalId: localSession.localId,
              isSynced: true,
            );
            await db.localExercises.put(localExercise);
          }
        });

        debugPrint('✅ Created session from program workout: ${apiSession.id}');
        return apiSession;
      } catch (e) {
        debugPrint(
          '⚠️ Failed to create session on server, creating locally: $e',
        );
        // Fall through to offline creation
      }
    }

    // Offline creation: Parse exercisesJson and create locally
    debugPrint('📴 Creating session from program workout offline');

    // Parse exercises from JSON
    final exercisesData = programWorkout.exercises;
    final exercises = <Exercise>[];

    // Use scheduledDate from ProgramWorkout if available (single source of truth)
    DateTime normalizedScheduledDate;
    if (programWorkout.scheduledDate != null) {
      final sd = programWorkout.scheduledDate!;
      normalizedScheduledDate = DateTime(sd.year, sd.month, sd.day);
    } else {
      // Fallback for old data: calculate using local time
      final localStartDate = programStartDate.toLocal();
      final startDate = DateTime(
        localStartDate.year,
        localStartDate.month,
        localStartDate.day,
      );
      final scheduledDate = startDate.add(
        Duration(
          days:
              (programWorkout.weekNumber - 1) * 7 +
              (programWorkout.dayNumber - 1),
        ),
      );
      normalizedScheduledDate = DateTime(
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
      );
    }

    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    // If workout is in the past and being created now, reschedule to today
    // This allows users to catch up on missed workouts
    final actualDate =
        normalizedScheduledDate.isBefore(today)
            ? today // Reschedule missed workout to today
            : normalizedScheduledDate; // Keep original date for future workouts

    // Determine status based on scheduled date
    // - If scheduled for future: status = 'planned'
    // - If scheduled for today or past: status = 'draft' (user can start immediately)
    final status = actualDate.isAfter(today) ? 'planned' : 'draft';

    debugPrint(
      '📅 Workout scheduled for: $normalizedScheduledDate, ${actualDate != normalizedScheduledDate ? 'rescheduled to today' : 'using original date'}',
    );

    // Create session with calculated date and status
    final session = Session(
      id: 0, // Will be replaced with local ID
      userId: userId,
      date: actualDate, // Use rescheduled date for past workouts
      name: programWorkout.workoutName,
      type: programWorkout.workoutType ?? 'Workout',
      status: status, // Use calculated status
      programId:
          programId, // Use passed programId instead of programWorkout.programId
      programWorkoutId: programWorkoutId,
      exercises: exercises,
    );

    late int sessionLocalId;

    await db.writeTxn(() async {
      // Create session
      final localSession = LocalSession(
        serverId: null,
        userId: userId,
        date: session.date,
        duration: session.duration,
        notes: session.notes,
        type: session.type,
        name: session.name,
        status: session.status,
        startedAt: session.startedAt,
        completedAt: session.completedAt,
        pausedAt: session.pausedAt,
        programId: session.programId,
        programWorkoutId: session.programWorkoutId,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now(),
      );

      sessionLocalId = await db.localSessions.put(localSession);

      // Create exercises from exercisesJson
      for (final exerciseData in exercisesData) {
        final exerciseName = exerciseData['name'] as String? ?? 'Exercise';
        final exerciseTemplateId = exerciseData['exerciseTemplateId'] as int?;
        final notes = exerciseData['notes'] as String?;
        final restTime = exerciseData['rest'] as int?;

        final exercise = Exercise(
          id: 0, // Temporary
          sessionId: sessionLocalId, // Use local ID
          name: exerciseName,
          exerciseTemplateId: exerciseTemplateId,
          notes: notes,
          restTime: restTime,
          duration: null,
          exerciseSets: [],
        );

        final localExercise = ModelMapper.exerciseToLocal(
          exercise,
          sessionLocalId: sessionLocalId,
          isSynced: false,
        );
        final exerciseLocalId = await db.localExercises.put(localExercise);

        exercises.add(exercise.copyWith(id: exerciseLocalId));
      }
    });

    debugPrint(
      '💾 Created session offline with ${exercises.length} exercises (localId: $sessionLocalId)',
    );

    return Session(
      id: sessionLocalId,
      userId: userId,
      date: session.date,
      duration: session.duration,
      notes: session.notes,
      type: session.type,
      name: session.name,
      status: session.status,
      startedAt: session.startedAt,
      completedAt: session.completedAt,
      pausedAt: session.pausedAt,
      programId: session.programId,
      programWorkoutId: session.programWorkoutId,
      exercises: exercises,
    );
  }

  /// Background sync: Create session on server
  Future<void> _syncCreateSessionToServer(
    Session session,
    Isar db,
    int localId,
  ) async {
    try {
      final data = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.sessions,
        data: session.toJson(),
      );
      final apiSession = Session.fromJson(data);

      // Update local session with server ID
      await db.writeTxn(() async {
        final localSession = await db.localSessions.get(localId);
        if (localSession != null) {
          localSession.serverId = apiSession.id;
          localSession.isSynced = true;
          localSession.syncStatus = 'synced';
          await db.localSessions.put(localSession);
        }
      });
    } catch (e) {
      rethrow; // Let caller handle error
    }
  }

  /// Create session in local database
  Future<Session> _createLocalSession(
    Session session,
    Isar db, {
    required bool isPending,
  }) async {
    final localSession = LocalSession(
      serverId: isPending ? null : session.id,
      userId: session.userId,
      date: session.date,
      duration: session.duration,
      notes: session.notes,
      type: session.type,
      name: session.name,
      status: session.status,
      startedAt: session.startedAt,
      completedAt: session.completedAt,
      pausedAt: session.pausedAt,
      programId: session.programId,
      programWorkoutId: session.programWorkoutId,
      isSynced: !isPending,
      syncStatus: isPending ? 'pending_create' : 'synced',
      lastModifiedLocal: DateTime.now(),
    );

    await db.writeTxn(() => db.localSessions.put(localSession));

    debugPrint('💾 Saved session locally: ${localSession.localId}');

    // Return with local ID (temporary until synced)
    return Session(
      id: localSession.localId, // Use local ID temporarily
      userId: localSession.userId,
      date: localSession.date,
      duration: localSession.duration,
      notes: localSession.notes,
      type: localSession.type,
      name: localSession.name,
      status: localSession.status,
      startedAt: localSession.startedAt,
      completedAt: localSession.completedAt,
      pausedAt: localSession.pausedAt,
      programId: localSession.programId,
      programWorkoutId: localSession.programWorkoutId,
    );
  }

  /// Update session status
  /// Optimistic update: updates locally first, syncs to server if online
  /// [startedAtUtc] optional timestamp for when starting workout (calculated by provider)
  Future<Session> updateSessionStatus(
    int id,
    String status, {
    int? duration,
    DateTime? startedAtUtc,
  }) async {
    final Isar db = _localDb.database;

    // Find local session using helper
    final localSession = await _findLocalSessionOrThrow(db, id);

    // ALWAYS update locally first for instant response
    await _updateLocalSessionStatus(
      db,
      localSession,
      status,
      duration: duration,
      startedAtUtc: startedAtUtc,
    );

    // Then sync to server in background if online (using helper)
    if (_connectivity.isOnline && localSession.serverId != null) {
      _backgroundSync(
        () => _syncSessionStatusToServer(
          db,
          localSession.serverId!,
          localSession,
        ),
        'Updated session status on server',
      );
    } else {
      debugPrint('📴 Offline - session status will sync later');
    }

    // Return session with exercises using helper
    return await _localSessionToSessionWithExercises(db, localSession);
  }

  /// Background sync: Update session status on server
  Future<void> _syncSessionStatusToServer(
    Isar db,
    int serverId,
    LocalSession localSession,
  ) async {
    // Helper to convert Isar timestamp to proper UTC ISO8601 string with 'Z' suffix
    // CRITICAL: Isar loses the isUtc flag, so we must reconstruct UTC DateTime
    // before serializing to ensure the 'Z' suffix is included
    String? toUtcIso8601(DateTime? dt) {
      if (dt == null) return null;
      // Reconstruct as UTC (Isar stores the raw value, loses isUtc flag)
      final utc =
          dt.isUtc
              ? dt
              : DateTime.utc(
                dt.year,
                dt.month,
                dt.day,
                dt.hour,
                dt.minute,
                dt.second,
                dt.millisecond,
              );
      return utc.toIso8601String(); // Will include 'Z' suffix
    }

    try {
      // Send status AND timestamps to server (preserves timer state)
      // IMPORTANT: Use toUtcIso8601 to ensure proper UTC format with 'Z' suffix
      final startedAtString = toUtcIso8601(localSession.startedAt);
      final pausedAtString = toUtcIso8601(localSession.pausedAt);

      // DEBUG: Log exactly what we're sending
      debugPrint('🔄 SYNC DEBUG - Sending to server:');
      debugPrint('   localSession.startedAt: ${localSession.startedAt}');
      debugPrint(
        '   localSession.startedAt.isUtc: ${localSession.startedAt?.isUtc}',
      );
      debugPrint(
        '   localSession.startedAt.hour: ${localSession.startedAt?.hour}',
      );
      debugPrint('   toUtcIso8601 result: $startedAtString');
      debugPrint('   localSession.pausedAt: ${localSession.pausedAt}');
      debugPrint('   pausedAt toUtcIso8601: $pausedAtString');

      final data = {
        'status': localSession.status,
        if (localSession.startedAt != null) 'startedAt': startedAtString,
        if (localSession.completedAt != null)
          'completedAt': toUtcIso8601(localSession.completedAt),
        if (localSession.pausedAt != null) 'pausedAt': pausedAtString,
        // When pausedAt is null, tell server to clear it (for resume operation)
        if (localSession.pausedAt == null) 'clearPausedAt': true,
        if (localSession.duration != null) 'duration': localSession.duration,
      };

      debugPrint('   Full data payload: $data');

      await _apiService.patch<void>(
        ApiConfig.sessionStatus(serverId),
        data: data,
      );

      debugPrint(
        '✅ Synced session $serverId with timestamps (startedAt: ${localSession.startedAt})',
      );

      // Update sync status in local DB
      await db.writeTxn(() async {
        final session =
            await db.localSessions
                .filter()
                .serverIdEqualTo(serverId)
                .findFirst();
        if (session != null) {
          session.isSynced = true;
          session.syncStatus = 'synced';
          await db.localSessions.put(session);
        }
      });
    } catch (e) {
      rethrow; // Let caller handle error
    }
  }

  /// Update session status in local database
  /// [startedAtUtc] optional timestamp from provider (ensures UTC consistency)
  Future<void> _updateLocalSessionStatus(
    Isar db,
    LocalSession localSession,
    String status, {
    int? duration,
    DateTime? startedAtUtc,
  }) async {
    await db.writeTxn(() async {
      final now = DateTime.now();
      localSession.status = status;
      localSession.lastModifiedLocal = now;
      localSession.isSynced = false;

      // Set startedAt when status changes to 'in_progress'
      if (status == 'in_progress' && localSession.startedAt == null) {
        // CRITICAL FIX: Use timestamp from provider if provided (calculated outside transaction)
        // This ensures the same UTC calculation pattern as pause/resume which work correctly
        final timestampToUse = startedAtUtc ?? DateTime.now().toUtc();

        debugPrint('🏋️ REPOSITORY - Setting startedAt:');
        debugPrint('   Received startedAtUtc param: $startedAtUtc');
        debugPrint('   startedAtUtc.isUtc: ${startedAtUtc?.isUtc}');
        debugPrint('   startedAtUtc.hour: ${startedAtUtc?.hour}');
        debugPrint('   timestampToUse: $timestampToUse');
        debugPrint('   timestampToUse.isUtc: ${timestampToUse.isUtc}');
        debugPrint('   timestampToUse.hour: ${timestampToUse.hour}');

        localSession.startedAt = timestampToUse;
        localSession.pausedAt = null; // Clear any pause state

        debugPrint(
          '   After assignment - localSession.startedAt: ${localSession.startedAt}',
        );
        debugPrint(
          '   After assignment - localSession.startedAt.isUtc: ${localSession.startedAt?.isUtc}',
        );
        debugPrint(
          '   After assignment - localSession.startedAt.hour: ${localSession.startedAt?.hour}',
        );
      }

      // Set completedAt when status changes to 'completed'
      if (status == 'completed' && localSession.completedAt == null) {
        final completedAtUtc = DateTime.now().toUtc();
        localSession.completedAt = completedAtUtc;
        debugPrint('✅ Set completedAt in DB (UTC): $completedAtUtc');

        // Update workout frequency goals when a workout is completed (Issue #11)
        final userId = await _authService.getUserId();
        if (userId != null) {
          await _updateWorkoutGoals(db, userId, completedAtUtc);
        }
      }

      // Update duration if provided (from timer elapsed time)
      if (duration != null) {
        localSession.duration = duration;
        debugPrint('⏱️ Set duration in DB: $duration minutes');
      }

      // Only mark as pending_update if session already exists on server
      // If no serverId, keep it as pending_create
      if (localSession.serverId != null) {
        localSession.syncStatus = 'pending_update';
      }
      await db.localSessions.put(localSession);

      // DEBUG: Check if Isar modified the object
      debugPrint('🗄️ AFTER ISAR PUT:');
      debugPrint('   localSession.startedAt: ${localSession.startedAt}');
      debugPrint(
        '   localSession.startedAt.isUtc: ${localSession.startedAt?.isUtc}',
      );
      debugPrint(
        '   localSession.startedAt.hour: ${localSession.startedAt?.hour}',
      );
    });
  }

  /// Update workout frequency goals when a workout is completed (Issue #11)
  /// This ensures goals update even when offline
  ///
  /// NOTE: Currently goals are server-only (no LocalGoal model exists).
  /// This method documents the intended client-side goal update logic.
  /// To fully implement offline goal updates, you would need to:
  /// 1. Create a LocalGoal model (lib/data/local/models/local_goal.dart)
  /// 2. Add goals to LocalDatabaseService collections
  /// 3. Update GoalsRepository to use offline-first pattern
  /// 4. Uncomment the implementation below
  ///
  /// For now, goal updates only happen server-side via SessionsController.cs
  Future<void> _updateWorkoutGoals(
    Isar db,
    int userId,
    DateTime completedAt,
  ) async {
    debugPrint(
      '📊 Goal updates (Issue #11): Currently server-only. LocalGoal model needed for offline support.',
    );

    // TODO: Uncomment when LocalGoal model is created
    /*
    try {
      // Find active workout frequency goals
      final goals = await db.localGoals
        .filter()
        .userIdEqualTo(userId)
        .isActiveEqualTo(true)
        .goalTypeContains('workout', caseSensitive: false)
        .or()
        .goalTypeContains('frequency', caseSensitive: false)
        .findAll();

      if (goals.isEmpty) {
        debugPrint('📊 No active workout frequency goals to update');
        return;
      }

      await db.writeTxn(() async {
        for (final goal in goals) {
          // Increment currentValue
          final oldValue = goal.currentValue ?? 0;
          goal.currentValue = oldValue + 1;

          debugPrint('📊 Updated goal "${goal.goalType}": $oldValue → ${goal.currentValue}/${goal.targetValue}');

          // Check if goal is now complete
          if (goal.currentValue! >= goal.targetValue!) {
            goal.isCompleted = true;
            goal.completedAt = completedAt;
            debugPrint('🎉 Goal completed: ${goal.goalType}');
          }

          // Mark as needing sync
          goal.isSynced = false;
          if (goal.serverId != null) {
            goal.syncStatus = 'pending_update';
          }
          goal.lastModifiedLocal = DateTime.now();

          await db.localGoals.put(goal);
        }
      });

      debugPrint('✅ Updated ${goals.length} workout goals locally');
    } catch (e) {
      debugPrint('⚠️ Failed to update workout goals: $e');
      // Don't throw - goal updates are non-critical
    }
    */
  }

  /// Pause session timer
  /// Works offline by updating local database
  /// [pausedAt] timestamp from provider (to avoid time drift)
  Future<void> pauseSession(int id, DateTime pausedAt) async {
    final Isar db = _localDb.database;

    // Find local session using helper
    final localSession = await _findLocalSessionOrThrow(db, id);

    // ALWAYS update locally first for instant response
    await db.writeTxn(() async {
      localSession.pausedAt = pausedAt; // Use provided timestamp (already UTC)
      localSession.lastModifiedLocal = DateTime.now();
      localSession.isSynced = false;
      if (localSession.serverId != null) {
        localSession.syncStatus = 'pending_update';
      }
      await db.localSessions.put(localSession);
    });

    debugPrint('⏸️ Session paused locally (pausedAt UTC: $pausedAt)');

    // Then sync to server in background if online (using helper)
    if (_connectivity.isOnline && localSession.serverId != null) {
      _backgroundSync(
        () => _syncSessionStatusToServer(
          db,
          localSession.serverId!,
          localSession,
        ),
        'Pause synced to server',
      );
    }
  }

  /// Resume session timer
  /// Works offline by updating local database
  /// [newStartedAt] adjusted timestamp from provider (to avoid time drift)
  Future<void> resumeSession(int id, DateTime newStartedAt) async {
    final Isar db = _localDb.database;

    // Find local session using helper
    final localSession = await _findLocalSessionOrThrow(db, id);

    // ALWAYS update locally first for instant response
    await db.writeTxn(() async {
      // Use the adjusted startedAt provided by provider (already calculated)
      localSession.startedAt = newStartedAt;
      localSession.pausedAt = null;
      localSession.lastModifiedLocal = DateTime.now();
      localSession.isSynced = false;
      if (localSession.serverId != null) {
        localSession.syncStatus = 'pending_update';
      }
      await db.localSessions.put(localSession);
      debugPrint('▶️ Adjusted startedAt to: $newStartedAt');
    });

    debugPrint('▶️ Session resumed locally');

    // Then sync to server in background if online (using helper)
    if (_connectivity.isOnline && localSession.serverId != null) {
      _backgroundSync(
        () => _syncSessionStatusToServer(
          db,
          localSession.serverId!,
          localSession,
        ),
        'Resume synced to server',
      );
    }
  }

  /// Archive a session (change status to 'archived')
  /// Archived sessions are hidden from main list but still count for programs
  Future<bool> archiveSession(int id) async {
    final Isar db = _localDb.database;

    // Find local session using helper
    final localSession = await _findLocalSessionOrThrow(db, id);

    // Change status to archived (using helper for standard sync marking)
    await _markSessionForSync(db, localSession, newStatus: 'archived');

    debugPrint(
      '📦 Archived session: ${localSession.serverId ?? localSession.localId}',
    );
    return true;
  }

  /// Delete session
  /// Marks as pending_delete offline, deletes from server when online
  Future<bool> deleteSession(int id) async {
    final Isar db = _localDb.database;

    // Find local session using helper
    final localSession = await _findLocalSessionOrThrow(db, id);

    // Prevent deletion of completed program workouts
    if (localSession.status == 'completed' &&
        localSession.programWorkoutId != null) {
      throw Exception(
        'Cannot delete completed program workout. Archive it instead.',
      );
    }

    if (_connectivity.isOnline && localSession.serverId != null) {
      try {
        // Delete from server
        final success = await _apiService.delete(
          ApiConfig.sessionById(localSession.serverId!),
        );

        if (success) {
          // Delete from local database (including exercises and sets)
          await _deleteSessionAndRelatedData(db, localSession);
          debugPrint('✅ Deleted session from server: ${localSession.serverId}');
          return true;
        }
        return false;
      } catch (e) {
        debugPrint('⚠️ Delete API failed, marking as pending: $e');
        await _markForDeletion(db, localSession);
        return true;
      }
    } else {
      debugPrint('📴 Offline - marking session for deletion');
      await _markForDeletion(db, localSession);
      return true;
    }
  }

  /// Mark session for deletion (to be synced later)
  Future<void> _markForDeletion(Isar db, LocalSession localSession) async {
    if (localSession.serverId == null) {
      // Never synced to server - safe to delete immediately (with related data)
      await _deleteSessionAndRelatedData(db, localSession);
    } else {
      // Synced before - mark for deletion
      await db.writeTxn(() async {
        localSession.isSynced = false;
        localSession.syncStatus = 'pending_delete';
        localSession.lastModifiedLocal = DateTime.now();
        await db.localSessions.put(localSession);
      });
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

  /// Update session name
  /// Optimistic update: updates locally first, syncs to server if online
  Future<Session> updateSessionName(int id, String name) async {
    final Isar db = _localDb.database;

    // Find local session using helper
    final localSession = await _findLocalSessionOrThrow(db, id);

    // ALWAYS update locally first for instant response
    await db.writeTxn(() async {
      localSession.name = name;
      localSession.lastModifiedLocal = DateTime.now();
      localSession.isSynced = false;
      if (localSession.serverId != null) {
        localSession.syncStatus = 'pending_update';
      }
      await db.localSessions.put(localSession);
    });

    debugPrint('✏️ Session name updated locally to: $name');

    // Then sync to server in background if online (using helper)
    if (_connectivity.isOnline && localSession.serverId != null) {
      _backgroundSync(
        () => _syncSessionNameToServer(db, localSession.serverId!, name),
        'Updated session name on server',
      );
    } else {
      debugPrint('📴 Offline - session name will sync later');
    }

    // Return session with exercises using helper
    return await _localSessionToSessionWithExercises(db, localSession);
  }

  /// Update workout date (used when starting future planned workout early)
  /// Optimistic update: updates locally first, syncs to server if online
  Future<void> updateWorkoutDate(int id, DateTime newDate) async {
    final Isar db = _localDb.database;

    // Find local session using helper
    final localSession = await _findLocalSessionOrThrow(db, id);

    // ALWAYS update locally first for instant response
    await db.writeTxn(() async {
      // Convert to date-only (no time component)
      final dateOnly = DateTime(newDate.year, newDate.month, newDate.day);
      localSession.date = dateOnly;
      localSession.lastModifiedLocal = DateTime.now();
      localSession.isSynced = false;
      if (localSession.serverId != null) {
        localSession.syncStatus = 'pending_update';
      }
      await db.localSessions.put(localSession);
    });

    debugPrint('📅 Workout date updated locally to: $newDate');

    // Then sync to server in background if online (using helper)
    if (_connectivity.isOnline && localSession.serverId != null) {
      _backgroundSync(
        () => _syncSessionDateToServer(db, localSession.serverId!, newDate),
        'Updated workout date on server',
      );
    } else {
      debugPrint('📴 Offline - workout date will sync later');
    }
  }

  /// Background sync: Update workout date on server
  Future<void> _syncSessionDateToServer(
    Isar db,
    int serverId,
    DateTime newDate,
  ) async {
    try {
      // Fetch the current session to send full data (required by PUT)
      final session =
          await db.localSessions.filter().serverIdEqualTo(serverId).findFirst();

      if (session == null) return;

      // Convert to API model
      final apiSession = ModelMapper.localToSession(session);
      final updateData = apiSession.toJson();

      await _apiService.put<void>(
        ApiConfig.sessionById(serverId),
        data: updateData,
      );

      // Mark as synced
      await db.writeTxn(() async {
        final updatedSession =
            await db.localSessions
                .filter()
                .serverIdEqualTo(serverId)
                .findFirst();
        if (updatedSession != null) {
          updatedSession.isSynced = true;
          updatedSession.syncStatus = 'synced';
          await db.localSessions.put(updatedSession);
        }
      });
    } on DioException catch (e) {
      // Handle version conflicts (Issue #13)
      if (e.response?.statusCode == 409) {
        debugPrint('⚠️ Conflict detected - server version is newer');

        // Server wins: reload fresh data from server
        try {
          final serverSession = await getSession(serverId);

          // Update local cache with server version
          await db.writeTxn(() async {
            final localSession =
                await db.localSessions
                    .filter()
                    .serverIdEqualTo(serverId)
                    .findFirst();
            if (localSession != null) {
              final updated = ModelMapper.sessionToLocal(
                serverSession,
                localId: localSession.localId,
                isSynced: true,
              );
              await db.localSessions.put(updated);
            }
          });

          debugPrint('🔄 Local session updated with server version');
        } catch (reloadError) {
          debugPrint('⚠️ Failed to reload server session: $reloadError');
        }
      } else {
        rethrow;
      }
    } catch (e) {
      debugPrint('Error syncing workout date to server: $e');
      rethrow;
    }
  }

  /// Background sync: Update session name on server
  Future<void> _syncSessionNameToServer(
    Isar db,
    int serverId,
    String name,
  ) async {
    try {
      // Fetch the current session to send full data (required by PUT)
      final session =
          await db.localSessions.filter().serverIdEqualTo(serverId).findFirst();

      if (session == null) return;

      // Convert to API model
      final apiSession = ModelMapper.localToSession(session);
      final updateData = apiSession.toJson();
      updateData['name'] = name; // Ensure name is updated

      await _apiService.put<void>(
        ApiConfig.sessionById(serverId),
        data: updateData,
      );

      // Update sync status in local DB
      await db.writeTxn(() async {
        final localSession =
            await db.localSessions
                .filter()
                .serverIdEqualTo(serverId)
                .findFirst();
        if (localSession != null) {
          localSession.isSynced = true;
          localSession.syncStatus = 'synced';
          await db.localSessions.put(localSession);
        }
      });
    } on DioException catch (e) {
      // Handle version conflicts (Issue #13)
      if (e.response?.statusCode == 409) {
        debugPrint('⚠️ Conflict detected - server version is newer');

        // Server wins: reload fresh data from server
        try {
          final serverSession = await getSession(serverId);

          // Update local cache with server version
          await db.writeTxn(() async {
            final localSession =
                await db.localSessions
                    .filter()
                    .serverIdEqualTo(serverId)
                    .findFirst();
            if (localSession != null) {
              final updated = ModelMapper.sessionToLocal(
                serverSession,
                localId: localSession.localId,
                isSynced: true,
              );
              await db.localSessions.put(updated);
            }
          });

          debugPrint('🔄 Local session updated with server version');
        } catch (reloadError) {
          debugPrint('⚠️ Failed to reload server session: $reloadError');
        }
      } else {
        rethrow;
      }
    } catch (e) {
      rethrow; // Let caller handle error
    }
  }

  /// Watch sessions for reactive updates (Issue #7)
  /// Returns a stream that emits whenever sessions change in local DB
  /// This enables automatic UI updates when background sync completes
  Stream<List<Session>> watchSessions(int userId) {
    final db = _localDb.database;

    return db.localSessions
        .filter()
        .userIdEqualTo(userId)
        .watch(fireImmediately: true)
        .asyncMap((localSessions) async {
          // Convert local sessions to domain models with exercises (using helper)
          final sessions = <Session>[];
          for (final localSession in localSessions) {
            // Skip deleted or archived sessions
            if (localSession.syncStatus == 'pending_delete' ||
                localSession.status == 'archived') {
              continue;
            }
            sessions.add(
              await _localSessionToSessionWithExercises(db, localSession),
            );
          }

          // Sort by date descending
          sessions.sort((a, b) => b.date.compareTo(a.date));
          return sessions;
        });
  }

  /// Add exercise to session
  /// Works offline by creating locally and syncing later
  Future<Exercise> addExerciseToSession(
    int sessionId,
    int exerciseTemplateId,
  ) async {
    final Isar db = _localDb.database;

    // Find local session using helper
    final localSession = await _findLocalSessionOrThrow(db, sessionId);

    if (_connectivity.isOnline && localSession.serverId != null) {
      try {
        // Try API first
        final data = await _apiService.post<Map<String, dynamic>>(
          ApiConfig.sessionExercises(localSession.serverId!),
          data: {'exerciseTemplateId': exerciseTemplateId},
        );
        final apiExercise = Exercise.fromJson(data);

        // Cache the exercise locally
        await db.writeTxn(() async {
          final localExercise = ModelMapper.exerciseToLocal(
            apiExercise,
            sessionLocalId: localSession.localId,
            isSynced: true,
          );
          await db.localExercises.put(localExercise);
        });

        return apiExercise;
      } catch (e) {
        debugPrint('⚠️ Add exercise API failed, creating locally: $e');
        // Fall through to offline creation
      }
    }

    // Create exercise locally (offline or API failed)
    // Get exercise template name from local cache
    String exerciseName = 'Exercise'; // Default name
    try {
      final templates =
          await db.collection<LocalExerciseTemplate>().where().findAll();
      final template = templates.firstWhere(
        (t) => t.serverId == exerciseTemplateId,
        orElse: () => templates.first,
      );
      exerciseName = template.name;
    } catch (e) {
      debugPrint('⚠️ Could not find exercise template $exerciseTemplateId: $e');
    }

    int localId = 0;

    await db.writeTxn(() async {
      final tempExercise = Exercise(
        id: 0, // Temporary, will be replaced
        sessionId: sessionId,
        name: exerciseName,
        exerciseTemplateId: exerciseTemplateId,
        duration: null,
        restTime: null,
        notes: null,
        exerciseSets: [],
      );

      final localExercise = ModelMapper.exerciseToLocal(
        tempExercise,
        sessionLocalId: localSession.localId,
        isSynced: false,
      );
      localId = await db.localExercises.put(localExercise);
    });

    // Return exercise with local ID and name
    final newExercise = Exercise(
      id: localId, // Use local ID temporarily
      sessionId: sessionId,
      name: exerciseName,
      exerciseTemplateId: exerciseTemplateId,
      duration: null,
      restTime: null,
      notes: null,
      exerciseSets: [],
    );

    debugPrint(
      '➕ Created exercise "$exerciseName" locally (offline), id=$localId, will sync later',
    );
    return newExercise;
  }
}
