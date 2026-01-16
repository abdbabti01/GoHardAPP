import 'dart:ui';
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

    // Only show FAB on certain tabs
    final showFab =
        tabService.currentTab == 0 || // Workouts
        tabService.currentTab == 2; // AI Coach

    return Scaffold(
      body: IndexedStack(index: tabService.currentTab, children: _screens),
      floatingActionButton:
          showFab
              ? FloatingActionButton(
                onPressed: () => _onFabPressed(context, tabService.currentTab),
                backgroundColor: theme.colorScheme.primary,
                elevation: 8, // Higher elevation for floating effect
                child: const Icon(Icons.add, size: 28, color: Colors.white),
              )
              : null,
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerFloat, // Float above, not docked
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(
                0xFF1C1C1E,
              ).withValues(alpha: 0.85), // Semi-transparent for blur effect
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              border: const Border(
                top: BorderSide(
                  color: Color(0xFF38383A), // Subtle top border
                  width: 0.5,
                ),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: tabService.currentTab,
              onTap: (index) {
                tabService.switchTab(index);
              },
              backgroundColor: Colors.transparent,
              selectedItemColor: theme.colorScheme.primary, // Green from theme
              unselectedItemColor: const Color(0xFF8E8E93), // Grey from theme
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
      ),
    );
  }
}
