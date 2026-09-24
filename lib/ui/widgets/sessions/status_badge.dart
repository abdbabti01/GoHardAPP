import 'package:flutter/material.dart';

/// Status badge widget for workout sessions
/// Displays colored badge based on session status
class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final badgeData = _getBadgeData(context, status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeData.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: badgeData.color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeData.icon, size: 14, color: badgeData.color),
          const SizedBox(width: 4),
          // Flexible so an increased text scale can never force this
          // badge's own content to overflow, regardless of how tightly a
          // parent (e.g. a Wrap sharing a line with other content)
          // constrains it - status is essential semantics, so the full
          // label always stays available via Semantics even on the rare
          // occasion the visual text needs to ellipsize.
          Flexible(
            child: Semantics(
              label: badgeData.label,
              child: ExcludeSemantics(
                child: Text(
                  badgeData.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: badgeData.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _BadgeData _getBadgeData(BuildContext context, String status) {
    // Fixed grey shades don't self-adjust for theme brightness the way
    // Material's dynamic colors do: shade700 (dark enough to pass 4.5:1 AA
    // on the light theme's near-white background) measures only 2.81:1 on
    // the dark theme's near-black one, so the "unlabeled status" shade
    // is picked per brightness instead of a single fixed value.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutralGrey = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    switch (status.toLowerCase()) {
      case 'completed':
        return _BadgeData(
          label: 'Completed',
          color: Colors.green,
          icon: Icons.check_circle,
        );
      case 'in_progress':
        return _BadgeData(
          label: 'In Progress',
          color: Colors.orange,
          icon: Icons.play_circle_filled,
        );
      case 'planned':
        return _BadgeData(
          label: 'Planned',
          color: Colors.blue,
          icon: Icons.event,
        );
      case 'draft':
        return _BadgeData(label: 'Draft', color: neutralGrey, icon: Icons.edit);
      default:
        return _BadgeData(
          label: status,
          color: neutralGrey,
          icon: Icons.circle,
        );
    }
  }
}

class _BadgeData {
  final String label;
  final Color color;
  final IconData icon;

  _BadgeData({required this.label, required this.color, required this.icon});
}
