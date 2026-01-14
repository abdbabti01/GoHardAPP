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

  @override
  Widget build(BuildContext context) {
    final tabService = context.watch<TabNavigationService>();

    return Scaffold(
      body: IndexedStack(index: tabService.currentTab, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tabService.currentTab,
        onTap: (index) {
          tabService.switchTab(index);
        },
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
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Exercises'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
