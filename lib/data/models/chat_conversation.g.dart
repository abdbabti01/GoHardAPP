// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_conversation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatConversation _$ChatConversationFromJson(Map<String, dynamic> json) =>
    ChatConversation(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      title: json['title'] as String,
      type: json['type'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastMessageAt:
          json['lastMessageAt'] == null
              ? null
              : DateTime.parse(json['lastMessageAt'] as String),
      isArchived: json['isArchived'] as bool? ?? false,
      messages:
          (json['messages'] as List<dynamic>?)
              ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      messageCount: (json['messageCount'] as num?)?.toInt(),
      draftProgramId: (json['draftProgramId'] as num?)?.toInt(),
      draftTotalWeeks: (json['draftTotalWeeks'] as num?)?.toInt(),
      draftProposedStartDate:
          json['draftProposedStartDate'] == null
              ? null
              : DateTime.parse(json['draftProposedStartDate'] as String),
      draftWorkoutCount: (json['draftWorkoutCount'] as num?)?.toInt(),
      draftRevision: json['draftRevision'] as String?,
    );

Map<String, dynamic> _$ChatConversationToJson(
  ChatConversation instance,
) => <String, dynamic>{
  'id': instance.id,
  'userId': instance.userId,
  'title': instance.title,
  'type': instance.type,
  'createdAt': instance.createdAt.toIso8601String(),
  'lastMessageAt': instance.lastMessageAt?.toIso8601String(),
  'isArchived': instance.isArchived,
  'messages': instance.messages,
  'messageCount': instance.messageCount,
  'draftProgramId': instance.draftProgramId,
  'draftTotalWeeks': instance.draftTotalWeeks,
  'draftProposedStartDate': instance.draftProposedStartDate?.toIso8601String(),
  'draftWorkoutCount': instance.draftWorkoutCount,
  'draftRevision': instance.draftRevision,
};
