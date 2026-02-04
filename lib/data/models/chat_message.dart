import 'package:json_annotation/json_annotation.dart';

part 'chat_message.g.dart';

@JsonSerializable()
class ChatMessage {
  final int id;
  final int conversationId;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime createdAt;
  final int? inputTokens;
  final int? outputTokens;
  final String? model;

  /// Type of structured content: 'text', 'workout_plan', 'meal_plan', 'progress_analysis'
  /// Used for rendering rich preview cards
  final String contentType;

  /// Parsed structured data for rich preview cards (workout sessions, meal plan days, etc.)
  /// Null for regular text messages
  final Map<String, dynamic>? structuredData;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.inputTokens,
    this.outputTokens,
    this.model,
    this.contentType = 'text',
    this.structuredData,
  });

  /// Whether this message has structured data for rich rendering
  bool get hasStructuredData => structuredData != null && contentType != 'text';

  /// Whether this is a workout plan message
  bool get isWorkoutPlan => contentType == 'workout_plan';

  /// Whether this is a meal plan message
  bool get isMealPlan => contentType == 'meal_plan';

  /// Whether this is a progress analysis message
  bool get isProgressAnalysis => contentType == 'progress_analysis';

  // Helper method to ensure datetime is in UTC
  static DateTime _toUtc(DateTime dt) {
    if (dt.isUtc) return dt;
    return dt.toUtc();
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final message = _$ChatMessageFromJson(json);

    return ChatMessage(
      id: message.id,
      conversationId: message.conversationId,
      role: message.role,
      content: message.content,
      createdAt: _toUtc(message.createdAt),
      inputTokens: message.inputTokens,
      outputTokens: message.outputTokens,
      model: message.model,
      contentType: message.contentType,
      structuredData: message.structuredData,
    );
  }

  Map<String, dynamic> toJson() => _$ChatMessageToJson(this);

  ChatMessage copyWith({
    int? id,
    int? conversationId,
    String? role,
    String? content,
    DateTime? createdAt,
    int? inputTokens,
    int? outputTokens,
    String? model,
    String? contentType,
    Map<String, dynamic>? structuredData,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      model: model ?? this.model,
      contentType: contentType ?? this.contentType,
      structuredData: structuredData ?? this.structuredData,
    );
  }
}
