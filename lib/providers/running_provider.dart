import 'dart:async';
import 'dart:math' show sin, cos, sqrt, atan2, pi;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../data/models/run_session.dart';
import '../data/models/gps_point.dart';
import '../data/repositories/running_repository.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/health_service.dart';
import '../core/services/calories_service.dart';

/// Explicit lifecycle state for the GPS position-stream subscription
/// backing an active run.
///
/// This replaces a bare "is active" bool, which could not represent "a
/// subscription was created but its underlying native stream has since
/// errored or completed" - that ambiguity let a dead stream masquerade as
/// healthy indefinitely (Running Finding R2), since nothing ever reset it.
enum GpsTrackingState {
  /// No subscription exists and none is currently being created.
  stopped,

  /// A subscription has been requested but no position/error/done callback
  /// has arrived for it yet. Treated as "healthy" for duplicate-prevention
  /// purposes - starting again while `starting` must not create a second
  /// subscription.
  starting,

  /// At least one position has been received on the current subscription.
  active,

  /// The current subscription errored, completed unexpectedly, or could
  /// not be created (e.g. a permission/service check failed). Recoverable:
  /// an explicit user action or an app-lifecycle resume may create a fresh
  /// subscription.
  failed,
}

/// Provider for active running session with timer and GPS tracking
class RunningProvider extends ChangeNotifier with WidgetsBindingObserver {
  final RunningRepository _runningRepository;
  // ignore: unused_field - Reserved for future online/offline status checks
  final ConnectivityService? _connectivity;

  // Injectable UTC clock, used only for lifecycle elapsed-time
  // recalculation so tests can control elapsed "time spent suspended"
  // deterministically. Defaults to the real clock in production. Mirrors
  // ActiveWorkoutProvider's established pattern.
  final DateTime Function() _nowUtc;

  RunSession? _currentRun;
  List<RunSession> _recentRuns = [];
  Map<String, dynamic> _weeklyStats = {};
  bool _isLoading = false;
  String? _errorMessage;

  // Timer state
  Timer? _timer;
  Duration _elapsedTime = Duration.zero;
  bool _isTimerRunning = false;

  // GPS state
  StreamSubscription<Position>? _positionStream;
  List<GpsPoint> _routePoints = [];
  double _currentDistance = 0;
  Position? _lastPosition;
  GpsTrackingState _gpsTrackingState = GpsTrackingState.stopped;

  // Monotonically increasing token identifying the "current" GPS
  // subscription attempt. Every subscription created by _startGpsTracking()
  // captures the generation value active at creation time, and every
  // position/error/done callback closes over that same value. A callback
  // whose captured generation no longer matches `_gpsGeneration` is from a
  // superseded or already-stopped subscription and must be ignored - this
  // is the primary defense against late callbacks mutating state after a
  // stop/restart/dispose, and does not rely on StreamSubscription.cancel()
  // alone to prevent every already-queued callback from running.
  int _gpsGeneration = 0;

  // Set synchronously at the start of dispose(). Every GPS callback checks
  // this before touching provider state or calling notifyListeners(), so a
  // cancellation future still pending when the provider is disposed can
  // never reach a disposed instance's state.
  bool _disposed = false;

  // The in-flight cancellation of the previous GPS subscription, if any.
  // Recorded by every path that begins cancelling a subscription
  // (_stopGpsTracking, _onPositionError, _onPositionDone, dispose) via
  // _beginGpsCancellation, and consulted by _startGpsTracking(), which
  // awaits it before creating a replacement subscription.
  //
  // Without this, a lifecycle-resumed recovery could call
  // Geolocator.getPositionStream().listen() again while the native side
  // was still tearing down the previous subscription - some platforms
  // reject a second concurrent listener ("already listening"), which
  // would immediately fail the recovery back to `failed`, where it stays
  // stuck until another resume event happens to arrive.
  //
  // The stored future is guaranteed to never throw (cancellation failures
  // are caught and logged inside _beginGpsCancellation), so awaiting it
  // can never itself leave a caller stuck, and it clears itself back to
  // null once the cancellation it represents completes.
  Future<void>? _gpsCancellationFuture;

  // The exact String object last assigned to _errorMessage by this file's
  // own GPS error handling (_onPositionError, _onPositionDone, or the
  // synchronous-throw catch in _startGpsTracking) - or null if no such
  // error is currently outstanding. A successful GPS start/self-heal
  // clears _errorMessage only if it is still `identical` to this value,
  // i.e. only if nothing else has overwritten it since. This is
  // deliberately reference identity, not a _gpsTrackingState-based
  // heuristic ("was the state `failed`") - the latter breaks the moment
  // an unrelated operation (e.g. loadDashboardData()) overwrites
  // _errorMessage while GPS happens to still be in its failed state, which
  // would otherwise make a later GPS recovery wrongly clear that unrelated
  // error.
  String? _gpsErrorMessage;

  // User weight for calories calculation (set from ProfileProvider)
  double? _userWeightKg;

  // Location settings for platforms with no platform-specific override
  // below (Android and any other supported platform) - unchanged from
  // before this PR.
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5, // Update every 5 meters
  );

  /// Resolves the [LocationSettings] to use for the current platform.
  ///
  /// iOS gets [AppleSettings] so the position stream can keep delivering
  /// while the app is backgrounded/locked for an explicitly user-started
  /// active run (Running Finding R2's iOS configuration PR):
  /// - `allowBackgroundLocationUpdates: true` plus `showBackgroundLocationIndicator: true`
  ///   are the two flags geolocator_apple forwards to
  ///   `CLLocationManager.allowsBackgroundLocationUpdates`/
  ///   `showsBackgroundLocationIndicator` - required for background
  ///   delivery to be attempted at all, together with the
  ///   `UIBackgroundModes: location` entry already present in
  ///   ios/Runner/Info.plist.
  /// - `pauseLocationUpdatesAutomatically: false` opts out of iOS's own
  ///   motion-based auto-pause heuristic (meant for automotive/stationary
  ///   detection), since GoHard's explicit pause/resume buttons are the
  ///   only intended way to stop tracking - an OS-driven pause here would
  ///   look identical to the "silent stall" failure mode Running Finding
  ///   R2 already guards against, but through a path this file cannot
  ///   observe or recover from.
  /// - `activityType: fitness` is Apple's documented hint for a
  ///   walking/running/cycling workout, affecting iOS's internal power
  ///   management heuristics.
  /// - `accuracy: high` matches the value already used for every other
  ///   platform, deliberately *not* raised to `best`. geolocator_apple
  ///   2.3.13 maps `LocationAccuracy.high` to `kCLLocationAccuracyNearestTenMeters`
  ///   and `LocationAccuracy.best` to `kCLLocationAccuracyBest` - a
  ///   materially higher (more power-hungry) tier per Apple's own
  ///   `CLLocationAccuracy` constants, not an equivalent one. Nothing about
  ///   this PR's background-delivery goal or the app's existing running
  ///   behavior requires that extra precision, so `high` is preserved
  ///   rather than trading battery life for accuracy with no concrete
  ///   requirement behind it.
  ///
  /// This method does not request "Always" authorization and does not
  /// change anything about `_checkLocationPermission()` - the existing
  /// When-In-Use permission flow is unchanged, as required for this PR.
  /// Background delivery depends on iOS authorization and runtime policy.
  /// This configuration enables background-capable active-run tracking;
  /// final behavior must be validated on a real iPhone before adding any
  /// Always-permission upgrade. This method configures `AppleSettings`
  /// only - any permission escalation is a separate, later decision.
  ///
  /// Every other platform (Android, and any future platform without an
  /// explicit branch) keeps using the existing [_locationSettings] value
  /// unchanged - this PR does not modify Android behavior.
  LocationSettings _resolveLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return _locationSettings;
  }

  RunningProvider(
    this._runningRepository, [
    this._connectivity,
    DateTime Function()? nowUtc,
  ]) : _nowUtc = nowUtc ?? _defaultNowUtc {
    WidgetsBinding.instance.addObserver(this);
  }

  static DateTime _defaultNowUtc() => DateTime.now().toUtc();

  // Getters
  RunSession? get currentRun => _currentRun;
  List<RunSession> get recentRuns => _recentRuns;
  Map<String, dynamic> get weeklyStats => _weeklyStats;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Duration get elapsedTime => _elapsedTime;
  bool get isTimerRunning => _isTimerRunning;
  List<GpsPoint> get routePoints => _routePoints;
  double get currentDistance => _currentDistance;

  /// Explicit GPS subscription state. See [GpsTrackingState]. Does not
  /// expose the underlying [StreamSubscription].
  GpsTrackingState get gpsTrackingState => _gpsTrackingState;

  /// True only when tracking is genuinely starting or actively receiving
  /// positions. False for `stopped` and `failed` - in particular, a
  /// subscription that errored or completed no longer reports active here,
  /// which is the specific bug this getter previously had (Running Finding
  /// R2: a bare bool that nothing ever reset on stream error/completion).
  bool get isGpsActive =>
      _gpsTrackingState == GpsTrackingState.starting ||
      _gpsTrackingState == GpsTrackingState.active;

  bool get hasActiveRun =>
      _currentRun != null && _currentRun!.status == 'in_progress';
  bool get hasDraftRun => _currentRun != null && _currentRun!.status == 'draft';

  /// Set user weight for more accurate calorie estimation
  /// Call this when profile is loaded
  set userWeightKg(double? weight) {
    _userWeightKg = weight;
  }

  /// Current pace in min/km
  /// Requires at least 10 meters of distance to avoid GPS noise causing absurd values
  double? get currentPace {
    if (_currentDistance < 0.01 || _elapsedTime.inSeconds <= 0) return null;
    return (_elapsedTime.inSeconds / 60) / _currentDistance;
  }

  /// Formatted current pace
  String get formattedPace {
    final pace = currentPace;
    if (pace == null) return '--:--';
    final minutes = pace.floor();
    final seconds = ((pace - minutes) * 60).round();
    return "$minutes'${seconds.toString().padLeft(2, '0')}\"";
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('⏱️ App resumed - recalculating elapsed time');
        _recalculateElapsedTime();
        unawaited(_recoverGpsTrackingIfNeeded());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Deliberately does nothing to the GPS subscription or pausedAt: a
        // healthy native stream must be allowed to keep delivering while
        // the app is backgrounded/locked (Running Finding R2). Cancelling
        // or marking the run paused here would reintroduce the exact
        // defect this change exists to fix. Timer/elapsed-time behavior is
        // unchanged from before this PR - _recalculateElapsedTime() on
        // resume is unaffected by whether the ticker kept running while
        // suspended.
        break;
    }
  }

  void _recalculateElapsedTime() {
    if (_currentRun == null || _currentRun!.startedAt == null) return;

    final Duration calculated;

    if (_currentRun!.pausedAt != null) {
      calculated = _currentRun!.pausedAt!.difference(_currentRun!.startedAt!);
      debugPrint('  Timer PAUSED - recalculated: ${calculated.inSeconds}s');
    } else {
      calculated = _nowUtc().difference(_currentRun!.startedAt!);
      debugPrint('  Timer RUNNING - recalculated: ${calculated.inSeconds}s');
    }

    _elapsedTime = calculated.isNegative ? Duration.zero : calculated;
    notifyListeners();
  }

  /// Recovers GPS tracking after an app-lifecycle resume if, and only if,
  /// the current run is active/unpaused and its subscription is known to
  /// be dead (`failed`) or was never started (`stopped`). A healthy
  /// (`starting`/`active`) subscription is left completely alone - this is
  /// what prevents a duplicate subscription on a routine resume, and what
  /// lets a genuinely healthy background stream keep delivering
  /// uninterrupted through the whole suspend/resume cycle. Calling this
  /// repeatedly (e.g. repeated `resumed` events) is idempotent: once
  /// recovery starts, `_startGpsTracking()`'s own guard prevents any
  /// further duplicate.
  Future<void> _recoverGpsTrackingIfNeeded() async {
    if (_currentRun == null) return;
    if (_currentRun!.status != 'in_progress') return;
    if (_currentRun!.pausedAt != null) return;

    switch (_gpsTrackingState) {
      case GpsTrackingState.starting:
      case GpsTrackingState.active:
        return; // healthy, or already being (re)established - never duplicate
      case GpsTrackingState.stopped:
      case GpsTrackingState.failed:
        await _startGpsTracking();
    }
  }

  /// Load recent runs and weekly stats
  Future<void> loadDashboardData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _recentRuns = await _runningRepository.getRecentRuns(limit: 5);
      _weeklyStats = await _runningRepository.getWeeklyStats();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load running data: $e';
      debugPrint('Load dashboard error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load a specific run session
  Future<void> loadRun(int localId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentRun = await _runningRepository.getRunSession(localId);

      if (_currentRun?.startedAt != null) {
        final Duration calculated;
        final bool shouldBeRunning;

        if (_currentRun?.pausedAt != null) {
          calculated = _currentRun!.pausedAt!.difference(
            _currentRun!.startedAt!,
          );
          shouldBeRunning = false;
        } else {
          calculated = DateTime.now().toUtc().difference(
            _currentRun!.startedAt!,
          );
          shouldBeRunning = _currentRun?.status == 'in_progress';
        }

        _stopTimer();
        _elapsedTime = calculated.isNegative ? Duration.zero : calculated;

        if (shouldBeRunning) {
          _startTimer();
        }

        // Restore route points
        _routePoints = List.from(_currentRun!.route);
        _currentDistance = _currentRun!.distance ?? 0;
      } else {
        _elapsedTime = Duration.zero;
        _stopTimer();
        _routePoints = [];
        _currentDistance = 0;
      }
    } catch (e) {
      _errorMessage = 'Failed to load run: $e';
      debugPrint('Load run error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a draft run without starting (for navigation to active screen)
  Future<int?> createDraftRun() async {
    try {
      // Check location permissions first
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        _errorMessage = 'Location permission required for running';
        notifyListeners();
        return null;
      }

      // Create new run session (draft status)
      _currentRun = await _runningRepository.createRunSession();
      _elapsedTime = Duration.zero;
      _routePoints = [];
      _currentDistance = 0;
      _lastPosition = null;

      debugPrint('🏃 Draft run created: ${_currentRun!.id}');
      notifyListeners();
      return _currentRun!.id;
    } catch (e) {
      _errorMessage = 'Failed to create run: $e';
      debugPrint('Create draft run error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Start the current run (called after countdown)
  Future<bool> startCurrentRun() async {
    if (_currentRun == null) return false;

    try {
      // Start the run
      _currentRun = await _runningRepository.startRun(_currentRun!.id);
      _elapsedTime = Duration.zero;

      _startTimer();
      await _startGpsTracking();

      debugPrint('🏃 Run started: ${_currentRun!.id}');
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to start run: $e';
      debugPrint('Start run error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Create and start a new run (legacy method, still used for quick start)
  Future<int?> startNewRun() async {
    try {
      // Check location permissions first
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        _errorMessage = 'Location permission required for running';
        notifyListeners();
        return null;
      }

      // Create new run session
      _currentRun = await _runningRepository.createRunSession();

      // Start the run
      _currentRun = await _runningRepository.startRun(_currentRun!.id);
      _elapsedTime = Duration.zero;
      _routePoints = [];
      _currentDistance = 0;
      _lastPosition = null;

      _startTimer();
      await _startGpsTracking();

      debugPrint('🏃 New run started: ${_currentRun!.id}');
      notifyListeners();
      return _currentRun!.id;
    } catch (e) {
      _errorMessage = 'Failed to start run: $e';
      debugPrint('Start run error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Pause the run
  Future<void> pauseRun() async {
    if (_currentRun == null) return;

    if (_currentRun!.startedAt == null) {
      await startNewRun();
      return;
    }

    final nowUtc = DateTime.now().toUtc();

    _stopTimer();
    await _stopGpsTracking();

    _currentRun = _currentRun!.copyWith(pausedAt: nowUtc);
    notifyListeners();

    try {
      await _runningRepository.pauseRun(_currentRun!.id, nowUtc);
      debugPrint('⏸️ Run paused - saved to DB');
    } catch (e) {
      _errorMessage = 'Failed to pause run: $e';
      debugPrint('Pause run error: $e');
      notifyListeners();
    }
  }

  /// Resume the run
  Future<void> resumeRun() async {
    if (_currentRun == null) return;

    if (_currentRun!.startedAt == null) {
      await startNewRun();
      return;
    }

    final now = DateTime.now().toUtc();
    final pauseDuration =
        _currentRun!.pausedAt != null
            ? now.difference(_currentRun!.pausedAt!)
            : Duration.zero;
    final newStartedAt = _currentRun!.startedAt!.add(pauseDuration);

    // CRITICAL: clearPausedAt: true is required to actually clear it -
    // pausedAt: null alone is indistinguishable from omitting it in
    // copyWith's "override or keep existing" convention and would leave
    // the stale pausedAt in place, which _recalculateElapsedTime relies on
    // to decide whether the run should still be treated as paused after an
    // app suspend/resume cycle.
    _currentRun = _currentRun!.copyWith(
      startedAt: newStartedAt,
      clearPausedAt: true,
    );

    _startTimer();
    await _startGpsTracking();
    notifyListeners();

    try {
      await _runningRepository.resumeRun(_currentRun!.id, newStartedAt);
      debugPrint('▶️ Run resumed - saved to DB');
    } catch (e) {
      _errorMessage = 'Failed to resume run: $e';
      debugPrint('Resume run error: $e');
      notifyListeners();
    }
  }

  /// Finish the run
  Future<bool> finishRun() async {
    if (_currentRun == null) return false;

    try {
      _stopTimer();
      await _stopGpsTracking();

      final duration = _elapsedTime.inSeconds;
      final durationMinutes = (duration / 60).ceil();
      final distance = _currentDistance;
      final pace = distance > 0 ? (duration / 60) / distance : null;

      // Estimate calories using MET-based calculation with pace and user weight
      final calories = CaloriesService.estimateRunningCalories(
        distanceKm: distance,
        durationMinutes: durationMinutes,
        userWeightKg: _userWeightKg,
      );

      // Store start time before updating (for health sync)
      final runStartTime = _currentRun!.startedAt;
      final runEndTime = DateTime.now();

      _currentRun = await _runningRepository.completeRun(
        _currentRun!.id,
        duration: duration,
        distance: distance,
        averagePace: pace,
        calories: calories,
        route: _routePoints,
      );

      // Sync to Apple Health / Google Fit
      _syncRunToHealth(
        startTime: runStartTime,
        endTime: runEndTime,
        durationSeconds: duration,
        distanceKm: distance,
        calories: calories,
      );

      // Reload dashboard data
      await loadDashboardData();

      debugPrint(
        '🏁 Run finished: ${distance.toStringAsFixed(2)} km in ${duration}s',
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to finish run: $e';
      debugPrint('Finish run error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Discard current run
  Future<void> discardRun() async {
    if (_currentRun == null) return;

    try {
      _stopTimer();
      await _stopGpsTracking();

      await _runningRepository.deleteRun(_currentRun!.id);

      _currentRun = null;
      _elapsedTime = Duration.zero;
      _routePoints = [];
      _currentDistance = 0;
      _lastPosition = null;

      debugPrint('🗑️ Run discarded');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to discard run: $e';
      debugPrint('Discard run error: $e');
      notifyListeners();
    }
  }

  /// Check location permission
  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _errorMessage = 'Location services are disabled';
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _errorMessage = 'Location permission denied';
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _errorMessage =
          'Location permission permanently denied. Please enable in settings.';
      return false;
    }

    return true;
  }

  /// Start GPS tracking.
  ///
  /// Idempotent: safe to call repeatedly (explicit resume, lifecycle
  /// recovery) without ever creating more than one live subscription -
  /// callers that need a permission/service check first (createDraftRun,
  /// startNewRun) perform it themselves before reaching this point,
  /// exactly as before this change; this method does not add a new
  /// permission gate here, preserving existing behavior for resumeRun()/
  /// startCurrentRun(), which have always called this directly.
  ///
  /// If a previous subscription's cancellation is still in flight
  /// (`_gpsCancellationFuture`), this awaits it first rather than racing a
  /// replacement `listen()` against the still-in-progress teardown. Any
  /// number of concurrent callers (e.g. two lifecycle `resumed` events
  /// arriving before the cancellation resolves) end up awaiting the same
  /// future; when it resolves, the first to resume claims `starting`
  /// synchronously - with no further `await` before that point - so every
  /// other awaiter's re-validation below sees the state already claimed
  /// and returns, guaranteeing at most one replacement subscription.
  Future<void> _startGpsTracking() async {
    if (_disposed) return;
    if (_gpsTrackingState == GpsTrackingState.starting ||
        _gpsTrackingState == GpsTrackingState.active) {
      return;
    }

    // Captured before any await, so a run-identity change while this call
    // is waiting on a stale cancellation can be detected below rather than
    // silently starting tracking attributed to whatever run happens to be
    // current by then.
    final int? expectedRunId = _currentRun?.id;

    final pendingCancellation = _gpsCancellationFuture;
    if (pendingCancellation != null) {
      await pendingCancellation;

      // Re-validate everything after the await: a newer stop/pause/
      // finish/discard/clear/dispose, another caller already starting a
      // fresh subscription, or the run itself changing identity/status/
      // pausedAt, must all win over this now-possibly-stale attempt.
      if (_disposed) return;
      if (_gpsTrackingState == GpsTrackingState.starting ||
          _gpsTrackingState == GpsTrackingState.active) {
        return;
      }
      if (_currentRun == null || _currentRun!.id != expectedRunId) return;
      if (_currentRun!.status != 'in_progress') return;
      if (_currentRun!.pausedAt != null) return;
    }

    final int generation = ++_gpsGeneration;
    final int? runId = expectedRunId;
    _gpsTrackingState = GpsTrackingState.starting;
    // Clear the stale GPS error this attempt is recovering from, now that
    // a fresh attempt is underway - matches the project convention of
    // clearing stale errors when retrying an operation. Uses reference
    // identity against _gpsErrorMessage (see its field doc comment) so an
    // unrelated error set by a different operation in the meantime is
    // never erased. A subsequent failure below sets its own message (and
    // its own _gpsErrorMessage) anyway.
    if (identical(_errorMessage, _gpsErrorMessage)) {
      _errorMessage = null;
    }
    _gpsErrorMessage = null;

    try {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: _resolveLocationSettings(),
      ).listen(
        (position) => _onPositionUpdate(position, generation, runId),
        onError:
            (Object error, StackTrace stackTrace) =>
                _onPositionError(error, generation, runId),
        onDone: () => _onPositionDone(generation, runId),
        cancelOnError: false,
      );
    } catch (e) {
      // getPositionStream()/.listen() can throw synchronously (e.g. a
      // platform rejecting a second concurrent listener) rather than
      // delivering the failure through onError. Without this, a
      // synchronous throw here would leave _gpsTrackingState stuck at
      // `starting` forever - never reset to `active` (no callback ever
      // attached) or `failed` (no error callback ever fires) - which is
      // exactly the "state that lies about being active" bug this PR
      // exists to eliminate.
      if (!_isGpsCallbackCurrent(generation, runId)) return;
      _gpsTrackingState = GpsTrackingState.failed;
      final message = 'Location tracking was interrupted: $e';
      _errorMessage = message;
      _gpsErrorMessage = message;
      debugPrint(
        '📍 GPS tracking failed to start (generation $generation): $e',
      );
      notifyListeners();
      return;
    }

    debugPrint('📍 GPS tracking started (generation $generation)');
  }

  /// Stop GPS tracking and await cancellation of any underlying
  /// subscription.
  ///
  /// Idempotent - safe to call when tracking is already stopped/failed.
  /// The generation is invalidated synchronously, before the cancellation
  /// await, so any callback already queued for the old subscription is
  /// guaranteed to see a stale generation and no-op, even though the
  /// actual cancellation future may still be pending when this method
  /// returns to its caller.
  Future<void> _stopGpsTracking() async {
    _gpsGeneration++;
    final subscription = _positionStream;
    _positionStream = null;
    _gpsTrackingState = GpsTrackingState.stopped;

    if (subscription == null) return;

    await _beginGpsCancellation(subscription);
    debugPrint('📍 GPS tracking stopped');
  }

  /// Begins cancelling [subscription] and records the resulting future in
  /// [_gpsCancellationFuture] so a subsequent _startGpsTracking() call can
  /// serialize against it. Every path that tears down a subscription
  /// (_stopGpsTracking, _onPositionError, _onPositionDone, dispose) goes
  /// through this single method, so `_gpsCancellationFuture` always
  /// reflects whatever cancellation is actually in flight, regardless of
  /// which of those paths triggered it.
  ///
  /// The returned/stored future never throws: a cancellation failure is
  /// logged (matching this file's existing debug-and-swallow convention,
  /// see _syncRunToHealth) rather than propagated, so awaiting it can
  /// never itself leave a caller stuck. This holds whether subscription
  /// .cancel() rejects its returned future OR throws synchronously (a
  /// contract violation for a well-behaved StreamSubscription, but guarded
  /// against regardless) - both are caught here. The reference is cleared
  /// back to null once this specific cancellation completes, guarded by an
  /// identity check so a slow, superseded cancellation can never clobber a
  /// newer one that has already taken its place.
  Future<void> _beginGpsCancellation(
    StreamSubscription<Position> subscription,
  ) {
    Future<void> future;
    try {
      future = subscription.cancel().then<void>(
        (_) {},
        onError: (Object e) {
          debugPrint('📍 GPS tracking cancel error (ignored): $e');
        },
      );
    } catch (e) {
      debugPrint('📍 GPS tracking cancel error (ignored): $e');
      future = Future<void>.value();
    }
    _gpsCancellationFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_gpsCancellationFuture, future)) {
          _gpsCancellationFuture = null;
        }
      }),
    );
    return future;
  }

  /// True if a callback captured at [generation] for run [runId] still
  /// applies to the provider's current state. Checked at the top of every
  /// position/error/done callback so a late callback from a superseded
  /// subscription can never mutate a different/new run, mutate state after
  /// disposal, or resurrect tracking for a run that is no longer in
  /// progress or has been explicitly paused by the user.
  bool _isGpsCallbackCurrent(int generation, int? runId) {
    if (_disposed) return false;
    if (generation != _gpsGeneration) return false;
    if (_currentRun == null || _currentRun!.id != runId) return false;
    if (_currentRun!.status != 'in_progress') return false;
    if (_currentRun!.pausedAt != null) return false;
    return true;
  }

  /// Handle GPS position update
  void _onPositionUpdate(Position position, int generation, int? runId) {
    if (!_isGpsCallbackCurrent(generation, runId)) return;

    // A stream that errored earlier but was not cancelled (cancelOnError:
    // false) may still self-heal and resume delivering positions - treat a
    // fresh position as proof of a healthy subscription regardless of the
    // prior state. Clear the error message only by reference identity
    // against _gpsErrorMessage (see its field doc comment), so an
    // unrelated error set by some other operation in the meantime is
    // never silently wiped by this GPS-internal recovery.
    if (identical(_errorMessage, _gpsErrorMessage)) {
      _errorMessage = null;
    }
    _gpsErrorMessage = null;
    _gpsTrackingState = GpsTrackingState.active;

    final gpsPoint = GpsPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      timestamp: DateTime.now().toUtc(),
      speed: position.speed,
      accuracy: position.accuracy,
    );

    _routePoints.add(gpsPoint);

    // Calculate distance from last point
    if (_lastPosition != null) {
      final distance = _calculateDistance(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      _currentDistance += distance;
    }

    _lastPosition = position;

    // Periodically save route to DB
    if (_routePoints.length % 10 == 0) {
      _runningRepository.updateRoute(_currentRun!.id, _routePoints);
      _runningRepository.updateDistance(_currentRun!.id, _currentDistance);
    }

    notifyListeners();
  }

  /// Handle a GPS stream error for the current generation.
  ///
  /// Marks tracking `failed` (never left dangling as "active", the core
  /// R2 bug) and surfaces an actionable message via the existing
  /// [errorMessage] mechanism. Does not retry automatically - recovery
  /// only happens via an explicit user action (pause/resume) or an
  /// app-lifecycle resume (`_recoverGpsTrackingIfNeeded`), so a
  /// persistently failing stream cannot spin in an automatic retry loop.
  void _onPositionError(Object error, int generation, int? runId) {
    if (!_isGpsCallbackCurrent(generation, runId)) return;

    // cancelOnError: false means the plugin does not auto-cancel this
    // subscription for us. Explicitly cancel it (via _beginGpsCancellation,
    // recorded in _gpsCancellationFuture - we already know it is dead) so
    // a subsequent recovery's _startGpsTracking() call serializes against
    // this teardown instead of racing a replacement listen() against it,
    // which some platforms reject as "already listening".
    final subscription = _positionStream;
    _positionStream = null;
    _gpsTrackingState = GpsTrackingState.failed;
    final message = 'Location tracking was interrupted: $error';
    _errorMessage = message;
    _gpsErrorMessage = message;
    debugPrint('📍 GPS stream error (generation $generation): $error');
    notifyListeners();

    if (subscription != null) {
      unawaited(_beginGpsCancellation(subscription));
    }
  }

  /// Handle GPS stream completion for the current generation.
  ///
  /// If an error already marked this generation `failed`, this is a no-op
  /// beyond releasing the subscription reference - it must not overwrite a
  /// more specific preceding error message or emit a redundant
  /// notification for the same underlying failure.
  void _onPositionDone(int generation, int? runId) {
    if (!_isGpsCallbackCurrent(generation, runId)) return;
    if (_gpsTrackingState == GpsTrackingState.failed) {
      _positionStream = null;
      return;
    }

    final subscription = _positionStream;
    _positionStream = null;
    _gpsTrackingState = GpsTrackingState.failed;
    // A const string literal is canonicalized by Dart, so it is `identical`
    // to any other occurrence of this exact literal text. Do not reuse
    // this exact string for an unrelated (non-GPS) _errorMessage
    // assignment elsewhere in this file - doing so would make it
    // `identical` to _gpsErrorMessage and wrongly clearable by a GPS
    // recovery/self-heal. See _gpsErrorMessage's field doc comment.
    const message = 'Location tracking stopped unexpectedly.';
    _errorMessage = message;
    _gpsErrorMessage = message;
    debugPrint('📍 GPS stream completed unexpectedly (generation $generation)');
    notifyListeners();

    if (subscription != null) {
      unawaited(_beginGpsCancellation(subscription));
    }
  }

  /// Calculate distance between two GPS points using Haversine formula
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371.0; // km

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  /// Start the timer
  void _startTimer() {
    if (_isTimerRunning) return;

    _isTimerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedTime += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  /// Stop the timer
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _isTimerRunning = false;
  }

  /// Sync run to Apple Health / Google Fit
  Future<void> _syncRunToHealth({
    required DateTime? startTime,
    required DateTime endTime,
    required int durationSeconds,
    required double distanceKm,
    required int calories,
  }) async {
    if (startTime == null) return;

    try {
      final healthService = HealthService.instance;

      if (!healthService.isEnabled || !healthService.isAuthorized) {
        debugPrint('🏥 Health sync skipped - not enabled or authorized');
        return;
      }

      final success = await healthService.writeWorkout(
        startTime: startTime,
        endTime: endTime,
        totalCalories: calories,
        workoutType: 'running',
      );

      if (success) {
        debugPrint(
          '🏥 ✅ Run synced to Health: ${distanceKm.toStringAsFixed(2)} km, ~$calories cal',
        );
      } else {
        debugPrint('🏥 ⚠️ Failed to sync run to Health');
      }
    } catch (e) {
      debugPrint('🏥 ❌ Error syncing to Health: $e');
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear all running data (called on logout)
  Future<void> clear() async {
    _stopTimer();
    await _stopGpsTracking();
    _currentRun = null;
    _recentRuns = [];
    _weeklyStats = {};
    _errorMessage = null;
    _isLoading = false;
    _elapsedTime = Duration.zero;
    _isTimerRunning = false;
    _routePoints = [];
    _currentDistance = 0;
    _lastPosition = null;
    notifyListeners();
    debugPrint('🧹 RunningProvider cleared');
  }

  @override
  void dispose() {
    // Dispose is synchronous and cannot await cancellation - so state is
    // invalidated synchronously here, before the actual native unsubscribe
    // is fired off. Every GPS callback checks `_disposed` and the
    // generation before touching provider state or calling
    // notifyListeners(), so it is safe for the cancellation future below to
    // still be pending (or to never be observed) after this method
    // returns: nothing it later does can reach this instance's state again.
    _disposed = true;
    _stopTimer();

    _gpsGeneration++;
    final subscription = _positionStream;
    _positionStream = null;
    _gpsTrackingState = GpsTrackingState.stopped;
    if (subscription != null) {
      unawaited(_beginGpsCancellation(subscription));
    }

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
