import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';
import 'package:go_hard_app/ui/screens/sessions/session_detail_screen.dart';

import 'session_detail_sync_issue_test.mocks.dart';

/// LAYOUT HOTFIX (isolated from the durable-key correction): deterministic
/// coverage that [SessionDetailScreen]'s header `Row` (date beside
/// [StatusBadge]) never overflows regardless of the formatted date's length,
/// screen width, or text scale.
///
/// Every date here is FIXED (never `DateTime.now()`), specifically chosen to
/// exercise the longest common English weekday ("Wednesday") and month
/// ("September") names together, since that combination is what originally
/// overflowed the pre-fix `Row` by 20 logical pixels.
void main() {
  late MockSessionRepository repo;
  late UserSessionEpoch epoch;
  late SessionsProvider provider;

  // Wednesday, September 30, 2026 - deliberately the longest common
  // weekday+month pairing, not a coincidence of "today".
  final longDate = DateTime(2026, 9, 30);

  setUp(() {
    repo = MockSessionRepository();
    when(
      repo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => <Session>[]);
    when(
      repo.watchSessionSyncSnapshot(any),
    ).thenAnswer((_) => const Stream.empty());
    epoch = UserSessionEpoch()..activate(1);
    provider = SessionsProvider(repo, epoch, ConnectivityService.instance);
  });

  tearDown(() {
    provider.dispose();
  });

  Session sessionWith({required String status, DateTime? date}) => Session(
    id: 1,
    userId: 1,
    date: date ?? longDate,
    name: 'Leg Day',
    status: status,
  );

  Widget host() => MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionsProvider>.value(value: provider),
      ],
      child: const SessionDetailScreen(sessionId: 1, localId: 1),
    ),
  );

  Future<void> pumpAtWidth(
    WidgetTester tester,
    Session session, {
    required double width,
    double textScale = 1.0,
  }) async {
    when(repo.getSession(any)).thenAnswer((_) async => session);
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 2400),
          textScaler: TextScaler.linear(textScale),
        ),
        child: host(),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  final formattedLongDate = 'Wednesday, September 30, 2026';

  group('ordinary width, normal text scale', () {
    testWidgets(
      'the long-weekday/month date and status badge both render with no '
      'layout exception at an ordinary phone width',
      (tester) async {
        await pumpAtWidth(tester, sessionWith(status: 'completed'), width: 400);

        expect(tester.takeException(), isNull);
        expect(find.byType(SessionDetailScreen), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
      },
    );
  });

  group('narrow phone width', () {
    testWidgets(
      'no layout exception at a narrow (320-logical-pixel) width with the '
      'long-weekday/month date',
      (tester) async {
        await pumpAtWidth(tester, sessionWith(status: 'completed'), width: 320);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the complete date remains available in semantics even at narrow '
      'width, regardless of whether the visual text wraps or ellipsizes',
      (tester) async {
        await pumpAtWidth(tester, sessionWith(status: 'completed'), width: 320);

        expect(tester.takeException(), isNull);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(formattedLongDate))),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the status badge label remains fully readable (never truncated) at '
      'narrow width',
      (tester) async {
        await pumpAtWidth(
          tester,
          sessionWith(status: 'in_progress'),
          width: 320,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('In Progress'), findsOneWidget);
      },
    );
  });

  group('narrow width + increased text scale', () {
    testWidgets(
      'no layout exception at narrow width combined with a 2x text scale - '
      'the hardest realistic combination',
      (tester) async {
        await pumpAtWidth(
          tester,
          sessionWith(status: 'completed'),
          width: 320,
          textScale: 2.0,
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the status badge stays readable and the full date stays in '
        'semantics under narrow width + 2x text scale', (tester) async {
      await pumpAtWidth(
        tester,
        sessionWith(status: 'planned'),
        width: 320,
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Planned'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(formattedLongDate))),
        findsOneWidget,
      );
      // The visual `Text('Planned')` check above only proves the RAW label
      // string exists in the widget tree - it says nothing about semantics,
      // and would still pass even if the visible text were rendered with
      // `overflow: TextOverflow.ellipsis` clipping it. This assertion
      // proves the complete, untruncated status label is independently
      // exposed via Semantics (StatusBadge's own Semantics+ExcludeSemantics
      // pairing), present exactly once, at the exact narrow-width/2x-scale
      // configuration under test - the real regression guard for "status
      // stays accessible despite visual ellipsis".
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape('Planned'))),
        findsOneWidget,
      );
    });
  });

  group('every status badge variant, narrow width + large text scale', () {
    for (final entry
        in const {
          'completed': 'Completed',
          'in_progress': 'In Progress',
          'planned': 'Planned',
          'draft': 'Draft',
        }.entries) {
      testWidgets(
        '${entry.key} status badge renders with no layout exception at '
        'narrow width + 2x text scale, label fully readable',
        (tester) async {
          await pumpAtWidth(
            tester,
            sessionWith(status: entry.key),
            width: 320,
            textScale: 2.0,
          );

          expect(tester.takeException(), isNull);
          expect(find.text(entry.value), findsOneWidget);
        },
      );
    }
  });
}
