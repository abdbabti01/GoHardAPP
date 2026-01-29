// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Friend _$FriendFromJson(Map<String, dynamic> json) => Friend(
  userId: (json['userId'] as num).toInt(),
  username: json['username'] as String,
  name: json['name'] as String,
  profilePhotoUrl: json['profilePhotoUrl'] as String?,
  friendsSince: DateTime.parse(json['friendsSince'] as String),
);

Map<String, dynamic> _$FriendToJson(Friend instance) => <String, dynamic>{
  'userId': instance.userId,
  'username': instance.username,
  'name': instance.name,
  'profilePhotoUrl': instance.profilePhotoUrl,
  'friendsSince': instance.friendsSince.toIso8601String(),
};
