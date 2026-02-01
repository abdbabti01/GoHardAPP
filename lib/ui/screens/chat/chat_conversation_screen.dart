import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/chat_provider.dart';
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

      // Delete the conversation after successful program creation
      final conversationId = chatProvider.currentConversation?.id;
      if (conversationId != null) {
        await chatProvider.deleteConversation(conversationId);
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

  /// Apply meal plan to today's nutrition log
  Future<void> _applyMealPlanToToday() async {
    final chatProvider = context.read<ChatProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final conversationId = chatProvider.currentConversation?.id;
    if (conversationId == null) return;

    // Show loading
    PremiumLoadingDialog.show(context, message: 'Applying meal plan...');

    final result = await chatProvider.applyMealPlanToToday(conversationId);

    if (!mounted) return;
    navigator.pop(); // Close loading

    if (result != null && result.success) {
      // Refresh nutrition data
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
                    Text('Goals updated & ${result.foodsAdded} foods logged:'),
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
