import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';

/// Compact weekly schedule widget with drag-and-drop support
/// Shows days as horizontal strip with expandable workout lists
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
  int? _hoveredDay;
  int? _expandedDay;

  List<List<ProgramWorkout>> _getThisWeeksWorkouts(Program program) {
    if (program.workouts == null) return List.generate(7, (_) => []);

    final currentWeek = program.currentWeek;
    final weekWorkouts = <List<ProgramWorkout>>[];

    for (int day = 1; day <= 7; day++) {
      final dayWorkouts =
          program.workouts!
              .where((w) => w.weekNumber == currentWeek && w.dayNumber == day)
              .toList()
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      weekWorkouts.add(dayWorkouts);
    }

    return weekWorkouts;
  }

  String _getDayAbbr(int dayNumber) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return days[dayNumber - 1];
  }

  String _getFullDayName(int dayNumber) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[dayNumber - 1];
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

    HapticFeedback.mediumImpact();

    try {
      final updatedWorkout = workout.copyWith(
        dayNumber: newDayNumber,
        orderIndex: newDayNumber * 10, // Space for multiple workouts per day
      );

      final success = await provider.updateWorkout(
        updatedWorkout.id,
        updatedWorkout,
      );

      if (!context.mounted) return;

      if (success) {
        // Force rebuild with new data
        setState(() {
          _expandedDay = newDayNumber;
        });
        widget.onWorkoutMoved?.call();
        HapticFeedback.lightImpact();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Moved to ${_getFullDayName(newDayNumber)}'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
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

  int _getTodayDayNumber() => DateTime.now().weekday;

  @override
  Widget build(BuildContext context) {
    // Watch provider for changes
    final provider = context.watch<ProgramsProvider>();
    final program =
        provider.getProgramFromCache(widget.program.id) ?? widget.program;

    final theme = Theme.of(context);
    final weekWorkouts = _getThisWeeksWorkouts(program);
    final todayNumber = _getTodayDayNumber();

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Compact Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: theme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Week ${program.currentWeek}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                const Spacer(),
                if (_isDragging)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_with,
                          size: 14,
                          color: theme.primaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Drop on a day',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    '${program.completedWorkoutsCount}/${program.totalWorkoutsCount} done',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
              ],
            ),
          ),

          // Days Strip - Horizontal scrollable
          SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 7,
              itemBuilder: (context, index) {
                final dayNumber = index + 1;
                return _buildDayChip(
                  context,
                  dayNumber,
                  weekWorkouts[index],
                  theme,
                  todayNumber,
                  program,
                );
              },
            ),
          ),

          // Expanded workouts for selected day
          if (_expandedDay != null) ...[
            const Divider(height: 1),
            _buildExpandedDayWorkouts(
              context,
              _expandedDay!,
              weekWorkouts[_expandedDay! - 1],
              theme,
              program,
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDayChip(
    BuildContext context,
    int dayNumber,
    List<ProgramWorkout> workouts,
    ThemeData theme,
    int todayNumber,
    Program program,
  ) {
    final isToday = dayNumber == todayNumber;
    final hasWorkout = workouts.isNotEmpty;
    final allCompleted = hasWorkout && workouts.every((w) => w.isCompleted);
    final hasMissed = workouts.any((w) => program.isWorkoutMissed(w));
    final isExpanded = _expandedDay == dayNumber;
    final isHovered = _hoveredDay == dayNumber;

    Color bgColor;
    Color textColor;
    Color borderColor;

    if (isHovered && _isDragging) {
      bgColor = theme.primaryColor;
      textColor = Colors.white;
      borderColor = theme.primaryColor;
    } else if (isExpanded) {
      bgColor = theme.primaryColor.withValues(alpha: 0.15);
      textColor = theme.primaryColor;
      borderColor = theme.primaryColor;
    } else if (isToday) {
      bgColor = theme.primaryColor;
      textColor = Colors.white;
      borderColor = theme.primaryColor;
    } else if (allCompleted) {
      bgColor = Colors.green.withValues(alpha: 0.15);
      textColor = Colors.green;
      borderColor = Colors.green;
    } else if (hasMissed) {
      bgColor = Colors.orange.withValues(alpha: 0.15);
      textColor = Colors.orange;
      borderColor = Colors.orange;
    } else if (hasWorkout) {
      bgColor = context.surface;
      textColor = context.textPrimary;
      borderColor = context.border;
    } else {
      bgColor = context.surface;
      textColor = context.textTertiary;
      borderColor = context.borderSubtle;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: DragTarget<ProgramWorkout>(
        onWillAcceptWithDetails: (details) {
          HapticFeedback.selectionClick();
          setState(() => _hoveredDay = dayNumber);
          return true;
        },
        onAcceptWithDetails: (details) async {
          final draggedWorkout = details.data;
          if (draggedWorkout.dayNumber != dayNumber) {
            await _updateWorkoutDay(context, draggedWorkout, dayNumber);
          }
          setState(() {
            _isDragging = false;
            _hoveredDay = null;
          });
        },
        onLeave: (data) => setState(() => _hoveredDay = null),
        builder: (context, candidateData, rejectedData) {
          final isDropTarget = candidateData.isNotEmpty || isHovered;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            transform: Matrix4.identity()..scale(isDropTarget ? 1.1 : 1.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _expandedDay = _expandedDay == dayNumber ? null : dayNumber;
                });
              },
              child: Container(
                width: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: borderColor,
                    width: isDropTarget ? 2 : 1,
                  ),
                  boxShadow:
                      isDropTarget
                          ? [
                            BoxShadow(
                              color: theme.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                          : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _getDayAbbr(dayNumber),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Workout indicator dots
                    if (hasWorkout)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          workouts.length.clamp(1, 3),
                          (i) => Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color:
                                  allCompleted
                                      ? Colors.green
                                      : hasMissed
                                      ? Colors.orange
                                      : isToday
                                      ? Colors.white
                                      : theme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExpandedDayWorkouts(
    BuildContext context,
    int dayNumber,
    List<ProgramWorkout> workouts,
    ThemeData theme,
    Program program,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day title
          Row(
            children: [
              Text(
                _getFullDayName(dayNumber),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: context.textSecondary),
                onPressed: () => setState(() => _expandedDay = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Workouts list
          if (workouts.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.self_improvement,
                    size: 20,
                    color: context.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Rest Day',
                    style: TextStyle(fontSize: 14, color: context.textTertiary),
                  ),
                ],
              ),
            )
          else
            ...workouts.map(
              (workout) => _buildWorkoutTile(
                context,
                workout,
                theme,
                dayNumber,
                program,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkoutTile(
    BuildContext context,
    ProgramWorkout workout,
    ThemeData theme,
    int dayNumber,
    Program program,
  ) {
    final isCompleted = workout.isCompleted;
    final isMissed = program.isWorkoutMissed(workout);
    final isRestDay = workout.isRestDay;

    Color accentColor;
    if (isCompleted) {
      accentColor = Colors.green;
    } else if (isMissed) {
      accentColor = Colors.orange;
    } else {
      accentColor = theme.primaryColor;
    }

    Widget tile = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
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
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: 12,
                      color: context.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${workout.exerciseCount} exercises',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textTertiary,
                      ),
                    ),
                    if (workout.estimatedDuration != null) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.schedule,
                        size: 12,
                        color: context.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${workout.estimatedDuration} min',
                        style: TextStyle(
                          fontSize: 12,
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
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 16, color: Colors.green),
            )
          else if (!isRestDay)
            Icon(Icons.drag_indicator, size: 20, color: context.textTertiary),
        ],
      ),
    );

    // Wrap with drag functionality
    if (!isRestDay && !isCompleted) {
      return LongPressDraggable<ProgramWorkout>(
        data: workout,
        delay: const Duration(milliseconds: 150),
        hapticFeedbackOnStart: true,
        onDragStarted: () {
          HapticFeedback.mediumImpact();
          setState(() {
            _isDragging = true;
          });
        },
        onDragEnd: (details) {
          setState(() {
            _isDragging = false;
            _hoveredDay = null;
          });
        },
        onDraggableCanceled: (velocity, offset) {
          setState(() {
            _isDragging = false;
            _hoveredDay = null;
          });
        },
        feedback: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(12),
          shadowColor: theme.primaryColor.withValues(alpha: 0.3),
          child: Container(
            width: 200,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.primaryColor, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fitness_center, size: 24, color: theme.primaryColor),
                const SizedBox(height: 8),
                Text(
                  _getCleanWorkoutName(workout.workoutName),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${workout.exerciseCount} exercises',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: GestureDetector(
          onTap:
              widget.onWorkoutTap != null
                  ? () => widget.onWorkoutTap!(workout)
                  : null,
          child: tile,
        ),
      );
    }

    return GestureDetector(
      onTap:
          widget.onWorkoutTap != null
              ? () => widget.onWorkoutTap!(workout)
              : null,
      child: tile,
    );
  }
}
