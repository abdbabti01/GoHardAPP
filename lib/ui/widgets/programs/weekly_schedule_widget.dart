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
  /// Returns a list of 7 days, each containing a list of workouts for that day
  List<List<ProgramWorkout>> _getThisWeeksWorkouts() {
    if (program.workouts == null) return List.generate(7, (_) => []);

    final currentWeek = program.currentWeek;
    final weekWorkouts = <List<ProgramWorkout>>[];

    // Get all workouts for each day (supports multiple workouts per day)
    for (int day = 1; day <= 7; day++) {
      final dayWorkouts =
          program.workouts!
              .where((w) => w.weekNumber == currentWeek && w.dayNumber == day)
              .toList();
      weekWorkouts.add(dayWorkouts);
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
  /// Implements MOVE logic: workout is moved to new day, allowing multiple workouts per day
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
      // MOVE: Update the workout's day number and order index
      final updatedWorkout = workout.copyWith(
        dayNumber: newDayNumber,
        orderIndex: newDayNumber, // Keep orderIndex synchronized with dayNumber
      );

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

  /// Build a compact card for a single workout with drag handle and status
  Widget _buildWorkoutCard(
    ProgramWorkout workout,
    bool isCurrentDay,
    bool isMissed,
    bool isCompleted,
    ThemeData theme, {
    required bool isDraggable,
  }) {
    final isRestDay = workout.isRestDay;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            isRestDay
                ? Colors.grey.shade100
                : (isCurrentDay
                    ? theme.primaryColor.withValues(alpha: 0.08)
                    : Colors.white),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color:
              isRestDay
                  ? Colors.grey.shade300
                  : (isCurrentDay
                      ? theme.primaryColor.withValues(alpha: 0.4)
                      : Colors.grey.shade300),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Drag handle icon (only for draggable workouts)
          if (isDraggable)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.drag_indicator,
                size: 18,
                color: Colors.grey.shade500,
              ),
            )
          else if (isRestDay)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.self_improvement,
                size: 18,
                color: Colors.grey.shade400,
              ),
            ),
          // Workout name
          Expanded(
            child: Text(
              _getCleanWorkoutName(workout.workoutName),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    isRestDay
                        ? Colors.grey.shade600
                        : (isCurrentDay
                            ? theme.primaryColor
                            : Colors.grey.shade800),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Status indicators
          if (isCurrentDay)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'TODAY',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else if (isCompleted)
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 18)
          else if (isMissed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'MISSED',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build a single day slot with fixed weekday label
  /// Supports multiple workouts per day
  Widget _buildDaySlot(
    BuildContext context,
    int dayNumber,
    List<ProgramWorkout> workouts,
    ThemeData theme,
  ) {
    final isRestDay = workouts.isEmpty;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day header with label
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      _getWeekdayName(dayNumber),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color:
                            workouts.any((w) => program.isCurrentWorkout(w))
                                ? theme.primaryColor
                                : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isRestDay)
                    Expanded(
                      child: Row(
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
                      ),
                    ),
                ],
              ),

              // Multiple workouts (if any)
              if (!isRestDay) ...[
                const SizedBox(height: 4),
                // Show workout count badge if multiple workouts
                if (workouts.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 92, bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.primaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '${workouts.length} workouts',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                // Workout cards
                ...workouts.map((workout) {
                  final isCurrentDay = program.isCurrentWorkout(workout);
                  final isMissed = program.isWorkoutMissed(workout);
                  final isCompleted = workout.isCompleted;
                  final isRestDayWorkout = workout.isRestDay;

                  // Don't make rest day workouts draggable
                  if (isRestDayWorkout) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 92, bottom: 6),
                      child: _buildWorkoutCard(
                        workout,
                        isCurrentDay,
                        isMissed,
                        isCompleted,
                        theme,
                        isDraggable: false,
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(left: 92, bottom: 6),
                    child: LongPressDraggable<ProgramWorkout>(
                      data: workout,
                      feedback: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 240,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.primaryColor.withValues(alpha: 0.4),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: theme.primaryColor.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.drag_indicator,
                                size: 20,
                                color: theme.primaryColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getCleanWorkoutName(workout.workoutName),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: theme.primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.3,
                        child: _buildWorkoutCard(
                          workout,
                          isCurrentDay,
                          isMissed,
                          isCompleted,
                          theme,
                          isDraggable: true,
                        ),
                      ),
                      child: InkWell(
                        onTap:
                            onWorkoutTap != null
                                ? () => onWorkoutTap!(workout)
                                : null,
                        borderRadius: BorderRadius.circular(8),
                        child: _buildWorkoutCard(
                          workout,
                          isCurrentDay,
                          isMissed,
                          isCompleted,
                          theme,
                          isDraggable: true,
                        ),
                      ),
                    ),
                  );
                }),
              ],
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
            final dayWorkouts = entry.value;
            return _buildDaySlot(context, dayNumber, dayWorkouts, theme);
          }),
        ],
      ),
    );
  }
}
