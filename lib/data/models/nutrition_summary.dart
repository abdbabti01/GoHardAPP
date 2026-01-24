import 'package:json_annotation/json_annotation.dart';
import 'nutrition_goal.dart';

part 'nutrition_summary.g.dart';

/// Nutrition totals for a day or period
@JsonSerializable(includeIfNull: false)
class NutritionTotals {
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;
  final double? fiber;
  final double? sodium;
  final double? water;

  NutritionTotals({
    this.calories = 0,
    this.protein = 0,
    this.carbohydrates = 0,
    this.fat = 0,
    this.fiber,
    this.sodium,
    this.water,
  });

  factory NutritionTotals.fromJson(Map<String, dynamic> json) =>
      _$NutritionTotalsFromJson(json);

  Map<String, dynamic> toJson() => _$NutritionTotalsToJson(this);
}

/// Nutrition percentages for progress tracking
@JsonSerializable(includeIfNull: false)
class NutritionPercentages {
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;

  NutritionPercentages({
    this.calories = 0,
    this.protein = 0,
    this.carbohydrates = 0,
    this.fat = 0,
  });

  factory NutritionPercentages.fromJson(Map<String, dynamic> json) =>
      _$NutritionPercentagesFromJson(json);

  Map<String, dynamic> toJson() => _$NutritionPercentagesToJson(this);
}

/// Daily progress vs nutrition goal
@JsonSerializable(includeIfNull: false)
class NutritionProgress {
  final DateTime date;
  final NutritionGoal goal;
  final NutritionTotals consumed;
  final NutritionTotals remaining;
  final NutritionPercentages percentageConsumed;

  NutritionProgress({
    required this.date,
    required this.goal,
    required this.consumed,
    required this.remaining,
    required this.percentageConsumed,
  });

  factory NutritionProgress.fromJson(Map<String, dynamic> json) =>
      _$NutritionProgressFromJson(json);

  Map<String, dynamic> toJson() => _$NutritionProgressToJson(this);

  /// Check if calories are on track (between 90% and 110% of goal)
  bool get caloriesOnTrack =>
      percentageConsumed.calories >= 90 && percentageConsumed.calories <= 110;

  /// Check if protein goal is met
  bool get proteinGoalMet => percentageConsumed.protein >= 100;
}

/// Daily summary for analytics
@JsonSerializable(includeIfNull: false)
class DailySummary {
  final DateTime date;
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;
  final double? fiber;
  final double? water;

  DailySummary({
    required this.date,
    this.calories = 0,
    this.protein = 0,
    this.carbohydrates = 0,
    this.fat = 0,
    this.fiber,
    this.water,
  });

  factory DailySummary.fromJson(Map<String, dynamic> json) =>
      _$DailySummaryFromJson(json);

  Map<String, dynamic> toJson() => _$DailySummaryToJson(this);
}

/// Macro breakdown for analytics
@JsonSerializable(includeIfNull: false)
class MacroBreakdown {
  final double totalCalories;
  final double totalProtein;
  final double totalCarbohydrates;
  final double totalFat;
  final double proteinPercentage;
  final double carbohydratesPercentage;
  final double fatPercentage;
  final double averageDailyCalories;
  final double averageDailyProtein;
  final double averageDailyCarbohydrates;
  final double averageDailyFat;

  MacroBreakdown({
    this.totalCalories = 0,
    this.totalProtein = 0,
    this.totalCarbohydrates = 0,
    this.totalFat = 0,
    this.proteinPercentage = 0,
    this.carbohydratesPercentage = 0,
    this.fatPercentage = 0,
    this.averageDailyCalories = 0,
    this.averageDailyProtein = 0,
    this.averageDailyCarbohydrates = 0,
    this.averageDailyFat = 0,
  });

  factory MacroBreakdown.fromJson(Map<String, dynamic> json) =>
      _$MacroBreakdownFromJson(json);

  Map<String, dynamic> toJson() => _$MacroBreakdownToJson(this);
}

/// Calorie trend point for charts
@JsonSerializable(includeIfNull: false)
class CalorieTrendPoint {
  final DateTime date;
  final double calories;
  final double? target;

  CalorieTrendPoint({required this.date, this.calories = 0, this.target});

  factory CalorieTrendPoint.fromJson(Map<String, dynamic> json) =>
      _$CalorieTrendPointFromJson(json);

  Map<String, dynamic> toJson() => _$CalorieTrendPointToJson(this);
}

/// Streak info for gamification
@JsonSerializable(includeIfNull: false)
class StreakInfo {
  final int currentStreak;
  final int longestStreak;
  final int totalDaysLogged;

  StreakInfo({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalDaysLogged = 0,
  });

  factory StreakInfo.fromJson(Map<String, dynamic> json) =>
      _$StreakInfoFromJson(json);

  Map<String, dynamic> toJson() => _$StreakInfoToJson(this);
}

/// Frequently logged food
@JsonSerializable(includeIfNull: false)
class FrequentFood {
  final String name;
  final int? foodTemplateId;
  final int count;
  final double totalCalories;
  final double averageCalories;

  FrequentFood({
    required this.name,
    this.foodTemplateId,
    this.count = 0,
    this.totalCalories = 0,
    this.averageCalories = 0,
  });

  factory FrequentFood.fromJson(Map<String, dynamic> json) =>
      _$FrequentFoodFromJson(json);

  Map<String, dynamic> toJson() => _$FrequentFoodToJson(this);
}
