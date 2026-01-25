import 'package:flutter/material.dart';
import '../../../data/models/meal_entry.dart';
import '../../../data/models/food_item.dart';
import 'macro_progress_bar.dart';

/// A card widget for displaying a meal with its food items
class MealCardWidget extends StatelessWidget {
  final String mealType;
  final MealEntry? mealEntry;
  final VoidCallback? onAddFood;
  final VoidCallback? onMealTap;
  final Function(FoodItem)? onEditFood;
  final Function(FoodItem)? onDeleteFood;
  final Function(FoodItem)? onSuggestAlternative;
  final VoidCallback? onMarkConsumed;

  const MealCardWidget({
    super.key,
    required this.mealType,
    this.mealEntry,
    this.onAddFood,
    this.onMealTap,
    this.onEditFood,
    this.onDeleteFood,
    this.onSuggestAlternative,
    this.onMarkConsumed,
  });

  @override
  Widget build(BuildContext context) {
    final hasFood =
        mealEntry != null && (mealEntry!.foodItems?.isNotEmpty ?? false);
    final isPlanned = hasFood && !(mealEntry!.isConsumed);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onMealTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    isPlanned
                        ? Colors.orange.withValues(alpha: 0.1)
                        : _getMealColor(context).withValues(alpha: 0.1),
              ),
              child: Row(
                children: [
                  Text(
                    MealTypes.getIcon(mealType),
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              mealType,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (isPlanned) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Planned',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (hasFood)
                          Text(
                            '${mealEntry!.totalCalories.toStringAsFixed(0)} kcal',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: onAddFood,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),

            // Food items or empty state
            if (hasFood) ...[
              const Divider(height: 1),
              // Show "Mark as Eaten" button for planned meals
              if (isPlanned && onMarkConsumed != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.orange.withValues(alpha: 0.05),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This meal is planned',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onMarkConsumed,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Mark as Eaten'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              if (isPlanned && onMarkConsumed != null) const Divider(height: 1),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: mealEntry!.foodItems!.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final food = mealEntry!.foodItems![index];
                  return Dismissible(
                    key: Key('food_${food.id}'),
                    direction:
                        onDeleteFood != null
                            ? DismissDirection.endToStart
                            : DismissDirection.none,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (direction) async {
                      return await showDialog<bool>(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: const Text('Delete Food'),
                              content: Text(
                                'Remove "${food.name}" from this meal?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed:
                                      () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                      );
                    },
                    onDismissed: (direction) {
                      onDeleteFood?.call(food);
                    },
                    child: ListTile(
                      dense: true,
                      onTap:
                          onEditFood != null ? () => onEditFood!(food) : null,
                      title: Text(
                        food.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      subtitle: Text(
                        _formatServingDescription(food),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${food.calories.toStringAsFixed(0)} kcal',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  MacroChip(
                                    label: 'P',
                                    value: food.protein,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 4),
                                  MacroChip(
                                    label: 'C',
                                    value: food.carbohydrates,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 4),
                                  MacroChip(
                                    label: 'F',
                                    value: food.fat,
                                    color: Colors.amber,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: 20,
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                            padding: EdgeInsets.zero,
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  onEditFood?.call(food);
                                  break;
                                case 'suggest':
                                  onSuggestAlternative?.call(food);
                                  break;
                                case 'delete':
                                  onDeleteFood?.call(food);
                                  break;
                              }
                            },
                            itemBuilder:
                                (context) => [
                                  if (onEditFood != null)
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, size: 18),
                                          SizedBox(width: 8),
                                          Text('Edit Quantity'),
                                        ],
                                      ),
                                    ),
                                  if (onSuggestAlternative != null)
                                    const PopupMenuItem(
                                      value: 'suggest',
                                      child: Row(
                                        children: [
                                          Icon(Icons.swap_horiz, size: 18),
                                          SizedBox(width: 8),
                                          Text('Suggest Alternative'),
                                        ],
                                      ),
                                    ),
                                  if (onDeleteFood != null)
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Delete',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.restaurant_menu,
                        size: 32,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No foods logged',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: onAddFood,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Food'),
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

  Color _getMealColor(BuildContext context) {
    switch (mealType) {
      case 'Breakfast':
        return Colors.orange;
      case 'Lunch':
        return Colors.green;
      case 'Dinner':
        return Colors.indigo;
      case 'Snack':
        return Colors.pink;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  /// Format serving description based on unit type
  /// For weight units (g, ml, oz), show "quantity x servingSize unit"
  /// For count units (egg, piece, slice, serving), show "quantity unit(s)"
  String _formatServingDescription(FoodItem food) {
    final unit = food.servingUnit.toLowerCase();
    final quantity = food.quantity * food.servingSize;

    // Count-based units that should display as "2 eggs" instead of "2 x 1egg"
    final countUnits = [
      'egg',
      'piece',
      'slice',
      'serving',
      'cup',
      'tbsp',
      'tsp',
      'scoop',
    ];

    if (countUnits.any((u) => unit.contains(u))) {
      final displayQty = quantity.toStringAsFixed(
        quantity.truncateToDouble() == quantity ? 0 : 1,
      );
      // Pluralize if needed
      final unitDisplay =
          quantity != 1 && !unit.endsWith('s')
              ? '${food.servingUnit}s'
              : food.servingUnit;
      return '$displayQty $unitDisplay';
    }

    // Weight/volume based - show as "quantity x servingSizeunit"
    return food.servingDescription;
  }
}
