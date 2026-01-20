import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../../../providers/programs_provider.dart';

/// Premium horizontal week calendar widget with drag-and-drop rescheduling
/// Compact view that expands to fullscreen modal for drag-and-drop
class PremiumWeekCalendarWidget extends StatefulWidget {
  final Program program;
  final int selectedWeek;
  final Function(int) onWeekChanged;
  final Function(ProgramWorkout)? onWorkoutTap;
  final VoidCallback? onWorkoutMoved;

  const PremiumWeekCalendarWidget({
    super.key,
    required this.program,
    required this.selectedWeek,
    required this.onWeekChanged,
    this.onWorkoutTap,
    this.onWorkoutMoved,
  });

  @override
  State<PremiumWeekCalendarWidget> createState() =>
      _PremiumWeekCalendarWidgetState();
}

class _PremiumWeekCalendarWidgetState extends State<PremiumWeekCalendarWidget> {
  /// Get ALL workouts for each day of the week (supports multiple per day)
  List<List<ProgramWorkout>> _getWeekWorkoutsGrouped(int weekNumber) {
    if (widget.program.workouts == null) return List.generate(7, (_) => []);

    return List.generate(7, (dayIndex) {
      final day = dayIndex + 1;
      return widget.program.workouts!
          .where((w) => w.weekNumber == weekNumber && w.dayNumber == day)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    });
  }

  DateTime _getDateForDay(int weekNumber, int dayNumber) {
    return widget.program.startDate.add(
      Duration(days: (weekNumber - 1) * 7 + (dayNumber - 1)),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  void _openFullscreenCalendar() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FullscreenCalendarModal(
        program: widget.program,
        selectedWeek: widget.selectedWeek,
        onWeekChanged: widget.onWeekChanged,
        onWorkoutTap: widget.onWorkoutTap,
        onWorkoutMoved: widget.onWorkoutMoved,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupedWorkouts = _getWeekWorkoutsGrouped(widget.selectedWeek);
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return GestureDetector(
      onTap: _openFullscreenCalendar,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Week header with navigation hint
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Week ${widget.selectedWeek} of ${widget.program.totalWeeks}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getWeekDateRange(),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.open_in_full_rounded,
                        size: 14,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Tap to edit',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Compact day cells
            Row(
              children: List.generate(7, (index) {
                final dayNumber = index + 1;
                final date = _getDateForDay(widget.selectedWeek, dayNumber);
                final dayWorkouts = groupedWorkouts[index];
                final isToday = _isToday(date);
                final hasWorkouts = dayWorkouts.isNotEmpty;
                final allCompleted = hasWorkouts && dayWorkouts.every((w) => w.isCompleted);

                return Expanded(
                  child: _buildCompactDayCell(
                    theme,
                    dayLabels[index],
                    date.day,
                    hasWorkouts,
                    allCompleted,
                    isToday,
                    dayWorkouts.length,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  String _getWeekDateRange() {
    final weekStart = _getDateForDay(widget.selectedWeek, 1);
    final weekEnd = _getDateForDay(widget.selectedWeek, 7);
    final dateFormat = DateFormat('MMM d');
    return '${dateFormat.format(weekStart)} - ${dateFormat.format(weekEnd)}';
  }

  Widget _buildCompactDayCell(
    ThemeData theme,
    String dayLabel,
    int dateNumber,
    bool hasWorkouts,
    bool allCompleted,
    bool isToday,
    int workoutCount,
  ) {
    Color backgroundColor;
    Color textColor;
    Color labelColor;

    if (isToday) {
      backgroundColor = theme.primaryColor;
      textColor = Colors.white;
      labelColor = Colors.white.withValues(alpha: 0.8);
    } else {
      backgroundColor = Colors.transparent;
      textColor = context.textPrimary;
      labelColor = context.textTertiary;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dayLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$dateNumber',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          // Status indicator
          if (allCompleted)
            Icon(Icons.check_circle, size: 14, color: isToday ? Colors.white : AppColors.accentGreen)
          else if (hasWorkouts)
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: isToday ? Colors.white.withValues(alpha: 0.2) : theme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$workoutCount',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isToday ? Colors.white : theme.primaryColor,
                  ),
                ),
              ),
            )
          else
            Icon(
              Icons.remove,
              size: 14,
              color: isToday ? Colors.white.withValues(alpha: 0.5) : context.textTertiary,
            ),
        ],
      ),
    );
  }
}

/// Fullscreen calendar modal for drag-and-drop workout rescheduling
class _FullscreenCalendarModal extends StatefulWidget {
  final Program program;
  final int selectedWeek;
  final Function(int) onWeekChanged;
  final Function(ProgramWorkout)? onWorkoutTap;
  final VoidCallback? onWorkoutMoved;

  const _FullscreenCalendarModal({
    required this.program,
    required this.selectedWeek,
    required this.onWeekChanged,
    this.onWorkoutTap,
    this.onWorkoutMoved,
  });

  @override
  State<_FullscreenCalendarModal> createState() => _FullscreenCalendarModalState();
}

class _FullscreenCalendarModalState extends State<_FullscreenCalendarModal> {
  late int _currentWeek;
  late PageController _pageController;
  bool _isDragging = false;
  int? _dragTargetDay;

  @override
  void initState() {
    super.initState();
    _currentWeek = widget.selectedWeek;
    _pageController = PageController(initialPage: _currentWeek - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<List<ProgramWorkout>> _getWeekWorkoutsGrouped(int weekNumber) {
    if (widget.program.workouts == null) return List.generate(7, (_) => []);

    return List.generate(7, (dayIndex) {
      final day = dayIndex + 1;
      return widget.program.workouts!
          .where((w) => w.weekNumber == weekNumber && w.dayNumber == day)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    });
  }

  DateTime _getDateForDay(int weekNumber, int dayNumber) {
    return widget.program.startDate.add(
      Duration(days: (weekNumber - 1) * 7 + (dayNumber - 1)),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Future<void> _moveWorkout(ProgramWorkout workout, int newDay) async {
    if (!mounted) return;

    final provider = context.read<ProgramsProvider>();
    HapticFeedback.mediumImpact();

    final dayWorkouts = _getWeekWorkoutsGrouped(_currentWeek)[newDay - 1];
    final maxOrder = dayWorkouts.isEmpty
        ? 0
        : dayWorkouts.map((w) => w.orderIndex).reduce((a, b) => a > b ? a : b);

    final updatedWorkout = workout.copyWith(
      dayNumber: newDay,
      orderIndex: maxOrder + 10,
    );

    final success = await provider.updateWorkout(workout.id, updatedWorkout);

    if (mounted && success) {
      widget.onWorkoutMoved?.call();
      HapticFeedback.lightImpact();

      final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Moved "${_cleanWorkoutName(workout.workoutName)}" to ${dayNames[newDay - 1]}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _cleanWorkoutName(String name) {
    final colonIndex = name.indexOf(':');
    if (colonIndex != -1 && colonIndex < 15) {
      return name.substring(colonIndex + 1).trim();
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.85,
      decoration: BoxDecoration(
        color: context.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.textTertiary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Schedule',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        'Drag workouts to reschedule',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.surfaceHighlight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 20, color: context.textPrimary),
                  ),
                ),
              ],
            ),
          ),

          // Week navigation
          _buildWeekNavigation(theme),

          // Drag indicator when dragging
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _isDragging
                ? Container(
                    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor.withValues(alpha: 0.15),
                          AppColors.accentSky.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.swap_horiz_rounded, color: theme.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Drop on a day to reschedule',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 16),

          // Week calendar with PageView
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: _isDragging ? const NeverScrollableScrollPhysics() : null,
              onPageChanged: (page) {
                HapticFeedback.selectionClick();
                setState(() => _currentWeek = page + 1);
                widget.onWeekChanged(page + 1);
              },
              itemCount: widget.program.totalWeeks,
              itemBuilder: (context, weekIndex) {
                return _buildWeekContent(weekIndex + 1, theme);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekNavigation(ThemeData theme) {
    final weekStart = _getDateForDay(_currentWeek, 1);
    final weekEnd = _getDateForDay(_currentWeek, 7);
    final dateFormat = DateFormat('MMM d');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildNavButton(
            Icons.chevron_left_rounded,
            _currentWeek > 1 && !_isDragging,
            () {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            },
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Week $_currentWeek of ${widget.program.totalWeeks}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${dateFormat.format(weekStart)} - ${dateFormat.format(weekEnd)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _buildNavButton(
            Icons.chevron_right_rounded,
            _currentWeek < widget.program.totalWeeks && !_isDragging,
            () {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled ? context.surface : context.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? context.border : context.border.withValues(alpha: 0.3),
          ),
        ),
        child: Icon(
          icon,
          size: 24,
          color: enabled ? context.textPrimary : context.textTertiary,
        ),
      ),
    );
  }

  Widget _buildWeekContent(int weekNumber, ThemeData theme) {
    final groupedWorkouts = _getWeekWorkoutsGrouped(weekNumber);
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 7,
      itemBuilder: (context, index) {
        final dayNumber = index + 1;
        final date = _getDateForDay(weekNumber, dayNumber);
        final dayWorkouts = groupedWorkouts[index];
        final isToday = _isToday(date);
        final isDragTarget = _dragTargetDay == dayNumber;

        return DragTarget<ProgramWorkout>(
          onWillAcceptWithDetails: (details) {
            HapticFeedback.selectionClick();
            setState(() => _dragTargetDay = dayNumber);
            return true;
          },
          onAcceptWithDetails: (details) async {
            setState(() {
              _isDragging = false;
              _dragTargetDay = null;
            });
            await _moveWorkout(details.data, dayNumber);
          },
          onLeave: (_) {
            setState(() => _dragTargetDay = null);
          },
          builder: (context, candidateData, rejectedData) {
            return _buildDayRow(
              theme,
              dayLabels[index],
              date,
              dayWorkouts,
              isToday,
              isDragTarget,
            );
          },
        );
      },
    );
  }

  Widget _buildDayRow(
    ThemeData theme,
    String dayLabel,
    DateTime date,
    List<ProgramWorkout> workouts,
    bool isToday,
    bool isDragTarget,
  ) {
    final hasWorkouts = workouts.isNotEmpty;
    final allCompleted = hasWorkouts && workouts.every((w) => w.isCompleted);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDragTarget
            ? theme.primaryColor.withValues(alpha: 0.1)
            : isToday
                ? theme.primaryColor.withValues(alpha: 0.05)
                : context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDragTarget
              ? theme.primaryColor
              : isToday
                  ? theme.primaryColor.withValues(alpha: 0.5)
                  : context.border,
          width: isDragTarget ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isToday ? theme.primaryColor : context.surfaceHighlight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  dayLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isToday ? Colors.white : context.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('MMM d').format(date),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              if (allCompleted)
                Icon(Icons.check_circle, size: 18, color: AppColors.accentGreen)
              else if (hasWorkouts)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${workouts.length} workout${workouts.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryColor,
                    ),
                  ),
                )
              else
                Text(
                  'Rest',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textTertiary,
                  ),
                ),
            ],
          ),

          // Workouts list
          if (workouts.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...workouts.map((workout) => _buildWorkoutChip(theme, workout)),
          ],

          // Drop zone hint when dragging
          if (isDragTarget && workouts.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.primaryColor,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: theme.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Drop here',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkoutChip(ThemeData theme, ProgramWorkout workout) {
    final isCompleted = workout.isCompleted;
    final isMissed = widget.program.isWorkoutMissed(workout);
    final canDrag = !isCompleted && !workout.isRestDay;

    Color accentColor;
    if (isCompleted) {
      accentColor = AppColors.accentGreen;
    } else if (isMissed) {
      accentColor = AppColors.accentCoral;
    } else {
      accentColor = theme.primaryColor;
    }

    Widget chip = GestureDetector(
      onTap: () {
        if (!workout.isRestDay && widget.onWorkoutTap != null) {
          Navigator.pop(context);
          widget.onWorkoutTap!(workout);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              isCompleted
                  ? Icons.check_circle_rounded
                  : isMissed
                      ? Icons.warning_rounded
                      : Icons.fitness_center_rounded,
              size: 18,
              color: accentColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _cleanWorkoutName(workout.workoutName),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canDrag)
              Icon(Icons.drag_indicator_rounded, size: 18, color: context.textTertiary),
          ],
        ),
      ),
    );

    if (canDrag) {
      return LongPressDraggable<ProgramWorkout>(
        data: workout,
        delay: const Duration(milliseconds: 150),
        hapticFeedbackOnStart: true,
        onDragStarted: () {
          HapticFeedback.mediumImpact();
          setState(() => _isDragging = true);
        },
        onDragEnd: (_) {
          setState(() {
            _isDragging = false;
            _dragTargetDay = null;
          });
        },
        onDraggableCanceled: (_, __) {
          setState(() {
            _isDragging = false;
            _dragTargetDay = null;
          });
        },
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.primaryColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: theme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fitness_center_rounded, size: 20, color: theme.primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _cleanWorkoutName(workout.workoutName),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.surfaceHighlight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.border, style: BorderStyle.solid),
          ),
          child: const SizedBox(height: 18),
        ),
        child: chip,
      );
    }

    return chip;
  }
}
