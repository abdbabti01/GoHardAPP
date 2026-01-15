import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sessions/sessions_screen.dart';
import 'goals/goals_screen.dart';
import 'programs/programs_screen.dart';
import 'profile/profile_screen.dart';
import '../../core/services/tab_navigation_service.dart';

/// Main screen wrapper with bottom navigation
/// Provides 4-tab navigation: Dashboard (Sessions), Diary (Goals), Plans (Programs), More (Profile)
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
    _screens = [
      SessionsScreen(initialTab: widget.initialSubTab), // Dashboard
      const GoalsScreen(), // Diary
      const ProgramsScreen(), // Plans
      const ProfileScreen(), // More
    ];
  }

  void _onFabPressed(BuildContext context, int currentTab) {
    // Contextual FAB action based on current tab
    switch (currentTab) {
      case 0: // Dashboard tab (Sessions)
        // Navigate to new workout/session creation
        Navigator.pushNamed(context, '/new-session');
        break;
      case 1: // Diary tab (Goals)
        // Could create new goal - for now, show a message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Create new goal - Coming soon!'),
            duration: Duration(seconds: 2),
          ),
        );
        break;
      case 2: // Plans tab (Programs)
        // Navigate to AI workout plan generator
        Navigator.pushNamed(context, '/workout-plan-form');
        break;
      case 3: // More tab (Profile)
        // No action needed for profile tab
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabService = context.watch<TabNavigationService>();
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(index: tabService.currentTab, children: _screens),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onFabPressed(context, tabService.currentTab),
        backgroundColor: theme.primaryColor,
        elevation: 6,
        child: const Icon(Icons.add, size: 32, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: BottomNavigationBar(
            currentIndex: tabService.currentTab,
            onTap: (index) {
              tabService.switchTab(index);
            },
            backgroundColor: Colors.transparent,
            selectedItemColor: Colors.green,
            unselectedItemColor: Colors.grey.shade400,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            selectedFontSize: 12,
            unselectedFontSize: 11,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.grid_view_rounded),
                label: 'Dashboard',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_today),
                label: 'Diary',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.assignment),
                label: 'Plans',
              ),
              BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'More'),
            ],
          ),
        ),
      ),
    );
  }
}
