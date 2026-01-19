import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';

/// A premium progress ring widget inspired by Apple Fitness+
/// Features smooth animations, gradient strokes, and center content
class ProgressRing extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final double size;
  final double strokeWidth;
  final Color? progressColor;
  final Color? backgroundColor;
  final Gradient? progressGradient;
  final Widget? centerContent;
  final Duration animationDuration;
  final bool showPercentage;
  final bool animate;

  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 120,
    this.strokeWidth = 12,
    this.progressColor,
    this.backgroundColor,
    this.progressGradient,
    this.centerContent,
    this.animationDuration = const Duration(milliseconds: 800),
    this.showPercentage = false,
    this.animate = true,
  });

  /// Creates a workout progress ring
  factory ProgressRing.workout({
    Key? key,
    required int completed,
    required int total,
    double size = 120,
    Widget? centerContent,
  }) {
    final progress = total > 0 ? completed / total : 0.0;
    return ProgressRing(
      key: key,
      progress: progress.clamp(0.0, 1.0),
      size: size,
      strokeWidth: 10,
      progressGradient: AppColors.primaryGradient,
      centerContent: centerContent,
    );
  }

  /// Creates a streak/fire themed ring
  factory ProgressRing.streak({
    Key? key,
    required double progress,
    double size = 100,
    Widget? centerContent,
  }) {
    return ProgressRing(
      key: key,
      progress: progress.clamp(0.0, 1.0),
      size: size,
      strokeWidth: 8,
      progressGradient: AppColors.streakGradient,
      centerContent: centerContent,
    );
  }

  /// Creates a small inline progress ring
  factory ProgressRing.small({
    Key? key,
    required double progress,
    Color? color,
  }) {
    return ProgressRing(
      key: key,
      progress: progress.clamp(0.0, 1.0),
      size: 40,
      strokeWidth: 4,
      progressColor: color ?? AppColors.accentGreen,
      showPercentage: false,
    );
  }

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;
  double _previousProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _progressAnimation = Tween<double>(
      begin: 0,
      end: widget.progress,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (widget.animate) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(ProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _previousProgress = _progressAnimation.value;
      _progressAnimation = Tween<double>(
        begin: _previousProgress,
        end: widget.progress,
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, child) {
        final animatedProgress =
            widget.animate ? _progressAnimation.value : widget.progress;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background ring
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _RingPainter(
                  progress: 1.0,
                  strokeWidth: widget.strokeWidth,
                  color: widget.backgroundColor ?? context.surfaceElevated,
                ),
              ),
              // Progress ring
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _RingPainter(
                  progress: animatedProgress,
                  strokeWidth: widget.strokeWidth,
                  color: widget.progressColor,
                  gradient: widget.progressGradient,
                ),
              ),
              // Center content
              if (widget.centerContent != null)
                widget.centerContent!
              else if (widget.showPercentage)
                Text(
                  '${(animatedProgress * 100).round()}%',
                  style: AppTypography.statSmall.copyWith(
                    color: context.textPrimary,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color? color;
  final Gradient? gradient;

  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    this.color,
    this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

    if (gradient != null) {
      paint.shader = gradient!.createShader(rect);
    } else {
      paint.color = color ?? AppColors.accentGreen;
    }

    // Start from top (-90 degrees = -pi/2)
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.gradient != gradient;
  }
}

/// A multi-ring progress widget (like Apple Activity rings)
class MultiProgressRing extends StatelessWidget {
  final List<RingData> rings;
  final double size;
  final Widget? centerContent;

  const MultiProgressRing({
    super.key,
    required this.rings,
    this.size = 140,
    this.centerContent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (int i = 0; i < rings.length; i++) _buildRing(context, i),
          if (centerContent != null) centerContent!,
        ],
      ),
    );
  }

  Widget _buildRing(BuildContext context, int index) {
    final ring = rings[index];
    final ringSize = size - (index * 28); // Each ring is 28px smaller
    final strokeWidth = 10.0 - (index * 1.5); // Slightly thinner inner rings

    return ProgressRing(
      progress: ring.progress,
      size: ringSize,
      strokeWidth: strokeWidth,
      progressColor: ring.color,
      progressGradient: ring.gradient,
      backgroundColor: (ring.color ?? AppColors.accentGreen).withValues(
        alpha: 0.15,
      ),
    );
  }
}

/// Data for a single ring in MultiProgressRing
class RingData {
  final double progress;
  final Color? color;
  final Gradient? gradient;
  final String? label;

  const RingData({
    required this.progress,
    this.color,
    this.gradient,
    this.label,
  });
}

/// Weekly goal progress ring with workout counts
class WeeklyGoalRing extends StatelessWidget {
  final int completed;
  final int goal;
  final double size;

  const WeeklyGoalRing({
    super.key,
    required this.completed,
    required this.goal,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goal > 0 ? (completed / goal).clamp(0.0, 1.0) : 0.0;
    final isComplete = completed >= goal;

    return ProgressRing(
      progress: progress,
      size: size,
      strokeWidth: 8,
      progressGradient:
          isComplete ? AppColors.successGradient : AppColors.primaryGradient,
      centerContent: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$completed',
            style: AppTypography.statMedium.copyWith(
              color: context.textPrimary,
            ),
          ),
          Text(
            'of $goal',
            style: AppTypography.labelMedium.copyWith(
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
