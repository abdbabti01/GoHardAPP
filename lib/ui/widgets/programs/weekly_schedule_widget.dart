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

  /// Build a single day card in grid layout
  /// Shows day name at top, workouts below (Activity Types style)
  Widget _buildDayCard(
    BuildContext context,
    int dayNumber,
    List<ProgramWorkout> workouts,
    ThemeData theme,
  ) {
    final isRestDay = workouts.isEmpty;
    final hasCurrentDay = workouts.any((w) => program.isCurrentWorkout(w));

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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                isHighlighted
                    ? theme.primaryColor.withValues(alpha: 0.15)
                    : const Color(
                      0xFF1C1C1E,
                    ), // Slightly darker than parent for layering
            border: Border.all(
              color:
                  isHighlighted
                      ? theme.primaryColor
                      : (hasCurrentDay
                          ? theme.primaryColor.withValues(alpha: 0.5)
                          : const Color(0xFF38383A)),
              width: isHighlighted ? 1.5 : 0.5, // Subtle borders
            ),
            borderRadius: BorderRadius.circular(10), // iOS corner radius
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Day badge at top
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      hasCurrentDay
                          ? theme.primaryColor
                          : theme.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _getWeekdayName(dayNumber).substring(0, 3).toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Workouts or Rest Day
              Expanded(
                child:
                    isRestDay
                        ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.self_improvement,
                                size: 32,
                                color: const Color(0xFF8E8E93),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Rest Day',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8E8E93),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                        : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Show workout count if multiple
                              if (workouts.length > 1)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    '${workouts.length} workouts',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF8E8E93),
                                    ),
                                  ),
                                ),
                              // Workout items
                              ...workouts.map((workout) {
                                final isCurrentDay = program.isCurrentWorkout(
                                  workout,
                                );
                                final isCompleted = workout.isCompleted;
                                final isMissed = program.isWorkoutMissed(
                                  workout,
                                );
                                final isRestDayWorkout = workout.isRestDay;

                                Widget workoutItem = Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        isRestDayWorkout
                                            ? const Color(0xFF1C1C1E)
                                            : const Color(0xFF1C1C1E),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          isCurrentDay
                                              ? theme.primaryColor
                                              : const Color(0xFF38383A),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (!isRestDayWorkout)
                                        const Icon(
                                          Icons.drag_indicator,
                                          size: 14,
                                          color: Color(0xFF8E8E93),
                                        ),
                                      if (isRestDayWorkout)
                                        const Icon(
                                          Icons.self_improvement,
                                          size: 14,
                                          color: Color(0xFF8E8E93),
                                        ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          _getCleanWorkoutName(
                                            workout.workoutName,
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                isCurrentDay
                                                    ? theme.primaryColor
                                                    : Colors.white,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      if (isCompleted)
                                        Icon(
                                          Icons.check_circle,
                                          color: Colors.green.shade600,
                                          size: 14,
                                        )
                                      else if (isMissed)
                                        Icon(
                                          Icons.cancel,
                                          color: Colors.orange,
                                          size: 14,
                                        ),
                                    ],
                                  ),
                                );

                                // Make draggable if not rest day
                                if (!isRestDayWorkout) {
                                  return LongPressDraggable<ProgramWorkout>(
                                    data: workout,
                                    feedback: Material(
                                      elevation: 6,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 150,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: theme.primaryColor
                                                .withValues(alpha: 0.5),
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: theme.primaryColor
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          _getCleanWorkoutName(
                                            workout.workoutName,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(
                                      opacity: 0.3,
                                      child: workoutItem,
                                    ),
                                    child: InkWell(
                                      onTap:
                                          onWorkoutTap != null
                                              ? () => onWorkoutTap!(workout)
                                              : null,
                                      borderRadius: BorderRadius.circular(6),
                                      child: workoutItem,
                                    ),
                                  );
                                }

                                return workoutItem;
                              }),
                            ],
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
        color: const Color(0xFF2C2C2E), // Lighter iOS grey
        borderRadius: BorderRadius.circular(12), // iOS corner radius
        border: Border.all(
          color: const Color(0xFF38383A),
          width: 0.5, // Hair-thin border
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
              const Text(
                'THIS WEEK\'S SCHEDULE',
                style: TextStyle(
                  fontSize: 13, // iOS subheadline
                  fontWeight: FontWeight.w600, // iOS semibold
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                'Week ${program.currentWeek}/${program.totalWeeks}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400, // iOS regular
                  color: Color(0xFF8E8E93), // iOS secondary text
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Long-press and drag workouts to reschedule',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF8E8E93),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),

          // 7 day grid layout (2 columns)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 10, // iOS spacing
              mainAxisSpacing: 10, // iOS spacing
            ),
            itemCount: 7,
            itemBuilder: (context, index) {
              final dayNumber = index + 1;
              final dayWorkouts = weekWorkouts[index];
              return _buildDayCard(context, dayNumber, dayWorkouts, theme);
            },
          ),
        ],
      ),
    );
  }
}
