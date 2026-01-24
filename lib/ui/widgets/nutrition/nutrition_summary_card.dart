import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/nutrition_provider.dart';
import '../../screens/nutrition/nutrition_dashboard_screen.dart';

/// Compact nutrition summary card for the main dashboard
/// Shows today's calorie progress and macros at a glance
class NutritionSummaryCard extends StatefulWidget {
  const NutritionSummaryCard({super.key});

  @override
  State<NutritionSummaryCard> createState() => _NutritionSummaryCardState();
}

class _NutritionSummaryCardState extends State<NutritionSummaryCard> {
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
        final consumed = provider.todaysMealLog?.totalCalories ?? 0;
        final goal = provider.activeGoal?.dailyCalories ?? 2000;
        final percentage = (consumed / goal * 100).clamp(0, 100);

        final protein = provider.todaysMealLog?.totalProtein ?? 0;
        final carbs = provider.todaysMealLog?.totalCarbohydrates ?? 0;
        final fat = provider.todaysMealLog?.totalFat ?? 0;

        final proteinGoal = provider.activeGoal?.dailyProtein ?? 150;
        final carbsGoal = provider.activeGoal?.dailyCarbohydrates ?? 200;
        final fatGoal = provider.activeGoal?.dailyFat ?? 65;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NutritionDashboardScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.restaurant_menu_rounded,
                            size: 20,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Today\'s Nutrition',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                '${consumed.toStringAsFixed(0)} / ${goal.toStringAsFixed(0)} kcal',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Circular progress
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            children: [
                              CircularProgressIndicator(
                                value: percentage / 100,
                                strokeWidth: 4,
                                backgroundColor: context.surfaceHighlight,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  percentage >= 100
                                      ? Colors.red
                                      : Colors.orange,
                                ),
                              ),
                              Center(
                                child: Text(
                                  '${percentage.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: context.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: context.textTertiary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Macro bars
                    Row(
                      children: [
                        Expanded(
                          child: _MacroMiniBar(
                            label: 'Protein',
                            current: protein,
                            goal: proteinGoal,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MacroMiniBar(
                            label: 'Carbs',
                            current: carbs,
                            goal: carbsGoal,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MacroMiniBar(
                            label: 'Fat',
                            current: fat,
                            goal: fatGoal,
                            color: Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MacroMiniBar extends StatelessWidget {
  final String label;
  final double current;
  final double goal;
  final Color color;

  const _MacroMiniBar({
    required this.label,
    required this.current,
    required this.goal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = (current / goal * 100).clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
            Text(
              '${current.toStringAsFixed(0)}g',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: 4,
            backgroundColor: context.surfaceHighlight,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
