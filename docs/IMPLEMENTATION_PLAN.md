# Workouts & Programs Reorganization - Implementation Plan

**Date:** 2026-01-11
**Status:** Ready for Review & Approval
**Purpose:** Detailed step-by-step implementation guide for reorganizing My Workouts and Programs tabs

---

## Table of Contents
1. [Overview](#overview)
2. [Phase 1: Remove Upcoming Section](#phase-1-remove-upcoming-section)
3. [Phase 2: Add Weekly Schedule to Programs](#phase-2-add-weekly-schedule-to-programs)
4. [Phase 3: Link Sessions & Programs](#phase-3-link-sessions--programs)
5. [Testing Strategy](#testing-strategy)
6. [Rollback Plan](#rollback-plan)

---

## Overview

### Goals
1. **Phase 1 (Short-term):** Remove confusing "Upcoming" section from My Workouts tab
2. **Phase 2 (Medium-term):** Add weekly schedule view to Programs tab
3. **Phase 3 (Long-term):** Link ProgramWorkouts to Sessions for unified tracking

### Timeline Estimate
- **Phase 1:** 1-2 hours
- **Phase 2:** 4-8 hours
- **Phase 3:** 16-24 hours (includes backend changes)

### Risk Level
- **Phase 1:** ✅ Low (UI only, no data changes)
- **Phase 2:** ✅ Low (UI only, reads existing data)
- **Phase 3:** ⚠️ Medium (database schema changes, data migration)

---

## Phase 1: Remove Upcoming Section

### Goal
Clean up My Workouts tab by removing the "Upcoming" section that only shows standalone planned workouts.

### Why Remove It?
- Program workouts don't create Sessions, so they don't appear in Upcoming
- Only shows standalone planned workouts (confusing)
- Users can schedule from Programs tab instead
- Simplifies the UI

### Files to Modify
1. `lib/ui/screens/sessions/sessions_screen.dart` (1 file)

---

### Step-by-Step Instructions

#### Step 1: Remove State Variables
**File:** `lib/ui/screens/sessions/sessions_screen.dart`
**Lines:** 28-32

**Remove:**
```dart
bool _isPlannedExpanded =
    false; // Track if planned workouts section is expanded
String _pastWorkoutsFilter = 'Last Month'; // Filter for past workouts
final Map<String, bool> _expandedWorkoutGroups =
    {}; // Track which workout name groups are expanded
```

**Replace with:**
```dart
String _pastWorkoutsFilter = 'Last Month'; // Filter for past workouts
```

---

#### Step 2: Remove plannedSessions Filter
**File:** `lib/ui/screens/sessions/sessions_screen.dart`
**Lines:** 688-691

**Remove:**
```dart
final plannedSessions =
    provider.sessions
        .where((s) => s.status == 'planned')
        .toList();
```

**Why:** We no longer need to filter for planned sessions since we're not displaying them.

---

#### Step 3: Remove Upcoming Section from UI
**File:** `lib/ui/screens/sessions/sessions_screen.dart`
**Lines:** 774-824

**Remove the entire section:**
```dart
// Planned/Upcoming Section (Grouped by Workout Name)
if (plannedSessions.isNotEmpty) ...[
  _buildSectionHeader(
    'Upcoming',
    Icons.event,
    plannedSessions.length,
  ),
  if (_isPlannedExpanded) ...[
    () {
      final groupedPlanned =
          _groupPlannedSessionsByName(
            plannedSessions,
          );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            groupedPlanned.entries.expand((entry) {
              final workoutName = entry.key;
              final sessions = entry.value;
              final isExpanded =
                  _expandedWorkoutGroups[workoutName] ??
                  false;

              return [
                _buildWorkoutNameSubheader(
                  workoutName,
                  sessions.length,
                ),
                // Only show sessions if this group is expanded
                if (isExpanded)
                  ...sessions.map(
                    (session) => SessionCard(
                      session: session,
                      onTap:
                          () => _handleSessionTap(
                            session.id,
                            session.status,
                          ),
                      onDelete:
                          () => _handleDeleteSession(
                            session.id,
                          ),
                    ),
                  ),
              ];
            }).toList(),
      );
    }(),
  ],
],
```

**Result:** The ListView will now only show: Progress Card → TODAY → THIS WEEK → PAST WORKOUTS

---

#### Step 4: Remove Helper Methods
**File:** `lib/ui/screens/sessions/sessions_screen.dart`

**Remove method: `_groupPlannedSessionsByName()` (lines 283-302)**
```dart
/// Group planned sessions by workout name
Map<String, List<Session>> _groupPlannedSessionsByName(
  List<Session> sessions,
) {
  final grouped = <String, List<Session>>{};

  for (final session in sessions) {
    final name = session.name ?? 'Unnamed Workout';
    if (!grouped.containsKey(name)) {
      grouped[name] = [];
    }
    grouped[name]!.add(session);
  }

  // Sort sessions within each group by date
  for (final group in grouped.values) {
    group.sort((a, b) => a.date.compareTo(b.date));
  }

  return grouped;
}
```

**Remove method: `_buildWorkoutNameSubheader()` (lines 305-360)**
```dart
/// Build subheader for workout name groups (collapsible)
Widget _buildWorkoutNameSubheader(String workoutName, int count) {
  final isExpanded = _expandedWorkoutGroups[workoutName] ?? false;

  return InkWell(
    onTap: () {
      setState(() {
        _expandedWorkoutGroups[workoutName] = !isExpanded;
      });
    },
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 8),
      child: Row(
        children: [
          Icon(
            isExpanded ? Icons.expand_more : Icons.chevron_right,
            size: 20,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.fitness_center,
            size: 16,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              workoutName,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

---

#### Step 5: Simplify `_buildSectionHeader()` Method
**File:** `lib/ui/screens/sessions/sessions_screen.dart`
**Lines:** 450-509

**Current code has collapsible logic for "Upcoming" section. Simplify it:**

**Remove:**
```dart
/// Build section header widget
Widget _buildSectionHeader(String label, IconData icon, int? count) {
  final isCollapsible = label == 'Upcoming';

  return InkWell(
    onTap:
        isCollapsible
            ? () {
              setState(() {
                _isPlannedExpanded = !_isPlannedExpanded;
              });
            }
            : null,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
          if (isCollapsible) ...[
            const Spacer(),
            Icon(
              _isPlannedExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    ),
  );
}
```

**Replace with simplified version:**
```dart
/// Build section header widget
Widget _buildSectionHeader(String label, IconData icon, int? count) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
```

---

### Testing Phase 1

#### Manual Testing Checklist
- [ ] App builds without errors
- [ ] My Workouts tab displays correctly
- [ ] TODAY section shows active/completed workouts
- [ ] THIS WEEK section shows Mon-yesterday workouts
- [ ] PAST WORKOUTS section shows historical workouts with filter
- [ ] Progress card displays correct weekly/monthly counts
- [ ] Floating action button "New Workout" still works
- [ ] No Upcoming section appears
- [ ] No visual glitches or layout issues

#### Edge Cases to Test
- [ ] Empty state (no workouts at all)
- [ ] Only today's workouts
- [ ] Only past workouts
- [ ] Active workout in progress

---

### Estimated Time: 1-2 hours
### Risk: ✅ Low
### Impact: ✅ Immediate UX improvement

---

## Phase 2: Add Weekly Schedule to Programs

### Goal
Add a 7-day calendar view to Programs tab showing the current week's workouts from the active program.

### Why Add It?
- Users need to see what's coming this week in their program
- Makes Programs tab the "command center" for structured training
- Shows rest days vs workout days clearly
- Highlights current day and completed workouts

### Files to Create
1. `lib/ui/widgets/programs/weekly_schedule_widget.dart` (NEW)
2. `lib/ui/widgets/programs/workout_day_card.dart` (NEW)

### Files to Modify
1. `lib/ui/screens/programs/programs_screen.dart`
2. `lib/providers/programs_provider.dart` (add helper method)

---

### Step-by-Step Instructions

#### Step 1: Create WeeklyScheduleWidget
**File:** `lib/ui/widgets/programs/weekly_schedule_widget.dart` (NEW)

```dart
import 'package:flutter/material.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_workout.dart';
import 'workout_day_card.dart';

/// Widget that displays a 7-day weekly schedule for a program
class WeeklyScheduleWidget extends StatelessWidget {
  final Program program;
  final Function(ProgramWorkout)? onWorkoutTap;

  const WeeklyScheduleWidget({
    super.key,
    required this.program,
    this.onWorkoutTap,
  });

  /// Get workouts for the current week
  List<ProgramWorkout?> _getThisWeeksWorkouts() {
    if (program.workouts == null) return List.filled(7, null);

    final currentWeek = program.currentWeek;
    final weekWorkouts = <ProgramWorkout?>[];

    // Get workouts for days 1-7 of current week
    for (int day = 1; day <= 7; day++) {
      final workout = program.workouts!.firstWhere(
        (w) => w.weekNumber == currentWeek && w.dayNumber == day,
        orElse: () => ProgramWorkout(
          id: 0,
          programId: program.id,
          weekNumber: currentWeek,
          dayNumber: day,
          workoutName: 'Rest',
          workoutType: 'rest',
          exercisesJson: '[]',
          isCompleted: false,
          orderIndex: day,
        ),
      );
      weekWorkouts.add(workout);
    }

    return weekWorkouts;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekWorkouts = _getThisWeeksWorkouts();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 20,
                color: theme.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                'THIS WEEK\'S SCHEDULE',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                'Week ${program.currentWeek}/${program.totalWeeks}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.primaryColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 7-day calendar
          ...weekWorkouts.asMap().entries.map((entry) {
            final dayNumber = entry.key + 1;
            final workout = entry.value;
            final isCurrentDay = dayNumber == program.currentDay;
            final isPastDay = dayNumber < program.currentDay;

            if (workout == null) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: WorkoutDayCard(
                workout: workout,
                isCurrentDay: isCurrentDay,
                isPastDay: isPastDay,
                onTap: onWorkoutTap != null ? () => onWorkoutTap!(workout) : null,
              ),
            );
          }),
        ],
      ),
    );
  }
}
```

---

#### Step 2: Create WorkoutDayCard
**File:** `lib/ui/widgets/programs/workout_day_card.dart` (NEW)

```dart
import 'package:flutter/material.dart';
import '../../../data/models/program_workout.dart';

/// Card widget for displaying a single day in the weekly schedule
class WorkoutDayCard extends StatelessWidget {
  final ProgramWorkout workout;
  final bool isCurrentDay;
  final bool isPastDay;
  final VoidCallback? onTap;

  const WorkoutDayCard({
    super.key,
    required this.workout,
    required this.isCurrentDay,
    required this.isPastDay,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRestDay = workout.isRestDay;
    final isCompleted = workout.isCompleted;

    // Determine colors
    Color backgroundColor;
    Color textColor;
    Color borderColor;

    if (isCurrentDay) {
      backgroundColor = theme.primaryColor.withValues(alpha: 0.1);
      textColor = theme.primaryColor;
      borderColor = theme.primaryColor;
    } else if (isCompleted) {
      backgroundColor = Colors.green.withValues(alpha: 0.1);
      textColor = Colors.green.shade700;
      borderColor = Colors.green;
    } else if (isRestDay) {
      backgroundColor = Colors.grey.shade50;
      textColor = Colors.grey.shade600;
      borderColor = Colors.grey.shade300;
    } else {
      backgroundColor = Colors.white;
      textColor = Colors.grey.shade800;
      borderColor = Colors.grey.shade300;
    }

    return InkWell(
      onTap: isRestDay ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: isCurrentDay ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Day name
            SizedBox(
              width: 70,
              child: Text(
                workout.dayNameFromNumber,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isCurrentDay ? FontWeight.bold : FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Workout name
            Expanded(
              child: Text(
                workout.workoutName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isCurrentDay ? FontWeight.bold : FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),

            // Status indicator
            if (isCurrentDay)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'TODAY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              )
            else if (isCompleted)
              Icon(Icons.check_circle, color: Colors.green, size: 24)
            else if (!isRestDay && !isPastDay)
              Icon(Icons.circle_outlined, color: Colors.grey.shade400, size: 24)
            else if (isRestDay)
              Icon(Icons.self_improvement, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}
```

---

#### Step 3: Add Helper Method to ProgramsProvider
**File:** `lib/providers/programs_provider.dart`

**Add this method after line 240:**

```dart
/// Get workouts for the current week of a program
List<ProgramWorkout> getThisWeeksWorkouts(Program program) {
  if (program.workouts == null || program.workouts!.isEmpty) {
    return [];
  }

  final currentWeek = program.currentWeek;
  return program.workouts!
      .where((w) => w.weekNumber == currentWeek)
      .toList()
    ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
}
```

---

#### Step 4: Update ProgramsScreen
**File:** `lib/ui/screens/programs/programs_screen.dart`

**Add import at top:**
```dart
import '../../widgets/programs/weekly_schedule_widget.dart';
```

**Replace the program card builder (lines 123-438) to include weekly schedule:**

Find this section in `_buildProgramCard()`:
```dart
// Current Phase Badge
if (!isCompleted)
  Container(
    padding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 6,
    ),
    ...
  ),
const SizedBox(height: 16),
```

**Add AFTER the phase badge and BEFORE the "Today's Workout Section":**

```dart
// Weekly Schedule
if (!isCompleted) ...[
  const Divider(height: 32),
  WeeklyScheduleWidget(
    program: program,
    onWorkoutTap: (workout) {
      if (!workout.isRestDay) {
        Navigator.pushNamed(
          context,
          RouteNames.programWorkout,
          arguments: {
            'workoutId': workout.id,
            'programId': program.id,
          },
        );
      }
    },
  ),
],
const SizedBox(height: 16),
```

---

### Testing Phase 2

#### Manual Testing Checklist
- [ ] App builds without errors
- [ ] Weekly schedule displays for active programs
- [ ] Shows all 7 days (Mon-Sun)
- [ ] Current day is highlighted correctly
- [ ] Completed days show checkmark
- [ ] Rest days are grayed out
- [ ] Tapping workout day navigates to workout detail
- [ ] Tapping rest day does nothing
- [ ] Week number displays correctly (Week X/Y)
- [ ] Schedule updates when program advances

#### Edge Cases to Test
- [ ] Program with no workouts
- [ ] Program in first week
- [ ] Program in last week
- [ ] All days completed
- [ ] No days completed
- [ ] Mix of rest and workout days

---

### Estimated Time: 4-8 hours
### Risk: ✅ Low
### Impact: 🎯 Significant UX improvement

---

## Phase 3: Link Sessions & Programs

### Goal
Add `programId` and `programWorkoutId` to Session model to link program workouts to actual workout sessions.

### Why Link Them?
- **Unified workout history** - See all workouts in one place
- **Accurate progress tracking** - Weekly/monthly stats count ALL workouts
- **Better insights** - Know which sessions came from programs
- **Future features** - Compare planned vs actual performance

### Impact
⚠️ **This is a breaking change** - requires database migration and API updates.

---

### Backend Changes Required

#### Database Migration
**Create migration:** `AddProgramFieldsToSessions`

```sql
-- Migration: Add program fields to Sessions table
ALTER TABLE Sessions
ADD COLUMN ProgramId INT NULL,
ADD COLUMN ProgramWorkoutId INT NULL;

-- Add foreign keys
ALTER TABLE Sessions
ADD CONSTRAINT FK_Sessions_Programs
  FOREIGN KEY (ProgramId) REFERENCES Programs(Id) ON DELETE SET NULL;

ALTER TABLE Sessions
ADD CONSTRAINT FK_Sessions_ProgramWorkouts
  FOREIGN KEY (ProgramWorkoutId) REFERENCES ProgramWorkouts(Id) ON DELETE SET NULL;

-- Add index for better query performance
CREATE INDEX IX_Sessions_ProgramId ON Sessions(ProgramId);
CREATE INDEX IX_Sessions_ProgramWorkoutId ON Sessions(ProgramWorkoutId);
```

---

#### API Changes

**SessionsController.cs**

**Add new endpoint to create session from program workout:**
```csharp
[HttpPost("from-program-workout")]
public async Task<ActionResult<Session>> CreateFromProgramWorkout(
    [FromBody] CreateSessionFromProgramWorkoutDto dto)
{
    var userId = GetCurrentUserId();

    // Get the program workout
    var programWorkout = await _context.ProgramWorkouts
        .Include(pw => pw.Program)
        .FirstOrDefaultAsync(pw => pw.Id == dto.ProgramWorkoutId);

    if (programWorkout == null)
        return NotFound("Program workout not found");

    // Verify user owns the program
    if (programWorkout.Program.UserId != userId)
        return Unauthorized();

    // Create session linked to program workout
    var session = new Session
    {
        UserId = userId,
        Date = DateTime.UtcNow.Date,
        Name = programWorkout.WorkoutName,
        Type = programWorkout.WorkoutType ?? "Workout",
        Status = "draft",
        ProgramId = programWorkout.ProgramId,
        ProgramWorkoutId = programWorkout.Id,
        CreatedAt = DateTime.UtcNow
    };

    // Parse exercises from JSON and create Exercise records
    var exercisesData = JsonSerializer.Deserialize<List<ExerciseTemplate>>(
        programWorkout.ExercisesJson);

    foreach (var exerciseData in exercisesData)
    {
        var exercise = new Exercise
        {
            SessionId = session.Id,
            ExerciseTemplateId = exerciseData.Id,
            Name = exerciseData.Name,
            Sets = exerciseData.Sets,
            Reps = exerciseData.Reps,
            OrderIndex = exerciseData.OrderIndex
        };
        session.Exercises.Add(exercise);
    }

    _context.Sessions.Add(session);
    await _context.SaveChangesAsync();

    return CreatedAtAction(nameof(GetSession), new { id = session.Id }, session);
}
```

**Add DTO:**
```csharp
public class CreateSessionFromProgramWorkoutDto
{
    public int ProgramWorkoutId { get; set; }
}
```

**Update Session model:**
```csharp
public class Session
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public DateTime Date { get; set; }
    public int? Duration { get; set; }
    public string? Notes { get; set; }
    public string? Type { get; set; }
    public string? Name { get; set; }
    public string Status { get; set; }
    public DateTime? StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime? PausedAt { get; set; }

    // NEW FIELDS
    public int? ProgramId { get; set; }
    public int? ProgramWorkoutId { get; set; }

    // Navigation properties
    public User User { get; set; }
    public List<Exercise> Exercises { get; set; } = new();

    // NEW NAVIGATION PROPERTIES
    public Program? Program { get; set; }
    public ProgramWorkout? ProgramWorkout { get; set; }
}
```

---

### Flutter Changes

#### Step 1: Update Session Model
**File:** `lib/data/models/session.dart`

```dart
@JsonSerializable()
class Session {
  final int id;
  final int userId;
  final DateTime date;
  final int? duration;
  final String? notes;
  final String? type;
  final String? name;
  final String status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? pausedAt;
  final List<Exercise> exercises;

  // NEW FIELDS
  final int? programId;
  final int? programWorkoutId;

  Session({
    required this.id,
    required this.userId,
    required this.date,
    this.duration,
    this.notes,
    this.type,
    this.name,
    this.status = 'draft',
    this.startedAt,
    this.completedAt,
    this.pausedAt,
    this.exercises = const [],
    this.programId,           // NEW
    this.programWorkoutId,     // NEW
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    final session = _$SessionFromJson(json);
    return Session(
      id: session.id,
      userId: session.userId,
      date: session.date,
      duration: session.duration,
      notes: session.notes,
      type: session.type,
      name: session.name,
      status: session.status,
      startedAt: session.startedAt?.toUtc(),
      completedAt: session.completedAt?.toUtc(),
      pausedAt: session.pausedAt?.toUtc(),
      exercises: session.exercises,
      programId: session.programId,           // NEW
      programWorkoutId: session.programWorkoutId, // NEW
    );
  }

  Map<String, dynamic> toJson() => _$SessionToJson(this);

  /// Check if session is from a program
  bool get isFromProgram => programId != null;

  Session copyWith({
    int? id,
    int? userId,
    DateTime? date,
    int? duration,
    String? notes,
    String? type,
    String? name,
    String? status,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? pausedAt,
    List<Exercise>? exercises,
    int? programId,              // NEW
    int? programWorkoutId,        // NEW
  }) {
    return Session(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      duration: duration ?? this.duration,
      notes: notes ?? this.notes,
      type: type ?? this.type,
      name: name ?? this.name,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      pausedAt: pausedAt ?? this.pausedAt,
      exercises: exercises ?? this.exercises,
      programId: programId ?? this.programId,              // NEW
      programWorkoutId: programWorkoutId ?? this.programWorkoutId, // NEW
    );
  }
}
```

**Don't forget to run:** `flutter pub run build_runner build`

---

#### Step 2: Add Repository Method
**File:** `lib/data/repositories/session_repository.dart`

**Add new method:**
```dart
/// Create a session from a program workout
Future<Session> createSessionFromProgramWorkout(int programWorkoutId) async {
  final response = await _apiClient.post(
    ApiConfig.sessionsFromProgramWorkout,
    body: {'programWorkoutId': programWorkoutId},
  );

  return Session.fromJson(response);
}
```

**Add to ApiConfig:**
```dart
static String get sessionsFromProgramWorkout => '$baseUrl/sessions/from-program-workout';
```

---

#### Step 3: Update SessionsProvider
**File:** `lib/providers/sessions_provider.dart`

**Add new method:**
```dart
/// Create a session from a program workout
Future<Session?> startProgramWorkout(int programWorkoutId) async {
  try {
    _errorMessage = null;

    final session = await _sessionRepository.createSessionFromProgramWorkout(
      programWorkoutId,
    );

    _sessions.insert(0, session);
    notifyListeners();

    debugPrint('✅ Created session from program workout: ${session.id}');
    return session;
  } catch (e) {
    _errorMessage =
        'Failed to start program workout: ${e.toString().replaceAll('Exception: ', '')}';
    debugPrint('Start program workout error: $e');
    notifyListeners();
    return null;
  }
}

/// Get sessions from a specific program
List<Session> getSessionsFromProgram(int programId) {
  return _sessions.where((s) => s.programId == programId).toList();
}

/// Get standalone sessions (not from programs)
List<Session> getStandaloneSessions() {
  return _sessions.where((s) => s.programId == null).toList();
}
```

---

#### Step 4: Update ProgramWorkoutScreen
**File:** `lib/ui/screens/programs/program_workout_screen.dart`

**Replace the "Start Workout" button section (currently shows TODO):**

Find the button section (around line 392-409) and replace with:

```dart
// Action Buttons
if (!isCompleted) ...[
  const SizedBox(height: 16),
  Row(
    children: [
      Expanded(
        flex: 2,
        child: ElevatedButton.icon(
          onPressed: () async {
            // Create session from program workout
            final sessionsProvider = context.read<SessionsProvider>();
            final session = await sessionsProvider.startProgramWorkout(
              widget.workoutId,
            );

            if (session != null && mounted) {
              // Navigate to active workout screen
              await Navigator.pushNamed(
                context,
                RouteNames.activeWorkout,
                arguments: session.id,
              );

              // When returning, mark program workout as complete
              if (mounted) {
                final programsProvider = context.read<ProgramsProvider>();

                // Check if session was completed
                final completedSession = await sessionsProvider.getSessionById(
                  session.id,
                );

                if (completedSession.status == 'completed') {
                  // Mark program workout as complete
                  await programsProvider.completeWorkout(widget.workoutId);
                  await programsProvider.advanceProgram(widget.programId);

                  if (mounted) {
                    Navigator.pop(context);
                  }
                }
              }
            }
          },
          icon: const Icon(Icons.play_arrow, size: 20),
          label: const Text('Start Workout'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 1,
        child: OutlinedButton.icon(
          onPressed: () async {
            // Quick complete without doing the workout
            final shouldComplete = await _showQuickCompleteDialog(context);

            if (shouldComplete == true && mounted) {
              final provider = context.read<ProgramsProvider>();
              await provider.completeWorkout(widget.workoutId);
              await provider.advanceProgram(widget.programId);

              if (mounted) {
                Navigator.pop(context);
              }
            }
          },
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Skip'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    ],
  ),
],
```

**Add helper method:**
```dart
Future<bool?> _showQuickCompleteDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Skip Workout?'),
      content: const Text(
        'Mark this workout as complete without doing it? This will not create a workout session or track any data.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Skip'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
        ),
      ],
    ),
  );
}
```

---

#### Step 5: Add Program Badge to Session Cards
**File:** `lib/ui/widgets/sessions/session_card.dart`

**Add this after the workout name/type section:**

```dart
// Program badge (if session is from a program)
if (session.isFromProgram) ...[
  const SizedBox(height: 8),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.blue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Colors.blue.withValues(alpha: 0.3),
        width: 1,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.calendar_view_week, size: 14, color: Colors.blue),
        const SizedBox(width: 6),
        Text(
          'From Program',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.blue.shade700,
          ),
        ),
      ],
    ),
  ),
],
```

---

#### Step 6: Update Progress Card Logic
**File:** `lib/ui/widgets/sessions/weekly_progress_card.dart`

**No changes needed!** The progress card already counts all sessions, so program workout sessions will automatically be included.

---

### Testing Phase 3

#### Manual Testing Checklist
- [ ] Database migration runs successfully
- [ ] API endpoints work correctly
- [ ] Can create session from program workout
- [ ] Session has correct programId and programWorkoutId
- [ ] Exercises are copied from program workout
- [ ] Active workout screen works with program sessions
- [ ] Completing session marks ProgramWorkout as complete
- [ ] Program advances to next day after completion
- [ ] "From Program" badge shows on session cards
- [ ] Progress tracking includes program sessions
- [ ] Can filter sessions by program
- [ ] Standalone sessions still work correctly

#### Edge Cases to Test
- [ ] Delete program with linked sessions (sessions remain, programId becomes null)
- [ ] Delete session that's linked to program (program workout remains)
- [ ] Start same program workout twice
- [ ] Complete workout but skip program advancement
- [ ] Offline mode (creates session locally, syncs later)

#### Data Migration Testing
- [ ] Existing sessions have null programId (backward compatible)
- [ ] New sessions can have programId
- [ ] Queries work with both null and non-null programId
- [ ] Performance is acceptable with indexes

---

### Estimated Time: 16-24 hours
### Risk: ⚠️ Medium (database changes)
### Impact: 🚀 Major - Unified workout tracking

---

## Testing Strategy

### Unit Tests to Write
1. Session model serialization with programId
2. SessionsProvider filtering methods
3. ProgramsProvider weekly schedule logic
4. Session creation from program workout

### Integration Tests
1. Full flow: Start program workout → Complete session → Mark program complete
2. Progress tracking includes both standalone and program sessions
3. Offline sync with program-linked sessions

### Manual Testing
Follow checklists in each phase above.

---

## Rollback Plan

### Phase 1 Rollback
- Simple: Revert the file changes in `sessions_screen.dart`
- No data loss, no migrations

### Phase 2 Rollback
- Simple: Remove new widget files, revert `programs_screen.dart`
- No data loss, no migrations

### Phase 3 Rollback
- ⚠️ **Complex**: Requires database migration rollback
- **If no production data:** Drop columns
- **If production data exists:** Need data migration plan

**Recommendation:** Test Phase 3 thoroughly in staging environment first.

---

## Summary

| Phase | Time | Risk | Impact | Dependencies |
|-------|------|------|--------|--------------|
| **Phase 1: Remove Upcoming** | 1-2h | Low | Immediate | None |
| **Phase 2: Weekly Schedule** | 4-8h | Low | Significant | None |
| **Phase 3: Link Programs** | 16-24h | Medium | Major | Backend team |

**Total estimated time:** 21-34 hours

---

## Recommended Approach

1. ✅ **Phase 1 first** - Quick win, test user reaction
2. ✅ **Phase 2 next** - Builds on Phase 1, major UX improvement
3. ⏳ **Phase 3 later** - Requires backend coordination, plan carefully

---

**Status:** Ready for approval
**Next step:** Get user approval to proceed with Phase 1
**Created:** 2026-01-11
**Last updated:** 2026-01-11
