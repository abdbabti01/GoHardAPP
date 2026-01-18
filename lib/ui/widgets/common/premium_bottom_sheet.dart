import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';

/// Premium bottom sheet with glassmorphism effect
class PremiumBottomSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final bool showHandle;
  final bool useGlass;
  final EdgeInsets? padding;

  const PremiumBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.showHandle = true,
    this.useGlass = true,
    this.padding,
  });

  /// Show the premium bottom sheet
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    bool showHandle = true,
    bool useGlass = true,
    bool isDismissible = true,
    bool enableDrag = true,
    EdgeInsets? padding,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder:
          (context) => PremiumBottomSheet(
            title: title,
            showHandle: showHandle,
            useGlass: useGlass,
            padding: padding,
            child: child,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color:
            useGlass ? context.surface.withValues(alpha: 0.9) : context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: context.isDarkMode ? AppColors.glassBorder : context.border,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHandle) _buildHandle(context),
            if (title != null) _buildTitle(context),
            Flexible(
              child: Padding(
                padding: padding ?? const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );

    if (useGlass && context.isDarkMode) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildHandle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: context.textTertiary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Text(
        title!,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: context.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

/// Premium action item for bottom sheets
class BottomSheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final bool isDestructive;
  final bool showArrow;

  const BottomSheetAction({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.iconColor,
    this.isDestructive = false,
    this.showArrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isDestructive ? AppColors.errorRed : iconColor ?? context.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),

              // Label and subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            isDestructive
                                ? AppColors.errorRed
                                : context.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Arrow
              if (showArrow)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: context.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Divider for bottom sheet actions
class BottomSheetDivider extends StatelessWidget {
  const BottomSheetDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(color: context.border, height: 1),
    );
  }
}

/// Confirmation bottom sheet
class ConfirmationBottomSheet extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  final bool isDestructive;
  final IconData? icon;

  const ConfirmationBottomSheet({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    required this.onConfirm,
    this.onCancel,
    this.isDestructive = false,
    this.icon,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
    IconData? icon,
  }) {
    return PremiumBottomSheet.show<bool>(
      context: context,
      child: ConfirmationBottomSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
        icon: icon,
        onConfirm: () => Navigator.of(context).pop(true),
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
        if (icon != null) ...[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: (isDestructive ? AppColors.errorRed : context.accent)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32,
              color: isDestructive ? AppColors.errorRed : context.accent,
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Title
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),

        // Message
        Text(
          message,
          style: TextStyle(
            fontSize: 15,
            color: context.textSecondary,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // Buttons
        Row(
          children: [
            // Cancel button
            Expanded(
              child: _buildButton(
                context,
                label: cancelLabel,
                onTap: onCancel ?? () => Navigator.of(context).pop(false),
                isPrimary: false,
              ),
            ),
            const SizedBox(width: 12),
            // Confirm button
            Expanded(
              child: _buildButton(
                context,
                label: confirmLabel,
                onTap: onConfirm,
                isPrimary: true,
                isDestructive: isDestructive,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
    bool isDestructive = false,
  }) {
    if (isPrimary) {
      return Container(
        decoration: BoxDecoration(
          gradient:
              isDestructive
                  ? LinearGradient(
                    colors: [
                      AppColors.errorRed,
                      AppColors.errorRed.withValues(alpha: 0.8),
                    ],
                  )
                  : AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (isDestructive
                      ? AppColors.errorRed
                      : AppColors.goHardGreen)
                  .withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDestructive ? Colors.white : AppColors.goHardBlack,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
