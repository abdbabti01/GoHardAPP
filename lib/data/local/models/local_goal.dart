import 'package:isar/isar.dart';

part 'local_goal.g.dart';

/// Local database model for fitness goals with offline sync support
@collection
class LocalGoal {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original Goal Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// User ID who owns this goal
  @Index()
  int userId;

  /// Type of goal: WorkoutFrequency, Weight, Volume, Exercise, BodyFat
  @Index()
  String goalType;

  /// Target value to achieve
  double targetValue;

  /// Current progress value
  double currentValue;

  /// Unit of measurement (e.g., 'lb', 'kg', 'workouts')
  String? unit;

  /// Time frame: weekly, monthly, total
  String? timeFrame;

  /// Goal start date
  DateTime startDate;

  /// Target completion date
  DateTime? targetDate;

  /// Whether goal is currently active
  @Index()
  bool isActive;

  /// Whether goal is completed
  bool isCompleted;

  /// Timestamp when goal was completed
  DateTime? completedAt;

  /// Timestamp when goal was created
  DateTime createdAt;

  // ========== Sync Tracking Fields ==========

  /// Whether entity is in sync with server
  @Index()
  bool isSynced;

  /// Current sync status
  @Index()
  String syncStatus; // 'synced', 'pending_create', 'pending_update', 'pending_delete'

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
  LocalGoal({
    this.serverId,
    required this.userId,
    required this.goalType,
    required this.targetValue,
    required this.currentValue,
    this.unit,
    this.timeFrame,
    required this.startDate,
    this.targetDate,
    this.isActive = true,
    this.isCompleted = false,
    this.completedAt,
    required this.createdAt,
    this.isSynced = false,
    this.syncStatus = 'pending_create',
    required this.lastModifiedLocal,
    this.lastModifiedServer,
    this.syncRetryCount = 0,
    this.lastSyncAttempt,
    this.syncError,
  });
}
