import 'package:flutter/material.dart';
import '../../../data/models/program_workout.dart';

/// Card widget for displaying a single day in the weekly schedule
class WorkoutDayCard extends StatelessWidget {
  final ProgramWorkout workout;
  final bool isCurrentDay;
  final bool isPastDay;
  final VoidCallback? onTap;

  const WorkoutDayCard({
    super.key,
    required this.workout,
    required this.isCurrentDay,
    required this.isPastDay,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRestDay = workout.isRestDay;
    final isCompleted = workout.isCompleted;

    // Determine colors
    Color backgroundColor;
    Color textColor;
    Color borderColor;

    if (isCurrentDay) {
      backgroundColor = theme.primaryColor.withValues(alpha: 0.1);
      textColor = theme.primaryColor;
      borderColor = theme.primaryColor;
    } else if (isCompleted) {
      backgroundColor = Colors.green.withValues(alpha: 0.1);
      textColor = Colors.green.shade700;
      borderColor = Colors.green;
    } else if (isRestDay) {
      backgroundColor = Colors.grey.shade50;
      textColor = Colors.grey.shade600;
      borderColor = Colors.grey.shade300;
    } else {
      backgroundColor = Colors.white;
      textColor = Colors.grey.shade800;
      borderColor = Colors.grey.shade300;
    }

    return InkWell(
      onTap: isRestDay ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isCurrentDay ? 2 : 1),
        ),
        child: Row(
          children: [
            // Day name
            SizedBox(
              width: 70,
              child: Text(
                workout.dayNameFromNumber,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isCurrentDay ? FontWeight.bold : FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Workout name
            Expanded(
              child: Text(
                workout.workoutName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      isCurrentDay ? FontWeight.bold : FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),

            // Status indicator
            if (isCurrentDay)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'TODAY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              )
            else if (isCompleted)
              Icon(Icons.check_circle, color: Colors.green, size: 24)
            else if (!isRestDay && !isPastDay)
              Icon(Icons.circle_outlined, color: Colors.grey.shade400, size: 24)
            else if (isRestDay)
              Icon(
                Icons.self_improvement,
                color: Colors.grey.shade400,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
