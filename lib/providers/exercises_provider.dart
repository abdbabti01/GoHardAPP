import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/exercise_template.dart';
import '../data/repositories/exercise_repository.dart';
import '../core/services/connectivity_service.dart';

/// Provider for exercise library browsing
/// Replaces ExercisesViewModel from MAUI app
class ExercisesProvider extends ChangeNotifier {
  final ExerciseRepository _exerciseRepository;
  final ConnectivityService? _connectivity;

  List<ExerciseTemplate> _exercises = [];
  List<ExerciseTemplate> _filteredExercises = [];
  bool _isLoading = false;
  String? _errorMessage;

  String? _selectedCategory;
  String? _selectedMuscleGroup;
  String? _selectedDifficulty;
  String _searchQuery = '';

  StreamSubscription<bool>? _connectivitySubscription;

  ExercisesProvider(this._exerciseRepository, [this._connectivity]) {
    // Auto-load exercises on initialization to cache them for offline use
    loadExercises();

    // Listen for connectivity changes and refresh when going online
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
      if (isOnline) {
        debugPrint('📡 Connection restored - refreshing exercise library');
        loadExercises(showLoading: false);
      }
    });
  }

  // Getters
  List<ExerciseTemplate> get exercises => _exercises;
  List<ExerciseTemplate> get filteredExercises => _filteredExercises;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get selectedCategory => _selectedCategory;
  String? get selectedMuscleGroup => _selectedMuscleGroup;
  String? get selectedDifficulty => _selectedDifficulty;
  String get searchQuery => _searchQuery;

  /// Search exercises by name
  void searchExercises(String query) {
    _searchQuery = query;
    _applyFilters();
  }

  /// Get exercises grouped by difficulty level
  Map<String, List<ExerciseTemplate>> get exercisesByDifficulty {
    final grouped = <String, List<ExerciseTemplate>>{
      'Beginner': [],
      'Intermediate': [],
      'Advanced': [],
    };

    for (final exercise in _filteredExercises) {
      final difficulty = exercise.difficulty ?? 'Beginner';
      if (grouped.containsKey(difficulty)) {
        grouped[difficulty]!.add(exercise);
      } else {
        grouped['Beginner']!.add(exercise);
      }
    }

    return grouped;
  }

  /// Load all exercise templates
  Future<void> loadExercises({bool showLoading = true}) async {
    if (_isLoading) return;

    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      _exercises = await _exerciseRepository.getExerciseTemplates();
      _applyFilters();
    } catch (e) {
      _errorMessage =
          'Failed to load exercises: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load exercises error: $e');
      notifyListeners();
    } finally {
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  /// Filter by category
  void filterByCategory(String? category) {
    _selectedCategory = category;
    _applyFilters();
  }

  /// Filter by muscle group
  void filterByMuscleGroup(String? muscleGroup) {
    _selectedMuscleGroup = muscleGroup;
    _applyFilters();
  }

  /// Filter by difficulty level
  void filterByDifficulty(String? difficulty) {
    _selectedDifficulty = difficulty;
    _applyFilters();
  }

  /// Apply current filters
  void _applyFilters() {
    _filteredExercises =
        _exercises.where((exercise) {
          // Search filter
          bool matchesSearch =
              _searchQuery.isEmpty ||
              (exercise.name.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              )) ||
              (exercise.muscleGroup?.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ??
                  false) ||
              (exercise.equipment?.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ??
                  false);

          bool matchesCategory =
              _selectedCategory == null ||
              _selectedCategory == 'All' ||
              exercise.category?.toLowerCase() ==
                  _selectedCategory?.toLowerCase();

          bool matchesMuscleGroup =
              _selectedMuscleGroup == null ||
              exercise.muscleGroup?.toLowerCase() ==
                  _selectedMuscleGroup?.toLowerCase();

          bool matchesDifficulty =
              _selectedDifficulty == null ||
              exercise.difficulty?.toLowerCase() ==
                  _selectedDifficulty?.toLowerCase();

          return matchesSearch &&
              matchesCategory &&
              matchesMuscleGroup &&
              matchesDifficulty;
        }).toList();

    // Sort alphabetically by name
    _filteredExercises.sort((a, b) => a.name.compareTo(b.name));

    notifyListeners();
  }

  /// Refresh exercises (pull-to-refresh)
  /// Don't show loading indicator for smooth UX
  Future<void> refresh() async {
    await loadExercises(showLoading: false);
  }

  /// Clear filters
  void clearFilters() {
    _selectedCategory = null;
    _selectedMuscleGroup = null;
    _selectedDifficulty = null;
    _searchQuery = '';
    _applyFilters();
  }

  /// Check if any filters are active
  bool get hasActiveFilters =>
      _selectedCategory != null ||
      _selectedMuscleGroup != null ||
      _selectedDifficulty != null ||
      _searchQuery.isNotEmpty;

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
