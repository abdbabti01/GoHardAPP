import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/services/onboarding_storage.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../core/theme/typography.dart';
import '../../../../providers/onboarding_provider.dart';
import '../../../widgets/common/animations.dart';

/// Experience page - select fitness experience level
class ExperiencePage extends StatelessWidget {
  const ExperiencePage({super.key});

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
                  'What\'s your\nexperience level?',
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
                  'This helps us recommend the right workouts for you.',
                  style: AppTypography.bodyLarge.copyWith(
                    color: context.textSecondary,
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // Experience options
              Expanded(
                child: Column(
                  children:
                      ExperienceLevel.all.asMap().entries.map((entry) {
                        final index = entry.key;
                        final level = entry.value;
                        final isSelected =
                            provider.selectedExperienceLevel == level;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: FadeSlideAnimation(
                            delay: Duration(milliseconds: 300 + (index * 100)),
                            child: _ExperienceCard(
                              level: level,
                              isSelected: isSelected,
                              onTap: () {
                                HapticService.selectionClick();
                                provider.setExperienceLevel(level);
                              },
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExperienceCard extends StatelessWidget {
  final String level;
  final bool isSelected;
  final VoidCallback onTap;

  const _ExperienceCard({
    required this.level,
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.accentGreen.withValues(alpha: 0.1)
                  : context.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.accentGreen : context.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? AppColors.accentGreen.withValues(alpha: 0.2)
                        : context.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  ExperienceLevel.getIcon(level),
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ExperienceLevel.getDisplayName(level),
                    style: AppTypography.titleLarge.copyWith(
                      color:
                          isSelected
                              ? AppColors.accentGreen
                              : context.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ExperienceLevel.getDescription(level),
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accentGreen : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.accentGreen : context.border,
                  width: 2,
                ),
              ),
              child:
                  isSelected
                      ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Colors.white,
                      )
                      : null,
            ),
          ],
        ),
      ),
    );
  }
}
