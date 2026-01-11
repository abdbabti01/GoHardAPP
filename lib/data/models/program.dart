import 'package:json_annotation/json_annotation.dart';
import 'program_workout.dart';
import 'goal.dart';

part 'program.g.dart';

@JsonSerializable(includeIfNull: false)
class Program {
  final int id;
  final int userId;
  final String title;
  final String? description;
  final int? goalId;
  final int totalWeeks;
  final int currentWeek;
  final int currentDay;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime createdAt;
  final String? programStructure;
  final List<ProgramWorkout>? workouts;
  final Goal? goal;

  Program({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.goalId,
    required this.totalWeeks,
    required this.currentWeek,
    required this.currentDay,
    required this.startDate,
    this.endDate,
    required this.isActive,
    required this.isCompleted,
    this.completedAt,
    required this.createdAt,
    this.programStructure,
    this.workouts,
    this.goal,
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

  factory Program.fromJson(Map<String, dynamic> json) {
    final program = _$ProgramFromJson(json);

    return Program(
      id: program.id,
      userId: program.userId,
      title: program.title,
      description: program.description,
      goalId: program.goalId,
      totalWeeks: program.totalWeeks,
      currentWeek: program.currentWeek,
      currentDay: program.currentDay,
      startDate: _toUtc(program.startDate),
      endDate: _toUtcNullable(program.endDate),
      isActive: program.isActive,
      isCompleted: program.isCompleted,
      completedAt: _toUtcNullable(program.completedAt),
      createdAt: _toUtc(program.createdAt),
      programStructure: program.programStructure,
      workouts: program.workouts,
      goal: program.goal,
    );
  }

  Map<String, dynamic> toJson() => _$ProgramToJson(this);

  /// Calculate progress percentage through the program
  double get progressPercentage {
    final totalDays = totalWeeks * 7;
    final completedDays = ((currentWeek - 1) * 7) + currentDay;
    return (completedDays / totalDays * 100).clamp(0, 100);
  }

  /// Get the current phase based on week (assumes 3 phases)
  int get currentPhase {
    final phaseLength = totalWeeks ~/ 3;
    if (currentWeek <= phaseLength) return 1;
    if (currentWeek <= phaseLength * 2) return 2;
    return 3;
  }

  /// Get phase name based on current week
  String get phaseName {
    switch (currentPhase) {
      case 1:
        return 'Foundation';
      case 2:
        return 'Progressive Overload';
      case 3:
        return 'Peak Performance';
      default:
        return 'Unknown';
    }
  }

  /// Get today's workout if available
  ProgramWorkout? get todaysWorkout {
    if (workouts == null) return null;
    return workouts!.firstWhere(
      (w) => w.weekNumber == currentWeek && w.dayNumber == currentDay,
      orElse: () => workouts!.first, // Fallback to avoid crash
    );
  }

  /// Get number of completed workouts
  int get completedWorkoutsCount {
    if (workouts == null) return 0;
    return workouts!.where((w) => w.isCompleted).length;
  }

  /// Get total number of workouts
  int get totalWorkoutsCount {
    return workouts?.length ?? 0;
  }

  /// Get days remaining in program
  int get daysRemaining {
    final totalDays = totalWeeks * 7;
    final currentDays = ((currentWeek - 1) * 7) + currentDay;
    return (totalDays - currentDays).clamp(0, totalDays);
  }

  /// Check if a workout is missed (past its date but not completed)
  bool isWorkoutMissed(ProgramWorkout workout) {
    // Can't be missed if already completed
    if (workout.isCompleted) return false;

    // Can't be missed if it's a rest day
    if (workout.isRestDay) return false;

    // Calculate the scheduled date for this workout
    final workoutDate = startDate.add(
      Duration(days: (workout.weekNumber - 1) * 7 + (workout.dayNumber - 1)),
    );

    // Calculate today's date in the program
    final programToday = startDate.add(
      Duration(days: (currentWeek - 1) * 7 + (currentDay - 1)),
    );

    // Workout is missed if its date is before today
    return workoutDate.isBefore(programToday);
  }

  Program copyWith({
    int? id,
    int? userId,
    String? title,
    String? description,
    int? goalId,
    int? totalWeeks,
    int? currentWeek,
    int? currentDay,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
    bool? isCompleted,
    DateTime? completedAt,
    DateTime? createdAt,
    String? programStructure,
    List<ProgramWorkout>? workouts,
    Goal? goal,
  }) {
    return Program(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      goalId: goalId ?? this.goalId,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      currentWeek: currentWeek ?? this.currentWeek,
      currentDay: currentDay ?? this.currentDay,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      programStructure: programStructure ?? this.programStructure,
      workouts: workouts ?? this.workouts,
      goal: goal ?? this.goal,
    );
  }
}
