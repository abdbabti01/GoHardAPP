import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for managing goal reminder preferences
/// Stores reminder settings locally on the device
class GoalReminderPreferences {
  static final GoalReminderPreferences _instance =
      GoalReminderPreferences._internal();
  factory GoalReminderPreferences() => _instance;
  GoalReminderPreferences._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _keyPrefix = 'goal_reminder_';

  /// Save reminder preference for a goal
  Future<void> saveReminderPreference({
    required int goalId,
    required String frequency,
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    final key = '$_keyPrefix$goalId';
    final preference = {
      'frequency': frequency,
      'hour': hour,
      'minute': minute,
      'enabled': enabled,
    };

    await _storage.write(key: key, value: jsonEncode(preference));
  }

  /// Get reminder preference for a goal
  Future<GoalReminderSetting?> getReminderPreference(int goalId) async {
    final key = '$_keyPrefix$goalId';
    final value = await _storage.read(key: key);

    if (value == null) return null;

    try {
      final map = jsonDecode(value) as Map<String, dynamic>;
      return GoalReminderSetting(
        frequency: map['frequency'] as String,
        hour: map['hour'] as int,
        minute: map['minute'] as int,
        enabled: map['enabled'] as bool,
      );
    } catch (e) {
      return null;
    }
  }

  /// Delete reminder preference for a goal
  Future<void> deleteReminderPreference(int goalId) async {
    final key = '$_keyPrefix$goalId';
    await _storage.delete(key: key);
  }

  /// Get all goal IDs with reminder preferences
  Future<List<int>> getAllGoalIdsWithReminders() async {
    final allKeys = await _storage.readAll();
    final goalIds = <int>[];

    for (final key in allKeys.keys) {
      if (key.startsWith(_keyPrefix)) {
        final idStr = key.substring(_keyPrefix.length);
        final id = int.tryParse(idStr);
        if (id != null) {
          goalIds.add(id);
        }
      }
    }

    return goalIds;
  }
}

/// Data class for goal reminder settings
class GoalReminderSetting {
  final String
  frequency; // 'daily', 'every2days', 'every3days', 'weekly', 'biweekly'
  final int hour;
  final int minute;
  final bool enabled;

  GoalReminderSetting({
    required this.frequency,
    required this.hour,
    required this.minute,
    required this.enabled,
  });

  String get frequencyDisplay {
    switch (frequency.toLowerCase()) {
      case 'daily':
        return 'Daily';
      case 'every2days':
        return 'Every 2 days';
      case 'every3days':
        return 'Every 3 days';
      case 'weekly':
        return 'Weekly';
      case 'biweekly':
        return 'Every 2 weeks';
      default:
        return 'Weekly';
    }
  }
}
