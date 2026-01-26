import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../models/food_template.dart';
import '../models/meal_log.dart';
import '../models/meal_entry.dart';
import '../models/food_item.dart';
import '../models/nutrition_goal.dart';
import '../models/nutrition_summary.dart';
import '../services/api_service.dart';

/// Repository for nutrition operations
class NutritionRepository {
  final ApiService _apiService;
  // ignore: unused_field - reserved for future offline support
  final ConnectivityService? _connectivity;

  NutritionRepository(this._apiService, [this._connectivity]);

  // ============ Food Templates ============

  /// Get all food templates with optional filtering
  Future<List<FoodTemplate>> getFoodTemplates({
    String? category,
    bool? isCustom,
    int page = 1,
    int pageSize = 50,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (category != null) queryParams['category'] = category;
    if (isCustom != null) queryParams['isCustom'] = isCustom.toString();

    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.foodTemplates,
      queryParameters: queryParams,
    );

    return data
        .map((json) => FoodTemplate.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get food template by ID
  Future<FoodTemplate> getFoodTemplateById(int id) async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.foodTemplateById(id),
    );
    return FoodTemplate.fromJson(data);
  }

  /// Get food template categories
  Future<List<String>> getFoodCategories() async {
    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.foodTemplateCategories,
    );
    return data.cast<String>();
  }

  /// Search food templates
  Future<List<FoodTemplate>> searchFoods(
    String query, {
    String? category,
    int limit = 20,
  }) async {
    final queryParams = <String, String>{
      'query': query,
      'limit': limit.toString(),
    };
    if (category != null) queryParams['category'] = category;

    final data = await _apiService.get<List<dynamic>>(
      '${ApiConfig.foodTemplates}/search',
      queryParameters: queryParams,
    );

    return data
        .map((json) => FoodTemplate.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get food template by barcode
  Future<FoodTemplate?> getFoodByBarcode(String barcode) async {
    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.foodTemplateByBarcode(barcode),
      );
      return FoodTemplate.fromJson(data);
    } catch (e) {
      debugPrint('Food not found for barcode: $barcode');
      return null;
    }
  }

  /// Create custom food template
  Future<FoodTemplate> createFoodTemplate(FoodTemplate template) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.foodTemplates,
      data: template.toJson(),
    );
    return FoodTemplate.fromJson(data);
  }

  // ============ Meal Logs ============

  /// Get meal logs for date range
  Future<List<MealLog>> getMealLogs({
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 30,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (startDate != null) {
      queryParams['startDate'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      queryParams['endDate'] = endDate.toIso8601String();
    }

    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.mealLogs,
      queryParameters: queryParams,
    );

    return data
        .map((json) => MealLog.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get meal log by ID
  Future<MealLog> getMealLogById(int id) async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.mealLogById(id),
    );
    return MealLog.fromJson(data);
  }

  /// Get meal log for a specific date
  Future<MealLog?> getMealLogByDate(DateTime date) async {
    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.mealLogByDate(date),
      );
      return MealLog.fromJson(data);
    } catch (e) {
      debugPrint('No meal log found for date: $date');
      return null;
    }
  }

  /// Get today's meal log (creates if not exists)
  Future<MealLog> getTodaysMealLog() async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.mealLogToday,
    );
    return MealLog.fromJson(data);
  }

  /// Create meal log
  Future<MealLog> createMealLog(MealLog mealLog) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.mealLogs,
      data: mealLog.toJson(),
    );
    return MealLog.fromJson(data);
  }

  /// Update water intake
  Future<void> updateWaterIntake(int mealLogId, double waterIntake) async {
    await _apiService.put<void>(
      ApiConfig.mealLogWater(mealLogId),
      data: waterIntake,
    );
  }

  /// Recalculate meal log totals
  Future<MealLog> recalculateMealLog(int mealLogId) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.mealLogRecalculate(mealLogId),
    );
    return MealLog.fromJson(data);
  }

  /// Clear all food from a meal log
  Future<MealLog> clearAllFood(int mealLogId) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.mealLogClear(mealLogId),
    );
    return MealLog.fromJson(data);
  }

  // ============ Meal Entries ============

  /// Get meal entries for a meal log
  Future<List<MealEntry>> getMealEntries(int mealLogId) async {
    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.mealEntriesByMealLog(mealLogId),
    );

    return data
        .map((json) => MealEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get meal entry by ID
  Future<MealEntry> getMealEntryById(int id) async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.mealEntryById(id),
    );
    return MealEntry.fromJson(data);
  }

  /// Create meal entry
  Future<MealEntry> createMealEntry(MealEntry entry) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.mealEntries,
      data: entry.toJson(),
    );
    return MealEntry.fromJson(data);
  }

  /// Mark meal entry as consumed
  Future<void> markMealAsConsumed(
    int entryId, {
    bool isConsumed = true,
    DateTime? consumedAt,
  }) async {
    await _apiService.put<void>(
      ApiConfig.mealEntryConsume(entryId),
      data: {
        'isConsumed': isConsumed,
        if (consumedAt != null) 'consumedAt': consumedAt.toIso8601String(),
      },
    );
  }

  /// Delete meal entry
  Future<void> deleteMealEntry(int id) async {
    await _apiService.delete(ApiConfig.mealEntryById(id));
  }

  // ============ Food Items ============

  /// Get food items for a meal entry
  Future<List<FoodItem>> getFoodItems(int mealEntryId) async {
    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.foodItemsByMealEntry(mealEntryId),
    );

    return data
        .map((json) => FoodItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Add food item
  Future<FoodItem> addFoodItem(FoodItem foodItem) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.foodItems,
      data: foodItem.toJson(),
    );
    return FoodItem.fromJson(data);
  }

  /// Quick add food from template
  Future<FoodItem> quickAddFood({
    required int mealEntryId,
    required int foodTemplateId,
    double quantity = 1,
  }) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.foodItemQuickAdd,
      data: {
        'mealEntryId': mealEntryId,
        'foodTemplateId': foodTemplateId,
        'quantity': quantity,
      },
    );
    return FoodItem.fromJson(data);
  }

  /// Update food item quantity
  Future<FoodItem> updateFoodQuantity(int foodItemId, double quantity) async {
    final data = await _apiService.put<Map<String, dynamic>>(
      ApiConfig.foodItemQuantity(foodItemId),
      data: quantity,
    );
    return FoodItem.fromJson(data);
  }

  /// Delete food item
  Future<void> deleteFoodItem(int id) async {
    await _apiService.delete(ApiConfig.foodItemById(id));
  }

  // ============ Nutrition Goals ============

  /// Get all nutrition goals
  Future<List<NutritionGoal>> getNutritionGoals() async {
    final data = await _apiService.get<List<dynamic>>(ApiConfig.nutritionGoals);

    return data
        .map((json) => NutritionGoal.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get active nutrition goal
  Future<NutritionGoal> getActiveNutritionGoal() async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.nutritionGoalActive,
    );
    return NutritionGoal.fromJson(data);
  }

  /// Create nutrition goal
  Future<NutritionGoal> createNutritionGoal(NutritionGoal goal) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.nutritionGoals,
      data: goal.toJson(),
    );
    return NutritionGoal.fromJson(data);
  }

  /// Update nutrition goal
  Future<void> updateNutritionGoal(int id, NutritionGoal goal) async {
    await _apiService.put<void>(
      ApiConfig.nutritionGoalById(id),
      data: goal.toJson(),
    );
  }

  /// Activate nutrition goal
  Future<void> activateNutritionGoal(int id) async {
    await _apiService.put<void>(ApiConfig.nutritionGoalActivate(id));
  }

  /// Get daily progress vs goal
  Future<NutritionProgress> getNutritionProgress({DateTime? date}) async {
    final queryParams =
        date != null ? {'date': date.toIso8601String().split('T')[0]} : null;

    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.nutritionGoalProgress,
      queryParameters: queryParams,
    );
    return NutritionProgress.fromJson(data);
  }

  /// Delete nutrition goal
  Future<void> deleteNutritionGoal(int id) async {
    await _apiService.delete(ApiConfig.nutritionGoalById(id));
  }

  // ============ Analytics ============

  /// Get daily summary for date range
  Future<List<DailySummary>> getDailySummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) {
      queryParams['startDate'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      queryParams['endDate'] = endDate.toIso8601String();
    }

    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.nutritionAnalyticsDailySummary,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    return data
        .map((json) => DailySummary.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get macro breakdown
  Future<MacroBreakdown> getMacroBreakdown({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (startDate != null) {
      queryParams['startDate'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      queryParams['endDate'] = endDate.toIso8601String();
    }

    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.nutritionAnalyticsMacroBreakdown,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    return MacroBreakdown.fromJson(data);
  }

  /// Get calorie trend
  Future<List<CalorieTrendPoint>> getCalorieTrend({int days = 30}) async {
    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.nutritionAnalyticsCalorieTrend,
      queryParameters: {'days': days.toString()},
    );

    return data
        .map((json) => CalorieTrendPoint.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get logging streak
  Future<StreakInfo> getStreak() async {
    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.nutritionAnalyticsStreak,
    );
    return StreakInfo.fromJson(data);
  }

  /// Get frequently logged foods
  Future<List<FrequentFood>> getFrequentFoods({
    int limit = 10,
    int days = 30,
  }) async {
    final data = await _apiService.get<List<dynamic>>(
      ApiConfig.nutritionAnalyticsFrequentFoods,
      queryParameters: {'limit': limit.toString(), 'days': days.toString()},
    );

    return data
        .map((json) => FrequentFood.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get AI-powered food alternatives
  Future<List<FoodAlternative>> getFoodAlternatives({
    required String foodName,
    required double calories,
    required double protein,
    required double carbohydrates,
    required double fat,
  }) async {
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.chatFoodSuggestion,
      data: {
        'foodName': foodName,
        'calories': calories,
        'protein': protein,
        'carbohydrates': carbohydrates,
        'fat': fat,
      },
    );

    final alternatives = data['alternatives'] as List<dynamic>?;
    if (alternatives == null || alternatives.isEmpty) {
      return [];
    }

    return alternatives
        .map((json) => FoodAlternative.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

/// Food alternative suggestion from AI
class FoodAlternative {
  final String name;
  final double servingSize;
  final String servingUnit;
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;
  final String? reason;

  FoodAlternative({
    required this.name,
    required this.servingSize,
    required this.servingUnit,
    required this.calories,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
    this.reason,
  });

  factory FoodAlternative.fromJson(Map<String, dynamic> json) {
    return FoodAlternative(
      name: json['name'] as String? ?? '',
      servingSize: (json['servingSize'] as num?)?.toDouble() ?? 100,
      servingUnit: json['servingUnit'] as String? ?? 'g',
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbohydrates: (json['carbohydrates'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      reason: json['reason'] as String?,
    );
  }
}
