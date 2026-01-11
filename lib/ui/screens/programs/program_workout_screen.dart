import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

    final theme = Theme.of(context);
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
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Completed',
                    style: TextStyle(
                      color: Colors.green,
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
              color: theme.primaryColor.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
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
                              color: Colors.grey.shade600,
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
                        theme.primaryColor,
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (workout.estimatedDuration != null) ...[
                      _buildInfoChip(
                        Icons.access_time,
                        '${workout.estimatedDuration} min',
                        Colors.orange,
                      ),
                      const SizedBox(width: 12),
                    ],
                    _buildInfoChip(
                      Icons.fitness_center,
                      '${exercises.length} exercises',
                      Colors.blue,
                    ),
                  ],
                ),
                if (workout.description != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    workout.description!,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
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
                  _buildSectionHeader(Icons.wb_sunny, 'Warm-up', Colors.orange),
                  const SizedBox(height: 8),
                  _buildInfoCard(workout.warmUp!),
                  const SizedBox(height: 20),
                ],

                // Exercises
                _buildSectionHeader(
                  Icons.fitness_center,
                  'Exercises',
                  theme.primaryColor,
                ),
                const SizedBox(height: 12),
                if (exercises.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No exercises in this workout',
                        style: TextStyle(color: Colors.grey.shade600),
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
                  _buildSectionHeader(Icons.ac_unit, 'Cool-down', Colors.blue),
                  const SizedBox(height: 8),
                  _buildInfoCard(workout.coolDown!),
                  const SizedBox(height: 20),
                ],

                // Completion Notes (if completed)
                if (workout.isCompleted && workout.completionNotes != null) ...[
                  _buildSectionHeader(Icons.notes, 'Notes', Colors.grey),
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
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
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
                          // Create session from program workout
                          final sessionsProvider =
                              context.read<SessionsProvider>();
                          final programsProvider =
                              context.read<ProgramsProvider>();
                          final navigator = Navigator.of(context);

                          final session = await sessionsProvider
                              .startProgramWorkout(widget.workoutId);

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
                                await programsProvider.completeWorkout(
                                  widget.workoutId,
                                );
                                await programsProvider.advanceProgram(
                                  widget.programId,
                                );

                                if (mounted) {
                                  navigator.pop();
                                }
                              }
                            }
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
                        onPressed: () => _showCompleteDialog(context, workout),
                        icon: const Icon(Icons.check, size: 20),
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
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          content,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(int number, Map<String, dynamic> exercise) {
    final theme = Theme.of(context);
    final name = exercise['name'] ?? 'Exercise $number';
    final sets = exercise['sets']?.toString() ?? '-';
    final reps = exercise['reps']?.toString() ?? '-';
    final rest = exercise['rest']?.toString() ?? '-';
    final weight = exercise['weight']?.toString() ?? '';
    final notes = exercise['notes']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    color: theme.primaryColor,
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
                color: Colors.grey.shade50,
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
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        notes,
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                        ),
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
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
    return Container(width: 1, height: 30, color: Colors.grey.shade300);
  }

  void _showCompleteDialog(BuildContext context, ProgramWorkout workout) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green),
                SizedBox(width: 12),
                Text('Complete Workout?'),
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
                    // Advance the program to next day
                    await provider.advanceProgram(widget.programId);

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Workout completed! Moving to next day...',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );

                    // Go back to program detail
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Complete'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            ],
          ),
    );
  }
}
