/// Service for goal validation and AI-powered suggestions
///
/// Provides validation logic for goal realism, suggested dates,
/// and rate calculations that can be shared across the app.
class GoalValidationService {
  static GoalValidationService? _instance;

  /// Singleton instance
  static GoalValidationService get instance {
    _instance ??= GoalValidationService._();
    return _instance!;
  }

  GoalValidationService._();

  // ============ Constants ============

  /// Maximum healthy weekly weight loss (lbs)
  static const double maxWeeklyWeightLoss = 2.5;

  /// Maximum realistic weekly muscle gain (lbs)
  static const double maxWeeklyMuscleGain = 1.0;

  /// Maximum body fat loss per month (%)
  static const double maxMonthlyBodyFatLoss = 1.5;

  /// Healthy weekly weight loss rate for date calculation (lbs)
  static const double healthyWeeklyWeightLoss = 1.5;

  /// Healthy weekly muscle gain rate for date calculation (lbs)
  static const double healthyWeeklyMuscleGain = 0.75;

  /// Healthy monthly body fat loss rate (%)
  static const double healthyMonthlyBodyFatLoss = 0.75;

  // ============ Validation ============

  /// Validates if a goal is realistic and healthy
  ///
  /// Returns a [GoalValidationResult] containing:
  /// - [isValid]: Whether the goal passes validation
  /// - [warning]: Warning message if goal is unrealistic (null if valid)
  /// - [severity]: 'error' for invalid, 'warning' for achievable but risky
  GoalValidationResult validateGoalRealism({
    required String goalType,
    required double currentValue,
    required double targetValue,
    DateTime? targetDate,
    int defaultWeeks = 12,
  }) {
    final change = (targetValue - currentValue).abs();
    final weeks =
        targetDate != null
            ? targetDate.difference(DateTime.now()).inDays / 7
            : defaultWeeks.toDouble();

    // Check if target equals current
    if (targetValue == currentValue) {
      return GoalValidationResult(
        isValid: false,
        warning: 'Target value is the same as current value.',
        severity: ValidationSeverity.error,
      );
    }

    switch (goalType) {
      case 'Weight Loss':
        return _validateWeightLoss(currentValue, targetValue, change, weeks);

      case 'Muscle Gain':
        return _validateMuscleGain(currentValue, targetValue, change, weeks);

      case 'Body Fat':
        return _validateBodyFat(change, weeks);

      default:
        return GoalValidationResult(isValid: true);
    }
  }

  GoalValidationResult _validateWeightLoss(
    double currentValue,
    double targetValue,
    double change,
    double weeks,
  ) {
    // Check direction
    if (targetValue >= currentValue) {
      return GoalValidationResult(
        isValid: false,
        warning:
            'Target weight should be less than current weight for weight loss.',
        severity: ValidationSeverity.error,
      );
    }

    // Check rate
    final weeklyLoss = weeks > 0 ? change / weeks : change;
    if (weeklyLoss > maxWeeklyWeightLoss) {
      return GoalValidationResult(
        isValid: true, // Allow but warn
        warning:
            'Losing more than 2 lbs/week is unhealthy. '
            'Your goal requires ${weeklyLoss.toStringAsFixed(1)} lbs/week.',
        severity: ValidationSeverity.warning,
      );
    }

    return GoalValidationResult(isValid: true);
  }

  GoalValidationResult _validateMuscleGain(
    double currentValue,
    double targetValue,
    double change,
    double weeks,
  ) {
    // Check direction
    if (targetValue <= currentValue) {
      return GoalValidationResult(
        isValid: false,
        warning: 'Target should be greater than current value for muscle gain.',
        severity: ValidationSeverity.error,
      );
    }

    // Check rate
    final weeklyGain = weeks > 0 ? change / weeks : change;
    if (weeklyGain > maxWeeklyMuscleGain) {
      return GoalValidationResult(
        isValid: true, // Allow but warn
        warning:
            'Gaining more than 1 lb/week of muscle is unrealistic. '
            'Your goal requires ${weeklyGain.toStringAsFixed(1)} lbs/week.',
        severity: ValidationSeverity.warning,
      );
    }

    return GoalValidationResult(isValid: true);
  }

  GoalValidationResult _validateBodyFat(double change, double weeks) {
    final monthlyLoss = weeks > 0 ? change / (weeks / 4) : change;
    if (monthlyLoss > maxMonthlyBodyFatLoss) {
      return GoalValidationResult(
        isValid: true, // Allow but warn
        warning:
            'Losing more than 1% body fat/month is difficult. '
            'Your goal requires ${monthlyLoss.toStringAsFixed(1)}%/month.',
        severity: ValidationSeverity.warning,
      );
    }

    return GoalValidationResult(isValid: true);
  }

  // ============ AI Suggested Date ============

  /// Calculates an AI-suggested target date based on healthy progress rates
  ///
  /// Returns a [DateTime] representing the suggested completion date,
  /// clamped between 14 and 365 days from now.
  DateTime calculateAISuggestedDate({
    required String goalType,
    required double currentValue,
    required double targetValue,
  }) {
    final difference = (targetValue - currentValue).abs();
    int daysToComplete = 90; // Default

    switch (goalType) {
      case 'Weight Loss':
        final weeksNeeded = difference / healthyWeeklyWeightLoss;
        daysToComplete = (weeksNeeded * 7).ceil();
        break;

      case 'Muscle Gain':
        final weeksNeeded = difference / healthyWeeklyMuscleGain;
        daysToComplete = (weeksNeeded * 7).ceil();
        break;

      case 'Body Fat':
        final monthsNeeded = difference / healthyMonthlyBodyFatLoss;
        daysToComplete = (monthsNeeded * 30).ceil();
        break;

      case 'Workout Frequency':
        daysToComplete = 60;
        break;

      case 'Strength (Total Volume)':
        daysToComplete = 180;
        break;

      case 'Cardiovascular Endurance':
        daysToComplete = 90;
        break;

      case 'Flexibility':
        daysToComplete = 120;
        break;
    }

    // Clamp between 2 weeks and 1 year
    daysToComplete = daysToComplete.clamp(14, 365);

    return DateTime.now().add(Duration(days: daysToComplete));
  }

  // ============ Rate Calculations ============

  /// Calculate required weekly rate to achieve goal
  double calculateRequiredWeeklyRate({
    required double currentValue,
    required double targetValue,
    required DateTime targetDate,
  }) {
    final change = (targetValue - currentValue).abs();
    final weeks = targetDate.difference(DateTime.now()).inDays / 7;

    if (weeks <= 0) return change; // If past due, return total change
    return change / weeks;
  }

  /// Get healthy rate recommendation for goal type
  double getHealthyWeeklyRate(String goalType) {
    switch (goalType) {
      case 'Weight Loss':
        return healthyWeeklyWeightLoss;
      case 'Muscle Gain':
        return healthyWeeklyMuscleGain;
      case 'Body Fat':
        return healthyMonthlyBodyFatLoss / 4; // Convert to weekly
      default:
        return 1.0;
    }
  }
}

/// Result of goal validation
class GoalValidationResult {
  final bool isValid;
  final String? warning;
  final ValidationSeverity severity;

  const GoalValidationResult({
    required this.isValid,
    this.warning,
    this.severity = ValidationSeverity.none,
  });
}

/// Severity level for validation warnings
enum ValidationSeverity { none, warning, error }
