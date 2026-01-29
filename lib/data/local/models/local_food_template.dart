import 'package:isar/isar.dart';

part 'local_food_template.g.dart';

/// Local database model for food templates with offline sync support
@collection
class LocalFoodTemplate {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original FoodTemplate Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// Food name
  @Index()
  String name;

  /// Brand name
  String? brand;

  /// Food category
  @Index()
  String? category;

  /// Barcode for quick lookup
  @Index()
  String? barcode;

  /// Serving size
  double servingSize;

  /// Serving unit (e.g., 'g', 'ml', 'oz')
  String servingUnit;

  /// Calories per serving
  double calories;

  /// Protein in grams per serving
  double protein;

  /// Carbohydrates in grams per serving
  double carbohydrates;

  /// Fat in grams per serving
  double fat;

  /// Fiber in grams per serving
  double? fiber;

  /// Sugar in grams per serving
  double? sugar;

  /// Sodium in mg per serving
  double? sodium;

  /// Description or notes
  String? description;

  /// Image URL
  String? imageUrl;

  /// Whether this is a custom user-created template
  @Index()
  bool isCustom;

  /// User ID who created this template (if custom)
  int? createdByUserId;

  /// Timestamp when template was created
  DateTime createdAt;

  /// Timestamp when template was last updated
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
  LocalFoodTemplate({
    this.serverId,
    required this.name,
    this.brand,
    this.category,
    this.barcode,
    this.servingSize = 100,
    this.servingUnit = 'g',
    required this.calories,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
    this.fiber,
    this.sugar,
    this.sodium,
    this.description,
    this.imageUrl,
    this.isCustom = false,
    this.createdByUserId,
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
