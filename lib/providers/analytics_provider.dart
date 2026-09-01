import 'dart:collection';

import 'package:flutter/foundation.dart';
import '../core/services/user_session_epoch.dart';
import '../data/repositories/analytics_repository.dart';
import '../data/services/session_request_exceptions.dart';
import '../data/models/workout_stats.dart';

/// Provider for the analytics dashboard.
///
/// ## Session ownership
///
/// App-scoped provider: a single instance created with `previous ??`
/// outlives logout/login (see main.dart), so a continuation started under
/// user A must never publish into the state user B now sees through this
/// same instance. Every async method captures `_sessionEpoch.capture()`
/// before its first `await` and rechecks ownership after every `await` - in
/// the success path, `catch`, and `finally` - before it touches
/// `_workoutStats`, a list, a flag, the error, or calls `notifyListeners()`.
/// A `null` capture (logged out) returns immediately using each method's
/// existing return convention without starting work.
///
/// ## Same-session ordering
///
/// [loadAnalytics] is the only method that publishes into the four analytics
/// fields, and it publishes atomically (all four commit together after
/// `Future.wait` succeeds - matching the established dashboard UX). A single
/// [_loadGen] identifies the most recent aggregate load: an older
/// [loadAnalytics] whose `Future.wait` resolves last, or one still running
/// when [clear] lands, fails its `owns()` check and can neither publish the
/// stale aggregate nor touch the spinner/error. There is no user-selectable
/// period/range/resource on the publishing path (the `days` arguments belong
/// only to the non-publishing [getExerciseProgressOverTime] /
/// [getVolumeOverTime] helpers), so a monotonic generation is sufficient and
/// no per-resource generation is needed.
///
/// [clear] and [dispose] bump [_loadGen] BEFORE resetting state, so an
/// in-flight continuation cannot repopulate cleared state - even when [clear]
/// is called without a preceding `UserSessionEpoch.invalidate()`.
///
/// ## List identity
///
/// The three analytics lists are each a single `final` list, only ever
/// mutated in place - never reassigned. Their getters hand out an
/// [UnmodifiableListView], so a caller cannot mutate provider state through
/// a getter AND a reference obtained before [clear] reflects the emptying.
class AnalyticsProvider extends ChangeNotifier {
  final AnalyticsRepository _repository;
  final UserSessionEpoch _sessionEpoch;

  WorkoutStats? _workoutStats;
  final List<ExerciseProgress> _exerciseProgress = [];
  final List<PersonalRecord> _personalRecords = [];
  final List<MuscleGroupVolume> _muscleGroupVolume = [];

  bool _isLoading = false;
  String? _errorMessage;

  // Identifies the most recent loadAnalytics aggregate request. Bumped by
  // loadAnalytics and by _invalidateGenerations (clear/dispose).
  int _loadGen = 0;

  AnalyticsProvider(this._repository, this._sessionEpoch);

  // Getters
  WorkoutStats? get workoutStats => _workoutStats;
  List<ExerciseProgress> get exerciseProgress =>
      UnmodifiableListView(_exerciseProgress);
  List<PersonalRecord> get personalRecords =>
      UnmodifiableListView(_personalRecords);
  List<MuscleGroupVolume> get muscleGroupVolume =>
      UnmodifiableListView(_muscleGroupVolume);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Load all analytics data.
  Future<void> loadAnalytics() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_loadGen;

    // True while this is still the newest aggregate load for the current
    // session - owns the spinner, the error slot, and the four fields.
    bool owns() => _sessionEpoch.isCurrent(token) && gen == _loadGen;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Load all data in parallel.
      final results = await Future.wait([
        _repository.getWorkoutStats(),
        _repository.getExerciseProgress(),
        _repository.getPersonalRecords(),
        _repository.getMuscleGroupVolume(days: 30),
      ]);

      if (!owns()) return;

      _workoutStats = results[0] as WorkoutStats;
      _exerciseProgress
        ..clear()
        ..addAll(results[1] as List<ExerciseProgress>);
      _personalRecords
        ..clear()
        ..addAll(results[2] as List<PersonalRecord>);
      _muscleGroupVolume
        ..clear()
        ..addAll(results[3] as List<MuscleGroupVolume>);
    } on SessionStaleException {
      // Lifecycle outcome: never a generic user-visible error, never an
      // empty "success". The finally below leaves a newer owner's spinner
      // untouched.
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      if (!owns()) return;
      _errorMessage =
          'Failed to load analytics: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Analytics error: $e');
    } finally {
      if (owns()) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Get progress over time for specific exercise. Feeds a transient
  /// `FutureBuilder`; never publishes into provider state.
  Future<List<ProgressDataPoint>> getExerciseProgressOverTime(
    int exerciseTemplateId, {
    int days = 90,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return [];
    try {
      final result = await _repository.getExerciseProgressOverTime(
        exerciseTemplateId,
        days: days,
      );
      // A result computed for A must not reach a FutureBuilder now mounted
      // under B.
      if (!_sessionEpoch.isCurrent(token)) return [];
      return result;
    } on SessionStaleException {
      return [];
    } on RequestCancelledException {
      return [];
    } catch (e) {
      debugPrint('Error loading exercise progress: $e');
      return [];
    }
  }

  /// Get volume over time. Feeds a transient `FutureBuilder`; never
  /// publishes into provider state.
  Future<List<ProgressDataPoint>> getVolumeOverTime({int days = 90}) async {
    final token = _sessionEpoch.capture();
    if (token == null) return [];
    try {
      final result = await _repository.getVolumeOverTime(days: days);
      if (!_sessionEpoch.isCurrent(token)) return [];
      return result;
    } on SessionStaleException {
      return [];
    } on RequestCancelledException {
      return [];
    } catch (e) {
      debugPrint('Error loading volume over time: $e');
      return [];
    }
  }

  /// Refresh analytics data.
  Future<void> refresh() async {
    await loadAnalytics();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Invalidate the aggregate generation so no in-flight continuation can
  /// publish after this returns.
  void _invalidateGenerations() {
    _loadGen++;
  }

  /// Clear all analytics data (called on logout via
  /// [SessionCleanupCoordinator]).
  ///
  /// [_loadGen] is bumped BEFORE any state is reset, so a [loadAnalytics]
  /// continuation that resolves after this returns fails its ownership check
  /// and can neither repopulate the cleared fields nor re-expose the
  /// previous user's error - even when `clear()` is called on its own,
  /// without a preceding `UserSessionEpoch.invalidate()`.
  ///
  /// The three lists are emptied in place (not reassigned), so any view a
  /// caller obtained before this call also becomes empty.
  void clear() {
    _invalidateGenerations();

    _workoutStats = null;
    _exerciseProgress.clear();
    _personalRecords.clear();
    _muscleGroupVolume.clear();
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
    debugPrint('🧹 AnalyticsProvider cleared');
  }

  @override
  void dispose() {
    _invalidateGenerations();
    super.dispose();
  }
}
