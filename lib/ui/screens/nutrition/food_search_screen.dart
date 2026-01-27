import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../data/models/food_template.dart';
import '../../../data/models/meal_entry.dart';
import 'create_custom_food_screen.dart';
import 'barcode_scanner_screen.dart';

class FoodSearchScreen extends StatefulWidget {
  final String? preselectedMealType;

  const FoodSearchScreen({super.key, this.preselectedMealType});

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final _searchController = TextEditingController();
  String? _selectedMealType;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedMealType = widget.preselectedMealType;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NutritionProvider>().loadCategories();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Food'),
        actions: [
          IconButton(
            onPressed: () => _openBarcodeScanner(context),
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan Barcode',
          ),
          IconButton(
            onPressed: () => _navigateToCreateCustomFood(context),
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create Custom Food',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search foods...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            context.read<NutritionProvider>().clearSearch();
                          },
                        )
                        : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                context.read<NutritionProvider>().searchFoods(
                  value,
                  category: _selectedCategory,
                );
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Meal type selector
          if (_selectedMealType == null) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Meal',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children:
                        MealTypes.all.map((type) {
                          return ChoiceChip(
                            label: Text('${MealTypes.getIcon(type)} $type'),
                            selected: _selectedMealType == type,
                            onSelected: (selected) {
                              setState(() {
                                _selectedMealType = selected ? type : null;
                              });
                            },
                          );
                        }).toList(),
                  ),
                ],
              ),
            ),
            const Divider(),
          ],

          // Category filter
          Consumer<NutritionProvider>(
            builder: (context, provider, child) {
              if (provider.categories.isEmpty) {
                return const SizedBox.shrink();
              }

              return SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _selectedCategory == null,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = null;
                        });
                        if (_searchController.text.isNotEmpty) {
                          provider.searchFoods(_searchController.text);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ...provider.categories.map((category) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(category),
                          selected: _selectedCategory == category,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategory = selected ? category : null;
                            });
                            if (_searchController.text.isNotEmpty) {
                              provider.searchFoods(
                                _searchController.text,
                                category: _selectedCategory,
                              );
                            }
                          },
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 8),

          // Search results
          Expanded(
            child: Consumer<NutritionProvider>(
              builder: (context, provider, child) {
                if (provider.isSearching) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (_searchController.text.isEmpty) {
                  return _buildEmptyState(context);
                }

                if (provider.searchResults.isEmpty) {
                  return _buildNoResults(context);
                }

                return ListView.builder(
                  itemCount: provider.searchResults.length,
                  itemBuilder: (context, index) {
                    final food = provider.searchResults[index];
                    return _buildFoodItem(context, food, provider);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'Search for a food to add',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try "chicken", "rice", or "apple"',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _openBarcodeScanner(context),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Barcode'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No foods found',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _navigateToCreateCustomFood(context),
            icon: const Icon(Icons.add),
            label: const Text('Create Custom Food'),
          ),
        ],
      ),
    );
  }

  void _navigateToCreateCustomFood(BuildContext context) async {
    final navigator = Navigator.of(context);

    final result = await navigator.push<bool>(
      MaterialPageRoute(
        builder:
            (context) =>
                CreateCustomFoodScreen(preselectedMealType: _selectedMealType),
      ),
    );

    if (result == true && mounted) {
      navigator.pop(); // Go back to dashboard
    }
  }

  void _openBarcodeScanner(BuildContext context) async {
    final navigator = Navigator.of(context);

    final result = await navigator.push<bool>(
      MaterialPageRoute(
        builder:
            (context) =>
                BarcodeScannerScreen(preselectedMealType: _selectedMealType),
      ),
    );

    if (result == true && mounted) {
      navigator.pop(); // Go back to dashboard
    }
  }

  Widget _buildFoodItem(
    BuildContext context,
    FoodTemplate food,
    NutritionProvider provider,
  ) {
    return ListTile(
      title: Text(food.name),
      subtitle: Text(
        '${food.servingSize.toStringAsFixed(0)}${food.servingUnit} • ${food.calories.toStringAsFixed(0)} kcal',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'P: ${food.protein.toStringAsFixed(0)}g',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_circle),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => _addFood(context, food, provider),
          ),
        ],
      ),
      onTap: () => _showFoodDetails(context, food, provider),
    );
  }

  Future<void> _addFood(
    BuildContext context,
    FoodTemplate food,
    NutritionProvider provider,
  ) async {
    if (_selectedMealType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a meal first')),
      );
      return;
    }

    final mealEntry = provider.getMealEntryByType(_selectedMealType!);
    if (mealEntry == null || mealEntry.id == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find meal entry')),
      );
      return;
    }

    // Capture references before async gap
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final success = await provider.quickAddFood(
      mealEntryId: mealEntry.id,
      foodTemplateId: food.id,
      quantity: 1,
    );

    if (success && mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Added ${food.name} to $_selectedMealType')),
      );
      navigator.pop();
    }
  }

  void _showFoodDetails(
    BuildContext context,
    FoodTemplate food,
    NutritionProvider provider,
  ) {
    // Capture parent navigator reference
    final parentNavigator = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => _FoodDetailSheet(
            food: food,
            onAdd: (quantity) async {
              if (_selectedMealType == null) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text('Please select a meal first')),
                );
                return;
              }

              final mealEntry = provider.getMealEntryByType(_selectedMealType!);
              if (mealEntry == null || mealEntry.id == 0) return;

              // Capture references before async gap
              final sheetNavigator = Navigator.of(sheetContext);
              final messenger = ScaffoldMessenger.of(sheetContext);

              final success = await provider.quickAddFood(
                mealEntryId: mealEntry.id,
                foodTemplateId: food.id,
                quantity: quantity,
              );

              if (success && mounted) {
                sheetNavigator.pop(); // Close bottom sheet
                parentNavigator.pop(); // Go back to dashboard
                messenger.showSnackBar(
                  SnackBar(content: Text('Added ${food.name}')),
                );
              }
            },
          ),
    );
  }
}

class _FoodDetailSheet extends StatefulWidget {
  final FoodTemplate food;
  final Function(double quantity) onAdd;

  const _FoodDetailSheet({required this.food, required this.onAdd});

  @override
  State<_FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends State<_FoodDetailSheet> {
  late TextEditingController _gramsController;
  double _grams = 0;

  @override
  void initState() {
    super.initState();
    // Default to the serving size in grams
    _grams = widget.food.servingSize;
    _gramsController = TextEditingController(text: _grams.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _gramsController.dispose();
    super.dispose();
  }

  void _updateGrams(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed >= 0) {
      setState(() {
        _grams = parsed;
      });
    }
  }

  // Calculate nutrition based on grams entered
  // Formula: (nutrition_per_serving / serving_size) * grams
  double _calculateNutrition(double perServing) {
    if (widget.food.servingSize <= 0) return 0;
    return (perServing / widget.food.servingSize) * _grams;
  }

  // Calculate quantity (servings) for API
  double _getQuantityForApi() {
    if (widget.food.servingSize <= 0) return 1;
    return _grams / widget.food.servingSize;
  }

  @override
  Widget build(BuildContext context) {
    final food = widget.food;
    final totalCalories = _calculateNutrition(food.calories);
    final totalProtein = _calculateNutrition(food.protein);
    final totalCarbs = _calculateNutrition(food.carbohydrates);
    final totalFat = _calculateNutrition(food.fat);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            food.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (food.brand != null) ...[
            const SizedBox(height: 4),
            Text(
              food.brand!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Show serving size info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '1 serving = ${food.servingSize.toStringAsFixed(0)}${food.servingUnit} • ${food.calories.toStringAsFixed(0)} kcal',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Grams input
          Row(
            children: [
              Text('Amount', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _gramsController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    suffixText: food.servingUnit,
                    suffixStyle: Theme.of(context).textTheme.bodyMedium,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: _updateGrams,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Quick amount buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _QuickAmountButton(
                label: '50${food.servingUnit}',
                onTap: () {
                  _gramsController.text = '50';
                  _updateGrams('50');
                },
              ),
              const SizedBox(width: 8),
              _QuickAmountButton(
                label: '100${food.servingUnit}',
                onTap: () {
                  _gramsController.text = '100';
                  _updateGrams('100');
                },
              ),
              const SizedBox(width: 8),
              _QuickAmountButton(
                label: '150${food.servingUnit}',
                onTap: () {
                  _gramsController.text = '150';
                  _updateGrams('150');
                },
              ),
              const SizedBox(width: 8),
              _QuickAmountButton(
                label: '200${food.servingUnit}',
                onTap: () {
                  _gramsController.text = '200';
                  _updateGrams('200');
                },
              ),
            ],
          ),

          const Divider(height: 32),

          // Nutrition info
          _buildNutritionRow(
            context,
            'Calories',
            '${totalCalories.toStringAsFixed(0)} kcal',
          ),
          _buildNutritionRow(
            context,
            'Protein',
            '${totalProtein.toStringAsFixed(1)}g',
          ),
          _buildNutritionRow(
            context,
            'Carbohydrates',
            '${totalCarbs.toStringAsFixed(1)}g',
          ),
          _buildNutritionRow(context, 'Fat', '${totalFat.toStringAsFixed(1)}g'),

          const SizedBox(height: 24),

          // Add button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _grams > 0 ? () => widget.onAdd(_getQuantityForApi()) : null,
              icon: const Icon(Icons.add),
              label: Text('Add ${totalCalories.toStringAsFixed(0)} kcal'),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }

  Widget _buildNutritionRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _QuickAmountButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickAmountButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
