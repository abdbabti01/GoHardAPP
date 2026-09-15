import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/services/tab_navigation_service.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../providers/programs_provider.dart';
import '../../../routes/route_names.dart';
import '../sessions/session_detail_screen.dart';
import '../../widgets/running/running_widget.dart';
import '../../widgets/common/active_workout_banner.dart';

/// Today screen - Home dashboard showing today's summary
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionsProvider>().loadSessions();
      final nutritionProvider = context.read<NutritionProvider>();
      nutritionProvider.loadTodaysData();
      nutritionProvider
          .loadNutritionHistory(); // Load history for yesterday's summary
      context.read<ProgramsProvider>().loadPrograms();
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Schedule a timer to refresh data at midnight when the day changes
  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();

    // Calculate duration until next midnight
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = nextMidnight.difference(now);

    debugPrint(
      '⏰ Scheduling midnight refresh in ${timeUntilMidnight.inMinutes} minutes',
    );

    _midnightTimer = Timer(timeUntilMidnight, () {
      debugPrint('🌙 Midnight reached - refreshing Today screen data');
      if (mounted) {
        // Refresh all data for the new day
        final nutritionProvider = context.read<NutritionProvider>();
        nutritionProvider.loadTodaysData();
        nutritionProvider.loadNutritionHistory();
        context.read<SessionsProvider>().loadSessions(showLoading: false);
        context.read<ProgramsProvider>().loadPrograms();

        // Rebuild to update greeting (Good Evening -> Good Morning)
        setState(() {});

        // Schedule next midnight check
        _scheduleMidnightRefresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check if day changed and refresh nutrition (food totals + targets,
      // loaded together by loadTodaysData) if needed
      context.read<NutritionProvider>().checkAndRefreshIfDayChanged();
      // Also refresh sessions AND program-based workout schedules on every
      // resume (not gated on day-change detection, matching sessions'
      // existing unconditional refresh) - a program can change schedule for
      // reasons other than the calendar day advancing (e.g. edited while
      // backgrounded on another device), and Today's program-derived
      // "today's workouts" must never go stale relative to the sessions list
      // it's rendered alongside.
      context.read<SessionsProvider>().loadSessions(showLoading: false);
      context.read<ProgramsProvider>().loadPrograms();
      // Reschedule midnight timer (in case it fired while app was in background)
      _scheduleMidnightRefresh();
    }
  }

  Future<void> _handleRefresh() async {
    final nutritionProvider = context.read<NutritionProvider>();
    await Future.wait([
      context.read<SessionsProvider>().loadSessions(),
      nutritionProvider.loadTodaysData(),
      nutritionProvider.loadNutritionHistory(),
      context.read<ProgramsProvider>().loadPrograms(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: context.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Active workout banner
            const ActiveWorkoutBanner(),

            // Greeting
            _buildGreeting(context),
            const SizedBox(height: 20),

            // Quick stats row
            _buildQuickStats(context),
            const SizedBox(height: 20),

            // Today's workouts
            _buildTodaysWorkouts(context),
            const SizedBox(height: 20),

            // Running widget
            const RunningWidget(),
            const SizedBox(height: 20),

            // Nutrition summary
            _buildNutritionSummary(context),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildGreeting(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting;
    IconData icon;

    if (hour < 12) {
      greeting = 'Good Morning';
      icon = Icons.wb_sunny_outlined;
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
      icon = Icons.wb_sunny;
    } else {
      greeting = 'Good Evening';
      icon = Icons.nights_stay_outlined;
    }

    return Row(
      children: [
        Icon(icon, color: context.accent, size: 28),
        const SizedBox(width: 12),
        Text(
          greeting,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(BuildContext context) {
    return Consumer2<SessionsProvider, NutritionProvider>(
      builder: (context, sessionsProvider, nutritionProvider, child) {
        // Count this week's workouts
        final now = DateTime.now();
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final thisWeekWorkouts =
            sessionsProvider.sessions
                .where(
                  (s) =>
                      s.status == 'completed' &&
                      s.date.isAfter(
                        weekStart.subtract(const Duration(days: 1)),
                      ),
                )
                .length;

        // Nutrition stats. Actual consumed calories are always real; a
        // "remaining" figure only means anything against a real target, so
        // it is never fabricated from a made-up default goal.
        final calories = nutritionProvider.todaysMealLog?.consumedCalories ?? 0;
        final hasGoal = nutritionProvider.hasActiveGoal;
        final calorieGoal = nutritionProvider.activeGoal?.dailyCalories ?? 0;

        return Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.fitness_center,
                iconColor: Colors.blue,
                value: '$thisWeekWorkouts',
                label: 'Workouts\nthis week',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.local_fire_department,
                iconColor: Colors.orange,
                value: calories.toStringAsFixed(0),
                label: 'Calories\ntoday',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.flag_outlined,
                iconColor: Colors.green,
                value:
                    hasGoal
                        ? (calorieGoal - calories).toStringAsFixed(0)
                        : '--',
                label: hasGoal ? 'Calories\nremaining' : 'No target\nset',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTodaysWorkouts(BuildContext context) {
    return Consumer2<SessionsProvider, ProgramsProvider>(
      builder: (context, sessionsProvider, programsProvider, child) {
        // First-load spinner ONLY - a background/silent refresh
        // (loadSessions(showLoading: false), used on resume/midnight) never
        // sets isLoading, so existing content stays visible during those.
        // This is what stops "rest day"/"nothing scheduled" from ever being
        // asserted before a load has actually completed.
        final isInitialLoading =
            sessionsProvider.isLoading || programsProvider.isLoading;

        if (isInitialLoading &&
            sessionsProvider.sessions.isEmpty &&
            programsProvider.programs.isEmpty) {
          return _buildSectionCard(
            context,
            title: "Today's Workouts",
            icon: Icons.fitness_center,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final hasError =
            sessionsProvider.errorMessage != null ||
            programsProvider.errorMessage != null;

        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);

        // Separate in-progress workouts from today's scheduled workouts.
        // Independent of program lifecycle by construction - filtered only
        // by the session's own status/date, never by its program's
        // active/archived/deleted state, so an in-progress or already-
        // scheduled session stays visible here even after its originating
        // program is archived or deleted.
        final inProgressWorkouts =
            sessionsProvider.sessions
                .where((s) => s.status == 'in_progress')
                .toList();

        final todaysScheduledWorkouts =
            sessionsProvider.sessions.where((s) {
              final sessionDate = DateTime(
                s.date.year,
                s.date.month,
                s.date.day,
              );
              // Only include today's workouts that are NOT in_progress
              // (in_progress are shown separately above)
              return sessionDate == todayStart && s.status != 'in_progress';
            }).toList();

        // Get today's program workouts, excluding those that already have sessions
        final allTodaysProgramWorkouts = programsProvider.getTodaysWorkouts();

        // Get IDs of program workouts that already have sessions
        final sessionProgramWorkoutIds =
            sessionsProvider.sessions
                .where((s) => s.programWorkoutId != null)
                .map((s) => s.programWorkoutId!)
                .toSet();

        // Filter out program workouts that already have sessions, are
        // completed, or were explicitly skipped - skip is a distinct,
        // resolved outcome, not something still "to do" today.
        final todaysProgramWorkouts =
            allTodaysProgramWorkouts
                .where(
                  (item) =>
                      !item.workout.isCompleted &&
                      !item.workout.isSkipped &&
                      !sessionProgramWorkoutIds.contains(item.workout.id),
                )
                .toList();

        final hasWorkouts =
            inProgressWorkouts.isNotEmpty ||
            todaysScheduledWorkouts.isNotEmpty ||
            todaysProgramWorkouts.isNotEmpty;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.fitness_center, color: context.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "Today's Workouts",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Failure banner - shown ABOVE whatever data did load, so a
              // programs-load failure never hides sessions that loaded fine
              // (or vice versa), and always carries a working retry action.
              if (hasError) ...[
                _InlineErrorBanner(
                  message:
                      programsProvider.errorMessage ??
                      sessionsProvider.errorMessage ??
                      'Failed to load today\'s workouts',
                  onRetry: () {
                    sessionsProvider.loadSessions();
                    programsProvider.loadPrograms();
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Continue workout section (in-progress from any date)
              if (inProgressWorkouts.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_circle_filled,
                        size: 14,
                        color: context.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Continue Workout',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...inProgressWorkouts.map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _WorkoutMiniCard(
                      name: session.name ?? 'Workout',
                      status: session.status,
                      exerciseCount: session.exercises.length,
                      scheduledDate: session.date,
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          RouteNames.activeWorkout,
                          arguments: session.id,
                        );
                      },
                    ),
                  ),
                ),
                if (todaysScheduledWorkouts.isNotEmpty)
                  const SizedBox(height: 12),
              ],

              // Today's scheduled workouts section
              if (todaysScheduledWorkouts.isNotEmpty) ...[
                if (inProgressWorkouts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Scheduled for Today',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                ...todaysScheduledWorkouts.map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _WorkoutMiniCard(
                      name: session.name ?? 'Workout',
                      status: session.status,
                      exerciseCount: session.exercises.length,
                      onTap: () {
                        if (session.status == 'draft' ||
                            session.status == 'planned') {
                          Navigator.pushNamed(
                            context,
                            RouteNames.activeWorkout,
                            arguments: session.id,
                          );
                        } else if (session.status == 'completed') {
                          Navigator.pushNamed(
                            context,
                            RouteNames.sessionDetail,
                            arguments: SessionDetailArgs(
                              sessionId: session.id,
                              localId: sessionsProvider.localIdFor(session),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
              ],

              // Program workouts section
              if (todaysProgramWorkouts.isNotEmpty) ...[
                if (inProgressWorkouts.isNotEmpty ||
                    todaysScheduledWorkouts.isNotEmpty)
                  const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.purple,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'From Program',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...todaysProgramWorkouts.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ProgramWorkoutMiniCard(
                      name: item.workout.workoutName,
                      programName: item.program.title,
                      exerciseCount: item.workout.exerciseCount,
                      isCompleted: item.workout.isCompleted,
                      onTap: () async {
                        // Start the workout from program
                        final session = await context
                            .read<SessionsProvider>()
                            .startProgramWorkout(
                              item.workout.id,
                              item.workout,
                              item.program.startDate,
                              item.program.id,
                            );
                        if (session != null && context.mounted) {
                          Navigator.pushNamed(
                            context,
                            RouteNames.activeWorkout,
                            arguments: session.id,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ],

              // Empty state - only asserted once loading has actually
              // finished with no error, and distinguishes a genuine rest
              // day from a program simply having nothing scheduled today
              // (getTodaysWorkouts alone can't tell these apart - see
              // ProgramsProvider.todaysScheduleStatus). With an error, the
              // banner above already explains why data may be incomplete,
              // so no confident "nothing scheduled" claim is made here.
              if (!hasWorkouts && !hasError)
                Builder(
                  builder: (context) {
                    final status = programsProvider.todaysScheduleStatus;
                    final IconData icon;
                    final String message;
                    // allResolved gets no "Plan Workout" CTA - there's nothing
                    // to plan, today's real occurrence(s) are already done.
                    final showPlanCta =
                        status != TodaysScheduleStatus.allResolved;
                    switch (status) {
                      case TodaysScheduleStatus.restDay:
                        icon = Icons.self_improvement;
                        message = 'Rest day - enjoy the recovery';
                        break;
                      case TodaysScheduleStatus.allResolved:
                        icon = Icons.check_circle_outline;
                        message = 'All done for today';
                        break;
                      case TodaysScheduleStatus.noActiveProgram:
                      case TodaysScheduleStatus.notScheduled:
                      case TodaysScheduleStatus.hasWorkouts:
                        icon = Icons.event_available;
                        message = 'No workouts scheduled';
                        break;
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(icon, size: 40, color: context.textTertiary),
                            const SizedBox(height: 8),
                            Text(
                              message,
                              style: TextStyle(color: context.textSecondary),
                            ),
                            if (showPlanCta) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/plan-workout');
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Plan Workout'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Shared card chrome for a Today section, so the loading/error early
  /// returns match the same look as the fully-loaded content.
  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: context.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildNutritionSummary(BuildContext context) {
    return Consumer<NutritionProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.todaysMealLog == null) {
          return _buildSectionCard(
            context,
            title: "Today's Nutrition",
            icon: Icons.restaurant_menu,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (provider.errorMessage != null && provider.todaysMealLog == null) {
          return _buildSectionCard(
            context,
            title: "Today's Nutrition",
            icon: Icons.restaurant_menu,
            child: _InlineErrorBanner(
              message: provider.errorMessage!,
              onRetry: () => provider.loadTodaysData(),
            ),
          );
        }

        final consumed = provider.todaysMealLog?.consumedCalories ?? 0;
        final hasGoal = provider.hasActiveGoal;
        // Actual consumed totals always render, regardless of whether a
        // target exists - only the target-relative bits (goal text,
        // progress bar, percentage) are gated on hasGoal.
        final goal = provider.activeGoal?.dailyCalories ?? 0;
        // Guard goal == 0 the same way NutritionProvider.calorieProgressPercentage
        // does - a zero-calorie goal is not impossible (no positive-value floor
        // on NutritionGoal) and consumed/0 would otherwise produce NaN/Infinity.
        final percentage =
            (hasGoal && goal > 0) ? (consumed / goal * 100).clamp(0, 100) : 0;

        final protein = provider.todaysMealLog?.consumedProtein ?? 0;
        final carbs = provider.todaysMealLog?.consumedCarbohydrates ?? 0;
        final fat = provider.todaysMealLog?.consumedFat ?? 0;

        final proteinGoal = provider.activeGoal?.dailyProtein ?? 0;
        final carbsGoal = provider.activeGoal?.dailyCarbohydrates ?? 0;
        final fatGoal = provider.activeGoal?.dailyFat ?? 0;

        // Check if there's nutrition history
        final hasHistory = provider.nutritionHistory.isNotEmpty;

        return GestureDetector(
          onTap: () {
            // Navigate to Eat tab (index 2) for full nutrition dashboard
            context.read<TabNavigationService>().switchTab(2);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.restaurant_menu, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Today's Nutrition",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      hasGoal
                          ? '${consumed.toStringAsFixed(0)} / ${goal.toStringAsFixed(0)} kcal'
                          : '${consumed.toStringAsFixed(0)} kcal',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: context.textTertiary,
                    ),
                  ],
                ),
                if (!hasGoal) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 12,
                        color: context.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'No target set - showing actual intake only',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                // Calorie progress bar - only meaningful against a real
                // target, never rendered against a fabricated default.
                if (hasGoal) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      minHeight: 10,
                      backgroundColor: context.surfaceHighlight,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percentage >= 100 ? Colors.red : Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Macro bars - same target-dependence as the calorie bar.
                if (hasGoal)
                  Row(
                    children: [
                      Expanded(
                        child: _MacroMini(
                          label: 'Protein',
                          current: protein,
                          goal: proteinGoal,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MacroMini(
                          label: 'Carbs',
                          current: carbs,
                          goal: carbsGoal,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MacroMini(
                          label: 'Fat',
                          current: fat,
                          goal: fatGoal,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _MacroActualOnly(
                          label: 'Protein',
                          value: protein,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MacroActualOnly(
                          label: 'Carbs',
                          value: carbs,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MacroActualOnly(
                          label: 'Fat',
                          value: fat,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                // Yesterday's summary / History link
                if (hasHistory) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceHighlight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history,
                          size: 14,
                          color: context.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Yesterday: ${provider.nutritionHistory.isNotEmpty ? provider.nutritionHistory.first.consumedCalories.toStringAsFixed(0) : 0} kcal',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'View History',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: context.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _WorkoutMiniCard extends StatelessWidget {
  final String name;
  final String status;
  final int exerciseCount;
  final DateTime? scheduledDate;
  final VoidCallback onTap;

  const _WorkoutMiniCard({
    required this.name,
    required this.status,
    required this.exerciseCount,
    this.scheduledDate,
    required this.onTap,
  });

  String _getSubtitle() {
    if (scheduledDate != null) {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final scheduleDay = DateTime(
        scheduledDate!.year,
        scheduledDate!.month,
        scheduledDate!.day,
      );

      if (scheduleDay != todayStart) {
        // Show the scheduled date if it's not today
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        return '$exerciseCount exercises • Scheduled ${months[scheduledDate!.month - 1]} ${scheduledDate!.day}';
      }
    }
    return '$exerciseCount exercises';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'in_progress';
    final isCompleted = status == 'completed';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isActive
                  ? context.accent.withValues(alpha: 0.1)
                  : isCompleted
                  ? Colors.green.withValues(alpha: 0.1)
                  : context.surfaceHighlight,
          borderRadius: BorderRadius.circular(12),
          border:
              isActive
                  ? Border.all(color: context.accent)
                  : isCompleted
                  ? Border.all(color: Colors.green.withValues(alpha: 0.5))
                  : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color:
                    isActive
                        ? context.accent
                        : isCompleted
                        ? Colors.green
                        : context.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isCompleted ? Icons.check : Icons.fitness_center,
                color:
                    (isActive || isCompleted)
                        ? Colors.white
                        : context.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  Text(
                    _getSubtitle(),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              )
            else if (isCompleted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'DONE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right, color: context.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _MacroMini extends StatelessWidget {
  final String label;
  final double current;
  final double goal;
  final Color color;

  const _MacroMini({
    required this.label,
    required this.current,
    required this.goal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // goal == 0 is a real, reachable value (no positive-value floor on
    // NutritionGoal's macro fields) - guard it the same way
    // NutritionProvider's own *ProgressPercentage getters do, rather than
    // letting current/0 produce NaN/Infinity.
    final percentage = goal > 0 ? (current / goal * 100).clamp(0, 100) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: context.textSecondary),
            ),
            Text(
              '${current.toStringAsFixed(0)}g',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: 4,
            backgroundColor: context.surfaceHighlight,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// Actual-consumption-only macro readout for when no target exists yet -
/// no progress bar, since there is nothing real to measure it against.
class _MacroActualOnly extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MacroActualOnly({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: context.textSecondary),
        ),
        Text(
          '${value.toStringAsFixed(0)}g',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Inline, retryable failure notice for a single Today section. Icon +
/// text together (never color alone), and never blocks other sections from
/// rendering their own data.
class _InlineErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: context.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: context.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ProgramWorkoutMiniCard extends StatelessWidget {
  final String name;
  final String programName;
  final int exerciseCount;
  final bool isCompleted;
  final VoidCallback onTap;

  const _ProgramWorkoutMiniCard({
    required this.name,
    required this.programName,
    required this.exerciseCount,
    required this.isCompleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isCompleted
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.purple.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border:
              isCompleted
                  ? Border.all(color: Colors.green.withValues(alpha: 0.5))
                  : Border.all(color: Colors.purple.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCompleted ? Colors.green : Colors.purple,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isCompleted ? Icons.check : Icons.fitness_center,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  Text(
                    '$programName • $exerciseCount exercises',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isCompleted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'DONE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right, color: context.textTertiary),
          ],
        ),
      ),
    );
  }
}
