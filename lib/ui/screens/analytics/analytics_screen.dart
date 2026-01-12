import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../data/models/workout_stats.dart';
import '../../widgets/charts/volume_chart.dart';
import '../../widgets/analytics/calendar_heatmap.dart';
import '../../widgets/analytics/streak_counter.dart';

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
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(provider.errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => provider.refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return _buildOverview(provider);
  }

  Widget _buildOverview(AnalyticsProvider provider) {
    final stats = provider.workoutStats;
    if (stats == null) {
      return const Center(child: Text('No data available'));
    }

    // Get sessions for heatmap and streak counter
    final sessionsProvider = context.watch<SessionsProvider>();
    final sessions = sessionsProvider.sessions;

    return RefreshIndicator(
      onRefresh: () => provider.refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Streak Counter
            StreakCounter(sessions: sessions),
            const SizedBox(height: 8),

            // Calendar Heatmap
            CalendarHeatmap(sessions: sessions),
            const SizedBox(height: 16),

            // Volume Over Time Chart
            FutureBuilder<List<ProgressDataPoint>>(
              future: provider.getVolumeOverTime(days: 30),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  return Column(
                    children: [
                      VolumeChart(data: snapshot.data!, lineColor: Colors.blue),
                      const SizedBox(height: 16),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            // Key Stats (4 most important)
            _buildKeyStatsGrid(stats, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyStatsGrid(WorkoutStats stats, AnalyticsProvider provider) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _buildStatCard(
          'Total Workouts',
          stats.totalWorkouts.toString(),
          Icons.fitness_center,
          Colors.blue,
        ),
        _buildStatCard(
          'Current Streak',
          '${stats.currentStreak} days',
          Icons.local_fire_department,
          Colors.orange,
        ),
        _buildStatCard(
          'This Week',
          stats.workoutsThisWeek.toString(),
          Icons.calendar_today,
          Colors.teal,
        ),
        _buildStatCard(
          'Personal Records',
          provider.personalRecords.length.toString(),
          Icons.emoji_events,
          Colors.amber,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
