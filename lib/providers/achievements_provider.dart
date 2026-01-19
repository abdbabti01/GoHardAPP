import 'package:flutter/foundation.dart';
import '../data/models/achievement.dart';
import '../data/repositories/achievement_repository.dart';

/// Provider for managing achievements state
class AchievementsProvider extends ChangeNotifier {
  final AchievementRepository _repository;

  List<Achievement> _unlockedAchievements = [];
  List<Achievement> _unseenAchievements = [];
  Map<String, AchievementProgress> _progress = {};
  Map<AchievementTier, int> _tierCounts = {};
  bool _isLoading = false;
  String? _errorMessage;

  AchievementsProvider(this._repository);

  // Getters
  List<Achievement> get unlockedAchievements => _unlockedAchievements;
  List<Achievement> get unseenAchievements => _unseenAchievements;
  Map<String, AchievementProgress> get progress => _progress;
  Map<AchievementTier, int> get tierCounts => _tierCounts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Total unlocked count
  int get totalUnlocked => _unlockedAchievements.length;

  /// Total available achievements
  int get totalAvailable => AchievementDefinition.all.length;

  /// Has new achievements to show
  bool get hasUnseenAchievements => _unseenAchievements.isNotEmpty;

  /// Get next achievement to show (oldest unseen)
  Achievement? get nextUnseenAchievement =>
      _unseenAchievements.isNotEmpty ? _unseenAchievements.first : null;

  /// Load all achievement data
  Future<void> loadAchievements({
    required int currentStreak,
    required int longestStreak,
    required int totalWorkouts,
    required int totalVolume,
    required int totalPRs,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Load unlocked achievements
      _unlockedAchievements = await _repository.getUnlockedAchievements();

      // Load unseen achievements
      _unseenAchievements = await _repository.getUnseenAchievements();

      // Load tier counts
      _tierCounts = await _repository.getUnlockedCountByTier();

      // Load progress
      _progress = await _repository.getProgress(
        currentStreak: currentStreak,
        longestStreak: longestStreak,
        totalWorkouts: totalWorkouts,
        totalVolume: totalVolume,
        totalPRs: totalPRs,
      );
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('Error loading achievements: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check and unlock new achievements after workout completion
  Future<List<Achievement>> checkAfterWorkout({
    required int currentStreak,
    required int longestStreak,
    required int totalWorkouts,
    required int totalVolume,
    required int totalPRs,
  }) async {
    try {
      final newlyUnlocked = await _repository.checkAndUnlockAchievements(
        currentStreak: currentStreak,
        longestStreak: longestStreak,
        totalWorkouts: totalWorkouts,
        totalVolume: totalVolume,
        totalPRs: totalPRs,
      );

      if (newlyUnlocked.isNotEmpty) {
        // Reload achievements
        _unlockedAchievements = await _repository.getUnlockedAchievements();
        _unseenAchievements = await _repository.getUnseenAchievements();
        _tierCounts = await _repository.getUnlockedCountByTier();

        // Update progress
        _progress = await _repository.getProgress(
          currentStreak: currentStreak,
          longestStreak: longestStreak,
          totalWorkouts: totalWorkouts,
          totalVolume: totalVolume,
          totalPRs: totalPRs,
        );

        notifyListeners();
      }

      return newlyUnlocked;
    } catch (e) {
      debugPrint('Error checking achievements: $e');
      return [];
    }
  }

  /// Mark an achievement as seen
  Future<void> markAchievementAsSeen(int achievementLocalId) async {
    try {
      await _repository.markAsSeen(achievementLocalId);

      // Remove from unseen list
      _unseenAchievements.removeWhere((a) => a.id == achievementLocalId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error marking achievement as seen: $e');
    }
  }

  /// Mark all achievements as seen
  Future<void> markAllAsSeen() async {
    try {
      await _repository.markAllAsSeen();
      _unseenAchievements = [];
      notifyListeners();
    } catch (e) {
      debugPrint('Error marking all achievements as seen: $e');
    }
  }

  /// Get achievements by category
  List<AchievementProgress> getByCategory(AchievementCategory category) {
    return _progress.values
        .where((p) => p.definition.category == category)
        .toList()
      ..sort(
        (a, b) => a.definition.requirement.compareTo(b.definition.requirement),
      );
  }

  /// Get achievements by tier
  List<AchievementProgress> getByTier(AchievementTier tier) {
    return _progress.values.where((p) => p.definition.tier == tier).toList()
      ..sort((a, b) => a.definition.name.compareTo(b.definition.name));
  }

  /// Get next achievement to unlock for each category
  Map<AchievementCategory, AchievementProgress?> getNextForEachCategory() {
    final result = <AchievementCategory, AchievementProgress?>{};

    for (final category in AchievementCategory.values) {
      final categoryAchievements = getByCategory(category);
      final locked = categoryAchievements.where((a) => !a.isUnlocked).toList();
      result[category] = locked.isNotEmpty ? locked.first : null;
    }

    return result;
  }

  /// Get closest achievement to unlocking
  AchievementProgress? getClosestToUnlocking() {
    final locked = _progress.values.where((p) => !p.isUnlocked).toList();
    if (locked.isEmpty) return null;

    locked.sort((a, b) => b.progressPercentage.compareTo(a.progressPercentage));
    return locked.first;
  }

  /// Reset state (on logout)
  void reset() {
    _unlockedAchievements = [];
    _unseenAchievements = [];
    _progress = {};
    _tierCounts = {};
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
