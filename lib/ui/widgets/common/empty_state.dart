import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import 'animations.dart';

/// Premium empty state widget with animations
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Color? iconColor;
  final bool animate;
  final List<QuickSuggestion>? suggestions;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.iconColor,
    this.animate = true,
    this.suggestions,
  });

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon container with pulse
            _buildIconContainer(context),
            const SizedBox(height: 28),
            // Title - larger, bolder
            Text(
              title,
              style: AppTypography.displaySmall.copyWith(
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            // Message
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.textSecondary,
                height: 1.6,
              ),
            ),
            // Contextual suggestions
            if (suggestions != null && suggestions!.isNotEmpty) ...[
              const SizedBox(height: 28),
              _buildSuggestions(context),
            ],
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
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: context.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.25), width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, size: 36, color: color),
        ),
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Quick Start',
            style: AppTypography.labelLarge.copyWith(
              color: context.textSecondary,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              suggestions!.map((suggestion) {
                return _SuggestionChip(suggestion: suggestion);
              }).toList(),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final QuickSuggestion suggestion;

  const _SuggestionChip({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return ScaleTapAnimation(
      onTap: suggestion.onTap,
      scaleDown: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (suggestion.icon != null) ...[
              Icon(suggestion.icon, size: 16, color: context.accent),
              const SizedBox(width: 8),
            ],
            Text(
              suggestion.label,
              style: AppTypography.labelLarge.copyWith(
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick suggestion for empty states
class QuickSuggestion {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const QuickSuggestion({required this.label, this.icon, required this.onTap});
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
                context.accent.withValues(alpha: 0.1),
                context.accent.withValues(alpha: 0.02),
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
              gradient: context.primaryGradient,
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
        gradient: context.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: context.accent.withValues(alpha: 0.3),
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
