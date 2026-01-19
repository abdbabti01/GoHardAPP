import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/services/haptic_service.dart';
import 'animations.dart';

/// Premium streak display with animated fire icon
/// Inspired by Duolingo and fitness apps like Strava
class StreakDisplay extends StatefulWidget {
  final int currentStreak;
  final int longestStreak;
  final int weeklyGoal;
  final int completedThisWeek;
  final bool animate;
  final VoidCallback? onTap;

  const StreakDisplay({
    super.key,
    required this.currentStreak,
    required this.longestStreak,
    this.weeklyGoal = 4,
    this.completedThisWeek = 0,
    this.animate = true,
    this.onTap,
  });

  @override
  State<StreakDisplay> createState() => _StreakDisplayState();
}

class _StreakDisplayState extends State<StreakDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _fireController;
  late Animation<double> _flameAnimation;

  @override
  void initState() {
    super.initState();
    _fireController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _flameAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.15,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_fireController);

    if (widget.animate && widget.currentStreak > 0) {
      _fireController.repeat();
    }
  }

  @override
  void dispose() {
    _fireController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnFire = widget.currentStreak >= 3;
    final isNewRecord =
        widget.currentStreak >= widget.longestStreak &&
        widget.currentStreak > 0;

    return GestureDetector(
      onTap: () {
        if (widget.onTap != null) {
          HapticService.cardTap();
          widget.onTap!();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient:
              isOnFire
                  ? LinearGradient(
                    colors: [
                      AppColors.accentAmber.withValues(alpha: 0.12),
                      AppColors.accentCoral.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                  : null,
          color: isOnFire ? null : context.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isOnFire
                    ? AppColors.accentAmber.withValues(alpha: 0.3)
                    : context.border,
            width: isOnFire ? 1.5 : 1,
          ),
          boxShadow:
              isOnFire
                  ? [
                    BoxShadow(
                      color: AppColors.accentAmber.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                  : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
        ),
        child: Row(
          children: [
            // Fire icon with animation
            _buildFireIcon(context, isOnFire),
            const SizedBox(width: 16),

            // Streak info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Current streak number
                      SpringCounter(
                        value: widget.currentStreak,
                        style: AppTypography.statMedium.copyWith(
                          color:
                              isOnFire
                                  ? AppColors.accentAmber
                                  : context.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'day${widget.currentStreak == 1 ? '' : 's'}',
                        style: AppTypography.titleMedium.copyWith(
                          color: context.textSecondary,
                        ),
                      ),
                      if (isNewRecord) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppColors.streakGradient,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'BEST',
                            style: AppTypography.labelSmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOnFire ? 'You\'re on fire!' : 'Current streak',
                    style: AppTypography.bodySmall.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Weekly progress indicator
            _buildWeeklyProgress(context),
          ],
        ),
      ),
    );
  }

  Widget _buildFireIcon(BuildContext context, bool isOnFire) {
    return AnimatedBuilder(
      animation: _fireController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Glow effect
            if (isOnFire)
              Container(
                width: 60 * _flameAnimation.value,
                height: 60 * _flameAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accentAmber.withValues(alpha: 0.3),
                      AppColors.accentAmber.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            // Fire container
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: isOnFire ? AppColors.streakGradient : null,
                color: isOnFire ? null : context.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                boxShadow:
                    isOnFire
                        ? [
                          BoxShadow(
                            color: AppColors.accentCoral.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                        : null,
              ),
              child: Center(
                child: Transform.scale(
                  scale: isOnFire ? _flameAnimation.value : 1.0,
                  child: Text(
                    '🔥',
                    style: TextStyle(fontSize: isOnFire ? 26 : 22),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWeeklyProgress(BuildContext context) {
    final progress =
        widget.weeklyGoal > 0
            ? (widget.completedThisWeek / widget.weeklyGoal).clamp(0.0, 1.0)
            : 0.0;
    final isComplete = widget.completedThisWeek >= widget.weeklyGoal;

    return Column(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Background circle
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 4,
                  backgroundColor: context.surfaceElevated,
                  valueColor: AlwaysStoppedAnimation(context.surfaceElevated),
                ),
              ),
              // Progress arc
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 4,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(
                        isComplete
                            ? AppColors.accentGreen
                            : AppColors.accentSky,
                      ),
                      strokeCap: StrokeCap.round,
                    ),
                  );
                },
              ),
              // Center text
              Text(
                '${widget.completedThisWeek}/${widget.weeklyGoal}',
                style: AppTypography.labelMedium.copyWith(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'This week',
          style: AppTypography.labelSmall.copyWith(color: context.textTertiary),
        ),
      ],
    );
  }
}

/// Compact streak badge for display in headers
class StreakBadge extends StatelessWidget {
  final int streak;
  final bool compact;

  const StreakBadge({super.key, required this.streak, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (streak == 0) return const SizedBox.shrink();

    final isOnFire = streak >= 3;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        gradient: isOnFire ? AppColors.streakGradient : null,
        color: isOnFire ? null : context.surfaceElevated,
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: isOnFire ? null : Border.all(color: context.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🔥', style: TextStyle(fontSize: compact ? 12 : 14)),
          const SizedBox(width: 4),
          Text(
            '$streak',
            style: (compact
                    ? AppTypography.labelMedium
                    : AppTypography.labelLarge)
                .copyWith(
                  color: isOnFire ? Colors.white : context.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

/// Animated fire particles for celebration effects
class FireParticles extends StatefulWidget {
  final double width;
  final double height;
  final int particleCount;

  const FireParticles({
    super.key,
    this.width = 100,
    this.height = 150,
    this.particleCount = 20,
  });

  @override
  State<FireParticles> createState() => _FireParticlesState();
}

class _FireParticlesState extends State<FireParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_FireParticle> _particles;
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _particles = List.generate(widget.particleCount, (index) {
      return _FireParticle(
        x: _random.nextDouble(),
        startY: 0.8 + _random.nextDouble() * 0.2,
        size: _random.nextDouble() * 8 + 4,
        speed: _random.nextDouble() * 0.3 + 0.2,
        wobble: _random.nextDouble() * 0.1,
        color:
            _random.nextBool() ? AppColors.accentAmber : AppColors.accentCoral,
      );
    });

    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(
        painter: _FireParticlesPainter(
          particles: _particles,
          progress: _controller.value,
        ),
      ),
    );
  }
}

class _FireParticle {
  final double x;
  final double startY;
  final double size;
  final double speed;
  final double wobble;
  final Color color;

  _FireParticle({
    required this.x,
    required this.startY,
    required this.size,
    required this.speed,
    required this.wobble,
    required this.color,
  });
}

class _FireParticlesPainter extends CustomPainter {
  final List<_FireParticle> particles;
  final double progress;

  _FireParticlesPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final particleProgress = (progress + particle.x) % 1.0;
      final y = particle.startY - particleProgress * particle.speed * 2;

      if (y < 0) continue;

      final opacity = (1 - particleProgress).clamp(0.0, 1.0) * 0.8;
      final currentSize = particle.size * (1 - particleProgress * 0.5);

      final x =
          particle.x +
          math.sin(particleProgress * math.pi * 4) * particle.wobble;

      final paint =
          Paint()
            ..color = particle.color.withValues(alpha: opacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        currentSize,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FireParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
