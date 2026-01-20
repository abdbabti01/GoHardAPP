import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/services/haptic_service.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import '../common/animations.dart';
import '../common/progress_ring.dart';

/// Premium program header card with progress ring
class PremiumProgramHeader extends StatelessWidget {
  final Program program;
  final VoidCallback? onTap;
  final bool showFullDetails;

  const PremiumProgramHeader({
    super.key,
    required this.program,
    this.onTap,
    this.showFullDetails = true,
  });

  @override
  Widget build(BuildContext context) {
    final progress = program.progressPercentage / 100;
    final isCompleted = program.isCompleted;
    final phaseColor = _getPhaseColor(context, program.phaseName);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [context.surface, phaseColor.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color:
              isCompleted
                  ? context.accent.withValues(alpha: 0.4)
                  : context.border,
          width: isCompleted ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color:
                context.isDarkMode
                    ? Colors.black.withValues(alpha: 0.4)
                    : Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with progress ring
            Row(
              children: [
                // Progress Ring
                _buildProgressRing(context, progress, phaseColor, isCompleted),
                const SizedBox(width: 20),
                // Program info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: phaseColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Phase ${program.currentPhase}: ${program.phaseName}',
                          style: AppTypography.labelMedium.copyWith(
                            color: phaseColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        program.title,
                        style: AppTypography.displaySmall.copyWith(
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Week ${program.currentWeek} of ${program.totalWeeks}',
                        style: AppTypography.cardSubtitle.copyWith(
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (showFullDetails) ...[
              const SizedBox(height: 24),

              // Progress bar
              _buildProgressBar(context, progress, phaseColor),

              const SizedBox(height: 20),

              // Stats row
              _buildStatsRow(context, phaseColor),

              // Completion badge
              if (isCompleted) ...[
                const SizedBox(height: 20),
                _buildCompletedBadge(context),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRing(
    BuildContext context,
    double progress,
    Color phaseColor,
    bool isCompleted,
  ) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ProgressRing(
          progress: progress,
          size: 100,
          strokeWidth: 8,
          progressColor: isCompleted ? context.accent : phaseColor,
          backgroundColor: (isCompleted ? context.accent : phaseColor)
              .withValues(alpha: 0.12),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${(progress * 100).toInt()}%',
              style: AppTypography.statSmall.copyWith(
                color: context.textPrimary,
              ),
            ),
            Text(
              'Done',
              style: AppTypography.labelSmall.copyWith(
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context, double progress, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Overall Progress',
              style: AppTypography.labelLarge.copyWith(
                color: context.textSecondary,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: AppTypography.labelLarge.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.8)],
                ),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context, Color phaseColor) {
    final workouts = program.workouts ?? [];
    final completedWorkouts = workouts.where((w) => w.isCompleted).length;
    final totalWorkouts = workouts.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              context,
              Icons.calendar_today_outlined,
              '${program.totalWeeks}',
              'Weeks',
              phaseColor,
            ),
          ),
          Container(width: 1, height: 40, color: context.border),
          Expanded(
            child: _buildStatItem(
              context,
              Icons.fitness_center,
              '$completedWorkouts/$totalWorkouts',
              'Workouts',
              AppColors.accentSky,
            ),
          ),
          Container(width: 1, height: 40, color: context.border),
          Expanded(
            child: _buildStatItem(
              context,
              Icons.local_fire_department_outlined,
              'Day ${program.currentDay}',
              'Current',
              AppColors.accentAmber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(color: context.textPrimary),
        ),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedBadge(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: AppColors.successGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: context.accent.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Text(
            'Program Completed!',
            style: AppTypography.titleMedium.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Color _getPhaseColor(BuildContext context, String phase) {
    switch (phase.toLowerCase()) {
      case 'foundation':
        return AppColors.accentSky;
      case 'progressive overload':
        return AppColors.accentCoral;
      case 'peak performance':
        return context.accent;
      default:
        return AppColors.accentSky;
    }
  }
}

/// Premium workout card for program schedules
class PremiumWorkoutCard extends StatelessWidget {
  final ProgramWorkout workout;
  final bool isToday;
  final bool isMissed;
  final VoidCallback? onTap;

  const PremiumWorkoutCard({
    super.key,
    required this.workout,
    this.isToday = false,
    this.isMissed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = workout.isCompleted;
    final statusColor = _getStatusColor(
      context,
      isCompleted,
      isToday,
      isMissed,
    );

    return PremiumTapAnimation(
      onTap: () {
        HapticService.cardTap();
        onTap?.call();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                isToday ? statusColor.withValues(alpha: 0.4) : context.border,
            width: isToday ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  context.isDarkMode
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
            if (isToday)
              BoxShadow(
                color: statusColor.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Day badge
              _buildDayBadge(context, statusColor, isCompleted),
              const SizedBox(width: 14),
              // Workout info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            workout.workoutName,
                            style: AppTypography.cardTitle.copyWith(
                              color: context.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isToday)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'TODAY',
                              style: AppTypography.labelSmall.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Info chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (workout.workoutType != null)
                          _buildInfoChip(
                            context,
                            workout.workoutType!,
                            Icons.category_outlined,
                          ),
                        if (workout.estimatedDuration != null)
                          _buildInfoChip(
                            context,
                            '${workout.estimatedDuration} min',
                            Icons.timer_outlined,
                          ),
                        _buildInfoChip(
                          context,
                          '${_getExerciseCount()} exercises',
                          Icons.fitness_center,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Status icon
              _buildStatusIcon(context, statusColor, isCompleted, isMissed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayBadge(BuildContext context, Color color, bool isCompleted) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient:
            isCompleted || isToday
                ? LinearGradient(
                  colors: [color, color.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                : null,
        color: isCompleted || isToday ? null : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        boxShadow:
            isToday
                ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
                : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            workout.dayNameFromNumber.substring(0, 3),
            style: AppTypography.labelMedium.copyWith(
              color: isCompleted || isToday ? Colors.white : color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Day ${workout.dayNumber}',
            style: AppTypography.labelSmall.copyWith(
              color:
                  isCompleted || isToday
                      ? Colors.white.withValues(alpha: 0.8)
                      : color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(BuildContext context, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.textTertiary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(
    BuildContext context,
    Color color,
    bool isCompleted,
    bool isMissed,
  ) {
    if (isCompleted) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: context.accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check_rounded, color: context.accent, size: 20),
      );
    }

    if (isMissed) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.accentRose.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.close_rounded,
          color: AppColors.accentRose,
          size: 20,
        ),
      );
    }

    return Icon(
      Icons.chevron_right_rounded,
      color: context.textTertiary,
      size: 24,
    );
  }

  int _getExerciseCount() {
    return workout.exerciseCount;
  }

  Color _getStatusColor(
    BuildContext context,
    bool isCompleted,
    bool isToday,
    bool isMissed,
  ) {
    if (isCompleted) return context.accent;
    if (isMissed) return AppColors.accentRose;
    if (isToday) return AppColors.accentCoral;
    return AppColors.accentSky;
  }
}

/// Compact program selector card
class ProgramSelectorCard extends StatelessWidget {
  final Program program;
  final bool isSelected;
  final VoidCallback? onTap;

  const ProgramSelectorCard({
    super.key,
    required this.program,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumTapAnimation(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? context.accent.withValues(alpha: 0.1)
                  : context.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isSelected
                    ? context.accent.withValues(alpha: 0.4)
                    : context.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Progress indicator
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: program.progressPercentage / 100,
                    strokeWidth: 4,
                    backgroundColor: context.accent.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(
                      program.isCompleted
                          ? context.accent
                          : AppColors.accentSky,
                    ),
                  ),
                  Text(
                    '${program.progressPercentage.toInt()}%',
                    style: AppTypography.labelSmall.copyWith(
                      color: context.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    program.title,
                    style: AppTypography.titleMedium.copyWith(
                      color: context.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Week ${program.currentWeek}/${program.totalWeeks}',
                    style: AppTypography.labelMedium.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: context.accent, size: 22),
          ],
        ),
      ),
    );
  }
}
