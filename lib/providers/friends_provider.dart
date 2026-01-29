import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/friend.dart';
import '../data/models/friend_request.dart';
import '../data/models/friendship_status.dart';
import '../data/models/public_profile.dart';
import '../data/models/user_search_result.dart';
import '../data/repositories/friends_repository.dart';

/// Provider for managing friends and friend requests
class FriendsProvider extends ChangeNotifier {
  final FriendsRepository _repository;

  List<Friend> _friends = [];
  List<FriendRequest> _incomingRequests = [];
  List<FriendRequest> _outgoingRequests = [];
  List<UserSearchResult> _searchResults = [];
  PublicProfile? _selectedProfile;
  FriendshipStatus? _selectedProfileStatus;

  bool _isLoading = false;
  bool _isSearching = false;
  bool _isLoadingProfile = false;
  String? _errorMessage;

  Timer? _pollingTimer;

  FriendsProvider(this._repository);

  // Getters
  List<Friend> get friends => _friends;
  List<FriendRequest> get incomingRequests => _incomingRequests;
  List<FriendRequest> get outgoingRequests => _outgoingRequests;
  List<UserSearchResult> get searchResults => _searchResults;
  PublicProfile? get selectedProfile => _selectedProfile;
  FriendshipStatus? get selectedProfileStatus => _selectedProfileStatus;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get isLoadingProfile => _isLoadingProfile;
  String? get errorMessage => _errorMessage;

  int get pendingRequestCount => _incomingRequests.length;

  /// Load friends list
  Future<void> loadFriends({bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _friends = await _repository.getFriends();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.loadFriends error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load incoming friend requests
  Future<void> loadIncomingRequests() async {
    try {
      _incomingRequests = await _repository.getIncomingRequests();
    } catch (e) {
      debugPrint('⚠️ FriendsProvider.loadIncomingRequests error: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Load outgoing friend requests
  Future<void> loadOutgoingRequests() async {
    try {
      _outgoingRequests = await _repository.getOutgoingRequests();
    } catch (e) {
      debugPrint('⚠️ FriendsProvider.loadOutgoingRequests error: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Load all data (friends and requests)
  Future<void> loadAll() async {
    _isLoading = true;
    notifyListeners();

    try {
      await Future.wait([
        loadFriends(showLoading: false),
        loadIncomingRequests(),
        loadOutgoingRequests(),
      ]);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search users by username
  Future<void> searchUsers(String query) async {
    if (query.length < 2) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    try {
      _searchResults = await _repository.searchUsers(query);
    } catch (e) {
      _searchResults = [];
      debugPrint('⚠️ FriendsProvider.searchUsers error: $e');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Clear search results
  void clearSearch() {
    _searchResults = [];
    notifyListeners();
  }

  /// Send friend request
  Future<bool> sendFriendRequest(int userId) async {
    try {
      await _repository.sendFriendRequest(userId);
      await loadOutgoingRequests();
      // Update search results to show pending status
      _searchResults = _searchResults.where((u) => u.userId != userId).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.sendFriendRequest error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Accept friend request
  Future<bool> acceptRequest(int friendshipId) async {
    try {
      await _repository.acceptRequest(friendshipId);
      await Future.wait([
        loadFriends(showLoading: false),
        loadIncomingRequests(),
      ]);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.acceptRequest error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Decline friend request
  Future<bool> declineRequest(int friendshipId) async {
    try {
      await _repository.declineRequest(friendshipId);
      _incomingRequests =
          _incomingRequests
              .where((r) => r.friendshipId != friendshipId)
              .toList();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.declineRequest error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Cancel outgoing friend request
  Future<bool> cancelFriendRequest(int friendshipId) async {
    try {
      await _repository.cancelFriendRequest(friendshipId);
      _outgoingRequests =
          _outgoingRequests
              .where((r) => r.friendshipId != friendshipId)
              .toList();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.cancelFriendRequest error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Remove friend
  Future<bool> removeFriend(int friendId) async {
    try {
      await _repository.removeFriend(friendId);
      _friends = _friends.where((f) => f.userId != friendId).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.removeFriend error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Load public profile of a user
  Future<void> loadPublicProfile(int userId) async {
    _isLoadingProfile = true;
    _selectedProfile = null;
    _selectedProfileStatus = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.getPublicProfile(userId),
        _repository.getFriendshipStatus(userId),
      ]);
      _selectedProfile = results[0] as PublicProfile;
      _selectedProfileStatus = results[1] as FriendshipStatus;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.loadPublicProfile error: $e');
    } finally {
      _isLoadingProfile = false;
      notifyListeners();
    }
  }

  /// Clear selected profile
  void clearSelectedProfile() {
    _selectedProfile = null;
    _selectedProfileStatus = null;
    notifyListeners();
  }

  /// Start polling for friend requests (for background updates)
  void startRequestPolling() {
    stopRequestPolling();
    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      loadIncomingRequests();
    });
  }

  /// Stop polling
  void stopRequestPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopRequestPolling();
    super.dispose();
  }
}
