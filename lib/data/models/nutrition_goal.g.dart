// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nutrition_goal.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NutritionGoal _$NutritionGoalFromJson(Map<String, dynamic> json) =>
    NutritionGoal(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      name: json['name'] as String?,
      dailyCalories: (json['dailyCalories'] as num?)?.toDouble() ?? 2000,
      dailyProtein: (json['dailyProtein'] as num?)?.toDouble() ?? 150,
      dailyCarbohydrates:
          (json['dailyCarbohydrates'] as num?)?.toDouble() ?? 200,
      dailyFat: (json['dailyFat'] as num?)?.toDouble() ?? 65,
      dailyFiber: (json['dailyFiber'] as num?)?.toDouble() ?? 25,
      dailySodium: (json['dailySodium'] as num?)?.toDouble() ?? 2300,
      dailySugar: (json['dailySugar'] as num?)?.toDouble(),
      dailyWater: (json['dailyWater'] as num?)?.toDouble() ?? 2000,
      proteinPercentage: (json['proteinPercentage'] as num?)?.toDouble(),
      carbohydratesPercentage:
          (json['carbohydratesPercentage'] as num?)?.toDouble(),
      fatPercentage: (json['fatPercentage'] as num?)?.toDouble(),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$NutritionGoalToJson(NutritionGoal instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'userId': instance.userId,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('name', instance.name);
  val['dailyCalories'] = instance.dailyCalories;
  val['dailyProtein'] = instance.dailyProtein;
  val['dailyCarbohydrates'] = instance.dailyCarbohydrates;
  val['dailyFat'] = instance.dailyFat;
  writeNotNull('dailyFiber', instance.dailyFiber);
  writeNotNull('dailySodium', instance.dailySodium);
  writeNotNull('dailySugar', instance.dailySugar);
  writeNotNull('dailyWater', instance.dailyWater);
  writeNotNull('proteinPercentage', instance.proteinPercentage);
  writeNotNull('carbohydratesPercentage', instance.carbohydratesPercentage);
  writeNotNull('fatPercentage', instance.fatPercentage);
  val['isActive'] = instance.isActive;
  val['createdAt'] = instance.createdAt.toIso8601String();
  writeNotNull('updatedAt', instance.updatedAt?.toIso8601String());
  return val;
}
