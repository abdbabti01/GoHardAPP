import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';

/// Simple weekly schedule widget - shows all workouts at a glance
/// No tap to expand - workouts visible directly under each day
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

  List<List<ProgramWorkout>> _getThisWeeksWorkouts() {
    if (widget.program.workouts == null) return List.generate(7, (_) => []);

    final currentWeek = widget.program.currentWeek;
    final weekWorkouts = <List<ProgramWorkout>>[];

    for (int day = 1; day <= 7; day++) {
      final dayWorkouts =
          widget.program.workouts!
              .where((w) => w.weekNumber == currentWeek && w.dayNumber == day)
              .toList()
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      weekWorkouts.add(dayWorkouts);
    }

    return weekWorkouts;
  }

  String _getDayLabel(int dayNumber) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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

  String _cleanName(String name) {
    final colonIndex = name.indexOf(':');
    if (colonIndex != -1 && colonIndex < 15) {
      return name.substring(colonIndex + 1).trim();
    }
    return name;
  }

  Future<void> _moveWorkout(ProgramWorkout workout, int newDay) async {
    if (!mounted) return;

    final provider = context.read<ProgramsProvider>();
    HapticFeedback.mediumImpact();

    final updated = workout.copyWith(
      dayNumber: newDay,
      orderIndex: newDay * 10,
    );
    final success = await provider.updateWorkout(workout.id, updated);

    if (!mounted) return;

    if (success) {
      widget.onWorkoutMoved?.call();
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved to ${_getFullDayName(newDay)}'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  int _getToday() => DateTime.now().weekday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workouts = _getThisWeeksWorkouts();
    final today = _getToday();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'Week ${widget.program.currentWeek}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              if (_isDragging)
                Text(
                  'Drop on a day',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                Text(
                  '${widget.program.completedWorkoutsCount}/${widget.program.totalWorkoutsCount}',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 7-day grid - 2 rows
          _buildWeekGrid(context, workouts, theme, today),
        ],
      ),
    );
  }

  Widget _buildWeekGrid(
    BuildContext context,
    List<List<ProgramWorkout>> workouts,
    ThemeData theme,
    int today,
  ) {
    return Column(
      children: [
        // Row 1: Mon-Thu
        Row(
          children: List.generate(4, (i) {
            final day = i + 1;
            return Expanded(
              child: _buildDayColumn(context, day, workouts[i], theme, today),
            );
          }),
        ),
        const SizedBox(height: 8),
        // Row 2: Fri-Sun (+ empty space)
        Row(
          children: [
            ...List.generate(3, (i) {
              final day = i + 5;
              return Expanded(
                child: _buildDayColumn(
                  context,
                  day,
                  workouts[day - 1],
                  theme,
                  today,
                ),
              );
            }),
            const Expanded(child: SizedBox()), // Empty 4th column for balance
          ],
        ),
      ],
    );
  }

  Widget _buildDayColumn(
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
        if (d.data.dayNumber != day) {
          await _moveWorkout(d.data, day);
        }
        setState(() {
          _isDragging = false;
          _hoveredDay = null;
        });
      },
      onLeave: (_) => setState(() => _hoveredDay = null),
      builder: (context, candidates, rejected) {
        final isTarget = candidates.isNotEmpty || isHovered;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color:
                isTarget
                    ? theme.primaryColor.withValues(alpha: 0.15)
                    : isToday
                    ? theme.primaryColor.withValues(alpha: 0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  isTarget
                      ? theme.primaryColor
                      : isToday
                      ? theme.primaryColor.withValues(alpha: 0.3)
                      : Colors.transparent,
              width: isTarget ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              // Day label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      isToday
                          ? theme.primaryColor
                          : allDone
                          ? Colors.green
                          : hasMissed
                          ? Colors.orange
                          : context.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _getDayLabel(day),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color:
                        isToday || allDone || hasMissed
                            ? Colors.white
                            : context.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Workouts - shown directly
              if (!hasWorkouts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Rest',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                ...dayWorkouts.map(
                  (w) => _buildWorkoutChip(context, w, theme, day),
                ),
            ],
          ),
        );
      },
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

    Color color;
    if (done) {
      color = Colors.green;
    } else if (missed) {
      color = Colors.orange;
    } else {
      color = theme.primaryColor;
    }

    Widget chip = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(Icons.check, size: 10, color: Colors.green),
            ),
          Flexible(
            child: Text(
              _cleanName(workout.workoutName),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    // Draggable if not completed and not rest day
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
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.primaryColor, width: 2),
            ),
            child: Text(
              _cleanName(workout.workoutName),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
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
