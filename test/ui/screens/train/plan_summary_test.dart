import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/program.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/ui/screens/train/plan_summary.dart';

ProgramWorkout _w(
  int id,
  DateTime date, {
  bool completed = false,
  bool skipped = false,
  bool rest = false,
}) => ProgramWorkout(
  id: id,
  programId: 1,
  weekNumber: 1,
  dayNumber: date.weekday,
  workoutName: rest ? 'Rest Day' : 'Workout $id',
  workoutType: rest ? 'Rest' : 'Strength',
  exercisesJson: '[]',
  isCompleted: completed,
  isSkipped: skipped,
  orderIndex: id,
  scheduledDate: date,
);

Program _program(List<ProgramWorkout> workouts) => Program(
  id: 1,
  userId: 1,
  title: 'Upper/Lower',
  totalWeeks: 12,
  currentWeek: 2,
  currentDay: 3,
  startDate: DateTime(2026, 9, 14),
  isActive: true,
  isCompleted: false,
  createdAt: DateTime(2026, 9, 1),
  workouts: workouts,
);

DateTime _byScheduledDate(Program _, ProgramWorkout w) => w.scheduledDate!;

void main() {
  // Wednesday 23 Sep 2026; this week is Mon 21 – Sun 27.
  final now = DateTime(2026, 9, 23, 10);

  test('counts done and due, excluding rest days and future workouts', () {
    final summary = PlanSummary.of(
      _program([
        _w(1, DateTime(2026, 9, 14), completed: true),
        _w(2, DateTime(2026, 9, 16), skipped: true),
        _w(3, DateTime(2026, 9, 18)), // missed last week
        _w(4, DateTime(2026, 9, 19), rest: true),
        _w(5, DateTime(2026, 9, 21), completed: true),
        _w(6, DateTime(2026, 9, 22)), // missed this week
        _w(7, DateTime(2026, 9, 23)), // today, not yet due
        _w(8, DateTime(2026, 9, 25)),
        _w(9, DateTime(2026, 9, 28)), // next week
      ]),
      now,
      _byScheduledDate,
    );

    expect(summary.done, 2);
    expect(summary.due, 5); // 1, 2, 3, 5, 6
  });

  test('this week lists Mon–Sun workouts in date order with their state', () {
    final summary = PlanSummary.of(
      _program([
        _w(8, DateTime(2026, 9, 25)),
        _w(5, DateTime(2026, 9, 21), completed: true),
        _w(7, DateTime(2026, 9, 23)),
        _w(6, DateTime(2026, 9, 22)),
        _w(10, DateTime(2026, 9, 24), skipped: true),
        _w(4, DateTime(2026, 9, 26), rest: true),
        _w(9, DateTime(2026, 9, 28)),
      ]),
      now,
      _byScheduledDate,
    );

    expect(summary.thisWeek.map((i) => i.workout.id), [5, 6, 7, 10, 8]);
    expect(summary.thisWeek.map((i) => i.state), [
      PlanDayState.done,
      PlanDayState.missed,
      PlanDayState.today,
      PlanDayState.skipped,
      PlanDayState.upcoming,
    ]);
  });

  test('a plan with no workouts yields zeros and an empty week', () {
    final summary = PlanSummary.of(_program([]), now, _byScheduledDate);
    expect(summary.done, 0);
    expect(summary.due, 0);
    expect(summary.thisWeek, isEmpty);
  });
}
