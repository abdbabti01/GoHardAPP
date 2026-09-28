import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/achievement.dart';
import 'package:go_hard_app/ui/widgets/common/celebration.dart';

/// Reachable copy about lifted volume must not claim a unit: stored set weights
/// have no reliably known unit (entry has always said lbs).
void main() {
  final unit = RegExp(r'\b(kg|lbs?)\b', caseSensitive: false);

  test('volume achievements describe volume without a unit; thresholds are '
      'unchanged', () {
    final volume = AchievementDefinition.getByCategory(
      AchievementCategory.volume,
    );

    expect(volume.map((a) => a.requirement), [1000, 10000, 50000, 100000]);
    for (final a in volume) {
      expect(a.description, isNot(matches(unit)), reason: a.id);
      expect(a.description, contains('volume'), reason: a.id);
    }
  });

  testWidgets('workout-complete celebration labels volume without a unit', (
    tester,
  ) async {
    // Phone-sized surface: the overlay is laid out for a portrait phone.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutCompleteCelebration(
          duration: 30,
          exerciseCount: 3,
          setCount: 9,
          onContinue: () {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Volume'), findsOneWidget);
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '');
    expect(texts.where(unit.hasMatch), isEmpty);
  });
}
