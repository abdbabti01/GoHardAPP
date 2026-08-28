import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models/food_template.dart';
import '../data/models/meal_log.dart';
import '../data/models/meal_entry.dart';
import '../data/models/food_item.dart';
import '../data/models/nutrition_goal.dart';
import '../data/models/nutrition_summary.dart';
import '../data/models/daily_nutrition_progress.dart';
import '../data/repositories/nutrition_repository.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/user_session_epoch.dart';

export '../data/repositories/nutrition_repository.dart'
    show
        FoodAlternative,
        CalculatedNutrition,
        UserMetricsSummary,
        ActivityLevelOption,
        OfflineNutritionException,
        MissingMetricsException,
        NutritionDashboardData;

/// Provider for nutrition tracking
class NutritionProvider extends ChangeNotifier {
  final NutritionRepository _nutritionRepository;

  /// Shared app-wide session-identity service. Every async method below
  /// captures a token before its first await and rechecks
  /// `_sessionEpoch.isCurrent(token)` after every await before touching any
  /// field or calling notifyListeners() - this drops any result that
  /// resolves after the session that requested it has ended (logout, or a
  /// different user logging in), instead of writing it into the shared
  /// provider instance the next session also uses. This does NOT protect
  /// NutritionRepository's own local Isar writes or background sync pushes
  /// - see the repository/SyncService follow-up notes referenced from the
  /// investigation this PR is based on.
  final UserSessionEpoch _sessionEpoch;
  final ConnectivityService? _connectivity;

  // State
  MealLog? _todaysMealLog;
  NutritionGoal? _activeGoal;
  NutritionProgress? _todaysProgress;
  DailyNutritionProgress? _dailyProgress;
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

  /// Monotonically increasing id for the most recently *requested*
  /// [loadNutritionHistory] call. Each call captures its own value at
  /// start; only the call whose captured value still equals this field when
  /// its await resolves is allowed to commit `_nutritionHistory`/
  /// `_isLoadingHistory`/`_errorMessage` - this is what makes the LATEST
  /// requested filter always win regardless of resolution order (A -> B ->
  /// A resolves correctly even though the first and third requests can
  /// share the same filter string, which is why generation - not the
  /// filter value alone - is the source of truth here). Bumped by [clear]
  /// too, so an in-flight history request is invalidated independently of
  /// the session epoch as well.
  int _historyRequestGeneration = 0;

  StreamSubscription<bool>? _connectivitySubscription;

  NutritionProvider(
    this._nutritionRepository,
    this._sessionEpoch, [
    this._connectivity,
  ]) {
    // Listen for connectivity changes and refresh when going online. This
    // callback can fire at any point in the app's lifetime, including
    // during a logged-out gap between one user's logout and the next
    // user's login - capture a token fresh on every invocation and skip
    // entirely if there is no active session, so a connectivity flap while
    // logged out can never dispatch a nutrition load for nobody.
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
      final token = _sessionEpoch.capture();
      if (token == null) return;
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
  DailyNutritionProgress? get dailyProgress => _dailyProgress;
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

  /// Load today's meal log, active goal, and progress.
  ///
  /// Session-epoch guarded: [token] is captured before any await, and
  /// re-checked after the await (including inside catch/finally) before
  /// touching any field or calling notifyListeners(). If the session that
  /// requested this load has since ended - logout, or a different user
  /// logging in - the response is dropped silently.
  Future<void> loadTodaysData() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Load in parallel
      final results = await Future.wait([
        _nutritionRepository.getTodaysMealLog(),
        _nutritionRepository.getNutritionDashboard(),
        _nutritionRepository.getStreak(),
      ]);
      if (!_sessionEpoch.isCurrent(token)) return;

      _todaysMealLog = results[0] as MealLog;
      final dashboardData = results[1] as NutritionDashboardData;
      _activeGoal = dashboardData.goal;
      _dailyProgress = dashboardData.progress;
      _streakInfo = results[2] as StreakInfo;

      // Track when data was loaded for day change detection
      _lastLoadedDate = DateTime.now();

      debugPrint(
        '✅ Loaded nutrition data - planned: ${_dailyProgress?.plannedCalories.toStringAsFixed(0)}, consumed: ${_dailyProgress?.consumedCalories.toStringAsFixed(0)} cals',
      );
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage =
          'Failed to load nutrition data: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load nutrition data error: $e');
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
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

  /// Load nutrition history for past days.
  ///
  /// Guarded by BOTH session identity and a monotonically increasing
  /// request generation, captured together before the first await:
  /// - [token] guards against the session ending or a different user
  ///   logging in while the request is in flight.
  /// - [requestGeneration] guards against the SAME user switching the
  ///   history filter (via [setHistoryFilter]) to a different value before
  ///   this request resolves - a case the session token alone cannot
  ///   catch, since the session never changes. Only the request holding
  ///   the CURRENT generation may commit, so the most recently *requested*
  ///   filter always wins regardless of resolution order (A -> B -> A
  ///   resolves correctly, since the first and third requests would share
  ///   a filter string but never a generation).
  Future<void> loadNutritionHistory() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    final requestGeneration = ++_historyRequestGeneration;
    final requestedFilter = _historyFilter;

    bool ownsRequest() =>
        _sessionEpoch.isCurrent(token) &&
        requestGeneration == _historyRequestGeneration &&
        requestedFilter == _historyFilter;

    _isLoadingHistory = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      final startDate = _getHistoryStartDate(now);

      final results = await _nutritionRepository.getMealLogs(
        startDate: startDate,
        endDate: now.subtract(const Duration(days: 1)), // Exclude today
      );
      if (!ownsRequest()) return;

      // Sort by date descending (most recent first)
      results.sort((a, b) => b.date.compareTo(a.date));
      _nutritionHistory = results;

      debugPrint(
        '✅ Loaded ${_nutritionHistory.length} days of nutrition history',
      );
    } catch (e) {
      if (!ownsRequest()) return;
      debugPrint('Load nutrition history error: $e');
    } finally {
      if (ownsRequest()) {
        _isLoadingHistory = false;
        notifyListeners();
      }
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

  /// Load food categories. Session-epoch guarded like [loadTodaysData].
  Future<void> loadCategories() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    try {
      final result = await _nutritionRepository.getFoodCategories();
      if (!_sessionEpoch.isCurrent(token)) return;
      _categories = result;
      notifyListeners();
    } catch (e) {
      debugPrint('Load categories error: $e');
    }
  }

  /// Search for foods. Session-epoch guarded like [loadTodaysData]; the
  /// short-query early return below is a purely synchronous local-state
  /// clear (no repository call, so no staleness is possible) and is left
  /// unguarded.
  Future<void> searchFoods(String query, {String? category}) async {
    if (query.length < 2) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return;

    _isSearching = true;
    notifyListeners();

    try {
      final results = await _nutritionRepository.searchFoods(
        query,
        category: category,
      );
      if (!_sessionEpoch.isCurrent(token)) return;
      _searchResults = results;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      debugPrint('Search foods error: $e');
      _searchResults = [];
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  /// Clear search results
  void clearSearch() {
    _searchResults = [];
    notifyListeners();
  }

  /// Get food by barcode. Session-epoch guarded: a stale result is dropped
  /// (returns null) rather than handed back to a caller whose session has
  /// since ended.
  Future<FoodTemplate?> getFoodByBarcode(String barcode) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;

    try {
      final result = await _nutritionRepository.getFoodByBarcode(barcode);
      if (!_sessionEpoch.isCurrent(token)) return null;
      return result;
    } catch (e) {
      debugPrint('Get food by barcode error: $e');
      return null;
    }
  }

  /// Quick add food to a meal.
  ///
  /// The outer [token] is captured before the mutation and rechecked
  /// immediately after it - if the session ended during the mutation
  /// itself, the nested reload below never starts. [loadTodaysData]
  /// independently captures and validates its own token; the recheck after
  /// awaiting it here only guards this method's own remaining state
  /// (`_isAddingFood`/the returned bool) against a session change that
  /// happened during the nested reload.
  Future<bool> quickAddFood({
    required int mealEntryId,
    required int foodTemplateId,
    double quantity = 1,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    _isAddingFood = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _nutritionRepository.quickAddFood(
        mealEntryId: mealEntryId,
        foodTemplateId: foodTemplateId,
        quantity: quantity,
      );
      if (!_sessionEpoch.isCurrent(token)) return false;

      // Reload today's data to get updated totals
      await loadTodaysData();
      if (!_sessionEpoch.isCurrent(token)) return false;

      debugPrint('✅ Added food to meal entry $mealEntryId');
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to add food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Add food error: $e');
      return false;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isAddingFood = false;
        notifyListeners();
      }
    }
  }

  /// Add custom food item. Same outer/nested ownership guarding as
  /// [quickAddFood].
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
    final token = _sessionEpoch.capture();
    if (token == null) return false;

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
      if (!_sessionEpoch.isCurrent(token)) return false;

      await loadTodaysData();
      if (!_sessionEpoch.isCurrent(token)) return false;

      debugPrint('✅ Added custom food: $name');
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to add food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Add custom food error: $e');
      return false;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isAddingFood = false;
        notifyListeners();
      }
    }
  }

  /// Update food item quantity. Same outer/nested ownership guarding as
  /// [quickAddFood]; no loading flag of its own, matching prior behavior.
  Future<bool> updateFoodQuantity(int foodItemId, double quantity) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      await _nutritionRepository.updateFoodQuantity(foodItemId, quantity);
      if (!_sessionEpoch.isCurrent(token)) return false;

      await loadTodaysData();
      if (!_sessionEpoch.isCurrent(token)) return false;

      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to update quantity: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update food quantity error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Delete food item. Same outer/nested ownership guarding as
  /// [quickAddFood]; no loading flag of its own, matching prior behavior.
  Future<bool> deleteFoodItem(int foodItemId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      await _nutritionRepository.deleteFoodItem(foodItemId);
      if (!_sessionEpoch.isCurrent(token)) return false;

      await loadTodaysData();
      if (!_sessionEpoch.isCurrent(token)) return false;

      debugPrint('✅ Deleted food item $foodItemId');
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to delete food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete food error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get AI-powered food alternatives for a food item. Session-epoch
  /// guarded: a stale result is dropped (returns empty list).
  Future<List<FoodAlternative>> getFoodAlternatives(FoodItem food) async {
    final token = _sessionEpoch.capture();
    if (token == null) return [];

    try {
      // Calculate per-serving values for the request
      final perServingCalories = food.calories / food.quantity;
      final perServingProtein = food.protein / food.quantity;
      final perServingCarbs = food.carbohydrates / food.quantity;
      final perServingFat = food.fat / food.quantity;

      final result = await _nutritionRepository.getFoodAlternatives(
        foodName: food.name,
        calories: perServingCalories,
        protein: perServingProtein,
        carbohydrates: perServingCarbs,
        fat: perServingFat,
      );
      if (!_sessionEpoch.isCurrent(token)) return [];
      return result;
    } catch (e) {
      debugPrint('Get food alternatives error: $e');
      return [];
    }
  }

  /// Replace a food item with an alternative. Rechecks ownership after
  /// EVERY await, including between the delete and the add - both are
  /// independent repository operations belonging to the same original
  /// session.
  Future<bool> replaceFoodWithAlternative(
    FoodItem oldFood,
    FoodAlternative alternative,
  ) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      // Delete the old food
      await _nutritionRepository.deleteFoodItem(oldFood.id);
      if (!_sessionEpoch.isCurrent(token)) return false;

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
      if (!_sessionEpoch.isCurrent(token)) return false;

      await loadTodaysData();
      if (!_sessionEpoch.isCurrent(token)) return false;

      debugPrint('✅ Replaced ${oldFood.name} with ${alternative.name}');
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to replace food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Replace food error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Mark meal as consumed. Same outer/nested ownership guarding as
  /// [quickAddFood]; no loading flag of its own, matching prior behavior.
  Future<bool> markMealAsConsumed(
    int mealEntryId, {
    bool isConsumed = true,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      await _nutritionRepository.markMealAsConsumed(
        mealEntryId,
        isConsumed: isConsumed,
        consumedAt: DateTime.now(),
      );
      if (!_sessionEpoch.isCurrent(token)) return false;

      await loadTodaysData();
      if (!_sessionEpoch.isCurrent(token)) return false;

      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to update meal: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Mark meal consumed error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Update water intake. Same outer/nested ownership guarding as
  /// [quickAddFood]; no loading flag of its own, matching prior behavior.
  Future<bool> updateWaterIntake(double waterMl) async {
    if (_todaysMealLog == null) return false;

    final token = _sessionEpoch.capture();
    if (token == null) return false;

    try {
      await _nutritionRepository.updateWaterIntake(_todaysMealLog!.id, waterMl);
      if (!_sessionEpoch.isCurrent(token)) return false;

      await loadTodaysData();
      if (!_sessionEpoch.isCurrent(token)) return false;

      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
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

  /// Get calories remaining today (goal minus consumed, not planned)
  double get caloriesRemaining {
    if (_activeGoal == null || _todaysMealLog == null) return 0;
    return _activeGoal!.dailyCalories - _todaysMealLog!.consumedCalories;
  }

  /// Get protein remaining today (goal minus consumed, not planned)
  double get proteinRemaining {
    if (_activeGoal == null || _todaysMealLog == null) return 0;
    return _activeGoal!.dailyProtein - _todaysMealLog!.consumedProtein;
  }

  /// Get calorie progress percentage (consumed, not planned)
  double get calorieProgressPercentage {
    if (_activeGoal == null ||
        _todaysMealLog == null ||
        _activeGoal!.dailyCalories == 0) {
      return 0;
    }
    return (_todaysMealLog!.consumedCalories / _activeGoal!.dailyCalories * 100)
        .clamp(0, 150);
  }

  /// Get protein progress percentage (consumed, not planned)
  double get proteinProgressPercentage {
    if (_activeGoal == null ||
        _todaysMealLog == null ||
        _activeGoal!.dailyProtein == 0) {
      return 0;
    }
    return (_todaysMealLog!.consumedProtein / _activeGoal!.dailyProtein * 100)
        .clamp(0, 150);
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Update nutrition goal. A stale completion can never overwrite
  /// `_activeGoal` with User A's edit once the session has moved on -
  /// there is no nested reload here, so the post-await check on the single
  /// repository call is the only guard this method needs.
  Future<bool> updateNutritionGoal({
    required double dailyCalories,
    required double dailyProtein,
    required double dailyCarbohydrates,
    required double dailyFat,
    double? dailyFiber,
    double? dailyWater,
  }) async {
    if (_activeGoal == null) return false;

    final token = _sessionEpoch.capture();
    if (token == null) return false;

    final currentGoal = _activeGoal!;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updatedGoal = currentGoal.copyWith(
        dailyCalories: dailyCalories,
        dailyProtein: dailyProtein,
        dailyCarbohydrates: dailyCarbohydrates,
        dailyFat: dailyFat,
        dailyFiber: dailyFiber,
        dailyWater: dailyWater,
        updatedAt: DateTime.now(),
      );

      await _nutritionRepository.updateNutritionGoal(
        currentGoal.id,
        updatedGoal,
      );
      if (!_sessionEpoch.isCurrent(token)) return false;
      _activeGoal = updatedGoal;

      debugPrint(
        '✅ Updated nutrition goal: ${dailyCalories.toStringAsFixed(0)} cals',
      );
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to update goals: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update nutrition goal error: $e');
      return false;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create a new nutrition goal. Same single-await ownership guarding as
  /// [updateNutritionGoal].
  Future<bool> createNutritionGoal({
    String? name,
    required double dailyCalories,
    required double dailyProtein,
    required double dailyCarbohydrates,
    required double dailyFat,
    double? dailyFiber,
    double? dailyWater,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

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

      final created = await _nutritionRepository.createNutritionGoal(newGoal);
      if (!_sessionEpoch.isCurrent(token)) return false;
      _activeGoal = created;

      debugPrint(
        '✅ Created nutrition goal: ${dailyCalories.toStringAsFixed(0)} cals',
      );
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to create goals: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create nutrition goal error: $e');
      return false;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create a custom food template. Session-epoch guarded like
  /// [updateNutritionGoal]; no field is written on success (the created
  /// template is returned to the caller), so only the loading/error flags
  /// and the returned value need guarding.
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
    final token = _sessionEpoch.capture();
    if (token == null) return null;

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
      if (!_sessionEpoch.isCurrent(token)) return null;

      debugPrint('✅ Created custom food template: $name');
      return created;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to create food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create custom food template error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create custom food template and add to meal. Both nested calls
  /// ([createCustomFoodTemplate] and [quickAddFood]) are independently
  /// session-epoch guarded; this wrapper additionally rechecks ownership
  /// between them so a session that ended while the template was being
  /// created never goes on to call the repository again via [quickAddFood].
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
    final token = _sessionEpoch.capture();
    if (token == null) return false;

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
    if (!_sessionEpoch.isCurrent(token)) return false;

    if (template == null) return false;

    // Then add it to the meal
    return quickAddFood(
      mealEntryId: mealEntryId,
      foodTemplateId: template.id,
      quantity: quantity,
    );
  }

  /// Clear all food for today's meal log. Same outer/nested ownership
  /// guarding as [quickAddFood].
  Future<bool> clearAllFood() async {
    if (_todaysMealLog == null) return false;

    final token = _sessionEpoch.capture();
    if (token == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _nutritionRepository.clearAllFood(_todaysMealLog!.id);
      if (!_sessionEpoch.isCurrent(token)) return false;

      await loadTodaysData();
      if (!_sessionEpoch.isCurrent(token)) return false;

      debugPrint('✅ Cleared all food for today');
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to clear food: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Clear all food error: $e');
      return false;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Calculate personalized nutrition targets from user metrics and goal.
  /// No field is written on success (the result is returned to the
  /// caller), so only the loading/error flags and the returned value need
  /// guarding.
  Future<CalculatedNutrition?> calculateNutritionFromMetrics({
    required String goalType,
    double? targetWeightChange,
    int? timeframeWeeks,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _nutritionRepository.calculateNutritionFromMetrics(
        goalType: goalType,
        targetWeightChange: targetWeightChange,
        timeframeWeeks: timeframeWeeks,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      if (result != null) {
        debugPrint(
          '✅ Calculated nutrition: ${result.dailyCalories.toStringAsFixed(0)} cals, ${result.dailyProtein.toStringAsFixed(0)}g protein',
        );
      }

      return result;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to calculate nutrition: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Calculate nutrition error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Calculate and save nutrition targets as active goal.
  /// Throws [OfflineNutritionException] if offline.
  ///
  /// [OfflineNutritionException]/[MissingMetricsException] are rethrown
  /// unconditionally regardless of session state - they touch no provider
  /// field, and the caller (not this provider) is responsible for handling
  /// them, exactly like before this guarding was added. The nested
  /// [loadTodaysData] reload is only started if the session is still
  /// current after the calculate-and-save call succeeds.
  Future<CalculatedNutrition?> calculateAndSaveNutrition({
    required String goalType,
    double? targetWeightChange,
    int? timeframeWeeks,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _nutritionRepository.calculateAndSaveNutrition(
        goalType: goalType,
        targetWeightChange: targetWeightChange,
        timeframeWeeks: timeframeWeeks,
      );
      if (!_sessionEpoch.isCurrent(token)) return null;

      if (result != null) {
        // Reload nutrition data to get updated goal
        await loadTodaysData();
        if (!_sessionEpoch.isCurrent(token)) return null;
        debugPrint(
          '✅ Calculated and saved nutrition: ${result.dailyCalories.toStringAsFixed(0)} cals',
        );
      }

      return result;
    } on OfflineNutritionException {
      // Re-throw offline exception so caller can handle it specifically
      rethrow;
    } on MissingMetricsException {
      // Re-throw missing metrics exception so caller can guide user
      rethrow;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage =
          'Failed to calculate and save nutrition: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Calculate and save nutrition error: $e');
      return null;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Get available activity levels. Session-epoch guarded: a stale result
  /// is dropped (returns empty list).
  Future<List<ActivityLevelOption>> getActivityLevels() async {
    final token = _sessionEpoch.capture();
    if (token == null) return [];

    final result = await _nutritionRepository.getActivityLevels();
    if (!_sessionEpoch.isCurrent(token)) return [];
    return result;
  }

  /// Clear all data (called on logout). Immediate and synchronous - no
  /// await here, so nothing can race this method itself. Also bumps
  /// [_historyRequestGeneration] so any in-flight [loadNutritionHistory]
  /// request is invalidated independently of the session epoch (this
  /// remains a complete invalidation even if clear() is ever invoked
  /// without a preceding UserSessionEpoch.invalidate() call).
  void clear() {
    _todaysMealLog = null;
    _activeGoal = null;
    _todaysProgress = null;
    _dailyProgress = null;
    _recentFoods = [];
    _searchResults = [];
    _categories = [];
    _streakInfo = null;
    _errorMessage = null;
    _isLoading = false;
    _isSearching = false;
    _isAddingFood = false;
    _lastLoadedDate = null;
    _nutritionHistory = [];
    _isLoadingHistory = false;
    _historyRequestGeneration++;
    notifyListeners();
    debugPrint('🧹 NutritionProvider cleared');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
