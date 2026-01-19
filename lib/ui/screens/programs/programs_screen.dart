import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/goals_provider.dart';
import '../../../core/services/tab_navigation_service.dart';
import '../../../routes/route_names.dart';
import '../../widgets/programs/program_calendar_widget.dart';
import '../../widgets/programs/premium_program_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/premium_bottom_sheet.dart';

/// Programs screen that shows program detail directly with selector
class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen>
    with SingleTickerProviderStateMixin {
  int? _selectedProgramId;
  int _selectedWeek = 1;
  bool _showCalendarView = false;
  TabController? _tabController;
  int? _lastTotalWeeks;

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
        // Clear the ID after selection
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
        _initTabController(programToSelect);
      }
    }
  }

  void _initTabController(Program program) {
    if (_tabController == null || _lastTotalWeeks != program.totalWeeks) {
      _tabController?.dispose();
      _tabController = TabController(
        length: program.totalWeeks,
        vsync: this,
        initialIndex: (program.currentWeek - 1).clamp(
          0,
          program.totalWeeks - 1,
        ),
      );
      _tabController!.addListener(() {
        if (!_tabController!.indexIsChanging) {
          setState(() {
            _selectedWeek = _tabController!.index + 1;
          });
        }
      });
      _lastTotalWeeks = program.totalWeeks;
    }
  }

  void _selectProgram(Program program) {
    setState(() {
      _selectedProgramId = program.id;
      _selectedWeek = program.currentWeek;
      _lastTotalWeeks = null; // Force tab controller rebuild
    });
    _initTabController(program);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
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

        // Initialize tab controller
        _initTabController(program);

        return RefreshIndicator(
          onRefresh: () => provider.loadPrograms(),
          child: Column(
            children: [
              // Program Selector
              _buildProgramSelector(context, provider, program),

              // Program Detail Content
              Expanded(child: _buildProgramDetail(context, program, provider)),
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

  Widget _buildProgramSelector(
    BuildContext context,
    ProgramsProvider provider,
    Program selectedProgram,
  ) {
    final theme = Theme.of(context);
    final activePrograms = provider.activePrograms;
    final completedPrograms = provider.completedPrograms;
    final hasMultiplePrograms =
        activePrograms.length + completedPrograms.length > 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Program dropdown/selector row
          Row(
            children: [
              Expanded(
                child:
                    hasMultiplePrograms
                        ? _buildProgramDropdown(
                          context,
                          provider,
                          selectedProgram,
                          theme,
                        )
                        : Text(
                          selectedProgram.title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
              ),
              const SizedBox(width: 8),
              // Calendar toggle
              IconButton(
                icon: Icon(
                  _showCalendarView ? Icons.view_week : Icons.calendar_month,
                  color: theme.primaryColor,
                ),
                onPressed: () {
                  setState(() => _showCalendarView = !_showCalendarView);
                },
                tooltip: _showCalendarView ? 'Week View' : 'Calendar View',
              ),
              // Menu
              if (!selectedProgram.isCompleted)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: context.textSecondary),
                  onSelected:
                      (value) => _handleMenuAction(value, selectedProgram),
                  itemBuilder:
                      (context) => [
                        if (selectedProgram.goalId == null)
                          const PopupMenuItem(
                            value: 'link_goal',
                            child: Row(
                              children: [
                                Icon(Icons.link),
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
                                Icon(Icons.link_off),
                                SizedBox(width: 12),
                                Text('Unlink from Goal'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'complete',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline),
                              SizedBox(width: 12),
                              Text('Mark as Complete'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: Colors.red),
                              SizedBox(width: 12),
                              Text(
                                'Delete Program',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgramDropdown(
    BuildContext context,
    ProgramsProvider provider,
    Program selectedProgram,
    ThemeData theme,
  ) {
    final activePrograms = provider.activePrograms;
    final completedPrograms = provider.completedPrograms;

    return PopupMenuButton<int>(
      offset: const Offset(0, 40),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selectedProgram.isCompleted
                  ? Icons.check_circle
                  : Icons.fitness_center,
              size: 20,
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
            Icon(Icons.arrow_drop_down, color: theme.primaryColor),
          ],
        ),
      ),
      itemBuilder:
          (context) => [
            if (activePrograms.isNotEmpty) ...[
              const PopupMenuItem(
                enabled: false,
                height: 32,
                child: Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...activePrograms.map(
                (p) => PopupMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      Icon(
                        Icons.fitness_center,
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
            if (completedPrograms.isNotEmpty) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                height: 32,
                child: Text(
                  'COMPLETED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...completedPrograms.map(
                (p) => PopupMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: Colors.green),
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

  Widget _buildProgramDetail(
    BuildContext context,
    Program program,
    ProgramsProvider provider,
  ) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Header with progress
        _buildProgramHeader(context, program, theme),

        // Calendar or Week tabs view
        if (_showCalendarView)
          Expanded(
            child: ProgramCalendarWidget(
              program: program,
              onDateTapped: (date, workout) {
                if (workout != null && !workout.isRestDay) {
                  Navigator.pushNamed(
                    context,
                    RouteNames.programWorkout,
                    arguments: {
                      'workoutId': workout.id,
                      'programId': program.id,
                    },
                  );
                }
              },
            ),
          )
        else ...[
          // Week tabs
          if (program.workouts != null && program.workouts!.isNotEmpty)
            TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: theme.primaryColor,
              labelColor: theme.primaryColor,
              unselectedLabelColor: context.textSecondary,
              tabs: List.generate(
                program.totalWeeks,
                (index) => Tab(text: 'Week ${index + 1}'),
              ),
            ),

          // Workouts list
          Expanded(
            child:
                program.workouts == null || program.workouts!.isEmpty
                    ? _buildNoWorkoutsState()
                    : TabBarView(
                      controller: _tabController,
                      children: List.generate(program.totalWeeks, (weekIndex) {
                        final weekNumber = weekIndex + 1;
                        final weekWorkouts =
                            program.workouts!
                                .where((w) => w.weekNumber == weekNumber)
                                .toList()
                              ..sort(
                                (a, b) => a.dayNumber.compareTo(b.dayNumber),
                              );

                        return _buildWeekView(context, weekWorkouts, program);
                      }),
                    ),
          ),
        ],
      ],
    );
  }

  Widget _buildProgramHeader(
    BuildContext context,
    Program program,
    ThemeData theme,
  ) {
    final phaseColor = _getPhaseColor(program.phaseName);
    final progress = program.progressPercentage / 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [context.surface, phaseColor.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Column(
        children: [
          // Progress row with ring
          Row(
            children: [
              // Progress ring
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 6,
                      backgroundColor: phaseColor.withValues(alpha: 0.12),
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
                        style: AppTypography.statSmall.copyWith(
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 20),
              // Week info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: phaseColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Phase ${program.currentPhase}: ${program.phaseName}',
                        style: AppTypography.labelMedium.copyWith(
                          color: phaseColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Week $_selectedWeek of ${program.totalWeeks}',
                      style: AppTypography.titleLarge.copyWith(
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${program.completedWorkoutsCount}/${program.totalWorkoutsCount} workouts completed',
                      style: AppTypography.cardMeta.copyWith(
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Goal badge
          if (program.goal != null) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: () {
                context.read<TabNavigationService>().switchTab(1);
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentSky.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.accentSky.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flag_rounded,
                      size: 16,
                      color: AppColors.accentSky,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Goal: ${program.goal!.goalType}',
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.accentSky,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: AppColors.accentSky,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Completed badge
          if (program.isCompleted) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
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
                  const Icon(Icons.emoji_events, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Program Completed!',
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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

  Widget _buildNoWorkoutsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fitness_center, size: 64, color: context.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No workouts in this program yet',
            style: TextStyle(color: context.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekView(
    BuildContext context,
    List<ProgramWorkout> weekWorkouts,
    Program program,
  ) {
    if (weekWorkouts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.self_improvement, size: 64, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Rest week - Recovery time!',
              style: TextStyle(color: context.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: weekWorkouts.length,
      itemBuilder: (context, index) {
        final workout = weekWorkouts[index];
        return _buildWorkoutCard(context, workout, program);
      },
    );
  }

  Widget _buildWorkoutCard(
    BuildContext context,
    ProgramWorkout workout,
    Program program,
  ) {
    final isCurrentWorkout = program.isCurrentWorkout(workout);
    final isMissed = program.isWorkoutMissed(workout);

    return PremiumWorkoutCard(
      workout: workout,
      isToday: isCurrentWorkout,
      isMissed: isMissed,
      onTap: () {
        Navigator.pushNamed(
          context,
          RouteNames.programWorkout,
          arguments: {'workoutId': workout.id, 'programId': program.id},
        );
      },
    );
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
          // Select another program
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
