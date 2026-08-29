# GoHardAPP Instructions

Flutter mobile application using Provider, Dio, Isar, secure storage, and an offline-first repository architecture.

## Commands

Run from `GoHardAPP/`:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Run code generation after modifying an Isar collection, JSON-serializable model, or generated mock declaration — see Verification below for the required check order.

## Architecture

Preserve the existing dependency direction:

```text
UI -> Provider -> Repository -> API and local database services
```

- Widgets must not call Dio, API services, or Isar directly.
- Providers own presentation state and coordinate repository operations.
- Repositories coordinate remote and local data sources.
- Services handle infrastructure such as HTTP, secure storage, connectivity, local persistence, and notifications.
- Keep business and synchronization logic out of widget `build` methods.
- Follow existing dependency-injection and routing patterns.
- Prefer small reusable widgets over very large screen build methods.

## Provider State Management

- Use `context.read()` for commands and one-time access.
- Use `context.watch()` only when the widget depends on the full provider state.
- Prefer `context.select()` when only one property should trigger a rebuild.
- Keep mutable fields private and expose controlled or immutable state.
- Model loading, success, empty, and error states explicitly.
- Clear stale errors when retrying an operation.
- Avoid redundant `notifyListeners()` calls and notifications after disposal.
- Dispose timers, animation controllers, text controllers, and stream subscriptions.
- Do not start repeated network or database work from `build()`.

## Offline-First Behavior

- Scope every cached query and pending operation to the authenticated user.
- Keep local Isar IDs distinct from server IDs.
- Preserve pending creates, updates, and deletes while offline.
- Never silently discard unsynchronized user data.
- Make synchronization operations idempotent where possible.
- Prevent duplicate server records when retrying a create after an uncertain response.
- Handle partial synchronization failures without marking the full batch successful.
- Define conflict behavior explicitly; do not assume server-wins unless the existing feature requires it.
- Refresh local state and notify the relevant provider after successful synchronization.
- Ensure logout prevents access to the previous user's cached data.
- Test both online and offline paths for repository changes.

## Models and Generated Code

- Preserve JSON field names, types, nullability, and defaults expected by the API.
- Treat persisted schema changes carefully because existing users may have older local data.
- Add an Isar migration or compatibility strategy when a schema change requires one.
- Never manually edit generated files such as `*.g.dart`, generated Isar schemas, or generated mocks.
- Regenerate code after changing annotations or serializable fields.
- Review generated diffs and commit them only when the repository's established policy requires it.

## Networking and Authentication

- Use the shared Dio/API service and its configured interceptors.
- Do not create feature-specific HTTP clients without a concrete requirement.
- Keep tokens in secure storage; never persist or print them in ordinary logs.
- Handle `401` consistently with the existing authentication flow.
- Use bounded timeouts and user-friendly errors.
- Do not expose raw server exceptions or sensitive response bodies to users.

## API Contract Changes

When the backend contract changes:

- Update affected Dart models and serialization.
- Update repository requests and response mapping.
- Update provider and UI behavior for new loading or error cases.
- Regenerate code.
- Add or update tests for online, offline, and synchronization behavior.
- Search `../GoHardAPI/` for the authoritative endpoint and DTO when available.

## UI Guidelines

- Reuse the existing theme, spacing, typography, and shared widgets.
- Support light and dark themes where the surrounding screen does.
- Avoid hardcoded dimensions when responsive layout is practical.
- Keep expensive calculations and I/O outside `build()`.
- Provide accessible labels and adequate touch targets for interactive controls.
- Preserve useful content during loading instead of unnecessarily replacing the entire screen.

## Verification

If the change affects an Isar collection, JSON-serializable model, Mockito mock, or other generated source, regenerate first:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Immediately after regenerating, run `dart format .` — generated `.mocks.dart` and `.g.dart` files are included, since CI checks formatting across the full repository, not just hand-written source. Never format only production files when generated files were also touched.

Then run final verification, in order:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
```

This is the canonical command order for this project; Skills and agents apply it rather than restating it. These commands approximate CI locally — they are not claimed to be a verbatim copy of `.github/workflows/`, which remains the source of truth for the actual pipeline.

Before staging or committing, always run `dart format --output=none --set-exit-if-changed .` yourself, even if a pre-commit hook is installed — do not rely on the hook as the only check. When a generated diff is unexpectedly large, inspect it and exclude unrelated generator churn before committing.

Before shipping a Flutter branch (opening a PR or handing off work), run `tool/verify.ps1` from the repository root. It applies formatting, then re-verifies formatting, analysis, and the full test suite in the same order as above, stopping at the first failure.

A tracked pre-commit hook is available at `.githooks/pre-commit` (formatting check + `flutter analyze`, no auto-formatting, no tests — kept fast). Enable it once per clone with `tool/install-hooks.ps1`; see `tool/README.md` for details.
