# Backend Fix Required: Program Workout Tracking

## Problem

When creating a session from a program workout using the `POST /api/sessions/from-program-workout` endpoint, the response should include both `programId` and `programWorkoutId` fields, but these are currently missing or not being set.

This causes sessions created from program workouts to NOT be marked as "From Program" in the UI.

## Current Behavior

1. User clicks workout in a program
2. Frontend calls `POST /api/sessions/from-program-workout` with `{ "programWorkoutId": 123 }`
3. Backend creates session and copies exercises from program workout
4. Backend returns session object, but `programId` and `programWorkoutId` are null/missing
5. UI doesn't show "From Program" badge because `session.isFromProgram` returns false

## Expected Behavior

1. User clicks workout in a program
2. Frontend calls `POST /api/sessions/from-program-workout` with `{ "programWorkoutId": 123 }`
3. Backend creates session and copies exercises from program workout
4. **Backend sets `programId` and `programWorkoutId` on the session**
5. Backend returns session with `programId` and `programWorkoutId` populated
6. UI shows "From Program" badge because `session.isFromProgram` returns true

## Required Backend Changes

### In the SessionsController or Sessions endpoint:

```csharp
[HttpPost("from-program-workout")]
public async Task<IActionResult> CreateSessionFromProgramWorkout([FromBody] CreateSessionFromProgramWorkoutDto dto)
{
    var userId = GetCurrentUserId(); // Get from JWT token

    // 1. Get the program workout
    var programWorkout = await _context.ProgramWorkouts
        .Include(pw => pw.Program)
        .FirstOrDefaultAsync(pw => pw.Id == dto.ProgramWorkoutId);

    if (programWorkout == null)
    {
        return NotFound("Program workout not found");
    }

    // 2. Create session with program tracking
    var session = new Session
    {
        UserId = userId,
        Date = DateTime.UtcNow.Date, // Or use programWorkout.ScheduledDate
        Status = "draft",
        Name = programWorkout.WorkoutName,
        Type = programWorkout.WorkoutType,
        ProgramId = programWorkout.ProgramId,         // ← SET THIS
        ProgramWorkoutId = programWorkout.Id,         // ← SET THIS
        CreatedAt = DateTime.UtcNow
    };

    _context.Sessions.Add(session);
    await _context.SaveChangesAsync();

    // 3. Copy exercises from program workout to session
    // ... (existing exercise copying logic) ...

    // 4. Return session with programId and programWorkoutId included
    return Ok(session);
}
```

## Testing

After fix, verify:

1. Create a session from a program workout
2. Check the API response includes:
   ```json
   {
     "id": 123,
     "programId": 5,
     "programWorkoutId": 42,
     ...
   }
   ```
3. UI should show blue "From Program" badge on the session card
4. Filtering by program should work correctly

## Frontend Already Supports This

The frontend already has full support:

- `Session` model has `programId` and `programWorkoutId` fields
- `session.isFromProgram` getter checks if `programId != null`
- `SessionCard` widget displays "From Program" badge when `session.isFromProgram` is true
- Can filter sessions by program using `getSessionsFromProgram(programId)`

**No frontend changes needed - only backend fix required.**
