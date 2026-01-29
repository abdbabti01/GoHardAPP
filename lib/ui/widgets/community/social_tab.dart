import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_config.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/friend.dart';
import '../../../data/models/dm_conversation.dart';
import '../../../providers/friends_provider.dart';
import '../../../providers/messages_provider.dart';
import '../common/loading_indicator.dart';

/// Social tab combining Friends and Messages sections
class SocialTab extends StatefulWidget {
  const SocialTab({super.key});

  @override
  State<SocialTab> createState() => _SocialTabState();
}

class _SocialTabState extends State<SocialTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsProvider>().loadAll();
      context.read<MessagesProvider>().loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final friendsProvider = context.watch<FriendsProvider>();
    final messagesProvider = context.watch<MessagesProvider>();

    if (friendsProvider.isLoading && messagesProvider.isLoading) {
      return const Center(child: PremiumLoader());
    }

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          friendsProvider.loadAll(),
          messagesProvider.loadConversations(),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // Friend Requests Banner (if any)
          if (friendsProvider.incomingRequests.isNotEmpty)
            _buildFriendRequestsBanner(context, friendsProvider),

          // Friends Section
          _buildFriendsSection(context, friendsProvider),

          const SizedBox(height: 20),

          // Messages Section
          _buildMessagesSection(context, messagesProvider),
        ],
      ),
    );
  }

  Widget _buildFriendRequestsBanner(
    BuildContext context,
    FriendsProvider provider,
  ) {
    final requests = provider.incomingRequests;
    final request = requests.first;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.primary.withOpacity(0.15),
            context.primary.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.primary.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, '/friends'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Stacked avatars
                SizedBox(
                  width: 52,
                  height: 40,
                  child: Stack(
                    children: [
                      _buildSmallAvatar(request.name, request.profilePhotoUrl),
                      if (requests.length > 1)
                        Positioned(
                          left: 20,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: context.surfaceElevated,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.surface,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '+${requests.length - 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: context.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requests.length == 1
                            ? '${request.name} wants to be friends'
                            : '${requests.length} friend requests',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Tap to view',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: context.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallAvatar(String name, String? photoUrl) {
    return CircleAvatar(
      radius: 16,
      backgroundImage:
          photoUrl != null
              ? NetworkImage(ApiConfig.getPhotoUrl(photoUrl))
              : null,
      child:
          photoUrl == null
              ? Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              )
              : null,
    );
  }

  Widget _buildFriendsSection(BuildContext context, FriendsProvider provider) {
    final friends = provider.friends;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.people, size: 20, color: context.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Friends',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  if (friends.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${friends.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/friends'),
                icon: Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: context.primary,
                ),
                label: Text(
                  'All',
                  style: TextStyle(
                    color: context.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Friends list or empty state
        if (friends.isEmpty)
          _buildEmptyFriendsState(context)
        else
          _buildFriendsGrid(context, friends.take(6).toList()),
      ],
    );
  }

  Widget _buildEmptyFriendsState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_add,
              size: 32,
              color: context.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Find your workout buddies',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Connect with friends to share progress',
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/friends'),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Find Friends'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsGrid(BuildContext context, List<Friend> friends) {
    return SizedBox(
      height: 88,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: friends.length + 1,
        itemBuilder: (context, index) {
          if (index == friends.length) {
            return _buildAddFriendButton(context);
          }
          return _buildFriendItem(context, friends[index]);
        },
      ),
    );
  }

  Widget _buildFriendItem(BuildContext context, Friend friend) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/conversation',
          arguments: {
            'friendId': friend.userId,
            'friendName': friend.name,
            'friendUsername': friend.username,
            'friendPhotoUrl': friend.profilePhotoUrl,
          },
        );
      },
      child: Container(
        width: 68,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [context.primary, context.primary.withOpacity(0.5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.surface,
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: context.surfaceElevated,
                  backgroundImage:
                      friend.profilePhotoUrl != null
                          ? NetworkImage(
                            ApiConfig.getPhotoUrl(friend.profilePhotoUrl),
                          )
                          : null,
                  child:
                      friend.profilePhotoUrl == null
                          ? Text(
                            friend.name[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          )
                          : null,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              friend.name.split(' ').first,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddFriendButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/friends'),
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.surfaceElevated,
                border: Border.all(
                  color: context.borderSubtle,
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: Icon(
                Icons.person_add,
                size: 22,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesSection(
    BuildContext context,
    MessagesProvider provider,
  ) {
    final conversations = provider.conversations;
    final totalUnread = provider.totalUnreadCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 20,
                    color: context.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Messages',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  if (totalUnread > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        totalUnread > 99 ? '99+' : '$totalUnread',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/messages'),
                icon: Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: context.primary,
                ),
                label: Text(
                  'All',
                  style: TextStyle(
                    color: context.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Messages list or empty state
        if (conversations.isEmpty)
          _buildEmptyMessagesState(context)
        else
          _buildMessagesList(context, conversations.take(4).toList()),
      ],
    );
  }

  Widget _buildEmptyMessagesState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 32,
              color: context.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Start a conversation with a friend',
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(
    BuildContext context,
    List<DMConversation> conversations,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children:
            conversations.asMap().entries.map((entry) {
              final index = entry.key;
              final conv = entry.value;
              final isLast = index == conversations.length - 1;
              return _buildMessageItem(context, conv, isLast);
            }).toList(),
      ),
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    DMConversation conv,
    bool isLast,
  ) {
    final hasUnread = conv.unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/conversation',
            arguments: {
              'friendId': conv.friendId,
              'friendName': conv.friendName,
              'friendUsername': conv.friendUsername,
              'friendPhotoUrl': conv.friendPhotoUrl,
            },
          );
        },
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isLast ? 0 : 0),
          bottom: Radius.circular(isLast ? 16 : 0),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border:
                isLast
                    ? null
                    : Border(
                      bottom: BorderSide(
                        color: context.borderSubtle,
                        width: 0.5,
                      ),
                    ),
          ),
          child: Row(
            children: [
              // Avatar with unread indicator
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: context.surface,
                    backgroundImage:
                        conv.friendPhotoUrl != null
                            ? NetworkImage(
                              ApiConfig.getPhotoUrl(conv.friendPhotoUrl),
                            )
                            : null,
                    child:
                        conv.friendPhotoUrl == null
                            ? Text(
                              conv.friendName[0].toUpperCase(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                              ),
                            )
                            : null,
                  ),
                  if (hasUnread)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: context.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.surfaceElevated,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Name and message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conv.friendName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            hasUnread ? FontWeight.w600 : FontWeight.w500,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      conv.lastMessage ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            hasUnread
                                ? context.textPrimary
                                : context.textSecondary,
                        fontWeight:
                            hasUnread ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Time
              if (conv.lastMessageAt != null)
                Text(
                  _formatTime(conv.lastMessageAt!),
                  style: TextStyle(
                    fontSize: 12,
                    color: hasUnread ? context.primary : context.textTertiary,
                    fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dateTime.day}/${dateTime.month}';
  }
}
