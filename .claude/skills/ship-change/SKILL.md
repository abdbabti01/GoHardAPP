---
name: ship-change
description: Verify, commit, and push a completed GoHardAPP change, and open a PR. Use when the user asks to commit, ship, or open a PR for work already implemented on a feature branch.
---

# Ship Change

Claude performs the Git operations here directly — safely and explicitly.

## Guardrails

- Never commit directly on `main` or `master`; if on one, stop and ask for/create a feature branch.
- Stage explicit files by name only. Never use `git add .`, `git add -A`, `git commit -a`, `git reset --hard`, or force push.
- Preserve unrelated changes and untracked files — do not touch anything outside the files you intend to ship.
- Never merge a PR unless explicitly requested.

## Steps

1. `git status --short` and `git diff` to see exactly what changed; decide the explicit file list to stage.
2. `git diff --check` for whitespace/conflict-marker errors, and review the staged diff content once staged.
3. Run the root `CLAUDE.md` verification order, stopping to fix on failure. If the change affects an Isar collection, JSON-serializable model, Mockito mock, or other generated source, regenerate first:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```
   Then run final verification:
   ```bash
   dart format --output=none --set-exit-if-changed .
   flutter analyze
   flutter test --concurrency=1
   ```
4. If `build_runner` regenerated files, inspect the diff of those generated files for unrelated churn (e.g. unrelated schema drift) before including them.
5. Stage the explicit file list (including any legitimately-changed generated files) and commit with a message describing why, not just what.
6. Push the branch normally (no `--force`).
7. If the GitHub CLI (`gh`) is installed and authenticated (`gh auth status`), open a PR with `gh pr create`. Otherwise, state that a PR was not created and why.

## Report

State clearly:
- Branch name and commit hash.
- Exact files committed.
- Verification commands run and their results.
- Final `git status` and whether a PR was opened (with URL) or not.
