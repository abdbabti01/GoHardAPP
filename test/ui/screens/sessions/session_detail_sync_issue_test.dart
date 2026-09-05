import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';
import 'package:go_hard_app/ui/screens/sessions/session_detail_screen.dart';

@GenerateMocks([SessionRepository])
import 'session_detail_sync_issue_test.mocks.dart';

/// [SessionDetailScreen]'s conditional sync-issue AppBar action is passive:
/// it opens a read-only dialog whose only control closes it, with no
/// retry/discard/keep-local/use-server/delete/reset action anywhere.
/// Dismissing it must call none of `SessionRepository`'s mutating methods.
void main() {
  late MockSessionRepository repo;
  late UserSessionEpoch epoch;
  late StreamController<SessionSyncSnapshot> watchController;
  late SessionsProvider provider;

  final aSession = Session(
    id: 1,
    userId: 1,
    date: DateTime(2026, 1, 1),
    name: 'Leg Day',
    status: 'draft',
  );

  setUp(() {
    repo = MockSessionRepository();
    watchController = StreamController<SessionSyncSnapshot>(sync: true);
    when(
      repo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => <Session>[]);
    when(
      repo.watchSessionSyncSnapshot(any),
    ).thenAnswer((_) => watchController.stream);
    when(repo.getSession(any)).thenAnswer((_) async => aSession);

    epoch = UserSessionEpoch()..activate(1);
    provider = SessionsProvider(repo, epoch, ConnectivityService.instance);
  });

  tearDown(() async {
    provider.dispose();
    if (!watchController.isClosed) await watchController.close();
  });

  Widget host({int? localId = 1}) => MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionsProvider>.value(value: provider),
      ],
      child: SessionDetailScreen(sessionId: 1, localId: localId),
    ),
  );

  testWidgets(
    '15. the retrying-failure icon opens a passive dialog; dismissing it '
    'calls no repository mutation and closes the session detail row '
    'unchanged',
    (tester) async {
      await provider.loadSessions();
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();

      watchController.add(
        SessionSyncSnapshot(
          visibleEntries: [
            SessionListEntry(
              session: aSession,
              localId: 1,
              diagnostics: const SessionSyncDiagnostics(
                state: SessionSyncState.retryingFailure,
              ),
            ),
          ],
          retryingFailureCount: 1,
          conflictCount: 0,
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.sync_problem_rounded));
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          "This workout hasn't synced yet. Your changes are saved and "
          'the app will keep trying.',
        ),
        findsOneWidget,
      );
      // Only a Close control - no retry/discard/keep-local/use-server.
      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Discard'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          "This workout hasn't synced yet. Your changes are saved and "
          'the app will keep trying.',
        ),
        findsNothing,
      );

      // No mutation of any kind was dispatched by opening/closing the dialog.
      verifyNever(repo.deleteSession(any));
      verifyNever(repo.archiveSession(any));
      verifyNever(repo.updateSessionStatus(any, any));
      verifyNever(repo.updateWorkoutDate(any, any));
      verifyNever(repo.createSession(any));
    },
  );

  testWidgets('a conflict opens a dialog stating local changes are preserved '
      'and needs review, also with only a Close control', (tester) async {
    await provider.loadSessions();
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    watchController.add(
      SessionSyncSnapshot(
        visibleEntries: [
          SessionListEntry(
            session: aSession,
            localId: 1,
            diagnostics: const SessionSyncDiagnostics(
              state: SessionSyncState.conflict,
            ),
          ),
        ],
        retryingFailureCount: 0,
        conflictCount: 1,
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.warning_rounded));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'This workout changed elsewhere. Your local changes are preserved '
        'and need review.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
  });

  testWidgets('no icon at all when the session is healthy', (tester) async {
    await provider.loadSessions();
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    watchController.add(
      SessionSyncSnapshot(
        visibleEntries: [SessionListEntry(session: aSession, localId: 1)],
        retryingFailureCount: 0,
        conflictCount: 0,
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.sync_problem_rounded), findsNothing);
    expect(find.byIcon(Icons.warning_rounded), findsNothing);
  });

  testWidgets(
    '6. an entry point with no local ID (SessionDetailScreen.localId == '
    'null) renders no sync-issue affordance at all, even though a failing '
    'row with the SAME public sessionId exists - it never guesses via the '
    'ambiguous id',
    (tester) async {
      await provider.loadSessions();
      await tester.pumpWidget(host(localId: null));
      await tester.pump();
      await tester.pump();

      // A row that WOULD show the icon if looked up by the ambiguous
      // sessionId (both are 1) - but this screen was opened with no
      // localId, so it must not guess.
      watchController.add(
        SessionSyncSnapshot(
          visibleEntries: [
            SessionListEntry(
              session: aSession,
              localId: 1,
              diagnostics: const SessionSyncDiagnostics(
                state: SessionSyncState.retryingFailure,
              ),
            ),
          ],
          retryingFailureCount: 1,
          conflictCount: 0,
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.sync_problem_rounded), findsNothing);
      expect(find.byIcon(Icons.warning_rounded), findsNothing);
    },
  );

  testWidgets(
    'the AppBar action looks up diagnostics by the screen\'s localId, '
    'never by its (numerically different) sessionId - a mutant that fed '
    'sessionId into the lookup instead would find nothing here and wrongly '
    'render no icon',
    (tester) async {
      // sessionId (the public/server id used to fetch the row's content) is
      // 1; the row's real, unambiguous localId is a DIFFERENT value, 77 -
      // simulating a synced row whose serverId and localId diverge. The
      // failure is registered ONLY under localId 77.
      await provider.loadSessions();
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<SessionsProvider>.value(value: provider),
            ],
            child: const SessionDetailScreen(sessionId: 1, localId: 77),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      watchController.add(
        SessionSyncSnapshot(
          visibleEntries: [
            SessionListEntry(
              session: aSession, // aSession.id == 1
              localId: 77,
              diagnostics: const SessionSyncDiagnostics(
                state: SessionSyncState.retryingFailure,
              ),
            ),
          ],
          retryingFailureCount: 1,
          conflictCount: 0,
        ),
      );
      await tester.pump();

      // Looked up by localId (77), which DOES have a registered failure -
      // the icon must render. A sessionId-based (1) lookup would find
      // nothing registered under 1 and wrongly show no icon.
      expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);
    },
  );
}
