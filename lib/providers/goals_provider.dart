import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models/goal.dart';
import '../data/models/goal_progress.dart';
import '../data/repositories/goals_repository.dart';
import '../core/services/connectivity_service.dart';

/// Provider for goals management
class GoalsProvider extends ChangeNotifier {
  final GoalsRepository _goalsRepository;
  final ConnectivityService? _connectivity;

  List<Goal> _goals = [];
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<bool>? _connectivitySubscription;

  GoalsProvider(this._goalsRepository, [this._connectivity]) {
    // Listen for connectivity changes and refresh when going online
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
      if (isOnline && _goals.isEmpty) {
        debugPrint('📡 Connection restored - loading goals');
        loadGoals();
      }
    });
  }

  // Getters - derive filtered lists from single source of truth
  List<Goal> get goals => _goals;
  List<Goal> get activeGoals =>
      _goals.where((g) => g.isActive && !g.isCompleted).toList();
  List<Goal> get completedGoals => _goals.where((g) => g.isCompleted).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Legacy getters for backwards compatibility (deprecated)
  @Deprecated('Use isLoading instead')
  bool get isCreating => _isLoading;
  @Deprecated('Use isLoading instead')
  bool get isUpdating => _isLoading;

  /// Load all goals for the current user
  Future<void> loadGoals({bool? isActive}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _goals = await _goalsRepository.getGoals(isActive: isActive);

      debugPrint(
        '✅ Loaded ${_goals.length} goals (${activeGoals.length} active, ${completedGoals.length} completed)',
      );
    } catch (e) {
      _errorMessage =
          'Failed to load goals: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load goals error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get a specific goal by ID with progress history
  Future<Goal?> getGoalById(int id) async {
    try {
      return await _goalsRepository.getGoalById(id);
    } catch (e) {
      _errorMessage =
          'Failed to load goal: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load goal error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Create a new goal with optimistic update
  Future<Goal?> createGoal(Goal goal) async {
    _errorMessage = null;

    // 1. Create optimistic goal with temporary ID
    final optimisticGoal = goal.copyWith(
      id: -1, // Temporary ID to identify optimistic update
      createdAt: DateTime.now(),
    );

    // 2. Add to list immediately (optimistic update)
    _goals.add(optimisticGoal);
    notifyListeners();

    debugPrint('📝 Optimistically added goal: ${optimisticGoal.goalType}');

    try {
      // 3. Make API call
      final newGoal = await _goalsRepository.createGoal(goal);

      // 4. Replace optimistic goal with real goal
      final index = _goals.indexWhere((g) => g.id == -1);
      if (index != -1) {
        _goals[index] = newGoal;
      }

      debugPrint('✅ Created goal: ${newGoal.goalType} (ID: ${newGoal.id})');
      notifyListeners();
      return newGoal;
    } catch (e) {
      // 5. Remove optimistic goal on failure
      _goals.removeWhere((g) => g.id == -1);

      _errorMessage =
          'Failed to create goal: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create goal error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Update an existing goal with optimistic update
  Future<bool> updateGoal(int id, Goal goal) async {
    _errorMessage = null;

    // 1. Store original goal for rollback
    final originalIndex = _goals.indexWhere((g) => g.id == id);
    final originalGoal = originalIndex != -1 ? _goals[originalIndex] : null;

    if (originalGoal == null) {
      _errorMessage = 'Goal not found';
      notifyListeners();
      return false;
    }

    // 2. Apply optimistic update
    _goals[originalIndex] = goal;
    notifyListeners();

    debugPrint('📝 Optimistically updated goal: $id');

    try {
      // 3. Make API call
      await _goalsRepository.updateGoal(id, goal);

      debugPrint('✅ Updated goal: $id');
      return true;
    } catch (e) {
      // 4. Rollback on failure
      _goals[originalIndex] = originalGoal;

      _errorMessage =
          'Failed to update goal: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update goal error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get deletion impact for a goal (how many programs and sessions will be deleted)
  Future<Map<String, int>> getDeletionImpact(int id) async {
    try {
      return await _goalsRepository.getDeletionImpact(id);
    } catch (e) {
      debugPrint('Get deletion impact error: $e');
      rethrow;
    }
  }

  /// Delete a goal with optimistic update
  Future<bool> deleteGoal(int id) async {
    _errorMessage = null;

    // 1. Store original goal for rollback
    final originalIndex = _goals.indexWhere((g) => g.id == id);
    if (originalIndex == -1) {
      return true; // Already deleted
    }
    final originalGoal = _goals[originalIndex];

    // 2. Optimistically remove
    _goals.removeAt(originalIndex);
    notifyListeners();

    debugPrint('📝 Optimistically deleted goal: $id');

    try {
      // 3. Make API call
      await _goalsRepository.deleteGoal(id);

      debugPrint('✅ Deleted goal: $id');
      return true;
    } catch (e) {
      // 4. Rollback on failure - re-add the goal
      if (originalIndex < _goals.length) {
        _goals.insert(originalIndex, originalGoal);
      } else {
        _goals.add(originalGoal);
      }

      _errorMessage =
          'Failed to delete goal: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete goal error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Mark a goal as completed with optimistic update
  Future<bool> completeGoal(int id) async {
    _errorMessage = null;

    // 1. Store original for rollback
    final originalIndex = _goals.indexWhere((g) => g.id == id);
    if (originalIndex == -1) {
      _errorMessage = 'Goal not found';
      notifyListeners();
      return false;
    }
    final originalGoal = _goals[originalIndex];

    // 2. Optimistically mark as completed
    _goals[originalIndex] = originalGoal.copyWith(
      isCompleted: true,
      isActive: false,
      completedAt: DateTime.now(),
    );
    notifyListeners();

    debugPrint('📝 Optimistically completed goal: $id');

    try {
      // 3. Make API call
      await _goalsRepository.completeGoal(id);

      debugPrint('✅ Completed goal: $id');
      return true;
    } catch (e) {
      // 4. Rollback on failure
      _goals[originalIndex] = originalGoal;

      _errorMessage =
          'Failed to complete goal: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Complete goal error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Add progress entry for a goal
  Future<bool> addProgress(int goalId, GoalProgress progress) async {
    _errorMessage = null;
    notifyListeners();

    try {
      await _goalsRepository.addProgress(goalId, progress);

      // Reload to get updated goal with new progress
      await loadGoals();

      debugPrint('✅ Added progress to goal: $goalId');
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to add progress: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Add progress error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get progress history for a goal
  Future<List<GoalProgress>> getProgressHistory(int goalId) async {
    try {
      return await _goalsRepository.getProgressHistory(goalId);
    } catch (e) {
      _errorMessage =
          'Failed to load progress history: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load progress history error: $e');
      notifyListeners();
      return [];
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear all goals data (called on logout)
  void clear() {
    _goals = [];
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
    debugPrint('🧹 GoalsProvider cleared');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
