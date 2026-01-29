import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../models/friend.dart';
import '../models/friend_request.dart';
import '../models/friendship_status.dart';
import '../models/public_profile.dart';
import '../models/user_search_result.dart';
import '../services/api_service.dart';

/// Repository for friends operations
class FriendsRepository {
  final ApiService _apiService;
  final ConnectivityService? _connectivity;

  FriendsRepository(this._apiService, [this._connectivity]);

  bool get _isOnline => _connectivity?.isOnline ?? true;

  /// Get all accepted friends
  Future<List<Friend>> getFriends() async {
    if (!_isOnline) {
      debugPrint('📴 Offline - friends feature requires online connection');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(ApiConfig.friends);
      return data
          .map((json) => Friend.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to fetch friends: $e');
      rethrow;
    }
  }

  /// Get incoming friend requests (pending)
  Future<List<FriendRequest>> getIncomingRequests() async {
    if (!_isOnline) return [];

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.friendsRequestsIncoming,
      );
      return data
          .map((json) => FriendRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to fetch incoming requests: $e');
      rethrow;
    }
  }

  /// Get outgoing friend requests (pending)
  Future<List<FriendRequest>> getOutgoingRequests() async {
    if (!_isOnline) return [];

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.friendsRequestsOutgoing,
      );
      return data
          .map((json) => FriendRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to fetch outgoing requests: $e');
      rethrow;
    }
  }

  /// Send a friend request to a user
  Future<void> sendFriendRequest(int userId) async {
    if (!_isOnline) {
      throw Exception('Cannot send friend request while offline');
    }

    try {
      await _apiService.post<Map<String, dynamic>>(
        ApiConfig.sendFriendRequest(userId),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to send friend request: $e');
      rethrow;
    }
  }

  /// Accept a friend request
  Future<void> acceptRequest(int friendshipId) async {
    if (!_isOnline) {
      throw Exception('Cannot accept friend request while offline');
    }

    try {
      await _apiService.post<Map<String, dynamic>>(
        ApiConfig.acceptFriendRequest(friendshipId),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to accept friend request: $e');
      rethrow;
    }
  }

  /// Decline a friend request
  Future<void> declineRequest(int friendshipId) async {
    if (!_isOnline) {
      throw Exception('Cannot decline friend request while offline');
    }

    try {
      await _apiService.post<Map<String, dynamic>>(
        ApiConfig.declineFriendRequest(friendshipId),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to decline friend request: $e');
      rethrow;
    }
  }

  /// Remove a friend
  Future<void> removeFriend(int friendId) async {
    if (!_isOnline) {
      throw Exception('Cannot remove friend while offline');
    }

    try {
      await _apiService.delete(ApiConfig.removeFriend(friendId));
    } catch (e) {
      debugPrint('⚠️ Failed to remove friend: $e');
      rethrow;
    }
  }

  /// Cancel an outgoing friend request
  Future<void> cancelFriendRequest(int friendshipId) async {
    if (!_isOnline) {
      throw Exception('Cannot cancel friend request while offline');
    }

    try {
      await _apiService.delete(ApiConfig.cancelFriendRequest(friendshipId));
    } catch (e) {
      debugPrint('⚠️ Failed to cancel friend request: $e');
      rethrow;
    }
  }

  /// Get friendship status with a user
  Future<FriendshipStatus> getFriendshipStatus(int targetUserId) async {
    if (!_isOnline) {
      return FriendshipStatus(status: 'none');
    }

    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.friendshipStatus(targetUserId),
      );
      return FriendshipStatus.fromJson(data);
    } catch (e) {
      debugPrint('⚠️ Failed to get friendship status: $e');
      return FriendshipStatus(status: 'none');
    }
  }

  /// Search users by username
  Future<List<UserSearchResult>> searchUsers(String query) async {
    if (!_isOnline) return [];
    if (query.length < 2) return [];

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.searchUsers(query),
      );
      return data
          .map(
            (json) => UserSearchResult.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      debugPrint('⚠️ Failed to search users: $e');
      rethrow;
    }
  }

  /// Get public profile of a user
  Future<PublicProfile> getPublicProfile(int userId) async {
    if (!_isOnline) {
      throw Exception('Cannot fetch profile while offline');
    }

    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.publicProfile(userId),
      );
      return PublicProfile.fromJson(data);
    } catch (e) {
      debugPrint('⚠️ Failed to get public profile: $e');
      rethrow;
    }
  }
}
