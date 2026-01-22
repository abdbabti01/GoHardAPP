import 'package:isar/isar.dart';

part 'local_program.g.dart';

/// Local database model for workout programs with offline sync support
@collection
class LocalProgram {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original Program Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// User ID who owns this program
  @Index()
  int userId;

  /// Program title
  String title;

  /// Program description
  String? description;

  /// Associated goal ID
  int? goalId;

  /// Total weeks in the program
  int totalWeeks;

  /// Current week number (user's progress)
  int currentWeek;

  /// Current day number (user's progress)
  int currentDay;

  /// Program start date
  @Index()
  DateTime startDate;

  /// Program end date
  DateTime? endDate;

  /// Whether program is currently active
  @Index()
  bool isActive;

  /// Whether program is completed
  bool isCompleted;

  /// Timestamp when program was completed
  DateTime? completedAt;

  /// Timestamp when program was created
  DateTime createdAt;

  /// Program structure (JSON string)
  String? programStructure;

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
  LocalProgram({
    this.serverId,
    required this.userId,
    required this.title,
    this.description,
    this.goalId,
    required this.totalWeeks,
    required this.currentWeek,
    required this.currentDay,
    required this.startDate,
    this.endDate,
    this.isActive = true,
    this.isCompleted = false,
    this.completedAt,
    required this.createdAt,
    this.programStructure,
    this.isSynced = false,
    this.syncStatus = 'pending_create',
    required this.lastModifiedLocal,
    this.lastModifiedServer,
    this.syncRetryCount = 0,
    this.lastSyncAttempt,
    this.syncError,
  });
}
