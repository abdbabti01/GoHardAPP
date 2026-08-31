import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/direct_message.dart';
import '../models/dm_conversation.dart';
import '../services/api_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';

/// Repository for direct messages operations.
///
/// ## Session binding
///
/// Every authenticated operation below captures exactly one
/// [SessionRequestContext] via [_sessionCoordinator] at operation entry -
/// before any other `await` - and passes that SAME context to every
/// [ApiService] call it makes, so the request carries the JWT pinned at
/// capture time (never the live secure-storage token) and the
/// generation-scoped `CancelToken` that a logout aborts. A `null` capture
/// (logged out, or the session changed while the JWT read was in flight) is
/// treated exactly like the existing "no connection" convention: no HTTP,
/// return the established empty/no-op result (`sendMessage`, which has no
/// safe empty result, throws instead - matching its existing offline
/// behavior).
///
/// This repository has no local (Isar) state, no detached/background work,
/// no nested or recovery HTTP, and constructs no Dio/CancelToken/ApiService
/// of its own - a single bound `get`/`post` per method is the whole surface.
/// Pagination (`getMessages` with `beforeId`) is still a single bound call.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures: they are
/// rethrown unchanged (never logged as a generic failure, never converted
/// into a successful empty result, never routed through `onUnauthorized`),
/// so the calling [MessagesProvider] discards them through its own session
/// token ownership checks. Every other exception keeps this repository's
/// original behavior exactly.
class DirectMessagesRepository {
  final ApiService _apiService;
  final ConnectivityService _connectivity;

  /// The app-wide shared session-identity instance. Injected for wiring
  /// symmetry with every other session-bound repository (and so a future
  /// local-cache addition here has it to hand), but not read directly
  /// today: this repository holds no Isar state and does no post-`await`
  /// local write, so every staleness decision is made by [ApiService]
  /// against [SessionRequestContext.epochToken] - which [_sessionCoordinator]
  /// derives from this exact same epoch instance.
  // ignore: unused_field
  final UserSessionEpoch _sessionEpoch;

  final SessionRequestCoordinator _sessionCoordinator;

  DirectMessagesRepository(
    this._apiService,
    this._connectivity,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  bool get _isOnline => _connectivity.isOnline;

  /// Captures the session context for one operation, or `null` if there is
  /// no authenticated session to act for.
  Future<SessionRequestContext?> _capture() =>
      _sessionCoordinator.captureContext();

  /// Get all conversations for the current user
  Future<List<DMConversation>> getConversations() async {
    final context = await _capture();
    if (context == null) {
      debugPrint('⚠️ Messages: no active session - skipping getConversations');
      return [];
    }

    if (!_isOnline) {
      debugPrint('📴 Offline - messages feature requires online connection');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.dmConversations,
        sessionContext: context,
      );
      return data
          .map((json) => DMConversation.fromJson(json as Map<String, dynamic>))
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch conversations: $e');
      rethrow;
    }
  }

  /// Get messages in a conversation with a friend (paginated).
  ///
  /// [beforeId] drives pagination; it is still a single bound request that
  /// reuses the context captured at entry - there is no follow-up call.
  Future<List<DirectMessage>> getMessages(
    int friendId, {
    int? beforeId,
    int limit = 50,
  }) async {
    final context = await _capture();
    if (context == null) {
      debugPrint('⚠️ Messages: no active session - skipping getMessages');
      return [];
    }

    if (!_isOnline) return [];

    try {
      final queryParams = <String, String>{'limit': limit.toString()};
      if (beforeId != null) {
        queryParams['beforeId'] = beforeId.toString();
      }

      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.dmMessages(friendId),
        queryParameters: queryParams,
        sessionContext: context,
      );
      return data
          .map((json) => DirectMessage.fromJson(json as Map<String, dynamic>))
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch messages: $e');
      rethrow;
    }
  }

  /// Send a message to a friend
  Future<DirectMessage> sendMessage(int friendId, String content) async {
    final context = await _capture();
    if (context == null) {
      throw Exception('Cannot send message - no active session');
    }

    if (!_isOnline) {
      throw Exception('Cannot send message while offline');
    }

    try {
      final data = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.dmMessages(friendId),
        data: {'content': content},
        sessionContext: context,
      );
      return DirectMessage.fromJson(data);
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to send message: $e');
      rethrow;
    }
  }

  /// Mark messages from a friend as read
  Future<void> markAsRead(int friendId) async {
    final context = await _capture();
    if (context == null) return;

    if (!_isOnline) return;

    try {
      await _apiService.post<Map<String, dynamic>>(
        ApiConfig.dmMarkAsRead(friendId),
        sessionContext: context,
      );
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to mark messages as read: $e');
      // Don't rethrow - an ordinary mark-as-read failure is not critical.
    }
  }

  /// Get total unread message count across all conversations
  Future<int> getUnreadCount() async {
    final context = await _capture();
    if (context == null) return 0;

    if (!_isOnline) return 0;

    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.dmUnreadCount,
        sessionContext: context,
      );
      return data['unreadCount'] as int? ?? 0;
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to get unread count: $e');
      return 0;
    }
  }
}
