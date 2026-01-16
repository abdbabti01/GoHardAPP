import 'package:flutter/material.dart';

/// Custom bottom navigation bar with curved notch for FAB
/// Inspired by the meal type selector UI design
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
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? const Color(0xFF1C1C1E);
    final activeColor = selectedColor ?? const Color(0xFF34C759);
    final inactiveColor = unselectedColor ?? const Color(0xFF8E8E93);
    final fabBgColor = fabColor ?? const Color(0xFF2C2C2E);

    return SizedBox(
      height: height + MediaQuery.of(context).padding.bottom,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background with notch
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomPaint(
              size: Size(
                MediaQuery.of(context).size.width,
                height + MediaQuery.of(context).padding.bottom,
              ),
              painter: _CurvedNotchPainter(
                backgroundColor: bgColor,
                notchRadius: 38,
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
                // Space for FAB
                const SizedBox(width: 80),
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
          // FAB in notch
          Positioned(
            left: 0,
            right: 0,
            top: -20,
            child: Center(
              child: GestureDetector(
                onTap: onFabTap,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: fabBgColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF38383A),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 28),
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

class _CurvedNotchPainter extends CustomPainter {
  final Color backgroundColor;
  final double notchRadius;
  final double bottomPadding;

  _CurvedNotchPainter({
    required this.backgroundColor,
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
    final notchDepth = notchRadius + 8;
    final notchWidth = notchRadius * 2 + 24;

    // Start from top-left
    path.moveTo(0, 20);

    // Left rounded corner
    path.quadraticBezierTo(0, 0, 20, 0);

    // Top edge to notch start
    path.lineTo(centerX - notchWidth / 2, 0);

    // Notch curve (left side down)
    path.quadraticBezierTo(
      centerX - notchWidth / 2 + 10,
      0,
      centerX - notchRadius - 4,
      notchDepth - 10,
    );

    // Notch bottom arc
    path.arcToPoint(
      Offset(centerX + notchRadius + 4, notchDepth - 10),
      radius: Radius.circular(notchRadius + 4),
      clockwise: false,
    );

    // Notch curve (right side up)
    path.quadraticBezierTo(
      centerX + notchWidth / 2 - 10,
      0,
      centerX + notchWidth / 2,
      0,
    );

    // Top edge from notch to right
    path.lineTo(size.width - 20, 0);

    // Right rounded corner
    path.quadraticBezierTo(size.width, 0, size.width, 20);

    // Right edge
    path.lineTo(size.width, size.height);

    // Bottom edge
    path.lineTo(0, size.height);

    // Left edge
    path.lineTo(0, 20);

    path.close();

    canvas.drawPath(path, paint);

    // Draw top border
    final borderPaint =
        Paint()
          ..color = const Color(0xFF38383A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;

    final borderPath = Path();
    borderPath.moveTo(0, 20);
    borderPath.quadraticBezierTo(0, 0, 20, 0);
    borderPath.lineTo(centerX - notchWidth / 2, 0);
    borderPath.quadraticBezierTo(
      centerX - notchWidth / 2 + 10,
      0,
      centerX - notchRadius - 4,
      notchDepth - 10,
    );
    borderPath.arcToPoint(
      Offset(centerX + notchRadius + 4, notchDepth - 10),
      radius: Radius.circular(notchRadius + 4),
      clockwise: false,
    );
    borderPath.quadraticBezierTo(
      centerX + notchWidth / 2 - 10,
      0,
      centerX + notchWidth / 2,
      0,
    );
    borderPath.lineTo(size.width - 20, 0);
    borderPath.quadraticBezierTo(size.width, 0, size.width, 20);

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
