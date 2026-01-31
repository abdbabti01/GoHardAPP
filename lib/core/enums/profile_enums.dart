enum Gender {
  male,
  female,
  other,
  preferNotToSay;

  String get displayName {
    switch (this) {
      case Gender.male:
        return 'Male';
      case Gender.female:
        return 'Female';
      case Gender.other:
        return 'Other';
      case Gender.preferNotToSay:
        return 'Prefer not to say';
    }
  }

  String get serverValue {
    switch (this) {
      case Gender.male:
        return 'Male';
      case Gender.female:
        return 'Female';
      case Gender.other:
        return 'Other';
      case Gender.preferNotToSay:
        return 'PreferNotToSay';
    }
  }

  static Gender? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'male':
        return Gender.male;
      case 'female':
        return Gender.female;
      case 'other':
        return Gender.other;
      case 'prefernottosay':
      case 'prefer not to say':
        return Gender.preferNotToSay;
      default:
        return null;
    }
  }
}

enum ExperienceLevel {
  beginner,
  intermediate,
  advanced,
  expert;

  String get displayName {
    switch (this) {
      case ExperienceLevel.beginner:
        return 'Beginner';
      case ExperienceLevel.intermediate:
        return 'Intermediate';
      case ExperienceLevel.advanced:
        return 'Advanced';
      case ExperienceLevel.expert:
        return 'Expert';
    }
  }

  String get serverValue {
    switch (this) {
      case ExperienceLevel.beginner:
        return 'Beginner';
      case ExperienceLevel.intermediate:
        return 'Intermediate';
      case ExperienceLevel.advanced:
        return 'Advanced';
      case ExperienceLevel.expert:
        return 'Expert';
    }
  }

  static ExperienceLevel? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'beginner':
        return ExperienceLevel.beginner;
      case 'intermediate':
        return ExperienceLevel.intermediate;
      case 'advanced':
        return ExperienceLevel.advanced;
      case 'expert':
        return ExperienceLevel.expert;
      default:
        return null;
    }
  }
}

enum FitnessGoal {
  weightLoss,
  muscleGain,
  strength,
  endurance,
  generalFitness;

  String get displayName {
    switch (this) {
      case FitnessGoal.weightLoss:
        return 'Weight Loss';
      case FitnessGoal.muscleGain:
        return 'Muscle Gain';
      case FitnessGoal.strength:
        return 'Strength';
      case FitnessGoal.endurance:
        return 'Endurance';
      case FitnessGoal.generalFitness:
        return 'General Fitness';
    }
  }

  String get serverValue {
    switch (this) {
      case FitnessGoal.weightLoss:
        return 'WeightLoss';
      case FitnessGoal.muscleGain:
        return 'MuscleGain';
      case FitnessGoal.strength:
        return 'Strength';
      case FitnessGoal.endurance:
        return 'Endurance';
      case FitnessGoal.generalFitness:
        return 'GeneralFitness';
    }
  }

  static FitnessGoal? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.trim().toLowerCase().replaceAll(' ', '');
    switch (normalized) {
      case 'weightloss':
        return FitnessGoal.weightLoss;
      case 'musclegain':
        return FitnessGoal.muscleGain;
      case 'strength':
        return FitnessGoal.strength;
      case 'endurance':
        return FitnessGoal.endurance;
      case 'generalfitness':
        return FitnessGoal.generalFitness;
      default:
        return null;
    }
  }
}

enum ActivityLevel {
  sedentary,
  lightlyActive,
  moderatelyActive,
  veryActive,
  extremelyActive;

  String get displayName {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Sedentary';
      case ActivityLevel.lightlyActive:
        return 'Lightly Active';
      case ActivityLevel.moderatelyActive:
        return 'Moderately Active';
      case ActivityLevel.veryActive:
        return 'Very Active';
      case ActivityLevel.extremelyActive:
        return 'Extremely Active';
    }
  }

  String get description {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Little or no exercise, desk job';
      case ActivityLevel.lightlyActive:
        return 'Light exercise 1-3 days/week';
      case ActivityLevel.moderatelyActive:
        return 'Moderate exercise 3-5 days/week';
      case ActivityLevel.veryActive:
        return 'Hard exercise 6-7 days/week';
      case ActivityLevel.extremelyActive:
        return 'Very hard exercise, physical job';
    }
  }

  String get serverValue {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Sedentary';
      case ActivityLevel.lightlyActive:
        return 'LightlyActive';
      case ActivityLevel.moderatelyActive:
        return 'ModeratelyActive';
      case ActivityLevel.veryActive:
        return 'VeryActive';
      case ActivityLevel.extremelyActive:
        return 'ExtremelyActive';
    }
  }

  static ActivityLevel? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized = value.trim().toLowerCase().replaceAll(' ', '');
    switch (normalized) {
      case 'sedentary':
        return ActivityLevel.sedentary;
      case 'lightlyactive':
        return ActivityLevel.lightlyActive;
      case 'moderatelyactive':
        return ActivityLevel.moderatelyActive;
      case 'veryactive':
        return ActivityLevel.veryActive;
      case 'extremelyactive':
        return ActivityLevel.extremelyActive;
      default:
        return null;
    }
  }
}

enum UnitPreference {
  metric,
  imperial;

  String get displayName {
    switch (this) {
      case UnitPreference.metric:
        return 'Metric (kg, cm)';
      case UnitPreference.imperial:
        return 'Imperial (lbs, ft/in)';
    }
  }

  String get serverValue {
    switch (this) {
      case UnitPreference.metric:
        return 'Metric';
      case UnitPreference.imperial:
        return 'Imperial';
    }
  }

  static UnitPreference fromString(String? value) {
    if (value == null || value.isEmpty) return UnitPreference.metric;
    final normalized = value.trim().toLowerCase();
    if (normalized == 'imperial') return UnitPreference.imperial;
    return UnitPreference.metric; // default
  }
}
