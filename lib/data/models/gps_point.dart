import 'package:json_annotation/json_annotation.dart';

part 'gps_point.g.dart';

/// Represents a single GPS coordinate point during a run
@JsonSerializable()
class GpsPoint {
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime timestamp;
  final double? speed; // m/s
  final double? accuracy; // meters

  GpsPoint({
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.timestamp,
    this.speed,
    this.accuracy,
  });

  factory GpsPoint.fromJson(Map<String, dynamic> json) =>
      _$GpsPointFromJson(json);

  Map<String, dynamic> toJson() => _$GpsPointToJson(this);

  GpsPoint copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    DateTime? timestamp,
    double? speed,
    double? accuracy,
  }) {
    return GpsPoint(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      timestamp: timestamp ?? this.timestamp,
      speed: speed ?? this.speed,
      accuracy: accuracy ?? this.accuracy,
    );
  }
}
