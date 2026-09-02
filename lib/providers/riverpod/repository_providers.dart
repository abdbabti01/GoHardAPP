/// Repository providers for data access layer.
/// These replace the ProxyProvider setup in the old Provider configuration.
///
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/shared_workout_repository.dart';
import '../../data/repositories/workout_template_repository.dart';
import '../../data/repositories/goals_repository.dart';
import '../../data/repositories/body_metrics_repository.dart';
import '../../data/repositories/programs_repository.dart';
import '../../data/repositories/running_repository.dart';
import '../../data/repositories/achievement_repository.dart';

import 'core_providers.dart';

// ============================================================
// Repository Providers
// ============================================================

/// Auth repository provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return AuthRepository(apiService);
});

/// Session repository provider
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return SessionRepository(
    apiService,
    localDb,
    connectivity,
    authService,
    sessionEpoch,
    sessionCoordinator,
  );
});

/// Exercise repository provider
final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return ExerciseRepository(
    apiService,
    localDb,
    connectivity,
    sessionEpoch,
    sessionCoordinator,
  );
});

/// User repository provider
final userRepositoryProvider = Provider<UserRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return UserRepository(apiService);
});

/// Profile repository provider
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return ProfileRepository(
    apiService,
    authService,
    sessionEpoch,
    sessionCoordinator,
    connectivity,
  );
});

/// Analytics repository provider
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return AnalyticsRepository(
    apiService,
    localDb,
    connectivity,
    sessionEpoch,
    sessionCoordinator,
  );
});

/// Chat repository provider
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return ChatRepository(
    apiService,
    localDb,
    connectivity,
    authService,
    sessionEpoch,
    sessionCoordinator,
  );
});

/// Shared workout repository provider
final sharedWorkoutRepositoryProvider = Provider<SharedWorkoutRepository>((
  ref,
) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return SharedWorkoutRepository(
    apiService,
    localDb,
    connectivity,
    authService,
    sessionEpoch,
    sessionCoordinator,
  );
});

/// Workout template repository provider
final workoutTemplateRepositoryProvider = Provider<WorkoutTemplateRepository>((
  ref,
) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return WorkoutTemplateRepository(
    apiService,
    localDb,
    connectivity,
    authService,
    sessionEpoch,
    sessionCoordinator,
  );
});

/// Goals repository provider
final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return GoalsRepository(
    apiService,
    sessionEpoch,
    sessionCoordinator,
    connectivity,
  );
});

/// Body metrics repository provider
final bodyMetricsRepositoryProvider = Provider<BodyMetricsRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return BodyMetricsRepository(
    apiService,
    sessionEpoch,
    sessionCoordinator,
    connectivity,
  );
});

/// Programs repository provider
final programsRepositoryProvider = Provider<ProgramsRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return ProgramsRepository(
    apiService,
    sessionEpoch,
    sessionCoordinator,
    connectivity,
    localDb,
  );
});

/// Running repository provider
final runningRepositoryProvider = Provider<RunningRepository>((ref) {
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final apiService = ref.watch(apiServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  final sessionCoordinator = ref.watch(sessionRequestCoordinatorProvider);
  return RunningRepository(
    localDb,
    connectivity,
    authService,
    apiService,
    sessionEpoch,
    sessionCoordinator,
  );
});

/// Achievement repository provider
final achievementRepositoryProvider = Provider<AchievementRepository>((ref) {
  final localDb = ref.watch(localDatabaseServiceProvider);
  final authService = ref.watch(authServiceProvider);
  return AchievementRepository(localDb: localDb, authService: authService);
});
