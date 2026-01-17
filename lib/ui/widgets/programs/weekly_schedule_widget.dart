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
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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

          // Horizontal scrollable days
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: 7,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 150,
                  child: _buildDayCard(
                    context,
                    index + 1,
                    weekWorkouts[index],
                    theme,
                    todayNumber,
                  ),
                );
              },
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
          transform: Matrix4.identity()..scale(isHighlighted ? 1.02 : 1.0),
          decoration: BoxDecoration(
            color:
                isHighlighted
                    ? theme.primaryColor.withValues(alpha: 0.15)
                    : isDragSource
                    ? context.surface.withValues(alpha: 0.5)
                    : isToday
                    ? theme.primaryColor.withValues(alpha: 0.08)
                    : context.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isHighlighted
                      ? theme.primaryColor
                      : isToday
                      ? theme.primaryColor
                      : allCompleted
                      ? Colors.green.withValues(alpha: 0.5)
                      : context.border,
              width: isHighlighted || isToday ? 2.5 : 1,
            ),
            boxShadow:
                isHighlighted
                    ? [
                      BoxShadow(
                        color: theme.primaryColor.withValues(alpha: 0.2),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                    : null,
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isDragSource ? 0.4 : 1.0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Day header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isToday
                                  ? theme.primaryColor
                                  : allCompleted
                                  ? Colors.green
                                  : hasMissed
                                  ? Colors.orange
                                  : theme.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _getWeekdayName(dayNumber),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color:
                                isToday || allCompleted || hasMissed
                                    ? Colors.white
                                    : theme.primaryColor,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'TODAY',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        )
                      else if (allCompleted)
                        const Icon(
                          Icons.check_circle,
                          size: 18,
                          color: Colors.green,
                        )
                      else if (hasMissed)
                        const Icon(
                          Icons.warning_rounded,
                          size: 18,
                          color: Colors.orange,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Workouts list or rest day
                  Expanded(
                    child:
                        workouts.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.spa_rounded,
                                    size: 28,
                                    color: context.textTertiary,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Rest Day',
                                    style: TextStyle(
                                      fontSize: 12,
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

    Widget workoutCard = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            isCompleted
                ? Colors.green.withValues(alpha: 0.1)
                : isMissed
                ? Colors.orange.withValues(alpha: 0.1)
                : context.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              isCompleted
                  ? Colors.green.withValues(alpha: 0.3)
                  : isMissed
                  ? Colors.orange.withValues(alpha: 0.3)
                  : context.borderSubtle,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status indicator bar
              Container(
                width: 4,
                height: 32,
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
              const SizedBox(width: 10),
              // Workout info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getCleanWorkoutName(workout.workoutName),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.fitness_center_rounded,
                          size: 12,
                          color: context.textTertiary,
                        ),
                        const SizedBox(width: 4),
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
              // Status or drag handle
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Colors.green),
                )
              else if (!isRestDay)
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: context.textTertiary,
                ),
            ],
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
          scale: 1.05,
          child: Material(
            elevation: 20,
            shadowColor: theme.primaryColor.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 180,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.primaryColor, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      size: 18,
                      color: theme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getCleanWorkoutName(workout.workoutName),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${workout.exerciseCount} exercises',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        childWhenDragging: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 8),
          height: 60,
          decoration: BoxDecoration(
            color: context.border.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.border, style: BorderStyle.solid),
          ),
          child: Center(
            child: Icon(
              Icons.add_rounded,
              color: context.textTertiary,
              size: 20,
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
