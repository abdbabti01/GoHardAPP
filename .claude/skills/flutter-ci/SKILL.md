---
name: flutter-ci
description: Diagnose a failing GoHardAPP CI run (GitHub Actions). Use when a build/format/analyze/test job is failing and the cause is unclear.
---

# Flutter CI

Diagnose CI failures without treating "make CI green" as license to weaken tests.

## Steps

1. Read the CI log and find the **first** actual failure — later failures are often downstream noise from the first one.
2. Classify it:
   - **Application defect**: code doesn't do what the test expects.
   - **Test defect**: test is flaky, order-dependent, or asserts the wrong thing.
   - **CI/environment issue**: tool version mismatch, missing generated files, caching, timeout, platform-specific path.
3. Reproduce locally using the root `CLAUDE.md` verification order (an approximation of the CI job's intent, not claimed to be a verbatim copy of `.github/workflows/`, which stays the source of truth for the actual pipeline):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   dart format --output=none --set-exit-if-changed .
   flutter analyze
   flutter test --concurrency=1
   ```
4. Fix the root cause:
   - Application defect → fix the code (use `flutter-feature`/`flutter-sync`/`flutter-ui` as appropriate) and keep the test.
   - Genuine test defect → fix the test's logic/setup, don't just loosen the assertion.
   - CI/environment issue → make the minimal workflow change needed; don't restructure the pipeline.

## Never

- Remove, skip (`skip:`), or weaken a legitimate test just to make the pipeline pass.
- Make broad, unrelated workflow changes.

## Done when

- The first failure's root cause is identified and fixed at the source.
- The reproduction commands above pass locally.
