import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../routes/route_names.dart';

class ProgramWorkoutScreen extends StatefulWidget {
  final int workoutId;
  final int programId;

  const ProgramWorkoutScreen({
    super.key,
    required this.workoutId,
    required this.programId,
  });

  @override
  State<ProgramWorkoutScreen> createState() => _ProgramWorkoutScreenState();
}

class _ProgramWorkoutScreenState extends State<ProgramWorkoutScreen> {
  ProgramWorkout? _workout;
  DateTime? _programStartDate;
  bool _isLoading = true;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWorkout();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkout() async {
    setState(() => _isLoading = true);
    final provider = context.read<ProgramsProvider>();
    final program = await provider.getProgramById(widget.programId);

    if (program != null && program.workouts != null && mounted) {
      final workout = program.workouts!.firstWhere(
        (w) => w.id == widget.workoutId,
        orElse: () => program.workouts!.first,
      );
      setState(() {
        _workout = workout;
        _programStartDate = program.startDate;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workout')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_workout == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workout')),
        body: const Center(child: Text('Workout not found')),
      );
    }

    final workout = _workout!;
    final exercises = workout.exercises;

    return Scaffold(
      appBar: AppBar(
        title: Text(workout.workoutName),
        actions: [
          if (workout.isCompleted)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: context.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: context.success, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Completed',
                    style: TextStyle(
                      color: context.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Workout Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.accent.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(color: context.borderSubtle, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            workout.workoutIdentifier,
                            style: TextStyle(
                              fontSize: 14,
                              color: context.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            workout.workoutName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (workout.workoutType != null) ...[
                      _buildInfoChip(
                        Icons.category_outlined,
                        workout.workoutType!,
                        context.accent,
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (workout.estimatedDuration != null) ...[
                      _buildInfoChip(
                        Icons.access_time,
                        '${workout.estimatedDuration} min',
                        context.warning,
                      ),
                      const SizedBox(width: 12),
                    ],
                    _buildInfoChip(
                      Icons.fitness_center,
                      '${exercises.length} exercises',
                      context.info,
                    ),
                  ],
                ),
                if (workout.description != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    workout.description!,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Workout Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Warm-up Section
                if (workout.warmUp != null && workout.warmUp!.isNotEmpty) ...[
                  _buildSectionHeader(
                    Icons.wb_sunny,
                    'Warm-up',
                    context.warning,
                  ),
                  const SizedBox(height: 8),
                  _buildInfoCard(workout.warmUp!),
                  const SizedBox(height: 20),
                ],

                // Exercises
                _buildSectionHeader(
                  Icons.fitness_center,
                  'Exercises',
                  context.accent,
                ),
                const SizedBox(height: 12),
                if (exercises.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No exercises in this workout',
                        style: TextStyle(color: context.textSecondary),
                      ),
                    ),
                  )
                else
                  ...exercises.asMap().entries.map((entry) {
                    final index = entry.key;
                    final exercise = entry.value;
                    return _buildExerciseCard(index + 1, exercise);
                  }),

                const SizedBox(height: 20),

                // Cool-down Section
                if (workout.coolDown != null &&
                    workout.coolDown!.isNotEmpty) ...[
                  _buildSectionHeader(Icons.ac_unit, 'Cool-down', context.info),
                  const SizedBox(height: 8),
                  _buildInfoCard(workout.coolDown!),
                  const SizedBox(height: 20),
                ],

                // Completion Notes (if completed)
                if (workout.isCompleted && workout.completionNotes != null) ...[
                  _buildSectionHeader(
                    Icons.notes,
                    'Notes',
                    context.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  _buildInfoCard(workout.completionNotes!),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),

          // Action Buttons
          if (!workout.isCompleted)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: context.isDarkMode ? 0.3 : 0.1,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // Capture providers/context before async operations
                          final sessionsProvider =
                              context.read<SessionsProvider>();
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(context);
                          final successColor = context.success;
                          final errorColor = context.error;

                          // Show confirmation dialog first
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: Row(
                                    children: [
                                      Icon(
                                        Icons.add_circle_outline,
                                        color: context.info,
                                      ),
                                      SizedBox(width: 12),
                                      Text('Add to My Workouts?'),
                                    ],
                                  ),
                                  content: Text(
                                    'Do you want to add "${workout.workoutName}" to your workout sessions?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text('Add & Start'),
                                    ),
                                  ],
                                ),
                          );

                          if (confirmed != true || !mounted) return;

                          // User confirmed - create session and navigate
                          final session = await sessionsProvider
                              .startProgramWorkout(
                                widget.workoutId,
                                _workout!,
                                _programStartDate ?? DateTime.now(),
                                widget.programId, // Pass actual programId
                              );

                          if (session != null && mounted) {
                            // Navigate to Active Workout screen
                            navigator.pushNamed(
                              RouteNames.activeWorkout,
                              arguments: session.id,
                            );

                            // Show success message
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${workout.workoutName} started!',
                                ),
                                backgroundColor: successColor,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } else if (mounted) {
                            // Failed to start - show error
                            final errorMsg =
                                sessionsProvider.errorMessage ??
                                'Failed to start workout';
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(errorMsg),
                                backgroundColor: errorColor,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                            sessionsProvider.clearError();
                          }
                        },
                        icon: const Icon(Icons.play_arrow, size: 24),
                        label: const Text(
                          'Start Workout',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        onPressed: () => _showSkipDialog(context, workout),
                        icon: const Icon(Icons.skip_next, size: 20),
                        label: const Text(
                          'Skip',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String content) {
    return Card(
      elevation: 0,
      color: context.surfaceHighlight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderSubtle, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          content,
          style: TextStyle(
            color: context.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(int number, Map<String, dynamic> exercise) {
    final name = exercise['name'] ?? 'Exercise $number';
    final sets = exercise['sets']?.toString() ?? '-';
    final reps = exercise['reps']?.toString() ?? '-';
    final rest = exercise['rest']?.toString() ?? '-';
    final weight = exercise['weight']?.toString() ?? '';
    final notes = exercise['notes']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderSubtle, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      number.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surfaceHighlight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildExerciseDetail('Sets', sets),
                  _buildVerticalDivider(),
                  _buildExerciseDetail('Reps', reps),
                  _buildVerticalDivider(),
                  _buildExerciseDetail('Rest', '$rest sec'),
                  if (weight.isNotEmpty) ...[
                    _buildVerticalDivider(),
                    _buildExerciseDetail('Weight', weight),
                  ],
                ],
              ),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.info.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: context.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        notes,
                        style: TextStyle(color: context.info, fontSize: 13),
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
  }

  Widget _buildExerciseDetail(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: context.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(width: 1, height: 30, color: context.borderSubtle);
  }

  void _showCompleteDialog(BuildContext context, ProgramWorkout workout) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle_outline, color: context.success),
                const SizedBox(width: 12),
                const Text('Complete Workout?'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Great job on completing "${workout.workoutName}"!'),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'How did the workout feel?',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  final provider = context.read<ProgramsProvider>();

                  // Complete the workout
                  final success = await provider.completeWorkout(
                    workout.id,
                    notes:
                        _notesController.text.isEmpty
                            ? null
                            : _notesController.text,
                  );

                  if (success && context.mounted) {
                    // No need to advance - program auto-syncs with calendar

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Workout completed!'),
                        backgroundColor: context.success,
                      ),
                    );

                    // Go back to program detail
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Complete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.success,
                ),
              ),
            ],
          ),
    );
  }

  void _showSkipDialog(BuildContext context, ProgramWorkout workout) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.skip_next, color: context.warning),
                const SizedBox(width: 12),
                const Text('Skip Workout?'),
              ],
            ),
            content: Text(
              'Skip "${workout.workoutName}"? It will be marked as skipped, '
              'not completed, and won\'t count toward your progress.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  final provider = context.read<ProgramsProvider>();
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);

                  String? errorMessage;
                  final result = await provider.skipWorkout(
                    workout.id,
                    onError: (message) => errorMessage = message,
                  );

                  if (!context.mounted) return;

                  if (result.success) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('Workout skipped'),
                        backgroundColor: context.warning,
                      ),
                    );
                    navigator.pop();
                  } else if (result.isBlocked) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text(
                          'This workout already has a session in progress. '
                          'Resume or manage it instead of skipping.',
                        ),
                        backgroundColor: context.error,
                        duration: const Duration(seconds: 4),
                        action:
                            result.blockingSessionId == null
                                ? null
                                : SnackBarAction(
                                  label: 'View',
                                  onPressed: () {
                                    navigator.pushNamed(
                                      RouteNames.sessionDetail,
                                      arguments: result.blockingSessionId,
                                    );
                                  },
                                ),
                      ),
                    );
                  } else if (errorMessage != null) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(errorMessage!),
                        backgroundColor: context.error,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.skip_next),
                label: const Text('Skip'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.warning,
                ),
              ),
            ],
          ),
    );
  }
}
