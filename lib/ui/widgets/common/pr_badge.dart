import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/services/haptic_service.dart';
import 'animations.dart';

/// Personal Record badge - highlights when user achieves a new PR
class PRBadge extends StatefulWidget {
  final String label;
  final String? value;
  final PRBadgeSize size;
  final bool animate;
  final VoidCallback? onTap;

  const PRBadge({
    super.key,
    this.label = 'PR',
    this.value,
    this.size = PRBadgeSize.medium,
    this.animate = true,
    this.onTap,
  });

  /// Creates a small inline PR indicator
  factory PRBadge.inline({Key? key}) {
    return PRBadge(key: key, size: PRBadgeSize.small, animate: false);
  }

  /// Creates a large celebration PR badge
  factory PRBadge.celebration({
    Key? key,
    required String value,
    String? label,
    VoidCallback? onTap,
  }) {
    return PRBadge(
      key: key,
      label: label ?? 'New Personal Record!',
      value: value,
      size: PRBadgeSize.large,
      animate: true,
      onTap: onTap,
    );
  }

  @override
  State<PRBadge> createState() => _PRBadgeState();
}

class _PRBadgeState extends State<PRBadge> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.15,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40),
    ]).animate(_controller);

    _glowAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.6), weight: 70),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (widget.animate) {
      _controller.forward();
      HapticService.prAchieved();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.size) {
      case PRBadgeSize.small:
        return _buildSmallBadge(context);
      case PRBadgeSize.medium:
        return _buildMediumBadge(context);
      case PRBadgeSize.large:
        return _buildLargeBadge(context);
    }
  }

  Widget _buildSmallBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: _prGradient,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            'PR',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediumBadge(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.animate ? _scaleAnimation.value : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: _prGradient,
              borderRadius: BorderRadius.circular(8),
              boxShadow:
                  widget.animate
                      ? [
                        BoxShadow(
                          color: AppColors.tierGold.withValues(
                            alpha: 0.4 * _glowAnimation.value,
                          ),
                          blurRadius: 12 * _glowAnimation.value,
                          spreadRadius: 2 * _glowAnimation.value,
                        ),
                      ]
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.value != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.value!,
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLargeBadge(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.animate ? _scaleAnimation.value : 1.0,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.tierGold.withValues(alpha: 0.15),
                    AppColors.accentAmber.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.tierGold.withValues(alpha: 0.4),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.tierGold.withValues(
                      alpha: 0.2 * _glowAnimation.value,
                    ),
                    blurRadius: 24 * _glowAnimation.value,
                    spreadRadius: 4 * _glowAnimation.value,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Trophy with glow
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: _prGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.tierGold.withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Label
                  Text(
                    widget.label,
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.tierGold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.value != null) ...[
                    const SizedBox(height: 8),
                    // Value with gradient
                    ShaderMask(
                      shaderCallback:
                          (bounds) => _prGradient.createShader(bounds),
                      child: Text(
                        widget.value!,
                        style: AppTypography.statLarge.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  LinearGradient get _prGradient => const LinearGradient(
    colors: [AppColors.tierGold, AppColors.accentAmber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

enum PRBadgeSize { small, medium, large }

/// PR highlight card - wraps content to highlight a PR achievement
class PRHighlightCard extends StatelessWidget {
  final Widget child;
  final bool isPR;
  final String? prLabel;

  const PRHighlightCard({
    super.key,
    required this.child,
    this.isPR = false,
    this.prLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!isPR) return child;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.tierGold.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.tierGold.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
        Positioned(
          top: -1,
          right: 12,
          child: PRBadge(
            label: prLabel ?? 'PR',
            size: PRBadgeSize.small,
            animate: false,
          ),
        ),
      ],
    );
  }
}

/// Animated PR achieved overlay
class PRAchievedOverlay extends StatefulWidget {
  final String exerciseName;
  final String value;
  final String? previousValue;
  final VoidCallback onDismiss;

  const PRAchievedOverlay({
    super.key,
    required this.exerciseName,
    required this.value,
    this.previousValue,
    required this.onDismiss,
  });

  @override
  State<PRAchievedOverlay> createState() => _PRAchievedOverlayState();
}

class _PRAchievedOverlayState extends State<PRAchievedOverlay> {
  @override
  void initState() {
    super.initState();
    HapticService.prAchieved();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          child: FadeSlideAnimation(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Trophy animation
                  PulseAnimation(
                    minScale: 0.95,
                    maxScale: 1.05,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.tierGold, AppColors.accentAmber],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.tierGold.withValues(alpha: 0.5),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        size: 50,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Title
                  Text(
                    'NEW PERSONAL RECORD!',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.tierGold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Exercise name
                  Text(
                    widget.exerciseName,
                    style: AppTypography.displaySmall.copyWith(
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Value
                  ShaderMask(
                    shaderCallback:
                        (bounds) => const LinearGradient(
                          colors: [AppColors.tierGold, AppColors.accentAmber],
                        ).createShader(bounds),
                    child: Text(
                      widget.value,
                      style: AppTypography.statHero.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),

                  // Previous value
                  if (widget.previousValue != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Previous: ',
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                        Text(
                          widget.previousValue!,
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white60,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 40),

                  // Dismiss hint
                  Text(
                    'Tap anywhere to continue',
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white38,
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
}
