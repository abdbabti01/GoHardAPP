import 'package:isar/isar.dart';

part 'local_run_session.g.dart';

/// Embedded GPS point for Isar storage
@embedded
class LocalGpsPoint {
  double latitude = 0;
  double longitude = 0;
  double? altitude;
  DateTime? timestamp;
  double? speed;
  double? accuracy;

  LocalGpsPoint();

  LocalGpsPoint.create({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.timestamp,
    this.speed,
    this.accuracy,
  });
}

/// Local database model for running sessions with offline sync support
@collection
class LocalRunSession {
  /// Local database ID (auto-increment)
  Id localId = Isar.autoIncrement;

  // ========== Original RunSession Fields ==========

  /// Server-side ID (null if not synced yet)
  int? serverId;

  /// User ID who owns this session
  int userId = 0;

  /// Name of the run (optional)
  String? name;

  /// Date of the run
  @Index()
  DateTime date = DateTime.now();

  /// Distance in kilometers
  double? distance;

  /// Duration in seconds
  int? duration;

  /// Average pace in min/km
  double? averagePace;

  /// Estimated calories burned
  int? calories;

  /// Session status: 'draft', 'in_progress', 'completed'
  @Index()
  String status = 'draft';

  /// Timestamp when run was started (UTC)
  DateTime? startedAt;

  /// Timestamp when run was completed (UTC)
  DateTime? completedAt;

  /// Timestamp when timer was paused (UTC)
  DateTime? pausedAt;

  /// GPS route points
  List<LocalGpsPoint> route = [];

  // ========== Sync Tracking Fields ==========

  /// Whether entity is in sync with server
  @Index()
  bool isSynced = false;

  /// Current sync status
  @Index()
  String syncStatus = 'pending_create'; // 'synced', 'pending_create', 'pending_update', 'pending_delete'

  /// Timestamp of last local modification
  DateTime lastModifiedLocal = DateTime.now();

  /// Timestamp of last server modification (from API response)
  DateTime? lastModifiedServer;

  /// Number of failed sync attempts
  int syncRetryCount = 0;

  /// Timestamp of last sync attempt
  DateTime? lastSyncAttempt;

  /// Error message from last failed sync
  String? syncError;

  /// Constructor
  LocalRunSession();

  /// Named constructor with parameters
  LocalRunSession.create({
    this.serverId,
    required this.userId,
    this.name,
    required this.date,
    this.distance,
    this.duration,
    this.averagePace,
    this.calories,
    this.status = 'draft',
    this.startedAt,
    this.completedAt,
    this.pausedAt,
    this.route = const [],
    this.isSynced = false,
    this.syncStatus = 'pending_create',
    required this.lastModifiedLocal,
    this.lastModifiedServer,
    this.syncRetryCount = 0,
    this.lastSyncAttempt,
    this.syncError,
  });
}
