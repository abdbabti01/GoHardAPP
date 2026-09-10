import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/friends_provider.dart';
import '../../../providers/messages_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/common/user_avatar.dart';

/// Me screen - Profile hub with goals, analytics, settings
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FriendsProvider>().loadIncomingRequests();
      context.read<MessagesProvider>().loadUnreadCount();

      // The profile hub is the first authenticated screen that shows the
      // user's photo/name, but nothing else loads the profile on login
      // (ProfileProvider is cleared on logout and only Settings triggers a
      // fetch). Pull it once here so the avatar and identity render, and so
      // it is fresh again after a logout/login on the same device.
      final profile = context.read<ProfileProvider>();
      if (profile.currentUser == null && !profile.isLoading) {
        profile.loadUserProfile();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final friendsProvider = context.watch<FriendsProvider>();
    final messagesProvider = context.watch<MessagesProvider>();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile header
          _buildProfileHeader(context),
          const SizedBox(height: 24),

          // Menu sections
          _buildMenuSection(context, 'Progress', [
            _MenuItem(
              icon: Icons.flag_outlined,
              iconColor: Colors.blue,
              title: 'Goals',
              subtitle: 'Set and track your goals',
              onTap: () => Navigator.pushNamed(context, RouteNames.goals),
            ),
            _MenuItem(
              icon: Icons.monitor_weight_outlined,
              iconColor: Colors.teal,
              title: 'Body Metrics',
              subtitle: 'Track weight & measurements',
              onTap: () => Navigator.pushNamed(context, RouteNames.bodyMetrics),
            ),
            _MenuItem(
              icon: Icons.emoji_events_outlined,
              iconColor: Colors.amber,
              title: 'Achievements',
              subtitle: 'View your badges',
              onTap:
                  () => Navigator.pushNamed(context, RouteNames.achievements),
            ),
          ]),
          const SizedBox(height: 16),

          // Social section
          _buildMenuSection(context, 'Social', [
            _MenuItem(
              icon: Icons.people_outlined,
              iconColor: Colors.indigo,
              title: 'Friends',
              subtitle: 'Manage friends & requests',
              badge: friendsProvider.pendingRequestCount,
              onTap: () => Navigator.pushNamed(context, RouteNames.friends),
            ),
            _MenuItem(
              icon: Icons.message_outlined,
              iconColor: Colors.green,
              title: 'Messages',
              subtitle: 'Direct messages',
              badge: messagesProvider.totalUnreadCount,
              onTap: () => Navigator.pushNamed(context, RouteNames.messages),
            ),
          ]),
          const SizedBox(height: 16),

          _buildMenuSection(context, 'Account', [
            _MenuItem(
              icon: Icons.person_outline,
              iconColor: Colors.blue,
              title: 'Edit Profile',
              onTap: () => Navigator.pushNamed(context, RouteNames.editProfile),
            ),
            _MenuItem(
              icon: Icons.settings_outlined,
              iconColor: Colors.grey,
              title: 'Settings',
              onTap: () => Navigator.pushNamed(context, RouteNames.settings),
            ),
          ]),
          const SizedBox(height: 16),

          _buildMenuSection(context, 'Support', [
            _MenuItem(
              icon: Icons.help_outline,
              iconColor: Colors.orange,
              title: 'Help & FAQ',
              onTap: () {
                // TODO: Help screen
              },
            ),
            _MenuItem(
              icon: Icons.feedback_outlined,
              iconColor: Colors.green,
              title: 'Send Feedback',
              onTap: () {
                // TODO: Feedback
              },
            ),
          ]),
          const SizedBox(height: 24),

          // Logout button
          _buildLogoutButton(context),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    return Consumer2<AuthProvider, ProfileProvider>(
      builder: (context, authProvider, profileProvider, child) {
        final userName = authProvider.currentUserName;
        final userEmail = authProvider.currentUserEmail;
        final username = authProvider.currentUsername;
        // Prefer the freshly loaded profile photo; fall back to nothing (the
        // avatar shows an initial/icon). Never a device file path.
        final photoUrl = profileProvider.currentUser?.profilePhotoUrl;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.border),
          ),
          child: Row(
            children: [
              UserAvatar(
                photoUrl: photoUrl,
                fallbackText: userName ?? username,
                radius: 35,
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName ?? 'User',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (username != null && username.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      userEmail ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Edit button
              IconButton(
                onPressed:
                    () => Navigator.pushNamed(context, RouteNames.editProfile),
                icon: Icon(Icons.edit_outlined, color: context.accent),
                tooltip: 'Edit profile',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuSection(
    BuildContext context,
    String title,
    List<_MenuItem> items,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...items.map((item) => _buildMenuItem(context, item)),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, _MenuItem item) {
    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: item.iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (item.badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.badge > 99 ? '99+' : item.badge.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (item.badge > 0) const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: context.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
          );

          if (confirmed == true && context.mounted) {
            // Navigation to the login screen is handled centrally by
            // AuthProvider.onLoggedOut (wired in SessionCleanupInitializer)
            // once cleanup and credential/Isar clearing complete - this is
            // also what the silent 401/session-expiry logout path relies
            // on, since it has no BuildContext of its own to navigate with.
            // A second manual navigation call here would violate "logout
            // navigates exactly once".
            await context.read<AuthProvider>().logout();
          }
        },
        icon: const Icon(Icons.logout, color: Colors.red),
        label: const Text('Logout', style: TextStyle(color: Colors.red)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final int badge;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.badge = 0,
    required this.onTap,
  });
}
