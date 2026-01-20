import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/achievement.dart';
import '../../../providers/achievements_provider.dart';
import '../../widgets/achievements/achievement_badge.dart';
import '../../widgets/common/animations.dart';

/// Achievements screen showing all achievements and progress
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _tabs = [
    const Tab(text: 'All'),
    const Tab(text: 'Streaks'),
    const Tab(text: 'Milestones'),
    const Tab(text: 'Volume'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs,
          labelColor: context.textPrimary,
          unselectedLabelColor: context.textTertiary,
          indicatorColor: context.accent,
        ),
      ),
      body: Consumer<AchievementsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Stats header
              _buildStatsHeader(context, provider),

              // Achievements list
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAllAchievements(context, provider),
                    _buildCategoryAchievements(
                      context,
                      provider,
                      AchievementCategory.streak,
                    ),
                    _buildCategoryAchievements(
                      context,
                      provider,
                      AchievementCategory.milestone,
                    ),
                    _buildCategoryAchievements(
                      context,
                      provider,
                      AchievementCategory.volume,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatsHeader(
    BuildContext context,
    AchievementsProvider provider,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Column(
        children: [
          // Progress circle
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: provider.totalUnlocked / provider.totalAvailable,
                      strokeWidth: 8,
                      backgroundColor: context.surfaceElevated,
                      color: context.accent,
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${provider.totalUnlocked}',
                          style: AppTypography.statMedium.copyWith(
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          '/${provider.totalAvailable}',
                          style: AppTypography.bodySmall.copyWith(
                            color: context.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Tier breakdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTierStat(
                context,
                'Bronze',
                provider.tierCounts[AchievementTier.bronze] ?? 0,
                AppColors.tierBronze,
              ),
              _buildTierStat(
                context,
                'Silver',
                provider.tierCounts[AchievementTier.silver] ?? 0,
                AppColors.tierSilver,
              ),
              _buildTierStat(
                context,
                'Gold',
                provider.tierCounts[AchievementTier.gold] ?? 0,
                AppColors.tierGold,
              ),
              _buildTierStat(
                context,
                'Platinum',
                provider.tierCounts[AchievementTier.platinum] ?? 0,
                AppColors.tierPlatinum,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTierStat(
    BuildContext context,
    String name,
    int count,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              '$count',
              style: AppTypography.statTiny.copyWith(color: color),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: AppTypography.labelSmall.copyWith(color: context.textTertiary),
        ),
      ],
    );
  }

  Widget _buildAllAchievements(
    BuildContext context,
    AchievementsProvider provider,
  ) {
    final allProgress =
        provider.progress.values.toList()..sort((a, b) {
          // Sort by unlocked first, then by progress
          if (a.isUnlocked && !b.isUnlocked) return -1;
          if (!a.isUnlocked && b.isUnlocked) return 1;
          return b.progressPercentage.compareTo(a.progressPercentage);
        });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allProgress.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FadeSlideAnimation(
            delay: Duration(milliseconds: index * 50),
            child: CompactAchievementBadge(progress: allProgress[index]),
          ),
        );
      },
    );
  }

  Widget _buildCategoryAchievements(
    BuildContext context,
    AchievementsProvider provider,
    AchievementCategory category,
  ) {
    final categoryProgress = provider.getByCategory(category);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: categoryProgress.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FadeSlideAnimation(
            delay: Duration(milliseconds: index * 50),
            child: CompactAchievementBadge(progress: categoryProgress[index]),
          ),
        );
      },
    );
  }
}
