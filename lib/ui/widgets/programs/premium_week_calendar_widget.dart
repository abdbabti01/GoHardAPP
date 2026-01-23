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

class _PremiumWeekCalendarWidgetState extends State<PremiumWeekCalendarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
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

  void _openFullscreenCalendar() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        duration: const Duration(milliseconds: 400),
        vsync: Navigator.of(context),
      ),
      builder:
          (context) => _FullscreenCalendarModal(
            programId: widget.program.id,
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
    // Fixed day labels - programs always follow Monday-Sunday structure
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: _openFullscreenCalendar,
          child: Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.border),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
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
                      _buildEditButton(theme),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Compact day cells
                  Row(
                    children: List.generate(7, (index) {
                      final dayNumber = index + 1;
                      final date = _getDateForDay(
                        widget.selectedWeek,
                        dayNumber,
                      );
                      final dayWorkouts = groupedWorkouts[index];
                      final isToday = _isToday(date);
                      // Filter out rest days for workout count
                      final actualWorkouts =
                          dayWorkouts.where((w) => !w.isRestDay).toList();
                      final hasWorkouts = actualWorkouts.isNotEmpty;
                      final allCompleted =
                          hasWorkouts &&
                          actualWorkouts.every((w) => w.isCompleted);

                      return Expanded(
                        child: _buildCompactDayCell(
                          theme,
                          dayLabels[index],
                          date.day,
                          hasWorkouts,
                          allCompleted,
                          isToday,
                          actualWorkouts.length,
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditButton(ThemeData theme) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        // Use accent color for visibility in both light and dark mode
        final accentColor = context.accent;
        return Transform.scale(
          scale: value,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withValues(alpha: 0.2),
                  accentColor.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_calendar_rounded, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  'Edit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow:
            isToday
                ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
                : null,
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
            Icon(
              Icons.check_circle,
              size: 14,
              color: isToday ? Colors.white : context.accent,
            )
          else if (hasWorkouts)
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color:
                    isToday
                        ? Colors.white.withValues(alpha: 0.2)
                        : context.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$workoutCount',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isToday ? Colors.white : context.accent,
                  ),
                ),
              ),
            )
          else
            // Rest days and no-workout days both show subtle dash
            Icon(
              Icons.remove,
              size: 14,
              color:
                  isToday
                      ? Colors.white.withValues(alpha: 0.5)
                      : context.textTertiary,
            ),
        ],
      ),
    );
  }
}

/// Fullscreen calendar modal for drag-and-drop workout rescheduling
class _FullscreenCalendarModal extends StatefulWidget {
  final int programId;
  final int selectedWeek;
  final Function(int) onWeekChanged;
  final Function(ProgramWorkout)? onWorkoutTap;
  final VoidCallback? onWorkoutMoved;

  const _FullscreenCalendarModal({
    required this.programId,
    required this.selectedWeek,
    required this.onWeekChanged,
    this.onWorkoutTap,
    this.onWorkoutMoved,
  });

  @override
  State<_FullscreenCalendarModal> createState() =>
      _FullscreenCalendarModalState();
}

class _FullscreenCalendarModalState extends State<_FullscreenCalendarModal>
    with TickerProviderStateMixin {
  late int _currentWeek;
  late PageController _pageController;
  late AnimationController _headerController;
  late AnimationController _dragPulseController;
  late Animation<double> _headerAnimation;
  late Animation<double> _dragPulseAnimation;

  bool _isDragging = false;
  int? _dragTargetDay;
  bool _isMoving = false;

  @override
  void initState() {
    super.initState();
    _currentWeek = widget.selectedWeek;
    _pageController = PageController(initialPage: _currentWeek - 1);

    _headerController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _headerAnimation = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOutBack,
    );
    _headerController.forward();

    _dragPulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _dragPulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _dragPulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _headerController.dispose();
    _dragPulseController.dispose();
    super.dispose();
  }

  List<List<ProgramWorkout>> _getWeekWorkoutsGrouped(
    Program program,
    int weekNumber,
  ) {
    if (program.workouts == null) return List.generate(7, (_) => []);

    return List.generate(7, (dayIndex) {
      final day = dayIndex + 1;
      return program.workouts!
          .where((w) => w.weekNumber == weekNumber && w.dayNumber == day)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    });
  }

  DateTime _getDateForDay(Program program, int weekNumber, int dayNumber) {
    return program.startDate.add(
      Duration(days: (weekNumber - 1) * 7 + (dayNumber - 1)),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Future<void> _moveWorkout(
    ProgramWorkout workout,
    int newDay,
    Program program,
  ) async {
    if (!mounted || _isMoving) return;
    if (workout.dayNumber == newDay) return; // No change needed

    setState(() => _isMoving = true);

    final provider = context.read<ProgramsProvider>();
    HapticFeedback.mediumImpact();

    final dayWorkouts =
        _getWeekWorkoutsGrouped(program, _currentWeek)[newDay - 1];
    final maxOrder =
        dayWorkouts.isEmpty
            ? 0
            : dayWorkouts
                .map((w) => w.orderIndex)
                .reduce((a, b) => a > b ? a : b);

    final updatedWorkout = workout.copyWith(
      dayNumber: newDay,
      orderIndex: maxOrder + 10,
    );

    final success = await provider.updateWorkout(workout.id, updatedWorkout);

    if (mounted) {
      setState(() => _isMoving = false);

      if (success) {
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
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Moved to ${dayNames[newDay - 1]}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: context.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
            elevation: 8,
          ),
        );
      }
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

    return Consumer<ProgramsProvider>(
      builder: (context, provider, child) {
        final program = provider.programs.firstWhere(
          (p) => p.id == widget.programId,
          orElse: () => provider.programs.first,
        );

        return Container(
          height: screenHeight * 0.88,
          decoration: BoxDecoration(
            color: context.scaffoldBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 30,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Premium drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: context.textTertiary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Animated header
              SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.3),
                  end: Offset.zero,
                ).animate(_headerAnimation),
                child: FadeTransition(
                  opacity: _headerAnimation,
                  child: _buildHeader(theme),
                ),
              ),

              // Week navigation
              _buildWeekNavigation(theme, program),

              // Drag indicator when dragging
              _buildDragIndicator(theme),

              const SizedBox(height: 12),

              // Week calendar with PageView
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics:
                      _isDragging
                          ? const NeverScrollableScrollPhysics()
                          : const BouncingScrollPhysics(),
                  onPageChanged: (page) {
                    HapticFeedback.selectionClick();
                    setState(() => _currentWeek = page + 1);
                    widget.onWeekChanged(page + 1);
                  },
                  itemCount: program.totalWeeks,
                  itemBuilder: (context, weekIndex) {
                    return _buildWeekContent(weekIndex + 1, theme, program);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.primaryColor.withValues(alpha: 0.2),
                            theme.primaryColor.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.calendar_month_rounded,
                        size: 20,
                        color: theme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Schedule',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      size: 14,
                      color: context.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Hold and drag workouts to reschedule',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surfaceHighlight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.close_rounded,
                  size: 22,
                  color: context.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragIndicator(ThemeData theme) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child:
          _isDragging
              ? AnimatedBuilder(
                animation: _dragPulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _dragPulseAnimation.value,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.primaryColor.withValues(alpha: 0.2),
                            AppColors.accentSky.withValues(alpha: 0.15),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: theme.primaryColor.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.primaryColor.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.swap_vert_rounded,
                            color: theme.primaryColor,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Drop on any day to move',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              )
              : const SizedBox.shrink(),
    );
  }

  Widget _buildWeekNavigation(ThemeData theme, Program program) {
    final weekStart = _getDateForDay(program, _currentWeek, 1);
    final weekEnd = _getDateForDay(program, _currentWeek, 7);
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
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              );
            },
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Week $_currentWeek of ${program.totalWeeks}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${dateFormat.format(weekStart)} - ${dateFormat.format(weekEnd)}',
                  style: TextStyle(fontSize: 13, color: context.textSecondary),
                ),
              ],
            ),
          ),
          _buildNavButton(
            Icons.chevron_right_rounded,
            _currentWeek < program.totalWeeks && !_isDragging,
            () {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            enabled
                ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
                : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
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
            size: 26,
            color: enabled ? context.textPrimary : context.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildWeekContent(int weekNumber, ThemeData theme, Program program) {
    final groupedWorkouts = _getWeekWorkoutsGrouped(program, weekNumber);
    // Fixed day labels - programs always follow Monday-Sunday structure
    const dayLabels = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      physics: const BouncingScrollPhysics(),
      itemCount: 7,
      itemBuilder: (context, index) {
        final dayNumber = index + 1;
        final date = _getDateForDay(program, weekNumber, dayNumber);
        final dayWorkouts = groupedWorkouts[index];
        final isToday = _isToday(date);
        final isDragTarget = _dragTargetDay == dayNumber;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 200 + (index * 50)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: DragTarget<ProgramWorkout>(
                  onWillAcceptWithDetails: (details) {
                    if (details.data.dayNumber != dayNumber) {
                      HapticFeedback.selectionClick();
                      setState(() => _dragTargetDay = dayNumber);
                    }
                    return true;
                  },
                  onAcceptWithDetails: (details) async {
                    setState(() {
                      _isDragging = false;
                      _dragTargetDay = null;
                    });
                    _dragPulseController.stop();
                    await _moveWorkout(details.data, dayNumber, program);
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
                      program,
                    );
                  },
                ),
              ),
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
    Program program,
  ) {
    // Filter out rest days for workout count
    final actualWorkouts = workouts.where((w) => !w.isRestDay).toList();
    final hasWorkouts = actualWorkouts.isNotEmpty;
    final allCompleted =
        hasWorkouts && actualWorkouts.every((w) => w.isCompleted);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:
            isDragTarget
                ? theme.primaryColor.withValues(alpha: 0.12)
                : isToday
                ? theme.primaryColor.withValues(alpha: 0.06)
                : context.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              isDragTarget
                  ? theme.primaryColor
                  : isToday
                  ? theme.primaryColor.withValues(alpha: 0.4)
                  : context.border,
          width: isDragTarget ? 2.5 : 1,
        ),
        boxShadow:
            isDragTarget
                ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
                : isToday
                ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
                : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isToday ? theme.primaryColor : context.surfaceHighlight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    dayLabel.substring(0, 3),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isToday ? Colors.white : context.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  DateFormat('MMM d').format(date),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryColor,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (allCompleted)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: context.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: context.accent,
                    ),
                  )
                else if (hasWorkouts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: context.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${actualWorkouts.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.accent,
                      ),
                    ),
                  )
                else
                  // Rest days and empty days both show subtle "Rest" text
                  Text(
                    'Rest',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: context.textTertiary,
                    ),
                  ),
              ],
            ),

            // Workouts list
            if (workouts.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...workouts.asMap().entries.map((entry) {
                return _buildWorkoutChip(
                  theme,
                  entry.value,
                  program,
                  entry.key,
                );
              }),
            ],

            // Drop zone hint when dragging
            if (isDragTarget) ...[
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.08),
                  border: Border.all(
                    color: theme.primaryColor,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignCenter,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: theme.primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Drop here',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutChip(
    ThemeData theme,
    ProgramWorkout workout,
    Program program,
    int index,
  ) {
    final isCompleted = workout.isCompleted;
    final isMissed = program.isWorkoutMissed(workout);
    final canDrag = !isCompleted && !workout.isRestDay;

    Color accentColor;
    IconData iconData;
    if (isCompleted) {
      accentColor = context.accent;
      iconData = Icons.check_circle_rounded;
    } else if (isMissed) {
      accentColor = AppColors.accentCoral;
      iconData = Icons.warning_rounded;
    } else {
      accentColor = theme.primaryColor;
      iconData = Icons.fitness_center_rounded;
    }

    Widget chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!workout.isRestDay && widget.onWorkoutTap != null) {
            Navigator.pop(context);
            widget.onWorkoutTap!(workout);
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.only(bottom: index < 10 ? 8 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accentColor.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(iconData, size: 16, color: accentColor),
              ),
              const SizedBox(width: 12),
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
              if (canDrag) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: context.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (canDrag) {
      return LongPressDraggable<ProgramWorkout>(
        data: workout,
        delay: const Duration(milliseconds: 180),
        hapticFeedbackOnStart: true,
        onDragStarted: () {
          HapticFeedback.mediumImpact();
          setState(() => _isDragging = true);
          _dragPulseController.repeat(reverse: true);
        },
        onDragEnd: (_) {
          setState(() {
            _isDragging = false;
            _dragTargetDay = null;
          });
          _dragPulseController.stop();
        },
        onDraggableCanceled: (_, __) {
          setState(() {
            _isDragging = false;
            _dragTargetDay = null;
          });
          _dragPulseController.stop();
        },
        feedback: _buildDragFeedback(theme, workout),
        childWhenDragging: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.only(bottom: index < 10 ? 8 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.surfaceHighlight.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.primaryColor.withValues(alpha: 0.3),
              style: BorderStyle.solid,
            ),
          ),
          child: const SizedBox(height: 28),
        ),
        child: chip,
      );
    }

    return chip;
  }

  Widget _buildDragFeedback(ThemeData theme, ProgramWorkout workout) {
    return Material(
      color: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.8, end: 1.0),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.primaryColor, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.35),
                    blurRadius: 28,
                    spreadRadius: 4,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor.withValues(alpha: 0.25),
                          theme.primaryColor.withValues(alpha: 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      size: 22,
                      color: theme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _cleanWorkoutName(workout.workoutName),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Moving...',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: theme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
