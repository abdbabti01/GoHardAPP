// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'public_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PublicProfile _$PublicProfileFromJson(Map<String, dynamic> json) =>
    PublicProfile(
      userId: (json['userId'] as num).toInt(),
      username: json['username'] as String,
      name: json['name'] as String,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      bio: json['bio'] as String?,
      experienceLevel: json['experienceLevel'] as String?,
      memberSince: DateTime.parse(json['memberSince'] as String),
      isFriend: json['isFriend'] as bool,
      sharedWorkoutsCount: (json['sharedWorkoutsCount'] as num).toInt(),
      totalWorkoutsCount: (json['totalWorkoutsCount'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PublicProfileToJson(PublicProfile instance) =>
    <String, dynamic>{
      'userId': instance.userId,
      'username': instance.username,
      'name': instance.name,
      'profilePhotoUrl': instance.profilePhotoUrl,
      'bio': instance.bio,
      'experienceLevel': instance.experienceLevel,
      'memberSince': instance.memberSince.toIso8601String(),
      'isFriend': instance.isFriend,
      'sharedWorkoutsCount': instance.sharedWorkoutsCount,
      'totalWorkoutsCount': instance.totalWorkoutsCount,
    };
