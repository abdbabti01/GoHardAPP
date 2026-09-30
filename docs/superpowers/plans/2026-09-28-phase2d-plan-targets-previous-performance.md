# Phase 2D — Plan Targets + Previous Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Snapshot plan prescriptions (sets × reps / rep range) and a conservatively resolved exercise identity onto every materialized session exercise, and answer "what did I do last time?" deterministically from local canonical-kg history.

**Architecture:** The API AI writer resolves exercise names to system `ExerciseTemplate` ids and writes `exerciseTemplateId` + `repsMax` into `ProgramWorkout.ExercisesJson`. Both materializers (API `ProgramWorkoutSessionMaterializer`, APP `SessionRepository.createSessionFromProgramWorkout`) copy template id, targets and a positional `sortOrder` onto the session exercise; reconcile adopts the server row via `ModelMapper.exerciseToLocal`. Previous performance is a local Isar query in `ExerciseRepository` using strict same-template ordinal pairing over completed, canonical (`!wouldPurge`) sessions, returning raw kg.

**Tech Stack:** ASP.NET Core 8 / EF Core (SQL Server local, PostgreSQL prod, SQLite + InMemory tests), xUnit; Flutter / Isar / json_serializable / Mockito, flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-28-phase2d-plan-targets-previous-performance-design.md` (approved at bf7b20b). Executors read both.

## Global Constraints

- Worktrees: API `C:\Users\babti\Documents\GitHub\GoHardAPI-phase2d`, APP `C:\Users\babti\Documents\GitHub\GoHardAPP-phase2d`; both on branch `feat/phase2d-targets-prev-perf` from origin/main. Never touch other checkouts.
- Every persisted lifted weight is kg. No lb storage. Repository/domain return raw kg; conversion only via `UnitConverter` at the UI.
- No fuzzy exercise matching. Resolver: system templates only (`IsCustom == false`), exact normalized name or exact curated alias; duplicates → lowest `Id`; else `null`.
- Targets are snapshotted at materialization; never joined from the plan at workout time; never parsed from display strings (non-integer JSON kinds ⇒ `null`).
- `sortOrder` = 0-based JSON array index in both materializers.
- Strict ordinal pairing; missing/unlogged ordinal ⇒ continue to older sessions; never substitute another occurrence.
- Legacy/purge-eligible history (`LiftedWeightContractMigration.wouldPurge('sessions', …) == true`) is excluded.
- Out of scope (do not touch): `PUT programs/workouts/{id}` template-id validation, backfill of existing programs/sessions, duplicate seed cleanup, Phase 2C behavior, Railway / `CanonicalHistory`, Active Workout redesign, the dead `create-sessions` chat endpoint, the AI progress prompt. No merge, no deploy.
- Never describe production sync / cross-device previous performance as operational while `CanonicalHistory=false` (spec §8).
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- APP: before every commit run `dart format --output=none --set-exit-if-changed .`; after `flutter pub get` revert churn in `linux/ macos/ windows/` (`git checkout -- linux macos windows`).

## Clarifications this plan adopts (flag at review if you disagree)

1. **Query location:** spec §3 named `SessionRepository.getPreviousPerformance`. This plan places it in `ExerciseRepository.getExerciseGuidance(exerciseId)` because Log Sets already works from a public exercise id through `LogSetsProvider → ExerciseRepository`, which already has `_resolveOwnedExercise` and the migration gate; `SessionRepository` is 3,135 lines. Rules are unchanged.
2. **"Prior" when the current session is itself completed** (e.g. viewing history): candidates must sort strictly older than the current session under the same ordering. For a non-completed current session every completed candidate is prior.
3. **Rows excluded from ordinal counting:** exercises with `syncStatus` `pending_delete` or `conflict` (a `conflict` row is a local placeholder whose server twin was inserted separately on reconcile — counting both would double an occurrence). Sets with `syncStatus == 'pending_delete'` are not "logged".
4. **Dart `Exercise` JSON** keeps the class's existing `@JsonSerializable()` defaults (nulls serialized), rather than spec §2's "omitted-if-null" wording; the API ignores these fields on input.

## File map

API (`GoHardAPI-phase2d`):
- Create `GoHardAPI/Services/ExerciseTemplateResolver.cs` — pure name→system-template-id resolution.
- Modify `GoHardAPI/Models/Exercise.cs` — `TargetSets`, `TargetRepsMin`, `TargetRepsMax`.
- Create `GoHardAPI/Migrations/ExerciseTargetsSql.cs`, `GoHardAPI/Migrations/<ts>_AddExerciseTargets.cs` (+ generated `.Designer.cs`, updated `TrainingContextModelSnapshot.cs`).
- Modify `GoHardAPI/Services/ProgramWorkoutSessionMaterializer.cs` — targets, int-guarded template id, `SortOrder`.
- Modify `GoHardAPI/Controllers/ChatController.cs` — `ExerciseData.RepsMax`, both prompts, `CreateDraftProgramFromWorkoutData` loads system templates, `BuildProgramWorkouts` writes `exerciseTemplateId` + `repsMax`.
- Modify `GoHardAPI.Tests/GoHardAPI.Tests.csproj` — copy `Fixtures/**` to output.
- Tests: `GoHardAPI.Tests/Services/ExerciseTemplateResolverTests.cs`, `GoHardAPI.Tests/Controllers/ExerciseTargetsMigrationTests.cs`, `GoHardAPI.Tests/Controllers/ExerciseTargetsMigrationPostgresTests.cs`, `GoHardAPI.Tests/Services/ProgramWorkoutSessionMaterializerTargetsTests.cs`, `GoHardAPI.Tests/Controllers/SessionCreateFromProgramWorkoutHttpTests.cs` (add tests), `GoHardAPI.Tests/Controllers/Phase2DPlanSessionContractTests.cs`, `GoHardAPI.Tests/Fixtures/phase2d_plan_session_contract.json`.

APP (`GoHardAPP-phase2d`):
- Modify `lib/data/models/exercise.dart` (+ regen `exercise.g.dart`), `lib/data/local/models/local_exercise.dart` (+ regen `local_exercise.g.dart`), `lib/data/local/services/model_mapper.dart`.
- Create `lib/data/models/plan_exercise_prescription.dart` — plan entry → structured prescription.
- Modify `lib/data/repositories/session_repository.dart` — local materializer uses it + `sortOrder`.
- Create `lib/data/models/exercise_guidance.dart` — `PreviousPerformance`, `ExerciseGuidance`, `PreviousPerformanceRules`.
- Modify `lib/data/repositories/exercise_repository.dart` — `getExerciseGuidance`.
- Create `lib/core/utils/rep_target_format.dart` — `formatRepTarget`.
- Modify `lib/providers/log_sets_provider.dart`, `lib/ui/screens/exercises/log_sets_screen.dart`, `lib/ui/screens/programs/program_workout_screen.dart`.
- Regen mocks that mock `ExerciseRepository` / `LogSetsProvider` (build_runner).
- Tests: `test/data/models/plan_exercise_prescription_test.dart`, `test/data/local/services/model_mapper_test.dart` (add group), `test/data/local/services/model_mapper_isar_roundtrip_test.dart` (add test), `test/data/local/models/local_exercise_legacy_schema_upgrade_test.dart` (add expects), `test/data/repositories/program_workout_durable_create_test.dart` (add group), `test/data/repositories/exercise_repository_previous_performance_test.dart`, `test/core/utils/rep_target_format_test.dart`, `test/ui/screens/exercises/log_sets_guidance_test.dart`, `test/fixtures/phase2d_plan_session_contract.json`.

## Sequencing

API Tasks 1–4 first (the contract originates server-side), then **Checkpoint A**, then APP Tasks 5–9, then **Checkpoint B** and final verification. APP tasks depend only on the JSON field names fixed in Task 2/3/4, so APP work may start after Checkpoint A.

---

## API

### Task 1: ExerciseTemplateResolver

**Files:**
- Create: `GoHardAPI/Services/ExerciseTemplateResolver.cs`
- Test: `GoHardAPI.Tests/Services/ExerciseTemplateResolverTests.cs`

**Interfaces:**
- Produces: `public static class ExerciseTemplateResolver { public static string Normalize(string name); public static int? Resolve(string? name, IEnumerable<ExerciseTemplate> templates); }`

- [ ] **Step 1: Write the failing tests**

```csharp
using GoHardAPI.Models;
using GoHardAPI.Services;
using Xunit;

namespace GoHardAPI.Tests.Services
{
    public class ExerciseTemplateResolverTests
    {
        private static ExerciseTemplate T(int id, string name, bool custom = false, int? owner = null) =>
            new() { Id = id, Name = name, IsCustom = custom, CreatedByUserId = owner };

        private static readonly List<ExerciseTemplate> Catalog = new()
        {
            T(1, "Bench Press"),
            T(2, "Dumbbell Bench Press"),
            T(3, "Pull-ups"),
            T(4, "Romanian Deadlift"),
            T(5, "Overhead Press"),
            T(6, "Leg Curl"),
            T(7, "Hammer Curls"),
            T(8, "Hammer Curls"),          // seed duplicate
            T(9, "Squat"),
            T(10, "Rowing Machine"),
            T(50, "Bench Press", custom: true, owner: 1),
            T(51, "My Special Press", custom: true, owner: 1),
        };

        [Theory]
        [InlineData("Bench Press", 1)]
        [InlineData("  bench   PRESS ", 1)]
        [InlineData("Dumbbell Bench Press", 2)]
        [InlineData("Pull Ups", 3)]
        [InlineData("pull-up", 3)]
        [InlineData("Pullups", 3)]
        [InlineData("RDL", 4)]
        [InlineData("OHP", 5)]
        [InlineData("Military Press", 5)]
        [InlineData("Barbell Bench Press", 1)]
        [InlineData("Back Squat", 9)]
        [InlineData("Leg Curls", 6)]
        public void Resolves_ExactNormalizedNameOrExactAlias(string aiName, int expectedId) =>
            Assert.Equal(expectedId, ExerciseTemplateResolver.Resolve(aiName, Catalog));

        [Fact]
        public void DuplicateSystemNames_ResolveToLowestId() =>
            Assert.Equal(7, ExerciseTemplateResolver.Resolve("Hammer Curl", Catalog));

        [Theory]
        [InlineData("DB Bench Press")]   // legacy matcher mapped this to barbell Bench Press
        [InlineData("Incline Bench")]
        [InlineData("Row")]              // legacy matcher mapped this to Rowing Machine
        [InlineData("Curl")]
        [InlineData("Cable Row")]
        [InlineData("")]
        [InlineData("   ")]
        [InlineData(null)]
        public void UnresolvedOrAmbiguous_ReturnsNull_NeverSubstringMatch(string? aiName) =>
            Assert.Null(ExerciseTemplateResolver.Resolve(aiName, Catalog));

        [Fact]
        public void CustomTemplates_AreNeverConsidered()
        {
            Assert.Null(ExerciseTemplateResolver.Resolve("My Special Press", Catalog));
            Assert.Equal(1, ExerciseTemplateResolver.Resolve("Bench Press", Catalog)); // not custom 50
        }

        [Theory]
        [InlineData("Push-ups", "push up")]
        [InlineData("Lunges", "lunge")]
        [InlineData("Leg Press", "leg press")]   // "ss" ending kept
        [InlineData("Bent-Over_Row", "bent over row")]
        public void Normalize_IsDeterministic(string input, string expected) =>
            Assert.Equal(expected, ExerciseTemplateResolver.Normalize(input));
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj --filter "FullyQualifiedName~ExerciseTemplateResolverTests"`
Expected: build FAIL — `ExerciseTemplateResolver` does not exist.

- [ ] **Step 3: Implement**

```csharp
using System.Text.RegularExpressions;
using GoHardAPI.Models;

namespace GoHardAPI.Services
{
    /// <summary>
    /// Conservative AI exercise-name → system <see cref="ExerciseTemplate"/> resolution for plan
    /// creation (Phase 2D spec §4). Exact normalized-name equality or an exact curated alias
    /// only — never substring, prefix stripping or word overlap, because a wrong match silently
    /// attaches history to the wrong movement. Custom templates are never considered. Several
    /// system templates with the same normalized name (seed duplicates) resolve to the lowest
    /// Id. Anything else is null (unresolved identity).
    /// </summary>
    public static class ExerciseTemplateResolver
    {
        // Declared first: static initializers run in textual order and Aliases calls Normalize.
        private static readonly Regex Whitespace = new(@"\s+", RegexOptions.Compiled);

        // alias (any spelling) -> exact system template name; both sides are normalized at load.
        private static readonly (string Alias, string Template)[] RawAliases =
        {
            ("barbell bench press", "Bench Press"),
            ("flat bench press", "Bench Press"),
            ("barbell flat bench press", "Bench Press"),
            ("back squat", "Squat"),
            ("barbell squat", "Squat"),
            ("barbell back squat", "Squat"),
            ("conventional deadlift", "Deadlift"),
            ("barbell deadlift", "Deadlift"),
            ("rdl", "Romanian Deadlift"),
            ("ohp", "Overhead Press"),
            ("military press", "Overhead Press"),
            ("barbell overhead press", "Overhead Press"),
            ("standing overhead press", "Overhead Press"),
            ("barbell row", "Bent-Over Row"),
            ("barbell bent over row", "Bent-Over Row"),
            ("bent over barbell row", "Bent-Over Row"),
            ("pullup", "Pull-ups"),
            ("pushup", "Push-ups"),
            ("chinup", "Chin-ups"),
        };

        private static readonly Dictionary<string, string> Aliases =
            RawAliases.ToDictionary(a => Normalize(a.Alias), a => Normalize(a.Template), StringComparer.Ordinal);

        public static string Normalize(string name)
        {
            var s = Whitespace.Replace(name.ToLowerInvariant().Replace('-', ' ').Replace('_', ' '), " ").Trim();
            var lastSpace = s.LastIndexOf(' ');
            var last = s[(lastSpace + 1)..];
            if (last.Length >= 3 && last.EndsWith('s') && !last.EndsWith("ss"))
            {
                s = s[..^1];
            }
            return s;
        }

        public static int? Resolve(string? name, IEnumerable<ExerciseTemplate> templates)
        {
            if (string.IsNullOrWhiteSpace(name))
            {
                return null;
            }

            var target = Normalize(name);
            var system = templates.Where(t => !t.IsCustom).ToList();

            var direct = LowestId(system, target);
            if (direct is not null)
            {
                return direct;
            }

            return Aliases.TryGetValue(target, out var aliasTarget) ? LowestId(system, aliasTarget) : null;
        }

        private static int? LowestId(List<ExerciseTemplate> system, string normalizedName) =>
            system.Where(t => Normalize(t.Name) == normalizedName)
                .Select(t => (int?)t.Id)
                .Min();
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj --filter "FullyQualifiedName~ExerciseTemplateResolverTests"`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add GoHardAPI/Services/ExerciseTemplateResolver.cs GoHardAPI.Tests/Services/ExerciseTemplateResolverTests.cs
git commit -m "feat(api): conservative AI exercise -> system template resolver"
```

---

### Task 2: Exercise target columns + migration

**Files:**
- Modify: `GoHardAPI/Models/Exercise.cs` (after `OccurrenceKey`)
- Create: `GoHardAPI/Migrations/ExerciseTargetsSql.cs`
- Create (generated, then edited): `GoHardAPI/Migrations/<timestamp>_AddExerciseTargets.cs`, `.Designer.cs`; modified `TrainingContextModelSnapshot.cs`
- Test: `GoHardAPI.Tests/Controllers/ExerciseTargetsMigrationTests.cs`, `GoHardAPI.Tests/Controllers/ExerciseTargetsMigrationPostgresTests.cs`

**Interfaces:**
- Produces: `Exercise.TargetSets`, `Exercise.TargetRepsMin`, `Exercise.TargetRepsMax` (`int?`), serialized camelCase `targetSets`, `targetRepsMin`, `targetRepsMax`.

- [ ] **Step 1: Add model properties**

```csharp
        /// <summary>
        /// Prescription snapshotted from the source <c>ProgramWorkout.ExercisesJson</c> entry at
        /// materialization (Phase 2D). Never re-read from the plan afterwards; null = none.
        /// Exact reps: <see cref="TargetRepsMin"/> == <see cref="TargetRepsMax"/>.
        /// </summary>
        public int? TargetSets { get; set; }
        public int? TargetRepsMin { get; set; }
        public int? TargetRepsMax { get; set; }
```

- [ ] **Step 2: Generate migration scaffold**

Run (from repo root): `dotnet ef migrations add AddExerciseTargets --project GoHardAPI`
If `dotnet ef` is missing: `dotnet tool install --global dotnet-ef --version 8.*` then retry. Inspect: the generated `Up` must contain exactly three `AddColumn<int>` on `Exercises` and nothing else; `Down` three `DropColumn`. If anything else appears, stop and report (model drift).

- [ ] **Step 3: Write provider SQL and replace the generated body**

`GoHardAPI/Migrations/ExerciseTargetsSql.cs`:

```csharp
namespace GoHardAPI.Migrations
{
    /// <summary>
    /// Provider-specific DDL for <see cref="AddExerciseTargets"/>, same pattern and rationale as
    /// <see cref="ExerciseOccurrenceKeySql"/>: guarded Up/Down on SQL Server and PostgreSQL,
    /// unguarded Up and no-op Down on SQLite. Three nullable int columns, no data migration.
    /// </summary>
    internal static class ExerciseTargetsSql
    {
        private static readonly string[] Columns = { "TargetSets", "TargetRepsMin", "TargetRepsMax" };

        internal static readonly string SqlServerUp = string.Concat(Columns.Select(c => $@"
IF COL_LENGTH(N'[Exercises]', N'{c}') IS NULL
    ALTER TABLE [Exercises] ADD [{c}] int NULL;
"));

        internal static readonly string SqlServerDown = string.Concat(Columns.Select(c => $@"
IF OBJECT_ID(N'[Exercises]', N'U') IS NOT NULL AND COL_LENGTH(N'[Exercises]', N'{c}') IS NOT NULL
    ALTER TABLE [Exercises] DROP COLUMN [{c}];
"));

        internal static readonly string NpgsqlUp = string.Concat(Columns.Select(c =>
            $"ALTER TABLE \"Exercises\" ADD COLUMN IF NOT EXISTS \"{c}\" integer NULL;\n"));

        internal static readonly string NpgsqlDown = string.Concat(Columns.Select(c =>
            $"ALTER TABLE IF EXISTS \"Exercises\" DROP COLUMN IF EXISTS \"{c}\";\n"));

        internal static readonly string GenericUp = string.Concat(Columns.Select(c =>
            $"ALTER TABLE \"Exercises\" ADD COLUMN \"{c}\" INTEGER NULL;\n"));

        internal const string GenericDown = "";
    }
}
```

Replace the generated migration class body (keep the generated class name/attributes and the `.Designer.cs` untouched):

```csharp
    /// <summary>
    /// Adds nullable <c>Exercises.TargetSets/TargetRepsMin/TargetRepsMax</c> (Phase 2D target
    /// snapshot). Additive, guarded, no backfill — see <see cref="ExerciseTargetsSql"/>.
    /// </summary>
    public partial class AddExerciseTargets : Migration
    {
        private const string SqlServer = "Microsoft.EntityFrameworkCore.SqlServer";
        private const string Npgsql = "Npgsql.EntityFrameworkCore.PostgreSQL";

        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(migrationBuilder.ActiveProvider switch
            {
                SqlServer => ExerciseTargetsSql.SqlServerUp,
                Npgsql => ExerciseTargetsSql.NpgsqlUp,
                _ => ExerciseTargetsSql.GenericUp
            });
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            var sql = migrationBuilder.ActiveProvider switch
            {
                SqlServer => ExerciseTargetsSql.SqlServerDown,
                Npgsql => ExerciseTargetsSql.NpgsqlDown,
                _ => ExerciseTargetsSql.GenericDown
            };
            if (!string.IsNullOrEmpty(sql))
            {
                migrationBuilder.Sql(sql);
            }
        }
    }
```

- [ ] **Step 4: Write migration tests**

`GoHardAPI.Tests/Controllers/ExerciseTargetsMigrationTests.cs` — copy the harness of `ExerciseOccurrenceKeyMigrationTests` (same `NewDb`, `PrepareHistory`, `Exec`, `Scalar`, `ColumnExists` helpers, with `MineId` = the generated migration id, e.g. `"20260928XXXXXX_AddExerciseTargets"`, and `PrevId = "20260914013617_AddNutritionGoalEffectiveDate"`); `CreatePreUpgradeExercisesTable` is the occurrenceKey version plus `""OccurrenceKey"" TEXT`. Tests:

```csharp
        [Fact]
        public void Migrate_AddsThreeNullableTargetColumns_ExistingRowsSurviveWithNulls()
        {
            var (conn, ctx) = NewDb();
            using (conn) using (ctx)
            {
                PrepareHistory(conn, ctx);
                CreatePreUpgradeExercisesTable(conn);
                Exec(conn, @"INSERT INTO ""Exercises"" (""SessionId"",""Name"",""OccurrenceKey"") VALUES (1,'Keep','k-1');");

                Assert.Equal(new[] { MineId }, ctx.Database.GetPendingMigrations().ToArray());
                ctx.Database.Migrate();

                foreach (var c in new[] { "TargetSets", "TargetRepsMin", "TargetRepsMax" })
                {
                    Assert.True(ColumnExists(conn, "Exercises", c));
                    Assert.Equal(0, Scalar(conn, $"SELECT COUNT(*) FROM \"Exercises\" WHERE \"{c}\" IS NOT NULL;"));
                }
                Assert.Equal(1, Scalar(conn, "SELECT COUNT(*) FROM \"Exercises\" WHERE \"Name\"='Keep' AND \"OccurrenceKey\"='k-1';"));
            }
        }

        [Fact]
        public void Migrate_RunTwice_SecondRunIsANoOp()
        {
            var (conn, ctx) = NewDb();
            using (conn) using (ctx)
            {
                PrepareHistory(conn, ctx);
                CreatePreUpgradeExercisesTable(conn);
                ctx.Database.Migrate();
                ctx.Database.Migrate();
                Assert.Empty(ctx.Database.GetPendingMigrations());
                Assert.Single(ctx.Database.GetAppliedMigrations().Where(m => m == MineId));
            }
        }

        [Fact]
        public void ProviderSql_IsGuarded_OnSqlServerAndPostgres()
        {
            Assert.Equal(3, Regex.Matches(ExerciseTargetsSql.SqlServerUp, "IF COL_LENGTH").Count);
            Assert.Equal(3, Regex.Matches(ExerciseTargetsSql.NpgsqlUp, "ADD COLUMN IF NOT EXISTS").Count);
            Assert.Equal(3, Regex.Matches(ExerciseTargetsSql.NpgsqlDown, "DROP COLUMN IF EXISTS").Count);
            Assert.Equal(3, Regex.Matches(ExerciseTargetsSql.SqlServerDown, "IS NOT NULL").Count);
        }
```

`GoHardAPI.Tests/Controllers/ExerciseTargetsMigrationPostgresTests.cs` — joins the existing collection (its fixture migrates the full database):

```csharp
using GoHardAPI.Migrations;
using GoHardAPI.Tests.Infrastructure;
using Npgsql;
using Xunit;

namespace GoHardAPI.Tests.Controllers
{
    [Collection(ProgramWorkoutOccurrenceKeyPostgresCollection.Name)]
    [Trait("Category", "PostgresIntegration")]
    public sealed class ExerciseTargetsMigrationPostgresTests
    {
        private readonly ProgramWorkoutOccurrenceKeyPostgresFixture _pg;
        public ExerciseTargetsMigrationPostgresTests(ProgramWorkoutOccurrenceKeyPostgresFixture pg) => _pg = pg;

        [DockerRequiredFact]
        public async Task Columns_ExistNullable_AndGuardedSqlIsReRunnable()
        {
            Assert.True(_pg.Available, "PostgreSQL container was not available.");
            await using var raw = new NpgsqlConnection(_pg.ConnectionString);
            await raw.OpenAsync();

            foreach (var c in new[] { "TargetSets", "TargetRepsMin", "TargetRepsMax" })
            {
                await using var check = raw.CreateCommand();
                check.CommandText = "SELECT is_nullable FROM information_schema.columns " +
                    $"WHERE table_name = 'Exercises' AND column_name = '{c}';";
                Assert.Equal("YES", (string?)await check.ExecuteScalarAsync());
            }

            await using (var again = raw.CreateCommand())
            {
                again.CommandText = ExerciseTargetsSql.NpgsqlUp; // guarded: no-op, no error
                await again.ExecuteNonQueryAsync();
            }
        }
    }
}
```

(Verify the fixture's namespace with `grep -rn "class ProgramWorkoutOccurrenceKeyPostgresFixture" GoHardAPI.Tests` and adjust the `using`.)

- [ ] **Step 5: Run**

Run: `dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj --filter "FullyQualifiedName~ExerciseTargetsMigration|FullyQualifiedName~ExerciseOccurrenceKeyMigrationTests"`
Expected: PASS (Postgres test PASS with Docker, otherwise reported skipped by `DockerRequiredFact`; record which).

- [ ] **Step 6: Commit**

```bash
git add GoHardAPI/Models/Exercise.cs GoHardAPI/Migrations/ GoHardAPI.Tests/Controllers/ExerciseTargetsMigration*.cs
git commit -m "feat(api): nullable exercise target columns (AddExerciseTargets)"
```

---

### Task 3: API materializer — targets, template id guard, sortOrder

**Files:**
- Modify: `GoHardAPI/Services/ProgramWorkoutSessionMaterializer.cs` (exercise loop)
- Test: `GoHardAPI.Tests/Services/ProgramWorkoutSessionMaterializerTargetsTests.cs`, `GoHardAPI.Tests/Controllers/SessionCreateFromProgramWorkoutHttpTests.cs` (add 2 tests)

**Interfaces:**
- Consumes: Task 2 properties.
- Produces: materialized `Exercise` with `SortOrder = index`, `ExerciseTemplateId`, `TargetSets`, `TargetRepsMin`, `TargetRepsMax` per spec §2.

- [ ] **Step 1: Write failing unit tests** (reuse the `WorkoutWith` helper shape from `ProgramWorkoutSessionMaterializerOccurrenceKeyTests`)

```csharp
using GoHardAPI.Models;
using GoHardAPI.Services;
using Xunit;

namespace GoHardAPI.Tests.Services
{
    public class ProgramWorkoutSessionMaterializerTargetsTests
    {
        private static ProgramWorkout WorkoutWith(string json) => new()
        {
            Id = 1, ProgramId = 1, WeekNumber = 1, DayNumber = 1,
            WorkoutName = "Day 1", WorkoutType = "Strength", ExercisesJson = json,
            Program = new GoHardAPI.Models.Program
            {
                Id = 1, UserId = 1, Title = "P",
                StartDate = new DateTime(2020, 1, 6, 0, 0, 0, DateTimeKind.Utc),
            },
        };

        private static List<Exercise> Build(string json) =>
            ProgramWorkoutSessionMaterializer.Build(1, WorkoutWith(json), 1).Exercises.ToList();

        [Fact]
        public void ExactPrescription_3x8_MinEqualsMax()
        {
            var e = Assert.Single(Build("""[{"name":"Bench","sets":3,"reps":8}]"""));
            Assert.Equal<(int?, int?, int?)>((3, 8, 8), (e.TargetSets, e.TargetRepsMin, e.TargetRepsMax));
        }

        [Fact]
        public void Range_3x8to10()
        {
            var e = Assert.Single(Build("""[{"name":"Bench","sets":3,"reps":8,"repsMax":10}]"""));
            Assert.Equal<(int?, int?, int?)>((3, 8, 10), (e.TargetSets, e.TargetRepsMin, e.TargetRepsMax));
        }

        [Theory]
        [InlineData("""{"name":"X","sets":"3","reps":"8-10"}""", null, null, null)]
        [InlineData("""{"name":"X","sets":3.5,"reps":8.0}""", null, null, null)]
        [InlineData("""{"name":"X","sets":0,"reps":-1}""", null, null, null)]
        [InlineData("""{"name":"X","sets":3,"reps":null}""", 3, null, null)]
        [InlineData("""{"name":"X","sets":3,"reps":10,"repsMax":8}""", 3, 10, 10)]
        [InlineData("""{"name":"X","reps":8,"repsMax":"10"}""", null, 8, 8)]
        [InlineData("""{"name":"X"}""", null, null, null)]
        public void InvalidOrPartialValues_NeverParsed(string entry, int? sets, int? min, int? max)
        {
            var e = Assert.Single(Build($"[{entry}]"));
            Assert.Equal<(int?, int?, int?)>((sets, min, max), (e.TargetSets, e.TargetRepsMin, e.TargetRepsMax));
        }

        [Fact]
        public void TwoOccurrencesOfSameExercise_KeepIndependentTargets_AndPositionalSortOrder()
        {
            var list = Build("""
            [
              {"name":"Bench","exerciseTemplateId":7,"sets":3,"reps":5,"occurrenceKey":"a"},
              {"name":"Row","sets":4,"reps":10,"occurrenceKey":"b"},
              {"name":"Bench","exerciseTemplateId":7,"sets":2,"reps":10,"repsMax":12,"occurrenceKey":"c"}
            ]
            """);
            Assert.Equal(new[] { 0, 1, 2 }, list.Select(e => e.SortOrder));
            var heavy = list.Single(e => e.OccurrenceKey == "a");
            var backoff = list.Single(e => e.OccurrenceKey == "c");
            Assert.Equal<(int?, int?, int?)>((3, 5, 5), (heavy.TargetSets, heavy.TargetRepsMin, heavy.TargetRepsMax));
            Assert.Equal<(int?, int?, int?)>((2, 10, 12), (backoff.TargetSets, backoff.TargetRepsMin, backoff.TargetRepsMax));
            Assert.Equal(7, heavy.ExerciseTemplateId);
        }

        [Theory]
        [InlineData("""{"name":"X","exerciseTemplateId":"7"}""")]
        [InlineData("""{"name":"X","exerciseTemplateId":7.5}""")]
        [InlineData("""{"name":"X","exerciseTemplateId":null}""")]
        public void NonIntegerTemplateId_IsNull_NeverThrows(string entry) =>
            Assert.Null(Assert.Single(Build($"[{entry}]")).ExerciseTemplateId);

        [Fact]
        public void PlanEditAfterMaterialization_DoesNotMutateTheBuiltSession()
        {
            var workout = WorkoutWith("""[{"name":"Bench","sets":3,"reps":8}]""");
            var session = ProgramWorkoutSessionMaterializer.Build(1, workout, 1);
            workout.ExercisesJson = """[{"name":"Bench","sets":5,"reps":3}]""";
            var e = Assert.Single(session.Exercises);
            Assert.Equal<(int?, int?, int?)>((3, 8, 8), (e.TargetSets, e.TargetRepsMin, e.TargetRepsMax));
        }
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (targets null / SortOrder 0 / `InvalidOperationException` on string template id)

Run: `dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj --filter "FullyQualifiedName~ProgramWorkoutSessionMaterializerTargetsTests"`

- [ ] **Step 3: Implement** — replace the `foreach (var exerciseData in exercisesData)` loop and its template-id block:

```csharp
            if (exercisesData != null)
            {
                for (var index = 0; index < exercisesData.Count; index++)
                {
                    var exerciseData = exercisesData[index];
                    var exercise = new Exercise
                    {
                        Name = exerciseData.ContainsKey("name")
                            ? exerciseData["name"].GetString() ?? "Exercise"
                            : "Exercise",
                        // Deterministic position (Phase 2D §2/§3): previous-performance ordinals
                        // are counted in this order.
                        SortOrder = index,
                        // Only a JSON integer is an identity; anything else is unresolved (null),
                        // never parsed or guessed.
                        ExerciseTemplateId = IntOrNull(exerciseData, "exerciseTemplateId"),
                    };

                    // Prescription snapshot (Phase 2D §2): JSON integers only, never parsed
                    // from strings. Exact reps store min == max.
                    var sets = IntOrNull(exerciseData, "sets");
                    var repsMin = IntOrNull(exerciseData, "reps");
                    var repsMax = IntOrNull(exerciseData, "repsMax");
                    exercise.TargetSets = sets >= 1 ? sets : null;
                    exercise.TargetRepsMin = repsMin >= 1 ? repsMin : null;
                    exercise.TargetRepsMax = exercise.TargetRepsMin is null
                        ? null
                        : repsMax >= exercise.TargetRepsMin ? repsMax : exercise.TargetRepsMin;

                    // ... existing notes / rest / occurrenceKey blocks unchanged ...

                    session.Exercises.Add(exercise);
                }
            }
```

and add the helper to the class:

```csharp
        private static int? IntOrNull(Dictionary<string, JsonElement> data, string key) =>
            data.TryGetValue(key, out var value)
                && value.ValueKind == JsonValueKind.Number
                && value.TryGetInt32(out var i)
                ? i
                : null;
```

- [ ] **Step 4: Add create-path tests** to `SessionCreateFromProgramWorkoutHttpTests` (InMemory harness already there):

```csharp
        private const string TargetJson = """
        [
          { "name": "Bench Press", "exerciseTemplateId": null, "sets": 3, "reps": 8, "repsMax": 10, "occurrenceKey": "k-1" },
          { "name": "Row", "sets": 4, "reps": 12, "occurrenceKey": "k-2" }
        ]
        """;

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task BothCreatePaths_SnapshotTargetsAndSortOrder(bool keyed)
        {
            var ctx = NewContext();
            await SeedUser(ctx, 1);
            var (p, w) = await SeedProgramWorkout(ctx, 1, TargetJson);

            var result = await Controller(ctx).CreateSessionFromProgramWorkout(
                Dto(p, w, keyed ? Guid.NewGuid() : null), CancellationToken.None);

            var exercises = SessionOf(result).Exercises.OrderBy(e => e.SortOrder).ToList();
            Assert.Equal(new[] { 0, 1 }, exercises.Select(e => e.SortOrder));
            Assert.Equal<(int?, int?, int?)>((3, 8, 10), (exercises[0].TargetSets, exercises[0].TargetRepsMin, exercises[0].TargetRepsMax));
            Assert.Equal<(int?, int?, int?)>((4, 12, 12), (exercises[1].TargetSets, exercises[1].TargetRepsMin, exercises[1].TargetRepsMax));
        }

        [Fact]
        public async Task PlanEditedAfterCreate_ExistingSessionTargetsUnchanged()
        {
            var ctx = NewContext();
            await SeedUser(ctx, 1);
            var (p, w) = await SeedProgramWorkout(ctx, 1, TargetJson);
            var created = SessionOf(await Controller(ctx).CreateSessionFromProgramWorkout(Dto(p, w, Guid.NewGuid()), CancellationToken.None));

            var workout = await ctx.ProgramWorkouts.SingleAsync(x => x.Id == w);
            workout.ExercisesJson = """[{"name":"Bench Press","sets":5,"reps":3,"occurrenceKey":"k-1"}]""";
            await ctx.SaveChangesAsync();

            var stored = await ctx.Exercises.Where(e => e.SessionId == created.Id).OrderBy(e => e.SortOrder).ToListAsync();
            Assert.Equal<(int?, int?, int?)>((3, 8, 10), (stored[0].TargetSets, stored[0].TargetRepsMin, stored[0].TargetRepsMax));
        }
```

- [ ] **Step 5: Run**

Run: `dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj --filter "FullyQualifiedName~ProgramWorkoutSessionMaterializer|FullyQualifiedName~SessionCreateFromProgramWorkout"`
Expected: PASS, including pre-existing occurrenceKey/keyed tests (Postgres-only tests skip without Docker).

- [ ] **Step 6: Commit**

```bash
git add GoHardAPI/Services/ProgramWorkoutSessionMaterializer.cs GoHardAPI.Tests/Services/ProgramWorkoutSessionMaterializerTargetsTests.cs GoHardAPI.Tests/Controllers/SessionCreateFromProgramWorkoutHttpTests.cs
git commit -m "feat(api): materialize plan targets, guarded template id and positional sortOrder"
```

---

### Task 4: AI writer — resolved template id + repsMax in plan JSON (API E2E half)

**Files:**
- Modify: `GoHardAPI/Controllers/ChatController.cs` — `ExerciseData` (≈L3400), generation prompt (≈L405-436), extraction prompt (≈L1410-1435), `BuildProgramWorkouts` (L1279), `CreateDraftProgramFromWorkoutData` (L1615)
- Modify: `GoHardAPI.Tests/GoHardAPI.Tests.csproj`
- Create: `GoHardAPI.Tests/Fixtures/phase2d_plan_session_contract.json`, `GoHardAPI.Tests/Controllers/Phase2DPlanSessionContractTests.cs`

**Interfaces:**
- Consumes: `ExerciseTemplateResolver.Resolve` (Task 1), materializer (Task 3).
- Produces: plan JSON entries `{name, exerciseTemplateId, sets, reps, repsMax, weight, rest, notes, occurrenceKey}`; the contract fixture used by APP Task 8.

- [ ] **Step 1: Create the shared fixture** (identical file is copied to APP in Task 8)

`GoHardAPI.Tests/Fixtures/phase2d_plan_session_contract.json`:

```json
{
  "aiExerciseName": "Bench Press",
  "systemTemplateId": 1,
  "programWorkoutExercise": {
    "name": "Bench Press",
    "exerciseTemplateId": 1,
    "sets": 3,
    "reps": 8,
    "repsMax": 10
  },
  "sessionExercise": {
    "name": "Bench Press",
    "sortOrder": 0,
    "exerciseTemplateId": 1,
    "targetSets": 3,
    "targetRepsMin": 8,
    "targetRepsMax": 10
  }
}
```

Add to `GoHardAPI.Tests.csproj` inside an `<ItemGroup>`:

```xml
    <None Update="Fixtures\**\*.json" CopyToOutputDirectory="PreserveNewest" />
```

- [ ] **Step 2: Write the failing E2E test** (SQLite harness from `ChatWorkoutPlanProviderFallbackTests`)

```csharp
using System.Security.Claims;
using System.Text.Json;
using GoHardAPI.Controllers;
using GoHardAPI.Data;
using GoHardAPI.DTOs;
using GoHardAPI.Models;
using GoHardAPI.Services;
using GoHardAPI.Tests.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace GoHardAPI.Tests.Controllers
{
    /// <summary>
    /// Phase 2D API half of the end-to-end identity/target contract: AI exercise name →
    /// ExerciseTemplateResolver → ProgramWorkout.exercisesJson.exerciseTemplateId (+ targets) →
    /// materialized session exercise, asserted against the fixture the APP half consumes.
    /// </summary>
    public sealed class Phase2DPlanSessionContractTests : IDisposable
    {
        private const int UserId = 1;
        private readonly SqliteConnection _connection;
        private readonly TrainingContext _context;
        private readonly JsonElement _fixture;

        public Phase2DPlanSessionContractTests()
        {
            _connection = new SqliteConnection("DataSource=:memory:");
            _connection.Open();
            _context = new TrainingContext(new DbContextOptionsBuilder<TrainingContext>().UseSqlite(_connection).Options);
            _context.Database.EnsureCreated();
            _context.Users.Add(new User { Id = UserId, Name = "u", Username = "u", Email = "u@x.com", PasswordHash = "h" });
            _context.ExerciseTemplates.AddRange(
                new ExerciseTemplate { Id = 1, Name = "Bench Press" },
                new ExerciseTemplate { Id = 2, Name = "Bench Press", IsCustom = true, CreatedByUserId = UserId },
                new ExerciseTemplate { Id = 3, Name = "Dumbbell Bench Press" });
            _context.SaveChanges();
            _fixture = JsonDocument.Parse(File.ReadAllText(
                Path.Combine(AppContext.BaseDirectory, "Fixtures", "phase2d_plan_session_contract.json"))).RootElement;
        }

        public void Dispose()
        {
            _context.Dispose();
            _connection.Dispose();
        }

        private const string PlanReply =
            "Plan.\n\n```json\n" +
            "{\"programName\":\"P\",\"totalWeeks\":1,\"sessions\":[{\"name\":\"Day 1\",\"type\":\"strength\"," +
            "\"exercises\":[" +
            "{\"name\":\"Bench Press\",\"sets\":3,\"reps\":8,\"repsMax\":10,\"restTime\":90}," +
            "{\"name\":\"DB Bench Press\",\"sets\":3,\"reps\":12,\"restTime\":60}" +
            "]}]}\n```\n";

        [Fact]
        public async Task AiName_Resolves_IntoPlanJson_AndSurvivesIntoMaterializedSession()
        {
            var body = await GeneratePlan();
            var workout = await _context.ProgramWorkouts.AsNoTracking()
                .Where(w => w.ProgramId == body.DraftProgramId && !w.IsRestDay).OrderBy(w => w.Id).FirstAsync();

            var entries = JsonDocument.Parse(workout.ExercisesJson).RootElement;
            AssertSubset(_fixture.GetProperty("programWorkoutExercise"), entries[0]);
            Assert.Equal(JsonValueKind.Null, entries[1].GetProperty("exerciseTemplateId").ValueKind); // unresolved, not fuzzy
            Assert.False(entries[1].TryGetProperty("repsMax", out var rm) && rm.ValueKind != JsonValueKind.Null);
            var key = entries[0].GetProperty("occurrenceKey").GetString();
            Assert.False(string.IsNullOrWhiteSpace(key));

            var sessions = new SessionsController(_context, new SessionCreateService(_context, NullLogger<SessionCreateService>.Instance))
            {
                ControllerContext = new ControllerContext { HttpContext = AuthedContext() },
            };
            var result = await sessions.CreateSessionFromProgramWorkout(
                new CreateSessionFromProgramWorkoutDto { ProgramId = body.DraftProgramId!.Value, ProgramWorkoutId = workout.Id },
                CancellationToken.None);
            var session = result.Result switch
            {
                CreatedAtActionResult c => Assert.IsType<Session>(c.Value),
                OkObjectResult o => Assert.IsType<Session>(o.Value),
                _ => throw new Xunit.Sdk.XunitException($"unexpected {result.Result?.GetType().Name}"),
            };

            var first = session.Exercises.OrderBy(e => e.SortOrder).First();
            var wire = JsonSerializer.SerializeToElement(first, new JsonSerializerOptions(JsonSerializerDefaults.Web)
            {
                ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles,
            });
            AssertSubset(_fixture.GetProperty("sessionExercise"), wire);
            Assert.Equal(key, first.OccurrenceKey);
        }

        private async Task<ConversationDetailResponse> GeneratePlan()
        {
            var config = new ConfigurationBuilder()
                .AddInMemoryCollection(new Dictionary<string, string?> { ["AISettings:DefaultProvider"] = "Groq" })
                .Build();
            var ai = new AIService(new FakeProviderFactory(config, new[] { FakeProvider.Returning("Groq", PlanReply) }), config, NullLogger<AIService>.Instance);
            var chat = new ChatController(_context, ai, new CurrentMeasurementsService(_context), NullLogger<ChatController>.Instance)
            {
                ControllerContext = new ControllerContext { HttpContext = AuthedContext() },
            };
            var result = await chat.GenerateWorkoutPlan(new GenerateWorkoutPlanRequest
            {
                Goal = "Build muscle", ExperienceLevel = "beginner", DaysPerWeek = 1, Equipment = "full gym",
            });
            var body = Assert.IsType<ConversationDetailResponse>(Assert.IsType<OkObjectResult>(result.Result).Value);
            Assert.NotNull(body.DraftProgramId);
            return body;
        }

        private static DefaultHttpContext AuthedContext() => new()
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, UserId.ToString()) }, "TestAuth")),
        };

        private static void AssertSubset(JsonElement expected, JsonElement actual)
        {
            foreach (var p in expected.EnumerateObject())
            {
                Assert.True(actual.TryGetProperty(p.Name, out var v), $"missing '{p.Name}'");
                Assert.Equal(p.Value.GetRawText(), v.GetRawText());
            }
        }
    }
}
```

(`FakeProvider`/`FakeProviderFactory` live in `GoHardAPI.Tests/Services/FakeAIProviders.cs`; confirm the `Returning(name, reply)` signature there.)

- [ ] **Step 3: Run — expect FAIL** (`exerciseTemplateId` missing from plan JSON; `repsMax` dropped)

Run: `dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj --filter "FullyQualifiedName~Phase2DPlanSessionContractTests"`

- [ ] **Step 4: Implement**

`ExerciseData`: add `public int? RepsMax { get; set; }` after `Reps`.

Generation prompt JSON example: add `""repsMax"": 10,` after `""reps"": 8,` and add rule lines to its IMPORTANT list:

```
- For a rep range like 8-10, set reps to the lower bound (8) and repsMax to the upper bound (10); for an exact rep count omit repsMax
```

Extraction prompt: same `""repsMax"": 10,` example line and the same rule appended to IMPORTANT RULES.

`CreateDraftProgramFromWorkoutData`, before `BuildProgramWorkouts(...)`:

```csharp
                // Conservative identity (Phase 2D §4): system templates only, resolved once per draft.
                var systemTemplates = await _context.ExerciseTemplates
                    .AsNoTracking()
                    .Where(t => !t.IsCustom)
                    .ToListAsync();

                var workouts = BuildProgramWorkouts(
                    program.Id, proposedStartDate, totalWeeks, effectiveDaysPerWeek, workoutData.Sessions, systemTemplates);
```

`BuildProgramWorkouts`: add parameter `List<ExerciseTemplate> systemTemplates`, and replace the anonymous projection:

```csharp
                    var exercisesList = sessionData.Exercises!.Select(e =>
                    {
                        var templateId = ExerciseTemplateResolver.Resolve(e.Name, systemTemplates);
                        if (templateId is null)
                        {
                            _logger.LogInformation("AI plan exercise {ExerciseName} left unresolved (no exact system template)", e.Name);
                        }

                        return new
                        {
                            name = e.Name,
                            exerciseTemplateId = templateId,
                            sets = e.Sets,
                            reps = e.Reps,
                            repsMax = e.RepsMax is int max && e.Reps is int min && max > min ? max : (int?)null,
                            weight = (double?)null, // see above
                            rest = e.RestTime,
                            notes = e.Notes,
                        };
                    }).ToList();
```

- [ ] **Step 5: Run focused + chat suites**

Run: `dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj --filter "FullyQualifiedName~Phase2DPlanSessionContractTests|FullyQualifiedName~ChatWorkoutPlan|FullyQualifiedName~ProgramDraftActivation"`
Expected: PASS (Postgres-only activation tests skip without Docker; note count).

- [ ] **Step 6: Commit**

```bash
git add GoHardAPI/Controllers/ChatController.cs GoHardAPI.Tests/GoHardAPI.Tests.csproj GoHardAPI.Tests/Fixtures GoHardAPI.Tests/Controllers/Phase2DPlanSessionContractTests.cs
git commit -m "feat(api): AI plans carry resolved system template id and rep ranges"
```

### Checkpoint A — API review + verification

- [ ] Run full API verification from `GoHardAPI-phase2d`:

```bash
dotnet restore
dotnet build GoHardAPI.sln
dotnet test GoHardAPI.Tests/GoHardAPI.Tests.csproj
dotnet publish GoHardAPI/GoHardAPI.csproj -c Release -o ./publish-test
```

Expected: build 0 errors; tests pass (record passed/skipped counts; skipped = Docker-gated). Delete `./publish-test` afterwards; never commit it.
- [ ] `git diff origin/main --stat` — only files in the API file map. No secrets, no `publish-test`.
- [ ] Dispatch superpowers:requesting-code-review for commits Tasks 1–4. Resolve findings via superpowers:receiving-code-review before APP work.

---

## APP

Setup once: `cd GoHardAPP-phase2d && flutter pub get && git checkout -- linux macos windows`.

### Task 5: Model fields + ModelMapper (targets, sortOrder)

**Files:**
- Modify: `lib/data/models/exercise.dart`, `lib/data/local/models/local_exercise.dart`, `lib/data/local/services/model_mapper.dart` (`exerciseToLocal` L208, `localToExercise` L242)
- Regenerate: `lib/data/models/exercise.g.dart`, `lib/data/local/models/local_exercise.g.dart`
- Test: `test/data/local/services/model_mapper_test.dart`, `test/data/local/services/model_mapper_isar_roundtrip_test.dart`, `test/data/local/models/local_exercise_legacy_schema_upgrade_test.dart`

**Interfaces:**
- Produces: `Exercise.targetSets/targetRepsMin/targetRepsMax` (`int?`, JSON `targetSets`/`targetRepsMin`/`targetRepsMax`), same on `LocalExercise`; `ModelMapper` maps these plus `sortOrder` both ways.

- [ ] **Step 1: Failing tests**

`model_mapper_test.dart`, new group:

```dart
  group('ModelMapper - Phase 2D exercise targets/sortOrder', () {
    final api = Exercise.fromJson({
      'id': 9001,
      'sessionId': 900,
      'name': 'Bench Press',
      'sortOrder': 2,
      'exerciseTemplateId': 1,
      'occurrenceKey': 'k-1',
      'targetSets': 3,
      'targetRepsMin': 8,
      'targetRepsMax': 10,
      'exerciseSets': <dynamic>[],
      'version': 1,
    });

    test('fromJson reads the server target fields', () {
      expect(
        (api.targetSets, api.targetRepsMin, api.targetRepsMax, api.sortOrder),
        (3, 8, 10, 2),
      );
    });

    test('exerciseToLocal carries targets, template id and sortOrder', () {
      final local = ModelMapper.exerciseToLocal(api, sessionLocalId: 1);
      expect(
        (local.targetSets, local.targetRepsMin, local.targetRepsMax, local.sortOrder, local.exerciseTemplateId),
        (3, 8, 10, 2, 1),
      );
    });

    test('localToExercise carries them back', () {
      final back = ModelMapper.localToExercise(
        ModelMapper.exerciseToLocal(api, sessionLocalId: 1),
      );
      expect(
        (back.targetSets, back.targetRepsMin, back.targetRepsMax, back.sortOrder),
        (3, 8, 10, 2),
      );
    });

    test('legacy server JSON without target fields maps to nulls', () {
      final legacy = Exercise.fromJson({
        'id': 1, 'sessionId': 1, 'name': 'X', 'exerciseSets': <dynamic>[],
      });
      final local = ModelMapper.exerciseToLocal(legacy, sessionLocalId: 1);
      expect((local.targetSets, local.targetRepsMin, local.targetRepsMax), (null, null, null));
    });
  });
```

`local_exercise_legacy_schema_upgrade_test.dart`, after `expect(upgraded.occurrenceKey, isNull);`:

```dart
    // Phase 2D: additive nullable target fields read as null on legacy rows.
    expect(upgraded.targetSets, isNull);
    expect(upgraded.targetRepsMin, isNull);
    expect(upgraded.targetRepsMax, isNull);
```

`model_mapper_isar_roundtrip_test.dart`, new test (use that file's existing Isar setup variables):

```dart
  test('Phase 2D target fields and sortOrder survive an Isar close/reopen', () async {
    final row = LocalExercise(
      sessionLocalId: 1,
      name: 'Bench Press',
      sortOrder: 1,
      exerciseTemplateId: 1,
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 10,
      lastModifiedLocal: DateTime.utc(2026, 9, 28),
    );
    late int id;
    await isar.writeTxn(() async => id = await isar.localExercises.put(row));
    final dir = isar.directory!;
    final name = isar.name;
    await isar.close();
    isar = await Isar.open([LocalExerciseSchema], directory: dir, name: name, inspector: false);
    final read = await isar.localExercises.get(id);
    expect(
      (read!.targetSets, read.targetRepsMin, read.targetRepsMax, read.sortOrder),
      (3, 8, 10, 1),
    );
  });
```

(If the roundtrip file opens Isar with more schemas or a different variable name, match its existing `openIsar` helper.)

- [ ] **Step 2: Run — expect compile FAIL**

Run: `flutter test test/data/local/services/model_mapper_test.dart`

- [ ] **Step 3: Implement**

`exercise.dart`: add fields after `occurrenceKey`:

```dart
  /// Prescription snapshotted from the source plan entry when the session
  /// was materialized (Phase 2D). Never re-read from the plan; `null` = none.
  /// Exact reps: [targetRepsMin] == [targetRepsMax].
  final int? targetSets;
  final int? targetRepsMin;
  final int? targetRepsMax;
```

constructor `this.targetSets, this.targetRepsMin, this.targetRepsMax,`; `copyWith` params + `targetSets: targetSets ?? this.targetSets,` (×3).

`local_exercise.dart`: same three `int? …;` fields (after `occurrenceKey`, with the same doc comment) and constructor params.

`model_mapper.dart` `exerciseToLocal`: add
```dart
      sortOrder: apiExercise.sortOrder,
      targetSets: apiExercise.targetSets,
      targetRepsMin: apiExercise.targetRepsMin,
      targetRepsMax: apiExercise.targetRepsMax,
```
`localToExercise`: add
```dart
      sortOrder: localExercise.sortOrder,
      targetSets: localExercise.targetSets,
      targetRepsMin: localExercise.targetRepsMin,
      targetRepsMax: localExercise.targetRepsMax,
```

- [ ] **Step 4: Codegen + format**

```bash
dart run build_runner build --delete-conflicting-outputs
dart format .
git status --short
```
Expected changes limited to `exercise.g.dart`, `local_exercise.g.dart` and the hand-edited files (plus mocks only if their inputs changed — inspect and revert unrelated generator churn).

- [ ] **Step 5: Run**

Run: `flutter test test/data/local/services/model_mapper_test.dart test/data/local/services/model_mapper_isar_roundtrip_test.dart test/data/local/models/local_exercise_legacy_schema_upgrade_test.dart test/data/repositories/program_workout_durable_create_test.dart`
Expected: PASS (existing reconcile tests unaffected).

- [ ] **Step 6: Commit**

```bash
dart format --output=none --set-exit-if-changed .
git add lib/data/models/exercise.dart lib/data/models/exercise.g.dart lib/data/local/models/local_exercise.dart lib/data/local/models/local_exercise.g.dart lib/data/local/services/model_mapper.dart test/data/local
git commit -m "feat(app): exercise target fields and sortOrder mapped through ModelMapper"
```

---

### Task 6: Local materializer — prescription, template id, sortOrder; reconcile adopts server

**Files:**
- Create: `lib/data/models/plan_exercise_prescription.dart`
- Modify: `lib/data/repositories/session_repository.dart` (loop in `createSessionFromProgramWorkout`, ≈L1437-1490)
- Test: `test/data/models/plan_exercise_prescription_test.dart`, `test/data/repositories/program_workout_durable_create_test.dart` (new group)

**Interfaces:**
- Produces: `class PlanExercisePrescription { final int? exerciseTemplateId, targetSets, targetRepsMin, targetRepsMax; factory PlanExercisePrescription.fromPlanEntry(Map<String, dynamic> entry); }`

- [ ] **Step 1: Failing unit test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/plan_exercise_prescription.dart';

void main() {
  (int?, int?, int?, int?) p(Map<String, dynamic> e) {
    final r = PlanExercisePrescription.fromPlanEntry(e);
    return (r.exerciseTemplateId, r.targetSets, r.targetRepsMin, r.targetRepsMax);
  }

  test('exact 3 x 8', () => expect(p({'sets': 3, 'reps': 8}), (null, 3, 8, 8)));
  test('range 3 x 8-10 with template', () {
    expect(p({'exerciseTemplateId': 1, 'sets': 3, 'reps': 8, 'repsMax': 10}), (1, 3, 8, 10));
  });
  test('strings / doubles / non-positive are never parsed', () {
    expect(p({'exerciseTemplateId': '1', 'sets': '3', 'reps': '8-10'}), (null, null, null, null));
    expect(p({'sets': 3.0, 'reps': 8.5}), (null, null, null, null));
    expect(p({'sets': 0, 'reps': -1}), (null, null, null, null));
  });
  test('repsMax below min collapses to exact; repsMax without reps ignored', () {
    expect(p({'sets': 3, 'reps': 10, 'repsMax': 8}), (null, 3, 10, 10));
    expect(p({'sets': 3, 'repsMax': 10}), (null, 3, null, null));
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`flutter test test/data/models/plan_exercise_prescription_test.dart`)

- [ ] **Step 3: Implement** `lib/data/models/plan_exercise_prescription.dart`:

```dart
/// Structured prescription + identity read from one
/// `ProgramWorkout.exercisesJson` entry at session materialization
/// (Phase 2D spec §2). Mirrors `GoHardAPI.Services
/// .ProgramWorkoutSessionMaterializer` exactly: only JSON integers count;
/// strings and fractional numbers are never parsed.
class PlanExercisePrescription {
  final int? exerciseTemplateId;
  final int? targetSets;
  final int? targetRepsMin;
  final int? targetRepsMax;

  const PlanExercisePrescription({
    this.exerciseTemplateId,
    this.targetSets,
    this.targetRepsMin,
    this.targetRepsMax,
  });

  factory PlanExercisePrescription.fromPlanEntry(Map<String, dynamic> entry) {
    int? positive(Object? v) => v is int && v >= 1 ? v : null;
    final templateId = entry['exerciseTemplateId'];
    final repsMin = positive(entry['reps']);
    final repsMax = entry['repsMax'];
    return PlanExercisePrescription(
      exerciseTemplateId: templateId is int ? templateId : null,
      targetSets: positive(entry['sets']),
      targetRepsMin: repsMin,
      targetRepsMax:
          repsMin == null
              ? null
              : (repsMax is int && repsMax >= repsMin ? repsMax : repsMin),
    );
  }
}
```

- [ ] **Step 4: Use it in `createSessionFromProgramWorkout`** — replace `for (final exerciseData in exercisesData) {` with an indexed loop and the identity/target reads:

```dart
      for (var i = 0; i < exercisesData.length; i++) {
        final exerciseData = exercisesData[i];
        final exerciseName = exerciseData['name'] as String? ?? 'Exercise';
        // Same rules as the server materializer (Phase 2D §2): integer-only
        // identity/targets, positional sortOrder. The server row replaces
        // this one on reconcile, so both sides must agree.
        final prescription = PlanExercisePrescription.fromPlanEntry(
          exerciseData,
        );
        final exerciseTemplateId = prescription.exerciseTemplateId;
```

add to the `LocalExercise(...)` and `Exercise(...)` constructors in that loop:

```dart
          sortOrder: i,
          targetSets: prescription.targetSets,
          targetRepsMin: prescription.targetRepsMin,
          targetRepsMax: prescription.targetRepsMax,
```

and add `import '../models/plan_exercise_prescription.dart';`.

- [ ] **Step 5: Failing-then-passing repository tests** — new group at the end of `main()` in `program_workout_durable_create_test.dart`, using that file's `loginAs`, `workout`, `exerciseJson`, `sessionJson`, `jsonResponse`, `adapter`, `repository`, `isar`:

```dart
  group('Phase 2D targets / identity / sortOrder', () {
    const targetsJson =
        '[{"name":"Bench Press","exerciseTemplateId":1,"sets":3,"reps":8,"repsMax":10,"occurrenceKey":"b1"},'
        '{"name":"Row","sets":4,"reps":12,"occurrenceKey":"r1"},'
        '{"name":"Bench Press","exerciseTemplateId":1,"sets":2,"reps":5,"occurrenceKey":"b2"}]';

    Future<List<LocalExercise>> localRows(int sessionLocalId) async =>
        (await isar.localExercises.filter().sessionLocalIdEqualTo(sessionLocalId).findAll())
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    test('offline materialization snapshots targets, template id and positional sortOrder', () async {
      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);
      final created = await repository.createSessionFromProgramWorkout(
        10, workout(exercisesJson: targetsJson), DateTime(2031, 1, 1), 5);

      final rows = await localRows(created.id);
      expect(rows.map((e) => e.sortOrder), [0, 1, 2]);
      expect((rows[0].exerciseTemplateId, rows[0].targetSets, rows[0].targetRepsMin, rows[0].targetRepsMax), (1, 3, 8, 10));
      expect((rows[1].exerciseTemplateId, rows[1].targetSets, rows[1].targetRepsMin, rows[1].targetRepsMax), (null, 4, 12, 12));
      expect((rows[2].targetSets, rows[2].targetRepsMin, rows[2].targetRepsMax), (2, 5, 5));
      expect(adapter.captured, isEmpty);
    });

    test('targets survive app restart (Isar close/reopen)', () async {
      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);
      final created = await repository.createSessionFromProgramWorkout(
        10, workout(exercisesJson: targetsJson), DateTime(2031, 1, 1), 5);
      final dir = isar.directory!;
      await isar.close();
      isar = await openIsar(dir);
      localDb.setTestDatabase(isar);
      final rows = await localRows(created.id);
      expect((rows[0].targetSets, rows[0].targetRepsMin, rows[0].targetRepsMax), (3, 8, 10));
    });

    test('plan edited after materialization does not change the session', () async {
      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(false);
      final created = await repository.createSessionFromProgramWorkout(
        10, workout(exercisesJson: targetsJson), DateTime(2031, 1, 1), 5);
      // A later call with an edited plan returns the SAME existing active session.
      await repository.createSessionFromProgramWorkout(
        10,
        workout(exercisesJson: '[{"name":"Bench Press","sets":5,"reps":3,"occurrenceKey":"b1"}]'),
        DateTime(2031, 1, 1), 5);
      final rows = await localRows(created.id);
      expect((rows[0].targetSets, rows[0].targetRepsMin), (3, 8));
    });

    test('reconcile adopts the authoritative server template id, targets and sortOrder', () async {
      loginAs(userA);
      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;
      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      final created = await repository.createSessionFromProgramWorkout(
        10, workout(exercisesJson: targetsJson), DateTime(2031, 1, 1), 5);
      repository.onBackgroundSyncScheduledForTesting = null;

      Map<String, dynamic> server(int id, String key, int sort, int? tpl, int sets, int min, int max) => {
        ...exerciseJson(id, sessionId: 900, name: key, exerciseTemplateId: tpl, occurrenceKey: key),
        'sortOrder': sort, 'targetSets': sets, 'targetRepsMin': min, 'targetRepsMax': max,
      };
      held.complete(jsonResponse(sessionJson(id: 900, exercises: [
        server(9001, 'b1', 0, 1, 3, 8, 10),
        server(9002, 'r1', 1, 42, 4, 12, 12), // server resolved identity differently
        server(9003, 'b2', 2, 1, 2, 5, 5),
      ])));
      await settled;

      final rows = await localRows(created.id);
      expect(rows.map((e) => e.serverId), [9001, 9002, 9003]);
      expect(rows[1].exerciseTemplateId, 42);
      expect((rows[0].targetSets, rows[0].targetRepsMin, rows[0].targetRepsMax), (3, 8, 10));
    });
  });
```

(If `openIsar` or `isar` are not reassignable in that file's scope, make `isar` non-final — it is declared `late Isar isar;` — and reuse `openIsar(String dir)` defined at the top.)

Run: `flutter test test/data/models/plan_exercise_prescription_test.dart test/data/repositories/program_workout_durable_create_test.dart`
Expected: PASS (all pre-existing tests too).

- [ ] **Step 6: Commit**

```bash
dart format --output=none --set-exit-if-changed .
git add lib/data/models/plan_exercise_prescription.dart lib/data/repositories/session_repository.dart test/data/models/plan_exercise_prescription_test.dart test/data/repositories/program_workout_durable_create_test.dart
git commit -m "feat(app): local program-workout materialization snapshots targets, identity and sortOrder"
```

---

### Task 7: Previous-performance query (`ExerciseRepository.getExerciseGuidance`)

**Files:**
- Create: `lib/data/models/exercise_guidance.dart`
- Modify: `lib/data/repositories/exercise_repository.dart` (new public method + private helper, near `getExerciseSets` L495)
- Test: `test/data/repositories/exercise_repository_previous_performance_test.dart`

**Interfaces:**
- Consumes: Task 5 fields; `LiftedWeightContractMigration.wouldPurge`.
- Produces:
  - `class PreviousPerformance { final int sessionLocalId; final DateTime performedAt; final List<ExerciseSet> sets; }` (weights raw kg, `setNumber` ascending)
  - `class ExerciseGuidance { final int? targetSets, targetRepsMin, targetRepsMax; final PreviousPerformance? previous; }`
  - `abstract final class PreviousPerformanceRules { static int compareExerciseOrder(LocalExercise a, LocalExercise b); static int compareSessionsNewestFirst(LocalSession a, LocalSession b); static bool isCountedExercise(LocalExercise e); static bool isLoggedSet(LocalExerciseSet s); }`
  - `Future<ExerciseGuidance?> ExerciseRepository.getExerciseGuidance(int exerciseId)` — `null` when the exercise is not owned/resolvable.

- [ ] **Step 1: Model file**

```dart
import '../local/models/local_exercise.dart';
import '../local/models/local_exercise_set.dart';
import '../local/models/local_session.dart';
import 'exercise_set.dart';

/// Most recent prior logged performance of one exercise occurrence
/// (Phase 2D spec §3). [sets] are in setNumber order with weights in
/// canonical kg exactly as stored - never converted here.
class PreviousPerformance {
  final int sessionLocalId;
  final DateTime performedAt;
  final List<ExerciseSet> sets;
  const PreviousPerformance({
    required this.sessionLocalId,
    required this.performedAt,
    required this.sets,
  });
}

/// What Log Sets shows for one exercise: the snapshotted target (from the
/// session exercise itself, never the plan) and the previous performance.
class ExerciseGuidance {
  final int? targetSets;
  final int? targetRepsMin;
  final int? targetRepsMax;
  final PreviousPerformance? previous;
  const ExerciseGuidance({
    this.targetSets,
    this.targetRepsMin,
    this.targetRepsMax,
    this.previous,
  });
}

/// Deterministic ordering/qualification rules for the previous-performance
/// query, kept pure for direct testing.
abstract final class PreviousPerformanceRules {
  /// Within one session: sortOrder, then localId.
  static int compareExerciseOrder(LocalExercise a, LocalExercise b) {
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    return bySort != 0 ? bySort : a.localId.compareTo(b.localId);
  }

  /// Newest first: (completedAt ?? date) desc, date desc, localId desc.
  static int compareSessionsNewestFirst(LocalSession a, LocalSession b) {
    final byWhen = (b.completedAt ?? b.date).compareTo(a.completedAt ?? a.date);
    if (byWhen != 0) return byWhen;
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.localId.compareTo(a.localId);
  }

  /// Deleted-intent rows and reconcile `conflict` placeholders (whose server
  /// twin exists separately) never occupy an ordinal slot.
  static bool isCountedExercise(LocalExercise e) =>
      e.syncStatus != 'pending_delete' && e.syncStatus != 'conflict';

  /// A logged set records something actually performed.
  static bool isLoggedSet(LocalExerciseSet s) =>
      s.syncStatus != 'pending_delete' &&
      (s.reps != null ||
          (s.duration ?? 0) > 0 ||
          (s.weight ?? 0) > 0);
}
```

- [ ] **Step 2: Failing tests** — `test/data/repositories/exercise_repository_previous_performance_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/lifted_weight_contract_migration.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_program.dart';
import 'package:go_hard_app/data/local/models/local_program_workout.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/local/services/model_mapper.dart';
import 'package:go_hard_app/data/repositories/exercise_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';

import 'session_repository_session_ownership_test.mocks.dart';

/// Phase 2D spec §3: previous performance is a local, offline, deterministic
/// query over completed canonical sessions, strict same-template ordinal
/// pairing, raw kg. Real Isar; any HTTP call fails the test.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService auth;
  late MockConnectivityService connectivity;
  late UserSessionEpoch epoch;

  const me = 1;
  const other = 2;

  setUpAll(() async => Isar.initializeIsarCore(download: true));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('prev_perf_');
    isar = await Isar.open(
      [
        LocalSessionSchema,
        LocalExerciseSchema,
        LocalExerciseSetSchema,
        LocalExerciseTemplateSchema,
        LocalProgramSchema,
        LocalProgramWorkoutSchema,
      ],
      directory: tempDir.path,
      inspector: false,
    );
    LocalDatabaseService.instance.setTestDatabase(isar);
    auth = MockAuthService();
    connectivity = MockConnectivityService();
    when(connectivity.isOnline).thenReturn(false); // offline by default
    when(auth.getUserId()).thenAnswer((_) async => me);
    when(auth.getToken()).thenAnswer((_) async => 'jwt');
    epoch = UserSessionEpoch()..activate(me);
  });

  tearDown(() async {
    await isar.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ExerciseRepository repo([LiftedWeightContractMigration? migration]) {
    final api = ApiService(auth, epoch)..testHttpClientAdapter = _NoNetwork();
    return ExerciseRepository(
      api,
      LocalDatabaseService.instance,
      connectivity,
      epoch,
      SessionRequestCoordinator(epoch, auth),
      migration,
    );
  }

  var clock = DateTime.utc(2026, 1, 1);
  DateTime next() => clock = clock.add(const Duration(days: 1));

  Future<int> session({
    int userId = me,
    String status = 'completed',
    DateTime? completedAt,
    int? serverId,
    String syncStatus = 'synced',
  }) async {
    final when_ = completedAt ?? next();
    final s = LocalSession(
      userId: userId,
      date: when_,
      name: 'W',
      type: 'Strength',
      status: status,
      completedAt: status == 'completed' ? when_ : null,
      serverId: serverId,
      syncStatus: syncStatus,
      isSynced: syncStatus == 'synced',
      lastModifiedLocal: when_,
    );
    return isar.writeTxn(() => isar.localSessions.put(s));
  }

  Future<int> exercise(
    int sessionLocalId, {
    int? templateId = 1,
    int sortOrder = 0,
    String syncStatus = 'synced',
    int? targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
  }) {
    final e = LocalExercise(
      sessionLocalId: sessionLocalId,
      name: 'Bench Press',
      sortOrder: sortOrder,
      exerciseTemplateId: templateId,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      syncStatus: syncStatus,
      isSynced: syncStatus == 'synced',
      lastModifiedLocal: clock,
    );
    return isar.writeTxn(() => isar.localExercises.put(e));
  }

  Future<void> sets(int exerciseLocalId, List<(int? reps, double? kg)> rows) =>
      isar.writeTxn(() async {
        for (var i = 0; i < rows.length; i++) {
          await isar.localExerciseSets.put(
            LocalExerciseSet(
              exerciseLocalId: exerciseLocalId,
              setNumber: i + 1,
              reps: rows[i].$1,
              weight: rows[i].$2,
              isCompleted: false,
              isSynced: true,
              syncStatus: 'synced',
              lastModifiedLocal: clock,
            ),
          );
        }
      });

  int publicId(int localId) => ModelMapper.publicRowId(serverId: null, localId: localId);

  Future<List<(int?, double?)>?> lastTime(ExerciseRepository r, int exerciseLocalId) async {
    final g = await r.getExerciseGuidance(publicId(exerciseLocalId));
    return g?.previous?.sets.map((s) => (s.reps, s.weight)).toList();
  }

  test('returns the most recent prior completed session, raw kg, setNumber order', () async {
    final old = await exercise(await session());
    await sets(old, [(10, 50.0)]);
    final recent = await exercise(await session());
    await sets(recent, [(10, 61.235), (9, 61.235), (8, 61.235)]);
    final current = await exercise(await session(status: 'in_progress'));

    expect(await lastTime(repo(), current), [(10, 61.235), (9, 61.235), (8, 61.235)]);
  });

  test('ignores the current session, non-completed, pending_delete and other users', () async {
    final draft = await exercise(await session(status: 'in_progress'));
    await sets(draft, [(5, 100.0)]);
    final deleted = await exercise(await session(syncStatus: 'pending_delete'));
    await sets(deleted, [(5, 100.0)]);
    final foreign = await exercise(await session(userId: other));
    await sets(foreign, [(5, 100.0)]);
    final currentSession = await session(status: 'in_progress');
    final current = await exercise(currentSession);
    await sets(current, [(1, 1.0)]);

    expect(await lastTime(repo(), current), isNull);
  });

  test('a completed current session never sees sessions completed after it', () async {
    final current = await exercise(await session());
    await sets(current, [(8, 60.0)]);
    final later = await exercise(await session());
    await sets(later, [(8, 70.0)]);
    expect(await lastTime(repo(), current), isNull);
  });

  test('no history -> null previous; targets still returned', () async {
    final current = await exercise(
      await session(status: 'in_progress'),
      targetSets: 3, targetRepsMin: 8, targetRepsMax: 10,
    );
    final g = await repo().getExerciseGuidance(publicId(current));
    expect(g!.previous, isNull);
    expect((g.targetSets, g.targetRepsMin, g.targetRepsMax), (3, 8, 10));
  });

  test('missing template id -> null previous (no name matching)', () async {
    final prior = await exercise(await session(), templateId: null);
    await sets(prior, [(10, 50.0)]);
    final current = await exercise(await session(status: 'in_progress'), templateId: null);
    expect(await lastTime(repo(), current), isNull);
  });

  test('prior occurrence without logged sets is skipped; older one used', () async {
    final older = await exercise(await session());
    await sets(older, [(10, 50.0)]);
    final emptyNewer = await exercise(await session());
    await sets(emptyNewer, [(null, null), (null, 0.0)]);
    final current = await exercise(await session(status: 'in_progress'));
    expect(await lastTime(repo(), current), [(10, 50.0)]);
  });

  test('incomplete prior session returns only its logged sets', () async {
    final prior = await exercise(await session());
    await sets(prior, [(10, 50.0), (null, null)]);
    final current = await exercise(await session(status: 'in_progress'));
    expect(await lastTime(repo(), current), [(10, 50.0)]);
  });

  test('bodyweight: reps with null weight returned unchanged', () async {
    final prior = await exercise(await session());
    await sets(prior, [(12, null), (10, null)]);
    final current = await exercise(await session(status: 'in_progress'));
    expect(await lastTime(repo(), current), [(12, null), (10, null)]);
  });

  group('strict ordinal pairing', () {
    test('current #2, previous session has only #1 -> skipped; older session #2 returned', () async {
      final olderSession = await session();
      final o1 = await exercise(olderSession, sortOrder: 0);
      await sets(o1, [(5, 100.0)]);
      final o2 = await exercise(olderSession, sortOrder: 2);
      await sets(o2, [(10, 70.0)]);
      final prev = await exercise(await session(), sortOrder: 0);
      await sets(prev, [(5, 105.0)]);

      final currentSession = await session(status: 'in_progress');
      final c1 = await exercise(currentSession, sortOrder: 0);
      final c2 = await exercise(currentSession, sortOrder: 3);

      expect(await lastTime(repo(), c1), [(5, 105.0)]);
      expect(await lastTime(repo(), c2), [(10, 70.0)]);
    });

    test('no historical #2 -> null for #2, #1 still resolves', () async {
      final prev = await exercise(await session());
      await sets(prev, [(5, 105.0)]);
      final currentSession = await session(status: 'in_progress');
      final c1 = await exercise(currentSession, sortOrder: 0);
      final c2 = await exercise(currentSession, sortOrder: 1);
      expect(await lastTime(repo(), c1), [(5, 105.0)]);
      expect(await lastTime(repo(), c2), isNull);
    });

    test('unlogged #1 does not shift a logged #2 into slot #1', () async {
      final older = await exercise(await session());
      await sets(older, [(5, 90.0)]);
      final priorSession = await session();
      final p1 = await exercise(priorSession, sortOrder: 0);
      await sets(p1, [(null, null)]);
      final p2 = await exercise(priorSession, sortOrder: 1);
      await sets(p2, [(10, 70.0)]);

      final currentSession = await session(status: 'in_progress');
      final c1 = await exercise(currentSession, sortOrder: 0);
      final c2 = await exercise(currentSession, sortOrder: 1);
      expect(await lastTime(repo(), c1), [(5, 90.0)]); // prior #1 unlogged -> older #1
      expect(await lastTime(repo(), c2), [(10, 70.0)]);
    });

    test('conflict / pending_delete exercises never occupy a slot', () async {
      final priorSession = await session();
      final ghost = await exercise(priorSession, sortOrder: 0, syncStatus: 'conflict');
      await sets(ghost, [(1, 1.0)]);
      final real = await exercise(priorSession, sortOrder: 1);
      await sets(real, [(10, 70.0)]);
      final current = await exercise(await session(status: 'in_progress'));
      expect(await lastTime(repo(), current), [(10, 70.0)]);
    });
  });

  group('lifted-weight migration gate', () {
    String? state;
    LiftedWeightContractMigration migration() => LiftedWeightContractMigration(
      database: () => isar,
      readState: () async => state,
      writeState: (j) async => state = j,
    );

    setUp(() => state = null);

    test('pending: legacy (below cutoff) and server-backed sessions are excluded', () async {
      final legacy = await exercise(await session());
      await sets(legacy, [(10, 100.0)]);
      final m = migration();
      await m.snapshotIfNeeded(); // cutoff = current max ids -> everything above is canonical
      final serverBacked = await exercise(await session(serverId: 77));
      await sets(serverBacked, [(10, 110.0)]);
      final current = await exercise(await session(status: 'in_progress'));

      expect(await lastTime(repo(m), current), isNull);

      final canonical = await exercise(await session(completedAt: DateTime.utc(2025, 1, 1)));
      await sets(canonical, [(8, 60.0)]);
      expect(await lastTime(repo(m), current), [(8, 60.0)]);
    });

    test('complete: server-backed history is eligible', () async {
      state = '{"status":"complete"}';
      final m = migration();
      await m.snapshotIfNeeded();
      final prior = await exercise(await session(serverId: 77));
      await sets(prior, [(10, 110.0)]);
      final current = await exercise(await session(status: 'in_progress'));
      expect(await lastTime(repo(m), current), [(10, 110.0)]);
    });
  });

  test('works offline and online identically: never touches the network', () async {
    final prior = await exercise(await session());
    await sets(prior, [(10, 50.0)]);
    final current = await exercise(await session(status: 'in_progress'));
    when(connectivity.isOnline).thenReturn(true);
    expect(await lastTime(repo(), current), [(10, 50.0)]); // _NoNetwork would throw
  });
}

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) =>
      throw StateError('previous performance must never hit the network: ${o.path}');
  @override
  void close({bool force = false}) {}
}
```

Notes for the implementer: `LocalSession` requires `lastModifiedLocal`; `completedAt: DateTime.utc(2025,1,1)` in the pending test gives that session an *older* date than `legacy`, proving the result comes from the canonical row rather than recency. If `LocalExerciseSet` has further required params, add them with neutral values. Unit invariance: `getExerciseGuidance` takes no unit input and returns stored kg — covered by the 61.235 assertion; the widget test in Task 9 covers Metric/Imperial display.

- [ ] **Step 3: Run — expect compile FAIL** (`flutter test test/data/repositories/exercise_repository_previous_performance_test.dart`)

- [ ] **Step 4: Implement** in `ExerciseRepository` (imports: `../models/exercise_guidance.dart`, `../local/models/local_session.dart` if not present):

```dart
  /// Target (snapshotted on the session exercise) plus most recent prior
  /// logged performance for [exerciseId] - Phase 2D spec §3. Purely local:
  /// identical online and offline, never calls the API. Weights are raw kg.
  /// `null` when [exerciseId] is not an owned exercise.
  Future<ExerciseGuidance?> getExerciseGuidance(int exerciseId) async {
    final context = await _sessionCoordinator.captureContext();
    if (context == null) throw const SessionStaleException();
    final token = context.epochToken;
    final Isar db = _localDb.database;

    final current = await _resolveOwnedExercise(db, exerciseId, token);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();
    if (current == null) return null;

    final previous = await _previousPerformance(db, current, token);
    if (!_sessionEpoch.isCurrent(token)) throw const SessionStaleException();

    return ExerciseGuidance(
      targetSets: current.targetSets,
      targetRepsMin: current.targetRepsMin,
      targetRepsMax: current.targetRepsMax,
      previous: previous,
    );
  }

  Future<List<LocalExercise>> _sameTemplateOccurrences(
    Isar db,
    int sessionLocalId,
    int templateId,
  ) async =>
      (await db.localExercises
            .filter()
            .sessionLocalIdEqualTo(sessionLocalId)
            .exerciseTemplateIdEqualTo(templateId)
            .findAll())
          .where(PreviousPerformanceRules.isCountedExercise)
          .toList()
        ..sort(PreviousPerformanceRules.compareExerciseOrder);

  /// Strict same-template ordinal pairing (spec §3): the current exercise's
  /// position k among same-template exercises in its session is matched to
  /// position k in each older canonical completed session, newest first;
  /// a missing or unlogged slot k moves on to the next older session and
  /// never falls back to another occurrence.
  Future<PreviousPerformance?> _previousPerformance(
    Isar db,
    LocalExercise current,
    UserSessionToken token,
  ) async {
    final templateId = current.exerciseTemplateId;
    if (templateId == null) return null;

    final currentSession = await db.localSessions.get(current.sessionLocalId);
    if (currentSession == null) return null;
    final k = (await _sameTemplateOccurrences(db, currentSession.localId, templateId))
        .indexWhere((e) => e.localId == current.localId);
    if (k < 0) return null;

    final candidates = (await db.localSessions
            .filter()
            .userIdEqualTo(token.userId)
            .statusEqualTo('completed')
            .findAll())
        .where(
          (s) =>
              s.localId != currentSession.localId &&
              s.syncStatus != 'pending_delete' &&
              // Legacy / purge-eligible history is unit-ambiguous (Phase 2C).
              !(_liftedWeightMigration?.wouldPurge('sessions', s.localId, s.serverId) ?? false) &&
              // Viewing a completed session: only strictly older sessions are prior.
              (currentSession.status != 'completed' ||
                  PreviousPerformanceRules.compareSessionsNewestFirst(currentSession, s) < 0),
        )
        .toList()
      ..sort(PreviousPerformanceRules.compareSessionsNewestFirst);
    if (!_sessionEpoch.isCurrent(token)) return null;

    for (final session in candidates) {
      final occurrences = await _sameTemplateOccurrences(db, session.localId, templateId);
      if (k >= occurrences.length) continue;
      final logged = (await db.localExerciseSets
              .filter()
              .exerciseLocalIdEqualTo(occurrences[k].localId)
              .findAll())
          .where(PreviousPerformanceRules.isLoggedSet)
          .toList()
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
      if (logged.isEmpty) continue;
      return PreviousPerformance(
        sessionLocalId: session.localId,
        performedAt: session.completedAt ?? session.date,
        sets: logged.map(ModelMapper.localToExerciseSet).toList(),
      );
    }
    return null;
  }
```

(`UserSessionToken`'s import is already used by `_resolveOwnedExercise`.)

- [ ] **Step 5: Run**

Run: `flutter test test/data/repositories/exercise_repository_previous_performance_test.dart test/data/repositories/exercise_repository_session_ownership_test.dart`
Expected: PASS.

- [ ] **Step 6: Regenerate mocks of `ExerciseRepository`** (new public method): `dart run build_runner build --delete-conflicting-outputs && dart format .`; confirm only `*.mocks.dart` files mocking `ExerciseRepository` changed; `flutter analyze` clean.

- [ ] **Step 7: Commit**

```bash
dart format --output=none --set-exit-if-changed .
git add lib/data/models/exercise_guidance.dart lib/data/repositories/exercise_repository.dart test/data/repositories/exercise_repository_previous_performance_test.dart && git add -u test
git commit -m "feat(app): deterministic local previous-performance query with strict ordinal pairing"
```

---

### Task 8: APP half of the end-to-end contract

**Files:**
- Create: `test/fixtures/phase2d_plan_session_contract.json` (byte-identical copy of the API fixture)
- Modify: `test/data/repositories/program_workout_durable_create_test.dart` (one test in the Task 6 group)

- [ ] **Step 1: Copy the fixture**

```bash
cp ../GoHardAPI-phase2d/GoHardAPI.Tests/Fixtures/phase2d_plan_session_contract.json test/fixtures/
```

- [ ] **Step 2: Write the test** (add `import 'package:go_hard_app/data/repositories/exercise_repository.dart';` and `import 'package:go_hard_app/data/local/services/model_mapper.dart';` if absent)

```dart
    test('E2E: fixture plan entry -> local materialization -> reconcile -> Isar -> previous performance', () async {
      final fixture = jsonDecode(
        File('test/fixtures/phase2d_plan_session_contract.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final planEntry = {
        ...(fixture['programWorkoutExercise'] as Map<String, dynamic>),
        'occurrenceKey': 'e2e-key',
      };
      final serverExercise = fixture['sessionExercise'] as Map<String, dynamic>;
      final templateId = fixture['systemTemplateId'] as int;

      loginAs(userA);

      // A prior completed canonical session with the same template.
      final priorSessionId = await isar.writeTxn(() => isar.localSessions.put(LocalSession(
        userId: userA, date: DateTime.utc(2031, 6, 1), name: 'Prior', type: 'Strength',
        status: 'completed', completedAt: DateTime.utc(2031, 6, 1),
        lastModifiedLocal: DateTime.utc(2031, 6, 1),
      )));
      final priorExerciseId = await isar.writeTxn(() => isar.localExercises.put(LocalExercise(
        sessionLocalId: priorSessionId, name: 'Bench Press', exerciseTemplateId: templateId,
        lastModifiedLocal: DateTime.utc(2031, 6, 1),
      )));
      await isar.writeTxn(() => isar.localExerciseSets.put(LocalExerciseSet(
        exerciseLocalId: priorExerciseId, setNumber: 1, reps: 10, weight: 61.235,
        isCompleted: true, lastModifiedLocal: DateTime.utc(2031, 6, 1),
      )));

      final held = Completer<ResponseBody>();
      adapter.responder = (o) => held.future;
      Future<void>? settled;
      repository.onBackgroundSyncScheduledForTesting = (s) => settled = s;
      final created = await repository.createSessionFromProgramWorkout(
        10, workout(exercisesJson: jsonEncode([planEntry])), DateTime(2031, 1, 1), 5);
      repository.onBackgroundSyncScheduledForTesting = null;

      var local = (await isar.localExercises.filter().sessionLocalIdEqualTo(created.id).findAll()).single;
      expect(local.exerciseTemplateId, templateId, reason: 'local materializer copies plan identity');

      held.complete(jsonResponse(sessionJson(id: 900, exercises: [
        {...exerciseJson(9001, sessionId: 900, exerciseTemplateId: templateId, occurrenceKey: 'e2e-key'), ...serverExercise},
      ])));
      await settled;

      local = (await isar.localExercises.filter().sessionLocalIdEqualTo(created.id).findAll()).single;
      expect(
        (local.serverId, local.exerciseTemplateId, local.sortOrder, local.targetSets, local.targetRepsMin, local.targetRepsMax),
        (9001, serverExercise['exerciseTemplateId'], serverExercise['sortOrder'], serverExercise['targetSets'],
            serverExercise['targetRepsMin'], serverExercise['targetRepsMax']),
      );

      final exercises = ExerciseRepository(apiService, localDb, mockConnectivity, sessionEpoch, sessionCoordinator);
      final guidance = await exercises.getExerciseGuidance(9001);
      expect(guidance!.previous!.sets.single.weight, 61.235);
      expect((guidance.targetSets, guidance.targetRepsMin, guidance.targetRepsMax), (3, 8, 10));
    });
```

- [ ] **Step 3: Run** — `flutter test test/data/repositories/program_workout_durable_create_test.dart` → PASS.
- [ ] **Step 4: Commit**

```bash
dart format --output=none --set-exit-if-changed .
git add test/fixtures/phase2d_plan_session_contract.json test/data/repositories/program_workout_durable_create_test.dart
git commit -m "test(app): Phase 2D plan -> session -> Isar -> previous-performance contract"
```

---

### Task 9: Minimal UI proof (target + last time; program rep ranges)

**Files:**
- Create: `lib/core/utils/rep_target_format.dart`
- Modify: `lib/providers/log_sets_provider.dart`, `lib/ui/screens/exercises/log_sets_screen.dart`, `lib/ui/screens/programs/program_workout_screen.dart` (`_buildExerciseCard`, L476-481)
- Test: `test/core/utils/rep_target_format_test.dart`, `test/ui/screens/exercises/log_sets_guidance_test.dart`

**Interfaces:**
- Produces: `String? formatRepTarget({int? sets, int? repsMin, int? repsMax})`; `LogSetsProvider.guidance` (`ExerciseGuidance?`), `Future<void> LogSetsProvider.loadGuidance(int exerciseId)`.

- [ ] **Step 1: Failing format tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/core/utils/rep_target_format.dart';

void main() {
  test('exact', () => expect(formatRepTarget(sets: 3, repsMin: 8, repsMax: 8), '3 × 8'));
  test('range', () => expect(formatRepTarget(sets: 3, repsMin: 8, repsMax: 10), '3 × 8–10'));
  test('reps only', () => expect(formatRepTarget(repsMin: 8, repsMax: 10), '8–10 reps'));
  test('sets only', () => expect(formatRepTarget(sets: 3), '3 sets'));
  test('nothing', () => expect(formatRepTarget(), isNull));
}
```

- [ ] **Step 2: Implement**

```dart
/// Display text for a structured rep prescription (Phase 2D). Formats
/// structured values only - never parses strings.
String? formatRepTarget({int? sets, int? repsMin, int? repsMax}) {
  final reps = repsMin == null
      ? null
      : (repsMax != null && repsMax > repsMin ? '$repsMin–$repsMax' : '$repsMin');
  if (sets != null && reps != null) return '$sets × $reps';
  if (reps != null) return '$reps reps';
  if (sets != null) return '$sets sets';
  return null;
}
```

Run `flutter test test/core/utils/rep_target_format_test.dart` → PASS.

- [ ] **Step 3: Program workout screen** — in `_buildExerciseCard` replace the `reps` line:

```dart
    final repsMin = exercise['reps'];
    final repsMax = exercise['repsMax'];
    final reps =
        repsMin is int
            ? formatRepTarget(repsMin: repsMin, repsMax: repsMax is int ? repsMax : null)!
                .replaceAll(' reps', '')
            : (repsMin?.toString() ?? '-');
```

(import `../../../core/utils/rep_target_format.dart`). Existing labels keep rendering `sets` and `reps` separately.

- [ ] **Step 4: Provider** — in `LogSetsProvider` add:

```dart
  ExerciseGuidance? _guidance;
  int _guidanceGen = 0;

  /// Target + previous performance for the exercise being logged (Phase 2D).
  /// Optional: a failure leaves it null and never blocks logging.
  ExerciseGuidance? get guidance => _guidance;

  Future<void> loadGuidance(int exerciseId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final myGen = ++_guidanceGen;
    _guidance = null;
    bool owns() => _sessionEpoch.isCurrent(token) && _guidanceGen == myGen;
    try {
      final guidance = await _exerciseRepository.getExerciseGuidance(exerciseId);
      if (!owns()) return;
      _guidance = guidance;
      notifyListeners();
    } catch (e) {
      if (!owns()) return;
      debugPrint('Load guidance error: $e');
    }
  }
```

In `_invalidateGenerations()` add `_guidanceGen++;`; in `clear()` add `_guidance = null;` before `notifyListeners()`. Import `../data/models/exercise_guidance.dart`.

- [ ] **Step 5: Screen** — in `initState`'s post-frame callback, after `loadSets`: `context.read<LogSetsProvider>().loadGuidance(widget.exerciseId);`. In `build`, insert as the first child of the `Column` (before `// Add set form`): `_GuidanceCard(guidance: provider.guidance, pref: pref),` and add at file end:

```dart
class _GuidanceCard extends StatelessWidget {
  final ExerciseGuidance? guidance;
  final String pref;
  const _GuidanceCard({required this.guidance, required this.pref});

  @override
  Widget build(BuildContext context) {
    final g = guidance;
    if (g == null) return const SizedBox.shrink();
    final target = formatRepTarget(
      sets: g.targetSets,
      repsMin: g.targetRepsMin,
      repsMax: g.targetRepsMax,
    );
    final previous = g.previous?.sets ?? const [];
    if (target == null && previous.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (target != null) Text('Target  $target', style: style),
          if (previous.isNotEmpty) ...[
            Text('Last time', style: style),
            for (final s in previous)
              Text(
                s.weight != null && s.weight! > 0
                    ? '${UnitConverter.formatLifted(s.weight!, pref)} × ${s.reps ?? '—'}'
                    : '${s.reps ?? '—'} reps',
                style: style,
              ),
          ],
        ],
      ),
    );
  }
}
```

(imports: `../../../data/models/exercise_guidance.dart`, `../../../core/utils/rep_target_format.dart`.)

- [ ] **Step 6: Widget test** `test/ui/screens/exercises/log_sets_guidance_test.dart` — copy the provider/mocks scaffolding of `log_sets_canonical_test.dart` (`@GenerateMocks([ExerciseRepository, ProfileRepository, AuthService])`, `buildProfileProvider`, `pumpScreen`), stub guidance, and assert:

```dart
  final guidance = ExerciseGuidance(
    targetSets: 3, targetRepsMin: 8, targetRepsMax: 10,
    previous: PreviousPerformance(sessionLocalId: 1, performedAt: DateTime.utc(2026, 1, 1), sets: [
      ExerciseSet(id: 1, exerciseId: 1, setNumber: 1, reps: 10, weight: 61.235, isCompleted: true),
    ]),
  );

  testWidgets('shows target and last time in kg (Metric)', (tester) async {
    when(exerciseRepo.getExerciseGuidance(any)).thenAnswer((_) async => guidance);
    await pumpScreen(tester, await buildProfileProvider(tester, 'Metric'));
    expect(find.text('Target  3 × 8–10'), findsOneWidget);
    expect(find.textContaining('61.2'), findsOneWidget);
    expect(find.textContaining('kg'), findsWidgets);
  });

  testWidgets('Imperial changes only display; stored kg value untouched', (tester) async {
    when(exerciseRepo.getExerciseGuidance(any)).thenAnswer((_) async => guidance);
    await pumpScreen(tester, await buildProfileProvider(tester, 'Imperial'));
    expect(find.textContaining('135'), findsOneWidget); // 61.235 kg -> 135.0 lb
    expect(guidance.previous!.sets.single.weight, 61.235);
    verifyNever(exerciseRepo.updateExerciseSet(any, any));
    verifyNever(exerciseRepo.createExerciseSet(any));
  });

  testWidgets('no guidance renders nothing extra', (tester) async {
    when(exerciseRepo.getExerciseGuidance(any)).thenAnswer((_) async => null);
    await pumpScreen(tester, await buildProfileProvider(tester, 'Metric'));
    expect(find.text('Last time'), findsNothing);
  });
```

Check the exact unit-preference strings `ProfileProvider` uses in `log_sets_canonical_test.dart` (e.g. `'Metric'`/`'Imperial'`) and `UnitConverter.formatLifted`'s output for 61.235 kg in lb, and assert that exact text. Also add `when(exerciseRepo.getExerciseGuidance(any)).thenAnswer((_) async => null);` to `log_sets_canonical_test.dart`'s `setUp` if its mock now throws on the unstubbed call.

- [ ] **Step 7: Codegen, run, commit**

```bash
dart run build_runner build --delete-conflicting-outputs
dart format .
flutter test test/core/utils/rep_target_format_test.dart test/ui/screens/exercises/
dart format --output=none --set-exit-if-changed .
git add lib/core/utils/rep_target_format.dart lib/providers/log_sets_provider.dart lib/ui/screens/exercises/log_sets_screen.dart lib/ui/screens/programs/program_workout_screen.dart test/core/utils/rep_target_format_test.dart test/ui/screens/exercises/
git commit -m "feat(app): show snapshotted target and last-time performance on Log Sets"
```

### Checkpoint B — APP review + full verification

- [ ] From `GoHardAPP-phase2d`:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --concurrency=1
```
Then `pwsh tool/verify.ps1` (repo root). Expected: all green; record test count.
- [ ] `git checkout -- linux macos windows`; `git diff origin/main --stat` shows only files from the APP file map (+ spec/plan docs, regenerated `.g.dart`/`.mocks.dart`).
- [ ] Re-run API verification (Checkpoint A commands) to confirm both repos green together.
- [ ] superpowers:requesting-code-review over both branches; apply accepted findings with TDD; superpowers:verification-before-completion before reporting.
- [ ] Stop. Report: target source of truth, data flow, identity/query rules, AI identity behavior, offline behavior, schema/model changes, commits per repo, test results (passed/skipped), review findings, remaining risks (spec §8 verbatim on Phase 2C). No merge, no deploy.

---

## Rollback / compatibility

- **Deploy order when eventually released: API before APP.** New APP + old API: the server's session exercise lacks target/sortOrder fields, so reconcile (`exerciseToLocal`) would overwrite locally snapshotted targets with null. Old APP + new API is safe: `json_serializable` ignores unknown keys; the old app already reads plan `exerciseTemplateId` as `int?`.
- While `CanonicalHistory=false`, workout uploads are gated, so reconcile does not run in production; the on-device snapshot is what users see (spec §8).
- **API rollback:** code rollback with the columns present is inert (nullable, unread). Migration `Down` drops the three columns on SQL Server/PostgreSQL (loses only snapshotted targets); SQLite Down is a no-op, same as `AddExerciseOccurrenceKey`. Plan JSON containing `exerciseTemplateId`/`repsMax` is valid input to the pre-2D materializer (template id was already read; `repsMax` ignored).
- **APP rollback:** Isar fields are additive nullable; an older build ignores them. `sortOrder` becomes 0 again on reconcile under older code (pre-2D behavior).
- **No data migration/backfill:** existing programs/sessions keep null identity/targets.
- Nothing is merged or deployed; Railway and `CanonicalHistory` untouched.

## Self-review (done)

- Spec coverage: §2 plan JSON/targets/sortOrder/reconcile → Tasks 2, 3, 5, 6; §3 query + strict ordinals + legacy exclusion → Task 7; §4 resolver + propagation → Tasks 1, 4, 8; §5 UI → Task 9; §7 tests → Tasks 1–9; §8 rollout → Global Constraints, Checkpoint B report, Rollback section.
- Names consistent: `ExerciseTemplateResolver.Resolve/Normalize`, `ExerciseTargetsSql`, `AddExerciseTargets`, `targetSets/targetRepsMin/targetRepsMax`, `PlanExercisePrescription.fromPlanEntry`, `ExerciseGuidance`, `PreviousPerformance`, `PreviousPerformanceRules`, `getExerciseGuidance`, `formatRepTarget`, `loadGuidance`.
- Known executor-verify points (existing-code facts not re-read while planning): `FakeProvider.Returning` signature; Postgres fixture namespace; `ProfileProvider` unit strings; exact lb formatting of 61.235 kg; any additional required ctor params on `LocalExerciseSet`/`LocalSession`.
