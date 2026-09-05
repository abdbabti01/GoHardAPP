import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/sessions_provider.dart';

/// Passive, aggregate, user-scoped banner surfacing retained Session sync
/// failures and conflicts. Read-only: no dismiss control, no button, no
/// action of any kind - it cannot mutate `LocalSession`, call
/// `SyncService`, or make an HTTP request. All state comes from
/// [SessionsProvider], which is itself reset on logout/`clear()` - this
/// widget never reads `SyncService` directly.
///
/// Hidden when there is nothing to show, and hidden while offline (the
/// existing [OfflineBanner] above it already explains why nothing is
/// syncing - showing both would be redundant, and would misleadingly frame
/// an expected offline state as an error).
class SyncIssuesBanner extends StatelessWidget {
  const SyncIssuesBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isOnline = context.select<ConnectivityService, bool>(
      (c) => c.isOnline,
    );
    final counts = context.select<SessionsProvider, (int, int)>(
      (p) => (p.retryingFailureCount, p.conflictCount),
    );
    final (retryingCount, conflictCount) = counts;

    if (!isOnline || (retryingCount == 0 && conflictCount == 0)) {
      return const SizedBox.shrink();
    }

    // Conflict and "still retrying" are semantically distinct passive
    // states - a conflict is never described as "retrying", and vice versa.
    // Render each present state as its own row rather than merging them
    // into one ambiguous line.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (retryingCount > 0)
            _SyncIssueRow(
              icon: Icons.sync_problem_rounded,
              color: context.warning,
              label:
                  retryingCount == 1
                      ? "1 workout hasn't synced yet. Your changes are saved "
                          'and automatic retry will continue.'
                      : "$retryingCount workouts haven't synced yet. Your "
                          'changes are saved and automatic retry will '
                          'continue.',
            ),
          if (retryingCount > 0 && conflictCount > 0) const SizedBox(height: 6),
          if (conflictCount > 0)
            _SyncIssueRow(
              icon: Icons.warning_rounded,
              color: context.error,
              label:
                  conflictCount == 1
                      ? '1 workout needs review. Your local changes are '
                          'preserved.'
                      : '$conflictCount workouts need review. Your local '
                          'changes are preserved.',
            ),
        ],
      ),
    );
  }
}

class _SyncIssueRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _SyncIssueRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
