import 'package:isar/isar.dart';
import '../models/achievement.dart';
import '../local/services/local_database_service.dart';
import '../services/auth_service.dart';

/// Repository for managing achievements (local-only)
class AchievementRepository {
  final LocalDatabaseService _localDb;
  final AuthService _authService;

  AchievementRepository({
    required LocalDatabaseService localDb,
    required AuthService authService,
  }) : _localDb = localDb,
       _authService = authService;

  /// Get all unlocked achievements for current user
  Future<List<Achievement>> getUnlockedAchievements() async {
    final userId = await _authService.getUserId();
    if (userId == null) return [];

    final isar = _localDb.database;
    return await isar.achievements
        .filter()
        .userIdEqualTo(userId)
        .sortByUnlockedAtDesc()
        .findAll();
  }

  /// Get unseen achievements (for showing unlock animations)
  Future<List<Achievement>> getUnseenAchievements() async {
    final userId = await _authService.getUserId();
    if (userId == null) return [];

    final isar = _localDb.database;
    return await isar.achievements
        .filter()
        .userIdEqualTo(userId)
        .hasBeenSeenEqualTo(false)
        .findAll();
  }

  /// Check if a specific achievement is unlocked
  Future<bool> isUnlocked(String achievementId) async {
    final userId = await _authService.getUserId();
    if (userId == null) return false;

    final isar = _localDb.database;
    final achievement =
        await isar.achievements
            .filter()
            .userIdEqualTo(userId)
            .achievementIdEqualTo(achievementId)
            .findFirst();

    return achievement != null;
  }

  /// Unlock an achievement
  Future<Achievement?> unlock(String achievementId) async {
    final userId = await _authService.getUserId();
    if (userId == null) return null;

    // Check if already unlocked
    if (await isUnlocked(achievementId)) return null;

    // Verify achievement exists
    final definition = AchievementDefinition.getById(achievementId);
    if (definition == null) return null;

    final achievement = Achievement.unlock(
      achievementId: achievementId,
      userId: userId,
    );

    final isar = _localDb.database;
    await isar.writeTxn(() async {
      await isar.achievements.put(achievement);
    });

    return achievement;
  }

  /// Mark achievement as seen
  Future<void> markAsSeen(int achievementLocalId) async {
    final isar = _localDb.database;
    await isar.writeTxn(() async {
      final achievement = await isar.achievements.get(achievementLocalId);
      if (achievement != null) {
        achievement.hasBeenSeen = true;
        await isar.achievements.put(achievement);
      }
    });
  }

  /// Mark all achievements as seen
  Future<void> markAllAsSeen() async {
    final userId = await _authService.getUserId();
    if (userId == null) return;

    final isar = _localDb.database;
    final unseen =
        await isar.achievements
            .filter()
            .userIdEqualTo(userId)
            .hasBeenSeenEqualTo(false)
            .findAll();

    await isar.writeTxn(() async {
      for (final achievement in unseen) {
        achievement.hasBeenSeen = true;
        await isar.achievements.put(achievement);
      }
    });
  }

  /// Get progress towards all achievements
  Future<Map<String, AchievementProgress>> getProgress({
    required int currentStreak,
    required int longestStreak,
    required int totalWorkouts,
    required int totalVolume,
    required int totalPRs,
  }) async {
    final userId = await _authService.getUserId();
    if (userId == null) return {};

    final unlocked = await getUnlockedAchievements();
    final unlockedIds = unlocked.map((a) => a.achievementId).toSet();

    final progress = <String, AchievementProgress>{};

    for (final def in AchievementDefinition.all) {
      int currentValue = 0;

      switch (def.category) {
        case AchievementCategory.streak:
          currentValue = longestStreak;
          break;
        case AchievementCategory.milestone:
          currentValue = totalWorkouts;
          break;
        case AchievementCategory.volume:
          currentValue = totalVolume;
          break;
        case AchievementCategory.prs:
          currentValue = totalPRs;
          break;
        case AchievementCategory.consistency:
          // These are handled separately
          currentValue = 0;
          break;
      }

      progress[def.id] = AchievementProgress(
        definition: def,
        currentValue: currentValue,
        isUnlocked: unlockedIds.contains(def.id),
        unlockedAt:
            unlocked
                .where((a) => a.achievementId == def.id)
                .map((a) => a.unlockedAt)
                .firstOrNull,
      );
    }

    return progress;
  }

  /// Check for newly unlockable achievements and unlock them
  Future<List<Achievement>> checkAndUnlockAchievements({
    required int currentStreak,
    required int longestStreak,
    required int totalWorkouts,
    required int totalVolume,
    required int totalPRs,
  }) async {
    final newlyUnlocked = <Achievement>[];

    // Check streak achievements
    for (final def in AchievementDefinition.getByCategory(
      AchievementCategory.streak,
    )) {
      if (longestStreak >= def.requirement && !await isUnlocked(def.id)) {
        final achievement = await unlock(def.id);
        if (achievement != null) newlyUnlocked.add(achievement);
      }
    }

    // Check milestone achievements
    for (final def in AchievementDefinition.getByCategory(
      AchievementCategory.milestone,
    )) {
      if (totalWorkouts >= def.requirement && !await isUnlocked(def.id)) {
        final achievement = await unlock(def.id);
        if (achievement != null) newlyUnlocked.add(achievement);
      }
    }

    // Check volume achievements
    for (final def in AchievementDefinition.getByCategory(
      AchievementCategory.volume,
    )) {
      if (totalVolume >= def.requirement && !await isUnlocked(def.id)) {
        final achievement = await unlock(def.id);
        if (achievement != null) newlyUnlocked.add(achievement);
      }
    }

    // Check PR achievements
    for (final def in AchievementDefinition.getByCategory(
      AchievementCategory.prs,
    )) {
      if (totalPRs >= def.requirement && !await isUnlocked(def.id)) {
        final achievement = await unlock(def.id);
        if (achievement != null) newlyUnlocked.add(achievement);
      }
    }

    return newlyUnlocked;
  }

  /// Get total achievements count by tier
  Future<Map<AchievementTier, int>> getUnlockedCountByTier() async {
    final unlocked = await getUnlockedAchievements();
    final counts = <AchievementTier, int>{
      AchievementTier.bronze: 0,
      AchievementTier.silver: 0,
      AchievementTier.gold: 0,
      AchievementTier.platinum: 0,
    };

    for (final achievement in unlocked) {
      final def = achievement.definition;
      if (def != null) {
        counts[def.tier] = (counts[def.tier] ?? 0) + 1;
      }
    }

    return counts;
  }
}

/// Achievement progress data
class AchievementProgress {
  final AchievementDefinition definition;
  final int currentValue;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  AchievementProgress({
    required this.definition,
    required this.currentValue,
    required this.isUnlocked,
    this.unlockedAt,
  });

  double get progressPercentage {
    if (isUnlocked) return 1.0;
    return (currentValue / definition.requirement).clamp(0.0, 1.0);
  }

  int get remaining {
    if (isUnlocked) return 0;
    return definition.requirement - currentValue;
  }
}
