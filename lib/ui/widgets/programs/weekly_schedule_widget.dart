import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
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
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Moving ${_getCleanWorkoutName(workout.workoutName)} to ${_getWeekdayName(newDayNumber)}...',
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final updatedWorkout = workout.copyWith(
        dayNumber: newDayNumber,
        orderIndex: newDayNumber,
      );

      final success = await provider.updateWorkout(
        updatedWorkout.id,
        updatedWorkout,
      );

      if (!context.mounted) return;

      if (success) {
        onWorkoutMoved?.call();
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Moved to ${_getWeekdayName(newDayNumber)}'),
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
        ),
      );
    }
  }

  /// Get today's day number (1=Monday, 7=Sunday)
  int _getTodayDayNumber() {
    return DateTime.now().weekday;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekWorkouts = _getThisWeeksWorkouts();
    final todayNumber = _getTodayDayNumber();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This Week\'s Schedule',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Week ${program.currentWeek} of ${program.totalWeeks}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${program.progressPercentage.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Long-press and drag to reschedule',
            style: TextStyle(
              fontSize: 11,
              color: context.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),

          // Week days row
          Row(
            children: List.generate(7, (index) {
              final dayNumber = index + 1;
              final isToday = dayNumber == todayNumber;
              final dayWorkouts = weekWorkouts[index];
              final hasWorkout = dayWorkouts.isNotEmpty;
              final isCompleted = dayWorkouts.any((w) => w.isCompleted);

              return Expanded(
                child: DragTarget<ProgramWorkout>(
                  onWillAcceptWithDetails: (details) => true,
                  onAcceptWithDetails: (details) async {
                    final draggedWorkout = details.data;
                    if (draggedWorkout.dayNumber != dayNumber) {
                      await _updateWorkoutDay(
                        context,
                        draggedWorkout,
                        dayNumber,
                      );
                    }
                  },
                  builder: (context, candidateData, rejectedData) {
                    final isHighlighted = candidateData.isNotEmpty;

                    return Container(
                      margin: EdgeInsets.only(right: index < 6 ? 4 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            isHighlighted
                                ? theme.primaryColor.withValues(alpha: 0.2)
                                : isToday
                                ? theme.primaryColor.withValues(alpha: 0.1)
                                : context.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              isHighlighted
                                  ? theme.primaryColor
                                  : isToday
                                  ? theme.primaryColor
                                  : context.borderSubtle,
                          width: isToday || isHighlighted ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _getWeekdayName(dayNumber),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  isToday ? FontWeight.bold : FontWeight.w500,
                              color:
                                  isToday
                                      ? theme.primaryColor
                                      : context.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color:
                                  isCompleted
                                      ? Colors.green
                                      : hasWorkout
                                      ? theme.primaryColor
                                      : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    isCompleted
                                        ? Colors.green
                                        : hasWorkout
                                        ? theme.primaryColor
                                        : context.borderSubtle,
                                width: 2,
                              ),
                            ),
                            child:
                                isCompleted
                                    ? const Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    )
                                    : hasWorkout
                                    ? Icon(
                                      Icons.fitness_center,
                                      size: 12,
                                      color: Colors.white,
                                    )
                                    : null,
                          ),
                          if (isToday) ...[
                            const SizedBox(height: 2),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: theme.primaryColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Workout cards for each day with workouts
          ...weekWorkouts.asMap().entries.where((e) => e.value.isNotEmpty).map((
            entry,
          ) {
            final dayNumber = entry.key + 1;
            final dayWorkouts = entry.value;
            final isToday = dayNumber == todayNumber;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:
                    dayWorkouts.map((workout) {
                      final isCompleted = workout.isCompleted;
                      final isMissed = program.isWorkoutMissed(workout);
                      final isRestDay = workout.isRestDay;

                      Widget workoutCard = Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              isToday
                                  ? theme.primaryColor.withValues(alpha: 0.05)
                                  : context.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                isToday
                                    ? theme.primaryColor.withValues(alpha: 0.3)
                                    : context.border,
                            width: isToday ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Day badge
                            Container(
                              width: 40,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color:
                                    isCompleted
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : isMissed
                                        ? Colors.orange.withValues(alpha: 0.1)
                                        : theme.primaryColor.withValues(
                                          alpha: 0.1,
                                        ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    _getWeekdayName(dayNumber),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          isCompleted
                                              ? Colors.green
                                              : isMissed
                                              ? Colors.orange
                                              : theme.primaryColor,
                                    ),
                                  ),
                                  if (isToday)
                                    Text(
                                      'Today',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: theme.primaryColor,
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
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: context.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      if (workout.estimatedDuration !=
                                          null) ...[
                                        Icon(
                                          Icons.timer_outlined,
                                          size: 12,
                                          color: context.textTertiary,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${workout.estimatedDuration}m',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.textTertiary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Icon(
                                        Icons.fitness_center,
                                        size: 12,
                                        color: context.textTertiary,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${workout.exerciseCount} exercises',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: context.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Status icon
                            if (isCompleted)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.green,
                                ),
                              )
                            else if (isMissed)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.schedule,
                                  size: 16,
                                  color: Colors.orange,
                                ),
                              )
                            else if (!isRestDay)
                              Icon(
                                Icons.drag_indicator,
                                size: 20,
                                color: context.textTertiary,
                              ),
                          ],
                        ),
                      );

                      // Make draggable if not rest day and not completed
                      if (!isRestDay && !isCompleted) {
                        return LongPressDraggable<ProgramWorkout>(
                          data: workout,
                          feedback: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 200,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.primaryColor,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fitness_center,
                                    size: 16,
                                    color: theme.primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _getCleanWorkoutName(workout.workoutName),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: context.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.3,
                            child: workoutCard,
                          ),
                          child: InkWell(
                            onTap:
                                onWorkoutTap != null
                                    ? () => onWorkoutTap!(workout)
                                    : null,
                            borderRadius: BorderRadius.circular(12),
                            child: workoutCard,
                          ),
                        );
                      }

                      return InkWell(
                        onTap:
                            onWorkoutTap != null
                                ? () => onWorkoutTap!(workout)
                                : null,
                        borderRadius: BorderRadius.circular(12),
                        child: workoutCard,
                      );
                    }).toList(),
              ),
            );
          }),

          // Empty state if no workouts this week
          if (weekWorkouts.every((day) => day.isEmpty))
            Container(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.self_improvement,
                      size: 48,
                      color: context.textTertiary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rest week - Recovery time!',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textSecondary,
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
}
