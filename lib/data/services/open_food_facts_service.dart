import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/food_template.dart';

/// Service for fetching food data from Open Food Facts API
class OpenFoodFactsService {
  final Dio _dio;

  OpenFoodFactsService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://world.openfoodfacts.org/api/v2',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  /// Get food product by barcode from Open Food Facts
  Future<FoodTemplate?> getFoodByBarcode(String barcode) async {
    try {
      final response = await _dio.get(
        '/product/$barcode',
        queryParameters: {
          'fields':
              'code,product_name,brands,serving_size,nutriments,categories_tags',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 1 && data['product'] != null) {
          return _parseProduct(data['product'], barcode);
        }
      }

      debugPrint('Product not found in Open Food Facts: $barcode');
      return null;
    } catch (e) {
      debugPrint('Open Food Facts API error: $e');
      return null;
    }
  }

  /// Parse Open Food Facts product data into FoodTemplate
  FoodTemplate? _parseProduct(Map<String, dynamic> product, String barcode) {
    try {
      final name = product['product_name'] as String?;
      if (name == null || name.isEmpty) return null;

      final nutriments = product['nutriments'] as Map<String, dynamic>? ?? {};
      final brand = product['brands'] as String?;

      // Parse serving size (default to 100g if not available)
      double servingSize = 100;
      String servingUnit = 'g';

      final servingSizeStr = product['serving_size'] as String?;
      if (servingSizeStr != null && servingSizeStr.isNotEmpty) {
        final match = RegExp(
          r'(\d+(?:\.\d+)?)\s*([a-zA-Z]+)?',
        ).firstMatch(servingSizeStr);
        if (match != null) {
          servingSize = double.tryParse(match.group(1) ?? '') ?? 100;
          servingUnit = match.group(2) ?? 'g';
        }
      }

      // Get per-100g values and calculate per-serving
      final caloriesPer100 =
          (nutriments['energy-kcal_100g'] as num?)?.toDouble() ??
          (nutriments['energy-kcal'] as num?)?.toDouble() ??
          0;
      final proteinPer100 =
          (nutriments['proteins_100g'] as num?)?.toDouble() ??
          (nutriments['proteins'] as num?)?.toDouble() ??
          0;
      final carbsPer100 =
          (nutriments['carbohydrates_100g'] as num?)?.toDouble() ??
          (nutriments['carbohydrates'] as num?)?.toDouble() ??
          0;
      final fatPer100 =
          (nutriments['fat_100g'] as num?)?.toDouble() ??
          (nutriments['fat'] as num?)?.toDouble() ??
          0;
      final fiberPer100 =
          (nutriments['fiber_100g'] as num?)?.toDouble() ??
          (nutriments['fiber'] as num?)?.toDouble();
      final sugarPer100 =
          (nutriments['sugars_100g'] as num?)?.toDouble() ??
          (nutriments['sugars'] as num?)?.toDouble();
      final sodiumPer100 =
          (nutriments['sodium_100g'] as num?)?.toDouble() ??
          (nutriments['sodium'] as num?)?.toDouble();

      // Calculate per-serving values
      final multiplier = servingSize / 100;
      final calories = caloriesPer100 * multiplier;
      final protein = proteinPer100 * multiplier;
      final carbs = carbsPer100 * multiplier;
      final fat = fatPer100 * multiplier;
      final fiber = fiberPer100 != null ? fiberPer100 * multiplier : null;
      final sugar = sugarPer100 != null ? sugarPer100 * multiplier : null;
      final sodium = sodiumPer100 != null ? sodiumPer100 * multiplier : null;

      // Parse category
      String category = 'Uncategorized';
      final categories = product['categories_tags'] as List<dynamic>?;
      if (categories != null && categories.isNotEmpty) {
        // Get the first category and clean it up
        category = (categories.first as String)
            .replaceAll('en:', '')
            .replaceAll('-', ' ')
            .split(' ')
            .map(
              (word) =>
                  word.isNotEmpty
                      ? '${word[0].toUpperCase()}${word.substring(1)}'
                      : '',
            )
            .join(' ');
      }

      return FoodTemplate(
        id: 0, // Will be assigned by API when saved
        name: name,
        brand: brand,
        barcode: barcode,
        category: category,
        servingSize: servingSize,
        servingUnit: servingUnit,
        calories: calories,
        protein: protein,
        carbohydrates: carbs,
        fat: fat,
        fiber: fiber,
        sugar: sugar,
        sodium: sodium,
        isCustom: false,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Error parsing Open Food Facts product: $e');
      return null;
    }
  }
}
