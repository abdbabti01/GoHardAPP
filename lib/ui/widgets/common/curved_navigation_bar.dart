import 'package:flutter/material.dart';
import '../../../core/theme/theme_colors.dart';

/// Custom bottom navigation bar with convex bump and FAB on top
/// Features upward curve in center with AI Coach button
/// Automatically adapts to light/dark theme
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
  final String fabLabel;

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
    this.height = 80,
    this.fabLabel = 'AI Coach',
  });

  @override
  Widget build(BuildContext context) {
    // Use theme-aware colors as defaults
    final bgColor = backgroundColor ?? context.navBarBackground;
    final activeColor = selectedColor ?? context.navBarSelected;
    final inactiveColor = unselectedColor ?? context.navBarUnselected;
    final fabBgColor = fabColor ?? context.navBarFabBackground;
    final borderColor = context.border;

    const double bumpHeight = 28;
    const double fabSize = 56;

    return SizedBox(
      height: height + MediaQuery.of(context).padding.bottom + bumpHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background with upward curve (convex bump)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              size: Size(
                MediaQuery.of(context).size.width,
                height + MediaQuery.of(context).padding.bottom + bumpHeight,
              ),
              painter: _ConvexBumpPainter(
                backgroundColor: bgColor,
                borderColor: borderColor,
                bumpRadius: 50,
                bumpHeight: bumpHeight,
                bottomPadding: MediaQuery.of(context).padding.bottom,
              ),
            ),
          ),
          // Navigation items (left side)
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
                // Center space for FAB label
                SizedBox(
                  width: 80,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: onFabTap,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          fabLabel,
                          style: TextStyle(
                            color: inactiveColor,
                            fontSize: 11,
                            fontWeight: FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
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
          // FAB on top of the bump
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Center(
              child: GestureDetector(
                onTap: onFabTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: fabSize,
                  height: fabSize,
                  decoration: BoxDecoration(
                    color: fabBgColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.add,
                    color: context.textOnPrimary,
                    size: 28,
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
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                color: isSelected ? activeColor : inactiveColor,
                fontSize: isSelected ? 12 : 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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

class _ConvexBumpPainter extends CustomPainter {
  final Color backgroundColor;
  final Color borderColor;
  final double bumpRadius;
  final double bumpHeight;
  final double bottomPadding;

  _ConvexBumpPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.bumpRadius,
    required this.bumpHeight,
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
    final bumpWidth = bumpRadius * 2 + 40;
    final topY = bumpHeight;

    // Start from top-left (below bump level)
    path.moveTo(0, topY + 20);

    // Left rounded corner
    path.quadraticBezierTo(0, topY, 20, topY);

    // Top edge to bump start
    path.lineTo(centerX - bumpWidth / 2, topY);

    // Bump curve (left side going up)
    path.quadraticBezierTo(
      centerX - bumpWidth / 2 + 20,
      topY,
      centerX - bumpRadius,
      8,
    );

    // Bump top arc (curves upward)
    path.arcToPoint(
      Offset(centerX + bumpRadius, 8),
      radius: Radius.circular(bumpRadius),
      clockwise: false,
    );

    // Bump curve (right side going down)
    path.quadraticBezierTo(
      centerX + bumpWidth / 2 - 20,
      topY,
      centerX + bumpWidth / 2,
      topY,
    );

    // Top edge from bump to right
    path.lineTo(size.width - 20, topY);

    // Right rounded corner
    path.quadraticBezierTo(size.width, topY, size.width, topY + 20);

    // Right edge
    path.lineTo(size.width, size.height);

    // Bottom edge
    path.lineTo(0, size.height);

    // Left edge
    path.lineTo(0, topY + 20);

    path.close();

    canvas.drawPath(path, paint);

    // Draw top border
    final borderPaint =
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;

    final borderPath = Path();
    borderPath.moveTo(0, topY + 20);
    borderPath.quadraticBezierTo(0, topY, 20, topY);
    borderPath.lineTo(centerX - bumpWidth / 2, topY);
    borderPath.quadraticBezierTo(
      centerX - bumpWidth / 2 + 20,
      topY,
      centerX - bumpRadius,
      8,
    );
    borderPath.arcToPoint(
      Offset(centerX + bumpRadius, 8),
      radius: Radius.circular(bumpRadius),
      clockwise: false,
    );
    borderPath.quadraticBezierTo(
      centerX + bumpWidth / 2 - 20,
      topY,
      centerX + bumpWidth / 2,
      topY,
    );
    borderPath.lineTo(size.width - 20, topY);
    borderPath.quadraticBezierTo(size.width, topY, size.width, topY + 20);

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
