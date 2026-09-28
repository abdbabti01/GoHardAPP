# Phase 2D — Plan Targets + Previous Performance (design)

Status: approved decisions 2026-09-28 (rep ranges: yes; AI identity: system templates only;
duplicates: ordinal pairing; legacy history: excluded). Data/domain plumbing only — no Active
Workout redesign.

## 1. Forensic baseline (origin/main: API bb0a5bb, APP c04721c)

- Targets live only in `ProgramWorkout.ExercisesJson`. The only live writer is
  `ChatController.BuildProgramWorkouts` (AI drafts): `{name, sets, reps, weight:null, rest, notes,
  occurrenceKey}`. `reps` is always an integer (extraction prompt forces ints). No client code
  authors exercise JSON; every program in practice is AI-generated.
- Both materializers drop `sets`/`reps`:
  - API `ProgramWorkoutSessionMaterializer.Build` (used by legacy `SessionsController` and keyed
    `SessionCreateService`).
  - APP `SessionRepository.createSessionFromProgramWorkout` (local-first from cached JSON; the
    server re-materializes from its own JSON and `_reconcileProgramWorkoutCreateExercises`
    overwrites the local row with the server's by `occurrenceKey`).
  - `POST chat/conversations/{id}/create-sessions` has no UI caller — untouched.
- `occurrenceKey` is stable within a ProgramWorkout (normalized + CAS-persisted, copied verbatim)
  but NOT across weeks (each week's row mints fresh keys). Used here only for existing reconcile.
- AI program exercises never carry `exerciseTemplateId`. The legacy `FindBestMatchingTemplate`
  (substring aliases, prefix stripping, loads all users' customs) is unsafe and is NOT reused.
- Seed data contains duplicate system names (Hammer/Preacher/Concentration/Cable/Incline
  Dumbbell Curls) and `EZ Bar Curls` vs `EZ Bar Curl`.
- Full session history (exercises + sets) syncs into Isar; analytics treats history as
  `status == completed` sessions, all sets.
- While `LiftedWeight__CanonicalHistory` is false, every client's lifted-weight migration stays
  `pending`: every server-backed row is legacy/unit-ambiguous.
  `LiftedWeightContractMigration.wouldPurge` is the existing classifier.

## 2. Target contract — snapshot onto the session exercise

Source of truth at workout time: the materialized session exercise. The plan is read only at
materialization. Later plan edits never mutate an existing session. No display-string parsing.

### Plan JSON entry (additive, backward compatible)
`sets` (int), `reps` (int, lower bound or exact), **new optional `repsMax`** (int, upper bound;
omitted/null = exact). Existing entries without `repsMax` remain valid.

### Session exercise (API `Exercise`, APP `Exercise` + `LocalExercise`)
New nullable ints: `targetSets`, `targetRepsMin`, `targetRepsMax` (JSON camelCase, nullable,
omitted-if-null on the Dart side like existing fields).

### Materialization rule (identical in API and APP; one pure function per side)
- `targetSets` = JSON `sets` if an integer number ≥ 1, else null.
- `targetRepsMin` = JSON `reps` if an integer number ≥ 1, else null.
- `targetRepsMax` = JSON `repsMax` if integer ≥ `targetRepsMin`, else `targetRepsMin`
  (null when `targetRepsMin` is null). Exact prescription ⇒ min == max.
- Non-number JSON kinds (strings like `"8-10"`, floats) ⇒ null. Never parsed.
- `targetSets` is independent of reps ("3 × to failure" ⇒ sets 3, reps null).

Sessions materialized before this change keep null targets (no backfill; data is disposable).
No exercise update endpoint exists, so targets are immutable server-side after creation.

### AI writer
`ExerciseData` gains `RepsMax`. Extraction prompt: a range like 8–10 ⇒ `reps: 8, repsMax: 10`;
otherwise omit `repsMax`. `BuildProgramWorkouts` emits `repsMax` only when > `reps`.
Program workout screen shows `8–10` when `repsMax` present.

### Schema
EF migration `AddExerciseTargets` with guarded provider SQL (`ExerciseTargetsSql`, same pattern as
`ExerciseOccurrenceKeySql`): three nullable int columns on `Exercises`. Isar: three nullable
fields on `LocalExercise` (regenerated `.g.dart`; additive, no data migration).

## 3. Previous performance — local, deterministic, kg

`SessionRepository.getPreviousPerformance(currentExercise)` → `PreviousPerformance?`
(`performedAt`, `sets` in `setNumber` order, weights raw kg, unchanged). No API endpoint; the
same query serves online and offline. No unit conversion in the repository.

Candidate sessions:
1. `userId` == authenticated user (epoch token), `status == 'completed'`,
2. not the current session, `syncStatus != 'pending_delete'`,
3. canonical: `!migration.wouldPurge('sessions', localId, serverId)` (children of a canonical
   session are canonical — repositories refuse children under a purge-eligible parent).

Exercise identity: same non-null `exerciseTemplateId`. Null template id ⇒ `null` result
(explicit "no identity"), never name matching.

A candidate exercise qualifies only if it has ≥ 1 *logged* set: `reps != null` or
`duration > 0` or `weight > 0`. Set-level `isCompleted` is not required (matches analytics).

Ordering (deterministic): sessions by `completedAt ?? date` desc, then `date` desc, then
`localId` desc; the first session with ≥ 1 qualifying exercise wins.

Duplicate occurrences (ordinal pairing): the current exercise's rank `k` among same-template
exercises in its session, ordered by (`sortOrder`, `localId`); in the winning prior session the
qualifying same-template exercises are ordered the same way and index `min(k, n-1)` is returned.

Edge cases: no history ⇒ null; bodyweight ⇒ sets with null/0 weight returned as-is; incomplete
prior session (some sets unlogged) ⇒ only logged sets returned; purged/legacy history ⇒ excluded
(until CanonicalHistory is true, only sessions logged locally on the canonical build qualify).
Unit preference (Metric/Imperial) never affects the query or storage.

## 4. AI exercise identity

New pure API service `ExerciseTemplateResolver.Resolve(name, systemTemplates) → int?`, used by
`BuildProgramWorkouts` (templates loaded once per draft: `IsCustom == false` only).

- Normalize: lowercase, trim, `-`/`_` → space, collapse whitespace, strip one trailing `s` from
  the last word when it has ≥ 3 characters and does not end in `ss`. Applied identically to both sides.
- Match normalized AI name to normalized template name, else to a small curated **exact** alias
  map (whole-string equality only — e.g. `rdl`→Romanian Deadlift, `ohp`/`military press`→
  Overhead Press, `back squat`/`barbell squat`→Squat, `barbell bench press`/`flat bench press`→
  Bench Press, `barbell row`→Bent-Over Row, `pullup`→Pull-ups, `pushup`→Push-ups,
  `chinup`→Chin-ups).
- Multiple matches (seed duplicates) ⇒ lowest `Id`. No match ⇒ null; name kept; logged.
- No substring/prefix stripping/word overlap; custom templates never considered (no cross-user
  exposure, no ambiguity). Resolved id flows plan → session via the existing field.
- Plan creation needs the network anyway (AI), so resolution has no offline implication.

## 5. Minimal UI proof

Log Sets screen: one line "Target 3 × 8–10" (when present) and one line "Last time" listing the
previous sets, weight rendered through the existing `UnitConverter` + unit preference.

## 6. Out of scope

Active Workout redesign, progression, target weight, backfill of old sessions, the dead
`create-sessions` endpoint, duplicate-seed cleanup, cross-week occurrence identity,
AI progress prompt unit assumptions, Phase 2C reset, Railway.

## 7. Tests

API: materializer targets (exact, range, invalid kinds, two occurrences independent, plan edit
after materialization), keyed + legacy create paths, AI writer emits `repsMax` + resolved
template ids, resolver (known, alias, duplicate→lowest id, unresolved, custom ignored,
no substring match e.g. "DB Bench Press" ≠ Bench Press), migration up/down SQL.
APP: local materialization targets (same cases), reconcile preserves server targets, Isar
round-trip (restart), ModelMapper both directions, previous-performance query (all §3 rules,
metric/imperial invariance, offline), log-sets target/last-time rendering.
