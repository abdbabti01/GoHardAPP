import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/exercise_template.dart';

/// Premium exercise card with modern design
class ExerciseCard extends StatelessWidget {
  final ExerciseTemplate exercise;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showDetails;

  const ExerciseCard({
    super.key,
    required this.exercise,
    this.onTap,
    this.trailing,
    this.showDetails = true,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Exercise icon with category color
                _buildIconContainer(context, categoryColor),
                const SizedBox(width: 14),

                // Exercise details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Exercise name
                      Text(
                        exercise.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // Tags row
                      _buildTagsRow(context, categoryColor),

                      // Equipment and difficulty
                      if (showDetails &&
                          (exercise.equipment != null ||
                              exercise.difficulty != null)) ...[
                        const SizedBox(height: 8),
                        _buildDetailsRow(context),
                      ],
                    ],
                  ),
                ),

                // Trailing widget
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ] else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.textTertiary,
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconContainer(BuildContext context, Color categoryColor) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            categoryColor.withValues(alpha: 0.2),
            categoryColor.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: categoryColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Icon(_getExerciseIcon(), size: 24, color: categoryColor),
    );
  }

  Widget _buildTagsRow(BuildContext context, Color categoryColor) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (exercise.category != null)
          _buildTag(context, exercise.category!, categoryColor, filled: true),
        if (exercise.muscleGroup != null)
          _buildTag(context, exercise.muscleGroup!, AppColors.goHardBlue),
      ],
    );
  }

  Widget _buildTag(
    BuildContext context,
    String label,
    Color color, {
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.15) : context.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: filled ? null : Border.all(color: context.border, width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? color : context.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDetailsRow(BuildContext context) {
    return Row(
      children: [
        if (exercise.equipment != null) ...[
          Icon(
            Icons.fitness_center_rounded,
            size: 13,
            color: context.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            exercise.equipment!,
            style: TextStyle(
              fontSize: 12,
              color: context.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (exercise.equipment != null && exercise.difficulty != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: context.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
        if (exercise.difficulty != null) ...[
          _buildDifficultyIndicator(context),
          const SizedBox(width: 4),
          Text(
            exercise.difficulty!,
            style: TextStyle(
              fontSize: 12,
              color: _getDifficultyColor(context, exercise.difficulty!),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDifficultyIndicator(BuildContext context) {
    final difficulty = exercise.difficulty?.toLowerCase() ?? 'intermediate';
    final color = _getDifficultyColor(context, difficulty);
    final bars =
        difficulty == 'beginner'
            ? 1
            : difficulty == 'advanced'
            ? 3
            : 2;

    return Row(
      children: List.generate(3, (index) {
        return Container(
          width: 3,
          height: 8 + (index * 2).toDouble(),
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: index < bars ? color : context.border,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  Color _getCategoryColor(BuildContext context) {
    if (exercise.category == null) return context.accent;

    switch (exercise.category!.toLowerCase()) {
      case 'strength':
        return AppColors.strengthRed;
      case 'cardio':
        return AppColors.cardioBlue;
      case 'flexibility':
        return AppColors.flexibilityGreen;
      case 'balance':
      case 'core':
        return AppColors.coreOrange;
      default:
        return context.accent;
    }
  }

  IconData _getExerciseIcon() {
    if (exercise.category == null) return Icons.fitness_center_rounded;

    switch (exercise.category!.toLowerCase()) {
      case 'strength':
        return Icons.fitness_center_rounded;
      case 'cardio':
        return Icons.directions_run_rounded;
      case 'flexibility':
        return Icons.self_improvement_rounded;
      case 'balance':
        return Icons.accessibility_new_rounded;
      case 'core':
        return Icons.sports_martial_arts_rounded;
      default:
        return Icons.fitness_center_rounded;
    }
  }

  Color _getDifficultyColor(BuildContext context, String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'beginner':
        return context.accent;
      case 'intermediate':
        return AppColors.goHardOrange;
      case 'advanced':
        return AppColors.errorRed;
      default:
        return context.accent;
    }
  }
}

/// Compact exercise card for lists within active workout
class ExerciseCardCompact extends StatelessWidget {
  final ExerciseTemplate exercise;
  final VoidCallback? onTap;
  final Widget? trailing;
  final int? setCount;
  final bool isActive;

  const ExerciseCardCompact({
    super.key,
    required this.exercise,
    this.onTap,
    this.trailing,
    this.setCount,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? context.surfaceHighlight : context.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isActive ? context.accent.withValues(alpha: 0.3) : context.border,
          width: isActive ? 1.5 : 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Category indicator
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),

                // Exercise name and sets
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (setCount != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$setCount ${setCount == 1 ? 'set' : 'sets'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Trailing
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(BuildContext context) {
    if (exercise.category == null) return context.accent;

    switch (exercise.category!.toLowerCase()) {
      case 'strength':
        return AppColors.strengthRed;
      case 'cardio':
        return AppColors.cardioBlue;
      case 'flexibility':
        return AppColors.flexibilityGreen;
      default:
        return context.accent;
    }
  }
}
