# Phase 2C — Canonical kg lifted weight (design)

Status: approved by owner 2026-09-27. Spans GoHardAPP + GoHardAPI.
Builds on Phase 2A (`fix/ambiguous-lifted-weight-units`: APP `101d6b1`, API `5212da8`).
Evidence base: `docs/phase2-weight-unit-forensic-audit.md` (workspace root).

## 1. Invariant

> After cutover, every persisted lifted-weight value (`ExerciseSets.Weight`,
> `LocalExerciseSet.weight`, every sync/API payload `weight` for a set) is
> **kilograms**.

- The user's `UnitPreference` (`Metric` | `Imperial`, existing field on `User`)
  controls **input and display only**.
- Conversion happens at exactly two boundaries in the app:
  **input → kg** when a set is submitted, **kg → user unit** when a value is
  rendered. Repositories, Isar, sync, API transport and the backend never convert.
- Constant: 1 lb = 0.45359237 kg (exact, international definition).
- Derived values (volume = Σ reps × kg, PR = max kg, e1RM = Brzycki on kg) are
  computed in kg. For display the **result** is converted: an Imperial user sees
  volume as `Σ reps × lb` (= kg-volume × 2.20462…), labelled with the unit.
- Existing history is **not** migrated; it is erased by a separate, manual
  production reset (§7). Owner decision: history is disposable.

## 2. Unit preference (app)

- Authoritative source stays `User.unitPreference` in `ProfileProvider`.
- Add an offline cache mirroring the theme preference
  (`AuthService.saveUnitPreference/getUnitPreference`, secure storage, survives
  logout like the theme). `ProfileProvider.unitPreference` resolves
  `currentUser?.unitPreference ?? cached ?? 'Metric'`.
- Toggling the preference changes presentation only; stored values never change.

## 3. Central conversion boundary (app)

`lib/core/utils/unit_converter.dart` (existing, weight helpers currently unused)
gains the only lifted-weight conversion API:

- `liftedInputToKg(double input, String pref)` (input boundary)
- `liftedKgToDisplay(double kg, String pref)` (display boundary)
- `liftedUnitLabel(String pref)` → `'kg'` | `'lb'`
- `formatLifted(double kg, String pref)` and `formatLiftedVolume(double kgVolume, String pref)`

Widgets never multiply/divide by a factor directly. Body-weight code is out of scope
and untouched.

## 4. Write paths

| Path | Change |
|---|---|
| Log Sets add set | Label `Weight (kg)` / `Weight (lb)` from preference; `liftedInputToKg` applied once at submit; provider/repository receive kg. |
| Repository / Isar / SyncService (create, update, complete, delete) | No conversion (tests assert byte-for-byte pass-through). |
| Edit set | **Out of scope.** No edit UI exists (`updateExerciseSet` has no UI caller). Follow-up. |
| API `POST/PUT exercisesets` | Guarded (§6); value persisted as received. |
| AI chat → sessions (`ChatController`) | Stop copying LLM `weight` (unknown unit); write `0` as today's default. |
| AI program JSON `weight` | Stop copying LLM `weight` (write `null`). |

## 5. Read paths (active surfaces)

| Surface | Presentation |
|---|---|
| Log Sets list | `5 reps × 135 lb` / `5 reps × 61.2 kg` |
| Analytics volume chart (tooltip + y-axis) | preference unit, result converted |
| API `ProgressDataPoint.Label` | stays unitless (Phase 2A); app formats from `value` |
| Workout history, Active Workout, Today/Train | show set counts only — no change |
| Celebration / achievements | never fed volume today — unchanged from 2A |
| Dead screens (analytics exercise detail, progress_line_chart, stale formatters) | untouched |

## 6. Compatibility guard + server contract state (API)

Config (`appsettings` / env, default **false**):

- `LiftedWeight:RequireCanonicalClient` — enforce the client marker.
- `LiftedWeight:CanonicalHistory` — "production reset executed and verified".

Effective guard = `RequireCanonicalClient || CanonicalHistory` (the AI flag can
never be on without the guard).

- New app sends `X-Lifted-Weight-Unit: kg` on **every** request (single
  `ApiService` interceptor; sync uses the same client).
- When the guard is effective, `POST exercisesets` and `PUT exercisesets/{id}`
  without that exact header → **400** `{ code: "LIFTED_WEIGHT_UNIT_REQUIRED",
  message: "Please update GoHard to keep logging workouts." }`. Old builds render
  this as "Bad request: Please update GoHard…". `PATCH …/complete` and `DELETE`
  carry no weight and stay allowed.
- `GET api/v1/liftedweightcontract` (authenticated) → `{ canonicalHistory: bool }`.
- AI analyze-progress: `CanonicalHistory == true` → loads described as kg
  (with the user's preferred unit for context); otherwise the Phase 2A
  "unit unknown" note, unchanged.

## 7. Local legacy purge (app) — versioned, idempotent, one transition only

Owner decision: **unsynced legacy workout history on devices is intentionally
discarded.** Without this, a pending legacy (lb-semantic) set would be uploaded by
the upgraded app *with* the kg header and silently accepted.

State (secure storage, key `lifted_weight_contract_v1`, JSON):
`{ status: "pending" | "complete", cutoffs: { sessions, exercises, sets, programs, programWorkouts } }`

1. **Snapshot (startup, before `runApp`, offline-safe).** If the key is absent,
   record the current max Isar `localId` of each collection and `status: pending`.
   Rows at or below a cutoff predate the canonical build.
2. **Gate.** While `pending`, `SyncService` skips the Sessions, Exercises, Sets,
   Programs and ProgramWorkouts upload phases (other phases run normally).
   Local logging keeps working — new rows are canonical kg and are preserved.
3. **Purge.** At the start of a sync pass, if `pending` and online, call
   `GET liftedweightcontract`. Only when `canonicalHistory == true`, in one Isar
   transaction delete, for sessions / exercises / sets / programs /
   programWorkouts:
   - every row with `localId <= cutoff` (legacy, including pending mutations), and
   - every row with a server identity (while gated, nothing canonical can have
     been uploaded from this device, so any server-backed row is legacy or will be
     re-downloaded from the reset server),
   - plus descendants of any deleted parent.
   Then write `status: complete` and run the normal pass.
4. **Idempotency.** Re-running a purge is harmless (same predicate, rows already
   gone). A crash between the Isar commit and the status write repeats the purge
   on next start. `complete` is terminal; the key is never cleared by logout.
   Fresh installs snapshot empty cutoffs and purge nothing but server-backed rows,
   of which there are none before the first download.

## 8. Production reset (separate manual operation, never automatic)

Script: `GoHardAPI/Scripts/Phase2C_WorkoutHistoryReset.sql` + runbook
`GoHardAPI/Scripts/Phase2C_WorkoutHistoryReset.md`. Preview mode, explicit
transaction, verification, rollback. Tested only on a disposable Postgres.

Erases: `Sessions` (cascade → `Exercises` → `ExerciseSets`),
`ChatConversations` of type `progress_analysis`
(+ `ChatMessages`), `SharedWorkouts` (+ likes / saves / comments).
Resets: `ProgramWorkouts` completion/skip markers, `Programs.CurrentWeek/CurrentDay`,
completed programs → active.
Preserves: `SessionCreateOperations` (FK → SET NULL, so each becomes a tombstone and
a legacy client's retried create returns 410 instead of recreating a session),
users, goals, `GoalProgressHistory`, programs + workouts + exercise JSON,
templates, nutrition, body metrics, run sessions, all other chats.

## 9. Rollout (documented, not executed)

1. Ship API build (both flags false) — behaviour identical to today; new
   endpoint returns `canonicalHistory: false`.
2. Ship the canonical app build through store review **ahead of cutover** (safe:
   it snapshots, logs locally in kg, and holds workout uploads until the server
   reports canonical history). For store builds use manual/managed release so
   it can go live immediately after step 3.
3. Maintenance window:
   a. `LiftedWeight__RequireCanonicalClient=true` → old builds can no longer
      write sets.
   b. Backup; run reset preview; run reset; run verification.
   c. `LiftedWeight__CanonicalHistory=true`.
   d. Release the app build.
4. Canonical clients purge + resume uploads on their next online sync.
   Legacy clients get the update-required message on set writes.

Guarantees: no legacy write after reset (guard precedes reset); AI never told
history is kg before verification (flag after verification); compatible users are
never locked out (local logging continues, uploads resume at cutover).

## 10. Known limitations (accepted)

- Between installing the canonical build and its purge, legacy local/downloaded
  rows are rendered as if they were kg. Minimised by releasing the app at
  cutover (step 3d).
- Edits made while gated to a server-backed row (e.g. a program, or a set added
  to an in-progress legacy session) are discarded by the purge together with the
  legacy row. Unsynced rows created after the snapshot under unaffected parents
  survive.
- Workouts logged while gated exist only on the device until cutover.
- Old builds keep their unsynced sets in a failing retry loop after the guard is
  on; that history is disposable by owner decision.
- Program `ExercisesJson.weight` already stored (seed/AI) is unitless; it is shown
  as before and not converted.

## 11. Testing

TDD. Imperial 135 lb → 61.23496995 kg; 61.23496995 kg → "135 lb"; Metric 60 → 60;
same stored kg in both preferences; preference flip leaves Isar unchanged;
equivalent lb/kg workouts give equal canonical volume/PR; repository + sync
payloads carry stored kg unchanged; header present on sync requests; guard
matrix; contract endpoint; AI prompt in both flag states; purge: snapshot,
gate, not-yet-canonical, canonical purge keeps post-cutoff unsynced rows,
repeated / interrupted startup; reset script on disposable DB.
