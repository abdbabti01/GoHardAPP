import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
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
import 'package:go_hard_app/routes/app_router.dart';
import 'package:go_hard_app/ui/screens/sessions/session_detail_screen.dart';
import 'package:go_hard_app/ui/screens/today/today_screen.dart';

@GenerateMocks([
  SessionRepository,
  ConnectivityService,
  ProgramsRepository,
  RunningRepository,
  NutritionRepository,
])
import 'today_screen_navigation_test.mocks.dart';

/// Proves - through the REAL `TodayScreen` (the app's home dashboard, and a
/// second real, reachable navigation surface distinct from `TrainScreen`
/// and `SessionsScreen`) - that tapping a completed workout's mini-card
/// constructs `SessionDetailArgs` with the tapped row's exact public
/// `sessionId` and its exact, unambiguous `localId`, even when another
/// visible row occupies the fully-swapped identity slot. No `pumpAndSettle`,
/// `Future.delayed`, `Timer`, or event-loop polling - only explicit
/// `tester.pump()` calls and synchronous `StreamController.add()`.
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

  final today = DateTime.now();
  final todayDateOnly = DateTime(today.year, today.month, today.day);

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
      // A FRESH stream per install, matching the real repository -
      // TodayScreen's own initState re-arms the watch on top of the load
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
      programsRepo.getPrograms(isActive: anyNamed('isActive')),
    ).thenAnswer((_) async => []);
    // RunningProvider.loadDashboardData() and NutritionProvider's loads each
    // catch any repository failure internally and simply leave their state
    // at its default (empty/null) - left unstubbed deliberately, matching
    // the established pattern in the sibling navigation tests.

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
      ChangeNotifierProvider<ActiveWorkoutProvider>.value(
        value: activeWorkoutProvider,
      ),
      ChangeNotifierProvider<ProgramsProvider>.value(value: programsProvider),
      ChangeNotifierProvider<RunningProvider>.value(value: runningProvider),
      ChangeNotifierProvider<NutritionProvider>.value(value: nutritionProvider),
    ],
    child: MaterialApp(
      onGenerateRoute: AppRouter.generateRoute,
      home: const Scaffold(body: TodayScreen()),
    ),
  );

  testWidgets("tapping a completed workout's mini-card on the real TodayScreen "
      'navigates with exactly the right SessionDetailArgs - the tapped '
      "row's REAL localId (41), never its public sessionId (700), never "
      'swapped, and never a value borrowed from a row occupying the '
      "opposite identity slot - and the pushed detail screen's diagnostic "
      "is the tapped row's own, not the colliding row's", (tester) async {
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
    // (conflict) makes any wrong lookup visibly distinguishable. Given a
    // status that does NOT also render as a "today" mini-card (avoiding
    // ambiguity about which mini-card is tapped), while still being a
    // fully joined, diagnostics-bearing row.
    final collidingSession = Session(
      id: 41,
      userId: 1,
      date: todayDateOnly.subtract(const Duration(days: 10)),
      name: 'Colliding Workout',
      status: 'completed',
    );
    when(sessionRepo.getSession(any)).thenAnswer((_) async => displayedSession);

    await sessionsProvider.loadSessions();
    await tester.pumpWidget(host());
    // Let TodayScreen's postFrameCallback-triggered loadSessions() (which
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

    await tester.tap(find.text('Displayed Workout'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final detailScreenFinder = find.byType(SessionDetailScreen);
    final pushed = tester.widget<SessionDetailScreen>(detailScreenFinder);
    expect(pushed.sessionId, 700);
    expect(pushed.localId, 41);

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
