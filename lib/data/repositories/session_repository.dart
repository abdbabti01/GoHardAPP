import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/session.dart';
import '../models/exercise.dart';
import 'session_sync_diagnostics.dart';
import '../models/program_workout.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_create_error.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';
import '../services/session_update_sync_helper.dart';
import '../local/services/local_database_service.dart';
import '../local/services/model_mapper.dart';
import '../local/models/local_session.dart';
import '../local/models/local_exercise.dart';
import '../local/models/local_exercise_set.dart';
import '../local/models/local_exercise_template.dart';

/// Repository for session (workout) operations with offline support.
///
/// ## Session/ownership model
///
/// Every public asynchronous operation below that touches authenticated
/// session data captures a [SessionRequestContext] via
/// [_sessionCoordinator] at operation entry (never after an internal
/// `await`), and uses `context.epochToken.userId` as the sole authoritative
/// user for the remainder of that operation - never a later, independently
/// re-read user ID. A `null` capture (logged out, or the session changed
/// while the JWT read was in flight) is treated exactly like today's
/// existing unauthenticated/not-found convention: no Isar mutation, no HTTP.
///
/// Every [ApiService] call this repository makes - foreground (awaited
/// inline) or background (fire-and-forget) - is bound to that captured
/// context, so it carries the pinned JWT captured at entry rather than
/// whatever the live token happens to be, and can never be dispatched after
/// the session that started it has ended (see [ApiService]'s own class doc
/// comment). Every detached/background push schedules
/// [SessionRequestCoordinator.captureContext] (or reuses the context already
/// captured at entry) SYNCHRONOUSLY, before any later callback, so the
/// background closure is always bound to the session that scheduled it, not
/// whichever session happens to be active when it finally runs.
///
/// ## Local ID ownership
///
/// Every public ID (`serverId ?? localId`, see `ModelMapper.localToSession`)
/// is resolved through [_resolveOwnedSession]/[_resolveOwnedSessionOrThrow]:
/// the server-ID interpretation is tried first, but only a match owned by
/// the captured user is accepted - a foreign server-ID match (same numeric
/// ID, different owner) never blocks falling through to the local-ID
/// interpretation, since server IDs and Isar auto-increment local IDs are
/// independent sequences that can collide on the same number. A foreign or
/// missing target always follows the existing not-found convention
/// (`Exception('Session not found: $id')`) without revealing whether a
/// foreign row exists.
///
/// ## Session graph ownership
///
/// [LocalExercise] is owned transitively through `sessionLocalId ->
/// LocalSession.userId`, and [LocalExerciseSet] through `exerciseLocalId ->
/// LocalExercise.sessionLocalId -> LocalSession.userId`. A background cache
/// refresh only ever writes/deletes child rows for a [LocalSession] it has
/// independently re-validated as owned by the captured user - never a
/// replacement or foreign session's children.
///
/// ## Transaction/logout race protection
///
/// Every mutation/cache acknowledgment below rechecks
/// [UserSessionEpoch.isCurrent] immediately after every awaited HTTP/local
/// lookup, immediately before entering its `writeTxn`, and again as the
/// FIRST statement inside that `writeTxn` - the three-checkpoint shape that
/// guarantees a session ending anywhere in that window (including while
/// Isar's write lock is being awaited) never lets a stale acknowledgment
/// resurrect or overwrite a since-replaced row. Neither explicit logout nor
/// forced expiration calls `LocalDatabaseService.clearAll()` (both are
/// non-destructive; see `AuthProvider._runTerminationPass`), but this
/// checkpoint shape remains correct defense-in-depth even if a future
/// genuinely destructive operation ever did. See the
/// `beforeWriteTxnForTesting` / `insideWriteTxnForTesting` /
/// `afterWriteTxnForTesting` and background-flavored equivalents below for
/// how this is exercised deterministically in tests.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures: they are
/// logged as neither a success nor an error, never surfaced to the user,
/// and never treated as grounds to mark a row permanently failed or
/// increment a retry counter. Every other exception preserves this
/// repository's existing "log and continue, retry later" behavior.
///
/// ## Program-workout exercise-occurrence identity
///
/// GoHardAPI's persistent occurrence-identity contract is deployed and live
/// (`GoHardAPI.Models.Exercise.OccurrenceKey`, backed by
/// `ProgramWorkoutExerciseOccurrences`/`ProgramWorkoutSessionMaterializer` -
/// see their class doc comments on the deployed side). This section
/// documents how this repository consumes it; it previously documented a
/// design PROPOSAL for a feature that has since shipped.
///
/// **What `occurrenceKey` identifies.** One exercise OCCURRENCE within a
/// single `ProgramWorkout.ExercisesJson` array - never the exercise TYPE
/// (`exerciseTemplateId` still means that), and never globally unique: the
/// SAME key legitimately repeats across every Exercise materialized from the
/// same `ProgramWorkout` into DIFFERENT Sessions (two intentional starts of
/// the same workout both get Exercises keyed identically to their shared
/// source template). Uniqueness is enforced only WITHIN one workout array.
///
/// **Where it comes from, client-side.** [createSessionFromProgramWorkout]
/// reads `occurrenceKey` directly off each parsed `exercisesData` map (the
/// SAME cached `ProgramWorkout.exercisesJson` this method already reads
/// `name`/`exerciseTemplateId`/`notes`/`rest` from) and persists it verbatim
/// on the local placeholder - never invented, never derived from anything
/// else. A template CACHED before this field existed (or not refreshed
/// since) simply has no key on some or all entries yet; every server
/// read path that returns a `ProgramWorkout` (program/workout GETs) now
/// self-heals this server-side (`ProgramWorkoutExerciseOccurrences
/// .EnsurePersistedAsync`), so this client's OWN next routine program/
/// workout refresh backfills real keys with zero client-side protocol
/// change - `ProgramWorkout.exercisesJson` is an opaque, already-generic
/// JSON blob on both the Isar (`LocalProgramWorkout.exercisesJson`) and API
/// (`ProgramWorkout.exercises` getter, parsed as raw `Map<String,dynamic>`)
/// sides, so the field rides through existing plumbing with no model change
/// there. A placeholder still materialized with no key (a genuinely stale
/// cache, or an ad-hoc exercise with no program-workout source at all) is
/// never matched by guessing - see the matching rule below.
///
/// **Where it comes from, server-side.** Every Exercise materialized
/// through the KEYED `POST /sessions/from-program-workout` path carries a
/// real, non-null `occurrenceKey`: `SessionCreateService
/// .ProgramWorkoutFirstWriteAsync` calls `EnsurePersistedAsync` on the
/// source workout BEFORE `ProgramWorkoutSessionMaterializer.Build` runs, so
/// even a source template that itself still lacks keys gets stable,
/// self-healed ones at materialization time (verified against the deployed
/// contract's own test,
/// `SessionCreateFromProgramWorkoutOccurrenceKeyTests
/// .KeyedCreate_SourceWorkoutMissingKeys_StillGetsStableKeysOnEachExercise`).
/// A keyed REPLAY never re-reads the source workout at all (existing
/// first-writer-wins contract, unchanged), so it always returns the SAME
/// Exercises with the SAME keys the original accepted write assigned -
/// confirmed by the deployed contract's own
/// `Replay_AfterSourceWorkoutEdited_StillReturnsTheOriginalSessionsOriginalKeys`
/// test. `occurrenceKey` is a normal persisted column, so it is naturally
/// present on every `GET /sessions/{id}`/`GET /sessions` response too
/// (raw-entity serialization, unchanged) and survives a server or this
/// client's own app restart with no special handling - nothing about this
/// class's durable-retry design (dispatch-before-persistence, retry after
/// restart, `dispatchedAt` comparisons) needed to change to keep it correct.
///
/// **Matching rule.** [_reconcileProgramWorkoutCreateExercises] delegates to
/// [ModelMapper.pairProgramWorkoutCreateExercises] - see its doc comment for
/// the full one-to-one-by-`occurrenceKey` contract, including why `null`
/// never establishes identity and why a duplicate/invalid response identity
/// is treated as a contract error (never partially assigned) rather than a
/// crash. The SAME matching contract is used by
/// [_syncCreateSessionFromProgramWorkoutToServer] (this class),
/// `SyncService._syncCreateSessionFromProgramWorkout` (its independent
/// twin), and now also by ordinary Session/Exercise refresh
/// ([_resolveExistingExerciseForRefresh], used by both [getSession] and
/// [_syncSessionsFromServer]): a later GET can now recognize an occurrence
/// already represented locally (e.g. a still-`conflict`-marked ambiguous
/// row, or a plain unsynced program-workout placeholder) by `occurrenceKey`
/// instead of only by `serverId`, closing the "a subsequent refresh inserts
/// a duplicate row" gap a prior round of this branch explicitly disclosed as
/// unresolved.
///
/// **Legacy/unresolved cases.** A local exercise that cannot be safely
/// matched (no key at all, or a key with no unique server counterpart - the
/// occurrence was removed/replaced before materialization) is marked
/// `syncStatus: 'conflict'` (see [_reconcileProgramWorkoutCreateExercises]) -
/// never guessed, never silently discarded, its `LocalExerciseSet` children
/// always preserved under its stable `localId`. This is a genuine, disclosed
/// limitation, not a defect: without a key, there is no data-safe way to
/// attach a server identity, and this codebase has no exercise-level
/// equivalent of the Session conflict-resolution UI yet (the `'conflict'`
/// status value is borrowed from that existing, Session-level concept - see
/// `SessionSyncDiagnostics` - precisely so a future UI has something to
/// surface it against).
class SessionRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;
  // Kept for constructor-shape consistency with every other repository's
  // ProxyProvider4<ApiService, LocalDatabaseService, ConnectivityService,
  // AuthService, ...> wiring in main.dart. No longer read directly - every
  // userId lookup this repository needs now comes from the captured
  // SessionRequestContext/UserSessionToken instead, per the class doc
  // comment above.
  // ignore: unused_field
  final AuthService _authService;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// every other Provider/repository that needs it (see main.dart). Only
  /// AuthProvider ever calls activate()/invalidate() on it; this repository
  /// only ever reads it via capture()/isCurrent().
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext]
  /// (pinned JWT + generation-scoped CancelToken) for every session-bound
  /// HTTP call this repository makes. The SAME instance handed to every
  /// other consumer (see main.dart); never constructed privately.
  final SessionRequestCoordinator _sessionCoordinator;

  SessionRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._authService,
    this._sessionEpoch,
    this._sessionCoordinator,
  );

  static const String _unauthenticated = 'User not authenticated';

  /// Canonical UUID v4 text for a new generic-CREATE operation key. `uuid`'s
  /// `Uuid.v4()` defaults to `CryptoRNG` (`Random.secure()` under the hood -
  /// verified against the installed package source), so no explicit RNG
  /// configuration is needed.
  static const Uuid _uuid = Uuid();

  /// Test-only override for operation-key generation - lets a deterministic
  /// test assert on a KNOWN value instead of a random one. `null` in
  /// production and in every test that doesn't explicitly set it.
  @visibleForTesting
  String Function()? operationIdGeneratorForTesting;

  String _generateOperationId() =>
      (operationIdGeneratorForTesting ?? _uuid.v4)();

  // ============ Test-only session-race seams ============
  //
  // One hook per checkpoint, mirroring NutritionRepository's identical
  // seams. Each is @visibleForTesting, defaults to null, and is never
  // assigned outside test code - production control flow/performance are
  // unaffected.
  @visibleForTesting
  Future<void> Function()? beforeWriteTxnForTesting;

  @visibleForTesting
  Future<void> Function()? insideWriteTxnForTesting;

  @visibleForTesting
  Future<void> Function()? afterWriteTxnForTesting;

  @visibleForTesting
  Future<void> Function()? beforeBackgroundHttpDispatchForTesting;

  @visibleForTesting
  Future<void> Function()? afterBackgroundHttpResponseForTesting;

  @visibleForTesting
  Future<void> Function()? insideBackgroundWriteTxnForTesting;

  /// Fires immediately before each child (Exercise/ExerciseSet) delete
  /// inside [_deleteSessionAndRelatedData]'s transaction, after the
  /// exercises have already been queried - lets a test land a parent
  /// reassignment exactly in the window the grandparent-ownership recheck
  /// below is meant to close.
  @visibleForTesting
  Future<void> Function()? beforeChildDeleteForTesting;

  Future<void> _runTestHook(Future<void> Function()? hook) async {
    if (hook != null) {
      await hook();
    }
  }

  // ============ Session/ownership helpers ============

  /// Resolves a [LocalSession] identified ambiguously by [id] (server ID or
  /// local Isar ID) to a row owned by [token.userId], or `null` if neither
  /// interpretation yields an owned row. See the class doc comment's "Local
  /// ID ownership" section.
  Future<LocalSession?> _resolveOwnedSession(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final byServerId =
        await db.localSessions
            .filter()
            .serverIdEqualTo(id)
            .userIdEqualTo(token.userId)
            .findFirst();
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byServerId != null) return byServerId;

    final byLocalId = await db.localSessions.get(id);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (byLocalId != null && byLocalId.userId == token.userId) {
      return byLocalId;
    }

    return null;
  }

  /// Same as [_resolveOwnedSession], but throws the existing not-found
  /// convention when no owned row exists.
  Future<LocalSession> _resolveOwnedSessionOrThrow(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final session = await _resolveOwnedSession(db, id, token);
    if (session == null) {
      throw Exception('Session not found: $id');
    }
    return session;
  }

  /// Re-resolves [localId] by its STABLE local identity and verifies direct
  /// ownership against [token.userId]. Used by every background
  /// acknowledgment to confirm the row it is about to write to still
  /// belongs to the session that started the operation, rather than
  /// trusting a captured reference that may since have been replaced.
  Future<LocalSession?> _ownedSessionByLocalId(
    Isar db,
    int localId,
    UserSessionToken token,
  ) async {
    final row = await db.localSessions.get(localId);
    if (!_sessionEpoch.isCurrent(token)) return null;
    if (row == null || row.userId != token.userId) return null;
    return row;
  }

  /// True if [sessionLocalId] resolves to a [LocalSession] owned by
  /// [token.userId]. False (never throws) for a missing/orphaned parent, so
  /// an orphaned exercise is treated the same as a foreign one - never
  /// mutated.
  Future<bool> _isSessionOwnedByLocalId(
    Isar db,
    int sessionLocalId,
    UserSessionToken token,
  ) async {
    final parent = await db.localSessions.get(sessionLocalId);
    if (!_sessionEpoch.isCurrent(token)) return false;
    return parent != null && parent.userId == token.userId;
  }

  // ============ Generic helpers ============

  /// Load exercises for a session from local database
  Future<List<Exercise>> _loadExercisesForSession(
    Isar db,
    int sessionLocalId,
  ) async {
    final localExercises =
        await db.localExercises
            .filter()
            .sessionLocalIdEqualTo(sessionLocalId)
            .findAll();

    return localExercises
        .map((localEx) => ModelMapper.localToExercise(localEx))
        .toList();
  }

  /// Convert a LocalSession to Session with exercises loaded
  Future<Session> _localSessionToSessionWithExercises(
    Isar db,
    LocalSession localSession,
  ) async {
    final exercises = await _loadExercisesForSession(db, localSession.localId);
    return ModelMapper.localToSession(localSession, exercises: exercises);
  }

  /// Fired synchronously, exactly once per [_backgroundSync] call, with the
  /// Future that completes once THAT SPECIFIC detached operation has fully
  /// settled - after its HTTP dispatch, its success/error handling, and any
  /// acknowledgment writeTxn or guarded stale/cancelled exit inside
  /// [operation] have all finished (it never rejects: the same
  /// success/error handling [_backgroundSync] always applies runs first,
  /// so this always completes, never throws). Tests use it to await
  /// deterministic completion of detached work instead of guessing with a
  /// delay - see `session_repository_session_ownership_test.dart`.
  ///
  /// Each call passes its OWN distinct Future, so a test scheduling
  /// multiple overlapping background operations (e.g. two repository calls
  /// in quick succession) can tell them apart by call order rather than
  /// awaiting the wrong one. Defaults to null in production - a pure
  /// no-op that does not change scheduling, timing, or error handling.
  @visibleForTesting
  void Function(Future<void> operationSettled)?
  onBackgroundSyncScheduledForTesting;

  /// Schedules [operation] to run detached from the caller. [operation]
  /// must already be bound to a captured [SessionRequestContext]/
  /// [UserSessionToken] - this helper only handles the fire-and-forget
  /// execution and expected-lifecycle-outcome classification, exactly like
  /// NutritionRepository's identical helper.
  ///
  /// [SessionStaleException] and [RequestCancelledException] are logged as
  /// neither a success nor a failure - never surfaced as a user-visible
  /// error, never grounds to mark anything permanently failed. Every other
  /// exception preserves this repository's original "log and continue"
  /// behavior.
  void _backgroundSync(
    Future<void> Function() operation,
    String successMessage,
  ) {
    final settled = operation()
        .then((_) {
          debugPrint('✅ Background sync: $successMessage');
        })
        .catchError((e) {
          if (e is SessionStaleException || e is RequestCancelledException) {
            debugPrint(
              'ℹ️ Background sync skipped (session ended): $successMessage',
            );
            return;
          }
          debugPrint('⚠️ Background sync failed, will retry later: $e');
        });
    onBackgroundSyncScheduledForTesting?.call(settled);
  }

  /// Wraps a single background HTTP call with the before-dispatch test seam.
  /// Staleness AT dispatch time is already enforced by [ApiService] itself
  /// via the bound [SessionRequestContext.epochToken].
  Future<T> _dispatchBackgroundHttp<T>(Future<T> Function() call) async {
    await _runTestHook(beforeBackgroundHttpDispatchForTesting);
    return call();
  }

  /// True while [localSession] has an unresolved 409 conflict recorded
  /// (see SessionUpdateSyncHelper). Only an explicit Keep Mine / Use Server
  /// resolution - not implemented yet - may leave this state; a routine
  /// local edit must never flip it back to pending_update, clear its
  /// conflict metadata, or queue it for a background PUT.
  bool _isConflicted(LocalSession localSession) =>
      localSession.syncStatus == 'conflict';

  /// Apply the standard local-edit sync-tracking bookkeeping
  /// (lastModifiedLocal / isSynced / syncStatus) to [localSession],
  /// preserving the conflict invariant above. Field-specific edits (name,
  /// date, status, timestamps, ...) are applied by the caller - this only
  /// manages the fields every edit path shares. [newStatus], if given, is
  /// applied even for a conflicted row, since a workout status change is
  /// itself a local mutable-field edit ("mine"), not a sync-status change.
  void _applyLocalEditBookkeeping(
    LocalSession localSession, {
    String? newStatus,
  }) {
    if (newStatus != null) {
      localSession.status = newStatus;
    }
    localSession.lastModifiedLocal = DateTime.now().toUtc();

    if (_isConflicted(localSession)) {
      // Conflict state and its metadata are intentionally left untouched.
      return;
    }

    localSession.isSynced = false;
    if (localSession.serverId != null) {
      localSession.syncStatus = 'pending_update';
    }
  }

  /// Whether a local edit to [localSession] should trigger an immediate
  /// background push to the server. Conflicted rows are excluded - they
  /// may only be resolved through an explicit Keep Mine / Use Server
  /// operation, never by a routine edit or the periodic sync loop.
  bool _shouldPushAfterEdit(LocalSession localSession) =>
      !_isConflicted(localSession) &&
      _connectivity.isOnline &&
      localSession.serverId != null;

  /// Mark a local session as needing sync (pending_update if server ID
  /// exists). [token] is rechecked as the first statement inside the write
  /// transaction, per the class doc comment's transaction-race section.
  Future<void> _markSessionForSync(
    Isar db,
    LocalSession localSession,
    UserSessionToken token, {
    String? newStatus,
  }) async {
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      _applyLocalEditBookkeeping(localSession, newStatus: newStatus);
      await db.localSessions.put(localSession);
    });
  }

  /// Get all sessions for the current user
  /// Offline-first: returns local cache immediately, syncs with server in background
  /// Set [waitForSync] to true to wait for server sync before returning (useful after login)
  Future<List<Session>> getSessions({bool waitForSync = false}) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      debugPrint('⚠️ No authenticated session, returning empty list');
      return [];
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    // If waitForSync is true and we're online, sync first then return fresh data
    if (waitForSync && _connectivity.isOnline) {
      debugPrint('⏳ Waiting for server sync before returning sessions...');
      try {
        await _syncSessionsFromServer(db, context);
      } on SessionStaleException {
        // Expected lifecycle outcome.
      } on RequestCancelledException {
        // Expected lifecycle outcome.
      }
      if (!_sessionEpoch.isCurrent(token)) return [];
      final freshSessions = await _getLocalSessions(db, token);
      return freshSessions;
    }

    // Otherwise, use offline-first approach: load from cache first for instant response
    final cachedSessions = await _getLocalSessions(db, token);

    // Then sync with server in background if online (don't block). The
    // context captured above is handed straight into the closure, so this
    // detached refresh stays bound to the session that scheduled it even
    // if a different user logs in before it completes.
    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _syncSessionsFromServer(db, context),
        'Sessions synced from server',
      );
    }

    return cachedSessions;
  }

  /// Get all in-progress sessions for the current user
  /// Used to ensure only one workout is active at a time
  Future<List<Session>> getInProgressSessions() async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      debugPrint('⚠️ No authenticated session, returning empty list');
      return [];
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    // Get all in-progress sessions from local DB
    final localSessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(token.userId)
            .statusEqualTo('in_progress')
            .findAll();
    if (!_sessionEpoch.isCurrent(token)) return [];

    // Convert to Session models with exercises (using helper)
    final sessions = <Session>[];
    for (final localSession in localSessions) {
      sessions.add(await _localSessionToSessionWithExercises(db, localSession));
    }

    return sessions;
  }

  /// Background sync: Fetch sessions from server and update cache. Bound to
  /// [context]: the HTTP call carries its pinned JWT, and every cache write
  /// is gated behind the class doc comment's three-checkpoint shape plus a
  /// direct [LocalSession.userId] ownership check.
  ///
  /// ## Matching a not-yet-acknowledged CREATE by operation key
  ///
  /// The "skip - has pending local changes" branch below matches an
  /// existing local row by `serverId`. That alone is not enough for a
  /// `pending_delete` row still keyed by `clientOperationId` alone (its own
  /// CREATE's response was lost - see [deleteSession]'s doc comment): if the
  /// server-side CREATE actually committed, this refresh's response
  /// contains the Session under a `serverId` this client never learned, so
  /// a `serverId`-only match would miss it and insert a brand-new, visible,
  /// resurrected row for a Session the user already asked to delete.
  ///
  /// `GET /api/v1/sessions` (and `GET /api/v1/sessions/{id}`) serialize the
  /// raw server `Session` entity, which - unlike the sanitized
  /// `SessionResponseDto` returned by POST/PUT - DOES carry back
  /// `clientOperationId` (confirmed by reading `SessionsController`'s GET
  /// actions and the `Session` entity in the paired GoHardAPI source: no DTO
  /// wrapper, no `[JsonIgnore]`, a real mapped/persisted column). So before
  /// falling back to the `serverId`-only match, an `apiSession` with no
  /// matching local row is additionally checked against this user's
  /// `pending_delete` rows by the EXACT retained `clientOperationId` - never
  /// a title/date/`programWorkoutId` heuristic. A match means this
  /// `apiSession` IS the target of a local cancellation still in flight:
  /// skip inserting it (attaching the now-known `serverId` to the existing
  /// hidden row instead, exactly like the CREATE-acknowledgment
  /// `pending_delete` guard in `_syncCreateSessionToServer`), so the pending
  /// cancellation converges on the SAME row instead of a resurrected
  /// duplicate, and a later refresh's own cleanup pass below removes the
  /// server-side original once cancellation completes.
  ///
  /// This does not suppress or delay any OTHER Session - only an exact
  /// operation-key match short-circuits the insert; every unrelated
  /// server Session (including ones this user created on another device)
  /// is cached normally.
  ///
  /// ## Ordering: a response captured BEFORE cancellation commits,
  /// reconciled AFTER the local tombstone is already gone
  ///
  /// This GET and an independent `DELETE .../by-operation/{key}` share no
  /// ordering: the server can process the GET before the cancel commits
  /// (so the response body still lists the Session), while the CLIENT
  /// processes the cancel's OWN acknowledgment first (removing the local
  /// `pending_delete` row entirely) and only reconciles this slower GET
  /// response afterward. At that point there is no live local row left to
  /// match by `clientOperationId` at all - the operation-key match above,
  /// by itself, protects only WHILE the tombstone still exists.
  ///
  /// `pendingCancellationKeysBeforeDispatch` (below) closes this: a snapshot of
  /// this user's `pending_delete` operation keys taken immediately before
  /// the HTTP dispatch below - BEFORE the cancel could possibly have
  /// completed and removed the row this call is about to race against.
  /// Reconciliation additionally checks this snapshot, not just the live
  /// row: an apiSession whose key was already pending cancellation as of
  /// dispatch time is never inserted, whether or not its tombstone survived
  /// until the response came back. Purely a local, in-memory, per-call
  /// snapshot - no persisted state, no schema change, and it never
  /// suppresses a session whose key was NOT already pending cancellation
  /// at that moment.
  ///
  /// Resolves the LOCAL row a refresh ([_syncSessionsFromServer] or
  /// [getSession]) should reconcile [apiExercise] against, for the already-
  /// resolved-and-owned parent Session at [sessionLocalId]. First by
  /// `serverId` (the pre-existing, general contract for any already-synced
  /// exercise - unconditionally correct regardless of program-workout
  /// origin), then - only when that fails - by `occurrenceKey`, using the
  /// SAME one-to-one contract [ModelMapper.pairProgramWorkoutCreateExercises]
  /// uses for the CREATE acknowledgment itself: exactly one local exercise
  /// in this session sharing [apiExercise]'s `occurrenceKey`. This is what
  /// lets a refresh recognize an occurrence already represented locally
  /// (e.g. a still-`conflict`-marked ambiguous row, or an ordinary unsynced
  /// program-workout placeholder still awaiting its own CREATE
  /// acknowledgment) instead of inserting a duplicate for it. Returns `null`
  /// when neither resolves to a UNIQUE local row (no key, or more than one
  /// local exercise sharing it - never guessed) - the caller's existing
  /// "insert as new" fallback applies unchanged, exactly as it did before
  /// `occurrenceKey` existed.
  ///
  /// The `serverId` lookup below is intentionally NOT scoped to
  /// [sessionLocalId] (unlike the `occurrenceKey` fallback, which IS scoped
  /// to it) - it relies on the same "server exercise ids are globally
  /// unique" assumption this whole feature already depends on elsewhere
  /// ([ModelMapper.pairProgramWorkoutCreateExercises]'s own preliminary
  /// already-resolved-by-serverId pass makes the identical assumption). A
  /// positive `serverId` is only ever attached to a local row by this
  /// repository's own acknowledged writes, always under ownership checks at
  /// write time, so a stale/foreign match here is not expected to occur in
  /// practice - not a newly-introduced risk, but called out here since nothing
  /// enforces it structurally at this call site the way [sessionLocalId]
  /// scoping enforces it for the `occurrenceKey` fallback.
  Future<LocalExercise?> _resolveExistingExerciseForRefresh(
    Isar db,
    int sessionLocalId,
    Exercise apiExercise,
  ) async {
    final byServerId =
        await db.localExercises
            .filter()
            .serverIdEqualTo(apiExercise.id)
            .findFirst();
    if (byServerId != null) return byServerId;

    final key = apiExercise.occurrenceKey;
    if (key == null) return null;

    final byOccurrenceKey =
        await db.localExercises
            .filter()
            .sessionLocalIdEqualTo(sessionLocalId)
            .occurrenceKeyEqualTo(key)
            .findAll();
    return byOccurrenceKey.length == 1 ? byOccurrenceKey.single : null;
  }

  Future<void> _syncSessionsFromServer(
    Isar db,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    // Snapshot BEFORE dispatch - see the doc comment above.
    final pendingCancellationKeysBeforeDispatch = await db.localSessions
        .filter()
        .userIdEqualTo(token.userId)
        .syncStatusEqualTo('pending_delete')
        .findAll()
        .then(
          (rows) =>
              rows.map((r) => r.clientOperationId).whereType<String>().toSet(),
        );

    // Fetch from API
    final data = await _dispatchBackgroundHttp(
      () => _apiService.get<List<dynamic>>(
        ApiConfig.sessions,
        sessionContext: context,
      ),
    );

    debugPrint('📥 Received ${data.length} sessions from API');

    final apiSessions =
        data
            .map((json) => Session.fromJson(json as Map<String, dynamic>))
            .toList();

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final currentUserId = token.userId;

    // Checkpoint: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(token)) return;

    // Update local cache (sessions AND their exercises)
    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(token)) return;

      for (final apiSession in apiSessions) {
        // Only cache sessions belonging to current user
        if (apiSession.userId != currentUserId) {
          debugPrint(
            '  ⏭️ Skipping session ${apiSession.id} - belongs to different user (${apiSession.userId} != $currentUserId)',
          );
          continue;
        }

        // Check if session already exists locally
        final existingLocal =
            await db.localSessions
                .filter()
                .serverIdEqualTo(apiSession.id)
                .findFirst();

        // No serverId match - before treating this as a brand-new Session,
        // check whether it is the target of a LOCAL pending cancellation
        // this client never learned the serverId for (see this method's
        // doc comment). Matched by the EXACT retained operation key only.
        if (existingLocal == null && apiSession.clientOperationId != null) {
          final pendingCancellation =
              await db.localSessions
                  .filter()
                  .userIdEqualTo(currentUserId)
                  .syncStatusEqualTo('pending_delete')
                  .clientOperationIdEqualTo(apiSession.clientOperationId)
                  .findFirst();
          if (pendingCancellation != null) {
            if (pendingCancellation.serverId != apiSession.id) {
              pendingCancellation.serverId = apiSession.id;
              pendingCancellation.version = apiSession.version;
              await db.localSessions.put(pendingCancellation);
            }
            debugPrint(
              '  ⏭️ Skipping session ${apiSession.id} - matches a pending '
              'cancellation by operation key',
            );
            continue;
          }

          // The tombstone is already gone: cancellation completed (this
          // client's own acknowledgment already removed the row) WHILE this
          // GET was still in flight, so this response is a stale snapshot
          // captured before that. Never resurrect it - see this method's
          // doc comment's "Ordering" section.
          if (pendingCancellationKeysBeforeDispatch.contains(
            apiSession.clientOperationId,
          )) {
            debugPrint(
              '  ⏭️ Skipping session ${apiSession.id} - stale snapshot from '
              'before an already-completed cancellation',
            );
            continue;
          }
        }

        // Never overwrite a row that no longer belongs to the current
        // user - a serverId collision (or a foreign row somehow sharing
        // it) must never be silently claimed by this refresh.
        if (existingLocal != null && existingLocal.userId != currentUserId) {
          debugPrint(
            '  ⏭️ Skipping session ${apiSession.id} - local row owned by a different user',
          );
          continue;
        }

        // Skip sessions with pending local changes - don't overwrite with
        // server data. 'conflict' rows are included here: a background
        // cache refresh must never silently discard the local edit and
        // conflict metadata a 409 resolution still needs.
        if (existingLocal != null &&
            (existingLocal.syncStatus == 'pending_delete' ||
                existingLocal.syncStatus == 'pending_update' ||
                existingLocal.syncStatus == 'conflict')) {
          debugPrint(
            '  ⏭️ Skipping session ${apiSession.id} - has pending local changes (${existingLocal.syncStatus})',
          );
          continue;
        }

        // CRITICAL FIX: Never overwrite in-progress sessions from server!
        // This prevents the 5-hour timer bug caused by server returning incorrect timestamps.
        // Local state is authoritative for active workouts.
        if (existingLocal != null && existingLocal.status == 'in_progress') {
          debugPrint(
            '  ⏭️ Skipping session ${apiSession.id} - in_progress workout, keeping local timestamps',
          );
          continue;
        }

        LocalSession savedSession;
        if (existingLocal != null) {
          // Update existing local session
          final updated = ModelMapper.sessionToLocal(
            apiSession,
            localId: existingLocal.localId,
            isSynced: true,
            clientOperationId: existingLocal.clientOperationId,
          );
          await db.localSessions.put(updated);
          savedSession = updated;
        } else {
          // Create new local session
          final localSession = ModelMapper.sessionToLocal(apiSession);
          await db.localSessions.put(localSession);
          savedSession = localSession;
        }

        // Save exercises for this session
        int exerciseCount = 0;
        for (final apiExercise in apiSession.exercises) {
          final existingExercise = await _resolveExistingExerciseForRefresh(
            db,
            savedSession.localId,
            apiExercise,
          );

          if (existingExercise != null) {
            // Update existing
            final updated = ModelMapper.exerciseToLocal(
              apiExercise,
              sessionLocalId: savedSession.localId,
              localId: existingExercise.localId,
              isSynced: true,
            );
            await db.localExercises.put(updated);
          } else {
            // Create new
            final localExercise = ModelMapper.exerciseToLocal(
              apiExercise,
              sessionLocalId: savedSession.localId,
            );
            await db.localExercises.put(localExercise);
          }
          exerciseCount++;
        }
        debugPrint(
          '  📝 Cached $exerciseCount exercises for session ${apiSession.id}',
        );
      }

      // Remove sessions that were deleted on the server (cascade delete cleanup).
      // Already scoped to currentUserId, so this cannot touch another
      // user's rows.
      final serverSessionIds = apiSessions.map((s) => s.id).toSet();
      final allLocalSessions =
          await db.localSessions
              .filter()
              .userIdEqualTo(currentUserId)
              .serverIdIsNotNull()
              .findAll();

      for (final localSession in allLocalSessions) {
        if (!serverSessionIds.contains(localSession.serverId)) {
          debugPrint(
            '  🗑️ Removing session ${localSession.serverId} (deleted on server)',
          );

          final exercisesToDelete =
              await db.localExercises
                  .filter()
                  .sessionLocalIdEqualTo(localSession.localId)
                  .findAll();

          for (final exercise in exercisesToDelete) {
            await db.localExerciseSets
                .filter()
                .exerciseLocalIdEqualTo(exercise.localId)
                .deleteAll();
            await db.localExercises.delete(exercise.localId);
          }

          await db.localSessions.delete(localSession.localId);
        }
      }
    });

    debugPrint('✅ Synced ${apiSessions.length} sessions from server');
  }

  /// Get sessions from local database with exercises, scoped to [token].
  Future<List<Session>> _getLocalSessions(
    Isar db,
    UserSessionToken token,
  ) async {
    final localSessions =
        await db.localSessions.filter().userIdEqualTo(token.userId).findAll();
    if (!_sessionEpoch.isCurrent(token)) return [];

    // Convert to Session models, skipping deleted/archived (using helper)
    final sessions = <Session>[];
    for (final localSession in localSessions) {
      // Skip sessions marked for deletion or archived
      if (localSession.syncStatus == 'pending_delete' ||
          localSession.status == 'archived') {
        continue;
      }

      sessions.add(await _localSessionToSessionWithExercises(db, localSession));
    }

    return sessions;
  }

  /// Get session by ID
  /// Offline-first: returns local cache, then tries to sync with server
  Future<Session> getSession(int id) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    // Check if there's a local (owned) version with pending changes
    final localSession = await _resolveOwnedSession(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // If local session has pending changes, return it instead of fetching from server
    if (localSession != null && !localSession.isSynced) {
      debugPrint('📝 Session has pending changes, returning local version');
      return await _localSessionToSessionWithExercises(db, localSession);
    }

    // CRITICAL FIX: Always use local data for in-progress sessions!
    // This prevents the 5-hour timer bug caused by server returning incorrect timestamps.
    // Local timestamps are authoritative during active workouts.
    if (localSession != null && localSession.status == 'in_progress') {
      debugPrint(
        '🏋️ In-progress session - using local timestamps (startedAt: ${localSession.startedAt})',
      );
      return await _localSessionToSessionWithExercises(db, localSession);
    }

    if (_connectivity.isOnline) {
      try {
        // Fetch from API
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.sessionById(id),
          sessionContext: context,
        );

        final apiSession = Session.fromJson(data);

        if (apiSession.userId != token.userId) {
          debugPrint('⚠️ Server returned a session for a different user');
          return await _getLocalSession(db, id, token);
        }

        await _runTestHook(beforeWriteTxnForTesting);
        if (!_sessionEpoch.isCurrent(token)) {
          throw const SessionStaleException();
        }

        // Update local cache (session AND exercises)
        await db.writeTxn(() async {
          await _runTestHook(insideWriteTxnForTesting);
          if (!_sessionEpoch.isCurrent(token)) return;

          final existingLocal =
              await db.localSessions
                  .filter()
                  .serverIdEqualTo(apiSession.id)
                  .findFirst();
          if (existingLocal != null && existingLocal.userId != token.userId) {
            return;
          }

          LocalSession savedSession;
          if (existingLocal != null) {
            final updated = ModelMapper.sessionToLocal(
              apiSession,
              localId: existingLocal.localId,
              isSynced: true,
              clientOperationId: existingLocal.clientOperationId,
            );
            await db.localSessions.put(updated);
            savedSession = updated;
          } else {
            final localSession = ModelMapper.sessionToLocal(apiSession);
            await db.localSessions.put(localSession);
            savedSession = localSession;
          }

          // Save exercises for this session
          for (final apiExercise in apiSession.exercises) {
            final existingExercise = await _resolveExistingExerciseForRefresh(
              db,
              savedSession.localId,
              apiExercise,
            );

            if (existingExercise != null) {
              final updated = ModelMapper.exerciseToLocal(
                apiExercise,
                sessionLocalId: savedSession.localId,
                localId: existingExercise.localId,
                isSynced: true,
              );
              await db.localExercises.put(updated);
            } else {
              final localExercise = ModelMapper.exerciseToLocal(
                apiExercise,
                sessionLocalId: savedSession.localId,
              );
              await db.localExercises.put(localExercise);
            }
          }
        });

        // Strip the internal correlation id before handing this Session to
        // a caller outside the repository layer - every other return path
        // here (_getLocalSession, _localSessionToSessionWithExercises)
        // builds via ModelMapper, which never carries it in the first
        // place. See Session.clientOperationId's doc comment.
        return apiSession.copyWith(clearClientOperationId: true);
      } on SessionStaleException {
        return await _getLocalSession(db, id, token);
      } on RequestCancelledException {
        return await _getLocalSession(db, id, token);
      } catch (e) {
        debugPrint('⚠️ API failed, falling back to local cache: $e');
        return await _getLocalSession(db, id, token);
      }
    } else {
      debugPrint('📴 Offline - returning cached session');
      return await _getLocalSession(db, id, token);
    }
  }

  /// Get session from local database by owned ID (server ID or local ID)
  /// with exercises
  Future<Session> _getLocalSession(
    Isar db,
    int id,
    UserSessionToken token,
  ) async {
    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    final exercises = await _loadExercisesForSession(db, localSession.localId);

    debugPrint(
      '  📦 Loaded session ${localSession.serverId ?? localSession.localId} from cache with ${exercises.length} exercises',
    );

    return ModelMapper.localToSession(localSession, exercises: exercises);
  }

  /// Create new session
  /// Optimistic update: saves locally first, syncs to server if online
  Future<Session> createSession(Session session) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final db = _localDb.database;

    // Generate exactly one durable operation key for this logical generic
    // CREATE, now that a valid captured user exists - persisted below in
    // the SAME write that first inserts the pending_create row, before any
    // HTTP dispatch. See `LocalSession.clientOperationId`'s doc comment.
    final operationId = _generateOperationId();

    // ALWAYS create locally first for instant response, always owned by
    // the captured user regardless of what the caller-supplied [session]
    // claims.
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    final localResult = await _createLocalSession(
      session,
      db,
      token,
      isPending: true,
      clientOperationId: operationId,
    );
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // Then sync to server in background if online (don't block). Bound to
    // the context captured at entry.
    if (_connectivity.isOnline) {
      // Pin the exact local revision the background CREATE will serialize
      // BEFORE scheduling it, re-read from the row just persisted. `session`
      // is immutable and was copied verbatim into this row by
      // `_createLocalSession`, so this `lastModifiedLocal` corresponds
      // exactly to the bytes `_syncCreateSessionToServer` sends. The
      // acknowledgment compares against it: a local edit / completion that
      // races the POST await advances `lastModifiedLocal` and is preserved
      // instead of being overwritten by the stale create response. (A delete
      // of a still-server-id-less row hard-deletes it - not this PR's
      // concern; see the doc comment on `_syncCreateSessionToServer`.)
      final createdRow = await _ownedSessionByLocalId(
        db,
        localResult.id,
        token,
      );
      if (createdRow == null) {
        // Already gone (deleted / logged out between the write and here) -
        // nothing to sync.
        return localResult;
      }
      final dispatchedAt = createdRow.lastModifiedLocal;
      // The canonical, just-persisted row's own key - not the `operationId`
      // local variable - so the dispatched value always matches whatever
      // Isar actually committed (see the class doc comment).
      final dispatchedOperationId = createdRow.clientOperationId;

      _backgroundSync(
        () => _syncCreateSessionToServer(
          session,
          db,
          localResult.id,
          dispatchedAt,
          context,
          dispatchedOperationId,
        ),
        'Created session on server',
      );
    } else {
      debugPrint('📴 Offline - session will sync later');
    }

    return localResult;
  }

  /// Helper method to convert LocalSession to Session with exercises
  Future<Session> _getSessionWithExercises(LocalSession localSession) async {
    final db = _localDb.database;
    return await _localSessionToSessionWithExercises(db, localSession);
  }

  /// Computes the scheduled `date`/initial `status` for a program-workout
  /// Session, from the SAME rule the previous online/offline branches used
  /// independently (now unified so they cannot drift): prefer
  /// [ProgramWorkout.scheduledDate], otherwise derive it from
  /// [programStartDate] + week/day offset; a computed date in the past is
  /// clamped to today (so an overdue workout can still be started "now"
  /// instead of showing a stale past date) - `status` follows from the
  /// CLAMPED date, exactly like before.
  ({DateTime date, String status}) _scheduleForProgramWorkout(
    ProgramWorkout programWorkout,
    DateTime programStartDate,
  ) {
    DateTime normalizedScheduledDate;
    if (programWorkout.scheduledDate != null) {
      final sd = programWorkout.scheduledDate!;
      normalizedScheduledDate = DateTime(sd.year, sd.month, sd.day);
    } else {
      final localStartDate = programStartDate.toLocal();
      final startDate = DateTime(
        localStartDate.year,
        localStartDate.month,
        localStartDate.day,
      );
      final scheduledDate = startDate.add(
        Duration(
          days:
              (programWorkout.weekNumber - 1) * 7 +
              (programWorkout.dayNumber - 1),
        ),
      );
      normalizedScheduledDate = DateTime(
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
      );
    }
    return _clampScheduleToToday(normalizedScheduledDate);
  }

  /// Pure `date`-only clamp shared by [_scheduleForProgramWorkout] (initial
  /// local materialization) and the CREATE acknowledgment (applied directly
  /// to the server's own `date`, with no [ProgramWorkout] object needed - see
  /// [_syncCreateSessionFromProgramWorkoutToServer]'s doc comment for why
  /// that matters for a retry dispatched after an app restart).
  ({DateTime date, String status}) _clampScheduleToToday(
    DateTime normalizedDate,
  ) {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final actualDate = normalizedDate.isBefore(today) ? today : normalizedDate;
    final status = actualDate.isAfter(today) ? 'planned' : 'draft';
    return (date: actualDate, status: status);
  }

  /// Create a session from a program workout. Links the session to the
  /// program and program workout, and works offline by parsing
  /// `exercisesJson` client-side.
  ///
  /// ## Durable, idempotent creation
  ///
  /// `POST /sessions/from-program-workout` now joins the SAME durable
  /// `clientOperationId` protocol [createSession] uses for the generic
  /// endpoint (see [LocalSession.clientOperationId]'s doc comment): exactly
  /// one operation key is generated here and persisted, atomically with the
  /// local Session/Exercise materialization, BEFORE any HTTP attempt -
  /// online or offline, this method always returns the just-persisted local
  /// row (mirroring [createSession]'s "local-first" contract), and dispatch
  /// to the server happens in the background via
  /// [_syncCreateSessionFromProgramWorkoutToServer], never inline here.
  ///
  /// The durable retry REQUEST is nothing more than the identifiers already
  /// on the row - `programWorkoutId`, `programId`, `clientOperationId` (no
  /// new schema field needed): the server materializes the Session's
  /// Exercises from ITS OWN current `ProgramWorkout.ExercisesJson` on the
  /// first accepted write and never re-reads it on a replay (see the
  /// deployed contract's doc comment on
  /// `SessionsController.CreateSessionFromProgramWorkout`), so a client-side
  /// retry never needs to (and never does) resend exercise data - a
  /// [programWorkout] edited after this call returns cannot change what a
  /// later retry of THIS operation sends.
  ///
  /// A background `SyncService` pass picks up a still-`pending_create` row
  /// exactly like any other - see the class-level dispatch-routing note on
  /// `SyncService._syncCreateSession` - and dispatches through the SAME
  /// endpoint with the SAME retained key, never through the generic
  /// `POST /api/v1/sessions` fallback (which would send a keyless/linkless
  /// body under a key the from-program-workout endpoint's server-side
  /// operation row already owns, permanently losing the template's
  /// exercises to first-writer-wins).
  Future<Session> createSessionFromProgramWorkout(
    int programWorkoutId,
    ProgramWorkout programWorkout,
    DateTime programStartDate,
    int programId, // Use actual programId instead of programWorkout.programId
  ) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final db = _localDb.database;
    final userId = token.userId;

    // Check if a session already exists for this program workout. This
    // guards against duplicate ACTIVE sessions for the same template, not
    // against a durable-operation-key check - a fresh key is generated below
    // for every genuinely new intent, so two separate intentional starts of
    // the SAME programWorkoutId (this one finished/archived, a new one
    // begun) never share a key.
    final existingSessions =
        await db.localSessions
            .filter()
            .userIdEqualTo(userId)
            .programWorkoutIdEqualTo(programWorkoutId)
            .findAll();
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // Find existing draft, planned, in_progress, or paused session
    final existingActiveSession = existingSessions.firstWhere(
      (session) =>
          session.status == 'draft' ||
          session.status == 'planned' ||
          session.status == 'in_progress' ||
          session.status == 'paused',
      orElse:
          () => LocalSession(
            userId: 0,
            date: DateTime.now(),
            type: '',
            name: '',
            status: '',
            lastModifiedLocal: DateTime.now().toUtc(),
          ), // Dummy session
    );

    // If we found an existing active session, return it
    if (existingActiveSession.userId != 0) {
      debugPrint(
        '✅ Found existing ${existingActiveSession.status} session for program workout $programWorkoutId',
      );
      return await _getSessionWithExercises(existingActiveSession);
    }

    // Check if there's a completed session (can't restart completed workouts)
    final existingCompletedSession = existingSessions.firstWhere(
      (session) => session.status == 'completed',
      orElse:
          () => LocalSession(
            userId: 0,
            date: DateTime.now(),
            type: '',
            name: '',
            status: '',
            lastModifiedLocal: DateTime.now().toUtc(),
          ),
    );

    // If past workout is already completed, can't start it again
    if (existingCompletedSession.userId != 0) {
      debugPrint('⚠️ Cannot start completed program workout $programWorkoutId');
      throw Exception(
        'This workout is already completed. You cannot start it again.',
      );
    }

    debugPrint(
      '📝 No existing draft/planned session found, creating new session for program workout $programWorkoutId',
    );

    // Generate exactly one durable operation key for this logical CREATE,
    // persisted below in the SAME write that first inserts the
    // pending_create row, before any HTTP dispatch - see
    // [LocalSession.clientOperationId]'s doc comment.
    final operationId = _generateOperationId();
    final schedule = _scheduleForProgramWorkout(
      programWorkout,
      programStartDate,
    );

    // Parse exercisesJson NOW - the only point this call reads the supplied
    // [programWorkout] object. A later template edit cannot retroactively
    // change what gets materialized here, and (per the class doc comment)
    // cannot change what a later retry of THIS operation sends either, since
    // the retry never resends exercise data at all.
    final exercisesData = programWorkout.exercises;
    final exercises = <Exercise>[];

    // ALWAYS materialize locally first for instant response and a durable
    // retry target, online or offline - one shared timestamp for the
    // Session AND every Exercise row created in this same transaction, so
    // the acknowledgment's "did anything change since dispatch" comparisons
    // (below) are exact.
    final createdAt = DateTime.now().toUtc();
    late int sessionLocalId;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final localSession = LocalSession(
        serverId: null,
        userId: userId,
        date: schedule.date,
        name: programWorkout.workoutName,
        type: programWorkout.workoutType ?? 'Workout',
        status: schedule.status,
        programId: programId,
        programWorkoutId: programWorkoutId,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: createdAt,
        clientOperationId: operationId,
      );

      sessionLocalId = await db.localSessions.put(localSession);

      for (final exerciseData in exercisesData) {
        final exerciseName = exerciseData['name'] as String? ?? 'Exercise';
        final exerciseTemplateId = exerciseData['exerciseTemplateId'] as int?;
        final notes = exerciseData['notes'] as String?;
        final restTime = exerciseData['rest'] as int?;
        // Copied verbatim from the cached template entry, exactly as the
        // deployed materializer does server-side - never invented here. A
        // template cached before this field existed (or never refreshed
        // since) simply has no key for this entry; see this method's class
        // doc comment section on program-workout exercise-occurrence
        // identity for why that is handled safely rather than guessed.
        final occurrenceKey = exerciseData['occurrenceKey'] as String?;

        final localExercise = LocalExercise(
          sessionLocalId: sessionLocalId,
          name: exerciseName,
          restTime: restTime,
          notes: notes,
          exerciseTemplateId: exerciseTemplateId,
          occurrenceKey: occurrenceKey,
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: createdAt,
        );
        final exerciseLocalId = await db.localExercises.put(localExercise);

        // Not-yet-synced exercise: expose it under the collision-free
        // public-id namespace (`-localId`), matching
        // ModelMapper.localToExercise, so a later ExerciseRepository lookup
        // resolves it as a local id, never as a server id.
        exercises.add(
          Exercise(
            id: ModelMapper.publicRowId(
              serverId: null,
              localId: exerciseLocalId,
            ),
            sessionId: sessionLocalId,
            name: exerciseName,
            exerciseTemplateId: exerciseTemplateId,
            occurrenceKey: occurrenceKey,
            notes: notes,
            restTime: restTime,
            duration: null,
            exerciseSets: const [],
          ),
        );
      }
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // Dispatch to server in background if online (never inline/blocking) -
    // bound to the context captured at entry, exactly like [createSession].
    if (_connectivity.isOnline) {
      // Pin the exact local revision the background CREATE will serialize BY
      // RE-READING the just-persisted row, not the raw `createdAt` value used
      // to construct it - Isar's own DateTime round-trip precision can
      // differ from the in-memory value, and the acknowledgment's
      // comparisons below must be against what Isar will ACTUALLY read back
      // later, exactly like [createSession] does. Every Exercise row in this
      // same transaction was stamped with the SAME `createdAt` instant, so
      // this one re-read is the correct baseline for all of them too.
      final createdRow = await _ownedSessionByLocalId(
        db,
        sessionLocalId,
        token,
      );
      if (createdRow != null) {
        final dispatchedAt = createdRow.lastModifiedLocal;
        _backgroundSync(
          () => _syncCreateSessionFromProgramWorkoutToServer(
            db,
            sessionLocalId,
            dispatchedAt,
            context,
            operationId,
          ),
          'Created session from program workout on server',
        );
      }
      // else: already gone (deleted / logged out between the write and
      // here) - nothing to sync, matching [createSession]'s identical case.
    } else {
      debugPrint('📴 Offline - program workout session will sync later');
    }

    debugPrint(
      '💾 Created session from program workout with ${exercises.length} exercises '
      '(localId: $sessionLocalId, op: $operationId)',
    );

    return Session(
      id: sessionLocalId,
      userId: userId,
      date: schedule.date,
      name: programWorkout.workoutName,
      type: programWorkout.workoutType ?? 'Workout',
      status: schedule.status,
      programId: programId,
      programWorkoutId: programWorkoutId,
      exercises: exercises,
    );
  }

  /// Background sync: Create session on server. Bound to [context]: the
  /// HTTP call carries its pinned JWT, and the resulting acknowledgment is
  /// gated behind the class doc comment's three-checkpoint shape plus a
  /// re-resolution of the target row by its stable local identity and
  /// direct ownership.
  ///
  /// [dispatchedAt] is the `lastModifiedLocal` of the exact owned row whose
  /// data was serialized into this POST, pinned by [createSession] BEFORE
  /// scheduling this call. The acknowledgment re-reads the row inside its
  /// write transaction and compares: an unchanged value is the normal
  /// success path; a changed value means a local edit / completion raced the
  /// POST await, so the row keeps the newer local state and is re-queued as
  /// `pending_update` with the server identity/version attached - never
  /// rebuilt from the stale create response, never marked synced, never
  /// re-created.
  ///
  /// A delete racing this POST (foreground [deleteSession] or the
  /// background `SyncService`'s delete phase) is preserved, not lost:
  /// `_markForDeletion` now keeps a still-server-id-less row as
  /// `pending_delete` (see its doc comment) instead of hard-deleting it, so
  /// the re-fetch below finds it with `syncStatus == 'pending_delete'` and
  /// this acknowledgment attaches the server identity/version WITHOUT
  /// touching `syncStatus` - deletion intent always wins over a late CREATE
  /// acknowledgment, and the row is never resurrected to visible or
  /// `pending_update`. See [deleteSession]'s doc comment for the
  /// cancellation-by-operation-key dispatch this durably represents, and
  /// `test/data/repositories/session_create_delete_cross_operation_race_test.dart`
  /// for the deterministic proof of this exact convergence.
  ///
  /// [clientOperationId] is the durable operation key already persisted on
  /// the row this POST serializes (see [createSession]) - merged into the
  /// request body here, never added to [Session]'s own JSON model.
  Future<void> _syncCreateSessionToServer(
    Session session,
    Isar db,
    int localId,
    DateTime dispatchedAt,
    SessionRequestContext context,
    String? clientOperationId,
  ) async {
    final token = context.epochToken;

    Map<String, dynamic> data;
    try {
      data = await _dispatchBackgroundHttp(
        () => _apiService.post<Map<String, dynamic>>(
          ApiConfig.sessions,
          data: {
            ...session.toJson(),
            if (clientOperationId != null)
              'clientOperationId': clientOperationId,
          },
          sessionContext: context,
        ),
      );
    } catch (e) {
      // A `409 operation_canceled` means the server holds a permanent
      // tombstone for this exact key - re-POSTing it can never succeed (see
      // `SessionCreateError`'s class doc comment). Converge locally instead
      // of leaving the row stuck retrying an operation the server will
      // forever refuse: transition a STILL-`pending_create` row to
      // `pending_delete`, preserving the SAME `clientOperationId` (never
      // rotating it, never generating a new key), so it is removed through
      // the ordinary cancel-by-operation-key delete phase on the next pass.
      // A row already moved on (the user's own delete already flipped it,
      // or it's gone) is left untouched.
      if (clientOperationId != null &&
          SessionCreateError.classify(e) ==
              SessionCreateErrorKind.operationCanceled) {
        await _convertCanceledCreateToPendingDelete(
          db,
          localId,
          clientOperationId,
          token,
        );
      }
      rethrow;
    }
    final apiSession = Session.fromJson(data);

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    // Re-resolve by stable local identity and direct ownership before
    // deciding whether to acknowledge.
    final target = await _ownedSessionByLocalId(db, localId, token);
    if (target == null) return;

    // Checkpoint: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(token)) return;

      final existing = await db.localSessions.get(localId);
      if (existing == null || existing.userId != token.userId) return;

      if (existing.syncStatus == 'pending_delete') {
        // Deletion/cancellation intent races (or already won) - a late
        // CREATE acknowledgment must never resurrect this row to
        // `pending_update` or visible/synced. Attach the identity/version
        // the server just confirmed (so a later delete pass can use
        // ordinary DELETE-by-serverId, and so a later server-list refresh's
        // serverId match keeps skipping this row) but leave `syncStatus`/
        // `isSynced` untouched - deletion intent always wins. See
        // [deleteSession]'s doc comment.
        existing.serverId = apiSession.id;
        existing.version = apiSession.version;
        existing.lastModifiedServer = DateTime.now();
        await db.localSessions.put(existing);
        return;
      }

      if (existing.lastModifiedLocal != dispatchedAt) {
        // A local edit / completion raced the POST await. Attach the server
        // identity + authoritative version (so no later pass re-creates the
        // row), keep the newer local fields, and re-queue as pending_update.
        // Retry/error bookkeeping is untouched.
        existing.serverId = apiSession.id;
        existing.version = apiSession.version;
        existing.lastModifiedServer = DateTime.now();
        existing.isSynced = false;
        existing.syncStatus = 'pending_update';
        await db.localSessions.put(existing);
        return;
      }

      final updated = ModelMapper.sessionToLocal(
        apiSession,
        localId: localId,
        isSynced: true,
        clientOperationId: existing.clientOperationId,
      );
      await db.localSessions.put(updated);
    });
  }

  /// Background sync: dispatch the durable `POST /sessions/from-program-workout`
  /// CREATE for the row [createSessionFromProgramWorkout] just persisted, and
  /// reconcile the acknowledgment. Mirrors [_syncCreateSessionToServer]'s
  /// dispatchedAt-comparison contract exactly, extended to also reconcile the
  /// child Exercises this endpoint (unlike generic CREATE) returns.
  ///
  /// The request body is ONLY `{programWorkoutId, programId,
  /// clientOperationId}` - re-read from the canonical row, never from a
  /// captured [ProgramWorkout] object (there isn't one here; see the class
  /// doc comment on [createSessionFromProgramWorkout] for why the server
  /// never needs one on a retry either). This is what makes the SAME retry
  /// safe to fire from [SyncService] after an app restart, with no in-memory
  /// template available at all.
  ///
  /// [dispatchedAt] is the shared `lastModifiedLocal` stamped onto the
  /// Session row AND every Exercise row created in the same transaction (see
  /// [createSessionFromProgramWorkout]). The acknowledgment compares each
  /// row's CURRENT `lastModifiedLocal` against it independently: an
  /// unchanged Session is reconciled fully from the server response; a
  /// Session edited (status change, completion, ...) while this POST was in
  /// flight keeps its newer local fields and is re-queued as
  /// `pending_update`, exactly like the generic path. Each Exercise gets the
  /// same per-row treatment, so a user editing/completing a set on ONE
  /// exercise while CREATE is in flight never loses that edit, and never
  /// blocks the other exercises from being reconciled normally.
  ///
  /// Exercises are paired to the server's response by `occurrenceKey`
  /// identity, NEVER by position, name, prescription, or `exerciseTemplateId`
  /// - see [ModelMapper.pairProgramWorkoutCreateExercises]'s doc comment for
  /// the full one-to-one matching contract, and
  /// [_reconcileProgramWorkoutCreateExercises]'s doc comment for exactly
  /// what an unresolvable pairing produces. Nothing here duplicates or loses
  /// a row a user has already added Sets under, and nothing here ever
  /// attaches an
  /// uncertain server identity to a local placeholder.
  Future<void> _syncCreateSessionFromProgramWorkoutToServer(
    Isar db,
    int localId,
    DateTime dispatchedAt,
    SessionRequestContext context,
    String clientOperationId,
  ) async {
    final token = context.epochToken;

    // Re-resolve by stable local identity before dispatch - never trust a
    // stale caller-held reference for the request body. Deliberately does
    // NOT also require `syncStatus == 'pending_create'` here (unlike
    // `SyncService._ensureCreateOperationKey`, which does) - this method is
    // only ever reached once, synchronously scheduled by
    // [createSessionFromProgramWorkout] immediately after that row's own
    // pending_create write, exactly mirroring
    // [_syncCreateSessionToServer]'s identical no-pre-status-check shape for
    // the generic path: any status change that raced in by the time the
    // HTTP response returns (including a delete-to-pending_delete) is fully
    // handled by the ack branches below, not by refusing to dispatch here.
    // If this asymmetry with `_ensureCreateOperationKey` is ever tightened
    // on one side, tighten it identically on the other.
    final preDispatch = await _ownedSessionByLocalId(db, localId, token);
    if (preDispatch == null ||
        preDispatch.programWorkoutId == null ||
        preDispatch.programId == null ||
        preDispatch.clientOperationId != clientOperationId) {
      // No longer an eligible, canonical program-workout pending_create row
      // for this exact key - abort without dispatch.
      return;
    }

    Map<String, dynamic> data;
    try {
      data = await _dispatchBackgroundHttp(
        () => _apiService.post<Map<String, dynamic>>(
          ApiConfig.sessionsFromProgramWorkout,
          data: {
            'programWorkoutId': preDispatch.programWorkoutId,
            'programId': preDispatch.programId,
            'clientOperationId': clientOperationId,
          },
          sessionContext: context,
        ),
      );
    } catch (e) {
      // Same terminal-tombstone convergence as the generic path - see
      // [_convertCanceledCreateToPendingDelete]'s doc comment. Fully generic
      // (keyed only on `clientOperationId` + `pending_create`), so it is
      // reused as-is for this endpoint too.
      if (SessionCreateError.classify(e) ==
          SessionCreateErrorKind.operationCanceled) {
        await _convertCanceledCreateToPendingDelete(
          db,
          localId,
          clientOperationId,
          token,
        );
      }
      rethrow;
    }
    _assertProgramWorkoutCreateCurrent(token);
    final apiSession = Session.fromJson(data);

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    final target = await _ownedSessionByLocalId(db, localId, token);
    if (!_sessionEpoch.isCurrent(token)) return;
    if (target == null) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final existing = await db.localSessions.get(localId);
      if (existing == null || existing.userId != token.userId) return;

      if (existing.syncStatus == 'pending_delete') {
        // Deletion/cancellation intent races (or already won) - never
        // resurrect. See [_syncCreateSessionToServer]'s identical branch.
        existing.serverId = apiSession.id;
        existing.version = apiSession.version;
        existing.lastModifiedServer = DateTime.now();
        await db.localSessions.put(existing);
        return;
      }

      if (existing.lastModifiedLocal != dispatchedAt) {
        // A local edit / completion raced the POST await - keep it, attach
        // identity, re-queue as pending_update. Exercises are still
        // reconciled below regardless of this branch.
        existing.serverId = apiSession.id;
        existing.version = apiSession.version;
        existing.lastModifiedServer = DateTime.now();
        existing.isSynced = false;
        existing.syncStatus = 'pending_update';
        await db.localSessions.put(existing);
      } else {
        // Unchanged: the same `date`-only clamp [createSessionFromProgramWorkout]
        // applied locally, reapplied here directly to the server's own date -
        // no ProgramWorkout object needed (see this method's doc comment).
        // `status`/`name`/`type` are trusted from the server as-is, exactly
        // like the previous online-success path did.
        final schedule = _clampScheduleToToday(apiSession.date);
        final updated = ModelMapper.sessionToLocal(
          apiSession.copyWith(date: schedule.date),
          localId: localId,
          isSynced: true,
          clientOperationId: existing.clientOperationId,
        );
        await db.localSessions.put(updated);
      }

      await _reconcileProgramWorkoutCreateExercises(db, localId, apiSession);
    });
  }

  /// Assert-and-throw variant of [UserSessionEpoch.isCurrent] used only
  /// between the HTTP call and the first Isar read below it in
  /// [_syncCreateSessionFromProgramWorkoutToServer] - every other checkpoint
  /// in that method returns early instead, matching
  /// [_syncCreateSessionToServer]'s existing convention.
  void _assertProgramWorkoutCreateCurrent(UserSessionToken token) {
    if (!_sessionEpoch.isCurrent(token)) {
      throw const SessionStaleException();
    }
  }

  /// Reconciles the child Exercises returned by a program-workout CREATE
  /// acknowledgment against the local placeholders
  /// [createSessionFromProgramWorkout] materialized before dispatch. Must be
  /// called from INSIDE the same write transaction that reconciles the
  /// parent Session - never touches [LocalExerciseSet] rows, so any Set a
  /// user added while CREATE was in flight survives untouched under its
  /// exercise's stable `localId`, regardless of anything below.
  ///
  /// Pairing/identity-safety rules live entirely in
  /// [ModelMapper.pairProgramWorkoutCreateExercises] - see its doc comment.
  /// This method only applies the three outcomes it returns:
  ///
  /// - `matched` (a local placeholder paired with EXACTLY the one server
  ///   exercise sharing its `occurrenceKey`, with no other candidate on
  ///   either side): overwritten UNCONDITIONALLY from the server's response
  ///   (never gated on a `lastModifiedLocal` comparison) - there is no UI
  ///   path that edits an Exercise's own fields (name/notes/rest) before it
  ///   is synced, so there is nothing "newer" to protect here, and the
  ///   deployed API has no PUT route for a single Exercise (`SyncService
  ///   ._syncUpdateExercise` refuses to dispatch anything with a positive
  ///   `serverId`) - flipping a matched exercise to `pending_update` instead
  ///   would strand it there permanently, including on an entirely benign
  ///   REDUNDANT re-acknowledgment (e.g. this dispatch racing a separate
  ///   `SyncService` pass for the exact same still-`pending_create` row -
  ///   both carry the identical key, so both eventually see the identical
  ///   apiSession data; overwriting twice with identical data is always a
  ///   safe no-op). Unlike the Session-level check above, this method takes
  ///   no `dispatchedAt`-equivalent parameter at all - there is nothing for
  ///   one to gate, for the reasons above.
  /// - `unmatchedServer` (a server exercise whose `occurrenceKey` no local
  ///   placeholder claims at all): inserted fresh, already synced - nothing
  ///   local could be confused with it.
  /// - `unmatchedLocal` (a local placeholder the pairing could not safely
  ///   attach an identity to - no key at all, or a key the server's response
  ///   doesn't uniquely corroborate; see the pairing method's doc comment
  ///   for every case this covers): marked `syncStatus: 'conflict'` (never
  ///   `serverId`, never `isSynced: true`) - the SAME "needs manual
  ///   resolution, never auto-dispatched" convention this codebase already
  ///   uses for a Session-level 409 (see `SessionSyncDiagnostics`).
  ///   `SyncService._syncExercises`'s phase switch has no case for
  ///   `'conflict'`, so it is silently skipped forever (its top-level query
  ///   is `isSyncedEqualTo(false)`, not filtered by `syncStatus`, so the row
  ///   is still enumerated and gets its `sessionServerId` patched, but never
  ///   reaches a dispatching switch case) - it can NEVER independently
  ///   re-create itself server-side, so an unresolved occurrence never turns
  ///   into a duplicate that way. A LATER refresh of the same session
  ///   ([getSession]/`SyncService._syncSessionsFromServer`, via
  ///   [_resolveExistingExerciseForRefresh]) can now ALSO recognize this row
  ///   by its retained `occurrenceKey` (if it has one) instead of only by
  ///   `serverId`, so a genuinely-resolvable occurrence converges on refresh
  ///   even if the CREATE ack that should have resolved it never did. A row
  ///   with NO `occurrenceKey` at all (the legacy-cache case) has no way to
  ///   be recognized by either path - it remains `'conflict'` until some
  ///   future manual-resolution mechanism (not built yet - there is no
  ///   exercise-level equivalent of the Session conflict-resolution UI this
  ///   borrows its status value from) decides what to do with it. This is a
  ///   genuine, disclosed limitation of a keyless local row, not a defect.
  Future<void> _reconcileProgramWorkoutCreateExercises(
    Isar db,
    int sessionLocalId,
    Session apiSession,
  ) async {
    final localExercises =
        await db.localExercises
              .filter()
              .sessionLocalIdEqualTo(sessionLocalId)
              .findAll()
          ..sort((a, b) => a.localId.compareTo(b.localId));
    final paired = ModelMapper.pairProgramWorkoutCreateExercises(
      localExercises,
      apiSession.exercises,
    );

    for (final (local, apiExercise) in paired.matched) {
      final updated = ModelMapper.exerciseToLocal(
        apiExercise,
        sessionLocalId: sessionLocalId,
        sessionServerId: apiSession.id,
        localId: local.localId,
        isSynced: true,
      );
      await db.localExercises.put(updated);
    }

    for (final apiExercise in paired.unmatchedServer) {
      final localExercise = ModelMapper.exerciseToLocal(
        apiExercise,
        sessionLocalId: sessionLocalId,
        sessionServerId: apiSession.id,
        isSynced: true,
      );
      await db.localExercises.put(localExercise);
    }

    // Never independently re-created (nor left able to be) - see this
    // method's doc comment for exactly what 'conflict' does and does not
    // close.
    for (final local in paired.unmatchedLocal) {
      local.syncStatus = 'conflict';
      local.isSynced = false;
      await db.localExercises.put(local);
    }
  }

  /// A CREATE dispatch that comes back `409 operation_canceled` means the
  /// server holds a PERMANENT tombstone for [operationId] - re-POSTing it can
  /// never succeed (see [SessionCreateError]'s class doc comment). Converts a
  /// row that is STILL `pending_create` to `pending_delete`, PRESERVING the
  /// same [operationId] (never rotating it, never generating a new key), so
  /// it converges to local removal through the ordinary
  /// cancel-by-operation-key delete path on the next sync pass instead of
  /// retrying an operation the server will forever refuse.
  ///
  /// A row already moved on since this CREATE was dispatched - the user's
  /// own delete already flipped it away from `pending_create`, its key was
  /// somehow replaced, or it is gone/foreign - is left untouched: this never
  /// overwrites a newer local intent.
  Future<void> _convertCanceledCreateToPendingDelete(
    Isar db,
    int localId,
    String operationId,
    UserSessionToken token,
  ) async {
    if (!_sessionEpoch.isCurrent(token)) return;
    final target = await _ownedSessionByLocalId(db, localId, token);
    if (target == null) return;
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      if (!_sessionEpoch.isCurrent(token)) return;
      final reFetched = await db.localSessions.get(localId);
      if (reFetched == null || reFetched.userId != token.userId) return;
      if (reFetched.syncStatus != 'pending_create') return;
      if (reFetched.clientOperationId != operationId) return;
      reFetched.syncStatus = 'pending_delete';
      reFetched.isSynced = false;
      reFetched.lastModifiedLocal = DateTime.now().toUtc();
      await db.localSessions.put(reFetched);
    });
  }

  /// Create session in local database, always owned by [token.userId]
  /// regardless of what [session] claims.
  ///
  /// [clientOperationId] is the durable generic-CREATE operation key
  /// generated by the caller BEFORE this write - only meaningful when
  /// [isPending] is true (a genuine generic `pending_create` row); ignored
  /// otherwise, since an already-synced row was never a generic CREATE this
  /// repository dispatched.
  Future<Session> _createLocalSession(
    Session session,
    Isar db,
    UserSessionToken token, {
    required bool isPending,
    String? clientOperationId,
  }) async {
    final localSession = LocalSession(
      serverId: isPending ? null : session.id,
      userId: token.userId,
      date: session.date,
      duration: session.duration,
      notes: session.notes,
      type: session.type,
      name: session.name,
      status: session.status,
      startedAt: session.startedAt,
      completedAt: session.completedAt,
      pausedAt: session.pausedAt,
      programId: session.programId,
      programWorkoutId: session.programWorkoutId,
      isSynced: !isPending,
      clientOperationId: isPending ? clientOperationId : null,
      syncStatus: isPending ? 'pending_create' : 'synced',
      lastModifiedLocal: DateTime.now().toUtc(),
    );

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      await db.localSessions.put(localSession);
    });

    debugPrint('💾 Saved session locally: ${localSession.localId}');

    return Session(
      id: localSession.localId,
      userId: localSession.userId,
      date: localSession.date,
      duration: localSession.duration,
      notes: localSession.notes,
      type: localSession.type,
      name: localSession.name,
      status: localSession.status,
      startedAt: localSession.startedAt,
      completedAt: localSession.completedAt,
      pausedAt: localSession.pausedAt,
      programId: localSession.programId,
      programWorkoutId: localSession.programWorkoutId,
    );
  }

  /// Update session status
  /// Optimistic update: updates locally first, syncs to server if online
  /// [startedAtUtc] optional timestamp for when starting workout (calculated by provider)
  Future<Session> updateSessionStatus(
    int id,
    String status, {
    int? duration,
    DateTime? startedAtUtc,
  }) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // ALWAYS update locally first for instant response
    await _updateLocalSessionStatus(
      db,
      localSession,
      status,
      token,
      duration: duration,
      startedAtUtc: startedAtUtc,
    );
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // Then sync to server in background if online (using helper), unless
    // the row has an unresolved conflict - it must not be pushed until
    // explicitly resolved.
    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _syncSessionStatusToServer(
          db,
          localSession.localId,
          localSession.serverId!,
          context,
        ),
        'Updated session status on server',
      );
    } else if (_isConflicted(localSession)) {
      debugPrint('⚠️ Session has an unresolved conflict - skipping sync');
    } else {
      debugPrint('📴 Offline - session status will sync later');
    }

    // Return session with exercises using helper
    return await _localSessionToSessionWithExercises(db, localSession);
  }

  /// Background sync: Update session status on server. Bound to [context]:
  /// the HTTP call carries its pinned JWT, and the resulting acknowledgment
  /// is gated behind the class doc comment's three-checkpoint shape plus a
  /// re-resolution of the target row by its STABLE LOCAL ID and direct
  /// ownership (never an unscoped `serverIdEqualTo` lookup).
  Future<void> _syncSessionStatusToServer(
    Isar db,
    int sessionLocalId,
    int serverId,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    // Snapshot the fields to send from the currently-owned row before
    // dispatching, so a concurrent edit mid-flight can't be lost.
    final source = await _ownedSessionByLocalId(db, sessionLocalId, token);
    if (source == null) return;

    String? toUtcIso8601(DateTime? dt) => dt?.toUtc().toIso8601String();

    final startedAtString = toUtcIso8601(source.startedAt);
    final pausedAtString = toUtcIso8601(source.pausedAt);

    final requestData = {
      'status': source.status,
      if (source.startedAt != null) 'startedAt': startedAtString,
      if (source.completedAt != null)
        'completedAt': toUtcIso8601(source.completedAt),
      if (source.pausedAt != null) 'pausedAt': pausedAtString,
      if (source.pausedAt == null) 'clearPausedAt': true,
      if (source.duration != null) 'duration': source.duration,
    };

    await _dispatchBackgroundHttp(
      () => _apiService.patch<void>(
        ApiConfig.sessionStatus(serverId),
        data: requestData,
        sessionContext: context,
      ),
    );

    debugPrint('✅ Synced session $serverId with timestamps');

    // Checkpoint: post-HTTP, before touching Isar at all.
    if (!_sessionEpoch.isCurrent(token)) return;

    await _runTestHook(afterBackgroundHttpResponseForTesting);

    // Re-resolve by stable local identity and direct ownership.
    final target = await _ownedSessionByLocalId(db, sessionLocalId, token);
    if (target == null) return;

    // Checkpoint: immediately before entering the write transaction.
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideBackgroundWriteTxnForTesting);
      // Checkpoint: first statement inside the write transaction.
      if (!_sessionEpoch.isCurrent(token)) return;

      final session = await db.localSessions.get(sessionLocalId);
      if (session == null || session.userId != token.userId) return;

      session.isSynced = true;
      session.syncStatus = 'synced';
      await db.localSessions.put(session);
    });
  }

  /// Update session status in local database
  /// [startedAtUtc] optional timestamp from provider (ensures UTC consistency)
  Future<void> _updateLocalSessionStatus(
    Isar db,
    LocalSession localSession,
    String status,
    UserSessionToken token, {
    int? duration,
    DateTime? startedAtUtc,
  }) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final now = DateTime.now();
      final conflicted = _isConflicted(localSession);
      localSession.status = status;
      localSession.lastModifiedLocal = now;
      if (!conflicted) {
        localSession.isSynced = false;
      }

      // Set startedAt when status changes to 'in_progress'
      if (status == 'in_progress' && localSession.startedAt == null) {
        final timestampToUse = startedAtUtc ?? DateTime.now().toUtc();
        localSession.startedAt = timestampToUse;
        localSession.pausedAt = null;
      }

      // Set completedAt when status changes to 'completed'
      if (status == 'completed' && localSession.completedAt == null) {
        final completedAtUtc = DateTime.now().toUtc();
        localSession.completedAt = completedAtUtc;
        await _updateWorkoutGoals(db, token.userId, completedAtUtc);
      }

      if (duration != null) {
        localSession.duration = duration;
      }

      if (!conflicted && localSession.serverId != null) {
        localSession.syncStatus = 'pending_update';
      }
      await db.localSessions.put(localSession);
    });

    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Update workout frequency goals when a workout is completed (Issue #11)
  ///
  /// NOTE: Currently goals are server-only (no LocalGoal model exists).
  /// This method documents the intended client-side goal update logic; see
  /// git history for the previous full commented-out implementation sketch.
  Future<void> _updateWorkoutGoals(
    Isar db,
    int userId,
    DateTime completedAt,
  ) async {
    debugPrint(
      '📊 Goal updates (Issue #11): Currently server-only. LocalGoal model needed for offline support.',
    );
  }

  /// Pause session timer
  /// Works offline by updating local database
  /// [pausedAt] timestamp from provider (to avoid time drift)
  Future<void> pauseSession(int id, DateTime pausedAt) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      localSession.pausedAt = pausedAt;
      _applyLocalEditBookkeeping(localSession);
      await db.localSessions.put(localSession);
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    debugPrint('⏸️ Session paused locally (pausedAt UTC: $pausedAt)');

    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _syncSessionStatusToServer(
          db,
          localSession.localId,
          localSession.serverId!,
          context,
        ),
        'Pause synced to server',
      );
    }
  }

  /// Resume session timer
  /// Works offline by updating local database
  /// [newStartedAt] adjusted timestamp from provider (to avoid time drift)
  Future<void> resumeSession(int id, DateTime newStartedAt) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      localSession.startedAt = newStartedAt;
      localSession.pausedAt = null;
      _applyLocalEditBookkeeping(localSession);
      await db.localSessions.put(localSession);
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    debugPrint('▶️ Session resumed locally');

    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _syncSessionStatusToServer(
          db,
          localSession.localId,
          localSession.serverId!,
          context,
        ),
        'Resume synced to server',
      );
    }
  }

  /// Archive a session (change status to 'archived')
  /// Archived sessions are hidden from main list but still count for programs
  Future<bool> archiveSession(int id) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }
    await _markSessionForSync(db, localSession, token, newStatus: 'archived');
    await _runTestHook(afterWriteTxnForTesting);

    debugPrint(
      '📦 Archived session: ${localSession.serverId ?? localSession.localId}',
    );
    return true;
  }

  /// Delete session
  /// Marks as pending_delete offline, deletes from server when online
  ///
  /// ## Dispatch rule (see [LocalSession.clientOperationId]'s doc comment)
  ///
  /// - A known [LocalSession.serverId] always uses ordinary
  ///   `DELETE /api/v1/sessions/{id}` - unaffected by any of this, EVEN when
  ///   a `clientOperationId` is also retained (it always is, once a keyed
  ///   CREATE has synced - see [LocalSession.clientOperationId]'s doc
  ///   comment). Confirmed safe by reading the paired GoHardAPI source
  ///   (`SessionCreateService.RunKeyedAttemptAsync` / the DB-level
  ///   `SessionCreateOperation.SessionId` FK, `ON DELETE SET NULL`): an
  ///   ordinary DELETE never touches the operation row, but the FK cascade
  ///   still blanks its `SessionId` while `CompletedAt` stays set - the
  ///   EXACT terminal state a later CREATE retry with that same key reads as
  ///   "Gone" (`410 operation_target_deleted`), never as "eligible to
  ///   recreate". This is exactly the deployed contract's OWN existing test
  ///   (`SessionCreateIdempotencyPostgresTests
  ///   .CompletedOperationWhoseSessionWasDeleted_Returns410_AndNeverRecreates`,
  ///   which deletes the Session with a raw SQL DELETE - the same operation
  ///   an ordinary `DELETE /sessions/{id}` performs - then replays the key
  ///   and asserts 410, never a second Session). Routing a known-`serverId`
  ///   delete through the operation-key endpoint instead would be no safer,
  ///   so this is left as ordinary DELETE rather than changed for style.
  /// - No `serverId` but a retained `clientOperationId` means the row's
  ///   keyed CREATE (generic `POST /api/v1/sessions` OR
  ///   `POST /sessions/from-program-workout` - both share this dispatch
  ///   rule identically, see [createSessionFromProgramWorkout]) may have
  ///   reached the server before its response was lost (or may still be in
  ///   flight) - a missing `serverId` does NOT prove CREATE never happened.
  ///   This dispatches `DELETE /api/v1/sessions/by-operation/{clientOperationId}`
  ///   instead, which is safe to call before, during, or after the server
  ///   commits the CREATE, and retains a server tombstone that blocks any
  ///   later replay of that exact key - regardless of which endpoint owns
  ///   it, since both write to the same `SessionCreateOperations` table.
  /// - Neither identity (no `serverId`, no `clientOperationId`) means this
  ///   row was never dispatched to a keyed CREATE endpoint at all - only
  ///   possible for a legacy row created before either CREATE entry point
  ///   assigned this field - there is nothing a server could be holding
  ///   under a key that was never generated, so it is safe to remove the
  ///   local row immediately, exactly as before this feature.
  ///
  /// The returned `bool` is not a uniform "HTTP call succeeded" signal
  /// across branches: the legacy `serverId` branch returns `false` for a
  /// non-2xx-but-non-throwing result, while the operation-key branch always
  /// returns `true` once cancellation intent is durably persisted -
  /// regardless of whether the cancel call itself has succeeded yet -
  /// since that intent will converge on a later pass either way.
  Future<bool> deleteSession(int id) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    // Prevent deletion of completed program workouts
    if (localSession.status == 'completed' &&
        localSession.programWorkoutId != null) {
      throw Exception(
        'Cannot delete completed program workout. Archive it instead.',
      );
    }

    final serverId = localSession.serverId;
    final operationId = localSession.clientOperationId;

    if (_connectivity.isOnline && serverId != null) {
      try {
        final success = await _apiService.delete(
          ApiConfig.sessionById(serverId),
          sessionContext: context,
        );

        if (success) {
          if (!_sessionEpoch.isCurrent(token)) {
            throw Exception(_unauthenticated);
          }
          await _deleteSessionAndRelatedData(db, localSession, token);
          debugPrint('✅ Deleted session from server: $serverId');
          return true;
        }
        return false;
      } on SessionStaleException {
        await _markForDeletion(db, localSession, token);
        return true;
      } on RequestCancelledException {
        await _markForDeletion(db, localSession, token);
        return true;
      } catch (e) {
        debugPrint('⚠️ Delete API failed, marking as pending: $e');
        await _markForDeletion(db, localSession, token);
        return true;
      }
    } else if (serverId == null && operationId != null) {
      // Persist cancellation intent atomically BEFORE any HTTP attempt (and
      // before this row disappears from the visible list) - never rely
      // solely on an in-memory callback or an immediate HTTP attempt alone.
      // A crash/restart landing anywhere after this point still finds the
      // row durably `pending_delete` with the SAME retained operation key,
      // never silently reverted back to visible. See [_markForDeletion]'s
      // doc comment.
      await _markForDeletion(db, localSession, token);
      if (!_sessionEpoch.isCurrent(token) || !_connectivity.isOnline) {
        // Intent is already durable either way - a later sync pass (or a
        // resumed session) dispatches the cancellation.
        return true;
      }

      try {
        final success = await _apiService.delete(
          ApiConfig.sessionCancelByOperation(operationId),
          sessionContext: context,
        );

        if (success && _sessionEpoch.isCurrent(token)) {
          await _deleteSessionAndRelatedData(
            db,
            localSession,
            token,
            requireOperationId: operationId,
          );
          debugPrint('✅ Canceled session create on server (op $operationId)');
        }
      } on SessionStaleException {
        // Intent already durable - retried by a later pass.
      } on RequestCancelledException {
        // Intent already durable - retried by a later pass.
      } catch (e) {
        debugPrint('⚠️ Cancel API failed, will retry later: $e');
      }
      return true;
    } else {
      debugPrint('📴 Offline - marking session for deletion');
      await _markForDeletion(db, localSession, token);
      return true;
    }
  }

  /// Deletes [localId]'s exercises, their sets, and the session row itself.
  /// Pure transaction-internal helper: assumes the caller has ALREADY
  /// verified epoch/ownership/identity as earlier statements inside its OWN
  /// transaction - this performs no such checks itself beyond the
  /// grandparent-ownership recheck on each child (closing the window
  /// between the exercise query and its own delete, per the class doc
  /// comment's session graph ownership section). Never call this outside an
  /// already-open `writeTxn`.
  Future<void> _deleteSessionRowAndChildren(Isar db, int localId) async {
    final exercises =
        await db.localExercises
            .filter()
            .sessionLocalIdEqualTo(localId)
            .findAll();

    for (final exercise in exercises) {
      await _runTestHook(beforeChildDeleteForTesting);
      // Grandparent-ownership recheck: re-resolve the exercise by its
      // stable local identity and confirm it still belongs to the session
      // being deleted before touching its sets.
      final currentExercise = await db.localExercises.get(exercise.localId);
      if (currentExercise == null ||
          currentExercise.sessionLocalId != localId) {
        continue;
      }
      await db.localExerciseSets
          .filter()
          .exerciseLocalIdEqualTo(exercise.localId)
          .deleteAll();
      await db.localExercises.delete(exercise.localId);
    }

    await db.localSessions.delete(localId);
  }

  /// Mark session for deletion (to be synced later).
  ///
  /// A row with neither a `serverId` nor a retained `clientOperationId` was
  /// never dispatched to the server under a durable key, so it is removed
  /// immediately - unchanged from before this feature. Every other row
  /// (a known `serverId`, OR no `serverId` but a retained `clientOperationId`
  /// whose CREATE may have reached the server) is persisted as
  /// `pending_delete` - never hard-deleted - so the deletion/cancellation
  /// intent survives restart, logout, and retryable failures. See
  /// [deleteSession]'s doc comment for the full dispatch rule this durably
  /// represents.
  ///
  /// The "neither identity" decision is made from a row re-fetched by
  /// stable local identity as the FIRST statement inside THIS transaction -
  /// never from the possibly-stale [localSession] parameter. A row observed
  /// keyless/serverId-less at an earlier read (e.g. `deleteSession`'s own
  /// resolution, or a prior failed cancel attempt) can still race a
  /// concurrent `SyncService._ensureCreateOperationKey` backfill (only a
  /// legacy pre-upgrade row starts with a `null` key now - both CREATE entry
  /// points assign one atomically at creation, see
  /// [LocalSession.clientOperationId]'s doc comment) that assigns a key and
  /// dispatches CREATE between that read and this write.
  /// If the fresh, in-transaction read shows EITHER identity now present,
  /// this always falls back to persisting `pending_delete` rather than
  /// hard-deleting - a concurrent backfill may have just attached the exact
  /// identity a later cancellation/delete would need, and silently
  /// discarding it here would reopen the orphan-Session race this feature
  /// exists to close.
  Future<void> _markForDeletion(
    Isar db,
    LocalSession localSession,
    UserSessionToken token,
  ) async {
    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final current = await db.localSessions.get(localSession.localId);
      if (current == null || current.userId != token.userId) return;

      if (current.serverId == null && current.clientOperationId == null) {
        // Proven fresh, inside this exact transaction: neither identity was
        // ever generated for this row - nothing a server could be holding
        // under a key. Safe to remove immediately.
        await _deleteSessionRowAndChildren(db, current.localId);
        return;
      }

      current.isSynced = false;
      current.syncStatus = 'pending_delete';
      current.lastModifiedLocal = DateTime.now().toUtc();
      await db.localSessions.put(current);
    });
    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Delete session and all related exercises and sets. Reverifies parent
  /// ownership as the first statement inside the transaction, per the class
  /// doc comment's session graph ownership section - this must never delete
  /// a session/its children that have been reassigned or replaced since
  /// [localSession] was resolved.
  ///
  /// [requireOperationId], when non-null, additionally requires - as part of
  /// the SAME re-read inside the transaction - that the row's retained
  /// `clientOperationId` still equals it AND that deletion intent is still
  /// current (`syncStatus == 'pending_delete'` - [deleteSession] always
  /// persists this durably BEFORE ever dispatching the cancellation HTTP
  /// call, so this holds by the time any acknowledgment can run). Passed
  /// only when this deletion is the acknowledgment of an accepted
  /// `DELETE /sessions/by-operation/{id}` cancellation, so a late
  /// acknowledgment can never remove a row whose operation key was somehow
  /// replaced, or one whose intent has since changed - never just an
  /// assertion, but the actual gate on whether anything is deleted. `null`
  /// (every pre-existing call site) preserves prior behavior exactly.
  Future<void> _deleteSessionAndRelatedData(
    Isar db,
    LocalSession localSession,
    UserSessionToken token, {
    String? requireOperationId,
  }) async {
    final localId = localSession.localId;

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) return;

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final current = await db.localSessions.get(localId);
      if (current == null || current.userId != token.userId) return;
      if (requireOperationId != null &&
          (current.clientOperationId != requireOperationId ||
              current.syncStatus != 'pending_delete')) {
        return;
      }

      await _deleteSessionRowAndChildren(db, localId);
    });
    await _runTestHook(afterWriteTxnForTesting);
  }

  /// Update session name
  /// Optimistic update: updates locally first, syncs to server if online
  Future<Session> updateSessionName(int id, String name) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      localSession.name = name;
      _applyLocalEditBookkeeping(localSession);
      await db.localSessions.put(localSession);
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    debugPrint('✏️ Session name updated locally to: $name');

    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _pushSessionUpdate(
          db,
          localSession.localId,
          'session name',
          context,
        ),
        'Updated session name on server',
      );
    } else if (_isConflicted(localSession)) {
      debugPrint('⚠️ Session has an unresolved conflict - skipping sync');
    } else {
      debugPrint('📴 Offline - session name will sync later');
    }

    return await _localSessionToSessionWithExercises(db, localSession);
  }

  /// Update workout date (used when starting future planned workout early)
  /// Optimistic update: updates locally first, syncs to server if online
  Future<void> updateWorkoutDate(int id, DateTime newDate) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(db, id, token);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await _runTestHook(beforeWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;
      final dateOnly = DateTime(newDate.year, newDate.month, newDate.day);
      localSession.date = dateOnly;
      _applyLocalEditBookkeeping(localSession);
      await db.localSessions.put(localSession);
    });
    await _runTestHook(afterWriteTxnForTesting);
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    debugPrint('📅 Workout date updated locally to: $newDate');

    if (_shouldPushAfterEdit(localSession)) {
      _backgroundSync(
        () => _pushSessionUpdate(
          db,
          localSession.localId,
          'workout date',
          context,
        ),
        'Updated workout date on server',
      );
    } else if (_isConflicted(localSession)) {
      debugPrint('⚠️ Session has an unresolved conflict - skipping sync');
    } else {
      debugPrint('📴 Offline - workout date will sync later');
    }
  }

  /// Push a full-session PUT update via the centralized sync helper and log
  /// the outcome. Bound to [context]: the PUT (and, on a non-map success
  /// response, the helper's own recovery GET) carries the pinned JWT, and
  /// every write the helper may perform is additionally gated by
  /// `isSessionCurrent`/`scopeUserId` - see `SessionUpdateSyncHelper`'s own
  /// class doc comment. [sessionLocalId] is re-resolved by its stable local
  /// identity and ownership immediately before dispatch, so a stale target
  /// is never pushed.
  Future<void> _pushSessionUpdate(
    Isar db,
    int sessionLocalId,
    String what,
    SessionRequestContext context,
  ) async {
    final token = context.epochToken;

    final session = await _ownedSessionByLocalId(db, sessionLocalId, token);
    if (session == null) return;
    if (!_sessionEpoch.isCurrent(token)) return;

    final outcome = await _dispatchBackgroundHttp(
      () => SessionUpdateSyncHelper(_apiService).pushUpdate(
        db,
        session,
        sessionContext: context,
        isSessionCurrent: () => _sessionEpoch.isCurrent(token),
        scopeUserId: token.userId,
      ),
    );

    switch (outcome) {
      case SessionSyncOutcome.synced:
        debugPrint('✅ Synced $what to server');
        break;
      case SessionSyncOutcome.conflict:
        debugPrint(
          '⚠️ Conflict detected updating $what - stored for manual resolution',
        );
        break;
      case SessionSyncOutcome.conflictDataInvalid:
        debugPrint(
          '⚠️ Conflict response malformed updating $what - will retry later',
        );
        break;
      case SessionSyncOutcome.deferred:
        debugPrint('⚠️ Could not confirm $what update - will retry later');
        break;
    }
  }

  /// Watch sessions for reactive updates (Issue #7)
  /// Returns a stream that emits whenever sessions change in local DB
  /// This enables automatic UI updates when background sync completes
  ///
  /// Implemented as a thin projection of [watchSessionSyncSnapshot] so
  /// there is exactly one underlying Isar watch over `localSessions` for
  /// this user, not two - existing behavior (filtering, sorting, the
  /// `pending_delete`/`archived` exclusion) is unchanged.
  Stream<List<Session>> watchSessions(int userId) {
    return watchSessionSyncSnapshot(
      userId,
    ).map((snapshot) => snapshot.visibleEntries.map((e) => e.session).toList());
  }

  /// Real-time, user-scoped, single-watch snapshot of both the visible
  /// session list and derived sync diagnostics for the SAME rows - see
  /// [SessionSyncSnapshot]. This is the single collection watch [SessionsProvider]
  /// installs; it must never be joined with a second `watch()`/
  /// `StreamSubscription` for diagnostics.
  ///
  /// Pure read: never writes to Isar, never calls `SyncService`, never
  /// makes an HTTP request. Diagnostics never carry raw
  /// `LocalSession.syncError` text - see [SessionSyncDiagnostics.deriveFrom].
  ///
  /// A `pending_delete` row is excluded from [SessionSyncSnapshot.visibleEntries]
  /// (same rule as the legacy `watchSessions` list), but a failing one still
  /// contributes to [SessionSyncSnapshot.retryingFailureCount] - a session
  /// stuck failing to delete must not become invisible to the aggregate
  /// count merely because it has no place in the visible list.
  ///
  /// Every [SessionListEntry] pairs its [Session] with the exact
  /// [LocalSession.localId] it was built from in this same loop - diagnostics
  /// are never attached via a later lookup keyed by the ambiguous
  /// `Session.id` (`serverId ?? localId`), which can collide between the
  /// server-id and local-id namespaces.
  Stream<SessionSyncSnapshot> watchSessionSyncSnapshot(int userId) {
    final db = _localDb.database;

    return db.localSessions
        .filter()
        .userIdEqualTo(userId)
        .watch(fireImmediately: true)
        .asyncMap((localSessions) async {
          final visibleEntries = <SessionListEntry>[];
          var retryingFailureCount = 0;
          var conflictCount = 0;

          for (final localSession in localSessions) {
            final diagnostics = SessionSyncDiagnostics.deriveFrom(localSession);
            switch (diagnostics?.state) {
              case SessionSyncState.conflict:
                conflictCount++;
              case SessionSyncState.retryingFailure:
                retryingFailureCount++;
              case null:
                break;
            }

            if (localSession.syncStatus == 'pending_delete' ||
                localSession.status == 'archived') {
              continue;
            }

            visibleEntries.add(
              SessionListEntry(
                session: await _localSessionToSessionWithExercises(
                  db,
                  localSession,
                ),
                localId: localSession.localId,
                diagnostics: diagnostics,
              ),
            );
          }

          visibleEntries.sort(
            (a, b) => b.session.date.compareTo(a.session.date),
          );
          return SessionSyncSnapshot(
            visibleEntries: visibleEntries,
            retryingFailureCount: retryingFailureCount,
            conflictCount: conflictCount,
          );
        });
  }

  /// Add exercise to session
  /// Works offline by creating locally and syncing later
  Future<Exercise> addExerciseToSession(
    int sessionId,
    int exerciseTemplateId,
  ) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) {
      throw Exception(_unauthenticated);
    }
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final localSession = await _resolveOwnedSessionOrThrow(
      db,
      sessionId,
      token,
    );
    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    if (_connectivity.isOnline && localSession.serverId != null) {
      try {
        final data = await _apiService.post<Map<String, dynamic>>(
          ApiConfig.sessionExercises(localSession.serverId!),
          data: {'exerciseTemplateId': exerciseTemplateId},
          sessionContext: context,
        );
        final apiExercise = Exercise.fromJson(data);

        if (!_sessionEpoch.isCurrent(token)) {
          throw const SessionStaleException();
        }
        if (!await _isSessionOwnedByLocalId(db, localSession.localId, token)) {
          throw const SessionStaleException();
        }

        await _runTestHook(beforeWriteTxnForTesting);
        await db.writeTxn(() async {
          await _runTestHook(insideWriteTxnForTesting);
          if (!_sessionEpoch.isCurrent(token)) {
            throw const SessionStaleException();
          }

          // Freshly reacquire the session by its stable local identity and
          // re-verify ownership as the first operation inside the
          // transaction - the pre-transaction check above (and the
          // `localSession` object it used) proves nothing about the state
          // at the moment this write actually happens, only about the
          // moment it was read. Never reuse that stale object as proof of
          // ownership here.
          final owningSession = await db.localSessions.get(
            localSession.localId,
          );
          if (owningSession == null || owningSession.userId != token.userId) {
            throw const SessionStaleException();
          }

          final localExercise = ModelMapper.exerciseToLocal(
            apiExercise,
            sessionLocalId: owningSession.localId,
            isSynced: true,
          );
          await db.localExercises.put(localExercise);
        });

        return apiExercise;
      } on SessionStaleException {
        // Fall through to offline creation below.
      } on RequestCancelledException {
        // Fall through to offline creation below.
      } catch (e) {
        debugPrint('⚠️ Add exercise API failed, creating locally: $e');
      }
    }

    // Create exercise locally (offline, API failed, or session no longer current)
    String exerciseName = 'Exercise';
    try {
      final templates =
          await db.collection<LocalExerciseTemplate>().where().findAll();
      final template = templates.firstWhere(
        (t) => t.serverId == exerciseTemplateId,
        orElse: () => templates.first,
      );
      exerciseName = template.name;
    } catch (e) {
      debugPrint('⚠️ Could not find exercise template $exerciseTemplateId: $e');
    }

    if (!_sessionEpoch.isCurrent(token)) {
      throw Exception(_unauthenticated);
    }

    int localId = 0;

    await _runTestHook(beforeWriteTxnForTesting);
    await db.writeTxn(() async {
      await _runTestHook(insideWriteTxnForTesting);
      if (!_sessionEpoch.isCurrent(token)) return;

      final current = await db.localSessions.get(localSession.localId);
      if (current == null || current.userId != token.userId) return;

      final tempExercise = Exercise(
        id: 0,
        sessionId: sessionId,
        name: exerciseName,
        exerciseTemplateId: exerciseTemplateId,
        duration: null,
        restTime: null,
        notes: null,
        exerciseSets: [],
      );

      final localExercise = ModelMapper.exerciseToLocal(
        tempExercise,
        sessionLocalId: localSession.localId,
        isSynced: false,
      );
      localId = await db.localExercises.put(localExercise);
    });

    final newExercise = Exercise(
      // Offline exercise: collision-free public id (`-localId`), matching
      // ModelMapper.localToExercise.
      id: ModelMapper.publicRowId(serverId: null, localId: localId),
      sessionId: sessionId,
      name: exerciseName,
      exerciseTemplateId: exerciseTemplateId,
      duration: null,
      restTime: null,
      notes: null,
      exerciseSets: [],
    );

    debugPrint(
      '➕ Created exercise "$exerciseName" locally (offline), id=-$localId, will sync later',
    );
    return newExercise;
  }
}
