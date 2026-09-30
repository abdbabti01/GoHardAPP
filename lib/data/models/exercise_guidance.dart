import '../local/models/local_exercise.dart';
import '../local/models/local_exercise_set.dart';
import '../local/models/local_session.dart';
import 'exercise_set.dart';

/// Most recent prior logged performance of one exercise occurrence
/// (Phase 2D spec §3). [sets] are in setNumber order with weights in
/// canonical kg exactly as stored - never converted here.
class PreviousPerformance {
  final int sessionLocalId;
  final DateTime performedAt;
  final List<ExerciseSet> sets;
  const PreviousPerformance({
    required this.sessionLocalId,
    required this.performedAt,
    required this.sets,
  });
}

/// What Log Sets shows for one exercise: the snapshotted target (from the
/// session exercise itself, never the plan) and the previous performance.
class ExerciseGuidance {
  final int? targetSets;
  final int? targetRepsMin;
  final int? targetRepsMax;
  final PreviousPerformance? previous;
  const ExerciseGuidance({
    this.targetSets,
    this.targetRepsMin,
    this.targetRepsMax,
    this.previous,
  });
}

/// Deterministic ordering/qualification rules for the previous-performance
/// query, kept pure for direct testing.
abstract final class PreviousPerformanceRules {
  /// Within one session: sortOrder, then localId.
  static int compareExerciseOrder(LocalExercise a, LocalExercise b) {
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    return bySort != 0 ? bySort : a.localId.compareTo(b.localId);
  }

  /// Newest first: (completedAt ?? date) desc, date desc, localId desc.
  static int compareSessionsNewestFirst(LocalSession a, LocalSession b) {
    final byWhen = (b.completedAt ?? b.date).compareTo(a.completedAt ?? a.date);
    if (byWhen != 0) return byWhen;
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.localId.compareTo(a.localId);
  }

  /// Deleted-intent rows and reconcile `conflict` placeholders (whose server
  /// twin exists separately) never occupy an ordinal slot.
  static bool isCountedExercise(LocalExercise e) =>
      e.syncStatus != 'pending_delete' && e.syncStatus != 'conflict';

  /// A logged set records something actually performed.
  static bool isLoggedSet(LocalExerciseSet s) =>
      s.syncStatus != 'pending_delete' &&
      (s.reps != null || (s.duration ?? 0) > 0 || (s.weight ?? 0) > 0);

  /// True only when [candidate] is a historical session eligible to supply
  /// previous performance for [current]: owned by [userId], completed,
  /// distinct from [current], not a deletion tombstone, canonical (not
  /// legacy / purge-eligible - see `LiftedWeightContractMigration.wouldPurge`),
  /// and - only when [current] is itself completed - strictly older than it
  /// (a completed session never sees history completed after it; a
  /// still-in-progress current session has no such boundary).
  static bool isEligibleCandidate(
    LocalSession current,
    LocalSession candidate,
    int userId, {
    required bool canonical,
  }) =>
      candidate.userId == userId &&
      candidate.status == 'completed' &&
      candidate.localId != current.localId &&
      candidate.syncStatus != 'pending_delete' &&
      canonical &&
      (current.status != 'completed' ||
          compareSessionsNewestFirst(current, candidate) < 0);

  /// The counted, ordered same-template exercises of one session (spec §3's
  /// ordinal sequence): [isCountedExercise] rows only, sorted by
  /// [compareExerciseOrder].
  static List<LocalExercise> orderedOccurrences(
    Iterable<LocalExercise> sameTemplate,
  ) =>
      sameTemplate.where(isCountedExercise).toList()
        ..sort(compareExerciseOrder);

  /// [current]'s position within [orderedOccurrences] of [sameTemplate], or
  /// `-1` if [current] does not occupy a counted slot in its own session.
  static int ordinalOf(
    Iterable<LocalExercise> sameTemplate,
    LocalExercise current,
  ) => orderedOccurrences(
    sameTemplate,
  ).indexWhere((e) => e.localId == current.localId);

  /// The exercise at ordinal position [k] within [orderedOccurrences] of
  /// [sameTemplate], or `null` when that session has no such slot. Never
  /// falls back to any other position.
  static LocalExercise? occurrenceAt(
    Iterable<LocalExercise> sameTemplate,
    int k,
  ) {
    final ordered = orderedOccurrences(sameTemplate);
    return k >= 0 && k < ordered.length ? ordered[k] : null;
  }
}
