import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';

/// Widget that displays a monthly calendar view for program workouts
///
/// Shows workouts mapped to their actual calendar dates with visual indicators
/// for completion status, rest days, and today's workout.
class ProgramCalendarWidget extends StatefulWidget {
  final Program program;
  final Function(DateTime, ProgramWorkout?)? onDateTapped;

  const ProgramCalendarWidget({
    super.key,
    required this.program,
    this.onDateTapped,
  });

  @override
  State<ProgramCalendarWidget> createState() => _ProgramCalendarWidgetState();
}

class _ProgramCalendarWidgetState extends State<ProgramCalendarWidget> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late Map<DateTime, ProgramWorkout> _workoutMap;

  @override
  void initState() {
    super.initState();
    _focusedDay = _calculateTodayInProgram();
    _selectedDay = _focusedDay;
    _workoutMap = _buildWorkoutMap();
  }

  @override
  void didUpdateWidget(ProgramCalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.program.id != widget.program.id ||
        oldWidget.program.workouts != widget.program.workouts) {
      _workoutMap = _buildWorkoutMap();
    }
  }

  /// Calculate what "today" means - uses real calendar date
  DateTime _calculateTodayInProgram() {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// Build a map of dates to workouts for O(1) lookup
  Map<DateTime, ProgramWorkout> _buildWorkoutMap() {
    final map = <DateTime, ProgramWorkout>{};

    for (final workout in widget.program.workouts ?? []) {
      // Calculate the actual calendar date for this workout
      final date = widget.program.startDate.add(
        Duration(days: (workout.weekNumber - 1) * 7 + (workout.dayNumber - 1)),
      );

      // Normalize to UTC midnight for consistent comparison
      final normalizedDate = DateTime.utc(date.year, date.month, date.day);
      map[normalizedDate] = workout;
    }

    return map;
  }

  /// Normalize a date to UTC midnight for map lookup
  DateTime _normalizeDate(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  /// Handle date selection with edge case handling
  void _onDateSelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = _normalizeDate(selectedDay);
      _focusedDay = focusedDay;
    });

    final workout = _workoutMap[_normalizeDate(selectedDay)];
    final programToday = _calculateTodayInProgram();

    // Case 1: No workout on this date
    if (workout == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No workout scheduled for this date'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Case 2: Rest day
    if (workout.isRestDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Rest day - Recovery is part of the program!'),
          backgroundColor: Colors.blue.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Case 3: Future workout (beyond program's current day)
    if (_normalizeDate(selectedDay).isAfter(programToday)) {
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Future Workout'),
              content: Text(
                'This workout is scheduled for ${DateFormat('MMM d, yyyy').format(selectedDay)}.\n\n'
                'Your program is currently on Week ${widget.program.currentWeek}, '
                'Day ${widget.program.currentDay}.\n\n'
                'Would you like to view this workout ahead of schedule?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDateTapped?.call(selectedDay, workout);
                  },
                  child: const Text('View Anyway'),
                ),
              ],
            ),
      );
      return;
    }

    // Case 4: Normal workout - navigate
    widget.onDateTapped?.call(selectedDay, workout);
  }

  /// Build marker (dot indicator) for a date
  Widget _buildMarker(
    BuildContext context,
    DateTime day,
    ProgramWorkout workout,
  ) {
    final theme = Theme.of(context);
    final normalized = _normalizeDate(day);
    final programToday = _calculateTodayInProgram();
    final isToday = normalized == programToday;
    final isMissed = widget.program.isWorkoutMissed(workout); // Check if missed

    Color markerColor;
    IconData? icon;

    if (workout.isRestDay) {
      markerColor = context.textTertiary;
      icon = Icons.self_improvement;
    } else if (workout.isCompleted) {
      markerColor = Colors.green.shade600;
      icon = Icons.check_circle;
    } else if (isToday) {
      markerColor = theme.colorScheme.primary;
      icon = Icons.play_circle_filled;
    } else if (normalized.isAfter(programToday)) {
      markerColor = theme.colorScheme.primary.withValues(alpha: 0.4);
      icon = Icons.circle_outlined;
    } else if (isMissed) {
      // Missed workout - past date but not completed
      markerColor = Colors.orange.shade600;
      icon = Icons.warning;
    } else {
      markerColor = theme.colorScheme.primary;
      icon = Icons.circle;
    }

    return Container(
      margin: const EdgeInsets.all(4),
      child: Icon(icon, size: 8, color: markerColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final programStart = widget.program.startDate;
    final programEnd = programStart.add(
      Duration(days: widget.program.totalWeeks * 7),
    );

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Calendar header info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Program Calendar',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          '${DateFormat('MMM d, yyyy').format(programStart)} - '
                          '${DateFormat('MMM d, yyyy').format(programEnd)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Calendar widget
            Expanded(
              child: TableCalendar(
                firstDay: programStart,
                lastDay: programEnd,
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: CalendarFormat.month,
                startingDayOfWeek: StartingDayOfWeek.monday,
                availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                headerStyle: HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  leftChevronIcon: Icon(
                    Icons.chevron_left,
                    color: theme.colorScheme.primary,
                  ),
                  rightChevronIcon: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.primary,
                  ),
                ),
                calendarStyle: CalendarStyle(
                  // Today's date (actual today)
                  todayDecoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  // Selected date
                  selectedDecoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  // Default days
                  defaultTextStyle: const TextStyle(fontSize: 14),
                  // Weekend days
                  weekendTextStyle: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.error.withValues(alpha: 0.7),
                  ),
                  // Outside month days
                  outsideTextStyle: TextStyle(
                    fontSize: 14,
                    color: context.textTertiary,
                  ),
                  // Disabled days (outside program range)
                  disabledTextStyle: TextStyle(
                    fontSize: 14,
                    color: context.textTertiary.withValues(alpha: 0.5),
                  ),
                ),
                // Enable/disable dates based on program range
                enabledDayPredicate: (day) {
                  final normalized = _normalizeDate(day);
                  return !normalized.isBefore(_normalizeDate(programStart)) &&
                      !normalized.isAfter(_normalizeDate(programEnd));
                },
                // Custom marker builder
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) {
                    final workout = _workoutMap[_normalizeDate(day)];
                    if (workout != null) {
                      return _buildMarker(context, day, workout);
                    }
                    return null;
                  },
                  // Add "TODAY" badge for program's current day
                  selectedBuilder: (context, day, focusedDay) {
                    final normalized = _normalizeDate(day);
                    final programToday = _calculateTodayInProgram();
                    final isProgramToday = normalized == programToday;

                    return Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color:
                            isProgramToday
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary.withValues(
                                  alpha: 0.7,
                                ),
                        shape: BoxShape.circle,
                        border:
                            isProgramToday
                                ? Border.all(
                                  color: theme.colorScheme.secondary,
                                  width: 2,
                                )
                                : null,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (isProgramToday)
                              Text(
                                'TODAY',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                onDaySelected: _onDateSelected,
                onPageChanged: (focusedDay) {
                  setState(() {
                    _focusedDay = focusedDay;
                  });
                },
              ),
            ),

            const SizedBox(height: 16),

            // Legend
            _buildLegend(theme),
          ],
        ),
      ),
    );
  }

  /// Build legend showing what each indicator means
  Widget _buildLegend(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceHighlight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Legend:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem(
                Icons.play_circle_filled,
                'Today\'s Workout',
                theme.colorScheme.primary,
              ),
              _buildLegendItem(
                Icons.check_circle,
                'Completed',
                Colors.green.shade600,
              ),
              _buildLegendItem(
                Icons.self_improvement,
                'Rest Day',
                context.textTertiary,
              ),
              _buildLegendItem(
                Icons.circle,
                'Scheduled',
                theme.colorScheme.primary,
              ),
              _buildLegendItem(
                Icons.circle_outlined,
                'Upcoming',
                theme.colorScheme.primary.withValues(alpha: 0.4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
