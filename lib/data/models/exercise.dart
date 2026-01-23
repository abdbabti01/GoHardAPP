import 'package:json_annotation/json_annotation.dart';
import 'exercise_set.dart';

part 'exercise.g.dart';

@JsonSerializable()
class Exercise {
  final int id;
  final int sessionId;
  final String name;
  final int sortOrder; // Display order within session (0-indexed)
  final int? duration;
  final int? restTime;
  final String? notes;
  final int? exerciseTemplateId;
  final List<ExerciseSet> exerciseSets;
  final int version; // Version tracking for conflict resolution (Issue #13)

  Exercise({
    required this.id,
    required this.sessionId,
    required this.name,
    this.sortOrder = 0,
    this.duration,
    this.restTime,
    this.notes,
    this.exerciseTemplateId,
    this.exerciseSets = const [],
    this.version = 1,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) =>
      _$ExerciseFromJson(json);
  Map<String, dynamic> toJson() => _$ExerciseToJson(this);

  Exercise copyWith({
    int? id,
    int? sessionId,
    String? name,
    int? sortOrder,
    int? duration,
    int? restTime,
    String? notes,
    int? exerciseTemplateId,
    List<ExerciseSet>? exerciseSets,
    int? version,
  }) {
    return Exercise(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      duration: duration ?? this.duration,
      restTime: restTime ?? this.restTime,
      notes: notes ?? this.notes,
      exerciseTemplateId: exerciseTemplateId ?? this.exerciseTemplateId,
      exerciseSets: exerciseSets ?? this.exerciseSets,
      version: version ?? this.version,
    );
  }
}
