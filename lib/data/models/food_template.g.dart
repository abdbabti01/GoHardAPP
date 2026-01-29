// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'food_template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FoodTemplate _$FoodTemplateFromJson(Map<String, dynamic> json) => FoodTemplate(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      brand: json['brand'] as String?,
      category: json['category'] as String?,
      barcode: json['barcode'] as String?,
      servingSize: (json['servingSize'] as num?)?.toDouble() ?? 100,
      servingUnit: json['servingUnit'] as String? ?? 'g',
      calories: (json['calories'] as num).toDouble(),
      protein: (json['protein'] as num).toDouble(),
      carbohydrates: (json['carbohydrates'] as num).toDouble(),
      fat: (json['fat'] as num).toDouble(),
      fiber: (json['fiber'] as num?)?.toDouble(),
      sugar: (json['sugar'] as num?)?.toDouble(),
      saturatedFat: (json['saturatedFat'] as num?)?.toDouble(),
      transFat: (json['transFat'] as num?)?.toDouble(),
      sodium: (json['sodium'] as num?)?.toDouble(),
      potassium: (json['potassium'] as num?)?.toDouble(),
      cholesterol: (json['cholesterol'] as num?)?.toDouble(),
      vitaminA: (json['vitaminA'] as num?)?.toDouble(),
      vitaminC: (json['vitaminC'] as num?)?.toDouble(),
      vitaminD: (json['vitaminD'] as num?)?.toDouble(),
      calcium: (json['calcium'] as num?)?.toDouble(),
      iron: (json['iron'] as num?)?.toDouble(),
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      isCustom: json['isCustom'] as bool? ?? false,
      createdByUserId: (json['createdByUserId'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$FoodTemplateToJson(FoodTemplate instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'name': instance.name,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('brand', instance.brand);
  writeNotNull('category', instance.category);
  writeNotNull('barcode', instance.barcode);
  val['servingSize'] = instance.servingSize;
  val['servingUnit'] = instance.servingUnit;
  val['calories'] = instance.calories;
  val['protein'] = instance.protein;
  val['carbohydrates'] = instance.carbohydrates;
  val['fat'] = instance.fat;
  writeNotNull('fiber', instance.fiber);
  writeNotNull('sugar', instance.sugar);
  writeNotNull('saturatedFat', instance.saturatedFat);
  writeNotNull('transFat', instance.transFat);
  writeNotNull('sodium', instance.sodium);
  writeNotNull('potassium', instance.potassium);
  writeNotNull('cholesterol', instance.cholesterol);
  writeNotNull('vitaminA', instance.vitaminA);
  writeNotNull('vitaminC', instance.vitaminC);
  writeNotNull('vitaminD', instance.vitaminD);
  writeNotNull('calcium', instance.calcium);
  writeNotNull('iron', instance.iron);
  writeNotNull('description', instance.description);
  writeNotNull('imageUrl', instance.imageUrl);
  val['isCustom'] = instance.isCustom;
  writeNotNull('createdByUserId', instance.createdByUserId);
  val['createdAt'] = instance.createdAt.toIso8601String();
  writeNotNull('updatedAt', instance.updatedAt?.toIso8601String());
  return val;
}
