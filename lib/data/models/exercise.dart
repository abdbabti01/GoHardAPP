import 'package:json_annotation/json_annotation.dart';
import 'exercise_set.dart';

part 'exercise.g.dart';

@JsonSerializable()
class Exercise {
  final int id;
  final int sessionId;
  final String name;
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
      duration: duration ?? this.duration,
      restTime: restTime ?? this.restTime,
      notes: notes ?? this.notes,
      exerciseTemplateId: exerciseTemplateId ?? this.exerciseTemplateId,
      exerciseSets: exerciseSets ?? this.exerciseSets,
      version: version ?? this.version,
    );
  }
}
