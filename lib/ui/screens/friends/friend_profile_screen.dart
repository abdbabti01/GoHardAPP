import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_config.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/friends_provider.dart';
import '../../widgets/common/loading_indicator.dart';

/// Screen to view a user's public profile
class FriendProfileScreen extends StatefulWidget {
  final int userId;

  const FriendProfileScreen({super.key, required this.userId});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsProvider>().loadPublicProfile(widget.userId);
    });
  }

  @override
  void dispose() {
    // Don't clear profile here as it might be needed when navigating back
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FriendsProvider>();
    final profile = provider.selectedProfile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body:
          provider.isLoadingProfile
              ? const Center(child: PremiumLoader())
              : profile == null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: context.error),
                    const SizedBox(height: 16),
                    Text(
                      provider.errorMessage ?? 'Failed to load profile',
                      style: TextStyle(color: context.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed:
                          () => provider.loadPublicProfile(widget.userId),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Profile Header
                    _buildProfileHeader(context, provider),
                    const SizedBox(height: 24),

                    // Action Buttons
                    _buildActionButtons(context, provider),
                    const SizedBox(height: 24),

                    // Stats
                    _buildStats(context),
                    const SizedBox(height: 24),

                    // Bio
                    if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                      _buildBioSection(context, profile.bio!),
                      const SizedBox(height: 24),
                    ],

                    // Info
                    _buildInfoSection(context),
                  ],
                ),
              ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, FriendsProvider provider) {
    final profile = provider.selectedProfile!;

    return Column(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundImage:
              profile.profilePhotoUrl != null
                  ? NetworkImage(ApiConfig.getPhotoUrl(profile.profilePhotoUrl))
                  : null,
          child:
              profile.profilePhotoUrl == null
                  ? Text(
                    profile.name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 40),
                  )
                  : null,
        ),
        const SizedBox(height: 16),
        Text(
          profile.name,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '@${profile.username}',
          style: TextStyle(fontSize: 16, color: context.textSecondary),
        ),
        if (profile.isFriend) ...[
          const SizedBox(height: 8),
          Chip(
            avatar: const Icon(Icons.check, size: 16),
            label: const Text('Friends'),
            backgroundColor: context.primary.withValues(alpha: 0.1),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, FriendsProvider provider) {
    final status = provider.selectedProfileStatus;
    final profile = provider.selectedProfile!;

    if (status == null) return const SizedBox.shrink();

    if (status.isSelf) {
      return const SizedBox.shrink();
    }

    if (status.isFriend) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.message),
            label: const Text('Message'),
            onPressed: () {
              Navigator.pushNamed(
                context,
                '/conversation',
                arguments: {
                  'friendId': profile.userId,
                  'friendName': profile.name,
                  'friendUsername': profile.username,
                  'friendPhotoUrl': profile.profilePhotoUrl,
                },
              );
            },
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_remove),
            label: const Text('Remove'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: const Text('Remove Friend'),
                      content: Text('Remove ${profile.name} from friends?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
              );
              if (confirmed == true) {
                await provider.removeFriend(profile.userId);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
          ),
        ],
      );
    }

    if (status.isPendingOutgoing) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.cancel),
        label: const Text('Cancel Request'),
        onPressed: () {
          if (status.friendshipId != null) {
            provider.cancelFriendRequest(status.friendshipId!);
          }
        },
      );
    }

    if (status.isPendingIncoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Accept'),
            onPressed: () {
              if (status.friendshipId != null) {
                provider.acceptRequest(status.friendshipId!);
              }
            },
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.close),
            label: const Text('Decline'),
            onPressed: () {
              if (status.friendshipId != null) {
                provider.declineRequest(status.friendshipId!);
              }
            },
          ),
        ],
      );
    }

    // Not friends, no pending request
    return ElevatedButton.icon(
      icon: const Icon(Icons.person_add),
      label: const Text('Add Friend'),
      onPressed: () => provider.sendFriendRequest(profile.userId),
    );
  }

  Widget _buildStats(BuildContext context) {
    final profile = context.read<FriendsProvider>().selectedProfile!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatItem(
              context,
              'Shared Workouts',
              profile.sharedWorkoutsCount.toString(),
              Icons.share,
            ),
            if (profile.isFriend && profile.totalWorkoutsCount != null)
              _buildStatItem(
                context,
                'Total Workouts',
                profile.totalWorkoutsCount.toString(),
                Icons.fitness_center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, size: 32, color: context.primary),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
      ],
    );
  }

  Widget _buildBioSection(BuildContext context, String bio) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(bio),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    final profile = context.read<FriendsProvider>().selectedProfile!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Info',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (profile.experienceLevel != null)
              _buildInfoRow(
                context,
                'Experience',
                profile.experienceLevel!,
                Icons.trending_up,
              ),
            _buildInfoRow(
              context,
              'Member Since',
              _formatDate(profile.memberSince),
              Icons.calendar_today,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.textSecondary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: context.textSecondary),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}
