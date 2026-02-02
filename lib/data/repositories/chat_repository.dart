import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../local/services/local_database_service.dart';
import '../local/models/local_chat_conversation.dart';
import '../local/models/local_chat_message.dart';

/// Repository for chat operations with offline support
/// Note: Sending messages requires online connection (AI responses)
class ChatRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;
  final AuthService _authService;

  ChatRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._authService,
  );

  /// Get all conversations for the current user
  /// Offline-first: returns local cache immediately, syncs with server in background
  Future<List<ChatConversation>> getConversations() async {
    final Isar db = _localDb.database;

    // ALWAYS load from cache first for instant response
    final cachedConversations = await _getLocalConversations(db);

    // Then sync with server in background if online (don't block)
    if (_connectivity.isOnline) {
      _syncConversationsFromServer(db)
          .then((_) {
            debugPrint('✅ Background sync: Conversations synced from server');
          })
          .catchError((e) {
            debugPrint('⚠️ Background sync failed: $e');
          });
    }

    return cachedConversations;
  }

  /// Get local conversations from cache
  Future<List<ChatConversation>> _getLocalConversations(Isar db) async {
    final localConvos =
        await db.localChatConversations
            .filter()
            .isArchivedEqualTo(false)
            .sortByLastMessageAtDesc()
            .findAll();

    return localConvos
        .map(
          (local) => ChatConversation(
            id: local.serverId ?? 0,
            userId: local.userId,
            title: local.title,
            type: local.type,
            createdAt: local.createdAt,
            lastMessageAt: local.lastMessageAt,
            isArchived: local.isArchived,
            messageCount: 0, // Will be loaded when conversation is opened
          ),
        )
        .toList();
  }

  /// Background sync: Fetch conversations from server and update cache
  Future<void> _syncConversationsFromServer(Isar db) async {
    try {
      final currentUserId = await _authService.getUserId();
      if (currentUserId == null) {
        debugPrint('⚠️ No authenticated user, skipping conversation sync');
        return;
      }

      // Fetch from API
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.chatConversations,
      );
      final apiConversations =
          data
              .map(
                (json) =>
                    ChatConversation.fromJson(json as Map<String, dynamic>),
              )
              .toList();

      // Update local cache
      await db.writeTxn(() async {
        for (final apiConvo in apiConversations) {
          // Only cache conversations belonging to current user
          if (apiConvo.userId != currentUserId) {
            continue;
          }

          // Check if conversation already exists locally
          final existingLocal =
              await db.localChatConversations
                  .filter()
                  .serverIdEqualTo(apiConvo.id)
                  .findFirst();

          if (existingLocal != null &&
              existingLocal.syncStatus == 'pending_delete') {
            continue; // Skip conversations marked for deletion
          }

          if (existingLocal != null) {
            // Update existing local conversation
            existingLocal.title = apiConvo.title;
            existingLocal.type = apiConvo.type;
            existingLocal.lastMessageAt = apiConvo.lastMessageAt;
            existingLocal.isArchived = apiConvo.isArchived;
            existingLocal.isSynced = true;
            existingLocal.syncStatus = 'synced';
            existingLocal.lastModifiedServer = DateTime.now().toUtc();

            await db.localChatConversations.put(existingLocal);
          } else {
            // Insert new conversation
            final newLocal = LocalChatConversation(
              serverId: apiConvo.id,
              userId: apiConvo.userId,
              title: apiConvo.title,
              type: apiConvo.type,
              createdAt: apiConvo.createdAt,
              lastMessageAt: apiConvo.lastMessageAt,
              isArchived: apiConvo.isArchived,
              isSynced: true,
              syncStatus: 'synced',
              lastModifiedLocal: DateTime.now().toUtc(),
              lastModifiedServer: DateTime.now().toUtc(),
            );

            await db.localChatConversations.put(newLocal);
          }
        }
      });
    } catch (e) {
      debugPrint('❌ Error syncing conversations: $e');
      rethrow;
    }
  }

  /// Get a single conversation with all messages
  /// Requires online connection to fetch messages
  Future<ChatConversation?> getConversation(int conversationId) async {
    if (!_connectivity.isOnline) {
      // Try to load from cache if offline
      return await _getLocalConversation(conversationId);
    }

    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.chatConversationById(conversationId),
      );
      final conversation = ChatConversation.fromJson(data);

      // Cache the conversation and messages
      await _cacheConversation(conversation);

      return conversation;
    } catch (e) {
      debugPrint('❌ Error fetching conversation: $e');
      // Fallback to cache if API fails
      return await _getLocalConversation(conversationId);
    }
  }

  /// Get conversation from local cache
  Future<ChatConversation?> _getLocalConversation(int conversationId) async {
    final db = _localDb.database;

    final localConvo =
        await db.localChatConversations
            .filter()
            .serverIdEqualTo(conversationId)
            .findFirst();

    if (localConvo == null) return null;

    // Load messages for this conversation
    final localMessages =
        await db.localChatMessages
            .filter()
            .conversationServerIdEqualTo(conversationId)
            .sortByCreatedAt()
            .findAll();

    final messages =
        localMessages
            .map(
              (local) => ChatMessage(
                id: local.serverId ?? 0,
                conversationId: conversationId,
                role: local.role,
                content: local.content,
                createdAt: local.createdAt,
                inputTokens: local.inputTokens,
                outputTokens: local.outputTokens,
                model: local.model,
              ),
            )
            .toList();

    return ChatConversation(
      id: conversationId,
      userId: localConvo.userId,
      title: localConvo.title,
      type: localConvo.type,
      createdAt: localConvo.createdAt,
      lastMessageAt: localConvo.lastMessageAt,
      isArchived: localConvo.isArchived,
      messages: messages,
    );
  }

  /// Cache a conversation and its messages locally
  Future<void> _cacheConversation(ChatConversation conversation) async {
    final db = _localDb.database;
    final currentUserId = await _authService.getUserId();
    if (currentUserId == null) return;

    await db.writeTxn(() async {
      // Cache conversation
      final existingLocal =
          await db.localChatConversations
              .filter()
              .serverIdEqualTo(conversation.id)
              .findFirst();

      if (existingLocal != null) {
        existingLocal.title = conversation.title;
        existingLocal.type = conversation.type;
        existingLocal.lastMessageAt = conversation.lastMessageAt;
        existingLocal.isArchived = conversation.isArchived;
        existingLocal.isSynced = true;
        existingLocal.syncStatus = 'synced';

        await db.localChatConversations.put(existingLocal);

        // Cache messages
        for (final message in conversation.messages) {
          final existingMessage =
              await db.localChatMessages
                  .filter()
                  .serverIdEqualTo(message.id)
                  .findFirst();

          if (existingMessage == null) {
            final newMessage = LocalChatMessage(
              serverId: message.id,
              conversationLocalId: existingLocal.localId,
              conversationServerId: conversation.id,
              role: message.role,
              content: message.content,
              createdAt: message.createdAt,
              inputTokens: message.inputTokens,
              outputTokens: message.outputTokens,
              model: message.model,
              isSynced: true,
              syncStatus: 'synced',
              lastModifiedLocal: DateTime.now().toUtc(),
            );

            await db.localChatMessages.put(newMessage);
          }
        }
      } else {
        // Create new local conversation
        final newLocal = LocalChatConversation(
          serverId: conversation.id,
          userId: conversation.userId,
          title: conversation.title,
          type: conversation.type,
          createdAt: conversation.createdAt,
          lastMessageAt: conversation.lastMessageAt,
          isArchived: conversation.isArchived,
          isSynced: true,
          syncStatus: 'synced',
          lastModifiedLocal: DateTime.now().toUtc(),
        );

        final localId = await db.localChatConversations.put(newLocal);

        // Cache messages
        for (final message in conversation.messages) {
          final newMessage = LocalChatMessage(
            serverId: message.id,
            conversationLocalId: localId,
            conversationServerId: conversation.id,
            role: message.role,
            content: message.content,
            createdAt: message.createdAt,
            inputTokens: message.inputTokens,
            outputTokens: message.outputTokens,
            model: message.model,
            isSynced: true,
            syncStatus: 'synced',
            lastModifiedLocal: DateTime.now().toUtc(),
          );

          await db.localChatMessages.put(newMessage);
        }
      }
    });
  }

  /// Create a new conversation
  /// Requires online connection
  Future<ChatConversation?> createConversation({
    required String title,
    required String type,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot create conversations offline');
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatConversations,
        data: {'title': title, 'type': type},
      );

      final conversation = ChatConversation.fromJson(response);

      // Cache locally
      await _cacheConversation(conversation);

      return conversation;
    } catch (e) {
      debugPrint('❌ Error creating conversation: $e');
      rethrow;
    }
  }

  /// Send a message and get AI response
  /// Requires online connection
  Future<ChatMessage?> sendMessage({
    required int conversationId,
    required String message,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot send messages offline - AI requires connection');
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatMessages(conversationId),
        data: {'message': message, 'stream': false},
      );

      final aiMessage = ChatMessage.fromJson(response);

      // Cache the AI response locally
      await _cacheMessage(conversationId, message, aiMessage);

      return aiMessage;
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      rethrow;
    }
  }

  /// Cache user message and AI response locally
  Future<void> _cacheMessage(
    int conversationId,
    String userMessage,
    ChatMessage aiResponse,
  ) async {
    final db = _localDb.database;

    final localConvo =
        await db.localChatConversations
            .filter()
            .serverIdEqualTo(conversationId)
            .findFirst();

    if (localConvo == null) return;

    await db.writeTxn(() async {
      // Cache user message (it's not returned from API, create it locally)
      final userMsg = LocalChatMessage(
        conversationLocalId: localConvo.localId,
        conversationServerId: conversationId,
        role: 'user',
        content: userMessage,
        createdAt: DateTime.now().toUtc(),
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await db.localChatMessages.put(userMsg);

      // Cache AI response
      final aiMsg = LocalChatMessage(
        serverId: aiResponse.id,
        conversationLocalId: localConvo.localId,
        conversationServerId: conversationId,
        role: aiResponse.role,
        content: aiResponse.content,
        createdAt: aiResponse.createdAt,
        inputTokens: aiResponse.inputTokens,
        outputTokens: aiResponse.outputTokens,
        model: aiResponse.model,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now().toUtc(),
      );
      await db.localChatMessages.put(aiMsg);

      // Update conversation's lastMessageAt
      localConvo.lastMessageAt = aiResponse.createdAt;
      await db.localChatConversations.put(localConvo);
    });
  }

  /// Delete a conversation
  /// Requires online connection
  Future<bool> deleteConversation(int conversationId) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot delete conversations offline');
    }

    try {
      await _apiService.delete(ApiConfig.chatConversationById(conversationId));

      // Remove from local cache
      final db = _localDb.database;
      await db.writeTxn(() async {
        final localConvo =
            await db.localChatConversations
                .filter()
                .serverIdEqualTo(conversationId)
                .findFirst();

        if (localConvo != null) {
          // Delete messages first
          final messages =
              await db.localChatMessages
                  .filter()
                  .conversationLocalIdEqualTo(localConvo.localId)
                  .findAll();

          for (final msg in messages) {
            await db.localChatMessages.delete(msg.localId);
          }

          // Delete conversation
          await db.localChatConversations.delete(localConvo.localId);
        }
      });

      return true;
    } catch (e) {
      debugPrint('❌ Error deleting conversation: $e');
      return false;
    }
  }

  /// Generate workout plan (creates conversation + first AI response)
  /// Requires online connection
  Future<ChatConversation?> generateWorkoutPlan({
    required String goal,
    required String experienceLevel,
    required int daysPerWeek,
    required String equipment,
    String? limitations,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot generate workout plan offline');
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatWorkoutPlan,
        data: {
          'goal': goal,
          'experienceLevel': experienceLevel,
          'daysPerWeek': daysPerWeek,
          'equipment': equipment,
          'limitations': limitations ?? '',
        },
      );

      final conversation = ChatConversation.fromJson(response);

      // Cache locally
      await _cacheConversation(conversation);

      return conversation;
    } catch (e) {
      debugPrint('❌ Error generating workout plan: $e');
      rethrow;
    }
  }

  /// Generate meal plan (creates conversation + first AI response)
  /// Requires online connection
  Future<ChatConversation?> generateMealPlan({
    required String dietaryGoal,
    int? targetCalories,
    String? macros,
    String? restrictions,
    String? preferences,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot generate meal plan offline');
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatMealPlan,
        data: {
          'dietaryGoal': dietaryGoal,
          'targetCalories': targetCalories,
          'macros': macros ?? '',
          'restrictions': restrictions ?? '',
          'preferences': preferences ?? '',
        },
      );

      final conversation = ChatConversation.fromJson(response);

      // Cache locally
      await _cacheConversation(conversation);

      return conversation;
    } catch (e) {
      debugPrint('❌ Error generating meal plan: $e');
      rethrow;
    }
  }

  /// Analyze user's progress (creates conversation + AI analysis)
  /// Requires online connection
  Future<ChatConversation?> analyzeProgress({
    DateTime? startDate,
    DateTime? endDate,
    String? focusArea,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot analyze progress offline');
    }

    try {
      final data = <String, dynamic>{};
      if (startDate != null) data['startDate'] = startDate.toIso8601String();
      if (endDate != null) data['endDate'] = endDate.toIso8601String();
      if (focusArea != null) data['focusArea'] = focusArea;

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatAnalyzeProgress,
        data: data,
      );

      final conversation = ChatConversation.fromJson(response);

      // Cache locally
      await _cacheConversation(conversation);

      return conversation;
    } catch (e) {
      debugPrint('❌ Error analyzing progress: $e');
      rethrow;
    }
  }

  /// Preview all 7 days of a meal plan for user selection
  /// Requires online connection
  Future<MealPlanPreview> previewMealPlan(int conversationId) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot preview meal plan offline');
    }

    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.chatPreviewMealPlan(conversationId),
      );

      debugPrint(
        '✅ Previewed meal plan: ${response['days']?.length ?? 0} days',
      );

      return MealPlanPreview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Error previewing meal plan: $e');
      rethrow;
    }
  }

  /// Apply meal plan from a conversation to today's meal log
  /// [day] specifies which day (1-7) of the meal plan to apply
  /// Requires online connection
  Future<ApplyMealPlanResult> applyMealPlanToToday(
    int conversationId, {
    int day = 1,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot apply meal plan offline');
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatApplyMealPlan(conversationId, day: day),
      );

      debugPrint(
        '✅ Applied meal plan day $day: ${response['foodsAdded']} foods added',
      );

      return ApplyMealPlanResult.fromJson(response);
    } catch (e) {
      debugPrint('❌ Error applying meal plan: $e');
      rethrow;
    }
  }

  /// Apply multiple days of a meal plan
  /// [applyAllDays] - if true, applies all 7 days
  /// [days] - specific days to apply (1-7), ignored if applyAllDays is true
  /// [startDate] - the date to start applying from (defaults to today)
  /// [overwriteExisting] - if true, replaces existing meal entries
  /// Requires online connection
  Future<ApplyMealPlanWeekResult> applyMealPlanWeek(
    int conversationId, {
    bool applyAllDays = false,
    List<int>? days,
    DateTime? startDate,
    bool overwriteExisting = true,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot apply meal plan offline');
    }

    try {
      final data = <String, dynamic>{
        'applyAllDays': applyAllDays,
        'overwriteExisting': overwriteExisting,
      };
      if (days != null && !applyAllDays) {
        data['days'] = days;
      }
      if (startDate != null) {
        data['startDate'] = startDate.toIso8601String();
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatApplyMealPlanWeek(conversationId),
        data: data,
      );

      debugPrint('✅ Applied ${response['daysApplied']} days of meal plan');

      return ApplyMealPlanWeekResult.fromJson(response);
    } catch (e) {
      debugPrint('❌ Error applying meal plan week: $e');
      rethrow;
    }
  }

  /// Preview workout sessions from an AI-generated workout plan (without creating)
  /// Requires online connection
  Future<Map<String, dynamic>> previewSessionsFromPlan({
    required int conversationId,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot preview sessions offline');
    }

    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.chatPreviewSessions(conversationId),
      );

      debugPrint(
        '✅ Previewed ${response['sessionsCount']} sessions from workout plan',
      );

      return response;
    } catch (e) {
      debugPrint('❌ Error previewing sessions: $e');
      rethrow;
    }
  }

  /// Create workout sessions from an AI-generated workout plan
  /// Requires online connection - cannot create sessions offline
  Future<Map<String, dynamic>> createSessionsFromPlan({
    required int conversationId,
    DateTime? startDate,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot create sessions offline');
    }

    try {
      final data = <String, dynamic>{};
      if (startDate != null) {
        data['startDate'] = startDate.toIso8601String();
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatCreateSessions(conversationId),
        data: data,
      );

      debugPrint(
        '✅ Created ${response['sessions'].length} sessions from workout plan',
      );

      return response;
    } catch (e) {
      debugPrint('❌ Error creating sessions from plan: $e');
      rethrow;
    }
  }

  /// Create a Program from an AI-generated workout plan
  /// Requires online connection - cannot create programs offline
  Future<Map<String, dynamic>> createProgramFromPlan({
    required int conversationId,
    String? title,
    String? description,
    int? goalId,
    int? totalWeeks,
    int? daysPerWeek,
    DateTime? startDate,
  }) async {
    if (!_connectivity.isOnline) {
      throw Exception('Cannot create program offline');
    }

    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (description != null) data['description'] = description;
      if (goalId != null) data['goalId'] = goalId;
      if (totalWeeks != null) data['totalWeeks'] = totalWeeks;
      if (daysPerWeek != null) data['daysPerWeek'] = daysPerWeek;
      if (startDate != null) data['startDate'] = startDate.toIso8601String();

      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatCreateProgram(conversationId),
        data: data,
      );

      debugPrint(
        '✅ Created program from workout plan: ${response['program']['title']}',
      );

      return response;
    } catch (e) {
      debugPrint('❌ Error creating program from plan: $e');
      rethrow;
    }
  }
}

/// Result of applying a meal plan to today's log
class ApplyMealPlanResult {
  final bool success;
  final String message;
  final int foodsAdded;
  final double totalCaloriesAdded;
  final double totalProteinAdded;
  final double totalCarbsAdded;
  final double totalFatAdded;

  /// Whether the nutrition goal was updated
  final bool goalUpdated;

  /// New daily calorie goal (if updated)
  final double? newDailyCalorieGoal;

  /// New daily protein goal (if updated)
  final double? newDailyProteinGoal;

  /// New daily carbs goal (if updated)
  final double? newDailyCarbsGoal;

  /// New daily fat goal (if updated)
  final double? newDailyFatGoal;

  ApplyMealPlanResult({
    required this.success,
    required this.message,
    required this.foodsAdded,
    required this.totalCaloriesAdded,
    required this.totalProteinAdded,
    required this.totalCarbsAdded,
    required this.totalFatAdded,
    this.goalUpdated = false,
    this.newDailyCalorieGoal,
    this.newDailyProteinGoal,
    this.newDailyCarbsGoal,
    this.newDailyFatGoal,
  });

  factory ApplyMealPlanResult.fromJson(Map<String, dynamic> json) {
    return ApplyMealPlanResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      foodsAdded: json['foodsAdded'] as int? ?? 0,
      totalCaloriesAdded: (json['totalCaloriesAdded'] as num?)?.toDouble() ?? 0,
      totalProteinAdded: (json['totalProteinAdded'] as num?)?.toDouble() ?? 0,
      totalCarbsAdded: (json['totalCarbsAdded'] as num?)?.toDouble() ?? 0,
      totalFatAdded: (json['totalFatAdded'] as num?)?.toDouble() ?? 0,
      goalUpdated: json['goalUpdated'] as bool? ?? false,
      newDailyCalorieGoal: (json['newDailyCalorieGoal'] as num?)?.toDouble(),
      newDailyProteinGoal: (json['newDailyProteinGoal'] as num?)?.toDouble(),
      newDailyCarbsGoal: (json['newDailyCarbsGoal'] as num?)?.toDouble(),
      newDailyFatGoal: (json['newDailyFatGoal'] as num?)?.toDouble(),
    );
  }
}

/// Preview of a 7-day meal plan for user selection
class MealPlanPreview {
  final bool success;
  final String? message;
  final double targetCalories;
  final List<MealPlanDayPreview> days;

  MealPlanPreview({
    required this.success,
    this.message,
    required this.targetCalories,
    required this.days,
  });

  factory MealPlanPreview.fromJson(Map<String, dynamic> json) {
    return MealPlanPreview(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      targetCalories: (json['targetCalories'] as num?)?.toDouble() ?? 2000,
      days:
          (json['days'] as List<dynamic>?)
              ?.map(
                (d) => MealPlanDayPreview.fromJson(d as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

/// Preview of a single day in the meal plan
class MealPlanDayPreview {
  final int day;
  final String summary;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final bool isWithinTarget;
  final List<MealPreview> meals;

  MealPlanDayPreview({
    required this.day,
    required this.summary,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.isWithinTarget,
    required this.meals,
  });

  factory MealPlanDayPreview.fromJson(Map<String, dynamic> json) {
    return MealPlanDayPreview(
      day: json['day'] as int? ?? 1,
      summary: json['summary'] as String? ?? '',
      totalCalories: (json['totalCalories'] as num?)?.toDouble() ?? 0,
      totalProtein: (json['totalProtein'] as num?)?.toDouble() ?? 0,
      totalCarbs: (json['totalCarbs'] as num?)?.toDouble() ?? 0,
      totalFat: (json['totalFat'] as num?)?.toDouble() ?? 0,
      isWithinTarget: json['isWithinTarget'] as bool? ?? false,
      meals:
          (json['meals'] as List<dynamic>?)
              ?.map((m) => MealPreview.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Preview of a single meal
class MealPreview {
  final String mealType;
  final List<String> foods;
  final double calories;

  MealPreview({
    required this.mealType,
    required this.foods,
    required this.calories,
  });

  factory MealPreview.fromJson(Map<String, dynamic> json) {
    return MealPreview(
      mealType: json['mealType'] as String? ?? '',
      foods:
          (json['foods'] as List<dynamic>?)
              ?.map((f) => f.toString())
              .toList() ??
          [],
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Result of applying multiple days of a meal plan
class ApplyMealPlanWeekResult {
  final bool success;
  final String message;
  final int daysApplied;
  final int totalFoodsAdded;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final List<DayApplyResult> dayResults;

  ApplyMealPlanWeekResult({
    required this.success,
    required this.message,
    required this.daysApplied,
    required this.totalFoodsAdded,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.dayResults,
  });

  factory ApplyMealPlanWeekResult.fromJson(Map<String, dynamic> json) {
    return ApplyMealPlanWeekResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      daysApplied: json['daysApplied'] as int? ?? 0,
      totalFoodsAdded: json['totalFoodsAdded'] as int? ?? 0,
      totalCalories: (json['totalCalories'] as num?)?.toDouble() ?? 0,
      totalProtein: (json['totalProtein'] as num?)?.toDouble() ?? 0,
      totalCarbs: (json['totalCarbs'] as num?)?.toDouble() ?? 0,
      totalFat: (json['totalFat'] as num?)?.toDouble() ?? 0,
      dayResults:
          (json['dayResults'] as List<dynamic>?)
              ?.map((d) => DayApplyResult.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Result for each day applied in a multi-day meal plan application
class DayApplyResult {
  final int day;
  final DateTime date;
  final int foodsAdded;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  DayApplyResult({
    required this.day,
    required this.date,
    required this.foodsAdded,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  factory DayApplyResult.fromJson(Map<String, dynamic> json) {
    return DayApplyResult(
      day: json['day'] as int? ?? 0,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      foodsAdded: json['foodsAdded'] as int? ?? 0,
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
    );
  }
}
