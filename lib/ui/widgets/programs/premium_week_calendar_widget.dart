import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';

/// Premium horizontal week calendar widget
/// Shows a clean, minimal 7-day view with smooth week navigation
class PremiumWeekCalendarWidget extends StatefulWidget {
  final Program program;
  final int selectedWeek;
  final Function(int) onWeekChanged;
  final Function(ProgramWorkout)? onWorkoutTap;

  const PremiumWeekCalendarWidget({
    super.key,
    required this.program,
    required this.selectedWeek,
    required this.onWeekChanged,
    this.onWorkoutTap,
  });

  @override
  State<PremiumWeekCalendarWidget> createState() =>
      _PremiumWeekCalendarWidgetState();
}

class _PremiumWeekCalendarWidgetState extends State<PremiumWeekCalendarWidget> {
  late PageController _pageController;
  int? _selectedDayIndex;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.selectedWeek - 1);
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
    super.dispose();
  }

  List<ProgramWorkout?> _getWeekWorkouts(int weekNumber) {
    if (widget.program.workouts == null) return List.filled(7, null);

    return List.generate(7, (dayIndex) {
      final day = dayIndex + 1;
      try {
        return widget.program.workouts!.firstWhere(
          (w) => w.weekNumber == weekNumber && w.dayNumber == day,
        );
      } catch (_) {
        return null;
      }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Week Navigation Header
        _buildWeekHeader(context, theme),
        const SizedBox(height: 16),

        // Week Calendar (swipeable)
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageController,
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

        // Selected day details
        if (_selectedDayIndex != null) ...[
          const SizedBox(height: 16),
          _buildSelectedDayDetails(context, theme),
        ],
      ],
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
            widget.selectedWeek > 1,
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
            widget.selectedWeek < widget.program.totalWeeks,
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
    final workouts = _getWeekWorkouts(weekNumber);
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: List.generate(7, (index) {
          final date = _getDateForDay(weekNumber, index + 1);
          final workout = workouts[index];
          final isToday = _isToday(date);
          final isPast = _isPast(date);
          final isSelected =
              _selectedDayIndex == index && widget.selectedWeek == weekNumber;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedDayIndex = _selectedDayIndex == index ? null : index;
                });
                if (workout != null && widget.onWorkoutTap != null) {
                  widget.onWorkoutTap!(workout);
                }
              },
              child: _buildDayCell(
                context,
                theme,
                dayLabels[index],
                date.day,
                workout,
                isToday,
                isPast,
                isSelected,
              ),
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
    int dayNumber,
    ProgramWorkout? workout,
    bool isToday,
    bool isPast,
    bool isSelected,
  ) {
    final hasWorkout = workout != null && !workout.isRestDay;
    final isCompleted = workout?.isCompleted ?? false;
    final isRest = workout?.isRestDay ?? false;
    final isMissed = workout != null && widget.program.isWorkoutMissed(workout);

    // Determine cell styling
    Color backgroundColor;
    Color borderColor;
    Color dayLabelColor;
    Color dateColor;
    Widget? statusIndicator;

    if (isToday) {
      backgroundColor = theme.primaryColor;
      borderColor = theme.primaryColor;
      dayLabelColor = Colors.white.withValues(alpha: 0.8);
      dateColor = Colors.white;
    } else if (isSelected) {
      backgroundColor = theme.primaryColor.withValues(alpha: 0.1);
      borderColor = theme.primaryColor;
      dayLabelColor = theme.primaryColor;
      dateColor = context.textPrimary;
    } else {
      backgroundColor = context.surface;
      borderColor = context.borderSubtle;
      dayLabelColor = context.textTertiary;
      dateColor = context.textPrimary;
    }

    // Status indicator
    if (isCompleted) {
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
    } else if (isMissed) {
      statusIndicator = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.accentCoral,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
      );
    } else if (isRest) {
      statusIndicator = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: context.surfaceHighlight,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.self_improvement_rounded,
          size: 14,
          color: context.textTertiary,
        ),
      );
    } else if (hasWorkout) {
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
        child: Icon(
          Icons.fitness_center_rounded,
          size: 12,
          color: isToday ? Colors.white : theme.primaryColor,
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        boxShadow:
            isToday
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
            '$dayNumber',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: dateColor,
            ),
          ),
          const SizedBox(height: 8),

          // Status indicator
          if (statusIndicator != null)
            statusIndicator
          else
            const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSelectedDayDetails(BuildContext context, ThemeData theme) {
    if (_selectedDayIndex == null) return const SizedBox.shrink();

    final workouts = _getWeekWorkouts(widget.selectedWeek);
    final workout = workouts[_selectedDayIndex!];
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

    if (workout == null) {
      return _buildRestDayCard(context, dayNames[_selectedDayIndex!], date);
    }

    return _buildWorkoutDetailCard(
      context,
      theme,
      workout,
      dayNames[_selectedDayIndex!],
      date,
    );
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
        ],
      ),
    );
  }

  Widget _buildWorkoutDetailCard(
    BuildContext context,
    ThemeData theme,
    ProgramWorkout workout,
    String dayName,
    DateTime date,
  ) {
    final isCompleted = workout.isCompleted;
    final isMissed = widget.program.isWorkoutMissed(workout);

    Color accentColor;
    IconData statusIcon;
    String statusText;

    if (isCompleted) {
      accentColor = AppColors.accentGreen;
      statusIcon = Icons.check_circle_rounded;
      statusText = 'Completed';
    } else if (isMissed) {
      accentColor = AppColors.accentCoral;
      statusIcon = Icons.warning_rounded;
      statusText = 'Missed';
    } else {
      accentColor = theme.primaryColor;
      statusIcon = Icons.play_circle_rounded;
      statusText = 'Scheduled';
    }

    return GestureDetector(
      onTap: () {
        if (widget.onWorkoutTap != null) {
          widget.onWorkoutTap!(workout);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.fitness_center_rounded,
                    color: accentColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _cleanWorkoutName(workout.workoutName),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dayName, ${DateFormat('MMM d').format(date)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Workout details
            if (workout.exerciseCount > 0 ||
                workout.estimatedDuration != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (workout.exerciseCount > 0) ...[
                    Icon(
                      Icons.format_list_numbered_rounded,
                      size: 16,
                      color: context.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${workout.exerciseCount} exercises',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                  if (workout.exerciseCount > 0 &&
                      workout.estimatedDuration != null)
                    const SizedBox(width: 16),
                  if (workout.estimatedDuration != null) ...[
                    Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: context.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${workout.estimatedDuration} min',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: context.textTertiary,
                  ),
                ],
              ),
            ],
          ],
        ),
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
