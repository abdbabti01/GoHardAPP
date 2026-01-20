import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/services/haptic_service.dart';
import '../../../data/models/goal.dart';
import '../common/animations.dart';
import '../common/progress_ring.dart';

/// Premium goal card with progress ring and modern styling
class PremiumGoalCard extends StatelessWidget {
  final Goal goal;
  final VoidCallback? onTap;
  final VoidCallback? onAddProgress;
  final Function(String)? onMenuAction;
  final int streak;

  const PremiumGoalCard({
    super.key,
    required this.goal,
    this.onTap,
    this.onAddProgress,
    this.onMenuAction,
    this.streak = 0,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (goal.progressPercentage / 100).clamp(0.0, 1.0);
    final isCompleted = goal.progressPercentage >= 100;
    final goalColor = _getGoalColor(context, goal.goalType);

    return PremiumTapAnimation(
      onTap: () {
        HapticService.cardTap();
        onTap?.call();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(20),
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
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            if (isCompleted)
              BoxShadow(
                color: context.accent.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with progress ring and info
              Row(
                children: [
                  // Progress Ring with Icon
                  _buildProgressRing(context, progress, goalColor),
                  const SizedBox(width: 16),
                  // Goal Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatGoalType(goal.goalType),
                          style: AppTypography.cardTitle.copyWith(
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          goal.getProgressDescription(),
                          style: AppTypography.cardMeta.copyWith(
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Menu
                  if (onMenuAction != null)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: context.textTertiary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      itemBuilder:
                          (context) => [
                            _buildMenuItem(
                              'create_program',
                              Icons.auto_awesome,
                              'Create Program',
                            ),
                            _buildMenuItem(
                              'reminder',
                              Icons.notifications_outlined,
                              'Set Reminder',
                            ),
                            _buildMenuItem(
                              'complete',
                              Icons.check_circle_outline,
                              'Mark Complete',
                            ),
                            _buildMenuItem(
                              'delete',
                              Icons.delete_outline,
                              'Delete',
                              isDestructive: true,
                            ),
                          ],
                      onSelected: onMenuAction,
                    ),
                ],
              ),

              const SizedBox(height: 20),

              // Stats Row (for weight goals)
              if (_isWeightGoal(goal)) ...[
                _buildWeightStats(context, goalColor),
                const SizedBox(height: 16),
              ],

              // Progress bar and percentage
              _buildProgressSection(context, progress, goalColor),

              const SizedBox(height: 16),

              // Action button or completion badge
              if (isCompleted)
                _buildCompletedBadge(context)
              else
                _buildAddProgressButton(context, goalColor),

              // AI Suggestion
              if (!isCompleted && goal.getProgressSuggestion() != null) ...[
                const SizedBox(height: 16),
                _buildAISuggestion(context, goalColor),
              ],

              // Target date
              if (goal.targetDate != null) ...[
                const SizedBox(height: 12),
                _buildTargetDate(context, goalColor),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressRing(
    BuildContext context,
    double progress,
    Color color,
  ) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ProgressRing(
          progress: progress,
          size: 72,
          strokeWidth: 6,
          progressColor: color,
          backgroundColor: color.withValues(alpha: 0.12),
        ),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(_getGoalIcon(goal.goalType), color: color, size: 26),
        ),
      ],
    );
  }

  Widget _buildWeightStats(BuildContext context, Color goalColor) {
    final currentWeight = _calculateCurrentWeight();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: goalColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: goalColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatColumn(
              context,
              'Starting',
              goal.startValue.toStringAsFixed(1),
              goal.unit ?? 'kg',
              context.textSecondary,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: goalColor.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _buildStatColumn(
              context,
              'Current',
              currentWeight.toStringAsFixed(1),
              goal.unit ?? 'kg',
              goalColor,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: goalColor.withValues(alpha: 0.2),
          ),
          Expanded(
            child: _buildStatColumn(
              context,
              'Target',
              goal.targetValue.toStringAsFixed(1),
              goal.unit ?? 'kg',
              context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(
    BuildContext context,
    String label,
    String value,
    String unit,
    Color valueColor,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(color: context.textTertiary),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: AppTypography.statTiny.copyWith(color: valueColor),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: AppTypography.labelSmall.copyWith(
                color: valueColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressSection(
    BuildContext context,
    double progress,
    Color goalColor,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${goal.progressPercentage.toStringAsFixed(0)}% Complete',
                    style: AppTypography.titleMedium.copyWith(color: goalColor),
                  ),
                  if (streak > 0) _buildStreakBadge(context),
                ],
              ),
              const SizedBox(height: 10),
              // Progress bar
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: goalColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [goalColor, goalColor.withValues(alpha: 0.8)],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStreakBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: AppColors.streakGradient,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            '$streak day${streak > 1 ? 's' : ''}',
            style: AppTypography.labelMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedBadge(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.accent.withValues(alpha: 0.1),
            context.accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: context.accent, size: 22),
          const SizedBox(width: 10),
          Text(
            'Goal Completed!',
            style: AppTypography.titleMedium.copyWith(color: context.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildAddProgressButton(BuildContext context, Color goalColor) {
    return ScaleTapAnimation(
      onTap: () {
        HapticService.buttonTap();
        onAddProgress?.call();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [goalColor, goalColor.withValues(alpha: 0.85)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: goalColor.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'Add Progress',
              style: AppTypography.titleMedium.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAISuggestion(BuildContext context, Color goalColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            goalColor.withValues(alpha: 0.08),
            goalColor.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: goalColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: goalColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.lightbulb_outline, size: 16, color: goalColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              goal.getProgressSuggestion()!,
              style: AppTypography.bodySmall.copyWith(
                color: context.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetDate(BuildContext context, Color goalColor) {
    final daysLeft = goal.targetDate!.difference(DateTime.now()).inDays;
    final isOverdue = daysLeft < 0;

    return Row(
      children: [
        Icon(
          Icons.calendar_today_outlined,
          size: 14,
          color: isOverdue ? AppColors.accentRose : context.textTertiary,
        ),
        const SizedBox(width: 6),
        Text(
          isOverdue ? '${-daysLeft} days overdue' : '$daysLeft days remaining',
          style: AppTypography.labelMedium.copyWith(
            color: isOverdue ? AppColors.accentRose : context.textSecondary,
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    String value,
    IconData icon,
    String label, {
    bool isDestructive = false,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isDestructive ? AppColors.accentRose : null,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: isDestructive ? AppColors.accentRose : null,
            ),
          ),
        ],
      ),
    );
  }

  bool _isWeightGoal(Goal goal) {
    final type = goal.goalType.toLowerCase();
    return type.contains('weight') || type.contains('muscle');
  }

  double _calculateCurrentWeight() {
    if (goal.isDecreaseGoal) {
      return goal.currentValue - goal.totalProgress;
    } else {
      return goal.currentValue + goal.totalProgress;
    }
  }

  String _formatGoalType(String type) {
    return type
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) =>
              word.isNotEmpty
                  ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
                  : '',
        )
        .join(' ');
  }

  Color _getGoalColor(BuildContext context, String goalType) {
    switch (goalType.toLowerCase()) {
      case 'weight':
      case 'weight_loss':
        return AppColors.accentSky;
      case 'muscle_gain':
        return AppColors.accentCoral;
      case 'workout_frequency':
        return context.accent;
      case 'volume':
        return AppColors.accentAmber;
      case 'body_fat':
        return AppColors.accentRose;
      case 'exercise':
        return const Color(0xFF8B5CF6); // Purple
      default:
        return AppColors.accentSky;
    }
  }

  IconData _getGoalIcon(String goalType) {
    switch (goalType.toLowerCase()) {
      case 'weight':
      case 'weight_loss':
        return Icons.monitor_weight_outlined;
      case 'muscle_gain':
        return Icons.fitness_center;
      case 'workout_frequency':
        return Icons.calendar_month;
      case 'volume':
        return Icons.trending_up;
      case 'body_fat':
        return Icons.percent;
      case 'exercise':
        return Icons.sports_gymnastics;
      default:
        return Icons.flag_outlined;
    }
  }
}

/// Compact completed goal card
class CompletedGoalCard extends StatelessWidget {
  final Goal goal;
  final VoidCallback? onTap;

  const CompletedGoalCard({super.key, required this.goal, this.onTap});

  @override
  Widget build(BuildContext context) {
    return PremiumTapAnimation(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.check_circle, color: context.accent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.goalType
                        .replaceAll('_', ' ')
                        .split(' ')
                        .map(
                          (w) =>
                              w.isNotEmpty
                                  ? '${w[0].toUpperCase()}${w.substring(1)}'
                                  : '',
                        )
                        .join(' '),
                    style: AppTypography.titleMedium.copyWith(
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Completed ${_formatDate(goal.completedAt ?? goal.createdAt)}',
                    style: AppTypography.labelMedium.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.textTertiary),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    if (diff < 7) return '$diff days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
