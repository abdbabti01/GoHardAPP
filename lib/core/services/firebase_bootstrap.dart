import 'package:flutter/foundation.dart';

import 'firebase_availability.dart';

/// Attempts Firebase initialization through an injectable [initializer]
/// and never lets a failure escape.
///
/// Android currently ships without a `google-services.json` or a
/// generated `firebase_options.dart`, and its Google Services Gradle
/// plugin is disabled, so `Firebase.initializeApp()` is expected to throw
/// there today. Startup - and, independently, the FCM background-message
/// isolate in `push_notification_service.dart` - must continue regardless
/// of the outcome, so callers treat the returned bool as "is it safe to
/// use Firebase-backed features now" rather than "did startup succeed".
///
/// [initializer] is injected so tests can exercise both outcomes
/// deterministically without touching real Firebase; production call
/// sites pass `Firebase.initializeApp`.
Future<bool> initializeFirebaseSafely(
  Future<void> Function() initializer,
) async {
  try {
    await initializer();
    return true;
  } catch (error) {
    // Sanitized on purpose: never log the underlying exception object,
    // since a misconfiguration error can carry request/config details.
    if (kDebugMode) {
      debugPrint(
        'Firebase unavailable (${error.runtimeType}); continuing without it.',
      );
    }
    return false;
  }
}

/// Runs the Firebase-aware startup sequence: attempts Firebase
/// initialization via [initializer] (through [initializeFirebaseSafely], so
/// only a Firebase-initialization failure is ever caught here), then
/// unconditionally invokes [continuation] exactly once with the resulting
/// [FirebaseAvailability] - regardless of whether Firebase succeeded.
///
/// This is the seam `main()` calls directly, not a test-only duplicate:
/// [continuation] carries the entire remainder of app startup (local
/// database, other services, provider construction, and `runApp()`), so a
/// test can inject a spy continuation and assert it runs exactly once with
/// the right availability, on both outcomes, without touching real
/// Firebase or any platform service.
///
/// A failure thrown by [continuation] itself is deliberately NOT caught
/// here - it propagates normally, so a bug in database/service/provider
/// initialization or in `runApp()` is never mistaken for "Firebase
/// unavailable" and never silently swallowed.
Future<void> runFirebaseAwareStartup({
  required Future<void> Function() initializer,
  required Future<void> Function(FirebaseAvailability availability)
  continuation,
}) async {
  final available = await initializeFirebaseSafely(initializer);
  await continuation(FirebaseAvailability(available));
}
