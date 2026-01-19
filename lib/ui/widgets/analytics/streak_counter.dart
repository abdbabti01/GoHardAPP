import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/session.dart';
import '../common/animations.dart';

/// Premium streak counter widget with animations
class StreakCounter extends StatelessWidget {
  final List<Session> sessions;
  final int weeklyGoal;

  const StreakCounter({super.key, required this.sessions, this.weeklyGoal = 3});

  @override
  Widget build(BuildContext context) {
    final streakData = _calculateStreaks();
    final thisWeekCount = _getThisWeekCount();
    final currentStreak = streakData['current']!;
    final longestStreak = streakData['longest']!;
    final isOnFire = currentStreak >= 3;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isOnFire
                  ? AppColors.accentAmber.withValues(alpha: 0.3)
                  : context.border,
          width: isOnFire ? 1.5 : 0.5,
        ),
        boxShadow:
            isOnFire
                ? [
                  BoxShadow(
                    color: AppColors.accentAmber.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
                : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.streakGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentAmber.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Streaks & Goals',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Keep the momentum going',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Streak stats row
            Row(
              children: [
                Expanded(
                  child: _buildStreakStat(
                    context,
                    value: currentStreak,
                    label: 'Current\nStreak',
                    icon: Icons.whatshot_rounded,
                    color:
                        currentStreak > 0
                            ? AppColors.accentCoral
                            : context.textTertiary,
                    isMain: true,
                  ),
                ),
                Container(width: 1, height: 80, color: context.border),
                Expanded(
                  child: _buildStreakStat(
                    context,
                    value: longestStreak,
                    label: 'Longest\nStreak',
                    icon: Icons.emoji_events_rounded,
                    color: AppColors.accentAmber,
                    isMain: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Weekly goal
            _buildWeeklyGoal(context, thisWeekCount),
          ],
        ),
      ),
    );
  }

  Widget _buildStreakStat(
    BuildContext context, {
    required int value,
    required String label,
    required IconData icon,
    required Color color,
    required bool isMain,
  }) {
    return Column(
      children: [
        // Icon with glow for active streak
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            boxShadow:
                isMain && value > 0
                    ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ]
                    : null,
          ),
          child: Icon(icon, size: 26, color: color),
        ),
        const SizedBox(height: 12),
        // Animated counter with premium typography
        AnimatedCounter(
          value: value,
          style: AppTypography.statMedium.copyWith(
            color: value > 0 ? color : context.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: context.textSecondary,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          'day${value != 1 ? 's' : ''}',
          style: TextStyle(fontSize: 11, color: context.textTertiary),
        ),
      ],
    );
  }

  Widget _buildWeeklyGoal(BuildContext context, int thisWeekCount) {
    final progress = thisWeekCount / weeklyGoal;
    final progressClamped = progress.clamp(0.0, 1.0);
    final isGoalMet = thisWeekCount >= weeklyGoal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              isGoalMet
                  ? [
                    AppColors.accentGreen.withValues(alpha: 0.10),
                    AppColors.accentGreenMuted.withValues(alpha: 0.05),
                  ]
                  : [
                    AppColors.accentSky.withValues(alpha: 0.08),
                    AppColors.accentSky.withValues(alpha: 0.03),
                  ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              isGoalMet
                  ? AppColors.accentGreen.withValues(alpha: 0.3)
                  : AppColors.accentSky.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.flag_rounded,
                    size: 18,
                    color:
                        isGoalMet ? AppColors.accentGreen : AppColors.accentSky,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Weekly Goal',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color:
                          isGoalMet
                              ? AppColors.accentGreen
                              : AppColors.accentSky,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      isGoalMet
                          ? AppColors.accentGreen.withValues(alpha: 0.15)
                          : AppColors.accentSky.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$thisWeekCount / $weeklyGoal',
                  style: AppTypography.statTiny.copyWith(
                    color:
                        isGoalMet ? AppColors.accentGreen : AppColors.accentSky,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress bar
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: context.surfaceElevated,
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progressClamped),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return FractionallySizedBox(
                    widthFactor: value,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient:
                            isGoalMet
                                ? AppColors.successGradient
                                : LinearGradient(
                                  colors: [
                                    AppColors.accentSky,
                                    AppColors.accentSky.withValues(alpha: 0.7),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: (isGoalMet
                                    ? AppColors.accentGreen
                                    : AppColors.accentSky)
                                .withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Status message
          if (isGoalMet)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: AppColors.successGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Goal achieved! Keep crushing it!',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.accentGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else if (thisWeekCount > 0)
            Text(
              '${weeklyGoal - thisWeekCount} more workout${weeklyGoal - thisWeekCount != 1 ? 's' : ''} to reach your goal',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.accentSky,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            Text(
              'Start your first workout this week!',
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
        ],
      ),
    );
  }

  Map<String, int> _calculateStreaks() {
    if (sessions.isEmpty) {
      return {'current': 0, 'longest': 0};
    }

    final completedSessions =
        sessions.where((s) => s.status == 'completed').toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    if (completedSessions.isEmpty) {
      return {'current': 0, 'longest': 0};
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final workoutDates = <DateTime>{};
    for (final session in completedSessions) {
      workoutDates.add(
        DateTime(session.date.year, session.date.month, session.date.day),
      );
    }

    final sortedDates = workoutDates.toList()..sort((a, b) => b.compareTo(a));

    int currentStreak = 0;
    DateTime checkDate = today;

    for (final date in sortedDates) {
      if (date == checkDate) {
        currentStreak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (date.isBefore(checkDate)) {
        break;
      }
    }

    int longestStreak = 0;
    int tempStreak = 1;

    for (int i = 0; i < sortedDates.length - 1; i++) {
      final diff = sortedDates[i].difference(sortedDates[i + 1]).inDays;
      if (diff == 1) {
        tempStreak++;
        if (tempStreak > longestStreak) {
          longestStreak = tempStreak;
        }
      } else {
        tempStreak = 1;
      }
    }

    if (tempStreak > longestStreak) {
      longestStreak = tempStreak;
    }
    if (currentStreak > longestStreak) {
      longestStreak = currentStreak;
    }

    return {'current': currentStreak, 'longest': longestStreak};
  }

  int _getThisWeekCount() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    return sessions
        .where(
          (s) =>
              s.status == 'completed' &&
              s.date.isAfter(weekStart.subtract(const Duration(days: 1))) &&
              s.date.isBefore(today.add(const Duration(days: 1))),
        )
        .length;
  }
}
