// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meal_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MealEntry _$MealEntryFromJson(Map<String, dynamic> json) => MealEntry(
  id: (json['id'] as num).toInt(),
  mealLogId: (json['mealLogId'] as num).toInt(),
  mealType: json['mealType'] as String? ?? 'Snack',
  name: json['name'] as String?,
  scheduledTime:
      json['scheduledTime'] == null
          ? null
          : DateTime.parse(json['scheduledTime'] as String),
  isConsumed: json['isConsumed'] as bool? ?? false,
  consumedAt:
      json['consumedAt'] == null
          ? null
          : DateTime.parse(json['consumedAt'] as String),
  notes: json['notes'] as String?,
  totalCalories: (json['totalCalories'] as num?)?.toDouble() ?? 0,
  totalProtein: (json['totalProtein'] as num?)?.toDouble() ?? 0,
  totalCarbohydrates: (json['totalCarbohydrates'] as num?)?.toDouble() ?? 0,
  totalFat: (json['totalFat'] as num?)?.toDouble() ?? 0,
  totalFiber: (json['totalFiber'] as num?)?.toDouble(),
  totalSodium: (json['totalSodium'] as num?)?.toDouble(),
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt:
      json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
  foodItems:
      (json['foodItems'] as List<dynamic>?)
          ?.map((e) => FoodItem.fromJson(e as Map<String, dynamic>))
          .toList(),
);

Map<String, dynamic> _$MealEntryToJson(MealEntry instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'mealLogId': instance.mealLogId,
    'mealType': instance.mealType,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('name', instance.name);
  writeNotNull('scheduledTime', instance.scheduledTime?.toIso8601String());
  val['isConsumed'] = instance.isConsumed;
  writeNotNull('consumedAt', instance.consumedAt?.toIso8601String());
  writeNotNull('notes', instance.notes);
  val['totalCalories'] = instance.totalCalories;
  val['totalProtein'] = instance.totalProtein;
  val['totalCarbohydrates'] = instance.totalCarbohydrates;
  val['totalFat'] = instance.totalFat;
  writeNotNull('totalFiber', instance.totalFiber);
  writeNotNull('totalSodium', instance.totalSodium);
  val['createdAt'] = instance.createdAt.toIso8601String();
  writeNotNull('updatedAt', instance.updatedAt?.toIso8601String());
  writeNotNull('foodItems', instance.foodItems);
  return val;
}
