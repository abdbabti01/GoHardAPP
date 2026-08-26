---
name: flutter-sync
description: Handle Isar local storage, offline data, and synchronization logic in GoHardAPP. Use for repository sync code, pending-state handling, conflict resolution, or anything touching the sync service.
---

# Flutter Sync

Work in `lib/data/repositories/`, `lib/data/local/`, and `lib/core/services/sync_service.dart` requires extra care because it protects user data across offline/online transitions.

Apply the offline-first invariants in the root `CLAUDE.md` — do not weaken them for this change; this skill only adds workflow-specific steps.

## Before editing

- Read the current sync flow in `sync_service.dart` and the repository being touched (e.g. `session_repository.dart`) end to end before changing it.
- Identify whether a schema change needs an Isar migration/compatibility path for existing local data.

## While implementing

- Handle partial sync failures without marking the whole batch as synced.
- Add retry/backoff behavior consistent with the existing sync engine rather than introducing a new mechanism.
- Follow the root `CLAUDE.md` generated-code verification order if `@collection`/`@JsonSerializable` types changed.

## Tests

- Cover online, offline, retry, and conflict paths for the changed repository/service.
- Run tests serially to avoid shared Isar instance flakiness, per the root `CLAUDE.md` verification commands (`flutter test --concurrency=1`).

## Done when

- No unsynchronized data can be lost or duplicated by the change.
- Conflict and offline paths are tested and pass under the root `CLAUDE.md` verification commands.
