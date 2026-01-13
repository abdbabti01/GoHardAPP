import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../models/program.dart';
import '../models/program_workout.dart';
import '../services/api_service.dart';

/// Repository for programs operations with offline caching
class ProgramsRepository {
  final ApiService _apiService;
  final ConnectivityService? _connectivity;

  ProgramsRepository(this._apiService, [this._connectivity]);

  /// Get all programs for the current user
  /// Optional filter: isActive (true for active programs, false for inactive/completed)
  Future<List<Program>> getPrograms({bool? isActive}) async {
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
      );

      return data
          .map((json) => Program.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to fetch programs: $e');
      rethrow;
    }
  }

  /// Get a specific program by ID with all workouts
  Future<Program> getProgramById(int id) async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.programById(id),
    );
    return Program.fromJson(data);
  }

  /// Create a new program
  Future<Program> createProgram(Program program) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.programs,
      data: program.toJson(),
    );
    return Program.fromJson(data);
  }

  /// Update an existing program
  Future<void> updateProgram(int id, Program program) async {
    await _apiService.put<void>(
      ApiConfig.programById(id),
      data: program.toJson(),
    );
  }

  /// Get deletion impact for a program
  Future<Map<String, int>> getDeletionImpact(int id) async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.programDeletionImpact(id),
    );
    return {'sessionsCount': data['sessionsCount'] as int};
  }

  /// Delete a program
  Future<void> deleteProgram(int id) async {
    await _apiService.delete(ApiConfig.programById(id));
  }

  /// Mark a program as completed
  Future<void> completeProgram(int id) async {
    await _apiService.put<void>(ApiConfig.programComplete(id));
  }

  /// Advance to next workout (increment day/week)
  Future<Program> advanceProgram(int id) async {
    final data = await _apiService.put<Map<String, dynamic>>(
      ApiConfig.programAdvance(id),
    );
    return Program.fromJson(data);
  }

  /// Get workouts for a specific week
  Future<List<ProgramWorkout>> getWeekWorkouts(
    int programId,
    int weekNumber,
  ) async {
    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.programWeek(programId, weekNumber),
    );
    return data
        .map((json) => ProgramWorkout.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get today's workout
  Future<ProgramWorkout> getTodaysWorkout(int programId) async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.programToday(programId),
    );
    return ProgramWorkout.fromJson(data);
  }

  /// Add a workout to a program
  Future<ProgramWorkout> addWorkout(
    int programId,
    ProgramWorkout workout,
  ) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.programWorkouts(programId),
      data: workout.toJson(),
    );
    return ProgramWorkout.fromJson(data);
  }

  /// Update a program workout
  Future<void> updateWorkout(int workoutId, ProgramWorkout workout) async {
    await _apiService.put<void>(
      ApiConfig.programWorkoutById(workoutId),
      data: workout.toJson(),
    );
  }

  /// Mark a workout as completed
  Future<void> completeWorkout(int workoutId, {String? notes}) async {
    await _apiService.put<void>(
      ApiConfig.programWorkoutComplete(workoutId),
      data: notes,
    );
  }

  /// Delete a workout
  Future<void> deleteWorkout(int workoutId) async {
    await _apiService.delete(ApiConfig.programWorkoutById(workoutId));
  }
}
