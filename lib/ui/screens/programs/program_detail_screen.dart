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

class ProgramDetailScreen extends StatefulWidget {
  final int programId;

  const ProgramDetailScreen({super.key, required this.programId});

  @override
  State<ProgramDetailScreen> createState() => _ProgramDetailScreenState();
}

class _ProgramDetailScreenState extends State<ProgramDetailScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  int _selectedWeek = 1;
  bool _showCalendarView = false;
  TabController? _tabController;
  int? _lastTotalWeeks;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadProgram();
  }

  Future<void> _loadProgram() async {
    setState(() => _isLoading = true);
    final provider = context.read<ProgramsProvider>();

    // Force refresh from server to get latest data
    await provider.loadPrograms();

    // Get program from cache (now updated by loadPrograms)
    final program = provider.getProgramFromCache(widget.programId);

    if (program != null && mounted) {
      _initTabController(program);
      setState(() {
        _selectedWeek = program.currentWeek;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _initTabController(Program program) {
    // Only recreate tab controller if total weeks changed
    if (_tabController == null || _lastTotalWeeks != program.totalWeeks) {
      _tabController?.dispose();
      _tabController = TabController(
        length: program.totalWeeks,
        vsync: this,
        initialIndex: program.currentWeek - 1,
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

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Program Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Watch the provider for changes and get program from cache
    final provider = context.watch<ProgramsProvider>();
    final program = provider.getProgramFromCache(widget.programId);

    if (program == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Program Details')),
        body: const Center(child: Text('Program not found')),
      );
    }

    // Initialize tab controller if needed
    _initTabController(program);

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(program.title),
        actions: [
          // Refresh button to reload latest data
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadProgram,
          ),
          // Advance to next workout button
          if (!program.isCompleted &&
              program.currentWorkout != null &&
              program.currentWorkout!.isCompleted)
            IconButton(
              icon: const Icon(Icons.skip_next),
              tooltip: 'Next Workout',
              onPressed: () => _advanceToNextWorkout(program),
            ),
          // Calendar/Week view toggle
          IconButton(
            icon: Icon(
              _showCalendarView ? Icons.view_week : Icons.calendar_month,
            ),
            onPressed: () {
              setState(() {
                _showCalendarView = !_showCalendarView;
              });
            },
            tooltip: _showCalendarView ? 'Week View' : 'Calendar View',
          ),
          if (!program.isCompleted)
            PopupMenuButton<String>(
              onSelected: (value) async {
                // DEBUG: Log menu selection
                debugPrint('🔔 Menu item selected: $value');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Menu selected: $value'),
                    duration: const Duration(seconds: 2),
                  ),
                );

                if (value == 'link_goal') {
                  _showLinkGoalDialog(context, program);
                } else if (value == 'unlink_goal') {
                  _unlinkGoal(context, program);
                } else if (value == 'complete') {
                  _showCompleteConfirmation(context, program);
                } else if (value == 'delete') {
                  debugPrint('🗑️ Calling _showDeleteConfirmation...');
                  _showDeleteConfirmation(context, program);
                }
              },
              itemBuilder:
                  (context) => [
                    if (program.goalId == null)
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
      body: Column(
        children: [
          // Program Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(color: context.border, width: 1),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Week $_selectedWeek of ${program.totalWeeks}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Phase ${program.currentPhase}: ${program.phaseName}',
                            style: TextStyle(
                              fontSize: 14,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${program.progressPercentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                        Text(
                          'Complete',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: program.progressPercentage / 100,
                    minHeight: 10,
                    backgroundColor: context.surfaceElevated,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.primaryColor,
                    ),
                  ),
                ),
                if (program.description != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    program.description!,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (program.goal != null) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => _showGoalDetailSheet(context, program.goal!),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.primaryColor.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag, size: 16, color: theme.primaryColor),
                          const SizedBox(width: 6),
                          Text(
                            'Goal: ${program.goal!.goalType}',
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 10,
                            color: theme.primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Conditional rendering: Calendar View or Week Tabs
          if (_showCalendarView)
            // Calendar View
            Expanded(
              child: ProgramCalendarWidget(
                program: program,
                onDateTapped: (date, workout) {
                  if (workout != null && !workout.isRestDay) {
                    // Navigate to workout detail screen to show details first
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
            // Week Tabs
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

            // Workouts List
            Expanded(
              child:
                  program.workouts == null || program.workouts!.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.fitness_center,
                              size: 64,
                              color: context.textTertiary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No workouts in this program yet',
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                      : TabBarView(
                        controller: _tabController,
                        children: List.generate(program.totalWeeks, (
                          weekIndex,
                        ) {
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
      ),
    );
  }

  /// Strip day prefix from workout name for display
  String _getCleanWorkoutName(String workoutName) {
    final colonIndex = workoutName.indexOf(':');
    if (colonIndex != -1 && colonIndex < 15) {
      return workoutName.substring(colonIndex + 1).trim();
    }
    return workoutName;
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

  /// Advance to next workout in the program
  Future<void> _advanceToNextWorkout(Program program) async {
    final provider = context.read<ProgramsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final success = await provider.advanceProgram(program.id);

    if (success && mounted) {
      await _loadProgram(); // Reload to show new current position

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Advanced to next workout'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else if (!success && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            provider.errorMessage ?? 'Failed to advance to next workout',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isCurrentWorkout ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side:
            isCurrentWorkout
                ? BorderSide(color: theme.primaryColor, width: 2)
                : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Navigate to workout detail screen to show details first
          Navigator.pushNamed(
            context,
            RouteNames.programWorkout,
            arguments: {'workoutId': workout.id, 'programId': program.id},
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Day Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
                    child: Text(
                      workout.dayNameFromNumber.substring(0, 3),
                      style: TextStyle(
                        color:
                            isCurrentWorkout || workout.isCompleted || isMissed
                                ? Colors.white
                                : context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getCleanWorkoutName(workout.workoutName),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        if (workout.workoutType != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            workout.workoutType!,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (workout.isCompleted)
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 24,
                    )
                  else if (isCurrentWorkout)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'TODAY',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'MISSED',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              if (workout.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  workout.description!,
                  style: TextStyle(color: context.textSecondary, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (workout.estimatedDuration != null) ...[
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: context.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${workout.estimatedDuration} min',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Icon(
                    Icons.fitness_center,
                    size: 16,
                    color: context.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${workout.exerciseCount} exercises',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (workout.isRestDay) ...[
                    const SizedBox(width: 16),
                    Icon(Icons.hotel, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Rest Day',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
                    Navigator.pop(context);
                  }
                },
                child: const Text('Complete'),
              ),
            ],
          ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Program program) async {
    debugPrint(
      '🗑️ Delete program requested: ${program.id} - ${program.title}',
    );
    final provider = context.read<ProgramsProvider>();

    // Show loading dialog with message
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
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
      debugPrint('📡 Fetching deletion impact for program ${program.id}...');
      final impact = await provider.getDeletionImpact(program.id);
      debugPrint('✅ Deletion impact: $impact');

      // Show success message briefly
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impact: ${impact['sessionsCount']} sessions'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Show confirmation with impact
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('⚠️ Delete Program?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to delete "${program.title}"?',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if ((impact['sessionsCount'] ?? 0) > 0) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'This will permanently delete:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• ${impact['sessionsCount'] ?? 0} Workout Session(s) with all exercises and sets',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.red,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This action cannot be undone!',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
      );

      if (confirmed == true && context.mounted) {
        final success = await provider.deleteProgram(program.id);
        if (success && context.mounted) {
          // Reload both sessions and programs to remove deleted items from cache
          await Future.wait([
            context.read<SessionsProvider>().loadSessions(waitForSync: true),
            context.read<ProgramsProvider>().loadPrograms(),
          ]);

          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Program deleted')));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching deletion impact: $e');
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Show error dialog instead of snackbar for better visibility
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('❌ Error'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Failed to fetch deletion impact:'),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
    }
  }

  void _showLinkGoalDialog(BuildContext context, Program program) async {
    // Load goals if not already loaded
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

    // Create updated program with new goalId
    final updatedProgram = Program(
      id: program.id,
      userId: program.userId,
      title: program.title,
      description: program.description,
      goalId: goalId, // Link to goal
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Program linked to goal')));
      await _loadProgram(); // Reload to show updated goal
    }
  }

  Future<void> _unlinkGoal(BuildContext context, Program program) async {
    final provider = context.read<ProgramsProvider>();

    // Create updated program with null goalId
    final updatedProgram = Program(
      id: program.id,
      userId: program.userId,
      title: program.title,
      description: program.description,
      goalId: null, // Unlink from goal
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

    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.updateProgram(program.id, updatedProgram);

    if (success && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Program unlinked from goal')),
      );
      await _loadProgram(); // Reload to show changes
    }
  }

  void _showGoalDetailSheet(BuildContext context, goal) {
    final theme = Theme.of(context);
    final progress = (goal.progressPercentage / 100).clamp(0.0, 1.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Goal type header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.flag, color: theme.primaryColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goal.goalType,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            goal.isCompleted ? 'Completed' : 'In Progress',
                            style: TextStyle(
                              color:
                                  goal.isCompleted
                                      ? Colors.green
                                      : context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Progress bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Progress',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${goal.progressPercentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: context.border,
                        valueColor: AlwaysStoppedAnimation(theme.primaryColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Stats row
                Row(
                  children: [
                    Expanded(
                      child: _buildGoalStat(
                        context,
                        'Current',
                        '${goal.currentValue.toStringAsFixed(1)} ${goal.unit ?? ''}',
                      ),
                    ),
                    Expanded(
                      child: _buildGoalStat(
                        context,
                        'Target',
                        '${goal.targetValue.toStringAsFixed(1)} ${goal.unit ?? ''}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // View in Goals button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.read<TabNavigationService>().switchTab(1);
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View in Goals'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  Widget _buildGoalStat(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.surfaceHighlight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
