import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/tab_navigation_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/exercise_repository.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/data/repositories/programs_repository.dart';
import 'package:go_hard_app/data/repositories/running_repository.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';
import 'package:go_hard_app/providers/exercises_provider.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';
import 'package:go_hard_app/providers/programs_provider.dart';
import 'package:go_hard_app/providers/running_provider.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';
import 'package:go_hard_app/routes/app_router.dart';
import 'package:go_hard_app/ui/screens/sessions/session_detail_screen.dart';
import 'package:go_hard_app/ui/screens/sessions/sessions_screen.dart';

@GenerateMocks([
  SessionRepository,
  ExerciseRepository,
  ConnectivityService,
  ProgramsRepository,
  RunningRepository,
  NutritionRepository,
])
import 'sessions_screen_navigation_test.mocks.dart';

/// Proves - through the REAL `SessionsScreen` "My Workouts" tab - that
/// tapping a session card constructs `SessionDetailArgs` with the tapped
/// row's exact public `sessionId` and its exact, unambiguous `localId`, even
/// when another visible row occupies the fully-swapped identity slot (its
/// public id equal to the tapped row's localId, and vice versa).
///
/// NOTE ON REACHABILITY: unlike `TrainScreen` (the real bottom-nav workouts
/// surface, see `train_screen_sync_issues_test.dart`) and `TodayScreen` (the
/// home dashboard), `SessionsScreen` is currently NOT wired into any live
/// navigation path - `RouteNames.sessions` is registered in
/// `AppRouter.generateRoute` and referenced by a couple of `popUntil`
/// predicates, but nothing in `lib/` ever `pushNamed`s it. This test still
/// mounts the real widget via the real `MaterialApp`/`Navigator`/
/// `AppRouter.generateRoute` and exercises its real `_handleSessionTap` /
/// `SessionDetailArgs` construction, guarding this file's identity-argument
/// correctness against regression if it is ever wired back in (or kept as a
/// deliberate alternate entry point) - it does not itself demonstrate that a
/// user can reach this screen today.
/// No `pumpAndSettle`, `Future.delayed`, `Timer`, or event-loop polling -
/// only explicit `tester.pump()` calls and synchronous
/// `StreamController.add()`.
void main() {
  late MockSessionRepository sessionRepo;
  late MockExerciseRepository exerciseRepo;
  late MockConnectivityService connectivity;
  late MockProgramsRepository programsRepo;
  late MockRunningRepository runningRepo;
  late MockNutritionRepository nutritionRepo;
  late UserSessionEpoch epoch;
  late List<StreamController<SessionSyncSnapshot>> watchControllers;
  late StreamController<bool> connectivityController;
  late SessionsProvider sessionsProvider;
  late ExercisesProvider exercisesProvider;
  late ActiveWorkoutProvider activeWorkoutProvider;
  late ProgramsProvider programsProvider;
  late RunningProvider runningProvider;
  late NutritionProvider nutritionProvider;
  late TabNavigationService tabNavigationService;

  final today = DateTime.now();
  final todayDateOnly = DateTime(today.year, today.month, today.day);

  setUp(() {
    sessionRepo = MockSessionRepository();
    exerciseRepo = MockExerciseRepository();
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
      // A FRESH stream per install, matching the real repository -
      // SessionsScreen's own initState re-arms the watch on top of the load
      // this test drives.
      final c = StreamController<SessionSyncSnapshot>(sync: true);
      watchControllers.add(c);
      return c.stream;
    });

    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);

    when(
      exerciseRepo.getExerciseTemplates(
        category: anyNamed('category'),
        muscleGroup: anyNamed('muscleGroup'),
        isCustom: anyNamed('isCustom'),
      ),
    ).thenAnswer((_) async => []);
    when(
      programsRepo.getPrograms(isActive: anyNamed('isActive')),
    ).thenAnswer((_) async => []);
    // RunningProvider.loadDashboardData() and NutritionProvider's own loads
    // each catch any repository failure internally and simply leave their
    // state at its default (empty/null) - left unstubbed deliberately,
    // exactly like the established ExerciseRepository/ProgramsRepository
    // pattern in the sibling TrainScreen test.

    epoch = UserSessionEpoch()..activate(1);
    sessionsProvider = SessionsProvider(sessionRepo, epoch, connectivity);
    exercisesProvider = ExercisesProvider(exerciseRepo, connectivity);
    activeWorkoutProvider = ActiveWorkoutProvider(
      sessionRepo,
      epoch,
      connectivity,
    );
    programsProvider = ProgramsProvider(programsRepo, epoch, connectivity);
    runningProvider = RunningProvider(runningRepo, epoch, connectivity);
    nutritionProvider = NutritionProvider(nutritionRepo, epoch, connectivity);
    tabNavigationService = TabNavigationService();
  });

  tearDown(() async {
    sessionsProvider.dispose();
    activeWorkoutProvider.dispose();
    for (final c in watchControllers) {
      if (!c.isClosed) await c.close();
    }
    if (!connectivityController.isClosed) await connectivityController.close();
  });

  // MultiProvider wraps the WHOLE MaterialApp (not just `home:`) so that
  // every route the app's own Navigator pushes - not only the first one -
  // is a descendant of these providers. A route pushed via `onGenerateRoute`
  // is inserted as a Navigator-internal sibling of the initial route, not as
  // a child of whatever wrapped `home:` alone - a MultiProvider placed
  // inside `home:` would leave any SECOND route (like the pushed
  // SessionDetailScreen) unable to find these providers at all.
  Widget host() => MultiProvider(
    providers: [
      ChangeNotifierProvider<ConnectivityService>.value(value: connectivity),
      ChangeNotifierProvider<SessionsProvider>.value(value: sessionsProvider),
      ChangeNotifierProvider<ExercisesProvider>.value(value: exercisesProvider),
      ChangeNotifierProvider<ActiveWorkoutProvider>.value(
        value: activeWorkoutProvider,
      ),
      ChangeNotifierProvider<ProgramsProvider>.value(value: programsProvider),
      ChangeNotifierProvider<RunningProvider>.value(value: runningProvider),
      ChangeNotifierProvider<NutritionProvider>.value(value: nutritionProvider),
      ChangeNotifierProvider<TabNavigationService>.value(
        value: tabNavigationService,
      ),
    ],
    child: MaterialApp(
      onGenerateRoute: AppRouter.generateRoute,
      home: const SessionsScreen(),
    ),
  );

  testWidgets('tapping a completed session card on the real SessionsScreen My '
      "Workouts tab navigates with exactly the right SessionDetailArgs - the "
      "tapped row's REAL localId (41), never its public sessionId (700), "
      'never swapped, and never a value borrowed from a row occupying the '
      "opposite identity slot - and the pushed detail screen's diagnostic is "
      "the tapped row's own, not the colliding row's", (tester) async {
    // Displayed row: public Session.id == 700, real localId == 41,
    // retrying failure.
    final displayedSession = Session(
      id: 700,
      userId: 1,
      date: todayDateOnly,
      name: 'Displayed Workout',
      status: 'completed',
    );
    // Colliding row: public Session.id (41) == displayed's REAL localId;
    // its OWN localId (700) == displayed's public sessionId - a full
    // cross-wiring collision in both directions. A different diagnostic
    // (conflict) makes any wrong lookup visibly distinguishable.
    final collidingSession = Session(
      id: 41,
      userId: 1,
      date: todayDateOnly,
      name: 'Colliding Workout',
      status: 'completed',
    );
    when(sessionRepo.getSession(any)).thenAnswer((_) async => displayedSession);

    await sessionsProvider.loadSessions();
    await tester.pumpWidget(host());
    // Let SessionsScreen's postFrameCallback-triggered loadSessions() (which
    // re-arms the watch with a fresh controller) fully resolve. This count
    // is tied to loadSessions()'s current shape (exactly one await -
    // getSessions() - before _installWatch); see the matching comment in
    // train_screen_sync_issues_test.dart for why an insufficient count
    // would target the wrong watch generation without necessarily failing
    // this specific test's assertions.
    await tester.pump();
    await tester.pump();

    watchControllers.last.add(
      SessionSyncSnapshot(
        visibleEntries: [
          SessionListEntry(
            session: displayedSession,
            localId: 41,
            diagnostics: const SessionSyncDiagnostics(
              state: SessionSyncState.retryingFailure,
            ),
          ),
          SessionListEntry(
            session: collidingSession,
            localId: 700,
            diagnostics: const SessionSyncDiagnostics(
              state: SessionSyncState.conflict,
            ),
          ),
        ],
        retryingFailureCount: 1,
        conflictCount: 1,
      ),
    );
    await tester.pump();

    // The "My Workouts" tab renders WeeklyProgressCard/RunningWidget/
    // NutritionSummaryCard/the program-workouts section ahead of the
    // "Today" section, pushing the target card beyond the ListView's
    // default (~250px) sliver cache extent - it never mounts as an Element
    // until scrolled into range. Incremental, deterministic jumpTo steps
    // (not a gesture-drag loop, and not a real-time wait; bounded by both
    // maxScrollExtent and a fixed iteration cap) on the SPECIFIC ListView's
    // own Scrollable - not the ancestor TabBarView/PageView's Scrollable,
    // and not a single full jump to maxScrollExtent, which would overshoot
    // past these near-the-top cards (with nothing below them in this
    // fixture) and scroll them back out of range from the other side.
    final listScrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    var offset = 0.0;
    for (
      var i = 0;
      i < 30 &&
          find.text('Displayed Workout').evaluate().isEmpty &&
          offset < listScrollable.position.maxScrollExtent;
      i++
    ) {
      offset = (offset + 200).clamp(
        0.0,
        listScrollable.position.maxScrollExtent,
      );
      listScrollable.position.jumpTo(offset);
      await tester.pump();
    }

    await tester.tap(find.text('Displayed Workout'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final detailScreenFinder = find.byType(SessionDetailScreen);
    final pushed = tester.widget<SessionDetailScreen>(detailScreenFinder);
    expect(pushed.sessionId, 700);
    expect(pushed.localId, 41);

    // Scoped to the pushed screen itself - the underlying SessionsScreen
    // route (still mounted beneath it) also renders a corner dot for
    // EACH row, which is irrelevant to what the DETAIL screen's own
    // AppBar action shows.
    expect(
      find.descendant(
        of: detailScreenFinder,
        matching: find.byIcon(Icons.sync_problem_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: detailScreenFinder,
        matching: find.byIcon(Icons.warning_rounded),
      ),
      findsNothing,
    );
  });
}
