// Regression: EmptyStateIllustrated's fallback illustration + title +
// message overflowed (RenderFlex) whenever a caller gave it less height than
// its natural size - reproduced by ActiveWorkoutScreen's exercise list once
// the timer card switches to its running layout (discovered while verifying
// BUG-11's workout-sync fix). flutter_test reports RenderFlex overflow as an
// exception, so pumping in a constrained box at various heights guards it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_hard_app/core/theme/app_theme.dart';
import 'package:go_hard_app/ui/widgets/common/empty_state.dart';

void main() {
  Widget host({required double height, double textScale = 1.0}) => MaterialApp(
    theme: AppTheme.darkTheme,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 340,
            height: height,
            child: const EmptyStateIllustrated(
              title: 'No Exercises Yet',
              message:
                  'Add exercises to your workout using the button '
                  'below',
            ),
          ),
        ),
      ),
    ),
  );

  // 177px reproduces the exact constrained height ActiveWorkoutScreen gave
  // this widget in the failing run; 400/600 cover generously roomy callers.
  for (final height in [120.0, 177.0, 250.0, 400.0, 600.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets('no overflow at height ${height}px, text scale $scale', (
        tester,
      ) async {
        await tester.pumpWidget(host(height: height, textScale: scale));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
