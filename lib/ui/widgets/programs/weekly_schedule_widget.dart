import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';

/// Widget that displays a 7-day weekly schedule with enhanced drag-and-drop
/// Redesigned with a timeline-style vertical layout for better multi-workout support
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

class _WeeklyScheduleWidgetState extends State<WeeklyScheduleWidget>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  int? _draggedFromDay;
  int? _hoveredDay;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

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
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(theme),

          // Drag hint
          _buildDragHint(theme),

          // Timeline days
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: List.generate(7, (index) {
                final dayNumber = index + 1;
                final isLast = dayNumber == 7;
                return _buildDayRow(
                  context,
                  dayNumber,
                  weekWorkouts[index],
                  theme,
                  todayNumber,
                  isLast,
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor.withValues(alpha: 0.08),
            theme.primaryColor.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              size: 24,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Week ${widget.program.currentWeek}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.program.totalWeeks - widget.program.currentWeek + 1} weeks remaining • ${widget.program.phaseName}',
                  style: TextStyle(fontSize: 13, color: context.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.primaryColor,
                  theme.primaryColor.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: theme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              '${widget.program.progressPercentage.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHint(ThemeData theme) {
    return AnimatedOpacity(
      opacity: _isDragging ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swipe_rounded, size: 18, color: theme.primaryColor),
            const SizedBox(width: 8),
            Text(
              'Hold & drag workouts to reschedule',
              style: TextStyle(
                fontSize: 13,
                color: theme.primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayRow(
    BuildContext context,
    int dayNumber,
    List<ProgramWorkout> workouts,
    ThemeData theme,
    int todayNumber,
    bool isLast,
  ) {
    final isToday = dayNumber == todayNumber;
    final hasWorkout = workouts.isNotEmpty;
    final allCompleted = hasWorkout && workouts.every((w) => w.isCompleted);
    final hasMissed = workouts.any((w) => widget.program.isWorkoutMissed(w));
    final isHovered = _hoveredDay == dayNumber;
    final isDragSource = _draggedFromDay == dayNumber;

    return DragTarget<ProgramWorkout>(
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
          _draggedFromDay = null;
          _hoveredDay = null;
        });
      },
      onLeave: (data) {
        setState(() => _hoveredDay = null);
      },
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty || isHovered;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.only(bottom: isLast ? 0 : 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline indicator
              _buildTimelineIndicator(
                theme,
                isToday,
                allCompleted,
                hasMissed,
                hasWorkout,
                isLast,
                isHighlighted,
              ),

              // Day badge
              _buildDayBadge(
                theme,
                dayNumber,
                isToday,
                allCompleted,
                hasMissed,
                isHighlighted,
              ),

              const SizedBox(width: 12),

              // Workouts area
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isHighlighted
                            ? theme.primaryColor.withValues(alpha: 0.1)
                            : isDragSource
                            ? context.surface.withValues(alpha: 0.3)
                            : context.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          isHighlighted
                              ? theme.primaryColor
                              : isToday
                              ? theme.primaryColor.withValues(alpha: 0.4)
                              : context.borderSubtle,
                      width: isHighlighted ? 2 : 1,
                    ),
                    boxShadow:
                        isHighlighted
                            ? [
                              BoxShadow(
                                color: theme.primaryColor.withValues(
                                  alpha: 0.15,
                                ),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                            : null,
                  ),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: isDragSource ? 0.4 : 1.0,
                    child:
                        workouts.isEmpty
                            ? _buildRestDayContent(context, theme)
                            : _buildWorkoutsContent(
                              context,
                              workouts,
                              theme,
                              dayNumber,
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

  Widget _buildTimelineIndicator(
    ThemeData theme,
    bool isToday,
    bool allCompleted,
    bool hasMissed,
    bool hasWorkout,
    bool isLast,
    bool isHighlighted,
  ) {
    Color dotColor;
    if (isHighlighted) {
      dotColor = theme.primaryColor;
    } else if (allCompleted) {
      dotColor = Colors.green;
    } else if (hasMissed) {
      dotColor = Colors.orange;
    } else if (isToday) {
      dotColor = theme.primaryColor;
    } else if (hasWorkout) {
      dotColor = context.textTertiary;
    } else {
      dotColor = context.borderSubtle;
    }

    return SizedBox(
      width: 24,
      child: Column(
        children: [
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation:
                isToday ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
            builder: (context, child) {
              return Transform.scale(
                scale: isToday ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow:
                        isToday || isHighlighted
                            ? [
                              BoxShadow(
                                color: dotColor.withValues(alpha: 0.4),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                            : null,
                  ),
                  child:
                      allCompleted
                          ? const Icon(
                            Icons.check,
                            size: 8,
                            color: Colors.white,
                          )
                          : null,
                ),
              );
            },
          ),
          if (!isLast)
            Container(
              width: 2,
              height: 40,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    dotColor.withValues(alpha: 0.5),
                    context.borderSubtle.withValues(alpha: 0.3),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayBadge(
    ThemeData theme,
    int dayNumber,
    bool isToday,
    bool allCompleted,
    bool hasMissed,
    bool isHighlighted,
  ) {
    Color bgColor;
    Color textColor;

    if (isHighlighted) {
      bgColor = theme.primaryColor;
      textColor = Colors.white;
    } else if (isToday) {
      bgColor = theme.primaryColor;
      textColor = Colors.white;
    } else if (allCompleted) {
      bgColor = Colors.green;
      textColor = Colors.white;
    } else if (hasMissed) {
      bgColor = Colors.orange;
      textColor = Colors.white;
    } else {
      bgColor = context.surface;
      textColor = context.textSecondary;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow:
            isToday || isHighlighted
                ? [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
                : null,
      ),
      child: Column(
        children: [
          Text(
            _getWeekdayName(dayNumber),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (isToday) ...[
            const SizedBox(height: 2),
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRestDayContent(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.textTertiary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.self_improvement_rounded,
            size: 20,
            color: context.textTertiary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Rest Day',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: context.textTertiary,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.spa_outlined,
          size: 16,
          color: context.textTertiary.withValues(alpha: 0.5),
        ),
      ],
    );
  }

  Widget _buildWorkoutsContent(
    BuildContext context,
    List<ProgramWorkout> workouts,
    ThemeData theme,
    int dayNumber,
  ) {
    // For single workout, show inline
    if (workouts.length == 1) {
      return _buildSingleWorkoutRow(context, workouts.first, theme, dayNumber);
    }

    // For multiple workouts, show as horizontal scrollable chips
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${workouts.length} workouts',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.primaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children:
                workouts.asMap().entries.map((entry) {
                  final index = entry.key;
                  final workout = entry.value;
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index < workouts.length - 1 ? 10 : 0,
                    ),
                    child: _buildWorkoutChip(
                      context,
                      workout,
                      theme,
                      dayNumber,
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleWorkoutRow(
    BuildContext context,
    ProgramWorkout workout,
    ThemeData theme,
    int dayNumber,
  ) {
    final isCompleted = workout.isCompleted;
    final isMissed = widget.program.isWorkoutMissed(workout);
    final isRestDay = workout.isRestDay;

    Color accentColor;
    if (isCompleted) {
      accentColor = Colors.green;
    } else if (isMissed) {
      accentColor = Colors.orange;
    } else {
      accentColor = theme.primaryColor;
    }

    Widget content = Row(
      children: [
        // Accent bar
        Container(
          width: 4,
          height: 44,
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
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 3),
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
                    style: TextStyle(fontSize: 12, color: context.textTertiary),
                  ),
                  if (workout.estimatedDuration != null) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.schedule_rounded,
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

        // Status/Drag indicator
        if (isCompleted)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 18,
              color: Colors.green,
            ),
          )
        else if (!isRestDay)
          Icon(
            Icons.drag_indicator_rounded,
            size: 20,
            color: context.textTertiary,
          ),
      ],
    );

    // Wrap with drag functionality
    if (!isRestDay && !isCompleted) {
      return _wrapWithDraggable(content, workout, theme, dayNumber);
    }

    return GestureDetector(
      onTap:
          widget.onWorkoutTap != null
              ? () => widget.onWorkoutTap!(workout)
              : null,
      child: content,
    );
  }

  Widget _buildWorkoutChip(
    BuildContext context,
    ProgramWorkout workout,
    ThemeData theme,
    int dayNumber,
  ) {
    final isCompleted = workout.isCompleted;
    final isMissed = widget.program.isWorkoutMissed(workout);
    final isRestDay = workout.isRestDay;

    Color accentColor;
    Color bgColor;
    if (isCompleted) {
      accentColor = Colors.green;
      bgColor = Colors.green.withValues(alpha: 0.1);
    } else if (isMissed) {
      accentColor = Colors.orange;
      bgColor = Colors.orange.withValues(alpha: 0.1);
    } else {
      accentColor = theme.primaryColor;
      bgColor = theme.primaryColor.withValues(alpha: 0.08);
    }

    Widget chip = Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _getCleanWorkoutName(workout.workoutName),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCompleted) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_circle, size: 14, color: Colors.green),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fitness_center_rounded,
                size: 11,
                color: context.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                '${workout.exerciseCount} ex.',
                style: TextStyle(fontSize: 11, color: context.textTertiary),
              ),
              if (!isRestDay && !isCompleted) ...[
                const Spacer(),
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 14,
                  color: context.textTertiary,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // Wrap with drag functionality
    if (!isRestDay && !isCompleted) {
      return _wrapWithDraggable(chip, workout, theme, dayNumber);
    }

    return GestureDetector(
      onTap:
          widget.onWorkoutTap != null
              ? () => widget.onWorkoutTap!(workout)
              : null,
      child: chip,
    );
  }

  Widget _wrapWithDraggable(
    Widget child,
    ProgramWorkout workout,
    ThemeData theme,
    int dayNumber,
  ) {
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
          _hoveredDay = null;
        });
      },
      onDraggableCanceled: (velocity, offset) {
        setState(() {
          _isDragging = false;
          _draggedFromDay = null;
          _hoveredDay = null;
        });
      },
      feedback: Transform.scale(
        scale: 1.05,
        child: Material(
          elevation: 20,
          shadowColor: theme.primaryColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 180,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.primaryColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: theme.primaryColor.withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.fitness_center_rounded,
                    size: 24,
                    color: theme.primaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _getCleanWorkoutName(workout.workoutName),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${workout.exerciseCount} exercises',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Drop on a day',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.primaryColor.withValues(alpha: 0.2),
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Icon(
              Icons.open_with_rounded,
              color: theme.primaryColor.withValues(alpha: 0.4),
              size: 24,
            ),
          ),
        ),
      ),
      child: GestureDetector(
        onTap:
            widget.onWorkoutTap != null
                ? () => widget.onWorkoutTap!(workout)
                : null,
        child: child,
      ),
    );
  }
}
