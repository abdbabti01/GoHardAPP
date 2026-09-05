/// Immutable record of whether Firebase actually initialized for this app
/// process, decided once in `main()` before `runApp()` (see
/// `initializeFirebaseSafely` in `firebase_bootstrap.dart`).
///
/// Handed through the widget tree the same way `UserSessionEpoch` is - a
/// plain app-lifetime value, constructed once, never reactively watched -
/// so any Firebase consumer (push notifications today; other
/// Firebase-backed features later) can check [isAvailable] instead of
/// assuming `Firebase.initializeApp()` succeeded.
class FirebaseAvailability {
  const FirebaseAvailability(this.isAvailable);

  final bool isAvailable;
}
