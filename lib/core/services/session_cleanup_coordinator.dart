import 'package:flutter/foundation.dart';

import '../../providers/active_workout_provider.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/achievements_provider.dart';
import '../../providers/body_metrics_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/friends_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/log_sets_provider.dart';
import '../../providers/messages_provider.dart';
import '../../providers/nutrition_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/programs_provider.dart';
import '../../providers/running_provider.dart';
import '../../providers/sessions_provider.dart';
import '../../providers/shared_workout_provider.dart';
import '../../providers/workout_template_provider.dart';
import 'notification_service.dart';

/// Centralizes the active-resource teardown and settled-state clearing that
/// must happen on every logout, regardless of which trigger (manual button,
/// 401/session-expiry) fired it.
///
/// Plain class, not a [ChangeNotifier] - it owns explicit typed references
/// only to the Providers/services it clears, and has a single [cleanUp]
/// entry point. It is wired into [AuthProvider] via a settable callback
/// (`AuthProvider.onSessionEnding`), mirroring the existing
/// `ApiService.onUnauthorized` callback pattern already used in this
/// codebase - this keeps `AuthProvider` from having to depend on 15+
/// feature Providers directly, and keeps this coordinator from depending on
/// `AuthProvider` at all, so neither side can form a circular dependency.
///
/// Scope (Logout PR 1 only): stops live background work (GPS, timers,
/// polling, the Isar session watcher) and clears already-settled in-memory
/// Provider state. It does NOT protect against an in-flight load `Future`
/// that is still awaiting a repository call when logout begins later
/// re-populating a cleared Provider once it resolves - per-Provider
/// generation/staleness guards for that are deferred to Logout PR 2 and are
/// deliberately not attempted here, EXCEPT for the two Providers that
/// already carry it: `RunningProvider` (from the earlier GPS
/// subscription-lifecycle hardening, which this coordinator relies on by
/// awaiting `RunningProvider.clear()` first) and `LogSetsProvider` (from
/// the log-sets session-cleanup PR: its `clear()` invalidates a
/// session/request-generation guard so an in-flight `loadSets` or set
/// mutation cannot repopulate the cleared list). This coordinator only
/// invokes their `clear()`; it does not add that protection anywhere else.
///
/// Deliberately excludes `ExercisesProvider`: its exercise-template library
/// is shared, unauthenticated reference content
/// (`ExerciseRepository.getExerciseTemplates()` takes no user identity and
/// is not scoped to the current user) rather than per-account data -
/// clearing it on logout would only force a wasted re-fetch of the same
/// shared catalog for the next session, exactly the kind of device-wide,
/// non-user-specific state this PR is told to preserve (the same reasoning
/// `ProfileProvider.clear()` already applies to the user's theme
/// preference).
class SessionCleanupCoordinator {
  SessionCleanupCoordinator({
    required RunningProvider runningProvider,
    required ActiveWorkoutProvider activeWorkoutProvider,
    required SessionsProvider sessionsProvider,
    required MessagesProvider messagesProvider,
    required NutritionProvider nutritionProvider,
    required GoalsProvider goalsProvider,
    required LogSetsProvider logSetsProvider,
    required ChatProvider chatProvider,
    required ProfileProvider profileProvider,
    required BodyMetricsProvider bodyMetricsProvider,
    required AnalyticsProvider analyticsProvider,
    required AchievementsProvider achievementsProvider,
    required FriendsProvider friendsProvider,
    required ProgramsProvider programsProvider,
    required WorkoutTemplateProvider workoutTemplateProvider,
    required SharedWorkoutProvider sharedWorkoutProvider,
    required NotificationService notificationService,
  }) : _runningProvider = runningProvider,
       _activeWorkoutProvider = activeWorkoutProvider,
       _sessionsProvider = sessionsProvider,
       _messagesProvider = messagesProvider,
       _nutritionProvider = nutritionProvider,
       _goalsProvider = goalsProvider,
       _logSetsProvider = logSetsProvider,
       _chatProvider = chatProvider,
       _profileProvider = profileProvider,
       _bodyMetricsProvider = bodyMetricsProvider,
       _analyticsProvider = analyticsProvider,
       _achievementsProvider = achievementsProvider,
       _friendsProvider = friendsProvider,
       _programsProvider = programsProvider,
       _workoutTemplateProvider = workoutTemplateProvider,
       _sharedWorkoutProvider = sharedWorkoutProvider,
       _notificationService = notificationService;

  final RunningProvider _runningProvider;
  final ActiveWorkoutProvider _activeWorkoutProvider;
  final SessionsProvider _sessionsProvider;
  final MessagesProvider _messagesProvider;
  final NutritionProvider _nutritionProvider;
  final GoalsProvider _goalsProvider;
  final LogSetsProvider _logSetsProvider;
  final ChatProvider _chatProvider;
  final ProfileProvider _profileProvider;
  final BodyMetricsProvider _bodyMetricsProvider;
  final AnalyticsProvider _analyticsProvider;
  final AchievementsProvider _achievementsProvider;
  final FriendsProvider _friendsProvider;
  final ProgramsProvider _programsProvider;
  final WorkoutTemplateProvider _workoutTemplateProvider;
  final SharedWorkoutProvider _sharedWorkoutProvider;
  final NotificationService _notificationService;

  // The in-flight cleanup Future, if any. A concurrent caller (e.g. a 401
  // arriving while a manual logout is already running cleanUp()) awaits
  // this SAME future instead of starting a second cleanup pass - this is
  // what guarantees cleanup runs exactly once under concurrency, not just
  // under sequential repeated calls. Cleared once the pass completes
  // (success or failure), so a later authenticated session's own eventual
  // logout can trigger a fresh pass.
  Future<void>? _inFlight;

  /// True while a cleanup pass is running. Exposed for tests/diagnostics.
  bool get isCleaning => _inFlight != null;

  /// Stops every currently-reachable active resource and clears every
  /// currently-clearable Provider's settled in-memory state, in the order
  /// required for logout privacy/safety:
  ///
  /// 1. [RunningProvider] first, awaited - invalidates GPS callbacks
  ///    synchronously and awaits native subscription cancellation, which is
  ///    what stops the Android foreground notification/wake lock and iOS
  ///    background delivery, before anything else runs.
  /// 2. [ActiveWorkoutProvider]'s ticker.
  /// 3. [SessionsProvider]'s Isar session watcher.
  /// 4. [MessagesProvider]'s polling timers.
  /// 5. Every other currently-clearable Provider's settled state.
  /// 6. [NotificationService], last - still before the caller (AuthProvider)
  ///    proceeds to remove credentials or clear Isar.
  ///
  /// Safe to call concurrently or repeatedly: every caller after the first
  /// awaits the same in-flight Future rather than re-running cleanup.
  ///
  /// Individually best-effort per operation: a single Provider's clear()
  /// throwing is caught and logged here and does not prevent any later
  /// step from running - callers still proceed to remove credentials and
  /// clear Isar regardless of what happened here.
  Future<void> cleanUp() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final future = _runCleanUp();
    _inFlight = future;
    return future.whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _runCleanUp() async {
    await _guard('RunningProvider', _runningProvider.clear);

    await _guard(
      'ActiveWorkoutProvider',
      () async => _activeWorkoutProvider.clear(),
    );

    await _guard('SessionsProvider', () async => _sessionsProvider.clear());

    await _guard('MessagesProvider', () async => _messagesProvider.clear());

    await _guard('NutritionProvider', () async => _nutritionProvider.clear());
    await _guard('GoalsProvider', () async => _goalsProvider.clear());
    await _guard('LogSetsProvider', () async => _logSetsProvider.clear());
    await _guard('ChatProvider', () async => _chatProvider.clear());
    await _guard('ProfileProvider', () async => _profileProvider.clear());
    await _guard(
      'BodyMetricsProvider',
      () async => _bodyMetricsProvider.clear(),
    );
    await _guard('AnalyticsProvider', () async => _analyticsProvider.clear());
    await _guard(
      'AchievementsProvider',
      () async => _achievementsProvider.reset(),
    );
    await _guard('FriendsProvider', () async => _friendsProvider.clear());
    await _guard('ProgramsProvider', () async => _programsProvider.clear());
    await _guard(
      'WorkoutTemplateProvider',
      () async => _workoutTemplateProvider.clear(),
    );
    await _guard(
      'SharedWorkoutProvider',
      () async => _sharedWorkoutProvider.clear(),
    );

    await _guard('NotificationService', _notificationService.cancelAll);
  }

  Future<void> _guard(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (e, stackTrace) {
      debugPrint('⚠️ SessionCleanupCoordinator: $label cleanup failed: $e');
      debugPrintStack(
        stackTrace: stackTrace,
        label: 'SessionCleanupCoordinator/$label',
      );
    }
  }
}
