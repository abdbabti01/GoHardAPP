import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/goal.dart';
import '../models/goal_progress.dart';
import '../services/api_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';

/// Repository for goals operations.
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
/// `AuthService` at all, and it has no local (Isar) cache.
///
/// A `null` capture (logged out, or the session changed while the JWT read
/// was in flight) is treated per-method, matching each method's own
/// pre-existing "nothing to return" convention:
///
/// - [getGoals] - the one list-returning GET with an established
///   "no data available" result (`[]` when offline); a null capture folds
///   into that same convention.
/// - Every other method operates on one required record / query with no safe
///   empty result, so a null capture is itself a stale state ->
///   [SessionStaleException], matching `BodyMetricsRepository`'s convention
///   for single-record and destructive operations.
///
/// There is no nested, recovery, pagination, or follow-up HTTP anywhere in
/// this repository - a single bound call per method is the entire surface.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures.
/// [getGoals] is the only method with a pre-existing `catch` block; it
/// rethrows both unchanged, before its generic logging/rethrow, so neither
/// is ever logged as an ordinary failure or converted into a successful
/// empty result. The remaining methods had no `catch` block before this
/// change and still have none - both exception types already propagate to
/// the caller untouched. `GoalsProvider`'s own session/generation guards
/// discard both without publishing.
class GoalsRepository {
  final ApiService _apiService;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// `AuthProvider`, `BodyMetricsRepository`, `AnalyticsRepository`, etc.
  /// (see main.dart). Only `AuthProvider` calls activate()/invalidate();
  /// this repository only ever reads it indirectly, through the context
  /// [_sessionCoordinator] derives from it - it holds no Isar state and does
  /// no post-`await` local write, so every staleness decision is made by
  /// [ApiService] against [SessionRequestContext.epochToken] (matches
  /// `BodyMetricsRepository`'s identical unused-field rationale).
  // ignore: unused_field
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext]
  /// (pinned JWT + generation-scoped CancelToken) for every session-bound
  /// HTTP call. The SAME instance handed to every other session-bound
  /// repository; never constructed privately.
  final SessionRequestCoordinator _sessionCoordinator;

  final ConnectivityService? _connectivity;

  GoalsRepository(
    this._apiService,
    this._sessionEpoch,
    this._sessionCoordinator, [
    this._connectivity,
  ]);

  /// Captures the session context for one operation, or `null` if there is
  /// no authenticated session to act for.
  Future<SessionRequestContext?> _capture() =>
      _sessionCoordinator.captureContext();

  /// Get all goals for the current user
  /// Optional filter: isActive (true for active goals, false for inactive/completed)
  Future<List<Goal>> getGoals({bool? isActive}) async {
    final context = await _capture();
    if (context == null) {
      debugPrint('⚠️ Goals: no active session - skipping getGoals');
      return [];
    }

    final isOnline = _connectivity?.isOnline ?? true;

    if (!isOnline) {
      debugPrint('📴 Offline - goals feature requires online connection');
      return [];
    }

    try {
      final queryParams =
          isActive != null ? {'isActive': isActive.toString()} : null;
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.goals,
        queryParameters: queryParams,
        sessionContext: context,
      );

      return data
          .map((json) => Goal.fromJson(json as Map<String, dynamic>))
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch goals: $e');
      rethrow;
    }
  }

  /// Get a specific goal by ID with progress history
  Future<Goal> getGoalById(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.goalById(id),
      sessionContext: context,
    );
    return Goal.fromJson(data);
  }

  /// Create a new goal
  Future<Goal> createGoal(Goal goal) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.goals,
      data: goal.toJson(),
      sessionContext: context,
    );
    return Goal.fromJson(data);
  }

  /// Update an existing goal
  Future<void> updateGoal(int id, Goal goal) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.put<void>(
      ApiConfig.goalById(id),
      data: goal.toJson(),
      sessionContext: context,
    );
  }

  /// Get deletion impact for a goal
  Future<Map<String, int>> getDeletionImpact(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.goalDeletionImpact(id),
      sessionContext: context,
    );
    return {
      'programsCount': data['programsCount'] as int,
      'sessionsCount': data['sessionsCount'] as int,
    };
  }

  /// Delete a goal
  Future<void> deleteGoal(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.delete(ApiConfig.goalById(id), sessionContext: context);
  }

  /// Mark a goal as completed
  Future<void> completeGoal(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.put<void>(
      ApiConfig.goalComplete(id),
      sessionContext: context,
    );
  }

  /// Add progress entry for a goal
  /// This also updates the goal's current value and may auto-complete the goal
  Future<GoalProgress> addProgress(int goalId, GoalProgress progress) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.goalProgress(goalId),
      data: progress.toJson(),
      sessionContext: context,
    );
    return GoalProgress.fromJson(data);
  }

  /// Get progress history for a goal
  Future<List<GoalProgress>> getProgressHistory(int goalId) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.goalHistory(goalId),
      sessionContext: context,
    );
    return data
        .map((json) => GoalProgress.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
