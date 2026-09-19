import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/common/offline_banner.dart';

/// Form screen for generating AI meal plans
class MealPlanFormScreen extends StatefulWidget {
  const MealPlanFormScreen({super.key});

  @override
  State<MealPlanFormScreen> createState() => _MealPlanFormScreenState();
}

class _MealPlanFormScreenState extends State<MealPlanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _goalController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _restrictionsController = TextEditingController();
  final _preferencesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill from user's nutrition goals
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNutritionGoals();
    });
  }

  void _loadNutritionGoals() {
    final nutritionProvider = context.read<NutritionProvider>();
    final goal = nutritionProvider.activeGoal;
    if (goal != null) {
      _caloriesController.text = goal.dailyCalories.toInt().toString();
      _proteinController.text = goal.dailyProtein.toInt().toString();
      _carbsController.text = goal.dailyCarbohydrates.toInt().toString();
      _fatController.text = goal.dailyFat.toInt().toString();
    }
  }

  @override
  void dispose() {
    _goalController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _restrictionsController.dispose();
    _preferencesController.dispose();
    super.dispose();
  }

  Future<void> _generatePlan() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<ChatProvider>();

    // Parse values
    int? targetCalories;
    int? targetProtein;
    int? targetCarbs;
    int? targetFat;

    if (_caloriesController.text.trim().isNotEmpty) {
      targetCalories = int.tryParse(_caloriesController.text.trim());
    }
    if (_proteinController.text.trim().isNotEmpty) {
      targetProtein = int.tryParse(_proteinController.text.trim());
    }
    if (_carbsController.text.trim().isNotEmpty) {
      targetCarbs = int.tryParse(_carbsController.text.trim());
    }
    if (_fatController.text.trim().isNotEmpty) {
      targetFat = int.tryParse(_fatController.text.trim());
    }

    // Build macros string from individual values
    String? macros;
    if (targetProtein != null || targetCarbs != null || targetFat != null) {
      final parts = <String>[];
      if (targetProtein != null) parts.add('${targetProtein}g protein');
      if (targetCarbs != null) parts.add('${targetCarbs}g carbs');
      if (targetFat != null) parts.add('${targetFat}g fat');
      macros = parts.join(', ');
    }

    // Capture context-dependent objects before async operation
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    String? errorMessage;
    final conversation = await provider.generateMealPlan(
      dietaryGoal: _goalController.text.trim(),
      targetCalories: targetCalories,
      macros: macros,
      restrictions:
          _restrictionsController.text.trim().isEmpty
              ? null
              : _restrictionsController.text.trim(),
      preferences:
          _preferencesController.text.trim().isEmpty
              ? null
              : _preferencesController.text.trim(),
      onError: (message) => errorMessage = message,
    );

    if (mounted) {
      navigator.pop(); // Close loading dialog

      if (conversation != null) {
        // Navigate to conversation screen
        navigator.pushReplacementNamed(
          RouteNames.chatConversation,
          arguments: conversation.id,
        );
      } else if (errorMessage != null) {
        // Show error
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(errorMessage!),
            backgroundColor: context.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Meal Plan'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tell us about your nutrition goals',
                      style: AppTypography.headline.copyWith(
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Dietary Goal
                    TextFormField(
                      controller: _goalController,
                      decoration: const InputDecoration(
                        labelText: 'Dietary Goal',
                        hintText: 'e.g., Muscle gain, Fat loss, Maintenance',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your dietary goal';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Target Calories
                    TextFormField(
                      controller: _caloriesController,
                      decoration: const InputDecoration(
                        labelText: 'Target Calories',
                        hintText: 'e.g., 2500',
                        suffixText: 'cal/day',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          final calories = int.tryParse(value.trim());
                          if (calories == null ||
                              calories < 1000 ||
                              calories > 5000) {
                            return 'Please enter a valid calorie amount (1000-5000)';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Macro Targets
                    Text(
                      'Macro Targets',
                      style: AppTypography.titleMedium.copyWith(
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _proteinController,
                            decoration: const InputDecoration(
                              labelText: 'Protein',
                              hintText: '150',
                              suffixText: 'g',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _carbsController,
                            decoration: const InputDecoration(
                              labelText: 'Carbs',
                              hintText: '200',
                              suffixText: 'g',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _fatController,
                            decoration: const InputDecoration(
                              labelText: 'Fat',
                              hintText: '65',
                              suffixText: 'g',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Dietary Restrictions
                    TextFormField(
                      controller: _restrictionsController,
                      decoration: const InputDecoration(
                        labelText: 'Dietary Restrictions (Optional)',
                        hintText:
                            'e.g., Vegetarian, Vegan, Gluten-free, Lactose intolerant',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Preferences
                    TextFormField(
                      controller: _preferencesController,
                      decoration: const InputDecoration(
                        labelText: 'Food Preferences (Optional)',
                        hintText:
                            'e.g., I love chicken, No seafood, 5 meals per day',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),

                    // Generate Button
                    SizedBox(
                      width: double.infinity,
                      child: Consumer<ChatProvider>(
                        builder: (context, provider, child) {
                          return ElevatedButton(
                            onPressed:
                                provider.isOffline ? null : _generatePlan,
                            child: const Text('Generate Meal Plan'),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Info card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.info.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: context.info.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: context.info),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'AI will create a personalized meal plan with recipes and macros. You can chat with it to adjust meals.',
                              style: AppTypography.bodySmall.copyWith(
                                color: context.info,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
