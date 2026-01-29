// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'program_workout.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProgramWorkout _$ProgramWorkoutFromJson(Map<String, dynamic> json) =>
    ProgramWorkout(
      id: (json['id'] as num).toInt(),
      programId: (json['programId'] as num).toInt(),
      weekNumber: (json['weekNumber'] as num).toInt(),
      dayNumber: (json['dayNumber'] as num).toInt(),
      dayName: json['dayName'] as String?,
      workoutName: json['workoutName'] as String,
      workoutType: json['workoutType'] as String?,
      description: json['description'] as String?,
      estimatedDuration: (json['estimatedDuration'] as num?)?.toInt(),
      exercisesJson: json['exercisesJson'] as String,
      warmUp: json['warmUp'] as String?,
      coolDown: json['coolDown'] as String?,
      isCompleted: json['isCompleted'] as bool,
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      completionNotes: json['completionNotes'] as String?,
      orderIndex: (json['orderIndex'] as num).toInt(),
      scheduledDate: json['scheduledDate'] == null
          ? null
          : DateTime.parse(json['scheduledDate'] as String),
    );

Map<String, dynamic> _$ProgramWorkoutToJson(ProgramWorkout instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'programId': instance.programId,
    'weekNumber': instance.weekNumber,
    'dayNumber': instance.dayNumber,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('dayName', instance.dayName);
  val['workoutName'] = instance.workoutName;
  writeNotNull('workoutType', instance.workoutType);
  writeNotNull('description', instance.description);
  writeNotNull('estimatedDuration', instance.estimatedDuration);
  val['exercisesJson'] = instance.exercisesJson;
  writeNotNull('warmUp', instance.warmUp);
  writeNotNull('coolDown', instance.coolDown);
  val['isCompleted'] = instance.isCompleted;
  writeNotNull('completedAt', instance.completedAt?.toIso8601String());
  writeNotNull('completionNotes', instance.completionNotes);
  val['orderIndex'] = instance.orderIndex;
  writeNotNull('scheduledDate', instance.scheduledDate?.toIso8601String());
  return val;
}
