import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sessions/sessions_screen.dart';
import 'goals/goals_screen.dart';
import 'exercises/exercises_screen.dart';
import 'profile/profile_screen.dart';
import '../../core/services/tab_navigation_service.dart';
import '../../core/theme/theme_colors.dart';
import '../widgets/common/curved_navigation_bar.dart';

/// Main screen wrapper with bottom navigation
/// Provides 4-tab navigation: Dashboard, Diary, Exercises, More
/// Features convex bump navigation bar with AI Coach FAB on top
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

    // Set initial tab in TabNavigationService if provided
    if (widget.initialTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<TabNavigationService>().switchTab(
          widget.initialTab!,
          subTabIndex: widget.initialSubTab,
        );
      });
    }

    // Create screens with initial sub-tab if provided
    // 4 tabs: Dashboard (Sessions), Goals, Exercises, More (Profile)
    _screens = [
      SessionsScreen(initialTab: widget.initialSubTab),
      const GoalsScreen(),
      const ExercisesScreen(),
      const ProfileScreen(),
    ];
  }

  void _onFabPressed(BuildContext context) {
    // Show quick action menu
    _showQuickActionsMenu(context);
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
                    Navigator.pushNamed(context, '/new-session');
                  },
                ),
                _QuickActionItem(
                  icon: Icons.calendar_today,
                  label: 'Plan Workout',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/plan-workout');
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
                _QuickActionItem(
                  icon: Icons.add_circle_outline,
                  label: 'Add Exercise',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/add-exercise');
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
      body: IndexedStack(index: tabService.currentTab, children: _screens),
      bottomNavigationBar: CurvedNavigationBar(
        currentIndex: tabService.currentTab,
        onTap: (index) {
          tabService.switchTab(index);
        },
        onFabTap: () => _onFabPressed(context),
        items: const [
          CurvedNavigationBarItem(
            icon: Icons.dashboard_rounded,
            label: 'Dashboard',
          ),
          CurvedNavigationBarItem(icon: Icons.flag_outlined, label: 'Goals'),
          CurvedNavigationBarItem(
            icon: Icons.fitness_center,
            label: 'Exercises',
          ),
          CurvedNavigationBarItem(icon: Icons.menu, label: 'More'),
        ],
      ),
    );
  }
}

/// Quick action item widget for the bottom sheet menu
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
