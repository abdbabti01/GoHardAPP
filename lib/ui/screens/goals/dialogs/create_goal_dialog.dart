import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../providers/goals_provider.dart';
import '../../../../providers/body_metrics_provider.dart';
import '../../../../data/models/goal.dart';
import '../../../../routes/route_names.dart';

/// Dialog for creating a new fitness goal with validation
class CreateGoalDialog extends StatefulWidget {
  const CreateGoalDialog({super.key});

  @override
  State<CreateGoalDialog> createState() => _CreateGoalDialogState();
}

class _CreateGoalDialogState extends State<CreateGoalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _targetValueController = TextEditingController();
  final _currentValueController = TextEditingController();

  // Dropdown values
  String? _selectedGoalType;
  String _selectedUnit = 'lb';
  DateTime? _targetDate;
  DateTime? _aiSuggestedDate;
  bool _isCreating = false;
  bool _metricsLoaded = false;

  // Body metrics for validation
  double? _currentWeight;
  double? _currentHeight;
  String? _currentActivityLevel;
  DateTime? _metricsRecordedAt;

  // Auto-populate tracking
  String? _autoPopulatedFrom;
  DateTime? _autoPopulatedDate;

  // Validation warnings
  String? _goalWarning;

  // Common fitness goal types
  final List<String> _goalTypes = [
    'Weight Loss',
    'Muscle Gain',
    'Body Fat',
    'Workout Frequency',
    'Strength (Total Volume)',
    'Cardiovascular Endurance',
    'Flexibility',
  ];

  // Unit options based on goal type
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

  /// Validate if the goal is realistic
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

    final change = (targetValue - currentValue).abs();
    final weeks =
        _targetDate != null
            ? _targetDate!.difference(DateTime.now()).inDays / 7
            : 12;

    String? warning;

    switch (_selectedGoalType!) {
      case 'Weight Loss':
        final weeklyLoss = weeks > 0 ? change / weeks : change;
        if (weeklyLoss > 2.5) {
          warning =
              'Losing more than 2 lbs/week is unhealthy. '
              'Your goal requires ${weeklyLoss.toStringAsFixed(1)} lbs/week.';
        } else if (targetValue >= currentValue) {
          warning =
              'Target weight should be less than current weight for weight loss.';
        }
        break;

      case 'Muscle Gain':
        final weeklyGain = weeks > 0 ? change / weeks : change;
        if (weeklyGain > 1.0) {
          warning =
              'Gaining more than 1 lb/week of muscle is unrealistic. '
              'Your goal requires ${weeklyGain.toStringAsFixed(1)} lbs/week.';
        } else if (targetValue <= currentValue) {
          warning =
              'Target should be greater than current value for muscle gain.';
        }
        break;

      case 'Body Fat':
        final monthlyLoss = weeks > 0 ? change / (weeks / 4) : change;
        if (monthlyLoss > 1.5) {
          warning =
              'Losing more than 1% body fat/month is difficult. '
              'Your goal requires ${monthlyLoss.toStringAsFixed(1)}%/month.';
        }
        break;
    }

    // Check if target equals current
    if (targetValue == currentValue && warning == null) {
      warning = 'Target value is the same as current value.';
    }

    setState(() => _goalWarning = warning);
  }

  void _calculateAISuggestedDate() {
    if (_selectedGoalType == null) return;

    final currentValue = double.tryParse(_currentValueController.text) ?? 0;
    final targetValue = double.tryParse(_targetValueController.text);

    if (targetValue == null || currentValue == 0) return;

    final difference = (targetValue - currentValue).abs();
    int daysToComplete = 90;

    switch (_selectedGoalType!) {
      case 'Weight Loss':
        final weeksNeeded = difference / 1.5;
        daysToComplete = (weeksNeeded * 7).ceil();
        break;
      case 'Muscle Gain':
        final weeksNeeded = difference / 0.75;
        daysToComplete = (weeksNeeded * 7).ceil();
        break;
      case 'Body Fat':
        final monthsNeeded = difference / 0.75;
        daysToComplete = (monthsNeeded * 30).ceil();
        break;
      case 'Workout Frequency':
        daysToComplete = 60;
        break;
      case 'Strength (Total Volume)':
        daysToComplete = 180;
        break;
      case 'Cardiovascular Endurance':
        daysToComplete = 90;
        break;
      case 'Flexibility':
        daysToComplete = 120;
        break;
    }

    daysToComplete = daysToComplete.clamp(14, 365);

    setState(() {
      _aiSuggestedDate = DateTime.now().add(Duration(days: daysToComplete));
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

  bool get _hasAllRequiredMetrics =>
      _currentWeight != null &&
      _currentHeight != null &&
      _currentActivityLevel != null;

  /// Check if body metrics are stale (older than 30 days)
  bool get _areMetricsStale {
    if (_metricsRecordedAt == null) return false;
    final daysSinceUpdate =
        DateTime.now().difference(_metricsRecordedAt!).inDays;
    return daysSinceUpdate > 30;
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

  Future<void> _selectTargetDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now().add(
        const Duration(days: 1),
      ), // Must be in future
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

  Future<void> _createGoal() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedGoalType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
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
            (context) => AlertDialog(
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
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Edit Goal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create Anyway'),
                ),
              ],
            ),
      );

      if (proceed != true) return;
    }

    setState(() => _isCreating = true);

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

    final provider = context.read<GoalsProvider>();
    final createdGoal = await provider.createGoal(goal);

    if (mounted) {
      setState(() => _isCreating = false);

      if (createdGoal != null) {
        Navigator.pop(context, createdGoal);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Goal created successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Failed to create goal'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
              'Your metrics are $daysSince days old. Consider updating them for accurate calculations.',
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
    if (!_hasAllRequiredMetrics) return const SizedBox.shrink();

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Goal'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show metrics warning if any are missing
              if (_metricsLoaded && !_hasAllRequiredMetrics)
                _buildMissingMetricsWarning(),

              // Show stale metrics warning
              if (_metricsLoaded && _hasAllRequiredMetrics && _areMetricsStale)
                _buildStaleMetricsWarning(),

              // Show current stats if all metrics available
              if (_metricsLoaded && _hasAllRequiredMetrics && !_areMetricsStale)
                _buildCurrentStatsCard(),

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
                  if (value == null) {
                    return 'Please select a goal type';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _currentValueController,
                decoration: InputDecoration(
                  labelText:
                      _isWeightGoal() ? 'Current Weight' : 'Current Value',
                  prefixIcon: const Icon(Icons.trending_up),
                  helperText: 'Your starting point',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: Colors.green.shade600,
                    ),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                  if (value != null) {
                    setState(() => _selectedUnit = value);
                  }
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
                    style: TextStyle(
                      color: _targetDate != null ? null : Colors.grey,
                    ),
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed:
              (_isCreating || !_hasAllRequiredMetrics) ? null : _createGoal,
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
      ],
    );
  }
}
