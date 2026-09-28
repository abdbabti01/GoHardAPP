# Canonical kg Lifted Weight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every lifted-weight value GoHard persists after cutover mean kilograms, with Metric/Imperial affecting only input and display, and make the legacy→canonical transition safe (server guard, local purge, manual reset).

**Architecture:** One conversion boundary in the app (`UnitConverter`), fed by the existing `User.unitPreference` (now cached offline). Repositories/Isar/sync/API never convert. The app declares the contract with a request header; the API rejects undeclared set writes when enabled by config and exposes whether the production reset has been verified. A versioned, idempotent local purge removes legacy workout rows once the server reports canonical history. The production reset is a standalone, manually run SQL script.

**Tech Stack:** Flutter (Provider, Dio, Isar, flutter_secure_storage, mockito), ASP.NET Core 8 (EF Core, Npgsql/SQL Server, xUnit, Testcontainers), PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-09-27-canonical-kg-lifted-weight-design.md` (this repo). Read it before any task.

## Global Constraints

- Worktrees only: APP `C:\Users\babti\Documents\GitHub\GoHardAPP-canonical-kg`, API `C:\Users\babti\Documents\GitHub\GoHardAPI-canonical-kg`, both on branch `feat/canonical-kg-lifted-weight` (based on Phase 2A heads `101d6b1` / `5212da8`). Never touch `GoHardAPP`, `GoHardAPI` or any other checkout.
- 1 lb = **0.45359237 kg** exactly. The only place this constant appears in app code is `lib/core/utils/unit_converter.dart`.
- Header: `X-Lifted-Weight-Unit: kg`. Config section `LiftedWeight` with `RequireCanonicalClient` and `CanonicalHistory`, both default `false`.
- Guard error: HTTP 400, body `{ "code": "LIFTED_WEIGHT_UNIT_REQUIRED", "message": "Please update GoHard to keep logging workouts." }`.
- Contract endpoint: `GET api/v1/liftedweightcontract` → `{ "canonicalHistory": bool }` (authorized).
- Purge state key (secure storage): `lifted_weight_contract_v1`.
- No conversion in repositories, Isar models, `SyncService`, `ModelMapper`, API DTOs, controllers' persistence.
- No schema/migration changes, no Isar schema changes, no edit-set UI, no fix for the 37+ rep 1RM bug (B6) or body-metric goal bug (B7), no body-weight changes.
- Nothing may delete server data automatically. The reset script is never run against production.
- APP verification: `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test --concurrency=1`. Never commit `linux/ macos/ windows/` plugin-registrant line-ending churn (`git checkout -- linux macos windows` before staging). Never use `--no-verify`.
- API verification: `dotnet build GoHardAPI.sln`; `dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj -- xUnit.ParallelizeTestCollections=false xUnit.ParallelizeAssembly=false` (the parallel run is flaky on main because of Testcontainers).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task 1 (API): Config, compatibility guard, contract endpoint

**Files:**
- Create: `GoHardAPI/Configuration/LiftedWeightOptions.cs`
- Create: `GoHardAPI/Filters/RequireCanonicalLiftedWeightClientAttribute.cs` (create the folder)
- Create: `GoHardAPI/Controllers/LiftedWeightContractController.cs`
- Modify: `GoHardAPI/Program.cs` (register options next to other `Configure<>` calls / service registrations)
- Modify: `GoHardAPI/Controllers/ExerciseSetsController.cs` (attribute on `CreateExerciseSet` and the `PUT` action only)
- Modify: `GoHardAPI/appsettings.json` (add section with both flags `false`)
- Test: `GoHardAPI.Tests/Controllers/LiftedWeightGuardHttpTests.cs`

**Interfaces:**
- Produces: `LiftedWeightOptions { const string SectionName = "LiftedWeight"; const string HeaderName = "X-Lifted-Weight-Unit"; const string CanonicalUnit = "kg"; bool RequireCanonicalClient; bool CanonicalHistory; bool GuardEnabled => RequireCanonicalClient || CanonicalHistory; }` (namespace `GoHardAPI.Configuration`). Task 2 consumes `CanonicalHistory`.

- [ ] **Step 1: Write failing HTTP tests.** Read an existing HTTP test (`SessionCreateHttpBindingTests.cs` or `AccountControllerHttpTests`-style factory used in this repo) and reuse its `WebApplicationFactory`/auth setup. Configure flags per test with `builder.UseSetting("LiftedWeight:RequireCanonicalClient", "true")` (or in-memory config). Cover:

```csharp
// guard off (both false): POST exercisesets without header -> 201 (unchanged behaviour)
// RequireCanonicalClient=true: POST without header -> 400, body.code == "LIFTED_WEIGHT_UNIT_REQUIRED"
// RequireCanonicalClient=true: POST with "X-Lifted-Weight-Unit: lb" -> 400
// RequireCanonicalClient=true: POST with "X-Lifted-Weight-Unit: kg" -> 201 and stored Weight == sent Weight exactly (e.g. 61.23496995)
// CanonicalHistory=true alone also enables the guard (POST without header -> 400)
// RequireCanonicalClient=true: PUT exercisesets/{id} without header -> 400; with header -> 204, stored Weight == sent
// RequireCanonicalClient=true: PATCH exercisesets/{id}/complete without header -> still succeeds
// GET api/v1/liftedweightcontract -> { canonicalHistory: false } by default, true when configured; 401 unauthenticated
```

- [ ] **Step 2: Run** `dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj --filter "FullyQualifiedName~LiftedWeightGuardHttpTests"` → FAIL (types missing).

- [ ] **Step 3: Implement.**

```csharp
// GoHardAPI/Configuration/LiftedWeightOptions.cs
namespace GoHardAPI.Configuration
{
    /// <summary>Lifted-weight contract cutover (Phase 2C). Both flags default false.</summary>
    public class LiftedWeightOptions
    {
        public const string SectionName = "LiftedWeight";
        public const string HeaderName = "X-Lifted-Weight-Unit";
        public const string CanonicalUnit = "kg";

        /// <summary>Reject set writes from clients that do not declare canonical kg.</summary>
        public bool RequireCanonicalClient { get; set; }

        /// <summary>Set ONLY after the production workout-history reset was run and verified.</summary>
        public bool CanonicalHistory { get; set; }

        /// <summary>History cannot be canonical while legacy clients may still write.</summary>
        public bool GuardEnabled => RequireCanonicalClient || CanonicalHistory;
    }
}
```

```csharp
// GoHardAPI/Filters/RequireCanonicalLiftedWeightClientAttribute.cs
using GoHardAPI.Configuration;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;

namespace GoHardAPI.Filters
{
    /// <summary>
    /// Rejects lifted-weight writes from clients that do not send
    /// X-Lifted-Weight-Unit: kg while the guard is enabled. Old builds sent
    /// numbers typed under an "lbs" label; they must never be stored as kg.
    /// </summary>
    public sealed class RequireCanonicalLiftedWeightClientAttribute : ActionFilterAttribute
    {
        public override void OnActionExecuting(ActionExecutingContext context)
        {
            var options = context.HttpContext.RequestServices
                .GetRequiredService<IOptionsMonitor<LiftedWeightOptions>>().CurrentValue;
            if (!options.GuardEnabled) return;

            var declared = context.HttpContext.Request.Headers[LiftedWeightOptions.HeaderName].ToString();
            if (string.Equals(declared, LiftedWeightOptions.CanonicalUnit, StringComparison.OrdinalIgnoreCase)) return;

            context.Result = new BadRequestObjectResult(new
            {
                code = "LIFTED_WEIGHT_UNIT_REQUIRED",
                message = "Please update GoHard to keep logging workouts.",
            });
        }
    }
}
```

```csharp
// GoHardAPI/Controllers/LiftedWeightContractController.cs
using Asp.Versioning;
using GoHardAPI.Configuration;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace GoHardAPI.Controllers
{
    [ApiVersion("1.0")]
    [Route("api/v{version:apiVersion}/[controller]")]
    [ApiController]
    [Authorize]
    public class LiftedWeightContractController : ControllerBase
    {
        private readonly IOptionsMonitor<LiftedWeightOptions> _options;
        public LiftedWeightContractController(IOptionsMonitor<LiftedWeightOptions> options) => _options = options;

        /// <summary>Whether stored workout history is canonical kg (production reset verified).</summary>
        [HttpGet]
        public ActionResult<object> Get() => Ok(new { canonicalHistory = _options.CurrentValue.CanonicalHistory });
    }
}
```

Program.cs: `builder.Services.Configure<LiftedWeightOptions>(builder.Configuration.GetSection(LiftedWeightOptions.SectionName));`
ExerciseSetsController: add `[RequireCanonicalLiftedWeightClient]` to the `[HttpPost]` and `[HttpPut("{id}")]` actions only.
appsettings.json: `"LiftedWeight": { "RequireCanonicalClient": false, "CanonicalHistory": false }`.

- [ ] **Step 4: Run the filtered tests → PASS; run the full API suite serially → all pass.**
- [ ] **Step 5: Commit** `feat(api): lifted-weight kg contract guard and contract endpoint`.

---

### Task 2 (API): AI prompt gating and unitless AI weights

**Files:**
- Modify: `GoHardAPI/Controllers/ChatController.cs` (constructor, `AnalyzeProgress`, AI session-set creation near `Weight = exerciseData.Weight ?? 0`, program JSON builder `weight = e.Weight`)
- Modify: `GoHardAPI.Tests/Controllers/LiftedWeightUnitPresentationTests.cs`
- Test: add cases to the same file (and a focused test for AI-created sets/program JSON if an existing test harness covers `CreateSessionsFromPlan`/program creation; otherwise assert through the smallest public method that exercises the code)

**Interfaces:**
- Consumes: `LiftedWeightOptions.CanonicalHistory` (Task 1).
- Produces: `ChatController` gains an **optional last** constructor parameter `IOptionsMonitor<LiftedWeightOptions>? liftedWeight = null` (null ⇒ treated as `CanonicalHistory == false`) so existing test constructions keep compiling.

- [ ] **Step 1: Failing tests.**
  - `CanonicalHistory=false` (default/null options): existing Phase 2A assertions still hold (unit note present, no unit words outside it).
  - `CanonicalHistory=true`: prompt does NOT contain `ProgressAnalysisLoadUnitNote`; bench line reads `Max: 102.5 kg, Avg: 101.3 kg` (`{MaxWeight:F1}`/`{AvgWeight:F1}` with current culture); contains a sentence naming the user's preferred unit for recommendations (`pounds (lb)` for `UnitPreference = "Imperial"`, `kilograms (kg)` otherwise).
  - AI-created planned sets: `Weight == 0` even when the extracted plan JSON contains `"weight": 225`.
  - AI program workout `ExercisesJson`: `weight` is null even when the extracted plan contains a weight.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement.** In `AnalyzeProgress`:

```csharp
var canonical = _liftedWeight?.CurrentValue.CanonicalHistory == true;
if (canonical)
{
    var user = await _context.Users.AsNoTracking().FirstAsync(u => u.Id == userId);
    var preferred = string.Equals(user.UnitPreference, "Imperial", StringComparison.OrdinalIgnoreCase)
        ? "pounds (lb)" : "kilograms (kg)";
    progressSummary.AppendLine($"Load values are in kilograms (kg). The user prefers {preferred}; express load recommendations in that unit.");
}
else
{
    progressSummary.AppendLine(ProgressAnalysisLoadUnitNote);
}
progressSummary.AppendLine();
progressSummary.AppendLine("Top 10 Exercises by Volume:");
foreach (var stat in exerciseStats)
{
    progressSummary.AppendLine(canonical
        ? $"- {stat.Name}: {stat.TotalSets} sets, Max: {stat.MaxWeight:F1} kg, Avg: {stat.AvgWeight:F1} kg"
        : $"- {stat.Name}: {stat.TotalSets} sets, Max load: {stat.MaxWeight}, Avg load: {stat.AvgWeight:F1}");
}
```

AI sets: `Weight = 0, // LLM weights have no known unit; never persist them as kg`. Program JSON: `weight = (double?)null, // see above`.
- [ ] **Step 4: Filtered tests PASS; full serial suite PASS.**
- [ ] **Step 5: Commit** `feat(api): describe canonical kg to AI only after verified reset; drop unitless AI weights`.

---

### Task 3 (API): Production workout-history reset script (never run on prod)

**Files:**
- Create: `GoHardAPI/Scripts/Phase2C_WorkoutHistoryReset.sql`
- Create: `GoHardAPI/Scripts/Phase2C_WorkoutHistoryReset.md` (runbook)
- Test: `GoHardAPI.Tests/Scripts/Phase2CWorkoutHistoryResetPostgresTests.cs` (Testcontainers, like existing `*PostgresTests`)

**Interfaces:** none consumed/produced by code.

- [ ] **Step 1:** From `Migrations/TrainingContextModelSnapshot.cs` **and** Program.cs startup schema patching, list every FK referencing `Sessions`, `Exercises`, `ExerciseSets`, `ChatConversations`, `SharedWorkouts` with its delete behaviour; list every column of `Programs` / `ProgramWorkouts` that records progress (at least `ProgramWorkouts.IsCompleted, CompletedAt, IsSkipped, SkippedAt`; `Programs.CurrentWeek, CurrentDay, IsCompleted, CompletedAt, Status`). Put the table in the runbook.
- [ ] **Step 2: Failing test.** Container DB migrated with the real migrations (reuse the existing Postgres test helper). Seed two users with: sessions/exercises/sets, a program with completed+skipped workouts and advanced CurrentWeek/Day and `Status='completed'`, a `SessionCreateOperation` pointing at a session, a `progress_analysis` conversation with messages and a `workout_plan` conversation, a shared workout with a like/save/comment, a goal with GoalProgress, body metric, run session, nutrition row, exercise template. Execute the script file's `-- RESET` section (split on markers) and assert: sessions/exercises/sets = 0; progress_analysis convs+messages = 0; workout_plan conv kept; shared workouts & children = 0; SessionCreateOperations kept with `SessionId` NULL; programs/workouts kept with progress reset; goals, goal progress, body metrics, runs, nutrition, templates, users unchanged. Also assert the `-- PREVIEW` section returns counts and mutates nothing, and that the `-- VERIFY` section returns all-zero remaining counts after reset.
- [ ] **Step 3: Run → FAIL (script missing).**
- [ ] **Step 4: Write the script** with three marked sections: `-- PREVIEW` (read-only counts inside `BEGIN READ ONLY … ROLLBACK`), `-- RESET` (single `BEGIN; SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='120s'; … COMMIT;` deleting children before parents explicitly, even where cascades exist, then the program progress `UPDATE`s), `-- VERIFY` (counts that must be zero + preserved-table counts to compare against the preview). Quote identifiers (`"Sessions"`). The runbook covers: backup (`pg_dump` custom format of the whole DB; Railway backup/snapshot), preconditions (guard on: `LiftedWeight__RequireCanonicalClient=true` deployed and verified with a header-less POST returning 400), exact order, rollback (before COMMIT: `ROLLBACK`; after: restore from backup — the reset is not reversible in SQL), app/local-cache implications, and "then set `LiftedWeight__CanonicalHistory=true`".
- [ ] **Step 5: Tests PASS; full serial suite PASS.**
- [ ] **Step 6: Commit** `docs(api): Phase 2C workout-history reset script and runbook (manual, never automatic)`.

---

### Task 4 (APP): Central conversion boundary + offline unit preference

**Files:**
- Modify: `lib/core/utils/unit_converter.dart`
- Modify: `lib/data/services/auth_service.dart` (add `saveUnitPreference` / `getUnitPreference`, key `unit_preference`, same try/catch style as theme; do NOT add it to any logout clear-list)
- Modify: `lib/providers/profile_provider.dart` (cache on load/update/toggle; `String get unitPreference`)
- Test: `test/core/utils/unit_converter_lifted_test.dart`, `test/providers/profile_provider_unit_preference_test.dart`

**Interfaces:**
- Produces (static on `UnitConverter`):
  - `static const double kgPerLb = 0.45359237;`
  - `static bool isImperial(String? pref)` (uses `UnitPreference.fromString(pref) == UnitPreference.imperial`)
  - `static double liftedInputToKg(double input, String? pref)`
  - `static double liftedKgToDisplay(double kg, String? pref)` (also used for volume: linear)
  - `static String liftedUnitLabel(String? pref)` → `'lb'` | `'kg'`
  - `static String formatLifted(double kg, String? pref)` → display value rounded to 1 decimal, trailing `.0` dropped, plus unit, e.g. `'135 lb'`, `'61.2 kg'`
  - `ProfileProvider.unitPreference` → `'Imperial'` | `'Metric'` (`currentUser?.unitPreference ?? cached ?? 'Metric'`, normalised via `UnitPreference.fromString(...).serverValue`)

- [ ] **Step 1: Failing tests.**

```dart
test('Imperial input 135 lb -> 61.23496995 kg', () {
  expect(UnitConverter.liftedInputToKg(135, 'Imperial'), closeTo(61.23496995, 1e-9));
});
test('Metric input is already kg', () {
  expect(UnitConverter.liftedInputToKg(60, 'Metric'), 60);
});
test('61.23496995 kg displays as 135 lb for Imperial', () {
  expect(UnitConverter.liftedKgToDisplay(61.23496995, 'Imperial'), closeTo(135, 1e-9));
  expect(UnitConverter.formatLifted(61.23496995, 'Imperial'), '135 lb');
});
test('100 kg displays 100 kg / 220.5 lb', () {
  expect(UnitConverter.formatLifted(100, 'Metric'), '100 kg');
  expect(UnitConverter.formatLifted(100, 'Imperial'), '220.5 lb');
});
test('140 lb input stores ~63.5029 kg', () {
  expect(UnitConverter.liftedInputToKg(140, 'Imperial'), closeTo(63.5029318, 1e-6));
});
test('null/unknown preference behaves as Metric', () {
  expect(UnitConverter.liftedUnitLabel(null), 'kg');
  expect(UnitConverter.liftedInputToKg(60, 'bogus'), 60);
});
test('lb -> kg -> lb round trip is exact to 1e-9', () {
  for (final lb in [45.0, 135.0, 102.5, 0.0]) {
    final kg = UnitConverter.liftedInputToKg(lb, 'Imperial');
    expect(UnitConverter.liftedKgToDisplay(kg, 'Imperial'), closeTo(lb, 1e-9));
  }
});
```

ProfileProvider tests (use existing profile provider test setup/mocks; read `test/providers/` for the established pattern): offline cold start with cached `'Imperial'` and no user → `unitPreference == 'Imperial'`; after `loadUserProfile` returning a user with `'Metric'` the cache is written `'Metric'`; toggling the preference writes the cache; no user and no cache → `'Metric'`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** (keep existing body-weight helpers' behaviour unchanged; add new methods, do not repoint body-weight code).

```dart
  /// 1 lb in kg (exact, international definition). The ONLY lifted-weight
  /// conversion constant in the app.
  static const double kgPerLb = 0.45359237;

  static bool isImperial(String? pref) =>
      UnitPreference.fromString(pref) == UnitPreference.imperial;

  /// Input boundary: what the user typed -> canonical kg.
  static double liftedInputToKg(double input, String? pref) =>
      isImperial(pref) ? input * kgPerLb : input;

  /// Display boundary: canonical kg (or kg-volume) -> the user's unit.
  static double liftedKgToDisplay(double kg, String? pref) =>
      isImperial(pref) ? kg / kgPerLb : kg;

  static String liftedUnitLabel(String? pref) => isImperial(pref) ? 'lb' : 'kg';

  static String formatLifted(double kg, String? pref) {
    final v = liftedKgToDisplay(kg, pref);
    final rounded = (v * 10).round() / 10;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return '$text ${liftedUnitLabel(pref)}';
  }
```

- [ ] **Step 4: PASS; `flutter analyze` clean.**
- [ ] **Step 5: Commit** `feat(app): central lifted-weight conversion boundary and offline unit preference`.

---

### Task 5 (APP): Contract header + Log Sets canonical input/display

**Files:**
- Modify: `lib/core/constants/api_config.dart` (`static const String liftedWeightUnitHeader = 'X-Lifted-Weight-Unit';`, `static const String liftedWeightCanonicalUnit = 'kg';`, `static const String liftedWeightContract = 'liftedweightcontract';`)
- Modify: `lib/data/services/api_service.dart` (add the header to `BaseOptions.headers`)
- Modify: `lib/ui/screens/exercises/log_sets_screen.dart`
- Replace: `test/providers/log_sets_weight_semantics_test.dart` (Phase 2A pin — superseded)
- Test: `test/ui/screens/exercises/log_sets_canonical_test.dart`, `test/data/services/api_service_lifted_weight_header_test.dart`, `test/core/services/sync_service_lifted_weight_passthrough_test.dart`

**Interfaces:**
- Consumes: `UnitConverter.liftedInputToKg/formatLifted/liftedUnitLabel`, `ProfileProvider.unitPreference` (Task 4).
- Produces: `ApiConfig.liftedWeightContract`, header constants (Task 7 uses them).

- [ ] **Step 1: Failing tests.**
  - Log Sets widget (reuse the provider/mocks approach of the Phase 2A test; provide a `ProfileProvider` whose `unitPreference` is stubbed — if `ProfileProvider` is hard to fake, pass the preference via `context.select` from a minimal `ChangeNotifierProvider<ProfileProvider>` built with mocked collaborators as other tests do):
    - Imperial: field label `Weight (lb)`; entering `135` calls `repo.createExerciseSet` with `weight` `closeTo(61.23496995, 1e-9)`; the list renders a stored `61.23496995` as `5 reps × 135 lb`.
    - Metric: label `Weight (kg)`; `60` → `60`; list renders `5 reps × 60 kg`.
    - Same stored set renders `135 lb` under Imperial and `61.2 kg` under Metric; switching preference does not call any repository write.
  - ApiService: using `testHttpClientAdapter` (see `analytics_repository_session_ownership_test.dart` `_FakeHttpClientAdapter`), assert every request (plain and session-bound) carries `X-Lifted-Weight-Unit: kg`.
  - Sync pass-through: seed a `LocalExerciseSet` `pending_create` with `weight: 61.23496995` under a synced exercise, run the sets phase (use the existing sync test harness in `test/core/services/sync_service_*_test.dart`), capture the POST body: `weight == 61.23496995` exactly and the request has the header. Same for a `pending_update` PUT. Download mapping: `ModelMapper` API→local keeps `61.23496995`.
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement.** In `LogSetsScreen`:

```dart
final pref = context.select<ProfileProvider, String>((p) => p.unitPreference);
// label:
labelText: 'Weight (${UnitConverter.liftedUnitLabel(pref)})',
// submit (_handleAddSet): read pref with context.read<ProfileProvider>().unitPreference
final weightKg = UnitConverter.liftedInputToKg(weight, pref);
await context.read<LogSetsProvider>().addSet(exerciseId: widget.exerciseId, reps: reps, weight: weightKg);
// list tile:
'${set.reps} reps × ${set.weight == null ? '—' : UnitConverter.formatLifted(set.weight!, pref)}',
```

`LogSetsProvider`, `ExerciseRepository`, `SyncService`, `ModelMapper` stay unchanged. ApiService `BaseOptions.headers` gains `ApiConfig.liftedWeightUnitHeader: ApiConfig.liftedWeightCanonicalUnit`. Delete the superseded 2A test file (its "lbs label, no conversion" contract is intentionally replaced).
- [ ] **Step 4: PASS; full APP verification.**
- [ ] **Step 5: Commit** `feat(app): log sets in the user's unit, persist canonical kg, declare kg contract header`.

---

### Task 6 (APP): Analytics volume in the user's unit + calculation equivalence

**Files:**
- Modify: `lib/ui/widgets/charts/volume_chart.dart` (add `final String unitPreference;` constructor param defaulting to `'Metric'`; spots, y-axis and tooltip use display-unit values)
- Modify: `lib/ui/screens/analytics/analytics_screen.dart` (pass `context.select<ProfileProvider, String>((p) => p.unitPreference)`)
- Modify: `test/ui/widgets/charts/volume_chart_test.dart` (Phase 2A unitless assertions superseded)
- Test: `test/data/repositories/analytics_repository_canonical_equivalence_test.dart`

**Interfaces:** Consumes Task 4. `volumeTooltipText(ProgressDataPoint point, String unitPreference)`.

- [ ] **Step 1: Failing tests.**
  - Tooltip: kg-volume `10000` → Metric `'Mar 5\nVolume 10.0k kg'`, Imperial `'Mar 5\nVolume 22.0k lb'` (10000 / 0.45359237 = 22046.2…); UTC date keeps its calendar day; server label is never echoed.
  - Axis captions contain no unit other than the preference's; y-axis values for Imperial are the converted values.
  - Equivalence (use the Isar harness from `analytics_repository_session_ownership_test.dart`): user A logs 5 × `liftedInputToKg(135,'Imperial')`, user B logs 5 × `liftedInputToKg(61.23496995,'Metric')`; offline `getVolumeOverTime`, `getWorkoutStats().totalVolume` and `getPersonalRecords()` (weight and e1RM) are equal within `1e-6`, and all are in kg (volume `≈ 306.17484975`).
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement.** Convert each point with `UnitConverter.liftedKgToDisplay(point.value, unitPreference)` for spots and tooltip; tooltip suffix `UnitConverter.liftedUnitLabel(unitPreference)`. Do not touch repository formulas.
- [ ] **Step 4: PASS; full APP verification.**
- [ ] **Step 5: Commit** `feat(app): show analytics volume in the user's unit from canonical kg`.

---

### Task 7 (APP): Versioned legacy workout purge + sync gate

**Files:**
- Create: `lib/core/services/lifted_weight_contract_migration.dart`
- Modify: `lib/main.dart` (snapshot right after `await localDb.initialize();`, before any provider/runApp; pass the instance into `SyncService`)
- Modify: `lib/core/services/sync_service.dart` (optional constructor param `LiftedWeightContractMigration? liftedWeightMigration`; gate in `_runSyncPhases`)
- Test: `test/core/services/lifted_weight_contract_migration_test.dart`, `test/core/services/sync_service_lifted_weight_gate_test.dart`

**Interfaces:**
- Consumes: `ApiConfig.liftedWeightContract` (Task 5), Isar collections `localSessions`, `localExercises`, `localExerciseSets`, `localPrograms`, `localProgramWorkouts` (fields `localId`, `serverId`, `sessionLocalId`, `exerciseLocalId`, `programLocalId`).
- Produces:

```dart
class LiftedWeightContractMigration {
  LiftedWeightContractMigration({
    required Isar Function() database,
    required Future<String?> Function() readState,
    required Future<void> Function(String json) writeState,
  });
  static const storageKey = 'lifted_weight_contract_v1';
  /// Startup, offline-safe. Records cutoffs once; no-op if state exists.
  Future<void> snapshotIfNeeded();
  /// True once the purge has completed (terminal).
  Future<bool> isComplete();
  /// Call at sync-pass start. If pending: asks [fetchCanonicalHistory];
  /// purges and returns true only when it reports true. Never throws for a
  /// failed/negative check (returns false, stays pending).
  Future<bool> ensureMigrated(Future<bool> Function() fetchCanonicalHistory);
}
```

State JSON: `{"status":"pending","cutoffs":{"sessions":N,"exercises":N,"sets":N,"programs":N,"programWorkouts":N}}` → `{"status":"complete",...}`. Production wiring in `main.dart` uses `FlutterSecureStorage` read/write of `storageKey` (same storage options as `AuthService`).

- [ ] **Step 1: Failing tests** (real Isar in temp dir like other repository tests; in-memory state closures):
  1. `snapshotIfNeeded` records max localIds; a second call (and a call after `complete`) does not change state.
  2. Fresh install (empty DB) → cutoffs 0.
  3. `ensureMigrated` with fetch → false: returns false, nothing deleted, still pending.
  4. fetch throws → returns false, nothing deleted.
  5. fetch → true: deletes rows with `localId <= cutoff` in all five collections (including `pending_create/update/delete`), deletes rows with `serverId != null` regardless of localId, deletes exercises/sets/programWorkouts whose parent was deleted, **keeps** an unsynced session → exercise → set chain created after the snapshot (weight preserved exactly), sets `complete`, returns true.
  6. Interrupted: simulate crash after the Isar purge but before the state write (make `writeState` throw once) → next `ensureMigrated` re-purges idempotently (no error, same result) and completes.
  7. After `complete`, rows created later (legacy-looking, e.g. serverId set by a later download) are never purged again; `ensureMigrated` returns true without calling fetch.
  8. Gate: with a pending migration, a sync pass does NOT dispatch session/exercise/set/program/programWorkout requests but DOES run e.g. goals; after the fetch reports true the same pass purges and then runs all phases; when `liftedWeightMigration` is null, behaviour is unchanged (existing tests stay green).
- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement.** Purge in ONE `db.writeTxn`: collect session ids to delete (`localId <= c.sessions || serverId != null`), exercise ids (`localId <= c.exercises || serverId != null || sessionLocalId in deletedSessions`), set ids (`localId <= c.sets || serverId != null || exerciseLocalId in deletedExercises`), program ids (`localId <= c.programs || serverId != null`), programWorkout ids (`localId <= c.programWorkouts || serverId != null || programLocalId in deletedPrograms`); `deleteAll` each. Then `writeState(complete)`. In `SyncService._runSyncPhases`, before the Sessions phase:

```dart
final workoutsReady = _liftedWeightMigration == null ||
    await _liftedWeightMigration!.ensureMigrated(() async {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.liftedWeightContract,
        sessionContext: context,
      );
      return data?['canonicalHistory'] == true;
    });
```

and wrap the five workout phases in `if (workoutsReady) { … }` keeping every existing epoch check/test hook in order for the phases that do run. Document in the class doc comment: **owner decision — unsynced legacy workout history is intentionally discarded at the legacy → canonical-kg transition; this runs once (versioned key) and is not a generic startup clear.**
- [ ] **Step 4: PASS; full APP verification.**
- [ ] **Step 5: Commit** `feat(app): versioned one-time legacy workout purge gated on verified canonical server history`.

---

### Task 8: Rollout doc, final review, verification

- [ ] Add `docs/superpowers/specs/…` cross-links to the API runbook; write the rollout section of the runbook (spec §9) with the exact env var names `LiftedWeight__RequireCanonicalClient`, `LiftedWeight__CanonicalHistory`.
- [ ] Whole-branch code review (both repos) with a fresh reviewer; fix Critical/Important.
- [ ] Full APP and API verification (commands in Global Constraints); push both branches; no PR, no merge, no deploy.
