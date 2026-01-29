import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/shared_workout_provider.dart';
import '../../../data/models/shared_workout.dart';
import '../../widgets/common/offline_banner.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/community/social_tab.dart';

/// Community screen for browsing and sharing workouts
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Load data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SharedWorkoutProvider>();
      provider.loadSharedWorkouts();
      provider.loadSavedWorkouts();
      provider.loadMySharedWorkouts();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SharedWorkoutProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.refresh(),
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Social', icon: Icon(Icons.people)),
            Tab(text: 'Discover', icon: Icon(Icons.explore)),
            Tab(text: 'My Content', icon: Icon(Icons.folder)),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!provider.isOnline) const OfflineBanner(),
          Expanded(
            child:
                provider.isLoading
                    ? const Center(child: PremiumLoader())
                    : provider.errorMessage != null
                    ? _buildErrorView(context, provider)
                    : TabBarView(
                      controller: _tabController,
                      children: [
                        const SocialTab(),
                        _buildDiscoverTab(context, provider),
                        _buildMyContentTab(context, provider),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, SharedWorkoutProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: context.error),
          const SizedBox(height: 16),
          Text(
            provider.errorMessage!,
            style: TextStyle(color: context.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => provider.refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverTab(
    BuildContext context,
    SharedWorkoutProvider provider,
  ) {
    final workouts = provider.sharedWorkouts;

    if (workouts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No shared content yet',
              style: TextStyle(fontSize: 16, color: context.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'When friends share workouts or runs,\nthey\'ll appear here',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.textTertiary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadSharedWorkouts(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: workouts.length,
        itemBuilder: (context, index) {
          return _buildWorkoutCard(context, workouts[index], provider);
        },
      ),
    );
  }

  Widget _buildMyContentTab(
    BuildContext context,
    SharedWorkoutProvider provider,
  ) {
    final savedWorkouts = provider.savedWorkouts;
    final myShares = provider.mySharedWorkouts;

    if (savedWorkouts.isEmpty && myShares.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_outlined, size: 64, color: context.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No content yet',
              style: TextStyle(fontSize: 16, color: context.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Save or share workouts to see them here',
              style: TextStyle(fontSize: 14, color: context.textTertiary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.loadSavedWorkouts();
        await provider.refresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Saved Workouts Section
          if (savedWorkouts.isNotEmpty) ...[
            _buildSectionHeader(context, 'Saved Workouts', Icons.bookmark),
            const SizedBox(height: 12),
            ...savedWorkouts.map(
              (workout) => _buildWorkoutCard(context, workout, provider),
            ),
            const SizedBox(height: 24),
          ],
          // My Shares Section
          if (myShares.isNotEmpty) ...[
            _buildSectionHeader(context, 'My Shares', Icons.share),
            const SizedBox(height: 12),
            ...myShares.map(
              (workout) => _buildWorkoutCard(
                context,
                workout,
                provider,
                isMyShare: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: context.textSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutCard(
    BuildContext context,
    SharedWorkout workout,
    SharedWorkoutProvider provider, {
    bool isMyShare = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showWorkoutDetails(workout),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    child: Text(workout.sharedByUserName[0].toUpperCase()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workout.sharedByUserName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          workout.timeSinceShared,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isMyShare)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(workout, provider),
                      color: context.error,
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Workout info
              Text(
                workout.workoutName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (workout.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  workout.description!,
                  style: TextStyle(color: context.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),

              // Tags or Run Stats
              if (workout.type == 'run')
                _buildRunStats(context, workout)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(
                      label: Text(workout.category),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (workout.difficulty != null)
                      Chip(
                        label: Text(workout.difficulty!),
                        visualDensity: VisualDensity.compact,
                      ),
                    Chip(
                      label: Text(workout.formattedDuration),
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.timer, size: 16),
                    ),
                  ],
                ),
              const SizedBox(height: 12),

              // Actions
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      workout.isLikedByCurrentUser
                          ? Icons.favorite
                          : Icons.favorite_border,
                    ),
                    color: workout.isLikedByCurrentUser ? Colors.red : null,
                    onPressed: () => provider.toggleLike(workout.id),
                  ),
                  Text('${workout.likeCount}'),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: Icon(
                      workout.isSavedByCurrentUser
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                    color: workout.isSavedByCurrentUser ? Colors.blue : null,
                    onPressed: () => provider.toggleSave(workout.id),
                  ),
                  Text('${workout.saveCount}'),
                  const Spacer(),
                  if (workout.type != 'run')
                    ElevatedButton.icon(
                      onPressed: () => _useWorkout(workout),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Use'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRunStats(BuildContext context, SharedWorkout workout) {
    // Parse run data from exercisesJson
    Map<String, dynamic> runData = {};
    try {
      runData = jsonDecode(workout.exercisesJson) as Map<String, dynamic>;
    } catch (_) {
      // Fallback if parsing fails
    }

    final distance = runData['distance'] as num? ?? 0;
    final duration = runData['duration'] as num? ?? 0;
    final pace = runData['pace'] as num? ?? 0;

    String formatDistance(num d) {
      return '${d.toStringAsFixed(2)} km';
    }

    String formatDuration(num seconds) {
      final mins = (seconds / 60).floor();
      final secs = (seconds % 60).floor();
      if (mins >= 60) {
        final hours = (mins / 60).floor();
        final remainingMins = mins % 60;
        return '$hours:${remainingMins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      }
      return '$mins:${secs.toString().padLeft(2, '0')}';
    }

    String formatPace(num p) {
      if (p <= 0) return '--';
      final mins = p.floor();
      final secs = ((p - mins) * 60).round();
      return "$mins'${secs.toString().padLeft(2, '0')}\"";
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildRunStatItem(
            context,
            Icons.straighten,
            formatDistance(distance),
            'Distance',
          ),
          _buildRunStatItem(
            context,
            Icons.timer_outlined,
            formatDuration(duration),
            'Time',
          ),
          _buildRunStatItem(context, Icons.speed, formatPace(pace), 'Pace'),
        ],
      ),
    );
  }

  Widget _buildRunStatItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: context.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.textSecondary),
        ),
      ],
    );
  }

  void _showWorkoutDetails(SharedWorkout workout) {
    final isRun = workout.type == 'run';

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  isRun ? Icons.directions_run : Icons.fitness_center,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(workout.workoutName)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Shared by: ${workout.sharedByUserName}'),
                  const SizedBox(height: 8),
                  Text('Category: ${workout.category}'),
                  if (workout.difficulty != null)
                    Text('Difficulty: ${workout.difficulty}'),
                  Text('Duration: ${workout.formattedDuration}'),
                  const SizedBox(height: 16),
                  if (workout.description != null) ...[
                    const Text(
                      'Description:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(workout.description!),
                    const SizedBox(height: 16),
                  ],
                  if (isRun) ...[
                    const Text(
                      'Run Stats:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildRunStats(context, workout),
                  ] else ...[
                    const Text(
                      'Exercises:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(workout.exercisesJson),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              if (!isRun)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _useWorkout(workout);
                  },
                  child: const Text('Use Workout'),
                ),
            ],
          ),
    );
  }

  void _useWorkout(SharedWorkout workout) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Use Workout'),
            content: Text(
              'Create a new workout session from "${workout.workoutName}"?\n\n'
              'This will start a new workout with the exercises from this shared workout.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _createSessionFromSharedWorkout(workout);
                },
                child: const Text('Start Workout'),
              ),
            ],
          ),
    );
  }

  Future<void> _createSessionFromSharedWorkout(SharedWorkout workout) async {
    final messenger = ScaffoldMessenger.of(context);

    // TODO: Integrate with SessionsProvider to create actual session
    // For now, show success message
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Workout session created from "${workout.workoutName}"!\n'
          'Navigate to Active Workout to start.',
        ),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'GO',
          onPressed: () {
            // Navigate to active workout screen
            Navigator.pushNamed(context, '/active-workout');
          },
        ),
      ),
    );
  }

  void _confirmDelete(SharedWorkout workout, SharedWorkoutProvider provider) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Shared Workout'),
            content: Text(
              'Are you sure you want to delete "${workout.workoutName}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final success = await provider.deleteSharedWorkout(
                    workout.id,
                  );
                  if (success && mounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Workout deleted')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  void _showFilterDialog() {
    final provider = context.read<SharedWorkoutProvider>();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Filter Workouts'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Category:'),
                DropdownButton<String?>(
                  value: provider.selectedCategory,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...[
                      'Strength',
                      'Cardio',
                      'Flexibility',
                      'HIIT',
                      'CrossFit',
                    ].map(
                      (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                    ),
                  ],
                  onChanged: (value) {
                    provider.setCategory(value);
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 16),
                const Text('Difficulty:'),
                DropdownButton<String?>(
                  value: provider.selectedDifficulty,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...['Beginner', 'Intermediate', 'Advanced'].map(
                      (diff) =>
                          DropdownMenuItem(value: diff, child: Text(diff)),
                    ),
                  ],
                  onChanged: (value) {
                    provider.setDifficulty(value);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  provider.clearFilters();
                  Navigator.pop(context);
                },
                child: const Text('Clear Filters'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}
