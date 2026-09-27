import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/workout_stats.dart';
import 'package:go_hard_app/ui/widgets/charts/volume_chart.dart';

/// Stored set weights have no reliably known unit (entry has always said lbs,
/// analytics used to say kg), so the volume chart must not claim either unit —
/// including when an older API build still sends a "... kg" label.
void main() {
  final unit = RegExp(r'\b(kg|lbs?)\b', caseSensitive: false);

  // What an API build from before this change sends.
  ProgressDataPoint legacyPoint(DateTime date, double value) =>
      ProgressDataPoint(
        date: date,
        value: value,
        label: '${value.toStringAsFixed(0)} kg',
      );

  group('volumeTooltipText', () {
    test('shows the unchanged value without any unit', () {
      final text = volumeTooltipText(legacyPoint(DateTime(2026, 3, 5), 12345));

      expect(text, isNot(matches(unit)));
      expect(text, contains('Volume 12.3k')); // 12345 / 1000, not converted
    });

    test('a UTC calendar date from the API keeps its calendar day', () {
      // The API serializes ProgressDataPoint.Date as UTC ("...Z"). Converting
      // to local time would show the previous day west of UTC.
      final text = volumeTooltipText(
        legacyPoint(DateTime.utc(2026, 3, 5), 12345),
      );

      expect(text, startsWith('Mar 5\n'));
    });

    test('does not echo the server label (no duplicated value/unit)', () {
      final text = volumeTooltipText(legacyPoint(DateTime(2026, 3, 5), 12345));

      expect(text, isNot(contains('12345')));
      expect('\n'.allMatches(text), hasLength(1)); // date line + volume line
    });
  });

  testWidgets('axis captions show dates, never a weight unit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VolumeChart(
            data: [
              legacyPoint(DateTime(2026, 3, 5), 1500),
              legacyPoint(DateTime(2026, 3, 7), 2500),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final captions = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '');
    expect(captions.where(unit.hasMatch), isEmpty);
    expect(captions, contains('3/5'));
  });
}
