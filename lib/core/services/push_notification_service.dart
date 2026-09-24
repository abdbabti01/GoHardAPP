import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../data/services/api_service.dart';
import '../../core/constants/api_config.dart';
import 'firebase_bootstrap.dart';

/// Background message handler - must be top-level function. Delegates to
/// [handleBackgroundFirebaseMessage], which is exposed for tests since
/// this function runs in a dedicated isolate spawned directly by the
/// native FCM plugin and can't be invoked from a test.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) =>
    handleBackgroundFirebaseMessage(message.messageId);

/// Initializes Firebase for the background-message isolate and logs the
/// message id on success, without ever letting a failure escape. This
/// isolate is unrelated to the main isolate's `FirebaseAvailability`, so
/// it must independently guard `Firebase.initializeApp()` - Android
/// currently ships unconfigured, so this is expected to fail there today.
@visibleForTesting
Future<void> handleBackgroundFirebaseMessage(
  String? messageId, {
  Future<void> Function() initializer = Firebase.initializeApp,
}) async {
  final available = await initializeFirebaseSafely(initializer);
  if (available) {
    debugPrint('🔔 Background message: $messageId');
  }
}

/// Service for handling Firebase Cloud Messaging push notifications
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  // `late` so this is only evaluated on first *use* (inside `initialize()`,
  // which callers gate on Firebase availability), not at construction -
  // `FirebaseMessaging.instance` throws immediately when no Firebase app
  // exists, and the singleton must remain constructible either way (e.g.
  // `unregisterToken()` never touches this field).
  late final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _fcmToken;
  ApiService? _apiService;

  /// Callback when notification is tapped
  Function(Map<String, dynamic>)? onNotificationTapped;

  /// Callback when message is received in foreground
  Function(RemoteMessage)? onMessageReceived;

  /// Get current FCM token
  String? get fcmToken => _fcmToken;

  /// Initialize the push notification service.
  ///
  /// Deliberately never calls `_messaging.requestPermission()` - this used
  /// to request the OS notification permission unconditionally right after
  /// login (this method runs from main_screen.dart on every authenticated
  /// app open), which is the same contextless-request problem as the local
  /// reminder notifications had. Permission acquisition and token
  /// registration are separate operations: APNs/FCM token generation does
  /// not require alert-permission to have been granted (this app's
  /// AppDelegate already calls `registerForRemoteNotifications()`
  /// unconditionally on launch), so token setup and message handling
  /// proceed regardless of permission state. The OS permission dialog is
  /// requested exactly once in this whole app, contextually, through
  /// NotificationService.ensurePermission() (Settings reminder toggles /
  /// goal reminders) - granting it there also makes push alerts visible,
  /// since local and push notifications share one OS permission.
  Future<void> initialize(ApiService apiService) async {
    if (_isInitialized) return;

    _apiService = apiService;

    try {
      // Set up background handler
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Token fetch/registration is isolated in its own try/catch (see
      // _registerTokenIfAvailable's doc comment) - its failure must not
      // abort the message listener setup below.
      await _registerTokenIfAvailable();

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('🔔 FCM Token refreshed: $newToken');
        _fcmToken = newToken;
        await _registerTokenWithServer(newToken);
      });

      // Set up local notifications for foreground messages. Channel/plugin
      // setup only (requestAlertPermission etc. are false below) - display
      // is silently suppressed by the OS until permission is granted.
      await _setupLocalNotifications();

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification tap when app is in background/terminated
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Check if app was opened from a notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      _isInitialized = true;
      debugPrint('🔔 Push notification service initialized');
    } catch (e) {
      debugPrint('🔔 Error initializing push notifications: $e');
    }
  }

  /// Fetches and registers the FCM token, tolerating failure without
  /// aborting the rest of initialize() (message listeners, local-notification
  /// setup still need to run either way).
  ///
  /// On iOS, `getToken()` can throw ("No APNS token specified") if called
  /// before the async APNs handshake completes - AppDelegate.swift's
  /// unconditional `registerForRemoteNotifications()` call kicks that off,
  /// but doesn't block on it, so briefly wait for the APNs token first.
  Future<void> _registerTokenIfAvailable() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _waitForApnsToken();
      }

      _fcmToken = await _messaging.getToken();
      debugPrint('🔔 FCM Token: $_fcmToken');

      if (_fcmToken != null) {
        await _registerTokenWithServer(_fcmToken!);
      }
    } catch (e) {
      debugPrint(
        '🔔 Could not fetch/register FCM token yet (will retry on next '
        'token refresh or app open): $e',
      );
    }
  }

  /// Polls briefly for the APNs token to become available. A harmless no-op
  /// once it's already set; gives up after ~3s rather than waiting forever.
  Future<void> _waitForApnsToken() async {
    for (var i = 0; i < 6; i++) {
      if (await _messaging.getAPNSToken() != null) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Set up local notifications for showing foreground messages
  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            onNotificationTapped?.call(data);
          } catch (e) {
            debugPrint('🔔 Error parsing notification payload: $e');
          }
        }
      },
    );

    // Create notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      'messages_channel',
      'Messages',
      description: 'Notifications for new messages',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('🔔 Foreground message: ${message.notification?.title}');

    // Notify listeners
    onMessageReceived?.call(message);

    // Show local notification
    final notification = message.notification;
    if (notification != null) {
      _showLocalNotification(
        title: notification.title ?? 'New Message',
        body: notification.body ?? '',
        payload: jsonEncode(message.data),
      );
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('🔔 Notification tapped: ${message.data}');
    onNotificationTapped?.call(message.data);
  }

  /// Show a local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'messages_channel',
      'Messages',
      channelDescription: 'Notifications for new messages',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
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

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Register FCM token with backend
  Future<void> _registerTokenWithServer(String token) async {
    if (_apiService == null) return;

    try {
      await _apiService!.post(
        '${ApiConfig.users}/fcm-token',
        data: {'token': token},
      );
      debugPrint('🔔 FCM token registered with server');
    } catch (e) {
      debugPrint('🔔 Error registering FCM token: $e');
    }
  }

  /// Unregister FCM token (call on logout)
  ///
  /// Deliberately never touches `_messaging`: this is called unconditionally
  /// on logout, unguarded by Firebase availability, and stays safe only
  /// because it doesn't force the `late` `FirebaseMessaging.instance` read.
  /// Keep it that way - a future addition here that reads `_messaging`
  /// would reintroduce the crash-when-unconfigured bug this class guards
  /// against elsewhere.
  Future<void> unregisterToken() async {
    if (_apiService == null || _fcmToken == null) return;

    try {
      await _apiService!.delete(
        '${ApiConfig.users}/fcm-token',
        data: {'token': _fcmToken},
      );
      debugPrint('🔔 FCM token unregistered from server');
    } catch (e) {
      debugPrint('🔔 Error unregistering FCM token: $e');
    }
  }
}
