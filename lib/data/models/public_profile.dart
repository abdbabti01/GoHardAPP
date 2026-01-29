import 'package:json_annotation/json_annotation.dart';

part 'public_profile.g.dart';

@JsonSerializable()
class PublicProfile {
  final int userId;
  final String username;
  final String name;
  final String? profilePhotoUrl;
  final String? bio;
  final String? experienceLevel;
  final DateTime memberSince;
  final bool isFriend;
  final int sharedWorkoutsCount;
  final int? totalWorkoutsCount; // Only visible to friends

  PublicProfile({
    required this.userId,
    required this.username,
    required this.name,
    this.profilePhotoUrl,
    this.bio,
    this.experienceLevel,
    required this.memberSince,
    required this.isFriend,
    required this.sharedWorkoutsCount,
    this.totalWorkoutsCount,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) =>
      _$PublicProfileFromJson(json);
  Map<String, dynamic> toJson() => _$PublicProfileToJson(this);
}
