import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../providers/onboarding_provider.dart';
import 'pages/welcome_page.dart';
import 'pages/goals_page.dart';
import 'pages/experience_page.dart';
import 'pages/ready_page.dart';

/// Main onboarding screen with PageView
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    context.read<OnboardingProvider>().setCurrentPage(page);
    HapticService.selectionClick();
  }

  void _nextPage() {
    final provider = context.read<OnboardingProvider>();
    if (provider.isLastPage) {
      _completeOnboarding();
    } else if (provider.canProceed) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _previousPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _completeOnboarding() async {
    HapticService.success();
    await context.read<OnboardingProvider>().completeOnboarding();
    widget.onComplete();
  }

  Future<void> _skipOnboarding() async {
    await context.read<OnboardingProvider>().skipOnboarding();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<OnboardingProvider>(
          builder: (context, provider, child) {
            return Column(
              children: [
                // Top bar with skip button
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back button (hidden on first page)
                      AnimatedOpacity(
                        opacity: provider.currentPage > 0 ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: IconButton(
                          onPressed:
                              provider.currentPage > 0 ? _previousPage : null,
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: context.textPrimary,
                          ),
                        ),
                      ),

                      // Skip button
                      TextButton(
                        onPressed: _skipOnboarding,
                        child: Text(
                          'Skip',
                          style: AppTypography.labelLarge.copyWith(
                            color: context.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Page content
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    physics: const ClampingScrollPhysics(),
                    children: const [
                      WelcomePage(),
                      GoalsPage(),
                      ExperiencePage(),
                      ReadyPage(),
                    ],
                  ),
                ),

                // Bottom section with indicators and button
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Page indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          provider.totalPages,
                          (index) => _buildPageIndicator(
                            context,
                            index,
                            provider.currentPage,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Continue button
                      SizedBox(
                        width: double.infinity,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          child: ElevatedButton(
                            onPressed: provider.canProceed ? _nextPage : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  provider.canProceed
                                      ? AppColors.accentGreen
                                      : context.surfaceElevated,
                              foregroundColor:
                                  provider.canProceed
                                      ? AppColors.charcoal
                                      : context.textTertiary,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              provider.isLastPage ? 'Get Started' : 'Continue',
                              style: AppTypography.titleMedium.copyWith(
                                color:
                                    provider.canProceed
                                        ? AppColors.charcoal
                                        : context.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPageIndicator(BuildContext context, int index, int currentPage) {
    final isActive = index == currentPage;
    final isPast = index < currentPage;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 32 : 8,
      height: 8,
      decoration: BoxDecoration(
        color:
            isActive
                ? AppColors.accentGreen
                : isPast
                ? AppColors.accentGreen.withValues(alpha: 0.5)
                : context.border,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
