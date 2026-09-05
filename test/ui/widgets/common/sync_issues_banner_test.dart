import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'package:go_hard_app/ui/widgets/common/sync_issues_banner.dart';

@GenerateMocks([SessionRepository])
import 'sync_issues_banner_test.mocks.dart';

/// [SyncIssuesBanner] is passive: self-hides when there is nothing to show,
/// renders retrying/conflict as visually AND semantically distinct rows, is
/// `Semantics(liveRegion: true)`, and - critically - dispatches nothing: it
/// has no button, no dismiss control, and never touches `SessionRepository`
/// or `SyncService`.
void main() {
  late MockSessionRepository repo;
  late UserSessionEpoch epoch;
  late StreamController<SessionSyncSnapshot> watchController;
  late SessionsProvider provider;

  Session session(int id) =>
      Session(id: id, userId: 1, date: DateTime(2026, 1, 1));

  setUp(() {
    repo = MockSessionRepository();
    watchController = StreamController<SessionSyncSnapshot>(sync: true);
    when(
      repo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => <Session>[]);
    when(
      repo.watchSessionSyncSnapshot(any),
    ).thenAnswer((_) => watchController.stream);

    epoch = UserSessionEpoch()..activate(1);
    provider = SessionsProvider(repo, epoch, ConnectivityService.instance);
  });

  tearDown(() async {
    provider.dispose();
    if (!watchController.isClosed) await watchController.close();
  });

  Widget host() => MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectivityService>.value(
          value: ConnectivityService.instance,
        ),
        ChangeNotifierProvider<SessionsProvider>.value(value: provider),
      ],
      child: const Scaffold(body: SyncIssuesBanner()),
    ),
  );

  testWidgets('hidden when there are no retrying failures or conflicts', (
    tester,
  ) async {
    await provider.loadSessions();
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.byType(SyncIssuesBanner), findsOneWidget);
    expect(
      find.text(
        "1 workout hasn't synced yet. Your changes are saved and "
        'automatic retry will continue.',
      ),
      findsNothing,
    );
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('shows the retrying-failure row with the required copy - '
      'never implies retry-count-3 is terminal', (tester) async {
    await provider.loadSessions();
    await tester.pumpWidget(host());

    watchController.add(
      SessionSyncSnapshot(
        visibleEntries: [
          SessionListEntry(
            session: session(1),
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

    expect(
      find.text(
        "1 workout hasn't synced yet. Your changes are saved and "
        'automatic retry will continue.',
      ),
      findsOneWidget,
    );
    // No button, no dismiss control of any kind.
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('conflict renders as its own distinct row, never merged into '
      'or worded as "retrying"', (tester) async {
    await provider.loadSessions();
    await tester.pumpWidget(host());

    watchController.add(
      SessionSyncSnapshot(
        visibleEntries: [
          SessionListEntry(
            session: session(1),
            localId: 1,
            diagnostics: const SessionSyncDiagnostics(
              state: SessionSyncState.conflict,
            ),
          ),
          SessionListEntry(
            session: session(2),
            localId: 2,
            diagnostics: const SessionSyncDiagnostics(
              state: SessionSyncState.retryingFailure,
            ),
          ),
        ],
        retryingFailureCount: 1,
        conflictCount: 1,
      ),
    );
    await tester.pump();

    expect(
      find.text('1 workout needs review. Your local changes are preserved.'),
      findsOneWidget,
    );
    expect(
      find.text(
        "1 workout hasn't synced yet. Your changes are saved and "
        'automatic retry will continue.',
      ),
      findsOneWidget,
    );
    // Never describes the conflict as retrying.
    expect(find.textContaining('review'), findsOneWidget);
  });

  testWidgets('the banner is a live region with a single understandable '
      'label per row', (tester) async {
    await provider.loadSessions();
    await tester.pumpWidget(host());

    watchController.add(
      SessionSyncSnapshot(
        visibleEntries: [
          SessionListEntry(
            session: session(1),
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

    final semantics = tester.getSemantics(
      find.bySemanticsLabel(
        "1 workout hasn't synced yet. Your changes are saved and automatic "
        'retry will continue.',
      ),
    );
    expect(semantics.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
  });
}
