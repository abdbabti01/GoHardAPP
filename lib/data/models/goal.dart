import 'package:json_annotation/json_annotation.dart';
import 'goal_progress.dart';

part 'goal.g.dart';

@JsonSerializable(includeIfNull: false)
class Goal {
  final int id;
  final int userId;
  final String goalType; // WorkoutFrequency, Weight, Volume, Exercise, BodyFat
  final double targetValue;
  final double currentValue;
  final String? unit;
  final String? timeFrame; // weekly, monthly, total
  final DateTime startDate;
  final DateTime? targetDate;
  final bool isActive;
  final bool isCompleted;
  final DateTime? completedAt;
  final DateTime createdAt;
  final List<GoalProgress>? progressHistory;

  Goal({
    required this.id,
    required this.userId,
    required this.goalType,
    required this.targetValue,
    required this.currentValue,
    this.unit,
    this.timeFrame,
    required this.startDate,
    this.targetDate,
    required this.isActive,
    required this.isCompleted,
    this.completedAt,
    required this.createdAt,
    this.progressHistory,
  });

  // Helper method to ensure datetime is in UTC
  static DateTime _toUtc(DateTime dt) {
    if (dt.isUtc) return dt;
    return dt.toUtc();
  }

  factory Goal.fromJson(Map<String, dynamic> json) {
    final goal = _$GoalFromJson(json);

    return Goal(
      id: goal.id,
      userId: goal.userId,
      goalType: goal.goalType,
      targetValue: goal.targetValue,
      currentValue: goal.currentValue,
      unit: goal.unit,
      timeFrame: goal.timeFrame,
      startDate: _toUtc(goal.startDate),
      targetDate: goal.targetDate != null ? _toUtc(goal.targetDate!) : null,
      isActive: goal.isActive,
      isCompleted: goal.isCompleted,
      completedAt: goal.completedAt != null ? _toUtc(goal.completedAt!) : null,
      createdAt: _toUtc(goal.createdAt),
      progressHistory: goal.progressHistory,
    );
  }

  Map<String, dynamic> toJson() => _$GoalToJson(this);

  /// Determine if this is a decrease goal (lower is better) or increase goal (higher is better)
  bool get isDecreaseGoal {
    final type = goalType.toLowerCase();
    return type.contains('weight') ||
        type.contains('bodyfat') ||
        type.contains('fat');
  }

  /// Get the starting value (currentValue represents starting weight/value)
  double get startValue => currentValue;

  /// Calculate total cumulative progress from all progress history entries
  /// For weight loss: sum of all pounds lost
  /// For increase goals: sum of all progress made
  double get totalProgress {
    if (progressHistory == null || progressHistory!.isEmpty) {
      return 0;
    }
    // Sum all progress values (each entry is a delta/increment)
    return progressHistory!.fold(0.0, (sum, p) => sum + p.value);
  }

  /// Calculate progress percentage correctly for both increase and decrease goals
  /// Progress entries represent incremental changes (e.g., 2 lbs lost, 3 workouts completed)
  double get progressPercentage {
    if (isDecreaseGoal) {
      // For weight loss: total progress / goal amount * 100
      // Example: Start 200, Target 150, Progress 12 = 12/50 = 24%
      final goalAmount = currentValue - targetValue; // 200 - 150 = 50
      if (goalAmount <= 0) return 0;

      return (totalProgress / goalAmount * 100).clamp(0, 100);
    } else {
      // For increase goals: total progress / target * 100
      // Example: Target 20 workouts, Progress 5 = 5/20 = 25%
      if (targetValue <= 0) return 0;
      return (totalProgress / targetValue * 100).clamp(0, 100);
    }
  }

  /// Get progress description (e.g., "Lost 12.0 / 50.0 lb" or "5.0 / 20.0 workouts")
  String getProgressDescription() {
    if (isDecreaseGoal) {
      final goalAmount = currentValue - targetValue; // Total to lose
      return 'Lost ${totalProgress.toStringAsFixed(1)} / ${goalAmount.toStringAsFixed(1)} ${unit ?? ''}';
    } else {
      return '${totalProgress.toStringAsFixed(1)} / ${targetValue.toStringAsFixed(1)} ${unit ?? ''}';
    }
  }

  /// Get suggested increment for quick actions based on goal type and unit
  List<double> get suggestedIncrements {
    if (isDecreaseGoal) {
      // For weight loss, suggest decrements
      if (unit?.toLowerCase().contains('lb') ?? false) {
        return [-0.5, -1, -2]; // Lose 0.5, 1, or 2 lbs
      } else if (unit?.toLowerCase().contains('kg') ?? false) {
        return [-0.2, -0.5, -1]; // Lose 0.2, 0.5, or 1 kg
      } else {
        return [-1, -2, -5]; // Generic decrements
      }
    } else {
      // For increase goals
      if (goalType.toLowerCase().contains('frequency') ||
          (unit?.toLowerCase().contains('workout') ?? false)) {
        return [1, 2, 3]; // Add 1, 2, or 3 workouts
      } else {
        return [1, 5, 10]; // Generic increments
      }
    }
  }

  /// Calculate progress rate (e.g., lbs/week, workouts/week)
  /// Returns null if not enough data to calculate rate
  double? getProgressRate() {
    if (progressHistory == null || progressHistory!.length < 2) {
      return null;
    }

    // Sort by date
    final sorted =
        progressHistory!.toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    // Get first and most recent progress entries
    final firstEntry = sorted.first;
    final lastEntry = sorted.last;

    // Calculate time difference in weeks
    final daysDiff =
        lastEntry.recordedAt.difference(firstEntry.recordedAt).inDays;
    if (daysDiff == 0) return null;
    final weeksDiff = daysDiff / 7.0;

    // Calculate value change
    final valueDiff = lastEntry.value - firstEntry.value;

    // Return rate per week
    return valueDiff / weeksDiff;
  }

  /// Get smart suggestion based on progress trends
  String? getProgressSuggestion() {
    final rate = getProgressRate();
    if (rate == null) {
      // Not enough data yet
      return 'Keep logging your progress to see personalized insights!';
    }

    final progress = progressPercentage;

    // Calculate expected completion based on current rate
    final daysElapsed = DateTime.now().difference(startDate).inDays;
    if (daysElapsed == 0) return null;

    if (isDecreaseGoal) {
      // Weight loss suggestions
      final remaining = currentValue - targetValue;

      if (rate < 0) {
        // Making progress (losing weight)
        final absRate = rate.abs();
        final weeklyRate = absRate;

        if (progress >= 75) {
          return '🎉 Amazing! You\'re ${progress.toStringAsFixed(0)}% there. Keep up the great work!';
        } else if (weeklyRate > 0) {
          final weeksRemaining = (remaining / weeklyRate).ceil();

          if (targetDate != null) {
            final targetWeeks =
                targetDate!.difference(DateTime.now()).inDays / 7;

            if (weeksRemaining <= targetWeeks * 1.1) {
              return '✅ Great progress! Losing ${weeklyRate.toStringAsFixed(1)} ${unit ?? ''}/week. On track to reach your goal!';
            } else {
              final neededRate = remaining / targetWeeks;
              return '💪 You\'re losing ${weeklyRate.toStringAsFixed(1)} ${unit ?? ''}/week. Try for ${neededRate.toStringAsFixed(1)} ${unit ?? ''}/week to hit your target date!';
            }
          } else {
            return '📈 Steady progress! Losing ${weeklyRate.toStringAsFixed(1)} ${unit ?? ''}/week. About $weeksRemaining weeks to go!';
          }
        }
      } else if (rate > 0) {
        // Gaining weight (not good for weight loss goal)
        return '⚠️ Weight is trending up. Review your nutrition and stay consistent with your plan!';
      } else {
        return '💡 Weight is stable. Consider adjusting your calorie intake to restart progress!';
      }
    } else {
      // Increase goal suggestions (workout frequency, volume, etc.)
      if (rate > 0) {
        // Making progress
        if (progress >= 75) {
          return '🔥 Fantastic! You\'re ${progress.toStringAsFixed(0)}% complete. Almost there!';
        } else if (rate > 0) {
          final remaining = targetValue - currentValue;
          final weeksRemaining = (remaining / rate).ceil();

          if (targetDate != null) {
            final targetWeeks =
                targetDate!.difference(DateTime.now()).inDays / 7;

            if (weeksRemaining <= targetWeeks * 1.1) {
              return '✅ Excellent pace! Adding ${rate.toStringAsFixed(1)} ${unit ?? ''}/week. Right on track!';
            } else {
              final neededRate = remaining / targetWeeks;
              return '💪 Currently ${rate.toStringAsFixed(1)} ${unit ?? ''}/week. Aim for ${neededRate.toStringAsFixed(1)} ${unit ?? ''}/week to hit your deadline!';
            }
          } else {
            return '📈 Great momentum! Adding ${rate.toStringAsFixed(1)} ${unit ?? ''}/week. Keep it up!';
          }
        }
      } else {
        return '💡 Progress has slowed. Stay consistent and you\'ll get back on track!';
      }
    }

    return null;
  }

  Goal copyWith({
    int? id,
    int? userId,
    String? goalType,
    double? targetValue,
    double? currentValue,
    String? unit,
    String? timeFrame,
    DateTime? startDate,
    DateTime? targetDate,
    bool? isActive,
    bool? isCompleted,
    DateTime? completedAt,
    DateTime? createdAt,
    List<GoalProgress>? progressHistory,
  }) {
    return Goal(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      goalType: goalType ?? this.goalType,
      targetValue: targetValue ?? this.targetValue,
      currentValue: currentValue ?? this.currentValue,
      unit: unit ?? this.unit,
      timeFrame: timeFrame ?? this.timeFrame,
      startDate: startDate ?? this.startDate,
      targetDate: targetDate ?? this.targetDate,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      progressHistory: progressHistory ?? this.progressHistory,
    );
  }
}
