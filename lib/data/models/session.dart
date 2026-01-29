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

    // CRITICAL FIX: Convert timestamp fields to UTC properly
    // The API returns timestamps in UTC, but if the 'Z' suffix is missing,
    // Dart's DateTime.parse() creates a LOCAL DateTime with the raw values.
    // Calling .toUtc() on a local DateTime SHIFTS the time by timezone offset (BUG!).
    // Instead, we must reconstruct the DateTime as UTC from the raw components.
    // This treats the raw values AS UTC, which is correct since the API sends UTC.
    DateTime? toUtcTimestamp(DateTime? dt) {
      if (dt == null) return null;
      // If already UTC, return as-is
      if (dt.isUtc) return dt;
      // Construct UTC DateTime from the raw components (NOT using toUtc which would shift the time)
      return DateTime.utc(
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second,
        dt.millisecond,
        dt.microsecond,
      );
    }

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
      startedAt: toUtcTimestamp(session.startedAt), // Properly treat as UTC
      completedAt: toUtcTimestamp(session.completedAt), // Properly treat as UTC
      pausedAt: toUtcTimestamp(session.pausedAt), // Properly treat as UTC
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
