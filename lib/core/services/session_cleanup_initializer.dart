import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/active_workout_provider.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/achievements_provider.dart';
import '../../providers/auth_provider.dart';
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
import '../../routes/route_names.dart';
import 'notification_service.dart';
import 'session_cleanup_coordinator.dart';

/// Widget that wires [AuthProvider.onSessionEnding] to a fresh
/// [SessionCleanupCoordinator] and [AuthProvider.onLoggedOut] to the single
/// centralized logout-navigation trigger, once per authenticated session.
///
/// Mirrors [SyncServiceInitializer]'s existing reactive shape (watches
/// `authProvider.isAuthenticated`) rather than wiring eagerly at app
/// startup: constructing the coordinator touches (lazily creates, via
/// `context.read`) every Provider it clears, and at least one of them
/// (`MessagesProvider`) starts a live polling `Timer` the instant it is
/// first created - doing that before any login would start network polling
/// with no auth token yet. Waiting for `isAuthenticated` to flip true keeps
/// that first-creation moment no earlier than it already effectively is via
/// normal navigation to the authenticated screens.
///
/// Must be positioned below every Provider it reads (same requirement as
/// [SyncServiceInitializer]) so each is available as an ancestor regardless
/// of main.dart's internal MultiProvider declaration order.
class SessionCleanupInitializer extends StatefulWidget {
  const SessionCleanupInitializer({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// The app's global navigator key (also passed to `MaterialApp`). Using a
  /// key rather than a captured `BuildContext` means a logout that
  /// completes after this widget (or the navigator) is gone simply no-ops
  /// (`currentState` is null) instead of touching a disposed context.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  State<SessionCleanupInitializer> createState() =>
      _SessionCleanupInitializerState();
}

class _SessionCleanupInitializerState extends State<SessionCleanupInitializer> {
  // True once the current authenticated session's coordinator+hooks are
  // wired. Reset back to false from inside onLoggedOut itself (not via a
  // rebuild) so the very next authenticated session gets a brand new
  // SessionCleanupCoordinator instance - with its own fresh in-flight
  // guard - rather than reusing one whose bookkeeping belonged to the
  // session that just ended.
  bool _wired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final authProvider = context.watch<AuthProvider>();

    if (!authProvider.isAuthenticated || _wired) return;
    _wired = true;

    final coordinator = SessionCleanupCoordinator(
      runningProvider: context.read<RunningProvider>(),
      activeWorkoutProvider: context.read<ActiveWorkoutProvider>(),
      sessionsProvider: context.read<SessionsProvider>(),
      messagesProvider: context.read<MessagesProvider>(),
      nutritionProvider: context.read<NutritionProvider>(),
      goalsProvider: context.read<GoalsProvider>(),
      logSetsProvider: context.read<LogSetsProvider>(),
      chatProvider: context.read<ChatProvider>(),
      profileProvider: context.read<ProfileProvider>(),
      bodyMetricsProvider: context.read<BodyMetricsProvider>(),
      analyticsProvider: context.read<AnalyticsProvider>(),
      achievementsProvider: context.read<AchievementsProvider>(),
      friendsProvider: context.read<FriendsProvider>(),
      programsProvider: context.read<ProgramsProvider>(),
      workoutTemplateProvider: context.read<WorkoutTemplateProvider>(),
      sharedWorkoutProvider: context.read<SharedWorkoutProvider>(),
      notificationService: context.read<NotificationService>(),
    );

    authProvider.onSessionEnding = coordinator.cleanUp;
    authProvider.onLoggedOut = () {
      widget.navigatorKey.currentState?.pushNamedAndRemoveUntil(
        RouteNames.login,
        (route) => false,
      );
      _wired = false;
    };
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
