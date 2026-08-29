# tool/

Local developer tooling for GoHardAPP. Windows PowerShell scripts that back
the verification steps documented in the root `CLAUDE.md`.

## Setup once

```powershell
.\tool\install-hooks.ps1
```

Configures this repository (only this repository — no global Git config
changes) to run the tracked hooks in `.githooks/` via `core.hooksPath`.

Once installed, every `git commit` runs `.githooks/pre-commit`, which checks
formatting (`dart format --output=none --set-exit-if-changed .`) and
`flutter analyze`. It does not modify files and does not run tests, so
commits stay fast. If the formatting check fails, run `dart format .` to fix
it, re-stage, and commit again.

## Before shipping a branch

```powershell
.\tool\verify.ps1
```

Runs the full canonical verification sequence from `CLAUDE.md`, in order:

1. `dart format .` (applies formatting)
2. `dart format --output=none --set-exit-if-changed .` (verifies)
3. `flutter analyze`
4. `flutter test --concurrency=1`

Stops immediately with a non-zero exit code on the first failure. Works from
any current directory — it resolves the repository root from its own script
location.
