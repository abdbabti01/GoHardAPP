import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/exercise_detail_provider.dart';
import '../../../data/models/exercise_template.dart';
import '../../widgets/exercises/category_badge.dart';

/// Exercise detail screen for viewing exercise template information
/// Matches ExerciseDetailPage.xaml from MAUI app
class ExerciseDetailScreen extends StatefulWidget {
  final int exerciseId;

  const ExerciseDetailScreen({super.key, required this.exerciseId});

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  YoutubePlayerController? _youtubeController;
  String? _currentVideoId;
  bool _hasPlaybackError = false;

  @override
  void initState() {
    super.initState();
    _loadExercise();
  }

  Future<void> _loadExercise() async {
    await context.read<ExerciseDetailProvider>().loadExercise(
      widget.exerciseId,
    );
  }

  void _initializeVideoController(String videoUrl) {
    final videoId = YoutubePlayer.convertUrlToId(videoUrl);

    // Only create a new controller if the video ID changed
    if (videoId != null && videoId != _currentVideoId) {
      // Dispose of the old controller first
      _youtubeController?.dispose();

      _currentVideoId = videoId;
      _hasPlaybackError = false;

      _youtubeController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          enableCaption: true,
          showLiveFullscreenButton: false,
        ),
      );

      // Listen for errors (playback restrictions, etc.)
      _youtubeController!.addListener(() {
        if (_youtubeController!.value.hasError && mounted) {
          setState(() => _hasPlaybackError = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _youtubeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise Details'), elevation: 0),
      body: Consumer<ExerciseDetailProvider>(
        builder: (context, provider, child) {
          // Loading state
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Error state
          if (provider.errorMessage != null &&
              provider.errorMessage!.isNotEmpty) {
            return _buildErrorState(provider.errorMessage!);
          }

          // Content
          if (provider.exercise != null) {
            return _buildExerciseContent(provider.exercise!);
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildYouTubePlayer(String videoUrl) {
    // Initialize controller if needed
    _initializeVideoController(videoUrl);

    if (_youtubeController == null) {
      return const SizedBox.shrink();
    }

    // Show fallback UI if there's a playback error
    if (_hasPlaybackError) {
      return _buildVideoFallback(videoUrl);
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: YoutubePlayer(
        controller: _youtubeController!,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Theme.of(context).colorScheme.primary,
        onReady: () {
          setState(() => _hasPlaybackError = false);
        },
        onEnded: (_) {},
        bottomActions: [
          CurrentPosition(),
          ProgressBar(
            isExpanded: true,
            colors: ProgressBarColors(
              playedColor: Theme.of(context).colorScheme.primary,
              handleColor: Theme.of(context).colorScheme.primary,
            ),
          ),
          RemainingDuration(),
          FullScreenButton(),
        ],
      ),
    );
  }

  Widget _buildVideoFallback(String videoUrl) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Card(
        margin: EdgeInsets.zero,
        color: Colors.grey.shade100,
        child: InkWell(
          onTap: () => _openInYouTube(videoUrl),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_circle_outline,
                  size: 64,
                  color: Colors.red.shade700,
                ),
                const SizedBox(height: 16),
                Text(
                  'Video Playback Restricted',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'The video owner has disabled playback on external apps',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _openInYouTube(videoUrl),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open in YouTube'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openInYouTube(String videoUrl) async {
    final uri = Uri.parse(videoUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open YouTube')));
      }
    }
  }

  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            'Error Loading Exercise',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadExercise,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseContent(ExerciseTemplate exercise) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video player at the top (if available)
          if (exercise.videoUrl != null && exercise.videoUrl!.isNotEmpty)
            _buildYouTubePlayer(exercise.videoUrl!),

          // Content with padding
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Exercise Name
                Text(
                  exercise.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Badges
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (exercise.category != null)
                      CategoryBadge(category: exercise.category),
                    if (exercise.muscleGroup != null)
                      _buildInfoBadge(
                        exercise.muscleGroup!,
                        Colors.blue,
                        Icons.accessibility_new,
                      ),
                    if (exercise.equipment != null)
                      _buildInfoBadge(
                        exercise.equipment!,
                        Colors.purple,
                        Icons.fitness_center,
                      ),
                    if (exercise.difficulty != null)
                      _buildInfoBadge(
                        exercise.difficulty!,
                        _getDifficultyColor(exercise.difficulty!),
                        _getDifficultyIcon(exercise.difficulty!),
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // Description
                if (exercise.description != null &&
                    exercise.description!.isNotEmpty) ...[
                  Text(
                    'Description',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    exercise.description!,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                ],

                // Instructions
                if (exercise.instructions != null &&
                    exercise.instructions!.isNotEmpty) ...[
                  Text(
                    'Instructions',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._buildInstructionsList(exercise.instructions!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildInstructionsList(String instructions) {
    final steps =
        instructions.split('\n').where((s) => s.trim().isNotEmpty).toList();

    return List.generate(steps.length, (index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  steps[index].trim(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  IconData _getDifficultyIcon(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'beginner':
        return Icons.signal_cellular_alt_1_bar;
      case 'intermediate':
        return Icons.signal_cellular_alt_2_bar;
      case 'advanced':
        return Icons.signal_cellular_alt;
      default:
        return Icons.signal_cellular_alt_2_bar;
    }
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'beginner':
        return Colors.green;
      case 'intermediate':
        return Colors.orange;
      case 'advanced':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
