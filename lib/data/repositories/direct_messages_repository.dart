import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../models/direct_message.dart';
import '../models/dm_conversation.dart';
import '../services/api_service.dart';

/// Repository for direct messages operations
class DirectMessagesRepository {
  final ApiService _apiService;
  final ConnectivityService? _connectivity;

  DirectMessagesRepository(this._apiService, [this._connectivity]);

  bool get _isOnline => _connectivity?.isOnline ?? true;

  /// Get all conversations for the current user
  Future<List<DMConversation>> getConversations() async {
    if (!_isOnline) {
      debugPrint('📴 Offline - messages feature requires online connection');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.dmConversations,
      );
      return data
          .map((json) => DMConversation.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to fetch conversations: $e');
      rethrow;
    }
  }

  /// Get messages in a conversation with a friend (paginated)
  Future<List<DirectMessage>> getMessages(
    int friendId, {
    int? beforeId,
    int limit = 50,
  }) async {
    if (!_isOnline) return [];

    try {
      final queryParams = <String, String>{'limit': limit.toString()};
      if (beforeId != null) {
        queryParams['beforeId'] = beforeId.toString();
      }

      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.dmMessages(friendId),
        queryParameters: queryParams,
      );
      return data
          .map((json) => DirectMessage.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to fetch messages: $e');
      rethrow;
    }
  }

  /// Send a message to a friend
  Future<DirectMessage> sendMessage(int friendId, String content) async {
    if (!_isOnline) {
      throw Exception('Cannot send message while offline');
    }

    try {
      final data = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.dmMessages(friendId),
        data: {'content': content},
      );
      return DirectMessage.fromJson(data);
    } catch (e) {
      debugPrint('⚠️ Failed to send message: $e');
      rethrow;
    }
  }

  /// Mark messages from a friend as read
  Future<void> markAsRead(int friendId) async {
    if (!_isOnline) return;

    try {
      await _apiService.post<Map<String, dynamic>>(
        ApiConfig.dmMarkAsRead(friendId),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to mark messages as read: $e');
      // Don't rethrow - this is not critical
    }
  }

  /// Get total unread message count across all conversations
  Future<int> getUnreadCount() async {
    if (!_isOnline) return 0;

    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.dmUnreadCount,
      );
      return data['unreadCount'] as int? ?? 0;
    } catch (e) {
      debugPrint('⚠️ Failed to get unread count: $e');
      return 0;
    }
  }
}
