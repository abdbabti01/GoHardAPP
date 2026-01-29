// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gps_point.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GpsPoint _$GpsPointFromJson(Map<String, dynamic> json) => GpsPoint(
  latitude: (json['latitude'] as num).toDouble(),
  longitude: (json['longitude'] as num).toDouble(),
  altitude: (json['altitude'] as num?)?.toDouble(),
  timestamp: DateTime.parse(json['timestamp'] as String),
  speed: (json['speed'] as num?)?.toDouble(),
  accuracy: (json['accuracy'] as num?)?.toDouble(),
);

Map<String, dynamic> _$GpsPointToJson(GpsPoint instance) => <String, dynamic>{
  'latitude': instance.latitude,
  'longitude': instance.longitude,
  'altitude': instance.altitude,
  'timestamp': instance.timestamp.toIso8601String(),
  'speed': instance.speed,
  'accuracy': instance.accuracy,
};
