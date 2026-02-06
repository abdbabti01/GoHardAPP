import 'package:json_annotation/json_annotation.dart';

part 'daily_nutrition_progress.g.dart';

/// Daily nutrition progress tracking (planned and consumed values)
/// One record per user per day - maps to NutritionProgress table in API
@JsonSerializable(includeIfNull: false)
class DailyNutritionProgress {
  final int id;
  final int userId;
  final DateTime date;
  final int? nutritionGoalId;

  // Planned values (from applied meals)
  final double plannedCalories;
  final double plannedProtein;
  final double plannedCarbohydrates;
  final double plannedFat;
  final double plannedFiber;
  final double plannedWater;

  // Consumed values (marked as eaten)
  final double consumedCalories;
  final double consumedProtein;
  final double consumedCarbohydrates;
  final double consumedFat;
  final double consumedFiber;
  final double consumedWater;

  final DateTime createdAt;
  final DateTime? updatedAt;

  DailyNutritionProgress({
    required this.id,
    required this.userId,
    required this.date,
    this.nutritionGoalId,
    this.plannedCalories = 0,
    this.plannedProtein = 0,
    this.plannedCarbohydrates = 0,
    this.plannedFat = 0,
    this.plannedFiber = 0,
    this.plannedWater = 0,
    this.consumedCalories = 0,
    this.consumedProtein = 0,
    this.consumedCarbohydrates = 0,
    this.consumedFat = 0,
    this.consumedFiber = 0,
    this.consumedWater = 0,
    required this.createdAt,
    this.updatedAt,
  });

  factory DailyNutritionProgress.fromJson(Map<String, dynamic> json) =>
      _$DailyNutritionProgressFromJson(json);

  Map<String, dynamic> toJson() => _$DailyNutritionProgressToJson(this);

  /// Create an empty progress for today
  factory DailyNutritionProgress.empty(int userId, {int? goalId}) {
    return DailyNutritionProgress(
      id: 0,
      userId: userId,
      date: DateTime.now(),
      nutritionGoalId: goalId,
      createdAt: DateTime.now(),
    );
  }

  /// Calculate remaining calories (goal - consumed)
  double remainingCalories(double goalCalories) {
    return goalCalories - consumedCalories;
  }

  /// Calculate consumed progress percentage
  double consumedPercentage(double goalCalories) {
    if (goalCalories <= 0) return 0;
    return (consumedCalories / goalCalories * 100).clamp(0, 150);
  }

  /// Calculate planned progress percentage
  double plannedPercentage(double goalCalories) {
    if (goalCalories <= 0) return 0;
    return (plannedCalories / goalCalories * 100).clamp(0, 150);
  }

  DailyNutritionProgress copyWith({
    int? id,
    int? userId,
    DateTime? date,
    int? nutritionGoalId,
    double? plannedCalories,
    double? plannedProtein,
    double? plannedCarbohydrates,
    double? plannedFat,
    double? plannedFiber,
    double? plannedWater,
    double? consumedCalories,
    double? consumedProtein,
    double? consumedCarbohydrates,
    double? consumedFat,
    double? consumedFiber,
    double? consumedWater,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DailyNutritionProgress(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      nutritionGoalId: nutritionGoalId ?? this.nutritionGoalId,
      plannedCalories: plannedCalories ?? this.plannedCalories,
      plannedProtein: plannedProtein ?? this.plannedProtein,
      plannedCarbohydrates: plannedCarbohydrates ?? this.plannedCarbohydrates,
      plannedFat: plannedFat ?? this.plannedFat,
      plannedFiber: plannedFiber ?? this.plannedFiber,
      plannedWater: plannedWater ?? this.plannedWater,
      consumedCalories: consumedCalories ?? this.consumedCalories,
      consumedProtein: consumedProtein ?? this.consumedProtein,
      consumedCarbohydrates:
          consumedCarbohydrates ?? this.consumedCarbohydrates,
      consumedFat: consumedFat ?? this.consumedFat,
      consumedFiber: consumedFiber ?? this.consumedFiber,
      consumedWater: consumedWater ?? this.consumedWater,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
