import 'package:json_annotation/json_annotation.dart';
import 'chat_message.dart';

part 'chat_conversation.g.dart';

@JsonSerializable()
class ChatConversation {
  final int id;
  final int userId;
  final String title;
  final String
  type; // 'general', 'workout_plan', 'meal_plan', 'progress_analysis'
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final bool isArchived;
  final List<ChatMessage> messages;
  final int? messageCount; // For list view without loading all messages

  /// If a draft program was auto-created for this (workout_plan) conversation, its id.
  final int? draftProgramId;

  /// The draft's actual week count — decided once at generation time and never editable at
  /// confirm time, since the draft is the single reviewed source of truth for activation.
  final int? draftTotalWeeks;

  /// The draft's proposed (Monday-snapped) start date, shown before activation. The user can
  /// still override it when confirming.
  final DateTime? draftProposedStartDate;

  /// Total non-rest-day workouts already materialized on the draft.
  final int? draftWorkoutCount;

  /// Content fingerprint of the draft's reviewable content (weeks/exercises/schedule shape —
  /// never the start date). Must be echoed back when confirming activation so the server can
  /// prove it's acting on exactly this reviewed content, not merely "whatever is latest". Null
  /// whenever the other draft* fields above are also null/unavailable (no draft, or a cached
  /// conversation that predates this field / was cached offline before it could be fetched) —
  /// see ChatConversationScreen's honest-preview handling, which never activates without this.
  final String? draftRevision;

  ChatConversation({
    required this.id,
    required this.userId,
    required this.title,
    required this.type,
    required this.createdAt,
    this.lastMessageAt,
    this.isArchived = false,
    this.messages = const [],
    this.messageCount,
    this.draftProgramId,
    this.draftTotalWeeks,
    this.draftProposedStartDate,
    this.draftWorkoutCount,
    this.draftRevision,
  });

  // Helper method to ensure datetime is in UTC
  static DateTime _toUtc(DateTime dt) {
    if (dt.isUtc) return dt;
    return dt.toUtc();
  }

  static DateTime? _toUtcNullable(DateTime? dt) {
    if (dt == null) return null;
    if (dt.isUtc) return dt;
    return dt.toUtc();
  }

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final conversation = _$ChatConversationFromJson(json);

    return ChatConversation(
      id: conversation.id,
      userId: conversation.userId,
      title: conversation.title,
      type: conversation.type,
      createdAt: _toUtc(conversation.createdAt),
      lastMessageAt: _toUtcNullable(conversation.lastMessageAt),
      isArchived: conversation.isArchived,
      messages: conversation.messages,
      messageCount: conversation.messageCount,
      draftProgramId: conversation.draftProgramId,
      draftTotalWeeks: conversation.draftTotalWeeks,
      draftProposedStartDate: _toUtcNullable(
        conversation.draftProposedStartDate,
      ),
      draftWorkoutCount: conversation.draftWorkoutCount,
      draftRevision: conversation.draftRevision,
    );
  }

  Map<String, dynamic> toJson() => _$ChatConversationToJson(this);

  ChatConversation copyWith({
    int? id,
    int? userId,
    String? title,
    String? type,
    DateTime? createdAt,
    DateTime? lastMessageAt,
    bool? isArchived,
    List<ChatMessage>? messages,
    int? messageCount,
    int? draftProgramId,
    int? draftTotalWeeks,
    DateTime? draftProposedStartDate,
    int? draftWorkoutCount,
    String? draftRevision,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      isArchived: isArchived ?? this.isArchived,
      messages: messages ?? this.messages,
      messageCount: messageCount ?? this.messageCount,
      draftProgramId: draftProgramId ?? this.draftProgramId,
      draftTotalWeeks: draftTotalWeeks ?? this.draftTotalWeeks,
      draftProposedStartDate:
          draftProposedStartDate ?? this.draftProposedStartDate,
      draftWorkoutCount: draftWorkoutCount ?? this.draftWorkoutCount,
      draftRevision: draftRevision ?? this.draftRevision,
    );
  }
}
