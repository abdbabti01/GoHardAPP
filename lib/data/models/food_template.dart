import 'package:json_annotation/json_annotation.dart';

part 'food_template.g.dart';

@JsonSerializable(includeIfNull: false)
class FoodTemplate {
  final int id;
  final String name;
  final String? brand;
  final String? category;
  final String? barcode;
  final double servingSize;
  final String servingUnit;
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;
  final double? fiber;
  final double? sugar;
  final double? saturatedFat;
  final double? transFat;
  final double? sodium;
  final double? potassium;
  final double? cholesterol;
  final double? vitaminA;
  final double? vitaminC;
  final double? vitaminD;
  final double? calcium;
  final double? iron;
  final String? description;
  final String? imageUrl;
  final bool isCustom;
  final int? createdByUserId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  FoodTemplate({
    required this.id,
    required this.name,
    this.brand,
    this.category,
    this.barcode,
    this.servingSize = 100,
    this.servingUnit = 'g',
    required this.calories,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
    this.fiber,
    this.sugar,
    this.saturatedFat,
    this.transFat,
    this.sodium,
    this.potassium,
    this.cholesterol,
    this.vitaminA,
    this.vitaminC,
    this.vitaminD,
    this.calcium,
    this.iron,
    this.description,
    this.imageUrl,
    this.isCustom = false,
    this.createdByUserId,
    required this.createdAt,
    this.updatedAt,
  });

  factory FoodTemplate.fromJson(Map<String, dynamic> json) =>
      _$FoodTemplateFromJson(json);

  Map<String, dynamic> toJson() => _$FoodTemplateToJson(this);

  FoodTemplate copyWith({
    int? id,
    String? name,
    String? brand,
    String? category,
    String? barcode,
    double? servingSize,
    String? servingUnit,
    double? calories,
    double? protein,
    double? carbohydrates,
    double? fat,
    double? fiber,
    double? sugar,
    double? saturatedFat,
    double? transFat,
    double? sodium,
    double? potassium,
    double? cholesterol,
    double? vitaminA,
    double? vitaminC,
    double? vitaminD,
    double? calcium,
    double? iron,
    String? description,
    String? imageUrl,
    bool? isCustom,
    int? createdByUserId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FoodTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      barcode: barcode ?? this.barcode,
      servingSize: servingSize ?? this.servingSize,
      servingUnit: servingUnit ?? this.servingUnit,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbohydrates: carbohydrates ?? this.carbohydrates,
      fat: fat ?? this.fat,
      fiber: fiber ?? this.fiber,
      sugar: sugar ?? this.sugar,
      saturatedFat: saturatedFat ?? this.saturatedFat,
      transFat: transFat ?? this.transFat,
      sodium: sodium ?? this.sodium,
      potassium: potassium ?? this.potassium,
      cholesterol: cholesterol ?? this.cholesterol,
      vitaminA: vitaminA ?? this.vitaminA,
      vitaminC: vitaminC ?? this.vitaminC,
      vitaminD: vitaminD ?? this.vitaminD,
      calcium: calcium ?? this.calcium,
      iron: iron ?? this.iron,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      isCustom: isCustom ?? this.isCustom,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
