// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dm_conversation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DMConversation _$DMConversationFromJson(Map<String, dynamic> json) =>
    DMConversation(
      friendId: (json['friendId'] as num).toInt(),
      friendUsername: json['friendUsername'] as String,
      friendName: json['friendName'] as String,
      friendPhotoUrl: json['friendPhotoUrl'] as String?,
      lastMessage: json['lastMessage'] as String?,
      lastMessageAt: json['lastMessageAt'] == null
          ? null
          : DateTime.parse(json['lastMessageAt'] as String),
      unreadCount: (json['unreadCount'] as num).toInt(),
    );

Map<String, dynamic> _$DMConversationToJson(DMConversation instance) =>
    <String, dynamic>{
      'friendId': instance.friendId,
      'friendUsername': instance.friendUsername,
      'friendName': instance.friendName,
      'friendPhotoUrl': instance.friendPhotoUrl,
      'lastMessage': instance.lastMessage,
      'lastMessageAt': instance.lastMessageAt?.toIso8601String(),
      'unreadCount': instance.unreadCount,
    };
