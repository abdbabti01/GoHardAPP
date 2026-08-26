---
name: review-change
description: Review the current branch's diff against origin/main before shipping. Use before committing/pushing a non-trivial change, or when the user asks for a review of what changed.
---

# Review Change

A read-only review of the current diff — not a full-project audit.

## Steps

1. In the main session, diff the current branch against `origin/main` (`git fetch origin` then `git diff origin/main...HEAD`) to get the exact changed files and content, and check the latest test output. Reviewer subagents have no Bash access and cannot do this themselves — this inspection must happen here first. Do not review files outside this diff.
2. Choose reviewers based on what changed, using **no more than two** agents:
   - Any screen/widget under `lib/ui/` changed → `flutter-ui-reviewer`.
   - Provider, repository, Isar, sync, or auth/cache code changed → `flutter-architecture-reviewer`.
   - API models, routes, or payloads changed → `api-contract-reviewer`.
   - If more than two categories apply, pick the two most load-bearing for this change (architecture/sync findings usually outrank pure UI polish).
   - CI-only changes (`.github/workflows/`) → use `flutter-ci` instead of the reviewers above.
   - Docs/configuration-only changes (e.g. `CLAUDE.md`, `.claude/`) → skip subagents; do a concise main-session review.
   - If none of the above applies → use no subagent; review the diff yourself in the main session.
   - Do not invoke a reviewer unrelated to what actually changed.
3. When delegating, give each reviewer the exact changed-file list and relevant diff content directly in its prompt — it cannot fetch this itself.
4. Collect findings and classify each as:
   - **Blocking** — correctness, data loss, security, or contract-breaking.
   - **Non-blocking** — worth fixing but not shipping-critical.
   - **Informational** — style/observation only.
5. Call out any changed or added test that could pass even if the real behavior were broken (e.g. asserts on a mock instead of real output, missing negative case, no assertion on the error path).
6. End with an explicit verdict: **Safe to ship** or **Unsafe to ship**, with the blocking findings that drove it.

## Constraints

- Read-only: no edits, no staging, no running formatters/generators.
- Scope to the diff — do not flag pre-existing issues in unchanged code.
