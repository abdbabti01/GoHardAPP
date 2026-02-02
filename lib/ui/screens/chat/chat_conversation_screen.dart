import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/chat_provider.dart'
    show
        ChatProvider,
        MealPlanPreview,
        MealPlanDayPreview,
        ApplyMealPlanWeekResult;
import '../../../providers/programs_provider.dart';
import '../../../providers/goals_provider.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/common/offline_banner.dart';
import '../../widgets/common/premium_bottom_sheet.dart';
import '../../widgets/common/loading_indicator.dart';

/// Chat conversation screen showing messages and input
class ChatConversationScreen extends StatefulWidget {
  final int conversationId;
  final String? initialMessage; // Optional pre-filled message
  final int? goalId; // Optional goal to link program to
  final int? suggestedWeeks; // Suggested program duration from goal
  final int?
  suggestedDaysPerWeek; // Suggested days per week based on activity level

  const ChatConversationScreen({
    super.key,
    required this.conversationId,
    this.initialMessage,
    this.goalId,
    this.suggestedWeeks,
    this.suggestedDaysPerWeek,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Set initial message if provided
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      _messageController.text = widget.initialMessage!;
    }
    // Load conversation on first build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        debugPrint('ChatConversationScreen: Loading conversation...');
        await context.read<ChatProvider>().loadConversation(
          widget.conversationId,
        );
        debugPrint('ChatConversationScreen: Conversation loaded');

        // Auto-send initial message if provided
        if (widget.initialMessage != null &&
            widget.initialMessage!.isNotEmpty &&
            mounted) {
          debugPrint('ChatConversationScreen: Auto-sending initial message...');
          await _sendMessage();
          debugPrint('ChatConversationScreen: Initial message sent');
        }
      } catch (e, stackTrace) {
        debugPrint('ChatConversationScreen initState error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    // Clear input immediately
    _messageController.clear();

    // Send message
    final provider = context.read<ChatProvider>();
    final success = await provider.sendMessage(message);

    // Scroll to bottom after sending
    if (success && mounted) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _saveProgramPlan() async {
    final navigator = Navigator.of(context);
    final chatProvider = context.read<ChatProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Show dialog to collect program details
    final programDetails = await _showProgramDetailsDialog();

    if (programDetails == null || !mounted) return;

    // Show loading
    PremiumLoadingDialog.show(context, message: 'Creating program...');

    // Create program
    final createResult = await chatProvider.createProgramFromPlan(
      title: programDetails['title'] as String?,
      description: programDetails['description'] as String?,
      goalId: programDetails['goalId'] as int?,
      totalWeeks: programDetails['totalWeeks'] as int?,
      daysPerWeek: programDetails['daysPerWeek'] as int?,
      startDate: programDetails['startDate'] as DateTime?,
    );

    if (!mounted) return;
    navigator.pop(); // Close loading

    if (createResult != null) {
      final programId = createResult['program']['id'] as int;
      final programTitle = createResult['program']['title'] ?? 'Program';
      final workoutCount = createResult['workouts']?.length ?? 0;

      // Check if this is a combined plan (has both workout and meal plan)
      final conversation = chatProvider.currentConversation;
      final isCombinedPlan = conversation?.type == 'combined_plan';

      if (isCombinedPlan) {
        // For combined plans, ask if user wants to apply meal plan too
        if (mounted) {
          final applyMealPlan = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Program Created!'),
                  content: Text(
                    'Created "$programTitle" with $workoutCount workouts.\n\n'
                    'This plan also includes a meal plan. Would you like to apply it now?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Maybe Later'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Apply Meal Plan'),
                    ),
                  ],
                ),
          );

          if (applyMealPlan == true && mounted) {
            // Show the meal plan day selection
            await _applyMealPlanToToday();
          }
        }

        // Don't delete conversation for combined plans - user might want to apply meal plan later
        // Only navigate after user makes their choice
      } else {
        // For workout-only plans, delete the conversation
        final conversationId = chatProvider.currentConversation?.id;
        if (conversationId != null) {
          await chatProvider.deleteConversation(conversationId);
        }
      }

      // Set the newly created program ID for auto-selection
      if (mounted) {
        final programsProvider = context.read<ProgramsProvider>();
        programsProvider.setNewlyCreatedProgramId(programId);

        debugPrint('🔄 Refreshing programs after creating workout plan...');
        await programsProvider.loadPrograms();
        debugPrint('✅ Programs refreshed after program creation');
      }

      // Navigate to the Programs tab (Sessions screen, tab index 1)
      if (mounted) {
        // Pop all screens and go to main with Programs tab selected
        navigator.pushNamedAndRemoveUntil(
          RouteNames.main,
          (route) => false,
          arguments: {
            'tab': 0,
            'subTab': 1,
          }, // Sessions tab (0), Programs sub-tab (1)
        );

        // Show success message
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Created program "$programTitle" with $workoutCount workouts!',
            ),
            backgroundColor: context.accent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            chatProvider.errorMessage ?? 'Failed to create program',
          ),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _showProgramDetailsDialog() async {
    final titleController = TextEditingController(
      text:
          context.read<ChatProvider>().currentConversation?.title ??
          'My Program',
    );
    final descriptionController = TextEditingController(
      text: 'AI-generated workout program',
    );
    // Programs always start on Monday - calculate next Monday (or today if Monday)
    final now = DateTime.now();
    final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
    final startDate =
        daysUntilMonday == 0
            ? DateTime(now.year, now.month, now.day) // Today is Monday
            : DateTime(
              now.year,
              now.month,
              now.day,
            ).add(Duration(days: daysUntilMonday));
    // Use suggested values from goal, fallback to defaults
    int totalWeeks = widget.suggestedWeeks ?? 8;
    int daysPerWeek = widget.suggestedDaysPerWeek ?? 4;
    int? selectedGoalId =
        widget.goalId; // Pre-select goal if passed from navigation

    // Fetch user's goals
    final goalsProvider = context.read<GoalsProvider>();
    await goalsProvider.loadGoals();
    final activeGoals = goalsProvider.goals.where((g) => g.isActive).toList();

    if (!mounted) return null;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text('Create Program'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: titleController,
                          decoration: const InputDecoration(
                            labelText: 'Program Title',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Description (optional)',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int?>(
                          value: selectedGoalId,
                          decoration: const InputDecoration(
                            labelText: 'Link to Goal (optional)',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('No goal'),
                            ),
                            ...activeGoals.map((goal) {
                              return DropdownMenuItem<int?>(
                                value: goal.id,
                                child: Text(goal.goalType),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedGoalId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: totalWeeks,
                          decoration: const InputDecoration(
                            labelText: 'Total Weeks',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              [4, 6, 8, 10, 12, 16, 20].map((weeks) {
                                return DropdownMenuItem(
                                  value: weeks,
                                  child: Text('$weeks weeks'),
                                );
                              }).toList(),
                          onChanged: (value) {
                            if (value != null) totalWeeks = value;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: daysPerWeek,
                          decoration: const InputDecoration(
                            labelText: 'Days Per Week',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              [3, 4, 5, 6, 7].map((days) {
                                return DropdownMenuItem(
                                  value: days,
                                  child: Text('$days days/week'),
                                );
                              }).toList(),
                          onChanged: (value) {
                            if (value != null) daysPerWeek = value;
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, {
                          'title': titleController.text.trim(),
                          'description':
                              descriptionController.text.trim().isEmpty
                                  ? null
                                  : descriptionController.text.trim(),
                          'totalWeeks': totalWeeks,
                          'daysPerWeek': daysPerWeek,
                          'startDate': startDate,
                          'goalId': selectedGoalId,
                        });
                      },
                      child: const Text('Create Program'),
                    ),
                  ],
                ),
          ),
    );
  }

  /// Detect if message contains workout pattern
  bool _detectWorkoutPattern(String message) {
    // Look for patterns like "4 sets", "x 8-10 reps", "3x10", etc.
    final hasSetPattern = RegExp(
      r'\d+\s*(sets?|x)',
      caseSensitive: false,
    ).hasMatch(message);
    final hasRepPattern = RegExp(
      r'(x\s*)?\d+(-\d+)?\s*(reps?|repetitions?)',
      caseSensitive: false,
    ).hasMatch(message);
    return hasSetPattern || hasRepPattern;
  }

  /// Apply meal plan to nutrition log (supports single day or multiple days)
  Future<void> _applyMealPlanToToday() async {
    final chatProvider = context.read<ChatProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final conversationId = chatProvider.currentConversation?.id;
    if (conversationId == null) return;

    // First, preview the meal plan to get all 7 days
    PremiumLoadingDialog.show(context, message: 'Loading meal plan...');

    final preview = await chatProvider.previewMealPlan(conversationId);

    if (!mounted) return;
    navigator.pop(); // Close loading

    if (preview == null || !preview.success) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            chatProvider.errorMessage ?? 'Failed to load meal plan',
          ),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    if (preview.days.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('No meal plan days found'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    // Show day selection dialog with multi-day support
    final selection = await _showMealPlanDayPickerEnhanced(preview);

    if (selection == null || !mounted) return;

    final applyAllDays = selection['applyAll'] as bool? ?? false;
    final selectedDay = selection['day'] as int?;
    final startDate = selection['startDate'] as DateTime? ?? DateTime.now();

    if (!applyAllDays && selectedDay == null) return;

    // Apply based on selection
    if (applyAllDays) {
      // Apply all 7 days
      PremiumLoadingDialog.show(context, message: 'Applying all 7 days...');

      final result = await chatProvider.applyMealPlanWeek(
        conversationId,
        applyAllDays: true,
        startDate: startDate,
        overwriteExisting: true,
      );

      if (!mounted) return;
      navigator.pop(); // Close loading

      if (result != null && result.success) {
        // Refresh nutrition data
        if (mounted) {
          await context.read<NutritionProvider>().loadTodaysData();
        }

        // Show success dialog for multi-day
        if (mounted) {
          await _showMultiDaySuccessDialog(result, startDate);
        }
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              chatProvider.errorMessage ?? 'Failed to apply meal plan',
            ),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } else {
      // Apply single day
      PremiumLoadingDialog.show(
        context,
        message: 'Applying Day $selectedDay...',
      );

      final result = await chatProvider.applyMealPlanToToday(
        conversationId,
        day: selectedDay!,
      );

      if (!mounted) return;
      navigator.pop(); // Close loading

      if (result != null && result.success) {
        // Refresh nutrition data (includes updated goal)
        if (mounted) {
          await context.read<NutritionProvider>().loadTodaysData();
        }

        // Show success and offer to view nutrition
        if (mounted) {
          final goToNutrition = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      const Text('Meal Plan Applied!'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (result.goalUpdated) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.flag, color: Colors.blue, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Daily goal updated to ${result.newDailyCalorieGoal?.toStringAsFixed(0) ?? "?"} kcal',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Text('Day $selectedDay foods logged:'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.surfaceHighlight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            _buildStatRow(
                              'Foods Added',
                              '${result.foodsAdded}',
                            ),
                            _buildStatRow(
                              'Calories',
                              '${result.totalCaloriesAdded.toStringAsFixed(0)} kcal',
                            ),
                            _buildStatRow(
                              'Protein',
                              '${result.totalProteinAdded.toStringAsFixed(0)}g',
                            ),
                            _buildStatRow(
                              'Carbs',
                              '${result.totalCarbsAdded.toStringAsFixed(0)}g',
                            ),
                            _buildStatRow(
                              'Fat',
                              '${result.totalFatAdded.toStringAsFixed(0)}g',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Stay Here'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('View Nutrition'),
                    ),
                  ],
                ),
          );

          if (goToNutrition == true && mounted) {
            navigator.pushNamedAndRemoveUntil(
              RouteNames.main,
              (route) => false,
              arguments: {'tab': 2}, // Nutrition tab
            );
          }
        }
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              chatProvider.errorMessage ?? 'Failed to apply meal plan',
            ),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  /// Show success dialog for multi-day meal plan application
  Future<void> _showMultiDaySuccessDialog(
    ApplyMealPlanWeekResult result,
    DateTime startDate,
  ) async {
    final navigator = Navigator.of(context);
    final endDate = startDate.add(Duration(days: result.daysApplied - 1));
    final dateFormat =
        '${startDate.month}/${startDate.day} - ${endDate.month}/${endDate.day}';

    final goToNutrition = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                const Expanded(child: Text('Meal Plan Applied!')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.daysApplied} days of meals logged ($dateFormat):',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.surfaceHighlight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _buildStatRow('Total Foods', '${result.totalFoodsAdded}'),
                      _buildStatRow(
                        'Avg Calories/Day',
                        '${(result.totalCalories / result.daysApplied).toStringAsFixed(0)} kcal',
                      ),
                      _buildStatRow(
                        'Avg Protein/Day',
                        '${(result.totalProtein / result.daysApplied).toStringAsFixed(0)}g',
                      ),
                      _buildStatRow(
                        'Avg Carbs/Day',
                        '${(result.totalCarbs / result.daysApplied).toStringAsFixed(0)}g',
                      ),
                      _buildStatRow(
                        'Avg Fat/Day',
                        '${(result.totalFat / result.daysApplied).toStringAsFixed(0)}g',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay Here'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('View Nutrition'),
              ),
            ],
          ),
    );

    if (goToNutrition == true && mounted) {
      navigator.pushNamedAndRemoveUntil(
        RouteNames.main,
        (route) => false,
        arguments: {'tab': 2}, // Nutrition tab
      );
    }
  }

  /// Show enhanced day picker dialog with multi-day support
  Future<Map<String, dynamic>?> _showMealPlanDayPickerEnhanced(
    MealPlanPreview preview,
  ) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _MealPlanDayPickerSheet(preview: preview),
    );
  }

  /// Legacy day picker (kept for compatibility)
  Future<int?> _showMealPlanDayPicker(MealPlanPreview preview) async {
    final result = await _showMealPlanDayPickerEnhanced(preview);
    if (result == null) return null;
    return result['day'] as int?;
  }

  Widget _buildMacroPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  IconData _getMealIcon(String mealType) {
    final type = mealType.toLowerCase();
    if (type.contains('breakfast')) return Icons.wb_sunny_outlined;
    if (type.contains('lunch')) return Icons.restaurant;
    if (type.contains('dinner')) return Icons.dinner_dining;
    if (type.contains('snack')) return Icons.cookie_outlined;
    return Icons.restaurant_menu;
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<bool> _handleBackPressed(ChatProvider provider) async {
    if (!provider.isSending) return true; // Allow navigation if not sending

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cancel Message?'),
            content: const Text(
              'A message is currently being generated. '
              'If you leave now, the response will be lost. '
              'Do you want to cancel and leave?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Cancel & Leave'),
              ),
            ],
          ),
    );

    return shouldLeave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        return PopScope(
          canPop: !chatProvider.isSending,
          onPopInvokedWithResult: (bool didPop, dynamic result) async {
            if (didPop) return;

            final navigator = Navigator.of(context);
            final shouldLeave = await _handleBackPressed(chatProvider);
            if (shouldLeave && mounted) {
              navigator.pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Consumer<ChatProvider>(
                builder: (context, provider, child) {
                  return Text(
                    provider.currentConversation?.title ?? 'Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
              centerTitle: true,
            ),
            body: Column(
              children: [
                const OfflineBanner(),
                Expanded(
                  child: Consumer<ChatProvider>(
                    builder: (context, provider, child) {
                      if (provider.isLoading &&
                          provider.currentConversation == null) {
                        return const Center(child: PremiumLoader());
                      }

                      if (provider.errorMessage != null &&
                          provider.currentConversation == null) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                provider.errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.errorRed,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed:
                                    () => provider.loadConversation(
                                      widget.conversationId,
                                    ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }

                      final conversation = provider.currentConversation;
                      if (conversation == null) {
                        return const Center(
                          child: Text('Conversation not found'),
                        );
                      }

                      if (conversation.messages.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Start the conversation below',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // Scroll to bottom when messages change
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToBottom();
                      });

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 16,
                        ),
                        itemCount: conversation.messages.length,
                        itemBuilder: (context, index) {
                          final message = conversation.messages[index];
                          final isUser = message.role == 'user';

                          return Align(
                            alignment:
                                isUser
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                            child: Container(
                              margin: EdgeInsets.only(
                                bottom: 8,
                                left: isUser ? 48 : 0,
                                right: isUser ? 0 : 48,
                              ),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    isUser
                                        ? context.userMessageBubble
                                        : context.aiMessageBubble,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isUser)
                                    Text(
                                      message.content,
                                      style: TextStyle(
                                        color: context.userMessageText,
                                        fontSize: 16,
                                      ),
                                    )
                                  else
                                    MarkdownBody(
                                      data: message.content,
                                      styleSheet: MarkdownStyleSheet(
                                        p: TextStyle(
                                          color: context.aiMessageText,
                                          fontSize: 16,
                                        ),
                                        code: TextStyle(
                                          backgroundColor:
                                              context.surfaceElevated,
                                          color: context.textPrimary,
                                          fontFamily: 'monospace',
                                        ),
                                        codeblockDecoration: BoxDecoration(
                                          color: context.surfaceElevated,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Show "Create Program" button if AI message contains workout
                                  // Works for workout_plan and combined_plan types
                                  if (!isUser &&
                                      _detectWorkoutPattern(message.content) &&
                                      (conversation.type == 'workout_plan' ||
                                          conversation.type == 'combined_plan'))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: ElevatedButton.icon(
                                        onPressed: () => _saveProgramPlan(),
                                        icon: const Icon(
                                          Icons.calendar_view_week,
                                          size: 18,
                                        ),
                                        label: const Text('Create Program'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Theme.of(context).primaryColor,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Show "Apply Meal Plan" button for meal_plan and combined_plan types
                                  if (!isUser &&
                                      (conversation.type == 'meal_plan' ||
                                          conversation.type ==
                                              'combined_plan') &&
                                      index == conversation.messages.length - 1)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            () => _applyMealPlanToToday(),
                                        icon: const Icon(
                                          Icons.restaurant_menu,
                                          size: 18,
                                        ),
                                        label: const Text('Apply Meal Plan'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!isUser && message.model != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Model: ${message.model}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: context.textTertiary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Consumer<ChatProvider>(
                  builder: (context, provider, child) {
                    if (provider.isSending) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'AI is thinking...',
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.surface,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                maxLines: null,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onSubmitted: (value) => _sendMessage(),
                                enabled: !provider.isOffline,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed:
                                  provider.isOffline ? null : _sendMessage,
                              icon: const Icon(Icons.send),
                              color: Theme.of(context).primaryColor,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Enhanced meal plan day picker with multi-day support
class _MealPlanDayPickerSheet extends StatefulWidget {
  final MealPlanPreview preview;

  const _MealPlanDayPickerSheet({required this.preview});

  @override
  State<_MealPlanDayPickerSheet> createState() =>
      _MealPlanDayPickerSheetState();
}

class _MealPlanDayPickerSheetState extends State<_MealPlanDayPickerSheet> {
  bool _applyAllDays = false;
  DateTime _startDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final totalCalories = widget.preview.days.fold<double>(
      0,
      (sum, day) => sum + day.totalCalories,
    );
    final avgCalories = totalCalories / widget.preview.days.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder:
          (context, scrollController) => Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Apply Meal Plan',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Target: ${widget.preview.targetCalories.toStringAsFixed(0)} kcal/day',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Mode selection
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildModeButton(
                        title: 'Single Day',
                        subtitle: 'Apply one day to today',
                        isSelected: !_applyAllDays,
                        onTap: () => setState(() => _applyAllDays = false),
                        icon: Icons.today,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildModeButton(
                        title: 'All 7 Days',
                        subtitle: 'Plan the whole week',
                        isSelected: _applyAllDays,
                        onTap: () => setState(() => _applyAllDays = true),
                        icon: Icons.date_range,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Start date picker (shown for all 7 days mode)
              if (_applyAllDays) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (picked != null) {
                        setState(() => _startDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.divider),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: context.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Starting From',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.textSecondary,
                                  ),
                                ),
                                Text(
                                  '${_startDate.month}/${_startDate.day}/${_startDate.year}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: context.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: context.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Summary for all days
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '7 Days Summary',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: context.textPrimary,
                              ),
                            ),
                            Text(
                              '${avgCalories.toStringAsFixed(0)} kcal/day avg',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Will apply meals to ${_startDate.month}/${_startDate.day} - ${_startDate.add(const Duration(days: 6)).month}/${_startDate.add(const Duration(days: 6)).day}',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // Apply all button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, {
                          'applyAll': true,
                          'startDate': _startDate,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'Apply All 7 Days',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                const Divider(height: 1),
                // Days list for single day selection
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: widget.preview.days.length,
                    itemBuilder: (context, index) {
                      final day = widget.preview.days[index];
                      return _buildDayCard(day);
                    },
                  ),
                ),
              ],
            ],
          ),
    );
  }

  Widget _buildModeButton({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? context.accent.withValues(alpha: 0.1)
                  : context.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? context.accent : context.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? context.accent : context.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? context.accent : context.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: context.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(MealPlanDayPreview day) {
    final isWithinTarget = day.isWithinTarget;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: context.surfaceElevated,
      child: InkWell(
        onTap:
            () => Navigator.pop(context, {
              'applyAll': false,
              'day': day.day,
              'startDate': DateTime.now(),
            }),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isWithinTarget
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Day ${day.day}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isWithinTarget ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${day.totalCalories.toStringAsFixed(0)} kcal',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isWithinTarget ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
              if (day.summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  day.summary,
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              // Macros row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMacroPill(
                    'P',
                    '${day.totalProtein.toStringAsFixed(0)}g',
                    Colors.blue,
                  ),
                  _buildMacroPill(
                    'C',
                    '${day.totalCarbs.toStringAsFixed(0)}g',
                    Colors.amber,
                  ),
                  _buildMacroPill(
                    'F',
                    '${day.totalFat.toStringAsFixed(0)}g',
                    Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMacroPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
