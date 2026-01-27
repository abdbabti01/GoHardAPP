import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../../providers/nutrition_provider.dart';
import '../../../data/models/food_template.dart';
import '../../../data/services/open_food_facts_service.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final String? preselectedMealType;

  const BarcodeScannerScreen({super.key, this.preselectedMealType});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  final OpenFoodFactsService _openFoodFactsService = OpenFoodFactsService();

  bool _isProcessing = false;
  String? _lastScannedBarcode;
  String? _errorMessage;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(String barcode) async {
    // Prevent duplicate scans
    if (_isProcessing || barcode == _lastScannedBarcode) return;

    setState(() {
      _isProcessing = true;
      _lastScannedBarcode = barcode;
      _errorMessage = null;
    });

    // Pause scanner while processing
    _scannerController.stop();

    try {
      // First try to find in our database
      final provider = context.read<NutritionProvider>();
      FoodTemplate? food = await provider.getFoodByBarcode(barcode);

      // If not found, try Open Food Facts
      food ??= await _openFoodFactsService.getFoodByBarcode(barcode);

      if (!mounted) return;

      if (food != null) {
        // Show food details dialog
        await _showFoodDialog(food);
      } else {
        setState(() {
          _errorMessage = 'Product not found';
        });
        // Resume scanner after delay
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          setState(() {
            _errorMessage = null;
            _lastScannedBarcode = null;
          });
          _scannerController.start();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error scanning barcode';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          setState(() {
            _errorMessage = null;
            _lastScannedBarcode = null;
          });
          _scannerController.start();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _showFoodDialog(FoodTemplate food) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => _ScannedFoodDialog(
            food: food,
            preselectedMealType: widget.preselectedMealType,
          ),
    );

    if (!mounted) return;

    if (result == true) {
      // Food was added, go back
      Navigator.of(context).pop(true);
    } else {
      // User cancelled, resume scanning
      setState(() {
        _lastScannedBarcode = null;
      });
      _scannerController.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _scannerController,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Scanner view
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final barcode = barcodes.first.rawValue;
                if (barcode != null && barcode.isNotEmpty) {
                  _handleBarcode(barcode);
                }
              }
            },
          ),

          // Scan overlay
          _buildScanOverlay(),

          // Status indicators
          if (_isProcessing)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Looking up product...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_errorMessage != null)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Instructions
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Point camera at barcode',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return CustomPaint(
      painter: _ScanOverlayPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.fill;

    final borderPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;

    // Calculate scan area (centered rectangle)
    const scanWidth = 280.0;
    const scanHeight = 150.0;
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 50),
      width: scanWidth,
      height: scanHeight,
    );

    // Draw dark overlay with cutout
    final path =
        Path()
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addRRect(
            RRect.fromRectAndRadius(scanRect, const Radius.circular(12)),
          )
          ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw border around scan area
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(12)),
      borderPaint,
    );

    // Draw corner accents
    const cornerLength = 30.0;
    final cornerPaint =
        Paint()
          ..color = Colors.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;

    // Top left
    canvas.drawLine(
      Offset(scanRect.left, scanRect.top + cornerLength),
      Offset(scanRect.left, scanRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanRect.left, scanRect.top),
      Offset(scanRect.left + cornerLength, scanRect.top),
      cornerPaint,
    );

    // Top right
    canvas.drawLine(
      Offset(scanRect.right - cornerLength, scanRect.top),
      Offset(scanRect.right, scanRect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanRect.right, scanRect.top),
      Offset(scanRect.right, scanRect.top + cornerLength),
      cornerPaint,
    );

    // Bottom left
    canvas.drawLine(
      Offset(scanRect.left, scanRect.bottom - cornerLength),
      Offset(scanRect.left, scanRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanRect.left, scanRect.bottom),
      Offset(scanRect.left + cornerLength, scanRect.bottom),
      cornerPaint,
    );

    // Bottom right
    canvas.drawLine(
      Offset(scanRect.right - cornerLength, scanRect.bottom),
      Offset(scanRect.right, scanRect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanRect.right, scanRect.bottom),
      Offset(scanRect.right, scanRect.bottom - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dialog shown when a product is scanned
class _ScannedFoodDialog extends StatefulWidget {
  final FoodTemplate food;
  final String? preselectedMealType;

  const _ScannedFoodDialog({required this.food, this.preselectedMealType});

  @override
  State<_ScannedFoodDialog> createState() => _ScannedFoodDialogState();
}

class _ScannedFoodDialogState extends State<_ScannedFoodDialog> {
  late TextEditingController _gramsController;
  double _grams = 0;
  String? _selectedMealType;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _grams = widget.food.servingSize;
    _gramsController = TextEditingController(text: _grams.toStringAsFixed(0));
    _selectedMealType = widget.preselectedMealType;
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

  double _calculateNutrition(double perServing) {
    if (widget.food.servingSize <= 0) return 0;
    return (perServing / widget.food.servingSize) * _grams;
  }

  double _getQuantityForApi() {
    if (widget.food.servingSize <= 0) return 1;
    return _grams / widget.food.servingSize;
  }

  Future<void> _addFood() async {
    if (_selectedMealType == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a meal')));
      return;
    }

    setState(() {
      _isAdding = true;
    });

    final provider = context.read<NutritionProvider>();
    final mealEntry = provider.getMealEntryByType(_selectedMealType!);

    if (mealEntry == null || mealEntry.id == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find meal entry')),
      );
      setState(() {
        _isAdding = false;
      });
      return;
    }

    bool success;

    // If food has no ID (from Open Food Facts), create it first
    if (widget.food.id == 0) {
      success = await provider.createAndAddCustomFood(
        mealEntryId: mealEntry.id,
        name: widget.food.name,
        brand: widget.food.brand,
        category: widget.food.category,
        servingSize: widget.food.servingSize,
        servingUnit: widget.food.servingUnit,
        calories: widget.food.calories,
        protein: widget.food.protein,
        carbohydrates: widget.food.carbohydrates,
        fat: widget.food.fat,
        fiber: widget.food.fiber,
        sugar: widget.food.sugar,
        sodium: widget.food.sodium,
        quantity: _getQuantityForApi(),
      );
    } else {
      success = await provider.quickAddFood(
        mealEntryId: mealEntry.id,
        foodTemplateId: widget.food.id,
        quantity: _getQuantityForApi(),
      );
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to add food')));
      setState(() {
        _isAdding = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final food = widget.food;
    final totalCalories = _calculateNutrition(food.calories);
    final totalProtein = _calculateNutrition(food.protein);
    final totalCarbs = _calculateNutrition(food.carbohydrates);
    final totalFat = _calculateNutrition(food.fat);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(food.name, style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (food.brand != null) ...[
              Text(
                food.brand!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Serving info
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '1 serving = ${food.servingSize.toStringAsFixed(0)}${food.servingUnit} (${food.calories.toStringAsFixed(0)} kcal)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            const SizedBox(height: 16),

            // Meal type selector
            if (_selectedMealType == null) ...[
              Text(
                'Select Meal',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    ['Breakfast', 'Lunch', 'Dinner', 'Snack'].map((type) {
                      return ChoiceChip(
                        label: Text(type),
                        selected: _selectedMealType == type,
                        onSelected: (selected) {
                          setState(() {
                            _selectedMealType = selected ? type : null;
                          });
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Amount input
            Row(
              children: [
                Text('Amount', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _gramsController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      suffixText: food.servingUnit,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: _updateGrams,
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Nutrition summary
            _buildNutritionRow(
              'Calories',
              '${totalCalories.toStringAsFixed(0)} kcal',
            ),
            _buildNutritionRow(
              'Protein',
              '${totalProtein.toStringAsFixed(1)}g',
            ),
            _buildNutritionRow('Carbs', '${totalCarbs.toStringAsFixed(1)}g'),
            _buildNutritionRow('Fat', '${totalFat.toStringAsFixed(1)}g'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isAdding ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isAdding || _grams <= 0 ? null : _addFood,
          child:
              _isAdding
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildNutritionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
