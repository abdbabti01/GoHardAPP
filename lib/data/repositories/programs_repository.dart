import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/program.dart';
import '../models/program_workout.dart';
import '../services/api_service.dart';
import '../local/services/local_database_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../local/models/local_session.dart';

/// Repository for programs operations.
///
/// ## Session binding
///
/// Every authenticated operation below captures exactly one
/// [SessionRequestContext] via [_sessionCoordinator] at operation entry -
/// before any other `await` - and passes that SAME context to each of its
/// [ApiService] calls, so the request carries the JWT pinned at capture time
/// (never the live secure-storage token) and the generation-scoped
/// `CancelToken` that a logout aborts. Live credentials are never reread
/// after an operation starts - this repository does not depend on
/// `AuthService` at all.
///
/// A `null` capture (logged out, or the session changed while the JWT read
/// was in flight) is treated per-method, matching each method's own
/// pre-existing "nothing to return" convention:
///
/// - [getPrograms] - the one list-returning GET with an established
///   "no data available" result (`[]` when offline); a null capture folds
///   into that same convention.
/// - Every other method operates on one required record / query with no safe
///   empty result, so a null capture is itself a stale state ->
///   [SessionStaleException], matching `GoalsRepository`'s convention for
///   single-record and destructive operations.
///
/// ## Local completion overlay
///
/// [getPrograms] and [getProgramById] fold locally-recorded workout
/// completion (`My Workouts` sessions) onto the freshly-fetched program via
/// [_syncWorkoutCompletionStatus]. That helper reads - never writes - the
/// `localSessions` collection, and this repository persists no rows of its
/// own (the `localPrograms` / `localProgramWorkouts` collections are owned
/// exclusively by `SyncService`, out of scope here). The overlay is scoped
/// to `context.epochToken.userId` - the user captured at operation entry,
/// never a live `AuthService.getUserId()` re-read.
///
/// The helper checks [UserSessionEpoch.isCurrent] against the captured token
/// on entry (ahead of its "nothing to overlay" early returns, so a
/// workout-less program is guarded too) AND again immediately after its Isar
/// read, and [getPrograms] repeats the check at the top of every loop
/// iteration. If the captured session has stopped being current at any of
/// those points the helper throws [SessionStaleException] - it never returns
/// captured-user Program data (overlaid OR un-overlaid) once the session is
/// lost, and [getPrograms] never returns a partially overlaid list. Lifecycle exceptions
/// ([SessionStaleException] / [RequestCancelledException]) are rethrown ahead
/// of the helper's generic `catch`, so an ordinary Isar/read failure still
/// falls back to the un-overlaid Program (the established non-lifecycle
/// contract) while a stale session does not.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures.
/// [getPrograms] is the only method with a pre-existing `catch` block; it
/// rethrows both unchanged, before its generic logging/rethrow, so neither
/// is ever logged as an ordinary failure or converted into a successful
/// empty result. The remaining methods had no `catch` block before this
/// change and still have none - both exception types already propagate to
/// the caller untouched. `ProgramsProvider`'s own session/generation guards
/// discard both without publishing.
class ProgramsRepository {
  final ApiService _apiService;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// `AuthProvider`, `GoalsRepository`, `BodyMetricsRepository`, etc. (see
  /// main.dart). Only `AuthProvider` calls activate()/invalidate(); this
  /// repository only ever reads it - through [UserSessionEpoch.isCurrent] in
  /// [_syncWorkoutCompletionStatus] to abandon a stale local overlay - and
  /// indirectly through the context [_sessionCoordinator] derives from it.
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext]
  /// (pinned JWT + generation-scoped CancelToken) for every session-bound
  /// HTTP call. The SAME instance handed to every other session-bound
  /// repository; never constructed privately.
  final SessionRequestCoordinator _sessionCoordinator;

  final ConnectivityService? _connectivity;
  final LocalDatabaseService? _localDb;

  ProgramsRepository(
    this._apiService,
    this._sessionEpoch,
    this._sessionCoordinator, [
    this._connectivity,
    this._localDb,
  ]);

  /// Captures the session context for one operation, or `null` if there is
  /// no authenticated session to act for.
  Future<SessionRequestContext?> _capture() =>
      _sessionCoordinator.captureContext();

  /// Test-only seam: awaited immediately after the completion-overlay's Isar
  /// read of `localSessions` and before its [UserSessionEpoch.isCurrent]
  /// recheck, so a test can land a logout / user switch exactly in that
  /// window. Null in production - setting it never changes control flow or
  /// performance.
  @visibleForTesting
  Future<void> Function()? afterLocalSessionsReadForTesting;

  /// Get all programs for the current user
  /// Optional filter: isActive (true for active programs, false for inactive/completed)
  Future<List<Program>> getPrograms({bool? isActive}) async {
    final context = await _capture();
    if (context == null) {
      debugPrint('⚠️ Programs: no active session - skipping getPrograms');
      return [];
    }

    final isOnline = _connectivity?.isOnline ?? true;

    if (!isOnline) {
      debugPrint('📴 Offline - programs feature requires online connection');
      return [];
    }

    try {
      final queryParams =
          isActive != null ? {'isActive': isActive.toString()} : null;
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.programs,
        queryParameters: queryParams,
        sessionContext: context,
      );

      final programs =
          data
              .map((json) => Program.fromJson(json as Map<String, dynamic>))
              .toList();

      // Sync workout completion status for each program. Guard the captured
      // session at the top of EVERY iteration and stop immediately when it is
      // no longer current - never return a partially overlaid User-A list
      // after the session changes. (_syncWorkoutCompletionStatus repeats the
      // check around its own await.)
      final syncedPrograms = <Program>[];
      for (final program in programs) {
        if (!_sessionEpoch.isCurrent(context.epochToken)) {
          throw const SessionStaleException();
        }
        syncedPrograms.add(
          await _syncWorkoutCompletionStatus(program, context),
        );
      }

      return syncedPrograms;
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch programs: $e');
      rethrow;
    }
  }

  /// Get a specific program by ID with all workouts
  Future<Program> getProgramById(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.programById(id),
      sessionContext: context,
    );
    var program = Program.fromJson(data);

    // Sync workout completion status from local sessions
    program = await _syncWorkoutCompletionStatus(program, context);

    return program;
  }

  /// Sync program workout completion status from local sessions
  /// This ensures that workouts completed via "My Workouts" are reflected in the program
  Future<Program> _syncWorkoutCompletionStatus(
    Program program,
    SessionRequestContext context,
  ) async {
    // Pre-read lifecycle check FIRST - ahead of the "nothing to overlay" early
    // returns below - so this helper never hands back captured-user Program
    // data (even a workout-less one, even with no local db) after the captured
    // session has stopped being current. This is the only lifecycle guard for
    // a workout-less Program, so it must run before those returns.
    if (!_sessionEpoch.isCurrent(context.epochToken)) {
      throw const SessionStaleException();
    }

    // Nothing to overlay: no local database access.
    if (_localDb == null) {
      return program;
    }

    // Nothing to overlay: program has no workouts.
    if (program.workouts == null || program.workouts!.isEmpty) {
      return program;
    }

    try {
      final db = _localDb.database;
      // Scope the overlay to the user captured at operation entry - never a
      // live re-read.
      final userId = context.epochToken.userId;

      // Get all sessions for this program
      final sessions =
          await db.localSessions
              .filter()
              .userIdEqualTo(userId)
              .programIdEqualTo(program.id)
              .findAll();

      final hook = afterLocalSessionsReadForTesting;
      if (hook != null) await hook();

      // Post-read lifecycle check: a logout / user switch that landed during
      // the Isar read means this result belongs to a session that is no
      // longer current. Fail the whole operation - never return captured-user
      // Program data (overlaid OR un-overlaid) after losing the captured
      // session.
      if (!_sessionEpoch.isCurrent(context.epochToken)) {
        throw const SessionStaleException();
      }

      // Create a map of programWorkoutId -> completion status
      final completionMap = <int, bool>{};
      for (final session in sessions) {
        if (session.programWorkoutId != null) {
          // Workout is completed if session is completed OR archived (archived still counts as completed)
          final isCompleted =
              session.status == 'completed' || session.status == 'archived';
          completionMap[session.programWorkoutId!] = isCompleted;
        }
      }

      // Update workout completion status
      final updatedWorkouts =
          program.workouts!.map((workout) {
            final isCompleted =
                completionMap[workout.id] ?? workout.isCompleted;
            return workout.copyWith(isCompleted: isCompleted);
          }).toList();

      return program.copyWith(workouts: updatedWorkouts);
    } on SessionStaleException {
      // Lifecycle staleness is not an overlay failure - rethrow ahead of the
      // generic fallback so it is never converted into un-overlaid data.
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      // Ordinary Isar/read failure keeps the established "return the
      // un-overlaid Program" fallback.
      debugPrint('⚠️ Failed to sync workout completion status: $e');
      return program;
    }
  }

  /// Create a new program
  Future<Program> createProgram(Program program) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.programs,
      data: program.toJson(),
      sessionContext: context,
    );
    return Program.fromJson(data);
  }

  /// Update an existing program
  Future<void> updateProgram(int id, Program program) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.put<void>(
      ApiConfig.programById(id),
      data: program.toJson(),
      sessionContext: context,
    );
  }

  /// Get deletion impact for a program
  Future<Map<String, int>> getDeletionImpact(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.programDeletionImpact(id),
      sessionContext: context,
    );
    return {'sessionsCount': data['sessionsCount'] as int};
  }

  /// Delete a program
  Future<void> deleteProgram(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.delete(
      ApiConfig.programById(id),
      sessionContext: context,
    );
  }

  /// Mark a program as completed
  Future<void> completeProgram(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.put<void>(
      ApiConfig.programComplete(id),
      sessionContext: context,
    );
  }

  /// Recalibrate a program's start date to Monday of its week
  /// Fixes calendar alignment issues for programs created on non-Monday days
  Future<Map<String, dynamic>> recalibrateProgram(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.put<Map<String, dynamic>>(
      ApiConfig.programRecalibrate(id),
      sessionContext: context,
    );
    return data;
  }

  /// Advance to next workout (increment day/week)
  Future<Program> advanceProgram(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.put<Map<String, dynamic>>(
      ApiConfig.programAdvance(id),
      sessionContext: context,
    );
    return Program.fromJson(data);
  }

  /// Get workouts for a specific week
  Future<List<ProgramWorkout>> getWeekWorkouts(
    int programId,
    int weekNumber,
  ) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.programWeek(programId, weekNumber),
      sessionContext: context,
    );
    return data
        .map((json) => ProgramWorkout.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get today's workout
  Future<ProgramWorkout> getTodaysWorkout(int programId) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.programToday(programId),
      sessionContext: context,
    );
    return ProgramWorkout.fromJson(data);
  }

  /// Add a workout to a program
  Future<ProgramWorkout> addWorkout(
    int programId,
    ProgramWorkout workout,
  ) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.programWorkouts(programId),
      data: workout.toJson(),
      sessionContext: context,
    );
    return ProgramWorkout.fromJson(data);
  }

  /// Update a program workout
  Future<void> updateWorkout(int workoutId, ProgramWorkout workout) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.put<void>(
      ApiConfig.programWorkoutById(workoutId),
      data: workout.toJson(),
      sessionContext: context,
    );
  }

  /// Swap two program workouts atomically
  Future<void> swapWorkouts(int workout1Id, int workout2Id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.post<void>(
      '${ApiConfig.programs}/workouts/swap',
      data: {'workout1Id': workout1Id, 'workout2Id': workout2Id},
      sessionContext: context,
    );
  }

  /// Mark a workout as completed
  Future<void> completeWorkout(int workoutId, {String? notes}) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.put<void>(
      ApiConfig.programWorkoutComplete(workoutId),
      data: notes,
      sessionContext: context,
    );
  }

  /// Delete a workout
  Future<void> deleteWorkout(int workoutId) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.delete(
      ApiConfig.programWorkoutById(workoutId),
      sessionContext: context,
    );
  }
}
