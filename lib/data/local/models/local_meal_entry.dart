import 'package:isar/isar.dart';

part 'local_meal_entry.g.dart';

/// Local database model for meal entries with offline sync support
@collection
class LocalMealEntry {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original MealEntry Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// Local ID of parent meal log
  @Index()
  int mealLogLocalId;

  /// Server ID of parent meal log (for API sync)
  int? mealLogServerId;

  /// Type of meal: 'Breakfast', 'Lunch', 'Dinner', 'Snack'
  @Index()
  String mealType;

  /// Custom name for the meal
  String? name;

  /// Scheduled time for the meal
  DateTime? scheduledTime;

  /// Whether the meal has been consumed
  bool isConsumed;

  /// Timestamp when the meal was consumed
  DateTime? consumedAt;

  /// Optional notes for the meal
  String? notes;

  /// Total calories for this meal (calculated from food items)
  double totalCalories;

  /// Total protein in grams
  double totalProtein;

  /// Total carbohydrates in grams
  double totalCarbohydrates;

  /// Total fat in grams
  double totalFat;

  /// Total fiber in grams
  double? totalFiber;

  /// Total sodium in mg
  double? totalSodium;

  /// Timestamp when meal entry was created
  DateTime createdAt;

  /// Timestamp when meal entry was last updated
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
  LocalMealEntry({
    this.serverId,
    required this.mealLogLocalId,
    this.mealLogServerId,
    this.mealType = 'Snack',
    this.name,
    this.scheduledTime,
    this.isConsumed = false,
    this.consumedAt,
    this.notes,
    this.totalCalories = 0,
    this.totalProtein = 0,
    this.totalCarbohydrates = 0,
    this.totalFat = 0,
    this.totalFiber,
    this.totalSodium,
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
