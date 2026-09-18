import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
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
import 'package:go_hard_app/ui/screens/today/today_screen.dart';

@GenerateMocks([
  SessionRepository,
  ConnectivityService,
  ProgramsRepository,
  RunningRepository,
  NutritionRepository,
])
import 'today_screen_state_test.mocks.dart';

/// Stubs a clean, error-free, real-goal nutrition load so tests focused on
/// the workouts/programs sections aren't cluttered by the nutrition
/// section's own independent loading/error UI.
void _stubHealthyNutrition(
  MockNutritionRepository nutritionRepo,
  DateTime todayDate,
) {
  when(nutritionRepo.getTodaysMealLog(date: anyNamed('date'))).thenAnswer(
    (_) async =>
        MealLog(id: 1, userId: 1, date: todayDate, createdAt: todayDate),
  );
  when(nutritionRepo.getNutritionDashboard(date: anyNamed('date'))).thenAnswer(
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
}

/// Today must represent actual state: loading is never mistaken for empty,
/// one section's failure never hides another's good data, cached content
/// survives a failed refresh, and a genuine rest day is distinguished from
/// a program that simply has nothing scheduled today - across multiple
/// concurrently active programs. Same real-TodayScreen-through-real-
/// providers harness as today_screen_navigation_test.dart.
void main() {
  late MockSessionRepository sessionRepo;
  late MockConnectivityService connectivity;
  late MockProgramsRepository programsRepo;
  late MockRunningRepository runningRepo;
  late MockNutritionRepository nutritionRepo;
  late UserSessionEpoch epoch;
  late List<StreamController<SessionSyncSnapshot>> watchControllers;
  late StreamController<bool> connectivityController;
  late SessionsProvider sessionsProvider;
  late ActiveWorkoutProvider activeWorkoutProvider;
  late ProgramsProvider programsProvider;
  late RunningProvider runningProvider;
  late NutritionProvider nutritionProvider;

  Program program(
    int id, {
    bool active = true,
    String title = 'P',
    List<ProgramWorkout>? workouts,
  }) => Program(
    id: id,
    userId: 1,
    title: title,
    totalWeeks: 4,
    currentWeek: 1,
    currentDay: 1,
    startDate: DateTime(2020, 1, 6),
    isActive: active,
    isCompleted: false,
    createdAt: DateTime(2020, 1, 6),
    workouts: workouts,
  );

  ProgramWorkout workout(
    int id, {
    required int programId,
    required DateTime scheduledDate,
    bool isRestDay = false,
    String name = 'Workout',
  }) => ProgramWorkout(
    id: id,
    programId: programId,
    weekNumber: 1,
    dayNumber: 1,
    workoutName: name,
    workoutType: isRestDay ? 'Rest' : 'Strength',
    exercisesJson: '[]',
    isCompleted: false,
    orderIndex: 0,
    scheduledDate: scheduledDate,
  );

  setUp(() {
    sessionRepo = MockSessionRepository();
    connectivity = MockConnectivityService();
    programsRepo = MockProgramsRepository();
    runningRepo = MockRunningRepository();
    nutritionRepo = MockNutritionRepository();
    watchControllers = [];
    connectivityController = StreamController<bool>.broadcast(sync: true);

    when(
      sessionRepo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => <Session>[]);
    when(sessionRepo.watchSessionSyncSnapshot(any)).thenAnswer((_) {
      final c = StreamController<SessionSyncSnapshot>(sync: true);
      watchControllers.add(c);
      return c.stream;
    });

    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);

    epoch = UserSessionEpoch()..activate(1);
    sessionsProvider = SessionsProvider(sessionRepo, epoch, connectivity);
    activeWorkoutProvider = ActiveWorkoutProvider(
      sessionRepo,
      epoch,
      connectivity,
    );
    programsProvider = ProgramsProvider(programsRepo, epoch, connectivity);
    runningProvider = RunningProvider(runningRepo, epoch, connectivity);
    nutritionProvider = NutritionProvider(nutritionRepo, epoch, connectivity);
  });

  tearDown(() async {
    sessionsProvider.dispose();
    activeWorkoutProvider.dispose();
    for (final c in watchControllers) {
      if (!c.isClosed) await c.close();
    }
    if (!connectivityController.isClosed) await connectivityController.close();
  });

  Widget host() => MultiProvider(
    providers: [
      ChangeNotifierProvider<ConnectivityService>.value(value: connectivity),
      ChangeNotifierProvider<SessionsProvider>.value(value: sessionsProvider),
      ChangeNotifierProvider<ActiveWorkoutProvider>.value(
        value: activeWorkoutProvider,
      ),
      ChangeNotifierProvider<ProgramsProvider>.value(value: programsProvider),
      ChangeNotifierProvider<RunningProvider>.value(value: runningProvider),
      ChangeNotifierProvider<NutritionProvider>.value(value: nutritionProvider),
    ],
    child: const MaterialApp(home: Scaffold(body: TodayScreen())),
  );

  testWidgets(
    'a slow initial programs/sessions load shows a spinner, never "No '
    'workouts scheduled" - loading is never mistaken for confirmed-empty',
    (tester) async {
      final programsCompleter = Completer<List<Program>>();
      when(
        programsRepo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => programsCompleter.future);

      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('No workouts scheduled'), findsNothing);
      expect(find.text('Rest day - enjoy the recovery'), findsNothing);

      programsCompleter.complete(<Program>[]);
      await tester.pump();
      await tester.pump();

      expect(find.text('No workouts scheduled'), findsOneWidget);
    },
  );

  testWidgets(
    'a programs-load failure shows a retryable error but does not blank out '
    'sessions that loaded successfully',
    (tester) async {
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
            name: 'Leg Day',
            status: 'planned',
          ),
        ],
      );
      when(
        programsRepo.getPrograms(isActive: anyNamed('isActive')),
      ).thenThrow(Exception('network error'));
      _stubHealthyNutrition(nutritionRepo, todayDate);

      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The session that loaded fine is still shown.
      expect(find.text('Leg Day'), findsOneWidget);
      // The programs failure is surfaced with a working retry action, not
      // silently swallowed into a false "nothing scheduled" claim - scoped
      // to the workouts card specifically, since an unrelated nutrition
      // section is stubbed to succeed cleanly in this test.
      expect(find.text('No workouts scheduled'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'cached programs survive a subsequent failed refresh - pull-to-refresh '
    'failing does not blank previously-loaded workouts',
    (tester) async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final p = program(
        1,
        workouts: [
          workout(10, programId: 1, scheduledDate: todayDate, name: 'Push Day'),
        ],
      );
      var callCount = 0;
      when(programsRepo.getPrograms(isActive: anyNamed('isActive'))).thenAnswer(
        (_) async {
          callCount++;
          if (callCount == 1) return [p];
          throw Exception('network error');
        },
      );
      _stubHealthyNutrition(nutritionRepo, todayDate);

      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Push Day'), findsOneWidget);

      // Force a second (failing) load without going through pull-to-refresh
      // gesture mechanics.
      await programsProvider.loadPrograms();
      await tester.pump();
      await tester.pump();

      // Still there - the failed refresh didn't clear it.
      expect(find.text('Push Day'), findsOneWidget);
    },
  );

  testWidgets(
    'two concurrently active programs: one with a real workout today and '
    'one on a rest day both surface correctly - the workout wins, no false '
    '"rest day" for everyone',
    (tester) async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final programWithWorkout = program(
        1,
        title: 'Strength',
        workouts: [
          workout(
            10,
            programId: 1,
            scheduledDate: todayDate,
            name: 'Bench Press Day',
          ),
        ],
      );
      final programOnRestDay = program(
        2,
        title: 'Cardio',
        workouts: [
          workout(
            20,
            programId: 2,
            scheduledDate: todayDate,
            isRestDay: true,
            name: 'Rest',
          ),
        ],
      );
      when(
        programsRepo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [programWithWorkout, programOnRestDay]);
      _stubHealthyNutrition(nutritionRepo, todayDate);

      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Bench Press Day'), findsOneWidget);
      expect(find.text('No workouts scheduled'), findsNothing);
      expect(find.text('Rest day - enjoy the recovery'), findsNothing);
    },
  );

  testWidgets(
    'every active program on a rest day today renders the distinct rest-day '
    'message, not the generic "nothing scheduled" one',
    (tester) async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final p = program(
        1,
        workouts: [
          workout(
            10,
            programId: 1,
            scheduledDate: todayDate,
            isRestDay: true,
            name: 'Rest',
          ),
        ],
      );
      when(
        programsRepo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [p]);
      _stubHealthyNutrition(nutritionRepo, todayDate);

      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Rest day - enjoy the recovery'), findsOneWidget);
      expect(find.text('No workouts scheduled'), findsNothing);
    },
  );

  testWidgets(
    'no nutrition target set: actual consumed calories still render, with '
    'no fabricated 2000/150/200/65 default target shown',
    (tester) async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      when(
        programsRepo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => []);
      when(nutritionRepo.getTodaysMealLog(date: anyNamed('date'))).thenAnswer(
        (_) async =>
            MealLog(id: 1, userId: 1, date: todayDate, createdAt: todayDate),
      );
      // No goal - the dashboard response's goal is null, exactly as the
      // real server-side ResolveForDateAsync now returns when no target
      // has ever been recorded (see NutritionGoalsController.GetDashboard).
      when(
        nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer(
        (_) async => NutritionDashboardData(
          date: todayDate,
          goal: null,
          progress: DailyNutritionProgress(
            id: 0,
            userId: 1,
            date: todayDate,
            createdAt: todayDate,
          ),
        ),
      );
      when(nutritionRepo.getStreak()).thenAnswer((_) async => StreakInfo());

      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // No fabricated goal text anywhere on screen.
      expect(find.textContaining('/ 2000'), findsNothing);
      expect(find.text('No target\nset'), findsOneWidget);
    },
  );

  testWidgets('local midnight fires while the app remains open and refreshes '
      'workouts, sessions, and nutrition together - not just one of them', (
    tester,
  ) async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    var programsCallCount = 0;
    when(programsRepo.getPrograms(isActive: anyNamed('isActive'))).thenAnswer((
      _,
    ) async {
      programsCallCount++;
      if (programsCallCount == 1) return <Program>[];
      return [
        program(
          1,
          workouts: [
            workout(
              10,
              programId: 1,
              scheduledDate: todayDate,
              name: 'Fresh Day Workout',
            ),
          ],
        ),
      ];
    });

    var sessionsCallCount = 0;
    when(
      sessionRepo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async {
      sessionsCallCount++;
      return <Session>[];
    });

    var mealLogCallCount = 0;
    when(nutritionRepo.getTodaysMealLog(date: anyNamed('date'))).thenAnswer((
      _,
    ) async {
      mealLogCallCount++;
      return MealLog(
        id: mealLogCallCount,
        userId: 1,
        date: todayDate,
        createdAt: todayDate,
      );
    });
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

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('No workouts scheduled'), findsOneWidget);
    expect(programsCallCount, 1);
    expect(sessionsCallCount, 1);
    expect(mealLogCallCount, 1);

    // Cross local midnight with the widget still mounted - no background/
    // resume cycle involved. `timeUntilMidnight` (computed from whatever
    // real time the test happens to run at) is always < 24h, so pumping
    // 24h+5m past the mount guarantees the scheduled Timer fires exactly
    // once, virtualized by flutter_test - no real waiting.
    await tester.pump(const Duration(hours: 24, minutes: 5));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
      programsCallCount,
      greaterThanOrEqualTo(2),
      reason: 'midnight must refresh program-derived workout schedules',
    );
    expect(
      sessionsCallCount,
      greaterThanOrEqualTo(2),
      reason: 'midnight must refresh sessions alongside programs',
    );
    expect(
      mealLogCallCount,
      greaterThanOrEqualTo(2),
      reason: 'midnight must refresh nutrition alongside programs/sessions',
    );
    expect(find.text('Fresh Day Workout'), findsOneWidget);
    expect(find.text('No workouts scheduled'), findsNothing);
  });

  testWidgets(
    'resuming the app reloads workout schedules (programs) and sessions '
    'together, not just one of them - both must never go stale relative '
    'to each other on Today',
    (tester) async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      var programsCallCount = 0;
      when(programsRepo.getPrograms(isActive: anyNamed('isActive'))).thenAnswer(
        (_) async {
          programsCallCount++;
          if (programsCallCount == 1) return <Program>[];
          return [
            program(
              1,
              workouts: [
                workout(
                  10,
                  programId: 1,
                  scheduledDate: todayDate,
                  name: 'Synced Workout',
                ),
              ],
            ),
          ];
        },
      );

      var sessionsCallCount = 0;
      when(
        sessionRepo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async {
        sessionsCallCount++;
        return <Session>[];
      });

      _stubHealthyNutrition(nutritionRepo, todayDate);

      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('No workouts scheduled'), findsOneWidget);
      expect(programsCallCount, 1);
      expect(sessionsCallCount, 1);

      // Dispatch through WidgetsBinding's real observer registry - the
      // exact path the OS uses - rather than calling the State's method
      // directly, so this also proves TodayScreen's observer is actually
      // registered and wired to both providers.
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        programsCallCount,
        2,
        reason:
            'resume must reload program-based workout schedules, not just '
            'sessions - previously only sessions refreshed here, leaving '
            'Today\'s program-derived schedule stale after a resume',
      );
      expect(sessionsCallCount, 2);
      expect(find.text('Synced Workout'), findsOneWidget);
      expect(find.text('No workouts scheduled'), findsNothing);
    },
  );

  testWidgets(
    'a timezone offset where the nutrition endpoint\'s UTC "today" differs '
    'from the device\'s local calendar day does not corrupt or hide either '
    'section - the workout list uses the local day (per '
    'ProgramsProvider.getTodaysWorkouts, entirely local-device-time based) '
    'and independently renders the workout, while the nutrition section '
    'renders whatever meal log the server actually returned for its own '
    '(UTC) notion of "today", with neither cross-checking the other\'s date',
    (tester) async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      // Simulates a user far enough ahead of UTC that the server's
      // DateTime.UtcNow.Date-based "today" (see
      // MealLogsController.GetTodaysMealLog) is still the PREVIOUS
      // calendar day relative to the device's local date - the exact
      // divergence a timezone offset produces between local-date and
      // UTC-date.
      final serverUtcTodayDate = todayDate.subtract(const Duration(days: 1));

      when(programsRepo.getPrograms(isActive: anyNamed('isActive'))).thenAnswer(
        (_) async => [
          program(
            1,
            workouts: [
              workout(
                10,
                programId: 1,
                scheduledDate: todayDate,
                name: 'Local Today Workout',
              ),
            ],
          ),
        ],
      );

      when(nutritionRepo.getTodaysMealLog(date: anyNamed('date'))).thenAnswer(
        (_) async => MealLog(
          id: 1,
          userId: 1,
          date: serverUtcTodayDate,
          createdAt: serverUtcTodayDate,
          mealEntries: [
            MealEntry(
              id: 1,
              mealLogId: 1,
              mealType: 'Breakfast',
              isConsumed: true,
              totalCalories: 550,
              createdAt: serverUtcTodayDate,
            ),
          ],
        ),
      );
      when(
        nutritionRepo.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer(
        (_) async => NutritionDashboardData(
          date: serverUtcTodayDate,
          goal: NutritionGoal(
            id: 1,
            userId: 1,
            dailyCalories: 2000,
            createdAt: serverUtcTodayDate,
          ),
          progress: DailyNutritionProgress(
            id: 0,
            userId: 1,
            date: serverUtcTodayDate,
            createdAt: serverUtcTodayDate,
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

      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The workout, scheduled for the LOCAL calendar day, is shown -
      // unaffected by the server's UTC-lagged meal log date.
      expect(find.text('Local Today Workout'), findsOneWidget);
      expect(find.text('No workouts scheduled'), findsNothing);

      // The nutrition section still renders the server's response - 550
      // consumed calories against a 2000 target - instead of hiding or
      // blanking it out merely because its date differs from the device's
      // local "today".
      expect(find.text('550'), findsOneWidget);
      expect(find.text('No target\nset'), findsNothing);
    },
  );
}
