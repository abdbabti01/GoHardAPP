import 'package:json_annotation/json_annotation.dart';

part 'nutrition_goal.g.dart';

@JsonSerializable(includeIfNull: false)
class NutritionGoal {
  final int id;
  final int userId;
  final String? name;
  final double dailyCalories;
  final double dailyProtein;
  final double dailyCarbohydrates;
  final double dailyFat;
  final double? dailyFiber;
  final double? dailySodium;
  final double? dailySugar;
  final double? dailyWater;
  final double? proteinPercentage;
  final double? carbohydratesPercentage;
  final double? fatPercentage;
  final bool isActive;

  /// The calendar date this target starts applying from (UTC midnight,
  /// matching the meal-log date convention). Historical resolution always
  /// picks the row whose [effectiveDate] is the latest one `<=` the queried
  /// date and not yet [deletedAt] as of that date - never "today's active
  /// goal" applied retroactively. See `NutritionRepository.getGoalForDate`.
  final DateTime effectiveDate;

  /// Soft-delete marker. A deleted goal still answers historical queries for
  /// dates before this timestamp - only dates on/after it stop seeing it.
  final DateTime? deletedAt;

  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Explanation of how the nutrition targets were calculated
  final String? explanation;

  /// BMR used in calculation
  final double? bmr;

  /// TDEE used in calculation
  final double? tdee;

  /// Daily calorie adjustment (deficit or surplus)
  final double? calorieAdjustment;

  NutritionGoal({
    required this.id,
    required this.userId,
    this.name,
    this.dailyCalories = 2000,
    this.dailyProtein = 150,
    this.dailyCarbohydrates = 200,
    this.dailyFat = 65,
    this.dailyFiber = 25,
    this.dailySodium = 2300,
    this.dailySugar,
    this.dailyWater = 2000,
    this.proteinPercentage,
    this.carbohydratesPercentage,
    this.fatPercentage,
    this.isActive = true,
    DateTime? effectiveDate,
    this.deletedAt,
    required this.createdAt,
    this.updatedAt,
    this.explanation,
    this.bmr,
    this.tdee,
    this.calorieAdjustment,
  }) : effectiveDate = effectiveDate ?? DateTime.now();

  factory NutritionGoal.fromJson(Map<String, dynamic> json) =>
      _$NutritionGoalFromJson(json);

  Map<String, dynamic> toJson() => _$NutritionGoalToJson(this);

  /// Calculate macro percentages from gram values
  double get calculatedProteinPercentage {
    final proteinCals = dailyProtein * 4;
    return (proteinCals / dailyCalories * 100);
  }

  double get calculatedCarbsPercentage {
    final carbCals = dailyCarbohydrates * 4;
    return (carbCals / dailyCalories * 100);
  }

  double get calculatedFatPercentage {
    final fatCals = dailyFat * 9;
    return (fatCals / dailyCalories * 100);
  }

  /// Create a default nutrition goal
  factory NutritionGoal.defaultGoal(int userId) {
    return NutritionGoal(
      id: 0,
      userId: userId,
      name: 'Default',
      dailyCalories: 2000,
      dailyProtein: 150,
      dailyCarbohydrates: 200,
      dailyFat: 65,
      dailyFiber: 25,
      dailyWater: 2000,
      isActive: true,
      createdAt: DateTime.now(),
    );
  }

  NutritionGoal copyWith({
    int? id,
    int? userId,
    String? name,
    double? dailyCalories,
    double? dailyProtein,
    double? dailyCarbohydrates,
    double? dailyFat,
    double? dailyFiber,
    double? dailySodium,
    double? dailySugar,
    double? dailyWater,
    double? proteinPercentage,
    double? carbohydratesPercentage,
    double? fatPercentage,
    bool? isActive,
    DateTime? effectiveDate,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? explanation,
    double? bmr,
    double? tdee,
    double? calorieAdjustment,
  }) {
    return NutritionGoal(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      dailyCalories: dailyCalories ?? this.dailyCalories,
      dailyProtein: dailyProtein ?? this.dailyProtein,
      dailyCarbohydrates: dailyCarbohydrates ?? this.dailyCarbohydrates,
      dailyFat: dailyFat ?? this.dailyFat,
      dailyFiber: dailyFiber ?? this.dailyFiber,
      dailySodium: dailySodium ?? this.dailySodium,
      dailySugar: dailySugar ?? this.dailySugar,
      dailyWater: dailyWater ?? this.dailyWater,
      proteinPercentage: proteinPercentage ?? this.proteinPercentage,
      carbohydratesPercentage:
          carbohydratesPercentage ?? this.carbohydratesPercentage,
      fatPercentage: fatPercentage ?? this.fatPercentage,
      isActive: isActive ?? this.isActive,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      explanation: explanation ?? this.explanation,
      bmr: bmr ?? this.bmr,
      tdee: tdee ?? this.tdee,
      calorieAdjustment: calorieAdjustment ?? this.calorieAdjustment,
    );
  }
}
