# Workout Flow Analysis - Issues Found

Complete analysis of all three workout creation scenarios with identified bugs and UX issues.

---

## SCENARIO 1: Standalone Workout (Start Now) ✅

### Flow:
1. User taps "New Workout" FAB → WorkoutOptionsSheet
2. User taps "Start Now" → WorkoutNameDialog
3. Session created with `status: 'draft'`
4. Navigate to ActiveWorkoutScreen automatically
5. User adds exercises, taps "Start Workout" button
6. Timer starts, status → `in_progress`
7. User completes workout → status → `completed`
8. Returns to Sessions screen, appears in "Today" section

### Issues Found: **NONE** ✅
This flow is clean and logical.

---

## SCENARIO 2: Planned Workout (Plan Later) ⚠️

### Flow:
1. User taps "New Workout" FAB → WorkoutOptionsSheet
2. User taps "Plan Later" → PlannedWorkoutFormScreen
3. User fills form (date, name, type, duration, notes)
4. Session created with `status: 'planned'`
5. Returns to Sessions screen, appears in "Upcoming Workouts" section
6. Later, user taps planned workout card
7. Dialog asks: "Do you want to start this planned workout now?"
8. User confirms → `startPlannedWorkout()` called
9. Status changes: `planned` → `in_progress`
10. Navigates to ActiveWorkoutScreen

### Issue #1: Status Transition Bug (MEDIUM PRIORITY)

**Location**: `sessions_provider.dart:157-160` (startPlannedWorkout method)

**Problem**:
When user confirms "Start Workout" dialog for a planned workout:
- Session status changes from `planned` → `in_progress`
- But `startedAt` timestamp is NOT set
- Timer remains at 00:00:00

**What Happens in UI**:
1. ActiveWorkoutScreen loads with status = `in_progress` but `startedAt = null`
2. Timer doesn't auto-start
3. UI checks `isDraft` (line 279 in active_workout_screen.dart)
4. `isDraft = (status == 'draft')` → false (status is 'in_progress')
5. "Start Workout" button hidden (only shows if isDraft)
6. "Resume" button shown instead (line 337-355)
7. User clicks "Resume" but it doesn't work properly (expects startedAt to exist)

**Root Cause**:
```dart
// sessions_provider.dart:154-160
Future<bool> startPlannedWorkout(int sessionId) async {
  try {
    // This only changes status, doesn't start timer!
    final updatedSession = await _sessionRepository.updateSessionStatus(
      sessionId,
      'in_progress',  // ❌ Status set but no startedAt timestamp
    );
    // ...
  }
}
```

**Expected Behavior**:
Option A: Keep status as `'draft'` instead of `'in_progress'` (let user manually start timer)
Option B: Set `startedAt` timestamp when changing to `'in_progress'` to actually start the timer

**Fix Needed**:
```dart
// Option A (Recommended):
final updatedSession = await _sessionRepository.updateSessionStatus(
  sessionId,
  'draft',  // ✅ User will manually tap "Start Workout" button
);

// OR Option B:
// Update repository to set startedAt when changing to in_progress
final updatedSession = await _sessionRepository.startSession(sessionId);
// (This would need a new repository method)
```

---

## SCENARIO 3: Program Workout ❌

### Flow:
1. User sees program in Programs tab
2. User taps workout card → ProgramWorkoutScreen
3. User sees workout details (exercises, sets, reps, duration)
4. User taps "Start Workout" button
5. Confirmation dialog: "Add to My Workouts?"
6. User confirms "Add & Start"
7. `startProgramWorkout()` called → creates session from API
8. Session created with `status: 'draft'`, `programId`, and `programWorkoutId` set
9. **Navigate to Sessions screen** (NOT ActiveWorkoutScreen)
10. Success message: "[workout name] added to My Workouts!"
11. User must manually tap session card in "Today" section
12. User must manually tap "Start Workout" button to begin

### Issue #2: Misleading Button Text (HIGH PRIORITY)

**Location**: `program_workout_screen.dart:299`

**Problem**:
Button says **"Add & Start"** but it does NOT start the workout.

**Current Behavior**:
1. User clicks "Add & Start" (expecting workout to start)
2. Session created as `draft` status
3. Navigates to Sessions screen
4. User must tap session card **again**
5. User must tap "Start Workout" button **again**
6. Requires **2 additional taps** after clicking "Add & Start"

**User Confusion**:
User expects workout to start immediately after clicking a button that says "& Start".

**Fix Options**:

**Option A (Recommended)**: Change button text to remove "& Start"
```dart
ElevatedButton(
  onPressed: () => Navigator.pop(context, true),
  child: const Text('Add to My Workouts'),  // ✅ Accurate text
),
```

**Option B**: Actually start the workout after adding
```dart
if (session != null && mounted) {
  // Navigate to ActiveWorkoutScreen instead of Sessions
  navigator.pushNamed(
    RouteNames.activeWorkout,
    arguments: session.id,  // ✅ Start workout
  );
  messenger.showSnackBar(...);
}
```

---

### Issue #3: Navigation Inconsistency (MEDIUM PRIORITY)

**Location**: `program_workout_screen.dart:313`

**Problem**:
Inconsistent navigation after creating workout sessions.

**Comparison**:

| Scenario | After Creation | Navigates To | Makes Sense? |
|----------|----------------|--------------|--------------|
| Start Now | Draft session | ActiveWorkoutScreen | ✅ Yes |
| Plan Later | Planned session | Sessions screen | ✅ Yes (it's for later) |
| **Program** | **Draft session** | **Sessions screen** | ❌ No (button says "& Start") |

**Fix**: Match navigation to button text:
- If button says "Add to My Workouts" → Navigate to Sessions screen ✅
- If button says "Add & Start" → Navigate to ActiveWorkoutScreen ✅

**Current Code**:
```dart
// program_workout_screen.dart:313
navigator.pushNamed(RouteNames.sessions);  // ❌ Inconsistent
```

**Recommended Fix** (matches Option A above):
```dart
// Keep navigation to Sessions, fix button text
child: const Text('Add to My Workouts'),
```

---

### Issue #4: Offline Limitation (LOW - By Design)

**Location**: `session_repository.dart:432-434`

**Problem**:
Cannot create program workout sessions while offline.

**Error Message**:
"Cannot create program workout session while offline. Please connect to the internet."

**Why**:
Server needs to copy exercises from program workout template to new session.

**Current Code**:
```dart
// session_repository.dart:431-435
} else {
  throw Exception(
    'Cannot create program workout session while offline. Please connect to the internet.',
  );
}
```

**Impact**:
User cannot start program workouts offline, even if program was previously synced.

**Recommendation**:
This might be acceptable if documented clearly in UI. Could be improved by:
1. Caching program workout templates with exercises locally
2. Implementing exercise copying in repository
3. Creating session offline with pending sync

**Not a bug**, but a limitation worth noting.

---

### Issue #5: Session Not Cleaned Up After Skip (MINOR)

**Location**: `program_workout_screen.dart:569-640` (Skip button dialog)

**Problem**:
Edge case where session remains orphaned.

**Scenario**:
1. User taps "Start Workout" → Creates draft session
2. User closes confirmation dialog (Cancel)
3. User decides not to do workout
4. User taps "Skip" button to mark program workout complete
5. Program workout marked complete in program context
6. **But draft session still exists in "My Workouts"**

**Current Flow**:
- "Skip" button calls `ProgramsProvider.completeWorkout()` (line 609)
- This marks ProgramWorkout as completed
- Does NOT check for or clean up associated session

**Fix Needed**:
When skipping program workout, check if session exists and either:
- Delete the draft session, OR
- Mark it as completed with zero duration

---

## SUMMARY OF CRITICAL ISSUES

### High Priority (Fix Immediately):
1. **Issue #2**: Change "Add & Start" button text to "Add to My Workouts"

### Medium Priority (Fix Soon):
2. **Issue #1**: Fix planned workout status transition (keep as 'draft' instead of 'in_progress')
3. **Issue #3**: Make navigation consistent (Sessions screen is fine if button text fixed)

### Low Priority (Nice to Have):
4. **Issue #4**: Document offline limitation or add offline support for program workouts
5. **Issue #5**: Clean up orphaned sessions when skipping program workouts

---

## RECOMMENDED FIXES

### Quick Win (5 minutes):
Change button text in program_workout_screen.dart:
```dart
// Line 299
child: const Text('Add to My Workouts'),  // Remove "& Start"
```

### Planned Workout Fix (10 minutes):
Change status in sessions_provider.dart:
```dart
// Line 157-160
final updatedSession = await _sessionRepository.updateSessionStatus(
  sessionId,
  'draft',  // Changed from 'in_progress'
);
```

---

## STATUS TRANSITION REFERENCE

### Correct Flow for All Scenarios:

| Status | Meaning | Timer State | User Action |
|--------|---------|-------------|-------------|
| `draft` | Created but not started | Stopped (00:00:00) | Can tap "Start Workout" |
| `in_progress` | Actively working out | Running | Can tap "Pause/Resume/Finish" |
| `planned` | Scheduled for future | N/A | Can tap to convert to draft |
| `completed` | Finished | Stopped (final time) | Read-only |

### Current Issues:
- ✅ Standalone: draft → in_progress → completed (CORRECT)
- ❌ Planned: planned → **in_progress (no timer)** → completed (BROKEN)
- ✅ Program: draft → in_progress → completed (CORRECT, but UX confusing)
