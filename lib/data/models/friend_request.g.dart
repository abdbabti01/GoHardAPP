// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FriendRequest _$FriendRequestFromJson(Map<String, dynamic> json) =>
    FriendRequest(
      friendshipId: (json['friendshipId'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      username: json['username'] as String,
      name: json['name'] as String,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      requestedAt: DateTime.parse(json['requestedAt'] as String),
    );

Map<String, dynamic> _$FriendRequestToJson(FriendRequest instance) =>
    <String, dynamic>{
      'friendshipId': instance.friendshipId,
      'userId': instance.userId,
      'username': instance.username,
      'name': instance.name,
      'profilePhotoUrl': instance.profilePhotoUrl,
      'requestedAt': instance.requestedAt.toIso8601String(),
    };
