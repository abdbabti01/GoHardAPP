import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';
import 'package:go_hard_app/providers/programs_provider.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/data/repositories/programs_repository.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/models/exercise.dart';
import 'package:go_hard_app/data/models/exercise_set.dart';
import 'package:go_hard_app/data/models/program.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/data/models/meal_log.dart';
import 'package:go_hard_app/data/models/nutrition_goal.dart';
import 'package:go_hard_app/data/models/nutrition_summary.dart';
import 'package:go_hard_app/core/services/connectivity_service.dart';

@GenerateMocks([
  SessionRepository,
  NutritionRepository,
  ProgramsRepository,
  AuthService,
  ConnectivityService,
])
import 'user_workflow_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSessionRepository mockSessionRepository;
  late MockNutritionRepository mockNutritionRepository;
  late MockProgramsRepository mockProgramsRepository;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;

  setUp(() {
    mockSessionRepository = MockSessionRepository();
    mockNutritionRepository = MockNutritionRepository();
    mockProgramsRepository = MockProgramsRepository();
    mockAuthService = MockAuthService();
    mockConnectivity = MockConnectivityService();

    // Default stubs
    when(mockAuthService.getUserId()).thenAnswer((_) async => 1);
    when(mockAuthService.getUserName()).thenAnswer((_) async => 'Test User');
    when(
      mockAuthService.getUserEmail(),
    ).thenAnswer((_) async => 'test@example.com');
    when(mockConnectivity.isOnline).thenReturn(true);
    when(
      mockConnectivity.connectivityStream,
    ).thenAnswer((_) => Stream.value(true));
  });

  // Helper function to create a test NutritionGoal
  NutritionGoal createTestGoal({
    double dailyCalories = 2000,
    double dailyProtein = 150,
    double dailyCarbs = 200,
    double dailyFat = 65,
  }) {
    return NutritionGoal(
      id: 1,
      userId: 1,
      name: 'Test Goal',
      dailyCalories: dailyCalories,
      dailyProtein: dailyProtein,
      dailyCarbohydrates: dailyCarbs,
      dailyFat: dailyFat,
      isActive: true,
      createdAt: DateTime.now(),
    );
  }

  // Helper function to create NutritionProgress
  NutritionProgress createTestProgress({
    required NutritionGoal goal,
    double consumedCalories = 0,
    double consumedProtein = 0,
    double consumedCarbs = 0,
    double consumedFat = 0,
  }) {
    return NutritionProgress(
      date: DateTime.now(),
      goal: goal,
      consumed: NutritionTotals(
        calories: consumedCalories,
        protein: consumedProtein,
        carbohydrates: consumedCarbs,
        fat: consumedFat,
      ),
      remaining: NutritionTotals(
        calories: goal.dailyCalories - consumedCalories,
        protein: goal.dailyProtein - consumedProtein,
        carbohydrates: goal.dailyCarbohydrates - consumedCarbs,
        fat: goal.dailyFat - consumedFat,
      ),
      percentageConsumed: NutritionPercentages(
        calories: consumedCalories / goal.dailyCalories * 100,
        protein: consumedProtein / goal.dailyProtein * 100,
        carbohydrates: consumedCarbs / goal.dailyCarbohydrates * 100,
        fat: consumedFat / goal.dailyFat * 100,
      ),
    );
  }

  // Helper function to create test Program
  Program createTestProgram({
    int id = 1,
    String title = 'Test Program',
    int totalWeeks = 4,
    int currentWeek = 1,
    int currentDay = 1,
    bool isActive = true,
    bool isCompleted = false,
    DateTime? startDate,
    List<ProgramWorkout>? workouts,
  }) {
    return Program(
      id: id,
      userId: 1,
      title: title,
      totalWeeks: totalWeeks,
      currentWeek: currentWeek,
      currentDay: currentDay,
      startDate: startDate ?? DateTime.now(),
      isActive: isActive,
      isCompleted: isCompleted,
      createdAt: DateTime.now(),
      workouts: workouts,
    );
  }

  // Helper function to create test ProgramWorkout
  ProgramWorkout createTestProgramWorkout({
    int id = 1,
    int programId = 1,
    int weekNumber = 1,
    int dayNumber = 1,
    String workoutName = 'Test Workout',
    String? workoutType,
    bool isCompleted = false,
    int orderIndex = 1,
    DateTime? scheduledDate,
  }) {
    return ProgramWorkout(
      id: id,
      programId: programId,
      weekNumber: weekNumber,
      dayNumber: dayNumber,
      workoutName: workoutName,
      workoutType: workoutType,
      exercisesJson: '[]',
      isCompleted: isCompleted,
      orderIndex: orderIndex,
      scheduledDate: scheduledDate,
    );
  }

  // =============================================================================
  // WORKOUT LIFECYCLE TESTS
  // =============================================================================
  group('Workout Lifecycle - Complete Flow', () {
    test(
      'User can create, start, pause, resume, and complete a workout',
      () async {
        // Arrange - Setup session data for each stage
        final draftSession = Session(
          id: 1,
          userId: 1,
          date: DateTime.now(),
          status: 'draft',
          name: 'Morning Workout',
          exercises: [],
        );

        final inProgressSession = draftSession.copyWith(
          status: 'in_progress',
          startedAt: DateTime.now().toUtc(),
        );

        final pausedSession = inProgressSession.copyWith(
          pausedAt: DateTime.now().toUtc(),
        );

        final resumedSession = pausedSession.copyWith(
          pausedAt: null,
          startedAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 5),
          ),
        );

        final completedSession = resumedSession.copyWith(
          status: 'completed',
          completedAt: DateTime.now().toUtc(),
          duration: 30,
        );

        // Mock repository calls
        when(
          mockSessionRepository.createSession(any),
        ).thenAnswer((_) async => draftSession);
        when(
          mockSessionRepository.getSession(1),
        ).thenAnswer((_) async => draftSession);
        when(
          mockSessionRepository.getInProgressSessions(),
        ).thenAnswer((_) async => []);
        when(
          mockSessionRepository.updateSessionStatus(1, 'in_progress'),
        ).thenAnswer((_) async => inProgressSession);
        when(
          mockSessionRepository.pauseSession(any, any),
        ).thenAnswer((_) async {});
        when(
          mockSessionRepository.resumeSession(any, any),
        ).thenAnswer((_) async {});
        when(
          mockSessionRepository.updateSessionStatus(
            1,
            'completed',
            duration: anyNamed('duration'),
          ),
        ).thenAnswer((_) async => completedSession);
        when(
          mockSessionRepository.getSessions(
            waitForSync: anyNamed('waitForSync'),
          ),
        ).thenAnswer((_) async => [draftSession]);
        when(
          mockSessionRepository.watchSessions(any),
        ).thenAnswer((_) => Stream.value([draftSession]));

        // Create providers
        final sessionsProvider = SessionsProvider(
          mockSessionRepository,
          mockAuthService,
          mockConnectivity,
        );

        final activeWorkoutProvider = ActiveWorkoutProvider(
          mockSessionRepository,
          mockConnectivity,
        );

        // Act & Assert - Step 1: Create workout
        final createdSession = await sessionsProvider.startNewWorkout(
          name: 'Morning Workout',
        );
        expect(createdSession, isNotNull);
        expect(createdSession!.status, equals('draft'));
        expect(createdSession.name, equals('Morning Workout'));
        verify(mockSessionRepository.createSession(any)).called(1);

        // Act & Assert - Step 2: Load and start workout
        await activeWorkoutProvider.loadSession(1);
        expect(activeWorkoutProvider.currentSession, isNotNull);
        expect(activeWorkoutProvider.currentSession!.status, equals('draft'));

        // Update mock for started session
        when(
          mockSessionRepository.getSession(1),
        ).thenAnswer((_) async => inProgressSession);

        await activeWorkoutProvider.startWorkout();
        verify(
          mockSessionRepository.updateSessionStatus(1, 'in_progress'),
        ).called(1);

        // Act & Assert - Step 3: Pause workout
        // Simulate some time passing
        await Future.delayed(const Duration(milliseconds: 100));

        // Reload with paused state
        when(
          mockSessionRepository.getSession(1),
        ).thenAnswer((_) async => pausedSession);
        await activeWorkoutProvider.pauseTimer();
        verify(mockSessionRepository.pauseSession(any, any)).called(1);
        expect(activeWorkoutProvider.isTimerRunning, isFalse);

        // Act & Assert - Step 4: Resume workout
        when(
          mockSessionRepository.getSession(1),
        ).thenAnswer((_) async => resumedSession);
        await activeWorkoutProvider.resumeTimer();
        verify(mockSessionRepository.resumeSession(any, any)).called(1);
        expect(activeWorkoutProvider.isTimerRunning, isTrue);

        // Act & Assert - Step 5: Complete workout
        when(
          mockSessionRepository.getSession(1),
        ).thenAnswer((_) async => completedSession);
        final finished = await activeWorkoutProvider.finishWorkout();
        expect(finished, isTrue);
        verify(
          mockSessionRepository.updateSessionStatus(
            1,
            'completed',
            duration: anyNamed('duration'),
          ),
        ).called(1);
      },
    );

    test(
      'Starting a workout auto-completes any existing in-progress workout',
      () async {
        // Arrange
        final existingInProgress = Session(
          id: 99,
          userId: 1,
          date: DateTime.now().subtract(const Duration(days: 1)),
          status: 'in_progress',
          startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          exercises: [],
        );

        final newDraft = Session(
          id: 1,
          userId: 1,
          date: DateTime.now(),
          status: 'draft',
          exercises: [],
        );

        final newInProgress = newDraft.copyWith(
          status: 'in_progress',
          startedAt: DateTime.now().toUtc(),
        );

        when(
          mockSessionRepository.getSession(1),
        ).thenAnswer((_) async => newDraft);
        when(
          mockSessionRepository.getInProgressSessions(),
        ).thenAnswer((_) async => [existingInProgress]);
        when(
          mockSessionRepository.updateSessionStatus(
            99,
            'completed',
            duration: anyNamed('duration'),
          ),
        ).thenAnswer(
          (_) async => existingInProgress.copyWith(status: 'completed'),
        );
        when(
          mockSessionRepository.updateSessionStatus(1, 'in_progress'),
        ).thenAnswer((_) async => newInProgress);

        final provider = ActiveWorkoutProvider(
          mockSessionRepository,
          mockConnectivity,
        );

        // Act
        await provider.loadSession(1);
        await provider.startWorkout();

        // Assert - existing workout should be auto-completed
        verify(
          mockSessionRepository.updateSessionStatus(
            99,
            'completed',
            duration: anyNamed('duration'),
          ),
        ).called(1);
        // New workout should be started
        verify(
          mockSessionRepository.updateSessionStatus(1, 'in_progress'),
        ).called(1);
      },
    );

    test(
      'Workout timer calculates elapsed time correctly after pause/resume',
      () async {
        // Arrange
        final now = DateTime.now().toUtc();
        final startedAt = now.subtract(const Duration(minutes: 10));
        final pausedAt = now.subtract(const Duration(minutes: 5));

        final pausedSession = Session(
          id: 1,
          userId: 1,
          date: DateTime.now(),
          status: 'in_progress',
          startedAt: startedAt,
          pausedAt: pausedAt,
          exercises: [],
        );

        when(
          mockSessionRepository.getSession(1),
        ).thenAnswer((_) async => pausedSession);

        final provider = ActiveWorkoutProvider(
          mockSessionRepository,
          mockConnectivity,
        );

        // Act
        await provider.loadSession(1);

        // Assert - elapsed time should be 5 minutes (10 min total - 5 min paused)
        expect(provider.elapsedTime.inMinutes, equals(5));
        expect(provider.isTimerRunning, isFalse);
      },
    );
  });

  // =============================================================================
  // SESSIONS PROVIDER TESTS
  // =============================================================================
  group('Sessions Provider - Session Management', () {
    test(
      'loadSessions fetches and sorts sessions by date descending',
      () async {
        // Arrange
        final sessions = [
          Session(
            id: 1,
            userId: 1,
            date: DateTime(2024, 1, 1),
            status: 'completed',
            exercises: [],
          ),
          Session(
            id: 2,
            userId: 1,
            date: DateTime(2024, 1, 3),
            status: 'completed',
            exercises: [],
          ),
          Session(
            id: 3,
            userId: 1,
            date: DateTime(2024, 1, 2),
            status: 'completed',
            exercises: [],
          ),
        ];

        when(
          mockSessionRepository.getSessions(
            waitForSync: anyNamed('waitForSync'),
          ),
        ).thenAnswer((_) async => sessions);
        when(
          mockSessionRepository.watchSessions(1),
        ).thenAnswer((_) => Stream.value(sessions));

        final provider = SessionsProvider(
          mockSessionRepository,
          mockAuthService,
          mockConnectivity,
        );

        // Act
        await provider.loadSessions();

        // Assert - sessions should be sorted by date descending
        expect(provider.sessions.length, equals(3));
        expect(provider.sessions[0].id, equals(2)); // Jan 3
        expect(provider.sessions[1].id, equals(3)); // Jan 2
        expect(provider.sessions[2].id, equals(1)); // Jan 1
      },
    );

    test('deleteSession removes session from local list', () async {
      // Arrange
      final session = Session(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        status: 'draft',
        exercises: [],
      );

      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => [session]);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value([session]));
      when(
        mockSessionRepository.deleteSession(1),
      ).thenAnswer((_) async => true);

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      await provider.loadSessions();
      expect(provider.sessions.length, equals(1));

      final deleted = await provider.deleteSession(1);

      // Assert
      expect(deleted, isTrue);
      expect(provider.sessions.length, equals(0));
      verify(mockSessionRepository.deleteSession(1)).called(1);
    });

    test(
      'createPlannedWorkout creates session with future date and planned status',
      () async {
        // Arrange
        final futureDate = DateTime.now().add(const Duration(days: 7));
        final plannedSession = Session(
          id: 1,
          userId: 1,
          date: DateTime(futureDate.year, futureDate.month, futureDate.day),
          status: 'planned',
          name: 'Future Workout',
          exercises: [],
        );

        when(
          mockSessionRepository.createSession(any),
        ).thenAnswer((_) async => plannedSession);
        when(
          mockSessionRepository.getSessions(
            waitForSync: anyNamed('waitForSync'),
          ),
        ).thenAnswer((_) async => []);
        when(
          mockSessionRepository.watchSessions(1),
        ).thenAnswer((_) => Stream.value([]));

        final provider = SessionsProvider(
          mockSessionRepository,
          mockAuthService,
          mockConnectivity,
        );

        // Act
        final created = await provider.createPlannedWorkout(
          name: 'Future Workout',
          scheduledDate: futureDate,
        );

        // Assert
        expect(created, isNotNull);
        expect(created!.status, equals('planned'));
        expect(created.name, equals('Future Workout'));
      },
    );
  });

  // =============================================================================
  // PROGRAM WORKOUT TESTS
  // =============================================================================
  group('Program Workout - Starting from Program', () {
    test('startProgramWorkout creates session linked to program', () async {
      // Arrange
      final program = createTestProgram(id: 1, title: 'Strength Program');

      final programWorkout = createTestProgramWorkout(
        id: 10,
        programId: 1,
        workoutName: 'Day 1 - Push',
        weekNumber: 1,
        dayNumber: 1,
        scheduledDate: DateTime.now(),
      );

      final createdSession = Session(
        id: 100,
        userId: 1,
        date: DateTime.now(),
        status: 'draft',
        name: 'Day 1 - Push',
        programId: 1,
        programWorkoutId: 10,
        exercises: [],
      );

      when(
        mockSessionRepository.createSessionFromProgramWorkout(
          any,
          any,
          any,
          any,
        ),
      ).thenAnswer((_) async => createdSession);
      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => []);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value([]));

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      final session = await provider.startProgramWorkout(
        programWorkout.id,
        programWorkout,
        program.startDate,
        program.id,
      );

      // Assert
      expect(session, isNotNull);
      expect(session!.programId, equals(1));
      expect(session.programWorkoutId, equals(10));
      expect(session.name, equals('Day 1 - Push'));
      verify(
        mockSessionRepository.createSessionFromProgramWorkout(10, any, any, 1),
      ).called(1);
    });

    test('getSessionsFromProgram filters sessions by programId', () async {
      // Arrange
      final sessions = [
        Session(
          id: 1,
          userId: 1,
          date: DateTime.now(),
          status: 'completed',
          programId: 1,
          exercises: [],
        ),
        Session(
          id: 2,
          userId: 1,
          date: DateTime.now(),
          status: 'completed',
          programId: 2,
          exercises: [],
        ),
        Session(
          id: 3,
          userId: 1,
          date: DateTime.now(),
          status: 'completed',
          programId: 1,
          exercises: [],
        ),
        Session(
          id: 4,
          userId: 1,
          date: DateTime.now(),
          status: 'completed',
          programId: null, // Standalone session
          exercises: [],
        ),
      ];

      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => sessions);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value(sessions));

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      await provider.loadSessions();
      final program1Sessions = provider.getSessionsFromProgram(1);
      final standaloneSessions = provider.getStandaloneSessions();

      // Assert
      expect(program1Sessions.length, equals(2));
      expect(program1Sessions.every((s) => s.programId == 1), isTrue);
      expect(standaloneSessions.length, equals(1));
      expect(standaloneSessions[0].programId, isNull);
    });
  });

  // =============================================================================
  // DATE HANDLING TESTS
  // =============================================================================
  group('Date Handling', () {
    test('Session date is normalized to local midnight', () {
      // Arrange - API returns UTC midnight which could be previous day in local time
      final jsonWithUtcMidnight = {
        'id': 1,
        'userId': 1,
        'date': '2024-01-15T00:00:00Z', // UTC midnight
        'status': 'draft',
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(jsonWithUtcMidnight);

      // Assert - date should be normalized to local date (year, month, day only)
      expect(session.date.hour, equals(0));
      expect(session.date.minute, equals(0));
      expect(session.date.second, equals(0));
    });

    test('Timestamps (startedAt, pausedAt) are converted to UTC', () {
      // Arrange
      final now = DateTime.now();
      final jsonWithTimestamps = {
        'id': 1,
        'userId': 1,
        'date': '2024-01-15T00:00:00Z',
        'status': 'in_progress',
        'startedAt': now.toIso8601String(),
        'pausedAt': now.add(const Duration(minutes: 5)).toIso8601String(),
        'exercises': [],
        'version': 1,
      };

      // Act
      final session = Session.fromJson(jsonWithTimestamps);

      // Assert - timestamps should be in UTC
      expect(session.startedAt, isNotNull);
      expect(session.startedAt!.isUtc, isTrue);
      expect(session.pausedAt, isNotNull);
      expect(session.pausedAt!.isUtc, isTrue);
    });

    test('updateWorkoutDate changes session date correctly', () async {
      // Arrange
      final originalDate = DateTime(2024, 1, 15);
      final newDate = DateTime(2024, 1, 20);
      final session = Session(
        id: 1,
        userId: 1,
        date: originalDate,
        status: 'planned',
        exercises: [],
      );

      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => [session]);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value([session]));
      when(
        mockSessionRepository.updateWorkoutDate(1, any),
      ).thenAnswer((_) async {});

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      await provider.loadSessions();
      final success = await provider.updateWorkoutDate(1, newDate);

      // Assert
      expect(success, isTrue);
      expect(provider.sessions[0].date.day, equals(20));
      verify(mockSessionRepository.updateWorkoutDate(1, any)).called(1);
    });
  });

  // =============================================================================
  // NUTRITION PROVIDER TESTS
  // =============================================================================
  group('Nutrition Provider - Complete Flow', () {
    test('loadTodaysData loads meal log, goal, and progress', () async {
      // Arrange
      final mealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalCalories: 1500,
        totalProtein: 100,
        totalCarbohydrates: 150,
        totalFat: 50,
      );

      final goal = createTestGoal();
      final progress = createTestProgress(
        goal: goal,
        consumedCalories: 1500,
        consumedProtein: 100,
        consumedCarbs: 150,
        consumedFat: 50,
      );

      final streak = StreakInfo(
        currentStreak: 5,
        longestStreak: 10,
        totalDaysLogged: 30,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => mealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadTodaysData();

      // Assert
      expect(provider.todaysMealLog, isNotNull);
      expect(provider.todaysMealLog!.totalCalories, equals(1500));
      expect(provider.activeGoal, isNotNull);
      expect(provider.activeGoal!.dailyCalories, equals(2000));
      expect(provider.todaysProgress, isNotNull);
      expect(provider.streakInfo, isNotNull);
      expect(provider.streakInfo!.currentStreak, equals(5));
    });

    test('caloriesRemaining calculates correctly', () async {
      // Arrange
      final mealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalCalories: 1200,
        totalProtein: 0,
        totalCarbohydrates: 0,
        totalFat: 0,
      );

      final goal = createTestGoal(dailyCalories: 2000);
      final progress = createTestProgress(goal: goal, consumedCalories: 1200);

      final streak = StreakInfo(
        currentStreak: 1,
        longestStreak: 1,
        totalDaysLogged: 1,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => mealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadTodaysData();

      // Assert
      expect(provider.caloriesRemaining, equals(800)); // 2000 - 1200
    });

    test('checkAndRefreshIfDayChanged does not reload on same day', () async {
      // Arrange
      final mealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalCalories: 1000,
        totalProtein: 0,
        totalCarbohydrates: 0,
        totalFat: 0,
      );

      final goal = createTestGoal();
      final progress = createTestProgress(goal: goal, consumedCalories: 1000);
      final streak = StreakInfo(
        currentStreak: 1,
        longestStreak: 1,
        totalDaysLogged: 1,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => mealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act - Initial load
      await provider.loadTodaysData();

      // Allow all async operations (including connectivity callbacks) to complete
      await Future.delayed(const Duration(milliseconds: 300));

      // Clear mock call history
      clearInteractions(mockNutritionRepository);

      // Act - Call checkAndRefreshIfDayChanged on same day (should not reload)
      provider.checkAndRefreshIfDayChanged();

      // Allow async operations to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert - getTodaysMealLog should NOT have been called again
      verifyNever(mockNutritionRepository.getTodaysMealLog());
    });

    test('loadNutritionHistory loads past meal logs', () async {
      // Arrange
      final today = DateTime.now();
      final historyLogs = [
        MealLog(
          id: 2,
          userId: 1,
          date: today.subtract(const Duration(days: 1)),
          createdAt: today.subtract(const Duration(days: 1)),
          totalCalories: 1800,
          totalProtein: 120,
          totalCarbohydrates: 180,
          totalFat: 60,
        ),
        MealLog(
          id: 3,
          userId: 1,
          date: today.subtract(const Duration(days: 2)),
          createdAt: today.subtract(const Duration(days: 2)),
          totalCalories: 1900,
          totalProtein: 130,
          totalCarbohydrates: 190,
          totalFat: 55,
        ),
      ];

      when(
        mockNutritionRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) async => historyLogs);

      // Stub today's data methods
      final goal = createTestGoal();
      when(mockNutritionRepository.getTodaysMealLog()).thenAnswer(
        (_) async => MealLog(
          id: 1,
          userId: 1,
          date: today,
          createdAt: today,
          totalCalories: 0,
          totalProtein: 0,
          totalCarbohydrates: 0,
          totalFat: 0,
        ),
      );
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => createTestProgress(goal: goal));
      when(mockNutritionRepository.getStreak()).thenAnswer(
        (_) async =>
            StreakInfo(currentStreak: 1, longestStreak: 1, totalDaysLogged: 1),
      );

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadNutritionHistory();

      // Assert
      expect(provider.nutritionHistory.length, equals(2));
      expect(provider.nutritionHistory[0].totalCalories, equals(1800));
      verify(
        mockNutritionRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).called(1);
    });

    test('setHistoryFilter changes filter and reloads history', () async {
      // Arrange
      when(
        mockNutritionRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) async => []);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      expect(provider.historyFilter, equals('week')); // Default
      provider.setHistoryFilter('month');

      // Allow async to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert
      expect(provider.historyFilter, equals('month'));
      verify(
        mockNutritionRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).called(1);
    });

    test('addWater increments water intake', () async {
      // Arrange
      final mealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        waterIntake: 500, // Starting with 500ml
        totalCalories: 0,
        totalProtein: 0,
        totalCarbohydrates: 0,
        totalFat: 0,
      );

      final goal = createTestGoal();
      final progress = createTestProgress(goal: goal);
      final streak = StreakInfo(
        currentStreak: 1,
        longestStreak: 1,
        totalDaysLogged: 1,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => mealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);
      when(
        mockNutritionRepository.updateWaterIntake(1, 750),
      ).thenAnswer((_) async {});

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadTodaysData();
      await provider.addWater(250); // Add 250ml

      // Assert - should call updateWaterIntake with 500 + 250 = 750
      verify(mockNutritionRepository.updateWaterIntake(1, 750)).called(1);
    });
  });

  // =============================================================================
  // PROGRAMS PROVIDER TESTS
  // =============================================================================
  group('Programs Provider', () {
    test('loadPrograms separates active and completed programs', () async {
      // Arrange
      final programs = [
        createTestProgram(
          id: 1,
          title: 'Active Program',
          isActive: true,
          isCompleted: false,
        ),
        createTestProgram(
          id: 2,
          title: 'Completed Program',
          isActive: false,
          isCompleted: true,
          startDate: DateTime.now().subtract(const Duration(days: 30)),
        ),
      ];

      when(
        mockProgramsRepository.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => programs);

      final provider = ProgramsProvider(
        mockProgramsRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadPrograms();

      // Assert
      expect(provider.programs.length, equals(2));
      expect(provider.activePrograms.length, equals(1));
      expect(provider.activePrograms[0].title, equals('Active Program'));
      expect(provider.completedPrograms.length, equals(1));
      expect(provider.completedPrograms[0].title, equals('Completed Program'));
    });

    test('getTodaysWorkouts returns workouts scheduled for today', () async {
      // Arrange
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      final program = createTestProgram(
        id: 1,
        title: 'Test Program',
        startDate: todayDate,
        workouts: [
          createTestProgramWorkout(
            id: 1,
            workoutName: 'Today Workout',
            weekNumber: 1,
            dayNumber: 1,
            scheduledDate: todayDate,
          ),
          createTestProgramWorkout(
            id: 2,
            workoutName: 'Tomorrow Workout',
            weekNumber: 1,
            dayNumber: 2,
            scheduledDate: todayDate.add(const Duration(days: 1)),
          ),
        ],
      );

      when(
        mockProgramsRepository.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program]);

      final provider = ProgramsProvider(
        mockProgramsRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadPrograms();
      final todaysWorkouts = provider.getTodaysWorkouts();

      // Assert
      expect(todaysWorkouts.length, equals(1));
      expect(todaysWorkouts[0].workout.workoutName, equals('Today Workout'));
    });

    test('completeWorkout marks workout as completed', () async {
      // Arrange
      final workout = createTestProgramWorkout(
        id: 1,
        workoutName: 'Test Workout',
        isCompleted: false,
      );

      final program = createTestProgram(
        id: 1,
        title: 'Test Program',
        workouts: [workout],
      );

      when(
        mockProgramsRepository.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program]);
      when(
        mockProgramsRepository.completeWorkout(1, notes: anyNamed('notes')),
      ).thenAnswer((_) async {});

      final provider = ProgramsProvider(
        mockProgramsRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadPrograms();
      final success = await provider.completeWorkout(1);

      // Assert
      expect(success, isTrue);
      verify(
        mockProgramsRepository.completeWorkout(1, notes: anyNamed('notes')),
      ).called(1);
    });
  });

  // =============================================================================
  // ERROR HANDLING TESTS
  // =============================================================================
  group('Error Handling', () {
    test('SessionsProvider handles load error gracefully', () async {
      // Arrange
      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenThrow(Exception('Network error'));
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value([]));

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      await provider.loadSessions();

      // Assert
      expect(provider.errorMessage, isNotNull);
      expect(provider.errorMessage, contains('Network error'));
      expect(provider.sessions, isEmpty);
    });

    test('ActiveWorkoutProvider handles start error gracefully', () async {
      // Arrange
      final session = Session(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        status: 'draft',
        exercises: [],
      );

      when(
        mockSessionRepository.getSession(1),
      ).thenAnswer((_) async => session);
      when(
        mockSessionRepository.getInProgressSessions(),
      ).thenAnswer((_) async => []);
      when(
        mockSessionRepository.updateSessionStatus(1, 'in_progress'),
      ).thenThrow(Exception('Server error'));

      final provider = ActiveWorkoutProvider(
        mockSessionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadSession(1);
      await provider.startWorkout();

      // Assert
      expect(provider.errorMessage, isNotNull);
      expect(provider.errorMessage, contains('Server error'));
    });

    test(
      'NutritionProvider handles API error and shows error message',
      () async {
        // Arrange
        when(
          mockNutritionRepository.getTodaysMealLog(),
        ).thenThrow(Exception('API unavailable'));

        final provider = NutritionProvider(
          mockNutritionRepository,
          mockConnectivity,
        );

        // Act
        await provider.loadTodaysData();

        // Assert
        expect(provider.errorMessage, isNotNull);
        expect(provider.errorMessage, contains('API unavailable'));
      },
    );
  });

  // =============================================================================
  // CLEAR/LOGOUT TESTS
  // =============================================================================
  group('Clear on Logout', () {
    test('SessionsProvider.clear() resets all state', () async {
      // Arrange
      final session = Session(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        status: 'completed',
        exercises: [],
      );

      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => [session]);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value([session]));

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Load some data
      await provider.loadSessions();
      expect(provider.sessions.length, equals(1));

      // Act
      provider.clear();

      // Assert
      expect(provider.sessions, isEmpty);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('ActiveWorkoutProvider.clear() resets timer and session', () async {
      // Arrange
      final session = Session(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        status: 'in_progress',
        startedAt: DateTime.now().toUtc(),
        exercises: [],
      );

      when(
        mockSessionRepository.getSession(1),
      ).thenAnswer((_) async => session);

      final provider = ActiveWorkoutProvider(
        mockSessionRepository,
        mockConnectivity,
      );

      // Load and start
      await provider.loadSession(1);
      expect(provider.currentSession, isNotNull);

      // Act
      provider.clear();

      // Assert
      expect(provider.currentSession, isNull);
      expect(provider.elapsedTime, equals(Duration.zero));
      expect(provider.isTimerRunning, isFalse);
    });

    test('NutritionProvider.clear() resets all nutrition data', () async {
      // Arrange
      final mealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalCalories: 1500,
        totalProtein: 0,
        totalCarbohydrates: 0,
        totalFat: 0,
      );

      final goal = createTestGoal();
      final progress = createTestProgress(goal: goal, consumedCalories: 1500);
      final streak = StreakInfo(
        currentStreak: 5,
        longestStreak: 10,
        totalDaysLogged: 30,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => mealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Load data
      await provider.loadTodaysData();
      expect(provider.todaysMealLog, isNotNull);

      // Act
      provider.clear();

      // Assert
      expect(provider.todaysMealLog, isNull);
      expect(provider.activeGoal, isNull);
      expect(provider.streakInfo, isNull);
      expect(provider.nutritionHistory, isEmpty);
    });
  });

  // =============================================================================
  // APP LIFECYCLE TESTS - Leaving and Returning to Active Workout
  // =============================================================================
  group('App Lifecycle - Active Workout Persistence', () {
    test(
      'Timer continues correctly when user leaves and returns to app',
      () async {
        // Arrange - Workout started 10 minutes ago
        final startTime = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );
        final activeSession = Session(
          id: 1,
          userId: 1,
          date: DateTime.now(),
          status: 'in_progress',
          startedAt: startTime,
          exercises: [],
        );

        when(
          mockSessionRepository.getSession(1),
        ).thenAnswer((_) async => activeSession);

        final provider = ActiveWorkoutProvider(
          mockSessionRepository,
          mockConnectivity,
        );

        // Act - Load session (simulates returning to app)
        await provider.loadSession(1);

        // Assert - Timer should show ~10 minutes elapsed
        expect(provider.elapsedTime.inMinutes, greaterThanOrEqualTo(9));
        expect(provider.elapsedTime.inMinutes, lessThanOrEqualTo(11));
        expect(provider.isTimerRunning, isTrue);
      },
    );

    test('Paused workout stays paused when user returns to app', () async {
      // Arrange - Workout started 20 minutes ago, paused 15 minutes ago
      final startTime = DateTime.now().toUtc().subtract(
        const Duration(minutes: 20),
      );
      final pausedTime = DateTime.now().toUtc().subtract(
        const Duration(minutes: 15),
      );

      final pausedSession = Session(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        status: 'in_progress',
        startedAt: startTime,
        pausedAt: pausedTime, // Paused after 5 minutes
        exercises: [],
      );

      when(
        mockSessionRepository.getSession(1),
      ).thenAnswer((_) async => pausedSession);

      final provider = ActiveWorkoutProvider(
        mockSessionRepository,
        mockConnectivity,
      );

      // Act - Load session (simulates returning to app)
      await provider.loadSession(1);

      // Assert - Timer should show 5 minutes (pause time - start time)
      expect(provider.elapsedTime.inMinutes, equals(5));
      expect(provider.isTimerRunning, isFalse);
    });

    test(
      'User can navigate away and back during workout multiple times',
      () async {
        // Arrange
        final startTime = DateTime.now().toUtc();
        var session = Session(
          id: 1,
          userId: 1,
          date: DateTime.now(),
          status: 'in_progress',
          startedAt: startTime,
          exercises: [],
        );

        when(
          mockSessionRepository.getSession(1),
        ).thenAnswer((_) async => session);
        when(
          mockSessionRepository.pauseSession(any, any),
        ).thenAnswer((_) async {});
        when(
          mockSessionRepository.resumeSession(any, any),
        ).thenAnswer((_) async {});

        final provider = ActiveWorkoutProvider(
          mockSessionRepository,
          mockConnectivity,
        );

        // Act - Simulate multiple leave/return cycles
        await provider.loadSession(1);
        expect(provider.isTimerRunning, isTrue);

        // First pause (user leaves app)
        await provider.pauseTimer();
        expect(provider.isTimerRunning, isFalse);

        // First resume (user returns)
        await provider.resumeTimer();
        expect(provider.isTimerRunning, isTrue);

        // Second pause
        await provider.pauseTimer();
        expect(provider.isTimerRunning, isFalse);

        // Second resume
        await provider.resumeTimer();
        expect(provider.isTimerRunning, isTrue);

        // Assert - Timer should still be functional
        verify(mockSessionRepository.pauseSession(any, any)).called(2);
        verify(mockSessionRepository.resumeSession(any, any)).called(2);
      },
    );

    test('Draft workout can be resumed after app restart', () async {
      // Arrange - Draft workout created yesterday
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final draftSession = Session(
        id: 1,
        userId: 1,
        date: yesterday,
        status: 'draft',
        name: 'Yesterday Draft',
        exercises: [],
      );

      final startedSession = draftSession.copyWith(
        status: 'in_progress',
        startedAt: DateTime.now().toUtc(),
      );

      when(
        mockSessionRepository.getSession(1),
      ).thenAnswer((_) async => draftSession);
      when(
        mockSessionRepository.getInProgressSessions(),
      ).thenAnswer((_) async => []);
      when(
        mockSessionRepository.updateSessionStatus(1, 'in_progress'),
      ).thenAnswer((_) async => startedSession);

      final provider = ActiveWorkoutProvider(
        mockSessionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadSession(1);
      expect(provider.currentSession!.status, equals('draft'));

      await provider.startWorkout();

      // Assert
      expect(provider.isTimerRunning, isTrue);
      expect(provider.elapsedTime, equals(Duration.zero));
      verify(
        mockSessionRepository.updateSessionStatus(1, 'in_progress'),
      ).called(1);
    });
  });

  // =============================================================================
  // MULTI-DAY WORKOUT SIMULATION
  // =============================================================================
  group('Multi-Day Workout Simulation', () {
    test('User completes workouts over 7 days and sees progress', () async {
      // Arrange - Create sessions for 7 days
      final today = DateTime.now();
      final weekSessions = List.generate(7, (i) {
        final date = today.subtract(Duration(days: 6 - i));
        return Session(
          id: i + 1,
          userId: 1,
          date: DateTime(date.year, date.month, date.day),
          status: 'completed',
          duration: 45 + (i * 5), // Increasing duration
          completedAt: date.toUtc(),
          exercises: [],
        );
      });

      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => weekSessions);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value(weekSessions));

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      await provider.loadSessions();

      // Assert - 7 completed sessions
      expect(provider.sessions.length, equals(7));
      expect(provider.sessions.every((s) => s.status == 'completed'), isTrue);
      // Sessions should be sorted by date descending
      expect(
        provider.sessions.first.date.isAfter(provider.sessions.last.date),
        isTrue,
      );
    });

    test('Today workout shows as today, yesterday as yesterday', () async {
      // Arrange
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      final sessions = [
        Session(
          id: 1,
          userId: 1,
          date: DateTime(today.year, today.month, today.day),
          status: 'completed',
          name: 'Today Workout',
          exercises: [],
        ),
        Session(
          id: 2,
          userId: 1,
          date: DateTime(yesterday.year, yesterday.month, yesterday.day),
          status: 'completed',
          name: 'Yesterday Workout',
          exercises: [],
        ),
      ];

      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => sessions);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value(sessions));

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      await provider.loadSessions();
      // Filter sessions for today manually
      final todayDate = DateTime(today.year, today.month, today.day);
      final todaySessions =
          provider.sessions
              .where(
                (s) =>
                    s.date.year == todayDate.year &&
                    s.date.month == todayDate.month &&
                    s.date.day == todayDate.day,
              )
              .toList();

      // Assert
      expect(todaySessions.length, equals(1));
      expect(todaySessions.first.name, equals('Today Workout'));
    });

    test('Planned future workouts appear in upcoming list', () async {
      // Arrange
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));
      final nextWeek = today.add(const Duration(days: 7));

      final sessions = [
        Session(
          id: 1,
          userId: 1,
          date: DateTime(today.year, today.month, today.day),
          status: 'completed',
          exercises: [],
        ),
        Session(
          id: 2,
          userId: 1,
          date: DateTime(tomorrow.year, tomorrow.month, tomorrow.day),
          status: 'planned',
          name: 'Tomorrow Workout',
          exercises: [],
        ),
        Session(
          id: 3,
          userId: 1,
          date: DateTime(nextWeek.year, nextWeek.month, nextWeek.day),
          status: 'planned',
          name: 'Next Week Workout',
          exercises: [],
        ),
      ];

      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => sessions);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value(sessions));

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      await provider.loadSessions();
      // Filter for planned sessions manually
      final plannedSessions =
          provider.sessions.where((s) => s.status == 'planned').toList();

      // Assert
      expect(plannedSessions.length, equals(2));
      expect(plannedSessions.every((s) => s.status == 'planned'), isTrue);
    });
  });

  // =============================================================================
  // PROGRAM WORKOUT LIFECYCLE - Complete 4-Week Program
  // =============================================================================
  group('Program Workout Lifecycle', () {
    test('User progresses through 4-week program day by day', () async {
      // Arrange - Create a 4-week program with workouts
      final startDate = DateTime.now().subtract(const Duration(days: 7));

      // Create workouts for week 1 and 2
      final workouts = <ProgramWorkout>[];
      for (var week = 1; week <= 2; week++) {
        for (var day = 1; day <= 3; day++) {
          workouts.add(
            createTestProgramWorkout(
              id: (week - 1) * 3 + day,
              programId: 1,
              weekNumber: week,
              dayNumber: day,
              workoutName: 'Week $week Day $day',
              isCompleted: week == 1 && day <= 2, // First 2 workouts completed
              scheduledDate: startDate.add(
                Duration(days: (week - 1) * 7 + day - 1),
              ),
            ),
          );
        }
      }

      final program = createTestProgram(
        id: 1,
        title: 'Strength Program',
        totalWeeks: 4,
        currentWeek: 1,
        currentDay: 3,
        startDate: startDate,
        workouts: workouts,
      );

      when(
        mockProgramsRepository.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program]);
      when(
        mockProgramsRepository.completeWorkout(any, notes: anyNamed('notes')),
      ).thenAnswer((_) async {});

      final provider = ProgramsProvider(
        mockProgramsRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadPrograms();

      // Assert - Check program state
      expect(provider.activePrograms.length, equals(1));
      final activeProgram = provider.activePrograms.first;

      // Count completed workouts
      final completedCount =
          activeProgram.workouts?.where((w) => w.isCompleted).length ?? 0;
      expect(completedCount, equals(2));

      // Get current workout (Week 1 Day 3)
      final currentWorkout = activeProgram.workouts?.firstWhere(
        (w) => w.weekNumber == 1 && w.dayNumber == 3,
      );
      expect(currentWorkout, isNotNull);
      expect(currentWorkout!.isCompleted, isFalse);
    });

    test('Completing program workout advances program progress', () async {
      // Arrange
      final workout = createTestProgramWorkout(
        id: 3,
        programId: 1,
        weekNumber: 1,
        dayNumber: 3,
        isCompleted: false,
      );

      final program = createTestProgram(id: 1, workouts: [workout]);

      when(
        mockProgramsRepository.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program]);
      when(
        mockProgramsRepository.completeWorkout(3, notes: anyNamed('notes')),
      ).thenAnswer((_) async {});

      final provider = ProgramsProvider(
        mockProgramsRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadPrograms();
      await provider.completeWorkout(3);

      // Assert
      verify(
        mockProgramsRepository.completeWorkout(3, notes: anyNamed('notes')),
      ).called(1);
    });

    test('Starting program workout creates linked session', () async {
      // Arrange
      final workout = createTestProgramWorkout(
        id: 10,
        programId: 1,
        workoutName: 'Push Day',
      );

      final program = createTestProgram(id: 1, workouts: [workout]);

      final linkedSession = Session(
        id: 100,
        userId: 1,
        date: DateTime.now(),
        status: 'draft',
        name: 'Push Day',
        programId: 1,
        programWorkoutId: 10,
        exercises: [],
      );

      when(
        mockSessionRepository.createSessionFromProgramWorkout(10, any, any, 1),
      ).thenAnswer((_) async => linkedSession);
      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => []);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value([]));

      final sessionsProvider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      final session = await sessionsProvider.startProgramWorkout(
        workout.id,
        workout,
        program.startDate,
        program.id,
      );

      // Assert
      expect(session, isNotNull);
      expect(session!.programId, equals(1));
      expect(session.programWorkoutId, equals(10));
    });

    test('Missed program workout shows as overdue', () async {
      // Arrange - Workout scheduled 2 days ago but not completed
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));

      final missedWorkout = createTestProgramWorkout(
        id: 1,
        workoutName: 'Missed Workout',
        isCompleted: false,
        scheduledDate: twoDaysAgo,
      );

      final program = createTestProgram(
        id: 1,
        startDate: twoDaysAgo.subtract(const Duration(days: 5)),
        workouts: [missedWorkout],
      );

      when(
        mockProgramsRepository.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program]);

      final provider = ProgramsProvider(
        mockProgramsRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadPrograms();

      // Manually filter for overdue workouts (scheduled before today and not completed)
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final overdueWorkouts =
          provider.programs
              .expand((p) => p.workouts ?? <ProgramWorkout>[])
              .where(
                (w) =>
                    !w.isCompleted &&
                    w.scheduledDate != null &&
                    w.scheduledDate!.isBefore(todayDate),
              )
              .toList();

      // Assert
      expect(overdueWorkouts.length, equals(1));
      expect(overdueWorkouts.first.workoutName, equals('Missed Workout'));
    });
  });

  // =============================================================================
  // NUTRITION MULTI-DAY SIMULATION
  // =============================================================================
  group('Nutrition Multi-Day Simulation', () {
    test('Nutrition history shows last 7 days of meals', () async {
      // Arrange
      final today = DateTime.now();
      final historyLogs = List.generate(7, (i) {
        final date = today.subtract(Duration(days: i + 1));
        return MealLog(
          id: i + 1,
          userId: 1,
          date: date,
          createdAt: date,
          totalCalories: 1800 + (i * 50).toDouble(),
          totalProtein: 120 + i.toDouble(),
          totalCarbohydrates: 180.0,
          totalFat: 60.0,
        );
      });

      // Need to stub all dependencies that loadNutritionHistory might trigger
      final goal = createTestGoal();
      final progress = createTestProgress(goal: goal);
      final streak = StreakInfo(
        currentStreak: 1,
        longestStreak: 1,
        totalDaysLogged: 7,
      );
      final todayMealLog = MealLog(
        id: 100,
        userId: 1,
        date: today,
        createdAt: today,
        totalCalories: 1500,
        totalProtein: 100,
        totalCarbohydrates: 150,
        totalFat: 50,
      );

      when(
        mockNutritionRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) async => historyLogs);
      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => todayMealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadNutritionHistory();

      // Assert
      expect(provider.nutritionHistory.length, equals(7));
      // Should be sorted by date (most recent first)
      expect(
        provider.nutritionHistory.first.date.isAfter(
          provider.nutritionHistory.last.date,
        ),
        isTrue,
      );
    });

    test(
      'Streak increments when user logs meals on consecutive days',
      () async {
        // Arrange
        final goal = createTestGoal();
        final progress = createTestProgress(goal: goal, consumedCalories: 1500);
        final streak = StreakInfo(
          currentStreak: 7,
          longestStreak: 14,
          totalDaysLogged: 30,
        );

        final mealLog = MealLog(
          id: 1,
          userId: 1,
          date: DateTime.now(),
          createdAt: DateTime.now(),
          totalCalories: 1500,
          totalProtein: 100,
          totalCarbohydrates: 150,
          totalFat: 50,
        );

        when(
          mockNutritionRepository.getTodaysMealLog(),
        ).thenAnswer((_) async => mealLog);
        when(
          mockNutritionRepository.getActiveNutritionGoal(),
        ).thenAnswer((_) async => goal);
        when(
          mockNutritionRepository.getNutritionProgress(),
        ).thenAnswer((_) async => progress);
        when(
          mockNutritionRepository.getStreak(),
        ).thenAnswer((_) async => streak);

        final provider = NutritionProvider(
          mockNutritionRepository,
          mockConnectivity,
        );

        // Act
        await provider.loadTodaysData();

        // Assert
        expect(provider.streakInfo, isNotNull);
        expect(provider.streakInfo!.currentStreak, equals(7));
        expect(provider.streakInfo!.longestStreak, equals(14));
      },
    );

    test('User meets daily goals and sees 100% progress', () async {
      // Arrange - User has hit exactly their goals
      final goal = createTestGoal(
        dailyCalories: 2000,
        dailyProtein: 150,
        dailyCarbs: 200,
        dailyFat: 65,
      );

      final progress = createTestProgress(
        goal: goal,
        consumedCalories: 2000,
        consumedProtein: 150,
        consumedCarbs: 200,
        consumedFat: 65,
      );

      final mealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalCalories: 2000,
        totalProtein: 150,
        totalCarbohydrates: 200,
        totalFat: 65,
      );

      final streak = StreakInfo(
        currentStreak: 1,
        longestStreak: 1,
        totalDaysLogged: 1,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => mealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadTodaysData();

      // Assert
      expect(provider.caloriesRemaining, equals(0));
      expect(provider.calorieProgressPercentage, equals(100.0)); // 100%
      expect(provider.proteinProgressPercentage, equals(100.0));
    });

    test('User exceeds calorie goal shows negative remaining', () async {
      // Arrange - User has exceeded their calorie goal
      final goal = createTestGoal(dailyCalories: 2000);
      final progress = createTestProgress(goal: goal, consumedCalories: 2500);

      final mealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalCalories: 2500,
        totalProtein: 0,
        totalCarbohydrates: 0,
        totalFat: 0,
      );

      final streak = StreakInfo(
        currentStreak: 1,
        longestStreak: 1,
        totalDaysLogged: 1,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => mealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadTodaysData();

      // Assert
      expect(provider.caloriesRemaining, equals(-500)); // Over by 500
      expect(
        provider.calorieProgressPercentage,
        greaterThan(100.0),
      ); // Over 100%
    });
  });

  // =============================================================================
  // OFFLINE SCENARIOS
  // =============================================================================
  group('Offline Scenarios', () {
    test('Workout can be started and completed offline', () async {
      // Arrange - Offline
      when(mockConnectivity.isOnline).thenReturn(false);

      final draftSession = Session(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        status: 'draft',
        exercises: [],
      );

      final startedSession = draftSession.copyWith(
        status: 'in_progress',
        startedAt: DateTime.now().toUtc(),
      );

      final completedSession = startedSession.copyWith(
        status: 'completed',
        completedAt: DateTime.now().toUtc(),
        duration: 30,
      );

      when(
        mockSessionRepository.getSession(1),
      ).thenAnswer((_) async => draftSession);
      when(
        mockSessionRepository.getInProgressSessions(),
      ).thenAnswer((_) async => []);
      when(
        mockSessionRepository.updateSessionStatus(1, 'in_progress'),
      ).thenAnswer((_) async => startedSession);
      when(
        mockSessionRepository.updateSessionStatus(
          1,
          'completed',
          duration: anyNamed('duration'),
        ),
      ).thenAnswer((_) async => completedSession);

      final provider = ActiveWorkoutProvider(
        mockSessionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadSession(1);
      await provider.startWorkout();
      final finished = await provider.finishWorkout();

      // Assert - Should work offline (data saved locally)
      expect(finished, isTrue);
      verify(
        mockSessionRepository.updateSessionStatus(1, 'in_progress'),
      ).called(1);
      verify(
        mockSessionRepository.updateSessionStatus(
          1,
          'completed',
          duration: anyNamed('duration'),
        ),
      ).called(1);
    });

    test('Nutrition data loads from cache when offline', () async {
      // Arrange - Offline
      when(mockConnectivity.isOnline).thenReturn(false);

      final goal = createTestGoal();
      final cachedMealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalCalories: 1000,
        totalProtein: 80,
        totalCarbohydrates: 100,
        totalFat: 40,
      );

      final progress = createTestProgress(goal: goal, consumedCalories: 1000);
      final streak = StreakInfo(
        currentStreak: 1,
        longestStreak: 1,
        totalDaysLogged: 1,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => cachedMealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadTodaysData();

      // Assert - Should load cached data
      expect(provider.todaysMealLog, isNotNull);
      expect(provider.todaysMealLog!.totalCalories, equals(1000));
    });

    test('Sessions list loads from local cache when offline', () async {
      // Arrange - Offline
      when(mockConnectivity.isOnline).thenReturn(false);

      final cachedSessions = [
        Session(
          id: 1,
          userId: 1,
          date: DateTime.now(),
          status: 'completed',
          exercises: [],
        ),
      ];

      when(
        mockSessionRepository.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => cachedSessions);
      when(
        mockSessionRepository.watchSessions(1),
      ).thenAnswer((_) => Stream.value(cachedSessions));

      final provider = SessionsProvider(
        mockSessionRepository,
        mockAuthService,
        mockConnectivity,
      );

      // Act
      await provider.loadSessions();

      // Assert
      expect(provider.sessions.length, equals(1));
      expect(provider.sessions.first.status, equals('completed'));
    });
  });

  // =============================================================================
  // EDGE CASES AND ERROR HANDLING
  // =============================================================================
  group('Edge Cases', () {
    test('Very long workout (24+ hours) handles correctly', () async {
      // Arrange - Workout started over 24 hours ago
      final longAgoStart = DateTime.now().toUtc().subtract(
        const Duration(hours: 25),
      );

      final longSession = Session(
        id: 1,
        userId: 1,
        date: DateTime.now().subtract(const Duration(days: 1)),
        status: 'in_progress',
        startedAt: longAgoStart,
        exercises: [],
      );

      when(
        mockSessionRepository.getSession(1),
      ).thenAnswer((_) async => longSession);

      final provider = ActiveWorkoutProvider(
        mockSessionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadSession(1);

      // Assert - Should handle 25+ hour workout
      expect(provider.elapsedTime.inHours, greaterThanOrEqualTo(25));
      expect(provider.isTimerRunning, isTrue);
    });

    test('Workout with 0 duration completes successfully', () async {
      // Arrange
      final session = Session(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        status: 'in_progress',
        startedAt: DateTime.now().toUtc(),
        exercises: [],
      );

      final completedSession = session.copyWith(
        status: 'completed',
        duration: 0,
      );

      when(
        mockSessionRepository.getSession(1),
      ).thenAnswer((_) async => session);
      when(
        mockSessionRepository.updateSessionStatus(
          1,
          'completed',
          duration: anyNamed('duration'),
        ),
      ).thenAnswer((_) async => completedSession);

      final provider = ActiveWorkoutProvider(
        mockSessionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadSession(1);
      final finished = await provider.finishWorkout();

      // Assert
      expect(finished, isTrue);
    });

    test('Empty meal log shows full goal remaining', () async {
      // Arrange - Empty meal log with 0 calories
      final goal = createTestGoal();
      final progress = createTestProgress(goal: goal);
      final streak = StreakInfo(
        currentStreak: 0,
        longestStreak: 5,
        totalDaysLogged: 10,
      );

      final emptyMealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalCalories: 0,
        totalProtein: 0,
        totalCarbohydrates: 0,
        totalFat: 0,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => emptyMealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadTodaysData();

      // Assert - Should show full goal remaining
      expect(provider.todaysMealLog, isNotNull);
      expect(provider.caloriesRemaining, equals(goal.dailyCalories));
    });

    test('Program with all workouts completed marks as completed', () async {
      // Arrange - All 3 workouts completed
      final workouts = List.generate(
        3,
        (i) => createTestProgramWorkout(
          id: i + 1,
          programId: 1,
          isCompleted: true,
        ),
      );

      final program = createTestProgram(
        id: 1,
        isActive: false,
        isCompleted: true,
        workouts: workouts,
      );

      when(
        mockProgramsRepository.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program]);

      final provider = ProgramsProvider(
        mockProgramsRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadPrograms();

      // Assert
      expect(provider.completedPrograms.length, equals(1));
      expect(provider.activePrograms.length, equals(0));
    });

    test('Multiple rapid pause/resume calls are handled correctly', () async {
      // Arrange
      final session = Session(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        status: 'in_progress',
        startedAt: DateTime.now().toUtc(),
        exercises: [],
      );

      when(
        mockSessionRepository.getSession(1),
      ).thenAnswer((_) async => session);
      when(
        mockSessionRepository.pauseSession(any, any),
      ).thenAnswer((_) async {});
      when(
        mockSessionRepository.resumeSession(any, any),
      ).thenAnswer((_) async {});

      final provider = ActiveWorkoutProvider(
        mockSessionRepository,
        mockConnectivity,
      );

      // Act - Rapid pause/resume
      await provider.loadSession(1);

      // Fire multiple operations without waiting
      provider.pauseTimer();
      provider.resumeTimer();
      provider.pauseTimer();
      provider.resumeTimer();

      // Wait for all to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert - Provider should be in a valid state
      expect(provider.currentSession, isNotNull);
      // Timer should be running (last operation was resume)
    });

    test('Session with exercises shows exercise count correctly', () async {
      // Arrange
      final exercises = <Exercise>[
        Exercise(
          id: 1,
          sessionId: 1,
          name: 'Bench Press',
          sortOrder: 0,
          exerciseSets: [
            ExerciseSet(
              id: 1,
              exerciseId: 1,
              setNumber: 1,
              reps: 10,
              weight: 60,
            ),
          ],
        ),
        Exercise(
          id: 2,
          sessionId: 1,
          name: 'Squat',
          sortOrder: 1,
          exerciseSets: [],
        ),
      ];

      final session = Session(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        status: 'in_progress',
        startedAt: DateTime.now().toUtc(),
        exercises: exercises,
      );

      when(
        mockSessionRepository.getSession(1),
      ).thenAnswer((_) async => session);

      final provider = ActiveWorkoutProvider(
        mockSessionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadSession(1);

      // Assert
      expect(provider.exercises.length, equals(2));
      expect(provider.exercises[0].name, equals('Bench Press'));
      expect(provider.exercises[0].exerciseSets.length, equals(1));
    });
  });

  // =============================================================================
  // NOTIFICATION TRIGGER SCENARIOS
  // =============================================================================
  group('Notification Trigger Scenarios', () {
    test(
      'Low nutrition progress late in day should trigger reminder check',
      () async {
        // Arrange - 8 PM with only 50% of calories
        final goal = createTestGoal(dailyCalories: 2000);
        final progress = createTestProgress(
          goal: goal,
          consumedCalories: 1000, // Only 50%
        );

        final mealLog = MealLog(
          id: 1,
          userId: 1,
          date: DateTime.now(),
          createdAt: DateTime.now(),
          totalCalories: 1000,
          totalProtein: 0,
          totalCarbohydrates: 0,
          totalFat: 0,
        );

        final streak = StreakInfo(
          currentStreak: 5,
          longestStreak: 10,
          totalDaysLogged: 30,
        );

        when(
          mockNutritionRepository.getTodaysMealLog(),
        ).thenAnswer((_) async => mealLog);
        when(
          mockNutritionRepository.getActiveNutritionGoal(),
        ).thenAnswer((_) async => goal);
        when(
          mockNutritionRepository.getNutritionProgress(),
        ).thenAnswer((_) async => progress);
        when(
          mockNutritionRepository.getStreak(),
        ).thenAnswer((_) async => streak);

        final provider = NutritionProvider(
          mockNutritionRepository,
          mockConnectivity,
        );

        // Act
        await provider.loadTodaysData();

        // Assert - Progress is under 80%, notification should be sent
        expect(provider.calorieProgressPercentage, lessThan(80.0));
        expect(provider.caloriesRemaining, equals(1000));
      },
    );

    test('High nutrition progress should not trigger reminder', () async {
      // Arrange - 85% of calories consumed
      final goal = createTestGoal(dailyCalories: 2000);
      final progress = createTestProgress(
        goal: goal,
        consumedCalories: 1700, // 85%
      );

      final mealLog = MealLog(
        id: 1,
        userId: 1,
        date: DateTime.now(),
        createdAt: DateTime.now(),
        totalCalories: 1700,
        totalProtein: 0,
        totalCarbohydrates: 0,
        totalFat: 0,
      );

      final streak = StreakInfo(
        currentStreak: 5,
        longestStreak: 10,
        totalDaysLogged: 30,
      );

      when(
        mockNutritionRepository.getTodaysMealLog(),
      ).thenAnswer((_) async => mealLog);
      when(
        mockNutritionRepository.getActiveNutritionGoal(),
      ).thenAnswer((_) async => goal);
      when(
        mockNutritionRepository.getNutritionProgress(),
      ).thenAnswer((_) async => progress);
      when(mockNutritionRepository.getStreak()).thenAnswer((_) async => streak);

      final provider = NutritionProvider(
        mockNutritionRepository,
        mockConnectivity,
      );

      // Act
      await provider.loadTodaysData();

      // Assert - Progress is over 80%, no notification needed
      expect(provider.calorieProgressPercentage, greaterThan(80.0));
    });
  });
}
