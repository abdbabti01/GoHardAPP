import 'package:isar/isar.dart';

part 'legacy_local_nutrition_goal.g.dart';

/// TEST-ONLY fixture: a byte-for-byte copy of the `LocalNutritionGoal`
/// collection exactly as it was at this branch's base commit (`HEAD` at the
/// time this fixture was written), BEFORE Phase 3's `effectiveDate`/
/// `deletedAt` fields existed. This is never imported by production code -
/// its sole purpose is to let a test write real, on-disk Isar data using the
/// OLD generated schema, then reopen that same on-disk database with the
/// CURRENT production schema (`lib/data/local/models/local_nutrition_goal.dart`,
/// imported side-by-side under a different prefix) to prove the additive
/// schema change opens and reads old data safely.
///
/// The class name is deliberately `LocalNutritionGoal` (matching production)
/// so Isar's collection identity (derived from the collection NAME, hashed -
/// see `CollectionSchema.id` in the generated file) is the SAME collection as
/// production's `LocalNutritionGoal` - this is what makes cross-schema-version
/// opening of the SAME on-disk directory possible without ever touching or
/// renaming the real production model.
///
/// Do NOT update this file when `local_nutrition_goal.dart` changes again -
/// it must stay frozen at the pre-effectiveDate/deletedAt shape to keep
/// testing the specific upgrade this fixture exists for.
@collection
class LocalNutritionGoal {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original NutritionGoal Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// User ID who owns this goal
  @Index()
  int userId;

  /// Goal name (e.g., 'Bulking', 'Cutting', 'Maintenance')
  String? name;

  /// Daily calorie target
  double dailyCalories;

  /// Daily protein target in grams
  double dailyProtein;

  /// Daily carbohydrates target in grams
  double dailyCarbohydrates;

  /// Daily fat target in grams
  double dailyFat;

  /// Daily fiber target in grams
  double? dailyFiber;

  /// Daily sodium target in mg
  double? dailySodium;

  /// Daily sugar target in grams
  double? dailySugar;

  /// Daily water target in ml
  double? dailyWater;

  /// Protein percentage (optional override)
  double? proteinPercentage;

  /// Carbohydrates percentage (optional override)
  double? carbohydratesPercentage;

  /// Fat percentage (optional override)
  double? fatPercentage;

  /// Whether this is the active goal
  @Index()
  bool isActive;

  /// Timestamp when goal was created
  DateTime createdAt;

  /// Timestamp when goal was last updated
  DateTime? updatedAt;

  /// Explanation of how the nutrition targets were calculated
  String? explanation;

  /// BMR (Basal Metabolic Rate) used in calculation
  double? bmr;

  /// TDEE (Total Daily Energy Expenditure) used in calculation
  double? tdee;

  /// Daily calorie adjustment (deficit or surplus)
  double? calorieAdjustment;

  // ========== Sync Tracking Fields ==========

  /// Whether entity is in sync with server
  @Index()
  bool isSynced;

  /// Current sync status: 'synced', 'pending_create', 'pending_update', 'pending_delete'
  @Index()
  String syncStatus;

  /// Timestamp of last local modification
  DateTime lastModifiedLocal;

  /// Timestamp of last server modification (from API response)
  DateTime? lastModifiedServer;

  /// Number of failed sync attempts
  int syncRetryCount;

  /// Timestamp of last sync attempt
  DateTime? lastSyncAttempt;

  /// Error message from last failed sync
  String? syncError;

  /// Constructor
  LocalNutritionGoal({
    this.serverId,
    required this.userId,
    this.name,
    this.dailyCalories = 0,
    this.dailyProtein = 0,
    this.dailyCarbohydrates = 0,
    this.dailyFat = 0,
    this.dailyFiber,
    this.dailySodium,
    this.dailySugar,
    this.dailyWater,
    this.proteinPercentage,
    this.carbohydratesPercentage,
    this.fatPercentage,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
    this.explanation,
    this.bmr,
    this.tdee,
    this.calorieAdjustment,
    this.isSynced = false,
    this.syncStatus = 'pending_create',
    required this.lastModifiedLocal,
    this.lastModifiedServer,
    this.syncRetryCount = 0,
    this.lastSyncAttempt,
    this.syncError,
  });
}
