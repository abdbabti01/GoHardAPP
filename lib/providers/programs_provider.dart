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

  /// Get a specific program by ID with all workouts (from API)
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

  /// Get a program from local cache by ID (no API call)
  /// Returns null if not found in local cache
  Program? getProgramFromCache(int id) {
    try {
      return _programs.firstWhere((p) => p.id == id);
    } catch (e) {
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

      // Update in local list, preserving workouts if the incoming program doesn't have them
      final index = _programs.indexWhere((p) => p.id == id);
      if (index != -1) {
        final existingProgram = _programs[index];

        // If the incoming program has no workouts but the existing one does,
        // preserve the existing workouts to avoid data loss
        final workoutsToKeep =
            (program.workouts == null || program.workouts!.isEmpty)
                ? existingProgram.workouts
                : program.workouts;

        // Also preserve the goal object if not provided in the update
        final goalToKeep = program.goal ?? existingProgram.goal;

        _programs[index] = program.copyWith(
          workouts: workoutsToKeep,
          goal: goalToKeep,
        );

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

  /// Get deletion impact for a program (how many sessions will be deleted)
  Future<Map<String, int>> getDeletionImpact(int id) async {
    try {
      return await _programsRepository.getDeletionImpact(id);
    } catch (e) {
      debugPrint('Get deletion impact error: $e');
      rethrow;
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

  /// Get workouts for the current week of a program
  List<ProgramWorkout> getThisWeeksWorkouts(Program program) {
    if (program.workouts == null || program.workouts!.isEmpty) {
      return [];
    }

    final currentWeek = program.currentWeek;
    return program.workouts!.where((w) => w.weekNumber == currentWeek).toList()
      ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
  }

  /// Add a workout to a program
  Future<bool> addWorkout(int programId, ProgramWorkout workout) async {
    try {
      final newWorkout = await _programsRepository.addWorkout(
        programId,
        workout,
      );

      // Update local programs list with the new workout
      for (int i = 0; i < _programs.length; i++) {
        if (_programs[i].id == programId) {
          final updatedWorkouts = List<ProgramWorkout>.from(
            _programs[i].workouts ?? [],
          );
          updatedWorkouts.add(newWorkout);
          _programs[i] = _programs[i].copyWith(workouts: updatedWorkouts);
          break;
        }
      }

      // Refresh active/completed lists
      _activePrograms = _programs.where((p) => p.isActive).toList();
      _completedPrograms = _programs.where((p) => p.isCompleted).toList();

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

      // Update workout in local programs list immediately
      for (int i = 0; i < _programs.length; i++) {
        final program = _programs[i];
        if (program.workouts != null) {
          final workoutIndex = program.workouts!.indexWhere(
            (w) => w.id == workoutId,
          );
          if (workoutIndex != -1) {
            // Create updated workouts list with the modified workout
            final updatedWorkouts = List<ProgramWorkout>.from(
              program.workouts!,
            );
            updatedWorkouts[workoutIndex] = workout;
            _programs[i] = program.copyWith(workouts: updatedWorkouts);
            debugPrint(
              '✅ Updated workout $workoutId in program ${program.id} (day ${workout.dayNumber})',
            );
            break;
          }
        }
      }

      // Refresh active/completed lists with updated programs
      _activePrograms = _programs.where((p) => p.isActive).toList();
      _completedPrograms = _programs.where((p) => p.isCompleted).toList();

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

  /// Swap two program workouts atomically
  Future<bool> swapWorkouts(int workout1Id, int workout2Id) async {
    try {
      await _programsRepository.swapWorkouts(workout1Id, workout2Id);

      // Swap workout day numbers in local programs list
      for (int i = 0; i < _programs.length; i++) {
        final program = _programs[i];
        if (program.workouts != null) {
          final workout1Index = program.workouts!.indexWhere(
            (w) => w.id == workout1Id,
          );
          final workout2Index = program.workouts!.indexWhere(
            (w) => w.id == workout2Id,
          );

          if (workout1Index != -1 && workout2Index != -1) {
            final updatedWorkouts = List<ProgramWorkout>.from(
              program.workouts!,
            );
            final workout1 = updatedWorkouts[workout1Index];
            final workout2 = updatedWorkouts[workout2Index];

            // Swap day numbers
            updatedWorkouts[workout1Index] = workout1.copyWith(
              dayNumber: workout2.dayNumber,
              orderIndex: workout2.orderIndex,
            );
            updatedWorkouts[workout2Index] = workout2.copyWith(
              dayNumber: workout1.dayNumber,
              orderIndex: workout1.orderIndex,
            );

            _programs[i] = program.copyWith(workouts: updatedWorkouts);
            break;
          }
        }
      }

      // Refresh active/completed lists
      _activePrograms = _programs.where((p) => p.isActive).toList();
      _completedPrograms = _programs.where((p) => p.isCompleted).toList();

      debugPrint('✅ Swapped workouts $workout1Id and $workout2Id');
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to swap workouts: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Swap workouts error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Mark a workout as completed
  Future<bool> completeWorkout(int workoutId, {String? notes}) async {
    try {
      await _programsRepository.completeWorkout(workoutId, notes: notes);

      // Update workout completion status in local programs list
      for (int i = 0; i < _programs.length; i++) {
        final program = _programs[i];
        if (program.workouts != null) {
          final workoutIndex = program.workouts!.indexWhere(
            (w) => w.id == workoutId,
          );
          if (workoutIndex != -1) {
            final updatedWorkouts = List<ProgramWorkout>.from(
              program.workouts!,
            );
            updatedWorkouts[workoutIndex] = updatedWorkouts[workoutIndex]
                .copyWith(
                  isCompleted: true,
                  completedAt: DateTime.now().toUtc(),
                );
            _programs[i] = program.copyWith(workouts: updatedWorkouts);
            break;
          }
        }
      }

      // Refresh active/completed lists
      _activePrograms = _programs.where((p) => p.isActive).toList();
      _completedPrograms = _programs.where((p) => p.isCompleted).toList();

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

      // Remove workout from local programs list
      for (int i = 0; i < _programs.length; i++) {
        final program = _programs[i];
        if (program.workouts != null) {
          final workoutIndex = program.workouts!.indexWhere(
            (w) => w.id == workoutId,
          );
          if (workoutIndex != -1) {
            final updatedWorkouts = List<ProgramWorkout>.from(
              program.workouts!,
            );
            updatedWorkouts.removeAt(workoutIndex);
            _programs[i] = program.copyWith(workouts: updatedWorkouts);
            break;
          }
        }
      }

      // Refresh active/completed lists
      _activePrograms = _programs.where((p) => p.isActive).toList();
      _completedPrograms = _programs.where((p) => p.isCompleted).toList();

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
