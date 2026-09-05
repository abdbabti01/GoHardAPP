import 'package:isar/isar.dart';

part 'local_session.g.dart';

/// Local database model for workout sessions with offline sync support
@collection
class LocalSession {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original Session Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// User ID who owns this session
  int userId;

  /// Date of the workout session
  @Index()
  DateTime date;

  /// Duration of the workout in seconds
  int? duration;

  /// User notes about the workout
  String? notes;

  /// Type of workout (e.g., 'strength', 'cardio')
  String? type;

  /// Custom workout name (e.g., 'Pull Day', 'Leg Day')
  String? name;

  /// Session status: 'draft', 'in_progress', 'completed'
  @Index()
  String status;

  /// Timestamp when workout was started (UTC)
  DateTime? startedAt;

  /// Timestamp when workout was completed (UTC)
  DateTime? completedAt;

  /// Timestamp when timer was paused (UTC)
  DateTime? pausedAt;

  /// Program ID if this session is from a program
  int? programId;

  /// Program Workout ID if this session is from a program workout
  int? programWorkoutId;

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

  // ========== Version / Conflict Tracking Fields ==========

  /// Server-side optimistic concurrency version. Null for rows created
  /// before version tracking existed, or before their first successful
  /// sync - never guess this value when sending an update to the server.
  int? version;

  /// Serialized server session snapshot captured when a 409 conflict (or a
  /// version-unknown reconciliation) is detected. Local mutable fields are
  /// left untouched while this is set; it exists for later manual
  /// resolution (Mine / Use Server), not automatic overwrite.
  String? conflictServerSnapshotJson;

  /// The server's version number at the time [conflictServerSnapshotJson]
  /// was captured.
  int? conflictServerVersion;

  /// When the conflict represented by [conflictServerSnapshotJson] was
  /// detected.
  DateTime? conflictDetectedAt;

  // ========== Generic-CREATE operation identity ==========

  /// Durable client-generated idempotency key for a GENERIC Session CREATE
  /// (`POST /api/v1/sessions`), paired with the deployed GoHardAPI
  /// `(userId, clientOperationId)` contract. Exactly one UUID v4 is
  /// generated and persisted per logical CREATE, before the first HTTP
  /// dispatch whose outcome could be uncertain, so a lost or retried
  /// acknowledgment replays the same server-side operation instead of
  /// creating a duplicate Session.
  ///
  /// `null` for legacy rows created before this field existed, and for
  /// every row produced by `POST /sessions/from-program-workout` (that
  /// endpoint does not accept this key - see
  /// `SessionRepository.createSessionFromProgramWorkout`). A row that falls
  /// back to a generic `pending_create` write is backfilled with a key on
  /// its first generic retry (`SyncService`), not here.
  ///
  /// Never derived from `localId`, `serverId`, `Session.id`, `userId`,
  /// timestamps, or any mutable workout field. Never read from server JSON
  /// - the API never echoes this value back. Never rotated once non-null.
  /// Retained after a successful sync.
  ///
  /// Rollback caveat: a row keyed by a build with this field, then acted on
  /// by a build DOWNGRADED to before this field existed, is invisible to
  /// that older build's request-body construction - its retry of the same
  /// logical CREATE goes out unkeyed, reverting to the pre-idempotency
  /// contract for that one row (and can duplicate a Session if the original
  /// keyed POST already committed). This is an inherent limitation of a
  /// client-only idempotency key, not something a later client-side change
  /// can fully close - avoid downgrading past this field's introduction
  /// while any row created under it is still unsynced.
  String? clientOperationId;

  /// Constructor
  LocalSession({
    this.serverId,
    required this.userId,
    required this.date,
    this.duration,
    this.notes,
    this.type,
    this.name,
    this.status = 'draft',
    this.startedAt,
    this.completedAt,
    this.pausedAt,
    this.programId,
    this.programWorkoutId,
    this.isSynced = false,
    this.syncStatus = 'pending_create',
    required this.lastModifiedLocal,
    this.lastModifiedServer,
    this.syncRetryCount = 0,
    this.lastSyncAttempt,
    this.syncError,
    this.version,
    this.conflictServerSnapshotJson,
    this.conflictServerVersion,
    this.conflictDetectedAt,
    this.clientOperationId,
  });
}
