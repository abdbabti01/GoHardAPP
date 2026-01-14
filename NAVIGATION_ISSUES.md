# UI Navigation Issues - GoHard App

**Date**: 2026-01-13
**Status**: Identified, awaiting fixes
**Priority**: CRITICAL - Multiple navigation flows are broken

---

## 🔴 CRITICAL ISSUES (Fix Immediately)

### **Issue #1: "Start Workout" Button Doesn't Actually Start Workout**

**Location**: `lib/ui/screens/programs/program_workout_screen.dart:320`

**Current Code**:
```dart
// Line 301-332
ElevatedButton(
  onPressed: () => Navigator.pop(context, true),
  child: const Text('Add & Start'),  // ❌ Button text is misleading
),

// Line 318-332
if (session != null && mounted) {
  // Navigate to My Workouts (Sessions screen)
  navigator.pushNamed(RouteNames.sessions);  // ❌ WRONG! Should go to ActiveWorkoutScreen

  // Show success message
  messenger.showSnackBar(
    SnackBar(
      content: Text('${workout.workoutName} added to My Workouts!'),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 2),
    ),
  );
}
```

**Problem**:
- Button says "Add & Start" implying the workout will start immediately
- Actually just navigates to the Sessions screen (workout list)
- User has to find the workout and manually start it again

**User Flow (Current - BROKEN)**:
1. Programs → View Workout → Click "Start Workout" (which says "Add & Start")
2. Lands on Sessions screen showing workout list
3. User confused: "Where's my workout? I thought I started it?"
4. User must manually find and click the workout again to actually start it

**Expected Behavior**:
- Clicking "Start Workout" should immediately start the workout with timer running
- User should land on `ActiveWorkoutScreen` with the workout already in progress

**Fix Options**:

**Option A (Recommended)**: Navigate to ActiveWorkoutScreen
```dart
// Line 318-332 - Replace navigator.pushNamed(RouteNames.sessions) with:
navigator.pushNamed(
  RouteNames.activeWorkout,
  arguments: session.id,
);

// Update success message
messenger.showSnackBar(
  SnackBar(
    content: Text('${workout.workoutName} started!'),
    backgroundColor: Colors.green,
    duration: const Duration(seconds: 2),
  ),
);
```

**Option B**: Change button text to be accurate
```dart
// Line 301
child: const Text('Add to My Workouts'),  // ✅ Accurate, but less useful
```

**Recommended**: Option A - Fix the navigation to match user expectation

**Priority**: 🔴 CRITICAL - This is a major UX bug that breaks the primary user flow

---

### **Issue #2: Can't Navigate Back After Creating Program from AI**

**Location**: `lib/ui/screens/chat/chat_conversation_screen.dart:151-155`

**Current Code**:
```dart
// Navigate directly to the created program detail screen
if (mounted) {
  navigator.pushNamedAndRemoveUntil(
    RouteNames.programDetail,
    (route) => route.isFirst, // ❌ Clears entire navigation stack except main screen
    arguments: programId,
  );

  // Show success message
  scaffoldMessenger.showSnackBar(
    SnackBar(
      content: Text('Created program "$programTitle" with $workoutCount workouts!'),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 3),
    ),
  );
}
```

**Problem**:
- Uses `pushNamedAndRemoveUntil` with `(route) => route.isFirst`
- This removes ALL screens from navigation stack except the first (main screen)
- User loses all navigation history and context
- Back button goes to main screen, not previous screen

**Navigation Stack**:
```
Before program creation:
Main Screen → Goals Screen → Chat Screen → (creating program)

After program creation (CURRENT - BROKEN):
Main Screen → Program Detail Screen
              ❌ Lost: Goals Screen, Chat Screen

User presses back → Goes to Main Screen (unexpected)
```

**Expected Behavior**:
- Back button should have reasonable behavior
- User should be able to navigate back through their history
- At minimum, should go back to Goals screen (where they started)

**Fix Options**:

**Option A (Recommended)**: Use regular pushNamed (preserve stack)
```dart
navigator.pushNamed(
  RouteNames.programDetail,
  arguments: programId,
);
// Navigation stack: Main → Goals → Chat → Program Detail ✅
// Back button: Program Detail → Chat → Goals → Main ✅
```

**Option B**: Navigate to main screen with specific tab, then to program detail
```dart
navigator.pushNamedAndRemoveUntil(
  RouteNames.main,
  (route) => false,  // Clear everything
  arguments: {'tab': 0, 'subTab': 1},  // Programs tab
);
// Then user can find their program in the list
```

**Option C**: Pop to main, then push program detail
```dart
navigator.popUntil((route) => route.isFirst);
navigator.pushNamed(RouteNames.programDetail, arguments: programId);
// Navigation stack: Main → Program Detail
// Back button: Program Detail → Main (cleaner, but still loses history)
```

**Recommended**: Option A - Preserve navigation history

**Priority**: 🔴 CRITICAL - Breaks expected back button behavior

---

### **Issue #3: "View Programs" Creates Duplicate Main Screen**

**Location**: `lib/ui/screens/goals/goals_screen.dart:520-527`

**Current Code**:
```dart
InkWell(
  onTap: () {
    // Navigate to Programs tab (Workouts tab index 0, sub-tab index 1)
    Navigator.pushNamed(
      context,
      RouteNames.main,  // ❌ Pushes ANOTHER main screen on top
      arguments: {
        'tab': 0, // Workouts tab
        'subTab': 1, // Programs sub-tab
      },
    ).then((_) {
      // Optional: could add logic to filter programs by this goal
    });
  },
  // ... "View Programs" badge UI
)
```

**Problem**:
- User is already on the Main Screen (Goals tab)
- Clicking "View Programs" pushes ANOTHER Main Screen on top
- Creates duplicate Main Screens in navigation stack
- Back button behavior becomes confusing

**Navigation Stack (BROKEN)**:
```
Main Screen (Goals tab selected)
  → Main Screen (Programs tab selected)  ❌ DUPLICATE!
    → Back button goes to Goals tab on a different Main Screen instance
```

**Expected Behavior**:
- Should switch to Programs tab on the SAME Main Screen
- Should not create duplicate Main Screen instances
- Back button should work normally

**Fix Options**:

**Option A (Recommended)**: Use event/callback to switch tabs
```dart
// Add this to main_screen.dart
class MainScreenState extends State<MainScreen> {
  // Add a method to switch tabs
  void switchToTab(int tabIndex, {int? subTabIndex}) {
    setState(() {
      _currentIndex = tabIndex;
      // If subTab switching logic exists, trigger it here
    });
  }
}

// In goals_screen.dart, use callback or event bus instead of navigation
onTap: () {
  // Option 1: Pop back to main and use callback
  Navigator.pop(context);
  // Trigger tab switch via parent callback or event

  // Option 2: Use a tab navigation service (see Option C)
}
```

**Option B**: Replace Main Screen instead of pushing
```dart
Navigator.pushReplacementNamed(
  context,
  RouteNames.main,
  arguments: {'tab': 0, 'subTab': 1},
);
// Still not ideal, but at least no duplicate screens
```

**Option C**: Create TabNavigationService (Best long-term solution)
```dart
// Create lib/core/services/tab_navigation_service.dart
class TabNavigationService extends ChangeNotifier {
  int _currentTab = 0;
  int? _currentSubTab;

  int get currentTab => _currentTab;
  int? get currentSubTab => _currentSubTab;

  void switchTab(int tabIndex, {int? subTabIndex}) {
    _currentTab = tabIndex;
    _currentSubTab = subTabIndex;
    notifyListeners();
  }
}

// Register in main.dart providers
ChangeNotifierProvider(create: (_) => TabNavigationService()),

// Use in MainScreen
final tabService = context.watch<TabNavigationService>();
_currentIndex = tabService.currentTab;

// Use in goals_screen.dart
onTap: () {
  context.read<TabNavigationService>().switchTab(0, subTabIndex: 1);
  Navigator.pop(context);  // Go back to main screen (which will show Programs tab)
}
```

**Recommended**: Option C for long-term fix, Option A as quick fix

**Priority**: 🔴 CRITICAL - Creates broken navigation stacks

---

## ⚠️ MODERATE ISSUES

### **Issue #4: Inconsistent Tab Switching from Program Detail**

**Location**: `lib/ui/screens/programs/program_detail_screen.dart:264-269`

**Current Code**:
```dart
InkWell(
  onTap: () {
    // Navigate to Goals tab in main screen
    Navigator.pushNamedAndRemoveUntil(
      context,
      RouteNames.main,
      (route) => route.isFirst,  // ❌ Clears navigation history
      arguments: 1, // Goals tab index
    );
  },
  // ... "View Goal" badge UI
)
```

**Problem**:
- Similar to Issue #3, but uses `pushNamedAndRemoveUntil`
- Clears all navigation history
- Inconsistent with how tab switching should work

**Navigation Stack (BROKEN)**:
```
Before: Main → Programs → Program Detail
After:  Main (Goals tab) ❌ Lost Program navigation history
```

**Expected**:
- Should preserve ability to go back to Programs
- Should use same tab-switching mechanism as other areas

**Fix**: Use same solution as Issue #3 (TabNavigationService)

**Priority**: ⚠️ MODERATE - Same issue as #3 but less frequently used

---

### **Issue #5: No Back Button Handling for Active Workouts**

**Location**: `lib/ui/screens/sessions/active_workout_screen.dart` (entire file)

**Current Code**: No `WillPopScope` or `PopScope` widget found

**Problem**:
- User can accidentally press back button during active workout
- Workout gets lost without warning
- Timer stops without confirmation
- User loses workout progress

**Expected Behavior**:
- Should show "Are you sure you want to leave this workout?" dialog
- Should warn that timer will be lost
- Should give option to finish or pause workout first

**Fix**:
```dart
// Wrap ActiveWorkoutScreen's Scaffold with PopScope
PopScope(
  canPop: false,
  onPopInvoked: (bool didPop) async {
    if (didPop) return;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Workout?'),
        content: const Text(
          'Your workout is still in progress. '
          'If you leave now, the timer will be lost. '
          'Do you want to finish the workout first?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave Anyway'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context, false);
              // Trigger finish workout dialog
              _handleFinishWorkout();
            },
            child: const Text('Finish Workout'),
          ),
        ],
      ),
    );

    if (shouldLeave == true && mounted) {
      Navigator.pop(context);
    }
  },
  child: Scaffold(
    // ... existing content
  ),
)
```

**Priority**: ⚠️ MODERATE - Can cause data loss, but user can restart workout

---

### **Issue #6: No Back Button Handling for Chat Conversations**

**Location**: `lib/ui/screens/chat/chat_conversation_screen.dart` (entire file)

**Problem**: Same as Issue #5, but for chat conversations

**Expected**: Warn before leaving if message is being generated or typed

**Fix**: Similar PopScope implementation as Issue #5

**Priority**: ⚠️ LOW - Less critical than workouts

---

### **Issue #7: Unpredictable Navigation After Workout Completion**

**Location**: `lib/ui/screens/sessions/active_workout_screen.dart:72-74`

**Current Code**:
```dart
if (success && mounted) {
  // Pop back to sessions screen
  Navigator.of(context).pop();
}
```

**Problem**:
- Simple `pop()` depends on where user came from
- If from Sessions screen → ✅ Works fine
- If from Program screen → ⚠️ Goes back to program, not updated sessions
- If from notification/deep link → ❌ Unpredictable destination

**Expected Behavior**:
- Should have consistent destination after workout completion
- Should show user their completed workout in Sessions list
- Should refresh Sessions list to show updated data

**Fix Options**:

**Option A**: Always navigate to Sessions screen
```dart
if (success && mounted) {
  // Always go to sessions screen to see completed workout
  Navigator.of(context).popUntil((route) => route.isFirst);
  Navigator.of(context).pushNamed(
    RouteNames.main,
    arguments: {'tab': 0, 'subTab': 0},  // My Workouts tab
  );
}
```

**Option B**: Pop until Sessions or Main screen
```dart
if (success && mounted) {
  Navigator.of(context).popUntil((route) {
    return route.settings.name == RouteNames.sessions ||
           route.settings.name == RouteNames.main ||
           route.isFirst;
  });
}
```

**Option C**: Add callback parameter to screen
```dart
// In active_workout_screen.dart
final VoidCallback? onWorkoutCompleted;

// In finish logic
if (success && mounted) {
  if (onWorkoutCompleted != null) {
    onWorkoutCompleted();
  } else {
    Navigator.of(context).pop();
  }
}
```

**Recommended**: Option B - Pop to known screen

**Priority**: ⚠️ LOW - Works in most common cases

---

## 💡 UX/POLISH ISSUES

### **Issue #8: No Navigation Feedback**

**Locations**: Multiple

**Problem**:
- Some navigations show SnackBar (✅ chat → program)
- Others are silent (❌ goals → chat, goals → programs)
- Inconsistent user feedback

**Fix**: Add SnackBar or visual feedback for all major navigation actions

**Priority**: 💡 POLISH - Nice to have

---

### **Issue #9: Multi-Step Flow Too Complex**

**Location**: Goal creation → AI workout plan → Program creation flow

**Current Flow** (7 steps with multiple dialogs):
1. Goals screen
2. Click "Create Goal" → Dialog
3. Create goal → Dialog shows "Generate Workout Plan?"
4. Generate plan → Navigate to Chat
5. Chat generates plan → Click "Create Program" → Dialog
6. Fill program details → Navigate to Program Detail

**Problem**:
- Too many modal dialogs
- User loses context
- Dialog → Screen → Dialog → Screen pattern is confusing

**Fix**: Consider wizard-style screens or streamlined flow

**Priority**: 💡 POLISH - Works but could be better

---

## 🔧 RECOMMENDED ARCHITECTURE IMPROVEMENTS

### **1. Add TabNavigationService**

Create a centralized service for tab switching to avoid duplicate Main Screen issues:

**File**: `lib/core/services/tab_navigation_service.dart`

```dart
import 'package:flutter/foundation.dart';

/// Service for managing main screen tab navigation
/// Prevents duplicate Main Screen instances in navigation stack
class TabNavigationService extends ChangeNotifier {
  int _currentTab = 0;
  int? _currentSubTab;

  int get currentTab => _currentTab;
  int? get currentSubTab => _currentSubTab;

  /// Switch to a specific tab
  /// [tabIndex] - Main tab index (0=Workouts, 1=Goals, 2=Chat, etc.)
  /// [subTabIndex] - Optional sub-tab index for tabs with sub-navigation
  void switchTab(int tabIndex, {int? subTabIndex}) {
    _currentTab = tabIndex;
    _currentSubTab = subTabIndex;
    notifyListeners();
  }

  /// Reset to first tab
  void reset() {
    _currentTab = 0;
    _currentSubTab = null;
    notifyListeners();
  }
}
```

**Register in `lib/main.dart`**:
```dart
// Add to providers list
ChangeNotifierProvider(create: (_) => TabNavigationService()),
```

**Use in `lib/ui/screens/main_screen.dart`**:
```dart
@override
Widget build(BuildContext context) {
  final tabService = context.watch<TabNavigationService>();

  return Scaffold(
    body: IndexedStack(
      index: tabService.currentTab,  // Use service instead of _currentIndex
      children: _screens,
    ),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: tabService.currentTab,
      onTap: (index) {
        tabService.switchTab(index);
      },
      // ... items
    ),
  );
}
```

**Use in other screens** (goals_screen.dart, program_detail_screen.dart):
```dart
// Instead of Navigator.pushNamed(RouteNames.main, ...)
context.read<TabNavigationService>().switchTab(0, subTabIndex: 1);
Navigator.pop(context);  // Pop back to main screen
```

---

### **2. Add PopScope Handlers for Critical Screens**

Protect users from accidental data loss:

**Active Workout Screen**:
```dart
PopScope(
  canPop: false,
  onPopInvoked: (didPop) async {
    if (didPop) return;
    final shouldLeave = await _showLeaveWorkoutDialog();
    if (shouldLeave && mounted) Navigator.pop(context);
  },
  child: Scaffold(...),
)
```

**Chat Conversation Screen** (if actively generating):
```dart
PopScope(
  canPop: !_isGenerating,  // Can pop if not generating
  onPopInvoked: (didPop) async {
    if (didPop) return;
    if (_isGenerating) {
      final shouldCancel = await _showCancelGenerationDialog();
      if (shouldCancel && mounted) Navigator.pop(context);
    }
  },
  child: Scaffold(...),
)
```

---

### **3. Standardize Navigation Patterns**

**Create navigation utility class**:

**File**: `lib/core/utils/navigation_helper.dart`

```dart
import 'package:flutter/material.dart';
import '../../routes/route_names.dart';

class NavigationHelper {
  /// Navigate to main screen with specific tab
  static void navigateToTab(
    BuildContext context,
    int tabIndex, {
    int? subTabIndex,
    bool clearStack = false,
  }) {
    if (clearStack) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        RouteNames.main,
        (route) => false,
        arguments: {'tab': tabIndex, 'subTab': subTabIndex},
      );
    } else {
      // Use TabNavigationService instead of pushing new main screen
      // context.read<TabNavigationService>().switchTab(tabIndex, subTabIndex: subTabIndex);
      // Navigator.popUntil(...);
    }
  }

  /// Navigate after completing a workout
  static void navigateAfterWorkoutComplete(BuildContext context) {
    // Pop until we find sessions or main screen
    Navigator.of(context).popUntil((route) {
      return route.settings.name == RouteNames.sessions ||
             route.settings.name == RouteNames.main ||
             route.isFirst;
    });
  }

  /// Show confirmation before destructive navigation
  static Future<bool> confirmDestructiveNavigation(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    ) ?? false;
  }
}
```

---

## 📋 FIX PRIORITY ORDER

### Phase 1: Critical Fixes (Do First)
1. ✅ Fix Issue #1 - Start Workout button navigation
2. ✅ Fix Issue #2 - Program creation navigation stack
3. ✅ Fix Issue #3 - Duplicate Main Screen from Goals

### Phase 2: Safety Improvements
4. ✅ Fix Issue #5 - Add PopScope to Active Workout
5. ✅ Fix Issue #4 - Consistent tab switching from Program Detail

### Phase 3: Architecture (Long-term)
6. ✅ Implement TabNavigationService
7. ✅ Add NavigationHelper utility class
8. ✅ Standardize all tab-switching to use service

### Phase 4: Polish
9. ✅ Add navigation feedback (SnackBars)
10. ✅ Fix Issue #7 - Consistent workout completion navigation

---

## 🧪 TESTING CHECKLIST

After fixes, test these flows:

### Critical Flows:
- [ ] Start workout from program → Should go directly to active workout screen
- [ ] Create goal → Generate AI plan → Create program → Back button should work normally
- [ ] From Goals tab, click "View Programs" → Should switch tabs, not create duplicate screen
- [ ] From Program Detail, click "View Goal" → Should switch tabs correctly
- [ ] Press back during active workout → Should show confirmation dialog

### Edge Cases:
- [ ] Complete workout from Program flow → Should show updated session
- [ ] Complete workout from Sessions flow → Should refresh list
- [ ] Navigate deep (Main → Programs → Detail → Workout → Active) → Back button should work
- [ ] Switch tabs multiple times → No duplicate Main Screens in stack

### Regression Testing:
- [ ] Login → Main navigation still works
- [ ] Logout → Clears stack correctly
- [ ] 404 handling → "Go Home" button works
- [ ] All existing navigation flows still work

---

## 📝 NOTES FOR IMPLEMENTATION

1. **Don't break existing flows**: Many navigation patterns work fine, only fix the broken ones
2. **Test on Android**: Back button behavior is critical on Android
3. **Consider deep links**: Future feature may require robust navigation handling
4. **Route observer**: Already in place at `lib/app.dart:90-102` for debugging
5. **IndexedStack**: Already preserves tab state correctly, don't break it

---

## 🔗 RELATED FILES

**Main Navigation Files**:
- `lib/app.dart` - Root app with route observer
- `lib/ui/screens/main_screen.dart` - Bottom navigation wrapper
- `lib/routes/app_router.dart` - Route generator
- `lib/routes/route_names.dart` - Route constants

**Files Needing Changes**:
- `lib/ui/screens/programs/program_workout_screen.dart` (Issue #1)
- `lib/ui/screens/chat/chat_conversation_screen.dart` (Issue #2)
- `lib/ui/screens/goals/goals_screen.dart` (Issue #3)
- `lib/ui/screens/programs/program_detail_screen.dart` (Issue #4)
- `lib/ui/screens/sessions/active_workout_screen.dart` (Issues #5, #7)

**Files to Create**:
- `lib/core/services/tab_navigation_service.dart` (New)
- `lib/core/utils/navigation_helper.dart` (New)

---

**End of Navigation Issues Report**
