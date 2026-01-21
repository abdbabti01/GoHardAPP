import 'package:json_annotation/json_annotation.dart';
import 'gps_point.dart';

part 'run_session.g.dart';

/// Represents a running session with GPS tracking
@JsonSerializable()
class RunSession {
  final int id;
  final int userId;
  final String? name;
  final DateTime date;
  final double? distance; // km
  final int? duration; // seconds
  final double? averagePace; // min/km
  final int? calories;
  final String status; // draft, in_progress, completed
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? pausedAt;
  final List<GpsPoint> route; // GPS coordinates

  RunSession({
    required this.id,
    required this.userId,
    this.name,
    required this.date,
    this.distance,
    this.duration,
    this.averagePace,
    this.calories,
    this.status = 'draft',
    this.startedAt,
    this.completedAt,
    this.pausedAt,
    this.route = const [],
  });

  factory RunSession.fromJson(Map<String, dynamic> json) {
    final session = _$RunSessionFromJson(json);

    // Normalize date to local midnight
    final normalizedDate = DateTime(
      session.date.year,
      session.date.month,
      session.date.day,
    );

    return RunSession(
      id: session.id,
      userId: session.userId,
      name: session.name,
      date: normalizedDate,
      distance: session.distance,
      duration: session.duration,
      averagePace: session.averagePace,
      calories: session.calories,
      status: session.status,
      startedAt: session.startedAt?.toUtc(),
      completedAt: session.completedAt?.toUtc(),
      pausedAt: session.pausedAt?.toUtc(),
      route: session.route,
    );
  }

  Map<String, dynamic> toJson() => _$RunSessionToJson(this);

  /// Calculate pace from distance and duration
  double? get calculatedPace {
    if (distance == null || duration == null || distance! <= 0) return null;
    // Pace in min/km = (duration in seconds / 60) / distance in km
    return (duration! / 60) / distance!;
  }

  /// Format pace as string (e.g., "5'30\"")
  String get formattedPace {
    final pace = averagePace ?? calculatedPace;
    if (pace == null) return '--:--';
    final minutes = pace.floor();
    final seconds = ((pace - minutes) * 60).round();
    return "$minutes'${seconds.toString().padLeft(2, '0')}\"";
  }

  /// Format duration as string (e.g., "28:30" or "1:28:30")
  String get formattedDuration {
    if (duration == null) return '--:--';
    final hours = duration! ~/ 3600;
    final minutes = (duration! % 3600) ~/ 60;
    final seconds = duration! % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format distance as string (e.g., "5.23 km")
  String get formattedDistance {
    if (distance == null) return '0.00 km';
    return '${distance!.toStringAsFixed(2)} km';
  }

  RunSession copyWith({
    int? id,
    int? userId,
    String? name,
    DateTime? date,
    double? distance,
    int? duration,
    double? averagePace,
    int? calories,
    String? status,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? pausedAt,
    List<GpsPoint>? route,
  }) {
    return RunSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      date: date ?? this.date,
      distance: distance ?? this.distance,
      duration: duration ?? this.duration,
      averagePace: averagePace ?? this.averagePace,
      calories: calories ?? this.calories,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      pausedAt: pausedAt ?? this.pausedAt,
      route: route ?? this.route,
    );
  }
}
