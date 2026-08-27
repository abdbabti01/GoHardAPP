import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/models/exercise.dart';

/// Regression coverage for Session.copyWith's pausedAt-clearing semantics.
///
/// copyWith's standard "pass to override, omit to keep" convention cannot
/// distinguish an omitted argument from an explicitly-passed `null` -
/// `pausedAt: pausedAt ?? this.pausedAt` means `copyWith(pausedAt: null)`
/// silently keeps the OLD value instead of clearing it. This is exactly the
/// bug that made ActiveWorkoutProvider.resumeTimer() fail to clear pausedAt,
/// which the new lifecycle logic relies on to decide whether to restart the
/// UI ticker. clearPausedAt is the explicit, unambiguous way to clear it.
void main() {
  Session baseSession({DateTime? pausedAt}) {
    return Session(
      id: 1,
      userId: 100,
      date: DateTime.utc(2024, 1, 15),
      duration: 45,
      notes: 'leg day notes',
      type: 'strength',
      name: 'Leg Day',
      status: 'in_progress',
      startedAt: DateTime.utc(2024, 1, 15, 10, 0, 0),
      completedAt: null,
      pausedAt: pausedAt,
      exercises: [Exercise(id: 1, sessionId: 1, name: 'Squat')],
      programId: 5,
      programWorkoutId: 9,
      version: 3,
    );
  }

  group('Session.copyWith - pausedAt clearing', () {
    test('copyWith() with no pausedAt argument preserves the existing '
        'non-null pausedAt (the standard override-or-keep convention)', () {
      final original = baseSession(
        pausedAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
      );

      final result = original.copyWith();

      expect(result.pausedAt, DateTime.utc(2024, 1, 15, 10, 30, 0));
    });

    test('copyWith(pausedAt: null) alone does NOT clear a non-null pausedAt '
        '- this documents the footgun clearPausedAt exists to avoid', () {
      final original = baseSession(
        pausedAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
      );

      // ignore: avoid_redundant_argument_values
      final result = original.copyWith(pausedAt: null);

      expect(
        result.pausedAt,
        DateTime.utc(2024, 1, 15, 10, 30, 0),
        reason:
            'passing pausedAt: null is indistinguishable from omitting it '
            'in the override-or-keep convention, so it must NOT clear the '
            'field - clearPausedAt is required for that instead',
      );
    });

    test('copyWith(clearPausedAt: true) sets pausedAt to null regardless of '
        'the current value', () {
      final original = baseSession(
        pausedAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
      );

      final result = original.copyWith(clearPausedAt: true);

      expect(result.pausedAt, isNull);
    });

    test('copyWith(clearPausedAt: true) combined with a new startedAt '
        'clears pausedAt while applying the new startedAt - the exact '
        'combination resumeTimer() needs', () {
      final original = baseSession(
        pausedAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
      );
      final newStartedAt = DateTime.utc(2024, 1, 15, 10, 35, 0);

      final result = original.copyWith(
        startedAt: newStartedAt,
        clearPausedAt: true,
      );

      expect(result.startedAt, newStartedAt);
      expect(result.pausedAt, isNull);
    });

    test('clearPausedAt: true takes precedence over a simultaneously '
        'supplied pausedAt value', () {
      final original = baseSession(
        pausedAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
      );

      final result = original.copyWith(
        pausedAt: DateTime.utc(2024, 1, 15, 11, 0, 0),
        clearPausedAt: true,
      );

      expect(
        result.pausedAt,
        isNull,
        reason:
            'when both are supplied, clearPausedAt must win and the '
            'passed pausedAt value must be ignored',
      );
    });

    test('clearPausedAt defaults to false, so ordinary copyWith calls that '
        'never mention it are unaffected', () {
      final original = baseSession(pausedAt: null);

      final result = original.copyWith(status: 'completed');

      expect(result.pausedAt, isNull);
      expect(result.status, 'completed');
    });

    test('all unrelated fields remain unchanged by a clearPausedAt call', () {
      final original = baseSession(
        pausedAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
      );

      final result = original.copyWith(clearPausedAt: true);

      expect(result.id, original.id);
      expect(result.userId, original.userId);
      expect(result.date, original.date);
      expect(result.duration, original.duration);
      expect(result.notes, original.notes);
      expect(result.type, original.type);
      expect(result.name, original.name);
      expect(result.status, original.status);
      expect(result.startedAt, original.startedAt);
      expect(result.completedAt, original.completedAt);
      expect(result.exercises, original.exercises);
      expect(result.programId, original.programId);
      expect(result.programWorkoutId, original.programWorkoutId);
      expect(result.version, original.version);
    });
  });
}
