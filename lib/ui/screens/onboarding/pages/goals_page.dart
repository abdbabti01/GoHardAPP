import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/services/onboarding_storage.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../core/theme/typography.dart';
import '../../../../providers/onboarding_provider.dart';
import '../../../widgets/common/animations.dart';

/// Goals page - select fitness goals
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingProvider>(
      builder: (context, provider, child) {
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // Title
              FadeSlideAnimation(
                delay: const Duration(milliseconds: 100),
                child: Text(
                  'What are your\nfitness goals?',
                  style: AppTypography.displayMedium.copyWith(
                    color: context.textPrimary,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              FadeSlideAnimation(
                delay: const Duration(milliseconds: 200),
                child: Text(
                  'Select all that apply. We\'ll personalize your experience.',
                  style: AppTypography.bodyLarge.copyWith(
                    color: context.textSecondary,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Goals grid
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.2,
                  children:
                      FitnessGoals.all.asMap().entries.map((entry) {
                        final index = entry.key;
                        final goal = entry.value;
                        final isSelected = provider.selectedGoals.contains(
                          goal,
                        );

                        return FadeSlideAnimation(
                          delay: Duration(milliseconds: 300 + (index * 50)),
                          child: _GoalCard(
                            goal: goal,
                            isSelected: isSelected,
                            onTap: () {
                              HapticService.selectionClick();
                              provider.toggleGoal(goal);
                            },
                          ),
                        );
                      }).toList(),
                ),
              ),

              // Selection count
              FadeSlideAnimation(
                delay: const Duration(milliseconds: 600),
                child: Center(
                  child: Text(
                    '${provider.selectedGoals.length} selected',
                    style: AppTypography.bodyMedium.copyWith(
                      color:
                          provider.selectedGoals.isNotEmpty
                              ? context.accent
                              : context.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _GoalCard extends StatelessWidget {
  final String goal;
  final bool isSelected;
  final VoidCallback onTap;

  const _GoalCard({
    required this.goal,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color:
              isSelected
                  ? context.accent.withValues(alpha: 0.1)
                  : context.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? context.accent : context.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Text(
                FitnessGoals.getIcon(goal),
                style: const TextStyle(fontSize: 32),
              ),

              const SizedBox(height: 12),

              // Name
              Text(
                FitnessGoals.getDisplayName(goal),
                style: AppTypography.titleMedium.copyWith(
                  color: isSelected ? context.accent : context.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),

              // Checkmark
              if (isSelected) ...[
                const SizedBox(height: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: context.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
