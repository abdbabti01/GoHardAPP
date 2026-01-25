import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import 'animations.dart';

/// Celebration overlay with confetti animation
class CelebrationOverlay extends StatefulWidget {
  final VoidCallback? onComplete;
  final Duration duration;
  final int particleCount;

  const CelebrationOverlay({
    super.key,
    this.onComplete,
    this.duration = const Duration(seconds: 3),
    this.particleCount = 50,
  });

  /// Show celebration overlay
  static void show(BuildContext context, {VoidCallback? onComplete}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder:
          (context) => CelebrationOverlay(
            onComplete: () {
              entry.remove();
              onComplete?.call();
            },
          ),
    );

    overlay.insert(entry);
  }

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _particles = List.generate(
      widget.particleCount,
      (index) => _Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble() * -0.5,
        size: _random.nextDouble() * 8 + 4,
        color: _getRandomColor(),
        speed: _random.nextDouble() * 0.5 + 0.3,
        rotation: _random.nextDouble() * 360,
        rotationSpeed: _random.nextDouble() * 10 - 5,
      ),
    );

    _controller.addListener(() => setState(() {}));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });
    _controller.forward();
  }

  Color _getRandomColor() {
    final colors = [
      context.accent,
      AppColors.accentSky,
      AppColors.accentAmber,
      AppColors.accentCoral,
      AppColors.tierGold,
      AppColors.silver,
      context.accentMuted,
    ];
    return colors[_random.nextInt(colors.length)];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _ConfettiPainter(
            particles: _particles,
            progress: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final Color color;
  final double speed;
  final double rotation;
  final double rotationSpeed;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.color,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final paint =
          Paint()
            ..color = particle.color.withValues(alpha: opacity)
            ..style = PaintingStyle.fill;

      final x = particle.x * size.width;
      final y = (particle.y + progress * particle.speed * 2) * size.height;
      final rotation =
          particle.rotation + progress * particle.rotationSpeed * 360;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation * 3.14159 / 180);

      // Draw different shapes
      final shapeType = (particle.x * 10).toInt() % 3;
      switch (shapeType) {
        case 0:
          // Circle
          canvas.drawCircle(Offset.zero, particle.size / 2, paint);
          break;
        case 1:
          // Rectangle
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: particle.size,
              height: particle.size * 0.6,
            ),
            paint,
          );
          break;
        case 2:
          // Triangle
          final path = Path();
          path.moveTo(0, -particle.size / 2);
          path.lineTo(particle.size / 2, particle.size / 2);
          path.lineTo(-particle.size / 2, particle.size / 2);
          path.close();
          canvas.drawPath(path, paint);
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Workout completion celebration screen - PREMIUM VERSION
/// Enhanced with better animations, haptics, and visual polish
class WorkoutCompleteCelebration extends StatefulWidget {
  final String? workoutName;
  final int duration; // in minutes
  final int exerciseCount;
  final int setCount;
  final int? totalVolume; // Optional total volume lifted
  final bool? isPersonalBest; // Did they achieve any PRs?
  final VoidCallback onContinue;

  const WorkoutCompleteCelebration({
    super.key,
    this.workoutName,
    required this.duration,
    required this.exerciseCount,
    required this.setCount,
    this.totalVolume,
    this.isPersonalBest,
    required this.onContinue,
  });

  @override
  State<WorkoutCompleteCelebration> createState() =>
      _WorkoutCompleteCelebrationState();
}

class _WorkoutCompleteCelebrationState extends State<WorkoutCompleteCelebration>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient background
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                context.scaffoldBackground,
                context.accent.withValues(alpha: 0.05),
                context.scaffoldBackground,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // Success animation with pulse
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 200),
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              gradient: AppColors.successGradient,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: context.accent.withValues(alpha: 0.4),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 56,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Title with gradient shimmer
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 400),
                    child: Column(
                      children: [
                        Text(
                          'WORKOUT',
                          style: AppTypography.labelLarge.copyWith(
                            color: context.accent,
                            letterSpacing: 4,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Complete!',
                          style: AppTypography.displayLarge.copyWith(
                            color: context.textPrimary,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Workout name
                  if (widget.workoutName != null)
                    FadeSlideAnimation(
                      delay: const Duration(milliseconds: 500),
                      child: Text(
                        widget.workoutName!,
                        style: AppTypography.titleMedium.copyWith(
                          color: context.textSecondary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),

                  // PR badge if achieved
                  if (widget.isPersonalBest == true) ...[
                    const SizedBox(height: 20),
                    FadeSlideAnimation(
                      delay: const Duration(milliseconds: 550),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.tierGold, AppColors.accentAmber],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.emoji_events_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'New Personal Record!',
                              style: AppTypography.labelLarge.copyWith(
                                color: Colors.white,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),

                  // Stats grid
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 600),
                    child: _buildStatsGrid(context),
                  ),

                  const Spacer(flex: 3),

                  // Continue button
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 800),
                    child: _buildContinueButton(context),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),

        // Confetti
        const CelebrationOverlay(particleCount: 80),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  _formatDuration(widget.duration),
                  'Duration',
                  Icons.timer_rounded,
                  AppColors.accentCoral,
                ),
              ),
              Container(width: 1, height: 70, color: context.border),
              Expanded(
                child: _buildStatItem(
                  context,
                  '${widget.exerciseCount}',
                  'Exercises',
                  Icons.fitness_center_rounded,
                  AppColors.accentSky,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: context.border, height: 1),
          ),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  '${widget.setCount}',
                  'Sets',
                  Icons.repeat_rounded,
                  context.accent,
                ),
              ),
              Container(width: 1, height: 70, color: context.border),
              Expanded(
                child: _buildStatItem(
                  context,
                  widget.totalVolume != null
                      ? '${(widget.totalVolume! / 1000).toStringAsFixed(1)}k'
                      : '-',
                  'Volume (kg)',
                  Icons.show_chart_rounded,
                  AppColors.accentAmber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String value,
    String label,
    IconData icon,
    Color accentColor,
  ) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 22, color: accentColor),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: AppTypography.statSmall.copyWith(
            color: context.textPrimary,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: context.textSecondary,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }

  Widget _buildContinueButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ScaleTapAnimation(
        onTap: widget.onContinue,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: context.primaryGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: context.accent.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'Continue',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.charcoal,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}

/// Streak celebration widget
class StreakCelebration extends StatelessWidget {
  final int streakDays;
  final VoidCallback onDismiss;

  const StreakCelebration({
    super.key,
    required this.streakDays,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: FadeSlideAnimation(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.accentAmber.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentAmber.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Fire emoji with glow
                GlowAnimation(
                  glowColor: AppColors.accentCoral,
                  child: const Text('🔥', style: TextStyle(fontSize: 64)),
                ),
                const SizedBox(height: 24),

                // Streak number with premium typography
                ShaderMask(
                  shaderCallback:
                      (bounds) => AppColors.streakGradient.createShader(bounds),
                  child: Text(
                    '$streakDays',
                    style: AppTypography.statHero.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  'Day Streak!',
                  style: AppTypography.displaySmall.copyWith(
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  'Keep up the great work!',
                  style: AppTypography.bodyLarge.copyWith(
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),

                // Dismiss button
                GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: context.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Awesome!',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.charcoal,
                      ),
                    ),
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
