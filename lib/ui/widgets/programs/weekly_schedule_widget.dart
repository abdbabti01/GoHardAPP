import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../data/models/session.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/programs_provider.dart';
import 'workout_day_card.dart';

/// Widget that displays a 7-day weekly schedule for a program with drag-and-drop support
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

  /// Get workouts for the current week based on calendar
  List<ProgramWorkout?> _getThisWeeksWorkouts() {
    if (program.workouts == null) return List.filled(7, null);

    final currentWeek = program.currentWeek;
    final weekWorkouts = <ProgramWorkout?>[];

    // Get workouts for days 1-7 of current week
    for (int day = 1; day <= 7; day++) {
      final workout = program.workouts!.firstWhere(
        (w) => w.weekNumber == currentWeek && w.dayNumber == day,
        orElse:
            () => ProgramWorkout(
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

  /// Find session for a given program workout
  Session? _findSessionForWorkout(
    List<Session> sessions,
    ProgramWorkout workout,
  ) {
    return sessions.cast<Session?>().firstWhere(
      (s) => s?.programWorkoutId == workout.id,
      orElse: () => null,
    );
  }

  /// Update workout day number when dropped on a new day
  Future<void> _updateWorkoutDay(
    BuildContext context,
    ProgramWorkout workout,
    int newDayNumber,
  ) async {
    final provider = context.read<ProgramsProvider>();

    // Update the workout with new day number
    final updatedWorkout = workout.copyWith(dayNumber: newDayNumber);

    // Call API to update
    await provider.updateWorkout(updatedWorkout.id, updatedWorkout);

    // Notify parent to reload
    onWorkoutMoved?.call();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved ${workout.workoutName} to Day $newDayNumber'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekWorkouts = _getThisWeeksWorkouts();

    // Get all sessions from the program to match with workouts
    final sessionsProvider = context.watch<SessionsProvider>();
    final programSessions = sessionsProvider.getSessionsFromProgram(program.id);

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

          // 7-day calendar with drag-and-drop
          ...weekWorkouts.asMap().entries.map((entry) {
            final dayNumber = entry.key + 1;
            final workout = entry.value;

            if (workout == null) return const SizedBox.shrink();

            // Find the session created from this workout
            final session = _findSessionForWorkout(programSessions, workout);

            // Use session-based logic
            final isCurrentDay = program.isCurrentWorkout(workout);
            final isPastDay =
                !program.isWorkoutFuture(workout) &&
                !program.isCurrentWorkout(workout);
            final isMissed = program.isWorkoutMissed(workout);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DragTarget<ProgramWorkout>(
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
                    decoration: BoxDecoration(
                      border:
                          isHighlighted
                              ? Border.all(color: theme.primaryColor, width: 2)
                              : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: LongPressDraggable<ProgramWorkout>(
                      data: workout,
                      feedback: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width - 64,
                          child: WorkoutDayCard(
                            workout: workout,
                            session: session,
                            isCurrentDay: isCurrentDay,
                            isPastDay: isPastDay,
                            isMissed: isMissed,
                            onTap: null,
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.3,
                        child: WorkoutDayCard(
                          workout: workout,
                          session: session,
                          isCurrentDay: isCurrentDay,
                          isPastDay: isPastDay,
                          isMissed: isMissed,
                          onTap: null,
                        ),
                      ),
                      child: WorkoutDayCard(
                        workout: workout,
                        session: session,
                        isCurrentDay: isCurrentDay,
                        isPastDay: isPastDay,
                        isMissed: isMissed,
                        onTap:
                            onWorkoutTap != null
                                ? () => onWorkoutTap!(workout)
                                : null,
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
