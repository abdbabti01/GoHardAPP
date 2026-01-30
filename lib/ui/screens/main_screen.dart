import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'today/today_screen.dart';
import 'train/train_screen.dart';
import 'nutrition/nutrition_dashboard_screen.dart';
import 'me/me_screen.dart';
import '../../core/services/tab_navigation_service.dart';
import '../../core/services/push_notification_service.dart';
import '../../core/theme/theme_colors.dart';
import '../../data/services/api_service.dart';
import '../../providers/sessions_provider.dart';
import '../../providers/messages_provider.dart';
import '../../routes/route_names.dart';
import '../widgets/common/curved_navigation_bar.dart';
import '../widgets/sessions/workout_name_dialog.dart';

/// Main screen wrapper with bottom navigation
/// 4-tab navigation: Today, Train, Eat, Me
class MainScreen extends StatefulWidget {
  final int? initialTab;
  final int? initialSubTab;

  const MainScreen({super.key, this.initialTab, this.initialSubTab});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    if (widget.initialTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<TabNavigationService>().switchTab(
          widget.initialTab!,
          subTabIndex: widget.initialSubTab,
        );
      });
    }

    // Initialize push notifications after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializePushNotifications();
    });

    _screens = [
      const TodayScreen(),
      TrainScreen(initialTab: widget.initialSubTab),
      const NutritionDashboardScreen(),
      const MeScreen(),
    ];
  }

  /// Initialize FCM push notifications
  Future<void> _initializePushNotifications() async {
    try {
      final apiService = context.read<ApiService>();
      await PushNotificationService().initialize(apiService);

      // Set up notification tap handler to navigate to messages
      PushNotificationService().onNotificationTapped = (data) {
        if (data['type'] == 'message' && data['senderId'] != null) {
          final senderId = int.tryParse(data['senderId'].toString());
          if (senderId != null && mounted) {
            Navigator.pushNamed(
              context,
              '/dm-conversation',
              arguments: {'friendId': senderId},
            );
          }
        }
      };

      // Set up foreground message handler to refresh unread count
      PushNotificationService().onMessageReceived = (message) {
        if (mounted) {
          context.read<MessagesProvider>().loadUnreadCount();
        }
      };
    } catch (e) {
      debugPrint('Error initializing push notifications: $e');
    }
  }

  void _onFabPressed(BuildContext context) {
    _showQuickActionsMenu(context);
  }

  Future<void> _startWorkout(BuildContext context) async {
    final sessionsProvider = context.read<SessionsProvider>();
    final tabService = context.read<TabNavigationService>();
    final navigator = Navigator.of(context);

    final workoutName = await showDialog<String>(
      context: context,
      builder: (context) => const WorkoutNameDialog(),
    );

    if (workoutName == null || !mounted) return;

    final session = await sessionsProvider.startNewWorkout(name: workoutName);

    if (session != null && mounted) {
      tabService.switchTab(1); // Switch to Train tab
      navigator.pushNamed(RouteNames.activeWorkout, arguments: session.id);
    }
  }

  void _showQuickActionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (ctx) => Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ctx.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Quick Actions',
                    style: TextStyle(
                      color: ctx.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _QuickActionItem(
                  icon: Icons.fitness_center,
                  label: 'Start Workout',
                  onTap: () {
                    Navigator.pop(context);
                    _startWorkout(context);
                  },
                ),
                _QuickActionItem(
                  icon: Icons.calendar_today,
                  label: 'Plan Workout',
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await Navigator.pushNamed(
                      context,
                      '/plan-workout',
                    );
                    if (result == true && context.mounted) {
                      context.read<TabNavigationService>().switchTab(1);
                    }
                  },
                ),
                _QuickActionItem(
                  icon: Icons.restaurant_menu,
                  label: 'Log Food',
                  onTap: () {
                    Navigator.pop(context);
                    context.read<TabNavigationService>().switchTab(
                      2,
                    ); // Switch to Eat tab
                  },
                ),
                _QuickActionItem(
                  icon: Icons.directions_run,
                  label: 'Start Run',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, RouteNames.activeRun);
                  },
                ),
                _QuickActionItem(
                  icon: Icons.psychology,
                  label: 'Ask AI Coach',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/chat');
                  },
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabService = context.watch<TabNavigationService>();

    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: context.scaffoldBackground,
        elevation: 0,
        title: Text(
          _getTitle(tabService.currentTab),
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: _buildAppBarActions(context, tabService.currentTab),
      ),
      body: IndexedStack(index: tabService.currentTab, children: _screens),
      bottomNavigationBar: CurvedNavigationBar(
        currentIndex: tabService.currentTab,
        onTap: (index) {
          tabService.switchTab(index);
        },
        onFabTap: () => _onFabPressed(context),
        items: const [
          CurvedNavigationBarItem(icon: Icons.home_rounded, label: 'Today'),
          CurvedNavigationBarItem(icon: Icons.fitness_center, label: 'Train'),
          CurvedNavigationBarItem(icon: Icons.restaurant_menu, label: 'Eat'),
          CurvedNavigationBarItem(icon: Icons.person_outline, label: 'Me'),
        ],
      ),
    );
  }

  String _getTitle(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return 'Today';
      case 1:
        return 'Train';
      case 2:
        return 'Nutrition';
      case 3:
        return 'Profile';
      default:
        return 'GoHard';
    }
  }

  List<Widget>? _buildAppBarActions(BuildContext context, int tabIndex) {
    // Only show actions for certain tabs
    if (tabIndex == 0) {
      // Today tab - community button with unread badge
      final unreadCount = context.watch<MessagesProvider>().totalUnreadCount;
      return [
        IconButton(
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(
              unreadCount > 99 ? '99+' : unreadCount.toString(),
              style: const TextStyle(fontSize: 10),
            ),
            child: Icon(Icons.people_outline, color: context.textSecondary),
          ),
          onPressed: () {
            Navigator.pushNamed(context, '/community');
          },
          tooltip: 'Community',
        ),
      ];
    }
    if (tabIndex == 2) {
      // Nutrition tab - settings
      return [
        IconButton(
          icon: Icon(Icons.settings_outlined, color: context.textSecondary),
          onPressed: () {
            Navigator.pushNamed(context, RouteNames.nutritionGoals);
          },
        ),
      ];
    }
    return null;
  }
}

class _QuickActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: context.textPrimary, size: 22),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: context.textTertiary, size: 24),
          ],
        ),
      ),
    );
  }
}
