import 'package:isar/isar.dart';

part 'achievement.g.dart';

/// Achievement tier levels
enum AchievementTier { bronze, silver, gold, platinum }

/// Achievement category types
enum AchievementCategory {
  streak, // Consecutive days
  milestone, // Total workouts
  volume, // Total weight lifted
  prs, // Personal records
  consistency, // Perfect weeks/months
}

/// Achievement definition (static data)
class AchievementDefinition {
  final String id;
  final String name;
  final String description;
  final String icon;
  final AchievementTier tier;
  final AchievementCategory category;
  final int requirement;

  const AchievementDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.tier,
    required this.category,
    required this.requirement,
  });

  /// All available achievements
  static const List<AchievementDefinition> all = [
    // Streak achievements
    AchievementDefinition(
      id: 'streak_3',
      name: 'Getting Started',
      description: 'Complete a 3-day workout streak',
      icon: '🔥',
      tier: AchievementTier.bronze,
      category: AchievementCategory.streak,
      requirement: 3,
    ),
    AchievementDefinition(
      id: 'streak_7',
      name: 'Week Warrior',
      description: 'Complete a 7-day workout streak',
      icon: '🔥',
      tier: AchievementTier.silver,
      category: AchievementCategory.streak,
      requirement: 7,
    ),
    AchievementDefinition(
      id: 'streak_30',
      name: 'Monthly Monster',
      description: 'Complete a 30-day workout streak',
      icon: '🔥',
      tier: AchievementTier.gold,
      category: AchievementCategory.streak,
      requirement: 30,
    ),
    AchievementDefinition(
      id: 'streak_100',
      name: 'Century Club',
      description: 'Complete a 100-day workout streak',
      icon: '💯',
      tier: AchievementTier.platinum,
      category: AchievementCategory.streak,
      requirement: 100,
    ),

    // Milestone achievements
    AchievementDefinition(
      id: 'workout_1',
      name: 'First Steps',
      description: 'Complete your first workout',
      icon: '🏋️',
      tier: AchievementTier.bronze,
      category: AchievementCategory.milestone,
      requirement: 1,
    ),
    AchievementDefinition(
      id: 'workout_10',
      name: 'Dedicated',
      description: 'Complete 10 workouts',
      icon: '💪',
      tier: AchievementTier.bronze,
      category: AchievementCategory.milestone,
      requirement: 10,
    ),
    AchievementDefinition(
      id: 'workout_50',
      name: 'Half Century',
      description: 'Complete 50 workouts',
      icon: '🎯',
      tier: AchievementTier.silver,
      category: AchievementCategory.milestone,
      requirement: 50,
    ),
    AchievementDefinition(
      id: 'workout_100',
      name: 'Triple Digits',
      description: 'Complete 100 workouts',
      icon: '🏆',
      tier: AchievementTier.gold,
      category: AchievementCategory.milestone,
      requirement: 100,
    ),
    AchievementDefinition(
      id: 'workout_250',
      name: 'Elite Performer',
      description: 'Complete 250 workouts',
      icon: '👑',
      tier: AchievementTier.platinum,
      category: AchievementCategory.milestone,
      requirement: 250,
    ),

    // Volume achievements
    AchievementDefinition(
      id: 'volume_1000',
      name: 'Ton Lifter',
      description: 'Lift 1,000 kg total',
      icon: '⚡',
      tier: AchievementTier.bronze,
      category: AchievementCategory.volume,
      requirement: 1000,
    ),
    AchievementDefinition(
      id: 'volume_10000',
      name: 'Heavy Hitter',
      description: 'Lift 10,000 kg total',
      icon: '💥',
      tier: AchievementTier.silver,
      category: AchievementCategory.volume,
      requirement: 10000,
    ),
    AchievementDefinition(
      id: 'volume_50000',
      name: 'Iron Giant',
      description: 'Lift 50,000 kg total',
      icon: '🦾',
      tier: AchievementTier.gold,
      category: AchievementCategory.volume,
      requirement: 50000,
    ),
    AchievementDefinition(
      id: 'volume_100000',
      name: 'Legendary',
      description: 'Lift 100,000 kg total',
      icon: '🌟',
      tier: AchievementTier.platinum,
      category: AchievementCategory.volume,
      requirement: 100000,
    ),

    // PR achievements
    AchievementDefinition(
      id: 'pr_10',
      name: 'Record Breaker',
      description: 'Set 10 personal records',
      icon: '📈',
      tier: AchievementTier.bronze,
      category: AchievementCategory.prs,
      requirement: 10,
    ),
    AchievementDefinition(
      id: 'pr_50',
      name: 'PR Machine',
      description: 'Set 50 personal records',
      icon: '🚀',
      tier: AchievementTier.silver,
      category: AchievementCategory.prs,
      requirement: 50,
    ),
    AchievementDefinition(
      id: 'pr_100',
      name: 'Unstoppable',
      description: 'Set 100 personal records',
      icon: '💎',
      tier: AchievementTier.gold,
      category: AchievementCategory.prs,
      requirement: 100,
    ),

    // Consistency achievements
    AchievementDefinition(
      id: 'perfect_week',
      name: 'Perfect Week',
      description: 'Complete all planned workouts in a week',
      icon: '✅',
      tier: AchievementTier.silver,
      category: AchievementCategory.consistency,
      requirement: 1,
    ),
    AchievementDefinition(
      id: 'perfect_month',
      name: 'Perfect Month',
      description: 'Complete all planned workouts in a month',
      icon: '🌙',
      tier: AchievementTier.gold,
      category: AchievementCategory.consistency,
      requirement: 1,
    ),
  ];

  /// Get achievement definition by ID
  static AchievementDefinition? getById(String id) {
    try {
      return all.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get achievements by category
  static List<AchievementDefinition> getByCategory(
    AchievementCategory category,
  ) {
    return all.where((a) => a.category == category).toList();
  }

  /// Get achievements by tier
  static List<AchievementDefinition> getByTier(AchievementTier tier) {
    return all.where((a) => a.tier == tier).toList();
  }
}

/// Unlocked achievement (user-specific, stored in Isar)
@collection
class Achievement {
  Id id = Isar.autoIncrement;

  @Index()
  late String achievementId;

  @Index()
  late int userId;

  late DateTime unlockedAt;

  /// Whether user has seen the unlock notification
  late bool hasBeenSeen;

  Achievement();

  /// Create a new unlocked achievement
  factory Achievement.unlock({
    required String achievementId,
    required int userId,
  }) {
    return Achievement()
      ..achievementId = achievementId
      ..userId = userId
      ..unlockedAt = DateTime.now().toUtc()
      ..hasBeenSeen = false;
  }

  /// Get the static definition for this achievement
  @ignore
  AchievementDefinition? get definition =>
      AchievementDefinition.getById(achievementId);
}
