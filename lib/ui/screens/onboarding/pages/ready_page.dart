import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/services/onboarding_storage.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../core/theme/typography.dart';
import '../../../../providers/onboarding_provider.dart';
import '../../../widgets/common/animations.dart';

/// Ready page - personalized welcome with summary
class ReadyPage extends StatelessWidget {
  const ReadyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingProvider>(
      builder: (context, provider, child) {
        final experienceLevel = provider.selectedExperienceLevel;
        final goals = provider.selectedGoals;

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Celebration icon
              FadeSlideAnimation(
                delay: const Duration(milliseconds: 200),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: AppColors.successGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentGreen.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.rocket_launch_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Title
              FadeSlideAnimation(
                delay: const Duration(milliseconds: 300),
                child: Text(
                  'You\'re All Set!',
                  style: AppTypography.displayMedium.copyWith(
                    color: context.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

              // Personalized message
              FadeSlideAnimation(
                delay: const Duration(milliseconds: 400),
                child: Text(
                  _getPersonalizedMessage(experienceLevel, goals),
                  style: AppTypography.bodyLarge.copyWith(
                    color: context.textSecondary,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 48),

              // Summary card
              FadeSlideAnimation(
                delay: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: context.border),
                  ),
                  child: Column(
                    children: [
                      // Experience level
                      if (experienceLevel != null) ...[
                        _buildSummaryRow(
                          context,
                          'Experience',
                          ExperienceLevel.getDisplayName(experienceLevel),
                          ExperienceLevel.getIcon(experienceLevel),
                        ),
                        if (goals.isNotEmpty) const SizedBox(height: 16),
                      ],

                      // Goals
                      if (goals.isNotEmpty)
                        _buildSummaryRow(
                          context,
                          'Goals',
                          goals
                                  .take(3)
                                  .map((g) => FitnessGoals.getDisplayName(g))
                                  .join(', ') +
                              (goals.length > 3 ? '...' : ''),
                          goals.map((g) => FitnessGoals.getIcon(g)).join(' '),
                        ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // What's next section
              FadeSlideAnimation(
                delay: const Duration(milliseconds: 600),
                child: Column(
                  children: [
                    Text(
                      'What\'s next?',
                      style: AppTypography.titleMedium.copyWith(
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildNextStep(context, '1', 'Create your account'),
                    const SizedBox(height: 8),
                    _buildNextStep(context, '2', 'Start your first workout'),
                    const SizedBox(height: 8),
                    _buildNextStep(context, '3', 'Track your progress'),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    String value,
    String icon,
  ) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: context.textTertiary,
                ),
              ),
              Text(
                value,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNextStep(BuildContext context, String number, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.accentGreen.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.accentGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 180,
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: context.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  String _getPersonalizedMessage(String? level, List<String> goals) {
    if (level == ExperienceLevel.beginner) {
      return 'Welcome to your fitness journey! We\'ll help you build healthy habits and track every step of your progress.';
    } else if (level == ExperienceLevel.intermediate) {
      return 'Ready to take your training to the next level! Let\'s track your workouts and crush those goals together.';
    } else if (level == ExperienceLevel.advanced) {
      return 'Time to optimize your training! We\'ll help you track every detail and push past your limits.';
    }
    return 'Your personalized fitness experience awaits. Let\'s start building your best self!';
  }
}
