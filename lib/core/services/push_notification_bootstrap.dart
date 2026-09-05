import 'package:flutter/foundation.dart';

/// Gates push-notification setup on Firebase availability and performs it
/// via an injectable [attempt] callback.
///
/// Kept separate from `PushNotificationService` so the "should we even
/// try" decision can be tested deterministically - without constructing
/// `PushNotificationService` (whose singleton talks to real
/// `FirebaseMessaging` once Firebase is configured) or touching real
/// Firebase. When [firebaseAvailable] is false, [attempt] is never
/// invoked, so no token retrieval or server registration is attempted.
///
/// A failure from [attempt] is deliberately left to propagate rather than
/// swallowed here - the only current caller (`MainScreen`) already wraps
/// this call in its own try/catch, so this relies on that outer guard
/// staying in place.
Future<void> bootstrapPushNotifications({
  required bool firebaseAvailable,
  required Future<void> Function() attempt,
}) async {
  if (!firebaseAvailable) {
    if (kDebugMode) {
      debugPrint('🔔 Push notifications skipped: Firebase unavailable.');
    }
    return;
  }
  await attempt();
}
