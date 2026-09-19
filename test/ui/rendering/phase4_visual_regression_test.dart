import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/core/theme/app_theme.dart';
import 'package:go_hard_app/data/models/daily_nutrition_progress.dart';
import 'package:go_hard_app/data/models/meal_entry.dart';
import 'package:go_hard_app/data/models/meal_log.dart';
import 'package:go_hard_app/data/models/nutrition_goal.dart';
import 'package:go_hard_app/data/models/nutrition_summary.dart';
import 'package:go_hard_app/data/models/program.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/data/repositories/programs_repository.dart';
import 'package:go_hard_app/data/repositories/running_repository.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';
import 'package:go_hard_app/providers/programs_provider.dart';
import 'package:go_hard_app/providers/running_provider.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';
import 'package:go_hard_app/ui/screens/programs/programs_screen.dart';
import 'package:go_hard_app/ui/screens/nutrition/nutrition_dashboard_screen.dart';
import 'package:go_hard_app/ui/screens/today/today_screen.dart';

@GenerateMocks([
  SessionRepository,
  ConnectivityService,
  ProgramsRepository,
  RunningRepository,
  NutritionRepository,
])
import 'phase4_visual_regression_test.mocks.dart';

/// Rendered-fixture verification for the Phase-4 polish pass: the real
/// production widgets, mounted with deterministic mocked repositories (no
/// live backend, no device), checked under three axes real users hit -
/// dark theme, a small-iPhone-class narrow width, and a large accessibility
/// text scale - asserting no dropped frame exceptions and no RenderFlex
/// overflow. This is automated rendered-fixture evidence, NOT a physical
/// device/VoiceOver/native-keyboard observation; see the task report for
/// what still needs a real device.
///
/// `pumpAndSettle()` is avoided throughout because ProgramsScreen's week
/// calendar runs a perpetual pulse animation - bounded `pump()` calls are
/// used instead, matching test/ui/screens/programs/
/// programs_screen_mutation_feedback_test.dart's established pattern for
/// the same screen.
void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> expectNoRenderExceptions(
    WidgetTester tester,
    Widget Function() buildHost, {
    required String label,
  }) async {
    for (final variation in [
      (
        name: 'dark theme',
        theme: AppTheme.darkTheme,
        size: const Size(390, 844), // ordinary phone width, for isolation
        textScale: 1.0,
      ),
      (
        name: 'narrow width (iPhone SE class, 320pt)',
        theme: AppTheme.lightTheme,
        size: const Size(320, 568),
        textScale: 1.0,
      ),
      (
        name: 'large text scale (2.0x)',
        theme: AppTheme.lightTheme,
        size: const Size(390, 844),
        textScale: 2.0,
      ),
    ]) {
      tester.view.physicalSize = variation.size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: variation.theme,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(variation.textScale)),
              child: child!,
            );
          },
          home: buildHost(),
        ),
      );
      await settle(tester);
      await settle(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: '$label under ${variation.name} threw an exception',
      );
    }
  }

  group('TodayScreen rendered-fixture checks', () {
    late MockSessionRepository sessionRepo;
    late MockConnectivityService connectivity;
    late MockProgramsRepository programsRepo;
    late MockRunningRepository runningRepo;
    late MockNutritionRepository nutritionRepo;
    late UserSessionEpoch epoch;
    late List<StreamController<SessionSyncSnapshot>> watchControllers;
    late StreamController<bool> connectivityController;

    setUp(() {
      sessionRepo = MockSessionRepository();
      connectivity = MockConnectivityService();
      programsRepo = MockProgramsRepository();
      runningRepo = MockRunningRepository();
      nutritionRepo = MockNutritionRepository();
      watchControllers = [];
      connectivityController = StreamController<bool>.broadcast(sync: true);

      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      when(
        sessionRepo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer(
        (_) async => [
          Session(
            id: 1,
            userId: 1,
            date: todayDate,
            name: 'Leg Day - Heavy Squats and Deadlifts',
            status: 'planned',
          ),
        ],
      );
      when(sessionRepo.watchSessionSyncSnapshot(any)).thenAnswer((_) {
        final c = StreamController<SessionSyncSnapshot>(sync: true);
        watchControllers.add(c);
        return c.stream;
      });
      when(connectivity.isOnline).thenReturn(true);
      when(
        connectivity.connectivityStream,
      ).thenAnswer((_) => connectivityController.stream);
      when(
        programsRepo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => <Program>[]);
      when(
        runningRepo.getRecentRuns(limit: anyNamed('limit')),
      ).thenAnswer((_) async => []);
      when(
        runningRepo.getWeeklyStats(),
      ).thenAnswer((_) async => <String, dynamic>{});
      when(nutritionRepo.getTodaysMealLog(date: anyNamed('date'))).thenAnswer(
        (_) async =>
            MealLog(id: 1, userId: 1, date: todayDate, createdAt: todayDate),
      );
      when(
        nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer(
        (_) async => NutritionDashboardData(
          date: todayDate,
          goal: NutritionGoal(id: 1, userId: 1, createdAt: todayDate),
          progress: DailyNutritionProgress(
            id: 0,
            userId: 1,
            date: todayDate,
            createdAt: todayDate,
          ),
        ),
      );
      when(nutritionRepo.getStreak()).thenAnswer((_) async => StreakInfo());
      when(
        nutritionRepo.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
          page: anyNamed('page'),
          pageSize: anyNamed('pageSize'),
        ),
      ).thenAnswer((_) async => <MealLog>[]);

      epoch = UserSessionEpoch()..activate(1);
    });

    tearDown(() async {
      for (final c in watchControllers) {
        if (!c.isClosed) await c.close();
      }
      if (!connectivityController.isClosed) {
        await connectivityController.close();
      }
    });

    testWidgets('renders with no exceptions/overflow under dark theme, narrow '
        'width, and large text scale', (tester) async {
      // Construct every provider exactly once and reuse the same
      // instances across all three variations below - otherwise each
      // variation would re-trigger a fresh async load, racing against
      // the bounded settle() pumps and risking a spurious loading/empty
      // flash that has nothing to do with the theme/size/text-scale
      // actually under test.
      final sessionsProvider = SessionsProvider(
        sessionRepo,
        epoch,
        connectivity,
      );
      final activeWorkoutProvider = ActiveWorkoutProvider(
        sessionRepo,
        epoch,
        connectivity,
      );
      final programsProvider = ProgramsProvider(
        programsRepo,
        epoch,
        connectivity,
      );
      final runningProvider = RunningProvider(runningRepo, epoch, connectivity);
      final nutritionProvider = NutritionProvider(
        nutritionRepo,
        epoch,
        connectivity,
      );

      await expectNoRenderExceptions(
        tester,
        () => MultiProvider(
          providers: [
            ChangeNotifierProvider<ConnectivityService>.value(
              value: connectivity,
            ),
            ChangeNotifierProvider<SessionsProvider>.value(
              value: sessionsProvider,
            ),
            ChangeNotifierProvider<ActiveWorkoutProvider>.value(
              value: activeWorkoutProvider,
            ),
            ChangeNotifierProvider<ProgramsProvider>.value(
              value: programsProvider,
            ),
            ChangeNotifierProvider<RunningProvider>.value(
              value: runningProvider,
            ),
            ChangeNotifierProvider<NutritionProvider>.value(
              value: nutritionProvider,
            ),
          ],
          child: const Scaffold(body: TodayScreen()),
        ),
        label: 'TodayScreen',
      );
    });
  });

  group('NutritionDashboardScreen rendered-fixture checks', () {
    late MockNutritionRepository nutritionRepo;
    late MockConnectivityService connectivity;
    late UserSessionEpoch epoch;

    setUp(() {
      nutritionRepo = MockNutritionRepository();
      connectivity = MockConnectivityService();
      epoch = UserSessionEpoch()..activate(1);

      when(connectivity.isOnline).thenReturn(true);
      when(
        connectivity.connectivityStream,
      ).thenAnswer((_) => const Stream<bool>.empty());

      final now = DateTime.now();
      when(nutritionRepo.getTodaysMealLog(date: anyNamed('date'))).thenAnswer(
        (_) async => MealLog(
          id: 1,
          userId: 1,
          date: now,
          createdAt: now,
          mealEntries: [
            MealEntry(
              id: 1,
              mealLogId: 1,
              mealType: 'Breakfast',
              isConsumed: true,
              totalCalories: 300,
              totalProtein: 20,
              totalCarbohydrates: 35,
              totalFat: 9,
              createdAt: now,
            ),
          ],
        ),
      );
      when(
        nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer(
        (_) async => NutritionDashboardData(
          date: now,
          goal: NutritionGoal(
            id: 1,
            userId: 1,
            createdAt: now,
            dailyCalories: 2000,
            dailyProtein: 150,
            dailyCarbohydrates: 200,
            dailyFat: 65,
          ),
          progress: DailyNutritionProgress(
            id: 1,
            userId: 1,
            date: now,
            createdAt: now,
          ),
        ),
      );
      when(nutritionRepo.getStreak()).thenAnswer((_) async => StreakInfo());
      when(
        nutritionRepo.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) async => <MealLog>[]);
    });

    testWidgets('renders with no exceptions/overflow under dark theme, narrow '
        'width, and large text scale', (tester) async {
      final nutritionProvider = NutritionProvider(
        nutritionRepo,
        epoch,
        connectivity,
      );

      await expectNoRenderExceptions(
        tester,
        () => MultiProvider(
          providers: [
            ChangeNotifierProvider<NutritionProvider>.value(
              value: nutritionProvider,
            ),
            ChangeNotifierProvider<ConnectivityService>.value(
              value: connectivity,
            ),
          ],
          child: const Scaffold(body: NutritionDashboardScreen()),
        ),
        label: 'NutritionDashboardScreen',
      );
    });
  });

  group('ProgramsScreen rendered-fixture checks', () {
    late MockProgramsRepository programsRepo;
    late UserSessionEpoch epoch;

    Program program(int id) => Program(
      id: id,
      userId: 1,
      title: 'A Fairly Long Program Title To Stress Narrow Widths',
      totalWeeks: 8,
      currentWeek: 3,
      currentDay: 2,
      startDate: DateTime(2024, 1, 1),
      isActive: true,
      isCompleted: false,
      createdAt: DateTime(2024, 1, 1),
      workouts: [
        ProgramWorkout(
          id: 1,
          programId: id,
          weekNumber: 3,
          dayNumber: 2,
          workoutName: 'Upper Body Push',
          workoutType: 'Strength',
          exercisesJson: '[]',
          isCompleted: false,
          orderIndex: 0,
          scheduledDate: DateTime.now(),
        ),
      ],
    );

    setUp(() {
      programsRepo = MockProgramsRepository();
      epoch = UserSessionEpoch()..activate(1);
      when(
        programsRepo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program(1)]);
    });

    testWidgets('renders with no exceptions/overflow under dark theme, narrow '
        'width, and large text scale', (tester) async {
      final programsProvider = ProgramsProvider(programsRepo, epoch);

      await expectNoRenderExceptions(
        tester,
        () => ChangeNotifierProvider<ProgramsProvider>.value(
          value: programsProvider,
          child: const Scaffold(body: ProgramsScreen()),
        ),
        label: 'ProgramsScreen',
      );
    });
  });
}
