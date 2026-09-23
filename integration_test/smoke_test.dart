// Proof-of-concept E2E smoke test using Flutter's official integration_test
// package, run directly against the real app on a real Android emulator.
//
// This exists to compare against maestro/flows/smoke.yaml: that Maestro flow
// launches the app correctly but its semantic `assertVisible` step currently
// fails because Maestro/UiAutomator cannot read Flutter's Android
// accessibility tree in this environment (see maestro/README.md). This test
// proves the same assertion succeeds when driven through Flutter's own
// widget tree instead of the native accessibility tree.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:go_hard_app/main.dart' as app;

import 'qa_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app launches and shows the welcome onboarding screen', (
    tester,
  ) async {
    app.main();
    await pumpUntilFound(tester, find.text('Welcome to GoHard'));

    expect(find.text('Welcome to GoHard'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
