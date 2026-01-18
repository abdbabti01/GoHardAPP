import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/session.dart';

/// Premium widget displaying weekly/monthly progress with visual impact
class WeeklyProgressCard extends StatefulWidget {
  final List<Session> thisWeekSessions;
  final List<Session> thisMonthSessions;

  const WeeklyProgressCard({
    super.key,
    required this.thisWeekSessions,
    required this.thisMonthSessions,
  });

  @override
  State<WeeklyProgressCard> createState() => _WeeklyProgressCardState();
}

class _WeeklyProgressCardState extends State<WeeklyProgressCard> {
  bool _isMonthlyView = false;

  @override
  Widget build(BuildContext context) {
    final sessions =
        _isMonthlyView ? widget.thisMonthSessions : widget.thisWeekSessions;

    final completed = sessions.where((s) => s.status == 'completed').length;
    final total = sessions.length;
    final percentage = total > 0 ? (completed / total * 100).round() : 0;

    // Calculate total duration
    int totalMinutes = 0;
    for (final session in sessions) {
      if (session.status == 'completed' && session.duration != null) {
        totalMinutes += session.duration!;
      }
    }

    final isOnFire = completed >= (_isMonthlyView ? 12 : 3);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: context.isDarkMode
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
        border: Border.all(
          color: isOnFire
              ? AppColors.goHardGreen.withValues(alpha: 0.3)
              : context.border,
          width: isOnFire ? 1.5 : 0.5,
        ),
        boxShadow: isOnFire
            ? [
                BoxShadow(
                  color: AppColors.goHardGreen.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Gradient icon container
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.goHardGreen.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isMonthlyView
                        ? Icons.calendar_month_rounded
                        : Icons.calendar_today_rounded,
                    size: 20,
                    color: AppColors.goHardBlack,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isMonthlyView ? 'This Month' : 'This Week',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Your progress overview',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle button
                _buildToggle(context),
              ],
            ),

            const SizedBox(height: 24),

            // Big stats row
            Row(
              children: [
                // Main stat - workouts completed
                Expanded(
                  flex: 2,
                  child: _buildMainStat(
                    context,
                    completed.toString(),
                    'of $total workouts',
                    percentage,
                  ),
                ),
                const SizedBox(width: 16),
                // Secondary stats
                Expanded(
                  child: Column(
                    children: [
                      _buildMiniStat(
                        context,
                        Icons.timer_rounded,
                        _formatDuration(totalMinutes),
                        'Total time',
                      ),
                      const SizedBox(height: 12),
                      _buildMiniStat(
                        context,
                        Icons.local_fire_department_rounded,
                        '$percentage%',
                        'Complete',
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Progress bar
            _buildProgressBar(context, completed, total, percentage),

            // Achievement badge
            if (percentage >= 80) ...[
              const SizedBox(height: 16),
              _buildAchievementBadge(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(context, 'W', !_isMonthlyView, () {
            setState(() => _isMonthlyView = false);
          }),
          _buildToggleButton(context, 'M', _isMonthlyView, () {
            setState(() => _isMonthlyView = true);
          }),
        ],
      ),
    );
  }

  Widget _buildToggleButton(
    BuildContext context,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.goHardBlack : context.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMainStat(
    BuildContext context,
    String value,
    String subtitle,
    int percentage,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
                height: 1,
                letterSpacing: -2,
              ),
            ),
            if (percentage >= 80)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  '🔥',
                  style: TextStyle(fontSize: 28),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: context.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
    BuildContext context,
    int completed,
    int total,
    int percentage,
  ) {
    final progress = total > 0 ? completed / total : 0.0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
            Text(
              '$percentage%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: context.surfaceElevated,
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: _getProgressGradient(percentage),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: _getProgressColor(percentage)
                              .withValues(alpha: 0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.goHardGreen.withValues(alpha: 0.15),
            AppColors.goHardCyan.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.goHardGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              size: 16,
              color: AppColors.goHardBlack,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Crushing it! Keep the momentum going!',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.goHardGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  Color _getProgressColor(int percentage) {
    if (percentage >= 80) return AppColors.goHardGreen;
    if (percentage >= 50) return AppColors.goHardOrange;
    return AppColors.goHardBlue;
  }

  LinearGradient _getProgressGradient(int percentage) {
    if (percentage >= 80) return AppColors.successGradient;
    if (percentage >= 50) return AppColors.activeGradient;
    return AppColors.secondaryGradient;
  }
}
