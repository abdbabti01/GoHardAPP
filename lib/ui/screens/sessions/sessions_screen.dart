import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/exercises_provider.dart';
import '../../../providers/active_workout_provider.dart';
import '../../../routes/route_names.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/tab_navigation_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../widgets/sessions/session_card.dart';
import '../../widgets/sessions/workout_name_dialog.dart';
import '../../widgets/sessions/workout_options_sheet.dart';
import '../../widgets/sessions/weekly_progress_card.dart';
import '../../widgets/common/offline_banner.dart';
import '../../widgets/common/active_workout_banner.dart';
import '../programs/programs_screen.dart';

/// Sessions screen with tabs for My Workouts and Programs
class SessionsScreen extends StatefulWidget {
  final int? initialTab;

  const SessionsScreen({super.key, this.initialTab});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _pastWorkoutsFilter = 'Last Month'; // Filter for past workouts

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab ?? 0,
    );
    // Listen to tab changes to update FAB
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // Rebuild to update FAB
      }
    });
    // Load sessions and exercise templates on first build (for offline caching)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionsProvider>().loadSessions();
      // Trigger exercise templates to load and cache for offline use
      context.read<ExercisesProvider>().loadExercises();

      // Listen to TabNavigationService for dynamic sub-tab switching
      final tabNavService = context.read<TabNavigationService>();
      tabNavService.addListener(_handleSubTabChange);
    });
  }

  void _handleSubTabChange() {
    final tabNavService = context.read<TabNavigationService>();
    // Only respond if we're on the Workouts tab (index 0) and subTab is specified
    if (tabNavService.currentTab == 0 &&
        tabNavService.currentSubTab != null &&
        _tabController.index != tabNavService.currentSubTab) {
      _tabController.animateTo(tabNavService.currentSubTab!);
    }
  }

  @override
  void dispose() {
    // Remove listener from TabNavigationService
    final tabNavService = context.read<TabNavigationService>();
    tabNavService.removeListener(_handleSubTabChange);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    // Trigger manual sync first (will upload pending changes)
    try {
      await context.read<SyncService>().sync();
    } catch (e) {
      debugPrint('Sync failed during refresh: $e');
    }

    // Then reload sessions from local DB (which now includes synced data)
    if (mounted) {
      await context.read<SessionsProvider>().loadSessions();
    }
  }

  Future<void> _handleStartNewWorkout() async {
    // Show dialog to select workout name
    final workoutName = await _showWorkoutNameDialog();

    if (workoutName == null || !mounted) return; // User cancelled or unmounted

    final provider = context.read<SessionsProvider>();
    final session = await provider.startNewWorkout(name: workoutName);

    if (session != null && mounted) {
      // Navigate to active workout screen and reload sessions when returning
      await Navigator.of(
        context,
      ).pushNamed(RouteNames.activeWorkout, arguments: session.id);

      // Reload sessions to reflect any status changes
      if (mounted) {
        await provider.loadSessions();
      }
    }
  }

  Future<String?> _showWorkoutNameDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => const WorkoutNameDialog(),
    );
  }

  Future<void> _handleDeleteSession(int sessionId) async {
    final sessionsProvider = context.read<SessionsProvider>();
    final activeWorkoutProvider = context.read<ActiveWorkoutProvider>();

    // Check if the session being deleted is the current active workout
    if (activeWorkoutProvider.currentSession?.id == sessionId) {
      // Clear the active workout provider to remove the timer bar
      activeWorkoutProvider.clear();
    }

    // Try to delete the session
    final success = await sessionsProvider.deleteSession(sessionId);

    if (!success && mounted) {
      // Check if error indicates this is a completed program workout
      if (sessionsProvider.errorMessage?.contains('Archive it instead') ==
          true) {
        // Show dialog offering to archive instead
        final shouldArchive = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Cannot Delete'),
                content: const Text(
                  'This is a completed program workout. Deleting it would mark the workout as "Missed" in your program.\n\nWould you like to archive it instead? It will be hidden from this list but will still count as completed in your program.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Archive'),
                  ),
                ],
              ),
        );

        if (shouldArchive == true && mounted) {
          // Archive the session
          final archived = await sessionsProvider.archiveSession(sessionId);
          if (archived && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Workout archived successfully'),
                backgroundColor: Colors.green,
              ),
            );
            // Reload without sync to avoid server overwriting archived status
            await sessionsProvider.loadSessions(showLoading: false);
          }
        }
      } else {
        // Show generic error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                sessionsProvider.errorMessage ?? 'Failed to delete session',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      // Clear error after showing it
      sessionsProvider.clearError();
    } else {
      // Deletion succeeded - reload to refresh UI
      if (mounted) {
        await sessionsProvider.loadSessions(showLoading: false);
      }
    }
  }

  Future<void> _handlePlanWorkout() async {
    final result = await Navigator.of(
      context,
    ).pushNamed(RouteNames.planWorkout);

    // Reload sessions if workout was created
    if (result == true && mounted) {
      await context.read<SessionsProvider>().loadSessions();
    }
  }

  void _showWorkoutOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => WorkoutOptionsSheet(
            onStartNow: () {
              Navigator.pop(context);
              _handleStartNewWorkout();
            },
            onPlanLater: () {
              Navigator.pop(context);
              _handlePlanWorkout();
            },
          ),
    );
  }

  Future<void> _handleSessionTap(int sessionId, String status) async {
    if (status == 'planned') {
      final provider = context.read<SessionsProvider>();
      final session = provider.sessions.firstWhere((s) => s.id == sessionId);

      // Check if workout is scheduled for a future date
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final workoutDate = DateTime(
        session.date.year,
        session.date.month,
        session.date.day,
      );
      final isScheduledForFuture = workoutDate.isAfter(today);

      // Show appropriate confirmation dialog
      final shouldStart =
          isScheduledForFuture
              ? await _showStartFuturePlannedWorkoutDialog(workoutDate)
              : await _showStartPlannedWorkoutDialog();

      if (shouldStart == true && mounted) {
        // If workout is in the future, update its date to today first
        if (isScheduledForFuture) {
          await provider.updateWorkoutDate(sessionId, DateTime.now());
        }

        // Start the planned workout (change status to in_progress)
        final success = await provider.startPlannedWorkout(sessionId);

        if (success && mounted) {
          // Navigate to active workout screen
          await Navigator.of(
            context,
          ).pushNamed(RouteNames.activeWorkout, arguments: sessionId);

          // Reload sessions to reflect any status changes
          if (mounted) {
            await provider.loadSessions();
          }
        }
      }
    } else if (status == 'in_progress' || status == 'draft') {
      // Navigate to active workout screen for in-progress/draft sessions
      await Navigator.of(
        context,
      ).pushNamed(RouteNames.activeWorkout, arguments: sessionId);

      // Reload sessions to reflect any status changes
      if (mounted) {
        await context.read<SessionsProvider>().loadSessions();
      }
    } else {
      // Navigate to detail screen for completed sessions
      Navigator.of(
        context,
      ).pushNamed(RouteNames.sessionDetail, arguments: sessionId);
    }
  }

  Future<bool?> _showStartPlannedWorkoutDialog() async {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Start Workout'),
            content: const Text(
              'Do you want to start this planned workout now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Start'),
              ),
            ],
          ),
    );
  }

  Future<bool?> _showStartFuturePlannedWorkoutDialog(
    DateTime scheduledDate,
  ) async {
    // Format the date nicely
    final dateStr =
        '${_getMonthName(scheduledDate.month)} ${scheduledDate.day}';
    final daysDiff = scheduledDate.difference(DateTime.now()).inDays;
    final whenStr = daysDiff == 1 ? 'tomorrow' : 'on $dateStr';

    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Start Early?'),
            content: Text(
              'This workout is scheduled for $whenStr. Do you want to start it today instead?\n\nThe workout date will be updated to today.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Start Today'),
              ),
            ],
          ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month];
  }

  /// Get number of days for past workouts filter
  int _getFilterDays(String filter) {
    switch (filter) {
      case 'Last Week':
        return 7;
      case 'Last Month':
        return 30;
      case 'Last 3 Months':
        return 90;
      case 'Last 6 Months':
        return 180;
      case 'Last 12 Months':
        return 365;
      default:
        return 30; // Default to last month
    }
  }

  /// Build week header widget
  Widget _buildWeekHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  /// Build past workouts filter dropdown
  Widget _buildPastWorkoutsFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'Past Workouts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: DropdownButton<String>(
              value: _pastWorkoutsFilter,
              underline: const SizedBox(),
              isDense: true,
              icon: Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.primary,
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
              items: const [
                DropdownMenuItem(value: 'Last Week', child: Text('Last Week')),
                DropdownMenuItem(
                  value: 'Last Month',
                  child: Text('Last Month'),
                ),
                DropdownMenuItem(
                  value: 'Last 3 Months',
                  child: Text('Last 3 Months'),
                ),
                DropdownMenuItem(
                  value: 'Last 6 Months',
                  child: Text('Last 6 Months'),
                ),
                DropdownMenuItem(
                  value: 'Last 12 Months',
                  child: Text('Last 12 Months'),
                ),
              ],
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _pastWorkoutsFilter = newValue;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build section header widget
  Widget _buildSectionHeader(String label, IconData icon, int? count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workouts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () {
              Navigator.pushNamed(context, RouteNames.community);
            },
            tooltip: 'Community',
          ),
          IconButton(
            icon: const Icon(Icons.bookmark),
            onPressed: () {
              Navigator.pushNamed(context, RouteNames.templates);
            },
            tooltip: 'Templates',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [Tab(text: 'My Workouts'), Tab(text: 'Programs')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // My Workouts tab
          Column(
            children: [
              const ActiveWorkoutBanner(),
              const OfflineBanner(),
              Expanded(
                child: Consumer<SessionsProvider>(
                  builder: (context, provider, child) {
                    // Loading state
                    if (provider.isLoading && provider.sessions.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // Error state
                    if (provider.errorMessage != null &&
                        provider.errorMessage!.isNotEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error Loading Workouts',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              child: Text(
                                provider.errorMessage!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _handleRefresh,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }

                    // Empty state
                    if (provider.sessions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.fitness_center,
                              size: 80,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Workouts Yet',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 48,
                              ),
                              child: Text(
                                'Start your first workout by tapping the + button below',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Organize sessions by time period
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final weekStart = today.subtract(
                      Duration(days: today.weekday - 1),
                    );

                    // Group sessions
                    // Today: includes today's workouts + ALL in-progress workouts (even if scheduled for future)
                    final todaySessions =
                        provider.sessions
                            .where(
                              (s) =>
                                  (s.status != 'planned' &&
                                      DateTime(
                                            s.date.year,
                                            s.date.month,
                                            s.date.day,
                                          ) ==
                                          today) ||
                                  s.status ==
                                      'in_progress', // Show all active workouts
                            )
                            .toList();

                    // ALL sessions for this week (for progress card) - includes planned, in-progress, completed, draft
                    final allThisWeekSessions =
                        provider.sessions
                            .where(
                              (s) =>
                                  s.date.isAfter(
                                    weekStart.subtract(const Duration(days: 1)),
                                  ) &&
                                  s.date.isBefore(
                                    weekStart.add(const Duration(days: 7)),
                                  ), // Monday through Sunday (this week only)
                            )
                            .toList();

                    // ALL sessions for this month (for progress card)
                    final monthStart = DateTime(now.year, now.month, 1);
                    final monthEnd = DateTime(now.year, now.month + 1, 1);
                    final allThisMonthSessions =
                        provider.sessions
                            .where(
                              (s) =>
                                  s.date.isAfter(
                                    monthStart.subtract(
                                      const Duration(days: 1),
                                    ),
                                  ) &&
                                  s.date.isBefore(monthEnd),
                            )
                            .toList();

                    // This Week: workouts from Monday to yesterday (not today, not before this week)
                    final thisWeekSessions =
                        provider.sessions
                            .where(
                              (s) =>
                                  s.status != 'planned' &&
                                  s.status != 'in_progress' &&
                                  !s.date.isBefore(
                                    weekStart,
                                  ) && // After/equal Monday
                                  DateTime(
                                        s.date.year,
                                        s.date.month,
                                        s.date.day,
                                      ) !=
                                      today, // Not today
                            )
                            .toList();

                    // Upcoming/Planned Workouts: all planned workouts in the future (NOT today)
                    final upcomingSessions =
                        provider.sessions
                            .where(
                              (s) =>
                                  s.status == 'planned' &&
                                  DateTime(
                                    s.date.year,
                                    s.date.month,
                                    s.date.day,
                                  ).isAfter(today), // Future only (not today)
                            )
                            .toList()
                          ..sort((a, b) => a.date.compareTo(b.date));

                    // Calculate date range for past workouts filter
                    final filterDays = _getFilterDays(_pastWorkoutsFilter);
                    final filterCutoff = today.subtract(
                      Duration(days: filterDays),
                    );

                    // Past sessions: before this week AND within filter range
                    final pastSessions =
                        provider.sessions
                            .where(
                              (s) =>
                                  s.status != 'planned' &&
                                  s.status != 'in_progress' &&
                                  s.date.isBefore(
                                    weekStart,
                                  ) && // Before this week
                                  s.date.isAfter(
                                    filterCutoff.subtract(
                                      const Duration(days: 1),
                                    ),
                                  ), // Within filter range
                            )
                            .toList();

                    // Group past sessions by week
                    final groupedPast = DateGroupingUtils.groupSessionsByWeek(
                      pastSessions,
                    );
                    final pastWeekLabels =
                        DateGroupingUtils.getOrderedWeekLabels(groupedPast);

                    return RefreshIndicator(
                      onRefresh: _handleRefresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 80),
                        children: [
                          // Weekly/Monthly Progress Card
                          if (allThisWeekSessions.isNotEmpty ||
                              allThisMonthSessions.isNotEmpty)
                            WeeklyProgressCard(
                              thisWeekSessions: allThisWeekSessions,
                              thisMonthSessions: allThisMonthSessions,
                            ),

                          // Today Section
                          if (todaySessions.isNotEmpty) ...[
                            _buildSectionHeader('Today', Icons.today, null),
                            ...todaySessions.map(
                              (session) => SessionCard(
                                session: session,
                                onTap:
                                    () => _handleSessionTap(
                                      session.id,
                                      session.status,
                                    ),
                                onDelete:
                                    () => _handleDeleteSession(session.id),
                              ),
                            ),
                          ],

                          // This Week Section (Monday to yesterday)
                          if (thisWeekSessions.isNotEmpty) ...[
                            _buildSectionHeader(
                              'This Week',
                              Icons.calendar_today,
                              null,
                            ),
                            ...thisWeekSessions.map(
                              (session) => SessionCard(
                                session: session,
                                onTap:
                                    () => _handleSessionTap(
                                      session.id,
                                      session.status,
                                    ),
                                onDelete:
                                    () => _handleDeleteSession(session.id),
                              ),
                            ),
                          ],

                          // Upcoming Workouts Section (Planned workouts)
                          if (upcomingSessions.isNotEmpty) ...[
                            _buildSectionHeader(
                              'Upcoming Workouts',
                              Icons.schedule,
                              upcomingSessions.length,
                            ),
                            ...upcomingSessions.map(
                              (session) => SessionCard(
                                session: session,
                                onTap:
                                    () => _handleSessionTap(
                                      session.id,
                                      session.status,
                                    ),
                                onDelete:
                                    () => _handleDeleteSession(session.id),
                              ),
                            ),
                          ],

                          // Past Sessions with Filter
                          if (pastSessions.isNotEmpty) ...[
                            _buildPastWorkoutsFilter(),
                            for (final label in pastWeekLabels) ...[
                              _buildWeekHeader(label),
                              ...groupedPast[label]!.map(
                                (session) => SessionCard(
                                  session: session,
                                  onTap:
                                      () => _handleSessionTap(
                                        session.id,
                                        session.status,
                                      ),
                                  onDelete:
                                      () => _handleDeleteSession(session.id),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          // Programs tab
          const ProgramsScreen(),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildFloatingActionButton() {
    final isMyWorkoutsTab = _tabController.index == 0;
    final buttonText = isMyWorkoutsTab ? 'New Workout' : 'Create Program';
    final buttonIcon = isMyWorkoutsTab ? Icons.fitness_center : Icons.add;
    final onTap =
        isMyWorkoutsTab ? _showWorkoutOptionsSheet : _showCreateProgramOptions;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  buttonIcon,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  buttonText,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateProgramOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Create New Program',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // AI-Generated Option
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.purple),
                  ),
                  title: const Text(
                    'Create with AI',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Let AI generate a personalized program',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, RouteNames.workoutPlanForm);
                  },
                ),
                const SizedBox(height: 12),

                // Manual Creation Option
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit, color: Colors.blue),
                  ),
                  title: const Text(
                    'Create Manually',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Build your own custom program'),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navigate to manual program creation screen
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Manual program creation coming soon!'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }
}
