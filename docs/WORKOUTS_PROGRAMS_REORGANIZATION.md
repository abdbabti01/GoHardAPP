# Workouts & Programs Reorganization Plan

**Date:** 2026-01-11
**Status:** Planning Phase
**Purpose:** Document the recommended reorganization of "My Workouts" and "Programs" tabs

---

## Table of Contents
1. [Current State](#current-state)
2. [Problem Statement](#problem-statement)
3. [Data Model Analysis](#data-model-analysis)
4. [Recommended Organization](#recommended-organization)
5. [Implementation Plan](#implementation-plan)
6. [Files to Modify](#files-to-modify)

---

## Current State

### My Workouts Tab
**Location:** `lib/ui/screens/sessions/sessions_screen.dart` (lines 547-873)

**Currently displays:**
- ✅ Weekly/Monthly Progress Card
- ✅ TODAY section (active + completed workouts)
- ⚠️ UPCOMING section (planned sessions - **CONFUSING**)
- ✅ THIS WEEK section (Monday-yesterday)
- ✅ PAST WORKOUTS section (with filter: Last Week/Month/3M/6M/12M)

**Floating Action Button:** "New Workout" (Start Now or Plan Later)

### Programs Tab
**Location:** `lib/ui/screens/programs/programs_screen.dart`

**Currently displays:**
- ✅ ACTIVE PROGRAMS section
- ✅ COMPLETED PROGRAMS section
- Program cards showing:
  - Title, description
  - Week X of Y progress
  - Current phase (Foundation/Progressive Overload/Peak Performance)
  - Today's workout from program
  - Progress percentage
  - Start/View buttons

---

## Problem Statement

### The Confusion
The "My Workouts" tab currently shows an "UPCOMING" section that mixes:
1. Standalone planned workouts (user manually scheduled)
2. Workouts from active programs
3. No clear distinction between the two

**User confusion:**
- Is "Push Day" in Upcoming a one-off workout or part of my 12-week program?
- Where do I see my program's weekly schedule?
- Should I plan workouts in My Workouts or follow Programs?

---

## Data Model Analysis

### Session (Individual Workout)
**Model:** `lib/data/models/session.dart`

```dart
class Session {
  int id;
  String name;           // e.g., "Push Day", "Morning Cardio"
  DateTime date;
  String status;         // draft, in_progress, completed, planned
  int? duration;         // Actual duration in minutes
  List<Exercise> exercises;
  DateTime? startedAt;
  DateTime? completedAt;
  DateTime? pausedAt;
}
```

**Characteristics:**
- ONE-TIME workout instance
- Ad-hoc or individually planned
- Has actual execution data (timer, completed sets)
- Flexible, spontaneous
- Optional link to goal

**Use cases:**
- "I want to do a quick arm workout now"
- "I'll do cardio tomorrow morning"
- One-off planned sessions

---

### Program (Training Plan)
**Model:** `lib/data/models/program.dart`

```dart
class Program {
  int id;
  String title;          // e.g., "12-Week Muscle Building"
  int totalWeeks;        // 12
  int currentWeek;       // 5
  int currentDay;        // 3
  DateTime startDate;
  DateTime? endDate;
  bool isActive;
  bool isCompleted;
  List<ProgramWorkout> workouts;  // ~84 workouts (12 weeks × 7 days)
  int? goalId;           // Always linked to a goal
}
```

**Characteristics:**
- STRUCTURED multi-week plan
- AI-generated or predefined template
- Has progression phases
- Always linked to fitness goal
- Tracks % completion through entire program
- Contains predefined workouts for each day/week

**Use cases:**
- "I want to gain 10 lbs of muscle in 12 weeks"
- "Follow a structured strength program"
- "AI generate a workout plan for my goal"

---

## Recommended Organization

### Option 1: Separate by Structure (RECOMMENDED) ⭐

#### MY WORKOUTS Tab
**Purpose:** Gym log + Quick flexible workouts

**Should contain:**
```
┌─────────────────────────────────┐
│ 📊 PROGRESS SUMMARY             │
│ This Week: 3/5 | Month: 12/20   │
├─────────────────────────────────┤
│ 📅 TODAY                        │
│ • Active workout (if running)   │
│ • Completed today               │
├─────────────────────────────────┤
│ 📆 THIS WEEK                    │
│ Monday - Today's workouts       │
├─────────────────────────────────┤
│ 📜 PAST WORKOUTS [Filter ▼]    │
│ • Historical log                │
│ • Grouped by week               │
└─────────────────────────────────┘

[+ New Workout] ← Quick start or plan one-off
```

**NOTE:** "Upcoming" section REMOVED per user decision - reduces confusion since program workouts don't create Sessions.

**Key principles:**
- Focus on INDIVIDUAL workouts
- Show workout HISTORY (log/journal)
- Quick access to START now
- Flexible, ad-hoc workouts

---

#### PROGRAMS Tab
**Purpose:** Follow structured training plans

**Should contain:**
```
┌─────────────────────────────────┐
│ 🎯 ACTIVE PROGRAMS              │
│ ┌─────────────────────────────┐ │
│ │ 12-Week Muscle Building     │ │
│ │ Week 5/12 • Phase 2         │ │
│ │ ━━━━━━━━━░░░░░░ 41%         │ │
│ │                             │ │
│ │ 📅 THIS WEEK'S SCHEDULE:    │ │
│ │ Mon: Upper Power ✓          │ │
│ │ Tue: Lower Power ✓          │ │
│ │ Wed: Rest                   │ │
│ │ Thu: Upper Hypertrophy  ← 📍│ │
│ │ Fri: Lower Hypertrophy      │ │
│ │ Sat: Full Body              │ │
│ │ Sun: Rest                   │ │
│ │                             │ │
│ │ [Start Today's Workout]     │ │
│ │ [View Full Program]         │ │
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│ 💡 RECOMMENDED PROGRAMS         │
│ • AI-generated from goals       │
│ • Pre-made templates            │
├─────────────────────────────────┤
│ ✅ COMPLETED PROGRAMS           │
│ • 8-Week Fat Loss ✓             │
│ • Beginner Strength ✓           │
└─────────────────────────────────┘

[+ Generate from Goal] ← AI create program
```

**Key principles:**
- Focus on STRUCTURED plans
- Show WEEKLY SCHEDULE
- Track PROGRESSION (phases, weeks)
- Always linked to GOALS

---

### Key Differences Table

| Aspect | My Workouts | Programs |
|--------|-------------|----------|
| **Type** | Individual sessions | Structured plans |
| **Creation** | Ad-hoc, spontaneous | Planned, goal-driven |
| **Timeline** | One-time | Multi-week progression |
| **Flexibility** | Very flexible | Follow the plan |
| **Link to Goal** | Optional | Always linked |
| **Progression** | No structure | Phases, periodization |
| **Planning** | Quick/same-day | Long-term (weeks/months) |
| **Examples** | "Quick arm workout" | "12-Week Bulk Program" |

---

## Implementation Plan

### Phase 1: Analysis & Design ✅
- [x] Analyze current implementation
- [x] Identify confusion points
- [x] Design recommended structure
- [x] Document in this file

### Phase 2: My Workouts Tab Cleanup
**Goal:** Make it purely about individual workout logging

**Changes needed:**
1. **REMOVE "Upcoming" section entirely** (`sessions_screen.dart` lines 774-824) ✅ USER DECISION
   - Remove `_isPlannedExpanded` state variable (line 28-29)
   - Remove `_expandedWorkoutGroups` map (line 31-32)
   - Remove `plannedSessions` filter logic (lines 688-691)
   - Remove entire "Upcoming" section rendering (lines 774-824)
   - Remove `_groupPlannedSessionsByName()` method (lines 283-302)
   - Remove `_buildWorkoutNameSubheader()` method (lines 305-360)
   - Remove collapsible section header logic from `_buildSectionHeader()` (lines 452-508)

   **Rationale:** Program workouts don't create Sessions, so "Upcoming" only shows standalone planned workouts which is confusing. Users can plan workouts from Programs tab instead.

2. **Improve Progress Card** (already good, keep it)
   - Should show ALL workouts (program + standalone)
   - Current implementation is correct

3. **Add clarifying text**
   - Empty state: "Quick workouts and your workout log"
   - Section headers: Make it clear these are individual sessions

### Phase 3: Programs Tab Enhancement
**Goal:** Make it the command center for structured training

**Changes needed:**
1. **Add "This Week's Schedule" view**
   - Show 7-day calendar for active program
   - Highlight current day
   - Show checkmarks for completed days
   - Show rest days

2. **Improve "Today's Workout" section**
   - Make it prominent
   - Show preview of exercises
   - One-tap to start

3. **Add "Recommended Programs" section**
   - Show AI-generated programs from goals
   - Show template programs
   - One-tap to activate

4. **Add calendar/timeline view**
   - Visual representation of program progression
   - Week-by-week view
   - Phase indicators

### Phase 4: Data Layer Updates

**Check if needed:**
- Is there a link between Session and Program?
- Can we filter sessions by `programId`?
- How to distinguish program workouts from standalone?

**Possible solution:**
```dart
class Session {
  // ... existing fields
  int? programId;        // Link to program if workout is from a program
  int? programWeek;      // Which week of program
  int? programDay;       // Which day of program week
}
```

### Phase 5: Testing & Validation
- [ ] Test creating standalone workout
- [ ] Test following program workout
- [ ] Verify filtering works correctly
- [ ] Test edge cases (no programs, no workouts, etc.)
- [ ] User feedback session

---

## Files to Modify

### Primary Files
1. **`lib/ui/screens/sessions/sessions_screen.dart`**
   - Lines 688-691: Filter plannedSessions logic
   - Lines 774-824: Upcoming section rendering
   - Add logic to exclude program workouts from "Upcoming"

2. **`lib/ui/screens/programs/programs_screen.dart`**
   - Add "This Week's Schedule" widget
   - Add "Recommended Programs" section
   - Enhance program cards with weekly view

### Supporting Files
3. **`lib/data/models/session.dart`**
   - Consider adding `programId`, `programWeek`, `programDay` fields
   - Add helper: `bool get isFromProgram => programId != null;`

4. **`lib/providers/sessions_provider.dart`**
   - Add method: `List<Session> getStandalonePlannedSessions()`
   - Add method: `List<Session> getProgramSessions(int programId)`

5. **`lib/providers/programs_provider.dart`**
   - Add method: `List<ProgramWorkout> getThisWeekSchedule(Program program)`
   - Add method: `ProgramWorkout? getTodaysWorkout(Program program)`

### New Widgets to Create
6. **`lib/ui/widgets/programs/weekly_schedule_widget.dart`**
   - Display 7-day calendar for program
   - Show current day, completed days, rest days

7. **`lib/ui/widgets/programs/program_timeline_widget.dart`**
   - Visual timeline of program progression
   - Phase indicators

---

## API Considerations

### Check if API supports:
- [ ] Filtering sessions by programId
- [ ] Getting program's weekly schedule
- [ ] Linking sessions to programs

### Potential API changes needed:
```csharp
// SessionsController.cs
GET /api/sessions?programId={id}  // Get sessions from specific program
GET /api/sessions?standalone=true  // Get only standalone sessions

// ProgramsController.cs
GET /api/programs/{id}/week/{weekNumber}  // Get specific week
GET /api/programs/{id}/today  // Get today's workout
```

---

## User Stories

### My Workouts Tab
1. "I want to see what I did today" → TODAY section
2. "I want to log a quick workout now" → [+ New Workout] → Start Now
3. "I want to plan a workout for Friday" → [+ New Workout] → Plan Later
4. "I want to see my workout history" → PAST WORKOUTS
5. "I want to see this week's activity" → THIS WEEK

### Programs Tab
1. "I want to follow my 12-week program" → ACTIVE PROGRAMS → View schedule
2. "I want to do today's program workout" → Start Today's Workout
3. "I want to see what's coming this week" → THIS WEEK'S SCHEDULE
4. "I want to start a new program for my goal" → [+ Generate from Goal]
5. "I want to see how far I've progressed" → Progress bar, Week 5/12

---

## Design Principles

### My Workouts
- **Flexibility first** - Quick access, ad-hoc workouts
- **Log/journal focus** - Emphasize history and tracking
- **Minimal planning** - Light scheduling for one-offs
- **Fast execution** - Start workout in 2 taps

### Programs
- **Structure first** - Follow the plan
- **Goal-oriented** - Always linked to achieving something
- **Long-term view** - See weeks ahead
- **Progression tracking** - Phases, milestones, completion

---

## Questions to Resolve

1. **Should program workouts appear in My Workouts history?** ❌ RESOLVED
   - ❌ NO - Currently program workouts do NOT create Session records
   - ProgramWorkout and Session are completely separate systems
   - Program workouts are tracked in ProgramWorkout table (isCompleted flag)
   - Standalone workouts are tracked in Session table
   - **Future improvement:** Link them by adding programId to Session model

2. **Can users edit/skip program workouts?**
   - Need to define flexibility rules
   - What happens if user skips a day?

3. **What if user has NO active programs?**
   - Show empty state with CTA to create from goal
   - Show recommended/template programs

4. **Remove "Upcoming" section from My Workouts?** ✅ RESOLVED
   - ✅ YES - User decision to remove it
   - Reduces confusion since it only showed standalone planned Sessions
   - Users will plan/schedule workouts from Programs tab instead

---

## Next Steps for Implementation

### Immediate Actions (Phase 2)
1. Read `lib/providers/sessions_provider.dart` to understand session filtering
2. Check if sessions have `programId` field (likely not yet)
3. Decide: Add `programId` to Session model OR use separate logic
4. Modify "Upcoming" section to filter out program workouts
5. Test the changes

### Future Enhancements (Phase 3+)
1. Design weekly schedule widget for Programs tab
2. Add calendar view to Programs
3. Implement program templates browser
4. Add "Generate from Goal" flow

---

## Notes for Future Claude Instances

### Context for This Analysis
- User reported confusion between "My Workouts" and "Programs" tabs
- Both tabs show workout-related content but serve different purposes
- Current "Upcoming" section in My Workouts is the main confusion point

### Key Insight
**The fundamental distinction:**
- **Session** = Individual workout instance (one-time)
- **Program** = Multi-week structured plan (ongoing)

### Decision Made
Use **Option 1: Separate by Structure**
- My Workouts = Gym log + Ad-hoc workouts
- Programs = Structured training plans

### Before Making Changes
1. Read this entire document
2. Review the current implementation in `sessions_screen.dart`
3. Check if `Session` model has `programId` field
4. Understand the data flow: Provider → Repository → API

### When in Doubt
- Ask user for clarification on edge cases
- Test thoroughly before committing
- Document any new decisions in this file

---

**Last Updated:** 2026-01-11
**Author:** Claude Sonnet 4.5
**Status:** Awaiting user approval to proceed with implementation
