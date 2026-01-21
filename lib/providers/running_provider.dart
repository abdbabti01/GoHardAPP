import 'dart:async';
import 'dart:math' show sin, cos, sqrt, atan2, pi;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import '../data/models/run_session.dart';
import '../data/models/gps_point.dart';
import '../data/repositories/running_repository.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/health_service.dart';

/// Provider for active running session with timer and GPS tracking
class RunningProvider extends ChangeNotifier with WidgetsBindingObserver {
  final RunningRepository _runningRepository;
  // ignore: unused_field - Reserved for future online/offline status checks
  final ConnectivityService? _connectivity;

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
  bool _isGpsActive = false;

  // Location settings
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5, // Update every 5 meters
  );

  RunningProvider(this._runningRepository, [this._connectivity]) {
    WidgetsBinding.instance.addObserver(this);
  }

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
  bool get isGpsActive => _isGpsActive;
  bool get hasActiveRun =>
      _currentRun != null && _currentRun!.status == 'in_progress';

  /// Current pace in min/km
  double? get currentPace {
    if (_currentDistance <= 0 || _elapsedTime.inSeconds <= 0) return null;
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

    if (state == AppLifecycleState.resumed) {
      debugPrint('⏱️ App resumed - recalculating elapsed time');
      _recalculateElapsedTime();
    }
  }

  void _recalculateElapsedTime() {
    if (_currentRun == null || _currentRun!.startedAt == null) return;

    final Duration calculated;

    if (_currentRun!.pausedAt != null) {
      calculated = _currentRun!.pausedAt!.difference(_currentRun!.startedAt!);
      debugPrint('  Timer PAUSED - recalculated: ${calculated.inSeconds}s');
    } else {
      calculated = DateTime.now().toUtc().difference(_currentRun!.startedAt!);
      debugPrint('  Timer RUNNING - recalculated: ${calculated.inSeconds}s');
    }

    _elapsedTime = calculated.isNegative ? Duration.zero : calculated;
    notifyListeners();
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

  /// Create and start a new run
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
    _stopGpsTracking();

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

    _currentRun = _currentRun!.copyWith(
      startedAt: newStartedAt,
      pausedAt: null,
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
      _stopGpsTracking();

      final duration = _elapsedTime.inSeconds;
      final distance = _currentDistance;
      final pace = distance > 0 ? (duration / 60) / distance : null;

      // Estimate calories (rough: ~60 cal/km for running)
      final calories = (distance * 60).round();

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
      _stopGpsTracking();

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

  /// Start GPS tracking
  Future<void> _startGpsTracking() async {
    if (_isGpsActive) return;

    _isGpsActive = true;
    _positionStream = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(_onPositionUpdate);

    debugPrint('📍 GPS tracking started');
  }

  /// Stop GPS tracking
  void _stopGpsTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isGpsActive = false;
    debugPrint('📍 GPS tracking stopped');
  }

  /// Handle GPS position update
  void _onPositionUpdate(Position position) {
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
  void clear() {
    _stopTimer();
    _stopGpsTracking();
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
    _stopTimer();
    _stopGpsTracking();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
