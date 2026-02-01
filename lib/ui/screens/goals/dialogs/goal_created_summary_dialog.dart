import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../data/models/goal.dart';
import '../../../../data/repositories/nutrition_repository.dart';

/// Result from the goal created dialog indicating which plans to generate
class GoalDialogResult {
  final bool generateWorkoutPlan;
  final bool generateMealPlan;

  const GoalDialogResult({
    required this.generateWorkoutPlan,
    required this.generateMealPlan,
  });

  bool get hasSelection => generateWorkoutPlan || generateMealPlan;
}

/// Dialog shown after goal creation with nutrition summary and action buttons
class GoalCreatedSummaryDialog extends StatefulWidget {
  final Goal goal;
  final CalculatedNutrition? nutrition;

  const GoalCreatedSummaryDialog({
    super.key,
    required this.goal,
    this.nutrition,
  });

  @override
  State<GoalCreatedSummaryDialog> createState() =>
      _GoalCreatedSummaryDialogState();
}

class _GoalCreatedSummaryDialogState extends State<GoalCreatedSummaryDialog> {
  bool _generateWorkoutPlan = false;
  bool _generateMealPlan = false;

  Goal get goal => widget.goal;
  CalculatedNutrition? get nutrition => widget.nutrition;

  @override
  Widget build(BuildContext context) {
    final hasSelection = _generateWorkoutPlan || _generateMealPlan;

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

            // Generation options with checkboxes
            Text(
              'Generate Plans (Optional)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select one or both to have AI create personalized plans:',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            _buildCheckboxOption(
              context,
              icon: Icons.fitness_center,
              label: 'Workout Plan',
              description: 'AI creates a personalized program',
              color: Colors.blue,
              value: _generateWorkoutPlan,
              onChanged: (value) {
                setState(() => _generateWorkoutPlan = value ?? false);
              },
            ),
            const SizedBox(height: 8),
            _buildCheckboxOption(
              context,
              icon: Icons.restaurant_menu,
              label: 'Meal Plan',
              description: 'AI creates meals matching your macros',
              color: Colors.green,
              value: _generateMealPlan,
              onChanged: (value) {
                setState(() => _generateMealPlan = value ?? false);
              },
            ),
            if (hasSelection) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      GoalDialogResult(
                        generateWorkoutPlan: _generateWorkoutPlan,
                        generateMealPlan: _generateMealPlan,
                      ),
                    );
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    _generateWorkoutPlan && _generateMealPlan
                        ? 'Generate Both Plans'
                        : _generateWorkoutPlan
                        ? 'Generate Workout Plan'
                        : 'Generate Meal Plan',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(hasSelection ? 'Skip' : 'Done'),
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

  Widget _buildCheckboxOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Material(
      color:
          value ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: value ? color : Colors.grey.shade300,
              width: value ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: color,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: value ? color : context.textPrimary,
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
            ],
          ),
        ),
      ),
    );
  }
}
