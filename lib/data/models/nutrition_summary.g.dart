// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nutrition_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NutritionTotals _$NutritionTotalsFromJson(Map<String, dynamic> json) =>
    NutritionTotals(
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbohydrates: (json['carbohydrates'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      fiber: (json['fiber'] as num?)?.toDouble(),
      sodium: (json['sodium'] as num?)?.toDouble(),
      water: (json['water'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$NutritionTotalsToJson(NutritionTotals instance) {
  final val = <String, dynamic>{
    'calories': instance.calories,
    'protein': instance.protein,
    'carbohydrates': instance.carbohydrates,
    'fat': instance.fat,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('fiber', instance.fiber);
  writeNotNull('sodium', instance.sodium);
  writeNotNull('water', instance.water);
  return val;
}

NutritionPercentages _$NutritionPercentagesFromJson(
        Map<String, dynamic> json) =>
    NutritionPercentages(
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbohydrates: (json['carbohydrates'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> _$NutritionPercentagesToJson(
        NutritionPercentages instance) =>
    <String, dynamic>{
      'calories': instance.calories,
      'protein': instance.protein,
      'carbohydrates': instance.carbohydrates,
      'fat': instance.fat,
    };

NutritionProgress _$NutritionProgressFromJson(Map<String, dynamic> json) =>
    NutritionProgress(
      date: DateTime.parse(json['date'] as String),
      goal: NutritionGoal.fromJson(json['goal'] as Map<String, dynamic>),
      consumed:
          NutritionTotals.fromJson(json['consumed'] as Map<String, dynamic>),
      remaining:
          NutritionTotals.fromJson(json['remaining'] as Map<String, dynamic>),
      percentageConsumed: NutritionPercentages.fromJson(
          json['percentageConsumed'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$NutritionProgressToJson(NutritionProgress instance) =>
    <String, dynamic>{
      'date': instance.date.toIso8601String(),
      'goal': instance.goal,
      'consumed': instance.consumed,
      'remaining': instance.remaining,
      'percentageConsumed': instance.percentageConsumed,
    };

DailySummary _$DailySummaryFromJson(Map<String, dynamic> json) => DailySummary(
      date: DateTime.parse(json['date'] as String),
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbohydrates: (json['carbohydrates'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      fiber: (json['fiber'] as num?)?.toDouble(),
      water: (json['water'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$DailySummaryToJson(DailySummary instance) {
  final val = <String, dynamic>{
    'date': instance.date.toIso8601String(),
    'calories': instance.calories,
    'protein': instance.protein,
    'carbohydrates': instance.carbohydrates,
    'fat': instance.fat,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('fiber', instance.fiber);
  writeNotNull('water', instance.water);
  return val;
}

MacroBreakdown _$MacroBreakdownFromJson(Map<String, dynamic> json) =>
    MacroBreakdown(
      totalCalories: (json['totalCalories'] as num?)?.toDouble() ?? 0,
      totalProtein: (json['totalProtein'] as num?)?.toDouble() ?? 0,
      totalCarbohydrates: (json['totalCarbohydrates'] as num?)?.toDouble() ?? 0,
      totalFat: (json['totalFat'] as num?)?.toDouble() ?? 0,
      proteinPercentage: (json['proteinPercentage'] as num?)?.toDouble() ?? 0,
      carbohydratesPercentage:
          (json['carbohydratesPercentage'] as num?)?.toDouble() ?? 0,
      fatPercentage: (json['fatPercentage'] as num?)?.toDouble() ?? 0,
      averageDailyCalories:
          (json['averageDailyCalories'] as num?)?.toDouble() ?? 0,
      averageDailyProtein:
          (json['averageDailyProtein'] as num?)?.toDouble() ?? 0,
      averageDailyCarbohydrates:
          (json['averageDailyCarbohydrates'] as num?)?.toDouble() ?? 0,
      averageDailyFat: (json['averageDailyFat'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> _$MacroBreakdownToJson(MacroBreakdown instance) =>
    <String, dynamic>{
      'totalCalories': instance.totalCalories,
      'totalProtein': instance.totalProtein,
      'totalCarbohydrates': instance.totalCarbohydrates,
      'totalFat': instance.totalFat,
      'proteinPercentage': instance.proteinPercentage,
      'carbohydratesPercentage': instance.carbohydratesPercentage,
      'fatPercentage': instance.fatPercentage,
      'averageDailyCalories': instance.averageDailyCalories,
      'averageDailyProtein': instance.averageDailyProtein,
      'averageDailyCarbohydrates': instance.averageDailyCarbohydrates,
      'averageDailyFat': instance.averageDailyFat,
    };

CalorieTrendPoint _$CalorieTrendPointFromJson(Map<String, dynamic> json) =>
    CalorieTrendPoint(
      date: DateTime.parse(json['date'] as String),
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      target: (json['target'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$CalorieTrendPointToJson(CalorieTrendPoint instance) {
  final val = <String, dynamic>{
    'date': instance.date.toIso8601String(),
    'calories': instance.calories,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('target', instance.target);
  return val;
}

StreakInfo _$StreakInfoFromJson(Map<String, dynamic> json) => StreakInfo(
      currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longestStreak'] as num?)?.toInt() ?? 0,
      totalDaysLogged: (json['totalDaysLogged'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$StreakInfoToJson(StreakInfo instance) =>
    <String, dynamic>{
      'currentStreak': instance.currentStreak,
      'longestStreak': instance.longestStreak,
      'totalDaysLogged': instance.totalDaysLogged,
    };

FrequentFood _$FrequentFoodFromJson(Map<String, dynamic> json) => FrequentFood(
      name: json['name'] as String,
      foodTemplateId: (json['foodTemplateId'] as num?)?.toInt(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      totalCalories: (json['totalCalories'] as num?)?.toDouble() ?? 0,
      averageCalories: (json['averageCalories'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> _$FrequentFoodToJson(FrequentFood instance) {
  final val = <String, dynamic>{
    'name': instance.name,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('foodTemplateId', instance.foodTemplateId);
  val['count'] = instance.count;
  val['totalCalories'] = instance.totalCalories;
  val['averageCalories'] = instance.averageCalories;
  return val;
}
