import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/program.dart';
import 'package:go_hard_app/data/repositories/programs_repository.dart';
import 'package:go_hard_app/providers/programs_provider.dart';
import 'package:go_hard_app/routes/app_router.dart';
import 'package:go_hard_app/routes/route_names.dart';
import 'package:go_hard_app/ui/screens/programs/programs_screen.dart';

@GenerateMocks([ProgramsRepository])
import 'programs_screen_mutation_feedback_test.mocks.dart';

/// Regression coverage for two Phase-4 mutation-feedback bugs on the
/// archive/complete/delete/link/unarchive actions this screen added:
///
/// Bug 1 (fixed by only showing a snackbar when a message exists): using
/// `provider.errorMessage ?? 'generic fallback'` after an operation
/// returned `false` couldn't distinguish a genuine failure from a stale
/// session / cancelled request / superseded mutation - all three
/// intentionally leave `errorMessage` untouched (see
/// test/providers/programs_provider_session_ownership_test.dart) - so a
/// late response after logout/account switch showed a made-up failure
/// snackbar.
///
/// Bug 2 (the one this file's [ProgramsProvider.onError] tests below
/// exist for): fixing Bug 1 by gating on `errorMessage != null` is
/// STILL wrong, because `errorMessage` is a single field SHARED across
/// every mutation the provider is handling. Two things follow: (a) an
/// old, unrelated, already-displayed error can be left sitting in
/// `errorMessage` and get re-shown for a completely different operation
/// that happens to also return `false`, and (b) two overlapping
/// mutations on different targets race to write/read that same field, so
/// one call's snackbar can show another call's message, or a genuine
/// failure can be silently dropped if an unrelated mutation's bookkeeping
/// touched the field first. The fix is [ProgramsProvider.onError]: a
/// synchronous, per-call callback invoked if and only if THAT call's own
/// operation genuinely failed while still owning its session and target -
/// never read from or written to the shared field - so no amount of
/// concurrent, stale, or leftover activity on `errorMessage` can affect
/// what a caller displays.
///
/// The "stale/cancelled/genuine" scenarios below prime the shared
/// `errorMessage` field with an unrelated, already-displayed error first,
/// specifically to prove the new operation's feedback decision does not
/// depend on - and cannot be confused with - that leftover value.
///
/// Targets the "Restore" (unarchive) menu action specifically: unlike
/// archive/complete/delete, it has no confirmation dialog in between, so
/// the test isn't entangled with the separate (pre-existing,
/// out-of-scope) `Navigator.pop(context)`-then-reuse-that-context pattern
/// those dialogs use.
void main() {
  late MockProgramsRepository repo;
  late UserSessionEpoch epoch;
  late ProgramsProvider provider;

  Program archivedProgram(int id) => Program(
    id: id,
    userId: 1,
    title: 'Push Pull Legs',
    totalWeeks: 4,
    currentWeek: 1,
    currentDay: 1,
    startDate: DateTime(2024, 1, 1),
    isActive: false,
    isCompleted: false,
    status: 'archived',
    createdAt: DateTime(2024, 1, 1),
  );

  setUp(() {
    repo = MockProgramsRepository();
    epoch = UserSessionEpoch()..activate(1);
    provider = ProgramsProvider(repo, epoch);
  });

  // ProgramsScreen's week calendar runs a perpetual pulse animation
  // (`_pulseController..repeat(reverse: true)`), so `pumpAndSettle()` never
  // converges here - use bounded pumps instead.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    when(
      repo.getPrograms(isActive: anyNamed('isActive')),
    ).thenAnswer((_) async => [archivedProgram(1)]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ProgramsProvider>.value(
          value: provider,
          child: const Scaffold(body: ProgramsScreen()),
        ),
      ),
    );
    await settle(tester);
  }

  // Regression coverage for a Restore-menu overflow: the popup menu's
  // action items (Row(Icon, SizedBox, Text)) had no Flexible/Expanded
  // around their Text, so the "Restore" item's Row overflowed its own
  // computed menu width by ~1.6px. Fixed in programs_screen.dart by
  // wrapping every action item's Text in a Flexible with ellipsis. No
  // FlutterError.onError tolerance needed here any more - a real
  // RenderFlex overflow now fails this test like any other assertion.
  Future<void> openMenuAndTapRestore(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await settle(tester);
    await tester.tap(find.text('Restore'));
  }

  // Seeds provider.errorMessage with an unrelated, already-displayed
  // failure, then waits out its SnackBar so each scenario test starts from
  // a clean-looking screen but a DIRTY (non-null) shared error field - the
  // exact precondition the bug this file guards against requires.
  Future<void> primeExistingError(WidgetTester tester) async {
    when(repo.unarchiveProgram(1)).thenThrow(Exception('primed failure'));
    await openMenuAndTapRestore(tester);
    await settle(tester);

    expect(provider.errorMessage, contains('primed failure'));
    expect(find.byType(SnackBar), findsOneWidget);

    // Outlive the SnackBar's default display duration so the next
    // assertion of findsNothing/findsOneWidget is unambiguous.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.byType(SnackBar), findsNothing);

    clearInteractions(repo);
  }

  testWidgets(
    'an existing error followed by a stale (logout) operation shows no '
    'snackbar and does not resurface the old message',
    (tester) async {
      await pumpScreen(tester);
      await primeExistingError(tester);

      final gate = Completer<void>();
      when(repo.unarchiveProgram(1)).thenAnswer((_) => gate.future);

      await openMenuAndTapRestore(tester);
      await tester.pump();

      // The session ends (logout / account switch) while this second,
      // unrelated unarchive request is still in flight.
      epoch.invalidate();
      gate.complete();
      await settle(tester);

      // Confirms the tap genuinely reached the menu item and the mutation
      // ran, rather than this test passing merely because the tap silently
      // missed.
      verify(repo.unarchiveProgram(1)).called(1);
      // The shared field still holds the OLD, already-displayed message -
      // proving that a UI which merely checked `errorMessage != null`
      // would incorrectly resurface it here. The onError-based call site
      // never reads this field, so nothing is shown regardless.
      expect(provider.errorMessage, contains('primed failure'));
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'an existing error followed by a cancelled/superseded operation shows '
    'no snackbar for the superseded call',
    (tester) async {
      await pumpScreen(tester);
      await primeExistingError(tester);

      final gate1 = Completer<void>();
      when(repo.unarchiveProgram(1)).thenAnswer((_) => gate1.future);

      // Call 1, via the UI - left in flight.
      await openMenuAndTapRestore(tester);
      // Let the menu's own closing animation finish (call 1 itself stays
      // pending on gate1, which only a real Completer.complete() resolves,
      // so this settles the UI, not the mutation).
      await settle(tester);

      // Call 2, ALSO via the UI (menu reopened and tapped again before
      // call 1 resolves), supersedes call 1 by bumping the same target's
      // mutation generation.
      final gate2 = Completer<void>();
      when(repo.unarchiveProgram(1)).thenAnswer((_) => gate2.future);
      await openMenuAndTapRestore(tester);
      await settle(tester);

      // Call 1 resolves first. It must own neither the session nor its
      // now-stale generation, so it must produce no feedback at all.
      gate1.complete();
      await tester.pump();

      // Call 2 (the current, owning call) now succeeds.
      gate2.complete();
      await settle(tester);

      verify(repo.unarchiveProgram(1)).called(2);
      // Exactly one snackbar - call 2's success - never call 1's silence
      // nor the old primed error resurfacing.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Plan restored'), findsOneWidget);
      expect(find.textContaining('primed failure'), findsNothing);
    },
  );

  testWidgets(
    'an existing error followed by a genuine current-operation failure '
    'still shows that new failure, not the old one',
    (tester) async {
      await pumpScreen(tester);
      await primeExistingError(tester);

      when(repo.unarchiveProgram(1)).thenThrow(Exception('fresh failure'));

      await openMenuAndTapRestore(tester);
      await settle(tester);

      expect(provider.errorMessage, contains('fresh failure'));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('fresh failure'), findsOneWidget);
      expect(find.textContaining('primed failure'), findsNothing);
    },
  );

  // Not a widget test: exercises ProgramsProvider.onError directly on two
  // DIFFERENT targets (program ids 1 and 2) racing concurrently, using the
  // exact callback the UI relies on instead of re-reading the shared
  // `errorMessage` field - which is precisely the point being proven,
  // since that shared field is demonstrably unreliable under overlap (see
  // the final assertion below). No widget/backend is needed to prove this;
  // it is a direct, deterministic exercise of the provider contract.
  test('overlapping operations on different targets: one call'
      "'s own failure surfaces via its own onError and never contaminates, "
      "or is contaminated by, the other call's outcome", () async {
    final gateA = Completer<void>();
    final gateB = Completer<void>();
    when(repo.unarchiveProgram(1)).thenAnswer((_) => gateA.future);
    when(repo.unarchiveProgram(2)).thenAnswer((_) => gateB.future);

    String? errorA;
    String? errorB;

    // Both calls start - each bumps the shared `_errorGen` counter, so
    // by the time both are in flight neither call's captured `errorGen`
    // matches the current one any more.
    final futureA = provider.unarchiveProgram(1, onError: (m) => errorA = m);
    final futureB = provider.unarchiveProgram(2, onError: (m) => errorB = m);

    // A fails genuinely. Despite the errorGen mismatch caused by B's
    // concurrent start, A still owns its own session and target, so its
    // own failure must still be reported through its own callback.
    gateA.completeError(Exception('A failed'));
    expect(await futureA, isFalse);
    expect(errorA, contains('A failed'));

    // B succeeds, and must never have received A's message nor produced
    // one of its own.
    gateB.complete();
    expect(await futureB, isTrue);
    expect(errorB, isNull);

    // The shared field is demonstrably NOT a reliable channel here: the
    // errorGen mismatch meant A's genuine failure was never written to
    // it, so a caller that read `provider.errorMessage` instead of using
    // `onError` would have missed A's failure entirely (or, in a
    // different interleaving, displayed a stale message belonging to
    // neither call). onError alone is authoritative.
    expect(provider.errorMessage, isNot(contains('A failed')));
  });

  testWidgets('empty state offers "Create a plan" and opens the plan form', (
    tester,
  ) async {
    when(
      repo.getPrograms(isActive: anyNamed('isActive')),
    ).thenAnswer((_) async => []);
    final pushed = <String?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ProgramsProvider>.value(
          value: provider,
          child: const Scaffold(body: ProgramsScreen()),
        ),
        onGenerateRoute: (settings) {
          pushed.add(settings.name);
          return MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('stub')),
            settings: settings,
          );
        },
      ),
    );
    await settle(tester);

    expect(find.text('No plan yet'), findsOneWidget);
    await tester.tap(find.text('Create a plan'));
    await settle(tester);
    expect(pushed, [RouteNames.workoutPlanForm]);
  });

  testWidgets('the My Plan route is a titled page with a back button', (
    tester,
  ) async {
    when(
      repo.getPrograms(isActive: anyNamed('isActive')),
    ).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ChangeNotifierProvider<ProgramsProvider>.value(
        value: provider,
        child: MaterialApp(
          onGenerateRoute: AppRouter.generateRoute,
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => Navigator.pushNamed(context, RouteNames.programs),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);

    expect(find.text('My Plan'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('No plan yet'), findsOneWidget);
  });
}
