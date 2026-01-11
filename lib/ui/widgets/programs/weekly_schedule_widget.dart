import 'package:flutter/material.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import 'workout_day_card.dart';

/// Widget that displays a 7-day weekly schedule for a program
class WeeklyScheduleWidget extends StatelessWidget {
  final Program program;
  final Function(ProgramWorkout)? onWorkoutTap;

  const WeeklyScheduleWidget({
    super.key,
    required this.program,
    this.onWorkoutTap,
  });

  /// Get workouts for the current week
  List<ProgramWorkout?> _getThisWeeksWorkouts() {
    if (program.workouts == null) return List.filled(7, null);

    final currentWeek = program.currentWeek;
    final weekWorkouts = <ProgramWorkout?>[];

    // Get workouts for days 1-7 of current week
    for (int day = 1; day <= 7; day++) {
      final workout = program.workouts!.firstWhere(
        (w) => w.weekNumber == currentWeek && w.dayNumber == day,
        orElse: () => ProgramWorkout(
          id: 0,
          programId: program.id,
          weekNumber: currentWeek,
          dayNumber: day,
          workoutName: 'Rest',
          workoutType: 'rest',
          exercisesJson: '[]',
          isCompleted: false,
          orderIndex: day,
        ),
      );
      weekWorkouts.add(workout);
    }

    return weekWorkouts;
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
              Icon(
                Icons.calendar_today,
                size: 20,
                color: theme.primaryColor,
              ),
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
          const SizedBox(height: 16),

          // 7-day calendar
          ...weekWorkouts.asMap().entries.map((entry) {
            final dayNumber = entry.key + 1;
            final workout = entry.value;
            final isCurrentDay = dayNumber == program.currentDay;
            final isPastDay = dayNumber < program.currentDay;

            if (workout == null) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: WorkoutDayCard(
                workout: workout,
                isCurrentDay: isCurrentDay,
                isPastDay: isPastDay,
                onTap: onWorkoutTap != null ? () => onWorkoutTap!(workout) : null,
              ),
            );
          }),
        ],
      ),
    );
  }
}
