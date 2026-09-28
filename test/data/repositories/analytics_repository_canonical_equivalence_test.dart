import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/core/utils/unit_converter.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/repositories/analytics_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';

import 'analytics_repository_session_ownership_test.mocks.dart';

/// Proves that the same physical workout, logged while the user's unit
/// preference is Imperial vs. Metric, produces identical canonical (kg)
/// analytics. [UnitConverter.liftedInputToKg] is the only input boundary -
/// the repository's offline volume/PR calculations never see or care which
/// unit the value was entered in.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late AnalyticsRepository repository;

  const userA = 1; // logged the workout while Imperial
  const userB = 2; // logged the identical workout while Metric

  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'analytics_repo_equivalence_',
    );
    isar = await Isar.open(
      [
        LocalSessionSchema,
        LocalExerciseSchema,
        LocalExerciseSetSchema,
        LocalExerciseTemplateSchema,
      ],
      directory: tempDir.path,
      inspector: false,
    );

    currentAuthUserId = null;
    mockAuthService = MockAuthService();
    mockConnectivity = MockConnectivityService();
    when(mockConnectivity.isOnline).thenReturn(false); // force local calc
    when(
      mockAuthService.getUserId(),
    ).thenAnswer((_) async => currentAuthUserId);
    when(mockAuthService.getToken()).thenAnswer(
      (_) async => currentAuthUserId == null ? null : 'jwt-$currentAuthUserId',
    );

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch();
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );
    apiService = ApiService(mockAuthService, sessionEpoch);

    repository = AnalyticsRepository(
      apiService,
      localDb,
      mockConnectivity,
      sessionEpoch,
      sessionCoordinator,
    );
  });

  tearDown(() async {
    if (isar.isOpen) await isar.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  void loginAs(int userId) {
    currentAuthUserId = userId;
    sessionEpoch.activate(userId);
  }

  /// One completed session -> one exercise (template 11) -> five single-rep
  /// sets, each at [weightKg] - the whole graph's volume is `5 * weightKg`.
  Future<void> logFiveSingleRepSets({
    required int uid,
    required double weightKg,
  }) async {
    final now = DateTime.now();
    final session = LocalSession(
      userId: uid,
      date: now.subtract(const Duration(days: 1)),
      status: 'completed',
      duration: 600,
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localSessions.put(session));

    final exercise = LocalExercise(
      sessionLocalId: session.localId,
      name: 'Bench Press',
      exerciseTemplateId: 11,
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localExercises.put(exercise));

    for (var i = 0; i < 5; i++) {
      final set = LocalExerciseSet(
        exerciseLocalId: exercise.localId,
        setNumber: i + 1,
        reps: 1,
        weight: weightKg,
        isCompleted: true,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: now,
      );
      await isar.writeTxn(() => isar.localExerciseSets.put(set));
    }
  }

  test('lb-entered and kg-entered identical workouts yield equal canonical kg '
      'volume, totalVolume and personal records', () async {
    const expectedVolumeKg = 306.17484975;
    final weightFromLb = UnitConverter.liftedInputToKg(135, 'Imperial');
    final weightFromKg = UnitConverter.liftedInputToKg(61.23496995, 'Metric');
    expect(weightFromLb, closeTo(expectedVolumeKg / 5, 1e-6));
    expect(weightFromKg, closeTo(expectedVolumeKg / 5, 1e-6));

    await logFiveSingleRepSets(uid: userA, weightKg: weightFromLb);
    await logFiveSingleRepSets(uid: userB, weightKg: weightFromKg);

    loginAs(userA);
    final aVolume = await repository.getVolumeOverTime();
    final aStats = await repository.getWorkoutStats();
    final aPrs = await repository.getPersonalRecords();

    loginAs(userB);
    final bVolume = await repository.getVolumeOverTime();
    final bStats = await repository.getWorkoutStats();
    final bPrs = await repository.getPersonalRecords();

    // Both are in kg, and both equal the expected canonical volume.
    expect(aVolume.single.value, closeTo(expectedVolumeKg, 1e-6));
    expect(bVolume.single.value, closeTo(expectedVolumeKg, 1e-6));
    expect(aVolume.single.value, closeTo(bVolume.single.value, 1e-6));

    expect(aStats.totalVolume, closeTo(expectedVolumeKg, 1e-6));
    expect(bStats.totalVolume, closeTo(expectedVolumeKg, 1e-6));
    expect(aStats.totalVolume, closeTo(bStats.totalVolume, 1e-6));

    expect(aPrs, hasLength(1));
    expect(bPrs, hasLength(1));
    expect(aPrs.single.weight, closeTo(bPrs.single.weight, 1e-6));
    expect(
      aPrs.single.estimatedOneRepMax,
      closeTo(bPrs.single.estimatedOneRepMax, 1e-6),
    );
    expect(aPrs.single.weight, closeTo(expectedVolumeKg / 5, 1e-6));
  });
}
