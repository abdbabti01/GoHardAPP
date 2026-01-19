import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../core/theme/typography.dart';
import '../../../widgets/common/animations.dart';

/// Welcome page - first onboarding screen with logo and tagline
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),

          // Logo
          FadeSlideAnimation(
            delay: const Duration(milliseconds: 200),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentGreen.withValues(alpha: 0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder:
                      (context, error, stackTrace) => Icon(
                        Icons.fitness_center_rounded,
                        size: 60,
                        color: AppColors.accentGreen,
                      ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 48),

          // Title
          FadeSlideAnimation(
            delay: const Duration(milliseconds: 400),
            child: Text(
              'Welcome to GoHard',
              style: AppTypography.displayMedium.copyWith(
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 16),

          // Tagline
          FadeSlideAnimation(
            delay: const Duration(milliseconds: 500),
            child: Text(
              'Your premium fitness companion for tracking workouts, crushing goals, and building the best version of yourself.',
              style: AppTypography.bodyLarge.copyWith(
                color: context.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 48),

          // Feature highlights
          FadeSlideAnimation(
            delay: const Duration(milliseconds: 600),
            child: Column(
              children: [
                _buildFeatureRow(
                  context,
                  Icons.fitness_center_rounded,
                  'Track every workout',
                ),
                const SizedBox(height: 16),
                _buildFeatureRow(
                  context,
                  Icons.insights_rounded,
                  'Visualize your progress',
                ),
                const SizedBox(height: 16),
                _buildFeatureRow(
                  context,
                  Icons.emoji_events_rounded,
                  'Earn achievements',
                ),
              ],
            ),
          ),

          const Spacer(),

          // Swipe hint
          FadeSlideAnimation(
            delay: const Duration(milliseconds: 800),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Swipe to get started',
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.textTertiary,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: context.textTertiary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.accentGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.accentGreen),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 180,
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: context.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
