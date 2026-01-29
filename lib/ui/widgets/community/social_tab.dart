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
        padding: const EdgeInsets.all(16),
        children: [
          _buildFriendsSection(context, friendsProvider),
          const SizedBox(height: 24),
          _buildMessagesSection(context, messagesProvider),
          const SizedBox(height: 24),
          _buildQuickActions(context),
        ],
      ),
    );
  }

  Widget _buildFriendsSection(BuildContext context, FriendsProvider provider) {
    final friends = provider.friends.take(5).toList();
    final pendingCount = provider.pendingRequestCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Friends',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$pendingCount pending',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/friends'),
              child: Text('See All', style: TextStyle(color: context.primary)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (friends.isEmpty)
          _buildEmptyFriendsCard(context)
        else
          _buildFriendsHorizontalList(context, friends, provider),
      ],
    );
  }

  Widget _buildEmptyFriendsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 48, color: context.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No friends yet',
              style: TextStyle(fontSize: 16, color: context.textSecondary),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/friends'),
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('Find Friends'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsHorizontalList(
    BuildContext context,
    List<Friend> friends,
    FriendsProvider provider,
  ) {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: friends.length + 1, // +1 for "Add" button
        itemBuilder: (context, index) {
          if (index == friends.length) {
            return _buildAddFriendButton(context);
          }
          return _buildFriendAvatar(context, friends[index]);
        },
      ),
    );
  }

  Widget _buildFriendAvatar(BuildContext context, Friend friend) {
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
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
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
                        style: const TextStyle(fontSize: 20),
                      )
                      : null,
            ),
            const SizedBox(height: 8),
            Text(
              friend.name.split(' ').first,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
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
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.borderSubtle,
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: Icon(Icons.add, color: context.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Add',
              style: TextStyle(fontSize: 12, color: context.textSecondary),
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
    final conversations = provider.conversations.take(3).toList();
    final totalUnread = provider.totalUnreadCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Messages',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      totalUnread > 99 ? '99+' : '$totalUnread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/messages'),
              child: Text('See All', style: TextStyle(color: context.primary)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (conversations.isEmpty)
          _buildEmptyMessagesCard(context)
        else
          _buildMessagesList(context, conversations),
      ],
    );
  }

  Widget _buildEmptyMessagesCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.message_outlined, size: 48, color: context.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No messages yet',
              style: TextStyle(fontSize: 16, color: context.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a conversation with a friend',
              style: TextStyle(fontSize: 14, color: context.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(
    BuildContext context,
    List<DMConversation> conversations,
  ) {
    return Card(
      child: Column(
        children:
            conversations.asMap().entries.map((entry) {
              final index = entry.key;
              final conv = entry.value;
              return Column(
                children: [
                  _buildMessageTile(context, conv),
                  if (index < conversations.length - 1)
                    Divider(height: 1, color: context.borderSubtle),
                ],
              );
            }).toList(),
      ),
    );
  }

  Widget _buildMessageTile(BuildContext context, DMConversation conv) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundImage:
                conv.friendPhotoUrl != null
                    ? NetworkImage(ApiConfig.getPhotoUrl(conv.friendPhotoUrl))
                    : null,
            child:
                conv.friendPhotoUrl == null
                    ? Text(conv.friendName[0].toUpperCase())
                    : null,
          ),
          if (conv.unreadCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: context.primary,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  conv.unreadCount > 9 ? '9+' : '${conv.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        conv.friendName,
        style: TextStyle(
          fontWeight:
              conv.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle:
          conv.lastMessage != null
              ? Text(
                conv.lastMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      conv.unreadCount > 0
                          ? context.textPrimary
                          : context.textSecondary,
                ),
              )
              : null,
      trailing: _buildTimeText(context, conv),
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
    );
  }

  Widget? _buildTimeText(BuildContext context, DMConversation conv) {
    if (conv.lastMessageAt == null) return null;

    final diff = DateTime.now().difference(conv.lastMessageAt!);
    String text;
    if (diff.inMinutes < 1) {
      text = 'Now';
    } else if (diff.inHours < 1) {
      text = '${diff.inMinutes}m';
    } else if (diff.inDays < 1) {
      text = '${diff.inHours}h';
    } else {
      text = '${diff.inDays}d';
    }

    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: conv.unreadCount > 0 ? context.primary : context.textTertiary,
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/friends'),
            icon: const Icon(Icons.person_add),
            label: const Text('Add Friend'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/messages'),
            icon: const Icon(Icons.message),
            label: const Text('Messages'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
