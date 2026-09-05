import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'core/services/firebase_availability.dart';
import 'core/services/firebase_bootstrap.dart';
import 'core/services/session_cleanup_initializer.dart';
import 'core/services/session_request_coordinator.dart';
import 'core/services/user_session_epoch.dart';
import 'data/services/auth_service.dart';
import 'data/services/api_service.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/session_repository.dart';
import 'data/repositories/exercise_repository.dart';
import 'data/repositories/user_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/analytics_repository.dart';
import 'data/repositories/chat_repository.dart';
import 'data/repositories/shared_workout_repository.dart';
import 'data/repositories/workout_template_repository.dart';
import 'data/repositories/goals_repository.dart';
import 'data/repositories/body_metrics_repository.dart';
import 'data/repositories/programs_repository.dart';
import 'data/repositories/running_repository.dart';
import 'data/repositories/nutrition_repository.dart';
import 'data/local/services/local_database_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/sync_service.dart';
import 'core/services/sync_service_initializer.dart';
import 'core/services/notification_service.dart';
import 'core/services/background_service.dart';
import 'core/services/tab_navigation_service.dart';
import 'providers/auth_provider.dart';
import 'providers/sessions_provider.dart';
import 'providers/active_workout_provider.dart';
import 'providers/exercises_provider.dart';
import 'providers/exercise_detail_provider.dart';
import 'providers/log_sets_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/shared_workout_provider.dart';
import 'providers/workout_template_provider.dart';
import 'providers/goals_provider.dart';
import 'providers/body_metrics_provider.dart';
import 'providers/programs_provider.dart';
import 'providers/music_player_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/onboarding_provider.dart';
import 'providers/achievements_provider.dart';
import 'providers/running_provider.dart';
import 'providers/nutrition_provider.dart';
import 'data/repositories/achievement_repository.dart';
import 'data/repositories/friends_repository.dart';
import 'data/repositories/direct_messages_repository.dart';
import 'core/services/health_service.dart';
import 'providers/friends_provider.dart';
import 'providers/messages_provider.dart';

void main() async {
  // Ensure Flutter bindings are initialized for async operations
  WidgetsFlutterBinding.ensureInitialized();

  // Attempt Firebase initialization without ever blocking startup, then
  // always continue into the rest of app startup exactly once via
  // `_startApp` - the same function `runFirebaseAwareStartup` is exercised
  // with in firebase_bootstrap_test.dart, not a test-only duplicate.
  // Android currently ships without google-services.json /
  // firebase_options.dart and with the Google Services Gradle plugin
  // disabled, so initialization is expected to fail there today - push
  // notifications are the only feature that depends on it, and
  // MainScreen skips setting them up when unavailable (see
  // bootstrapPushNotifications).
  await runFirebaseAwareStartup(
    initializer: Firebase.initializeApp,
    continuation: _startApp,
  );
}

/// The remainder of app startup after the Firebase attempt: local
/// database, connectivity, other app-lifetime services, provider
/// construction, and `runApp()`. Passed to `runFirebaseAwareStartup` as
/// its continuation, so it always runs exactly once regardless of whether
/// Firebase initialized - nothing below is conditioned on
/// [firebaseAvailability] except the one debug log line.
Future<void> _startApp(FirebaseAvailability firebaseAvailability) async {
  if (firebaseAvailability.isAvailable) {
    debugPrint('🔥 Firebase initialized');
  }

  // Initialize local database before app starts
  final localDb = LocalDatabaseService.instance;
  await localDb.initialize();

  debugPrint('✅ Local database initialized successfully');
  debugPrint('📊 Database path: ${localDb.database.directory}');
  debugPrint('🔍 Isar Inspector enabled - use Isar Inspector app to view data');

  // NOTE: no pre-authentication cleanup runs here. Startup must never delete a
  // Session (or its Exercises/ExerciseSets) that has not been synchronized -
  // sync failures are transient and the retry counter is diagnostic only.
  // Deletion is authoritative (a successful server DELETE, or an explicit
  // authenticated user action) and always runs owner-scoped, after auth.

  // Initialize connectivity service
  final connectivity = ConnectivityService.instance;
  await connectivity.initialize();

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Initialize health service (Apple Health / Google Fit)
  final healthService = HealthService.instance;
  await healthService.initialize();

  // Initialize background service for smart notifications
  await BackgroundService.initialize();

  // Initialize secure storage
  const secureStorage = FlutterSecureStorage();

  // Single shared session-identity instance for the whole app process.
  // Depends on nothing (see UserSessionEpoch's own doc comment), so it is
  // safe to construct here alongside the other app-lifetime singletons and
  // hand the SAME instance to every Provider that needs to capture/check
  // it - only AuthProvider ever calls activate()/invalidate() on it.
  final sessionEpoch = UserSessionEpoch();

  runApp(
    /// MultiProvider setup for dependency injection and state management
    /// Matches the service and ViewModel structure from MAUI app
    MultiProvider(
      providers: [
        // Services (singletons)
        Provider<LocalDatabaseService>.value(value: localDb),
        ChangeNotifierProvider<ConnectivityService>.value(value: connectivity),
        Provider<NotificationService>.value(value: notificationService),
        Provider<FlutterSecureStorage>.value(value: secureStorage),
        Provider<UserSessionEpoch>.value(value: sessionEpoch),
        Provider<FirebaseAvailability>.value(value: firebaseAvailability),
        Provider<AuthService>(create: (_) => AuthService()),
        ProxyProvider2<AuthService, UserSessionEpoch, ApiService>(
          update:
              (_, authService, sessionEpoch, __) =>
                  ApiService(authService, sessionEpoch),
        ),
        // Session-bound HTTP request capture/cancellation coordinator.
        // Depends only on the same shared UserSessionEpoch instance and
        // AuthService. Consumed by NutritionRepository for session-bound
        // requests and by AuthProvider's logout pass, which cancels the
        // active generation here on every logout.
        ProxyProvider2<
          UserSessionEpoch,
          AuthService,
          SessionRequestCoordinator
        >(
          update:
              (_, sessionEpoch, authService, __) =>
                  SessionRequestCoordinator(sessionEpoch, authService),
        ),

        // Repositories
        ProxyProvider<ApiService, AuthRepository>(
          update: (_, apiService, __) => AuthRepository(apiService),
        ),
        ProxyProvider4<
          ApiService,
          LocalDatabaseService,
          ConnectivityService,
          AuthService,
          SessionRepository
        >(
          update:
              (context, apiService, localDb, connectivity, authService, __) =>
                  SessionRepository(
                    apiService,
                    localDb,
                    connectivity,
                    authService,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters (matches NutritionRepository's wiring
                    // below).
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),
        ProxyProvider3<
          ApiService,
          LocalDatabaseService,
          ConnectivityService,
          ExerciseRepository
        >(
          update:
              (context, apiService, localDb, connectivity, __) =>
                  ExerciseRepository(
                    apiService,
                    localDb,
                    connectivity,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters (matches SessionRepository's wiring above).
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),
        ProxyProvider<ApiService, UserRepository>(
          update: (_, apiService, __) => UserRepository(apiService),
        ),
        ProxyProvider3<
          ApiService,
          AuthService,
          ConnectivityService,
          ProfileRepository
        >(
          update:
              (context, apiService, authService, connectivity, __) =>
                  ProfileRepository(
                    apiService,
                    authService,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters (matches GoalsRepository's wiring below).
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                    connectivity,
                  ),
        ),
        ProxyProvider3<
          ApiService,
          LocalDatabaseService,
          ConnectivityService,
          AnalyticsRepository
        >(
          update:
              (context, apiService, localDb, connectivity, __) =>
                  AnalyticsRepository(
                    apiService,
                    localDb,
                    connectivity,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters (matches ExerciseRepository's wiring above).
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),
        ProxyProvider4<
          ApiService,
          LocalDatabaseService,
          ConnectivityService,
          AuthService,
          ChatRepository
        >(
          update:
              (context, apiService, localDb, connectivity, authService, __) =>
                  ChatRepository(
                    apiService,
                    localDb,
                    connectivity,
                    authService,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters.
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),
        ProxyProvider4<
          ApiService,
          LocalDatabaseService,
          ConnectivityService,
          AuthService,
          SharedWorkoutRepository
        >(
          update:
              (context, apiService, localDb, connectivity, authService, __) =>
                  SharedWorkoutRepository(
                    apiService,
                    localDb,
                    connectivity,
                    authService,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters.
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),
        ProxyProvider4<
          ApiService,
          LocalDatabaseService,
          ConnectivityService,
          AuthService,
          WorkoutTemplateRepository
        >(
          update:
              (
                context,
                apiService,
                localDb,
                connectivity,
                authService,
                previous,
              ) =>
                  // Unlike the sibling session-ownership repositories, this one
                  // holds cross-operation instance state (its per-serverId write
                  // clock), so it must be a stable singleton: `previous ??` keeps
                  // the first instance rather than rebuilding it on every
                  // ConnectivityService notification. All four dependencies above
                  // are themselves stable singletons (`Provider`/`.value`), so a
                  // retained `previous` can never hold a stale collaborator.
                  previous ??
                  WorkoutTemplateRepository(
                    apiService,
                    localDb,
                    connectivity,
                    authService,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters.
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),
        ProxyProvider2<ApiService, ConnectivityService, GoalsRepository>(
          update:
              (context, apiService, connectivity, __) => GoalsRepository(
                apiService,
                // UserSessionEpoch and SessionRequestCoordinator are fixed
                // .value()/ProxyProvider singletons, never reactively
                // watched, so they are read directly here rather than added
                // as formal ProxyProvider type parameters (matches
                // BodyMetricsRepository's wiring below).
                context.read<UserSessionEpoch>(),
                context.read<SessionRequestCoordinator>(),
                connectivity,
              ),
        ),
        ProxyProvider2<ApiService, ConnectivityService, BodyMetricsRepository>(
          update:
              (context, apiService, connectivity, __) => BodyMetricsRepository(
                apiService,
                // UserSessionEpoch and SessionRequestCoordinator are fixed
                // .value()/ProxyProvider singletons, never reactively
                // watched, so they are read directly here rather than added
                // as formal ProxyProvider type parameters (matches
                // DirectMessagesRepository's wiring above).
                context.read<UserSessionEpoch>(),
                context.read<SessionRequestCoordinator>(),
                connectivity,
              ),
        ),
        ProxyProvider3<
          ApiService,
          ConnectivityService,
          LocalDatabaseService,
          ProgramsRepository
        >(
          update:
              (context, apiService, connectivity, localDb, __) =>
                  ProgramsRepository(
                    apiService,
                    // UserSessionEpoch and SessionRequestCoordinator are fixed
                    // .value()/ProxyProvider singletons, never reactively
                    // watched, so they are read directly here rather than added
                    // as formal ProxyProvider type parameters (matches
                    // GoalsRepository's wiring above).
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                    connectivity,
                    localDb,
                  ),
        ),
        ProxyProvider4<
          ApiService,
          LocalDatabaseService,
          ConnectivityService,
          AuthService,
          RunningRepository
        >(
          update:
              (context, apiService, localDb, connectivity, authService, __) =>
                  RunningRepository(
                    localDb,
                    connectivity,
                    authService,
                    apiService,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters.
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),
        ProxyProvider4<
          ApiService,
          LocalDatabaseService,
          ConnectivityService,
          AuthService,
          NutritionRepository
        >(
          update:
              (context, apiService, localDb, connectivity, authService, __) =>
                  NutritionRepository(
                    apiService,
                    localDb,
                    connectivity,
                    authService,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters.
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),
        ProxyProvider2<ApiService, ConnectivityService, FriendsRepository>(
          update:
              (context, apiService, connectivity, __) => FriendsRepository(
                apiService,
                connectivity,
                // UserSessionEpoch and SessionRequestCoordinator are fixed
                // .value()/ProxyProvider singletons, never reactively
                // watched, so they are read directly here rather than added
                // as formal ProxyProvider type parameters.
                context.read<UserSessionEpoch>(),
                context.read<SessionRequestCoordinator>(),
              ),
        ),
        ProxyProvider2<
          ApiService,
          ConnectivityService,
          DirectMessagesRepository
        >(
          update:
              (context, apiService, connectivity, __) =>
                  DirectMessagesRepository(
                    apiService,
                    connectivity,
                    // UserSessionEpoch and SessionRequestCoordinator are fixed
                    // .value()/ProxyProvider singletons, never reactively
                    // watched, so they are read directly here rather than added
                    // as formal ProxyProvider type parameters.
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),

        // Sync Service
        ProxyProvider4<
          ApiService,
          AuthService,
          LocalDatabaseService,
          ConnectivityService,
          SyncService
        >(
          update:
              (context, apiService, authService, localDb, connectivity, __) =>
                  SyncService(
                    apiService: apiService,
                    authService: authService,
                    localDb: localDb,
                    connectivity: connectivity,
                    // UserSessionEpoch and SessionRequestCoordinator are
                    // fixed .value()/ProxyProvider singletons, never
                    // reactively watched, so they are read directly here
                    // rather than added as formal ProxyProvider type
                    // parameters.
                    sessionEpoch: context.read<UserSessionEpoch>(),
                    sessionCoordinator:
                        context.read<SessionRequestCoordinator>(),
                  ),
        ),

        // Providers (state managers - equivalent to ViewModels)
        ChangeNotifierProxyProvider4<
          AuthRepository,
          AuthService,
          ApiService,
          LocalDatabaseService,
          AuthProvider
        >(
          create:
              (context) => AuthProvider(
                context.read<AuthRepository>(),
                context.read<AuthService>(),
                context.read<ApiService>(),
                context.read<LocalDatabaseService>(),
                // UserSessionEpoch and SessionRequestCoordinator are fixed
                // .value()/ProxyProvider singletons, never reactively
                // watched, so they are read directly here rather than added
                // as formal ProxyProvider type parameters.
                context.read<UserSessionEpoch>(),
                context.read<SessionRequestCoordinator>(),
              ),
          update:
              (context, authRepo, authService, apiService, localDb, previous) =>
                  previous ??
                  AuthProvider(
                    authRepo,
                    authService,
                    apiService,
                    localDb,
                    context.read<UserSessionEpoch>(),
                    context.read<SessionRequestCoordinator>(),
                  ),
        ),
        ChangeNotifierProxyProvider2<
          SessionRepository,
          ConnectivityService,
          SessionsProvider
        >(
          create:
              (context) => SessionsProvider(
                context.read<SessionRepository>(),
                // UserSessionEpoch is a fixed .value() singleton, never
                // reactively watched, so it is read directly here rather
                // than added as a formal ProxyProvider type parameter.
                context.read<UserSessionEpoch>(),
                context.read<ConnectivityService>(),
              ),
          update:
              (context, sessionRepo, connectivity, previous) =>
                  previous ??
                  SessionsProvider(
                    sessionRepo,
                    context.read<UserSessionEpoch>(),
                    connectivity,
                  ),
        ),
        ChangeNotifierProxyProvider2<
          SessionRepository,
          ConnectivityService,
          ActiveWorkoutProvider
        >(
          create:
              (context) => ActiveWorkoutProvider(
                context.read<SessionRepository>(),
                context.read<UserSessionEpoch>(),
                context.read<ConnectivityService>(),
              ),
          update:
              (context, sessionRepo, connectivity, previous) =>
                  previous ??
                  ActiveWorkoutProvider(
                    sessionRepo,
                    context.read<UserSessionEpoch>(),
                    connectivity,
                  ),
        ),
        ChangeNotifierProxyProvider2<
          ExerciseRepository,
          ConnectivityService,
          ExercisesProvider
        >(
          create:
              (context) => ExercisesProvider(
                context.read<ExerciseRepository>(),
                context.read<ConnectivityService>(),
              ),
          update:
              (_, exerciseRepo, connectivity, previous) =>
                  previous ?? ExercisesProvider(exerciseRepo, connectivity),
        ),
        ChangeNotifierProxyProvider<ExerciseRepository, ExerciseDetailProvider>(
          create:
              (context) =>
                  ExerciseDetailProvider(context.read<ExerciseRepository>()),
          update:
              (_, exerciseRepo, previous) =>
                  previous ?? ExerciseDetailProvider(exerciseRepo),
        ),
        ChangeNotifierProxyProvider<ExerciseRepository, LogSetsProvider>(
          create:
              (context) => LogSetsProvider(
                context.read<ExerciseRepository>(),
                // UserSessionEpoch is a fixed .value() singleton, never
                // reactively watched, so it is read directly here rather
                // than added as a formal ProxyProvider type parameter.
                context.read<UserSessionEpoch>(),
              ),
          update:
              (context, exerciseRepo, previous) =>
                  previous ??
                  LogSetsProvider(
                    exerciseRepo,
                    context.read<UserSessionEpoch>(),
                  ),
        ),
        ChangeNotifierProxyProvider3<
          ProfileRepository,
          AuthService,
          ConnectivityService,
          ProfileProvider
        >(
          create:
              (context) => ProfileProvider(
                context.read<ProfileRepository>(),
                context.read<AuthService>(),
                context.read<UserSessionEpoch>(),
                context.read<ConnectivityService>(),
              ),
          update:
              (context, profileRepo, authService, connectivity, previous) =>
                  previous ??
                  ProfileProvider(
                    profileRepo,
                    authService,
                    context.read<UserSessionEpoch>(),
                    connectivity,
                  ),
        ),
        ChangeNotifierProxyProvider<AnalyticsRepository, AnalyticsProvider>(
          create:
              (context) => AnalyticsProvider(
                context.read<AnalyticsRepository>(),
                context.read<UserSessionEpoch>(),
              ),
          update:
              (context, analyticsRepo, previous) =>
                  previous ??
                  AnalyticsProvider(
                    analyticsRepo,
                    context.read<UserSessionEpoch>(),
                  ),
        ),
        ChangeNotifierProxyProvider2<
          ChatRepository,
          ConnectivityService,
          ChatProvider
        >(
          create:
              (context) => ChatProvider(
                context.read<ChatRepository>(),
                context.read<ConnectivityService>(),
                context.read<UserSessionEpoch>(),
              ),
          update:
              (context, chatRepo, connectivity, previous) =>
                  previous ??
                  ChatProvider(
                    chatRepo,
                    connectivity,
                    context.read<UserSessionEpoch>(),
                  ),
        ),
        ChangeNotifierProxyProvider2<
          SharedWorkoutRepository,
          ConnectivityService,
          SharedWorkoutProvider
        >(
          create:
              (context) => SharedWorkoutProvider(
                context.read<SharedWorkoutRepository>(),
                context.read<ConnectivityService>(),
                context.read<UserSessionEpoch>(),
              ),
          update:
              (context, sharedWorkoutRepo, connectivity, previous) =>
                  previous ??
                  SharedWorkoutProvider(
                    sharedWorkoutRepo,
                    connectivity,
                    context.read<UserSessionEpoch>(),
                  ),
        ),
        ChangeNotifierProxyProvider2<
          WorkoutTemplateRepository,
          ConnectivityService,
          WorkoutTemplateProvider
        >(
          create:
              (context) => WorkoutTemplateProvider(
                context.read<WorkoutTemplateRepository>(),
                context.read<ConnectivityService>(),
                context.read<UserSessionEpoch>(),
              ),
          update:
              (context, workoutTemplateRepo, connectivity, previous) =>
                  previous ??
                  WorkoutTemplateProvider(
                    workoutTemplateRepo,
                    connectivity,
                    context.read<UserSessionEpoch>(),
                  ),
        ),
        ChangeNotifierProxyProvider2<
          GoalsRepository,
          ConnectivityService,
          GoalsProvider
        >(
          create:
              (context) => GoalsProvider(
                context.read<GoalsRepository>(),
                // UserSessionEpoch is a fixed .value() singleton, never
                // reactively watched, so it is read directly here rather
                // than added as a formal ProxyProvider type parameter.
                context.read<UserSessionEpoch>(),
                context.read<ConnectivityService>(),
              ),
          update:
              (context, goalsRepo, connectivity, previous) =>
                  previous ??
                  GoalsProvider(
                    goalsRepo,
                    context.read<UserSessionEpoch>(),
                    connectivity,
                  ),
        ),
        ChangeNotifierProxyProvider2<
          BodyMetricsRepository,
          ConnectivityService,
          BodyMetricsProvider
        >(
          create:
              (context) => BodyMetricsProvider(
                context.read<BodyMetricsRepository>(),
                // UserSessionEpoch is a fixed .value() singleton, never
                // reactively watched, so it is read directly here rather
                // than added as a formal ProxyProvider type parameter.
                context.read<UserSessionEpoch>(),
                context.read<ConnectivityService>(),
              ),
          update:
              (context, bodyMetricsRepo, connectivity, previous) =>
                  previous ??
                  BodyMetricsProvider(
                    bodyMetricsRepo,
                    context.read<UserSessionEpoch>(),
                    connectivity,
                  ),
        ),
        ChangeNotifierProxyProvider2<
          ProgramsRepository,
          ConnectivityService,
          ProgramsProvider
        >(
          create:
              (context) => ProgramsProvider(
                context.read<ProgramsRepository>(),
                // UserSessionEpoch is a fixed .value() singleton, never
                // reactively watched, so it is read directly here rather
                // than added as a formal ProxyProvider type parameter.
                context.read<UserSessionEpoch>(),
                context.read<ConnectivityService>(),
              ),
          update:
              (context, programsRepo, connectivity, previous) =>
                  previous ??
                  ProgramsProvider(
                    programsRepo,
                    context.read<UserSessionEpoch>(),
                    connectivity,
                  ),
        ),
        ChangeNotifierProxyProvider2<
          RunningRepository,
          ConnectivityService,
          RunningProvider
        >(
          create:
              (context) => RunningProvider(
                context.read<RunningRepository>(),
                // UserSessionEpoch is a fixed .value() singleton, never
                // reactively watched, so it is read directly here rather
                // than added as a formal ProxyProvider type parameter.
                context.read<UserSessionEpoch>(),
                context.read<ConnectivityService>(),
              ),
          update:
              (context, runningRepo, connectivity, previous) =>
                  previous ??
                  RunningProvider(
                    runningRepo,
                    context.read<UserSessionEpoch>(),
                    connectivity,
                  ),
        ),
        ChangeNotifierProxyProvider2<
          NutritionRepository,
          ConnectivityService,
          NutritionProvider
        >(
          create:
              (context) => NutritionProvider(
                context.read<NutritionRepository>(),
                // UserSessionEpoch is a fixed .value() singleton, never
                // reactively watched, so it is read directly here rather
                // than added as a formal ProxyProvider type parameter.
                context.read<UserSessionEpoch>(),
                context.read<ConnectivityService>(),
              ),
          update:
              (context, nutritionRepo, connectivity, previous) =>
                  previous ??
                  NutritionProvider(
                    nutritionRepo,
                    context.read<UserSessionEpoch>(),
                    connectivity,
                  ),
        ),
        ChangeNotifierProvider<MusicPlayerProvider>(
          create: (_) => MusicPlayerProvider(),
        ),
        ChangeNotifierProvider<TabNavigationService>(
          create: (_) => TabNavigationService(),
        ),
        ChangeNotifierProxyProvider2<
          FlutterSecureStorage,
          NotificationService,
          SettingsProvider
        >(
          create:
              (context) => SettingsProvider(
                context.read<FlutterSecureStorage>(),
                context.read<NotificationService>(),
              ),
          update:
              (_, storage, notificationService, previous) =>
                  previous ?? SettingsProvider(storage, notificationService),
        ),

        // Onboarding provider (no dependencies)
        ChangeNotifierProvider<OnboardingProvider>(
          create: (_) => OnboardingProvider()..initialize(),
        ),

        // Achievement repository
        ProxyProvider2<
          LocalDatabaseService,
          AuthService,
          AchievementRepository
        >(
          update:
              (_, localDb, authService, __) => AchievementRepository(
                localDb: localDb,
                authService: authService,
              ),
        ),

        // Achievements provider
        ChangeNotifierProxyProvider<
          AchievementRepository,
          AchievementsProvider
        >(
          create:
              (context) =>
                  AchievementsProvider(context.read<AchievementRepository>()),
          update:
              (_, achievementRepo, previous) =>
                  previous ?? AchievementsProvider(achievementRepo),
        ),

        // Friends provider
        ChangeNotifierProxyProvider<FriendsRepository, FriendsProvider>(
          create:
              (context) => FriendsProvider(
                context.read<FriendsRepository>(),
                // UserSessionEpoch is a fixed .value() singleton, never
                // reactively watched, so it is read directly here rather
                // than added as a formal ProxyProvider type parameter.
                context.read<UserSessionEpoch>(),
              ),
          update:
              (context, friendsRepo, previous) =>
                  previous ??
                  FriendsProvider(
                    friendsRepo,
                    context.read<UserSessionEpoch>(),
                  ),
        ),

        // Messages provider
        ChangeNotifierProxyProvider<DirectMessagesRepository, MessagesProvider>(
          create:
              (context) => MessagesProvider(
                context.read<DirectMessagesRepository>(),
                // UserSessionEpoch is a fixed .value() singleton, never
                // reactively watched, so it is read directly here rather
                // than added as a formal ProxyProvider type parameter.
                context.read<UserSessionEpoch>(),
              ),
          update:
              (context, messagesRepo, previous) =>
                  previous ??
                  MessagesProvider(
                    messagesRepo,
                    context.read<UserSessionEpoch>(),
                  ),
        ),
      ],
      child: SyncServiceInitializer(
        child: SessionCleanupInitializer(
          navigatorKey: appNavigatorKey,
          child: const MyApp(),
        ),
      ),
    ),
  );
}
