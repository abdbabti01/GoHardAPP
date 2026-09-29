import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/plan_exercise_prescription.dart';

void main() {
  (int?, int?, int?, int?) p(Map<String, dynamic> e) {
    final r = PlanExercisePrescription.fromPlanEntry(e);
    return (
      r.exerciseTemplateId,
      r.targetSets,
      r.targetRepsMin,
      r.targetRepsMax,
    );
  }

  test('exact 3 x 8', () => expect(p({'sets': 3, 'reps': 8}), (null, 3, 8, 8)));
  test('range 3 x 8-10 with template', () {
    expect(p({'exerciseTemplateId': 1, 'sets': 3, 'reps': 8, 'repsMax': 10}), (
      1,
      3,
      8,
      10,
    ));
  });
  test('strings / doubles / non-positive are never parsed', () {
    expect(p({'exerciseTemplateId': '1', 'sets': '3', 'reps': '8-10'}), (
      null,
      null,
      null,
      null,
    ));
    expect(p({'sets': 3.0, 'reps': 8.5}), (null, null, null, null));
    expect(p({'sets': 0, 'reps': -1}), (null, null, null, null));
  });
  test(
    'repsMax below min collapses to exact; repsMax without reps ignored',
    () {
      expect(p({'sets': 3, 'reps': 10, 'repsMax': 8}), (null, 3, 10, 10));
      expect(p({'sets': 3, 'repsMax': 10}), (null, 3, null, null));
    },
  );
}
