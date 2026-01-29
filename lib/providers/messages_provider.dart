import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/direct_message.dart';
import '../data/models/dm_conversation.dart';
import '../data/repositories/direct_messages_repository.dart';

/// Provider for managing direct messages
class MessagesProvider extends ChangeNotifier {
  final DirectMessagesRepository _repository;

  List<DMConversation> _conversations = [];
  final Map<int, List<DirectMessage>> _messagesByFriend = {};
  int _totalUnreadCount = 0;
  int? _activeConversationFriendId;

  bool _isLoading = false;
  bool _isLoadingMessages = false;
  bool _isSending = false;
  String? _errorMessage;

  Timer? _conversationPollingTimer;
  Timer? _unreadCountPollingTimer;

  MessagesProvider(this._repository);

  // Getters
  List<DMConversation> get conversations => _conversations;
  int get totalUnreadCount => _totalUnreadCount;
  bool get isLoading => _isLoading;
  bool get isLoadingMessages => _isLoadingMessages;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;

  /// Get messages for a specific friend
  List<DirectMessage> getMessagesForFriend(int friendId) {
    return _messagesByFriend[friendId] ?? [];
  }

  /// Load all conversations
  Future<void> loadConversations({bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _conversations = await _repository.getConversations();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ MessagesProvider.loadConversations error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load messages for a conversation
  Future<void> loadMessages(int friendId, {bool showLoading = true}) async {
    if (showLoading) {
      _isLoadingMessages = true;
      notifyListeners();
    }

    try {
      final messages = await _repository.getMessages(friendId);
      _messagesByFriend[friendId] = messages;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ MessagesProvider.loadMessages error: $e');
    } finally {
      _isLoadingMessages = false;
      notifyListeners();
    }
  }

  /// Load more messages (pagination)
  Future<void> loadMoreMessages(int friendId) async {
    final currentMessages = _messagesByFriend[friendId] ?? [];
    if (currentMessages.isEmpty) return;

    final oldestId = currentMessages.first.id;

    try {
      final olderMessages = await _repository.getMessages(
        friendId,
        beforeId: oldestId,
      );

      if (olderMessages.isNotEmpty) {
        _messagesByFriend[friendId] = [...olderMessages, ...currentMessages];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ MessagesProvider.loadMoreMessages error: $e');
    }
  }

  /// Send a message
  Future<bool> sendMessage(int friendId, String content) async {
    if (content.trim().isEmpty) return false;

    _isSending = true;
    notifyListeners();

    try {
      final message = await _repository.sendMessage(friendId, content);

      // Add to local messages
      final currentMessages = _messagesByFriend[friendId] ?? [];
      _messagesByFriend[friendId] = [...currentMessages, message];

      // Update conversation's last message
      _updateConversationLastMessage(friendId, message);

      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ MessagesProvider.sendMessage error: $e');
      notifyListeners();
      return false;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  /// Update conversation's last message locally
  void _updateConversationLastMessage(int friendId, DirectMessage message) {
    final index = _conversations.indexWhere((c) => c.friendId == friendId);
    if (index != -1) {
      final conv = _conversations[index];
      _conversations[index] = DMConversation(
        friendId: conv.friendId,
        friendUsername: conv.friendUsername,
        friendName: conv.friendName,
        friendPhotoUrl: conv.friendPhotoUrl,
        lastMessage: message.content,
        lastMessageAt: message.sentAt,
        unreadCount: conv.unreadCount,
      );

      // Move to top
      final updated = _conversations.removeAt(index);
      _conversations.insert(0, updated);
    }
  }

  /// Mark messages as read
  Future<void> markAsRead(int friendId) async {
    try {
      await _repository.markAsRead(friendId);

      // Update local state
      final index = _conversations.indexWhere((c) => c.friendId == friendId);
      if (index != -1) {
        final conv = _conversations[index];
        final unreadToSubtract = conv.unreadCount;
        _conversations[index] = DMConversation(
          friendId: conv.friendId,
          friendUsername: conv.friendUsername,
          friendName: conv.friendName,
          friendPhotoUrl: conv.friendPhotoUrl,
          lastMessage: conv.lastMessage,
          lastMessageAt: conv.lastMessageAt,
          unreadCount: 0,
        );
        _totalUnreadCount = (_totalUnreadCount - unreadToSubtract).clamp(
          0,
          999,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ MessagesProvider.markAsRead error: $e');
    }
  }

  /// Load total unread count
  Future<void> loadUnreadCount() async {
    try {
      _totalUnreadCount = await _repository.getUnreadCount();
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ MessagesProvider.loadUnreadCount error: $e');
    }
  }

  /// Start polling for active conversation (5 seconds)
  void startConversationPolling(int friendId) {
    _activeConversationFriendId = friendId;
    stopConversationPolling();

    _conversationPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_activeConversationFriendId == friendId) {
        _pollForNewMessages(friendId);
      }
    });
  }

  /// Poll for new messages
  Future<void> _pollForNewMessages(int friendId) async {
    try {
      final currentMessages = _messagesByFriend[friendId] ?? [];
      final newMessages = await _repository.getMessages(friendId, limit: 20);

      if (newMessages.isNotEmpty) {
        // Find messages that are newer than what we have
        final latestId =
            currentMessages.isNotEmpty ? currentMessages.last.id : 0;

        final trulyNewMessages =
            newMessages.where((m) => m.id > latestId).toList();

        if (trulyNewMessages.isNotEmpty) {
          _messagesByFriend[friendId] = [
            ...currentMessages,
            ...trulyNewMessages,
          ];

          // Mark as read since user is viewing
          markAsRead(friendId);

          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('⚠️ MessagesProvider._pollForNewMessages error: $e');
    }
  }

  /// Stop conversation polling
  void stopConversationPolling() {
    _conversationPollingTimer?.cancel();
    _conversationPollingTimer = null;
    _activeConversationFriendId = null;
  }

  /// Start polling for unread count (30 seconds)
  void startUnreadCountPolling() {
    stopUnreadCountPolling();
    _unreadCountPollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => loadUnreadCount(),
    );
  }

  /// Stop unread count polling
  void stopUnreadCountPolling() {
    _unreadCountPollingTimer?.cancel();
    _unreadCountPollingTimer = null;
  }

  /// Clear messages cache
  void clearMessagesCache() {
    _messagesByFriend.clear();
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopConversationPolling();
    stopUnreadCountPolling();
    super.dispose();
  }
}
