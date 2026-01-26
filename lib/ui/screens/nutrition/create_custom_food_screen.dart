import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../data/models/meal_entry.dart';

class CreateCustomFoodScreen extends StatefulWidget {
  final String? preselectedMealType;

  const CreateCustomFoodScreen({super.key, this.preselectedMealType});

  @override
  State<CreateCustomFoodScreen> createState() => _CreateCustomFoodScreenState();
}

class _CreateCustomFoodScreenState extends State<CreateCustomFoodScreen> {
  final _formKey = GlobalKey<FormState>();

  // Basic info controllers
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _servingSizeController = TextEditingController(text: '100');

  // Macro controllers
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();

  // Optional micro controllers
  final _fiberController = TextEditingController();
  final _sugarController = TextEditingController();
  final _sodiumController = TextEditingController();

  String _selectedMealType = '';
  String _servingUnit = 'g';
  String _category = 'Custom';
  bool _showOptionalFields = false;
  bool _saveAsTemplate = true;
  bool _isSubmitting = false;

  final List<String> _servingUnits = [
    'g',
    'ml',
    'oz',
    'cup',
    'tbsp',
    'tsp',
    'piece',
  ];
  final List<String> _categories = [
    'Custom',
    'Proteins',
    'Carbohydrates',
    'Vegetables',
    'Fruits',
    'Dairy',
    'Fats & Oils',
    'Snacks',
    'Beverages',
  ];

  @override
  void initState() {
    super.initState();
    _selectedMealType = widget.preselectedMealType ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _servingSizeController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    _fiberController.dispose();
    _sugarController.dispose();
    _sodiumController.dispose();
    super.dispose();
  }

  double? _parseDouble(String value) {
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedMealType.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a meal')));
      return;
    }

    setState(() => _isSubmitting = true);

    final provider = context.read<NutritionProvider>();
    final mealEntry = provider.getMealEntryByType(_selectedMealType);

    if (mealEntry == null || mealEntry.id == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find meal entry')),
      );
      setState(() => _isSubmitting = false);
      return;
    }

    final name = _nameController.text.trim();
    final brand = _brandController.text.trim();
    final servingSize = _parseDouble(_servingSizeController.text) ?? 100;
    final calories = _parseDouble(_caloriesController.text) ?? 0;
    final protein = _parseDouble(_proteinController.text) ?? 0;
    final carbs = _parseDouble(_carbsController.text) ?? 0;
    final fat = _parseDouble(_fatController.text) ?? 0;
    final fiber = _parseDouble(_fiberController.text);
    final sugar = _parseDouble(_sugarController.text);
    final sodium = _parseDouble(_sodiumController.text);

    bool success;

    if (_saveAsTemplate) {
      // Create as reusable template and add to meal
      success = await provider.createAndAddCustomFood(
        mealEntryId: mealEntry.id,
        name: name,
        brand: brand.isNotEmpty ? brand : null,
        category: _category,
        servingSize: servingSize,
        servingUnit: _servingUnit,
        calories: calories,
        protein: protein,
        carbohydrates: carbs,
        fat: fat,
        fiber: fiber,
        sugar: sugar,
        sodium: sodium,
        quantity: 1,
      );
    } else {
      // Add as one-time food item
      success = await provider.addCustomFood(
        mealEntryId: mealEntry.id,
        name: name,
        calories: calories,
        protein: protein,
        carbohydrates: carbs,
        fat: fat,
        servingSize: servingSize,
        servingUnit: _servingUnit,
        quantity: 1,
      );
    }

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $name to $_selectedMealType')),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to add food'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Custom Food')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Meal type selector
            if (_selectedMealType.isEmpty) ...[
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
                            _selectedMealType = selected ? type : '';
                          });
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            // Basic info section
            Text(
              'Food Information',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Name field
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Food Name *',
                hintText: 'e.g., Homemade Protein Shake',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a food name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Brand field
            TextFormField(
              controller: _brandController,
              decoration: const InputDecoration(
                labelText: 'Brand (optional)',
                hintText: 'e.g., Homemade',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),

            // Serving size row
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _servingSizeController,
                    decoration: const InputDecoration(
                      labelText: 'Serving Size *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      final number = double.tryParse(value);
                      if (number == null || number <= 0) {
                        return 'Invalid';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _servingUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        _servingUnits.map((unit) {
                          return DropdownMenuItem(
                            value: unit,
                            child: Text(unit),
                          );
                        }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _servingUnit = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Macros section
            Text(
              'Nutrition Facts (per serving)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Calories
            TextFormField(
              controller: _caloriesController,
              decoration: const InputDecoration(
                labelText: 'Calories *',
                suffixText: 'kcal',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter calories';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Macro row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _proteinController,
                    decoration: const InputDecoration(
                      labelText: 'Protein *',
                      suffixText: 'g',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _carbsController,
                    decoration: const InputDecoration(
                      labelText: 'Carbs *',
                      suffixText: 'g',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _fatController,
                    decoration: const InputDecoration(
                      labelText: 'Fat *',
                      suffixText: 'g',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Optional fields toggle
            TextButton.icon(
              onPressed: () {
                setState(() => _showOptionalFields = !_showOptionalFields);
              },
              icon: Icon(
                _showOptionalFields ? Icons.expand_less : Icons.expand_more,
              ),
              label: Text(
                _showOptionalFields
                    ? 'Hide optional fields'
                    : 'Show optional fields',
              ),
            ),

            // Optional fields
            if (_showOptionalFields) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fiberController,
                      decoration: const InputDecoration(
                        labelText: 'Fiber',
                        suffixText: 'g',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _sugarController,
                      decoration: const InputDecoration(
                        labelText: 'Sugar',
                        suffixText: 'g',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _sodiumController,
                      decoration: const InputDecoration(
                        labelText: 'Sodium',
                        suffixText: 'mg',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Category dropdown
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items:
                    _categories.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat));
                    }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
            ],

            const SizedBox(height: 24),

            // Save as template toggle
            SwitchListTile(
              title: const Text('Save for future use'),
              subtitle: const Text(
                'This food will appear in your search results',
              ),
              value: _saveAsTemplate,
              onChanged: (value) {
                setState(() => _saveAsTemplate = value);
              },
            ),

            const SizedBox(height: 24),

            // Submit button
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon:
                  _isSubmitting
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.add),
              label: Text(_isSubmitting ? 'Adding...' : 'Add Food'),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
