// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'direct_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DirectMessage _$DirectMessageFromJson(Map<String, dynamic> json) =>
    DirectMessage(
      id: (json['id'] as num).toInt(),
      senderId: (json['senderId'] as num).toInt(),
      content: json['content'] as String,
      sentAt: DateTime.parse(json['sentAt'] as String),
      readAt:
          json['readAt'] == null
              ? null
              : DateTime.parse(json['readAt'] as String),
      isFromMe: json['isFromMe'] as bool,
    );

Map<String, dynamic> _$DirectMessageToJson(DirectMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'senderId': instance.senderId,
      'content': instance.content,
      'sentAt': instance.sentAt.toIso8601String(),
      'readAt': instance.readAt?.toIso8601String(),
      'isFromMe': instance.isFromMe,
    };
