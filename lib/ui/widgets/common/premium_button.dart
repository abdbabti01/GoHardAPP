import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/services/haptic_service.dart';

/// Premium button variants for consistent styling across the app
enum PremiumButtonVariant {
  /// Primary action - green gradient with shadow
  primary,

  /// Secondary action - surface color with border
  secondary,

  /// Tertiary action - text only, minimal styling
  tertiary,

  /// Destructive action - red themed
  destructive,

  /// Ghost button - transparent with subtle hover
  ghost,
}

/// Premium button sizes
enum PremiumButtonSize {
  /// Small - 40px height, 13px text
  small,

  /// Medium - 48px height, 15px text (default)
  medium,

  /// Large - 56px height, 16px text
  large,
}

/// A premium, consistently styled button component
/// Features: haptic feedback, scale animation on press, consistent styling
class PremiumButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool iconTrailing;
  final PremiumButtonVariant variant;
  final PremiumButtonSize size;
  final bool isLoading;
  final bool expand;
  final bool enableHaptics;

  const PremiumButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.iconTrailing = false,
    this.variant = PremiumButtonVariant.primary,
    this.size = PremiumButtonSize.medium,
    this.isLoading = false,
    this.expand = false,
    this.enableHaptics = true,
  });

  /// Primary CTA button
  factory PremiumButton.primary({
    Key? key,
    required String label,
    VoidCallback? onPressed,
    IconData? icon,
    bool isLoading = false,
    bool expand = false,
  }) {
    return PremiumButton(
      key: key,
      label: label,
      onPressed: onPressed,
      icon: icon,
      variant: PremiumButtonVariant.primary,
      isLoading: isLoading,
      expand: expand,
    );
  }

  /// Secondary button
  factory PremiumButton.secondary({
    Key? key,
    required String label,
    VoidCallback? onPressed,
    IconData? icon,
    bool expand = false,
  }) {
    return PremiumButton(
      key: key,
      label: label,
      onPressed: onPressed,
      icon: icon,
      variant: PremiumButtonVariant.secondary,
      expand: expand,
    );
  }

  /// Text-only button
  factory PremiumButton.text({
    Key? key,
    required String label,
    VoidCallback? onPressed,
    IconData? icon,
  }) {
    return PremiumButton(
      key: key,
      label: label,
      onPressed: onPressed,
      icon: icon,
      variant: PremiumButtonVariant.tertiary,
    );
  }

  /// Destructive/danger button
  factory PremiumButton.destructive({
    Key? key,
    required String label,
    VoidCallback? onPressed,
    IconData? icon,
  }) {
    return PremiumButton(
      key: key,
      label: label,
      onPressed: onPressed,
      icon: icon,
      variant: PremiumButtonVariant.destructive,
    );
  }

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed == null || widget.isLoading) return;
    _controller.forward();
    if (widget.enableHaptics) {
      HapticService.buttonTap();
    }
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    if (widget.onPressed != null && !widget.isLoading) {
      widget.onPressed!();
    }
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null || widget.isLoading;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: isDisabled ? 0.5 : 1.0,
              child: _buildButton(context),
            ),
          );
        },
      ),
    );
  }

  Widget _buildButton(BuildContext context) {
    final height = _getHeight();
    final padding = _getPadding();
    final textStyle = _getTextStyle();
    final iconSize = _getIconSize();

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading) ...[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(_getTextColor(context)),
            ),
          ),
          const SizedBox(width: 10),
        ] else if (widget.icon != null && !widget.iconTrailing) ...[
          Icon(widget.icon, size: iconSize, color: _getTextColor(context)),
          const SizedBox(width: 10),
        ],
        Text(
          widget.label,
          style: textStyle.copyWith(color: _getTextColor(context)),
        ),
        if (widget.icon != null &&
            widget.iconTrailing &&
            !widget.isLoading) ...[
          const SizedBox(width: 10),
          Icon(widget.icon, size: iconSize, color: _getTextColor(context)),
        ],
      ],
    );

    if (widget.variant == PremiumButtonVariant.tertiary) {
      return Padding(padding: padding, child: content);
    }

    return Container(
      height: height,
      width: widget.expand ? double.infinity : null,
      decoration: _getDecoration(context),
      child: Padding(padding: padding, child: content),
    );
  }

  double _getHeight() {
    switch (widget.size) {
      case PremiumButtonSize.small:
        return 40;
      case PremiumButtonSize.medium:
        return 48;
      case PremiumButtonSize.large:
        return 56;
    }
  }

  EdgeInsets _getPadding() {
    switch (widget.size) {
      case PremiumButtonSize.small:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
      case PremiumButtonSize.medium:
        return const EdgeInsets.symmetric(horizontal: 20, vertical: 12);
      case PremiumButtonSize.large:
        return const EdgeInsets.symmetric(horizontal: 28, vertical: 16);
    }
  }

  TextStyle _getTextStyle() {
    switch (widget.size) {
      case PremiumButtonSize.small:
        return AppTypography.labelLarge;
      case PremiumButtonSize.medium:
        return AppTypography.titleMedium;
      case PremiumButtonSize.large:
        return AppTypography.titleLarge;
    }
  }

  double _getIconSize() {
    switch (widget.size) {
      case PremiumButtonSize.small:
        return 16;
      case PremiumButtonSize.medium:
        return 20;
      case PremiumButtonSize.large:
        return 22;
    }
  }

  Color _getTextColor(BuildContext context) {
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        return AppColors.charcoal;
      case PremiumButtonVariant.secondary:
        return context.textPrimary;
      case PremiumButtonVariant.tertiary:
        return context.accent;
      case PremiumButtonVariant.destructive:
        return Colors.white;
      case PremiumButtonVariant.ghost:
        return context.textPrimary;
    }
  }

  BoxDecoration _getDecoration(BuildContext context) {
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        return BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentGreen.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        );
      case PremiumButtonVariant.secondary:
        return BoxDecoration(
          color: context.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.border, width: 1.5),
        );
      case PremiumButtonVariant.tertiary:
        return const BoxDecoration(); // No decoration for text button
      case PremiumButtonVariant.destructive:
        return BoxDecoration(
          color: AppColors.accentRose,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentRose.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        );
      case PremiumButtonVariant.ghost:
        return BoxDecoration(
          color: context.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        );
    }
  }
}

/// Icon-only premium button
class PremiumIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final PremiumButtonVariant variant;
  final double size;
  final bool enableHaptics;

  const PremiumIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.variant = PremiumButtonVariant.secondary,
    this.size = 48,
    this.enableHaptics = true,
  });

  @override
  State<PremiumIconButton> createState() => _PremiumIconButtonState();
}

class _PremiumIconButtonState extends State<PremiumIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onPressed != null) {
          _controller.forward();
          if (widget.enableHaptics) HapticService.buttonTap();
        }
      },
      onTapUp: (_) {
        _controller.reverse();
        widget.onPressed?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: _getDecoration(context),
              child: Icon(
                widget.icon,
                size: widget.size * 0.45,
                color: _getIconColor(context),
              ),
            ),
          );
        },
      ),
    );
  }

  BoxDecoration _getDecoration(BuildContext context) {
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        return BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(widget.size * 0.28),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentGreen.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        );
      case PremiumButtonVariant.secondary:
        return BoxDecoration(
          color: context.surfaceElevated,
          borderRadius: BorderRadius.circular(widget.size * 0.28),
          border: Border.all(color: context.border),
        );
      default:
        return BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(widget.size * 0.28),
        );
    }
  }

  Color _getIconColor(BuildContext context) {
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        return AppColors.charcoal;
      default:
        return context.textPrimary;
    }
  }
}
