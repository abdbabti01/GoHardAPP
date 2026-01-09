import 'package:json_annotation/json_annotation.dart';
import 'dart:convert';

part 'program_workout.g.dart';

@JsonSerializable(includeIfNull: false)
class ProgramWorkout {
  final int id;
  final int programId;
  final int weekNumber;
  final int dayNumber;
  final String? dayName;
  final String workoutName;
  final String? workoutType;
  final String? description;
  final int? estimatedDuration;
  final String exercisesJson;
  final String? warmUp;
  final String? coolDown;
  final bool isCompleted;
  final DateTime? completedAt;
  final String? completionNotes;
  final int orderIndex;

  ProgramWorkout({
    required this.id,
    required this.programId,
    required this.weekNumber,
    required this.dayNumber,
    this.dayName,
    required this.workoutName,
    this.workoutType,
    this.description,
    this.estimatedDuration,
    required this.exercisesJson,
    this.warmUp,
    this.coolDown,
    required this.isCompleted,
    this.completedAt,
    this.completionNotes,
    required this.orderIndex,
  });

  // Helper method to ensure datetime is in UTC
  static DateTime _toUtc(DateTime dt) {
    if (dt.isUtc) return dt;
    return dt.toUtc();
  }

  static DateTime? _toUtcNullable(DateTime? dt) {
    if (dt == null) return null;
    if (dt.isUtc) return dt;
    return dt.toUtc();
  }

  factory ProgramWorkout.fromJson(Map<String, dynamic> json) {
    final workout = _$ProgramWorkoutFromJson(json);

    return ProgramWorkout(
      id: workout.id,
      programId: workout.programId,
      weekNumber: workout.weekNumber,
      dayNumber: workout.dayNumber,
      dayName: workout.dayName,
      workoutName: workout.workoutName,
      workoutType: workout.workoutType,
      description: workout.description,
      estimatedDuration: workout.estimatedDuration,
      exercisesJson: workout.exercisesJson,
      warmUp: workout.warmUp,
      coolDown: workout.coolDown,
      isCompleted: workout.isCompleted,
      completedAt: _toUtcNullable(workout.completedAt),
      completionNotes: workout.completionNotes,
      orderIndex: workout.orderIndex,
    );
  }

  Map<String, dynamic> toJson() => _$ProgramWorkoutToJson(this);

  /// Parse exercises from JSON string
  List<Map<String, dynamic>> get exercises {
    try {
      final decoded = jsonDecode(exercisesJson);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(
          decoded.map((e) => Map<String, dynamic>.from(e)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get number of exercises in this workout
  int get exerciseCount {
    return exercises.length;
  }

  /// Get day name from day number (1=Monday, 7=Sunday)
  String get dayNameFromNumber {
    if (dayName != null && dayName!.isNotEmpty) {
      return dayName!;
    }
    switch (dayNumber) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Day $dayNumber';
    }
  }

  /// Get formatted workout identifier
  String get workoutIdentifier {
    return 'Week $weekNumber, Day $dayNumber - $dayNameFromNumber';
  }

  /// Check if workout is a rest day
  bool get isRestDay {
    return workoutType?.toLowerCase() == 'rest' ||
        workoutName.toLowerCase().contains('rest');
  }

  ProgramWorkout copyWith({
    int? id,
    int? programId,
    int? weekNumber,
    int? dayNumber,
    String? dayName,
    String? workoutName,
    String? workoutType,
    String? description,
    int? estimatedDuration,
    String? exercisesJson,
    String? warmUp,
    String? coolDown,
    bool? isCompleted,
    DateTime? completedAt,
    String? completionNotes,
    int? orderIndex,
  }) {
    return ProgramWorkout(
      id: id ?? this.id,
      programId: programId ?? this.programId,
      weekNumber: weekNumber ?? this.weekNumber,
      dayNumber: dayNumber ?? this.dayNumber,
      dayName: dayName ?? this.dayName,
      workoutName: workoutName ?? this.workoutName,
      workoutType: workoutType ?? this.workoutType,
      description: description ?? this.description,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      exercisesJson: exercisesJson ?? this.exercisesJson,
      warmUp: warmUp ?? this.warmUp,
      coolDown: coolDown ?? this.coolDown,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      completionNotes: completionNotes ?? this.completionNotes,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }
}
