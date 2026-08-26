import 'package:flutter_test/flutter_test.dart';

import 'package:go_hard_app/data/local/models/local_meal_entry.dart';
import 'package:go_hard_app/data/local/services/local_nutrition_totals_calculator.dart';

LocalMealEntry _entry({
  required bool isConsumed,
  required double calories,
  required double protein,
  required double carbohydrates,
  required double fat,
  double? fiber,
  double? sodium,
}) {
  final now = DateTime.now();
  return LocalMealEntry(
    mealLogLocalId: 1,
    isConsumed: isConsumed,
    totalCalories: calories,
    totalProtein: protein,
    totalCarbohydrates: carbohydrates,
    totalFat: fat,
    totalFiber: fiber,
    totalSodium: sodium,
    createdAt: now,
    lastModifiedLocal: now,
  );
}

void main() {
  group('LocalNutritionTotalsCalculator', () {
    test('empty entries produce zero planned and consumed totals', () {
      final planned = LocalNutritionTotalsCalculator.planned(const []);
      final consumed = LocalNutritionTotalsCalculator.consumed(const []);

      for (final totals in [planned, consumed]) {
        expect(totals.calories, 0);
        expect(totals.protein, 0);
        expect(totals.carbohydrates, 0);
        expect(totals.fat, 0);
        expect(totals.fiber, 0);
        expect(totals.sodium, 0);
      }
    });

    test('unconsumed-only entries contribute to planned but not consumed', () {
      final entries = [
        _entry(
          isConsumed: false,
          calories: 100,
          protein: 10,
          carbohydrates: 20,
          fat: 5,
          fiber: 3,
          sodium: 150,
        ),
      ];

      final planned = LocalNutritionTotalsCalculator.planned(entries);
      final consumed = LocalNutritionTotalsCalculator.consumed(entries);

      expect(planned.calories, 100);
      expect(planned.protein, 10);
      expect(planned.carbohydrates, 20);
      expect(planned.fat, 5);
      expect(planned.fiber, 3);
      expect(planned.sodium, 150);

      expect(consumed.calories, 0);
      expect(consumed.protein, 0);
      expect(consumed.carbohydrates, 0);
      expect(consumed.fat, 0);
      expect(consumed.fiber, 0);
      expect(consumed.sodium, 0);
    });

    test(
      'consumed-only entries contribute equally to planned and consumed',
      () {
        final entries = [
          _entry(
            isConsumed: true,
            calories: 100,
            protein: 10,
            carbohydrates: 20,
            fat: 5,
            fiber: 3,
            sodium: 150,
          ),
        ];

        final planned = LocalNutritionTotalsCalculator.planned(entries);
        final consumed = LocalNutritionTotalsCalculator.consumed(entries);

        expect(planned.calories, 100);
        expect(consumed.calories, 100);
        expect(planned.protein, consumed.protein);
        expect(planned.carbohydrates, consumed.carbohydrates);
        expect(planned.fat, consumed.fat);
        expect(planned.fiber, consumed.fiber);
        expect(planned.sodium, consumed.sodium);
      },
    );

    test(
      'mixed consumed/unconsumed entries calculate calories and every macro correctly',
      () {
        final entries = [
          _entry(
            isConsumed: true,
            calories: 100,
            protein: 10,
            carbohydrates: 20,
            fat: 5,
            fiber: 3,
            sodium: 200,
          ),
          _entry(
            isConsumed: false,
            calories: 300,
            protein: 25,
            carbohydrates: 40,
            fat: 12,
            fiber: 4,
            sodium: 500,
          ),
          _entry(
            isConsumed: true,
            calories: 50,
            protein: 4,
            carbohydrates: 6,
            fat: 2,
            fiber: 1,
            sodium: 80,
          ),
        ];

        final planned = LocalNutritionTotalsCalculator.planned(entries);
        final consumed = LocalNutritionTotalsCalculator.consumed(entries);

        expect(planned.calories, 450);
        expect(planned.protein, 39);
        expect(planned.carbohydrates, 66);
        expect(planned.fat, 19);
        expect(planned.fiber, 8);
        expect(planned.sodium, 780);

        expect(consumed.calories, 150);
        expect(consumed.protein, 14);
        expect(consumed.carbohydrates, 26);
        expect(consumed.fat, 7);
        expect(consumed.fiber, 4);
        expect(consumed.sodium, 280);
      },
    );

    test('entries with null fiber/sodium are treated as zero, not skipped', () {
      final entries = [
        _entry(
          isConsumed: true,
          calories: 100,
          protein: 10,
          carbohydrates: 20,
          fat: 5,
        ),
      ];

      final consumed = LocalNutritionTotalsCalculator.consumed(entries);

      expect(consumed.fiber, 0);
      expect(consumed.sodium, 0);
    });

    test('does not mutate input entries', () {
      final entry = _entry(
        isConsumed: true,
        calories: 100,
        protein: 10,
        carbohydrates: 20,
        fat: 5,
      );

      LocalNutritionTotalsCalculator.consumed([entry]);
      LocalNutritionTotalsCalculator.planned([entry]);

      expect(entry.totalCalories, 100);
      expect(entry.totalProtein, 10);
      expect(entry.totalCarbohydrates, 20);
      expect(entry.totalFat, 5);
      expect(entry.isConsumed, true);
    });
  });
}
