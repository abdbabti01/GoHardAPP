import 'package:flutter/material.dart';

/// Preview card for displaying AI-generated meal plans in chat
/// Shows structured meal data with expandable days and action buttons
class MealPlanPreviewCard extends StatefulWidget {
  final Map<String, dynamic> planData;
  final VoidCallback onApply;
  final Function(int day)? onApplyDay;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;

  const MealPlanPreviewCard({
    super.key,
    required this.planData,
    required this.onApply,
    this.onApplyDay,
    this.onEdit,
    this.onRegenerate,
  });

  @override
  State<MealPlanPreviewCard> createState() => _MealPlanPreviewCardState();
}

class _MealPlanPreviewCardState extends State<MealPlanPreviewCard> {
  bool _isExpanded = false;
  int? _selectedDay;

  List<dynamic> get days => (widget.planData['days'] as List?) ?? [];

  double get targetCalories =>
      (widget.planData['targetCalories'] as num?)?.toDouble() ?? 2000;

  double get avgCalories {
    if (days.isEmpty) return targetCalories;
    double total = 0;
    for (final day in days) {
      total += (day['totalCalories'] as num?)?.toDouble() ?? 0;
    }
    return total / days.length;
  }

  double get avgProtein {
    if (days.isEmpty) return 0;
    double total = 0;
    for (final day in days) {
      total += (day['totalProtein'] as num?)?.toDouble() ?? 0;
    }
    return total / days.length;
  }

  double get avgCarbs {
    if (days.isEmpty) return 0;
    double total = 0;
    for (final day in days) {
      total += (day['totalCarbs'] as num?)?.toDouble() ?? 0;
    }
    return total / days.length;
  }

  double get avgFat {
    if (days.isEmpty) return 0;
    double total = 0;
    for (final day in days) {
      total += (day['totalFat'] as num?)?.toDouble() ?? 0;
    }
    return total / days.length;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(context),

          // Macro summary
          _buildMacroSummary(context),

          // Expandable days
          _buildDaysList(context),

          // Quick day selection chips
          if (widget.onApplyDay != null) _buildDayChips(context),

          // Action buttons
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.restaurant_menu,
              color: Colors.green,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Meal Plan Ready',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${days.length}-Day Plan',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${avgCalories.round()} kcal/day',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
          ),
          if (widget.onEdit != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: widget.onEdit,
              tooltip: 'Edit Plan',
              color: Colors.green,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroSummary(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMacroIndicator('Protein', avgProtein.round(), 'g', Colors.red),
          _buildMacroIndicator('Carbs', avgCarbs.round(), 'g', Colors.blue),
          _buildMacroIndicator('Fat', avgFat.round(), 'g', Colors.purple),
        ],
      ),
    );
  }

  Widget _buildMacroIndicator(
    String label,
    int value,
    String unit,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color,
                  ),
                ),
                Text(unit, style: TextStyle(fontSize: 9, color: color)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildDaysList(BuildContext context) {
    return Column(
      children: [
        // Toggle expand button
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  _isExpanded ? 'Hide Days' : 'View Days',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded day list
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children:
                days.asMap().entries.map((entry) {
                  return _buildDayTile(
                    entry.key + 1,
                    entry.value as Map<String, dynamic>,
                  );
                }).toList(),
          ),
          crossFadeState:
              _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildDayTile(int dayNumber, Map<String, dynamic> day) {
    final totalCalories = (day['totalCalories'] as num?)?.toDouble() ?? 0;
    final totalProtein = (day['totalProtein'] as num?)?.toDouble() ?? 0;
    final meals = (day['meals'] as List?) ?? [];

    final isWithinTarget =
        (totalCalories - targetCalories).abs() <= targetCalories * 0.1;

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor:
            isWithinTarget
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.orange.withValues(alpha: 0.2),
        radius: 18,
        child: Text(
          'D$dayNumber',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: isWithinTarget ? Colors.green : Colors.orange,
          ),
        ),
      ),
      title: Text(
        'Day $dayNumber',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Row(
        children: [
          Text(
            '${totalCalories.round()} kcal',
            style: TextStyle(
              fontSize: 12,
              color:
                  isWithinTarget
                      ? Colors.green.shade600
                      : Colors.orange.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            ' • ${totalProtein.round()}g protein',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
      trailing:
          widget.onApplyDay != null
              ? TextButton(
                onPressed: () => widget.onApplyDay!(dayNumber),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Apply', style: TextStyle(fontSize: 12)),
              )
              : null,
      children:
          meals
              .map((meal) => _buildMealTile(meal as Map<String, dynamic>))
              .toList(),
    );
  }

  Widget _buildMealTile(Map<String, dynamic> meal) {
    final mealType = meal['mealType'] as String? ?? 'Meal';
    final foods = (meal['foods'] as List?) ?? [];
    final totalCalories = (meal['totalCalories'] as num?)?.toDouble() ?? 0;

    IconData mealIcon;
    Color mealColor;
    switch (mealType.toLowerCase()) {
      case 'breakfast':
        mealIcon = Icons.free_breakfast;
        mealColor = Colors.orange;
        break;
      case 'lunch':
        mealIcon = Icons.lunch_dining;
        mealColor = Colors.blue;
        break;
      case 'dinner':
        mealIcon = Icons.dinner_dining;
        mealColor = Colors.purple;
        break;
      case 'snack':
        mealIcon = Icons.icecream;
        mealColor = Colors.pink;
        break;
      default:
        mealIcon = Icons.restaurant;
        mealColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(mealIcon, size: 18, color: mealColor),
              const SizedBox(width: 8),
              Text(
                mealType,
                style: TextStyle(fontWeight: FontWeight.w600, color: mealColor),
              ),
              const Spacer(),
              Text(
                '${totalCalories.round()} kcal',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (foods.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...foods.map((food) {
              final name = food['name'] as String? ?? 'Food';
              final calories = (food['calories'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(name, style: const TextStyle(fontSize: 12)),
                    ),
                    Text(
                      '${calories.round()} kcal',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDayChips(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Apply:',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(days.length, (index) {
              final dayNumber = index + 1;
              final isSelected = _selectedDay == dayNumber;
              return ChoiceChip(
                label: Text('Day $dayNumber'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedDay = selected ? dayNumber : null;
                  });
                  if (selected && widget.onApplyDay != null) {
                    widget.onApplyDay!(dayNumber);
                  }
                },
                selectedColor: Colors.green.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color:
                      isSelected ? Colors.green.shade700 : Colors.grey.shade700,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          if (widget.onRegenerate != null) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onRegenerate,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Regenerate'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: widget.onApply,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Apply Full Week'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
