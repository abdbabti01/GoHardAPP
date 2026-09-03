import 'package:json_annotation/json_annotation.dart';

import '../../core/utils/datetime_helper.dart';

part 'exercise_set.g.dart';

@JsonSerializable()
class ExerciseSet {
  final int id;
  final int exerciseId;
  final int setNumber;
  final int? reps;
  final double? weight;
  final int? duration;
  final bool isCompleted;

  /// The moment the set was completed. This is an absolute instant - the API
  /// stamps it with `DateTime.UtcNow` and always serializes it as UTC - not a
  /// floating local wall-clock time. It must therefore cross the wire as UTC
  /// with a `Z` suffix: [DateTimeHelper.formatTimestampOrNull] converts the
  /// value (Isar hands DateTimes back local-flagged) to `value.toUtc()` before
  /// encoding, wired in via the [JsonKey] below so the generated
  /// `_$ExerciseSetToJson` uses it and no field can silently drift onto the
  /// wire with the raw `toIso8601String()` encoding.
  @JsonKey(toJson: DateTimeHelper.formatTimestampOrNull)
  final DateTime? completedAt;
  final String? notes;

  ExerciseSet({
    required this.id,
    required this.exerciseId,
    required this.setNumber,
    this.reps,
    this.weight,
    this.duration,
    this.isCompleted = false,
    this.completedAt,
    this.notes,
  });

  factory ExerciseSet.fromJson(Map<String, dynamic> json) =>
      _$ExerciseSetFromJson(json);

  Map<String, dynamic> toJson() => _$ExerciseSetToJson(this);
}
