import 'package:flutter/foundation.dart';

/// Service for managing main screen tab navigation
/// Prevents duplicate Main Screen instances in navigation stack
class TabNavigationService extends ChangeNotifier {
  int _currentTab = 0;
  int? _currentSubTab;

  int get currentTab => _currentTab;
  int? get currentSubTab => _currentSubTab;

  /// Switch to a specific tab
  /// [tabIndex] - Main tab index (0=Workouts, 1=Goals, 2=Chat, etc.)
  /// [subTabIndex] - Optional sub-tab index for tabs with sub-navigation
  void switchTab(int tabIndex, {int? subTabIndex}) {
    _currentTab = tabIndex;
    _currentSubTab = subTabIndex;
    notifyListeners();
  }

  /// Reset to first tab
  void reset() {
    _currentTab = 0;
    _currentSubTab = null;
    notifyListeners();
  }
}
