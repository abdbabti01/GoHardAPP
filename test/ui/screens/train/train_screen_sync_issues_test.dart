import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/exercise_repository.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';
import 'package:go_hard_app/providers/exercises_provider.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';
import 'package:go_hard_app/routes/app_router.dart';
import 'package:go_hard_app/ui/screens/sessions/session_detail_screen.dart';
import 'package:go_hard_app/ui/screens/train/train_screen.dart';
import 'package:go_hard_app/ui/widgets/common/sync_issues_banner.dart';

@GenerateMocks([SessionRepository, ExerciseRepository, ConnectivityService])
import 'train_screen_sync_issues_test.mocks.dart';

/// Proves - through the REAL `TrainScreen` workouts-tab path (the actual
/// bottom-nav workout surface a user reaches; `SessionsScreen` is not
/// navigated to in normal use) - that the passive sync-issues surface is
/// genuinely reachable and correctly wired: the aggregate banner, the
/// per-card decorative indicator, distinct conflict copy, offline
/// suppression, and the total absence of any retry/discard/resolution
/// control. Real [UserSessionEpoch]; the joined watch is
/// StreamController-gated (a FRESH controller per `_installWatch` call,
/// matching production - `TrainScreen.initState` itself calls
/// `loadSessions()`, so a second, real re-arm happens on top of the load
/// this test drives) - no `pumpAndSettle`, `Future.delayed`, `Timer`, or
/// event-loop polling.
void main() {
  late MockSessionRepository sessionRepo;
  late MockExerciseRepository exerciseRepo;
  late MockConnectivityService connectivity;
  late UserSessionEpoch epoch;
  late List<StreamController<SessionSyncSnapshot>> watchControllers;
  late StreamController<bool> connectivityController;
  late SessionsProvider sessionsProvider;
  late ExercisesProvider exercisesProvider;
  late ActiveWorkoutProvider activeWorkoutProvider;

  final today = DateTime.now();
  final todayDateOnly = DateTime(today.year, today.month, today.day);

  // Deliberately id != localId on every fixture session (id offset by
  // +100 from its localId) - a prior version of this fixture had id ==
  // localId for all three sessions, which meant a mutant that swapped
  // `sessionId`/`localId` (or substituted one for the other) anywhere in
  // the TrainScreen -> SessionDetailArgs path would have been numerically
  // invisible to every test in this file. This non-equal fixture makes
  // that whole test file load-bearing against that mutation class.
  final healthySession = Session(
    id: 101,
    userId: 1,
    date: todayDateOnly,
    name: 'Healthy Workout',
    status: 'completed',
  );
  final failingSession = Session(
    id: 102,
    userId: 1,
    date: todayDateOnly,
    name: 'Retrying Workout',
    status: 'draft',
  );
  final conflictSession = Session(
    id: 103,
    userId: 1,
    date: todayDateOnly,
    name: 'Conflicted Workout',
    status: 'draft',
  );

  final visibleList = [healthySession, failingSession, conflictSession];

  setUp(() {
    sessionRepo = MockSessionRepository();
    exerciseRepo = MockExerciseRepository();
    connectivity = MockConnectivityService();
    watchControllers = [];
    connectivityController = StreamController<bool>.broadcast(sync: true);

    when(
      sessionRepo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => visibleList);
    when(sessionRepo.watchSessionSyncSnapshot(any)).thenAnswer((_) {
      // A FRESH stream per install, exactly like the real repository (Isar's
      // Query.watch() returns a new stream every call) - TrainScreen's own
      // initState re-arms the watch on top of the load this test drives, so
      // reusing a single StreamController (single-subscription) would throw
      // "Stream has already been listened to" on the second install.
      final c = StreamController<SessionSyncSnapshot>(sync: true);
      watchControllers.add(c);
      return c.stream;
    });

    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    // ExercisesProvider auto-loads on construction and again from
    // TrainScreen.initState; stub it to a clean empty result rather than
    // relying on the (also-safe) caught MissingStubError path, to keep test
    // output free of unrelated noise.
    when(
      exerciseRepo.getExerciseTemplates(
        category: anyNamed('category'),
        muscleGroup: anyNamed('muscleGroup'),
        isCustom: anyNamed('isCustom'),
      ),
    ).thenAnswer((_) async => []);

    epoch = UserSessionEpoch()..activate(1);
    sessionsProvider = SessionsProvider(sessionRepo, epoch, connectivity);
    exercisesProvider = ExercisesProvider(exerciseRepo, connectivity);
    // TrainScreen's workouts tab renders ActiveWorkoutBanner unconditionally,
    // which reads this provider - it renders SizedBox.shrink() while
    // currentSession is null (its default), so no extra stubbing is needed.
    activeWorkoutProvider = ActiveWorkoutProvider(
      sessionRepo,
      epoch,
      connectivity,
    );
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
    ],
    child: MaterialApp(
      // The real production router - so a tap that navigates to
      // RouteNames.sessionDetail goes through AppRouter.generateRoute
      // exactly as it does in the app, constructing a real
      // SessionDetailScreen from whatever SessionDetailArgs the tapped
      // card's onTap actually built.
      onGenerateRoute: AppRouter.generateRoute,
      home: const Scaffold(body: TrainScreen()),
    ),
  );

  /// Loads sessions, mounts the real TrainScreen on its default (Workouts)
  /// tab, then feeds the CURRENTLY-ACTIVE joined watch (the last one
  /// installed - TrainScreen's own initState re-arms it once on top of this
  /// test's own load) a snapshot with one retrying failure and one
  /// conflict - the same fixture every test in this file starts from.
  Future<void> pumpWithIssues(WidgetTester tester) async {
    await sessionsProvider.loadSessions();
    await tester.pumpWidget(host());
    // Let TrainScreen's postFrameCallback-triggered loadSessions() (which
    // re-arms the watch with a fresh controller) fully resolve. This count
    // is tied to loadSessions()'s current shape (exactly one await -
    // getSessions() - before _installWatch); if that method's async
    // structure ever grows another await ahead of the re-arm, re-check this
    // margin (watchControllers.last would still resolve correctly by
    // construction - see _watchCallbackOwns's identical() guard - but an
    // insufficient pump count could leave it pointing at an OLDER watch
    // generation than intended, even though the same test data would still
    // pass by coincidence).
    await tester.pump();
    await tester.pump();

    watchControllers.last.add(
      SessionSyncSnapshot(
        visibleEntries: [
          SessionListEntry(session: healthySession, localId: 1),
          SessionListEntry(
            session: failingSession,
            localId: 2,
            diagnostics: const SessionSyncDiagnostics(
              state: SessionSyncState.retryingFailure,
            ),
          ),
          SessionListEntry(
            session: conflictSession,
            localId: 3,
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
  }

  testWidgets(
    'a retrying failure renders the passive aggregate banner through the '
    'real TrainScreen workouts tab',
    (tester) async {
      await pumpWithIssues(tester);

      expect(find.byType(SyncIssuesBanner), findsOneWidget);
      expect(
        find.text(
          "1 workout hasn't synced yet. Your changes are saved and "
          'automatic retry will continue.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'conflicts use the distinct passive copy - never worded as retrying',
    (tester) async {
      await pumpWithIssues(tester);

      expect(
        find.text('1 workout needs review. Your local changes are preserved.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the correct card receives its decorative issue indicator and healthy '
    'cards do not - the merged semantics prove correct per-card attribution',
    (tester) async {
      await pumpWithIssues(tester);

      final healthyLabel =
          tester.getSemantics(find.text('Healthy Workout')).label;
      final failingLabel =
          tester.getSemantics(find.text('Retrying Workout')).label;
      final conflictLabel =
          tester.getSemantics(find.text('Conflicted Workout')).label;

      expect(healthyLabel, isNot(contains('synced')));
      expect(healthyLabel, isNot(contains('review')));
      expect(
        failingLabel,
        contains(
          "Retrying Workout. This workout hasn't synced yet. Your changes "
          'are saved and the app will keep trying.',
        ),
      );
      expect(
        conflictLabel,
        contains(
          'Conflicted Workout. This workout changed elsewhere. Your local '
          'changes are preserved and need review.',
        ),
      );

      // Icons.sync_problem_rounded appears twice by design: once in the
      // aggregate banner's retrying row, once as the failing card's corner
      // dot. Icons.priority_high_rounded appears only once - the conflict
      // card's corner dot (the banner's own conflict icon is the distinct
      // Icons.warning_rounded, never priority_high_rounded).
      expect(find.byIcon(Icons.sync_problem_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    },
  );

  testWidgets('offline state suppresses the sync-issues banner entirely', (
    tester,
  ) async {
    when(connectivity.isOnline).thenReturn(false);
    await pumpWithIssues(tester);

    expect(find.byType(SyncIssuesBanner), findsOneWidget);
    expect(
      find.text(
        "1 workout hasn't synced yet. Your changes are saved and "
        'automatic retry will continue.',
      ),
      findsNothing,
    );
    expect(
      find.text('1 workout needs review. Your local changes are preserved.'),
      findsNothing,
    );
    // Offline only hides the AGGREGATE banner text - the per-card corner
    // dots are diagnostics-driven, not connectivity-gated, so the failing
    // card's indicator remains visible.
    expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);
  });

  testWidgets(
    'there is no Retry, discard, or conflict-resolution control anywhere '
    'on the screen',
    (tester) async {
      await pumpWithIssues(tester);

      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Retry Now'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Discard'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Keep Mine'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Use Server'), findsNothing);
      // The banner itself carries no button of any kind.
      final bannerButtons = find.descendant(
        of: find.byType(SyncIssuesBanner),
        matching: find.byWidgetPredicate(
          (w) => w is TextButton || w is ElevatedButton || w is IconButton,
        ),
      );
      expect(bannerButtons, findsNothing);
    },
  );

  testWidgets(
    'tapping a completed session card navigates with exactly the right '
    "SessionDetailArgs - the tapped row's REAL localId (41), never its "
    'public sessionId (700), never swapped, and never a value borrowed '
    'from a row occupying the opposite identity slot - and the pushed '
    "detail screen's diagnostic is the tapped row's own, not the "
    "colliding row's",
    (tester) async {
      // Displayed row: public Session.id == 700, real localId == 41,
      // retrying failure.
      final displayedSession = Session(
        id: 700,
        userId: 1,
        date: todayDateOnly,
        name: 'Displayed Workout',
        status: 'completed',
      );
      // Colliding row: its public Session.id (41) IS the displayed row's
      // real localId, and its OWN localId (700) IS the displayed row's
      // public sessionId - a full cross-wiring collision in both
      // directions. Gets a DIFFERENT diagnostic (conflict) so any wrong
      // lookup is visibly distinguishable from the correct one.
      final collidingSession = Session(
        id: 41,
        userId: 1,
        date: todayDateOnly,
        name: 'Colliding Workout',
        status: 'completed',
      );
      when(
        sessionRepo.getSession(any),
      ).thenAnswer((_) async => displayedSession);

      await sessionsProvider.loadSessions();
      await tester.pumpWidget(host());
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

      // The pushed screen must show the RETRYING icon (displayed row's own
      // diagnostic, keyed by its real localId 41) - never the CONFLICT icon
      // that belongs to the colliding row (whose localId, 700, is the same
      // integer as displayed's public sessionId). Scoped to descendants of
      // the pushed screen itself - the underlying TrainScreen route (still
      // mounted beneath it) also renders a corner dot for EACH row (one
      // sync_problem_rounded for displayed, one priority_high_rounded for
      // colliding), which is irrelevant to what the DETAIL screen's own
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
    },
  );
}
