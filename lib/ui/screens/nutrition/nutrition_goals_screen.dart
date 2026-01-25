import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/nutrition_provider.dart';

/// Screen for configuring nutrition goals (calories, protein, carbs, fat, water)
class NutritionGoalsScreen extends StatefulWidget {
  const NutritionGoalsScreen({super.key});

  @override
  State<NutritionGoalsScreen> createState() => _NutritionGoalsScreenState();
}

class _NutritionGoalsScreenState extends State<NutritionGoalsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _caloriesController;
  late TextEditingController _proteinController;
  late TextEditingController _carbsController;
  late TextEditingController _fatController;
  late TextEditingController _fiberController;
  late TextEditingController _waterController;

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _caloriesController = TextEditingController();
    _proteinController = TextEditingController();
    _carbsController = TextEditingController();
    _fatController = TextEditingController();
    _fiberController = TextEditingController();
    _waterController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _initializeFromGoal();
      _isInitialized = true;
    }
  }

  void _initializeFromGoal() {
    final goal = context.read<NutritionProvider>().activeGoal;
    if (goal != null) {
      _caloriesController.text = goal.dailyCalories.toStringAsFixed(0);
      _proteinController.text = goal.dailyProtein.toStringAsFixed(0);
      _carbsController.text = goal.dailyCarbohydrates.toStringAsFixed(0);
      _fatController.text = goal.dailyFat.toStringAsFixed(0);
      _fiberController.text = (goal.dailyFiber ?? 25).toStringAsFixed(0);
      _waterController.text = (goal.dailyWater ?? 2000).toStringAsFixed(0);
    } else {
      // Default values
      _caloriesController.text = '2000';
      _proteinController.text = '150';
      _carbsController.text = '200';
      _fatController.text = '65';
      _fiberController.text = '25';
      _waterController.text = '2000';
    }
  }

  @override
  void dispose() {
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    _waterController.dispose();
    super.dispose();
  }

  Future<void> _saveGoals() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<NutritionProvider>();
    final calories = double.tryParse(_caloriesController.text) ?? 2000;
    final protein = double.tryParse(_proteinController.text) ?? 150;
    final carbs = double.tryParse(_carbsController.text) ?? 200;
    final fat = double.tryParse(_fatController.text) ?? 65;
    final fiber = double.tryParse(_fiberController.text);
    final water = double.tryParse(_waterController.text);

    bool success;
    // Check if we have a real goal (id > 0) or just the default placeholder (id == 0)
    final existingGoal = provider.activeGoal;
    if (existingGoal != null && existingGoal.id > 0) {
      success = await provider.updateNutritionGoal(
        dailyCalories: calories,
        dailyProtein: protein,
        dailyCarbohydrates: carbs,
        dailyFat: fat,
        dailyFiber: fiber,
        dailyWater: water,
      );
    } else {
      success = await provider.createNutritionGoal(
        dailyCalories: calories,
        dailyProtein: protein,
        dailyCarbohydrates: carbs,
        dailyFat: fat,
        dailyFiber: fiber,
        dailyWater: water,
      );
    }

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Goals saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to save goals'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: context.scaffoldBackground,
        title: Text(
          'Nutrition Goals',
          style: TextStyle(color: context.textPrimary),
        ),
        actions: [
          Consumer<NutritionProvider>(
            builder: (context, provider, child) {
              return TextButton(
                onPressed: provider.isLoading ? null : _saveGoals,
                child:
                    provider.isLoading
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : Text(
                          'Save',
                          style: TextStyle(
                            color: context.accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: context.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Set your daily nutrition targets based on your fitness goals.',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Calories section
              _buildSectionTitle(
                context,
                'Calories',
                Icons.local_fire_department,
                Colors.orange,
              ),
              const SizedBox(height: 12),
              _buildGoalInput(
                context,
                controller: _caloriesController,
                label: 'Daily Calories',
                hint: 'e.g., 2000',
                suffix: 'kcal',
                icon: Icons.local_fire_department,
                iconColor: Colors.orange,
              ),
              const SizedBox(height: 24),

              // Macros section
              _buildSectionTitle(
                context,
                'Macronutrients',
                Icons.pie_chart,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildGoalInput(
                context,
                controller: _proteinController,
                label: 'Daily Protein',
                hint: 'e.g., 150',
                suffix: 'g',
                icon: Icons.egg_outlined,
                iconColor: Colors.red,
              ),
              const SizedBox(height: 12),
              _buildGoalInput(
                context,
                controller: _carbsController,
                label: 'Daily Carbohydrates',
                hint: 'e.g., 200',
                suffix: 'g',
                icon: Icons.grain,
                iconColor: Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildGoalInput(
                context,
                controller: _fatController,
                label: 'Daily Fat',
                hint: 'e.g., 65',
                suffix: 'g',
                icon: Icons.opacity,
                iconColor: Colors.amber,
              ),
              const SizedBox(height: 24),

              // Other nutrients section
              _buildSectionTitle(
                context,
                'Other',
                Icons.more_horiz,
                Colors.grey,
              ),
              const SizedBox(height: 12),
              _buildGoalInput(
                context,
                controller: _fiberController,
                label: 'Daily Fiber',
                hint: 'e.g., 25',
                suffix: 'g',
                icon: Icons.grass,
                iconColor: Colors.green,
                isOptional: true,
              ),
              const SizedBox(height: 12),
              _buildGoalInput(
                context,
                controller: _waterController,
                label: 'Daily Water',
                hint: 'e.g., 2000',
                suffix: 'ml',
                icon: Icons.water_drop,
                iconColor: Colors.blue,
                isOptional: true,
              ),
              const SizedBox(height: 32),

              // Macro breakdown preview
              _buildMacroPreview(context),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildGoalInput(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required String suffix,
    required IconData icon,
    required Color iconColor,
    bool isOptional = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: TextStyle(color: context.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: context.textSecondary),
          hintText: hint,
          hintStyle: TextStyle(color: context.textTertiary),
          suffixText: suffix,
          suffixStyle: TextStyle(color: context.textSecondary),
          prefixIcon: Icon(icon, color: iconColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        validator:
            isOptional
                ? null
                : (value) {
                  if (value == null || value.isEmpty) {
                    return 'Required';
                  }
                  final number = double.tryParse(value);
                  if (number == null || number <= 0) {
                    return 'Enter a valid number';
                  }
                  return null;
                },
      ),
    );
  }

  Widget _buildMacroPreview(BuildContext context) {
    final protein = double.tryParse(_proteinController.text) ?? 150;
    final carbs = double.tryParse(_carbsController.text) ?? 200;
    final fat = double.tryParse(_fatController.text) ?? 65;

    // Calculate percentages
    final proteinCals = protein * 4;
    final carbsCals = carbs * 4;
    final fatCals = fat * 9;
    final totalMacroCals = proteinCals + carbsCals + fatCals;

    final proteinPct =
        totalMacroCals > 0 ? (proteinCals / totalMacroCals * 100) : 0.0;
    final carbsPct =
        totalMacroCals > 0 ? (carbsCals / totalMacroCals * 100) : 0.0;
    final fatPct = totalMacroCals > 0 ? (fatCals / totalMacroCals * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Macro Breakdown',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Visual bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Expanded(
                  flex: proteinPct.round(),
                  child: Container(height: 24, color: Colors.red),
                ),
                Expanded(
                  flex: carbsPct.round(),
                  child: Container(height: 24, color: Colors.blue),
                ),
                Expanded(
                  flex: fatPct.round(),
                  child: Container(height: 24, color: Colors.amber),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMacroLegend(context, 'Protein', proteinPct, Colors.red),
              _buildMacroLegend(context, 'Carbs', carbsPct, Colors.blue),
              _buildMacroLegend(context, 'Fat', fatPct, Colors.amber),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Total from macros: ${totalMacroCals.toStringAsFixed(0)} kcal',
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroLegend(
    BuildContext context,
    String label,
    double percentage,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
        Text(
          '${percentage.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }
}
