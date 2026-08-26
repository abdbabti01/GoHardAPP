---
name: flutter-ui
description: Implement or change GoHardAPP screens and widgets. Use for visual/UI work — new screens, layout changes, component reuse, responsiveness, accessibility, and UI state handling.
---

# Flutter UI

Implement the requested screen or widget change while keeping the UI layer a thin consumer of providers. Apply the UI Guidelines and Provider State Management rules in the root `CLAUDE.md`; this skill only adds workflow-specific steps.

## Before editing

- Inspect the existing theme (`lib/core/theme/`) and shared widgets. Find a similar existing screen/widget and match its structure and Provider usage instead of inventing new patterns.

## While implementing

- Keep business logic and I/O out of `build()`; call into an existing provider/repository.
- Cover the states relevant to the screen: loading, empty, error, offline, and sync-conflict (if the underlying data can be pending/conflicted).
- BuildContext safety:
  - After `await`, check `context.mounted` before using `BuildContext`.
  - Do not retain a `BuildContext` across an asynchronous gap.
  - Check `mounted` before asynchronous UI or state updates where applicable.

## Visual verification

For material screen or widget changes, use the `run` Skill to launch the app on an available emulator, simulator, or device, and verify:
- normal phone layout,
- small-screen overflow,
- loading state,
- empty state,
- error or offline state when applicable.

Skip visual launching for tiny text, color, or spacing changes when widget tests and inspection are sufficient.

## Tests

- Add widget tests for the new/changed UI covering at least the primary state and one alternate state (error, empty, or offline).

## Done when

- The screen reuses existing design system elements per the root `CLAUDE.md` UI Guidelines.
- Loading/empty/error/offline states and BuildContext safety are handled where applicable.
- Widget tests pass and the root `CLAUDE.md` verification commands are clean.
