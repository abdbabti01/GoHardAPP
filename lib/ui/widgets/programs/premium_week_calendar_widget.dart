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
/// Supports multiple workouts per day and shows rest days properly
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

class _PremiumWeekCalendarWidgetState extends State<PremiumWeekCalendarWidget>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _dragAnimationController;

  int? _selectedDayIndex;
  bool _isDragging = false;
  int? _dragTargetDay;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.selectedWeek - 1);

    // Animation controller for drag visual feedback
    _dragAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(PremiumWeekCalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedWeek != widget.selectedWeek) {
      _pageController.animateToPage(
        widget.selectedWeek - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _dragAnimationController.dispose();
    super.dispose();
  }

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

  bool _isPast(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return date.isBefore(today);
  }

  Future<void> _moveWorkout(ProgramWorkout workout, int newDay) async {
    if (!mounted) return;

    final provider = context.read<ProgramsProvider>();
    HapticFeedback.mediumImpact();

    // Calculate new order index (place at end of day)
    final dayWorkouts =
        _getWeekWorkoutsGrouped(widget.selectedWeek)[newDay - 1];
    final maxOrder =
        dayWorkouts.isEmpty
            ? 0
            : dayWorkouts
                .map((w) => w.orderIndex)
                .reduce((a, b) => a > b ? a : b);

    // Update workout with new day
    final updatedWorkout = workout.copyWith(
      dayNumber: newDay,
      orderIndex: maxOrder + 10,
    );

    final success = await provider.updateWorkout(workout.id, updatedWorkout);

    if (mounted && success) {
      widget.onWorkoutMoved?.call();
      HapticFeedback.lightImpact();

      final dayNames = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Week Navigation Header
        _buildWeekHeader(context, theme),
        const SizedBox(height: 16),

        // Drag Mode Indicator
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child:
              _isDragging
                  ? _buildDragModeIndicator(context, theme)
                  : const SizedBox.shrink(),
        ),

        // Week Calendar (swipeable)
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageController,
            physics: _isDragging ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (page) {
              HapticFeedback.selectionClick();
              widget.onWeekChanged(page + 1);
            },
            itemCount: widget.program.totalWeeks,
            itemBuilder: (context, weekIndex) {
              return _buildWeekView(context, weekIndex + 1, theme);
            },
          ),
        ),

        // Selected day workouts panel
        if (_selectedDayIndex != null && !_isDragging) ...[
          const SizedBox(height: 16),
          _buildSelectedDayWorkouts(context, theme),
        ],
      ],
    );
  }

  Widget _buildDragModeIndicator(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
    );
  }

  Widget _buildWeekHeader(BuildContext context, ThemeData theme) {
    final weekStart = _getDateForDay(widget.selectedWeek, 1);
    final weekEnd = _getDateForDay(widget.selectedWeek, 7);
    final dateFormat = DateFormat('MMM d');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Previous week button
          _buildNavButton(
            context,
            Icons.chevron_left_rounded,
            widget.selectedWeek > 1 && !_isDragging,
            () => widget.onWeekChanged(widget.selectedWeek - 1),
          ),

          // Week info
          Expanded(
            child: Column(
              children: [
                Text(
                  'Week ${widget.selectedWeek}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${dateFormat.format(weekStart)} - ${dateFormat.format(weekEnd)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Next week button
          _buildNavButton(
            context,
            Icons.chevron_right_rounded,
            widget.selectedWeek < widget.program.totalWeeks && !_isDragging,
            () => widget.onWeekChanged(widget.selectedWeek + 1),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(
    BuildContext context,
    IconData icon,
    bool enabled,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap:
          enabled
              ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
              : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color:
              enabled
                  ? context.surface
                  : context.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                enabled
                    ? context.border
                    : context.border.withValues(alpha: 0.3),
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

  Widget _buildWeekView(BuildContext context, int weekNumber, ThemeData theme) {
    final groupedWorkouts = _getWeekWorkoutsGrouped(weekNumber);
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: List.generate(7, (index) {
          final dayNumber = index + 1;
          final date = _getDateForDay(weekNumber, dayNumber);
          final dayWorkouts = groupedWorkouts[index];
          final isToday = _isToday(date);
          final isPast = _isPast(date);
          final isSelected =
              _selectedDayIndex == index && widget.selectedWeek == weekNumber;
          final isDragTarget = _dragTargetDay == dayNumber;

          // Build the day cell
          Widget dayCell = _buildDayCell(
            context,
            theme,
            dayLabels[index],
            date.day,
            dayNumber,
            dayWorkouts,
            isToday,
            isPast,
            isSelected,
            isDragTarget,
          );

          // Wrap with DragTarget to accept dropped workouts
          dayCell = DragTarget<ProgramWorkout>(
            onWillAcceptWithDetails: (details) {
              // Can drop on any day
              HapticFeedback.selectionClick();
              setState(() => _dragTargetDay = dayNumber);
              return true;
            },
            onAcceptWithDetails: (details) async {
              setState(() {
                _isDragging = false;
                _dragTargetDay = null;
              });
              _dragAnimationController.stop();
              await _moveWorkout(details.data, dayNumber);
            },
            onLeave: (_) {
              setState(() => _dragTargetDay = null);
            },
            builder: (context, candidateData, rejectedData) {
              return dayCell;
            },
          );

          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedDayIndex = _selectedDayIndex == index ? null : index;
                });
              },
              child: dayCell,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    ThemeData theme,
    String dayLabel,
    int dateNumber,
    int actualDay,
    List<ProgramWorkout> dayWorkouts,
    bool isToday,
    bool isPast,
    bool isSelected,
    bool isDragTarget,
  ) {
    final hasWorkouts = dayWorkouts.isNotEmpty;
    final isRestDay = !hasWorkouts;
    final allCompleted = hasWorkouts && dayWorkouts.every((w) => w.isCompleted);
    final hasMissed =
        hasWorkouts &&
        dayWorkouts.any(
          (w) => !w.isCompleted && widget.program.isWorkoutMissed(w),
        );
    final isDark = theme.brightness == Brightness.dark;

    // Determine cell styling
    Color backgroundColor;
    Color borderColor;
    Color dayLabelColor;
    Color dateColor;
    double borderWidth = 1;

    final defaultSurface = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final defaultBorder =
        isDark ? const Color(0xFF3D4449) : const Color(0xFFE5E5EA);
    final defaultTextPrimary = isDark ? Colors.white : Colors.black;
    final defaultTextTertiary =
        isDark ? const Color(0xFF636E72) : const Color(0xFF8B959B);

    if (isDragTarget) {
      backgroundColor = theme.primaryColor.withValues(alpha: 0.15);
      borderColor = theme.primaryColor;
      dayLabelColor = theme.primaryColor;
      dateColor = theme.primaryColor;
      borderWidth = 2;
    } else if (isToday) {
      backgroundColor = theme.primaryColor;
      borderColor = theme.primaryColor;
      dayLabelColor = Colors.white.withValues(alpha: 0.8);
      dateColor = Colors.white;
    } else if (isSelected) {
      backgroundColor = theme.primaryColor.withValues(alpha: 0.1);
      borderColor = theme.primaryColor;
      dayLabelColor = theme.primaryColor;
      dateColor = defaultTextPrimary;
      borderWidth = 2;
    } else {
      backgroundColor = defaultSurface;
      borderColor = defaultBorder;
      dayLabelColor = defaultTextTertiary;
      dateColor = defaultTextPrimary;
    }

    // Build status indicator
    Widget statusIndicator;
    if (isDragTarget) {
      statusIndicator = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: theme.primaryColor, width: 2),
        ),
        child: Icon(Icons.add_rounded, size: 14, color: theme.primaryColor),
      );
    } else if (allCompleted && hasWorkouts) {
      statusIndicator = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          gradient: AppColors.successGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accentGreen.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
      );
    } else if (hasMissed) {
      statusIndicator = Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: AppColors.accentCoral,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '${dayWorkouts.where((w) => !w.isCompleted).length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    } else if (isRestDay) {
      final surfaceHighlight =
          isDark ? const Color(0xFF3D4449) : const Color(0xFFDFE6E9);
      statusIndicator = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: surfaceHighlight,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.self_improvement_rounded,
          size: 14,
          color: defaultTextTertiary,
        ),
      );
    } else if (hasWorkouts) {
      // Show workout count badge
      statusIndicator = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color:
              isToday
                  ? Colors.white.withValues(alpha: 0.2)
                  : theme.primaryColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(
            color:
                isToday
                    ? Colors.white.withValues(alpha: 0.5)
                    : theme.primaryColor.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            '${dayWorkouts.length}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isToday ? Colors.white : theme.primaryColor,
            ),
          ),
        ),
      );
    } else {
      statusIndicator = const SizedBox(height: 24);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow:
            isDragTarget
                ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.2),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
                : isToday
                ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
                : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Day label (M, T, W...)
          Text(
            dayLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: dayLabelColor,
            ),
          ),
          const SizedBox(height: 4),

          // Date number
          Text(
            '$dateNumber',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: dateColor,
            ),
          ),
          const SizedBox(height: 8),

          // Status indicator
          statusIndicator,
        ],
      ),
    );
  }

  /// Build the selected day workouts panel
  Widget _buildSelectedDayWorkouts(BuildContext context, ThemeData theme) {
    if (_selectedDayIndex == null) return const SizedBox.shrink();

    final groupedWorkouts = _getWeekWorkoutsGrouped(widget.selectedWeek);
    final dayWorkouts = groupedWorkouts[_selectedDayIndex!];
    final date = _getDateForDay(widget.selectedWeek, _selectedDayIndex! + 1);
    final dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final dayName = dayNames[_selectedDayIndex!];

    if (dayWorkouts.isEmpty) {
      return _buildRestDayCard(context, dayName, date);
    }

    return _buildDayWorkoutsPanel(context, theme, dayWorkouts, dayName, date);
  }

  Widget _buildRestDayCard(
    BuildContext context,
    String dayName,
    DateTime date,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.surfaceHighlight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.self_improvement_rounded,
              color: context.textTertiary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rest Day',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dayName, ${DateFormat('MMM d').format(date)}',
                  style: TextStyle(fontSize: 13, color: context.textSecondary),
                ),
              ],
            ),
          ),
          // Hint that workouts can be dropped here
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: context.surfaceHighlight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 14, color: context.textTertiary),
                const SizedBox(width: 4),
                Text(
                  'Drop workout',
                  style: TextStyle(fontSize: 11, color: context.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayWorkoutsPanel(
    BuildContext context,
    ThemeData theme,
    List<ProgramWorkout> workouts,
    String dayName,
    DateTime date,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        '${DateFormat('MMM d').format(date)} - ${workouts.length} workout${workouts.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Hold to drag',
                  style: TextStyle(fontSize: 11, color: context.textTertiary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Workout list
          ...workouts.map(
            (workout) => _buildWorkoutItem(context, theme, workout),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutItem(
    BuildContext context,
    ThemeData theme,
    ProgramWorkout workout,
  ) {
    final isCompleted = workout.isCompleted;
    final isMissed = widget.program.isWorkoutMissed(workout);
    final canDrag = !isCompleted && !workout.isRestDay;

    Color accentColor;
    IconData statusIcon;

    if (isCompleted) {
      accentColor = AppColors.accentGreen;
      statusIcon = Icons.check_circle_rounded;
    } else if (isMissed) {
      accentColor = AppColors.accentCoral;
      statusIcon = Icons.warning_rounded;
    } else {
      accentColor = theme.primaryColor;
      statusIcon = Icons.play_circle_rounded;
    }

    Widget itemContent = GestureDetector(
      onTap: () {
        if (!workout.isRestDay && widget.onWorkoutTap != null) {
          widget.onWorkoutTap!(workout);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Status icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(statusIcon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            // Workout info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _cleanWorkoutName(workout.workoutName),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (workout.exerciseCount > 0) ...[
                        Text(
                          '${workout.exerciseCount} exercises',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                      if (workout.exerciseCount > 0 &&
                          workout.estimatedDuration != null)
                        Text(
                          ' - ',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      if (workout.estimatedDuration != null)
                        Text(
                          '${workout.estimatedDuration} min',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Drag handle or arrow
            if (canDrag)
              Icon(
                Icons.drag_indicator_rounded,
                color: context.textTertiary,
                size: 20,
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: context.textTertiary,
                size: 20,
              ),
          ],
        ),
      ),
    );

    // Wrap with LongPressDraggable if draggable
    if (canDrag) {
      return LongPressDraggable<ProgramWorkout>(
        data: workout,
        delay: const Duration(milliseconds: 200),
        hapticFeedbackOnStart: true,
        onDragStarted: () {
          HapticFeedback.mediumImpact();
          setState(() {
            _isDragging = true;
          });
          _dragAnimationController.repeat(reverse: true);
        },
        onDragEnd: (_) {
          setState(() {
            _isDragging = false;
            _dragTargetDay = null;
          });
          _dragAnimationController.stop();
        },
        onDraggableCanceled: (_, __) {
          setState(() {
            _isDragging = false;
            _dragTargetDay = null;
          });
          _dragAnimationController.stop();
        },
        feedback: _buildDragFeedback(context, theme, workout),
        childWhenDragging: _buildDraggingPlaceholder(context),
        child: itemContent,
      );
    }

    return itemContent;
  }

  /// Premium drag feedback widget
  Widget _buildDragFeedback(
    BuildContext context,
    ThemeData theme,
    ProgramWorkout workout,
  ) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.primaryColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: theme.primaryColor.withValues(alpha: 0.3),
              blurRadius: 24,
              spreadRadius: 4,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle indicator
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Workout icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.primaryColor.withValues(alpha: 0.2),
                    theme.primaryColor.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.primaryColor.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.fitness_center_rounded,
                color: theme.primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),

            // Workout name
            Text(
              _cleanWorkoutName(workout.workoutName),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Reschedule label
            Text(
              'Reschedule',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: theme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Placeholder shown while dragging
  Widget _buildDraggingPlaceholder(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.surfaceHighlight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: context.border,
                style: BorderStyle.solid,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: context.surfaceHighlight,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cleanWorkoutName(String name) {
    final colonIndex = name.indexOf(':');
    if (colonIndex != -1 && colonIndex < 15) {
      return name.substring(colonIndex + 1).trim();
    }
    return name;
  }
}
