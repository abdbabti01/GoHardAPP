import 'package:isar/isar.dart';

part 'legacy_local_exercise.g.dart';

/// TEST-ONLY fixture: a byte-for-byte copy of the `LocalExercise` collection
/// exactly as it was committed at this branch's base commit (`152243e`,
/// `HEAD` at the time this fixture was written), BEFORE the `occurrenceKey`
/// field existed. This is never imported by production code - its sole
/// purpose is to let a test write real, on-disk Isar data using the OLD
/// generated schema, then reopen that same on-disk database with the CURRENT
/// production schema (`lib/data/local/models/local_exercise.dart`, imported
/// side-by-side under a different prefix) to prove the additive schema
/// change opens and reads old data safely, INCLUDING child `LocalExerciseSet`
/// rows that were never part of this schema change and are opened under
/// their own unmodified current schema throughout.
///
/// The class name is deliberately `LocalExercise` (matching production) so
/// Isar's collection identity (derived from the collection NAME, hashed -
/// see `CollectionSchema.id` in the generated file) is the SAME collection
/// as production's `LocalExercise` - this is what makes cross-schema-version
/// opening of the SAME on-disk directory possible without ever touching or
/// renaming the real production model.
///
/// Do NOT update this file when `local_exercise.dart` changes again - it
/// must stay frozen at the pre-`occurrenceKey` shape to keep testing the
/// specific upgrade this fixture exists for.
@collection
class LocalExercise {
  Id localId = Isar.autoIncrement;

  int? serverId;

  int sessionLocalId;

  int? sessionServerId;

  String name;

  int sortOrder;

  int? duration;

  int? restTime;

  String? notes;

  int? exerciseTemplateId;

  @Index()
  bool isSynced;

  @Index()
  String syncStatus;

  DateTime lastModifiedLocal;

  DateTime? lastModifiedServer;

  int syncRetryCount;

  DateTime? lastSyncAttempt;

  String? syncError;

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
    this.isSynced = false,
    this.syncStatus = 'pending_create',
    required this.lastModifiedLocal,
    this.lastModifiedServer,
    this.syncRetryCount = 0,
    this.lastSyncAttempt,
    this.syncError,
  });
}
