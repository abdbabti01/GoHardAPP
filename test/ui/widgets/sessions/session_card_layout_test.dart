// BUG-12 regression: SessionCard's meta row (date • N exercises • duration)
// overflowed by ~10px in a narrow slot once a completed session added its
// duration segment. flutter_test reports any RenderFlex overflow as an
// exception, so simply pumping the card at these widths/text scales guards it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/ui/widgets/sessions/session_card.dart';

void main() {
  final completed = Session(
    id: 1,
    userId: 1,
    date: DateTime(2026, 9, 20),
    name: 'Chest Day',
    status: 'completed',
    duration: 95,
  );

  Widget host({required double width, double textScale = 1.0}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: SessionCard(session: completed)),
        ),
      ),
    ),
  );

  // Supported range: compact phones (320dp) to standard (360dp); common
  // accessibility text scales up to 1.5. The original failure was the meta
  // row in a ~172px inner column of a normal-width card.
  for (final width in [360.0, 320.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets(
        'completed card with duration does not overflow at ${width}px, '
        'text scale $scale',
        (tester) async {
          await tester.pumpWidget(host(width: width, textScale: scale));
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
