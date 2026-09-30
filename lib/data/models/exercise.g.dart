// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exercise.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Exercise _$ExerciseFromJson(Map<String, dynamic> json) => Exercise(
  id: (json['id'] as num).toInt(),
  sessionId: (json['sessionId'] as num).toInt(),
  name: json['name'] as String,
  sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
  duration: (json['duration'] as num?)?.toInt(),
  restTime: (json['restTime'] as num?)?.toInt(),
  notes: json['notes'] as String?,
  exerciseTemplateId: (json['exerciseTemplateId'] as num?)?.toInt(),
  occurrenceKey: json['occurrenceKey'] as String?,
  targetSets: (json['targetSets'] as num?)?.toInt(),
  targetRepsMin: (json['targetRepsMin'] as num?)?.toInt(),
  targetRepsMax: (json['targetRepsMax'] as num?)?.toInt(),
  exerciseSets:
      (json['exerciseSets'] as List<dynamic>?)
          ?.map((e) => ExerciseSet.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  version: (json['version'] as num?)?.toInt() ?? 1,
);

Map<String, dynamic> _$ExerciseToJson(Exercise instance) => <String, dynamic>{
  'id': instance.id,
  'sessionId': instance.sessionId,
  'name': instance.name,
  'sortOrder': instance.sortOrder,
  'duration': instance.duration,
  'restTime': instance.restTime,
  'notes': instance.notes,
  'exerciseTemplateId': instance.exerciseTemplateId,
  'occurrenceKey': instance.occurrenceKey,
  'targetSets': instance.targetSets,
  'targetRepsMin': instance.targetRepsMin,
  'targetRepsMax': instance.targetRepsMax,
  'exerciseSets': instance.exerciseSets,
  'version': instance.version,
};
