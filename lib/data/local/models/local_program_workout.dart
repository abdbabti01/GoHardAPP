import 'package:isar/isar.dart';

part 'local_program_workout.g.dart';

/// Local database model for program workouts with offline sync support
@collection
class LocalProgramWorkout {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original ProgramWorkout Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// Local ID of parent program
  int programLocalId;

  /// Server ID of parent program (null if parent not synced)
  int? programServerId;

  /// Week number within the program
  @Index()
  int weekNumber;

  /// Day number within the week (1-7)
  int dayNumber;

  /// Custom day name
  String? dayName;

  /// Workout name/title
  String workoutName;

  /// Type of workout (e.g., 'strength', 'cardio', 'rest')
  String? workoutType;

  /// Workout description
  String? description;

  /// Estimated duration in minutes
  int? estimatedDuration;

  /// JSON string containing exercise details
  String exercisesJson;

  /// Warm-up instructions
  String? warmUp;

  /// Cool-down instructions
  String? coolDown;

  /// Whether workout is completed
  bool isCompleted;

  /// Timestamp when workout was completed
  DateTime? completedAt;

  /// Notes from completion
  String? completionNotes;

  /// Order index for sorting
  int orderIndex;

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
  LocalProgramWorkout({
    this.serverId,
    required this.programLocalId,
    this.programServerId,
    required this.weekNumber,
    required this.dayNumber,
    this.dayName,
    required this.workoutName,
    this.workoutType,
    this.description,
    this.estimatedDuration,
    required this.exercisesJson,
    this.warmUp,
    this.coolDown,
    this.isCompleted = false,
    this.completedAt,
    this.completionNotes,
    required this.orderIndex,
    this.isSynced = false,
    this.syncStatus = 'pending_create',
    required this.lastModifiedLocal,
    this.lastModifiedServer,
    this.syncRetryCount = 0,
    this.lastSyncAttempt,
    this.syncError,
  });
}
