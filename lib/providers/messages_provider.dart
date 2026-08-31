import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/services/user_session_epoch.dart';
import '../data/models/direct_message.dart';
import '../data/models/dm_conversation.dart';
import '../data/repositories/direct_messages_repository.dart';

/// Provider for managing direct messages.
///
/// ## Session ownership
///
/// This is an app-scoped provider: a single instance outlives logout/login,
/// so a continuation started under user A must never publish into the state
/// user B now sees. Every async method captures `_sessionEpoch.capture()`
/// before its first `await` and rechecks `_sessionEpoch.isCurrent(token)`
/// after every `await`, in success, `catch`, and `finally`, before touching
/// any field, flag, timer, or calling `notifyListeners()`. A `null` capture
/// (logged out) follows each method's existing no-op convention.
///
/// ## Same-session ordering
///
/// Session identity alone cannot order two requests within one session, so
/// each operation family carries a monotonically increasing generation:
///
/// - [_conversationsRequestGen] - a slower conversation-list load cannot
///   overwrite a newer one.
/// - [_messageLoadGen] - shared by [loadMessages] and [loadMoreMessages];
///   an older thread load or pagination page cannot overwrite a newer
///   refresh, and thread A completing after thread B loses. Each write still
///   lands in `_messagesByFriend[thatFriendId]`, so it can never bleed into
///   another friend's bucket.
/// - [_unreadRequestGen] - an older unread poll cannot overwrite a newer
///   manual unread refresh.
/// - [_sendGens] - keyed per friend: every state write a send makes
///   (message append, conversation-list reorder, error, `_isSending` reset)
///   is dropped once a newer send to THAT SAME thread has started; a send to
///   friend A is never superseded by a send to friend B.
///
/// [clear] and [dispose] bump every request generation and both polling
/// generations BEFORE resetting state, so an in-flight continuation or a
/// mid-execution timer callback can neither repopulate cleared state nor
/// re-arm a timer.
///
/// ## Polling ownership
///
/// Each polling timer closes over the session token AND the polling
/// generation as they were when it was scheduled. Every tick runs only
/// while its generation is still current ([_conversationPollingGen] /
/// [_unreadPollingGen], bumped by every re-schedule, stop, clear, and
/// dispose) AND the captured token is still the current session; otherwise
/// it cancels its OWN `Timer` instance - never the timer field - so a stale
/// tick can never cancel a replacement timer a newer session installed.
/// Logged-out scheduling installs no timer. [_pollForNewMessages]
/// re-checks its generation and session after its `await` before writing
/// anything, refuses to overlap itself, and awaits (never fire-and-forgets)
/// its `markAsRead`.
class MessagesProvider extends ChangeNotifier {
  final DirectMessagesRepository _repository;
  final UserSessionEpoch _sessionEpoch;

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

  // Timer-ownership generations. Each `startXPolling` bumps its generation
  // and each tick closes over the value current when it was scheduled; a
  // tick whose generation has been superseded (a newer schedule, a stop, a
  // clear, a dispose) cancels its OWN Timer instance and does nothing else -
  // it never touches the timer field, so a stale tick can never cancel a
  // replacement timer a newer session installed.
  int _conversationPollingGen = 0;
  int _unreadPollingGen = 0;

  // Guards _pollForNewMessages against running while its previous HTTP
  // round-trip is still in flight (the 2s interval can be shorter than the
  // request).
  bool _conversationPollInFlight = false;

  /// Test-only view of the poll re-entrancy flag, used to prove the poll
  /// awaits its `markAsRead` rather than firing it and forgetting.
  @visibleForTesting
  bool get conversationPollInFlightForTesting => _conversationPollInFlight;

  // Monotonic per-operation generations - see the class doc comment.
  int _conversationsRequestGen = 0;
  int _messageLoadGen = 0;
  int _unreadRequestGen = 0;

  // Per-friend send generations: a stale (superseded) send to a friend
  // never writes state, but a send to friend A is NEVER superseded by a
  // send to friend B - the two threads are independent.
  final Map<int, int> _sendGens = {};

  MessagesProvider(this._repository, this._sessionEpoch) {
    // Load initial unread count and start polling
    _initialize();
  }

  Future<void> _initialize() async {
    // Nothing to initialize for a session that does not exist yet; both
    // calls below also self-guard, this just avoids starting at all.
    if (_sessionEpoch.capture() == null) return;
    await loadUnreadCount();
    startUnreadCountPolling();
  }

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
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_conversationsRequestGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && gen == _conversationsRequestGen;

    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final conversations = await _repository.getConversations();
      if (!owns()) return;
      _conversations = conversations;
      _errorMessage = null;
    } catch (e) {
      if (!owns()) return;
      _errorMessage = e.toString();
      debugPrint('⚠️ MessagesProvider.loadConversations error: $e');
    } finally {
      if (owns()) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Load messages for a conversation
  Future<void> loadMessages(int friendId, {bool showLoading = true}) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_messageLoadGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _messageLoadGen;

    if (showLoading) {
      _isLoadingMessages = true;
      notifyListeners();
    }

    try {
      final messages = await _repository.getMessages(friendId);
      if (!owns()) return;
      _messagesByFriend[friendId] = messages;
      _errorMessage = null;
    } catch (e) {
      if (!owns()) return;
      _errorMessage = e.toString();
      debugPrint('⚠️ MessagesProvider.loadMessages error: $e');
    } finally {
      if (owns()) {
        _isLoadingMessages = false;
        notifyListeners();
      }
    }
  }

  /// Load more messages (pagination)
  Future<void> loadMoreMessages(int friendId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    final currentMessages = _messagesByFriend[friendId] ?? [];
    if (currentMessages.isEmpty) return;

    final oldestId = currentMessages.first.id;
    final gen = ++_messageLoadGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _messageLoadGen;

    try {
      final olderMessages = await _repository.getMessages(
        friendId,
        beforeId: oldestId,
      );
      if (!owns()) return;

      if (olderMessages.isNotEmpty) {
        // Re-read the current list: a concurrent (newer) refresh would have
        // bumped the generation and failed owns() above, so if we are here
        // the list for this friend has not been replaced under us - but
        // read it fresh anyway rather than trusting the pre-await snapshot.
        final latest = _messagesByFriend[friendId] ?? const [];
        _messagesByFriend[friendId] = [...olderMessages, ...latest];
        notifyListeners();
      }
    } catch (e) {
      if (!owns()) return;
      debugPrint('⚠️ MessagesProvider.loadMoreMessages error: $e');
    }
  }

  /// Send a message.
  ///
  /// The target [friendId] is fixed by the argument, so nothing this method
  /// writes can ever land on a different thread. Beyond the session token,
  /// every state write is also gated on this friend's [_sendGens] entry
  /// being current: a stale (superseded) send to THIS friend - its message
  /// append, conversation-list reorder, error, or `_isSending` reset - is
  /// dropped, exactly like a superseded load's result; a send to a
  /// different friend never supersedes it. The genuinely-sent message is
  /// not lost:
  /// the conversation screen's 2s poll (or the next [loadMessages]) picks it
  /// up. `_isSending` is a single global flag (the send button reads
  /// `isSending` with no argument), and the send button is disabled while it
  /// is set, so at most one send is ever in flight - this generation gate is
  /// belt-and-braces for the rare case where that UI guard is bypassed.
  Future<bool> sendMessage(int friendId, String content) async {
    if (content.trim().isEmpty) return false;

    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final sendGen = (_sendGens[friendId] ?? 0) + 1;
    _sendGens[friendId] = sendGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _sendGens[friendId] == sendGen;

    _isSending = true;
    notifyListeners();

    try {
      final message = await _repository.sendMessage(friendId, content);
      if (!owns()) return false;

      // Add to this friend's messages (by argument, never the active thread)
      final currentMessages = _messagesByFriend[friendId] ?? [];
      _messagesByFriend[friendId] = [...currentMessages, message];

      // Update conversation's last message
      _updateConversationLastMessage(friendId, message);

      if (_activeConversationFriendId == friendId) {
        _errorMessage = null;
      }
      notifyListeners();
      return true;
    } catch (e) {
      if (!owns()) return false;
      if (_activeConversationFriendId == friendId) {
        _errorMessage = e.toString();
      }
      debugPrint('⚠️ MessagesProvider.sendMessage error: $e');
      notifyListeners();
      return false;
    } finally {
      // Only clear the flag if still current and no newer send has started.
      if (owns()) {
        _isSending = false;
        notifyListeners();
      }
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
    final token = _sessionEpoch.capture();
    if (token == null) return;

    try {
      await _repository.markAsRead(friendId);
      if (!_sessionEpoch.isCurrent(token)) return;

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
      if (_sessionEpoch.isCurrent(token)) {
        debugPrint('⚠️ MessagesProvider.markAsRead error: $e');
      }
    }
  }

  /// Load total unread count
  Future<void> loadUnreadCount() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_unreadRequestGen;

    try {
      final count = await _repository.getUnreadCount();
      if (!_sessionEpoch.isCurrent(token) || gen != _unreadRequestGen) return;
      _totalUnreadCount = count;
      notifyListeners();
    } catch (e) {
      if (_sessionEpoch.isCurrent(token)) {
        debugPrint('⚠️ MessagesProvider.loadUnreadCount error: $e');
      }
    }
  }

  /// Start polling for the active conversation (every 2 seconds).
  ///
  /// The token AND generation captured here own the timer; a tick whose
  /// generation has been superseded (a re-schedule, stop, clear, or
  /// dispose) or whose session has ended cancels only its own `Timer`
  /// instance. Scheduling while logged out installs no timer.
  void startConversationPolling(int friendId) {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    // Supersede any previous conversation timer by generation. A previous
    // timer instance is NOT hard-cancelled here - it self-cancels on its
    // next tick when it sees the newer generation - so it can never be
    // this method's job to cancel a timer another session might own.
    // `_conversationPollInFlight` is deliberately NOT touched here: it is
    // owned solely by [_pollForNewMessages]'s try/finally, so a poll from
    // the superseded generation still in flight keeps blocking a new one
    // from starting until it settles (its own generation check then makes
    // it a no-op).
    final gen = ++_conversationPollingGen;
    _activeConversationFriendId = friendId;

    // Poll immediately first, bound to the token/gen captured just above.
    _pollForNewMessages(friendId, token, gen);

    // Then poll every 2 seconds for real-time feel. Each tick is bound to
    // [gen] and [token], both captured at scheduling time and never
    // re-derived here.
    _conversationPollingTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) {
      if (gen != _conversationPollingGen || !_sessionEpoch.isCurrent(token)) {
        timer.cancel();
        return;
      }
      _pollForNewMessages(friendId, token, gen);
    });
  }

  /// Poll for new messages for [friendId], bound to the [token] and polling
  /// [gen] captured when this poll's owning timer was scheduled (or, for the
  /// immediate first poll, in [startConversationPolling]). The polling
  /// generation IS the "still viewing this thread" identity: every
  /// [startConversationPolling] / [stopConversationPolling] (including the
  /// one the conversation screen's `dispose` triggers) bumps it, so a stale
  /// [gen] means the user has left, switched threads, or logged out. Every
  /// state mutation below is re-gated - after the `await` - on that exact
  /// generation still being current AND the session still being current.
  Future<void> _pollForNewMessages(
    int friendId,
    UserSessionToken token,
    int gen,
  ) async {
    if (_conversationPollInFlight) return;
    if (gen != _conversationPollingGen) return;
    _conversationPollInFlight = true;

    bool owns() =>
        gen == _conversationPollingGen && _sessionEpoch.isCurrent(token);

    try {
      final newMessages = await _repository.getMessages(friendId, limit: 20);
      if (!owns()) return;

      if (newMessages.isNotEmpty) {
        final currentMessages = _messagesByFriend[friendId] ?? const [];
        final latestId =
            currentMessages.isNotEmpty ? currentMessages.last.id : 0;

        final trulyNewMessages =
            newMessages.where((m) => m.id > latestId).toList();

        if (trulyNewMessages.isNotEmpty) {
          _messagesByFriend[friendId] = [
            ...currentMessages,
            ...trulyNewMessages,
          ];
          notifyListeners();

          // Mark as read since the user is viewing this thread. Awaited and
          // guarded - never fire-and-forget from a (possibly stale) tick.
          if (owns()) {
            await markAsRead(friendId);
          }
        }
      }
    } catch (e) {
      if (owns()) {
        debugPrint('⚠️ MessagesProvider._pollForNewMessages error: $e');
      }
    } finally {
      _conversationPollInFlight = false;
    }
  }

  /// Stop conversation polling. Authoritative, unconditional teardown -
  /// called from the conversation screen's `dispose`, from [clear], and
  /// from [dispose]. Bumps the polling generation so any timer tick or
  /// in-flight [_pollForNewMessages] from the superseded generation becomes
  /// a no-op. `_conversationPollInFlight` is left to that in-flight poll's
  /// own `finally` to clear - resetting it here could let a fresh poll
  /// start and overlap a still-awaiting superseded one.
  void stopConversationPolling() {
    _conversationPollingGen++;
    _conversationPollingTimer?.cancel();
    _conversationPollingTimer = null;
    _activeConversationFriendId = null;
  }

  /// Start polling for the unread count (every 30 seconds). Same
  /// generation-bound tick ownership as [startConversationPolling].
  void startUnreadCountPolling() {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    stopUnreadCountPolling();
    final gen = ++_unreadPollingGen;

    _unreadCountPollingTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) {
      if (gen != _unreadPollingGen || !_sessionEpoch.isCurrent(token)) {
        timer.cancel();
        return;
      }
      loadUnreadCount();
    });
  }

  /// Stop unread count polling. Authoritative, unconditional teardown.
  void stopUnreadCountPolling() {
    _unreadPollingGen++;
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

  /// Clear all direct-message state and stop both polling timers (called on
  /// logout via [SessionCleanupCoordinator]).
  ///
  /// Every request generation is bumped, every per-friend send generation is
  /// bumped, and both polling generations are bumped (inside
  /// [stopConversationPolling]/[stopUnreadCountPolling]) BEFORE any state is
  /// reset, so a load, send, or poll continuation that resolves after this
  /// returns - or a timer callback mid-execution - fails its ownership check
  /// and can neither repopulate the cleared state nor re-arm a timer.
  /// [stopConversationPolling]/[stopUnreadCountPolling] are the sole
  /// mechanism that resets [_activeConversationFriendId] and hard-cancels
  /// the live timers. In the live logout path
  /// `UserSessionEpoch.invalidate()` has already run, so `isCurrent(token)`
  /// is also false; the generation bumps make this correct even when
  /// `clear()` is called on its own.
  void clear() {
    _conversationsRequestGen++;
    _messageLoadGen++;
    _unreadRequestGen++;
    _sendGens.updateAll((_, value) => value + 1);

    stopConversationPolling();
    stopUnreadCountPolling();

    _conversations = [];
    _messagesByFriend.clear();
    _totalUnreadCount = 0;
    _isLoading = false;
    _isLoadingMessages = false;
    _isSending = false;
    _errorMessage = null;
    notifyListeners();
    debugPrint('🧹 MessagesProvider cleared');
  }

  @override
  void dispose() {
    _conversationsRequestGen++;
    _messageLoadGen++;
    _unreadRequestGen++;
    _sendGens.updateAll((_, value) => value + 1);
    stopConversationPolling();
    stopUnreadCountPolling();
    super.dispose();
  }
}
