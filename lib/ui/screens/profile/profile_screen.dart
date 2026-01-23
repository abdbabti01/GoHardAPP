import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/active_workout_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../routes/route_names.dart';
import '../../../core/constants/api_config.dart';
import '../../widgets/common/animations.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/premium_bottom_sheet.dart';
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
    final confirmed = await ConfirmationBottomSheet.show(
      context: context,
      title: 'Logout',
      message: 'Are you sure you want to logout? Your workout data is saved.',
      confirmLabel: 'Logout',
      cancelLabel: 'Stay',
      isDestructive: true,
      icon: Icons.logout_rounded,
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
            return const Center(child: PremiumLoader());
          }

          // Error state
          if (provider.errorMessage != null &&
              provider.errorMessage!.isNotEmpty) {
            return Center(
              child: FadeSlideAnimation(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.errorRed.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        size: 40,
                        color: AppColors.errorRed,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Error Loading Profile',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
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
                    ScaleTapAnimation(
                      onTap: _handleRefresh,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: context.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'Retry',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.goHardBlack,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                    FadeSlideAnimation(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Text(
                          'More',
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    ),

                    // Profile header card
                    FadeSlideAnimation(
                      delay: const Duration(milliseconds: 100),
                      child: _buildProfileHeader(context, provider),
                    ),
                    const SizedBox(height: 16),

                    // Quick Stats
                    FadeSlideAnimation(
                      delay: const Duration(milliseconds: 200),
                      child: _buildQuickStats(context, provider),
                    ),
                    const SizedBox(height: 16),

                    // Menu items
                    FadeSlideAnimation(
                      delay: const Duration(milliseconds: 300),
                      child: _buildMenuSection(context),
                    ),
                    const SizedBox(height: 16),

                    // App section
                    FadeSlideAnimation(
                      delay: const Duration(milliseconds: 400),
                      child: _buildAppSection(context),
                    ),
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

    return ScaleTapAnimation(
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              context.surface,
              context.surfaceElevated.withValues(alpha: 0.5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: context.accent.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: context.accent.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar with gradient border
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: context.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 32,
                backgroundColor: context.surface,
                backgroundImage:
                    user?.profilePhotoUrl != null
                        ? NetworkImage(
                          ApiConfig.getPhotoUrl(user!.profilePhotoUrl!),
                        )
                        : null,
                child:
                    user?.profilePhotoUrl == null
                        ? Icon(
                          Icons.person_rounded,
                          size: 32,
                          color: context.textTertiary,
                        )
                        : null,
              ),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
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
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: context.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          size: 12,
                          color: context.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Edit Profile',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.textTertiary,
              size: 24,
            ),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(
              context,
              Icons.fitness_center_rounded,
              stats?.totalWorkouts ?? 0,
              'Workouts',
              AppColors.goHardBlue,
            ),
          ),
          Container(width: 1, height: 70, color: context.border),
          Expanded(
            child: _buildStatItem(
              context,
              Icons.local_fire_department_rounded,
              stats?.currentStreak ?? 0,
              'Streak',
              AppColors.goHardOrange,
            ),
          ),
          Container(width: 1, height: 70, color: context.border),
          Expanded(
            child: _buildStatItem(
              context,
              Icons.emoji_events_rounded,
              stats?.personalRecords ?? 0,
              'PRs',
              AppColors.goHardAmber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    int value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 24, color: color),
        ),
        const SizedBox(height: 12),
        AnimatedCounter(
          value: value,
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: context.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    final menuItems = [
      _MenuItem(
        icon: Icons.monitor_weight_rounded,
        label: 'Body Metrics',
        subtitle: 'Log measurements',
        color: context.accent,
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BodyMetricsScreen()),
            ),
      ),
      _MenuItem(
        icon: Icons.bookmark_rounded,
        label: 'Templates',
        subtitle: 'Saved workout templates',
        color: AppColors.goHardAmber,
        onTap: () => Navigator.pushNamed(context, RouteNames.templates),
      ),
      _MenuItem(
        icon: Icons.people_rounded,
        label: 'Community',
        subtitle: 'Discover shared workouts',
        color: AppColors.goHardOrange,
        onTap: () => Navigator.pushNamed(context, RouteNames.community),
      ),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border, width: 0.5),
      ),
      child: Column(
        children: [
          for (int i = 0; i < menuItems.length; i++) ...[
            _buildMenuItem(context: context, item: menuItems[i]),
            if (i < menuItems.length - 1) _buildMenuDivider(context),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required _MenuItem item,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        color: context.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.textTertiary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuDivider(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 74),
      height: 0.5,
      color: context.border,
    );
  }

  Widget _buildAppSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border, width: 0.5),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            context: context,
            item: _MenuItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              subtitle: 'App preferences',
              color: context.textSecondary,
              onTap: () => Navigator.pushNamed(context, RouteNames.settings),
            ),
          ),
          _buildMenuDivider(context),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _handleLogout,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.errorRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: AppColors.errorRed,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Logout',
                            style: TextStyle(
                              color: AppColors.errorRed,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Sign out of your account',
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}
