import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/services/user_session_epoch.dart';
import '../data/models/friend.dart';
import '../data/models/friend_request.dart';
import '../data/models/friendship_status.dart';
import '../data/models/public_profile.dart';
import '../data/models/user_search_result.dart';
import '../data/repositories/friends_repository.dart';

/// Provider for managing friends and friend requests.
///
/// ## Session ownership
///
/// This is an app-scoped provider: a single instance outlives logout/login,
/// so a continuation started under user A must never publish into the state
/// user B now sees. Every async method captures `_sessionEpoch.capture()`
/// before its first `await` and rechecks `_sessionEpoch.isCurrent(token)`
/// after every `await`, in success, `catch`, and `finally`, before touching
/// any list, flag, error, timer, or calling `notifyListeners()`. A `null`
/// capture (logged out) follows each method's existing no-op convention.
///
/// ## Same-session ordering
///
/// Session identity alone cannot order two requests within one session, so
/// each independently-refreshable resource carries a monotonically
/// increasing generation:
///
/// - [_friendsGen] - the friends list. Bumped by [loadFriends] AND by
///   [removeFriend]/[acceptRequest]'s refreshes so a slower in-flight list
///   load can never resurrect a friend a newer mutation removed.
/// - [_incomingGen] - incoming requests. Bumped by [loadIncomingRequests]
///   AND by [declineRequest]/[acceptRequest] when they edit the list.
/// - [_outgoingGen] - outgoing requests. Bumped by [loadOutgoingRequests]
///   AND by [sendFriendRequest]/[cancelFriendRequest].
/// - [_searchGen] - user search results. Bumped by [searchUsers],
///   [clearSearch] and [sendFriendRequest] (which prunes the sent-to user).
///   Resolves an A->B->A query race by generation identity, not by query
///   string equality.
/// - [_loadAllGen] - the aggregate [loadAll]. Owns only [loadAll]'s own
///   `_isLoading` bookkeeping; each of its three child loads still commits
///   its own resource under that resource's own generation, so an older
///   `loadAll` completing last can neither flip the spinner back on nor
///   commit a stale partial result.
/// - [_profileGen] - the selected public profile + friendship status.
///
/// Each mutation additionally carries a per-target generation
/// ([_sendGens]/[_acceptGens]/[_declineGens]/[_cancelGens]/[_removeGens],
/// keyed by the userId or friendshipId fixed before the first `await`): a
/// superseded mutation to a target writes nothing - not its list edit, not
/// its error, not a spinner reset - while a mutation to a different target
/// is never superseded by it.
///
/// [clear] and [dispose] bump every generation (resource, per-target
/// mutation, and polling) BEFORE resetting state, so an in-flight
/// continuation or a mid-execution timer callback can neither repopulate
/// cleared state nor re-arm a timer - even when [clear] is called without a
/// preceding `UserSessionEpoch.invalidate()`.
///
/// ## Polling ownership
///
/// [startRequestPolling] captures the session token AND [_pollingGen] as
/// they are at scheduling time. Every tick runs only while its generation
/// is still current (bumped by every re-schedule, [stopRequestPolling],
/// [clear] and [dispose]) AND the captured token is still the current
/// session; otherwise it cancels its OWN `Timer` instance - never the timer
/// field - so a stale tick can never cancel a replacement timer a newer
/// session installed. Logged-out scheduling installs no timer.
/// [_pollIncomingRequests] refuses to overlap itself.
class FriendsProvider extends ChangeNotifier {
  final FriendsRepository _repository;
  final UserSessionEpoch _sessionEpoch;

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

  // Monotonic per-resource generations - see the class doc comment.
  int _friendsGen = 0;
  int _incomingGen = 0;
  int _outgoingGen = 0;
  int _searchGen = 0;
  int _loadAllGen = 0;
  int _profileGen = 0;

  // Per-target mutation generations. A superseded (stale) mutation to a
  // target never writes state; a mutation to a different target never
  // supersedes it.
  final Map<int, int> _sendGens = {}; // keyed by userId
  final Map<int, int> _acceptGens = {}; // keyed by friendshipId
  final Map<int, int> _declineGens = {}; // keyed by friendshipId
  final Map<int, int> _cancelGens = {}; // keyed by friendshipId
  final Map<int, int> _removeGens = {}; // keyed by friendId

  // Polling ownership - see the class doc comment.
  int _pollingGen = 0;
  bool _pollInFlight = false;

  /// Test-only view of the poll re-entrancy flag, used to prove the poll
  /// does not overlap itself.
  @visibleForTesting
  bool get pollInFlightForTesting => _pollInFlight;

  FriendsProvider(this._repository, this._sessionEpoch);

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
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_friendsGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _friendsGen;

    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final friends = await _repository.getFriends();
      if (!owns()) return;
      _friends = friends;
      _errorMessage = null;
      if (!showLoading) notifyListeners();
    } catch (e) {
      if (!owns()) return;
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.loadFriends error: $e');
      if (!showLoading) notifyListeners();
    } finally {
      // Only this method's own spinner is cleared here. When called with
      // showLoading:false (from loadAll / acceptRequest) the caller owns
      // _isLoading, so a background refresh must not clear a concurrent
      // user-initiated load's spinner.
      if (showLoading && owns()) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Load incoming friend requests
  Future<void> loadIncomingRequests() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_incomingGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _incomingGen;

    try {
      final requests = await _repository.getIncomingRequests();
      if (!owns()) return;
      _incomingRequests = requests;
    } catch (e) {
      if (!owns()) return;
      debugPrint('⚠️ FriendsProvider.loadIncomingRequests error: $e');
    } finally {
      if (owns()) notifyListeners();
    }
  }

  /// Load outgoing friend requests
  Future<void> loadOutgoingRequests() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_outgoingGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _outgoingGen;

    try {
      final requests = await _repository.getOutgoingRequests();
      if (!owns()) return;
      _outgoingRequests = requests;
    } catch (e) {
      if (!owns()) return;
      debugPrint('⚠️ FriendsProvider.loadOutgoingRequests error: $e');
    } finally {
      if (owns()) notifyListeners();
    }
  }

  /// Load all data (friends and requests)
  Future<void> loadAll() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_loadAllGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _loadAllGen;

    _isLoading = true;
    notifyListeners();

    try {
      await Future.wait([
        loadFriends(showLoading: false),
        loadIncomingRequests(),
        loadOutgoingRequests(),
      ]);
    } finally {
      if (owns()) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Search users by username
  Future<void> searchUsers(String query) async {
    if (query.length < 2) {
      // Clearing to empty can never leak another session's data; still bump
      // the generation so an in-flight longer-query search cannot land its
      // results after the user has emptied the field.
      _searchGen++;
      _searchResults = [];
      notifyListeners();
      return;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_searchGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _searchGen;

    _isSearching = true;
    notifyListeners();

    try {
      final results = await _repository.searchUsers(query);
      if (!owns()) return;
      _searchResults = results;
    } catch (e) {
      if (!owns()) return;
      _searchResults = [];
      debugPrint('⚠️ FriendsProvider.searchUsers error: $e');
    } finally {
      if (owns()) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  /// Clear search results
  void clearSearch() {
    _searchGen++;
    _searchResults = [];
    notifyListeners();
  }

  /// Send friend request
  Future<bool> sendFriendRequest(int userId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final myGen = (_sendGens[userId] ?? 0) + 1;
    _sendGens[userId] = myGen;

    bool owns() => _sessionEpoch.isCurrent(token) && _sendGens[userId] == myGen;

    try {
      await _repository.sendFriendRequest(userId);
      if (!owns()) return false;

      await loadOutgoingRequests();
      if (!owns()) return false;

      // Prune the sent-to user from the search results, and supersede any
      // in-flight search load so it cannot re-add them.
      _searchGen++;
      _searchResults = _searchResults.where((u) => u.userId != userId).toList();
      notifyListeners();
      return true;
    } catch (e) {
      if (!owns()) return false;
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.sendFriendRequest error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Accept friend request
  Future<bool> acceptRequest(int friendshipId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final myGen = (_acceptGens[friendshipId] ?? 0) + 1;
    _acceptGens[friendshipId] = myGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _acceptGens[friendshipId] == myGen;

    try {
      await _repository.acceptRequest(friendshipId);
      if (!owns()) return false;

      await Future.wait([
        loadFriends(showLoading: false),
        loadIncomingRequests(),
      ]);
      return true;
    } catch (e) {
      if (!owns()) return false;
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.acceptRequest error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Decline friend request
  Future<bool> declineRequest(int friendshipId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final myGen = (_declineGens[friendshipId] ?? 0) + 1;
    _declineGens[friendshipId] = myGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _declineGens[friendshipId] == myGen;

    try {
      await _repository.declineRequest(friendshipId);
      if (!owns()) return false;

      // Supersede any in-flight incoming-requests load so a slower response
      // captured before the decline cannot resurrect this request.
      _incomingGen++;
      _incomingRequests =
          _incomingRequests
              .where((r) => r.friendshipId != friendshipId)
              .toList();
      notifyListeners();
      return true;
    } catch (e) {
      if (!owns()) return false;
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.declineRequest error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Cancel outgoing friend request
  Future<bool> cancelFriendRequest(int friendshipId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final myGen = (_cancelGens[friendshipId] ?? 0) + 1;
    _cancelGens[friendshipId] = myGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _cancelGens[friendshipId] == myGen;

    try {
      await _repository.cancelFriendRequest(friendshipId);
      if (!owns()) return false;

      _outgoingGen++;
      _outgoingRequests =
          _outgoingRequests
              .where((r) => r.friendshipId != friendshipId)
              .toList();
      notifyListeners();
      return true;
    } catch (e) {
      if (!owns()) return false;
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.cancelFriendRequest error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Remove friend
  Future<bool> removeFriend(int friendId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final myGen = (_removeGens[friendId] ?? 0) + 1;
    _removeGens[friendId] = myGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _removeGens[friendId] == myGen;

    try {
      await _repository.removeFriend(friendId);
      if (!owns()) return false;

      _friendsGen++;
      _friends = _friends.where((f) => f.userId != friendId).toList();
      notifyListeners();
      return true;
    } catch (e) {
      if (!owns()) return false;
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.removeFriend error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Load public profile of a user
  Future<void> loadPublicProfile(int userId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_profileGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _profileGen;

    _isLoadingProfile = true;
    _selectedProfile = null;
    _selectedProfileStatus = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.getPublicProfile(userId),
        _repository.getFriendshipStatus(userId),
      ]);
      if (!owns()) return;
      _selectedProfile = results[0] as PublicProfile;
      _selectedProfileStatus = results[1] as FriendshipStatus;
    } catch (e) {
      if (!owns()) return;
      _errorMessage = e.toString();
      debugPrint('⚠️ FriendsProvider.loadPublicProfile error: $e');
    } finally {
      if (owns()) {
        _isLoadingProfile = false;
        notifyListeners();
      }
    }
  }

  /// Clear selected profile
  void clearSelectedProfile() {
    _profileGen++;
    _selectedProfile = null;
    _selectedProfileStatus = null;
    notifyListeners();
  }

  /// Start polling for friend requests (for background updates).
  ///
  /// The token AND generation captured here own the timer; a tick whose
  /// generation has been superseded (a re-schedule, stop, clear, or
  /// dispose) or whose session has ended cancels only its own `Timer`
  /// instance. Scheduling while logged out installs no timer.
  void startRequestPolling() {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    // Supersede any previous timer by generation; a previous timer instance
    // is NOT hard-cancelled here - it self-cancels on its next tick when it
    // sees the newer generation - so it can never be this method's job to
    // cancel a timer another session might own.
    final gen = ++_pollingGen;

    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (gen != _pollingGen || !_sessionEpoch.isCurrent(token)) {
        timer.cancel();
        return;
      }
      _pollIncomingRequests(token, gen);
    });
  }

  /// One polling round. Bound to the [token] and [gen] captured when the
  /// owning timer was scheduled; refuses to overlap a still-in-flight round.
  Future<void> _pollIncomingRequests(UserSessionToken token, int gen) async {
    if (_pollInFlight) return;
    if (gen != _pollingGen || !_sessionEpoch.isCurrent(token)) return;
    _pollInFlight = true;
    try {
      // loadIncomingRequests captures its own token/generation, so a poll
      // that goes stale mid-flight still cannot commit into a new session.
      await loadIncomingRequests();
    } finally {
      _pollInFlight = false;
    }
  }

  /// Stop polling. Authoritative, unconditional teardown - bumps the polling
  /// generation so any timer tick or in-flight round from the superseded
  /// generation becomes a no-op.
  ///
  /// [_pollInFlight] is also cleared: a superseded in-flight round's own
  /// generation check already makes it a harmless no-op (it only calls the
  /// self-guarding [loadIncomingRequests]), so there is nothing to protect
  /// by leaving the re-entrancy latch set - and clearing it means a hung
  /// round can never silently disable a later session's polling.
  void stopRequestPolling() {
    _pollingGen++;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _pollInFlight = false;
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Invalidate every generation so no in-flight continuation, mutation, or
  /// timer callback can publish after this returns.
  void _invalidateGenerations() {
    _friendsGen++;
    _incomingGen++;
    _outgoingGen++;
    _searchGen++;
    _loadAllGen++;
    _profileGen++;
    _sendGens.updateAll((_, value) => value + 1);
    _acceptGens.updateAll((_, value) => value + 1);
    _declineGens.updateAll((_, value) => value + 1);
    _cancelGens.updateAll((_, value) => value + 1);
    _removeGens.updateAll((_, value) => value + 1);
  }

  /// Clear all friends/requests state and stop request polling
  /// (called on logout via [SessionCleanupCoordinator]).
  ///
  /// Every generation is bumped BEFORE any state is reset, so a load,
  /// mutation, or poll continuation that resolves after this returns - or a
  /// timer callback mid-execution - fails its ownership check and can
  /// neither repopulate the cleared state nor re-arm a timer. In the live
  /// logout path `UserSessionEpoch.invalidate()` has already run, so
  /// `isCurrent(token)` is also false; the generation bumps make this
  /// correct even when `clear()` is called on its own.
  void clear() {
    _invalidateGenerations();
    stopRequestPolling();

    _friends = [];
    _incomingRequests = [];
    _outgoingRequests = [];
    _searchResults = [];
    _selectedProfile = null;
    _selectedProfileStatus = null;
    _isLoading = false;
    _isSearching = false;
    _isLoadingProfile = false;
    _errorMessage = null;
    notifyListeners();
    debugPrint('🧹 FriendsProvider cleared');
  }

  @override
  void dispose() {
    _invalidateGenerations();
    stopRequestPolling();
    super.dispose();
  }
}
