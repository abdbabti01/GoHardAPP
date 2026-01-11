import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/programs/program_calendar_widget.dart';

class ProgramDetailScreen extends StatefulWidget {
  final int programId;

  const ProgramDetailScreen({super.key, required this.programId});

  @override
  State<ProgramDetailScreen> createState() => _ProgramDetailScreenState();
}

class _ProgramDetailScreenState extends State<ProgramDetailScreen>
    with SingleTickerProviderStateMixin {
  Program? _program;
  bool _isLoading = true;
  int _selectedWeek = 1;
  bool _showCalendarView = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _loadProgram();
  }

  Future<void> _loadProgram() async {
    setState(() => _isLoading = true);
    final provider = context.read<ProgramsProvider>();
    final program = await provider.getProgramById(widget.programId);
    if (program != null && mounted) {
      setState(() {
        _program = program;
        _selectedWeek = program.currentWeek;
        _isLoading = false;
      });
      _tabController = TabController(
        length: program.totalWeeks,
        vsync: this,
        initialIndex: program.currentWeek - 1,
      );
      _tabController.addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() {
            _selectedWeek = _tabController.index + 1;
          });
        }
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    if (_program != null) {
      _tabController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Program Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_program == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Program Details')),
        body: const Center(child: Text('Program not found')),
      );
    }

    final theme = Theme.of(context);
    final program = _program!;

    return Scaffold(
      appBar: AppBar(
        title: Text(program.title),
        actions: [
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
                if (value == 'complete') {
                  _showCompleteConfirmation(context, program);
                } else if (value == 'delete') {
                  _showDeleteConfirmation(context, program);
                }
              },
              itemBuilder:
                  (context) => [
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
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
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
                              color: Colors.grey.shade600,
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
                            color: Colors.grey.shade600,
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
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.primaryColor,
                    ),
                  ),
                ),
                if (program.description != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    program.description!,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                    textAlign: TextAlign.center,
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
                onDateTapped: (date, workout) async {
                  if (workout == null) return;

                  // Don't allow starting rest days
                  if (workout.isRestDay) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Rest day - Recovery is part of the program!',
                        ),
                        backgroundColor: Colors.blue.shade700,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    return;
                  }

                  // Don't allow restarting completed workouts
                  if (workout.isCompleted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('This workout is already completed!'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }

                  // Auto-start the workout
                  final sessionsProvider = context.read<SessionsProvider>();
                  final programsProvider = context.read<ProgramsProvider>();
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);

                  final session = await sessionsProvider.startProgramWorkout(
                    workout.id,
                  );

                  if (session != null && mounted) {
                    // Navigate to active workout screen
                    await navigator.pushNamed(
                      RouteNames.activeWorkout,
                      arguments: session.id,
                    );

                    // When returning, check if session was completed
                    if (mounted) {
                      final completedSession = await sessionsProvider
                          .getSessionById(session.id);

                      if (completedSession.status == 'completed') {
                        // Mark program workout as complete
                        await programsProvider.completeWorkout(workout.id);
                        await programsProvider.advanceProgram(program.id);

                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Workout completed! Program advanced.',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                          // Reload program to reflect changes
                          _loadProgram();
                        }
                      }
                    }
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
                unselectedLabelColor: Colors.grey.shade600,
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
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No workouts in this program yet',
                              style: TextStyle(
                                color: Colors.grey.shade600,
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
                                  (a, b) =>
                                      a.orderIndex.compareTo(b.orderIndex),
                                );

                          return weekWorkouts.isEmpty
                              ? Center(
                                child: Text(
                                  'No workouts for Week $weekNumber',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                              : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: weekWorkouts.length,
                                itemBuilder: (context, index) {
                                  final workout = weekWorkouts[index];
                                  return _buildWorkoutCard(
                                    context,
                                    workout,
                                    program,
                                  );
                                },
                              );
                        }),
                      ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkoutCard(
    BuildContext context,
    ProgramWorkout workout,
    Program program,
  ) {
    final theme = Theme.of(context);
    final isCurrentWorkout =
        program.currentWeek == workout.weekNumber &&
        program.currentDay == workout.dayNumber;
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
        onTap: () async {
          // Don't allow starting rest days
          if (workout.isRestDay) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Rest day - Recovery is part of the program!',
                ),
                backgroundColor: Colors.blue.shade700,
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }

          // Don't allow restarting completed workouts
          if (workout.isCompleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This workout is already completed!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }

          // Auto-start the workout
          final sessionsProvider = context.read<SessionsProvider>();
          final programsProvider = context.read<ProgramsProvider>();
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);

          final session = await sessionsProvider.startProgramWorkout(
            workout.id,
          );

          if (session != null && mounted) {
            // Navigate to active workout screen
            await navigator.pushNamed(
              RouteNames.activeWorkout,
              arguments: session.id,
            );

            // When returning, check if session was completed
            if (mounted) {
              final completedSession = await sessionsProvider.getSessionById(
                session.id,
              );

              if (completedSession.status == 'completed') {
                // Mark program workout as complete
                await programsProvider.completeWorkout(workout.id);
                await programsProvider.advanceProgram(program.id);

                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Workout completed! Program advanced.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  // Reload program to reflect changes
                  _loadProgram();
                }
              }
            }
          }
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
                              : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      workout.dayNameFromNumber.substring(0, 3).toUpperCase(),
                      style: TextStyle(
                        color:
                            isCurrentWorkout || workout.isCompleted || isMissed
                                ? Colors.white
                                : Colors.grey.shade700,
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
                          workout.workoutName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (workout.workoutType != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            workout.workoutType!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
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
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
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
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${workout.estimatedDuration} min',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Icon(
                    Icons.fitness_center,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${workout.exerciseCount} exercises',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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

  void _showDeleteConfirmation(BuildContext context, Program program) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Program?'),
            content: Text(
              'Are you sure you want to delete "${program.title}"? This action cannot be undone.',
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
                  final success = await provider.deleteProgram(program.id);
                  if (success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Program deleted')),
                    );
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}
