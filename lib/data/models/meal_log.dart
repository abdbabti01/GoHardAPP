import 'package:json_annotation/json_annotation.dart';
import 'meal_entry.dart';

part 'meal_log.g.dart';

@JsonSerializable(includeIfNull: false)
class MealLog {
  final int id;
  final int userId;
  final DateTime date;
  final String? notes;
  final double waterIntake;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbohydrates;
  final double totalFat;
  final double? totalFiber;
  final double? totalSodium;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<MealEntry>? mealEntries;

  MealLog({
    required this.id,
    required this.userId,
    required this.date,
    this.notes,
    this.waterIntake = 0,
    this.totalCalories = 0,
    this.totalProtein = 0,
    this.totalCarbohydrates = 0,
    this.totalFat = 0,
    this.totalFiber,
    this.totalSodium,
    required this.createdAt,
    this.updatedAt,
    this.mealEntries,
  });

  factory MealLog.fromJson(Map<String, dynamic> json) =>
      _$MealLogFromJson(json);

  Map<String, dynamic> toJson() => _$MealLogToJson(this);

  /// Get meal entries by type
  List<MealEntry> getMealsByType(String mealType) {
    return mealEntries?.where((e) => e.mealType == mealType).toList() ?? [];
  }

  /// Get breakfast entries
  List<MealEntry> get breakfastEntries => getMealsByType('Breakfast');

  /// Get lunch entries
  List<MealEntry> get lunchEntries => getMealsByType('Lunch');

  /// Get dinner entries
  List<MealEntry> get dinnerEntries => getMealsByType('Dinner');

  /// Get snack entries
  List<MealEntry> get snackEntries => getMealsByType('Snack');

  MealLog copyWith({
    int? id,
    int? userId,
    DateTime? date,
    String? notes,
    double? waterIntake,
    double? totalCalories,
    double? totalProtein,
    double? totalCarbohydrates,
    double? totalFat,
    double? totalFiber,
    double? totalSodium,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<MealEntry>? mealEntries,
  }) {
    return MealLog(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      waterIntake: waterIntake ?? this.waterIntake,
      totalCalories: totalCalories ?? this.totalCalories,
      totalProtein: totalProtein ?? this.totalProtein,
      totalCarbohydrates: totalCarbohydrates ?? this.totalCarbohydrates,
      totalFat: totalFat ?? this.totalFat,
      totalFiber: totalFiber ?? this.totalFiber,
      totalSodium: totalSodium ?? this.totalSodium,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mealEntries: mealEntries ?? this.mealEntries,
    );
  }
}
