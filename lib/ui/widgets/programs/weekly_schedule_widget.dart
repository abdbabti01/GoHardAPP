import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';

/// Widget that displays a 7-day weekly schedule with drag-and-drop support
/// Each day slot has a FIXED weekday label, workouts can be dragged between slots
class WeeklyScheduleWidget extends StatelessWidget {
  final Program program;
  final Function(ProgramWorkout)? onWorkoutTap;
  final VoidCallback? onWorkoutMoved;

  const WeeklyScheduleWidget({
    super.key,
    required this.program,
    this.onWorkoutTap,
    this.onWorkoutMoved,
  });

  /// Get workouts for the current week based on program position
  List<ProgramWorkout?> _getThisWeeksWorkouts() {
    if (program.workouts == null) return List.filled(7, null);

    final currentWeek = program.currentWeek;
    final weekWorkouts = <ProgramWorkout?>[];

    // Get workouts for days 1-7 of current week
    for (int day = 1; day <= 7; day++) {
      final workout = program.workouts!.cast<ProgramWorkout?>().firstWhere(
        (w) => w?.weekNumber == currentWeek && w?.dayNumber == day,
        orElse: () => null,
      );
      weekWorkouts.add(workout);
    }

    return weekWorkouts;
  }

  /// Get weekday name from day number (1=Monday, 7=Sunday)
  String _getWeekdayName(int dayNumber) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdays[dayNumber - 1];
  }

  /// Strip day prefix from workout name for display
  String _getCleanWorkoutName(String workoutName) {
    final colonIndex = workoutName.indexOf(':');
    if (colonIndex != -1 && colonIndex < 15) {
      return workoutName.substring(colonIndex + 1).trim();
    }
    return workoutName;
  }

  /// Update workout day number when dropped on a new day
  Future<void> _updateWorkoutDay(
    BuildContext context,
    ProgramWorkout workout,
    int newDayNumber,
  ) async {
    if (!context.mounted) return;

    final provider = context.read<ProgramsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Show loading indicator
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Moving ${_getCleanWorkoutName(workout.workoutName)} to ${_getWeekdayName(newDayNumber)}...',
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      // Update the workout with new day number
      final updatedWorkout = workout.copyWith(dayNumber: newDayNumber);

      // Call API to update
      final success = await provider.updateWorkout(
        updatedWorkout.id,
        updatedWorkout,
      );

      if (!context.mounted) return;

      if (success) {
        // Trigger parent reload through callback
        onWorkoutMoved?.call();

        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Moved ${_getCleanWorkoutName(workout.workoutName)} to ${_getWeekdayName(newDayNumber)}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Failed to move workout'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;

      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Build a single day slot with fixed weekday label
  Widget _buildDaySlot(
    BuildContext context,
    int dayNumber,
    ProgramWorkout? workout,
    ThemeData theme,
  ) {
    final isCurrentDay = workout != null && program.isCurrentWorkout(workout);
    final isMissed = workout != null && program.isWorkoutMissed(workout);
    final isCompleted = workout != null && workout.isCompleted;
    final isRestDay = workout == null;

    return DragTarget<ProgramWorkout>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) async {
        final draggedWorkout = details.data;
        if (draggedWorkout.dayNumber != dayNumber) {
          await _updateWorkoutDay(context, draggedWorkout, dayNumber);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                isHighlighted
                    ? theme.primaryColor.withValues(alpha: 0.1)
                    : Colors.transparent,
            border: Border.all(
              color: isHighlighted ? theme.primaryColor : Colors.grey.shade300,
              width: isHighlighted ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // FIXED weekday label (never changes)
              SizedBox(
                width: 80,
                child: Text(
                  _getWeekdayName(dayNumber),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color:
                        isCurrentDay
                            ? theme.primaryColor
                            : Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Workout content (draggable if not rest day)
              Expanded(
                child:
                    isRestDay
                        ? Row(
                          children: [
                            Icon(
                              Icons.self_improvement,
                              size: 18,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Rest Day',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        )
                        : LongPressDraggable<ProgramWorkout>(
                          data: workout,
                          feedback: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 200,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                _getCleanWorkoutName(workout.workoutName),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.3,
                            child: Text(
                              _getCleanWorkoutName(workout.workoutName),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          child: InkWell(
                            onTap:
                                onWorkoutTap != null
                                    ? () => onWorkoutTap!(workout)
                                    : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                _getCleanWorkoutName(workout.workoutName),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isCurrentDay
                                          ? theme.primaryColor
                                          : Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ),
                        ),
              ),

              // Status indicators
              if (isCurrentDay)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'TODAY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                )
              else if (isCompleted)
                const Icon(Icons.check_circle, color: Colors.green, size: 20)
              else if (isMissed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'MISSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekWorkouts = _getThisWeeksWorkouts();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.calendar_today, size: 20, color: theme.primaryColor),
              const SizedBox(width: 8),
              Text(
                'THIS WEEK\'S SCHEDULE',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                'Week ${program.currentWeek}/${program.totalWeeks}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.primaryColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Long-press and drag workouts to reschedule',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),

          // 7 FIXED day slots with draggable workouts
          ...weekWorkouts.asMap().entries.map((entry) {
            final dayNumber = entry.key + 1;
            final workout = entry.value;
            return _buildDaySlot(context, dayNumber, workout, theme);
          }),
        ],
      ),
    );
  }
}
