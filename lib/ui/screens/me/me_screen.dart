import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../routes/route_names.dart';

/// Me screen - Profile hub with goals, analytics, settings
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
              icon: Icons.analytics_outlined,
              iconColor: Colors.purple,
              title: 'Analytics',
              subtitle: 'View your workout stats',
              onTap: () => Navigator.pushNamed(context, RouteNames.analytics),
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
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final userName = authProvider.currentUserName;
        final userEmail = authProvider.currentUserEmail;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.border),
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  gradient: context.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person,
                  size: 36,
                  color: context.textOnPrimary,
                ),
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
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userEmail ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Edit button
              IconButton(
                onPressed:
                    () => Navigator.pushNamed(context, RouteNames.editProfile),
                icon: Icon(Icons.edit_outlined, color: context.accent),
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
            await context.read<AuthProvider>().logout();
            if (context.mounted) {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
            }
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
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
}
