# Provider to Riverpod Migration Guide

This guide explains how to incrementally migrate from Provider to Riverpod.

## Current Architecture

The app uses Provider with 19 ChangeNotifier classes for state management:

- AuthProvider
- SessionsProvider
- ActiveWorkoutProvider
- ExercisesProvider
- ExerciseDetailProvider
- LogSetsProvider
- ProfileProvider
- AnalyticsProvider
- ChatProvider
- SharedWorkoutProvider
- WorkoutTemplateProvider
- GoalsProvider
- BodyMetricsProvider
- ProgramsProvider
- RunningProvider
- MusicPlayerProvider
- SettingsProvider
- OnboardingProvider
- AchievementsProvider

## Migration Strategy

### Phase 1: Infrastructure (COMPLETE)
- [x] Add Riverpod dependencies to pubspec.yaml
- [x] Create core service providers
- [x] Create repository providers
- [x] Create AuthNotifier and SessionsNotifier as examples

### Phase 2: Hybrid Setup
Update `main.dart` to use both Provider and Riverpod:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services...

  runApp(
    ProviderScope(
      child: MultiProvider(
        providers: [
          // Keep existing Provider setup for now
        ],
        child: const MyApp(),
      ),
    ),
  );
}
```

### Phase 3: Screen-by-Screen Migration
For each screen:

1. **Add Riverpod imports:**
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_hard_app/providers/riverpod/providers.dart';
```

2. **Convert StatelessWidget to ConsumerWidget:**
```dart
// Before
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MyProvider>();
    return Text(provider.value);
  }
}

// After
class MyScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myNotifierProvider);
    return Text(state.value);
  }
}
```

3. **Convert StatefulWidget to ConsumerStatefulWidget:**
```dart
// Before
class MyScreen extends StatefulWidget {
  @override
  _MyScreenState createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MyProvider>();
    return Text(provider.value);
  }
}

// After
class MyScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myNotifierProvider);
    return Text(state.value);
  }
}
```

### Phase 4: Provider Deprecation
Once all screens are migrated:
1. Remove old ChangeNotifier providers
2. Remove Provider package from pubspec.yaml
3. Clean up MultiProvider from main.dart

## Key Differences

### State Updates
```dart
// Provider (mutable)
class MyProvider extends ChangeNotifier {
  String _value = '';
  void setValue(String v) {
    _value = v;
    notifyListeners();
  }
}

// Riverpod (immutable)
class MyNotifier extends StateNotifier<MyState> {
  MyNotifier() : super(const MyState());

  void setValue(String v) {
    state = state.copyWith(value: v);
  }
}
```

### Accessing State
```dart
// Provider
final value = context.watch<MyProvider>().value;
final value = context.read<MyProvider>().value;

// Riverpod
final value = ref.watch(myNotifierProvider).value;
final value = ref.read(myNotifierProvider).value;
```

### Calling Methods
```dart
// Provider
context.read<MyProvider>().doSomething();

// Riverpod
ref.read(myNotifierProvider.notifier).doSomething();
```

## Benefits of Riverpod

1. **Compile-time safety:** No runtime errors from missing providers
2. **Better testing:** Providers can be easily mocked/overridden
3. **No BuildContext required:** Can access providers anywhere
4. **Auto-dispose:** StateNotifierProvider automatically disposes
5. **Family providers:** Easy parameterized providers
6. **Computed values:** Derived state without boilerplate

## Migration Priority

Recommended order based on complexity and usage:

1. **Auth** (foundation for all auth-related features)
2. **Sessions** (core workout data)
3. **Exercises** (used in many screens)
4. **Profile** (user settings)
5. **Analytics** (standalone feature)
6. Remaining providers...

## Testing

For each migrated provider, ensure:
1. Unit tests pass with new StateNotifier
2. Integration tests work with ProviderScope
3. Widget tests use ProviderScope.overrides for mocking
