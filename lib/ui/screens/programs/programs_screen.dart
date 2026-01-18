import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/goals_provider.dart';
import '../../../core/services/tab_navigation_service.dart';
import '../../../routes/route_names.dart';
import '../../widgets/programs/program_calendar_widget.dart';

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
      // Auto-select first active program, or first completed if no active
      final defaultProgram =
          provider.activePrograms.isNotEmpty
              ? provider.activePrograms.first
              : provider.completedPrograms.isNotEmpty
              ? provider.completedPrograms.first
              : null;

      if (defaultProgram != null) {
        setState(() {
          _selectedProgramId = defaultProgram.id;
          _selectedWeek = defaultProgram.currentWeek;
        });
        _initTabController(defaultProgram);
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
          return const Center(child: CircularProgressIndicator());
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fitness_center, size: 80, color: context.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No Programs Yet',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: context.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a goal and generate\na workout plan to get started!',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textSecondary, fontSize: 16),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.04),
        border: Border(bottom: BorderSide(color: context.border, width: 0.5)),
      ),
      child: Column(
        children: [
          // Progress row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Week $_selectedWeek of ${program.totalWeeks}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Phase ${program.currentPhase}: ${program.phaseName}',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${program.progressPercentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryColor,
                    ),
                  ),
                  Text(
                    'Complete',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: program.progressPercentage / 100,
              minHeight: 8,
              backgroundColor: context.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(
                program.isCompleted ? context.success : theme.primaryColor,
              ),
            ),
          ),

          // Goal badge
          if (program.goal != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                context.read<TabNavigationService>().switchTab(1);
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag, size: 14, color: theme.primaryColor),
                    const SizedBox(width: 5),
                    Text(
                      'Goal: ${program.goal!.goalType}',
                      style: TextStyle(
                        color: theme.primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 9,
                      color: theme.primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Completed badge
          if (program.isCompleted) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.celebration, size: 16, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    'Program Completed!',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (program.completedAt != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${program.completedAt!.month}/${program.completedAt!.day}/${program.completedAt!.year}',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
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

  String _getCleanWorkoutName(String workoutName) {
    final colonIndex = workoutName.indexOf(':');
    if (colonIndex != -1 && colonIndex < 15) {
      return workoutName.substring(colonIndex + 1).trim();
    }
    return workoutName;
  }

  Widget _buildWorkoutCard(
    BuildContext context,
    ProgramWorkout workout,
    Program program,
  ) {
    final theme = Theme.of(context);
    final isCurrentWorkout = program.isCurrentWorkout(workout);
    final isMissed = program.isWorkoutMissed(workout);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isCurrentWorkout ? 2 : 0,
      shadowColor: theme.primaryColor.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            isCurrentWorkout
                ? BorderSide(color: theme.primaryColor, width: 1.5)
                : BorderSide(color: context.border, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.pushNamed(
            context,
            RouteNames.programWorkout,
            arguments: {'workoutId': workout.id, 'programId': program.id},
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Day badge
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color:
                      isCurrentWorkout
                          ? theme.primaryColor
                          : workout.isCompleted
                          ? Colors.green
                          : isMissed
                          ? Colors.orange
                          : context.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      workout.dayNameFromNumber.substring(0, 3),
                      style: TextStyle(
                        color:
                            isCurrentWorkout || workout.isCompleted || isMissed
                                ? Colors.white
                                : context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
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
                    Text(
                      _getCleanWorkoutName(workout.workoutName),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (workout.estimatedDuration != null) ...[
                          Icon(
                            Icons.access_time,
                            size: 13,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${workout.estimatedDuration} min',
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Icon(
                          Icons.fitness_center,
                          size: 13,
                          color: context.textTertiary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${workout.exerciseCount} exercises',
                          style: TextStyle(
                            color: context.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                        if (workout.isRestDay) ...[
                          const SizedBox(width: 10),
                          Icon(
                            Icons.hotel,
                            size: 13,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Rest',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Status indicator
              if (workout.isCompleted)
                const Icon(Icons.check_circle, color: Colors.green, size: 22)
              else if (isCurrentWorkout)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'TODAY',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (isMissed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'MISSED',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right, color: context.textTertiary),
            ],
          ),
        ),
      ),
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Checking deletion impact...'),
              ],
            ),
          ),
    );

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
