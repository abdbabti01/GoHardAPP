import 'package:isar/isar.dart';

part 'local_food_item.g.dart';

/// Local database model for food items with offline sync support
@collection
class LocalFoodItem {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original FoodItem Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// Local ID of parent meal entry
  @Index()
  int mealEntryLocalId;

  /// Server ID of parent meal entry (for API sync)
  int? mealEntryServerId;

  /// Food template ID if created from a template
  int? foodTemplateId;

  /// Name of the food
  String name;

  /// Brand name
  String? brand;

  /// Quantity (multiplier for serving size)
  double quantity;

  /// Serving size
  double servingSize;

  /// Serving unit (e.g., 'g', 'ml', 'oz')
  String servingUnit;

  /// Calories per quantity
  double calories;

  /// Protein in grams per quantity
  double protein;

  /// Carbohydrates in grams per quantity
  double carbohydrates;

  /// Fat in grams per quantity
  double fat;

  /// Fiber in grams per quantity
  double? fiber;

  /// Sugar in grams per quantity
  double? sugar;

  /// Sodium in mg per quantity
  double? sodium;

  /// Timestamp when food item was created
  DateTime createdAt;

  /// Timestamp when food item was last updated
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
  LocalFoodItem({
    this.serverId,
    required this.mealEntryLocalId,
    this.mealEntryServerId,
    this.foodTemplateId,
    required this.name,
    this.brand,
    this.quantity = 1,
    this.servingSize = 100,
    this.servingUnit = 'g',
    required this.calories,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
    this.fiber,
    this.sugar,
    this.sodium,
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
