import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage service for onboarding preferences
class OnboardingStorage {
  static const _storage = FlutterSecureStorage();

  // Storage keys
  static const _keyOnboardingCompleted = 'onboarding_completed';
  static const _keyFitnessGoals = 'fitness_goals';
  static const _keyExperienceLevel = 'experience_level';
  static const _keyOnboardingTimestamp = 'onboarding_timestamp';

  /// Check if onboarding has been completed
  static Future<bool> hasCompletedOnboarding() async {
    final completed = await _storage.read(key: _keyOnboardingCompleted);
    return completed == 'true';
  }

  /// Mark onboarding as completed
  static Future<void> setOnboardingCompleted() async {
    await _storage.write(key: _keyOnboardingCompleted, value: 'true');
    await _storage.write(
      key: _keyOnboardingTimestamp,
      value: DateTime.now().toIso8601String(),
    );
  }

  /// Save selected fitness goals
  static Future<void> saveFitnessGoals(List<String> goals) async {
    await _storage.write(key: _keyFitnessGoals, value: goals.join(','));
  }

  /// Get saved fitness goals
  static Future<List<String>> getFitnessGoals() async {
    final goals = await _storage.read(key: _keyFitnessGoals);
    if (goals == null || goals.isEmpty) return [];
    return goals.split(',');
  }

  /// Save experience level
  static Future<void> saveExperienceLevel(String level) async {
    await _storage.write(key: _keyExperienceLevel, value: level);
  }

  /// Get experience level
  static Future<String?> getExperienceLevel() async {
    return await _storage.read(key: _keyExperienceLevel);
  }

  /// Clear onboarding data (for testing or reset)
  static Future<void> clearOnboarding() async {
    await _storage.delete(key: _keyOnboardingCompleted);
    await _storage.delete(key: _keyFitnessGoals);
    await _storage.delete(key: _keyExperienceLevel);
    await _storage.delete(key: _keyOnboardingTimestamp);
  }

  /// Get onboarding completion timestamp
  static Future<DateTime?> getOnboardingTimestamp() async {
    final timestamp = await _storage.read(key: _keyOnboardingTimestamp);
    if (timestamp == null) return null;
    return DateTime.tryParse(timestamp);
  }
}

/// Available fitness goals for onboarding
class FitnessGoals {
  static const buildMuscle = 'build_muscle';
  static const loseWeight = 'lose_weight';
  static const getStronger = 'get_stronger';
  static const improveEndurance = 'improve_endurance';
  static const stayHealthy = 'stay_healthy';
  static const trackProgress = 'track_progress';

  static const all = [
    buildMuscle,
    loseWeight,
    getStronger,
    improveEndurance,
    stayHealthy,
    trackProgress,
  ];

  static String getDisplayName(String goal) {
    switch (goal) {
      case buildMuscle:
        return 'Build Muscle';
      case loseWeight:
        return 'Lose Weight';
      case getStronger:
        return 'Get Stronger';
      case improveEndurance:
        return 'Improve Endurance';
      case stayHealthy:
        return 'Stay Healthy';
      case trackProgress:
        return 'Track Progress';
      default:
        return goal;
    }
  }

  static String getIcon(String goal) {
    switch (goal) {
      case buildMuscle:
        return '💪';
      case loseWeight:
        return '⚡';
      case getStronger:
        return '🏋️';
      case improveEndurance:
        return '🏃';
      case stayHealthy:
        return '❤️';
      case trackProgress:
        return '📊';
      default:
        return '🎯';
    }
  }
}

/// Experience levels for onboarding
class ExperienceLevel {
  static const beginner = 'beginner';
  static const intermediate = 'intermediate';
  static const advanced = 'advanced';

  static const all = [beginner, intermediate, advanced];

  static String getDisplayName(String level) {
    switch (level) {
      case beginner:
        return 'Beginner';
      case intermediate:
        return 'Intermediate';
      case advanced:
        return 'Advanced';
      default:
        return level;
    }
  }

  static String getDescription(String level) {
    switch (level) {
      case beginner:
        return 'New to fitness or just starting out';
      case intermediate:
        return 'Consistent training for 6+ months';
      case advanced:
        return 'Years of experience, pursuing serious goals';
      default:
        return '';
    }
  }

  static String getIcon(String level) {
    switch (level) {
      case beginner:
        return '🌱';
      case intermediate:
        return '💪';
      case advanced:
        return '🏆';
      default:
        return '🎯';
    }
  }
}
