# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GoHardAPP is a cross-platform Flutter mobile application for comprehensive fitness tracking with offline-first architecture. Features include workout sessions, exercise library, analytics with calendar heatmap, AI chat integration, social workout sharing, and workout templates with scheduling.

## Technology Stack

- **Framework**: Flutter 3.29.2, Dart ^3.7.2
- **State Management**: Provider pattern (ChangeNotifier)
- **HTTP Client**: Dio 5.4.0 with JWT interceptors
- **Local Database**: Isar 3.1.0+ (NoSQL, offline-first)
- **Secure Storage**: flutter_secure_storage 9.0.0
- **Connectivity**: connectivity_plus 5.0.2
- **Charts**: fl_chart 0.68.0
- **Backend**: ASP.NET Core 8.0 API at https://gohardapi-production.up.railway.app/api/

## Build & Run Commands

### Setup & Dependencies
```bash
# Install dependencies
flutter pub get

# Generate Isar schemas and JSON serialization code
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode for continuous code generation during development
flutter pub run build_runner watch
```

### Development
```bash
# Run on connected device/emulator
flutter run

# Run on specific device
flutter devices
flutter run -d <device-id>

# Run in release mode
flutter run --release

# Run in debug mode (default)
flutter run --debug
```

### Code Quality
```bash
# Format code
flutter format .

# Static analysis
flutter analyze

# Clean build artifacts
flutter clean
```

### Testing
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/providers/auth_provider_test.dart

# Run with coverage
flutter test --coverage

# Generate mocks for testing
flutter pub run build_runner build --delete-conflicting-outputs
```

### Building for Production
```bash
# Android APK (for sideloading)
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Android App Bundle (for Play Store)
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab

# iOS (unsigned for testing)
flutter build ios --release --no-codesign

# iOS (signed, configure in Xcode first)
flutter build ios --release
```

## Architecture

### MVVM-like Pattern with Repository Layer

```
UI (Screens/Widgets)
    ↓ watch/read
Providers (ChangeNotifier - ViewModels)
    ↓ dependency injection
Repositories (Data Access Logic)
    ↓ dual data sources
┌──────────────┬──────────────┐
│  API Service │  Local DB    │
│  (Dio/HTTP)  │  (Isar)      │
└──────────────┴──────────────┘
```

### Offline-First Strategy

**Read Operations**:
1. Load from local Isar cache FIRST (instant UI)
2. Return cached data immediately if offline
3. Background fetch from server if online
4. Update cache with fresh data

**Write Operations**:
1. Save to local database immediately
2. Update UI optimistically
3. Queue for sync with `isSynced: false`
4. Background sync when online
5. Update with server IDs

**Sync Service**:
- Auto-sync every 30 seconds when online
- Manual sync via pull-to-refresh
- Connectivity monitoring with automatic triggers
- Retry logic for failed syncs

## Key Files & Directories

### Entry Point & Configuration

**lib/main.dart**:
- App initialization
- Isar database setup
- Connectivity service initialization
- Notification service setup
- MultiProvider dependency injection (20+ providers)

**lib/app.dart**:
- MaterialApp configuration
- Theme setup (light/dark mode)
- Route generation with AppRouter
- Auth guard for protected routes

**lib/core/constants/api_config.dart**:
- Base API URL (production: Railway, dev: localhost:5121)
- Platform-specific URLs (iOS: localhost, Android: 10.0.2.2, Windows: localhost)
- 20+ endpoint definitions
- Connection timeout: 3s, Receive timeout: 180s

**lib/core/theme/app_theme.dart**:
- Material Design 3 themes
- GoHard brand colors (black/white monochrome)
- iOS system colors for compatibility
- Dark/light mode support

### Data Layer

**lib/data/models/** (45+ models):
- Isar schemas: `@collection` annotation
- JSON serialization: `@JsonSerializable()`
- Generated files: `.g.dart` (JSON), `.isar.dart` (Isar schema)
- Key models: Session, Exercise, ExerciseSet, ExerciseTemplate, SharedWorkout, WorkoutTemplate, ChatConversation, Goal, BodyMetric

**lib/data/repositories/** (12 repositories):
All follow offline-first pattern with:
- ApiService for server communication
- LocalDatabaseService for Isar operations
- ConnectivityService for network status
- AuthService for user context

Key repositories:
- `SessionRepository`: Sessions CRUD + offline sync queue (largest, 38KB)
- `ExerciseRepository`: Exercise templates with caching
- `ChatRepository`: AI chat conversations (21KB)
- `SharedWorkoutRepository`: Community workouts with social features
- `WorkoutTemplateRepository`: Templates with scheduling logic
- `GoalsRepository`: Goal tracking with progress
- `BodyMetricsRepository`: Body measurements

**lib/data/services/api_service.dart**:
- Dio HTTP client wrapper
- Automatic JWT token injection via interceptors
- Generic GET/POST/PUT/PATCH/DELETE methods
- 401 detection for automatic logout
- Request/response logging

**lib/data/services/auth_service.dart**:
- Secure token storage (flutter_secure_storage)
- Token retrieval and clearing
- User ID extraction from JWT

**lib/data/local/services/local_database_service.dart**:
- Isar database singleton
- Collections: LocalSession, LocalExercise, LocalExerciseSet, LocalExerciseTemplate, SharedWorkout, WorkoutTemplate, ChatConversation, ChatMessage
- Inspector enabled for debugging
- Async initialization in main()

**lib/core/services/connectivity_service.dart**:
- Real-time network monitoring
- `isOnline` stream and property
- ChangeNotifier for UI updates
- Triggers sync when connectivity restored

**lib/core/services/sync_service.dart** (22KB):
- Background sync engine
- Periodic timer (every 30s when online)
- Handles pending creates/updates/deletes
- Retry logic with exponential backoff
- User data isolation (only sync current user)

### Providers (16 state managers)

All extend `ChangeNotifier` and follow this pattern:
```dart
class ExampleProvider extends ChangeNotifier {
  final ExampleRepository _repository;

  List<Item> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Item> get items => _items;
  bool get isLoading => _isLoading;

  Future<void> loadItems() async {
    _isLoading = true;
    notifyListeners();
    try {
      _items = await _repository.getItems();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

**Provider List**:
1. **AuthProvider**: Login, signup, logout, token management, auth state
2. **SessionsProvider**: Sessions list, CRUD, sync queue, filters
3. **ActiveWorkoutProvider**: Live timer, pause/resume, exercise tracking (13KB)
4. **ExercisesProvider**: Exercise library with category/muscle filtering
5. **ExerciseDetailProvider**: Single exercise details
6. **LogSetsProvider**: Set logging during workouts
7. **ProfileProvider**: User profile, settings, theme
8. **AnalyticsProvider**: Heatmap data, streaks, statistics
9. **GoalsProvider**: Goals management with progress tracking
10. **BodyMetricsProvider**: Body measurements
11. **ChatProvider**: AI chat conversations (16KB)
12. **SharedWorkoutProvider**: Community workouts, likes, saves
13. **WorkoutTemplateProvider**: Templates CRUD, scheduling, ratings
14. **ProgramsProvider**: Workout programs with weekly schedules (10KB)
15. **MusicPlayerProvider**: Workout music playback
16. **SettingsProvider**: App preferences

### UI Layer

**lib/ui/screens/** (28 screens):

**auth/**:
- `login_screen.dart`: Email/password login
- `signup_screen.dart`: User registration

**sessions/**:
- `sessions_screen.dart`: Main workout list (completed/past/upcoming filters)
- `session_detail_screen.dart`: Single session view with exercises
- `active_workout_screen.dart`: Live workout tracker with timer

**exercises/**:
- `exercises_screen.dart`: Library with category/muscle/equipment filters
- `exercise_detail_screen.dart`: Exercise info, benefits, alternatives
- `add_exercise_screen.dart`: Custom exercise creation
- `log_sets_screen.dart`: Set logging during active workout

**analytics/**:
- `analytics_screen.dart`: Calendar heatmap, streaks, weekly progress, charts

**community/**:
- `community_screen.dart`: 3 tabs (Discover, Saved, My Shares), social features

**templates/**:
- `templates_screen.dart`: 2 tabs (My Templates, Community)
- `template_form_dialog.dart`: Create/edit templates with recurrence patterns

**programs/**:
- `programs_screen.dart`: Workout programs with weekly schedule
- `program_detail_screen.dart`: Program details and progress
- `program_workout_screen.dart`: Individual workout from program

**chat/**:
- `chat_list_screen.dart`: Conversation list
- `chat_conversation_screen.dart`: Chat interface with AI
- `workout_plan_form_screen.dart`: AI workout plan generator
- `meal_plan_form_screen.dart`: AI meal plan generator

**profile/**:
- `profile_screen.dart`: User info, stats, settings

**body_metrics/**:
- `body_metrics_screen.dart`: Body measurements tracking

**goals/**:
- Goals management screens

**main_screen.dart**: Bottom navigation wrapper (5+ tabs)

**lib/ui/widgets/** (Reusable components):
- `common/`: OfflineBanner, LoadingIndicator
- `sessions/`: SessionCard, WorkoutTimer, ExerciseListItem
- `exercises/`: ExerciseCard, SetRow, CategoryChip
- `analytics/`: CalendarHeatmap, StreakCounter, StatCard
- `music/`: Music player components
- `programs/`: Program card, week view widgets

### Routing

**lib/routes/route_names.dart**:
Route string constants for all 25+ routes

**lib/routes/app_router.dart**:
- Dynamic route generation
- Argument passing (sessionId, initialTab, etc.)
- Auth guard for protected routes
- NotFoundScreen for invalid routes

## Development Workflow

### Adding a New Feature

1. **Create Model** (if needed):
```dart
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';

part 'my_model.g.dart';

@JsonSerializable()
@collection
class MyModel {
  Id id = Isar.autoIncrement;

  @Index()
  int? serverId;

  String name;
  DateTime createdAt;

  @Index()
  bool isSynced;

  MyModel({
    required this.name,
    required this.createdAt,
    this.isSynced = false,
  });

  factory MyModel.fromJson(Map<String, dynamic> json) => _$MyModelFromJson(json);
  Map<String, dynamic> toJson() => _$MyModelToJson(this);
}
```

2. **Generate Code**:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

3. **Create Repository**:
```dart
class MyRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;

  Future<List<MyModel>> getItems() async {
    final isar = _localDb.isar;

    // 1. Load from cache first
    final cached = await isar.myModels.where().findAll();

    // 2. Return cache if offline
    if (_connectivity.isOffline) return cached;

    // 3. Background sync
    _syncFromServer().catchError((e) => debugPrint('Sync error: $e'));

    // 4. Return cached data (instant UI)
    return cached;
  }
}
```

4. **Create Provider**:
```dart
class MyProvider extends ChangeNotifier {
  final MyRepository _repository;

  List<MyModel> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<MyModel> get items => _items;
  bool get isLoading => _isLoading;

  MyProvider(this._repository);

  Future<void> loadItems() async {
    _isLoading = true;
    notifyListeners();

    try {
      _items = await _repository.getItems();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

5. **Register Provider in lib/app.dart**:
```dart
ChangeNotifierProxyProvider<MyRepository, MyProvider>(
  create: (context) => MyProvider(context.read<MyRepository>()),
  update: (_, repo, previous) => previous ?? MyProvider(repo),
)
```

6. **Create Screen**:
```dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MyProvider>();

    return Scaffold(
      appBar: AppBar(title: Text('My Feature')),
      body: provider.isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: provider.items.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(provider.items[index].name),
                );
              },
            ),
    );
  }
}
```

7. **Add Route in lib/routes/app_router.dart**

### Common Patterns

**Using Provider in UI**:
```dart
// Read once (for actions)
context.read<MyProvider>().doSomething();

// Watch (rebuilds on change)
final provider = context.watch<MyProvider>();

// Select specific property (efficient rebuilds)
final isLoading = context.select((MyProvider p) => p.isLoading);
```

**Offline-First Repository Pattern**:
```dart
Future<MyModel> createItem(MyModel item) async {
  if (_connectivity.isOnline) {
    try {
      final result = await _apiService.post('/items', data: item.toJson());
      await _saveToCache(result, isSynced: true);
      return result;
    } catch (e) {
      return await _createLocal(item, isPending: true);
    }
  } else {
    return await _createLocal(item, isPending: true);
  }
}
```

**User Context in Repositories**:
```dart
Future<List<MyModel>> getItems() async {
  final userId = await _authService.getUserId();
  if (userId == null) return [];

  return await isar.myModels
      .filter()
      .userIdEqualTo(userId)
      .findAll();
}
```

## API Configuration

**Base URLs** (lib/core/constants/api_config.dart):
- **Production**: `https://gohardapi-production.up.railway.app/api/`
- **Development**: Platform-specific (localhost:5121 for iOS/Windows, 10.0.2.2:5121 for Android)

**Endpoint Constants**:
All API endpoints defined as static constants:
- `/sessions`, `/exercises`, `/exercisetemplates`, `/users`
- `/chat`, `/goals`, `/bodymetrics`, `/analytics`
- `/sharedworkouts`, `/workouttemplates`, `/programs`

**Timeouts**:
- Connect timeout: 3 seconds
- Receive timeout: 180 seconds (for AI responses)

## State Management Best Practices

1. **Keep providers focused**: Single responsibility principle
2. **Use private setters, public getters**: Encapsulation
3. **Always call notifyListeners()**: After state changes
4. **Handle loading and error states**: Proper UI feedback
5. **Use context.read() for actions**: Don't rebuild unnecessarily
6. **Use context.watch() for reactive rebuilds**: When UI depends on state
7. **Dispose resources**: Override dispose() if needed

## Testing

### Test Structure
```
test/
├── providers/
│   ├── auth_provider_test.dart (9+ tests)
│   └── *.mocks.dart (generated)
└── ui/screens/auth/
    ├── login_screen_test.dart (7+ tests)
    └── *.mocks.dart (generated)
```

### Mock Generation
```bash
# Generate mocks for repositories and services
flutter pub run build_runner build --delete-conflicting-outputs
```

### Example Test
```dart
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([AuthService])
void main() {
  late AuthProvider provider;
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
    provider = AuthProvider(mockAuthService);
  });

  test('login success updates isAuthenticated', () async {
    when(mockAuthService.login(any, any))
        .thenAnswer((_) async => AuthResponse(token: '...', userId: 1));

    await provider.login('test@test.com', 'password');

    expect(provider.isAuthenticated, true);
    expect(provider.errorMessage, null);
  });
}
```

## Troubleshooting

### API Connection Failed
- Check API URL in `lib/core/constants/api_config.dart`
- For Android emulator: Use `10.0.2.2` instead of `localhost`
- For iOS simulator: Use `localhost`
- Verify backend is running at expected URL

### Isar Build Failed
```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Code Generation Issues
```bash
# Delete all generated files and rebuild
find . -name "*.g.dart" -delete
find . -name "*.isar.dart" -delete
flutter pub run build_runner build --delete-conflicting-outputs
```

### Tests Failing
1. Regenerate mocks: `flutter pub run build_runner build --delete-conflicting-outputs`
2. Check mock stubs in test setup
3. Verify all dependencies: `flutter pub get`

### Offline Mode Not Working
1. Check connectivity_plus permissions in AndroidManifest.xml/Info.plist
2. Verify LocalDatabaseService initialized in main.dart
3. Check ConnectivityService initialization
4. Verify repositories use connectivity checks

### Hot Reload Issues
1. Try hot restart (Shift+R or `r` in CLI)
2. Stop and restart app
3. Run `flutter clean` and restart

## CI/CD Pipeline

**GitHub Actions** (.github/workflows/main.yml):

**Triggers**:
- Push to `main` or `release/*`
- Pull requests to `main`
- Manual workflow dispatch

**Jobs**:
1. **Test**: Format check, static analysis, mock generation, unit/widget tests
2. **Build Android APK**: Release APK (artifact: 30-day retention)
3. **Build Android AAB**: App Bundle for Play Store (artifact: 30-day retention)
4. **Build iOS**: Unsigned IPA (artifact: 30-day retention)
5. **Build Summary**: Aggregate job results

**Artifacts**: Downloaded from Actions tab, 30-day retention

## Important Notes

- **Always run code generation** after modifying models with `@JsonSerializable` or `@collection`
- **Never commit API keys**: Use environment variables or secure config
- **User data isolation**: All operations filter by current user from JWT
- **UTC timestamps**: All DateTime values use UTC
- **Logout clears local DB**: For user privacy and data isolation
- **Server wins conflicts**: Last-write-wins strategy for sync conflicts
- **Optimistic UI updates**: Show changes immediately, sync in background
