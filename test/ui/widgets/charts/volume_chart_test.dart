import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/workout_stats.dart';
import 'package:go_hard_app/ui/widgets/charts/volume_chart.dart';

/// Volume is stored/computed in canonical kg; the chart converts to the
/// user's unit at the presentation boundary only (`UnitConverter`), the same
/// boundary Task 4 established for Log Sets. `point.label` is never echoed:
/// older API builds send it with a hard-coded "kg".
void main() {
  ProgressDataPoint point(DateTime date, double kgValue) =>
      ProgressDataPoint(date: date, value: kgValue, label: 'ignored kg');

  group('volumeTooltipText', () {
    test('Metric shows the kg value unconverted', () {
      final text = volumeTooltipText(
        point(DateTime(2026, 3, 5), 10000),
        'Metric',
      );

      expect(text, 'Mar 5\nVolume 10.0k kg');
    });

    test('Imperial converts kg volume to lb', () {
      // 10000 / 0.45359237 = 22046.2...
      final text = volumeTooltipText(
        point(DateTime(2026, 3, 5), 10000),
        'Imperial',
      );

      expect(text, 'Mar 5\nVolume 22.0k lb');
    });

    test('a UTC calendar date from the API keeps its calendar day', () {
      // The API serializes ProgressDataPoint.Date as UTC ("...Z"). Converting
      // to local time would show the previous day west of UTC.
      final text = volumeTooltipText(
        point(DateTime.utc(2026, 3, 5), 10000),
        'Metric',
      );

      expect(text, startsWith('Mar 5\n'));
    });

    test('does not echo the server label', () {
      final text = volumeTooltipText(
        point(DateTime(2026, 3, 5), 10000),
        'Metric',
      );

      expect(text, isNot(contains('ignored')));
    });
  });

  testWidgets('x-axis captions show dates regardless of unit preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VolumeChart(
            data: [
              point(DateTime(2026, 3, 5), 1500),
              point(DateTime(2026, 3, 7), 2500),
            ],
            unitPreference: 'Imperial',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final captions = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '');
    expect(captions, contains('3/5'));
  });

  testWidgets('spots use display-unit values converted from canonical kg', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VolumeChart(
            data: [
              point(DateTime(2026, 3, 5), 10000),
              point(DateTime(2026, 3, 7), 20000),
            ],
            unitPreference: 'Imperial',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final spots = chart.data.lineBarsData.single.spots;
    expect(spots[0].y, closeTo(10000 / 0.45359237, 1e-6));
    expect(spots[1].y, closeTo(20000 / 0.45359237, 1e-6));
  });

  testWidgets('defaulting to Metric keeps existing callers compiling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VolumeChart(
            data: [
              point(DateTime(2026, 3, 5), 1000),
              point(DateTime(2026, 3, 7), 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final spots = chart.data.lineBarsData.single.spots;
    expect(spots[0].y, 1000); // Metric: no conversion
  });
}
