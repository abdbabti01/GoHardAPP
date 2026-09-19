import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
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
        final hasNoDataYet = provider.recentRuns.isEmpty && runCount == 0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
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
                        Flexible(
                          child: Text(
                            'Running',
                            style: AppTypography.titleLarge.copyWith(
                              color: context.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // History button - full row is the tap target, not just the text.
                  Semantics(
                    button: true,
                    label: 'View run history',
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pushNamed(context, RouteNames.runHistory);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'History',
                              style: AppTypography.labelLarge.copyWith(
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
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // First-load loading state - only asserted with no data yet, so
              // a silent background refresh never hides already-loaded stats.
              if (provider.isLoading && hasNoDataYet)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              // First-load error state - distinct from "no runs yet" so an
              // outage never looks identical to a genuinely empty history.
              else if (provider.errorMessage != null && hasNoDataYet)
                _RunningErrorNotice(
                  message: provider.errorMessage!,
                  onRetry: () => provider.loadDashboardData(),
                )
              else
                // Main content row
                Row(
                  children: [
                    // Start Run button. Sized off the text scale factor
                    // (clamped) rather than a bare fixed 80x80: at a fixed
                    // size, FittedBox(scaleDown) has to compress the
                    // icon+label back down to as little as ~44% of their
                    // already-scaled size at 3x text scale (measured via
                    // the child's actual painted/transformed bounds, not
                    // just its pre-transform layout size) - visibly
                    // defeating a user's enlarged-text preference. Growing
                    // the box lets FittedBox apply little or no shrink
                    // instead. Capped at 1.75x so the button cannot grow
                    // unboundedly at extreme accessibility scales.
                    Builder(
                      builder: (context) {
                        final buttonSize =
                            80.0 *
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(1.0).clamp(1.0, 1.75);
                        return GestureDetector(
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

                            // Create draft run and navigate (don't start yet)
                            final runId = await provider.createDraftRun();
                            if (runId != null && context.mounted) {
                              Navigator.pushNamed(
                                context,
                                RouteNames.activeRun,
                                arguments: runId,
                              );
                            }
                          },
                          child: Container(
                            width: buttonSize,
                            height: buttonSize,
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
                            // FittedBox keeps this inside the button at
                            // large accessibility text scales instead of
                            // overflowing it, for whatever residual excess
                            // remains beyond buttonSize's own growth.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
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
                        );
                      },
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
                            style: AppTypography.labelLarge.copyWith(
                              color: context.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            runCount == 0
                                ? 'No runs yet'
                                : '$runCount run${runCount > 1 ? 's' : ''} - ${totalDistance.toStringAsFixed(1)} km',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),

                          if (lastRun != null) ...[
                            const SizedBox(height: 12),

                            // Last run stats
                            Text(
                              'Last Run',
                              style: AppTypography.labelLarge.copyWith(
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
        );
      },
    );
  }
}

/// Inline, retryable failure notice matching the pattern used by the other
/// Today sections - icon + text together, with a real (>=44px) tap target.
class _RunningErrorNotice extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _RunningErrorNotice({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: context.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: context.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(64, 44),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
