# Maestro E2E Flows

Native-Android-level E2E automation for GoHardAPP, driven by
[Maestro](https://maestro.mobile.dev).

**Maestro is not the primary layer for asserting on Flutter app content in
this project — see "Known limitation" below.** Use
`integration_test/` (Flutter's official E2E package, at the repo root) for
that instead; reserve Maestro for things outside the Flutter widget tree:
permission dialogs, cold install/launch checks, deep links, cross-app flows,
and device screenshots/video for human review.

## Prerequisites

- Android emulator or device running and visible to `adb devices`.
- App installed: `flutter build apk --debug` then
  `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
  (or `flutter install -d <device-id>`).
- Maestro CLI on PATH: `maestro --version`.

## Running

From this directory or the repo root:

```
maestro test maestro/flows/smoke.yaml
```

Run all flows:

```
maestro test maestro/flows
```

## App identity

- applicationId: `com.example.go_hard_app` (see `android/app/build.gradle.kts`).

## Conventions

- Prefer `assertVisible`/`tapOn` with visible text or accessibility labels over
  raw coordinates — but see the limitation below: this currently doesn't work
  for Flutter-drawn content at all in this project, only for genuinely native
  Android UI (permission dialogs, system screens).
- Keep flows small and focused on one journey each.

## Known limitation: Maestro cannot read Flutter's accessibility tree here

Confirmed by direct testing, re-verified across two Flutter versions and two
Android API levels: `maestro/flows/smoke.yaml` launches the real app
correctly, but its `assertVisible "Welcome to GoHard"` step fails every time.
This is not a local misconfiguration:

- `maestro hierarchy` and raw `adb shell uiautomator dump` both return only
  the OS status bar clock for the Flutter view — zero Flutter widgets ever
  appear, on Flutter 3.29.2 and 3.47.5 alike, on Android 14 (API 34,
  `Pixel_API_34`) and Android 16 (API 36, `Pixel_7`/`Pixel_9`) alike.
- TalkBack, run as a real bound AccessibilityService, correctly builds and
  navigates the same tree (its focus highlight lands on the right widget) —
  so Flutter genuinely is exposing semantics to Android; Maestro's/
  UiAutomator's snapshot of it comes back empty regardless.
- The same `maestro hierarchy` command correctly reads all text from a
  native (non-Flutter) screen, e.g. Android Settings, on the same emulator —
  ruling out a broken Maestro install or ADB connection.
- `SemanticsBinding.instance.ensureSemantics()` was tried in `lib/main.dart`
  and made no measurable difference in any of the above (tested with/without,
  TalkBack on/off) — it was reverted. Real screen-reader users already get
  correct semantics automatically the moment a real AccessibilityService is
  active; that mechanism, not `ensureSemantics()`, is what TalkBack relies on.

This matches a known, currently-unresolved upstream Maestro/Flutter issue
(mobile-dev-inc/Maestro#2298 and related reports across Android 14–16) in
how Maestro/UiAutomator read Flutter's embedded accessibility nodes, not
something fixable from this project's code or Gradle/AGP/Kotlin
configuration.

**Do not add coordinate-based taps/assertions here to work around this.**
Use `integration_test/` instead for anything that needs to assert on real
Flutter content — it finds widgets via the Dart widget tree directly
(`find.text()`, `find.byType()`, etc.), which is unaffected by this issue,
and was confirmed working with `flutter test integration_test/smoke_test.dart
-d <device>` on both API 34 and API 36.

Re-test this limitation periodically: `maestro --version` was 2.10.0 (already
latest) at time of writing; if a future Maestro/Flutter release claims a fix,
re-run `maestro hierarchy` while the app is on the welcome screen and check
for real widget text (not just the status-bar clock) before trusting
`assertVisible` again.

## Emulator notes (unrelated crashes found and fixed along the way)

- Pixel_2 / Pixel_3a / Pixel_4 (older, 32-bit `x86` images) crash the app on
  startup with `IsarError: Cannot open Environment: MdbxError (75): Value too
  large for defined data type` — Isar/MDBX needs a 64-bit process. Use an
  `x86_64` image (`Pixel_7`, `Pixel_9`, `Pixel_API_34`) instead.
- The app used to crash on startup on any API level once you looked closely
  (`ClassCastException: MainActivity cannot be cast to
  androidx.activity.ComponentActivity`, then a fatal NPE in
  `audio_service`'s `AudioServicePlugin$2.onConnectionFailed`). Root cause:
  `AndroidManifest.xml` was missing the `audio_service` plugin's required
  `<service>`/`<receiver>` declarations, and `MainActivity` extended plain
  `FlutterActivity` instead of `AudioServiceFragmentActivity`. Both are now
  fixed (see `AndroidManifest.xml` and `MainActivity.kt`) — this was a real,
  latent app bug, not test-environment-specific, just easier to hit on some
  emulator images than others.
