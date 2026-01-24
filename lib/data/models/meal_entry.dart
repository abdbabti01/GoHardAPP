import 'package:json_annotation/json_annotation.dart';
import 'food_item.dart';

part 'meal_entry.g.dart';

@JsonSerializable(includeIfNull: false)
class MealEntry {
  final int id;
  final int mealLogId;
  final String mealType; // Breakfast, Lunch, Dinner, Snack
  final String? name;
  final DateTime? scheduledTime;
  final bool isConsumed;
  final DateTime? consumedAt;
  final String? notes;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbohydrates;
  final double totalFat;
  final double? totalFiber;
  final double? totalSodium;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<FoodItem>? foodItems;

  MealEntry({
    required this.id,
    required this.mealLogId,
    this.mealType = 'Snack',
    this.name,
    this.scheduledTime,
    this.isConsumed = false,
    this.consumedAt,
    this.notes,
    this.totalCalories = 0,
    this.totalProtein = 0,
    this.totalCarbohydrates = 0,
    this.totalFat = 0,
    this.totalFiber,
    this.totalSodium,
    required this.createdAt,
    this.updatedAt,
    this.foodItems,
  });

  factory MealEntry.fromJson(Map<String, dynamic> json) =>
      _$MealEntryFromJson(json);

  Map<String, dynamic> toJson() => _$MealEntryToJson(this);

  /// Get the display name for this meal entry
  String get displayName => name ?? mealType;

  /// Get the total number of food items
  int get foodItemCount => foodItems?.length ?? 0;

  MealEntry copyWith({
    int? id,
    int? mealLogId,
    String? mealType,
    String? name,
    DateTime? scheduledTime,
    bool? isConsumed,
    DateTime? consumedAt,
    String? notes,
    double? totalCalories,
    double? totalProtein,
    double? totalCarbohydrates,
    double? totalFat,
    double? totalFiber,
    double? totalSodium,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<FoodItem>? foodItems,
  }) {
    return MealEntry(
      id: id ?? this.id,
      mealLogId: mealLogId ?? this.mealLogId,
      mealType: mealType ?? this.mealType,
      name: name ?? this.name,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      isConsumed: isConsumed ?? this.isConsumed,
      consumedAt: consumedAt ?? this.consumedAt,
      notes: notes ?? this.notes,
      totalCalories: totalCalories ?? this.totalCalories,
      totalProtein: totalProtein ?? this.totalProtein,
      totalCarbohydrates: totalCarbohydrates ?? this.totalCarbohydrates,
      totalFat: totalFat ?? this.totalFat,
      totalFiber: totalFiber ?? this.totalFiber,
      totalSodium: totalSodium ?? this.totalSodium,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      foodItems: foodItems ?? this.foodItems,
    );
  }
}

/// Meal type constants
class MealTypes {
  static const String breakfast = 'Breakfast';
  static const String lunch = 'Lunch';
  static const String dinner = 'Dinner';
  static const String snack = 'Snack';

  static const List<String> all = [breakfast, lunch, dinner, snack];

  /// Get icon for meal type
  static String getIcon(String mealType) {
    switch (mealType) {
      case breakfast:
        return '🌅';
      case lunch:
        return '☀️';
      case dinner:
        return '🌙';
      case snack:
        return '🍎';
      default:
        return '🍽️';
    }
  }
}
