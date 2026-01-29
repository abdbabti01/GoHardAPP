import 'package:isar/isar.dart';

part 'local_meal_log.g.dart';

/// Local database model for daily meal logs with offline sync support
@collection
class LocalMealLog {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original MealLog Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// User ID who owns this meal log
  @Index()
  int userId;

  /// Date of the meal log (one per day per user)
  @Index()
  DateTime date;

  /// Optional notes for the day
  String? notes;

  /// Water intake in ml
  double waterIntake;

  /// Total calories for the day (calculated from meal entries)
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

  /// Timestamp when meal log was created
  DateTime createdAt;

  /// Timestamp when meal log was last updated
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
  LocalMealLog({
    this.serverId,
    required this.userId,
    required this.date,
    this.notes,
    this.waterIntake = 0,
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
