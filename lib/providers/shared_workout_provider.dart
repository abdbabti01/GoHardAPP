import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../data/models/shared_workout.dart';
import '../data/repositories/shared_workout_repository.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/user_session_epoch.dart';

/// Provider for community shared workouts management.
///
/// Session-epoch guarded: every async method and the connectivity-restored
/// callback captures a [UserSessionToken] before its first await and
/// rechecks `_sessionEpoch.isCurrent(token)` after every await - including
/// inside catch/finally - before touching any list, loading flag, error
/// field, filter, or calling `notifyListeners()`. If the session that
/// started an operation has since ended (logout, or a different user
/// logging in), the operation's result, error, and finally-block cleanup
/// are all dropped rather than committed onto whatever session now owns
/// this shared provider instance. Optimistic mutations are only ever
/// applied to the session that made them, and their rollback targets are
/// re-located from the current lists only while the original token is still
/// current.
class SharedWorkoutProvider extends ChangeNotifier {
  final SharedWorkoutRepository _repository;
  final ConnectivityService _connectivity;
  final UserSessionEpoch _sessionEpoch;

  List<SharedWorkout> _sharedWorkouts = [];
  List<SharedWorkout> _savedWorkouts = [];
  List<SharedWorkout> _mySharedWorkouts = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<bool>? _connectivitySubscription;

  // Filter states
  String? _selectedCategory;
  String? _selectedDifficulty;

  SharedWorkoutProvider(
    this._repository,
    this._connectivity,
    this._sessionEpoch,
  ) {
    // Listen for connectivity changes. This callback can fire at any point
    // in the app's lifetime, including during a logged-out gap between one
    // user's logout and the next user's login - capture a token fresh on
    // every invocation and skip entirely if there is no active session, so
    // a connectivity flap while logged out can never dispatch a refresh
    // for nobody, and a refresh that a since-invalidated session started
    // can never commit.
    _connectivitySubscription = _connectivity.connectivityStream.listen((
      isOnline,
    ) {
      final token = _sessionEpoch.capture();
      if (token == null) return;
      if (isOnline) {
        debugPrint('📡 Connection restored - refreshing shared workouts');
        loadSharedWorkouts(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // Getters
  List<SharedWorkout> get sharedWorkouts => _sharedWorkouts;
  List<SharedWorkout> get savedWorkouts => _savedWorkouts;
  List<SharedWorkout> get mySharedWorkouts => _mySharedWorkouts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isOnline => _connectivity.isOnline;
  String? get selectedCategory => _selectedCategory;
  String? get selectedDifficulty => _selectedDifficulty;

  /// Load community shared workouts
  Future<void> loadSharedWorkouts({bool showLoading = true}) async {
    if (_isLoading) return;

    final token = _sessionEpoch.capture();
    if (token == null) return;

    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final workouts = await _repository.getSharedWorkouts(
        category: _selectedCategory,
        difficulty: _selectedDifficulty,
        limit: 50,
      );
      if (!_sessionEpoch.isCurrent(token)) return;
      _sharedWorkouts = workouts;
      debugPrint('✅ Loaded ${_sharedWorkouts.length} shared workouts');
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage =
          'Failed to load shared workouts: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Load shared workouts error: $e');
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        if (showLoading) {
          _isLoading = false;
        }
        notifyListeners();
      }
    }
  }

  /// Load saved workouts for current user
  Future<void> loadSavedWorkouts() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    try {
      final workouts = await _repository.getSavedWorkouts();
      if (!_sessionEpoch.isCurrent(token)) return;
      _savedWorkouts = workouts;
      notifyListeners();
      debugPrint('✅ Loaded ${_savedWorkouts.length} saved workouts');
    } catch (e) {
      debugPrint('❌ Load saved workouts error: $e');
    }
  }

  /// Load workouts shared by current user
  Future<void> loadMySharedWorkouts() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    try {
      final workouts = await _repository.getMySharedWorkouts();
      if (!_sessionEpoch.isCurrent(token)) return;
      _mySharedWorkouts = workouts;
      notifyListeners();
      debugPrint('✅ Loaded ${_mySharedWorkouts.length} of my shared workouts');
    } catch (e) {
      debugPrint('❌ Load my shared workouts error: $e');
    }
  }

  /// Share a workout to the community
  Future<SharedWorkout?> shareWorkout({
    required int originalId,
    required String type,
    required String workoutName,
    String? description,
    required String exercisesJson,
    required int duration,
    required String category,
    String? difficulty,
  }) async {
    if (!_connectivity.isOnline) {
      _errorMessage = 'Cannot share workout while offline';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final shared = await _repository.shareWorkout(
        originalId: originalId,
        type: type,
        workoutName: workoutName,
        description: description,
        exercisesJson: exercisesJson,
        duration: duration,
        category: category,
        difficulty: difficulty,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      // Add to my shared workouts list
      _mySharedWorkouts.insert(0, shared);
      _sharedWorkouts.insert(0, shared);

      debugPrint('✅ Successfully shared workout: ${shared.workoutName}');
      return shared;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to share workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Share workout error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Toggle like on a shared workout
  Future<void> toggleLike(int sharedWorkoutId) async {
    if (!_connectivity.isOnline) {
      _errorMessage = 'Cannot like/unlike while offline';
      notifyListeners();
      return;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return;

    // Find the workout in our lists
    final workout = _findWorkoutById(sharedWorkoutId);
    if (workout == null) return;

    final newLikedState = !workout.isLikedByCurrentUser;

    // Optimistically update this session's own UI state before the await.
    workout.isLikedByCurrentUser = newLikedState;
    workout.likeCount += newLikedState ? 1 : -1;
    notifyListeners();

    try {
      // Make API call
      await _repository.toggleLike(sharedWorkoutId, newLikedState);
      if (!_sessionEpoch.isCurrent(token)) return;
      debugPrint('✅ Toggled like on workout $sharedWorkoutId');
    } catch (e) {
      // Only roll back if the session that made the optimistic change is
      // still current - never re-locate a rollback target from lists that
      // now belong to a different session.
      if (!_sessionEpoch.isCurrent(token)) return;
      final target = _findWorkoutById(sharedWorkoutId);
      if (target != null) {
        target.isLikedByCurrentUser = !target.isLikedByCurrentUser;
        target.likeCount += target.isLikedByCurrentUser ? 1 : -1;
      }

      _errorMessage =
          'Failed to like workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Toggle like error: $e');
      notifyListeners();
    }
  }

  /// Toggle save on a shared workout
  Future<void> toggleSave(int sharedWorkoutId) async {
    if (!_connectivity.isOnline) {
      _errorMessage = 'Cannot save/unsave while offline';
      notifyListeners();
      return;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return;

    // Find the workout in our lists
    final workout = _findWorkoutById(sharedWorkoutId);
    if (workout == null) return;

    final newSavedState = !workout.isSavedByCurrentUser;

    // Optimistically update this session's own UI state before the await.
    workout.isSavedByCurrentUser = newSavedState;
    workout.saveCount += newSavedState ? 1 : -1;

    if (newSavedState) {
      if (!_savedWorkouts.any((w) => w.id == workout.id)) {
        _savedWorkouts.insert(0, workout);
      }
    } else {
      _savedWorkouts.removeWhere((w) => w.id == workout.id);
    }
    notifyListeners();

    try {
      // Make API call
      await _repository.toggleSave(sharedWorkoutId, newSavedState);
      if (!_sessionEpoch.isCurrent(token)) return;
      debugPrint('✅ Toggled save on workout $sharedWorkoutId');
    } catch (e) {
      // Only roll back if the session that made the optimistic change is
      // still current.
      if (!_sessionEpoch.isCurrent(token)) return;
      final target = _findWorkoutById(sharedWorkoutId);
      if (target != null) {
        target.isSavedByCurrentUser = !target.isSavedByCurrentUser;
        target.saveCount += target.isSavedByCurrentUser ? 1 : -1;

        if (target.isSavedByCurrentUser) {
          if (!_savedWorkouts.any((w) => w.id == target.id)) {
            _savedWorkouts.insert(0, target);
          }
        } else {
          _savedWorkouts.removeWhere((w) => w.id == target.id);
        }
      }

      _errorMessage =
          'Failed to save workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Toggle save error: $e');
      notifyListeners();
    }
  }

  /// Delete a shared workout (only if created by current user)
  Future<bool> deleteSharedWorkout(int sharedWorkoutId) async {
    if (!_connectivity.isOnline) {
      _errorMessage = 'Cannot delete while offline';
      notifyListeners();
      return false;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      await _repository.deleteSharedWorkout(sharedWorkoutId);
      if (!_sessionEpoch.isCurrent(token)) return false;

      // Remove from all lists
      _sharedWorkouts.removeWhere((w) => w.id == sharedWorkoutId);
      _mySharedWorkouts.removeWhere((w) => w.id == sharedWorkoutId);
      _savedWorkouts.removeWhere((w) => w.id == sharedWorkoutId);

      notifyListeners();
      debugPrint('✅ Deleted shared workout $sharedWorkoutId');
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to delete workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Delete shared workout error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Set category filter
  void setCategory(String? category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      loadSharedWorkouts();
    }
  }

  /// Set difficulty filter
  void setDifficulty(String? difficulty) {
    if (_selectedDifficulty != difficulty) {
      _selectedDifficulty = difficulty;
      loadSharedWorkouts();
    }
  }

  /// Clear all filters
  void clearFilters() {
    if (_selectedCategory != null || _selectedDifficulty != null) {
      _selectedCategory = null;
      _selectedDifficulty = null;
      loadSharedWorkouts();
    }
  }

  /// Refresh all data
  Future<void> refresh() async {
    await loadSharedWorkouts();
    await loadSavedWorkouts();
    await loadMySharedWorkouts();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear all shared-workout data (called on logout)
  void clear() {
    _sharedWorkouts = [];
    _savedWorkouts = [];
    _mySharedWorkouts = [];
    _isLoading = false;
    _errorMessage = null;
    _selectedCategory = null;
    _selectedDifficulty = null;
    notifyListeners();
    debugPrint('🧹 SharedWorkoutProvider cleared');
  }

  // === PRIVATE HELPERS ===

  /// Find a workout by ID across all lists
  SharedWorkout? _findWorkoutById(int id) {
    // Try shared workouts first
    var workout = _sharedWorkouts.firstWhere(
      (w) => w.id == id,
      orElse:
          () => _savedWorkouts.firstWhere(
            (w) => w.id == id,
            orElse:
                () => _mySharedWorkouts.firstWhere(
                  (w) => w.id == id,
                  orElse:
                      () => SharedWorkout(
                        originalId: 0,
                        type: '',
                        sharedByUserId: 0,
                        sharedByUserName: '',
                        workoutName: '',
                        exercisesJson: '',
                        duration: 0,
                        category: '',
                        sharedAt: DateTime.now(),
                      ),
                ),
          ),
    );

    return workout.id == Isar.autoIncrement ? null : workout;
  }
}
