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
  return SessionRepository(apiService, localDb, connectivity, authService);
});

/// Exercise repository provider
final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return ExerciseRepository(apiService, localDb, connectivity);
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
  return ProfileRepository(apiService, authService, connectivity);
});

/// Analytics repository provider
final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final authService = ref.watch(authServiceProvider);
  return AnalyticsRepository(apiService, localDb, connectivity, authService);
});

/// Chat repository provider
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final authService = ref.watch(authServiceProvider);
  return ChatRepository(apiService, localDb, connectivity, authService);
});

/// Shared workout repository provider
final sharedWorkoutRepositoryProvider = Provider<SharedWorkoutRepository>((
  ref,
) {
  final apiService = ref.watch(apiServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final authService = ref.watch(authServiceProvider);
  return SharedWorkoutRepository(
    apiService,
    localDb,
    connectivity,
    authService,
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
  return WorkoutTemplateRepository(
    apiService,
    localDb,
    connectivity,
    authService,
  );
});

/// Goals repository provider
final goalsRepositoryProvider = Provider<GoalsRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return GoalsRepository(apiService, connectivity);
});

/// Body metrics repository provider
final bodyMetricsRepositoryProvider = Provider<BodyMetricsRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return BodyMetricsRepository(apiService, connectivity);
});

/// Programs repository provider
final programsRepositoryProvider = Provider<ProgramsRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final authService = ref.watch(authServiceProvider);
  return ProgramsRepository(apiService, connectivity, localDb, authService);
});

/// Running repository provider
final runningRepositoryProvider = Provider<RunningRepository>((ref) {
  final localDb = ref.watch(localDatabaseServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final authService = ref.watch(authServiceProvider);
  final apiService = ref.watch(apiServiceProvider);
  return RunningRepository(localDb, connectivity, authService, apiService);
});

/// Achievement repository provider
final achievementRepositoryProvider = Provider<AchievementRepository>((ref) {
  final localDb = ref.watch(localDatabaseServiceProvider);
  final authService = ref.watch(authServiceProvider);
  return AchievementRepository(localDb: localDb, authService: authService);
});
