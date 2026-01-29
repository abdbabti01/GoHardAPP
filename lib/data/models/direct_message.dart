import 'package:json_annotation/json_annotation.dart';

part 'direct_message.g.dart';

@JsonSerializable()
class DirectMessage {
  final int id;
  final int senderId;
  final String content;
  final DateTime sentAt;
  final DateTime? readAt;
  final bool isFromMe;

  DirectMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.sentAt,
    this.readAt,
    required this.isFromMe,
  });

  factory DirectMessage.fromJson(Map<String, dynamic> json) =>
      _$DirectMessageFromJson(json);
  Map<String, dynamic> toJson() => _$DirectMessageToJson(this);
}
