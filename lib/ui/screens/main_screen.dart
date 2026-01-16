import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sessions/sessions_screen.dart';
import 'analytics/analytics_screen.dart';
import 'chat/chat_list_screen.dart';
import 'profile/profile_screen.dart';
import '../../core/services/tab_navigation_service.dart';
import '../widgets/common/curved_navigation_bar.dart';

/// Main screen wrapper with bottom navigation
/// Provides 4-tab navigation: Dashboard, Diary, Plans, More
/// Features curved notch navigation bar with centered FAB
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
    // 4 tabs: Dashboard (Sessions), Diary (Analytics), Plans (AI Coach), More (Profile with exercises)
    _screens = [
      SessionsScreen(initialTab: widget.initialSubTab),
      const AnalyticsScreen(),
      const ChatListScreen(),
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
          (context) => Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
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
                    color: const Color(0xFF48484A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Quick Actions',
                    style: TextStyle(
                      color: Colors.white,
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
      backgroundColor: const Color(0xFF121212),
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
          CurvedNavigationBarItem(icon: Icons.book_outlined, label: 'Diary'),
          CurvedNavigationBarItem(
            icon: Icons.calendar_view_week_rounded,
            label: 'Plans',
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
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFF8E8E93), size: 24),
          ],
        ),
      ),
    );
  }
}
