import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import 'animations.dart';

/// Premium empty state widget with animations
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Color? iconColor;
  final bool animate;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.iconColor,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon container
            _buildIconContainer(context),
            const SizedBox(height: 24),
            // Title
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Message
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: context.textSecondary,
                height: 1.5,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 32), action!],
          ],
        ),
      ),
    );

    if (animate) {
      return FadeSlideAnimation(
        duration: const Duration(milliseconds: 500),
        child: content,
      );
    }
    return content;
  }

  Widget _buildIconContainer(BuildContext context) {
    final color = iconColor ?? context.accent;

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.15),
            color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
      ),
      child: Icon(icon, size: 44, color: color),
    );
  }
}

/// Premium empty state with illustration placeholder
class EmptyStateIllustrated extends StatelessWidget {
  final String title;
  final String message;
  final Widget? illustration;
  final Widget? action;
  final IconData fallbackIcon;

  const EmptyStateIllustrated({
    super.key,
    required this.title,
    required this.message,
    this.illustration,
    this.action,
    this.fallbackIcon = Icons.inbox_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return FadeSlideAnimation(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Illustration or fallback
              illustration ?? _buildFallbackIllustration(context),
              const SizedBox(height: 32),
              // Title
              Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.textSecondary,
                    height: 1.6,
                  ),
                ),
              ),
              if (action != null) ...[const SizedBox(height: 32), action!],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackIllustration(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background circles
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                AppColors.goHardGreen.withValues(alpha: 0.1),
                AppColors.goHardGreen.withValues(alpha: 0.02),
              ],
            ),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: context.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(color: context.border, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(fallbackIcon, size: 44, color: context.textTertiary),
        ),
        // Decorative elements
        Positioned(
          top: 10,
          right: 20,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: 20,
          left: 15,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.goHardBlue,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

/// Action button for empty states
class EmptyStateAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const EmptyStateAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.goHardGreen.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: AppColors.goHardBlack),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.goHardBlack,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
