import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';

/// Clean, aligned weekly schedule widget with drag-and-drop
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

  List<List<ProgramWorkout>> _getWeekWorkouts() {
    if (widget.program.workouts == null) return List.generate(7, (_) => []);

    final week = widget.program.currentWeek;
    return List.generate(7, (i) {
      final day = i + 1;
      return widget.program.workouts!
          .where((w) => w.weekNumber == week && w.dayNumber == day)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    });
  }

  /// Get the actual date for a specific day in the current week
  DateTime _getDateForDay(int dayNumber) {
    final localStartDate = widget.program.startDate.toLocal();
    final week = widget.program.currentWeek;
    return localStartDate.add(
      Duration(days: (week - 1) * 7 + (dayNumber - 1)),
    );
  }

  /// Get short day label from actual date
  String _dayLabel(int day) {
    final date = _getDateForDay(day);
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[date.weekday - 1];
  }

  /// Get full day name from actual date
  String _dayFull(int day) {
    final date = _getDateForDay(day);
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[date.weekday - 1];
  }

  String _cleanName(String name) {
    final i = name.indexOf(':');
    return (i != -1 && i < 15) ? name.substring(i + 1).trim() : name;
  }

  Future<void> _moveWorkout(ProgramWorkout workout, int newDay) async {
    if (!mounted) return;
    final provider = context.read<ProgramsProvider>();
    HapticFeedback.mediumImpact();

    final success = await provider.updateWorkout(
      workout.id,
      workout.copyWith(dayNumber: newDay, orderIndex: newDay * 10),
    );

    if (mounted && success) {
      widget.onWorkoutMoved?.call();
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved to ${_dayFull(newDay)}'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workouts = _getWeekWorkouts();
    final today = DateTime.now().weekday;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Week ${widget.program.currentWeek}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              if (_isDragging)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Drop on a day',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Text(
                  '${widget.program.completedWorkoutsCount} of ${widget.program.totalWorkoutsCount} done',
                  style: TextStyle(fontSize: 13, color: context.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Week grid (3 columns per row)
          _buildWeekRow(context, workouts, theme, today, 1, 3),
          const SizedBox(height: 12),
          _buildWeekRow(context, workouts, theme, today, 4, 6),
          const SizedBox(height: 12),
          _buildWeekRow(context, workouts, theme, today, 7, 7),
        ],
      ),
    );
  }

  Widget _buildWeekRow(
    BuildContext context,
    List<List<ProgramWorkout>> workouts,
    ThemeData theme,
    int today,
    int startDay,
    int endDay,
  ) {
    final count = endDay - startDay + 1;
    final items = List.generate(count, (i) {
      final day = startDay + i;
      return _buildDayCell(context, day, workouts[day - 1], theme, today);
    });

    // Pad to 3 columns for alignment
    while (items.length < 3) {
      items.add(const Expanded(child: SizedBox()));
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children:
            items.map((item) {
              if (item is Expanded) return item;
              return Expanded(child: item);
            }).toList(),
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    int day,
    List<ProgramWorkout> dayWorkouts,
    ThemeData theme,
    int today,
  ) {
    final isToday = day == today;
    final hasWorkouts = dayWorkouts.isNotEmpty;
    final allDone = hasWorkouts && dayWorkouts.every((w) => w.isCompleted);
    final hasMissed = dayWorkouts.any((w) => widget.program.isWorkoutMissed(w));
    final isHovered = _hoveredDay == day && _isDragging;

    return DragTarget<ProgramWorkout>(
      onWillAcceptWithDetails: (d) {
        HapticFeedback.selectionClick();
        setState(() => _hoveredDay = day);
        return true;
      },
      onAcceptWithDetails: (d) async {
        if (d.data.dayNumber != day) await _moveWorkout(d.data, day);
        setState(() {
          _isDragging = false;
          _hoveredDay = null;
        });
      },
      onLeave: (_) => setState(() => _hoveredDay = null),
      builder: (context, candidates, _) {
        final isTarget = candidates.isNotEmpty || isHovered;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color:
                isTarget
                    ? theme.primaryColor.withValues(alpha: 0.12)
                    : isToday
                    ? theme.primaryColor.withValues(alpha: 0.06)
                    : context.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isTarget
                      ? theme.primaryColor
                      : isToday
                      ? theme.primaryColor.withValues(alpha: 0.4)
                      : context.borderSubtle,
              width: isTarget ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Day label badge
              _buildDayBadge(context, day, theme, isToday, allDone, hasMissed),
              const SizedBox(height: 10),

              // Workouts or Rest
              Expanded(
                child:
                    hasWorkouts
                        ? Column(
                          children:
                              dayWorkouts
                                  .map(
                                    (w) => _buildWorkoutChip(
                                      context,
                                      w,
                                      theme,
                                      day,
                                    ),
                                  )
                                  .toList(),
                        )
                        : Center(
                          child: Text(
                            'Rest',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textTertiary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDayBadge(
    BuildContext context,
    int day,
    ThemeData theme,
    bool isToday,
    bool allDone,
    bool hasMissed,
  ) {
    Color bgColor;
    Color textColor;

    if (isToday) {
      bgColor = theme.primaryColor;
      textColor = Colors.white;
    } else if (allDone) {
      bgColor = Colors.green;
      textColor = Colors.white;
    } else if (hasMissed) {
      bgColor = Colors.orange;
      textColor = Colors.white;
    } else {
      bgColor = context.surfaceElevated;
      textColor = context.textSecondary;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _dayLabel(day),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          if (allDone && !isToday) ...[
            const SizedBox(width: 4),
            Icon(Icons.check, size: 12, color: textColor),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkoutChip(
    BuildContext context,
    ProgramWorkout workout,
    ThemeData theme,
    int day,
  ) {
    final done = workout.isCompleted;
    final missed = widget.program.isWorkoutMissed(workout);
    final isRest = workout.isRestDay;

    final color =
        done
            ? Colors.green
            : missed
            ? Colors.orange
            : theme.primaryColor;

    Widget chip = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          if (done)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.check_circle, size: 14, color: Colors.green),
            ),
          Expanded(
            child: Text(
              _cleanName(workout.workoutName),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (!done && !isRest) {
      return LongPressDraggable<ProgramWorkout>(
        data: workout,
        delay: const Duration(milliseconds: 150),
        hapticFeedbackOnStart: true,
        onDragStarted: () {
          HapticFeedback.mediumImpact();
          setState(() => _isDragging = true);
        },
        onDragEnd:
            (_) => setState(() {
              _isDragging = false;
              _hoveredDay = null;
            }),
        onDraggableCanceled:
            (_, __) => setState(() {
              _isDragging = false;
              _hoveredDay = null;
            }),
        feedback: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(10),
          shadowColor: theme.primaryColor.withValues(alpha: 0.3),
          child: Container(
            width: 160,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.primaryColor, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fitness_center, size: 20, color: theme.primaryColor),
                const SizedBox(height: 8),
                Text(
                  _cleanName(workout.workoutName),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: chip),
        child: GestureDetector(
          onTap:
              widget.onWorkoutTap != null
                  ? () => widget.onWorkoutTap!(workout)
                  : null,
          child: chip,
        ),
      );
    }

    return GestureDetector(
      onTap:
          widget.onWorkoutTap != null
              ? () => widget.onWorkoutTap!(workout)
              : null,
      child: chip,
    );
  }
}
