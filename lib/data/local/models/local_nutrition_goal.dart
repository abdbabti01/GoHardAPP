import 'package:isar/isar.dart';

part 'local_nutrition_goal.g.dart';

/// Local database model for nutrition goals with offline sync support
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
    this.isSynced = false,
    this.syncStatus = 'pending_create',
    required this.lastModifiedLocal,
    this.lastModifiedServer,
    this.syncRetryCount = 0,
    this.lastSyncAttempt,
    this.syncError,
  });
}
