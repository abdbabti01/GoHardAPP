import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../data/models/meal_entry.dart';
import '../../widgets/nutrition/calorie_ring_widget.dart';
import '../../widgets/nutrition/macro_progress_bar.dart';
import '../../widgets/nutrition/meal_card_widget.dart';
import 'food_search_screen.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // TODO: Navigate to nutrition goals settings
            },
          ),
        ],
      ),
      body: Consumer<NutritionProvider>(
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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

                  // Meals section
                  Text(
                    "Today's Meals",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Streak info
                  if (provider.streakInfo != null) ...[
                    const SizedBox(height: 12),
                    _buildStreakCard(context, provider),
                  ],

                  const SizedBox(height: 80), // FAB space
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToFoodSearch(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Log Food'),
      ),
    );
  }

  Widget _buildCalorieSummaryCard(
    BuildContext context,
    NutritionProvider provider,
  ) {
    final consumed = provider.todaysMealLog?.totalCalories ?? 0;
    final goal = provider.activeGoal?.dailyCalories ?? 2000;
    final remaining = goal - consumed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildMacroProgress(BuildContext context, NutritionProvider provider) {
    final mealLog = provider.todaysMealLog;
    final goal = provider.activeGoal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Macros',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
      ),
    );
  }

  Widget _buildWaterSection(BuildContext context, NutritionProvider provider) {
    final waterMl = provider.todaysMealLog?.waterIntake ?? 0;
    final goalMl = provider.activeGoal?.dailyWater ?? 2000;
    final percentage = (waterMl / goalMl * 100).clamp(0, 100);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Water',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${waterMl.toStringAsFixed(0)} / ${goalMl.toStringAsFixed(0)} ml',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percentage / 100,
                minHeight: 12,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
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
      child: Text(label),
    );
  }

  Widget _buildStreakCard(BuildContext context, NutritionProvider provider) {
    final streak = provider.streakInfo!;

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.local_fire_department,
              size: 40,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${streak.currentStreak} Day Streak!',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  'Longest: ${streak.longestStreak} days',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
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
}
