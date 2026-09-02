import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/services/user_session_epoch.dart';
import '../data/models/session.dart';
import '../data/models/program_workout.dart';
import '../data/repositories/session_repository.dart';
import '../data/services/session_request_exceptions.dart';
import '../core/services/connectivity_service.dart';

/// Provider for sessions (workouts) management.
///
/// ## Repository boundary
///
/// `SessionRepository` already owns all HTTP/session binding, all
/// user-scoped local reads/writes, transaction-boundary ownership rechecks,
/// local-vs-server id disambiguation and conflict/write ordering. This
/// provider adds nothing to that layer - it only protects its OWN
/// publication boundary: it never lets a repository result, error, `finally`
/// cleanup, or Isar-watch stream event that began under user A land on the
/// state user B now sees through this same app-scoped instance, and it
/// orders competing same-session requests so an older one can never overwrite
/// a newer one.
///
/// ## Session ownership
///
/// App-scoped provider (a single instance created with `previous ??` outlives
/// logout/login - see main.dart). Every async method captures
/// `_sessionEpoch.capture()` before its first `await`, claims its operation
/// generation, and rechecks ownership after every `await` (success, `catch`
/// AND `finally` independently) before touching `_sessions`, the loading /
/// error state, the watch subscription, or `notifyListeners()`. A `null`
/// capture (logged out) returns each method's established empty/false/null
/// result without starting work.
///
/// The provider dispatches NO HTTP itself - every network call goes through
/// `SessionRepository`, which is already fully bound - so `SessionsProvider`
/// takes only the shared [UserSessionEpoch], never a
/// `SessionRequestCoordinator`, `AuthService`, `ApiService`, `Dio` or
/// `CancelToken`. The authenticated user for building `Session` models and
/// for the Isar watch is `token.userId`, captured once at operation entry -
/// never a later live `AuthService.getUserId()` re-read.
///
/// The repository's `getSession` / `createSession` / mutation methods throw a
/// plain `Exception('User not authenticated')` (not a typed lifecycle
/// exception) when their own capture is null or their mid-flight recheck
/// fails; the provider's `owns()` guard catches the same session change, so a
/// stale continuation publishes nothing regardless. The typed
/// [SessionStaleException] / [RequestCancelledException] are still intercepted
/// ahead of the generic `catch` where a repository path does propagate them.
///
/// ## Same-session ordering
///
/// - [_listGen] - the session list. Bumped by [loadSessions] entry AND by
///   every successful mutation, so a slower in-flight list load can neither
///   resurrect a session a newer mutation removed nor overwrite a newer
///   mutation's edit.
/// - [_loadGen] - bumped only by [loadSessions] entry / [_invalidateGenerations];
///   guards the `_isLoading` reset in [loadSessions]'s `finally` so a newer
///   same-session mutation bumping [_listGen] cannot strand the spinner.
/// - [_detailGen] - orders one [getSessionById] against another (same axis);
///   the result is returned to the caller, never stored, and is gated by a
///   final [UserSessionEpoch.isCurrent] check.
/// - [_sessionMutationGens] - keyed by session id, SHARED by [deleteSession],
///   [archiveSession], [startPlannedWorkout], [updateWorkoutDate] and
///   [updateSessionDateForProgramWorkout]: a stale mutation to a session
///   writes nothing (not its list edit, not its error); a mutation to a
///   DIFFERENT session is never superseded by it; an older update can never
///   resurrect a session a newer delete removed nor undo a newer
///   archive/date/start.
/// - [_createGen] - a monotonic supersede-chain for the create/start family
///   ([startNewWorkout], [createPlannedWorkout], [startProgramWorkout]);
///   [_batchGen] is the separate supersede-chain for
///   [createRecurringPlannedWorkouts]. A superseded create's direct
///   `_sessions.insert` is skipped, but the row it wrote to Isar still
///   surfaces through the authoritative watch, so no session is lost.
/// - [_errorGen] - a single global error-publication generation: an error
///   write only lands if the writing op is still the newest error-slot
///   claimant AND passes its own axis `owns()`.
///
/// No global serialization: each method uses only its own per-id / per-axis
/// generation, so unrelated sessions run fully concurrently. No list index is
/// ever retained across an `await` - every `indexWhere` is a fresh lookup
/// immediately before use.
///
/// ## User-bound Isar watch
///
/// [loadSessions] installs a `SessionRepository.watchSessions(userId)`
/// subscription via [_installWatch], bound to four things: the captured
/// [UserSessionToken], the captured `userId` (== `token.userId`), a
/// monotonic [_watchGen], and the exact [StreamSubscription] instance. Every
/// stream data/error/done callback verifies ALL of: not [_disposed], session
/// still current for the captured token, [_watchGen] unchanged, and the
/// callback's subscription is `identical` to [_sessionsStreamSubscription] -
/// so an A-session event can never publish into B and never recaptures a
/// fresh token. The Isar watch is authoritative for the list once installed;
/// [loadSessions] only publishes its own initial `getSessions()` snapshot if
/// no newer watch snapshot ([_streamPublishSeq]) has landed since that load
/// began, so an older load result never overwrites a fresher stream emission.
///
/// [_installWatch] bumps [_watchGen], detaches [_sessionsStreamSubscription]
/// BEFORE cancelling the previous subscription (so a late callback from the
/// old one fails its `identical` check), and is only ever reached from
/// [loadSessions] under a passing `owns()`, or from
/// [_rearmWatchAfterMutation] under a passing mutation `owns()` - so an older
/// load or a superseded mutation can never cancel or replace a newer watch.
///
/// Every owned per-session / create / batch mutation, once its repository
/// write has committed, calls [_rearmWatchAfterMutation]: Isar's
/// `Query.watch()` re-queries on change, but the result crosses two
/// `asyncMap` stages before it publishes, so a `findAll()` taken before the
/// mutation can still be delivered after the mutation's direct `_sessions`
/// edit. Re-arming swaps in a fresh subscription whose first snapshot is a
/// `findAll()` guaranteed to run after the commit; the old subscription's
/// in-flight stale emissions then fail [_watchCallbackOwns]. The direct edit
/// is retained for instant UI until that first authoritative snapshot lands.
///
/// [clear] / [dispose] bump [_watchGen] (and every other generation) FIRST,
/// then detach and cancel the current subscription, so an in-flight
/// [loadSessions] fails its `owns()` check before it can re-install, and no
/// stream event can repopulate afterward. [dispose] additionally sets
/// [_disposed] synchronously as its first statement.
///
/// ## Connectivity
///
/// The connectivity-restored callback captures a fresh token per event and
/// no-ops entirely if there is no active session or the provider is
/// disposed, and only refreshes while no load is already running. The
/// refresh it triggers is [loadSessions] itself, bound by the same
/// [_listGen] / [_watchGen] ordering - it can never install a watch for an
/// older user, stack a duplicate watch, or repopulate after [clear].
class SessionsProvider extends ChangeNotifier {
  final SessionRepository _sessionRepository;
  final UserSessionEpoch _sessionEpoch;
  final ConnectivityService _connectivity;

  final List<Session> _sessions = [];
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<List<Session>>? _sessionsStreamSubscription;

  // Set synchronously as the first statement of dispose(); every watch
  // callback checks it before touching state or calling notifyListeners().
  bool _disposed = false;

  // Monotonic per-resource generations - see the class doc comment.
  int _listGen = 0;
  int _loadGen = 0;
  int _detailGen = 0;
  int _createGen = 0;
  int _batchGen = 0;
  int _errorGen = 0;

  // Monotonic identity of the "current" Isar watch. Every subscription
  // captures the value at creation; every callback closes over it and is
  // ignored on mismatch. Bumped by [_installWatch] and [_invalidateGenerations].
  int _watchGen = 0;

  // The user the currently-installed watch is filtering for. Set by
  // [_installWatch], cleared by [clear] / [dispose] / an owned watch `onDone`.
  int? _watchedUserId;

  // Incremented every time the watch callback publishes into [_sessions].
  // [loadSessions] captures it at entry and only publishes its own
  // `getSessions()` snapshot if it is unchanged when the load resolves, so an
  // older load result never overwrites a fresher stream emission.
  int _streamPublishSeq = 0;

  // Per-session mutation generations - see the class doc comment.
  final Map<int, int> _sessionMutationGens = {};

  /// Test-only seam: invoked with the `Future` returned by the
  /// connectivity-restored listener's own fire-and-forget call to
  /// [loadSessions], so a test can await that real ownership path to
  /// completion deterministically instead of pumping the event loop. Null in
  /// production; setting it never changes control flow or performance.
  @visibleForTesting
  void Function(Future<void> refresh)? onConnectivityRefreshForTesting;

  SessionsProvider(
    this._sessionRepository,
    this._sessionEpoch,
    this._connectivity,
  ) {
    // Don't auto-load here - sessions load after login. Listen for
    // connectivity changes and refresh when going online, but only for an
    // active session and only when no load is already running.
    _connectivitySubscription = _connectivity.connectivityStream.listen((
      isOnline,
    ) {
      if (_disposed) return;
      final token = _sessionEpoch.capture();
      if (token == null) return;
      if (isOnline && !_isLoading) {
        debugPrint('📡 Connection restored - refreshing sessions');
        final refresh = loadSessions(showLoading: false);
        onConnectivityRefreshForTesting?.call(refresh);
      }
    });
  }

  // Getters
  List<Session> get sessions => _sessions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// The user the currently-installed Isar watch filters for, or `null` when
  /// no watch is installed. Exposed for tests/diagnostics only.
  @visibleForTesting
  int? get watchedUserId => _watchedUserId;

  int _bumpSessionMutationGen(int id) {
    final next = (_sessionMutationGens[id] ?? 0) + 1;
    _sessionMutationGens[id] = next;
    return next;
  }

  /// Invalidate every request / mutation / watch generation so no in-flight
  /// continuation or stream callback can publish after this returns.
  void _invalidateGenerations() {
    _listGen++;
    _loadGen++;
    _detailGen++;
    _createGen++;
    _batchGen++;
    _errorGen++;
    _watchGen++;
    _sessionMutationGens.updateAll((_, v) => v + 1);
  }

  // ---------------------------------------------------------------------------
  // Session list + Isar watch
  // ---------------------------------------------------------------------------

  /// Load all sessions for the current user and (re)install the reactive
  /// Isar watch bound to that user.
  Future<void> loadSessions({
    bool showLoading = true,
    bool waitForSync = false,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) {
      debugPrint('⚠️ SessionsProvider.loadSessions: no active session');
      return;
    }
    final userId = token.userId;
    final gen = ++_listGen;
    final loadGen = ++_loadGen;
    final errorGen = ++_errorGen;
    final seqAtEntry = _streamPublishSeq;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _listGen;

    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final sessionList = await _sessionRepository.getSessions(
        waitForSync: waitForSync,
      );
      if (!owns()) return;

      // The Isar watch is authoritative once installed. Only publish this
      // initial snapshot if no newer watch snapshot has landed since the load
      // began - an older getSessions() result must not overwrite a fresher
      // stream emission.
      if (_streamPublishSeq == seqAtEntry) {
        _sessions
          ..clear()
          ..addAll(sessionList..sort((a, b) => b.date.compareTo(a.date)));
        debugPrint('✅ Loaded ${_sessions.length} sessions into provider');
      }

      _installWatch(token, userId);
    } on SessionStaleException {
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return;
      _errorMessage =
          'Failed to load sessions: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Load sessions error: $e');
    } finally {
      if (_sessionEpoch.isCurrent(token) && loadGen == _loadGen) {
        if (showLoading) _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Installs the reactive watch for [userId], bound to [token] and a fresh
  /// [_watchGen]. Only ever called from [loadSessions] under a passing
  /// `owns()`, so an older load can never reach here.
  void _installWatch(UserSessionToken token, int userId) {
    final watchGen = ++_watchGen;

    // Detach the shared field BEFORE cancelling the previous subscription, so
    // any already-queued callback from the old one fails its `identical`
    // check immediately.
    final previous = _sessionsStreamSubscription;
    _sessionsStreamSubscription = null;

    late final StreamSubscription<List<Session>> sub;
    sub = _sessionRepository
        .watchSessions(userId)
        .listen(
          (updated) => _onWatchData(updated, token, watchGen, sub),
          onError:
              (Object error, StackTrace _) =>
                  _onWatchError(error, token, watchGen, sub),
          onDone: () => _onWatchDone(watchGen, sub),
          cancelOnError: false,
        );
    _sessionsStreamSubscription = sub;
    _watchedUserId = userId;

    // Cancel exactly the superseded instance. It is already detached, so a
    // late callback from it is inert regardless of when the cancel completes.
    // This runs on every owned mutation now (via [_rearmWatchAfterMutation]),
    // so guard it the same way [clear] does.
    try {
      previous?.cancel();
    } catch (e) {
      debugPrint('⚠️ SessionsProvider: stream cancel error (ignored): $e');
    }
  }

  bool _watchCallbackOwns(
    UserSessionToken token,
    int watchGen,
    StreamSubscription<List<Session>> sub,
  ) {
    if (_disposed) return false;
    if (!_sessionEpoch.isCurrent(token)) return false;
    if (watchGen != _watchGen) return false;
    if (!identical(sub, _sessionsStreamSubscription)) return false;
    // The watch must still be filtering for exactly the user this callback
    // was bound to (redundant with the checks above, kept explicit per the
    // user-bound-watch contract).
    if (_watchedUserId != token.userId) return false;
    return true;
  }

  void _onWatchData(
    List<Session> updated,
    UserSessionToken token,
    int watchGen,
    StreamSubscription<List<Session>> sub,
  ) {
    if (!_watchCallbackOwns(token, watchGen, sub)) return;
    _sessions
      ..clear()
      ..addAll(updated); // repository already sorts by date desc
    _streamPublishSeq++;
    notifyListeners();
    debugPrint('🔄 Sessions auto-updated from background sync');
  }

  void _onWatchError(
    Object error,
    UserSessionToken token,
    int watchGen,
    StreamSubscription<List<Session>> sub,
  ) {
    if (!_watchCallbackOwns(token, watchGen, sub)) return;
    debugPrint('⚠️ Sessions stream error: $error');
    // Keep existing sessions - do not publish on error.
  }

  void _onWatchDone(int watchGen, StreamSubscription<List<Session>> sub) {
    if (watchGen == _watchGen && identical(sub, _sessionsStreamSubscription)) {
      _sessionsStreamSubscription = null;
      _watchedUserId = null;
    }
  }

  /// Re-arm the reactive watch after an owned mutation has committed, so the
  /// next authoritative snapshot is a fresh `findAll()` taken AFTER that
  /// commit.
  ///
  /// Isar's `Query.watch()` is `watchLazy().asyncMap((_) => findAll())`, and
  /// [SessionRepository.watchSessions] adds a second `asyncMap` that hydrates
  /// each row's exercises and sorts. A change signal does trigger a fresh
  /// `findAll()`, but that result then travels through both `asyncMap` stages
  /// before it reaches [_onWatchData]. A `findAll()` that ran BEFORE this
  /// mutation committed can therefore still be delivered AFTER the mutation's
  /// repository `Future` resolved and its direct `_sessions` edit published -
  /// resurrecting a deleted / archived row or reverting an updated
  /// date / status. Cancelling the old subscription does not retract an
  /// emission already in flight between those stages.
  ///
  /// Installing a fresh subscription (via [_installWatch]) bumps [_watchGen]
  /// and swaps [_sessionsStreamSubscription], so every stale in-flight
  /// emission from the old subscription now fails [_watchCallbackOwns]; and
  /// the new subscription's `fireImmediately` snapshot is a `findAll()` that
  /// necessarily runs after this commit, so it reflects the mutation. The
  /// immediate direct edit is kept for instant UI and is superseded by that
  /// first authoritative snapshot.
  ///
  /// Guarded by the caller's own `owns()` so a superseded mutation can never
  /// rotate or cancel a newer mutation's / load's watch handoff, and a no-op
  /// when no watch is installed (a mutation must not start one).
  void _rearmWatchAfterMutation(bool Function() owns, UserSessionToken token) {
    if (_disposed) return;
    // Every caller invokes this synchronously right after a passing `owns()`
    // with no `await` in between, so this re-check only matters if a future
    // call site breaks that contract - keep it.
    if (!owns()) return;
    if (_sessionsStreamSubscription == null) return;
    if (!_sessionEpoch.isCurrent(token)) return;
    if (_watchedUserId != token.userId) return;
    _installWatch(token, token.userId);
  }

  // ---------------------------------------------------------------------------
  // Detail
  // ---------------------------------------------------------------------------

  /// Get session by ID. Returned directly to the caller; `null` when logged
  /// out or when the session changed before the result resolved.
  Future<Session?> getSessionById(int sessionId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final gen = ++_detailGen;
    try {
      final session = await _sessionRepository.getSession(sessionId);
      return _sessionEpoch.isCurrent(token) && gen == _detailGen
          ? session
          : null;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      // A session change surfaces from the repository as
      // Exception('User not authenticated'); swallow it as a stale outcome.
      // A genuine not-found / error under a still-current session still
      // propagates to the caller unchanged.
      if (!_sessionEpoch.isCurrent(token)) return null;
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Per-session mutations
  // ---------------------------------------------------------------------------

  /// Delete a session by ID
  Future<bool> deleteSession(int sessionId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpSessionMutationGen(sessionId);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) &&
        _sessionMutationGens[sessionId] == gen;

    try {
      final success = await _sessionRepository.deleteSession(sessionId);
      if (!owns()) return false;
      if (success) {
        _rearmWatchAfterMutation(owns, token);
        _sessions.removeWhere((s) => s.id == sessionId);
        _listGen++;
        notifyListeners();
        return true;
      }
      if (errorGen == _errorGen) {
        _errorMessage = 'Failed to delete session';
        notifyListeners();
      }
      return false;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to delete session: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Delete session error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Archive a session (hides from main list but keeps for program tracking)
  Future<bool> archiveSession(int sessionId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpSessionMutationGen(sessionId);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) &&
        _sessionMutationGens[sessionId] == gen;

    try {
      final success = await _sessionRepository.archiveSession(sessionId);
      if (!owns()) return false;
      if (success) {
        _rearmWatchAfterMutation(owns, token);
        _sessions.removeWhere((s) => s.id == sessionId);
        _listGen++;
        notifyListeners();
        return true;
      }
      if (errorGen == _errorGen) {
        _errorMessage = 'Failed to archive session';
        notifyListeners();
      }
      return false;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to archive session: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Archive session error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Start a planned workout (change status from 'planned' to 'in_progress')
  Future<bool> startPlannedWorkout(int sessionId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpSessionMutationGen(sessionId);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) &&
        _sessionMutationGens[sessionId] == gen;

    try {
      final updatedSession = await _sessionRepository.updateSessionStatus(
        sessionId,
        'in_progress',
      );
      if (!owns()) return false;
      _rearmWatchAfterMutation(owns, token);

      final index = _sessions.indexWhere((s) => s.id == sessionId);
      if (index != -1) {
        _sessions[index] = updatedSession;
      }
      _listGen++;
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to start planned workout: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Start planned workout error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Update workout date (used when starting a future planned workout early)
  Future<bool> updateWorkoutDate(int sessionId, DateTime newDate) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpSessionMutationGen(sessionId);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) &&
        _sessionMutationGens[sessionId] == gen;

    try {
      await _sessionRepository.updateWorkoutDate(sessionId, newDate);
      if (!owns()) return false;
      _rearmWatchAfterMutation(owns, token);

      final index = _sessions.indexWhere((s) => s.id == sessionId);
      if (index != -1) {
        _sessions[index] = _sessions[index].copyWith(date: newDate);
      }
      _listGen++;
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to update workout date: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Update workout date error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Update session date when its program workout is moved to a different day.
  Future<bool> updateSessionDateForProgramWorkout({
    required int programWorkoutId,
    required DateTime newScheduledDate,
  }) async {
    final token = _sessionEpoch.capture();
    // Logged out: there is definitionally no linked session to update, which
    // is the method's established "nothing to do" success result.
    if (token == null) return true;

    // Resolve the linked session id BEFORE the first await (stable id, never
    // an index held across an await).
    final linkedSession = _sessions.firstWhere(
      (s) => s.programWorkoutId == programWorkoutId && s.status != 'completed',
      orElse:
          () => Session(
            id: -1,
            userId: 0,
            date: DateTime.now(),
            type: '',
            status: '',
          ),
    );
    if (linkedSession.id == -1) {
      debugPrint(
        '📅 No active session found for program workout $programWorkoutId',
      );
      return true;
    }
    final sessionId = linkedSession.id;
    final gen = _bumpSessionMutationGen(sessionId);

    bool owns() =>
        _sessionEpoch.isCurrent(token) &&
        _sessionMutationGens[sessionId] == gen;

    final newDate = DateTime(
      newScheduledDate.year,
      newScheduledDate.month,
      newScheduledDate.day,
    );

    try {
      await _sessionRepository.updateWorkoutDate(sessionId, newDate);
      if (!owns()) return false;
      _rearmWatchAfterMutation(owns, token);

      final index = _sessions.indexWhere((s) => s.id == sessionId);
      if (index != -1) {
        _sessions[index] = _sessions[index].copyWith(date: newDate);
        _listGen++;
        notifyListeners();
      }
      debugPrint(
        '📅 Updated session $sessionId date to $newDate (moved program workout $programWorkoutId)',
      );
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      debugPrint(
        'Failed to update session date for program workout $programWorkoutId: $e',
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Create / start
  // ---------------------------------------------------------------------------

  /// Start a new workout session
  Future<Session?> startNewWorkout({String? name}) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final gen = ++_createGen;
    final errorGen = ++_errorGen;
    final userId = token.userId;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _createGen;

    try {
      final now = DateTime.now();
      final newSession = Session(
        id: 0,
        userId: userId,
        date: DateTime(now.year, now.month, now.day),
        type: 'Workout',
        status: 'draft',
        notes: '',
        name: name,
      );

      final createdSession = await _sessionRepository.createSession(newSession);
      if (!owns()) return null;
      _rearmWatchAfterMutation(owns, token);

      _sessions.insert(0, createdSession);
      _listGen++;
      notifyListeners();
      return createdSession;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to start workout: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Start workout error: $e');
        notifyListeners();
      }
      return null;
    }
  }

  /// Create a single planned workout for a future date
  Future<Session?> createPlannedWorkout({
    required String name,
    required DateTime scheduledDate,
    String? type,
    String? notes,
    int? estimatedDuration,
    List<int>? exerciseTemplateIds,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final gen = ++_createGen;
    final errorGen = ++_errorGen;
    final userId = token.userId;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _createGen;

    try {
      final dateOnly = DateTime(
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
      );

      final newSession = Session(
        id: 0,
        userId: userId,
        date: dateOnly,
        type: type ?? 'Workout',
        status: 'planned',
        notes: notes ?? '',
        name: name,
        duration: estimatedDuration,
      );

      final createdSession = await _sessionRepository.createSession(newSession);
      if (!owns()) return null;

      if (exerciseTemplateIds != null && exerciseTemplateIds.isNotEmpty) {
        for (final templateId in exerciseTemplateIds) {
          if (!owns()) return null;
          try {
            await _sessionRepository.addExerciseToSession(
              createdSession.id,
              templateId,
            );
            debugPrint(
              '✅ Added exercise template $templateId to planned workout',
            );
          } catch (e) {
            debugPrint('⚠️ Failed to add exercise template $templateId: $e');
          }
        }
        if (!owns()) return null;
        final updatedSession = await _sessionRepository.getSession(
          createdSession.id,
        );
        if (!owns()) return null;
        _rearmWatchAfterMutation(owns, token);
        _sessions.insert(0, updatedSession);
        _listGen++;
        notifyListeners();
        return updatedSession;
      }

      _rearmWatchAfterMutation(owns, token);
      _sessions.insert(0, createdSession);
      _listGen++;
      notifyListeners();
      return createdSession;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to create planned workout: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Create planned workout error: $e');
        notifyListeners();
      }
      return null;
    }
  }

  /// Create multiple recurring planned workouts
  Future<List<Session>> createRecurringPlannedWorkouts({
    required String name,
    required DateTime startDate,
    required String frequency,
    List<int>? daysOfWeek,
    int? intervalDays,
    int? occurrences,
    DateTime? endDate,
    String? type,
    String? notes,
    int? estimatedDuration,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return [];
    final gen = ++_batchGen;
    final errorGen = ++_errorGen;
    final userId = token.userId;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _batchGen;

    try {
      final dates = _calculateRecurringDates(
        startDate: startDate,
        frequency: frequency,
        daysOfWeek: daysOfWeek,
        intervalDays: intervalDays,
        occurrences: occurrences,
        endDate: endDate,
      );
      final limitedDates = dates.take(52).toList();

      final createdSessions = <Session>[];
      for (final date in limitedDates) {
        if (!owns()) break;
        final dateOnly = DateTime(date.year, date.month, date.day);
        final session = Session(
          id: 0,
          userId: userId,
          date: dateOnly,
          type: type ?? 'Workout',
          status: 'planned',
          notes: notes ?? '',
          name: name,
          duration: estimatedDuration,
        );
        createdSessions.add(await _sessionRepository.createSession(session));
      }

      if (!owns()) return [];

      if (createdSessions.isNotEmpty) {
        _rearmWatchAfterMutation(owns, token);
      }
      for (final s in createdSessions) {
        _sessions.insert(0, s);
      }
      if (createdSessions.isNotEmpty) {
        _listGen++;
        notifyListeners();
      }
      return createdSessions;
    } on SessionStaleException {
      return [];
    } on RequestCancelledException {
      return [];
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to create recurring workouts: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Create recurring workouts error: $e');
        notifyListeners();
      }
      return [];
    }
  }

  /// Create a session from a program workout
  Future<Session?> startProgramWorkout(
    int programWorkoutId,
    ProgramWorkout programWorkout,
    DateTime programStartDate,
    int programId,
  ) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final gen = ++_createGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _createGen;

    _errorMessage = null;

    try {
      final session = await _sessionRepository.createSessionFromProgramWorkout(
        programWorkoutId,
        programWorkout,
        programStartDate,
        programId,
      );
      if (!owns()) return null;
      _rearmWatchAfterMutation(owns, token);

      _sessions.insert(0, session);
      _listGen++;
      notifyListeners();
      debugPrint('✅ Created session from program workout: ${session.id}');
      return session;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to start program workout: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Start program workout error: $e');
        notifyListeners();
      }
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Sync helpers / derived reads
  // ---------------------------------------------------------------------------

  /// Refresh sessions (pull-to-refresh) - no loading indicator for smooth UX
  Future<void> refresh() async {
    await loadSessions(showLoading: false);
  }

  /// Get sessions from a specific program
  List<Session> getSessionsFromProgram(int programId) {
    return _sessions.where((s) => s.programId == programId).toList();
  }

  /// Get standalone sessions (not from programs)
  List<Session> getStandaloneSessions() {
    return _sessions.where((s) => s.programId == null).toList();
  }

  /// Clear error message
  void clearError() {
    _errorGen++;
    _errorMessage = null;
    notifyListeners();
  }

  /// Calculate dates for recurring workouts
  List<DateTime> _calculateRecurringDates({
    required DateTime startDate,
    required String frequency,
    List<int>? daysOfWeek,
    int? intervalDays,
    int? occurrences,
    DateTime? endDate,
  }) {
    final dates = <DateTime>[];
    var currentDate = startDate;
    final maxDate = endDate ?? startDate.add(const Duration(days: 365));

    switch (frequency) {
      case 'daily':
        while (dates.length < (occurrences ?? 365) &&
            currentDate.isBefore(maxDate.add(const Duration(days: 1)))) {
          dates.add(currentDate);
          currentDate = currentDate.add(const Duration(days: 1));
        }
        break;

      case 'weekly':
        if (daysOfWeek == null || daysOfWeek.isEmpty) break;

        while (!daysOfWeek.contains(currentDate.weekday) &&
            currentDate.isBefore(maxDate.add(const Duration(days: 1)))) {
          currentDate = currentDate.add(const Duration(days: 1));
        }

        while (dates.length < (occurrences ?? 365) &&
            currentDate.isBefore(maxDate.add(const Duration(days: 1)))) {
          if (daysOfWeek.contains(currentDate.weekday)) {
            dates.add(currentDate);
          }
          currentDate = currentDate.add(const Duration(days: 1));
        }
        break;

      case 'custom':
        final interval = intervalDays ?? 1;
        while (dates.length < (occurrences ?? 365) &&
            currentDate.isBefore(maxDate.add(const Duration(days: 1)))) {
          dates.add(currentDate);
          currentDate = currentDate.add(Duration(days: interval));
        }
        break;
    }

    return dates;
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Clear all sessions data (called on logout via [SessionCleanupCoordinator]).
  ///
  /// Every generation - including [_watchGen] - is bumped BEFORE any state is
  /// reset, so an in-flight [loadSessions] fails its `owns()` check before it
  /// can re-install a watch, and no stream callback can repopulate afterward.
  /// [_sessions] is emptied in place (not reassigned), so a caller holding a
  /// reference via the [sessions] getter also observes the reset.
  void clear() {
    // A logout pass that somehow runs after dispose() must not reach
    // notifyListeners(); dispose() already invalidated every generation and
    // cancelled both subscriptions, so there is nothing left to do.
    if (_disposed) return;

    _invalidateGenerations();

    // Detach the shared field before cancelling, so a late callback from the
    // old subscription fails its `identical` check.
    final old = _sessionsStreamSubscription;
    _sessionsStreamSubscription = null;
    _watchedUserId = null;

    _sessions.clear();
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();

    try {
      old?.cancel();
    } catch (e) {
      debugPrint('⚠️ SessionsProvider: stream cancel error (ignored): $e');
    }
    debugPrint('🧹 SessionsProvider cleared');
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateGenerations();

    _connectivitySubscription?.cancel();

    final sub = _sessionsStreamSubscription;
    _sessionsStreamSubscription = null;
    _watchedUserId = null;
    sub?.cancel();

    super.dispose();
  }
}
