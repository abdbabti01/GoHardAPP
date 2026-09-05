import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';
import 'package:go_hard_app/ui/widgets/sessions/session_card.dart';

/// [SessionCard]'s corner sync-issue indicator must be decorative only
/// (never focusable/tappable on its own), never rely on color alone
/// (distinct icon per state), never render raw `syncError` text, and the
/// friendly summary must be appended to the card's existing title semantics
/// rather than exposed as a second node.
void main() {
  Session session({String? name}) => Session(
    id: 1,
    userId: 1,
    date: DateTime(2026, 1, 1),
    name: name ?? 'Leg Day',
    status: 'draft',
  );

  Widget host(SessionSyncDiagnostics? diagnostics) => MaterialApp(
    home: Scaffold(
      body: SessionCard(session: session(), diagnostics: diagnostics),
    ),
  );

  testWidgets('no diagnostics: the card\'s merged semantics label carries '
      'no sync-issue text', (tester) async {
    await tester.pumpWidget(host(null));

    final label = tester.getSemantics(find.text('Leg Day')).label;
    expect(label, contains('Leg Day'));
    expect(label, isNot(contains('synced')));
    expect(label, isNot(contains('review')));
  });

  testWidgets('retrying failure: the friendly message is appended right '
      'after the title into the SAME merged node, never raw syncError '
      'text, and never as a second separately-findable label', (tester) async {
    await tester.pumpWidget(
      host(
        const SessionSyncDiagnostics(state: SessionSyncState.retryingFailure),
      ),
    );

    // find.text('Leg Day') still locates the RenderObject by its literal
    // text content; the semantics reached from it is the card's single
    // auto-merged node (PremiumTapAnimation's GestureDetector already
    // merges all descendant text) - proving the friendly text was appended
    // into that SAME node, not exposed as an independent one.
    final label = tester.getSemantics(find.text('Leg Day')).label;
    expect(
      label,
      contains(
        "Leg Day. This workout hasn't synced yet. Your changes are saved "
        'and the app will keep trying.',
      ),
    );
    // Exactly one merged node carries this text - it is not duplicated
    // into a second, independently-findable semantics label.
    expect(find.bySemanticsLabel(RegExp("hasn't synced yet")), findsOneWidget);
  });

  testWidgets('conflict renders a distinct icon from retrying failure - '
      'never color alone', (tester) async {
    await tester.pumpWidget(
      host(const SessionSyncDiagnostics(state: SessionSyncState.conflict)),
    );
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sync_problem_rounded), findsNothing);

    await tester.pumpWidget(
      host(
        const SessionSyncDiagnostics(state: SessionSyncState.retryingFailure),
      ),
    );
    expect(find.byIcon(Icons.sync_problem_rounded), findsOneWidget);
    expect(find.byIcon(Icons.priority_high_rounded), findsNothing);
  });

  testWidgets('the corner indicator adds no gesture region of its own - the '
      'GestureDetector count with a diagnostic present equals the count '
      'without one (only the card\'s own existing tap/dismiss handling)', (
    tester,
  ) async {
    await tester.pumpWidget(host(null));
    final withoutBadge = find.byType(GestureDetector).evaluate().length;

    await tester.pumpWidget(
      host(
        const SessionSyncDiagnostics(state: SessionSyncState.retryingFailure),
      ),
    );
    final withBadge = find.byType(GestureDetector).evaluate().length;

    expect(withBadge, withoutBadge);
  });

  testWidgets('the corner indicator contributes nothing to the merged '
      'semantics label - its shortLabel text never appears anywhere in it '
      '(it is ExcludeSemantics; the merged label is driven ONLY by the '
      'title Semantics wrapper)', (tester) async {
    await tester.pumpWidget(
      host(
        const SessionSyncDiagnostics(state: SessionSyncState.retryingFailure),
      ),
    );

    // The whole card merges into one semantics node (PremiumTapAnimation's
    // GestureDetector). If the dot's ExcludeSemantics were ever removed, its
    // shortLabel ("Not synced yet") would additively appear in this merged
    // label - assert it does not.
    final merged = tester.getSemantics(find.byType(SessionCard)).label;
    expect(
      merged,
      isNot(contains(SessionSyncState.retryingFailure.shortLabel)),
    );
    expect(merged, contains(SessionSyncState.retryingFailure.friendlyMessage));
  });
}
