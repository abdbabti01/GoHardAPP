import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../data/models/meal_entry.dart';
import '../../../data/models/meal_log.dart';
import '../../../data/models/food_item.dart';
import '../../widgets/nutrition/calorie_ring_widget.dart';
import '../../widgets/nutrition/macro_progress_bar.dart';
import '../../widgets/nutrition/meal_card_widget.dart';
import 'food_search_screen.dart';

/// Nutrition dashboard screen - works as a tab in the main dashboard
class NutritionDashboardScreen extends StatefulWidget {
  const NutritionDashboardScreen({super.key});

  @override
  State<NutritionDashboardScreen> createState() =>
      _NutritionDashboardScreenState();
}

class _NutritionDashboardScreenState extends State<NutritionDashboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NutritionProvider>();
      provider.loadTodaysData();
      provider.loadNutritionHistory();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<NutritionProvider>().checkAndRefreshIfDayChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NutritionProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.todaysMealLog == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.errorMessage != null && provider.todaysMealLog == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  provider.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => provider.loadTodaysData(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadTodaysData(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Calorie summary card
                _buildCalorieSummaryCard(context, provider),
                const SizedBox(height: 16),

                // Macro progress bars
                _buildMacroProgress(context, provider),
                const SizedBox(height: 24),

                // Water intake
                _buildWaterSection(context, provider),
                const SizedBox(height: 24),

                // Meals section header with clear button
                Row(
                  children: [
                    Text(
                      "Today's Meals",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (_hasFoodItems(provider))
                      TextButton.icon(
                        onPressed: () => _showClearAllDialog(context, provider),
                        icon: Icon(
                          Icons.delete_sweep,
                          size: 18,
                          color: context.textSecondary,
                        ),
                        label: Text(
                          'Clear All',
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Meal cards for each meal type
                for (final mealType in MealTypes.all) ...[
                  MealCardWidget(
                    mealType: mealType,
                    mealEntry: provider.getMealEntryByType(mealType),
                    onAddFood: () => _navigateToFoodSearch(context, mealType),
                    onMealTap: () {
                      // TODO: Navigate to meal detail
                    },
                    onEditFood: (food) => _showEditFoodDialog(context, food),
                    onDeleteFood: (food) => _deleteFood(context, food),
                    onSuggestAlternative:
                        (food) => _suggestAlternative(context, food),
                    onMarkConsumed:
                        () => _markMealConsumed(
                          context,
                          provider.getMealEntryByType(mealType),
                        ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Streak info
                if (provider.streakInfo != null) ...[
                  const SizedBox(height: 12),
                  _buildStreakCard(context, provider),
                ],

                const SizedBox(height: 24),

                // History section
                _buildHistorySection(context, provider),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalorieSummaryCard(
    BuildContext context,
    NutritionProvider provider,
  ) {
    final mealLog = provider.todaysMealLog;
    final goal = provider.activeGoal?.dailyCalories ?? 2000;
    final planned = mealLog?.plannedCalories ?? 0;
    final consumed = mealLog?.consumedCalories ?? 0;
    final remaining = goal - planned;
    final isOverBudget = planned > goal;
    final isOverConsumed = consumed > goal;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isOverBudget ? Colors.red.withValues(alpha: 0.5) : context.border,
          width: isOverBudget ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Calorie ring - shows planned vs goal
              CalorieRingWidget(consumed: planned, goal: goal, size: 120),
              const SizedBox(width: 24),
              // Stats
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calories',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCalorieRow(
                      context,
                      'Goal',
                      goal.toStringAsFixed(0),
                      Icons.track_changes,
                      Colors.blue,
                    ),
                    const SizedBox(height: 8),
                    _buildCalorieRow(
                      context,
                      'Planned',
                      planned.toStringAsFixed(0),
                      Icons.calendar_today,
                      isOverBudget ? Colors.red : Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    _buildCalorieRow(
                      context,
                      'Consumed',
                      consumed.toStringAsFixed(0),
                      Icons.local_fire_department,
                      isOverConsumed ? Colors.red : Colors.green,
                    ),
                    const SizedBox(height: 8),
                    _buildCalorieRow(
                      context,
                      'Remaining',
                      '${remaining >= 0 ? '' : '+'}${remaining.abs().toStringAsFixed(0)}',
                      remaining >= 0
                          ? Icons.flag_outlined
                          : Icons.warning_amber,
                      remaining >= 0 ? Colors.green : Colors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Warning messages
          if (isOverBudget) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Over budget by ${(planned - goal).toStringAsFixed(0)} cal',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isOverConsumed && !isOverBudget) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You\'ve exceeded your goal by ${(consumed - goal).toStringAsFixed(0)} cal',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalorieRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildMacroProgress(BuildContext context, NutritionProvider provider) {
    final mealLog = provider.todaysMealLog;
    final goal = provider.activeGoal;

    // Use planned values (all meals) for macro tracking
    final plannedProtein = mealLog?.plannedProtein ?? 0;
    final plannedCarbs = mealLog?.plannedCarbohydrates ?? 0;
    final plannedFat = mealLog?.plannedFat ?? 0;

    final goalProtein = goal?.dailyProtein ?? 150;
    final goalCarbs = goal?.dailyCarbohydrates ?? 200;
    final goalFat = goal?.dailyFat ?? 65;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Macros',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Planned',
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MacroProgressBar(
            label: 'Protein',
            current: plannedProtein,
            goal: goalProtein,
            color:
                plannedProtein > goalProtein ? Colors.red : Colors.red.shade400,
            unit: 'g',
          ),
          const SizedBox(height: 12),
          MacroProgressBar(
            label: 'Carbs',
            current: plannedCarbs,
            goal: goalCarbs,
            color: plannedCarbs > goalCarbs ? Colors.red : Colors.blue,
            unit: 'g',
          ),
          const SizedBox(height: 12),
          MacroProgressBar(
            label: 'Fat',
            current: plannedFat,
            goal: goalFat,
            color: plannedFat > goalFat ? Colors.red : Colors.amber,
            unit: 'g',
          ),
        ],
      ),
    );
  }

  Widget _buildWaterSection(BuildContext context, NutritionProvider provider) {
    final waterMl = provider.todaysMealLog?.waterIntake ?? 0;
    final goalMl = provider.activeGoal?.dailyWater ?? 2000;
    final percentage = (waterMl / goalMl * 100).clamp(0, 100);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Water',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${waterMl.toStringAsFixed(0)} / ${goalMl.toStringAsFixed(0)} ml',
                style: TextStyle(fontSize: 14, color: context.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 12,
              backgroundColor: context.surfaceHighlight,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildWaterButton(context, provider, 250, '250ml'),
              _buildWaterButton(context, provider, 500, '500ml'),
              _buildWaterButton(context, provider, 750, '750ml'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWaterButton(
    BuildContext context,
    NutritionProvider provider,
    double amount,
    String label,
  ) {
    return OutlinedButton(
      onPressed: () => provider.addWater(amount),
      style: OutlinedButton.styleFrom(side: BorderSide(color: context.border)),
      child: Text(label),
    );
  }

  Widget _buildStreakCard(BuildContext context, NutritionProvider provider) {
    final streak = provider.streakInfo!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orange.withValues(alpha: 0.2),
            Colors.deepOrange.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department,
            size: 40,
            color: Colors.orange,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${streak.currentStreak} Day Streak!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              Text(
                'Longest: ${streak.longestStreak} days',
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(
    BuildContext context,
    NutritionProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with filter dropdown
        Row(
          children: [
            Text(
              'History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: provider.historyFilter,
                  isDense: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: context.textSecondary,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'week', child: Text('Last Week')),
                    DropdownMenuItem(value: 'month', child: Text('Last Month')),
                    DropdownMenuItem(value: '3months', child: Text('3 Months')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      provider.setHistoryFilter(value);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // History list
        if (provider.isLoadingHistory)
          Container(
            padding: const EdgeInsets.all(24),
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (provider.nutritionHistory.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.border),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.history, size: 40, color: context.textTertiary),
                  const SizedBox(height: 8),
                  Text(
                    'No past nutrition logs',
                    style: TextStyle(color: context.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          ...provider.nutritionHistory.map(
            (log) => _buildHistoryDayCard(context, log, provider),
          ),
      ],
    );
  }

  Widget _buildHistoryDayCard(
    BuildContext context,
    MealLog log,
    NutritionProvider provider,
  ) {
    final goal = provider.activeGoal;
    final goalCalories = goal?.dailyCalories ?? 2000;
    final progressPercent = (log.totalCalories / goalCalories * 100).clamp(
      0,
      150,
    );
    final isGoalMet = progressPercent >= 80 && progressPercent <= 110;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Row(
        children: [
          // Date column
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEE, MMM d').format(log.date),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    isGoalMet
                        ? Icons.check_circle
                        : Icons.remove_circle_outline,
                    size: 14,
                    color: isGoalMet ? Colors.green : context.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${progressPercent.toStringAsFixed(0)}% of goal',
                    style: TextStyle(
                      fontSize: 12,
                      color: isGoalMet ? Colors.green : context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // Macros column
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${log.totalCalories.toStringAsFixed(0)} cal',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMiniMacro('P', log.totalProtein, Colors.red.shade400),
                  const SizedBox(width: 8),
                  _buildMiniMacro('C', log.totalCarbohydrates, Colors.blue),
                  const SizedBox(width: 8),
                  _buildMiniMacro('F', log.totalFat, Colors.amber),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMacro(String label, double value, Color color) {
    return Text(
      '$label: ${value.toStringAsFixed(0)}g',
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
    );
  }

  void _navigateToFoodSearch(BuildContext context, String? mealType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FoodSearchScreen(preselectedMealType: mealType),
      ),
    );
  }

  Future<void> _showEditFoodDialog(BuildContext context, FoodItem food) async {
    final provider = context.read<NutritionProvider>();
    final quantityController = TextEditingController(
      text: food.quantity.toStringAsFixed(1),
    );

    final result = await showDialog<double>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Edit ${food.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Serving: ${food.servingSize.toStringAsFixed(0)}${food.servingUnit}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quantity (servings)',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                Text(
                  'Per serving: ${(food.calories / food.quantity).toStringAsFixed(0)} kcal',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final newQuantity = double.tryParse(quantityController.text);
                  if (newQuantity != null && newQuantity > 0) {
                    Navigator.pop(context, newQuantity);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (result != null && result != food.quantity) {
      await provider.updateFoodQuantity(food.id, result);
    }
  }

  Future<void> _deleteFood(BuildContext context, FoodItem food) async {
    final provider = context.read<NutritionProvider>();
    await provider.deleteFoodItem(food.id);
  }

  Future<void> _markMealConsumed(
    BuildContext context,
    MealEntry? mealEntry,
  ) async {
    if (mealEntry == null || mealEntry.id == 0) return;

    final provider = context.read<NutritionProvider>();
    final success = await provider.markMealAsConsumed(mealEntry.id);

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${mealEntry.mealType} marked as eaten'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _suggestAlternative(BuildContext context, FoodItem food) async {
    final provider = context.read<NutritionProvider>();

    // Show loading bottom sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetContext) =>
              _FoodAlternativesSheet(food: food, provider: provider),
    );
  }

  /// Check if there are any food items in today's meals
  bool _hasFoodItems(NutritionProvider provider) {
    final mealLog = provider.todaysMealLog;
    if (mealLog == null || mealLog.mealEntries == null) return false;
    return mealLog.mealEntries!.any(
      (entry) => entry.foodItems != null && entry.foodItems!.isNotEmpty,
    );
  }

  /// Show confirmation dialog to clear all food
  Future<void> _showClearAllDialog(
    BuildContext context,
    NutritionProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear All Food?'),
            content: const Text(
              'This will remove all food items from today\'s meals. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Clear All'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      final success = await provider.clearAllFood();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'All food cleared' : 'Failed to clear food',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }
}

/// Bottom sheet for showing food alternatives
class _FoodAlternativesSheet extends StatefulWidget {
  final FoodItem food;
  final NutritionProvider provider;

  const _FoodAlternativesSheet({required this.food, required this.provider});

  @override
  State<_FoodAlternativesSheet> createState() => _FoodAlternativesSheetState();
}

class _FoodAlternativesSheetState extends State<_FoodAlternativesSheet> {
  List<FoodAlternative>? _alternatives;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlternatives();
  }

  Future<void> _loadAlternatives() async {
    try {
      final alternatives = await widget.provider.getFoodAlternatives(
        widget.food,
      );
      if (mounted) {
        setState(() {
          _alternatives = alternatives;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to get suggestions';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alternatives for',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                        Text(
                          widget.food.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Content
            Expanded(child: _buildContent(context, scrollController)),
          ],
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ScrollController scrollController,
  ) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Finding similar foods...',
              style: TextStyle(color: context.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: context.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadAlternatives();
              },
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_alternatives == null || _alternatives!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No alternatives found',
              style: TextStyle(color: context.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _alternatives!.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final alt = _alternatives![index];
        return _buildAlternativeCard(context, alt);
      },
    );
  }

  Widget _buildAlternativeCard(BuildContext context, FoodAlternative alt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceHighlight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  alt.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ),
              Text(
                '${alt.calories.toStringAsFixed(0)} kcal',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${alt.servingSize.toStringAsFixed(0)}${alt.servingUnit}',
            style: TextStyle(fontSize: 12, color: context.textSecondary),
          ),
          if (alt.reason != null) ...[
            const SizedBox(height: 8),
            Text(
              alt.reason!,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: context.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMacroChip('P', alt.protein, Colors.red),
              const SizedBox(width: 8),
              _buildMacroChip('C', alt.carbohydrates, Colors.blue),
              const SizedBox(width: 8),
              _buildMacroChip('F', alt.fat, Colors.amber),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _replaceFood(context, alt),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Replace'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _replaceFood(BuildContext context, FoodAlternative alt) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final success = await widget.provider.replaceFoodWithAlternative(
      widget.food,
      alt,
    );

    // Close loading dialog
    if (context.mounted) Navigator.pop(context);

    if (success) {
      // Close the alternatives sheet
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Replaced with ${alt.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.provider.errorMessage ?? 'Failed to replace food',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMacroChip(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: ${value.toStringAsFixed(0)}g',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
