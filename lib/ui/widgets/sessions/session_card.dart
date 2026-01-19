import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/services/haptic_service.dart';
import '../../../data/models/session.dart';
import '../common/animations.dart';
import 'quick_actions_sheet.dart';

/// Premium card widget for displaying a workout session
/// PREMIUM DESIGN: Increased padding, subtle shadows, strong typography hierarchy
class SessionCard extends StatelessWidget {
  final Session session;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onReschedule;
  final VoidCallback? onDuplicate;

  const SessionCard({
    super.key,
    required this.session,
    this.onTap,
    this.onDelete,
    this.onReschedule,
    this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = session.status == 'completed';
    final isInProgress = session.status == 'in_progress';
    final isPlanned = session.status == 'planned';

    // Status-based colors
    final statusColor =
        isCompleted
            ? AppColors.accentGreen
            : (isInProgress ? AppColors.accentCoral : AppColors.accentSky);

    final statusGradient =
        isCompleted
            ? AppColors.successGradient
            : (isInProgress
                ? AppColors.activeGradient
                : AppColors.secondaryGradient);

    return Dismissible(
      key: Key('session_${session.id}'),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(),
      confirmDismiss: (direction) async {
        HapticService.swipeAction();
        return await _showDeleteConfirmation(context);
      },
      onDismissed: (direction) {
        HapticService.deleteAction();
        onDelete?.call();
      },
      child: PremiumTapAnimation(
        onTap: () {
          HapticService.cardTap();
          onTap?.call();
        },
        onLongPress: () => _showQuickActions(context),
        enableHaptics: false, // Already handling haptics above
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  isInProgress
                      ? statusColor.withValues(alpha: 0.4)
                      : context.border.withValues(alpha: 0.8),
              width: isInProgress ? 1.5 : 1,
            ),
            boxShadow: [
              // Subtle shadow for all cards - premium depth
              BoxShadow(
                color:
                    context.isDarkMode
                        ? Colors.black.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              // Extra glow for active workouts
              if (isInProgress)
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18), // INCREASED from 16
            child: Row(
              children: [
                // Premium gradient icon container
                Container(
                  width: 56, // INCREASED from 52
                  height: 56,
                  decoration: BoxDecoration(
                    gradient:
                        isCompleted || isInProgress ? statusGradient : null,
                    color:
                        isPlanned ? statusColor.withValues(alpha: 0.12) : null,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow:
                        isCompleted || isInProgress
                            ? [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                            : null,
                  ),
                  child: Icon(
                    isCompleted
                        ? Icons.check_rounded
                        : (isInProgress
                            ? Icons.play_arrow_rounded
                            : Icons.event_rounded),
                    color:
                        isCompleted || isInProgress
                            ? Colors.white
                            : statusColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16), // INCREASED from 14
                // Workout info - IMPROVED TYPOGRAPHY
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Workout name - using card title style
                      Text(
                        session.name ?? _getDefaultName(),
                        style: AppTypography.cardTitle.copyWith(
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Meta info row - smaller text for hierarchy
                      Row(
                        children: [
                          // Date
                          Text(
                            _formatDate(session.date),
                            style: AppTypography.cardMeta.copyWith(
                              color: context.textSecondary,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: context.textTertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          // Exercise count with icon
                          Icon(
                            Icons.fitness_center_rounded,
                            size: 12,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${session.exercises.length} exercises',
                            style: AppTypography.cardMeta.copyWith(
                              color: context.textSecondary,
                            ),
                          ),
                          // Duration if completed
                          if (isCompleted && session.duration != null) ...[
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: context.textTertiary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Icon(
                              Icons.timer_outlined,
                              size: 12,
                              color: context.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(session.duration!),
                              style: AppTypography.cardMeta.copyWith(
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Status badge
                _buildStatusBadge(
                  context,
                  isCompleted,
                  isInProgress,
                  statusColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  Widget _buildStatusBadge(
    BuildContext context,
    bool isCompleted,
    bool isInProgress,
    Color statusColor,
  ) {
    if (isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 14, color: statusColor),
            const SizedBox(width: 4),
            Text(
              'Done',
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    } else if (isInProgress) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: AppColors.activeGradient,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'Active',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    } else {
      return Icon(
        Icons.chevron_right_rounded,
        color: context.textTertiary,
        size: 24,
      );
    }
  }

  void _showQuickActions(BuildContext context) {
    QuickActionsSheet.show(
      context,
      session,
      onReschedule: onReschedule,
      onDuplicate: onDuplicate,
    );
  }

  Widget _buildDismissBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete, color: Colors.white, size: 32),
          SizedBox(height: 4),
          Text(
            'Delete',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmation(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Session'),
            content: const Text(
              'Are you sure you want to delete this workout session? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  String _getDefaultName() {
    // Generate default name based on date
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDate = DateTime(
      session.date.year,
      session.date.month,
      session.date.day,
    );

    final daysDifference = today.difference(sessionDate).inDays;

    if (daysDifference == 0) {
      return 'Today\'s Workout';
    } else if (daysDifference == 1) {
      return 'Yesterday\'s Workout';
    } else {
      return 'Workout';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final sessionDate = DateTime(date.year, date.month, date.day);

    if (sessionDate == today) {
      return 'Today';
    } else if (sessionDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }
}
