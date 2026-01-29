// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RunSession _$RunSessionFromJson(Map<String, dynamic> json) => RunSession(
  id: (json['id'] as num).toInt(),
  userId: (json['userId'] as num).toInt(),
  name: json['name'] as String?,
  date: DateTime.parse(json['date'] as String),
  distance: (json['distance'] as num?)?.toDouble(),
  duration: (json['duration'] as num?)?.toInt(),
  averagePace: (json['averagePace'] as num?)?.toDouble(),
  calories: (json['calories'] as num?)?.toInt(),
  status: json['status'] as String? ?? 'draft',
  startedAt:
      json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
  completedAt:
      json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
  pausedAt:
      json['pausedAt'] == null
          ? null
          : DateTime.parse(json['pausedAt'] as String),
  route:
      (json['route'] as List<dynamic>?)
          ?.map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$RunSessionToJson(RunSession instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'name': instance.name,
      'date': instance.date.toIso8601String(),
      'distance': instance.distance,
      'duration': instance.duration,
      'averagePace': instance.averagePace,
      'calories': instance.calories,
      'status': instance.status,
      'startedAt': instance.startedAt?.toIso8601String(),
      'completedAt': instance.completedAt?.toIso8601String(),
      'pausedAt': instance.pausedAt?.toIso8601String(),
      'route': instance.route,
    };
