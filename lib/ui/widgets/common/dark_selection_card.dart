import 'package:flutter/material.dart';

/// Dark selection card widget inspired by meal type selector UI
/// Features icon, label, and optional checkbox for selection
class DarkSelectionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool showCheckbox;
  final VoidCallback? onTap;
  final Color? iconBackgroundColor;
  final Color? iconColor;

  const DarkSelectionCard({
    super.key,
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.showCheckbox = true,
    this.onTap,
    this.iconBackgroundColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF48484A) : const Color(0xFF38383A),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBackgroundColor ?? const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor ?? Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            // Label
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Checkbox
            if (showCheckbox)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFF34C759) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color:
                        isSelected
                            ? const Color(0xFF34C759)
                            : const Color(0xFF48484A),
                    width: 2,
                  ),
                ),
                child:
                    isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// Dark card container for grouping content
/// Matches the "Meal Type" card container style
class DarkCardContainer extends StatelessWidget {
  final String? title;
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  const DarkCardContainer({
    super.key,
    this.title,
    required this.child,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF38383A), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
          ],
          child,
        ],
      ),
    );
  }
}

/// Dark list tile similar to the meal type items
/// For use in lists and menus
class DarkListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconBackgroundColor;
  final Color? iconColor;
  final bool showChevron;

  const DarkListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconBackgroundColor,
    this.iconColor,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF38383A), width: 1),
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBackgroundColor ?? const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor ?? Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Trailing widget or chevron
            if (trailing != null)
              trailing!
            else if (showChevron)
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF8E8E93),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

/// Dark action button like the "NEXT" button in the image
class DarkActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isEnabled;
  final bool isLoading;

  const DarkActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isEnabled = true,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled && !isLoading ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: isEnabled ? const Color(0xFF48484A) : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(24),
        ),
        child:
            isLoading
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                : Text(
                  label,
                  style: TextStyle(
                    color: isEnabled ? Colors.white : const Color(0xFF8E8E93),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
      ),
    );
  }
}

/// Dark page scaffold with back button header
class DarkPageScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? bottomWidget;
  final VoidCallback? onBackPressed;

  const DarkPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.bottomWidget,
    this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onBackPressed ?? () => Navigator.pop(context),
                    child: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(child: body),
            // Bottom widget
            if (bottomWidget != null) bottomWidget!,
          ],
        ),
      ),
    );
  }
}
