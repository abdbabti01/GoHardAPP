import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';

/// Where one planned workout in the current week stands today.
enum PlanDayState { done, skipped, missed, today, upcoming }

class PlanWeekItem {
  final ProgramWorkout workout;
  final DateTime date;
  final PlanDayState state;

  const PlanWeekItem({
    required this.workout,
    required this.date,
    required this.state,
  });
}

/// Read-only numbers Train shows for a plan. Rest days never count.
class PlanSummary {
  /// Completed workouts.
  final int done;

  /// Workouts due by now: every completed one plus any scheduled before
  /// today (skipped and missed count as due but not done).
  final int due;

  /// This calendar week's (Mon–Sun) workouts, in date order.
  final List<PlanWeekItem> thisWeek;

  const PlanSummary({
    required this.done,
    required this.due,
    required this.thisWeek,
  });

  factory PlanSummary.of(
    Program program,
    DateTime now,
    DateTime Function(Program, ProgramWorkout) scheduledDateOf,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    var done = 0;
    var due = 0;
    final thisWeek = <PlanWeekItem>[];

    for (final workout in program.workouts ?? const <ProgramWorkout>[]) {
      if (workout.isRestDay) continue;
      final date = scheduledDateOf(program, workout);
      if (workout.isCompleted) done++;
      if (workout.isCompleted || date.isBefore(today)) due++;
      if (!date.isBefore(weekStart) && date.isBefore(weekEnd)) {
        thisWeek.add(
          PlanWeekItem(
            workout: workout,
            date: date,
            state: _stateOf(workout, date, today),
          ),
        );
      }
    }

    thisWeek.sort((a, b) => a.date.compareTo(b.date));
    return PlanSummary(done: done, due: due, thisWeek: thisWeek);
  }

  static PlanDayState _stateOf(
    ProgramWorkout workout,
    DateTime date,
    DateTime today,
  ) {
    if (workout.isCompleted) return PlanDayState.done;
    if (workout.isSkipped) return PlanDayState.skipped;
    if (date == today) return PlanDayState.today;
    return date.isBefore(today) ? PlanDayState.missed : PlanDayState.upcoming;
  }
}
