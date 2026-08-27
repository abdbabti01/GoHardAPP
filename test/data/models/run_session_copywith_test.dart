import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/run_session.dart';

/// Regression coverage for RunSession.copyWith's pausedAt-clearing semantics.
///
/// copyWith's standard "pass to override, omit to keep" convention cannot
/// distinguish an omitted argument from an explicitly-passed `null` -
/// `pausedAt: pausedAt ?? this.pausedAt` means `copyWith(pausedAt: null)`
/// silently keeps the OLD value instead of clearing it. This is exactly the
/// bug that made RunningProvider.resumeRun() fail to clear pausedAt, which
/// _recalculateElapsedTime() relies on to decide whether the run should
/// still be treated as paused after an app suspend/resume cycle.
/// clearPausedAt is the explicit, unambiguous way to clear it, mirroring
/// Session.copyWith's established pattern (session_copywith_test.dart).
void main() {
  RunSession baseRun({DateTime? pausedAt}) {
    return RunSession(
      id: 1,
      userId: 100,
      name: 'Morning Run',
      date: DateTime.utc(2024, 1, 15),
      distance: 3.2,
      duration: 1200,
      averagePace: 6.1,
      calories: 280,
      status: 'in_progress',
      startedAt: DateTime.utc(2024, 1, 15, 7, 0, 0),
      completedAt: null,
      pausedAt: pausedAt,
      // Left empty (constructor default) deliberately: RunSession.toJson's
      // generated `route` field stores raw GpsPoint objects rather than
      // serialized maps, so a non-empty route cannot round-trip through
      // fromJson(toJson()) - a pre-existing quirk unrelated to this fix's
      // pausedAt-clearing scope, and out of scope to touch here.
    );
  }

  group('RunSession.copyWith - pausedAt clearing', () {
    test('copyWith() with no pausedAt argument preserves the existing '
        'non-null pausedAt (the standard override-or-keep convention)', () {
      final original = baseRun(pausedAt: DateTime.utc(2024, 1, 15, 7, 30, 0));

      final result = original.copyWith();

      expect(result.pausedAt, DateTime.utc(2024, 1, 15, 7, 30, 0));
    });

    test('copyWith(pausedAt: <value>) replaces the existing pausedAt', () {
      final original = baseRun(pausedAt: DateTime.utc(2024, 1, 15, 7, 30, 0));
      final newPausedAt = DateTime.utc(2024, 1, 15, 7, 45, 0);

      final result = original.copyWith(pausedAt: newPausedAt);

      expect(result.pausedAt, newPausedAt);
    });

    test('copyWith(pausedAt: null) alone does NOT clear a non-null pausedAt '
        '- this documents the footgun clearPausedAt exists to avoid', () {
      final original = baseRun(pausedAt: DateTime.utc(2024, 1, 15, 7, 30, 0));

      // ignore: avoid_redundant_argument_values
      final result = original.copyWith(pausedAt: null);

      expect(
        result.pausedAt,
        DateTime.utc(2024, 1, 15, 7, 30, 0),
        reason:
            'passing pausedAt: null is indistinguishable from omitting it '
            'in the override-or-keep convention, so it must NOT clear the '
            'field - clearPausedAt is required for that instead',
      );
    });

    test('clearPausedAt defaults to false, so ordinary copyWith calls that '
        'never mention it are unaffected', () {
      final original = baseRun(pausedAt: null);

      final result = original.copyWith(status: 'completed');

      expect(result.pausedAt, isNull);
      expect(result.status, 'completed');
    });

    test('copyWith(clearPausedAt: true) sets pausedAt to null regardless of '
        'the current value', () {
      final original = baseRun(pausedAt: DateTime.utc(2024, 1, 15, 7, 30, 0));

      final result = original.copyWith(clearPausedAt: true);

      expect(result.pausedAt, isNull);
    });

    test('copyWith(clearPausedAt: true) combined with a new startedAt '
        'clears pausedAt while applying the new startedAt - the exact '
        'combination resumeRun() needs', () {
      final original = baseRun(pausedAt: DateTime.utc(2024, 1, 15, 7, 30, 0));
      final newStartedAt = DateTime.utc(2024, 1, 15, 7, 35, 0);

      final result = original.copyWith(
        startedAt: newStartedAt,
        clearPausedAt: true,
      );

      expect(result.startedAt, newStartedAt);
      expect(result.pausedAt, isNull);
    });

    test('clearPausedAt: true takes precedence over a simultaneously '
        'supplied pausedAt value', () {
      final original = baseRun(pausedAt: DateTime.utc(2024, 1, 15, 7, 30, 0));

      final result = original.copyWith(
        pausedAt: DateTime.utc(2024, 1, 15, 8, 0, 0),
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

    test('all unrelated fields remain unchanged by a clearPausedAt call', () {
      final original = baseRun(pausedAt: DateTime.utc(2024, 1, 15, 7, 30, 0));

      final result = original.copyWith(clearPausedAt: true);

      expect(result.id, original.id);
      expect(result.userId, original.userId);
      expect(result.name, original.name);
      expect(result.date, original.date);
      expect(result.distance, original.distance);
      expect(result.duration, original.duration);
      expect(result.averagePace, original.averagePace);
      expect(result.calories, original.calories);
      expect(result.status, original.status);
      expect(result.startedAt, original.startedAt);
      expect(result.completedAt, original.completedAt);
      expect(result.route, original.route);
    });

    test('JSON serialization round-trip is unaffected by the new '
        'clearPausedAt parameter (it is copyWith-only, not part of the '
        'model or its wire format)', () {
      final original = baseRun(pausedAt: DateTime.utc(2024, 1, 15, 7, 30, 0));
      final cleared = original.copyWith(clearPausedAt: true);

      final originalJson = original.toJson();
      final clearedJson = cleared.toJson();

      expect(originalJson['pausedAt'], isNotNull);
      expect(clearedJson['pausedAt'], isNull);

      // Round-tripping the cleared copy through fromJson/toJson must still
      // work exactly as before - clearPausedAt does not alter the JSON
      // shape or the fromJson/toJson implementations at all.
      final roundTripped = RunSession.fromJson(clearedJson);
      expect(roundTripped.pausedAt, isNull);
      expect(roundTripped.id, original.id);
      expect(roundTripped.startedAt, original.startedAt);
    });
  });
}
