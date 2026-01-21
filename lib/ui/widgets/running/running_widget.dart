import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/running_provider.dart';
import '../../../routes/route_names.dart';
import 'run_stats_row.dart';

/// Premium widget displaying running stats and quick start button
class RunningWidget extends StatefulWidget {
  const RunningWidget({super.key});

  @override
  State<RunningWidget> createState() => _RunningWidgetState();
}

class _RunningWidgetState extends State<RunningWidget> {
  @override
  void initState() {
    super.initState();
    // Load running data on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RunningProvider>().loadDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RunningProvider>(
      builder: (context, provider, child) {
        final weeklyStats = provider.weeklyStats;
        final lastRun =
            provider.recentRuns.isNotEmpty ? provider.recentRuns.first : null;
        final runCount = weeklyStats['runCount'] ?? 0;
        final totalDistance = weeklyStats['totalDistance'] ?? 0.0;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient:
                context.isDarkMode
                    ? LinearGradient(
                      colors: [
                        AppColors.darkSurface,
                        AppColors.darkSurfaceElevated,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                    : null,
            color: context.isDarkMode ? null : context.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.border, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: context.accentCoral.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.directions_run_rounded,
                            size: 18,
                            color: context.accentCoral,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Running',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    // History button
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pushNamed(context, RouteNames.runHistory);
                      },
                      child: Row(
                        children: [
                          Text(
                            'History',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: context.accent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Main content row
                Row(
                  children: [
                    // Start Run button
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.mediumImpact();

                        // If there's an active run, go to it
                        if (provider.hasActiveRun) {
                          Navigator.pushNamed(
                            context,
                            RouteNames.activeRun,
                            arguments: provider.currentRun!.id,
                          );
                          return;
                        }

                        // Otherwise start new run
                        final runId = await provider.startNewRun();
                        if (runId != null && context.mounted) {
                          Navigator.pushNamed(
                            context,
                            RouteNames.activeRun,
                            arguments: runId,
                          );
                        }
                      },
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors:
                                provider.hasActiveRun
                                    ? [
                                      context.accentCoral,
                                      AppColors.accentAmber,
                                    ]
                                    : [context.accent, context.accentMuted],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: (provider.hasActiveRun
                                      ? context.accentCoral
                                      : context.accent)
                                  .withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              provider.hasActiveRun
                                  ? Icons.play_arrow_rounded
                                  : Icons.directions_run_rounded,
                              size: 32,
                              color: AppColors.goHardBlack,
                            ),
                            Text(
                              provider.hasActiveRun ? 'Resume' : 'Start',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.goHardBlack,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Stats column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // This week stats
                          Text(
                            'This Week',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            runCount == 0
                                ? 'No runs yet'
                                : '$runCount run${runCount > 1 ? 's' : ''} - ${totalDistance.toStringAsFixed(1)} km',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),

                          if (lastRun != null) ...[
                            const SizedBox(height: 12),

                            // Last run stats
                            Text(
                              'Last Run',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            RunStatsRow(
                              distance: lastRun.formattedDistance,
                              duration: lastRun.formattedDuration,
                              pace: lastRun.formattedPace,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
