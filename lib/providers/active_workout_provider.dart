import 'dart:async';
import 'package:flutter/widgets.dart';
import '../data/models/session.dart';
import '../data/models/exercise.dart';
import '../data/repositories/session_repository.dart';
import '../data/services/session_request_exceptions.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/health_service.dart';
import '../core/services/calories_service.dart';
import '../core/services/user_session_epoch.dart';

/// Provider for active workout session with timer
/// Replaces ActiveWorkoutViewModel from MAUI app
///
/// ## Session ownership
///
/// App-scoped provider: a single instance created with `previous ??` in
/// `main.dart` outlives logout/login, so a continuation, timer callback, or
/// lifecycle callback started under user A must never publish into the state
/// user B now sees through this same instance.
///
/// Every async method captures `_sessionEpoch.capture()` before its first
/// `await`; a `null` capture (logged out) returns immediately using the
/// method's existing return convention without starting work. After every
/// `await` - in success, `catch`, and `finally` - it rechecks
/// `_sessionEpoch.isCurrent(token)` AND its operation generation AND
/// `!_disposed` before touching `_currentSession`, the exercise list,
/// elapsed/rest time, any flag, the error, a timer, or calling
/// `notifyListeners()`. A stale continuation is dropped silently -
/// [SessionStaleException] / [RequestCancelledException] never become a
/// user-B error.
///
/// ## Same-session ordering
///
/// - [_requestGeneration] - identifies the newest "acquire the active
///   workout" operation ([loadSession], [createWorkoutFromAI],
///   [startWorkout]). An A->B->A navigation race resolves by generation, not
///   by workout-id equality; a superseded acquire publishes nothing.
/// - [_editGeneration] - bumped by every in-place edit of the current workout
///   ([pauseTimer], [resumeTimer], [updateWorkoutName], [finishWorkout]) AND
///   by [loadSession] / [createWorkoutFromAI]. A newer edit that bumps it
///   supersedes an older edit's - and an in-flight load's - RESULT; a newer
///   load supersedes an in-flight edit. Purely a result-content clock.
/// - [_loadingClaim] - governs the shared `_isLoading` indicator ONLY,
///   independently of result ownership, so a load whose result was superseded
///   can still release its own spinner without a stale finally ever clearing a
///   newer operation's / user B's spinner. See the field doc.
/// - [addExercise] / [createWorkoutFromAI] appends are NOT given a per-append
///   generation: two rapid adds on the same workout must both land. They rely
///   on `_requestGeneration` (a replaced/cleared workout supersedes them) plus
///   the `_currentSession.id` check.
/// - [_timerGeneration] - see [_startTimer].
/// - [_lifecycleGeneration] - invalidates lifecycle-started async work.
///
/// [clear] and [dispose] bump every generation BEFORE resetting state, so an
/// in-flight continuation, tick, or lifecycle callback cannot repopulate or
/// restart anything after they return - even when [clear] runs without a
/// preceding `UserSessionEpoch.invalidate()` (the "delete the session I'm
/// looking at" path from the sessions list).
///
/// This provider performs no direct HTTP/Dio/AuthService/Isar access; all
/// user-owned reads and writes go through [SessionRepository], which enforces
/// its own request-context ownership.
class ActiveWorkoutProvider extends ChangeNotifier with WidgetsBindingObserver {
  final SessionRepository _sessionRepository;

  /// Shared app-wide session-identity service - the SAME instance handed to
  /// `AuthProvider`, `SessionRepository`, `SyncService`, `RunningProvider`,
  /// etc. (see `main.dart`). Only `AuthProvider` calls activate()/invalidate();
  /// this provider only ever reads it via capture()/isCurrent().
  final UserSessionEpoch _sessionEpoch;

  final ConnectivityService? _connectivity;

  // Injectable UTC clock, used only for lifecycle elapsed-time
  // recalculation so tests can control elapsed "time spent suspended"
  // deterministically. Defaults to the real clock in production.
  final DateTime Function() _nowUtc;

  Session? _currentSession;
  bool _isLoading = false;
  String? _errorMessage;

  // Timer state
  Timer? _timer;
  Duration _elapsedTime = Duration.zero;
  bool _isTimerRunning = false;

  // User weight for calories calculation (set from ProfileProvider)
  double? _userWeightKg;

  // Connectivity subscription
  StreamSubscription<bool>? _connectivitySubscription;

  // ===== Ownership / ordering generations =====

  /// Set synchronously as the first line of [dispose]; every async
  /// continuation, timer callback, and lifecycle callback checks it before
  /// touching state or notifying, so nothing publishes after disposal.
  bool _disposed = false;

  /// Newest "acquire/replace the active workout" operation. Bumped by
  /// [loadSession], [createWorkoutFromAI], [startWorkout], and
  /// [_invalidateGenerations].
  int _requestGeneration = 0;

  /// Newest in-place edit of the current workout. Bumped by [pauseTimer],
  /// [resumeTimer], [updateWorkoutName], [finishWorkout], and
  /// [_invalidateGenerations].
  int _editGeneration = 0;

  /// Independent claim on the shared `_isLoading` indicator, SEPARATE from
  /// result ownership. Bumped by every operation that sets `_isLoading = true`
  /// ([loadSession] with `showLoading`, [createWorkoutFromAI]) and by
  /// [_invalidateGenerations]. An operation's `finally` may clear `_isLoading`
  /// only while it (a) is still under the session it captured
  /// (`_sessionEpoch.isCurrent(token)`) AND (b) still owns this claim. So a
  /// load whose RESULT was superseded by a newer same-session edit can still
  /// release its own spinner, but a continuation captured under user A does
  /// nothing at all once the epoch belongs to user B - it never touches
  /// `_isLoading` or notifies, independently of whether logout cleanup has run
  /// yet. A newer loading operation also bumps this claim, so a stale finally
  /// can never clear a newer operation's spinner.
  int _loadingClaim = 0;

  /// See [_startTimer] / [_stopTimer] / [_stopTimerIfOwned].
  int _timerGeneration = 0;

  /// Invalidates any async work started from a lifecycle callback. Bumped by
  /// [_invalidateGenerations].
  int _lifecycleGeneration = 0;

  ActiveWorkoutProvider(
    this._sessionRepository,
    this._sessionEpoch, [
    this._connectivity,
    DateTime Function()? nowUtc,
  ]) : _nowUtc = nowUtc ?? _defaultNowUtc {
    // Register app lifecycle observer to detect when app resumes. Exactly
    // once per instance; `previous ??` in main.dart keeps a single instance
    // for the app's lifetime, and dispose() removes it exactly once.
    WidgetsBinding.instance.addObserver(this);

    // Listen for connectivity changes and refresh session when going online
    // BUT NOT for in_progress sessions - their timestamps are authoritative in memory
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
      if (_disposed) return;
      if (isOnline &&
          _currentSession != null &&
          _currentSession!.status != 'in_progress') {
        debugPrint(
          '📡 Connection restored - refreshing workout (ID: ${_currentSession!.id})',
        );
        loadSession(_currentSession!.id, showLoading: false);
      } else if (isOnline && _currentSession?.status == 'in_progress') {
        debugPrint(
          '📡 Connection restored - in_progress session, keeping local timestamps',
        );
      }
    });
  }

  static DateTime _defaultNowUtc() => DateTime.now().toUtc();

  /// Whether the current session should have an active UI refresh ticker:
  /// in-progress and not paused by the user. Timer.periodic is never the
  /// source of truth for elapsed time - this is the single place that
  /// condition is expressed, so lifecycle handling and session loading
  /// never duplicate it inline.
  bool get _shouldHaveRunningTicker =>
      _currentSession != null &&
      _currentSession!.status == 'in_progress' &&
      _currentSession!.pausedAt == null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_disposed) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _handleAppSuspending();
        break;
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
    }
  }

  /// The app is going inactive/hidden/backgrounded/detached (screen locked,
  /// app switched away, or similar). iOS may suspend the process at any
  /// point after this, so Timer.periodic cannot be relied on to keep
  /// ticking - stop and cancel it now. This never touches startedAt,
  /// pausedAt, status, duration, version, or sync/conflict metadata, never
  /// reloads the session, and never pauses the workout: the workout keeps
  /// running conceptually according to its timestamps while suspended, and
  /// resuming recalculates elapsed time from those timestamps.
  void _handleAppSuspending() {
    if (_disposed) return;
    _stopTimer();
  }

  /// The app has returned to the foreground. The in-memory session's
  /// timestamps are authoritative, so elapsed time is recalculated from
  /// them directly - no repository/Isar read is needed or performed for an
  /// in-progress session. If the workout should be ticking, exactly one
  /// fresh ticker is (re)started; _startTimer()'s own guard combined with
  /// stopping first here keeps repeated resumed events from ever creating
  /// more than one.
  void _handleAppResumed() {
    if (_disposed) return;
    // A logout may have happened while the app was backgrounded - there is
    // no session to recalculate or reload for, and no ticker to restart.
    if (_sessionEpoch.capture() == null || _currentSession == null) return;

    final lifeGen = _lifecycleGeneration;

    debugPrint('⏱️ App resumed - recalculating elapsed time');
    _recalculateElapsedTime();

    if (lifeGen != _lifecycleGeneration || _disposed) return;

    if (_shouldHaveRunningTicker) {
      _stopTimer();
      _startTimer();
    }

    // CRITICAL FIX: For in-progress sessions, DON'T reload from DB!
    // The in-memory state has correct UTC timestamps. Reloading from DB
    // could load corrupted timestamps (from before the UTC fix was deployed).
    // Only reload for non-active sessions (draft, completed, etc.)
    if (_currentSession != null && _currentSession!.status != 'in_progress') {
      debugPrint(
        '🔄 Reloading session ${_currentSession!.id} from DB after resume (not in_progress)',
      );
      // loadSession is itself fully session/generation-guarded; a logout or
      // manual clear between here and its first await drops the result.
      loadSession(_currentSession!.id, showLoading: false);
    } else if (_currentSession != null) {
      debugPrint(
        '🏋️ In-progress session - keeping in-memory timestamps (startedAt: ${_currentSession!.startedAt})',
      );
    }
  }

  /// Recalculate elapsed time based on current time and startedAt timestamp
  void _recalculateElapsedTime() {
    if (_disposed) return;
    if (_currentSession == null || _currentSession!.startedAt == null) {
      return;
    }

    final Duration calculated;

    if (_currentSession!.pausedAt != null) {
      // Timer is paused - elapsed time is when it was paused
      calculated = _currentSession!.pausedAt!.difference(
        _currentSession!.startedAt!,
      );
      debugPrint('  Timer PAUSED - recalculated: ${calculated.inSeconds}s');
    } else {
      // Timer is running - calculate from current time
      calculated = _nowUtc().difference(_currentSession!.startedAt!);
      debugPrint('  Timer RUNNING - recalculated: ${calculated.inSeconds}s');
    }

    // Update elapsed time and notify listeners
    _elapsedTime = calculated.isNegative ? Duration.zero : calculated;
    notifyListeners();
  }

  // Getters
  Session? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Duration get elapsedTime => _elapsedTime;
  bool get isTimerRunning => _isTimerRunning;
  List<Exercise> get exercises => _currentSession?.exercises ?? [];

  /// Set user weight for more accurate calorie estimation
  /// Call this when profile is loaded
  set userWeightKg(double? weight) {
    _userWeightKg = weight;
  }

  /// Load session by ID and calculate elapsed time
  Future<void> loadSession(int sessionId, {bool showLoading = true}) async {
    if (_disposed) return;
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final req = ++_requestGeneration;
    // A (re)load supersedes any in-flight in-place edit AND vice versa: a
    // newer edit that bumps `_editGeneration` supersedes THIS load's result.
    final myEdit = ++_editGeneration;

    // The RESULT ownership predicate - governs publishing the loaded session,
    // an error, and the timer/elapsed recalculation.
    bool ownsResult() =>
        !_disposed &&
        _sessionEpoch.isCurrent(token) &&
        req == _requestGeneration &&
        myEdit == _editGeneration;

    // The LOADING-INDICATOR ownership predicate - entirely independent of
    // `ownsResult()`. `showLoading: false` never claims, sets, clears, or
    // notifies for the flag (`myLoad` stays 0, which never matches a real
    // claim).
    final int myLoad = showLoading ? ++_loadingClaim : 0;
    bool ownsLoading() =>
        !_disposed &&
        _sessionEpoch.isCurrent(token) &&
        showLoading &&
        myLoad == _loadingClaim;

    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    Session? loaded;
    Object? failure;
    try {
      loaded = await _sessionRepository.getSession(sessionId);
    } on SessionStaleException {
      failure = const SessionStaleException();
    } on RequestCancelledException {
      failure = const RequestCancelledException();
    } catch (e) {
      failure = e;
    }

    // `changed` tracks whether any observable state actually moved, so a
    // superseded load - or a `showLoading: false` load that only hit a typed
    // lifecycle exception - produces no redundant no-op notification.
    var changed = false;

    if (ownsResult()) {
      if (failure == null && loaded != null) {
        _currentSession = loaded;
        changed = true;

        debugPrint('⏱️ TIMER DEBUG - loadSession called');
        debugPrint('  Session ID: ${_currentSession?.id}');
        debugPrint('  Status: ${_currentSession?.status}');
        debugPrint(
          '  StartedAt: ${_currentSession?.startedAt} (isUtc: ${_currentSession?.startedAt?.isUtc})',
        );
        debugPrint(
          '  PausedAt: ${_currentSession?.pausedAt} (isUtc: ${_currentSession?.pausedAt?.isUtc})',
        );
        debugPrint('  Current time LOCAL: ${DateTime.now()}');
        debugPrint('  Current time UTC: ${DateTime.now().toUtc()}');
        debugPrint('  Timezone offset: ${DateTime.now().timeZoneOffset}');

        // Calculate elapsed time if session has started
        // (startedAt and pausedAt are already in UTC from Session.fromJson)
        if (_currentSession?.startedAt != null) {
          final Duration calculated;
          final bool shouldBeRunning;

          if (_currentSession?.pausedAt != null) {
            // Timer is paused - elapsed time is when it was paused
            calculated = _currentSession!.pausedAt!.difference(
              _currentSession!.startedAt!,
            );
            shouldBeRunning = _shouldHaveRunningTicker;
            debugPrint('  Timer PAUSED:');
            debugPrint(
              '    pausedAt: ${_currentSession!.pausedAt} (isUtc: ${_currentSession!.pausedAt!.isUtc})',
            );
            debugPrint(
              '    startedAt: ${_currentSession!.startedAt} (isUtc: ${_currentSession!.startedAt!.isUtc})',
            );
            debugPrint(
              '    calculated difference: ${calculated.inSeconds}s (${calculated.inMinutes}m ${calculated.inSeconds % 60}s)',
            );
          } else {
            // Timer is running - calculate from current time
            final nowUtc = DateTime.now().toUtc();
            calculated = nowUtc.difference(_currentSession!.startedAt!);
            shouldBeRunning = _shouldHaveRunningTicker;
            debugPrint('  Timer RUNNING:');
            debugPrint('    nowUtc: $nowUtc');
            debugPrint(
              '    startedAt: ${_currentSession!.startedAt} (isUtc: ${_currentSession!.startedAt!.isUtc})',
            );
            debugPrint(
              '    calculated difference: ${calculated.inSeconds}s (${calculated.inMinutes}m ${calculated.inSeconds % 60}s)',
            );
          }

          // CRITICAL: Always stop timer first to avoid race condition
          _stopTimer();

          // Set the correct elapsed time
          _elapsedTime = calculated.isNegative ? Duration.zero : calculated;
          debugPrint('  Set _elapsedTime to: ${_elapsedTime.inSeconds}s');

          // Then restart timer if it should be running
          if (shouldBeRunning) {
            _startTimer();
            debugPrint('  Timer restarted');
          }
        } else {
          // Session hasn't started yet (still draft), reset timer
          debugPrint('  StartedAt is NULL - resetting timer to zero');
          _elapsedTime = Duration.zero;
          _stopTimer();
        }
      } else if (failure != null &&
          failure is! SessionStaleException &&
          failure is! RequestCancelledException) {
        // Ordinary current-session failure: preserve the existing public
        // behavior (surface a user-facing error). A lifecycle exception on a
        // still-current session is swallowed - it is not user-actionable.
        _errorMessage =
            'Failed to load session: ${failure.toString().replaceAll('Exception: ', '')}';
        debugPrint('Load session error: $failure');
        changed = true;
      }
    }

    // Release the loading claim independently of result ownership: a load
    // whose RESULT was superseded (by a newer edit or a different user) still
    // clears ONLY its own still-current spinner - never a newer load's or
    // user B's. A newer loading operation (or clear()/dispose()) has bumped
    // `_loadingClaim` past `myLoad`, so this is a no-op in that case.
    if (ownsLoading()) {
      _isLoading = false;
      changed = true;
    }

    if (changed) notifyListeners();
  }

  /// Start the workout timer, returning the [_timerGeneration] this call now
  /// owns. ALWAYS bumps the generation, even when it idempotently no-ops
  /// because a ticker is already running, so a caller on a session-guarded
  /// path can later undo THIS specific call via [_stopTimerIfOwned] without
  /// touching a newer session's ticker (even if that newer ticker is
  /// physically the same [Timer] object via the idempotency below). A
  /// logged-out call creates no [Timer].
  int _startTimer() {
    final generation = ++_timerGeneration;
    if (_isTimerRunning) return generation;
    if (_disposed) return generation;

    final token = _sessionEpoch.capture();
    if (token == null) return generation; // logged-out: no ticker

    final workoutId = _currentSession?.id;

    _isTimerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Every guard the scheduling context implied must still hold at tick
      // time. A tick that fails any of them changes nothing and does not
      // notify; a session/workout mismatch also cancels this specific timer
      // so no orphan ticker keeps firing.
      if (_disposed) return;
      if (!_sessionEpoch.isCurrent(token)) {
        _stopTimerIfOwned(generation);
        return;
      }
      if (generation != _timerGeneration) return;
      if (_currentSession?.id != workoutId) {
        _stopTimerIfOwned(generation);
        return;
      }
      _elapsedTime += const Duration(seconds: 1);
      notifyListeners();
    });
    return generation;
  }

  /// Stop the ticker unconditionally, and invalidate its generation so any
  /// already-queued callback from it no-ops. Reserved for a caller acting on
  /// its OWN still-current session (pause/finish/load/clear/dispose) - never
  /// from a stale completion path (use [_stopTimerIfOwned]).
  void _stopTimer() {
    _timerGeneration++;
    _timer?.cancel();
    _timer = null;
    _isTimerRunning = false;
  }

  /// Stop the ticker only if [generation] still matches [_timerGeneration] -
  /// i.e. only if nothing else has claimed the ticker since this caller's
  /// own [_startTimer]. Used by a stale rejection to undo the ticker THAT
  /// SPECIFIC call started, without ever touching a newer session's ticker.
  void _stopTimerIfOwned(int generation) {
    if (generation != _timerGeneration) return;
    _stopTimer();
  }

  /// Start workout (update status to in_progress)
  Future<void> startWorkout() async {
    if (_disposed || _currentSession == null) return;
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final req = ++_requestGeneration;
    ++_editGeneration;
    final workoutId = _currentSession!.id;

    bool owns() =>
        !_disposed &&
        _sessionEpoch.isCurrent(token) &&
        req == _requestGeneration &&
        _currentSession?.id == workoutId;

    try {
      // CRITICAL: Check for any existing in-progress sessions
      // Only one workout can be active at a time
      final inProgressSessions =
          await _sessionRepository.getInProgressSessions();
      if (!owns()) return;

      for (final session in inProgressSessions) {
        // Skip if it's the current session
        if (session.id == workoutId) continue;

        // Auto-complete any other in-progress workout
        debugPrint(
          '⚠️ Found existing in-progress workout (ID: ${session.id}), auto-completing...',
        );

        // Calculate duration from that session's timer
        final duration =
            session.startedAt != null
                ? DateTime.now()
                    .toUtc()
                    .difference(session.startedAt!)
                    .inMinutes
                : 0;

        await _sessionRepository.updateSessionStatus(
          session.id,
          'completed',
          duration: duration,
        );
        if (!owns()) return;

        debugPrint(
          '✅ Auto-completed workout ${session.id} with duration: $duration minutes',
        );
      }

      // CRITICAL FIX: Calculate UTC timestamp HERE (same pattern as pauseTimer)
      // This ensures consistent UTC handling - calculating inside Isar transactions
      // was causing the 5-hour bug where local time was treated as UTC
      final startedAtUtc = DateTime.now().toUtc();
      debugPrint('🏋️ Starting workout with UTC timestamp: $startedAtUtc');

      // Now start the new workout - pass UTC timestamp to repository
      final updatedSession = await _sessionRepository.updateSessionStatus(
        workoutId,
        'in_progress',
        startedAtUtc: startedAtUtc,
      );
      if (!owns()) return;

      // Use the session from DB to ensure timestamps match
      _currentSession = updatedSession;
      _elapsedTime = Duration.zero;
      // Stop-then-start defensively: a live ticker here is not expected (start
      // runs on draft sessions) but must never be left frozen by the
      // idempotent-`_startTimer()` generation bump.
      _stopTimer();
      final timerGen = _startTimer();
      if (!owns()) {
        // A logout / newer acquire landed between the check above and here.
        _stopTimerIfOwned(timerGen);
        return;
      }
      debugPrint('🏋️ Workout started with provider-calculated UTC timestamp');
      notifyListeners();
    } on SessionStaleException {
      // Lifecycle exception - never a user-B (or user-A) error here.
    } on RequestCancelledException {
      // Same.
    } catch (e) {
      if (!owns()) return;
      _errorMessage =
          'Failed to start workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Start workout error: $e');
      notifyListeners();
    }
  }

  /// Pause the timer (keeps session in_progress but stops timer)
  Future<void> pauseTimer() async {
    if (_disposed || _currentSession == null) return;

    // If session hasn't started yet, start it first
    if (_currentSession!.startedAt == null) {
      await startWorkout();
      return;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return;
    final myEdit = ++_editGeneration;
    final req = _requestGeneration;
    final workoutId = _currentSession!.id;

    bool owns() =>
        !_disposed &&
        _sessionEpoch.isCurrent(token) &&
        myEdit == _editGeneration &&
        req == _requestGeneration &&
        _currentSession?.id == workoutId;

    // Calculate timestamp ONCE to avoid drift
    final nowUtc = DateTime.now().toUtc(); // CRITICAL: Use UTC

    // Update UI IMMEDIATELY - don't wait for anything. This runs before the
    // first await, so it is still the current session by definition.
    _stopTimer();
    _currentSession = _currentSession!.copyWith(pausedAt: nowUtc);
    notifyListeners();
    debugPrint('⏸️ Timer paused (UI updated) - pausedAt UTC: $nowUtc');

    // CRITICAL FIX #10 & #1: AWAIT the pause to ensure local DB write completes
    try {
      await _sessionRepository.pauseSession(workoutId, nowUtc);
      debugPrint('✅ Pause persisted to local DB - timer state safe');
    } on SessionStaleException {
      // swallowed
    } on RequestCancelledException {
      // swallowed
    } catch (e) {
      if (!owns()) return;
      _errorMessage =
          'Failed to pause: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Pause error: $e');
      notifyListeners();
    }
  }

  /// Resume the timer (continues from current elapsed time)
  Future<void> resumeTimer() async {
    if (_disposed || _currentSession == null) return;

    // If session hasn't started yet, start it instead of resuming
    if (_currentSession!.startedAt == null) {
      await startWorkout();
      return;
    }

    final token = _sessionEpoch.capture();
    if (token == null) return;
    final myEdit = ++_editGeneration;
    final req = _requestGeneration;
    final workoutId = _currentSession!.id;

    bool owns() =>
        !_disposed &&
        _sessionEpoch.isCurrent(token) &&
        myEdit == _editGeneration &&
        req == _requestGeneration &&
        _currentSession?.id == workoutId;

    // Calculate adjusted startedAt ONCE to avoid drift
    final now = DateTime.now().toUtc();
    final pauseDuration =
        _currentSession!.pausedAt != null
            ? now.difference(_currentSession!.pausedAt!)
            : Duration.zero;
    final newStartedAt = _currentSession!.startedAt!.add(pauseDuration);

    // Update UI IMMEDIATELY - don't wait for anything.
    // CRITICAL: clearPausedAt: true is required to actually clear it.
    _currentSession = _currentSession!.copyWith(
      startedAt: newStartedAt,
      clearPausedAt: true,
    );

    // Resume timer. Always stop-then-start (as loadSession / _handleAppResumed
    // do): a "resume while a ticker is still running" call - e.g. a double-tap,
    // or a lifecycle resume racing a manual one - would otherwise advance
    // `_timerGeneration` on `_startTimer()`'s idempotent no-op path and leave
    // the running callback bailing on the generation check forever without a
    // replacement ticker being created.
    _stopTimer();
    _startTimer();
    notifyListeners();
    debugPrint('▶️ Timer resumed (UI updated) - new startedAt: $newStartedAt');

    // CRITICAL FIX #10 & #1: AWAIT the resume to ensure local DB write completes
    try {
      await _sessionRepository.resumeSession(workoutId, newStartedAt);
      debugPrint('✅ Resume persisted to local DB - timer state safe');
    } on SessionStaleException {
      // swallowed
    } on RequestCancelledException {
      // swallowed
    } catch (e) {
      if (!owns()) return;
      _errorMessage =
          'Failed to resume: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Resume error: $e');
      notifyListeners();
    }
  }

  /// Finish workout (update status to completed)
  Future<bool> finishWorkout() async {
    if (_disposed || _currentSession == null) return false;
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final myEdit = ++_editGeneration;
    final req = _requestGeneration;
    final workoutId = _currentSession!.id;

    bool owns() =>
        !_disposed &&
        _sessionEpoch.isCurrent(token) &&
        myEdit == _editGeneration &&
        req == _requestGeneration &&
        _currentSession?.id == workoutId;

    try {
      _stopTimer();

      // Calculate workout duration in minutes from elapsed time
      final durationMinutes = _elapsedTime.inMinutes;
      debugPrint('🏁 Finishing workout - Duration: $durationMinutes minutes');

      // Store start time before updating session (for health sync)
      final workoutStartTime = _currentSession!.startedAt;
      final workoutEndTime = DateTime.now();
      final workoutType = _currentSession!.type ?? 'strength';

      final completed = await _sessionRepository.updateSessionStatus(
        workoutId,
        'completed',
        duration: durationMinutes,
      );
      if (!owns()) return false;

      _currentSession = completed;

      // Sync to Apple Health / Google Fit if enabled (fire-and-forget;
      // health sync is user-agnostic and self-guards on service state).
      _syncWorkoutToHealth(
        startTime: workoutStartTime,
        endTime: workoutEndTime,
        durationMinutes: durationMinutes,
        workoutType: workoutType,
      );

      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (!owns()) return false;
      _errorMessage =
          'Failed to finish workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Finish workout error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Sync completed workout to Apple Health / Google Fit
  Future<void> _syncWorkoutToHealth({
    required DateTime? startTime,
    required DateTime endTime,
    required int durationMinutes,
    required String workoutType,
  }) async {
    if (startTime == null) return;

    try {
      final healthService = HealthService.instance;

      if (!healthService.isEnabled || !healthService.isAuthorized) {
        debugPrint('🏥 Health sync skipped - not enabled or authorized');
        return;
      }

      // Estimate calories using MET-based calculation with user weight
      final estimatedCalories = CaloriesService.estimateWorkoutCalories(
        durationMinutes: durationMinutes,
        userWeightKg: _userWeightKg,
        workoutType: workoutType,
      );

      final success = await healthService.writeWorkout(
        startTime: startTime,
        endTime: endTime,
        totalCalories: estimatedCalories,
        workoutType: workoutType,
      );

      if (success) {
        debugPrint(
          '🏥 ✅ Workout synced to Health: $durationMinutes min, ~$estimatedCalories cal (weight: ${_userWeightKg ?? "default"}kg)',
        );
      } else {
        debugPrint('🏥 ⚠️ Failed to sync workout to Health');
      }
    } catch (e) {
      debugPrint('🏥 ❌ Error syncing to Health: $e');
    }
  }

  /// Update workout name
  Future<bool> updateWorkoutName(String name) async {
    if (_disposed || _currentSession == null) return false;
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final myEdit = ++_editGeneration;
    final req = _requestGeneration;
    final workoutId = _currentSession!.id;

    bool owns() =>
        !_disposed &&
        _sessionEpoch.isCurrent(token) &&
        myEdit == _editGeneration &&
        req == _requestGeneration &&
        _currentSession?.id == workoutId;

    try {
      final updated = await _sessionRepository.updateSessionName(
        workoutId,
        name,
      );
      if (!owns()) return false;
      _currentSession = updated;
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (!owns()) return false;
      _errorMessage =
          'Failed to update workout name: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update workout name error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Add exercise to current session
  Future<void> addExercise(int exerciseTemplateId) async {
    if (_disposed || _currentSession == null) return;
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final req = _requestGeneration;
    final workoutId = _currentSession!.id;

    // Deliberately NOT gated by a per-add generation: two rapid adds on the
    // same workout must BOTH land (each reads the live exercise list at write
    // time). `req == _requestGeneration` supersedes an add whose workout was
    // replaced or whose session was cleared (`_invalidateGenerations()` bumps
    // `_requestGeneration`); `isCurrent(token)` supersedes a cross-user one.
    bool owns() =>
        !_disposed &&
        _sessionEpoch.isCurrent(token) &&
        req == _requestGeneration &&
        _currentSession?.id == workoutId;

    try {
      final newExercise = await _sessionRepository.addExerciseToSession(
        workoutId,
        exerciseTemplateId,
      );
      if (!owns()) return;

      // Read the CURRENT list at write time so a concurrent add is not lost.
      final updatedExercises = [..._currentSession!.exercises, newExercise];
      _currentSession = _currentSession!.copyWith(exercises: updatedExercises);

      debugPrint('✅ Exercise added to session (timer preserved)');
      notifyListeners();
    } on SessionStaleException {
      // swallowed
    } on RequestCancelledException {
      // swallowed
    } catch (e) {
      if (!owns()) return;
      _errorMessage =
          'Failed to add exercise: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Add exercise error: $e');
      notifyListeners();
    }
  }

  /// Create a new workout session from AI-generated exercises
  /// Returns the session ID if successful, null otherwise
  Future<int?> createWorkoutFromAI({
    required String workoutName,
    required List<int> exerciseTemplateIds,
  }) async {
    if (_disposed) return null;
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final req = ++_requestGeneration;
    final myEdit = ++_editGeneration;

    bool owns() =>
        !_disposed &&
        _sessionEpoch.isCurrent(token) &&
        req == _requestGeneration &&
        myEdit == _editGeneration;

    // Shares `_isLoading` with loadSession - it must take the same independent
    // loading claim so its `finally` only releases its own still-current
    // spinner.
    final myLoad = ++_loadingClaim;
    bool ownsLoading() =>
        !_disposed && _sessionEpoch.isCurrent(token) && myLoad == _loadingClaim;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Create new session
      final newSession = Session(
        id: 0, // Will be assigned by repository
        userId: 0, // Will be set by repository
        date: DateTime.now(),
        duration: 0,
        name: workoutName,
        type: 'strength',
        status: 'draft',
        exercises: const [],
      );

      // Save session
      final createdSession = await _sessionRepository.createSession(newSession);
      if (!owns()) return null;
      _currentSession = createdSession;

      debugPrint('✅ Created AI workout session: ${createdSession.id}');

      // Add exercises to the session
      for (final templateId in exerciseTemplateIds) {
        try {
          final exercise = await _sessionRepository.addExerciseToSession(
            createdSession.id,
            templateId,
          );
          if (!owns() || _currentSession?.id != createdSession.id) return null;
          // Add to current session's list
          final updatedExercises = [..._currentSession!.exercises, exercise];
          _currentSession = _currentSession!.copyWith(
            exercises: updatedExercises,
          );
          debugPrint('  ✅ Added exercise: ${exercise.name}');
        } on SessionStaleException {
          return null;
        } on RequestCancelledException {
          return null;
        } catch (e) {
          if (!owns()) return null;
          debugPrint('  ⚠️ Failed to add exercise template $templateId: $e');
          // Continue adding other exercises even if one fails
        }
      }

      if (!owns()) return null;
      notifyListeners();
      return createdSession.id;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      if (owns()) {
        _errorMessage =
            'Failed to create workout: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Create workout from AI error: $e');
        notifyListeners();
      }
      return null;
    } finally {
      // Release the loading claim independently of result ownership - a
      // superseded create still clears ONLY its own still-current spinner.
      if (ownsLoading()) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Clear error message
  void clearError() {
    if (_disposed) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// Bump every ownership/ordering generation so no in-flight continuation,
  /// timer callback, or lifecycle callback can publish or restart anything
  /// after this returns - even when called without a preceding
  /// `UserSessionEpoch.invalidate()`.
  void _invalidateGenerations() {
    _requestGeneration++;
    _editGeneration++;
    _loadingClaim++;
    _timerGeneration++;
    _lifecycleGeneration++;
  }

  /// Clear all workout data (called on logout via [SessionCleanupCoordinator],
  /// and on "delete the session I'm viewing" from the sessions list).
  ///
  /// Synchronous and unconditional: never gated by a captured token, since it
  /// is what logout relies on. Generations are invalidated FIRST, then every
  /// timer is cancelled, then every user-visible and transient field is
  /// reset.
  void clear() {
    _invalidateGenerations();
    _stopTimer();
    _currentSession = null;
    _errorMessage = null;
    _isLoading = false;
    _elapsedTime = Duration.zero;
    _isTimerRunning = false;
    if (!_disposed) notifyListeners();
    debugPrint('🧹 ActiveWorkoutProvider cleared');
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateGenerations();
    _stopTimer();
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
