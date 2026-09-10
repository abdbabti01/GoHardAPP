import 'package:json_annotation/json_annotation.dart';

part 'profile_update_request.g.dart';

@JsonSerializable()
class ProfileUpdateRequest {
  final String? name;

  /// Account handle (`@username`). Distinct from [name], which is the
  /// free-text display name. Omitted (null) means "leave unchanged" - the
  /// deployed API treats an absent `username` as no-op and only validates a
  /// present one (1-30 chars, `[A-Za-z0-9_]`).
  final String? username;

  final String? bio;
  final DateTime? dateOfBirth;
  final String? gender;
  final double? height;
  final double? weight;
  final double? targetWeight;
  final double? bodyFatPercentage;
  final String? experienceLevel;
  final String? primaryGoal;
  final String? activityLevel;
  final String? goals;
  final String? unitPreference;
  final String? themePreference;
  final String? favoriteExercises;

  ProfileUpdateRequest({
    this.name,
    this.username,
    this.bio,
    this.dateOfBirth,
    this.gender,
    this.height,
    this.weight,
    this.targetWeight,
    this.bodyFatPercentage,
    this.experienceLevel,
    this.primaryGoal,
    this.activityLevel,
    this.goals,
    this.unitPreference,
    this.themePreference,
    this.favoriteExercises,
  });

  factory ProfileUpdateRequest.fromJson(Map<String, dynamic> json) =>
      _$ProfileUpdateRequestFromJson(json);

  Map<String, dynamic> toJson() {
    final json = _$ProfileUpdateRequestToJson(this);

    // Date of birth is a calendar date, not an instant. The generated
    // serializer emits a full ISO-8601 timestamp (`toIso8601String()`); if
    // that carries a time/zone the server can round-trip it to a different
    // day for users behind/ahead of UTC. Send date-only (`yyyy-MM-dd`) so the
    // day the user picked is the day that is stored and read back.
    final dob = dateOfBirth;
    if (dob != null) {
      json['dateOfBirth'] =
          '${dob.year.toString().padLeft(4, '0')}-'
          '${dob.month.toString().padLeft(2, '0')}-'
          '${dob.day.toString().padLeft(2, '0')}';
    }

    // Remove null values to avoid sending unnecessary fields
    json.removeWhere((key, value) => value == null);
    return json;
  }
}
