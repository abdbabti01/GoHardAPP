import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';

/// Widget that displays a 7-day weekly schedule with drag-and-drop support
/// Each day is a drop target where workouts can be dragged between days
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

  List<List<ProgramWorkout>> _getThisWeeksWorkouts() {
    if (program.workouts == null) return List.generate(7, (_) => []);

    final currentWeek = program.currentWeek;
    final weekWorkouts = <List<ProgramWorkout>>[];

    for (int day = 1; day <= 7; day++) {
      final dayWorkouts =
          program.workouts!
              .where((w) => w.weekNumber == currentWeek && w.dayNumber == day)
              .toList();
      weekWorkouts.add(dayWorkouts);
    }

    return weekWorkouts;
  }

  String _getWeekdayName(int dayNumber) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[dayNumber - 1];
  }

  String _getCleanWorkoutName(String workoutName) {
    final colonIndex = workoutName.indexOf(':');
    if (colonIndex != -1 && colonIndex < 15) {
      return workoutName.substring(colonIndex + 1).trim();
    }
    return workoutName;
  }

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
        content: Text('Moving to ${_getWeekdayName(newDayNumber)}...'),
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
          const SizedBox(height: 4),
          Text(
            'Drag workouts to reschedule',
            style: TextStyle(
              fontSize: 11,
              color: context.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),

          // 7-day grid - 4 days on first row, 3 on second
          Row(
            children: [
              for (int i = 0; i < 4; i++) ...[
                Expanded(
                  child: _buildDayCard(
                    context,
                    i + 1,
                    weekWorkouts[i],
                    theme,
                    todayNumber,
                  ),
                ),
                if (i < 3) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 4; i < 7; i++) ...[
                Expanded(
                  child: _buildDayCard(
                    context,
                    i + 1,
                    weekWorkouts[i],
                    theme,
                    todayNumber,
                  ),
                ),
                if (i < 6) const SizedBox(width: 8),
              ],
              // Empty space to balance the row
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(
    BuildContext context,
    int dayNumber,
    List<ProgramWorkout> workouts,
    ThemeData theme,
    int todayNumber,
  ) {
    final isToday = dayNumber == todayNumber;
    final hasWorkout = workouts.isNotEmpty;
    final allCompleted = hasWorkout && workouts.every((w) => w.isCompleted);
    final hasMissed = workouts.any((w) => program.isWorkoutMissed(w));

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
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                isHighlighted
                    ? theme.primaryColor.withValues(alpha: 0.15)
                    : isToday
                    ? theme.primaryColor.withValues(alpha: 0.08)
                    : context.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isHighlighted
                      ? theme.primaryColor
                      : isToday
                      ? theme.primaryColor
                      : allCompleted
                      ? Colors.green.withValues(alpha: 0.5)
                      : context.border,
              width: isHighlighted || isToday ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isToday
                              ? theme.primaryColor
                              : allCompleted
                              ? Colors.green
                              : hasMissed
                              ? Colors.orange
                              : theme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getWeekdayName(dayNumber),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color:
                            isToday || allCompleted || hasMissed
                                ? Colors.white
                                : theme.primaryColor,
                      ),
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (allCompleted)
                    Icon(Icons.check_circle, size: 14, color: Colors.green)
                  else if (hasMissed)
                    Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                ],
              ),
              const SizedBox(height: 8),

              // Workouts list or rest day
              if (workouts.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.self_improvement,
                          size: 20,
                          color: context.textTertiary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rest',
                          style: TextStyle(
                            fontSize: 10,
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children:
                          workouts.map((workout) {
                            return _buildWorkoutItem(context, workout, theme);
                          }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkoutItem(
    BuildContext context,
    ProgramWorkout workout,
    ThemeData theme,
  ) {
    final isCompleted = workout.isCompleted;
    final isMissed = program.isWorkoutMissed(workout);
    final isRestDay = workout.isRestDay;

    Widget workoutCard = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color:
            isCompleted
                ? Colors.green.withValues(alpha: 0.1)
                : isMissed
                ? Colors.orange.withValues(alpha: 0.1)
                : context.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color:
              isCompleted
                  ? Colors.green.withValues(alpha: 0.3)
                  : isMissed
                  ? Colors.orange.withValues(alpha: 0.3)
                  : context.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color:
                  isCompleted
                      ? Colors.green
                      : isMissed
                      ? Colors.orange
                      : theme.primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          // Workout info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getCleanWorkoutName(workout.workoutName),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: 10,
                      color: context.textTertiary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${workout.exerciseCount}',
                      style: TextStyle(
                        fontSize: 9,
                        color: context.textTertiary,
                      ),
                    ),
                    if (workout.estimatedDuration != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.timer_outlined,
                        size: 10,
                        color: context.textTertiary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${workout.estimatedDuration}m',
                        style: TextStyle(
                          fontSize: 9,
                          color: context.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Status icon or drag handle
          if (isCompleted)
            Icon(Icons.check, size: 14, color: Colors.green)
          else if (!isRestDay)
            Icon(Icons.drag_indicator, size: 14, color: context.textTertiary),
        ],
      ),
    );

    // Make draggable if not rest day and not completed
    if (!isRestDay && !isCompleted) {
      return LongPressDraggable<ProgramWorkout>(
        data: workout,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 160,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.primaryColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: theme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fitness_center, size: 14, color: theme.primaryColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _getCleanWorkoutName(workout.workoutName),
                    style: TextStyle(
                      fontSize: 12,
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
        childWhenDragging: Opacity(opacity: 0.3, child: workoutCard),
        child: GestureDetector(
          onTap: onWorkoutTap != null ? () => onWorkoutTap!(workout) : null,
          child: workoutCard,
        ),
      );
    }

    return GestureDetector(
      onTap: onWorkoutTap != null ? () => onWorkoutTap!(workout) : null,
      child: workoutCard,
    );
  }
}
