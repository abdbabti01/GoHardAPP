import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/friend.dart';
import '../models/friend_request.dart';
import '../models/friendship_status.dart';
import '../models/public_profile.dart';
import '../models/user_search_result.dart';
import '../services/api_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';

/// Repository for friends operations.
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
/// return the established empty/no-op result. The mutations that already
/// threw when offline ([sendFriendRequest], [acceptRequest], [declineRequest],
/// [removeFriend], [cancelFriendRequest], [getPublicProfile]) keep throwing
/// for a `null` capture, matching that existing offline behavior.
///
/// This repository has no local (Isar) state, no detached/background work,
/// no nested or recovery HTTP, and constructs no Dio/CancelToken/ApiService
/// of its own - a single bound `get`/`post`/`delete` per method is the whole
/// surface.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures: they are
/// rethrown unchanged (never logged as a generic failure, never converted
/// into a successful empty/`'none'` result, never routed through
/// `onUnauthorized`), so the calling [FriendsProvider] discards them through
/// its own session-token ownership checks. Every other exception keeps this
/// repository's original behavior exactly - including
/// [getFriendshipStatus]'s "any ordinary failure returns `status: 'none'`".
class FriendsRepository {
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

  FriendsRepository(
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

  /// Get all accepted friends
  Future<List<Friend>> getFriends() async {
    final context = await _capture();
    if (context == null) {
      debugPrint('⚠️ Friends: no active session - skipping getFriends');
      return [];
    }

    if (!_isOnline) {
      debugPrint('📴 Offline - friends feature requires online connection');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.friends,
        sessionContext: context,
      );
      return data
          .map((json) => Friend.fromJson(json as Map<String, dynamic>))
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch friends: $e');
      rethrow;
    }
  }

  /// Get incoming friend requests (pending)
  Future<List<FriendRequest>> getIncomingRequests() async {
    final context = await _capture();
    if (context == null) return [];

    if (!_isOnline) return [];

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.friendsRequestsIncoming,
        sessionContext: context,
      );
      return data
          .map((json) => FriendRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch incoming requests: $e');
      rethrow;
    }
  }

  /// Get outgoing friend requests (pending)
  Future<List<FriendRequest>> getOutgoingRequests() async {
    final context = await _capture();
    if (context == null) return [];

    if (!_isOnline) return [];

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.friendsRequestsOutgoing,
        sessionContext: context,
      );
      return data
          .map((json) => FriendRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch outgoing requests: $e');
      rethrow;
    }
  }

  /// Send a friend request to a user
  Future<void> sendFriendRequest(int userId) async {
    final context = await _capture();
    if (context == null) {
      throw Exception('Cannot send friend request - no active session');
    }

    if (!_isOnline) {
      throw Exception('Cannot send friend request while offline');
    }

    try {
      await _apiService.post<Map<String, dynamic>>(
        ApiConfig.sendFriendRequest(userId),
        sessionContext: context,
      );
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to send friend request: $e');
      rethrow;
    }
  }

  /// Accept a friend request
  Future<void> acceptRequest(int friendshipId) async {
    final context = await _capture();
    if (context == null) {
      throw Exception('Cannot accept friend request - no active session');
    }

    if (!_isOnline) {
      throw Exception('Cannot accept friend request while offline');
    }

    try {
      await _apiService.post<Map<String, dynamic>>(
        ApiConfig.acceptFriendRequest(friendshipId),
        sessionContext: context,
      );
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to accept friend request: $e');
      rethrow;
    }
  }

  /// Decline a friend request
  Future<void> declineRequest(int friendshipId) async {
    final context = await _capture();
    if (context == null) {
      throw Exception('Cannot decline friend request - no active session');
    }

    if (!_isOnline) {
      throw Exception('Cannot decline friend request while offline');
    }

    try {
      await _apiService.post<Map<String, dynamic>>(
        ApiConfig.declineFriendRequest(friendshipId),
        sessionContext: context,
      );
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to decline friend request: $e');
      rethrow;
    }
  }

  /// Remove a friend
  Future<void> removeFriend(int friendId) async {
    final context = await _capture();
    if (context == null) {
      throw Exception('Cannot remove friend - no active session');
    }

    if (!_isOnline) {
      throw Exception('Cannot remove friend while offline');
    }

    try {
      await _apiService.delete(
        ApiConfig.removeFriend(friendId),
        sessionContext: context,
      );
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to remove friend: $e');
      rethrow;
    }
  }

  /// Cancel an outgoing friend request
  Future<void> cancelFriendRequest(int friendshipId) async {
    final context = await _capture();
    if (context == null) {
      throw Exception('Cannot cancel friend request - no active session');
    }

    if (!_isOnline) {
      throw Exception('Cannot cancel friend request while offline');
    }

    try {
      await _apiService.delete(
        ApiConfig.cancelFriendRequest(friendshipId),
        sessionContext: context,
      );
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to cancel friend request: $e');
      rethrow;
    }
  }

  /// Get friendship status with a user.
  ///
  /// An ordinary failure (network, 5xx, malformed body) still resolves to
  /// `status: 'none'` exactly as before. Only the two session-lifecycle
  /// exceptions are rethrown - converting "the session ended mid-request"
  /// into a successful `'none'` would let a stale continuation publish a
  /// bogus "not friends" state into the next user's provider.
  Future<FriendshipStatus> getFriendshipStatus(int targetUserId) async {
    final context = await _capture();
    if (context == null) {
      return FriendshipStatus(status: 'none');
    }

    if (!_isOnline) {
      return FriendshipStatus(status: 'none');
    }

    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.friendshipStatus(targetUserId),
        sessionContext: context,
      );
      return FriendshipStatus.fromJson(data);
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to get friendship status: $e');
      return FriendshipStatus(status: 'none');
    }
  }

  /// Search users by username
  Future<List<UserSearchResult>> searchUsers(String query) async {
    final context = await _capture();
    if (context == null) return [];

    if (query.length < 2) return [];
    if (!_isOnline) return [];

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.searchUsers(query),
        sessionContext: context,
      );
      return data
          .map(
            (json) => UserSearchResult.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to search users: $e');
      rethrow;
    }
  }

  /// Get public profile of a user
  Future<PublicProfile> getPublicProfile(int userId) async {
    final context = await _capture();
    if (context == null) {
      throw Exception('Cannot fetch profile - no active session');
    }

    if (!_isOnline) {
      throw Exception('Cannot fetch profile while offline');
    }

    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.publicProfile(userId),
        sessionContext: context,
      );
      return PublicProfile.fromJson(data);
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to get public profile: $e');
      rethrow;
    }
  }
}
