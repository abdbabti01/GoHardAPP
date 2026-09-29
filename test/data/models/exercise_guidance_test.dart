import 'package:flutter_test/flutter_test.dart';

import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/models/exercise_guidance.dart';

/// Pure unit coverage of [PreviousPerformanceRules] (Phase 2D spec §3) using
/// plain in-memory model objects - no Isar. The repository-level Isar tests
/// in `exercise_repository_previous_performance_test.dart` remain the
/// integration evidence; this file isolates the candidate-selection and
/// strict ordinal-pairing logic so it can be verified directly.
void main() {
  final base = DateTime.utc(2026, 1, 1);

  LocalSession sessionOf({
    required int localId,
    int userId = 1,
    String status = 'completed',
    DateTime? date,
    DateTime? completedAt,
    String syncStatus = 'synced',
  }) => LocalSession(
    userId: userId,
    date: date ?? base,
    status: status,
    completedAt: completedAt,
    syncStatus: syncStatus,
    lastModifiedLocal: date ?? base,
  )..localId = localId;

  LocalExercise exerciseOf({
    required int localId,
    int sessionLocalId = 1,
    int sortOrder = 0,
    String syncStatus = 'synced',
  }) => LocalExercise(
    sessionLocalId: sessionLocalId,
    name: 'Bench Press',
    sortOrder: sortOrder,
    syncStatus: syncStatus,
    lastModifiedLocal: base,
  )..localId = localId;

  LocalExerciseSet setOf({
    required int localId,
    int exerciseLocalId = 1,
    int setNumber = 1,
    int? reps,
    double? weight,
    int? duration,
    String syncStatus = 'synced',
  }) => LocalExerciseSet(
    exerciseLocalId: exerciseLocalId,
    setNumber: setNumber,
    reps: reps,
    weight: weight,
    duration: duration,
    syncStatus: syncStatus,
    lastModifiedLocal: base,
  )..localId = localId;

  group('compareSessionsNewestFirst', () {
    test('orders by completedAt desc when present', () {
      final a = sessionOf(localId: 1, completedAt: base);
      final b = sessionOf(
        localId: 2,
        completedAt: base.add(const Duration(days: 1)),
      );
      expect(
        PreviousPerformanceRules.compareSessionsNewestFirst(a, b) > 0,
        isTrue,
      );
      expect(
        PreviousPerformanceRules.compareSessionsNewestFirst(b, a) < 0,
        isTrue,
      );
    });

    test('falls back to date when completedAt is null', () {
      final a = sessionOf(localId: 1, status: 'in_progress', date: base);
      final b = sessionOf(
        localId: 2,
        status: 'in_progress',
        date: base.add(const Duration(days: 1)),
      );
      expect(
        PreviousPerformanceRules.compareSessionsNewestFirst(a, b) > 0,
        isTrue,
      );
    });

    test('ties break deterministically by localId desc', () {
      final a = sessionOf(localId: 1, completedAt: base);
      final b = sessionOf(localId: 2, completedAt: base);
      // Same completedAt and (implicitly) same date -> higher localId first.
      expect(
        PreviousPerformanceRules.compareSessionsNewestFirst(a, b) > 0,
        isTrue,
      );
      expect(
        PreviousPerformanceRules.compareSessionsNewestFirst(b, a) < 0,
        isTrue,
      );
    });
  });

  group('isCountedExercise', () {
    test('synced and pending_create/update rows count', () {
      expect(
        PreviousPerformanceRules.isCountedExercise(exerciseOf(localId: 1)),
        isTrue,
      );
      expect(
        PreviousPerformanceRules.isCountedExercise(
          exerciseOf(localId: 1, syncStatus: 'pending_create'),
        ),
        isTrue,
      );
    });

    test('pending_delete and conflict rows never count', () {
      expect(
        PreviousPerformanceRules.isCountedExercise(
          exerciseOf(localId: 1, syncStatus: 'pending_delete'),
        ),
        isFalse,
      );
      expect(
        PreviousPerformanceRules.isCountedExercise(
          exerciseOf(localId: 1, syncStatus: 'conflict'),
        ),
        isFalse,
      );
    });
  });

  group('isLoggedSet', () {
    test('reps, positive duration, or positive weight counts as logged', () {
      expect(
        PreviousPerformanceRules.isLoggedSet(setOf(localId: 1, reps: 10)),
        isTrue,
      );
      expect(
        PreviousPerformanceRules.isLoggedSet(setOf(localId: 1, duration: 30)),
        isTrue,
      );
      expect(
        PreviousPerformanceRules.isLoggedSet(setOf(localId: 1, weight: 50.0)),
        isTrue,
      );
    });

    test('all-empty or zero/negative values are not logged', () {
      expect(PreviousPerformanceRules.isLoggedSet(setOf(localId: 1)), isFalse);
      expect(
        PreviousPerformanceRules.isLoggedSet(setOf(localId: 1, duration: 0)),
        isFalse,
      );
      expect(
        PreviousPerformanceRules.isLoggedSet(setOf(localId: 1, weight: 0.0)),
        isFalse,
      );
    });

    test('pending_delete sets are never logged, even with values', () {
      expect(
        PreviousPerformanceRules.isLoggedSet(
          setOf(
            localId: 1,
            reps: 10,
            weight: 50.0,
            syncStatus: 'pending_delete',
          ),
        ),
        isFalse,
      );
    });
  });

  group('isEligibleCandidate', () {
    final current = sessionOf(localId: 10, status: 'in_progress', date: base);

    test('other user is excluded', () {
      final candidate = sessionOf(localId: 1, userId: 2, completedAt: base);
      expect(
        PreviousPerformanceRules.isEligibleCandidate(
          current,
          candidate,
          1,
          canonical: true,
        ),
        isFalse,
      );
    });

    test('not completed is excluded', () {
      final candidate = sessionOf(
        localId: 1,
        status: 'in_progress',
        date: base,
      );
      expect(
        PreviousPerformanceRules.isEligibleCandidate(
          current,
          candidate,
          1,
          canonical: true,
        ),
        isFalse,
      );
    });

    test('the current session itself is excluded', () {
      final self = sessionOf(localId: 10, status: 'in_progress', date: base);
      expect(
        PreviousPerformanceRules.isEligibleCandidate(
          current,
          self,
          1,
          canonical: true,
        ),
        isFalse,
      );
    });

    test('pending_delete session is excluded', () {
      final candidate = sessionOf(
        localId: 1,
        completedAt: base,
        syncStatus: 'pending_delete',
      );
      expect(
        PreviousPerformanceRules.isEligibleCandidate(
          current,
          candidate,
          1,
          canonical: true,
        ),
        isFalse,
      );
    });

    test('non-canonical (legacy / purge-eligible) is excluded', () {
      final candidate = sessionOf(localId: 1, completedAt: base);
      expect(
        PreviousPerformanceRules.isEligibleCandidate(
          current,
          candidate,
          1,
          canonical: false,
        ),
        isFalse,
      );
    });

    test('otherwise-eligible candidate is accepted', () {
      final candidate = sessionOf(localId: 1, completedAt: base);
      expect(
        PreviousPerformanceRules.isEligibleCandidate(
          current,
          candidate,
          1,
          canonical: true,
        ),
        isTrue,
      );
    });

    group('completed-current temporal boundary', () {
      test('strictly older candidate is eligible', () {
        final completedCurrent = sessionOf(
          localId: 10,
          completedAt: base.add(const Duration(days: 5)),
        );
        final older = sessionOf(localId: 1, completedAt: base);
        expect(
          PreviousPerformanceRules.isEligibleCandidate(
            completedCurrent,
            older,
            1,
            canonical: true,
          ),
          isTrue,
        );
      });

      test('a candidate completed strictly after is excluded', () {
        final completedCurrent = sessionOf(localId: 10, completedAt: base);
        final later = sessionOf(
          localId: 1,
          completedAt: base.add(const Duration(days: 5)),
        );
        expect(
          PreviousPerformanceRules.isEligibleCandidate(
            completedCurrent,
            later,
            1,
            canonical: true,
          ),
          isFalse,
        );
      });

      test(
        'equal ordering key ties break deterministically (higher localId is "newer")',
        () {
          // Same completedAt/date: compareSessionsNewestFirst breaks the tie by
          // localId desc, so a candidate with a HIGHER localId than current is
          // treated as not-older (excluded), and a LOWER localId is older
          // (included) - even though nothing distinguishes their timestamps.
          final completedCurrent = sessionOf(localId: 10, completedAt: base);
          final higherLocalId = sessionOf(localId: 20, completedAt: base);
          final lowerLocalId = sessionOf(localId: 5, completedAt: base);
          expect(
            PreviousPerformanceRules.isEligibleCandidate(
              completedCurrent,
              higherLocalId,
              1,
              canonical: true,
            ),
            isFalse,
          );
          expect(
            PreviousPerformanceRules.isEligibleCandidate(
              completedCurrent,
              lowerLocalId,
              1,
              canonical: true,
            ),
            isTrue,
          );
        },
      );

      test('an in_progress current session has no temporal boundary', () {
        final inProgressCurrent = sessionOf(
          localId: 10,
          status: 'in_progress',
          date: base,
        );
        final laterCompleted = sessionOf(
          localId: 20,
          completedAt: base.add(const Duration(days: 5)),
        );
        expect(
          PreviousPerformanceRules.isEligibleCandidate(
            inProgressCurrent,
            laterCompleted,
            1,
            canonical: true,
          ),
          isTrue,
        );
      });
    });
  });

  group('orderedOccurrences / ordinalOf / occurrenceAt', () {
    test('conflict and pending_delete exercises never occupy a slot', () {
      final ghost = exerciseOf(
        localId: 1,
        sortOrder: 0,
        syncStatus: 'conflict',
      );
      final deleted = exerciseOf(
        localId: 2,
        sortOrder: 1,
        syncStatus: 'pending_delete',
      );
      final real = exerciseOf(localId: 3, sortOrder: 2);
      final ordered = PreviousPerformanceRules.orderedOccurrences([
        ghost,
        deleted,
        real,
      ]);
      expect(ordered.map((e) => e.localId).toList(), [3]);
    });

    test('ordering ties (same sortOrder) are broken by localId', () {
      final b = exerciseOf(localId: 20, sortOrder: 0);
      final a = exerciseOf(localId: 10, sortOrder: 0);
      final ordered = PreviousPerformanceRules.orderedOccurrences([b, a]);
      expect(ordered.map((e) => e.localId).toList(), [10, 20]);
    });

    test(
      'ordinalOf finds the counted position of current, ignoring non-counted rows before it',
      () {
        final ghost = exerciseOf(
          localId: 1,
          sortOrder: 0,
          syncStatus: 'conflict',
        );
        final first = exerciseOf(localId: 2, sortOrder: 1);
        final second = exerciseOf(localId: 3, sortOrder: 2);
        final all = [ghost, first, second];
        expect(PreviousPerformanceRules.ordinalOf(all, first), 0);
        expect(PreviousPerformanceRules.ordinalOf(all, second), 1);
      },
    );

    test('ordinalOf returns -1 when current is not itself counted', () {
      final deleted = exerciseOf(
        localId: 1,
        sortOrder: 0,
        syncStatus: 'pending_delete',
      );
      final real = exerciseOf(localId: 2, sortOrder: 1);
      expect(PreviousPerformanceRules.ordinalOf([deleted, real], deleted), -1);
    });

    test('occurrenceAt returns the k-th counted row', () {
      final first = exerciseOf(localId: 1, sortOrder: 0);
      final second = exerciseOf(localId: 2, sortOrder: 1);
      final all = [first, second];
      expect(PreviousPerformanceRules.occurrenceAt(all, 0)?.localId, 1);
      expect(PreviousPerformanceRules.occurrenceAt(all, 1)?.localId, 2);
    });

    test(
      'occurrenceAt beyond range -> null, with no fallback to any other index',
      () {
        final only = exerciseOf(localId: 1, sortOrder: 0);
        expect(PreviousPerformanceRules.occurrenceAt([only], 1), isNull);
        expect(PreviousPerformanceRules.occurrenceAt([only], 5), isNull);
        expect(
          PreviousPerformanceRules.occurrenceAt(<LocalExercise>[], 0),
          isNull,
        );
      },
    );

    test(
      'occurrenceAt never returns a non-counted row even at its raw index',
      () {
        final deleted = exerciseOf(
          localId: 1,
          sortOrder: 0,
          syncStatus: 'pending_delete',
        );
        // Only one row, and it is not counted -> no slot 0 at all.
        expect(PreviousPerformanceRules.occurrenceAt([deleted], 0), isNull);
      },
    );
  });
}
