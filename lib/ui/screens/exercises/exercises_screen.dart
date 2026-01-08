import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/exercises_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/exercises/exercise_card.dart';

/// Exercises screen displaying exercise library
/// Matches ExercisesPage.xaml from MAUI app
class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  // Track expanded state for difficulty sections
  final Map<String, bool> _expandedSections = {
    'Beginner': true,
    'Intermediate': true,
    'Advanced': true,
  };

  @override
  void initState() {
    super.initState();
    // Load exercises on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExercisesProvider>().loadExercises();
    });
  }

  Future<void> _handleRefresh() async {
    await context.read<ExercisesProvider>().loadExercises();
  }

  void _handleExerciseTap(int exerciseId) {
    Navigator.of(
      context,
    ).pushNamed(RouteNames.exerciseDetail, arguments: exerciseId);
  }

  void _showCategoryFilter() {
    final provider = context.read<ExercisesProvider>();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter by Category',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip(context, provider, null, 'All'),
                    _buildFilterChip(context, provider, 'Strength', 'Strength'),
                    _buildFilterChip(context, provider, 'Cardio', 'Cardio'),
                    _buildFilterChip(
                      context,
                      provider,
                      'Flexibility',
                      'Flexibility',
                    ),
                    _buildFilterChip(context, provider, 'Balance', 'Balance'),
                    _buildFilterChip(context, provider, 'Core', 'Core'),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    ExercisesProvider provider,
    String? category,
    String label,
  ) {
    final isSelected =
        provider.selectedCategory == category ||
        (category == null && provider.selectedCategory == null);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        provider.filterByCategory(category);
        Navigator.of(context).pop();
      },
      selectedColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.2),
      checkmarkColor: Theme.of(context).colorScheme.primary,
    );
  }

  /// Build exercise list organized by difficulty with collapsible sections
  Widget _buildDifficultyOrganizedList(ExercisesProvider provider) {
    final groupedExercises = provider.exercisesByDifficulty;
    final difficulties = ['Beginner', 'Intermediate', 'Advanced'];

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: difficulties.length,
      itemBuilder: (context, index) {
        final difficulty = difficulties[index];
        final exercises = groupedExercises[difficulty] ?? [];
        final isExpanded = _expandedSections[difficulty] ?? true;

        if (exercises.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Difficulty section header
            InkWell(
              onTap: () {
                setState(() {
                  _expandedSections[difficulty] = !isExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _getDifficultyColor(difficulty).withValues(alpha: 0.1),
                  border: Border(
                    bottom: BorderSide(
                      color: _getDifficultyColor(
                        difficulty,
                      ).withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getDifficultyColor(difficulty),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        difficulty.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${exercises.length} exercise${exercises.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: _getDifficultyColor(difficulty),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Collapsible exercise list
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child:
                  isExpanded
                      ? Column(
                        children:
                            exercises.map((exercise) {
                              return ExerciseCard(
                                exercise: exercise,
                                onTap: () => _handleExerciseTap(exercise.id),
                              );
                            }).toList(),
                      )
                      : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  /// Get color for difficulty level
  Color _getDifficultyColor(String difficulty) {
    switch (difficulty) {
      case 'Beginner':
        return Colors.green;
      case 'Intermediate':
        return Colors.orange;
      case 'Advanced':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showCategoryFilter,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _handleRefresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<ExercisesProvider>(
        builder: (context, provider, child) {
          // Loading state
          if (provider.isLoading && provider.exercises.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          // Error state
          if (provider.errorMessage != null &&
              provider.errorMessage!.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Exercises',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _handleRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          // Empty state
          if (provider.filteredExercises.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    provider.selectedCategory != null
                        ? 'No ${provider.selectedCategory} Exercises'
                        : 'No Exercises Found',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      provider.selectedCategory != null
                          ? 'Try selecting a different category'
                          : 'Pull down to refresh',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                  ),
                  if (provider.selectedCategory != null) ...[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.filterByCategory(null),
                      child: const Text('Clear Filter'),
                    ),
                  ],
                ],
              ),
            );
          }

          // Exercises list with pull-to-refresh
          return Column(
            children: [
              // Active filter indicator
              if (provider.selectedCategory != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      Icon(
                        Icons.filter_list,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Filtered by: ${provider.selectedCategory}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => provider.filterByCategory(null),
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),

              // Exercise list organized by difficulty
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _handleRefresh,
                  child: _buildDifficultyOrganizedList(provider),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
