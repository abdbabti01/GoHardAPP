import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/session.dart';
import 'quick_actions_sheet.dart';

/// Premium card widget for displaying a workout session
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
    final statusColor = isCompleted
        ? AppColors.goHardGreen
        : (isInProgress ? AppColors.goHardOrange : AppColors.goHardBlue);

    final statusGradient = isCompleted
        ? AppColors.successGradient
        : (isInProgress ? AppColors.activeGradient : AppColors.secondaryGradient);

    return Dismissible(
      key: Key('session_${session.id}'),
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(),
      confirmDismiss: (direction) async {
        return await _showDeleteConfirmation(context);
      },
      onDismissed: (direction) {
        onDelete?.call();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isInProgress
                ? statusColor.withValues(alpha: 0.3)
                : context.border,
            width: isInProgress ? 1.5 : 0.5,
          ),
          boxShadow: isInProgress
              ? [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: () => _showQuickActions(context),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Premium gradient icon container
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: isCompleted || isInProgress
                          ? statusGradient
                          : null,
                      color: isPlanned
                          ? statusColor.withValues(alpha: 0.15)
                          : null,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: isCompleted || isInProgress
                          ? [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
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
                      color: isCompleted || isInProgress
                          ? Colors.white
                          : statusColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Workout info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Workout name - bolder
                        Text(
                          session.name ?? _getDefaultName(),
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Meta info row
                        Row(
                          children: [
                            // Date
                            Text(
                              _formatDate(session.date),
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: context.textTertiary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            // Exercise count with icon
                            Icon(
                              Icons.fitness_center_rounded,
                              size: 14,
                              color: context.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${session.exercises.length}',
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status badge
                  _buildStatusBadge(context, isCompleted, isInProgress, statusColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
