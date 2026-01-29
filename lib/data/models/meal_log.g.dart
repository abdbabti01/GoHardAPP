// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meal_log.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MealLog _$MealLogFromJson(Map<String, dynamic> json) => MealLog(
  id: (json['id'] as num).toInt(),
  userId: (json['userId'] as num).toInt(),
  date: DateTime.parse(json['date'] as String),
  notes: json['notes'] as String?,
  waterIntake: (json['waterIntake'] as num?)?.toDouble() ?? 0,
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
  mealEntries:
      (json['mealEntries'] as List<dynamic>?)
          ?.map((e) => MealEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
);

Map<String, dynamic> _$MealLogToJson(MealLog instance) {
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

  writeNotNull('notes', instance.notes);
  val['waterIntake'] = instance.waterIntake;
  val['totalCalories'] = instance.totalCalories;
  val['totalProtein'] = instance.totalProtein;
  val['totalCarbohydrates'] = instance.totalCarbohydrates;
  val['totalFat'] = instance.totalFat;
  writeNotNull('totalFiber', instance.totalFiber);
  writeNotNull('totalSodium', instance.totalSodium);
  val['createdAt'] = instance.createdAt.toIso8601String();
  writeNotNull('updatedAt', instance.updatedAt?.toIso8601String());
  writeNotNull('mealEntries', instance.mealEntries);
  return val;
}
