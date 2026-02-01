import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/services/tab_navigation_service.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../providers/programs_provider.dart';
import '../../../routes/route_names.dart';
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
      // Check if day changed and refresh data if needed
      context.read<NutritionProvider>().checkAndRefreshIfDayChanged();
      // Also refresh sessions to update "today's workouts"
      context.read<SessionsProvider>().loadSessions(showLoading: false);
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

        // Nutrition stats
        final calories = nutritionProvider.todaysMealLog?.totalCalories ?? 0;
        final calorieGoal = nutritionProvider.activeGoal?.dailyCalories ?? 2000;

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
                value: (calorieGoal - calories).toStringAsFixed(0),
                label: 'Calories\nremaining',
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
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day);

        // Separate in-progress workouts from today's scheduled workouts
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

        // Filter out program workouts that already have sessions or are completed
        final todaysProgramWorkouts =
            allTodaysProgramWorkouts
                .where(
                  (item) =>
                      !item.workout.isCompleted &&
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
                            arguments: session.id,
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

              // Empty state
              if (!hasWorkouts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_available,
                          size: 40,
                          color: context.textTertiary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No workouts scheduled',
                          style: TextStyle(color: context.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/plan-workout');
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Plan Workout'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNutritionSummary(BuildContext context) {
    return Consumer<NutritionProvider>(
      builder: (context, provider, child) {
        final consumed = provider.todaysMealLog?.totalCalories ?? 0;
        final goal = provider.activeGoal?.dailyCalories ?? 2000;
        final percentage = (consumed / goal * 100).clamp(0, 100);

        final protein = provider.todaysMealLog?.totalProtein ?? 0;
        final carbs = provider.todaysMealLog?.totalCarbohydrates ?? 0;
        final fat = provider.todaysMealLog?.totalFat ?? 0;

        final proteinGoal = provider.activeGoal?.dailyProtein ?? 150;
        final carbsGoal = provider.activeGoal?.dailyCarbohydrates ?? 200;
        final fatGoal = provider.activeGoal?.dailyFat ?? 65;

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
                      '${consumed.toStringAsFixed(0)} / ${goal.toStringAsFixed(0)} kcal',
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
                const SizedBox(height: 16),
                // Calorie progress bar
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
                // Macro bars
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
                          'Yesterday: ${provider.nutritionHistory.isNotEmpty ? provider.nutritionHistory.first.totalCalories.toStringAsFixed(0) : 0} kcal',
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
    final percentage = (current / goal * 100).clamp(0, 100);

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
