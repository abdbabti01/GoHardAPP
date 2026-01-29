import 'dart:async';
import 'package:flutter/widgets.dart';
import '../data/models/session.dart';
import '../data/models/exercise.dart';
import '../data/repositories/session_repository.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/health_service.dart';
import '../core/services/calories_service.dart';

/// Provider for active workout session with timer
/// Replaces ActiveWorkoutViewModel from MAUI app
class ActiveWorkoutProvider extends ChangeNotifier with WidgetsBindingObserver {
  final SessionRepository _sessionRepository;
  final ConnectivityService? _connectivity;

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

  ActiveWorkoutProvider(this._sessionRepository, [this._connectivity]) {
    // Register app lifecycle observer to detect when app resumes
    WidgetsBinding.instance.addObserver(this);

    // Listen for connectivity changes and refresh session when going online
    // BUT NOT for in_progress sessions - their timestamps are authoritative in memory
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      debugPrint('⏱️ App resumed - recalculating elapsed time');
      // Recalculate elapsed time immediately for responsive UI
      _recalculateElapsedTime();

      // CRITICAL FIX: For in-progress sessions, DON'T reload from DB!
      // The in-memory state has correct UTC timestamps. Reloading from DB
      // could load corrupted timestamps (from before the UTC fix was deployed).
      // Only reload for non-active sessions (draft, completed, etc.)
      if (_currentSession != null && _currentSession!.status != 'in_progress') {
        debugPrint(
          '🔄 Reloading session ${_currentSession!.id} from DB after resume (not in_progress)',
        );
        loadSession(_currentSession!.id, showLoading: false);
      } else if (_currentSession != null) {
        debugPrint(
          '🏋️ In-progress session - keeping in-memory timestamps (startedAt: ${_currentSession!.startedAt})',
        );
      }
    }
  }

  /// Recalculate elapsed time based on current time and startedAt timestamp
  void _recalculateElapsedTime() {
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
      calculated = DateTime.now().toUtc().difference(
        _currentSession!.startedAt!,
      );
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
    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      _currentSession = await _sessionRepository.getSession(sessionId);

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
          shouldBeRunning = false;
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
          shouldBeRunning = _currentSession?.status == 'in_progress';
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
    } catch (e) {
      _errorMessage =
          'Failed to load session: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load session error: $e');
    } finally {
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  /// Start the workout timer
  void _startTimer() {
    if (_isTimerRunning) return;

    _isTimerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedTime += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  /// Stop the workout timer
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _isTimerRunning = false;
  }

  /// Start workout (update status to in_progress)
  Future<void> startWorkout() async {
    if (_currentSession == null) return;

    try {
      // CRITICAL: Check for any existing in-progress sessions
      // Only one workout can be active at a time
      final inProgressSessions =
          await _sessionRepository.getInProgressSessions();

      for (final session in inProgressSessions) {
        // Skip if it's the current session
        if (session.id == _currentSession!.id) continue;

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

        debugPrint(
          '✅ Auto-completed workout ${session.id} with duration: $duration minutes',
        );
      }

      // CRITICAL FIX: Calculate UTC timestamp HERE (same pattern as pauseTimer)
      // This ensures consistent UTC handling - calculating inside Isar transactions
      // was causing the 5-hour bug where local time was treated as UTC
      final startedAtUtc = DateTime.now().toUtc();
      debugPrint('🏋️ Starting workout with UTC timestamp: $startedAtUtc');
      debugPrint('   DateTime.now(): ${DateTime.now()}');
      debugPrint('   DateTime.now().toUtc(): $startedAtUtc');
      debugPrint('   startedAtUtc.isUtc: ${startedAtUtc.isUtc}');
      debugPrint('   startedAtUtc.hour: ${startedAtUtc.hour}');

      // Now start the new workout - pass UTC timestamp to repository
      final updatedSession = await _sessionRepository.updateSessionStatus(
        _currentSession!.id,
        'in_progress',
        startedAtUtc: startedAtUtc,
      );

      // Use the session from DB to ensure timestamps match
      _currentSession = updatedSession;
      _elapsedTime = Duration.zero;
      _startTimer();
      debugPrint('🏋️ Workout started with provider-calculated UTC timestamp');
      notifyListeners();
    } catch (e) {
      _errorMessage =
          'Failed to start workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Start workout error: $e');
      notifyListeners();
    }
  }

  /// Pause the timer (keeps session in_progress but stops timer)
  Future<void> pauseTimer() async {
    if (_currentSession == null) return;

    // If session hasn't started yet, start it first
    if (_currentSession!.startedAt == null) {
      await startWorkout();
      return;
    }

    // Calculate timestamp ONCE to avoid drift
    final nowUtc = DateTime.now().toUtc(); // CRITICAL: Use UTC

    // Update UI IMMEDIATELY - don't wait for anything
    _stopTimer();
    _currentSession = _currentSession!.copyWith(
      pausedAt: nowUtc, // Store as UTC
    );
    notifyListeners();
    debugPrint('⏸️ Timer paused (UI updated) - pausedAt UTC: $nowUtc');

    // CRITICAL FIX #10 & #1: AWAIT the pause to ensure local DB write completes
    // This prevents timer drift if app is killed before sync completes
    // Repository method writes to Isar synchronously, then syncs to API in background
    try {
      await _sessionRepository.pauseSession(_currentSession!.id, nowUtc);
      debugPrint('✅ Pause persisted to local DB - timer state safe');
    } catch (e) {
      _errorMessage =
          'Failed to pause: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Pause error: $e');
      notifyListeners();
    }
  }

  /// Resume the timer (continues from current elapsed time)
  Future<void> resumeTimer() async {
    if (_currentSession == null) return;

    // If session hasn't started yet, start it instead of resuming
    if (_currentSession!.startedAt == null) {
      await startWorkout();
      return;
    }

    // Calculate adjusted startedAt ONCE to avoid drift
    final now = DateTime.now().toUtc();
    final pauseDuration =
        _currentSession!.pausedAt != null
            ? now.difference(_currentSession!.pausedAt!)
            : Duration.zero;
    final newStartedAt = _currentSession!.startedAt!.add(pauseDuration);

    // Update UI IMMEDIATELY - don't wait for anything
    _currentSession = _currentSession!.copyWith(
      startedAt: newStartedAt,
      pausedAt: null, // Clear pausedAt
    );

    // Resume timer
    _startTimer();
    notifyListeners();
    debugPrint('▶️ Timer resumed (UI updated) - new startedAt: $newStartedAt');

    // CRITICAL FIX #10 & #1: AWAIT the resume to ensure local DB write completes
    // This prevents timer drift if app is killed before sync completes
    // Repository method writes to Isar synchronously, then syncs to API in background
    try {
      await _sessionRepository.resumeSession(_currentSession!.id, newStartedAt);
      debugPrint('✅ Resume persisted to local DB - timer state safe');
    } catch (e) {
      _errorMessage =
          'Failed to resume: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('❌ Resume error: $e');
      notifyListeners();
    }
  }

  /// Finish workout (update status to completed)
  Future<bool> finishWorkout() async {
    if (_currentSession == null) return false;

    try {
      _stopTimer();

      // Calculate workout duration in minutes from elapsed time
      final durationMinutes = _elapsedTime.inMinutes;
      debugPrint('🏁 Finishing workout - Duration: $durationMinutes minutes');

      // Store start time before updating session (for health sync)
      final workoutStartTime = _currentSession!.startedAt;
      final workoutEndTime = DateTime.now();
      final workoutType = _currentSession!.type ?? 'strength';

      _currentSession = await _sessionRepository.updateSessionStatus(
        _currentSession!.id,
        'completed',
        duration: durationMinutes,
      );

      // Sync to Apple Health / Google Fit if enabled
      _syncWorkoutToHealth(
        startTime: workoutStartTime,
        endTime: workoutEndTime,
        durationMinutes: durationMinutes,
        workoutType: workoutType,
      );

      notifyListeners();
      return true;
    } catch (e) {
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
    if (_currentSession == null) return false;

    try {
      _currentSession = await _sessionRepository.updateSessionName(
        _currentSession!.id,
        name,
      );
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage =
          'Failed to update workout name: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update workout name error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Add exercise to current session
  Future<void> addExercise(int exerciseTemplateId) async {
    if (_currentSession == null) return;

    try {
      // Add exercise and get the new exercise object
      final newExercise = await _sessionRepository.addExerciseToSession(
        _currentSession!.id,
        exerciseTemplateId,
      );

      // Add exercise to current session's list (don't reload entire session)
      final updatedExercises = [..._currentSession!.exercises, newExercise];
      _currentSession = _currentSession!.copyWith(exercises: updatedExercises);

      debugPrint('✅ Exercise added to session (timer preserved)');
      notifyListeners();
    } catch (e) {
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
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

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
      _currentSession = createdSession;

      debugPrint('✅ Created AI workout session: ${createdSession.id}');

      // Add exercises to the session
      for (final templateId in exerciseTemplateIds) {
        try {
          final exercise = await _sessionRepository.addExerciseToSession(
            createdSession.id,
            templateId,
          );
          // Add to current session's list
          final updatedExercises = [..._currentSession!.exercises, exercise];
          _currentSession = _currentSession!.copyWith(
            exercises: updatedExercises,
          );
          debugPrint('  ✅ Added exercise: ${exercise.name}');
        } catch (e) {
          debugPrint('  ⚠️ Failed to add exercise template $templateId: $e');
          // Continue adding other exercises even if one fails
        }
      }

      notifyListeners();
      return createdSession.id;
    } catch (e) {
      _errorMessage =
          'Failed to create workout: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create workout from AI error: $e');
      notifyListeners();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear all workout data (called on logout)
  void clear() {
    _stopTimer();
    _currentSession = null;
    _errorMessage = null;
    _isLoading = false;
    _elapsedTime = Duration.zero;
    _isTimerRunning = false;
    notifyListeners();
    debugPrint('🧹 ActiveWorkoutProvider cleared');
  }

  @override
  void dispose() {
    _stopTimer();
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
