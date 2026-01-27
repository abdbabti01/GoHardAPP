import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/services/haptic_service.dart';
import '../../../providers/exercises_provider.dart';
import '../../../providers/active_workout_provider.dart';
import '../../widgets/exercises/exercise_card.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/animations.dart';

/// Add exercise screen for selecting exercises to add to active workout
/// Updated to match ExercisesScreen with search and comprehensive filters
class AddExerciseScreen extends StatefulWidget {
  final int sessionId;

  const AddExerciseScreen({super.key, required this.sessionId});

  @override
  State<AddExerciseScreen> createState() => _AddExerciseScreenState();
}

class _AddExerciseScreenState extends State<AddExerciseScreen> {
  final Set<int> _selectedExerciseIds = {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
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

  void _toggleExerciseSelection(int exerciseId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedExerciseIds.contains(exerciseId)) {
        _selectedExerciseIds.remove(exerciseId);
      } else {
        _selectedExerciseIds.add(exerciseId);
      }
    });
  }

  Future<void> _handleAddExercises() async {
    if (_selectedExerciseIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one exercise')),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isAdding = true);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final provider = context.read<ActiveWorkoutProvider>();

      for (final exerciseId in _selectedExerciseIds) {
        await provider.addExercise(exerciseId);
      }

      if (mounted) {
        HapticFeedback.heavyImpact();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  '${_selectedExerciseIds.length} exercise${_selectedExerciseIds.length == 1 ? '' : 's'} added!',
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) navigator.pop(true);
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Error adding exercises: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
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
                          // Header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Filter Exercises',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              TextButton(
                                onPressed: () => provider.clearFilters(),
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

  Widget _buildExerciseList(ExercisesProvider provider) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: provider.filteredExercises.length,
      itemBuilder: (context, index) {
        final exercise = provider.filteredExercises[index];
        final isSelected = _selectedExerciseIds.contains(exercise.id);

        return ExerciseCard(
          exercise: exercise,
          onTap: () => _toggleExerciseSelection(exercise.id),
          trailing: Checkbox(
            value: isSelected,
            onChanged: (_) => _toggleExerciseSelection(exercise.id),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Exercises'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilters,
            tooltip: 'Filter',
          ),
          if (_selectedExerciseIds.isNotEmpty)
            IconButton(
              icon:
                  _isAdding
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.check),
              onPressed: _isAdding ? null : _handleAddExercises,
              tooltip: 'Add Selected',
            ),
        ],
      ),
      body: Consumer<ExercisesProvider>(
        builder: (context, provider, child) {
          // Loading state
          if (provider.isLoading && provider.exercises.isEmpty) {
            return ListView(
              padding: const EdgeInsets.only(top: 16),
              children: [for (int i = 0; i < 6; i++) const SkeletonCard()],
            );
          }

          // Error state
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
                    ElevatedButton.icon(
                      onPressed: _handleRefresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          // Empty state
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
                      TextButton.icon(
                        onPressed: () => provider.clearFilters(),
                        icon: const Icon(Icons.clear_all_rounded),
                        label: const Text('Clear All Filters'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          // Exercise list
          return Column(
            children: [
              // Selection counter
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child:
                    _selectedExerciseIds.isNotEmpty
                        ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1),
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${_selectedExerciseIds.length} exercise${_selectedExerciseIds.length == 1 ? '' : 's'} selected',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  setState(() => _selectedExerciseIds.clear());
                                },
                                icon: const Icon(Icons.clear, size: 18),
                                label: const Text('Clear'),
                              ),
                            ],
                          ),
                        )
                        : const SizedBox.shrink(),
              ),

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

              // Exercise list
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
      floatingActionButton: AnimatedScale(
        scale: _selectedExerciseIds.isNotEmpty ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.elasticOut,
        child:
            _selectedExerciseIds.isNotEmpty
                ? FloatingActionButton.extended(
                  onPressed: _isAdding ? null : _handleAddExercises,
                  backgroundColor: _isAdding ? Colors.grey : null,
                  icon:
                      _isAdding
                          ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.add_rounded),
                  label: Text(
                    _isAdding
                        ? 'Adding...'
                        : 'Add ${_selectedExerciseIds.length} Exercise${_selectedExerciseIds.length == 1 ? '' : 's'}',
                  ),
                )
                : const SizedBox.shrink(),
      ),
    );
  }
}
