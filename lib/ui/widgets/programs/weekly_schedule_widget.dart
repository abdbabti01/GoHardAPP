import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';

/// Widget that displays a 7-day weekly schedule with enhanced drag-and-drop
class WeeklyScheduleWidget extends StatefulWidget {
  final Program program;
  final Function(ProgramWorkout)? onWorkoutTap;
  final VoidCallback? onWorkoutMoved;

  const WeeklyScheduleWidget({
    super.key,
    required this.program,
    this.onWorkoutTap,
    this.onWorkoutMoved,
  });

  @override
  State<WeeklyScheduleWidget> createState() => _WeeklyScheduleWidgetState();
}

class _WeeklyScheduleWidgetState extends State<WeeklyScheduleWidget> {
  bool _isDragging = false;
  int? _draggedFromDay;

  List<List<ProgramWorkout>> _getThisWeeksWorkouts() {
    if (widget.program.workouts == null) return List.generate(7, (_) => []);

    final currentWeek = widget.program.currentWeek;
    final weekWorkouts = <List<ProgramWorkout>>[];

    for (int day = 1; day <= 7; day++) {
      final dayWorkouts =
          widget.program.workouts!
              .where((w) => w.weekNumber == currentWeek && w.dayNumber == day)
              .toList();
      weekWorkouts.add(dayWorkouts);
    }

    return weekWorkouts;
  }

  String _getWeekdayName(int dayNumber) {
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return weekdays[dayNumber - 1];
  }

  String _getFullWeekdayName(int dayNumber) {
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

    // Haptic feedback
    HapticFeedback.mediumImpact();

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
        widget.onWorkoutMoved?.call();
        HapticFeedback.lightImpact();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Moved to ${_getFullWeekdayName(newDayNumber)}'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Failed to move workout'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: 22,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Week ${widget.program.currentWeek}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      '${widget.program.totalWeeks - widget.program.currentWeek + 1} weeks remaining',
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
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.primaryColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${widget.program.progressPercentage.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Drag hint
          AnimatedOpacity(
            opacity: _isDragging ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: 16,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Hold & drag workouts to reschedule',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // All 7 days in a row
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(7, (index) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : 3,
                      right: index == 6 ? 0 : 3,
                    ),
                    child: _buildDayCard(
                      context,
                      index + 1,
                      weekWorkouts[index],
                      theme,
                      todayNumber,
                    ),
                  ),
                );
              }),
            ),
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
    final hasMissed = workouts.any((w) => widget.program.isWorkoutMissed(w));
    final isDragSource = _draggedFromDay == dayNumber;

    return DragTarget<ProgramWorkout>(
      onWillAcceptWithDetails: (details) {
        HapticFeedback.selectionClick();
        return true;
      },
      onAcceptWithDetails: (details) async {
        final draggedWorkout = details.data;
        if (draggedWorkout.dayNumber != dayNumber) {
          await _updateWorkoutDay(context, draggedWorkout, dayNumber);
        }
        setState(() {
          _isDragging = false;
          _draggedFromDay = null;
        });
      },
      onLeave: (data) {
        // Optional: handle when drag leaves
      },
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()..scale(isHighlighted ? 1.03 : 1.0),
          decoration: BoxDecoration(
            color:
                isHighlighted
                    ? theme.primaryColor.withValues(alpha: 0.15)
                    : isDragSource
                    ? context.surface.withValues(alpha: 0.5)
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
            boxShadow:
                isHighlighted
                    ? [
                      BoxShadow(
                        color: theme.primaryColor.withValues(alpha: 0.25),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                    : null,
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isDragSource ? 0.4 : 1.0,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  // Day header - centered single letter
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          isToday
                              ? theme.primaryColor
                              : allCompleted
                              ? Colors.green
                              : hasMissed
                              ? Colors.orange
                              : theme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _getWeekdayName(dayNumber),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color:
                                isToday || allCompleted || hasMissed
                                    ? Colors.white
                                    : theme.primaryColor,
                          ),
                        ),
                        if (isToday)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          )
                        else if (allCompleted)
                          const Icon(Icons.check, size: 12, color: Colors.white)
                        else if (hasMissed)
                          const Icon(
                            Icons.priority_high,
                            size: 12,
                            color: Colors.white,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Workouts list or rest day
                  Expanded(
                    child:
                        workouts.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.remove,
                                    size: 20,
                                    color: context.textTertiary,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Rest',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: context.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            : SingleChildScrollView(
                              child: Column(
                                children:
                                    workouts.map((workout) {
                                      return _buildWorkoutItem(
                                        context,
                                        workout,
                                        theme,
                                        dayNumber,
                                      );
                                    }).toList(),
                              ),
                            ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkoutItem(
    BuildContext context,
    ProgramWorkout workout,
    ThemeData theme,
    int dayNumber,
  ) {
    final isCompleted = workout.isCompleted;
    final isMissed = widget.program.isWorkoutMissed(workout);
    final isRestDay = workout.isRestDay;

    // Compact workout card for narrow columns
    Widget workoutCard = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color:
            isCompleted
                ? Colors.green.withValues(alpha: 0.15)
                : isMissed
                ? Colors.orange.withValues(alpha: 0.15)
                : context.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              isCompleted
                  ? Colors.green.withValues(alpha: 0.4)
                  : isMissed
                  ? Colors.orange.withValues(alpha: 0.4)
                  : context.borderSubtle,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status bar at top
          Container(
            width: double.infinity,
            height: 3,
            margin: const EdgeInsets.only(bottom: 4),
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
          // Workout name
          Text(
            _getCleanWorkoutName(workout.workoutName),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // Exercise count
          Text(
            '${workout.exerciseCount} ex',
            style: TextStyle(fontSize: 9, color: context.textTertiary),
          ),
          // Status icon
          if (isCompleted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(Icons.check_circle, size: 14, color: Colors.green),
            )
          else if (!isRestDay)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(
                Icons.drag_indicator,
                size: 12,
                color: context.textTertiary,
              ),
            ),
        ],
      ),
    );

    // Make draggable if not rest day and not completed
    if (!isRestDay && !isCompleted) {
      return LongPressDraggable<ProgramWorkout>(
        data: workout,
        delay: const Duration(milliseconds: 150),
        hapticFeedbackOnStart: true,
        onDragStarted: () {
          HapticFeedback.mediumImpact();
          setState(() {
            _isDragging = true;
            _draggedFromDay = dayNumber;
          });
        },
        onDragEnd: (details) {
          setState(() {
            _isDragging = false;
            _draggedFromDay = null;
          });
        },
        onDraggableCanceled: (velocity, offset) {
          setState(() {
            _isDragging = false;
            _draggedFromDay = null;
          });
        },
        feedback: Transform.scale(
          scale: 1.1,
          child: Material(
            elevation: 16,
            shadowColor: theme.primaryColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.primaryColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fitness_center_rounded,
                    size: 20,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getCleanWorkoutName(workout.workoutName),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${workout.exerciseCount} exercises',
                    style: TextStyle(fontSize: 9, color: context.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        childWhenDragging: Container(
          margin: const EdgeInsets.only(bottom: 4),
          height: 40,
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.primaryColor.withValues(alpha: 0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.drag_indicator,
              color: theme.primaryColor.withValues(alpha: 0.5),
              size: 16,
            ),
          ),
        ),
        child: GestureDetector(
          onTap:
              widget.onWorkoutTap != null
                  ? () => widget.onWorkoutTap!(workout)
                  : null,
          child: workoutCard,
        ),
      );
    }

    return GestureDetector(
      onTap:
          widget.onWorkoutTap != null
              ? () => widget.onWorkoutTap!(workout)
              : null,
      child: workoutCard,
    );
  }
}
