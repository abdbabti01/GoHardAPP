import 'package:isar/isar.dart';

part 'legacy_local_session.g.dart';

/// TEST-ONLY fixture: a byte-for-byte copy of the `LocalSession` collection
/// exactly as it was committed at this branch's base commit (`884f164`,
/// `HEAD` at the time this fixture was written), BEFORE the
/// `clientOperationId` field existed. This is never imported by production
/// code - its sole purpose is to let a test write real, on-disk Isar data
/// using the OLD generated schema, then reopen that same on-disk database
/// with the CURRENT production schema (`lib/data/local/models/local_session.dart`,
/// imported side-by-side under a different prefix) to prove the additive
/// schema change opens and reads old data safely.
///
/// The class name is deliberately `LocalSession` (matching production) so
/// Isar's collection identity (derived from the collection NAME, hashed -
/// see `CollectionSchema.id` in the generated file) is the SAME collection
/// as production's `LocalSession` - this is what makes cross-schema-version
/// opening of the SAME on-disk directory possible without ever touching or
/// renaming the real production model.
///
/// Do NOT update this file when `local_session.dart` changes again - it must
/// stay frozen at the pre-`clientOperationId` shape to keep testing the
/// specific upgrade this fixture exists for.
@collection
class LocalSession {
  Id localId = Isar.autoIncrement;

  int? serverId;

  int userId;

  @Index()
  DateTime date;

  int? duration;

  String? notes;

  String? type;

  String? name;

  @Index()
  String status;

  DateTime? startedAt;

  DateTime? completedAt;

  DateTime? pausedAt;

  int? programId;

  int? programWorkoutId;

  @Index()
  bool isSynced;

  @Index()
  String syncStatus;

  DateTime lastModifiedLocal;

  DateTime? lastModifiedServer;

  int syncRetryCount;

  DateTime? lastSyncAttempt;

  String? syncError;

  int? version;

  String? conflictServerSnapshotJson;

  int? conflictServerVersion;

  DateTime? conflictDetectedAt;

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
  });
}
