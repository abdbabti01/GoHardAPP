import 'package:isar/isar.dart';

part 'local_exercise.g.dart';

/// Local database model for exercises within a workout session
@collection
class LocalExercise {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original Exercise Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// Local ID of parent session
  int sessionLocalId;

  /// Server ID of parent session (for sync reference)
  int? sessionServerId;

  /// Exercise name
  String name;

  /// Display order within session (0-indexed, for drag-and-drop reordering)
  int sortOrder;

  /// Duration in seconds
  int? duration;

  /// Rest time between sets in seconds
  int? restTime;

  /// User notes about this exercise
  String? notes;

  /// Reference to exercise template ID
  int? exerciseTemplateId;

  /// Persistent occurrence identity, copied verbatim from the source
  /// program-workout template entry / the server's CREATE response (see
  /// `Exercise.occurrenceKey`'s doc comment on the API model - this field
  /// mirrors it exactly). Identifies a specific exercise OCCURRENCE within
  /// one `ProgramWorkout`, never the exercise type ([exerciseTemplateId]
  /// does that), and never globally unique across Sessions or users - see
  /// `SessionRepository`'s doc comment section on program-workout
  /// exercise-occurrence identity for the full matching contract this field
  /// exists to support. `null` for an ad-hoc exercise, or a program-workout
  /// exercise whose local placeholder was materialized from a cached
  /// template that predates this field (see the SAME doc comment section
  /// for how that legacy case is handled - never guessed, never backfilled
  /// from another field).
  @Index()
  String? occurrenceKey;

  // ========== Sync Tracking Fields ==========

  /// Whether entity is in sync with server
  @Index()
  bool isSynced;

  /// Current sync status
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
  LocalExercise({
    this.serverId,
    required this.sessionLocalId,
    this.sessionServerId,
    required this.name,
    this.sortOrder = 0,
    this.duration,
    this.restTime,
    this.notes,
    this.exerciseTemplateId,
    this.occurrenceKey,
    this.isSynced = false,
    this.syncStatus = 'pending_create',
    required this.lastModifiedLocal,
    this.lastModifiedServer,
    this.syncRetryCount = 0,
    this.lastSyncAttempt,
    this.syncError,
  });
}
