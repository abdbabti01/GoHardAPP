import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/chat_conversation.dart';
import '../data/models/chat_message.dart';
import '../data/repositories/chat_repository.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/user_session_epoch.dart';

export '../data/repositories/chat_repository.dart'
    show
        ApplyMealPlanResult,
        ApplyMealPlanWeekResult,
        DayApplyResult,
        MealPlanPreview,
        MealPlanDayPreview,
        MealPreview;

/// Provider for AI chat management
class ChatProvider extends ChangeNotifier {
  final ChatRepository _chatRepository;
  final ConnectivityService _connectivity;
  final UserSessionEpoch _sessionEpoch;

  List<ChatConversation> _conversations = [];
  ChatConversation? _currentConversation;
  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;
  StreamSubscription<bool>? _connectivitySubscription;

  ChatProvider(this._chatRepository, this._connectivity, this._sessionEpoch) {
    // Don't auto-load conversations here - they'll be loaded after login
    // This prevents trying to load conversations before user is authenticated

    // Listen for connectivity changes and refresh when going online. This
    // callback can fire at any point in the app's lifetime, including during
    // a logged-out gap between one user's logout and the next user's login -
    // capture a token fresh on every invocation and skip entirely if there
    // is no active session, so a connectivity flap while logged out can
    // never dispatch a conversation load for nobody.
    _connectivitySubscription = _connectivity.connectivityStream.listen((
      isOnline,
    ) {
      final token = _sessionEpoch.capture();
      if (token == null) return;
      if (isOnline) {
        debugPrint('📡 Connection restored - refreshing conversations');
        loadConversations(showLoading: false);
      }
    });
  }

  // Getters
  List<ChatConversation> get conversations => _conversations;
  ChatConversation? get currentConversation => _currentConversation;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;
  bool get isOffline => !_connectivity.isOnline;

  /// Load all conversations for current user.
  ///
  /// Session-epoch guarded: [token] is captured before any await, and
  /// re-checked after every await (including inside catch/finally) before
  /// touching any field or calling notifyListeners(). If the session that
  /// requested this load has since ended - logout, or a different user
  /// logging in - the response is dropped silently.
  Future<void> loadConversations({bool showLoading = true}) async {
    if (_isLoading) return;

    final token = _sessionEpoch.capture();
    if (token == null) return;

    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final conversationList = await _chatRepository.getConversations();
      if (!_sessionEpoch.isCurrent(token)) return;
      _conversations = conversationList;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage =
          'Failed to load conversations: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load conversations error: $e');
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        if (showLoading) {
          _isLoading = false;
        }
        notifyListeners();
      }
    }
  }

  /// Load a specific conversation with all messages. Same session-epoch
  /// guarding as [loadConversations].
  Future<void> loadConversation(int conversationId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final conversation = await _chatRepository.getConversation(
        conversationId,
      );
      if (!_sessionEpoch.isCurrent(token)) return;
      _currentConversation = conversation;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage =
          'Failed to load conversation: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load conversation error: $e');
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create a new conversation
  Future<ChatConversation?> createConversation({
    required String title,
    required String type,
  }) async {
    if (isOffline) {
      _errorMessage = 'Cannot create conversations offline';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final conversation = await _chatRepository.createConversation(
        title: title,
        type: type,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      if (conversation != null) {
        _conversations.insert(0, conversation);
        _currentConversation = conversation;
      }

      return conversation;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to create conversation: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create conversation error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Send a message and get AI response.
  ///
  /// Guarded by BOTH session identity and conversation identity, captured
  /// together before the first await:
  /// - [token] guards against the session ending (logout) or a different
  ///   user logging in while the AI-response await is in flight.
  /// - [conversationId] guards against the SAME user switching to a
  ///   DIFFERENT conversation in this same shared provider instance while
  ///   that await is in flight - a case the session token alone cannot
  ///   catch, since the session never changes.
  ///
  /// [ownsConversation] is rechecked after the await and before every
  /// success/failure/error mutation; nothing below ever mutates
  /// [_currentConversation] or [_conversations] without it passing first,
  /// and every mutation re-reads the CURRENT conversation by [conversationId]
  /// rather than reusing a stale local reference or list index. This
  /// prevents both a null-assert crash (if [clear] ran mid-flight) and
  /// appending this response into a conversation - same account or a
  /// different one - that it does not belong to.
  ///
  /// The `_isSending` reentrancy guard below also means at most one
  /// [sendMessage] call is ever in flight for this provider at a time, so
  /// there is never a "newer" send operation for this one's `finally` block
  /// to incorrectly clear.
  Future<bool> sendMessage(String message) async {
    if (isOffline) {
      _errorMessage = 'Cannot send messages offline - AI requires connection';
      notifyListeners();
      return false;
    }

    if (_isSending) return false;

    final conversation = _currentConversation;
    if (conversation == null) {
      _errorMessage = 'No active conversation';
      notifyListeners();
      return false;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return false;

    final conversationId = conversation.id;

    bool ownsConversation() =>
        _sessionEpoch.isCurrent(token) &&
        _currentConversation?.id == conversationId;

    _isSending = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Add user message optimistically to UI
      final userMessage = ChatMessage(
        id: 0, // Temporary ID
        conversationId: conversationId,
        role: 'user',
        content: message,
        createdAt: DateTime.now().toUtc(),
      );

      _currentConversation = conversation.copyWith(
        messages: [...conversation.messages, userMessage],
      );
      notifyListeners();

      // Send to server and get AI response
      final aiResponse = await _chatRepository.sendMessage(
        conversationId: conversationId,
        message: message,
      );
      if (!ownsConversation()) return false;
      // Re-read the CURRENT conversation by id - never the locally
      // captured [conversation] snapshot from before the await, which may
      // now be stale even though the id still matches (e.g. a reload
      // picked up other changes while this request was in flight).
      final owned = _currentConversation!;

      if (aiResponse != null && aiResponse.conversationId != conversationId) {
        // Defense-in-depth: the repository's own response claims a
        // different conversation than the one this request was sent for -
        // never attach it, regardless of local state. Treated the same as
        // a failed response: roll back the optimistic message rather than
        // leaving it stuck in a pending-looking state.
        _currentConversation = owned.copyWith(
          messages: owned.messages.where((m) => m.id != 0).toList(),
        );
        _errorMessage = 'Failed to get AI response';
        return false;
      }

      if (aiResponse != null) {
        // Update conversation with AI response
        final updated = owned.copyWith(
          messages: [...owned.messages, aiResponse],
          lastMessageAt: aiResponse.createdAt,
        );
        _currentConversation = updated;

        // Update conversation in list by its stable id, never by a
        // positional index captured before the await.
        final index = _conversations.indexWhere((c) => c.id == conversationId);
        if (index != -1) {
          _conversations[index] = updated;
        }

        return true;
      } else {
        // Remove optimistic user message on failure
        _currentConversation = owned.copyWith(
          messages: owned.messages.where((m) => m.id != 0).toList(),
        );
        _errorMessage = 'Failed to get AI response';
        return false;
      }
    } catch (e) {
      if (ownsConversation()) {
        // Remove optimistic user message on error
        final owned = _currentConversation!;
        _currentConversation = owned.copyWith(
          messages: owned.messages.where((m) => m.id != 0).toList(),
        );
        _errorMessage =
            'Failed to send message: ${e.toString().replaceAll('Exception: ', '')}';
      }
      debugPrint('Send message error: $e');
      return false;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isSending = false;
        notifyListeners();
      }
    }
  }

  /// Delete a conversation
  Future<bool> deleteConversation(int conversationId) async {
    if (isOffline) {
      _errorMessage = 'Cannot delete conversations offline';
      notifyListeners();
      return false;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      final success = await _chatRepository.deleteConversation(conversationId);
      if (!_sessionEpoch.isCurrent(token)) return false;

      if (success) {
        _conversations.removeWhere((c) => c.id == conversationId);

        // Clear current conversation if it was deleted
        if (_currentConversation?.id == conversationId) {
          _currentConversation = null;
        }

        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Failed to delete conversation';
        notifyListeners();
        return false;
      }
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to delete conversation: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete conversation error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Delete all conversations. Each iteration of the delete loop is
  /// re-checked against [token]: if the session ends mid-batch, the loop
  /// stops issuing further UI-state mutations for what is now a stale list
  /// rather than continuing to clear/notify on behalf of a session that no
  /// longer owns this provider instance.
  Future<bool> deleteAllConversations() async {
    if (isOffline) {
      _errorMessage = 'Cannot delete conversations offline';
      notifyListeners();
      return false;
    }

    if (_conversations.isEmpty) {
      return true;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      // Delete all conversations one by one
      int successCount = 0;
      int failCount = 0;

      for (final conversation in List.from(_conversations)) {
        final success = await _chatRepository.deleteConversation(
          conversation.id,
        );
        if (!_sessionEpoch.isCurrent(token)) return false;
        if (success) {
          successCount++;
        } else {
          failCount++;
        }
      }

      // Clear local state
      _conversations.clear();
      _currentConversation = null;
      notifyListeners();

      if (failCount > 0) {
        _errorMessage =
            'Deleted $successCount conversations, $failCount failed';
        debugPrint('⚠️ Some conversations failed to delete');
      } else {
        debugPrint('✅ Deleted all $successCount conversations');
      }

      return failCount == 0;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to delete conversations: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete all conversations error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Generate workout plan (creates conversation with AI plan)
  Future<ChatConversation?> generateWorkoutPlan({
    required String goal,
    required String experienceLevel,
    required int daysPerWeek,
    required String equipment,
    String? limitations,
  }) async {
    if (isOffline) {
      _errorMessage = 'Cannot generate workout plan offline';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final conversation = await _chatRepository.generateWorkoutPlan(
        goal: goal,
        experienceLevel: experienceLevel,
        daysPerWeek: daysPerWeek,
        equipment: equipment,
        limitations: limitations,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      if (conversation != null) {
        _conversations.insert(0, conversation);
        _currentConversation = conversation;
      }

      return conversation;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to generate workout plan: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Generate workout plan error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Generate meal plan (creates conversation with AI meal plan)
  Future<ChatConversation?> generateMealPlan({
    required String dietaryGoal,
    int? targetCalories,
    String? macros,
    String? restrictions,
    String? preferences,
  }) async {
    if (isOffline) {
      _errorMessage = 'Cannot generate meal plan offline';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final conversation = await _chatRepository.generateMealPlan(
        dietaryGoal: dietaryGoal,
        targetCalories: targetCalories,
        macros: macros,
        restrictions: restrictions,
        preferences: preferences,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      if (conversation != null) {
        _conversations.insert(0, conversation);
        _currentConversation = conversation;
      }

      return conversation;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to generate meal plan: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Generate meal plan error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Preview all 7 days of a meal plan for user selection
  Future<MealPlanPreview?> previewMealPlan(int conversationId) async {
    if (isOffline) {
      _errorMessage = 'Cannot preview meal plan offline';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _chatRepository.previewMealPlan(conversationId);
      if (!_sessionEpoch.isCurrent(token)) return null;
      return result;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to preview meal plan: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Preview meal plan error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Apply meal plan from a conversation to today's meal log
  /// [day] specifies which day (1-7) of the meal plan to apply
  Future<ApplyMealPlanResult?> applyMealPlanToToday(
    int conversationId, {
    int day = 1,
  }) async {
    if (isOffline) {
      _errorMessage = 'Cannot apply meal plan offline';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _chatRepository.applyMealPlanToToday(
        conversationId,
        day: day,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;
      return result;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to apply meal plan: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Apply meal plan error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Apply multiple days of a meal plan
  /// [applyAllDays] - if true, applies all 7 days
  /// [days] - specific days to apply (1-7), ignored if applyAllDays is true
  /// [startDate] - the date to start applying from (defaults to today)
  /// [overwriteExisting] - if true, replaces existing meal entries
  Future<ApplyMealPlanWeekResult?> applyMealPlanWeek(
    int conversationId, {
    bool applyAllDays = false,
    List<int>? days,
    DateTime? startDate,
    bool overwriteExisting = true,
  }) async {
    if (isOffline) {
      _errorMessage = 'Cannot apply meal plan offline';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _chatRepository.applyMealPlanWeek(
        conversationId,
        applyAllDays: applyAllDays,
        days: days,
        startDate: startDate,
        overwriteExisting: overwriteExisting,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;
      return result;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to apply meal plan: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Apply meal plan week error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Analyze user's progress (creates conversation with AI analysis)
  Future<ChatConversation?> analyzeProgress({
    DateTime? startDate,
    DateTime? endDate,
    String? focusArea,
  }) async {
    if (isOffline) {
      _errorMessage = 'Cannot analyze progress offline';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final conversation = await _chatRepository.analyzeProgress(
        startDate: startDate,
        endDate: endDate,
        focusArea: focusArea,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      if (conversation != null) {
        _conversations.insert(0, conversation);
        _currentConversation = conversation;
      }

      return conversation;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to analyze progress: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Analyze progress error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Refresh conversations (pull-to-refresh)
  Future<void> refresh() async {
    await loadConversations(showLoading: false);
  }

  /// Clear current conversation
  void clearCurrentConversation() {
    _currentConversation = null;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Preview workout sessions from the current workout plan conversation
  Future<Map<String, dynamic>?> previewSessionsFromPlan() async {
    if (isOffline) {
      _errorMessage = 'Cannot preview sessions offline';
      notifyListeners();
      return null;
    }

    if (_currentConversation == null) {
      _errorMessage = 'No active conversation';
      notifyListeners();
      return null;
    }

    if (_currentConversation!.type != 'workout_plan' &&
        _currentConversation!.type != 'combined_plan') {
      _errorMessage = 'This conversation is not a workout plan';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _chatRepository.previewSessionsFromPlan(
        conversationId: _currentConversation!.id,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      return result;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to preview sessions: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Preview sessions error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create workout sessions from the current workout plan conversation
  Future<Map<String, dynamic>?> createSessionsFromPlan({
    DateTime? startDate,
  }) async {
    if (isOffline) {
      _errorMessage = 'Cannot create sessions offline';
      notifyListeners();
      return null;
    }

    if (_currentConversation == null) {
      _errorMessage = 'No active conversation';
      notifyListeners();
      return null;
    }

    if (_currentConversation!.type != 'workout_plan' &&
        _currentConversation!.type != 'combined_plan') {
      _errorMessage = 'This conversation is not a workout plan';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _chatRepository.createSessionsFromPlan(
        conversationId: _currentConversation!.id,
        startDate: startDate,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      return result;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to create sessions: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create sessions error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create a Program from the current workout plan conversation
  Future<Map<String, dynamic>?> createProgramFromPlan({
    String? title,
    String? description,
    int? goalId,
    int? totalWeeks,
    int? daysPerWeek,
    DateTime? startDate,
  }) async {
    if (isOffline) {
      _errorMessage = 'Cannot create program offline';
      notifyListeners();
      return null;
    }

    if (_currentConversation == null) {
      _errorMessage = 'No active conversation';
      notifyListeners();
      return null;
    }

    if (_currentConversation!.type != 'workout_plan' &&
        _currentConversation!.type != 'combined_plan') {
      _errorMessage = 'This conversation is not a workout plan';
      notifyListeners();
      return null;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _chatRepository.createProgramFromPlan(
        conversationId: _currentConversation!.id,
        title: title,
        description: description,
        goalId: goalId,
        totalWeeks: totalWeeks,
        daysPerWeek: daysPerWeek,
        startDate: startDate,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      return result;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to create program: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create program error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Clear all chat data (called on logout)
  void clear() {
    _conversations = [];
    _currentConversation = null;
    _errorMessage = null;
    _isLoading = false;
    _isSending = false;
    notifyListeners();
    debugPrint('🧹 ChatProvider cleared');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
