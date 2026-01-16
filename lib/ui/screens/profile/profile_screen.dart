import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
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
          (ctx) => AlertDialog(
            backgroundColor: ctx.surface,
            title: Text('Logout', style: TextStyle(color: ctx.textPrimary)),
            content: Text(
              'Are you sure you want to logout?',
              style: TextStyle(color: ctx.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ctx.error,
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
      backgroundColor: context.scaffoldBackground,
      body: Consumer<ProfileProvider>(
        builder: (context, provider, child) {
          // Loading state
          if (provider.isLoading && provider.currentUser == null) {
            return Center(
              child: CircularProgressIndicator(color: context.accent),
            );
          }

          // Error state
          if (provider.errorMessage != null &&
              provider.errorMessage!.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: context.error),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Profile',
                    style: TextStyle(
                      color: context.textPrimary,
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
                      style: TextStyle(color: context.textSecondary),
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
            color: context.accent,
            backgroundColor: context.surface,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        'More',
                        style: TextStyle(
                          color: context.textPrimary,
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
          color: context.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.border, width: 1),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 30,
              backgroundColor: context.surfaceElevated,
              backgroundImage:
                  user?.profilePhotoUrl != null
                      ? NetworkImage(
                        ApiConfig.getPhotoUrl(user!.profilePhotoUrl!),
                      )
                      : null,
              child:
                  user?.profilePhotoUrl == null
                      ? Icon(
                        Icons.person,
                        size: 30,
                        color: context.textTertiary,
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
                        style: TextStyle(
                          color: context.textPrimary,
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
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 14,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.textTertiary, size: 24),
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
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            context,
            Icons.fitness_center,
            stats?.totalWorkouts.toString() ?? '-',
            'Workouts',
          ),
          Container(width: 1, height: 50, color: context.border),
          _buildStatItem(
            context,
            Icons.local_fire_department,
            stats?.currentStreak.toString() ?? '-',
            'Streak',
          ),
          Container(width: 1, height: 50, color: context.border),
          _buildStatItem(
            context,
            Icons.trending_up,
            stats?.personalRecords.toString() ?? '-',
            'PRs',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(icon, size: 28, color: context.accent),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: context.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            context: context,
            icon: Icons.list,
            label: 'Exercises',
            onTap: () => Navigator.pushNamed(context, RouteNames.exercises),
          ),
          _buildMenuDivider(context),
          _buildMenuItem(
            context: context,
            icon: Icons.analytics,
            label: 'Analytics',
            onTap: () => Navigator.pushNamed(context, RouteNames.analytics),
          ),
          _buildMenuDivider(context),
          _buildMenuItem(
            context: context,
            icon: Icons.monitor_weight,
            label: 'Body Metrics',
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BodyMetricsScreen()),
                ),
          ),
          _buildMenuDivider(context),
          _buildMenuItem(
            context: context,
            icon: Icons.bookmark,
            label: 'Templates',
            onTap: () => Navigator.pushNamed(context, RouteNames.templates),
          ),
          _buildMenuDivider(context),
          _buildMenuItem(
            context: context,
            icon: Icons.people,
            label: 'Community',
            onTap: () => Navigator.pushNamed(context, RouteNames.community),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
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
                color: context.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: context.textPrimary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: context.textTertiary, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuDivider(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 66),
      height: 0.5,
      color: context.border,
    );
  }

  Widget _buildAppSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            context: context,
            icon: Icons.settings,
            label: 'Settings',
            onTap: () => Navigator.pushNamed(context, RouteNames.settings),
          ),
          _buildMenuDivider(context),
          _buildMenuItem(
            context: context,
            icon: Icons.logout,
            label: 'Logout',
            onTap: _handleLogout,
          ),
        ],
      ),
    );
  }
}
