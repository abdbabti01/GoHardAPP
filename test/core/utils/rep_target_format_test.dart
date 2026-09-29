import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/utils/rep_target_format.dart';

void main() {
  test(
    'exact',
    () => expect(formatRepTarget(sets: 3, repsMin: 8, repsMax: 8), '3 × 8'),
  );
  test(
    'range',
    () => expect(formatRepTarget(sets: 3, repsMin: 8, repsMax: 10), '3 × 8–10'),
  );
  test(
    'reps only',
    () => expect(formatRepTarget(repsMin: 8, repsMax: 10), '8–10 reps'),
  );
  test('sets only', () => expect(formatRepTarget(sets: 3), '3 sets'));
  test('nothing', () => expect(formatRepTarget(), isNull));
}
