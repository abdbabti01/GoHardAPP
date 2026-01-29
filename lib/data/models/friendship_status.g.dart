// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friendship_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FriendshipStatus _$FriendshipStatusFromJson(Map<String, dynamic> json) =>
    FriendshipStatus(
      status: json['status'] as String,
      friendshipId: (json['friendshipId'] as num?)?.toInt(),
    );

Map<String, dynamic> _$FriendshipStatusToJson(FriendshipStatus instance) =>
    <String, dynamic>{
      'status': instance.status,
      'friendshipId': instance.friendshipId,
    };
