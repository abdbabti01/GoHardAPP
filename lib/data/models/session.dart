import 'package:json_annotation/json_annotation.dart';
import 'exercise.dart';
import '../../core/utils/datetime_helper.dart';

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
    // Parse exercises manually to handle the list
    final exercisesList =
        (json['exercises'] as List<dynamic>?)
            ?.map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return Session(
      id: json['id'] as int,
      userId: json['userId'] as int,
      // Date-only field: API returns "yyyy-MM-dd", parse as local date
      date: DateTimeHelper.parseDateFromJson(json['date']),
      duration: json['duration'] as int?,
      notes: json['notes'] as String?,
      type: json['type'] as String?,
      name: json['name'] as String?,
      status: json['status'] as String? ?? 'draft',
      // Timestamp fields: API returns with 'Z' suffix, parse as UTC
      startedAt: DateTimeHelper.parseTimestampOrNullFromJson(json['startedAt']),
      completedAt: DateTimeHelper.parseTimestampOrNullFromJson(
        json['completedAt'],
      ),
      pausedAt: DateTimeHelper.parseTimestampOrNullFromJson(json['pausedAt']),
      exercises: exercisesList,
      programId: json['programId'] as int?,
      programWorkoutId: json['programWorkoutId'] as int?,
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      // Date-only field: format as "yyyy-MM-dd"
      'date': DateTimeHelper.formatDate(date),
      'duration': duration,
      'notes': notes,
      'type': type,
      'name': name,
      'status': status,
      // Timestamp fields: format as UTC ISO 8601
      'startedAt':
          startedAt != null ? DateTimeHelper.formatTimestamp(startedAt!) : null,
      'completedAt':
          completedAt != null
              ? DateTimeHelper.formatTimestamp(completedAt!)
              : null,
      'pausedAt':
          pausedAt != null ? DateTimeHelper.formatTimestamp(pausedAt!) : null,
      'exercises': exercises.map((e) => e.toJson()).toList(),
      'programId': programId,
      'programWorkoutId': programWorkoutId,
      'version': version,
    };
  }

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
