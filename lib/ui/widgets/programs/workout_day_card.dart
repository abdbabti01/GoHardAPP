import 'package:flutter/material.dart';
import '../../../data/models/program_workout.dart';
import '../../../data/models/session.dart';

/// Card widget for displaying a single day in the weekly schedule
class WorkoutDayCard extends StatelessWidget {
  final ProgramWorkout workout;
  final Session? session; // Session created from this workout (if any)
  final bool isCurrentDay;
  final bool isPastDay;
  final bool isMissed;
  final VoidCallback? onTap;

  const WorkoutDayCard({
    super.key,
    required this.workout,
    this.session,
    required this.isCurrentDay,
    required this.isPastDay,
    this.isMissed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRestDay = workout.isRestDay;

    // Determine status from session (if exists) OR workout.isCompleted
    // This ensures archived workouts still show as completed in the program
    final sessionStatus = session?.status;
    final isCompleted =
        sessionStatus == 'completed' ||
        sessionStatus == 'archived' ||
        workout.isCompleted;
    final isInProgress = sessionStatus == 'in_progress';
    final isNotStarted =
        !isCompleted &&
        (session == null ||
            sessionStatus == 'planned' ||
            sessionStatus == 'draft');

    // Determine colors based on session status
    Color backgroundColor;
    Color textColor;
    Color borderColor;

    if (isCurrentDay) {
      backgroundColor = theme.primaryColor.withValues(alpha: 0.1);
      textColor = theme.primaryColor;
      borderColor = theme.primaryColor;
    } else if (isCompleted) {
      // Completed workout - green
      backgroundColor = Colors.green.withValues(alpha: 0.1);
      textColor = Colors.green.shade700;
      borderColor = Colors.green;
    } else if (isInProgress) {
      // In progress workout - blue
      backgroundColor = Colors.blue.withValues(alpha: 0.1);
      textColor = Colors.blue.shade700;
      borderColor = Colors.blue;
    } else if (isMissed) {
      backgroundColor = Colors.orange.withValues(alpha: 0.1);
      textColor = Colors.orange.shade700;
      borderColor = Colors.orange;
    } else if (isRestDay) {
      backgroundColor = Colors.grey.shade50;
      textColor = Colors.grey.shade600;
      borderColor = Colors.grey.shade300;
    } else if (isNotStarted) {
      // Not started - grey
      backgroundColor = Colors.grey.shade100;
      textColor = Colors.grey.shade700;
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
            else if (isInProgress)
              Icon(Icons.play_circle_filled, color: Colors.blue, size: 24)
            else if (isMissed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'MISSED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              )
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
