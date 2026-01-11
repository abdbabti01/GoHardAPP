# Backend Date Fix for Program Workouts

## Problem
When creating a program, the first workout's `dayName` shows "Monday" even if the actual scheduled date is a different day (e.g., Thursday).

## Example
```
User creates program on Thursday, January 9, 2025
startDate = 2025-01-09 (Thursday)

Workout 1:
  dayName = "Monday" ❌ (WRONG - should be "Thursday")
  weekNumber = 1
  dayNumber = 1
  Scheduled for 2025-01-09 (Thursday) ✓
  Shows as "TODAY" ✓
```

## Root Cause
Backend is calculating `dayName` from `dayNumber` position, not from the actual scheduled calendar date.

**Current (WRONG) Logic:**
```csharp
// Sets dayName based on position in week (1=Monday, 2=Tuesday, etc.)
workout.DayName = GetDayName(dayNumber); // dayNumber=1 → "Monday"
```

## Required Fix
Calculate `dayName` from the actual calendar date:

```csharp
// CORRECT APPROACH:
DateTime workoutDate = program.StartDate.AddDays((weekNumber - 1) * 7 + (dayNumber - 1));
workout.DayName = workoutDate.DayOfWeek.ToString(); // → "Thursday"
```

## Files to Check (Backend)
Look for program creation logic, specifically where `ProgramWorkout` entities are created:
- Program creation endpoint (`POST /api/programs`)
- Chat workout plan to program conversion (`POST /api/chat/{id}/create-program`)
- Anywhere `ProgramWorkout.DayName` is set

## Testing
After fix, verify:
1. Create program starting on Thursday
2. First workout should have:
   - `dayName = "Thursday"` ✓
   - `dayNumber = 1` ✓
   - `weekNumber = 1` ✓
3. Second workout (next day):
   - `dayName = "Friday"` ✓
   - `dayNumber = 2` ✓
   - `weekNumber = 1` ✓

## Frontend Changes (Already Implemented)
The frontend now uses **true calendar-sync** and expects:
- `dayName` to match the actual calendar date
- Program progression based on real calendar dates (DateTime.now())
- No manual "advance" needed - auto-syncs with calendar
