import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/goals_provider.dart';
import '../../../core/services/tab_navigation_service.dart';
import '../../../routes/route_names.dart';
import '../../widgets/programs/premium_week_calendar_widget.dart';
import '../../widgets/programs/program_calendar_widget.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/premium_bottom_sheet.dart';

/// Premium Programs screen with calendar-first design
class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  int? _selectedProgramId;
  int _selectedWeek = 1;
  bool _showMonthView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPrograms();
    });
  }

  Future<void> _loadPrograms() async {
    final provider = context.read<ProgramsProvider>();
    await provider.loadPrograms();

    if (mounted && provider.programs.isNotEmpty) {
      Program? programToSelect;

      // Check if there's a newly created program to auto-select
      if (provider.newlyCreatedProgramId != null) {
        programToSelect = provider.programs.firstWhere(
          (p) => p.id == provider.newlyCreatedProgramId,
          orElse:
              () =>
                  provider.activePrograms.isNotEmpty
                      ? provider.activePrograms.first
                      : provider.completedPrograms.first,
        );
        provider.clearNewlyCreatedProgramId();
      } else {
        // Auto-select first active program, or first completed if no active
        programToSelect =
            provider.activePrograms.isNotEmpty
                ? provider.activePrograms.first
                : provider.completedPrograms.isNotEmpty
                ? provider.completedPrograms.first
                : null;
      }

      if (programToSelect != null) {
        setState(() {
          _selectedProgramId = programToSelect!.id;
          _selectedWeek = programToSelect.currentWeek;
        });
      }
    }
  }

  void _selectProgram(Program program) {
    setState(() {
      _selectedProgramId = program.id;
      _selectedWeek = program.currentWeek;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProgramsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.programs.isEmpty) {
          return const Center(child: PremiumLoader());
        }

        if (provider.errorMessage != null && provider.programs.isEmpty) {
          return _buildErrorState(provider);
        }

        if (provider.programs.isEmpty) {
          return _buildEmptyState();
        }

        // Get selected program
        final program =
            provider.getProgramFromCache(_selectedProgramId ?? 0) ??
            (provider.activePrograms.isNotEmpty
                ? provider.activePrograms.first
                : provider.completedPrograms.first);

        // Update selection if needed
        if (_selectedProgramId != program.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _selectProgram(program);
          });
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadPrograms(),
          color: Theme.of(context).primaryColor,
          child: CustomScrollView(
            slivers: [
              // Program Header
              SliverToBoxAdapter(
                child: _buildProgramHeader(context, provider, program),
              ),

              // Calendar or Month View
              SliverToBoxAdapter(
                child:
                    _showMonthView
                        ? _buildMonthCalendar(context, program)
                        : _buildWeekCalendar(context, program),
              ),

              // Upcoming Workouts Section
              SliverToBoxAdapter(
                child: _buildUpcomingWorkoutsSection(context, program),
              ),

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState(ProgramsProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: context.error),
          const SizedBox(height: 16),
          Text(
            provider.errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.error),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => provider.loadPrograms(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: EmptyState(
          icon: Icons.fitness_center,
          title: 'No Programs Yet',
          message:
              'Create a goal and let AI generate a personalized workout program for you',
          suggestions: [
            QuickSuggestion(
              label: 'Create Goal',
              icon: Icons.flag_outlined,
              onTap: () {
                context.read<TabNavigationService>().switchTab(1);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgramHeader(
    BuildContext context,
    ProgramsProvider provider,
    Program program,
  ) {
    final theme = Theme.of(context);
    final phaseColor = _getPhaseColor(program.phaseName);
    final progress = program.progressPercentage / 100;
    final hasMultiplePrograms =
        provider.activePrograms.length + provider.completedPrograms.length > 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row with program selector and actions
          Row(
            children: [
              Expanded(
                child:
                    hasMultiplePrograms
                        ? _buildProgramSelector(
                          context,
                          provider,
                          program,
                          theme,
                        )
                        : Text(
                          program.title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
              ),
              const SizedBox(width: 12),
              // View toggle
              _buildViewToggle(context, theme),
              const SizedBox(width: 8),
              // Menu
              if (!program.isCompleted) _buildMenuButton(context, program),
            ],
          ),

          const SizedBox(height: 20),

          // Progress Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  phaseColor.withValues(alpha: 0.08),
                  phaseColor.withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: phaseColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                // Progress Ring
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: phaseColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(
                          program.isCompleted
                              ? AppColors.accentGreen
                              : phaseColor,
                        ),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${program.progressPercentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(width: 16),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Phase badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: phaseColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          program.phaseName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: phaseColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${program.completedWorkoutsCount} of ${program.totalWorkoutsCount} workouts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${program.totalWeeks} weeks total',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Completed badge
          if (program.isCompleted) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.successGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentGreen.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Program Completed!',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Goal badge
          if (program.goal != null && !program.isCompleted) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                context.read<TabNavigationService>().switchTab(1);
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentSky.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.accentSky.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flag_rounded,
                      size: 14,
                      color: AppColors.accentSky,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Goal: ${program.goal!.goalType}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentSky,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: AppColors.accentSky,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewToggle(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceHighlight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            context,
            Icons.calendar_view_week_rounded,
            !_showMonthView,
            () => setState(() => _showMonthView = false),
          ),
          _buildToggleButton(
            context,
            Icons.calendar_month_rounded,
            _showMonthView,
            () => setState(() => _showMonthView = true),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(
    BuildContext context,
    IconData icon,
    bool isActive,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? theme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isActive ? Colors.white : context.textSecondary,
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, Program program) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: context.textSecondary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) => _handleMenuAction(value, program),
      itemBuilder:
          (context) => [
            if (program.goalId == null)
              const PopupMenuItem(
                value: 'link_goal',
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Link to Goal'),
                  ],
                ),
              )
            else
              const PopupMenuItem(
                value: 'unlink_goal',
                child: Row(
                  children: [
                    Icon(Icons.link_off_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Unlink from Goal'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'complete',
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Mark as Complete'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Delete Program',
                    style: TextStyle(color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
    );
  }

  Widget _buildProgramSelector(
    BuildContext context,
    ProgramsProvider provider,
    Program selectedProgram,
    ThemeData theme,
  ) {
    return PopupMenuButton<int>(
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selectedProgram.isCompleted
                  ? Icons.check_circle_rounded
                  : Icons.fitness_center_rounded,
              size: 18,
              color: theme.primaryColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                selectedProgram.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: theme.primaryColor,
              size: 20,
            ),
          ],
        ),
      ),
      itemBuilder:
          (context) => [
            if (provider.activePrograms.isNotEmpty) ...[
              const PopupMenuItem(
                enabled: false,
                height: 32,
                child: Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...provider.activePrograms.map(
                (p) => PopupMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      Icon(
                        Icons.fitness_center_rounded,
                        size: 18,
                        color:
                            p.id == selectedProgram.id
                                ? theme.primaryColor
                                : context.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p.title,
                          style: TextStyle(
                            fontWeight:
                                p.id == selectedProgram.id
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${p.progressPercentage.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (provider.completedPrograms.isNotEmpty) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                height: 32,
                child: Text(
                  'COMPLETED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...provider.completedPrograms.map(
                (p) => PopupMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p.title,
                          style: TextStyle(
                            fontWeight:
                                p.id == selectedProgram.id
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
      onSelected: (programId) {
        final program = provider.getProgramFromCache(programId);
        if (program != null) {
          _selectProgram(program);
        }
      },
    );
  }

  Widget _buildWeekCalendar(BuildContext context, Program program) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: PremiumWeekCalendarWidget(
        program: program,
        selectedWeek: _selectedWeek,
        onWeekChanged: (week) => setState(() => _selectedWeek = week),
        onWorkoutTap: (workout) {
          if (!workout.isRestDay) {
            Navigator.pushNamed(
              context,
              RouteNames.programWorkout,
              arguments: {'workoutId': workout.id, 'programId': program.id},
            );
          }
        },
        onWorkoutMoved: () async {
          // Refresh program data after workout is moved
          final provider = context.read<ProgramsProvider>();
          await provider.loadPrograms();
          // Ensure UI updates with the latest data
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  Widget _buildMonthCalendar(BuildContext context, Program program) {
    return SizedBox(
      height: 480,
      child: ProgramCalendarWidget(
        program: program,
        onDateTapped: (date, workout) {
          if (workout != null && !workout.isRestDay) {
            Navigator.pushNamed(
              context,
              RouteNames.programWorkout,
              arguments: {'workoutId': workout.id, 'programId': program.id},
            );
          }
        },
      ),
    );
  }

  Widget _buildUpcomingWorkoutsSection(BuildContext context, Program program) {
    final weekWorkouts =
        program.workouts
            ?.where((w) => w.weekNumber == _selectedWeek && !w.isRestDay)
            .toList() ??
        [];
    weekWorkouts.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));

    if (weekWorkouts.isEmpty) {
      return const SizedBox.shrink();
    }

    // Filter to show only incomplete workouts
    final upcomingWorkouts = weekWorkouts.where((w) => !w.isCompleted).toList();

    if (upcomingWorkouts.isEmpty) {
      return _buildAllCompletedCard(context);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Remaining This Week',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${upcomingWorkouts.length} workout${upcomingWorkouts.length != 1 ? 's' : ''}',
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...upcomingWorkouts.map(
            (workout) => _buildWorkoutListItem(context, workout, program),
          ),
        ],
      ),
    );
  }

  Widget _buildAllCompletedCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accentGreen.withValues(alpha: 0.1),
              AppColors.accentGreen.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.accentGreen.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.celebration_rounded,
                color: AppColors.accentGreen,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Week Complete!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'All workouts for this week are done',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutListItem(
    BuildContext context,
    ProgramWorkout workout,
    Program program,
  ) {
    final theme = Theme.of(context);
    final isMissed = program.isWorkoutMissed(workout);
    final isToday =
        workout.weekNumber == program.currentWeek &&
        workout.dayNumber == DateTime.now().weekday;
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          RouteNames.programWorkout,
          arguments: {'workoutId': workout.id, 'programId': program.id},
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isToday
                    ? theme.primaryColor.withValues(alpha: 0.3)
                    : isMissed
                    ? AppColors.accentCoral.withValues(alpha: 0.3)
                    : context.border,
          ),
        ),
        child: Row(
          children: [
            // Day badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    isToday
                        ? theme.primaryColor
                        : isMissed
                        ? AppColors.accentCoral.withValues(alpha: 0.1)
                        : context.surfaceHighlight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayNames[workout.dayNumber - 1],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          isToday
                              ? Colors.white
                              : isMissed
                              ? AppColors.accentCoral
                              : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Workout info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _cleanWorkoutName(workout.workoutName),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isToday)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'TODAY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      if (isMissed && !isToday)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentCoral.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'MISSED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accentCoral,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (workout.exerciseCount > 0) ...[
                        Icon(
                          Icons.format_list_numbered_rounded,
                          size: 14,
                          color: context.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${workout.exerciseCount} exercises',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                      if (workout.estimatedDuration != null) ...[
                        if (workout.exerciseCount > 0)
                          const SizedBox(width: 12),
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: context.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${workout.estimatedDuration} min',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.textTertiary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Color _getPhaseColor(String phase) {
    switch (phase.toLowerCase()) {
      case 'foundation':
        return AppColors.accentSky;
      case 'progressive overload':
        return AppColors.accentCoral;
      case 'peak performance':
        return AppColors.accentGreen;
      default:
        return AppColors.accentSky;
    }
  }

  String _cleanWorkoutName(String name) {
    final colonIndex = name.indexOf(':');
    if (colonIndex != -1 && colonIndex < 15) {
      return name.substring(colonIndex + 1).trim();
    }
    return name;
  }

  void _handleMenuAction(String value, Program program) async {
    if (value == 'link_goal') {
      _showLinkGoalDialog(context, program);
    } else if (value == 'unlink_goal') {
      _unlinkGoal(context, program);
    } else if (value == 'complete') {
      _showCompleteConfirmation(context, program);
    } else if (value == 'delete') {
      _showDeleteConfirmation(context, program);
    }
  }

  void _showCompleteConfirmation(BuildContext context, Program program) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Complete Program?'),
            content: Text(
              'Mark "${program.title}" as completed? You can still view it in your completed programs.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final provider = context.read<ProgramsProvider>();
                  final success = await provider.completeProgram(program.id);
                  if (success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Program completed!')),
                    );
                  }
                },
                child: const Text('Complete'),
              ),
            ],
          ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Program program) async {
    final provider = context.read<ProgramsProvider>();
    final sessionsProvider = context.read<SessionsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    PremiumLoadingDialog.show(context, message: 'Checking deletion impact...');

    try {
      final impact = await provider.getDeletionImpact(program.id);

      if (!mounted) return;
      navigator.pop();

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: this.context,
        builder:
            (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Delete Program?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Are you sure you want to delete "${program.title}"?'),
                  if ((impact['sessionsCount'] ?? 0) > 0) ...[
                    const SizedBox(height: 16),
                    Text(
                      'This will delete ${impact['sessionsCount']} workout session(s).',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
      );

      if (confirmed == true && mounted) {
        final success = await provider.deleteProgram(program.id);
        if (success && mounted) {
          await sessionsProvider.loadSessions(waitForSync: true);
          messenger.showSnackBar(
            const SnackBar(content: Text('Program deleted')),
          );
          _loadPrograms();
        }
      }
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showLinkGoalDialog(BuildContext context, Program program) async {
    final goalsProvider = context.read<GoalsProvider>();
    await goalsProvider.loadGoals();

    if (!context.mounted) return;

    final activeGoals = goalsProvider.activeGoals;

    if (activeGoals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active goals found. Create a goal first!'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Link to Goal'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: activeGoals.length,
                itemBuilder: (context, index) {
                  final goal = activeGoals[index];
                  return ListTile(
                    title: Text(goal.goalType),
                    subtitle: Text(
                      'Target: ${goal.targetValue} ${goal.unit ?? ''}',
                    ),
                    trailing: Text(
                      '${goal.progressPercentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _linkProgramToGoal(program, goal.id);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  Future<void> _linkProgramToGoal(Program program, int goalId) async {
    final provider = context.read<ProgramsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final updatedProgram = Program(
      id: program.id,
      userId: program.userId,
      title: program.title,
      description: program.description,
      goalId: goalId,
      totalWeeks: program.totalWeeks,
      currentWeek: program.currentWeek,
      currentDay: program.currentDay,
      startDate: program.startDate,
      endDate: program.endDate,
      isActive: program.isActive,
      isCompleted: program.isCompleted,
      completedAt: program.completedAt,
      createdAt: program.createdAt,
      programStructure: program.programStructure,
      workouts: program.workouts,
      goal: program.goal,
    );

    final success = await provider.updateProgram(program.id, updatedProgram);

    if (success && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Program linked to goal')),
      );
      await provider.loadPrograms();
    }
  }

  Future<void> _unlinkGoal(BuildContext context, Program program) async {
    final provider = context.read<ProgramsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final updatedProgram = Program(
      id: program.id,
      userId: program.userId,
      title: program.title,
      description: program.description,
      goalId: null,
      totalWeeks: program.totalWeeks,
      currentWeek: program.currentWeek,
      currentDay: program.currentDay,
      startDate: program.startDate,
      endDate: program.endDate,
      isActive: program.isActive,
      isCompleted: program.isCompleted,
      completedAt: program.completedAt,
      createdAt: program.createdAt,
      programStructure: program.programStructure,
      workouts: program.workouts,
      goal: program.goal,
    );

    final success = await provider.updateProgram(program.id, updatedProgram);

    if (success && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Program unlinked from goal')),
      );
      await provider.loadPrograms();
    }
  }
}
