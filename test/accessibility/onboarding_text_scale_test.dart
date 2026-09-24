// BUG-9 regression: the onboarding Welcome page overflowed at Android text
// scale 1.3x. flutter_test reports RenderFlex overflow as an exception, so
// pumping at each scale/size and checking takeException() guards it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_hard_app/core/theme/app_theme.dart';
import 'package:go_hard_app/ui/screens/onboarding/pages/welcome_page.dart';

void main() {
  // Logical sizes: compact (320x568) and a typical Pixel-class phone.
  const sizes = [Size(320, 568), Size(360, 760)];
  const scales = [1.0, 1.3, 1.5, 2.0];

  for (final size in sizes) {
    for (final scale in scales) {
      testWidgets('WelcomePage has no overflow at ${size.width.toInt()}x'
          '${size.height.toInt()}, text scale $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: const Scaffold(body: WelcomePage()),
            ),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(tester.takeException(), isNull);
      });
    }
  }
}
