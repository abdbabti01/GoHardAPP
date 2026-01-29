import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_config.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/dm_conversation.dart';
import '../../../providers/messages_provider.dart';
import '../../widgets/common/loading_indicator.dart';

/// Screen showing list of message conversations
class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessagesProvider>().loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessagesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.loadConversations(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body:
          provider.isLoading
              ? const Center(child: PremiumLoader())
              : provider.conversations.isEmpty
              ? _buildEmptyState(context)
              : _buildConversationsList(context, provider),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.message_outlined, size: 64, color: context.textTertiary),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(fontSize: 16, color: context.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation with a friend',
            style: TextStyle(fontSize: 14, color: context.textTertiary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/friends'),
            icon: const Icon(Icons.people),
            label: const Text('View Friends'),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationsList(
    BuildContext context,
    MessagesProvider provider,
  ) {
    return RefreshIndicator(
      onRefresh: () => provider.loadConversations(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: provider.conversations.length,
        itemBuilder: (context, index) {
          return _buildConversationTile(context, provider.conversations[index]);
        },
      ),
    );
  }

  Widget _buildConversationTile(BuildContext context, DMConversation conv) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.primary,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Text(
                  conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
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
                  fontWeight:
                      conv.unreadCount > 0
                          ? FontWeight.w500
                          : FontWeight.normal,
                ),
              )
              : Text(
                'No messages yet',
                style: TextStyle(
                  color: context.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
      trailing:
          conv.lastMessageAt != null
              ? Text(
                _formatTime(conv.lastMessageAt!),
                style: TextStyle(
                  fontSize: 12,
                  color:
                      conv.unreadCount > 0
                          ? context.primary
                          : context.textSecondary,
                ),
              )
              : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'Now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }
}
