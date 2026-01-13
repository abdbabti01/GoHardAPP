import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../providers/goals_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/goal_progress.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/goal_reminder_preferences.dart';
import '../../../routes/route_names.dart';
import '../analytics/analytics_screen.dart';

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
                return const Center(child: CircularProgressIndicator());
              }

              if (provider.errorMessage != null) {
                return _buildErrorState(provider);
              }

              if (provider.activeGoals.isEmpty &&
                  provider.completedGoals.isEmpty) {
                return _buildEmptyState();
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
                          'Active Goals',
                          provider.activeGoals.length,
                        ),
                        ...provider.activeGoals.map(
                          (goal) => _buildEnhancedGoalCard(goal),
                        ),
                      ],

                      // Completed Goals Section
                      if (provider.completedGoals.isNotEmpty) ...[
                        _buildSectionHeader(
                          'Completed',
                          provider.completedGoals.length,
                        ),
                        ...provider.completedGoals.map(
                          (goal) => _buildCompletedGoalCard(goal),
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

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isWeightGoal(Goal goal) {
    final type = goal.goalType.toLowerCase();
    return type.contains('weight') || type.contains('muscle');
  }

  double _calculateCurrentWeight(Goal goal) {
    if (goal.isDecreaseGoal) {
      // Weight loss: subtract progress from starting weight
      return goal.currentValue - goal.totalProgress;
    } else {
      // Muscle gain: add progress to starting weight
      return goal.currentValue + goal.totalProgress;
    }
  }

  Widget _buildEnhancedGoalCard(Goal goal) {
    final progress = (goal.progressPercentage / 100).clamp(0.0, 1.0);
    final isCompleted = goal.progressPercentage >= 100;
    final goalColor = _getGoalColor(goal.goalType); // Keep original color
    final goalIcon = _getGoalIcon(goal.goalType);
    final streak = _calculateStreak(goal);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white, // Keep white background
        borderRadius: BorderRadius.circular(20),
        // Add subtle green left border accent when completed
        border:
            isCompleted
                ? Border(left: BorderSide(color: Colors.green, width: 4))
                : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Icon and Menu
            Row(
              children: [
                // Goal Icon with circular progress
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: goalColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(goalColor),
                      ),
                    ),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: goalColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(goalIcon, color: goalColor, size: 26),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // Goal Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatGoalType(goal.goalType),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        goal.getProgressDescription(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Menu
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'create_program',
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome, size: 20),
                              SizedBox(width: 12),
                              Text('Create Program'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'reminder',
                          child: Row(
                            children: [
                              Icon(Icons.notifications_outlined, size: 20),
                              SizedBox(width: 12),
                              Text('Set Reminder'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'complete',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, size: 20),
                              SizedBox(width: 12),
                              Text('Mark Complete'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Colors.red,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                  onSelected: (value) => _handleGoalAction(goal, value),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Weight/Value summary (for weight loss AND muscle gain goals)
            if (_isWeightGoal(goal)) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: goalColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: goalColor.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildWeightStat(
                      'Starting',
                      '${goal.startValue.toStringAsFixed(1)} ${goal.unit ?? ''}',
                      Colors.grey.shade600,
                    ),
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.grey.shade300,
                    ),
                    _buildWeightStat(
                      'Current',
                      '${_calculateCurrentWeight(goal).toStringAsFixed(1)} ${goal.unit ?? ''}',
                      goalColor,
                    ),
                    Container(
                      height: 30,
                      width: 1,
                      color: Colors.grey.shade300,
                    ),
                    _buildWeightStat(
                      'Target',
                      '${goal.targetValue.toStringAsFixed(1)} ${goal.unit ?? ''}',
                      Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Progress percentage and streak
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${goal.progressPercentage.toStringAsFixed(0)}% Complete',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: goalColor,
                  ),
                ),
                if (streak > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Text(
                          '$streak day${streak > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Add Progress Button OR Completion Badge
            if (isCompleted) ...[
              // Goal Completed Badge (subtle design)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Goal Completed 🎉',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Add Progress Button (only if not completed)
              SizedBox(
                width: double.infinity,
                child: _buildQuickActionButton(
                  'Add Progress',
                  goalColor,
                  () => _showAddProgressDialog(goal),
                ),
              ),
            ],

            // AI Suggestion card (only show if not completed)
            if (!isCompleted && goal.getProgressSuggestion() != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      goalColor.withValues(alpha: 0.1),
                      goalColor.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: goalColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 20, color: goalColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        goal.getProgressSuggestion()!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade800,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Target date if set
            if (goal.targetDate != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Target: ${DateFormat('MMM d, y').format(goal.targetDate!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  Text(
                    _getDaysRemaining(goal.targetDate!),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getDaysRemainingColor(goal.targetDate!),
                    ),
                  ),
                ],
              ),
            ],

            // View Programs badge
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                // Navigate to Programs tab in Sessions screen (index 1)
                Navigator.pushNamed(
                  context,
                  RouteNames.main,
                  arguments:
                      0, // Sessions tab, which contains Programs as second tab
                ).then((_) {
                  // Optional: could add logic to filter programs by this goal
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_view_week,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'View Programs',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 10,
                      color: Colors.blue,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionButton(
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedGoalCard(Goal goal) {
    final goalColor = Colors.green;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: goalColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: goalColor, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatGoalType(goal.goalType),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Completed ${DateFormat('MMM d').format(goal.completedAt!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getGoalColor(String goalType) {
    switch (goalType.toLowerCase()) {
      case 'weight':
        return Colors.blue;
      case 'workoutfrequency':
        return Colors.purple;
      case 'volume':
        return Colors.orange;
      case 'bodyfat':
        return Colors.teal;
      case 'exercise':
        return Colors.red;
      default:
        return Colors.indigo;
    }
  }

  IconData _getGoalIcon(String goalType) {
    switch (goalType.toLowerCase()) {
      case 'weight':
        return Icons.monitor_weight;
      case 'workoutfrequency':
        return Icons.fitness_center;
      case 'volume':
        return Icons.trending_up;
      case 'bodyfat':
        return Icons.spa;
      case 'exercise':
        return Icons.sports_gymnastics;
      default:
        return Icons.flag;
    }
  }

  String _formatGoalType(String goalType) {
    return goalType
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(0)}')
        .trim();
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

  String _getDaysRemaining(DateTime targetDate) {
    final now = DateTime.now();
    final difference =
        targetDate.difference(DateTime(now.year, now.month, now.day)).inDays;

    if (difference < 0) {
      return '${difference.abs()} days overdue';
    } else if (difference == 0) {
      return 'Due today!';
    } else if (difference == 1) {
      return '1 day left';
    } else {
      return '$difference days left';
    }
  }

  Color _getDaysRemainingColor(DateTime targetDate) {
    final difference = targetDate.difference(DateTime.now()).inDays;

    if (difference < 0) return Colors.red;
    if (difference <= 7) return Colors.orange;
    return Colors.grey.shade600;
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

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
        await provider.deleteGoal(goal.id);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flag_outlined, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 24),
            const Text(
              'No Goals Yet',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Set your first goal and start tracking your progress',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showCreateGoalDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Goal'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(GoalsProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(provider.errorMessage!),
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
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Add'),
        ),
      ],
    );
  }
}
