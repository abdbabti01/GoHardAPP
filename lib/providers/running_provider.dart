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
import '../core/services/user_session_epoch.dart';

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

  /// Shared app-wide session-identity service. Every async method below
  /// that awaits a [RunningRepository] call captures a token via
  /// [UserSessionEpoch.capture] before its first await and rechecks
  /// `_sessionEpoch.isCurrent(token)` after every await - including inside
  /// catch/finally, and between two sequential repository calls in the same
  /// method - before touching currentRun/recentRuns/weeklyStats/
  /// errorMessage/isLoading or calling notifyListeners(). This drops any
  /// result that resolves after the session that requested it has ended
  /// (logout, or a different user logging in) instead of writing it into
  /// the shared provider instance the next session also uses.
  ///
  /// This is a SEPARATE boundary from [_gpsGeneration]/[_disposed]/
  /// [_gpsCancellationFuture]: those guard "is this GPS stream callback
  /// still current for the run/lifecycle this provider cares about, within
  /// a single session" and are entirely unchanged by this - a stale
  /// repository completion is dropped here, before it could ever reach the
  /// GPS-generation machinery. Neither mechanism replaces the other. [clear]
  /// is never itself gated by a captured token - it must always run
  /// immediately and unconditionally, since it is what a real logout relies
  /// on. In every real logout path (`AuthProvider._performLogout`),
  /// `UserSessionEpoch.invalidate()` runs synchronously BEFORE
  /// `SessionCleanupCoordinator.cleanUp()` calls [clear] - so by the time
  /// [clear] runs, any token already captured by an in-flight call below is
  /// already stale, and this class's own epoch checks are what keep that
  /// in-flight call from then resurrecting state [clear] just reset.
  ///
  /// Does not protect [RunningRepository]'s own local Isar writes or
  /// background sync pushes - see that class's own doc comment for that
  /// half of the fix.
  final UserSessionEpoch _sessionEpoch;

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

  // Monotonically increasing identity for "whoever most recently claimed
  // ownership of the ticker," bumped by EVERY _startTimer() call -
  // including a call that idempotently no-ops because a timer is already
  // running (see _startTimer()'s own doc comment for why a no-op call
  // still must claim ownership). This is deliberately independent of
  // whether a NEW physical Timer object was actually created: two
  // different logical start operations (e.g. session A's startNewRun(),
  // then session B's startNewRun() after A goes stale, arriving while
  // A's ticker is still physically running) can end up sharing the exact
  // same Timer instance via that idempotency, so object identity alone
  // cannot distinguish "my ticker" from "someone else's ticker" the way
  // it can for GPS subscriptions (_gpsGeneration). A stale A completion
  // must only ever stop the ticker via _stopTimerIfOwned(myGeneration) -
  // never the unconditional _stopTimer() - so that a generation mismatch
  // (B has since claimed ownership) correctly leaves B's ticker running
  // untouched, even when it is physically the same Timer object A
  // started.
  int _timerGeneration = 0;

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

  // Location settings used as a fallback for any platform without a
  // platform-specific override below - both iOS and Android now have their
  // own (see _resolveLocationSettings()).
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5, // Update every 5 meters
  );

  /// Foreground-service notification configuration for Android background
  /// location delivery on an explicitly user-started active run - the
  /// Android counterpart to Running Finding R2's iOS configuration PR:
  /// - Supplying [AndroidSettings.foregroundNotificationConfig] is what
  ///   makes geolocator_android 4.6.2 route position-stream creation through
  ///   `GeolocatorLocationService.startLocationService()` +
  ///   `enableBackgroundMode()` (see the plugin's `StreamHandlerImpl.onListen`)
  ///   instead of a plain, non-foreground location client. That method calls
  ///   the real `Service.startForeground()` API on a dedicated
  ///   `android.app.Service` the plugin already declares in its own
  ///   AndroidManifest.xml with `foregroundServiceType="location"` - this
  ///   app does not need to declare that service itself. This is what keeps
  ///   GPS delivering while the screen is locked or the app is backgrounded.
  /// - `setOngoing: true` makes the notification non-dismissible while a run
  ///   is being tracked, so it keeps clearly indicating that tracking is
  ///   active - a swipe-dismissible notification would let the foreground
  ///   service keep running invisibly, which the product requirement
  ///   explicitly rules out.
  /// - Tapping the notification returns to the app for free: the plugin's
  ///   `BackgroundNotification.buildBringToFrontIntent()` always attaches a
  ///   `PendingIntent` that relaunches the app's launcher activity. No
  ///   config field exists for this on geolocator_android 4.6.2, and none is
  ///   needed.
  /// - `notificationIcon` is deliberately left at its default
  ///   (`AndroidResource(name: 'ic_launcher', defType: 'mipmap')`), which is
  ///   exactly the `@mipmap/ic_launcher` icon already used by every other
  ///   notification in this app (push_notification_service.dart,
  ///   notification_service.dart) - no new drawable resource is introduced.
  /// - `enableWakeLock: true`: this foreground service represents an
  ///   explicitly user-started active workout - reliable GPS delivery while
  ///   the screen is locked is more important than minimizing power draw
  ///   for the run's duration, so the CPU is deliberately kept awake rather
  ///   than risking delayed/batched position updates. The wake lock is
  ///   scoped entirely to the lifetime of this subscription: geolocator_android's
  ///   `GeolocatorLocationService.obtainWakeLocks()` acquires it in the same
  ///   `enableBackgroundMode()` call that starts the foreground service, and
  ///   `disableBackgroundMode()` calls `releaseWakeLocks()` - which is
  ///   invoked by `StreamHandlerImpl.onCancel()` the moment this app cancels
  ///   the subscription (via `_stopGpsTracking()`/`dispose()`, unchanged by
  ///   this PR). There is no separate lifecycle to manage here - cancelling
  ///   the subscription is sufficient to release the wake lock, exactly like
  ///   it is sufficient to remove the notification and stop the service.
  /// - `enableWifiLock: false`: GPS tracking does not depend on Wi-Fi, so
  ///   there is no reason to hold the Wi-Fi radio awake - left at its
  ///   default.
  ///
  /// Actual stop-promptly behavior (pause/finish/discard/clear/disposal)
  /// requires no extra native code: every one of those paths already goes
  /// through `_stopGpsTracking()` or `dispose()`, both of which cancel the
  /// underlying subscription - and geolocator_android's
  /// `StreamHandlerImpl.onCancel()` responds to that cancellation by calling
  /// `stopLocationService()` + `disableBackgroundMode()`, which tears down
  /// the foreground service, releases the wake lock, and removes the
  /// notification, all together.
  static const ForegroundNotificationConfig
  _androidForegroundNotificationConfig = ForegroundNotificationConfig(
    notificationTitle: 'GoHard',
    notificationText: 'Tracking your run',
    notificationChannelName: 'Run Tracking',
    setOngoing: true,
    enableWakeLock: true,
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
  /// Android gets [AndroidSettings] with [_androidForegroundNotificationConfig]
  /// so the position stream keeps delivering while the app is backgrounded/
  /// the screen is locked for an explicitly user-started active run, backed
  /// by a real Android location foreground service and its ongoing
  /// notification - see [_androidForegroundNotificationConfig]'s doc comment
  /// for exactly how and why. `accuracy`/`distanceFilter` are preserved at
  /// the same values every other platform already used, unchanged by this
  /// PR.
  ///
  /// Any future platform without an explicit branch keeps using the
  /// existing [_locationSettings] value unchanged.
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
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: _androidForegroundNotificationConfig,
      );
    }
    return _locationSettings;
  }

  RunningProvider(
    this._runningRepository,
    this._sessionEpoch, [
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
  /// the current run is active/unpaused, belongs to a currently active
  /// session, and its subscription is known to be dead (`failed`) or was
  /// never started (`stopped`). A healthy (`starting`/`active`)
  /// subscription is left completely alone - this is what prevents a
  /// duplicate subscription on a routine resume, and what lets a
  /// genuinely healthy background stream keep delivering uninterrupted
  /// through the whole suspend/resume cycle. Calling this repeatedly (e.g.
  /// repeated `resumed` events) is idempotent: once recovery starts,
  /// `_startGpsTracking()`'s own guard prevents any further duplicate.
  ///
  /// Captures its own [UserSessionToken] synchronously, the instant the
  /// recovery event begins (before the `_currentRun` checks below, and
  /// before the only await in this method) - a lifecycle resume can fire
  /// at any point, including during a logged-out gap or immediately after
  /// a different user has logged in, and must never recover tracking
  /// attributed to a run/session pairing that no longer both hold.
  Future<void> _recoverGpsTrackingIfNeeded() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    if (_currentRun == null) return;
    if (_currentRun!.status != 'in_progress') return;
    if (_currentRun!.pausedAt != null) return;

    switch (_gpsTrackingState) {
      case GpsTrackingState.starting:
      case GpsTrackingState.active:
        return; // healthy, or already being (re)established - never duplicate
      case GpsTrackingState.stopped:
      case GpsTrackingState.failed:
        await _startGpsTracking(token);
    }
  }

  /// Load recent runs and weekly stats.
  ///
  /// Session-epoch guarded: [token] is captured before any await, and
  /// rechecked after each await - including between the two sequential
  /// repository calls, so a session that ends after the first call never
  /// dispatches the second on its behalf - before touching any field or
  /// calling notifyListeners(). If the session that requested this load has
  /// since ended, the response is dropped silently.
  Future<void> loadDashboardData() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final recentRuns = await _runningRepository.getRecentRuns(limit: 5);
      if (!_sessionEpoch.isCurrent(token)) return;

      final weeklyStats = await _runningRepository.getWeeklyStats();
      if (!_sessionEpoch.isCurrent(token)) return;

      _recentRuns = recentRuns;
      _weeklyStats = weeklyStats;
      _errorMessage = null;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage = 'Failed to load running data: $e';
      debugPrint('Load dashboard error: $e');
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Load a specific run session.
  ///
  /// Session-epoch guarded: see [loadDashboardData]'s doc comment.
  Future<void> loadRun(int localId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final run = await _runningRepository.getRunSession(localId);
      if (!_sessionEpoch.isCurrent(token)) return;
      _currentRun = run;

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
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage = 'Failed to load run: $e';
      debugPrint('Load run error: $e');
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create a draft run without starting (for navigation to active screen).
  ///
  /// Session-epoch guarded: [token] is captured before the FIRST await
  /// (the permission check), since a session can end during that await too,
  /// not only during the repository call.
  Future<int?> createDraftRun() async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;

    try {
      // Check location permissions first
      final hasPermission = await _checkLocationPermission();
      if (!_sessionEpoch.isCurrent(token)) return null;
      if (!hasPermission) {
        _errorMessage = 'Location permission required for running';
        notifyListeners();
        return null;
      }

      // Create new run session (draft status)
      final createdRun = await _runningRepository.createRunSession();
      if (!_sessionEpoch.isCurrent(token)) return null;

      _currentRun = createdRun;
      _elapsedTime = Duration.zero;
      _routePoints = [];
      _currentDistance = 0;
      _lastPosition = null;

      debugPrint('🏃 Draft run created: ${_currentRun!.id}');
      notifyListeners();
      return _currentRun!.id;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage = 'Failed to create run: $e';
      debugPrint('Create draft run error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Start the current run (called after countdown).
  ///
  /// Session-epoch guarded: see [createDraftRun]'s doc comment. GPS/timer
  /// lifecycle (`_startTimer`/`_startGpsTracking`) is unchanged - it is
  /// only reached at all once the repository result has already passed the
  /// epoch check below.
  Future<bool> startCurrentRun() async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    if (_currentRun == null) return false;

    try {
      // Start the run
      final startedRun = await _runningRepository.startRun(_currentRun!.id);
      if (!_sessionEpoch.isCurrent(token)) return false;
      _currentRun = startedRun;
      _elapsedTime = Duration.zero;

      final timerGeneration = _startTimer();
      await _startGpsTracking(token);
      if (!_sessionEpoch.isCurrent(token) || _currentRun == null) {
        // _startTimer() above ran while the token was still current, so a
        // stale rejection here must undo it - but only the ticker THIS
        // call started: a stale A here must never stop a newer session's
        // ticker via the unconditional _stopTimer(), including the case
        // where B's own _startTimer() call idempotently reused the exact
        // same Timer object A's call above did (see _timerGeneration's
        // field doc comment).
        _stopTimerIfOwned(timerGeneration);
        return false;
      }

      debugPrint('🏃 Run started: ${_currentRun!.id}');
      notifyListeners();
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage = 'Failed to start run: $e';
      debugPrint('Start run error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Create and start a new run (legacy method, still used for quick start).
  ///
  /// Session-epoch guarded: see [createDraftRun]'s doc comment. Rechecked
  /// between the create and start repository calls too, so a session that
  /// ends after the create never dispatches the start call on its behalf.
  Future<int?> startNewRun() async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;

    try {
      // Check location permissions first
      final hasPermission = await _checkLocationPermission();
      if (!_sessionEpoch.isCurrent(token)) return null;
      if (!hasPermission) {
        _errorMessage = 'Location permission required for running';
        notifyListeners();
        return null;
      }

      // Create new run session
      final createdRun = await _runningRepository.createRunSession();
      if (!_sessionEpoch.isCurrent(token)) return null;
      _currentRun = createdRun;

      // Start the run
      final startedRun = await _runningRepository.startRun(_currentRun!.id);
      if (!_sessionEpoch.isCurrent(token)) return null;
      _currentRun = startedRun;

      _elapsedTime = Duration.zero;
      _routePoints = [];
      _currentDistance = 0;
      _lastPosition = null;

      final timerGeneration = _startTimer();
      await _startGpsTracking(token);
      if (!_sessionEpoch.isCurrent(token) || _currentRun == null) {
        // _startTimer() above ran while the token was still current, so a
        // stale rejection here must undo it - but only the ticker THIS
        // call started: a stale A here must never stop a newer session's
        // ticker via the unconditional _stopTimer(), including the case
        // where B's own _startTimer() call idempotently reused the exact
        // same Timer object A's call above did (see _timerGeneration's
        // field doc comment).
        _stopTimerIfOwned(timerGeneration);
        return null;
      }

      debugPrint('🏃 New run started: ${_currentRun!.id}');
      notifyListeners();
      return _currentRun!.id;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return null;
      _errorMessage = 'Failed to start run: $e';
      debugPrint('Start run error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Pause the run.
  ///
  /// Session-epoch guarded: [token] is captured before the FIRST await
  /// (`_stopGpsTracking`, unchanged GPS lifecycle logic). Rechecked
  /// immediately after that await, together with a fresh `_currentRun !=
  /// null` check, before ever touching `_currentRun` again - a concurrent
  /// `clear()` (which always runs immediately and unconditionally on
  /// logout, before this token's own epoch invalidation is even visible
  /// here) may have already nulled it out from under this still-in-flight
  /// call.
  Future<void> pauseRun() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    if (_currentRun == null) return;

    if (_currentRun!.startedAt == null) {
      await startNewRun();
      return;
    }

    final nowUtc = DateTime.now().toUtc();

    _stopTimer();
    await _stopGpsTracking();
    if (!_sessionEpoch.isCurrent(token) || _currentRun == null) return;

    _currentRun = _currentRun!.copyWith(pausedAt: nowUtc);
    notifyListeners();

    try {
      await _runningRepository.pauseRun(_currentRun!.id, nowUtc);
      if (!_sessionEpoch.isCurrent(token)) return;
      debugPrint('⏸️ Run paused - saved to DB');
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage = 'Failed to pause run: $e';
      debugPrint('Pause run error: $e');
      notifyListeners();
    }
  }

  /// Resume the run.
  ///
  /// Session-epoch guarded: see [pauseRun]'s doc comment. The optimistic
  /// `_currentRun` update and `_startTimer()`/`_startGpsTracking()` call
  /// happen before any await can occur (unchanged GPS/timer lifecycle), so
  /// the epoch is rechecked right after that await instead, before
  /// `notifyListeners()` or the repository call can reach a since-cleared
  /// `_currentRun`.
  Future<void> resumeRun() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
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

    final timerGeneration = _startTimer();
    await _startGpsTracking(token);
    if (!_sessionEpoch.isCurrent(token) || _currentRun == null) {
      // _startTimer() above ran while the token was still current, so a
      // stale rejection here must undo it - but only the ticker THIS call
      // started: a stale A here must never stop a newer session's ticker
      // via the unconditional _stopTimer(), including the case where B's
      // own _startTimer() call idempotently reused the exact same Timer
      // object A's call above did (see _timerGeneration's field doc
      // comment).
      _stopTimerIfOwned(timerGeneration);
      return;
    }
    notifyListeners();

    try {
      await _runningRepository.resumeRun(_currentRun!.id, newStartedAt);
      if (!_sessionEpoch.isCurrent(token)) return;
      debugPrint('▶️ Run resumed - saved to DB');
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage = 'Failed to resume run: $e';
      debugPrint('Resume run error: $e');
      notifyListeners();
    }
  }

  /// Finish the run.
  ///
  /// Session-epoch guarded: [token] is captured before the FIRST await
  /// (`_stopGpsTracking`, unchanged GPS lifecycle logic), and rechecked
  /// after every subsequent await - including before the unawaited
  /// `_syncRunToHealth` fire-and-forget call and the nested
  /// `loadDashboardData()` call (which is independently epoch-guarded on
  /// its own, but must not even be dispatched on a stale session's behalf).
  Future<bool> finishRun() async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    if (_currentRun == null) return false;

    try {
      _stopTimer();
      await _stopGpsTracking();
      if (!_sessionEpoch.isCurrent(token) || _currentRun == null) {
        return false;
      }

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

      final completedRun = await _runningRepository.completeRun(
        _currentRun!.id,
        duration: duration,
        distance: distance,
        averagePace: pace,
        calories: calories,
        route: _routePoints,
      );
      if (!_sessionEpoch.isCurrent(token)) return false;
      _currentRun = completedRun;

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
      if (!_sessionEpoch.isCurrent(token)) return false;

      debugPrint(
        '🏁 Run finished: ${distance.toStringAsFixed(2)} km in ${duration}s',
      );
      notifyListeners();
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage = 'Failed to finish run: $e';
      debugPrint('Finish run error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Discard current run.
  ///
  /// Session-epoch guarded: see [finishRun]'s doc comment. In particular,
  /// `_currentRun = null` and the rest of the in-memory reset only happen
  /// once the delete has been confirmed still current - a stale discard
  /// must never null out a `_currentRun` that a fresh User B operation has
  /// since populated.
  Future<void> discardRun() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    if (_currentRun == null) return;

    try {
      _stopTimer();
      await _stopGpsTracking();
      if (!_sessionEpoch.isCurrent(token) || _currentRun == null) return;

      await _runningRepository.deleteRun(_currentRun!.id);
      if (!_sessionEpoch.isCurrent(token)) return;

      _currentRun = null;
      _elapsedTime = Duration.zero;
      _routePoints = [];
      _currentDistance = 0;
      _lastPosition = null;

      debugPrint('🗑️ Run discarded');
      notifyListeners();
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
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

  /// Start GPS tracking, bound to [token] - the SAME
  /// [UserSessionToken] the caller already captured for its own operation,
  /// never re-captured here. This is what makes GPS startup itself
  /// session-aware: a start initiated by session A must never commit a
  /// subscription once A's token is no longer current, including a
  /// different user (B) having since logged in - passing the caller's
  /// already-captured token (rather than calling
  /// `_sessionEpoch.capture()` again inside this method) is what prevents
  /// a resumed, formerly-A call from silently adopting B's token.
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
  ///
  /// [_sessionEpoch.isCurrent(token)] is rechecked exactly once, as the
  /// FIRST statement after the pending-cancellation await (and its own
  /// pre-existing run-identity re-validation) resolves - covering both
  /// "after any pending-cancellation await" and "immediately before
  /// creating/listening to the new position stream" in a single
  /// checkpoint, since nothing else in this method ever awaits between
  /// that point and the synchronous `Geolocator.getPositionStream(...)
  /// .listen(...)` call below. Because that entire remaining span is
  /// synchronous (no `await`), Dart's single-threaded execution makes it
  /// atomic with this check: nothing else can run and invalidate the
  /// token between the check passing and the subscription actually being
  /// created, so a stale token can never reach `.listen()` - there is no
  /// narrower boundary left to close.
  Future<void> _startGpsTracking(UserSessionToken token) async {
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

    // See this method's doc comment: this single checkpoint covers both
    // "after the pending-cancellation await" and "immediately before
    // listen()", since nothing awaits in between.
    if (!_sessionEpoch.isCurrent(token)) return;

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

  /// Start the ticker, returning the [_timerGeneration] this call now
  /// owns. ALWAYS bumps the generation, even when idempotently no-op'ing
  /// because a ticker is already running - see [_timerGeneration]'s own
  /// field doc comment for why a no-op call still claims ownership.
  /// Callers on a session-epoch-guarded path (`startCurrentRun`,
  /// `startNewRun`, `resumeRun`) that may later need to undo this specific
  /// call after a stale rejection MUST capture the returned generation and
  /// pass it to [_stopTimerIfOwned] - never call the unconditional
  /// [_stopTimer] from a stale completion. Callers that are not gating a
  /// later conditional stop (e.g. `loadRun`'s unconditional restore) may
  /// simply ignore the return value, exactly as before this method
  /// returned anything.
  int _startTimer() {
    final generation = ++_timerGeneration;
    if (_isTimerRunning) return generation;

    _isTimerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedTime += const Duration(seconds: 1);
      notifyListeners();
    });
    return generation;
  }

  /// Stop the ticker unconditionally. Reserved for a caller acting on its
  /// OWN still-current session (pause/finish/discard/clear/dispose, all of
  /// which call this before their own first await, or - for clear/dispose
  /// - as the authoritative "everything stops now" reset) - never call
  /// this from a stale completion path. See [_stopTimerIfOwned] for that
  /// case.
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _isTimerRunning = false;
  }

  /// Stop the ticker only if [generation] still matches [_timerGeneration]
  /// - i.e. only if nothing else has called [_startTimer] since this
  /// caller's own call. Used exclusively by a stale rejection (in
  /// `startCurrentRun`/`startNewRun`/`resumeRun`, after `await
  /// _startGpsTracking(token)` finds the session no longer current) to
  /// undo the ticker THAT SPECIFIC CALL started, without ever touching a
  /// newer session's ticker - including the case where a newer session's
  /// own `_startTimer()` call idempotently reused the exact same physical
  /// `Timer` object (see [_timerGeneration]'s field doc comment): the
  /// generation mismatch alone is what correctly leaves that ticker
  /// running, independent of `Timer` object identity.
  void _stopTimerIfOwned(int generation) {
    if (generation != _timerGeneration) return;
    _stopTimer();
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
