import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models/food_template.dart';
import '../data/models/meal_log.dart';
import '../data/models/meal_entry.dart';
import '../data/models/food_item.dart';
import '../data/models/nutrition_goal.dart';
import '../data/models/nutrition_summary.dart';
import '../data/repositories/nutrition_repository.dart';
import '../core/services/connectivity_service.dart';

export '../data/repositories/nutrition_repository.dart' show FoodAlternative;

/// Provider for nutrition tracking
class NutritionProvider extends ChangeNotifier {
  final NutritionRepository _nutritionRepository;
  final ConnectivityService? _connectivity;

  // State
  MealLog? _todaysMealLog;
  NutritionGoal? _activeGoal;
  NutritionProgress? _todaysProgress;
  List<FoodTemplate> _recentFoods = [];
  List<FoodTemplate> _searchResults = [];
  List<String> _categories = [];
  StreakInfo? _streakInfo;

  bool _isLoading = false;
  bool _isSearching = false;
  bool _isAddingFood = false;
  String? _errorMessage;

  // Day change detection
  DateTime? _lastLoadedDate;

  // Nutrition history
  List<MealLog> _nutritionHistory = [];
  bool _isLoadingHistory = false;
  String _historyFilter = 'week'; // 'week', 'month', '3months'

  StreamSubscription<bool>? _connectivitySubscription;

  NutritionProvider(this._nutritionRepository, [this._connectivity]) {
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
      if (isOnline && _todaysMealLog == null) {
        debugPrint('📡 Connection restored - loading nutrition data');
        loadTodaysData();
      }
    });
  }

  // Getters
  MealLog? get todaysMealLog => _todaysMealLog;
  NutritionGoal? get activeGoal => _activeGoal;
  NutritionProgress? get todaysProgress => _todaysProgress;
  List<FoodTemplate> get recentFoods => _recentFoods;
  List<FoodTemplate> get searchResults => _searchResults;
  List<String> get categories => _categories;
  StreakInfo? get streakInfo => _streakInfo;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get isAddingFood => _isAddingFood;
  String? get errorMessage => _errorMessage;
  List<MealLog> get nutritionHistory => _nutritionHistory;
  bool get isLoadingHistory => _isLoadingHistory;
  String get historyFilter => _historyFilter;

  /// Load today's meal log, active goal, and progress
  Future<void> loadTodaysData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Load in parallel
      final results = await Future.wait([
        _nutritionRepository.getTodaysMealLog(),
        _nutritionRepository.getActiveNutritionGoal(),
        _nutritionRepository.getNutritionProgress(),
        _nutritionRepository.getStreak(),
      ]);

      _todaysMealLog = results[0] as MealLog;
      _activeGoal = results[1] as NutritionGoal;
      _todaysProgress = results[2] as NutritionProgress;
      _streakInfo = results[3] as StreakInfo;

      // Track when data was loaded for day change detection
      _lastLoadedDate = DateTime.now();

      debugPrint(
        '✅ Loaded nutrition data - ${_todaysMealLog?.totalCalories.toStringAsFixed(0)} cals today',
      );
    } catch (e) {
      _errorMessage =
          'Failed to load nutrition data: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load nutrition data error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if day changed and refresh data if needed
  /// Called when app resumes from background
  void checkAndRefreshIfDayChanged() {
    final today = DateTime.now();
    if (_lastLoadedDate != null &&
        (_lastLoadedDate!.day != today.day ||
            _lastLoadedDate!.month != today.month ||
            _lastLoadedDate!.year != today.year)) {
      debugPrint('📅 Day changed - reloading nutrition data');
      loadTodaysData();
      // Always reload history when day changes to update "yesterday" correctly
      loadNutritionHistory();
    }
  }

  /// Load nutrition history for past days
  Future<void> loadNutritionHistory() async {
    _isLoadingHistory = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final startDate = _getHistoryStartDate(now);

      _nutritionHistory = await _nutritionRepository.getMealLogs(
        startDate: startDate,
        endDate: now.subtract(const Duration(days: 1)), // Exclude today
      );

      // Sort by date descending (most recent first)
      _nutritionHistory.sort((a, b) => b.date.compareTo(a.date));

      debugPrint(
        '✅ Loaded ${_nutritionHistory.length} days of nutrition history',
      );
    } catch (e) {
      debugPrint('Load nutrition history error: $e');
    } finally {
      _isLoadingHistory = false;
      notifyListeners();
    }
  }

  /// Get history start date based on filter
  DateTime _getHistoryStartDate(DateTime now) {
    switch (_historyFilter) {
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return now.subtract(const Duration(days: 30));
      case '3months':
        return now.subtract(const Duration(days: 90));
      default:
        return now.subtract(const Duration(days: 7));
    }
  }

  /// Set history filter and reload
  void setHistoryFilter(String filter) {
    if (_historyFilter != filter) {
      _historyFilter = filter;
      loadNutritionHistory();
    }
  }

  /// Load food categories
  Future<void> loadCategories() async {
    try {
      _categories = await _nutritionRepository.getFoodCategories();
      notifyListeners();
    } catch (e) {
      debugPrint('Load categories error: $e');
    }
  }

  /// Search for foods
  Future<void> searchFoods(String query, {String? category}) async {
    if (query.length < 2) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    try {
      _searchResults = await _nutritionRepository.searchFoods(
        query,
        category: category,
      );
    } catch (e) {
      debugPrint('Search foods error: $e');
      _searchResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Clear search results
  void clearSearch() {
    _searchResults = [];
    notifyListeners();
  }

  /// Get food by barcode
  Future<FoodTemplate?> getFoodByBarcode(String barcode) async {
    try {
      return await _nutritionRepository.getFoodByBarcode(barcode);
    } catch (e) {
      debugPrint('Get food by barcode error: $e');
      return null;
    }
  }

  /// Quick add food to a meal
  Future<bool> quickAddFood({
    required int mealEntryId,
    required int foodTemplateId,
    double quantity = 1,
  }) async {
    _isAddingFood = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _nutritionRepository.quickAddFood(
        mealEntryId: mealEntryId,
        foodTemplateId: foodTemplateId,
        quantity: quantity,
      );

      // Reload today's data to get updated totals
      await loadTodaysData();

      debugPrint('✅ Added food to meal entry $mealEntryId');
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to add food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Add food error: $e');
      return false;
    } finally {
      _isAddingFood = false;
      notifyListeners();
    }
  }

  /// Add custom food item
  Future<bool> addCustomFood({
    required int mealEntryId,
    required String name,
    required double calories,
    required double protein,
    required double carbohydrates,
    required double fat,
    double quantity = 1,
    double servingSize = 100,
    String servingUnit = 'g',
  }) async {
    _isAddingFood = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final foodItem = FoodItem(
        id: 0,
        mealEntryId: mealEntryId,
        name: name,
        quantity: quantity,
        servingSize: servingSize,
        servingUnit: servingUnit,
        calories: calories * quantity,
        protein: protein * quantity,
        carbohydrates: carbohydrates * quantity,
        fat: fat * quantity,
        createdAt: DateTime.now(),
      );

      await _nutritionRepository.addFoodItem(foodItem);
      await loadTodaysData();

      debugPrint('✅ Added custom food: $name');
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to add food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Add custom food error: $e');
      _isAddingFood = false;
      notifyListeners();
      return false;
    }
  }

  /// Update food item quantity
  Future<bool> updateFoodQuantity(int foodItemId, double quantity) async {
    try {
      await _nutritionRepository.updateFoodQuantity(foodItemId, quantity);
      await loadTodaysData();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to update quantity: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update food quantity error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Delete food item
  Future<bool> deleteFoodItem(int foodItemId) async {
    try {
      await _nutritionRepository.deleteFoodItem(foodItemId);
      await loadTodaysData();
      debugPrint('✅ Deleted food item $foodItemId');
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to delete food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete food error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get AI-powered food alternatives for a food item
  Future<List<FoodAlternative>> getFoodAlternatives(FoodItem food) async {
    try {
      // Calculate per-serving values for the request
      final perServingCalories = food.calories / food.quantity;
      final perServingProtein = food.protein / food.quantity;
      final perServingCarbs = food.carbohydrates / food.quantity;
      final perServingFat = food.fat / food.quantity;

      return await _nutritionRepository.getFoodAlternatives(
        foodName: food.name,
        calories: perServingCalories,
        protein: perServingProtein,
        carbohydrates: perServingCarbs,
        fat: perServingFat,
      );
    } catch (e) {
      debugPrint('Get food alternatives error: $e');
      return [];
    }
  }

  /// Replace a food item with an alternative
  Future<bool> replaceFoodWithAlternative(
    FoodItem oldFood,
    FoodAlternative alternative,
  ) async {
    try {
      // Delete the old food
      await _nutritionRepository.deleteFoodItem(oldFood.id);

      // Add the new food
      final newFoodItem = FoodItem(
        id: 0,
        mealEntryId: oldFood.mealEntryId,
        name: alternative.name,
        quantity: 1,
        servingSize: alternative.servingSize,
        servingUnit: alternative.servingUnit,
        calories: alternative.calories,
        protein: alternative.protein,
        carbohydrates: alternative.carbohydrates,
        fat: alternative.fat,
        createdAt: DateTime.now(),
      );

      await _nutritionRepository.addFoodItem(newFoodItem);
      await loadTodaysData();

      debugPrint('✅ Replaced ${oldFood.name} with ${alternative.name}');
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to replace food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Replace food error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Mark meal as consumed
  Future<bool> markMealAsConsumed(
    int mealEntryId, {
    bool isConsumed = true,
  }) async {
    try {
      await _nutritionRepository.markMealAsConsumed(
        mealEntryId,
        isConsumed: isConsumed,
        consumedAt: DateTime.now(),
      );
      await loadTodaysData();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to update meal: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Mark meal consumed error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Update water intake
  Future<bool> updateWaterIntake(double waterMl) async {
    if (_todaysMealLog == null) return false;

    try {
      await _nutritionRepository.updateWaterIntake(_todaysMealLog!.id, waterMl);
      await loadTodaysData();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to update water: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update water error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Add water (incremental)
  Future<bool> addWater(double amountMl) async {
    final currentWater = _todaysMealLog?.waterIntake ?? 0;
    return updateWaterIntake(currentWater + amountMl);
  }

  /// Get meal entry by type from today's log
  MealEntry? getMealEntryByType(String mealType) {
    return _todaysMealLog?.mealEntries?.firstWhere(
      (e) => e.mealType == mealType,
      orElse:
          () => MealEntry(
            id: 0,
            mealLogId: _todaysMealLog?.id ?? 0,
            mealType: mealType,
            createdAt: DateTime.now(),
          ),
    );
  }

  /// Get calories remaining today
  double get caloriesRemaining {
    if (_activeGoal == null || _todaysMealLog == null) return 0;
    return _activeGoal!.dailyCalories - _todaysMealLog!.totalCalories;
  }

  /// Get protein remaining today
  double get proteinRemaining {
    if (_activeGoal == null || _todaysMealLog == null) return 0;
    return _activeGoal!.dailyProtein - _todaysMealLog!.totalProtein;
  }

  /// Get calorie progress percentage
  double get calorieProgressPercentage {
    if (_activeGoal == null ||
        _todaysMealLog == null ||
        _activeGoal!.dailyCalories == 0) {
      return 0;
    }
    return (_todaysMealLog!.totalCalories / _activeGoal!.dailyCalories * 100)
        .clamp(0, 150);
  }

  /// Get protein progress percentage
  double get proteinProgressPercentage {
    if (_activeGoal == null ||
        _todaysMealLog == null ||
        _activeGoal!.dailyProtein == 0) {
      return 0;
    }
    return (_todaysMealLog!.totalProtein / _activeGoal!.dailyProtein * 100)
        .clamp(0, 150);
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Update nutrition goal
  Future<bool> updateNutritionGoal({
    required double dailyCalories,
    required double dailyProtein,
    required double dailyCarbohydrates,
    required double dailyFat,
    double? dailyFiber,
    double? dailyWater,
  }) async {
    if (_activeGoal == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updatedGoal = _activeGoal!.copyWith(
        dailyCalories: dailyCalories,
        dailyProtein: dailyProtein,
        dailyCarbohydrates: dailyCarbohydrates,
        dailyFat: dailyFat,
        dailyFiber: dailyFiber,
        dailyWater: dailyWater,
        updatedAt: DateTime.now(),
      );

      await _nutritionRepository.updateNutritionGoal(
        _activeGoal!.id,
        updatedGoal,
      );
      _activeGoal = updatedGoal;

      debugPrint(
        '✅ Updated nutrition goal: ${dailyCalories.toStringAsFixed(0)} cals',
      );
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to update goals: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update nutrition goal error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new nutrition goal
  Future<bool> createNutritionGoal({
    String? name,
    required double dailyCalories,
    required double dailyProtein,
    required double dailyCarbohydrates,
    required double dailyFat,
    double? dailyFiber,
    double? dailyWater,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newGoal = NutritionGoal(
        id: 0,
        userId: 0, // Will be set by API
        name: name ?? 'My Goals',
        dailyCalories: dailyCalories,
        dailyProtein: dailyProtein,
        dailyCarbohydrates: dailyCarbohydrates,
        dailyFat: dailyFat,
        dailyFiber: dailyFiber,
        dailyWater: dailyWater,
        isActive: true,
        createdAt: DateTime.now(),
      );

      _activeGoal = await _nutritionRepository.createNutritionGoal(newGoal);

      debugPrint(
        '✅ Created nutrition goal: ${dailyCalories.toStringAsFixed(0)} cals',
      );
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to create goals: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create nutrition goal error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a custom food template
  Future<FoodTemplate?> createCustomFoodTemplate({
    required String name,
    String? brand,
    String? category,
    required double servingSize,
    required String servingUnit,
    required double calories,
    required double protein,
    required double carbohydrates,
    required double fat,
    double? fiber,
    double? sugar,
    double? sodium,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final template = FoodTemplate(
        id: 0, // Will be set by API
        name: name,
        brand: brand,
        category: category ?? 'Custom',
        servingSize: servingSize,
        servingUnit: servingUnit,
        calories: calories,
        protein: protein,
        carbohydrates: carbohydrates,
        fat: fat,
        fiber: fiber,
        sugar: sugar,
        sodium: sodium,
        isCustom: true,
        createdAt: DateTime.now(),
      );

      final created = await _nutritionRepository.createFoodTemplate(template);
      debugPrint('✅ Created custom food template: $name');
      return created;
    } catch (e) {
      _errorMessage =
          'Failed to create food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create custom food template error: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create custom food template and add to meal
  Future<bool> createAndAddCustomFood({
    required int mealEntryId,
    required String name,
    String? brand,
    String? category,
    required double servingSize,
    required String servingUnit,
    required double calories,
    required double protein,
    required double carbohydrates,
    required double fat,
    double? fiber,
    double? sugar,
    double? sodium,
    double quantity = 1,
  }) async {
    // First create the template
    final template = await createCustomFoodTemplate(
      name: name,
      brand: brand,
      category: category,
      servingSize: servingSize,
      servingUnit: servingUnit,
      calories: calories,
      protein: protein,
      carbohydrates: carbohydrates,
      fat: fat,
      fiber: fiber,
      sugar: sugar,
      sodium: sodium,
    );

    if (template == null) return false;

    // Then add it to the meal
    return quickAddFood(
      mealEntryId: mealEntryId,
      foodTemplateId: template.id,
      quantity: quantity,
    );
  }

  /// Clear all food for today's meal log
  Future<bool> clearAllFood() async {
    if (_todaysMealLog == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _nutritionRepository.clearAllFood(_todaysMealLog!.id);
      await loadTodaysData();
      debugPrint('✅ Cleared all food for today');
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to clear food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Clear all food error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear all data (called on logout)
  void clear() {
    _todaysMealLog = null;
    _activeGoal = null;
    _todaysProgress = null;
    _recentFoods = [];
    _searchResults = [];
    _categories = [];
    _streakInfo = null;
    _errorMessage = null;
    _isLoading = false;
    _isSearching = false;
    _isAddingFood = false;
    notifyListeners();
    debugPrint('🧹 NutritionProvider cleared');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
