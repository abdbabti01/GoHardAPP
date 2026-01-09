import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models/program.dart';
import '../data/models/program_workout.dart';
import '../data/repositories/programs_repository.dart';
import '../core/services/connectivity_service.dart';

/// Provider for programs management
class ProgramsProvider extends ChangeNotifier {
  final ProgramsRepository _programsRepository;
  final ConnectivityService? _connectivity;

  List<Program> _programs = [];
  List<Program> _activePrograms = [];
  List<Program> _completedPrograms = [];
  bool _isLoading = false;
  bool _isCreating = false;
  bool _isUpdating = false;
  String? _errorMessage;

  StreamSubscription<bool>? _connectivitySubscription;

  ProgramsProvider(this._programsRepository, [this._connectivity]) {
    // Listen for connectivity changes and refresh when going online
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
      if (isOnline && _programs.isEmpty) {
        debugPrint('📡 Connection restored - loading programs');
        loadPrograms();
      }
    });
  }

  // Getters
  List<Program> get programs => _programs;
  List<Program> get activePrograms => _activePrograms;
  List<Program> get completedPrograms => _completedPrograms;
  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;
  bool get isUpdating => _isUpdating;
  String? get errorMessage => _errorMessage;

  /// Load all programs for the current user
  Future<void> loadPrograms({bool? isActive}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _programs = await _programsRepository.getPrograms(isActive: isActive);

      // Split into active and completed
      _activePrograms = _programs.where((p) => p.isActive).toList();
      _completedPrograms = _programs.where((p) => p.isCompleted).toList();

      debugPrint(
        '✅ Loaded ${_programs.length} programs (${_activePrograms.length} active, ${_completedPrograms.length} completed)',
      );
    } catch (e) {
      _errorMessage =
          'Failed to load programs: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load programs error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get a specific program by ID with all workouts
  Future<Program?> getProgramById(int id) async {
    try {
      return await _programsRepository.getProgramById(id);
    } catch (e) {
      _errorMessage =
          'Failed to load program: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load program error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Create a new program
  Future<bool> createProgram(Program program) async {
    _isCreating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newProgram = await _programsRepository.createProgram(program);
      _programs.add(newProgram);
      _activePrograms.add(newProgram);

      debugPrint('✅ Created program: ${newProgram.title}');
      _isCreating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to create program: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create program error: $e');
      _isCreating = false;
      notifyListeners();
      return false;
    }
  }

  /// Update an existing program
  Future<bool> updateProgram(int id, Program program) async {
    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _programsRepository.updateProgram(id, program);

      // Update in local list
      final index = _programs.indexWhere((p) => p.id == id);
      if (index != -1) {
        _programs[index] = program;
        _activePrograms = _programs.where((p) => p.isActive).toList();
        _completedPrograms = _programs.where((p) => p.isCompleted).toList();
      }

      debugPrint('✅ Updated program: ${program.title}');
      _isUpdating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to update program: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update program error: $e');
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  /// Delete a program
  Future<bool> deleteProgram(int id) async {
    try {
      await _programsRepository.deleteProgram(id);

      _programs.removeWhere((p) => p.id == id);
      _activePrograms.removeWhere((p) => p.id == id);
      _completedPrograms.removeWhere((p) => p.id == id);

      debugPrint('✅ Deleted program $id');
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to delete program: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete program error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Mark a program as completed
  Future<bool> completeProgram(int id) async {
    try {
      await _programsRepository.completeProgram(id);

      // Update in local list
      final index = _programs.indexWhere((p) => p.id == id);
      if (index != -1) {
        _programs[index] = _programs[index].copyWith(
          isCompleted: true,
          completedAt: DateTime.now().toUtc(),
          isActive: false,
        );
        _activePrograms = _programs.where((p) => p.isActive).toList();
        _completedPrograms = _programs.where((p) => p.isCompleted).toList();
      }

      debugPrint('✅ Completed program $id');
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to complete program: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Complete program error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Advance to next workout (increment day/week)
  Future<bool> advanceProgram(int id) async {
    try {
      final updatedProgram = await _programsRepository.advanceProgram(id);

      // Update in local list
      final index = _programs.indexWhere((p) => p.id == id);
      if (index != -1) {
        _programs[index] = updatedProgram;
        _activePrograms = _programs.where((p) => p.isActive).toList();
        _completedPrograms = _programs.where((p) => p.isCompleted).toList();
      }

      debugPrint(
        '✅ Advanced program to week ${updatedProgram.currentWeek}, day ${updatedProgram.currentDay}',
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to advance program: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Advance program error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get workouts for a specific week
  Future<List<ProgramWorkout>> getWeekWorkouts(
    int programId,
    int weekNumber,
  ) async {
    try {
      return await _programsRepository.getWeekWorkouts(programId, weekNumber);
    } catch (e) {
      _errorMessage =
          'Failed to load workouts: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load workouts error: $e');
      notifyListeners();
      return [];
    }
  }

  /// Get today's workout
  Future<ProgramWorkout?> getTodaysWorkout(int programId) async {
    try {
      return await _programsRepository.getTodaysWorkout(programId);
    } catch (e) {
      debugPrint('No workout found for today: $e');
      return null;
    }
  }

  /// Add a workout to a program
  Future<bool> addWorkout(int programId, ProgramWorkout workout) async {
    try {
      await _programsRepository.addWorkout(programId, workout);
      debugPrint('✅ Added workout to program $programId');
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to add workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Add workout error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Update a program workout
  Future<bool> updateWorkout(int workoutId, ProgramWorkout workout) async {
    try {
      await _programsRepository.updateWorkout(workoutId, workout);
      debugPrint('✅ Updated workout $workoutId');
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to update workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update workout error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Mark a workout as completed
  Future<bool> completeWorkout(int workoutId, {String? notes}) async {
    try {
      await _programsRepository.completeWorkout(workoutId, notes: notes);
      debugPrint('✅ Completed workout $workoutId');
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to complete workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Complete workout error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Delete a workout
  Future<bool> deleteWorkout(int workoutId) async {
    try {
      await _programsRepository.deleteWorkout(workoutId);
      debugPrint('✅ Deleted workout $workoutId');
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to delete workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete workout error: $e');
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
