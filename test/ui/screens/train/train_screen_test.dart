import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/goal.dart';
import 'package:go_hard_app/data/models/program.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/programs_repository.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';
import 'package:go_hard_app/providers/programs_provider.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';
import 'package:go_hard_app/routes/route_names.dart';
import 'package:go_hard_app/ui/screens/train/train_screen.dart';

@GenerateMocks([SessionRepository, ProgramsRepository, ConnectivityService])
import 'train_screen_test.mocks.dart';

void main() {
  late MockSessionRepository sessionRepo;
  late MockProgramsRepository programsRepo;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late List<StreamController<SessionSyncSnapshot>> watchControllers;
  late UserSessionEpoch epoch;
  late SessionsProvider sessionsProvider;
  late ProgramsProvider programsProvider;
  late ActiveWorkoutProvider activeWorkoutProvider;
  late List<String?> pushed;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  ProgramWorkout workout(int id, DateTime date, {bool completed = false}) =>
      ProgramWorkout(
        id: id,
        programId: 1,
        weekNumber: 1,
        dayNumber: date.weekday,
        workoutName: id == 3 ? 'Upper Body' : 'Workout $id',
        workoutType: 'Strength',
        exercisesJson: '[]',
        isCompleted: completed,
        orderIndex: id,
        scheduledDate: date,
      );

  Program activePlan() => Program(
    id: 1,
    userId: 1,
    title: '4-Day Upper/Lower',
    totalWeeks: 12,
    currentWeek: 2,
    currentDay: 1,
    startDate: today.subtract(const Duration(days: 14)),
    isActive: true,
    isCompleted: false,
    createdAt: today.subtract(const Duration(days: 20)),
    goal: Goal(
      id: 9,
      userId: 1,
      goalType: 'Muscle Gain',
      targetValue: 10,
      currentValue: 0,
      startDate: today.subtract(const Duration(days: 20)),
      isActive: true,
      isCompleted: false,
      createdAt: today.subtract(const Duration(days: 20)),
    ),
    workouts: [
      workout(1, today.subtract(const Duration(days: 8)), completed: true),
      workout(2, today.subtract(const Duration(days: 7))), // missed
      workout(3, today), // today
      workout(4, today.add(const Duration(days: 8))), // not due
    ],
  );

  Session completed(int id, int daysAgo) => Session(
    id: id,
    userId: 1,
    date: today.subtract(Duration(days: daysAgo)),
    name: 'Done $id',
    status: 'completed',
  );

  void stubSessions(List<Session> sessions) {
    when(
      sessionRepo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => sessions);
  }

  void stubPrograms(List<Program> programs) {
    when(
      programsRepo.getPrograms(isActive: anyNamed('isActive')),
    ).thenAnswer((_) async => programs);
  }

  setUp(() {
    sessionRepo = MockSessionRepository();
    programsRepo = MockProgramsRepository();
    connectivity = MockConnectivityService();
    connectivityController = StreamController<bool>.broadcast(sync: true);
    watchControllers = [];
    pushed = [];

    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    when(sessionRepo.watchSessionSyncSnapshot(any)).thenAnswer((_) {
      final c = StreamController<SessionSyncSnapshot>(sync: true);
      watchControllers.add(c);
      return c.stream;
    });
    stubSessions([]);
    stubPrograms([]);

    epoch = UserSessionEpoch()..activate(1);
    sessionsProvider = SessionsProvider(sessionRepo, epoch, connectivity);
    programsProvider = ProgramsProvider(programsRepo, epoch, connectivity);
    activeWorkoutProvider = ActiveWorkoutProvider(
      sessionRepo,
      epoch,
      connectivity,
    );
  });

  tearDown(() async {
    sessionsProvider.dispose();
    programsProvider.dispose();
    activeWorkoutProvider.dispose();
    for (final c in watchControllers) {
      if (!c.isClosed) await c.close();
    }
    await connectivityController.close();
  });

  Future<void> pumpTrain(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConnectivityService>.value(
            value: connectivity,
          ),
          ChangeNotifierProvider<SessionsProvider>.value(
            value: sessionsProvider,
          ),
          ChangeNotifierProvider<ProgramsProvider>.value(
            value: programsProvider,
          ),
          ChangeNotifierProvider<ActiveWorkoutProvider>.value(
            value: activeWorkoutProvider,
          ),
        ],
        child: MaterialApp(
          home: const Scaffold(body: TrainScreen()),
          onGenerateRoute: (settings) {
            pushed.add(settings.name);
            return MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('stub')),
              settings: settings,
            );
          },
        ),
      ),
    );
    // initState's post-frame loadSessions()/loadPrograms() each resolve
    // after one await; bounded pumps (WeeklyProgressCard may animate).
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('one page with five sections and no sub-tabs', (tester) async {
    stubPrograms([activePlan()]);
    await pumpTrain(tester);

    expect(find.byType(TabBar), findsNothing);
    for (final title in [
      'My Plan',
      'This Week',
      'Progress',
      'Recent',
      'Tools',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('My Plan shows plan, goal, week and adherence', (tester) async {
    stubPrograms([activePlan()]);
    await pumpTrain(tester);

    expect(find.text('4-Day Upper/Lower'), findsOneWidget);
    expect(find.text('Goal: Muscle Gain'), findsOneWidget);
    expect(find.text('Week 2 of 12 · 1 of 2 workouts done'), findsOneWidget);
  });

  testWidgets('This Week marks today and opens the planned workout', (
    tester,
  ) async {
    stubPrograms([activePlan()]);
    await pumpTrain(tester);

    expect(find.text('Upper Body'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.text('Upper Body'));
    await tester.pump();
    expect(pushed, [RouteNames.programWorkout]);
  });

  testWidgets('no plan while online offers Create a plan', (tester) async {
    await pumpTrain(tester);

    expect(find.text('No plan yet.'), findsOneWidget);
    expect(find.text('This Week'), findsNothing);
    await tester.tap(find.text('Create a plan'));
    await tester.pump();
    expect(pushed, [RouteNames.workoutPlanForm]);
  });

  testWidgets('offline with nothing loaded never claims there is no plan', (
    tester,
  ) async {
    when(connectivity.isOnline).thenReturn(false);
    await pumpTrain(tester);

    expect(find.text('No plan yet.'), findsNothing);
    expect(find.text('Create a plan'), findsNothing);
    expect(
      find.text("Your plan shows here when you're online."),
      findsOneWidget,
    );
  });

  testWidgets('Recent lists the last three finished workouts only', (
    tester,
  ) async {
    stubSessions([
      completed(1, 1),
      completed(2, 2),
      completed(3, 3),
      completed(4, 4),
      Session(
        id: 5,
        userId: 1,
        date: today.add(const Duration(days: 1)),
        name: 'Planned 5',
        status: 'planned',
      ),
    ]);
    await pumpTrain(tester);

    expect(find.text('Done 1'), findsOneWidget);
    expect(find.text('Done 3'), findsOneWidget);
    expect(find.text('Done 4'), findsNothing);
    expect(find.text('Planned 5'), findsNothing);
  });

  for (final (label, route) in [
    ('View plan', RouteNames.programs),
    ('View progress', RouteNames.analytics),
    ('History', RouteNames.workoutHistory),
    ('Exercise library', RouteNames.exercises),
  ]) {
    testWidgets('"$label" opens $route', (tester) async {
      stubPrograms([activePlan()]);
      await pumpTrain(tester);

      await tester.tap(find.text(label));
      await tester.pump();
      expect(pushed, [route]);
    });
  }

  test('legacy Train sub-tabs map to the screens that replaced them', () {
    expect(TrainScreen.routeForLegacySubTab(0), RouteNames.workoutHistory);
    expect(TrainScreen.routeForLegacySubTab(1), RouteNames.programs);
    expect(TrainScreen.routeForLegacySubTab(2), RouteNames.exercises);
    expect(TrainScreen.routeForLegacySubTab(null), isNull);
    expect(TrainScreen.routeForLegacySubTab(7), isNull);
  });
}
