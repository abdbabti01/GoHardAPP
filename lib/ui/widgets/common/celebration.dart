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
      AppColors.accentGreen,
      AppColors.accentSky,
      AppColors.accentAmber,
      AppColors.accentCoral,
      AppColors.tierGold,
      AppColors.silver,
      AppColors.accentGreenMuted,
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

/// Workout completion celebration screen
class WorkoutCompleteCelebration extends StatelessWidget {
  final String? workoutName;
  final int duration; // in minutes
  final int exerciseCount;
  final int setCount;
  final VoidCallback onContinue;

  const WorkoutCompleteCelebration({
    super.key,
    this.workoutName,
    required this.duration,
    required this.exerciseCount,
    required this.setCount,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background
        Container(
          color: context.scaffoldBackground,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),

                  // Success animation
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 200),
                    child: SuccessCheckAnimation(
                      size: 100,
                      color: AppColors.accentGreen,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Title with premium typography
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 400),
                    child: Text(
                      'Workout Complete!',
                      style: AppTypography.displayMedium.copyWith(
                        color: context.textPrimary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Workout name
                  if (workoutName != null)
                    FadeSlideAnimation(
                      delay: const Duration(milliseconds: 500),
                      child: Text(
                        workoutName!,
                        style: TextStyle(
                          fontSize: 18,
                          color: context.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  const SizedBox(height: 48),

                  // Stats
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 600),
                    child: _buildStats(context),
                  ),

                  const Spacer(),

                  // Continue button
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 800),
                    child: _buildContinueButton(context),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),

        // Confetti
        const CelebrationOverlay(),
      ],
    );
  }

  Widget _buildStats(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStat(
            context,
            _formatDuration(duration),
            'Duration',
            Icons.timer_rounded,
          ),
          _buildDivider(context),
          _buildStat(
            context,
            '$exerciseCount',
            'Exercises',
            Icons.fitness_center_rounded,
          ),
          _buildDivider(context),
          _buildStat(context, '$setCount', 'Sets', Icons.repeat_rounded),
        ],
      ),
    );
  }

  Widget _buildStat(
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.charcoal,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 24, color: AppColors.accentGreen),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: AppTypography.statSmall.copyWith(color: context.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: context.textSecondary),
        ),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Container(width: 1, height: 60, color: context.border);
  }

  Widget _buildContinueButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.accentGreen,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentGreen.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onContinue,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Continue',
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
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
                      color: AppColors.accentGreen,
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
