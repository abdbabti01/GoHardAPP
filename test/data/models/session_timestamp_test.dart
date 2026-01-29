import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/session.dart';

void main() {
  group('Session.fromJson - Timestamp Parsing (Timer Bug Fix)', () {
    test('should preserve timestamp values when API returns without Z suffix', () {
      // This test reproduces the bug where timestamps were shifted by timezone offset.
      // The API returns timestamps like "2024-01-15T10:30:00" (without 'Z').
      // Previously, calling .toUtc() on the parsed DateTime would SHIFT the time
      // by the local timezone offset (e.g., +5 hours in EST).
      //
      // The fix reconstructs the DateTime as UTC from raw components, preserving
      // the original values.

      // Arrange - API response with timestamps WITHOUT 'Z' suffix
      final json = {
        'id': 1,
        'userId': 100,
        'date': '2024-01-15T00:00:00',
        'status': 'in_progress',
        'startedAt': '2024-01-15T10:30:00', // 10:30 AM - no Z suffix
        'completedAt': null,
        'pausedAt': '2024-01-15T10:45:00', // 10:45 AM - no Z suffix
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(json);

      // Assert - Timestamps should be UTC with SAME hour/minute values
      // NOT shifted by timezone offset
      expect(session.startedAt, isNotNull);
      expect(session.startedAt!.isUtc, true);
      expect(
        session.startedAt!.hour,
        10,
      ); // Should be 10, not 10 + timezone offset
      expect(session.startedAt!.minute, 30);

      expect(session.pausedAt, isNotNull);
      expect(session.pausedAt!.isUtc, true);
      expect(session.pausedAt!.hour, 10); // Should be 10, not shifted
      expect(session.pausedAt!.minute, 45);
    });

    test('should handle timestamps with Z suffix correctly', () {
      // When API returns proper UTC timestamps with 'Z' suffix,
      // they should be parsed as UTC and remain unchanged.

      // Arrange - API response with timestamps WITH 'Z' suffix
      final json = {
        'id': 2,
        'userId': 100,
        'date': '2024-01-15T00:00:00Z',
        'status': 'completed',
        'startedAt': '2024-01-15T14:00:00Z', // Already UTC
        'completedAt': '2024-01-15T15:30:00Z', // Already UTC
        'pausedAt': null,
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(json);

      // Assert - Should remain as-is since already UTC
      expect(session.startedAt, isNotNull);
      expect(session.startedAt!.isUtc, true);
      expect(session.startedAt!.hour, 14);
      expect(session.startedAt!.minute, 0);

      expect(session.completedAt, isNotNull);
      expect(session.completedAt!.isUtc, true);
      expect(session.completedAt!.hour, 15);
      expect(session.completedAt!.minute, 30);
    });

    test('should handle null timestamps gracefully', () {
      // Arrange
      final json = {
        'id': 3,
        'userId': 100,
        'date': '2024-01-15T00:00:00',
        'status': 'draft',
        'startedAt': null,
        'completedAt': null,
        'pausedAt': null,
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(json);

      // Assert
      expect(session.startedAt, isNull);
      expect(session.completedAt, isNull);
      expect(session.pausedAt, isNull);
    });

    test('timer duration calculation should be accurate after parsing', () {
      // This test ensures the timer doesn't show wrong duration
      // (e.g., 5 hours added) after parsing and resuming a workout.

      // Arrange - Workout started at 10:00, paused at 10:30 (30 min elapsed)
      final json = {
        'id': 4,
        'userId': 100,
        'date': '2024-01-15T00:00:00',
        'status': 'paused',
        'startedAt': '2024-01-15T10:00:00',
        'completedAt': null,
        'pausedAt': '2024-01-15T10:30:00',
        'duration': 1800, // 30 minutes in seconds
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(json);

      // Assert
      expect(session.startedAt, isNotNull);
      expect(session.pausedAt, isNotNull);

      // Calculate elapsed time from timestamps
      final elapsed = session.pausedAt!.difference(session.startedAt!);

      // Should be exactly 30 minutes, NOT 30 minutes + timezone offset
      expect(elapsed.inMinutes, 30);
      expect(elapsed.inHours, 0); // Should NOT be 5+ hours
    });

    test(
      'workout resumed after pause should calculate correct elapsed time',
      () {
        // Simulates the exact bug scenario:
        // 1. User starts workout at 10:00 AM
        // 2. User pauses at 10:30 AM (30 min elapsed)
        // 3. App goes to background, comes back
        // 4. Timer should show ~30 min, NOT 5h30m

        // Arrange
        final startTime = DateTime.utc(2024, 1, 15, 10, 0, 0);
        final pauseTime = DateTime.utc(2024, 1, 15, 10, 30, 0);

        final json = {
          'id': 5,
          'userId': 100,
          'date': '2024-01-15T00:00:00',
          'status': 'paused',
          'startedAt':
              '2024-01-15T10:00:00', // Without Z - this was causing the bug
          'completedAt': null,
          'pausedAt': '2024-01-15T10:30:00', // Without Z
          'duration': null,
          'exercises': [],
          'version': 1,
        };

        // Act
        final session = Session.fromJson(json);

        // Assert - Both timestamps should be treated as UTC
        expect(session.startedAt!.isUtc, true);
        expect(session.pausedAt!.isUtc, true);

        // The time difference should be 30 minutes
        final elapsedDuration = session.pausedAt!.difference(
          session.startedAt!,
        );
        expect(elapsedDuration.inMinutes, 30);

        // Critically: elapsed should NOT include timezone offset
        expect(elapsedDuration.inHours, lessThan(1));
      },
    );

    test('all timestamp fields should be converted consistently', () {
      // Ensure startedAt, completedAt, and pausedAt are all handled the same way

      // Arrange
      final json = {
        'id': 6,
        'userId': 100,
        'date': '2024-01-15T00:00:00',
        'status': 'completed',
        'startedAt': '2024-01-15T09:00:00',
        'completedAt': '2024-01-15T10:15:00',
        'pausedAt': '2024-01-15T09:30:00',
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(json);

      // Assert - All should be UTC
      expect(session.startedAt!.isUtc, true);
      expect(session.completedAt!.isUtc, true);
      expect(session.pausedAt!.isUtc, true);

      // All should preserve their original hour values
      expect(session.startedAt!.hour, 9);
      expect(session.completedAt!.hour, 10);
      expect(session.pausedAt!.hour, 9);
    });

    test('date field should be normalized to local midnight', () {
      // The date field represents the workout day, not a precise timestamp
      // It should be normalized to midnight in local time

      // Arrange
      final json = {
        'id': 7,
        'userId': 100,
        'date': '2024-01-15T14:30:00', // Arbitrary time
        'status': 'draft',
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(json);

      // Assert - Date should be normalized to midnight (time components = 0)
      expect(session.date.hour, 0);
      expect(session.date.minute, 0);
      expect(session.date.second, 0);
      expect(session.date.year, 2024);
      expect(session.date.month, 1);
      expect(session.date.day, 15);
    });

    test('edge case: midnight timestamps should not shift to previous day', () {
      // Timestamps at midnight should stay on the same day after conversion

      // Arrange
      final json = {
        'id': 8,
        'userId': 100,
        'date': '2024-01-15T00:00:00',
        'status': 'in_progress',
        'startedAt': '2024-01-15T00:00:00', // Midnight
        'completedAt': null,
        'pausedAt': null,
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(json);

      // Assert - Should still be Jan 15, not Jan 14
      expect(session.startedAt!.day, 15);
      expect(session.startedAt!.month, 1);
      expect(session.startedAt!.hour, 0);
      expect(session.startedAt!.minute, 0);
    });

    test('regression: 5-hour offset bug should not occur', () {
      // This is the exact regression test for the reported bug:
      // "when I start a workout, leave and come back, 5 hours are added to timer"
      //
      // The bug occurred because:
      // 1. API returns: "2024-01-15T10:00:00" (no Z suffix)
      // 2. Dart parses as LOCAL DateTime(2024, 1, 15, 10, 0) - isUtc = false
      // 3. Old code called .toUtc() which SHIFTS the time
      // 4. In EST (UTC-5), toUtc() would return DateTime.utc(2024, 1, 15, 15, 0)
      // 5. This caused 5 hours to be "added" to the timer

      // Arrange - Simulate API response
      final json = {
        'id': 99,
        'userId': 100,
        'date': '2024-01-15T00:00:00',
        'status': 'in_progress',
        'startedAt': '2024-01-15T10:00:00', // 10:00 AM without Z
        'completedAt': null,
        'pausedAt': null,
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(json);

      // Assert
      // The critical check: hour should be 10, not 10 + offset
      expect(
        session.startedAt!.hour,
        10,
        reason: 'Hour should be 10, not shifted by timezone offset',
      );

      // If we were still using the buggy .toUtc() approach, and the test
      // machine is in a timezone like EST (UTC-5), the hour would be 15.
      // Or if in a UTC+5 timezone, it would be 5.
      // The fix ensures it's always 10 regardless of local timezone.
    });
  });
}
