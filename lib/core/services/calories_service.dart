/// Service for estimating calories burned during workouts
/// Uses MET (Metabolic Equivalent of Task) values for more accurate calculations
///
/// Formula: Calories = MET × weight (kg) × duration (hours)
class CaloriesService {
  // MET values for different workout types
  static const Map<String, double> _metValues = {
    // Strength training
    'strength': 5.0, // Moderate effort weight training
    'strength_light': 3.5, // Light effort
    'strength_vigorous': 6.0, // Vigorous effort
    // Cardio
    'cardio': 7.0, // General cardio
    'running': 9.8, // Running 6 mph (10 min/mile)
    'running_slow': 8.0, // Running 5 mph (12 min/mile)
    'running_fast': 11.5, // Running 7 mph (8.5 min/mile)
    'cycling': 7.5, // Moderate cycling
    'swimming': 8.0, // Moderate swimming
    'rowing': 7.0, // Moderate rowing
    // Other
    'mixed': 5.5, // Mixed workout
    'hiit': 8.0, // High intensity interval training
    'yoga': 2.5, // Hatha yoga
    'stretching': 2.3, // Stretching
    'walking': 3.5, // Walking 3.5 mph
  };

  // Default weight to use if user weight is unknown (average adult)
  static const double _defaultWeight = 70.0; // kg

  /// Estimate calories burned for a strength/general workout
  ///
  /// [durationMinutes] - workout duration in minutes
  /// [userWeightKg] - user's weight in kg (uses default if null)
  /// [workoutType] - type of workout (strength, cardio, mixed, etc.)
  /// [intensity] - optional intensity modifier (0.5 = light, 1.0 = normal, 1.5 = vigorous)
  static int estimateWorkoutCalories({
    required int durationMinutes,
    double? userWeightKg,
    String workoutType = 'strength',
    double intensity = 1.0,
  }) {
    final weight = userWeightKg ?? _defaultWeight;
    final durationHours = durationMinutes / 60.0;

    // Get MET value for workout type, default to strength if unknown
    final baseMet =
        _metValues[workoutType.toLowerCase()] ?? _metValues['strength']!;

    // Apply intensity modifier (clamped to reasonable range)
    final adjustedMet = baseMet * intensity.clamp(0.5, 2.0);

    // Calculate calories: MET × weight × hours
    final calories = adjustedMet * weight * durationHours;

    return calories.round();
  }

  /// Estimate calories burned for a running session
  ///
  /// [distanceKm] - distance covered in kilometers
  /// [durationMinutes] - duration in minutes
  /// [userWeightKg] - user's weight in kg (uses default if null)
  static int estimateRunningCalories({
    required double distanceKm,
    required int durationMinutes,
    double? userWeightKg,
  }) {
    final weight = userWeightKg ?? _defaultWeight;

    if (distanceKm <= 0 || durationMinutes <= 0) {
      return 0;
    }

    // Calculate pace (min/km)
    final paceMinPerKm = durationMinutes / distanceKm;

    // Determine MET based on pace
    double met;
    if (paceMinPerKm <= 6.0) {
      // Faster than 6 min/km (10 km/h+) - fast running
      met = _metValues['running_fast']!;
    } else if (paceMinPerKm <= 8.0) {
      // 6-8 min/km - moderate running
      met = _metValues['running']!;
    } else if (paceMinPerKm <= 10.0) {
      // 8-10 min/km - slow running/jogging
      met = _metValues['running_slow']!;
    } else {
      // Slower than 10 min/km - fast walking/very slow jog
      met = _metValues['walking']! + 2.0; // ~5.5 MET
    }

    final durationHours = durationMinutes / 60.0;
    final calories = met * weight * durationHours;

    return calories.round();
  }

  /// Get the MET value for a workout type
  static double getMetValue(String workoutType) {
    return _metValues[workoutType.toLowerCase()] ?? _metValues['strength']!;
  }

  /// Get all available workout types
  static List<String> get availableWorkoutTypes => _metValues.keys.toList();
}
