import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for integrating with Apple Health / Google Fit
/// Provides read/write access to health and fitness data
class HealthService extends ChangeNotifier {
  static final HealthService _instance = HealthService._internal();
  static HealthService get instance => _instance;

  HealthService._internal();

  final Health _health = Health();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _healthEnabledKey = 'health_integration_enabled';

  bool _isAuthorized = false;
  bool _isEnabled = false;
  bool _isAvailable = false;

  // Getters
  bool get isAuthorized => _isAuthorized;
  bool get isEnabled => _isEnabled;
  bool get isAvailable => _isAvailable;

  /// Health data types we need to read/write
  static final List<HealthDataType> _readTypes = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
  ];

  static final List<HealthDataType> _writeTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  /// Initialize the health service
  Future<void> initialize() async {
    try {
      // Check if health is available on this platform
      _isAvailable = Platform.isIOS || Platform.isAndroid;

      if (!_isAvailable) {
        debugPrint('🏥 Health integration not available on this platform');
        return;
      }

      // Load enabled state from storage
      final enabled = await _storage.read(key: _healthEnabledKey);
      _isEnabled = enabled == 'true';

      if (_isEnabled) {
        // Check if we still have authorization
        _isAuthorized = await _checkAuthorization();
      }

      debugPrint(
        '🏥 Health service initialized - enabled: $_isEnabled, authorized: $_isAuthorized',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('🏥 Error initializing health service: $e');
      _isAvailable = false;
    }
  }

  /// Check if we have authorization
  Future<bool> _checkAuthorization() async {
    try {
      // On iOS, we can check if we have authorization
      // On Android, we need to request permissions to check
      if (Platform.isIOS) {
        return await _health.hasPermissions(_readTypes) ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('🏥 Error checking authorization: $e');
      return false;
    }
  }

  /// Request permissions for health data
  Future<bool> requestPermissions() async {
    if (!_isAvailable) return false;

    try {
      // Configure the health plugin
      await _health.configure();

      // Request authorization
      final authorized = await _health.requestAuthorization(
        _readTypes,
        permissions:
            _writeTypes.map((_) => HealthDataAccess.READ_WRITE).toList(),
      );

      _isAuthorized = authorized;

      if (authorized) {
        _isEnabled = true;
        await _storage.write(key: _healthEnabledKey, value: 'true');
      }

      debugPrint('🏥 Health permissions requested - authorized: $authorized');
      notifyListeners();
      return authorized;
    } catch (e) {
      debugPrint('🏥 Error requesting health permissions: $e');
      return false;
    }
  }

  /// Disable health integration
  Future<void> disable() async {
    _isEnabled = false;
    await _storage.write(key: _healthEnabledKey, value: 'false');
    notifyListeners();
    debugPrint('🏥 Health integration disabled');
  }

  /// Enable health integration (requests permissions if needed)
  Future<bool> enable() async {
    if (!_isAvailable) return false;

    if (!_isAuthorized) {
      return await requestPermissions();
    }

    _isEnabled = true;
    await _storage.write(key: _healthEnabledKey, value: 'true');
    notifyListeners();
    debugPrint('🏥 Health integration enabled');
    return true;
  }

  /// Write a completed workout to health
  Future<bool> writeWorkout({
    required DateTime startTime,
    required DateTime endTime,
    required int totalCalories,
    required String workoutType,
  }) async {
    if (!_isEnabled || !_isAuthorized) {
      debugPrint('🏥 Cannot write workout - not enabled or authorized');
      return false;
    }

    try {
      // Map workout type to health workout type
      final healthWorkoutType = _mapWorkoutType(workoutType);

      // Write workout
      final success = await _health.writeWorkoutData(
        activityType: healthWorkoutType,
        start: startTime,
        end: endTime,
        totalEnergyBurned: totalCalories,
        totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
      );

      debugPrint('🏥 Workout written to health: $success');
      return success;
    } catch (e) {
      debugPrint('🏥 Error writing workout: $e');
      return false;
    }
  }

  /// Get steps for today
  Future<int> getStepsToday() async {
    if (!_isEnabled || !_isAuthorized) return 0;

    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);

      final steps = await _health.getTotalStepsInInterval(midnight, now);
      debugPrint('🏥 Steps today: $steps');
      return steps ?? 0;
    } catch (e) {
      debugPrint('🏥 Error getting steps: $e');
      return 0;
    }
  }

  /// Get heart rate data for a time range
  Future<List<HealthDataPoint>> getHeartRateData({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (!_isEnabled || !_isAuthorized) return [];

    try {
      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: startTime,
        endTime: endTime,
      );

      debugPrint('🏥 Got ${data.length} heart rate data points');
      return data;
    } catch (e) {
      debugPrint('🏥 Error getting heart rate data: $e');
      return [];
    }
  }

  /// Get average heart rate for a time range
  Future<double?> getAverageHeartRate({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final data = await getHeartRateData(startTime: startTime, endTime: endTime);
    if (data.isEmpty) return null;

    final total = data.fold<double>(
      0,
      (sum, point) => sum + (point.value as NumericHealthValue).numericValue,
    );
    return total / data.length;
  }

  /// Get active calories burned today
  Future<int> getActiveCaloriesToday() async {
    if (!_isEnabled || !_isAuthorized) return 0;

    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);

      final data = await _health.getHealthDataFromTypes(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: midnight,
        endTime: now,
      );

      final total = data.fold<double>(
        0,
        (sum, point) => sum + (point.value as NumericHealthValue).numericValue,
      );

      debugPrint('🏥 Active calories today: ${total.toInt()}');
      return total.toInt();
    } catch (e) {
      debugPrint('🏥 Error getting active calories: $e');
      return 0;
    }
  }

  /// Map our workout types to Health workout types
  HealthWorkoutActivityType _mapWorkoutType(String workoutType) {
    final type = workoutType.toLowerCase();

    if (type.contains('strength') ||
        type.contains('weight') ||
        type.contains('lift')) {
      return HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING;
    } else if (type.contains('cardio') ||
        type.contains('run') ||
        type.contains('jog')) {
      return HealthWorkoutActivityType.RUNNING;
    } else if (type.contains('hiit') || type.contains('interval')) {
      return HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING;
    } else if (type.contains('yoga') || type.contains('stretch')) {
      return HealthWorkoutActivityType.YOGA;
    } else if (type.contains('cycle') || type.contains('bike')) {
      return HealthWorkoutActivityType.BIKING;
    } else if (type.contains('swim')) {
      return HealthWorkoutActivityType.SWIMMING;
    } else if (type.contains('walk')) {
      return HealthWorkoutActivityType.WALKING;
    } else if (type.contains('row')) {
      return HealthWorkoutActivityType.ROWING;
    } else if (type.contains('cross') || type.contains('functional')) {
      return HealthWorkoutActivityType.CROSS_TRAINING;
    } else {
      return HealthWorkoutActivityType.OTHER;
    }
  }

  /// Get health status summary
  Future<HealthSummary> getHealthSummary() async {
    final steps = await getStepsToday();
    final calories = await getActiveCaloriesToday();

    return HealthSummary(
      stepsToday: steps,
      activeCaloriesToday: calories,
      isConnected: _isEnabled && _isAuthorized,
    );
  }
}

/// Summary of health data
class HealthSummary {
  final int stepsToday;
  final int activeCaloriesToday;
  final bool isConnected;

  HealthSummary({
    required this.stepsToday,
    required this.activeCaloriesToday,
    required this.isConnected,
  });
}
