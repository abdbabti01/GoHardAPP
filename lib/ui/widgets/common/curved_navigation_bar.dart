import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';

/// Premium bottom navigation bar with notched FAB
/// Features electric green FAB with glow effect
class CurvedNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onFabTap;
  final List<CurvedNavigationBarItem> items;
  final Color? backgroundColor;
  final Color? selectedColor;
  final Color? unselectedColor;
  final Color? fabColor;
  final double notchMargin;
  final double height;

  const CurvedNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.onFabTap,
    this.backgroundColor,
    this.selectedColor,
    this.unselectedColor,
    this.fabColor,
    this.notchMargin = 8.0,
    this.height = 70,
  });

  @override
  Widget build(BuildContext context) {
    // Premium theme-aware colors
    final bgColor = backgroundColor ?? context.navBarBackground;
    final activeColor = selectedColor ?? context.navBarSelected;
    final inactiveColor = unselectedColor ?? context.navBarUnselected;
    final fabBgColor = fabColor ?? AppColors.goHardGreen;
    final borderColor = context.border;

    const double notchRadius = 38;
    const double fabSize = 60;

    return SizedBox(
      height: height + MediaQuery.of(context).padding.bottom,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background with notch curve
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              size: Size(
                MediaQuery.of(context).size.width,
                height + MediaQuery.of(context).padding.bottom,
              ),
              painter: _NotchedNavBarPainter(
                backgroundColor: bgColor,
                borderColor: borderColor,
                notchRadius: notchRadius,
                bottomPadding: MediaQuery.of(context).padding.bottom,
              ),
            ),
          ),
          // Navigation items
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom,
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Left items
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children:
                        items
                            .take(items.length ~/ 2)
                            .toList()
                            .asMap()
                            .entries
                            .map((entry) {
                              final index = entry.key;
                              final item = entry.value;
                              return _buildNavItem(
                                context: context,
                                item: item,
                                index: index,
                                isSelected: currentIndex == index,
                                activeColor: activeColor,
                                inactiveColor: inactiveColor,
                              );
                            })
                            .toList(),
                  ),
                ),
                // Center space for FAB
                const SizedBox(width: 84),
                // Right items
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children:
                        items
                            .skip(items.length ~/ 2)
                            .toList()
                            .asMap()
                            .entries
                            .map((entry) {
                              final index = entry.key + items.length ~/ 2;
                              final item = entry.value;
                              return _buildNavItem(
                                context: context,
                                item: item,
                                index: index,
                                isSelected: currentIndex == index,
                                activeColor: activeColor,
                                inactiveColor: inactiveColor,
                              );
                            })
                            .toList(),
                  ),
                ),
              ],
            ),
          ),
          // Premium FAB with glow
          Positioned(
            left: 0,
            right: 0,
            top: -fabSize / 2 + 6,
            child: Center(
              child: GestureDetector(
                onTap: onFabTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: fabSize,
                  height: fabSize,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      // Glow effect
                      BoxShadow(
                        color: fabBgColor.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                      // Subtle dark shadow for depth
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: AppColors.goHardBlack,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required CurvedNavigationBarItem item,
    required int index,
    required bool isSelected,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? activeColor.withValues(alpha: 0.12)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.icon,
                color: isSelected ? activeColor : inactiveColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class CurvedNavigationBarItem {
  final IconData icon;
  final String label;

  const CurvedNavigationBarItem({required this.icon, required this.label});
}

class _NotchedNavBarPainter extends CustomPainter {
  final Color backgroundColor;
  final Color borderColor;
  final double notchRadius;
  final double bottomPadding;

  _NotchedNavBarPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.notchRadius,
    required this.bottomPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = backgroundColor
          ..style = PaintingStyle.fill;

    final path = Path();
    final centerX = size.width / 2;
    final notchWidth = notchRadius * 2 + 20;

    // Start from top-left
    path.moveTo(0, 0);

    // Top edge to notch start
    path.lineTo(centerX - notchWidth / 2, 0);

    // Notch curve (going down into the bar)
    path.quadraticBezierTo(
      centerX - notchWidth / 2 + 15,
      0,
      centerX - notchRadius,
      notchRadius - 5,
    );

    // Bottom of notch arc
    path.arcToPoint(
      Offset(centerX + notchRadius, notchRadius - 5),
      radius: Radius.circular(notchRadius + 5),
      clockwise: false,
    );

    // Notch curve (coming back up)
    path.quadraticBezierTo(
      centerX + notchWidth / 2 - 15,
      0,
      centerX + notchWidth / 2,
      0,
    );

    // Top edge from notch to right
    path.lineTo(size.width, 0);

    // Right edge
    path.lineTo(size.width, size.height);

    // Bottom edge
    path.lineTo(0, size.height);

    // Left edge
    path.lineTo(0, 0);

    path.close();

    canvas.drawPath(path, paint);

    // Draw top border
    final borderPaint =
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;

    final borderPath = Path();
    borderPath.moveTo(0, 0);
    borderPath.lineTo(centerX - notchWidth / 2, 0);
    borderPath.quadraticBezierTo(
      centerX - notchWidth / 2 + 15,
      0,
      centerX - notchRadius,
      notchRadius - 5,
    );
    borderPath.arcToPoint(
      Offset(centerX + notchRadius, notchRadius - 5),
      radius: Radius.circular(notchRadius + 5),
      clockwise: false,
    );
    borderPath.quadraticBezierTo(
      centerX + notchWidth / 2 - 15,
      0,
      centerX + notchWidth / 2,
      0,
    );
    borderPath.lineTo(size.width, 0);

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
