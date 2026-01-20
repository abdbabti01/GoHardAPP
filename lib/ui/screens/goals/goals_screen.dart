import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../providers/goals_provider.dart';
import '../../../providers/programs_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/goal_progress.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/goal_reminder_preferences.dart';
import '../../../routes/route_names.dart';
import '../analytics/analytics_screen.dart';
import '../../widgets/goals/premium_goal_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/premium_bottom_sheet.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GoalsProvider>().loadGoals();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goals & Stats'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showCreateGoalDialog(context),
            tooltip: 'Create Goal',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [Tab(text: 'Goals'), Tab(text: 'Stats')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Consumer<GoalsProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return const Center(child: PremiumLoader());
              }

              if (provider.errorMessage != null) {
                return _buildErrorState(context, provider);
              }

              if (provider.activeGoals.isEmpty &&
                  provider.completedGoals.isEmpty) {
                return _buildEmptyState(context);
              }

              return RefreshIndicator(
                onRefresh: () => provider.loadGoals(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Active Goals Section
                      if (provider.activeGoals.isNotEmpty) ...[
                        _buildSectionHeader(
                          context,
                          'Active Goals',
                          provider.activeGoals.length,
                        ),
                        ...provider.activeGoals.map(
                          (goal) => PremiumGoalCard(
                            goal: goal,
                            streak: _calculateStreak(goal),
                            onAddProgress: () => _showAddProgressDialog(goal),
                            onMenuAction:
                                (action) => _handleGoalAction(goal, action),
                          ),
                        ),
                      ],

                      // Completed Goals Section
                      if (provider.completedGoals.isNotEmpty) ...[
                        _buildSectionHeader(
                          context,
                          'Completed',
                          provider.completedGoals.length,
                        ),
                        ...provider.completedGoals.map(
                          (goal) => CompletedGoalCard(goal: goal),
                        ),
                      ],

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              );
            },
          ),
          const AnalyticsScreen(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.headline.copyWith(color: context.textPrimary),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: AppTypography.labelLarge.copyWith(
                color: context.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _calculateStreak(Goal goal) {
    // Simple streak calculation based on progress history
    // In a real implementation, this would check consecutive days with progress
    if (goal.progressHistory == null || goal.progressHistory!.isEmpty) {
      return 0;
    }

    int streak = 0;
    DateTime now = DateTime.now();

    for (int i = 0; i < 30; i++) {
      DateTime checkDate = now.subtract(Duration(days: i));
      bool hasProgress = goal.progressHistory!.any((p) {
        DateTime progressDate = p.recordedAt;
        return progressDate.year == checkDate.year &&
            progressDate.month == checkDate.month &&
            progressDate.day == checkDate.day;
      });

      if (hasProgress) {
        streak++;
      } else if (i > 0) {
        break;
      }
    }

    return streak;
  }

  void _handleGoalAction(Goal goal, String action) async {
    final provider = context.read<GoalsProvider>();

    if (action == 'create_program') {
      // Navigate to workout plan form with goal info pre-filled
      Navigator.pushNamed(
        context,
        RouteNames.workoutPlanForm,
        arguments: {'goalId': goal.id, 'prefilledGoal': goal.goalType},
      );
    } else if (action == 'reminder') {
      await _showReminderDialog(goal);
    } else if (action == 'complete') {
      final confirmed = await _showConfirmDialog(
        'Complete Goal',
        'Mark this goal as completed?',
      );
      if (confirmed == true && mounted) {
        await provider.completeGoal(goal.id);
      }
    } else if (action == 'delete') {
      await _showDeleteGoalConfirmation(goal);
    }
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );
  }

  void _showCreateGoalDialog(BuildContext context) async {
    final createdGoal = await showDialog<Goal>(
      context: context,
      builder: (context) => const CreateGoalDialog(),
    );

    // If goal was created, ask if user wants to generate workout plan
    if (createdGoal != null && context.mounted) {
      _showWorkoutPlanDialog(context, createdGoal);
    }
  }

  void _showAddProgressDialog(Goal goal) {
    showDialog(
      context: context,
      builder: (context) => AddProgressDialog(goal: goal),
    );
  }

  Future<void> _showDeleteGoalConfirmation(Goal goal) async {
    // Fetch deletion impact
    final provider = context.read<GoalsProvider>();

    // Show loading dialog
    PremiumLoadingDialog.show(context, message: 'Creating goal...');

    try {
      final impact = await provider.getDeletionImpact(goal.id);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Show confirmation with impact
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('⚠️ Delete Goal?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to delete "${goal.goalType}"?',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if ((impact['programsCount'] ?? 0) > 0 ||
                      (impact['sessionsCount'] ?? 0) > 0) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'This will permanently delete:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if ((impact['programsCount'] ?? 0) > 0)
                      Text(
                        '• ${impact['programsCount']} Program(s) with all their workouts',
                        style: const TextStyle(fontSize: 14),
                      ),
                    if ((impact['sessionsCount'] ?? 0) > 0)
                      Text(
                        '• ${impact['sessionsCount']} Workout Session(s) with all exercises and sets',
                        style: const TextStyle(fontSize: 14),
                      ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.red,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This action cannot be undone!',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
      );

      if (confirmed == true && mounted) {
        final success = await provider.deleteGoal(goal.id);

        if (success && mounted) {
          // Reload programs and sessions to remove cascade-deleted items
          await Future.wait([
            context.read<ProgramsProvider>().loadPrograms(),
            context.read<SessionsProvider>().loadSessions(waitForSync: true),
          ]);
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: EmptyState(
          icon: Icons.flag_outlined,
          title: 'No Goals Yet',
          message:
              'Set your first goal and start tracking your fitness journey',
          suggestions: [
            QuickSuggestion(
              label: 'Create Goal',
              icon: Icons.add_rounded,
              onTap: () => _showCreateGoalDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, GoalsProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: context.error),
          const SizedBox(height: 16),
          Text(
            provider.errorMessage!,
            style: TextStyle(color: context.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => provider.loadGoals(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReminderDialog(Goal goal) async {
    final prefs = GoalReminderPreferences();
    final notificationService = NotificationService();

    // Load current reminder settings
    final currentSetting = await prefs.getReminderPreference(goal.id);

    // Dialog state
    bool reminderEnabled = currentSetting?.enabled ?? false;
    String selectedFrequency = currentSetting?.frequency ?? 'weekly';
    TimeOfDay selectedTime =
        currentSetting != null
            ? TimeOfDay(
              hour: currentSetting.hour,
              minute: currentSetting.minute,
            )
            : const TimeOfDay(hour: 18, minute: 0);

    if (!mounted) return;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Row(
                    children: [
                      const Icon(Icons.notifications_active, size: 24),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Progress Reminder')),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Goal name
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            goal.goalType,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Enable/Disable switch
                        SwitchListTile(
                          title: const Text('Enable Reminder'),
                          subtitle: const Text(
                            'Get notified to update your progress',
                          ),
                          value: reminderEnabled,
                          onChanged: (value) {
                            setState(() {
                              reminderEnabled = value;
                            });
                          },
                        ),

                        const SizedBox(height: 16),

                        // Frequency selection (only shown when enabled)
                        if (reminderEnabled) ...[
                          const Text(
                            'Frequency',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...[
                            'daily',
                            'every2days',
                            'every3days',
                            'weekly',
                            'biweekly',
                          ].map(
                            (freq) => RadioListTile<String>(
                              title: Text(_getFrequencyDisplay(freq)),
                              value: freq,
                              groupValue: selectedFrequency,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    selectedFrequency = value;
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Time selection
                          const Text(
                            'Time',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            leading: const Icon(Icons.access_time),
                            title: Text(
                              selectedTime.format(context),
                              style: const TextStyle(fontSize: 16),
                            ),
                            trailing: const Icon(Icons.edit),
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );
                              if (time != null) {
                                setState(() {
                                  selectedTime = time;
                                });
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        // Capture context before async operations
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        final timeString = selectedTime.format(context);

                        // Save reminder preference
                        await prefs.saveReminderPreference(
                          goalId: goal.id,
                          frequency: selectedFrequency,
                          hour: selectedTime.hour,
                          minute: selectedTime.minute,
                          enabled: reminderEnabled,
                        );

                        if (reminderEnabled) {
                          // Request notification permissions if not granted
                          final hasPermission =
                              await notificationService.requestPermissions();
                          if (!hasPermission) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Notification permissions not granted. Please enable in settings.',
                                ),
                              ),
                            );
                            navigator.pop();
                            return;
                          }

                          // Schedule the reminder
                          await notificationService.scheduleGoalReminder(
                            goalId: goal.id,
                            goalName: goal.goalType,
                            goalType: goal.goalType,
                            frequency: selectedFrequency,
                            hour: selectedTime.hour,
                            minute: selectedTime.minute,
                          );

                          if (!mounted) return;
                          final displayText =
                              'Reminder set: ${_getFrequencyDisplay(selectedFrequency)} at $timeString';
                          messenger.showSnackBar(
                            SnackBar(content: Text(displayText)),
                          );
                        } else {
                          // Cancel the reminder
                          await notificationService.cancelGoalReminder(goal.id);

                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Reminder disabled')),
                          );
                        }

                        if (!mounted) return;
                        navigator.pop();
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
  }

  String _getFrequencyDisplay(String frequency) {
    switch (frequency.toLowerCase()) {
      case 'daily':
        return 'Daily';
      case 'every2days':
        return 'Every 2 days';
      case 'every3days':
        return 'Every 3 days';
      case 'weekly':
        return 'Weekly';
      case 'biweekly':
        return 'Every 2 weeks';
      default:
        return 'Weekly';
    }
  }

  void _showWorkoutPlanDialog(BuildContext context, Goal goal) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.fitness_center,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Generate Workout Plan?')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Would you like AI to create a personalized workout plan to help you reach this goal?',
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.goalType,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        goal.getProgressDescription(),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Maybe Later'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _navigateToWorkoutPlanChat(context, goal);
                },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Generate Plan'),
              ),
            ],
          ),
    );
  }

  Future<void> _navigateToWorkoutPlanChat(
    BuildContext context,
    Goal goal,
  ) async {
    try {
      final chatProvider = context.read<ChatProvider>();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Creating workout plan chat...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final prompt = _generateWorkoutPlanPrompt(goal);

      final conversation = await chatProvider.createConversation(
        title: 'Workout Plan: ${goal.goalType}',
        type: 'workout_plan',
      );

      if (conversation != null && context.mounted) {
        await Navigator.pushNamed(
          context,
          RouteNames.chatConversation,
          arguments: {
            'conversationId': conversation.id,
            'initialMessage': prompt,
            'goalId': goal.id, // Pass goalId to chat
          },
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                chatProvider.errorMessage ?? 'Failed to create conversation',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _generateWorkoutPlanPrompt(Goal goal) {
    String prompt;

    if (goal.goalType.toLowerCase().contains('loss')) {
      final totalToLose = goal.currentValue - goal.targetValue;
      prompt =
          'Create a comprehensive workout plan to help me lose ${totalToLose.toStringAsFixed(0)} ${goal.unit ?? ''} (from ${goal.currentValue.toStringAsFixed(0)} to ${goal.targetValue.toStringAsFixed(0)} ${goal.unit ?? ''})';
    } else if (goal.goalType.toLowerCase().contains('muscle') ||
        goal.goalType.toLowerCase().contains('gain')) {
      final totalToGain = goal.targetValue - goal.currentValue;
      prompt =
          'Create a comprehensive workout plan to help me gain ${totalToGain.toStringAsFixed(0)} ${goal.unit ?? ''} of muscle (from ${goal.currentValue.toStringAsFixed(0)} to ${goal.targetValue.toStringAsFixed(0)} ${goal.unit ?? ''})';
    } else {
      prompt =
          'Create a comprehensive workout plan to help me achieve my ${goal.goalType} goal (target: ${goal.targetValue.toStringAsFixed(0)} ${goal.unit ?? ''})';
    }

    if (goal.targetDate != null) {
      final months = goal.targetDate!.difference(DateTime.now()).inDays ~/ 30;
      if (months > 0) {
        prompt +=
            ' within the next $months ${months == 1 ? 'month' : 'months'}';
      }
    }

    prompt +=
        '.\n\nPlease include:\n- Weekly workout schedule\n- Specific exercises with sets and reps\n- Progressive overload strategy\n- Rest and recovery recommendations';

    return prompt;
  }
}

// Import the dialog classes from the original goals_screen.dart
// These remain unchanged
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

  void _calculateAISuggestedDate() {
    if (_selectedGoalType == null) return;

    final currentValue = double.tryParse(_currentValueController.text) ?? 0;
    final targetValue = double.tryParse(_targetValueController.text);

    if (targetValue == null || currentValue == 0) return;

    final difference = (targetValue - currentValue).abs();
    int daysToComplete = 90; // Default 3 months

    // AI-suggested timelines based on goal type and realistic progress rates
    switch (_selectedGoalType!) {
      case 'Weight Loss':
        // Healthy weight loss: 1-2 lbs/week
        final weeksNeeded = difference / 1.5; // 1.5 lbs/week average
        daysToComplete = (weeksNeeded * 7).ceil();
        break;

      case 'Muscle Gain':
        // Realistic muscle gain: 0.5-1 lb/week for beginners
        final weeksNeeded = difference / 0.75; // 0.75 lbs/week average
        daysToComplete = (weeksNeeded * 7).ceil();
        break;

      case 'Body Fat':
        // Healthy body fat loss: 0.5-1% per month
        final monthsNeeded = difference / 0.75; // 0.75% per month
        daysToComplete = (monthsNeeded * 30).ceil();
        break;

      case 'Workout Frequency':
        // Build habit gradually
        daysToComplete = 60; // 2 months to establish routine
        break;

      case 'Strength (Total Volume)':
        // Progressive overload: 5-10% increase per month
        final monthsNeeded = 6; // 6 months for significant strength gains
        daysToComplete = monthsNeeded * 30;
        break;

      case 'Cardiovascular Endurance':
        // Gradual cardio improvement
        daysToComplete = 90; // 3 months typical
        break;

      case 'Flexibility':
        // Flexibility takes time
        daysToComplete = 120; // 4 months
        break;
    }

    // Cap at 12 months, minimum 14 days
    daysToComplete = daysToComplete.clamp(14, 365);

    setState(() {
      _aiSuggestedDate = DateTime.now().add(Duration(days: daysToComplete));
      _targetDate = _aiSuggestedDate; // Auto-set to AI suggestion
    });
  }

  @override
  void initState() {
    super.initState();
    // Listen to value changes to recalculate AI suggestion
    _targetValueController.addListener(_calculateAISuggestedDate);
    _currentValueController.addListener(_calculateAISuggestedDate);
  }

  Future<void> _selectTargetDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Target Date',
    );

    if (picked != null) {
      setState(() {
        _targetDate = picked;
      });
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

    setState(() => _isCreating = true);

    final goal = Goal(
      id: 0,
      userId: 0,
      goalType: _selectedGoalType!,
      targetValue: double.parse(_targetValueController.text),
      currentValue: double.tryParse(_currentValueController.text) ?? 0,
      unit: _selectedUnit,
      timeFrame: null, // Removed - not needed for goal tracking
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
        // Return the created goal with server ID to parent
        Navigator.pop(context, createdGoal);

        // Show success message on parent screen
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
                    // Reset unit to first available option when goal type changes
                    if (value != null) {
                      _selectedUnit = _availableUnits.first;
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
              // Current Weight/Value field (starting point) - shown FIRST
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
              const SizedBox(height: 16),
              // Target Weight/Value field - shown SECOND
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
                    const SizedBox(
                      width: 40,
                    ), // Align with InputDecorator content
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
          onPressed: _isCreating ? null : _createGoal,
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

class AddProgressDialog extends StatefulWidget {
  final Goal goal;

  const AddProgressDialog({super.key, required this.goal});

  @override
  State<AddProgressDialog> createState() => _AddProgressDialogState();
}

class _AddProgressDialogState extends State<AddProgressDialog> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isAdding = false;

  String _getProgressLabel() {
    if (widget.goal.isDecreaseGoal) {
      return 'Amount Lost';
    } else {
      final type = widget.goal.goalType.toLowerCase();
      if (type.contains('weight') || type.contains('muscle')) {
        return 'Amount Gained';
      } else {
        return 'Progress Made';
      }
    }
  }

  String _getProgressHelperText() {
    if (widget.goal.isDecreaseGoal) {
      return 'Enter how much you lost (e.g., 2 for 2 lbs lost)';
    } else {
      final type = widget.goal.goalType.toLowerCase();
      if (type.contains('weight') || type.contains('muscle')) {
        return 'Enter how much you gained (e.g., 2 for 2 lbs gained)';
      } else {
        return 'Enter your progress (e.g., 3 for 3 workouts completed)';
      }
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addProgress() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isAdding = true);

    final progress = GoalProgress(
      id: 0,
      goalId: widget.goal.id,
      recordedAt: DateTime.now(),
      value: double.parse(_valueController.text),
      notes:
          _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
    );

    final provider = context.read<GoalsProvider>();
    final success = await provider.addProgress(widget.goal.id, progress);

    if (mounted) {
      setState(() => _isAdding = false);

      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Progress added successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Failed to add progress'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Progress'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.goal.goalType,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            // Show current progress
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.goal.getProgressDescription(),
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            // Progress input field
            TextFormField(
              controller: _valueController,
              decoration: InputDecoration(
                labelText: _getProgressLabel(),
                suffixText: widget.goal.unit,
                prefixIcon: const Icon(Icons.add_circle_outline),
                helperText: _getProgressHelperText(),
                helperMaxLines: 2,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter progress';
                }
                final num = double.tryParse(value);
                if (num == null) {
                  return 'Please enter a valid number';
                }
                if (num <= 0) {
                  return 'Progress must be greater than 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.note),
                hintText: 'Add a note about your progress...',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isAdding ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isAdding ? null : _addProgress,
          child:
              _isAdding
                  ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.accent,
                    ),
                  )
                  : const Text('Add'),
        ),
      ],
    );
  }
}
