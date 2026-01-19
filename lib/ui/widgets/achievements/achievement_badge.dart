import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/achievement.dart';
import '../../../data/repositories/achievement_repository.dart';

/// Premium achievement badge widget
class AchievementBadge extends StatelessWidget {
  final AchievementDefinition definition;
  final bool isUnlocked;
  final double? progress;
  final double size;
  final bool showProgress;
  final VoidCallback? onTap;

  const AchievementBadge({
    super.key,
    required this.definition,
    this.isUnlocked = false,
    this.progress,
    this.size = 80,
    this.showProgress = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tierColor = _getTierColor(definition.tier);
    final tierGradient = _getTierGradient(definition.tier);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Badge icon
          Stack(
            alignment: Alignment.center,
            children: [
              // Progress ring (if showing progress)
              if (showProgress && !isUnlocked && progress != null)
                SizedBox(
                  width: size + 8,
                  height: size + 8,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    backgroundColor: context.border,
                    color: tierColor.withValues(alpha: 0.7),
                  ),
                ),

              // Badge container
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isUnlocked ? tierGradient : null,
                  color: isUnlocked ? null : context.surfaceElevated,
                  border: Border.all(
                    color: isUnlocked ? tierColor : context.border,
                    width: isUnlocked ? 3 : 1,
                  ),
                  boxShadow:
                      isUnlocked
                          ? [
                            BoxShadow(
                              color: tierColor.withValues(alpha: 0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ]
                          : null,
                ),
                child: Center(
                  child:
                      isUnlocked
                          ? Text(
                            definition.icon,
                            style: TextStyle(fontSize: size * 0.45),
                          )
                          : Icon(
                            Icons.lock_outline_rounded,
                            size: size * 0.35,
                            color: context.textTertiary,
                          ),
                ),
              ),

              // Tier badge
              if (isUnlocked)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: tierColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.surface, width: 2),
                    ),
                    child: Icon(
                      _getTierIcon(definition.tier),
                      size: size * 0.18,
                      color: _getTierIconColor(definition.tier),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          // Name
          SizedBox(
            width: size + 20,
            child: Text(
              definition.name,
              style: AppTypography.labelMedium.copyWith(
                color: isUnlocked ? context.textPrimary : context.textTertiary,
                fontWeight: isUnlocked ? FontWeight.w600 : FontWeight.w400,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTierColor(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze:
        return AppColors.tierBronze;
      case AchievementTier.silver:
        return AppColors.tierSilver;
      case AchievementTier.gold:
        return AppColors.tierGold;
      case AchievementTier.platinum:
        return AppColors.tierPlatinum;
    }
  }

  LinearGradient _getTierGradient(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze:
        return AppColors.bronzeGradient;
      case AchievementTier.silver:
        return AppColors.silverGradient;
      case AchievementTier.gold:
        return AppColors.goldGradient;
      case AchievementTier.platinum:
        return AppColors.platinumGradient;
    }
  }

  IconData _getTierIcon(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze:
        return Icons.star_rounded;
      case AchievementTier.silver:
        return Icons.star_rounded;
      case AchievementTier.gold:
        return Icons.star_rounded;
      case AchievementTier.platinum:
        return Icons.diamond_rounded;
    }
  }

  Color _getTierIconColor(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze:
      case AchievementTier.gold:
        return AppColors.charcoal;
      case AchievementTier.silver:
      case AchievementTier.platinum:
        return AppColors.charcoal;
    }
  }
}

/// Compact achievement badge for lists
class CompactAchievementBadge extends StatelessWidget {
  final AchievementProgress progress;
  final VoidCallback? onTap;

  const CompactAchievementBadge({
    super.key,
    required this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final def = progress.definition;
    final tierColor = _getTierColor(def.tier);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                progress.isUnlocked
                    ? tierColor.withValues(alpha: 0.3)
                    : context.border,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient:
                    progress.isUnlocked ? _getTierGradient(def.tier) : null,
                color: progress.isUnlocked ? null : context.surfaceElevated,
                border: Border.all(
                  color: progress.isUnlocked ? tierColor : context.border,
                  width: 2,
                ),
              ),
              child: Center(
                child:
                    progress.isUnlocked
                        ? Text(def.icon, style: const TextStyle(fontSize: 24))
                        : Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: context.textTertiary,
                        ),
              ),
            ),

            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          def.name,
                          style: AppTypography.titleMedium.copyWith(
                            color:
                                progress.isUnlocked
                                    ? context.textPrimary
                                    : context.textSecondary,
                          ),
                        ),
                      ),
                      _TierChip(tier: def.tier),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    def.description,
                    style: AppTypography.bodySmall.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                  if (!progress.isUnlocked) ...[
                    const SizedBox(height: 8),
                    // Progress bar
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress.progressPercentage,
                              backgroundColor: context.surfaceElevated,
                              color: tierColor,
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${progress.currentValue}/${def.requirement}',
                          style: AppTypography.labelSmall.copyWith(
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTierColor(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze:
        return AppColors.tierBronze;
      case AchievementTier.silver:
        return AppColors.tierSilver;
      case AchievementTier.gold:
        return AppColors.tierGold;
      case AchievementTier.platinum:
        return AppColors.tierPlatinum;
    }
  }

  LinearGradient _getTierGradient(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze:
        return AppColors.bronzeGradient;
      case AchievementTier.silver:
        return AppColors.silverGradient;
      case AchievementTier.gold:
        return AppColors.goldGradient;
      case AchievementTier.platinum:
        return AppColors.platinumGradient;
    }
  }
}

/// Small tier indicator chip
class _TierChip extends StatelessWidget {
  final AchievementTier tier;

  const _TierChip({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getTierColor(tier).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _getTierName(tier),
        style: AppTypography.labelSmall.copyWith(
          color: _getTierColor(tier),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getTierColor(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze:
        return AppColors.tierBronze;
      case AchievementTier.silver:
        return AppColors.tierSilver;
      case AchievementTier.gold:
        return AppColors.tierGold;
      case AchievementTier.platinum:
        return AppColors.tierPlatinum;
    }
  }

  String _getTierName(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze:
        return 'Bronze';
      case AchievementTier.silver:
        return 'Silver';
      case AchievementTier.gold:
        return 'Gold';
      case AchievementTier.platinum:
        return 'Platinum';
    }
  }
}
