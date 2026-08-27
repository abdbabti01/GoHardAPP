import '../models/local_meal_entry.dart';

/// Immutable, typed aggregation result for a single meal log's nutrient
/// totals.
///
/// Mirrors the fields actually persisted on [LocalMealLog]/`MealLog`:
/// calories, protein, and carbohydrates/fat are always present; fiber and
/// sodium are nullable to match the underlying `double?` schema fields.
class LocalNutritionTotals {
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;
  final double fiber;
  final double sodium;

  const LocalNutritionTotals({
    required this.calories,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
    required this.fiber,
    required this.sodium,
  });

  static const LocalNutritionTotals zero = LocalNutritionTotals(
    calories: 0,
    protein: 0,
    carbohydrates: 0,
    fat: 0,
    fiber: 0,
    sodium: 0,
  );
}

/// Single, pure source of truth for aggregating [LocalMealEntry] rows into
/// planned and consumed nutrition totals.
///
/// Authoritative invariant (matches the deployed GoHardAPI contract, where
/// `MealLog.RecalculateTotals` defaults to `consumedOnly: true`):
/// - `MealLog.total*` / `LocalMealLog.total*` mean **consumed-only**.
/// - `MealEntry.total*` / `LocalMealEntry.total*` are status-independent
///   (each entry's own food sum, regardless of `isConsumed`) and are never
///   changed by this calculator.
/// - Planned = every entry. Consumed = only entries where
///   `isConsumed == true`.
///
/// Used by repository mutation reconciliation, legacy-cache read repair,
/// and sync payload construction, so there is exactly one formula for
/// "what counts as consumed" across storage, repair, and the network
/// boundary.
class LocalNutritionTotalsCalculator {
  const LocalNutritionTotalsCalculator._();

  /// Sum of every entry, regardless of consumed status.
  static LocalNutritionTotals planned(List<LocalMealEntry> entries) {
    return _sum(entries);
  }

  /// Sum of only the entries where `isConsumed == true`.
  static LocalNutritionTotals consumed(List<LocalMealEntry> entries) {
    return _sum(entries.where((entry) => entry.isConsumed));
  }

  static LocalNutritionTotals _sum(Iterable<LocalMealEntry> entries) {
    var calories = 0.0;
    var protein = 0.0;
    var carbohydrates = 0.0;
    var fat = 0.0;
    var fiber = 0.0;
    var sodium = 0.0;

    for (final entry in entries) {
      calories += entry.totalCalories;
      protein += entry.totalProtein;
      carbohydrates += entry.totalCarbohydrates;
      fat += entry.totalFat;
      fiber += entry.totalFiber ?? 0;
      sodium += entry.totalSodium ?? 0;
    }

    return LocalNutritionTotals(
      calories: calories,
      protein: protein,
      carbohydrates: carbohydrates,
      fat: fat,
      fiber: fiber,
      sodium: sodium,
    );
  }
}
