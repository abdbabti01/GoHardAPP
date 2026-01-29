import 'package:json_annotation/json_annotation.dart';

part 'dm_conversation.g.dart';

@JsonSerializable()
class DMConversation {
  final int friendId;
  final String friendUsername;
  final String friendName;
  final String? friendPhotoUrl;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  DMConversation({
    required this.friendId,
    required this.friendUsername,
    required this.friendName,
    this.friendPhotoUrl,
    this.lastMessage,
    this.lastMessageAt,
    required this.unreadCount,
  });

  factory DMConversation.fromJson(Map<String, dynamic> json) =>
      _$DMConversationFromJson(json);
  Map<String, dynamic> toJson() => _$DMConversationToJson(this);
}
