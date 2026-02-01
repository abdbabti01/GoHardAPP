import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../data/models/goal.dart';
import '../../../../data/repositories/nutrition_repository.dart';

/// Dialog shown after goal creation with nutrition summary and action buttons
class GoalCreatedSummaryDialog extends StatelessWidget {
  final Goal goal;
  final CalculatedNutrition? nutrition;
  final VoidCallback onGenerateWorkoutPlan;
  final VoidCallback onGenerateMealPlan;

  const GoalCreatedSummaryDialog({
    super.key,
    required this.goal,
    this.nutrition,
    required this.onGenerateWorkoutPlan,
    required this.onGenerateMealPlan,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade600, size: 28),
          const SizedBox(width: 12),
          const Expanded(child: Text('Goal Created!')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Goal summary
            _buildGoalSummary(context),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Nutrition targets
            if (nutrition != null) ...[
              Text(
                'Your Nutrition Plan',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildNutritionCard(context),
              const SizedBox(height: 16),
            ] else ...[
              _buildNoNutritionWarning(context),
              const SizedBox(height: 16),
            ],

            // Action buttons
            Text(
              'Next Steps',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              context,
              icon: Icons.fitness_center,
              label: 'Generate Workout Plan',
              description: 'AI creates a personalized program',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                onGenerateWorkoutPlan();
              },
            ),
            const SizedBox(height: 8),
            _buildActionButton(
              context,
              icon: Icons.restaurant_menu,
              label: 'Generate Meal Plan',
              description: 'AI creates meals matching your macros',
              color: Colors.green,
              onTap: () {
                Navigator.pop(context);
                onGenerateMealPlan();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildGoalSummary(BuildContext context) {
    final weeks =
        goal.targetDate != null
            ? goal.targetDate!.difference(DateTime.now()).inDays ~/ 7
            : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  goal.goalType,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${goal.currentValue.toStringAsFixed(1)} → ${goal.targetValue.toStringAsFixed(1)} ${goal.unit ?? ''}',
            style: TextStyle(fontSize: 15, color: Colors.blue.shade900),
          ),
          if (goal.targetDate != null) ...[
            const SizedBox(height: 4),
            Text(
              'Target: ${DateFormat('MMM d, y').format(goal.targetDate!)}${weeks != null ? ' ($weeks weeks)' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNutritionCard(BuildContext context) {
    final isDeficit = nutrition!.calorieAdjustment < 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          // Main targets row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMacroCircle(
                'Calories',
                '${nutrition!.dailyCalories.round()}',
                'kcal',
                Colors.orange,
              ),
              _buildMacroCircle(
                'Protein',
                '${nutrition!.dailyProtein.round()}',
                'g',
                Colors.red,
              ),
              _buildMacroCircle(
                'Carbs',
                '${nutrition!.dailyCarbohydrates.round()}',
                'g',
                Colors.blue,
              ),
              _buildMacroCircle(
                'Fat',
                '${nutrition!.dailyFat.round()}',
                'g',
                Colors.purple,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Calorie adjustment info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDeficit ? Colors.orange.shade100 : Colors.green.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isDeficit ? Icons.trending_down : Icons.trending_up,
                  size: 18,
                  color:
                      isDeficit
                          ? Colors.orange.shade800
                          : Colors.green.shade800,
                ),
                const SizedBox(width: 8),
                Text(
                  isDeficit
                      ? '${nutrition!.calorieAdjustment.abs().round()} cal deficit/day'
                      : '${nutrition!.calorieAdjustment.round()} cal surplus/day',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color:
                        isDeficit
                            ? Colors.orange.shade800
                            : Colors.green.shade800,
                  ),
                ),
              ],
            ),
          ),

          if (nutrition!.expectedWeeklyWeightChange != 0) ...[
            const SizedBox(height: 8),
            Text(
              'Expected: ${nutrition!.expectedWeeklyWeightChange > 0 ? '+' : ''}${nutrition!.expectedWeeklyWeightChange.toStringAsFixed(1)} lbs/week',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],

          if (nutrition!.explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              nutrition!.explanation,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroCircle(
    String label,
    String value,
    String unit,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                Text(unit, style: TextStyle(fontSize: 9, color: color)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildNoNutritionWarning(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.yellow.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.yellow.shade700),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.yellow.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nutrition calculation unavailable. You can still generate plans manually.',
              style: TextStyle(fontSize: 12, color: Colors.yellow.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
