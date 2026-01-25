import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/constants/colors.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/exercises_provider.dart';
import '../../../providers/active_workout_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/sessions/session_card.dart';
import '../../widgets/common/offline_banner.dart';
import '../../widgets/common/active_workout_banner.dart';
import '../../widgets/common/loading_indicator.dart';
import '../programs/programs_screen.dart';
import '../exercises/exercises_screen.dart';

/// Train screen with tabs for Workouts, Programs, and Exercises
class TrainScreen extends StatefulWidget {
  final int? initialTab;

  const TrainScreen({super.key, this.initialTab});

  @override
  State<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends State<TrainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _pastWorkoutsFilter = 'Last Month';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab ?? 0,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionsProvider>().loadSessions();
      context.read<ExercisesProvider>().loadExercises();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    try {
      await context.read<SyncService>().sync();
    } catch (e) {
      debugPrint('Sync failed during refresh: $e');
    }
    if (mounted) {
      await context.read<SessionsProvider>().loadSessions();
    }
  }

  Future<void> _handleDeleteSession(int sessionId) async {
    final sessionsProvider = context.read<SessionsProvider>();
    final activeWorkoutProvider = context.read<ActiveWorkoutProvider>();

    if (activeWorkoutProvider.currentSession?.id == sessionId) {
      activeWorkoutProvider.clear();
    }

    final success = await sessionsProvider.deleteSession(sessionId);

    if (!success && mounted) {
      if (sessionsProvider.errorMessage?.contains('Archive it instead') ==
          true) {
        final shouldArchive = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Cannot Delete'),
                content: const Text(
                  'This is a completed program workout. Would you like to archive it instead?',
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
          final archived = await sessionsProvider.archiveSession(sessionId);
          if (archived && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Workout archived successfully'),
                backgroundColor: context.success,
              ),
            );
            await sessionsProvider.loadSessions(showLoading: false);
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                sessionsProvider.errorMessage ?? 'Failed to delete',
              ),
              backgroundColor: context.error,
            ),
          );
        }
      }
      sessionsProvider.clearError();
    } else {
      if (mounted) {
        await sessionsProvider.loadSessions(showLoading: false);
      }
    }
  }

  Future<void> _handleSessionTap(int sessionId, String status) async {
    if (status == 'planned') {
      final provider = context.read<SessionsProvider>();
      final session = provider.sessions.firstWhere((s) => s.id == sessionId);

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

      final shouldStart = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(
                isScheduledForFuture ? 'Start Early?' : 'Start Workout',
              ),
              content: Text(
                isScheduledForFuture
                    ? 'This workout is scheduled for later. Start it today?'
                    : 'Do you want to start this planned workout now?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(isScheduledForFuture ? 'Start Today' : 'Start'),
                ),
              ],
            ),
      );

      if (shouldStart == true && mounted) {
        if (isScheduledForFuture) {
          await provider.updateWorkoutDate(sessionId, DateTime.now());
        }
        final success = await provider.startPlannedWorkout(sessionId);
        if (success && mounted) {
          await Navigator.of(
            context,
          ).pushNamed(RouteNames.activeWorkout, arguments: sessionId);
          if (mounted) await provider.loadSessions();
        }
      }
    } else if (status == 'in_progress' || status == 'draft') {
      await Navigator.of(
        context,
      ).pushNamed(RouteNames.activeWorkout, arguments: sessionId);
      if (mounted) await context.read<SessionsProvider>().loadSessions();
    } else {
      Navigator.of(
        context,
      ).pushNamed(RouteNames.sessionDetail, arguments: sessionId);
    }
  }

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
        return 30;
    }
  }

  Widget _buildWeekHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: context.accent.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPastWorkoutsFilter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(Icons.history, size: 20, color: context.accent),
          const SizedBox(width: 8),
          Text(
            'Past Workouts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.accent,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: context.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
            ),
            child: DropdownButton<String>(
              value: _pastWorkoutsFilter,
              underline: const SizedBox(),
              isDense: true,
              dropdownColor: context.surfaceElevated,
              icon: Icon(Icons.arrow_drop_down, color: context.accent),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.accent,
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
                  setState(() => _pastWorkoutsFilter = newValue);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String label,
    IconData icon,
    int? count,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: context.accent),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: context.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.goHardBlack,
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
    return Column(
      children: [
        // Tab bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: context.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(4),
            labelColor: context.textOnPrimary,
            unselectedLabelColor: context.textSecondary,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Workouts'),
              Tab(text: 'Programs'),
              Tab(text: 'Exercises'),
            ],
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Workouts tab
              _buildWorkoutsTab(),
              // Programs tab
              const ProgramsScreen(),
              // Exercises tab
              const ExercisesScreen(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutsTab() {
    return Column(
      children: [
        const ActiveWorkoutBanner(),
        const OfflineBanner(),
        Expanded(
          child: Consumer<SessionsProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading && provider.sessions.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.only(top: 16),
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      height: 140,
                      child: SkeletonLoader(
                        width: double.infinity,
                        height: 140,
                        borderRadius: 20,
                      ),
                    ),
                    for (int i = 0; i < 4; i++) const SkeletonCard(),
                  ],
                );
              }

              if (provider.errorMessage != null &&
                  provider.errorMessage!.isNotEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 64,
                        color: AppColors.errorRed,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error Loading Workouts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        provider.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _handleRefresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              if (provider.sessions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.fitness_center_rounded,
                        size: 64,
                        color: context.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Workouts Yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start your first workout!',
                        style: TextStyle(color: context.textSecondary),
                      ),
                    ],
                  ),
                );
              }

              // Organize sessions
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final weekStart = today.subtract(
                Duration(days: today.weekday - 1),
              );

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
                            s.status == 'in_progress',
                      )
                      .toList();

              final thisWeekSessions =
                  provider.sessions
                      .where(
                        (s) =>
                            s.status != 'planned' &&
                            s.status != 'in_progress' &&
                            !s.date.isBefore(weekStart) &&
                            DateTime(s.date.year, s.date.month, s.date.day) !=
                                today,
                      )
                      .toList();

              final upcomingSessions =
                  provider.sessions
                      .where(
                        (s) =>
                            s.status == 'planned' &&
                            DateTime(
                              s.date.year,
                              s.date.month,
                              s.date.day,
                            ).isAfter(today),
                      )
                      .toList()
                    ..sort((a, b) => a.date.compareTo(b.date));

              final filterDays = _getFilterDays(_pastWorkoutsFilter);
              final filterCutoff = today.subtract(Duration(days: filterDays));
              final pastSessions =
                  provider.sessions
                      .where(
                        (s) =>
                            s.status != 'planned' &&
                            s.status != 'in_progress' &&
                            s.date.isBefore(weekStart) &&
                            s.date.isAfter(
                              filterCutoff.subtract(const Duration(days: 1)),
                            ),
                      )
                      .toList();

              final groupedPast = DateGroupingUtils.groupSessionsByWeek(
                pastSessions,
              );
              final pastWeekLabels = DateGroupingUtils.getOrderedWeekLabels(
                groupedPast,
              );

              return RefreshIndicator(
                onRefresh: _handleRefresh,
                color: context.accent,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 80),
                  children: [
                    if (todaySessions.isNotEmpty) ...[
                      _buildSectionHeader(context, 'Today', Icons.today, null),
                      ...todaySessions.map(
                        (s) => SessionCard(
                          session: s,
                          onTap: () => _handleSessionTap(s.id, s.status),
                          onDelete: () => _handleDeleteSession(s.id),
                        ),
                      ),
                    ],
                    if (thisWeekSessions.isNotEmpty) ...[
                      _buildSectionHeader(
                        context,
                        'This Week',
                        Icons.calendar_today,
                        null,
                      ),
                      ...thisWeekSessions.map(
                        (s) => SessionCard(
                          session: s,
                          onTap: () => _handleSessionTap(s.id, s.status),
                          onDelete: () => _handleDeleteSession(s.id),
                        ),
                      ),
                    ],
                    if (upcomingSessions.isNotEmpty) ...[
                      _buildSectionHeader(
                        context,
                        'Upcoming',
                        Icons.schedule,
                        upcomingSessions.length,
                      ),
                      ...upcomingSessions.map(
                        (s) => SessionCard(
                          session: s,
                          onTap: () => _handleSessionTap(s.id, s.status),
                          onDelete: () => _handleDeleteSession(s.id),
                        ),
                      ),
                    ],
                    if (pastSessions.isNotEmpty) ...[
                      _buildPastWorkoutsFilter(context),
                      for (final label in pastWeekLabels) ...[
                        _buildWeekHeader(context, label),
                        ...groupedPast[label]!.map(
                          (s) => SessionCard(
                            session: s,
                            onTap: () => _handleSessionTap(s.id, s.status),
                            onDelete: () => _handleDeleteSession(s.id),
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
    );
  }
}
