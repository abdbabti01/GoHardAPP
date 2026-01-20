import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/theme_colors.dart';

/// Premium bottom navigation bar with notched FAB
/// Features smooth animations, sliding indicator, and haptic feedback
class CurvedNavigationBar extends StatefulWidget {
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
  State<CurvedNavigationBar> createState() => _CurvedNavigationBarState();
}

class _CurvedNavigationBarState extends State<CurvedNavigationBar>
    with TickerProviderStateMixin {
  late AnimationController _fabController;
  late AnimationController _indicatorController;
  late Animation<double> _fabScaleAnimation;
  late Animation<double> _indicatorAnimation;

  @override
  void initState() {
    super.initState();

    // FAB press animation
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _fabScaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.easeInOut),
    );

    // Indicator slide animation
    _indicatorController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _indicatorAnimation = Tween<double>(
      begin: widget.currentIndex.toDouble(),
      end: widget.currentIndex.toDouble(),
    ).animate(CurvedAnimation(
      parent: _indicatorController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(CurvedNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _animateIndicator(oldWidget.currentIndex, widget.currentIndex);
    }
  }

  void _animateIndicator(int from, int to) {
    _indicatorAnimation = Tween<double>(
      begin: from.toDouble(),
      end: to.toDouble(),
    ).animate(CurvedAnimation(
      parent: _indicatorController,
      curve: Curves.easeOutCubic,
    ));
    _indicatorController.forward(from: 0);
  }

  @override
  void dispose() {
    _fabController.dispose();
    _indicatorController.dispose();
    super.dispose();
  }

  void _onFabTapDown(TapDownDetails details) {
    _fabController.forward();
    HapticFeedback.lightImpact();
  }

  void _onFabTapUp(TapUpDetails details) {
    _fabController.reverse();
    widget.onFabTap?.call();
  }

  void _onFabTapCancel() {
    _fabController.reverse();
  }

  void _onItemTap(int index) {
    if (index != widget.currentIndex) {
      HapticFeedback.selectionClick();
      widget.onTap(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? context.navBarBackground;
    final activeColor = widget.selectedColor ?? context.navBarSelected;
    final inactiveColor = widget.unselectedColor ?? context.navBarUnselected;
    final fabBgColor = widget.fabColor ?? context.accent;
    final borderColor = context.border;

    const double notchRadius = 38;
    const double fabSize = 60;

    return SizedBox(
      height: widget.height + MediaQuery.of(context).padding.bottom,
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
                widget.height + MediaQuery.of(context).padding.bottom,
              ),
              painter: _NotchedNavBarPainter(
                backgroundColor: bgColor,
                borderColor: borderColor,
                notchRadius: notchRadius,
                bottomPadding: MediaQuery.of(context).padding.bottom,
              ),
            ),
          ),

          // Sliding indicator
          AnimatedBuilder(
            animation: _indicatorAnimation,
            builder: (context, child) {
              return Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).padding.bottom,
                height: widget.height,
                child: _buildSlidingIndicator(
                  context,
                  _indicatorAnimation.value,
                  activeColor,
                ),
              );
            },
          ),

          // Navigation items
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom,
            height: widget.height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Left items
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: widget.items
                        .take(widget.items.length ~/ 2)
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return _NavItem(
                        item: item,
                        index: index,
                        isSelected: widget.currentIndex == index,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        onTap: () => _onItemTap(index),
                      );
                    }).toList(),
                  ),
                ),
                // Center space for FAB
                const SizedBox(width: 84),
                // Right items
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: widget.items
                        .skip(widget.items.length ~/ 2)
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                      final index = entry.key + widget.items.length ~/ 2;
                      final item = entry.value;
                      return _NavItem(
                        item: item,
                        index: index,
                        isSelected: widget.currentIndex == index,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        onTap: () => _onItemTap(index),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Premium FAB with glow and press animation
          Positioned(
            left: 0,
            right: 0,
            top: -fabSize / 2 + 6,
            child: Center(
              child: GestureDetector(
                onTapDown: _onFabTapDown,
                onTapUp: _onFabTapUp,
                onTapCancel: _onFabTapCancel,
                behavior: HitTestBehavior.opaque,
                child: AnimatedBuilder(
                  animation: _fabScaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _fabScaleAnimation.value,
                      child: Container(
                        width: fabSize,
                        height: fabSize,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [context.accentDark, context.accent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
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
                        child: Icon(
                          Icons.add_rounded,
                          color: context.isDarkMode ? Colors.white : Colors.black,
                          size: 32,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlidingIndicator(
    BuildContext context,
    double position,
    Color activeColor,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final leftSideWidth = (screenWidth - 84) / 2;
    final itemWidth = leftSideWidth / 2;

    double indicatorLeft;
    if (position < 2) {
      // Left side items (0, 1)
      indicatorLeft = itemWidth * position + itemWidth / 2 - 20;
    } else {
      // Right side items (2, 3)
      final rightPosition = position - 2;
      indicatorLeft = leftSideWidth + 84 + itemWidth * rightPosition + itemWidth / 2 - 20;
    }

    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          left: indicatorLeft,
          top: 8,
          child: Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: activeColor,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Individual navigation item with smooth animations
class _NavItem extends StatefulWidget {
  final CurvedNavigationBarItem item;
  final int index;
  final bool isSelected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.item,
    required this.index,
    required this.isSelected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _iconSizeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _iconSizeAnimation = Tween<double>(begin: 24.0, end: 22.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: SizedBox(
              width: 72,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon with animated background
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.isSelected ? 16 : 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? widget.activeColor.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: child,
                        );
                      },
                      child: Icon(
                        widget.item.icon,
                        key: ValueKey(widget.isSelected),
                        color: widget.isSelected
                            ? widget.activeColor
                            : widget.inactiveColor,
                        size: _iconSizeAnimation.value,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Label with smooth color transition
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: widget.isSelected
                          ? widget.activeColor
                          : widget.inactiveColor,
                      fontSize: widget.isSelected ? 11 : 10,
                      fontWeight:
                          widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                    child: Text(
                      widget.item.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
    final paint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    final path = Path();
    final centerX = size.width / 2;
    final notchWidth = notchRadius * 2 + 24;

    // Smoother notch curve
    const cornerRadius = 20.0;

    // Start from top-left with rounded corner
    path.moveTo(0, cornerRadius);
    path.quadraticBezierTo(0, 0, cornerRadius, 0);

    // Top edge to notch start
    path.lineTo(centerX - notchWidth / 2, 0);

    // Smoother notch curve (going down into the bar)
    path.cubicTo(
      centerX - notchWidth / 2 + 20, 0,
      centerX - notchRadius - 8, notchRadius - 2,
      centerX - notchRadius, notchRadius + 2,
    );

    // Bottom of notch arc - smoother
    path.arcToPoint(
      Offset(centerX + notchRadius, notchRadius + 2),
      radius: Radius.circular(notchRadius + 4),
      clockwise: false,
    );

    // Notch curve (coming back up) - smoother
    path.cubicTo(
      centerX + notchRadius + 8, notchRadius - 2,
      centerX + notchWidth / 2 - 20, 0,
      centerX + notchWidth / 2, 0,
    );

    // Top edge from notch to right
    path.lineTo(size.width - cornerRadius, 0);

    // Top-right rounded corner
    path.quadraticBezierTo(size.width, 0, size.width, cornerRadius);

    // Right edge
    path.lineTo(size.width, size.height);

    // Bottom edge
    path.lineTo(0, size.height);

    // Left edge
    path.lineTo(0, cornerRadius);

    path.close();

    // Draw shadow first
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.1), 8, false);

    // Then fill
    canvas.drawPath(path, paint);

    // Draw top border with smoother line
    final borderPaint = Paint()
      ..color = borderColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeCap = StrokeCap.round;

    final borderPath = Path();
    borderPath.moveTo(cornerRadius, 0);
    borderPath.lineTo(centerX - notchWidth / 2, 0);
    borderPath.cubicTo(
      centerX - notchWidth / 2 + 20, 0,
      centerX - notchRadius - 8, notchRadius - 2,
      centerX - notchRadius, notchRadius + 2,
    );
    borderPath.arcToPoint(
      Offset(centerX + notchRadius, notchRadius + 2),
      radius: Radius.circular(notchRadius + 4),
      clockwise: false,
    );
    borderPath.cubicTo(
      centerX + notchRadius + 8, notchRadius - 2,
      centerX + notchWidth / 2 - 20, 0,
      centerX + notchWidth / 2, 0,
    );
    borderPath.lineTo(size.width - cornerRadius, 0);

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _NotchedNavBarPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor;
  }
}
