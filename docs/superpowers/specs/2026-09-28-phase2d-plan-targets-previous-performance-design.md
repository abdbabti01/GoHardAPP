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
`ProgramWorkout.exercisesJson` entry fields relevant to this contract:

| field | type | meaning |
|---|---|---|
| `name` | string | display name (unchanged) |
| `exerciseTemplateId` | int, optional | **explicit part of this contract**: the resolved *system* template id (§4): integer when resolved; null or omitted means unresolved. |
| `sets` | int, optional | target sets |
| `reps` | int, optional | target reps — lower bound, or exact |
| `repsMax` | int, optional, **new** | target reps upper bound; omitted/null = exact |
| `occurrenceKey` | string | unchanged (per-workout occurrence identity) |

Existing entries without `exerciseTemplateId` / `repsMax` remain valid. Neither field is ever
derived from `name` or any display string at materialization time.

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
- `exerciseTemplateId` = JSON `exerciseTemplateId` if an integer number, else null (a non-integer
  kind no longer throws). Both materializers already copy this field today; this spec makes it
  contractual and adds the integer-kind guard on the API side.
- `sortOrder` = the entry's index in the JSON array (0-based), on both sides — see §3 ordinal
  rule. Today both materializers leave it 0.

### Reconciliation
The server's materialized exercise is authoritative. `_reconcileProgramWorkoutCreateExercises`
already replaces each paired local row with the server row via `ModelMapper.exerciseToLocal`;
that mapping must carry `exerciseTemplateId`, `targetSets`, `targetRepsMin`, `targetRepsMax` and
`sortOrder` (sortOrder is currently NOT mapped by ModelMapper in either direction — fixed here),
so after reconcile every one of these equals the server value. The same mapping serves the full
history download, so downloaded sessions carry the same fields.

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

Session ordering (deterministic): `completedAt ?? date` desc, then `date` desc, then `localId`
desc.

Strict ordinal pairing (handles an exercise appearing more than once in a workout):
1. Order exercises within a session by (`sortOrder`, `localId`). Ordinal `k` (1-based) of the
   current exercise = its position among ALL exercises in the current session with the same
   `exerciseTemplateId`.
2. Walk candidate sessions in session order. In each, order ALL same-template exercises the same
   way (qualifying or not — an unlogged occurrence #1 must not shift a logged #2 into slot #1)
   and take position `k`.
3. If position `k` exists AND qualifies (≥ 1 logged set), return it. Otherwise this session
   yields nothing for `k`; **continue to the next older session**. Never fall back to a
   different ordinal.
4. Exhausting all candidates ⇒ null.

Example: current session has Bench #1 and Bench #2. Last session had only one Bench; the session
before had two. Bench #1 ⇒ last session's Bench. Bench #2 ⇒ the older session's Bench #2. If no
session ever had a qualifying Bench #2 ⇒ null for #2.

Ordinal ordering depends on `sortOrder`: a user drag-reorder changes ordinals for that session
(intended — ordinals follow the order the user performed/arranged).

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
  exposure, no ambiguity).
- Plan creation needs the network anyway (AI), so resolution has no offline implication.

### Propagation (explicit contract)
```
AI exercise name
 → ExerciseTemplateResolver.Resolve                     (API, at draft creation)
 → ProgramWorkout.exercisesJson[i].exerciseTemplateId    (BuildProgramWorkouts writes it: integer when resolved; null or omitted means unresolved)
 → materialized Exercise.ExerciseTemplateId             (API materializer §2)
 → LocalExercise.exerciseTemplateId                     (APP local materializer from cached JSON,
                                                         then overwritten by server value on reconcile)
 → previous-performance identity (§3)
```
Programs created before this change keep no template ids in their JSON (no backfill; disposable
data). Their sessions therefore get no previous performance — identical to today.

`exerciseTemplateId` in plan JSON is only written by the server-side AI writer. Plan JSON can
also arrive via `PUT programs/workouts/{id}`; the materializer copies whatever integer is there.
A non-existent id fails the session insert on the FK (pre-existing behavior, not widened here);
validating visibility of client-supplied ids is out of scope and listed as a risk (§8).

## 5. Minimal UI proof

Log Sets screen: one line "Target 3 × 8–10" (when present) and one line "Last time" listing the
previous sets, weight rendered through the existing `UnitConverter` + unit preference.

## 6. Out of scope (see also §8)

Active Workout redesign, progression, target weight, backfill of old sessions, the dead
`create-sessions` endpoint, duplicate-seed cleanup, cross-week occurrence identity,
AI progress prompt unit assumptions, Phase 2C reset, Railway.

## 7. Tests

API: materializer targets (exact, range, invalid kinds, two occurrences independent, plan edit
after materialization), `sortOrder` = JSON index, non-integer `exerciseTemplateId` ⇒ null,
keyed + legacy create paths, AI writer emits `repsMax` + resolved `exerciseTemplateId`,
resolver (known, alias, duplicate→lowest id, unresolved, custom ignored, no substring match e.g.
"DB Bench Press" ≠ Bench Press), migration up/down SQL.

APP: local materialization targets + `exerciseTemplateId` + `sortOrder` (same cases), reconcile
adopts server targets/template id/sortOrder, Isar round-trip (restart), ModelMapper both
directions, previous-performance query (all §3 rules, metric/imperial invariance, offline),
log-sets target/last-time rendering.

Strict ordinal cases:
- current occurrence #2, previous session has only occurrence #1 ⇒ skip it;
- an older session has occurrence #2 ⇒ returned;
- no historical occurrence #2 ⇒ null (occurrence #1 still resolves normally);
- prior session with unlogged #1 and logged #2 ⇒ current #1 skips that session, current #2
  gets its #2.

End-to-end identity (two halves joined by one shared contract fixture, because the API and APP
run in different test processes):
- API half: AI extraction payload with "Bench Press" → `CreateDraftProgramFromWorkoutData` →
  stored `exercisesJson[i].exerciseTemplateId` == system Bench Press id → keyed
  `POST sessions/from-program-workout` → response exercise `exerciseTemplateId` == same id.
  The resulting program-workout JSON and session response are asserted against a checked-in
  fixture (`test/fixtures/phase2d_plan_session_contract.json` in APP, mirrored in API tests).
- APP half: that fixture's program workout → `createSessionFromProgramWorkout` (offline) →
  `LocalExercise.exerciseTemplateId` → reconcile with the fixture's server response → still the
  same id in Isar → complete a prior session with the same template → previous-performance query
  returns it.

## 8. Rollout dependency and risks

**Phase 2C dependency (blocking for production behavior, not for implementation).**
Deployed state: `LiftedWeight__RequireCanonicalClient=true`, `LiftedWeight__CanonicalHistory`
intentionally absent/false. With it false, the Phase 2C app design keeps every client's
lifted-weight migration `pending` indefinitely, which:
- withholds all workout uploads (sessions, exercises, sets) — locally created sessions,
  including Phase 2D program-workout sessions, stay `pending_create` and never reach the server;
  server-side materialization/reconcile (§2) therefore does not run in production;
- marks every server-backed row purge-eligible, so previous performance (§3) sees only sessions
  logged locally on the canonical build, on that device.

Phase 2D does NOT change Phase 2C, Railway configuration, or run the Phase 2C reset. Phase 2D is
implemented and tested independently (unit/integration tests exercise the `complete` migration
state as well as `pending`). Until the Phase 2C migration completes in production, it must not be
claimed that production workout sync or full cross-device previous performance is operational —
only local, on-device targets and previous performance are.

**Other risks.**
- Programs created before this change have no `exerciseTemplateId` / targets in their JSON and
  sessions created before it have no targets (no backfill; data disposable).
- Duplicate seed template names split history for five curl variants; the resolver picks the
  lowest id, while manual template picks may use the other id. Seed cleanup is out of scope.
- Client-supplied `exerciseTemplateId` in plan JSON (via `PUT programs/workouts/{id}`) is not
  validated for existence/visibility (pre-existing).
- `GET exercisetemplates` may list other users' custom templates (pre-existing, observed during
  forensics; not changed here).
- Ordinals follow `sortOrder`; exercises materialized before this change all have `sortOrder` 0
  and fall back to `localId` order.
