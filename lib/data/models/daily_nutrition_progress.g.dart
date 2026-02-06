// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daily_nutrition_progress.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DailyNutritionProgress _$DailyNutritionProgressFromJson(
        Map<String, dynamic> json) =>
    DailyNutritionProgress(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      date: DateTime.parse(json['date'] as String),
      nutritionGoalId: (json['nutritionGoalId'] as num?)?.toInt(),
      plannedCalories: (json['plannedCalories'] as num?)?.toDouble() ?? 0,
      plannedProtein: (json['plannedProtein'] as num?)?.toDouble() ?? 0,
      plannedCarbohydrates:
          (json['plannedCarbohydrates'] as num?)?.toDouble() ?? 0,
      plannedFat: (json['plannedFat'] as num?)?.toDouble() ?? 0,
      plannedFiber: (json['plannedFiber'] as num?)?.toDouble() ?? 0,
      plannedWater: (json['plannedWater'] as num?)?.toDouble() ?? 0,
      consumedCalories: (json['consumedCalories'] as num?)?.toDouble() ?? 0,
      consumedProtein: (json['consumedProtein'] as num?)?.toDouble() ?? 0,
      consumedCarbohydrates:
          (json['consumedCarbohydrates'] as num?)?.toDouble() ?? 0,
      consumedFat: (json['consumedFat'] as num?)?.toDouble() ?? 0,
      consumedFiber: (json['consumedFiber'] as num?)?.toDouble() ?? 0,
      consumedWater: (json['consumedWater'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$DailyNutritionProgressToJson(
    DailyNutritionProgress instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'userId': instance.userId,
    'date': instance.date.toIso8601String(),
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('nutritionGoalId', instance.nutritionGoalId);
  val['plannedCalories'] = instance.plannedCalories;
  val['plannedProtein'] = instance.plannedProtein;
  val['plannedCarbohydrates'] = instance.plannedCarbohydrates;
  val['plannedFat'] = instance.plannedFat;
  val['plannedFiber'] = instance.plannedFiber;
  val['plannedWater'] = instance.plannedWater;
  val['consumedCalories'] = instance.consumedCalories;
  val['consumedProtein'] = instance.consumedProtein;
  val['consumedCarbohydrates'] = instance.consumedCarbohydrates;
  val['consumedFat'] = instance.consumedFat;
  val['consumedFiber'] = instance.consumedFiber;
  val['consumedWater'] = instance.consumedWater;
  val['createdAt'] = instance.createdAt.toIso8601String();
  writeNotNull('updatedAt', instance.updatedAt?.toIso8601String());
  return val;
}
