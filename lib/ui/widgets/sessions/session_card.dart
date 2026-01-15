import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/models/session.dart';
import 'quick_actions_sheet.dart';

/// Card widget for displaying a workout session
/// Matches SessionCard from MAUI app
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
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
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
                  // Icon on the left in circular container
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color:
                          isCompleted
                              ? Colors.green.withValues(alpha: 0.2)
                              : (isInProgress
                                  ? Colors.orange.withValues(alpha: 0.2)
                                  : Colors.blue.withValues(alpha: 0.2)),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCompleted
                          ? Icons.check_circle
                          : (isInProgress
                              ? Icons.play_circle_filled
                              : Icons.fitness_center),
                      color:
                          isCompleted
                              ? Colors.green.shade400
                              : (isInProgress
                                  ? Colors.orange.shade400
                                  : Colors.blue.shade400),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Workout info in the middle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Workout name
                        Text(
                          session.name ?? _getDefaultName(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Date and exercise count
                        Row(
                          children: [
                            Text(
                              _formatDate(session.date),
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '•',
                              style: TextStyle(color: Colors.grey.shade400),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.fitness_center,
                              size: 12,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${session.exercises.length} ${session.exercises.length == 1 ? 'exercise' : 'exercises'}',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status indicator on the right
                  if (isCompleted)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 14,
                      ),
                    )
                  else if (isInProgress)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 14,
                      ),
                    )
                  else
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey.shade500,
                          width: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
