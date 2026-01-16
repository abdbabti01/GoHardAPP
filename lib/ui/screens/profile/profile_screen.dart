import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/active_workout_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../routes/route_names.dart';
import '../../../core/constants/api_config.dart';
import '../../widgets/common/dark_selection_card.dart';
import 'edit_profile_screen.dart';
import '../body_metrics/body_metrics_screen.dart';

/// Profile screen for viewing user information and settings
/// Now serves as the "More" tab with dark card styling
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Load user profile on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileProvider>().loadUserProfile();
    });
  }

  Future<void> _handleRefresh() async {
    await context.read<ProfileProvider>().loadUserProfile();
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text('Logout', style: TextStyle(color: Colors.white)),
            content: const Text(
              'Are you sure you want to logout?',
              style: TextStyle(color: Color(0xFFB0B0B0)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Logout'),
              ),
            ],
          ),
    );

    if (confirmed == true && mounted) {
      // Clear all provider states before logout
      context.read<SessionsProvider>().clear();
      context.read<ActiveWorkoutProvider>().clear();
      context.read<ProfileProvider>().clear();
      context.read<ChatProvider>().clear();

      await context.read<AuthProvider>().logout();

      if (mounted) {
        // Navigate to login and clear navigation stack
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Consumer<ProfileProvider>(
        builder: (context, provider, child) {
          // Loading state
          if (provider.isLoading && provider.currentUser == null) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF34C759)),
            );
          }

          // Error state
          if (provider.errorMessage != null &&
              provider.errorMessage!.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Error Loading Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF8E8E93)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  DarkActionButton(label: 'Retry', onPressed: _handleRefresh),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _handleRefresh,
            color: const Color(0xFF34C759),
            backgroundColor: const Color(0xFF1C1C1E),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        'More',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Profile header card
                    _buildProfileHeader(context, provider),
                    const SizedBox(height: 16),

                    // Quick Stats
                    _buildQuickStats(context, provider),
                    const SizedBox(height: 16),

                    // Menu items
                    _buildMenuSection(context),
                    const SizedBox(height: 16),

                    // App section
                    _buildAppSection(context),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, ProfileProvider provider) {
    final user = provider.currentUser;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditProfileScreen()),
        );
        if (mounted) {
          _handleRefresh();
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF38383A), width: 1),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF2C2C2E),
              backgroundImage:
                  user?.profilePhotoUrl != null
                      ? NetworkImage(
                        ApiConfig.getPhotoUrl(user!.profilePhotoUrl!),
                      )
                      : null,
              child:
                  user?.profilePhotoUrl == null
                      ? const Icon(
                        Icons.person,
                        size: 30,
                        color: Color(0xFF8E8E93),
                      )
                      : null,
            ),
            const SizedBox(width: 16),
            // Name and email
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<String>(
                    future: provider.getUserName(),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? 'Loading...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<String>(
                    future: provider.getUserEmail(),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? '',
                        style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 14,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF8E8E93), size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context, ProfileProvider provider) {
    final user = provider.currentUser;
    final stats = user?.stats;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38383A), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            Icons.fitness_center,
            stats?.totalWorkouts.toString() ?? '-',
            'Workouts',
          ),
          Container(width: 1, height: 50, color: const Color(0xFF38383A)),
          _buildStatItem(
            Icons.local_fire_department,
            stats?.currentStreak.toString() ?? '-',
            'Streak',
          ),
          Container(width: 1, height: 50, color: const Color(0xFF38383A)),
          _buildStatItem(
            Icons.trending_up,
            stats?.personalRecords.toString() ?? '-',
            'PRs',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 28, color: const Color(0xFF34C759)),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38383A), width: 1),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.list,
            label: 'Exercises',
            onTap: () => Navigator.pushNamed(context, RouteNames.exercises),
          ),
          _buildMenuDivider(),
          _buildMenuItem(
            icon: Icons.analytics,
            label: 'Analytics',
            onTap: () => Navigator.pushNamed(context, RouteNames.analytics),
          ),
          _buildMenuDivider(),
          _buildMenuItem(
            icon: Icons.monitor_weight,
            label: 'Body Metrics',
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BodyMetricsScreen()),
                ),
          ),
          _buildMenuDivider(),
          _buildMenuItem(
            icon: Icons.bookmark,
            label: 'Templates',
            onTap: () => Navigator.pushNamed(context, RouteNames.templates),
          ),
          _buildMenuDivider(),
          _buildMenuItem(
            icon: Icons.people,
            label: 'Community',
            onTap: () => Navigator.pushNamed(context, RouteNames.community),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF8E8E93), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuDivider() {
    return Container(
      margin: const EdgeInsets.only(left: 66),
      height: 0.5,
      color: const Color(0xFF38383A),
    );
  }

  Widget _buildAppSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38383A), width: 1),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.settings,
            label: 'Settings',
            onTap: () => Navigator.pushNamed(context, RouteNames.settings),
          ),
          _buildMenuDivider(),
          _buildMenuItem(
            icon: Icons.logout,
            label: 'Logout',
            onTap: _handleLogout,
          ),
        ],
      ),
    );
  }
}
