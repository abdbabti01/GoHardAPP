import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import '../constants/api_config.dart';

/// Task name for nutrition goal check
const nutritionCheckTask = 'nutrition_goal_check';

/// Background task callback dispatcher
/// This must be a top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('🔄 Background task executing: $task');

    if (task == nutritionCheckTask) {
      await _checkNutritionGoal();
    }

    return true;
  });
}

/// Check nutrition goal and show notification if needed
Future<void> _checkNutritionGoal() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null || token.isEmpty) {
      debugPrint('🍎 No auth token - skipping nutrition check');
      return;
    }

    // Create Dio client with token for background request
    final dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ),
    );

    // Fetch today's nutrition progress
    final response = await dio.get<Map<String, dynamic>>(
      ApiConfig.nutritionGoalProgress,
    );

    final progressData = response.data ?? {};
    final consumed =
        (progressData['consumedCalories'] as num?)?.toDouble() ?? 0;
    final goal = (progressData['goalCalories'] as num?)?.toDouble() ?? 2000;

    debugPrint(
      '🍎 Nutrition progress: ${consumed.toStringAsFixed(0)}/${goal.toStringAsFixed(0)} cal',
    );

    // Initialize notification service and show notification if needed
    final notificationService = NotificationService();
    await notificationService.initialize();
    await notificationService.showNutritionGoalNotification(
      consumed: consumed,
      goal: goal,
    );
  } catch (e) {
    debugPrint('🍎 Background nutrition check failed: $e');
  }
}

/// Service for managing background tasks
class BackgroundService {
  static bool _isInitialized = false;

  /// Initialize the background service
  static Future<void> initialize() async {
    if (_isInitialized) return;

    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );

    _isInitialized = true;
    debugPrint('✅ BackgroundService initialized');
  }

  /// Schedule daily nutrition goal check
  static Future<void> scheduleNutritionCheck({
    required int hour,
    required int minute,
  }) async {
    // Cancel existing task
    await Workmanager().cancelByUniqueName(nutritionCheckTask);

    // Calculate initial delay to target time
    final now = DateTime.now();
    var targetTime = DateTime(now.year, now.month, now.day, hour, minute);

    // If the time has passed today, schedule for tomorrow
    if (targetTime.isBefore(now)) {
      targetTime = targetTime.add(const Duration(days: 1));
    }

    final initialDelay = targetTime.difference(now);

    // Register periodic task (daily)
    await Workmanager().registerPeriodicTask(
      nutritionCheckTask,
      nutritionCheckTask,
      initialDelay: initialDelay,
      frequency: const Duration(days: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    debugPrint(
      '🍎 Scheduled nutrition check at $hour:${minute.toString().padLeft(2, '0')} '
      '(initial delay: ${initialDelay.inHours}h ${initialDelay.inMinutes % 60}m)',
    );
  }

  /// Cancel the nutrition check task
  static Future<void> cancelNutritionCheck() async {
    await Workmanager().cancelByUniqueName(nutritionCheckTask);
    debugPrint('🍎 Cancelled nutrition check task');
  }

  /// Save auth token for background tasks
  static Future<void> saveAuthToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  /// Clear auth token (call on logout)
  static Future<void> clearAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }
}
