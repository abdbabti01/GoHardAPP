import 'package:json_annotation/json_annotation.dart';
import 'exercise.dart';

part 'session.g.dart';

@JsonSerializable()
class Session {
  final int id;
  final int userId;
  final DateTime date;
  final int? duration;
  final String? notes;
  final String? type;
  final String? name;
  final String status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? pausedAt;
  final List<Exercise> exercises;
  final int? programId;
  final int? programWorkoutId;
  final int version; // Version tracking for conflict resolution (Issue #13)

  Session({
    required this.id,
    required this.userId,
    required this.date,
    this.duration,
    this.notes,
    this.type,
    this.name,
    this.status = 'draft',
    this.startedAt,
    this.completedAt,
    this.pausedAt,
    this.exercises = const [],
    this.programId,
    this.programWorkoutId,
    this.version = 1,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    // Parse the session using generated code
    final session = _$SessionFromJson(json);

    // Normalize date to local midnight (fixes timezone issue where UTC midnight becomes yesterday)
    final normalizedDate = DateTime(
      session.date.year,
      session.date.month,
      session.date.day,
    );

    // Convert timestamp fields to UTC using standard conversion
    // NOTE: The 'date' field is date-only and normalized to local timezone midnight above
    // Timestamps (startedAt, completedAt, pausedAt) MUST be UTC for proper time calculations
    // Using toUtc() ensures proper conversion regardless of JSON parser behavior
    return Session(
      id: session.id,
      userId: session.userId,
      date:
          normalizedDate, // Normalize to local midnight (fixes timezone issue)
      duration: session.duration,
      notes: session.notes,
      type: session.type,
      name: session.name, // Preserve workout name
      status: session.status,
      startedAt: session.startedAt?.toUtc(), // Convert to UTC (timestamp)
      completedAt: session.completedAt?.toUtc(), // Convert to UTC (timestamp)
      pausedAt: session.pausedAt?.toUtc(), // Convert to UTC (timestamp)
      exercises: session.exercises,
      programId: session.programId,
      programWorkoutId: session.programWorkoutId,
      version: session.version,
    );
  }

  Map<String, dynamic> toJson() => _$SessionToJson(this);

  /// Check if session is from a program
  bool get isFromProgram => programId != null && programId! > 0;

  /// Create a copy of this Session with some fields replaced
  Session copyWith({
    int? id,
    int? userId,
    DateTime? date,
    int? duration,
    String? notes,
    String? type,
    String? name,
    String? status,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? pausedAt,
    List<Exercise>? exercises,
    int? programId,
    int? programWorkoutId,
    int? version,
  }) {
    return Session(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      duration: duration ?? this.duration,
      notes: notes ?? this.notes,
      type: type ?? this.type,
      name: name ?? this.name,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      pausedAt: pausedAt ?? this.pausedAt,
      exercises: exercises ?? this.exercises,
      programId: programId ?? this.programId,
      programWorkoutId: programWorkoutId ?? this.programWorkoutId,
      version: version ?? this.version,
    );
  }
}
