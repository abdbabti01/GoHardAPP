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
  final DateTime createdAt;
  final DateTime? updatedAt;

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
    required this.createdAt,
    this.updatedAt,
  });

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
    DateTime? createdAt,
    DateTime? updatedAt,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
