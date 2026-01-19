import 'package:flutter/services.dart';

/// Centralized haptic feedback service for premium micro-interactions
/// Provides consistent haptic patterns throughout the app
class HapticService {
  HapticService._();

  // ============ BASIC HAPTICS ============

  /// Light impact - subtle feedback for minor interactions
  /// Use for: list selections, toggles, small taps
  static Future<void> lightImpact() async {
    await HapticFeedback.lightImpact();
  }

  /// Medium impact - standard feedback for normal interactions
  /// Use for: button presses, card taps, navigation
  static Future<void> mediumImpact() async {
    await HapticFeedback.mediumImpact();
  }

  /// Heavy impact - strong feedback for significant actions
  /// Use for: completing sets, finishing workouts, achievements
  static Future<void> heavyImpact() async {
    await HapticFeedback.heavyImpact();
  }

  /// Selection click - crisp feedback for selections
  /// Use for: picker selections, tab changes, chip selections
  static Future<void> selectionClick() async {
    await HapticFeedback.selectionClick();
  }

  /// Vibrate - standard vibration
  static Future<void> vibrate() async {
    await HapticFeedback.vibrate();
  }

  // ============ PREMIUM PATTERNS ============

  /// Success pattern - double pulse for positive feedback
  /// Use for: completing sets, achieving goals, PRs
  static Future<void> success() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.lightImpact();
  }

  /// Error pattern - sharp feedback for errors
  /// Use for: validation errors, failed operations
  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
  }

  /// Warning pattern - attention-grabbing feedback
  /// Use for: important alerts, warnings
  static Future<void> warning() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.mediumImpact();
  }

  /// Set complete - satisfying feedback for completing a set
  /// Use for: marking sets as done
  static Future<void> setComplete() async {
    await HapticFeedback.mediumImpact();
  }

  /// Exercise complete - enhanced feedback for finishing an exercise
  /// Use for: completing all sets of an exercise
  static Future<void> exerciseComplete() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.lightImpact();
  }

  /// Workout complete - celebration pattern
  /// Use for: finishing entire workout
  static Future<void> workoutComplete() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
  }

  /// Achievement unlocked - exciting pattern for achievements
  /// Use for: unlocking badges, reaching milestones
  static Future<void> achievementUnlocked() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.heavyImpact();
  }

  /// PR achieved - special pattern for personal records
  /// Use for: setting new personal records
  static Future<void> prAchieved() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.heavyImpact();
  }

  /// Timer tick - subtle tick for countdown timers
  /// Use for: rest timer ticks, countdown ticks
  static Future<void> timerTick() async {
    await HapticFeedback.selectionClick();
  }

  /// Timer warning - alert when timer is almost done
  /// Use for: last 5 seconds of rest timer
  static Future<void> timerWarning() async {
    await HapticFeedback.lightImpact();
  }

  /// Timer complete - timer finished
  /// Use for: rest timer complete
  static Future<void> timerComplete() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }

  /// Button tap - standard button feedback
  /// Use for: all button presses
  static Future<void> buttonTap() async {
    await HapticFeedback.lightImpact();
  }

  /// Card tap - feedback for tapping cards
  /// Use for: session cards, exercise cards, etc.
  static Future<void> cardTap() async {
    await HapticFeedback.lightImpact();
  }

  /// Swipe action - feedback for swipe gestures
  /// Use for: swipe to delete, swipe actions
  static Future<void> swipeAction() async {
    await HapticFeedback.mediumImpact();
  }

  /// Delete action - feedback for destructive actions
  /// Use for: deleting items
  static Future<void> deleteAction() async {
    await HapticFeedback.heavyImpact();
  }

  /// Refresh - pull to refresh feedback
  /// Use for: pull-to-refresh
  static Future<void> refresh() async {
    await HapticFeedback.lightImpact();
  }

  /// Navigation - feedback for navigation actions
  /// Use for: navigating between screens
  static Future<void> navigation() async {
    await HapticFeedback.selectionClick();
  }

  /// Increment/Decrement - feedback for number changes
  /// Use for: incrementing/decrementing weight, reps
  static Future<void> increment() async {
    await HapticFeedback.selectionClick();
  }

  /// Streak milestone - feedback for streak achievements
  /// Use for: 3-day, 7-day, 30-day streaks
  static Future<void> streakMilestone() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }

  /// Long press - feedback for long press actions
  /// Use for: long press to reveal options
  static Future<void> longPress() async {
    await HapticFeedback.mediumImpact();
  }

  /// Drag start - feedback when starting to drag
  /// Use for: dragging items to reorder
  static Future<void> dragStart() async {
    await HapticFeedback.mediumImpact();
  }

  /// Drag end - feedback when dropping dragged item
  /// Use for: dropping reordered items
  static Future<void> dragEnd() async {
    await HapticFeedback.lightImpact();
  }
}
