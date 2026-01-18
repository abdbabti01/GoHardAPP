import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../data/models/workout_stats.dart';
import '../../widgets/charts/volume_chart.dart';
import '../../widgets/analytics/calendar_heatmap.dart';
import '../../widgets/analytics/streak_counter.dart';
import '../../widgets/common/animations.dart';
import '../../widgets/common/loading_indicator.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();

    // Load analytics data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnalyticsProvider>().loadAnalytics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnalyticsProvider>();

    if (provider.isLoading) {
      return const Center(child: PremiumLoader());
    }

    if (provider.errorMessage != null) {
      return Center(
        child: FadeSlideAnimation(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.errorRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: AppColors.errorRed,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                provider.errorMessage!,
                style: TextStyle(color: context.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ScaleTapAnimation(
                onTap: () => provider.refresh(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: AppColors.goHardBlack,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.goHardBlack,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildOverview(provider);
  }

  Widget _buildOverview(AnalyticsProvider provider) {
    final stats = provider.workoutStats;
    if (stats == null) {
      return Center(
        child: FadeSlideAnimation(
          child: Text(
            'No data available',
            style: TextStyle(color: context.textSecondary),
          ),
        ),
      );
    }

    // Get sessions for heatmap and streak counter
    final sessionsProvider = context.watch<SessionsProvider>();
    final sessions = sessionsProvider.sessions;

    return RefreshIndicator(
      onRefresh: () => provider.refresh(),
      color: AppColors.goHardGreen,
      backgroundColor: context.surface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Streak Counter
            FadeSlideAnimation(child: StreakCounter(sessions: sessions)),
            const SizedBox(height: 8),

            // Calendar Heatmap
            FadeSlideAnimation(
              delay: const Duration(milliseconds: 100),
              child: CalendarHeatmap(sessions: sessions),
            ),
            const SizedBox(height: 16),

            // Volume Over Time Chart
            FutureBuilder<List<ProgressDataPoint>>(
              future: provider.getVolumeOverTime(days: 30),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  return FadeSlideAnimation(
                    delay: const Duration(milliseconds: 200),
                    child: Column(
                      children: [
                        _buildChartCard(context, snapshot.data!),
                        const SizedBox(height: 16),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            // Key Stats (4 most important)
            FadeSlideAnimation(
              delay: const Duration(milliseconds: 300),
              child: _buildKeyStatsGrid(context, stats, provider),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, List<ProgressDataPoint> data) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.goHardBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.show_chart_rounded,
                  size: 20,
                  color: AppColors.goHardBlue,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Volume Trend',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                  Text(
                    'Last 30 days',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          VolumeChart(data: data, lineColor: AppColors.goHardBlue),
        ],
      ),
    );
  }

  Widget _buildKeyStatsGrid(
    BuildContext context,
    WorkoutStats stats,
    AnalyticsProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Quick Stats',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: [
            _buildStatCard(
              context,
              'Total Workouts',
              stats.totalWorkouts,
              Icons.fitness_center_rounded,
              AppColors.goHardBlue,
            ),
            _buildStatCard(
              context,
              'Current Streak',
              stats.currentStreak,
              Icons.local_fire_department_rounded,
              AppColors.goHardOrange,
              suffix: ' days',
            ),
            _buildStatCard(
              context,
              'This Week',
              stats.workoutsThisWeek,
              Icons.calendar_today_rounded,
              AppColors.goHardCyan,
            ),
            _buildStatCard(
              context,
              'Personal Records',
              provider.personalRecords.length,
              Icons.emoji_events_rounded,
              AppColors.goHardAmber,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    int value,
    IconData icon,
    Color color, {
    String suffix = '',
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border, width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AnimatedCounter(
                value: value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                ),
              ),
              if (suffix.isNotEmpty)
                Text(
                  suffix,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
