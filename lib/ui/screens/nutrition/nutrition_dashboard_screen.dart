import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../data/models/meal_entry.dart';
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

class _NutritionDashboardScreenState extends State<NutritionDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NutritionProvider>().loadTodaysData();
    });
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

        return Stack(
          children: [
            RefreshIndicator(
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

                    // Meals section
                    Text(
                      "Today's Meals",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Meal cards for each meal type
                    for (final mealType in MealTypes.all) ...[
                      MealCardWidget(
                        mealType: mealType,
                        mealEntry: provider.getMealEntryByType(mealType),
                        onAddFood:
                            () => _navigateToFoodSearch(context, mealType),
                        onMealTap: () {
                          // TODO: Navigate to meal detail
                        },
                        onEditFood:
                            (food) => _showEditFoodDialog(context, food),
                        onDeleteFood: (food) => _deleteFood(context, food),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Streak info
                    if (provider.streakInfo != null) ...[
                      const SizedBox(height: 12),
                      _buildStreakCard(context, provider),
                    ],

                    const SizedBox(height: 100), // FAB space
                  ],
                ),
              ),
            ),
            // Floating Action Button
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: 'nutrition_fab',
                onPressed: () => _navigateToFoodSearch(context, null),
                icon: const Icon(Icons.add),
                label: const Text('Log Food'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCalorieSummaryCard(
    BuildContext context,
    NutritionProvider provider,
  ) {
    final consumed = provider.todaysMealLog?.totalCalories ?? 0;
    final goal = provider.activeGoal?.dailyCalories ?? 2000;
    final remaining = goal - consumed;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Row(
        children: [
          // Calorie ring
          CalorieRingWidget(consumed: consumed, goal: goal, size: 120),
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
                  'Consumed',
                  consumed.toStringAsFixed(0),
                  Icons.local_fire_department,
                  Colors.orange,
                ),
                const SizedBox(height: 8),
                _buildCalorieRow(
                  context,
                  'Remaining',
                  remaining.toStringAsFixed(0),
                  Icons.flag_outlined,
                  remaining >= 0 ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 8),
                _buildCalorieRow(
                  context,
                  'Goal',
                  goal.toStringAsFixed(0),
                  Icons.track_changes,
                  Colors.blue,
                ),
              ],
            ),
          ),
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
          Text(
            'Macros',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          MacroProgressBar(
            label: 'Protein',
            current: mealLog?.totalProtein ?? 0,
            goal: goal?.dailyProtein ?? 150,
            color: Colors.red,
            unit: 'g',
          ),
          const SizedBox(height: 12),
          MacroProgressBar(
            label: 'Carbs',
            current: mealLog?.totalCarbohydrates ?? 0,
            goal: goal?.dailyCarbohydrates ?? 200,
            color: Colors.blue,
            unit: 'g',
          ),
          const SizedBox(height: 12),
          MacroProgressBar(
            label: 'Fat',
            current: mealLog?.totalFat ?? 0,
            goal: goal?.dailyFat ?? 65,
            color: Colors.amber,
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
}
