---
name: flutter-feature
description: Implement a normal Flutter feature in GoHardAPP end-to-end (UI, Provider, Repository, API/Isar) following existing patterns. Use when adding or changing app functionality that is not a pure UI, sync, or CI task.
---

# Flutter Feature

Implement the requested behavior while preserving the app's layering:

```
UI (Screen/Widget) -> Provider (ChangeNotifier) -> Repository -> API service / Isar
```

## Before editing

- Read the nearest `CLAUDE.md` and the existing provider/repository/model for the feature area.
- Find an existing feature with a similar shape (e.g. a sibling repository or provider) and match its structure, naming, and error handling instead of inventing a new pattern.
- Note whether the change touches the API contract, Isar schema, or generated code — if so, hand off to `flutter-sync` (data/offline logic) or check `../GoHardAPI/` for the authoritative DTO.

## While implementing

- Keep widgets free of direct Dio/API/Isar calls — go through the provider and repository.
- Model loading, empty, success, and error states explicitly in the provider.
- Reuse existing services (API client, secure storage, connectivity) rather than creating new ones.
- Do not introduce new abstractions, packages, or refactors beyond what the feature requires.

## Tests

- Add or update provider and repository tests for the new behavior (success, error, and offline paths where relevant).
- Run the narrowest relevant test file before the full suite.
- Follow the root `CLAUDE.md` generated-code verification order (regenerate before formatting/analyzing/testing) if models or mocked classes changed.

## Done when

- Behavior matches the request with no unrelated refactors.
- Tests cover the change and pass.
- The root `CLAUDE.md` verification commands are clean.
