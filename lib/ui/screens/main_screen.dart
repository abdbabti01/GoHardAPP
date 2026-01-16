import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sessions/sessions_screen.dart';
import 'exercises/exercises_screen.dart';
import 'goals/goals_screen.dart';
import 'chat/chat_list_screen.dart';
import 'profile/profile_screen.dart';
import '../../core/services/tab_navigation_service.dart';

/// Main screen wrapper with bottom navigation
/// Provides 5-tab navigation: Workouts, Goals & Stats, AI Coach, Exercises, Profile
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
      SessionsScreen(initialTab: widget.initialSubTab),
      const GoalsScreen(),
      const ChatListScreen(),
      const ExercisesScreen(),
      const ProfileScreen(),
    ];
  }

  void _onFabPressed(BuildContext context, int currentTab) {
    // Contextual FAB action based on current tab
    switch (currentTab) {
      case 0: // Workouts tab
        // Navigate to new workout/session creation
        Navigator.pushNamed(context, '/new-session');
        break;
      case 1: // Goals & Stats tab
        // Could create new goal - for now, show a message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Create new goal - Coming soon!'),
            duration: Duration(seconds: 2),
          ),
        );
        break;
      case 2: // AI Coach tab
        // Navigate to new chat/conversation
        Navigator.pushNamed(context, '/chat');
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
                icon: Icon(Icons.fitness_center),
                label: 'Workouts',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.flag),
                label: 'Goals & Stats',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.psychology),
                label: 'AI Coach',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.list),
                label: 'Exercises',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
