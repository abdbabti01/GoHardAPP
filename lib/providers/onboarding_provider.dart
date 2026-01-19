import 'package:flutter/foundation.dart';
import '../core/services/onboarding_storage.dart';

/// Provider for managing onboarding flow state
class OnboardingProvider extends ChangeNotifier {
  bool _hasCompletedOnboarding = false;
  bool _isLoading = true;
  int _currentPage = 0;
  List<String> _selectedGoals = [];
  String? _selectedExperienceLevel;

  // Getters
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
  bool get isLoading => _isLoading;
  int get currentPage => _currentPage;
  List<String> get selectedGoals => _selectedGoals;
  String? get selectedExperienceLevel => _selectedExperienceLevel;

  /// Total number of onboarding pages
  int get totalPages => 4;

  /// Check if can proceed to next page
  bool get canProceed {
    switch (_currentPage) {
      case 0: // Welcome
        return true;
      case 1: // Goals
        return _selectedGoals.isNotEmpty;
      case 2: // Experience
        return _selectedExperienceLevel != null;
      case 3: // Ready
        return true;
      default:
        return false;
    }
  }

  /// Is on last page
  bool get isLastPage => _currentPage == totalPages - 1;

  /// Initialize onboarding state
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _hasCompletedOnboarding =
          await OnboardingStorage.hasCompletedOnboarding();
      _selectedGoals = await OnboardingStorage.getFitnessGoals();
      _selectedExperienceLevel = await OnboardingStorage.getExperienceLevel();
    } catch (e) {
      debugPrint('Error initializing onboarding: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set current page
  void setCurrentPage(int page) {
    if (page >= 0 && page < totalPages) {
      _currentPage = page;
      notifyListeners();
    }
  }

  /// Go to next page
  void nextPage() {
    if (_currentPage < totalPages - 1) {
      _currentPage++;
      notifyListeners();
    }
  }

  /// Go to previous page
  void previousPage() {
    if (_currentPage > 0) {
      _currentPage--;
      notifyListeners();
    }
  }

  /// Toggle a fitness goal selection
  void toggleGoal(String goal) {
    if (_selectedGoals.contains(goal)) {
      _selectedGoals.remove(goal);
    } else {
      _selectedGoals.add(goal);
    }
    notifyListeners();
  }

  /// Set experience level
  void setExperienceLevel(String level) {
    _selectedExperienceLevel = level;
    notifyListeners();
  }

  /// Complete onboarding
  Future<void> completeOnboarding() async {
    try {
      // Save preferences
      await OnboardingStorage.saveFitnessGoals(_selectedGoals);
      if (_selectedExperienceLevel != null) {
        await OnboardingStorage.saveExperienceLevel(_selectedExperienceLevel!);
      }

      // Mark as completed
      await OnboardingStorage.setOnboardingCompleted();
      _hasCompletedOnboarding = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error completing onboarding: $e');
    }
  }

  /// Skip onboarding (mark as completed without saving preferences)
  Future<void> skipOnboarding() async {
    try {
      await OnboardingStorage.setOnboardingCompleted();
      _hasCompletedOnboarding = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error skipping onboarding: $e');
    }
  }

  /// Reset onboarding (for testing)
  Future<void> resetOnboarding() async {
    try {
      await OnboardingStorage.clearOnboarding();
      _hasCompletedOnboarding = false;
      _currentPage = 0;
      _selectedGoals = [];
      _selectedExperienceLevel = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error resetting onboarding: $e');
    }
  }
}
