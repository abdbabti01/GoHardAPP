// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'food_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FoodItem _$FoodItemFromJson(Map<String, dynamic> json) => FoodItem(
      id: (json['id'] as num).toInt(),
      mealEntryId: (json['mealEntryId'] as num).toInt(),
      foodTemplateId: (json['foodTemplateId'] as num?)?.toInt(),
      name: json['name'] as String,
      brand: json['brand'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
      servingSize: (json['servingSize'] as num?)?.toDouble() ?? 100,
      servingUnit: json['servingUnit'] as String? ?? 'g',
      calories: (json['calories'] as num).toDouble(),
      protein: (json['protein'] as num).toDouble(),
      carbohydrates: (json['carbohydrates'] as num).toDouble(),
      fat: (json['fat'] as num).toDouble(),
      fiber: (json['fiber'] as num?)?.toDouble(),
      sugar: (json['sugar'] as num?)?.toDouble(),
      sodium: (json['sodium'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      foodTemplate: json['foodTemplate'] == null
          ? null
          : FoodTemplate.fromJson(json['foodTemplate'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$FoodItemToJson(FoodItem instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'mealEntryId': instance.mealEntryId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('foodTemplateId', instance.foodTemplateId);
  val['name'] = instance.name;
  writeNotNull('brand', instance.brand);
  val['quantity'] = instance.quantity;
  val['servingSize'] = instance.servingSize;
  val['servingUnit'] = instance.servingUnit;
  val['calories'] = instance.calories;
  val['protein'] = instance.protein;
  val['carbohydrates'] = instance.carbohydrates;
  val['fat'] = instance.fat;
  writeNotNull('fiber', instance.fiber);
  writeNotNull('sugar', instance.sugar);
  writeNotNull('sodium', instance.sodium);
  val['createdAt'] = instance.createdAt.toIso8601String();
  writeNotNull('updatedAt', instance.updatedAt?.toIso8601String());
  writeNotNull('foodTemplate', instance.foodTemplate);
  return val;
}
