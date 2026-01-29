import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/api_config.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/friend.dart';
import '../../../data/models/friend_request.dart';
import '../../../data/models/user_search_result.dart';
import '../../../providers/friends_provider.dart';
import '../../widgets/common/loading_indicator.dart';

/// Friends screen with 3 tabs: Friends, Requests, Search
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FriendsProvider>().loadAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FriendsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.loadAll(),
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Friends', icon: Icon(Icons.people)),
            Tab(
              icon: Badge(
                isLabelVisible: provider.pendingRequestCount > 0,
                label: Text('${provider.pendingRequestCount}'),
                child: const Icon(Icons.person_add),
              ),
              text: 'Requests',
            ),
            const Tab(text: 'Search', icon: Icon(Icons.search)),
          ],
        ),
      ),
      body:
          provider.isLoading
              ? const Center(child: PremiumLoader())
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildFriendsTab(context, provider),
                  _buildRequestsTab(context, provider),
                  _buildSearchTab(context, provider),
                ],
              ),
    );
  }

  Widget _buildFriendsTab(BuildContext context, FriendsProvider provider) {
    final friends = provider.friends;

    if (friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: TextStyle(fontSize: 16, color: context.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Search for users to add friends',
              style: TextStyle(fontSize: 14, color: context.textTertiary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(2),
              icon: const Icon(Icons.search),
              label: const Text('Find Friends'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadFriends(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: friends.length,
        itemBuilder:
            (context, index) =>
                _buildFriendTile(context, friends[index], provider),
      ),
    );
  }

  Widget _buildFriendTile(
    BuildContext context,
    Friend friend,
    FriendsProvider provider,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              friend.profilePhotoUrl != null
                  ? NetworkImage(ApiConfig.getPhotoUrl(friend.profilePhotoUrl))
                  : null,
          child:
              friend.profilePhotoUrl == null
                  ? Text(friend.name[0].toUpperCase())
                  : null,
        ),
        title: Text(friend.name),
        subtitle: Text('@${friend.username}'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'message') {
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
            } else if (value == 'profile') {
              Navigator.pushNamed(
                context,
                '/friend-profile',
                arguments: friend.userId,
              );
            } else if (value == 'remove') {
              final confirmed = await _showRemoveConfirmDialog(context, friend);
              if (confirmed == true) {
                provider.removeFriend(friend.userId);
              }
            }
          },
          itemBuilder:
              (context) => [
                const PopupMenuItem(
                  value: 'message',
                  child: ListTile(
                    leading: Icon(Icons.message),
                    title: Text('Message'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'profile',
                  child: ListTile(
                    leading: Icon(Icons.person),
                    title: Text('View Profile'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'remove',
                  child: ListTile(
                    leading: Icon(Icons.person_remove, color: Colors.red),
                    title: Text('Remove', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
        ),
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
      ),
    );
  }

  Future<bool?> _showRemoveConfirmDialog(BuildContext context, Friend friend) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Remove Friend'),
            content: Text('Are you sure you want to remove ${friend.name}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
  }

  Widget _buildRequestsTab(BuildContext context, FriendsProvider provider) {
    final incoming = provider.incomingRequests;
    final outgoing = provider.outgoingRequests;

    if (incoming.isEmpty && outgoing.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No pending requests',
              style: TextStyle(fontSize: 16, color: context.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.loadIncomingRequests();
        await provider.loadOutgoingRequests();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (incoming.isNotEmpty) ...[
            Text(
              'Incoming Requests',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...incoming.map(
              (r) => _buildIncomingRequestTile(context, r, provider),
            ),
            const SizedBox(height: 24),
          ],
          if (outgoing.isNotEmpty) ...[
            Text(
              'Sent Requests',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...outgoing.map(
              (r) => _buildOutgoingRequestTile(context, r, provider),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIncomingRequestTile(
    BuildContext context,
    FriendRequest request,
    FriendsProvider provider,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              request.profilePhotoUrl != null
                  ? NetworkImage(ApiConfig.getPhotoUrl(request.profilePhotoUrl))
                  : null,
          child:
              request.profilePhotoUrl == null
                  ? Text(request.name[0].toUpperCase())
                  : null,
        ),
        title: Text(request.name),
        subtitle: Text('@${request.username}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: () => provider.acceptRequest(request.friendshipId),
              tooltip: 'Accept',
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => provider.declineRequest(request.friendshipId),
              tooltip: 'Decline',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutgoingRequestTile(
    BuildContext context,
    FriendRequest request,
    FriendsProvider provider,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              request.profilePhotoUrl != null
                  ? NetworkImage(ApiConfig.getPhotoUrl(request.profilePhotoUrl))
                  : null,
          child:
              request.profilePhotoUrl == null
                  ? Text(request.name[0].toUpperCase())
                  : null,
        ),
        title: Text(request.name),
        subtitle: Text('@${request.username} - Pending'),
        trailing: TextButton(
          onPressed: () => provider.cancelFriendRequest(request.friendshipId),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _buildSearchTab(BuildContext context, FriendsProvider provider) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by username',
              prefixIcon: const Icon(Icons.search),
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          provider.clearSearch();
                        },
                      )
                      : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) {
              provider.searchUsers(value);
            },
          ),
        ),
        Expanded(child: _buildSearchResults(context, provider)),
      ],
    );
  }

  Widget _buildSearchResults(BuildContext context, FriendsProvider provider) {
    if (provider.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Enter at least 2 characters to search',
              style: TextStyle(fontSize: 14, color: context.textSecondary),
            ),
          ],
        ),
      );
    }

    final results = provider.searchResults;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(fontSize: 16, color: context.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length,
      itemBuilder:
          (context, index) =>
              _buildSearchResultTile(context, results[index], provider),
    );
  }

  Widget _buildSearchResultTile(
    BuildContext context,
    UserSearchResult user,
    FriendsProvider provider,
  ) {
    // Check if already a friend
    final isFriend = provider.friends.any((f) => f.userId == user.userId);
    // Check if request pending
    final hasPendingRequest = provider.outgoingRequests.any(
      (r) => r.userId == user.userId,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              user.profilePhotoUrl != null
                  ? NetworkImage(ApiConfig.getPhotoUrl(user.profilePhotoUrl))
                  : null,
          child:
              user.profilePhotoUrl == null
                  ? Text(user.name[0].toUpperCase())
                  : null,
        ),
        title: Text(user.name),
        subtitle: Text('@${user.username}'),
        trailing:
            isFriend
                ? const Chip(
                  label: Text('Friends'),
                  avatar: Icon(Icons.check, size: 16),
                )
                : hasPendingRequest
                ? const Chip(label: Text('Pending'))
                : ElevatedButton.icon(
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Add'),
                  onPressed: () => provider.sendFriendRequest(user.userId),
                ),
        onTap: () {
          Navigator.pushNamed(
            context,
            '/friend-profile',
            arguments: user.userId,
          );
        },
      ),
    );
  }
}
