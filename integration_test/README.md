# Integration Tests

Real-device/emulator E2E tests using Flutter's official
[`integration_test`](https://docs.flutter.dev/testing/integration-tests)
package. This is the primary layer for asserting on real Flutter app
content end-to-end — see `../maestro/README.md` for why Maestro is used only
for native-Android-level concerns in this project instead.

## Running

```
flutter test integration_test/smoke_test.dart -d <device-id>
```

`<device-id>` is whatever `flutter devices`/`adb devices` shows (e.g. an
emulator ID like `emulator-5554`).

## Writing a new test

Call the app's own `main()` so tests exercise the real startup path, then
drive/assert with the same `WidgetTester` API used in ordinary widget tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_hard_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('...', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('...'), findsOneWidget);
    // tester.tap(...), tester.enterText(...), etc.
  });
}
```

## Running the QA journeys (isolated local backend only)

The `qa_*` tests create accounts and write data. They must only run against a
disposable local backend, never production.

1. Start a disposable Postgres and the API (from `GoHardAPI/GoHardAPI`):

   ```
   docker run -d --name gohard-qa-postgres -e POSTGRES_PASSWORD=qapass -p 5434:5432 postgres:15
   $env:ASPNETCORE_ENVIRONMENT="Development"
   $env:LOCAL_QA_ENSURE_CREATED="true"
   $env:DATABASE_URL="postgresql://postgres:qapass@localhost:5434/gohard_qa_local"
   dotnet run --urls "http://0.0.0.0:5121"
   ```

   (`LOCAL_QA_ENSURE_CREATED` builds the schema directly because the migration
   history is not replayable on an empty database; it is a local-QA bypass only.)

2. Run the files with the runner. It refuses non-local API hosts, checks the
   API is reachable, clears app data before every file, and reports PASS/FAIL
   per file (logs in `build/qa-runs/`):

   ```
   .\tool\run-integration.ps1 -Files qa_auth_journey_test.dart
   .\tool\run-integration.ps1 -All
   ```

   The app reads its API base from `--dart-define=API_HOST=http://10.0.2.2:5121`
   (`10.0.2.2` is the host machine as seen from the Android emulator); the
   runner passes it for you.

Why state is reset between files: a session left signed in by one file leaks
into the next and produces misleading failures. `flutter test` also uninstalls
the app when a run finishes, so it cannot be used to check data that must
survive a process restart - use an installed debug build and `adb shell am
force-stop` for that.

### Writing tests: gotchas seen in practice

- Coordinates in `tester.drag`/`dragFrom` are logical pixels (a 1080x2280 phone
  is roughly 393x829), so off-screen offsets silently do nothing. Drag a
  finder (`tester.drag(find.byType(ListView).first, ...)`).
- Wait for animations before tapping (FAB entrance, list fade-in) or the tap
  lands on the wrong widget.
- `pumpUntilFound` in `qa_helpers.dart` does not throw on timeout; assert after it.
- Persistence to the server is asynchronous: poll the API for the expected
  state instead of asserting immediately.
- Known intentionally-red regression test: `qa_workout_sync_test.dart` (BUG-11,
  a started workout never reaches the server as `in_progress`). It turns green
  only when that defect is fixed.

## Release signing

Release builds read `android/key.properties` (git-ignored) or the
`GOHARD_KEYSTORE_PATH/_PASSWORD`, `GOHARD_KEY_ALIAS/_PASSWORD` environment
variables. Without them a release build falls back to the debug key with a
warning; set `REQUIRE_RELEASE_SIGNING=true` in release CI to make that a hard
failure. `key.properties` format:

```
storeFile=C:/path/to/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```
