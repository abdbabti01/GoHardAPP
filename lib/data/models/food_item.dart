import 'package:json_annotation/json_annotation.dart';
import 'food_template.dart';

part 'food_item.g.dart';

@JsonSerializable(includeIfNull: false)
class FoodItem {
  final int id;
  final int mealEntryId;
  final int? foodTemplateId;
  final String name;
  final String? brand;
  final double quantity;
  final double servingSize;
  final String servingUnit;
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;
  final double? fiber;
  final double? sugar;
  final double? sodium;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final FoodTemplate? foodTemplate;

  FoodItem({
    required this.id,
    required this.mealEntryId,
    this.foodTemplateId,
    required this.name,
    this.brand,
    this.quantity = 1,
    this.servingSize = 100,
    this.servingUnit = 'g',
    required this.calories,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
    this.fiber,
    this.sugar,
    this.sodium,
    required this.createdAt,
    this.updatedAt,
    this.foodTemplate,
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) =>
      _$FoodItemFromJson(json);

  Map<String, dynamic> toJson() => _$FoodItemToJson(this);

  /// Create a food item from a template with a given quantity
  factory FoodItem.fromTemplate({
    required int mealEntryId,
    required FoodTemplate template,
    double quantity = 1,
  }) {
    return FoodItem(
      id: 0, // Will be set by server
      mealEntryId: mealEntryId,
      foodTemplateId: template.id,
      name: template.name,
      brand: template.brand,
      quantity: quantity,
      servingSize: template.servingSize,
      servingUnit: template.servingUnit,
      calories: template.calories * quantity,
      protein: template.protein * quantity,
      carbohydrates: template.carbohydrates * quantity,
      fat: template.fat * quantity,
      fiber: template.fiber != null ? template.fiber! * quantity : null,
      sugar: template.sugar != null ? template.sugar! * quantity : null,
      sodium: template.sodium != null ? template.sodium! * quantity : null,
      createdAt: DateTime.now(),
    );
  }

  /// Get the serving description (e.g., "1 x 100g")
  String get servingDescription =>
      '${quantity.toStringAsFixed(quantity.truncateToDouble() == quantity ? 0 : 1)} x ${servingSize.toStringAsFixed(0)}$servingUnit';

  FoodItem copyWith({
    int? id,
    int? mealEntryId,
    int? foodTemplateId,
    String? name,
    String? brand,
    double? quantity,
    double? servingSize,
    String? servingUnit,
    double? calories,
    double? protein,
    double? carbohydrates,
    double? fat,
    double? fiber,
    double? sugar,
    double? sodium,
    DateTime? createdAt,
    DateTime? updatedAt,
    FoodTemplate? foodTemplate,
  }) {
    return FoodItem(
      id: id ?? this.id,
      mealEntryId: mealEntryId ?? this.mealEntryId,
      foodTemplateId: foodTemplateId ?? this.foodTemplateId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      quantity: quantity ?? this.quantity,
      servingSize: servingSize ?? this.servingSize,
      servingUnit: servingUnit ?? this.servingUnit,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbohydrates: carbohydrates ?? this.carbohydrates,
      fat: fat ?? this.fat,
      fiber: fiber ?? this.fiber,
      sugar: sugar ?? this.sugar,
      sodium: sodium ?? this.sodium,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      foodTemplate: foodTemplate ?? this.foodTemplate,
    );
  }
}
