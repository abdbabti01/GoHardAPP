import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/achievement.dart';

/// Achievement unlock celebration overlay
class AchievementUnlockOverlay extends StatefulWidget {
  final AchievementDefinition definition;
  final VoidCallback onDismiss;
  final Duration showDuration;

  const AchievementUnlockOverlay({
    super.key,
    required this.definition,
    required this.onDismiss,
    this.showDuration = const Duration(seconds: 4),
  });

  /// Show achievement unlock overlay
  static void show(
    BuildContext context, {
    required AchievementDefinition definition,
    VoidCallback? onDismiss,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder:
          (context) => AchievementUnlockOverlay(
            definition: definition,
            onDismiss: () {
              entry.remove();
              onDismiss?.call();
            },
          ),
    );

    overlay.insert(entry);
  }

  @override
  State<AchievementUnlockOverlay> createState() =>
      _AchievementUnlockOverlayState();
}

class _AchievementUnlockOverlayState extends State<AchievementUnlockOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.1,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_controller);

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Play haptic and start animation
    HapticService.achievementUnlocked();
    _controller.forward();

    // Auto dismiss after duration
    Future.delayed(widget.showDuration, () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _getTierColor(widget.definition.tier);
    final tierGradient = _getTierGradient(widget.definition.tier);

    return GestureDetector(
      onTap: _dismiss,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            color: Colors.black.withValues(alpha: 0.7 * _fadeAnimation.value),
            child: Center(
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Container(
                    margin: const EdgeInsets.all(32),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: tierColor.withValues(alpha: 0.4),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tierColor.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Unlock text
                        Text(
                          'ACHIEVEMENT UNLOCKED',
                          style: AppTypography.labelMedium.copyWith(
                            color: tierColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Badge
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: tierGradient,
                            border: Border.all(color: tierColor, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: tierColor.withValues(alpha: 0.4),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              widget.definition.icon,
                              style: const TextStyle(fontSize: 48),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Achievement name
                        Text(
                          widget.definition.name,
                          style: AppTypography.displaySmall.copyWith(
                            color: context.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 8),

                        // Description
                        Text(
                          widget.definition.description,
                          style: AppTypography.bodyMedium.copyWith(
                            color: context.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 16),

                        // Tier badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: tierColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getTierIcon(widget.definition.tier),
                                size: 16,
                                color: tierColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _getTierName(widget.definition.tier),
                                style: AppTypography.labelMedium.copyWith(
                                  color: tierColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Tap to dismiss
                        Text(
                          'Tap to continue',
                          style: AppTypography.bodySmall.copyWith(
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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

  String _getTierName(AchievementTier tier) {
    switch (tier) {
      case AchievementTier.bronze:
        return 'BRONZE';
      case AchievementTier.silver:
        return 'SILVER';
      case AchievementTier.gold:
        return 'GOLD';
      case AchievementTier.platinum:
        return 'PLATINUM';
    }
  }
}
