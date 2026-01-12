import 'package:flutter/material.dart';
import 'sessions/sessions_screen.dart';
import 'exercises/exercises_screen.dart';
import 'goals/goals_screen.dart';
import 'chat/chat_list_screen.dart';
import 'profile/profile_screen.dart';

/// Main screen wrapper with bottom navigation
/// Provides 5-tab navigation: Workouts, Goals & Stats, AI Coach, Exercises, Profile
class MainScreen extends StatefulWidget {
  final int? initialTab;

  const MainScreen({super.key, this.initialTab});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;

  // Screens for each tab
  final List<Widget> _screens = [
    const SessionsScreen(),
    const GoalsScreen(),
    const ChatListScreen(),
    const ExercisesScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
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
