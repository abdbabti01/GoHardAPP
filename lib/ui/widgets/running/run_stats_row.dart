import 'package:flutter/material.dart';
import '../../../core/theme/theme_colors.dart';

/// A row displaying run stats with icons
class RunStatsRow extends StatelessWidget {
  final String distance;
  final String duration;
  final String pace;
  final double iconSize;
  final double fontSize;

  const RunStatsRow({
    super.key,
    required this.distance,
    required this.duration,
    required this.pace,
    this.iconSize = 14,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildStat(context, Icons.straighten_rounded, distance),
        const SizedBox(width: 12),
        _buildStat(context, Icons.timer_outlined, duration),
        const SizedBox(width: 12),
        _buildStat(context, Icons.speed_rounded, pace),
      ],
    );
  }

  Widget _buildStat(BuildContext context, IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: context.textTertiary),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// A larger stats display card for run detail screens
class RunStatsCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color? iconColor;

  const RunStatsCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor ?? context.accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                  height: 1,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
