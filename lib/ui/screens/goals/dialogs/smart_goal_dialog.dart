import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../core/services/goal_validation_service.dart';
import '../../../../providers/goals_provider.dart';
import '../../../../providers/body_metrics_provider.dart';
import '../../../../providers/nutrition_provider.dart';
import '../../../../data/models/goal.dart';
import '../../../../routes/route_names.dart';

/// Quick goal template for one-tap creation
class GoalTemplate {
  final String name;
  final String goalType;
  final double targetChange;
  final String unit;
  final IconData icon;
  final Color color;

  const GoalTemplate({
    required this.name,
    required this.goalType,
    required this.targetChange,
    required this.unit,
    required this.icon,
    required this.color,
  });
}

/// Result from the smart goal dialog
class SmartGoalDialogResult {
  final Goal goal;
  final CalculatedNutrition? nutrition;
  final bool generateWorkoutPlan;
  final bool generateMealPlan;

  const SmartGoalDialogResult({
    required this.goal,
    this.nutrition,
    this.generateWorkoutPlan = false,
    this.generateMealPlan = false,
  });

  bool get hasSelection => generateWorkoutPlan || generateMealPlan;
}

/// Dialog states
enum SmartGoalDialogState {
  form, // Goal creation form
  loading, // Creating goal + calculating nutrition
  summary, // Results + plan generation options
  error, // Error occurred during creation
}

/// Unified smart dialog for goal creation with nutrition calculation and plan generation
class SmartGoalDialog extends StatefulWidget {
  const SmartGoalDialog({super.key});

  @override
  State<SmartGoalDialog> createState() => _SmartGoalDialogState();
}

class _SmartGoalDialogState extends State<SmartGoalDialog> {
  // Dialog state
  SmartGoalDialogState _state = SmartGoalDialogState.form;
  String? _loadingMessage;
  String? _errorMessage;

  // Created goal and nutrition
  Goal? _createdGoal;
  CalculatedNutrition? _nutrition;

  // Plan generation selections
  bool _generateWorkoutPlan = false;
  bool _generateMealPlan = false;

  // Form state
  final _formKey = GlobalKey<FormState>();
  final _targetValueController = TextEditingController();
  final _currentValueController = TextEditingController();

  String? _selectedGoalType;
  String _selectedUnit = 'lb';
  DateTime? _targetDate;
  DateTime? _aiSuggestedDate;
  bool _isCreating = false;
  bool _metricsLoaded = false;
  bool _showAdvancedForm = false;

  // Body metrics
  double? _currentWeight;
  double? _currentHeight;
  String? _currentActivityLevel;
  DateTime? _metricsRecordedAt;

  // Auto-populate tracking
  String? _autoPopulatedFrom;
  DateTime? _autoPopulatedDate;

  // Validation warnings
  String? _goalWarning;

  // Nutrition calculation status
  String? _nutritionWarning;

  // Quick goal templates
  static const List<GoalTemplate> _templates = [
    GoalTemplate(
      name: 'Lose 10 lbs',
      goalType: 'Weight Loss',
      targetChange: -10,
      unit: 'lb',
      icon: Icons.trending_down,
      color: Colors.orange,
    ),
    GoalTemplate(
      name: 'Lose 20 lbs',
      goalType: 'Weight Loss',
      targetChange: -20,
      unit: 'lb',
      icon: Icons.trending_down,
      color: Colors.deepOrange,
    ),
    GoalTemplate(
      name: 'Gain 5 lbs muscle',
      goalType: 'Muscle Gain',
      targetChange: 5,
      unit: 'lb',
      icon: Icons.fitness_center,
      color: Colors.blue,
    ),
    GoalTemplate(
      name: 'Gain 10 lbs muscle',
      goalType: 'Muscle Gain',
      targetChange: 10,
      unit: 'lb',
      icon: Icons.fitness_center,
      color: Colors.indigo,
    ),
  ];

  final List<String> _goalTypes = [
    'Weight Loss',
    'Muscle Gain',
    'Body Fat',
    'Workout Frequency',
    'Strength (Total Volume)',
    'Cardiovascular Endurance',
    'Flexibility',
  ];

  List<String> get _availableUnits {
    if (_selectedGoalType == null) return ['lb', 'kg'];

    switch (_selectedGoalType!) {
      case 'Weight Loss':
      case 'Muscle Gain':
        return ['lb', 'kg'];
      case 'Body Fat':
        return ['%'];
      case 'Workout Frequency':
        return ['workouts/week', 'workouts/month'];
      case 'Strength (Total Volume)':
        return ['lb', 'kg'];
      case 'Cardiovascular Endurance':
        return ['minutes', 'km', 'miles'];
      case 'Flexibility':
        return ['cm', 'inches'];
      default:
        return ['lb', 'kg'];
    }
  }

  bool _isWeightGoal() {
    return _selectedGoalType != null &&
        (_selectedGoalType!.toLowerCase().contains('weight') ||
            _selectedGoalType!.toLowerCase().contains('muscle'));
  }

  bool get _hasAllRequiredMetrics =>
      _currentWeight != null &&
      _currentHeight != null &&
      _currentActivityLevel != null;

  bool get _areMetricsStale {
    if (_metricsRecordedAt == null) return false;
    final daysSinceUpdate =
        DateTime.now().difference(_metricsRecordedAt!).inDays;
    return daysSinceUpdate > 30;
  }

  @override
  void dispose() {
    _targetValueController.dispose();
    _currentValueController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _targetValueController.addListener(_onValuesChanged);
    _currentValueController.addListener(_onValuesChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBodyMetrics();
    });
  }

  void _onValuesChanged() {
    _calculateAISuggestedDate();
    _validateGoalRealism();
  }

  void _validateGoalRealism() {
    if (_selectedGoalType == null) {
      setState(() => _goalWarning = null);
      return;
    }

    final currentValue = double.tryParse(_currentValueController.text);
    final targetValue = double.tryParse(_targetValueController.text);

    if (currentValue == null || targetValue == null) {
      setState(() => _goalWarning = null);
      return;
    }

    final result = GoalValidationService.instance.validateGoalRealism(
      goalType: _selectedGoalType!,
      currentValue: currentValue,
      targetValue: targetValue,
      targetDate: _targetDate,
    );

    setState(() => _goalWarning = result.warning);
  }

  void _calculateAISuggestedDate() {
    if (_selectedGoalType == null) return;

    final currentValue = double.tryParse(_currentValueController.text) ?? 0;
    final targetValue = double.tryParse(_targetValueController.text);

    if (targetValue == null || currentValue == 0) return;

    final suggestedDate = GoalValidationService.instance
        .calculateAISuggestedDate(
          goalType: _selectedGoalType!,
          currentValue: currentValue,
          targetValue: targetValue,
        );

    setState(() {
      _aiSuggestedDate = suggestedDate;
      _targetDate ??= _aiSuggestedDate;
    });
  }

  Future<void> _loadBodyMetrics() async {
    final provider = context.read<BodyMetricsProvider>();
    await provider.loadLatestMetric();

    final latest = provider.latestMetric;
    if (mounted) {
      setState(() {
        _currentWeight = latest?.weight;
        _currentHeight = latest?.height;
        _currentActivityLevel = latest?.activityLevel;
        _metricsRecordedAt = latest?.recordedAt;
        _metricsLoaded = true;
      });
    }
  }

  String _formatActivityLevelDisplay(String level) {
    switch (level) {
      case 'Sedentary':
        return 'Sedentary';
      case 'LightlyActive':
        return 'Lightly Active';
      case 'ModeratelyActive':
        return 'Moderately Active';
      case 'VeryActive':
        return 'Very Active';
      case 'ExtremelyActive':
        return 'Extremely Active';
      default:
        return level;
    }
  }

  void _autoPopulateFromMetrics(String goalType) {
    final bodyMetricsProvider = context.read<BodyMetricsProvider>();
    final latest = bodyMetricsProvider.latestMetric;

    if (latest == null) return;

    final type = goalType.toLowerCase();

    if (type.contains('weight') || type.contains('muscle')) {
      if (latest.weight != null) {
        double value = latest.weight!;
        if (_selectedUnit == 'lb') {
          value = value * 2.20462;
        }
        _currentValueController.text = value.toStringAsFixed(1);
        _autoPopulatedFrom = 'weight';
        _autoPopulatedDate = latest.recordedAt;
      }
    } else if (type.contains('fat')) {
      if (latest.bodyFatPercentage != null) {
        _currentValueController.text = latest.bodyFatPercentage!
            .toStringAsFixed(1);
        _autoPopulatedFrom = 'bodyFat';
        _autoPopulatedDate = latest.recordedAt;
      }
    }
  }

  void _applyTemplate(GoalTemplate template) {
    if (_currentWeight == null) return;

    final currentWeightLbs = _currentWeight! * 2.20462;
    final targetValue = currentWeightLbs + template.targetChange;

    setState(() {
      _selectedGoalType = template.goalType;
      _selectedUnit = template.unit;
      _currentValueController.text = currentWeightLbs.toStringAsFixed(1);
      _targetValueController.text = targetValue.toStringAsFixed(1);
      _autoPopulatedFrom = 'weight';
      _autoPopulatedDate = _metricsRecordedAt;
      _showAdvancedForm = true;
    });

    _calculateAISuggestedDate();
    _validateGoalRealism();
  }

  Future<void> _selectTargetDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Target Date',
    );

    if (picked != null) {
      setState(() {
        _targetDate = picked;
      });
      _validateGoalRealism();
    }
  }

  String? _getGoalPreview() {
    if (_selectedGoalType == null) return null;

    final currentValue = double.tryParse(_currentValueController.text);
    final targetValue = double.tryParse(_targetValueController.text);

    if (currentValue == null || targetValue == null) return null;

    final change = (targetValue - currentValue).abs();
    final unit = _selectedUnit;
    final isDecrease = targetValue < currentValue;

    String action;
    if (_selectedGoalType == 'Weight Loss') {
      action = 'Lose';
    } else if (_selectedGoalType == 'Muscle Gain') {
      action = 'Gain';
    } else if (_selectedGoalType == 'Body Fat') {
      action = isDecrease ? 'Reduce' : 'Increase';
    } else {
      action = isDecrease ? 'Decrease' : 'Increase';
    }

    String dateText = '';
    if (_targetDate != null) {
      final weeksLeft = _targetDate!.difference(DateTime.now()).inDays ~/ 7;
      dateText = ' in $weeksLeft weeks';
    }

    return '$action ${change.toStringAsFixed(1)} $unit$dateText';
  }

  /// Create goal and calculate nutrition
  Future<void> _createGoalAndCalculateNutrition() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<GoalsProvider>();
    final nutritionProvider = context.read<NutritionProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (_selectedGoalType == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please select a goal type'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show warning confirmation if there's a warning
    if (_goalWarning != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Goal Warning'),
                ],
              ),
              content: Text(
                '$_goalWarning\n\nDo you want to create this goal anyway?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Edit Goal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Create Anyway'),
                ),
              ],
            ),
      );

      if (proceed != true) return;
    }

    // Transition to loading state
    setState(() {
      _state = SmartGoalDialogState.loading;
      _loadingMessage = 'Creating goal...';
      _isCreating = true;
    });

    // Create the goal
    final goal = Goal(
      id: 0,
      userId: 0,
      goalType: _selectedGoalType!,
      targetValue: double.parse(_targetValueController.text),
      currentValue: double.tryParse(_currentValueController.text) ?? 0,
      unit: _selectedUnit,
      timeFrame: null,
      startDate: DateTime.now(),
      targetDate: _targetDate,
      isActive: true,
      isCompleted: false,
      createdAt: DateTime.now(),
    );

    final createdGoal = await provider.createGoal(goal);

    if (createdGoal == null) {
      if (mounted) {
        setState(() {
          _state = SmartGoalDialogState.error;
          _errorMessage = provider.errorMessage ?? 'Failed to create goal';
          _isCreating = false;
        });
      }
      return;
    }

    _createdGoal = createdGoal;

    // Calculate nutrition
    setState(() {
      _loadingMessage = 'Calculating your nutrition plan...';
    });

    try {
      _nutrition = await _calculateNutritionForGoal(
        createdGoal,
        nutritionProvider,
      );
    } on OfflineNutritionException catch (e) {
      debugPrint('Nutrition calculation offline: $e');
      _nutritionWarning = e.message;
      // Continue without nutrition - goal was saved, nutrition will sync later
    } on MissingMetricsException catch (e) {
      debugPrint('Missing metrics for nutrition calculation: $e');
      _nutritionWarning =
          '${e.message}\n\nGo to Body Metrics to add your ${e.missingFields.join(" and ")}.';
      // Continue without nutrition - user needs to add metrics first
    } catch (e) {
      debugPrint('Nutrition calculation failed: $e');
      _nutritionWarning =
          'Nutrition calculation failed. You can set targets manually in the Nutrition tab.';
      // Continue without nutrition - it's optional
    }

    // Transition to summary state
    if (mounted) {
      setState(() {
        _state = SmartGoalDialogState.summary;
        _isCreating = false;
      });
    }
  }

  Future<CalculatedNutrition?> _calculateNutritionForGoal(
    Goal goal,
    NutritionProvider nutritionProvider,
  ) async {
    String nutritionGoalType = 'Maintenance';
    double? targetWeightChange;
    int? timeframeWeeks;

    final goalType = goal.goalType.toLowerCase();
    if (goalType.contains('loss')) {
      nutritionGoalType = 'WeightLoss';
      targetWeightChange = (goal.currentValue - goal.targetValue).abs();
    } else if (goalType.contains('gain') || goalType.contains('muscle')) {
      nutritionGoalType = 'MuscleGain';
      targetWeightChange = (goal.targetValue - goal.currentValue).abs();
    }

    // Convert to lbs if user entered in kg (API uses 3500 cal = 1 lb formula)
    if (targetWeightChange != null && goal.unit?.toLowerCase() == 'kg') {
      targetWeightChange = targetWeightChange * 2.20462;
    }

    if (goal.targetDate != null) {
      timeframeWeeks = goal.targetDate!.difference(DateTime.now()).inDays ~/ 7;
      if (timeframeWeeks < 1) timeframeWeeks = 1;
    }

    return await nutritionProvider.calculateAndSaveNutrition(
      goalType: nutritionGoalType,
      targetWeightChange: targetWeightChange,
      timeframeWeeks: timeframeWeeks,
    );
  }

  void _finishWithPlans() {
    Navigator.pop(
      context,
      SmartGoalDialogResult(
        goal: _createdGoal!,
        nutrition: _nutrition,
        generateWorkoutPlan: _generateWorkoutPlan,
        generateMealPlan: _generateMealPlan,
      ),
    );
  }

  void _finishWithoutPlans() {
    Navigator.pop(
      context,
      SmartGoalDialogResult(
        goal: _createdGoal!,
        nutrition: _nutrition,
        generateWorkoutPlan: false,
        generateMealPlan: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _buildTitle(),
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildContent(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildTitle() {
    switch (_state) {
      case SmartGoalDialogState.form:
        return const Text('Create Goal');
      case SmartGoalDialogState.loading:
        return const Text('Creating Goal...');
      case SmartGoalDialogState.summary:
        return Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('Goal Created!')),
          ],
        );
      case SmartGoalDialogState.error:
        return Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade600, size: 28),
            const SizedBox(width: 12),
            const Expanded(child: Text('Error')),
          ],
        );
    }
  }

  Widget _buildContent() {
    switch (_state) {
      case SmartGoalDialogState.form:
        return _buildFormContent();
      case SmartGoalDialogState.loading:
        return _buildLoadingContent();
      case SmartGoalDialogState.summary:
        return _buildSummaryContent();
      case SmartGoalDialogState.error:
        return _buildErrorContent();
    }
  }

  List<Widget> _buildActions() {
    switch (_state) {
      case SmartGoalDialogState.form:
        return [
          TextButton(
            onPressed: _isCreating ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (_showAdvancedForm || !_hasAllRequiredMetrics)
            ElevatedButton(
              onPressed:
                  (_isCreating || !_hasAllRequiredMetrics)
                      ? null
                      : _createGoalAndCalculateNutrition,
              child:
                  _isCreating
                      ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.accent,
                        ),
                      )
                      : const Text('Create'),
            ),
        ];
      case SmartGoalDialogState.loading:
        return []; // No actions during loading
      case SmartGoalDialogState.summary:
        final hasSelection = _generateWorkoutPlan || _generateMealPlan;
        return [
          TextButton(
            onPressed: _finishWithoutPlans,
            child: Text(hasSelection ? 'Skip' : 'Done'),
          ),
          if (hasSelection)
            ElevatedButton.icon(
              onPressed: _finishWithPlans,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                _generateWorkoutPlan && _generateMealPlan
                    ? 'Generate Both'
                    : _generateWorkoutPlan
                    ? 'Generate Workout'
                    : 'Generate Meal Plan',
              ),
            ),
        ];
      case SmartGoalDialogState.error:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _retryFromError,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ];
    }
  }

  // ==================== FORM CONTENT ====================

  Widget _buildFormContent() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_metricsLoaded && !_hasAllRequiredMetrics)
              _buildMissingMetricsWarning(),
            if (_metricsLoaded && _hasAllRequiredMetrics && _areMetricsStale)
              _buildStaleMetricsWarning(),
            if (_metricsLoaded && _hasAllRequiredMetrics && !_areMetricsStale)
              _buildCurrentStatsCard(),
            if (_metricsLoaded && _hasAllRequiredMetrics && !_showAdvancedForm)
              _buildQuickTemplates(),
            if (_showAdvancedForm || !_hasAllRequiredMetrics)
              _buildAdvancedForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTemplates() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flash_on, size: 16, color: Colors.amber.shade700),
            const SizedBox(width: 4),
            Text(
              'Quick Start',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _templates.map((template) {
                return ActionChip(
                  avatar: Icon(template.icon, size: 18, color: template.color),
                  label: Text(template.name),
                  backgroundColor: template.color.withValues(alpha: 0.1),
                  side: BorderSide(
                    color: template.color.withValues(alpha: 0.3),
                  ),
                  onPressed: () => _applyTemplate(template),
                );
              }).toList(),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _showAdvancedForm = true),
            child: const Text('Or create custom goal...'),
          ),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildAdvancedForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          value: _selectedGoalType,
          decoration: const InputDecoration(
            labelText: 'Goal Type',
            prefixIcon: Icon(Icons.flag),
          ),
          items:
              _goalTypes.map((type) {
                return DropdownMenuItem(value: type, child: Text(type));
              }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedGoalType = value;
              if (value != null) {
                _selectedUnit = _availableUnits.first;
                _autoPopulatedFrom = null;
                _autoPopulatedDate = null;
                _autoPopulateFromMetrics(value);
                _calculateAISuggestedDate();
              }
            });
          },
          validator: (value) {
            if (value == null) return 'Please select a goal type';
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _currentValueController,
          decoration: InputDecoration(
            labelText: _isWeightGoal() ? 'Current Weight' : 'Current Value',
            prefixIcon: const Icon(Icons.trending_up),
            helperText: 'Your starting point',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) {
            if (_autoPopulatedFrom != null) {
              setState(() {
                _autoPopulatedFrom = null;
                _autoPopulatedDate = null;
              });
            }
          },
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return _isWeightGoal()
                  ? 'Please enter current weight'
                  : 'Please enter current value';
            }
            if (double.tryParse(value) == null) {
              return 'Please enter a valid number';
            }
            return null;
          },
        ),
        if (_autoPopulatedFrom != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 40),
              Icon(Icons.auto_awesome, size: 14, color: Colors.green.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _autoPopulatedDate != null
                      ? 'Auto-filled from body metrics (${DateFormat('MMM d').format(_autoPopulatedDate!)})'
                      : 'Auto-filled from latest body metric',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          controller: _targetValueController,
          decoration: InputDecoration(
            labelText: _isWeightGoal() ? 'Target Weight' : 'Target Value',
            prefixIcon: const Icon(Icons.track_changes),
            helperText: 'Your goal',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return _isWeightGoal()
                  ? 'Please enter target weight'
                  : 'Please enter target value';
            }
            if (double.tryParse(value) == null) {
              return 'Please enter a valid number';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedUnit,
          decoration: const InputDecoration(
            labelText: 'Unit',
            prefixIcon: Icon(Icons.straighten),
          ),
          items:
              _availableUnits.map((unit) {
                return DropdownMenuItem(value: unit, child: Text(unit));
              }).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _selectedUnit = value);
          },
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _selectTargetDate,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Target Date',
              prefixIcon: Icon(Icons.event),
            ),
            child: Text(
              _targetDate != null
                  ? DateFormat('MMM d, y').format(_targetDate!)
                  : 'Select target date',
              style: TextStyle(color: _targetDate != null ? null : Colors.grey),
            ),
          ),
        ),
        if (_aiSuggestedDate != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 40),
              Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI suggests: ${DateFormat('MMM d, y').format(_aiSuggestedDate!)} based on healthy progress rates',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
        _buildGoalWarning(),
        _buildGoalPreview(),
      ],
    );
  }

  Widget _buildMissingMetricsWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber,
                color: Colors.orange.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Complete your body metrics first',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMetricStatus(
            'Weight',
            _currentWeight != null,
            _currentWeight != null
                ? '${_currentWeight!.toStringAsFixed(1)} kg'
                : null,
          ),
          _buildMetricStatus(
            'Height',
            _currentHeight != null,
            _currentHeight != null
                ? '${_currentHeight!.toStringAsFixed(1)} cm'
                : null,
          ),
          _buildMetricStatus(
            'Activity Level',
            _currentActivityLevel != null,
            _currentActivityLevel != null
                ? _formatActivityLevelDisplay(_currentActivityLevel!)
                : null,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, RouteNames.bodyMetrics);
              },
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Go to Body Metrics'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaleMetricsWarning() {
    final daysSince = DateTime.now().difference(_metricsRecordedAt!).inDays;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.yellow.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.yellow.shade700),
      ),
      child: Row(
        children: [
          Icon(Icons.update, color: Colors.yellow.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your metrics are $daysSince days old. Consider updating them.',
              style: TextStyle(fontSize: 12, color: Colors.yellow.shade900),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, RouteNames.bodyMetrics);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricStatus(String label, bool hasValue, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            hasValue ? Icons.check_circle : Icons.cancel,
            color: hasValue ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text('$label: '),
          Text(
            hasValue ? value! : 'Missing',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: hasValue ? Colors.green.shade700 : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStatsCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Your Current Stats',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Weight: ${_currentWeight!.toStringAsFixed(1)} kg (${(_currentWeight! * 2.205).toStringAsFixed(1)} lbs)',
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            'Height: ${_currentHeight!.toStringAsFixed(1)} cm',
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            'Activity: ${_formatActivityLevelDisplay(_currentActivityLevel!)}',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalWarning() {
    if (_goalWarning == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _goalWarning!,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalPreview() {
    final preview = _getGoalPreview();
    if (preview == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.preview,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Your Goal',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            preview,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          if (_targetDate != null) ...[
            const SizedBox(height: 4),
            Text(
              'Target: ${DateFormat('MMM d, yyyy').format(_targetDate!)}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== LOADING CONTENT ====================

  Widget _buildLoadingContent() {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _loadingMessage ?? 'Please wait...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ERROR CONTENT ====================

  Widget _buildErrorContent() {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to create goal',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _errorMessage ?? 'An unexpected error occurred',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _retryFromError() {
    setState(() {
      _state = SmartGoalDialogState.form;
      _errorMessage = null;
    });
  }

  // ==================== SUMMARY CONTENT ====================

  Widget _buildSummaryContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildGoalSummaryCard(),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          if (_nutrition != null) ...[
            Text(
              'Your Nutrition Plan',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _buildNutritionCard(),
            if (_nutrition!.hasWarning) ...[
              const SizedBox(height: 12),
              _buildAggressiveDeficitWarning(),
            ],
            const SizedBox(height: 16),
          ] else ...[
            _buildNoNutritionWarning(),
            const SizedBox(height: 16),
          ],
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
          _buildPlanCheckboxOption(
            icon: Icons.fitness_center,
            label: 'Workout Plan',
            description: 'AI creates a personalized program',
            color: Colors.blue,
            value: _generateWorkoutPlan,
            onChanged:
                (value) =>
                    setState(() => _generateWorkoutPlan = value ?? false),
          ),
          const SizedBox(height: 8),
          _buildPlanCheckboxOption(
            icon: Icons.restaurant_menu,
            label: 'Meal Plan',
            description: 'AI creates meals matching your macros',
            color: Colors.green,
            value: _generateMealPlan,
            onChanged:
                (value) => setState(() => _generateMealPlan = value ?? false),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalSummaryCard() {
    final goal = _createdGoal!;
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

  Widget _buildNutritionCard() {
    final isDeficit = _nutrition!.calorieAdjustment < 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMacroCircle(
                'Calories',
                '${_nutrition!.dailyCalories.round()}',
                'kcal',
                Colors.orange,
              ),
              _buildMacroCircle(
                'Protein',
                '${_nutrition!.dailyProtein.round()}',
                'g',
                Colors.red,
              ),
              _buildMacroCircle(
                'Carbs',
                '${_nutrition!.dailyCarbohydrates.round()}',
                'g',
                Colors.blue,
              ),
              _buildMacroCircle(
                'Fat',
                '${_nutrition!.dailyFat.round()}',
                'g',
                Colors.purple,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
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
                      ? '${_nutrition!.calorieAdjustment.abs().round()} cal deficit/day'
                      : '${_nutrition!.calorieAdjustment.round()} cal surplus/day',
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
          if (_nutrition!.expectedWeeklyWeightChange != 0) ...[
            const SizedBox(height: 8),
            Text(
              'Expected: ${_nutrition!.expectedWeeklyWeightChange > 0 ? '+' : ''}${_nutrition!.expectedWeeklyWeightChange.toStringAsFixed(1)} lbs/week',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAggressiveDeficitWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber,
                color: Colors.orange.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aggressive Plan Warning',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _nutrition!.warning!,
            style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
          ),
          if (_nutrition!.recommendation != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: Colors.green.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nutrition!.recommendation!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade800,
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

  Widget _buildNoNutritionWarning() {
    final isOffline =
        _nutritionWarning?.contains('internet') == true ||
        _nutritionWarning?.contains('offline') == true;
    final warningColor = isOffline ? Colors.orange : Colors.yellow;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warningColor.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warningColor.shade700),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isOffline ? Icons.wifi_off : Icons.info_outline,
            color: warningColor.shade800,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _nutritionWarning ??
                  'Nutrition calculation unavailable. You can set targets manually in the Nutrition tab.',
              style: TextStyle(fontSize: 12, color: warningColor.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCheckboxOption({
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
