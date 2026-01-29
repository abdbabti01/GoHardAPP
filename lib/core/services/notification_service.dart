import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../../data/models/session.dart';

/// Service for managing local notifications
/// Handles daily workout reminders and motivational notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Notification IDs
  static const int morningReminderId = 1;
  static const int eveningReminderId = 2;
  static const int nutritionReminderId = 3;

  /// Goal reminders start at ID 100
  /// Each goal uses its goalId + 100 as the notification ID
  static const int goalReminderBaseId = 100;

  /// Initialize notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize timezone database
      tz.initializeTimeZones();

      // Set local timezone to device's timezone
      final String timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
      debugPrint('🕒 Timezone set to: $timezoneName');

      // Android initialization settings
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Initialize with callback for when notification is tapped
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // For iOS, explicitly request permissions
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }

      _isInitialized = true;
    } catch (e, stackTrace) {
      debugPrint('Failed to initialize notifications: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // Navigation will be handled by the app router based on payload
  }

  /// Request notification permissions (Android 13+, iOS)
  Future<bool> requestPermissions() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.request();
        return status.isGranted;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Request iOS permissions explicitly
        final granted = await _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return granted ?? false;
      }

      return true;
    } catch (e) {
      debugPrint('Failed to request notification permissions: $e');
      return false;
    }
  }

  /// Schedule morning reminder
  /// Shows planned workouts or motivational message
  Future<void> scheduleMorningReminder({
    required int hour,
    required int minute,
    List<Session>? todayWorkouts,
  }) async {
    await _scheduleDailyNotification(
      id: morningReminderId,
      hour: hour,
      minute: minute,
      title: '💪 GoHard - Daily Reminder',
      body: _getMorningNotificationBody(todayWorkouts),
      payload: 'morning_reminder',
    );
  }

  /// Schedule evening reminder
  /// Motivates user if they haven't worked out
  Future<void> scheduleEveningReminder({
    required int hour,
    required int minute,
  }) async {
    await _scheduleDailyNotification(
      id: eveningReminderId,
      hour: hour,
      minute: minute,
      title: '🔥 Don\'t Break Your Streak!',
      body: 'You haven\'t worked out today. Even 15 minutes counts!',
      payload: 'evening_reminder',
    );
  }

  /// Schedule goal progress reminder
  /// Frequency: 'daily', 'every2days', 'every3days', 'weekly', 'biweekly'
  Future<void> scheduleGoalReminder({
    required int goalId,
    required String goalName,
    required String goalType,
    required String frequency,
    int hour = 18, // Default to 6 PM
    int minute = 0,
  }) async {
    try {
      final notificationId = goalReminderBaseId + goalId;
      final title = '📊 Goal Progress Update';
      final body = 'Time to log your progress for: $goalName';

      // Parse frequency to days interval
      final daysInterval = _parseFrequencyToDays(frequency);

      if (daysInterval == 1) {
        // Daily reminder - use matchDateTimeComponents
        await _scheduleDailyNotification(
          id: notificationId,
          hour: hour,
          minute: minute,
          title: title,
          body: body,
          payload: 'goal_reminder:$goalId',
        );
      } else {
        // Custom interval (every N days)
        await _schedulePeriodicGoalNotification(
          id: notificationId,
          hour: hour,
          minute: minute,
          daysInterval: daysInterval,
          title: title,
          body: body,
          payload: 'goal_reminder:$goalId',
        );
      }
    } catch (e) {
      debugPrint('Failed to schedule goal reminder: $e');
    }
  }

  /// Parse frequency string to days interval
  int _parseFrequencyToDays(String frequency) {
    switch (frequency.toLowerCase()) {
      case 'daily':
        return 1;
      case 'every2days':
        return 2;
      case 'every3days':
        return 3;
      case 'weekly':
        return 7;
      case 'biweekly':
        return 14;
      default:
        return 7; // Default to weekly
    }
  }

  /// Schedule a periodic notification for goals (every N days)
  Future<void> _schedulePeriodicGoalNotification({
    required int id,
    required int hour,
    required int minute,
    required int daysInterval,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      // Cancel existing notification with this ID
      await _notifications.cancel(id);

      // Create notification time for today
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      // If the time has passed today, schedule for next interval
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(Duration(days: daysInterval));
      }

      // Android notification details
      const androidDetails = AndroidNotificationDetails(
        'goal_progress_reminders',
        'Goal Progress Reminders',
        channelDescription: 'Reminders to update your fitness goals progress',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      // iOS notification details
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Schedule the notification
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      // Note: For periodic notifications (every N days where N > 1),
      // we'll need to reschedule after each notification fires.
      // This is handled by the notification tap callback.
    } catch (e) {
      debugPrint('Failed to schedule periodic goal notification: $e');
    }
  }

  /// Cancel goal reminder
  Future<void> cancelGoalReminder(int goalId) async {
    final notificationId = goalReminderBaseId + goalId;
    await _notifications.cancel(notificationId);
  }

  /// Update goal reminder (cancel old and schedule new)
  Future<void> updateGoalReminder({
    required int goalId,
    required String goalName,
    required String goalType,
    required String frequency,
    int hour = 18,
    int minute = 0,
  }) async {
    await cancelGoalReminder(goalId);
    await scheduleGoalReminder(
      goalId: goalId,
      goalName: goalName,
      goalType: goalType,
      frequency: frequency,
      hour: hour,
      minute: minute,
    );
  }

  /// Schedule a daily recurring notification
  Future<void> _scheduleDailyNotification({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      // Cancel existing notification with this ID
      await _notifications.cancel(id);

      // Create notification time for today
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      // If the time has passed today, schedule for tomorrow
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      // Android notification details
      const androidDetails = AndroidNotificationDetails(
        'daily_workout_reminders',
        'Daily Workout Reminders',
        channelDescription: 'Daily notifications to remind you about workouts',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      // iOS notification details
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Schedule daily notification
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // Repeat daily
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Failed to schedule notification: $e');
    }
  }

  /// Generate morning notification body based on today's workouts
  String _getMorningNotificationBody(List<Session>? todayWorkouts) {
    if (todayWorkouts == null || todayWorkouts.isEmpty) {
      return 'No workouts planned today.\n\nPlan a quick session?';
    }

    if (todayWorkouts.length == 1) {
      final workout = todayWorkouts.first;
      return 'You have 1 workout planned:\n• ${workout.name ?? "Workout"}';
    }

    final count = todayWorkouts.length;
    final firstTwo = todayWorkouts.take(2).map((w) => w.name ?? 'Workout');
    return 'You have $count workouts planned:\n• ${firstTwo.join('\n• ')}';
  }

  /// Update morning reminder with latest workout data
  Future<void> updateMorningReminder({
    required int hour,
    required int minute,
    required List<Session> todayWorkouts,
  }) async {
    await scheduleMorningReminder(
      hour: hour,
      minute: minute,
      todayWorkouts: todayWorkouts,
    );
  }

  /// Cancel morning reminder
  Future<void> cancelMorningReminder() async {
    await _notifications.cancel(morningReminderId);
  }

  /// Cancel evening reminder
  Future<void> cancelEveningReminder() async {
    await _notifications.cancel(eveningReminderId);
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// Show nutrition goal notification (called from background task)
  /// Only shows if calorie goal < 80% met
  Future<void> showNutritionGoalNotification({
    required double consumed,
    required double goal,
  }) async {
    final percentAchieved =
        goal > 0 ? (consumed / goal * 100).clamp(0, 100) : 0;

    // Only show if less than 80% achieved
    if (percentAchieved >= 80) {
      debugPrint(
        '🍎 Nutrition goal ${percentAchieved.toStringAsFixed(0)}% met - skipping notification',
      );
      return;
    }

    final remaining = goal - consumed;
    String body;
    if (consumed == 0) {
      body = "You haven't logged any meals today. Don't forget to track!";
    } else {
      body =
          "You're ${remaining.toStringAsFixed(0)} calories short of your goal today.";
    }

    const androidDetails = AndroidNotificationDetails(
      'nutrition_reminders',
      'Nutrition Reminders',
      channelDescription: 'Evening reminders about nutrition goals',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _notifications.show(
      nutritionReminderId,
      '🍎 Nutrition Goal Reminder',
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: 'nutrition_reminder',
    );

    debugPrint('🍎 Showed nutrition reminder notification');
  }

  /// Cancel nutrition reminder
  Future<void> cancelNutritionReminder() async {
    await _notifications.cancel(nutritionReminderId);
  }

  /// Show immediate test notification
  Future<void> showTestNotification() async {
    try {
      // Check iOS permissions before showing notification
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosImpl =
            _notifications
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >();

        if (iosImpl != null) {
          // Request permissions again to ensure they're granted
          final granted = await iosImpl.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

          if (granted != true) {
            throw Exception('iOS notification permissions not granted');
          }
        }
      }

      const androidDetails = AndroidNotificationDetails(
        'test_notifications',
        'Test Notifications',
        channelDescription: 'Test notification channel',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        999,
        '💪 Test Notification',
        'Your notifications are working!',
        details,
        payload: 'test',
      );
    } catch (e, stackTrace) {
      debugPrint('Error showing test notification: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
