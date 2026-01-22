import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/services/haptic_service.dart';
import '../../../providers/exercises_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/exercises/exercise_card.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/animations.dart';

/// Exercises screen displaying exercise library
/// Matches ExercisesPage.xaml from MAUI app
class ExercisesScreen extends StatefulWidget {
  const ExercisesScreen({super.key});

  @override
  State<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends State<ExercisesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Load exercises on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExercisesProvider>().loadExercises();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    await context.read<ExercisesProvider>().loadExercises();
  }

  void _handleExerciseTap(int exerciseId) {
    Navigator.of(
      context,
    ).pushNamed(RouteNames.exerciseDetail, arguments: exerciseId);
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => Consumer<ExercisesProvider>(
            builder: (context, provider, child) {
              return DraggableScrollableSheet(
                initialChildSize: 0.7,
                minChildSize: 0.5,
                maxChildSize: 0.9,
                expand: false,
                builder: (context, scrollController) {
                  return SingleChildScrollView(
                    controller: scrollController,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with clear all button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Filter Exercises',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              TextButton(
                                onPressed: () {
                                  provider.clearFilters();
                                },
                                child: const Text('Clear All'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Category Filter
                          Text(
                            'Category',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildFilterChip(
                                context,
                                isSelected: provider.selectedCategory == null,
                                label: 'All',
                                onTap: () => provider.filterByCategory(null),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedCategory == 'Strength',
                                label: 'Strength',
                                onTap:
                                    () => provider.filterByCategory('Strength'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedCategory == 'Cardio',
                                label: 'Cardio',
                                onTap:
                                    () => provider.filterByCategory('Cardio'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedCategory == 'Flexibility',
                                label: 'Flexibility',
                                onTap:
                                    () => provider.filterByCategory(
                                      'Flexibility',
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Muscle Group Filter
                          Text(
                            'Muscle Group',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == null,
                                label: 'All',
                                onTap: () => provider.filterByMuscleGroup(null),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Chest',
                                label: 'Chest',
                                onTap:
                                    () => provider.filterByMuscleGroup('Chest'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Back',
                                label: 'Back',
                                onTap:
                                    () => provider.filterByMuscleGroup('Back'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Shoulders',
                                label: 'Shoulders',
                                onTap:
                                    () => provider.filterByMuscleGroup(
                                      'Shoulders',
                                    ),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Arms',
                                label: 'Arms',
                                onTap:
                                    () => provider.filterByMuscleGroup('Arms'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Legs',
                                label: 'Legs',
                                onTap:
                                    () => provider.filterByMuscleGroup('Legs'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Abs',
                                label: 'Abs',
                                onTap:
                                    () => provider.filterByMuscleGroup('Abs'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Glutes',
                                label: 'Glutes',
                                onTap:
                                    () =>
                                        provider.filterByMuscleGroup('Glutes'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Traps',
                                label: 'Traps',
                                onTap:
                                    () => provider.filterByMuscleGroup('Traps'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Forearms',
                                label: 'Forearms',
                                onTap:
                                    () => provider.filterByMuscleGroup(
                                      'Forearms',
                                    ),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup ==
                                    'Lower Back',
                                label: 'Lower Back',
                                onTap:
                                    () => provider.filterByMuscleGroup(
                                      'Lower Back',
                                    ),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedMuscleGroup == 'Full Body',
                                label: 'Full Body',
                                onTap:
                                    () => provider.filterByMuscleGroup(
                                      'Full Body',
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Difficulty Filter
                          Text(
                            'Difficulty Level',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildFilterChip(
                                context,
                                isSelected: provider.selectedDifficulty == null,
                                label: 'All',
                                onTap: () => provider.filterByDifficulty(null),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedDifficulty == 'Beginner',
                                label: 'Beginner',
                                color: context.accent,
                                onTap:
                                    () =>
                                        provider.filterByDifficulty('Beginner'),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedDifficulty ==
                                    'Intermediate',
                                label: 'Intermediate',
                                color: AppColors.goHardOrange,
                                onTap:
                                    () => provider.filterByDifficulty(
                                      'Intermediate',
                                    ),
                              ),
                              _buildFilterChip(
                                context,
                                isSelected:
                                    provider.selectedDifficulty == 'Advanced',
                                label: 'Advanced',
                                color: AppColors.errorRed,
                                onTap:
                                    () =>
                                        provider.filterByDifficulty('Advanced'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Apply button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Apply Filters'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required bool isSelected,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final chipColor = color ?? Theme.of(context).colorScheme.primary;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => onTap(),
      selectedColor: chipColor.withValues(alpha: 0.2),
      checkmarkColor: chipColor,
      labelStyle: TextStyle(
        color: isSelected ? chipColor : context.textSecondary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildActiveFilterChip(
    BuildContext context,
    String label,
    VoidCallback onRemove,
  ) {
    return Chip(
      label: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      deleteIcon: Icon(
        Icons.close,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
      onDeleted: onRemove,
      backgroundColor: context.surface,
      side: BorderSide(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }

  /// Build flat exercise list sorted alphabetically
  Widget _buildExerciseList(ExercisesProvider provider) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: provider.filteredExercises.length,
      itemBuilder: (context, index) {
        final exercise = provider.filteredExercises[index];
        return ExerciseCard(
          exercise: exercise,
          onTap: () => _handleExerciseTap(exercise.id),
        );
      },
    );
  }

  /// Build search bar widget
  Widget _buildSearchBar(ExercisesProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (value) => provider.searchExercises(value),
        decoration: InputDecoration(
          hintText: 'Search exercises...',
          prefixIcon: Icon(Icons.search, color: context.textSecondary),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? IconButton(
                    icon: Icon(Icons.clear, color: context.textSecondary),
                    onPressed: () {
                      _searchController.clear();
                      provider.searchExercises('');
                      _searchFocusNode.unfocus();
                    },
                  )
                  : null,
          filled: true,
          fillColor: context.surfaceHighlight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilters,
            tooltip: 'Filter',
          ),
        ],
      ),
      body: Consumer<ExercisesProvider>(
        builder: (context, provider, child) {
          // Loading state - Premium skeleton
          if (provider.isLoading && provider.exercises.isEmpty) {
            return ListView(
              padding: const EdgeInsets.only(top: 16),
              children: [
                // Skeleton difficulty section
                for (int section = 0; section < 3; section++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: SkeletonLoader(
                      width: 120,
                      height: 28,
                      borderRadius: 12,
                    ),
                  ),
                  for (int i = 0; i < 3; i++) const SkeletonCard(),
                ],
              ],
            );
          }

          // Error state - Premium styling
          if (provider.errorMessage != null &&
              provider.errorMessage!.isNotEmpty) {
            return Center(
              child: FadeSlideAnimation(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.errorRed.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        size: 40,
                        color: AppColors.errorRed,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Error Loading Exercises',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        provider.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ScaleTapAnimation(
                      onTap: _handleRefresh,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          gradient: context.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.refresh_rounded,
                              size: 18,
                              color: AppColors.goHardBlack,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.goHardBlack,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Empty state - Premium styling
          if (provider.filteredExercises.isEmpty) {
            final hasActiveFilters =
                provider.selectedCategory != null ||
                provider.selectedMuscleGroup != null ||
                provider.selectedDifficulty != null;

            return Center(
              child: FadeSlideAnimation(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.goHardBlue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasActiveFilters
                            ? Icons.filter_alt_off_rounded
                            : Icons.search_off_rounded,
                        size: 48,
                        color: AppColors.goHardBlue,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      hasActiveFilters
                          ? 'No Exercises Match Filters'
                          : 'No Exercises Found',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text(
                        hasActiveFilters
                            ? 'Try adjusting your filters'
                            : 'Pull down to refresh',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (hasActiveFilters) ...[
                      const SizedBox(height: 24),
                      ScaleTapAnimation(
                        onTap: () => provider.clearFilters(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.goHardBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.goHardBlue.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.clear_all_rounded,
                                size: 18,
                                color: AppColors.goHardBlue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Clear All Filters',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.goHardBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          // Exercises list with pull-to-refresh
          return Column(
            children: [
              // Search bar
              _buildSearchBar(provider),

              // Active filter indicator
              if (provider.selectedCategory != null ||
                  provider.selectedMuscleGroup != null ||
                  provider.selectedDifficulty != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.filter_list,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Active Filters',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () {
                              provider.clearFilters();
                              _searchController.clear();
                            },
                            child: Icon(
                              Icons.close,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (provider.selectedCategory != null)
                            _buildActiveFilterChip(
                              context,
                              provider.selectedCategory!,
                              () => provider.filterByCategory(null),
                            ),
                          if (provider.selectedMuscleGroup != null)
                            _buildActiveFilterChip(
                              context,
                              provider.selectedMuscleGroup!,
                              () => provider.filterByMuscleGroup(null),
                            ),
                          if (provider.selectedDifficulty != null)
                            _buildActiveFilterChip(
                              context,
                              provider.selectedDifficulty!,
                              () => provider.filterByDifficulty(null),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Results count
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      '${provider.filteredExercises.length} exercises',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Flat exercise list
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    HapticService.refresh();
                    await _handleRefresh();
                  },
                  color: context.accent,
                  backgroundColor: context.surface,
                  child: _buildExerciseList(provider),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
