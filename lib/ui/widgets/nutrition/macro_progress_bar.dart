import 'package:flutter/material.dart';

/// A horizontal progress bar for displaying macro nutrient progress
class MacroProgressBar extends StatelessWidget {
  final String label;
  final double current;
  final double goal;
  final Color color;
  final String unit;
  final double height;

  const MacroProgressBar({
    super.key,
    required this.label,
    required this.current,
    required this.goal,
    required this.color,
    this.unit = 'g',
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = goal > 0 ? (current / goal).clamp(0.0, 1.0) : 0.0;
    final isOverGoal = current > goal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
            Text(
              '${current.toStringAsFixed(0)} / ${goal.toStringAsFixed(0)} $unit',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color:
                    isOverGoal
                        ? Colors.red
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: isOverGoal ? FontWeight.bold : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: height,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              isOverGoal ? Colors.red : color,
            ),
          ),
        ),
      ],
    );
  }
}

/// A compact macro chip for displaying in lists
class MacroChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final String unit;

  const MacroChip({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.unit = 'g',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            '${value.toStringAsFixed(0)}$unit',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
