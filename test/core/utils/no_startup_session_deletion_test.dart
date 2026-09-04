import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structure guard against re-introducing a destructive, retry-count-based,
/// pre-authentication Session cleanup. Behavioural coverage lives in
/// `session_sync_failure_retention_test.dart`; this file only pins the wiring
/// so the anti-pattern cannot come back unnoticed.
void main() {
  final repoRoot = Directory.current.path;
  String read(String rel) => File('$repoRoot/$rel').readAsStringSync();

  test('main.dart invokes no DatabaseCleanup / retired cleanup method', () {
    final main = read('lib/main.dart');
    expect(main.contains('cleanupFailedSessions'), isFalse);
    expect(main.contains('cleanupDuplicateProgramWorkouts'), isFalse);
    expect(main.contains('DatabaseCleanup'), isFalse);
  });

  test('database_cleanup.dart no longer defines the destructive methods and '
      'cannot delete Sessions by a retry-count / programWorkoutId scan', () {
    final src = read('lib/core/utils/database_cleanup.dart');

    // The two retired methods are gone.
    expect(src.contains('cleanupFailedSessions'), isFalse);
    expect(src.contains('cleanupDuplicateProgramWorkouts'), isFalse);

    // No retry-count / duplicate-draft filtering, no per-row session delete -
    // the only surviving helper is `clearAllData` (a full `.clear()` wipe).
    expect(src.contains('syncRetryCountGreaterThan'), isFalse);
    expect(src.contains('programWorkoutId'), isFalse);
    expect(src.contains('.delete('), isFalse);
    expect(src.contains('.deleteAll('), isFalse);
    expect(src.contains("statusEqualTo('draft')"), isFalse);
    expect(src.contains("statusEqualTo('planned')"), isFalse);

    // Exactly one public helper remains. The return-type pattern is
    // deliberately permissive (nested generics, non-Future returns) so a
    // re-introduced destructive helper cannot hide behind an exotic signature.
    final methods =
        RegExp(
          r'static\s+[\w<>,\s]+?\s+(\w+)\s*\(',
        ).allMatches(src).map((m) => m.group(1)).toList();
    expect(methods, ['clearAllData']);
  });
}
