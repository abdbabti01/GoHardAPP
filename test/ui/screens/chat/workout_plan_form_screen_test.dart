import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/chat_conversation.dart';
import 'package:go_hard_app/data/repositories/chat_repository.dart';
import 'package:go_hard_app/providers/chat_provider.dart';
import 'package:go_hard_app/routes/route_names.dart';
import 'package:go_hard_app/ui/screens/chat/workout_plan_form_screen.dart';

@GenerateMocks([ChatRepository])
import 'workout_plan_form_screen_test.mocks.dart';

/// Rendered/interaction coverage for WorkoutPlanFormScreen, closing the
/// gap acknowledged in the prior report: the [ChatProvider.generateWorkoutPlan]
/// onError fix was covered at the provider level (chat_provider_test.dart)
/// but never through the real form screen. Reuses that same provider/repo
/// pairing rather than duplicating its full session-ownership matrix -
/// only the screen-level submit/feedback/disposal/layout behavior is new
/// here.
void main() {
  late MockChatRepository repo;
  late UserSessionEpoch epoch;
  late ChatProvider provider;

  ChatConversation conversation(int id) => ChatConversation(
    id: id,
    userId: 1,
    title: 'Workout plan',
    type: 'workout_plan',
    createdAt: DateTime.utc(2024, 1, 1),
  );

  setUp(() {
    repo = MockChatRepository();
    epoch = UserSessionEpoch()..activate(1);
    // Real singleton, defaults to online and is never re-initialized here
    // (matching chat_provider_test.dart's own setup) - no network/platform
    // channel work is triggered by simply reading `.instance`.
    provider = ChatProvider(repo, ConnectivityService.instance, epoch);
  });

  Widget hostApp(Widget child) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatProvider>.value(value: provider),
          // OfflineBanner (rendered by this screen) reads this via
          // context.watch - must be provided even though this test never
          // exercises the offline path itself.
          ChangeNotifierProvider<ConnectivityService>.value(
            value: ConnectivityService.instance,
          ),
        ],
        child: child,
      ),
      routes: {RouteNames.chatConversation: (_) => const Scaffold()},
    );
  }

  Future<void> fillValidForm(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Fitness Goal'),
      'Build muscle',
    );
  }

  // Scroll the Generate button into view before any tap so a hit-test
  // miss (the button can sit below the fold at the default test
  // viewport) can never silently no-op the tap instead of failing loudly.
  Future<void> tapGenerate(WidgetTester tester) async {
    final button = find.widgetWithText(ElevatedButton, 'Generate Workout Plan');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
  }

  testWidgets(
    'a valid submission reaches ChatRepository.generateWorkoutPlan with '
    'the form\'s own values',
    (tester) async {
      when(
        repo.generateWorkoutPlan(
          goal: anyNamed('goal'),
          experienceLevel: anyNamed('experienceLevel'),
          daysPerWeek: anyNamed('daysPerWeek'),
          equipment: anyNamed('equipment'),
          limitations: anyNamed('limitations'),
        ),
      ).thenAnswer((_) async => conversation(1));

      await tester.pumpWidget(hostApp(const WorkoutPlanFormScreen()));
      await fillValidForm(tester);

      await tapGenerate(tester);
      await tester.pumpAndSettle();

      verify(
        repo.generateWorkoutPlan(
          goal: 'Build muscle',
          experienceLevel: 'beginner',
          daysPerWeek: 3,
          equipment: 'full gym',
          limitations: null,
        ),
      ).called(1);
    },
  );

  testWidgets(
    'a genuine current-operation failure shows its own sanitized message',
    (tester) async {
      when(
        repo.generateWorkoutPlan(
          goal: anyNamed('goal'),
          experienceLevel: anyNamed('experienceLevel'),
          daysPerWeek: anyNamed('daysPerWeek'),
          equipment: anyNamed('equipment'),
          limitations: anyNamed('limitations'),
        ),
      ).thenThrow(Exception('network unreachable'));

      await tester.pumpWidget(hostApp(const WorkoutPlanFormScreen()));
      await fillValidForm(tester);

      await tapGenerate(tester);
      await tester.pumpAndSettle();

      // Sanitized: the provider strips the "Exception: " prefix and wraps
      // it in its own message, never surfacing the raw exception verbatim.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('Failed to generate workout plan'),
        findsOneWidget,
      );
      expect(find.textContaining('network unreachable'), findsOneWidget);
      expect(find.textContaining('Exception:'), findsNothing);
    },
  );

  testWidgets('a late failure after session invalidation causes no feedback or '
      'navigation', (tester) async {
    final gate = Completer<ChatConversation?>();
    when(
      repo.generateWorkoutPlan(
        goal: anyNamed('goal'),
        experienceLevel: anyNamed('experienceLevel'),
        daysPerWeek: anyNamed('daysPerWeek'),
        equipment: anyNamed('equipment'),
        limitations: anyNamed('limitations'),
      ),
    ).thenAnswer((_) => gate.future);

    await tester.pumpWidget(hostApp(const WorkoutPlanFormScreen()));
    await fillValidForm(tester);

    await tapGenerate(tester);
    await tester.pump();

    // The loading dialog is up while the request is in flight.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // The session ends (logout / account switch) while still in flight,
    // then the request finally resolves as a failure.
    epoch.invalidate();
    gate.completeError(Exception('too late'));
    await tester.pumpAndSettle();

    // No snackbar, and no navigation to the conversation screen - the
    // form screen is still the one on top (its own loading dialog pop is
    // also skipped, but that is an existing pre-Phase-4 dialog pattern,
    // not the mutation-feedback contract under test here).
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(WorkoutPlanFormScreen), findsOneWidget);
  });

  testWidgets(
    'a late failure after the screen is disposed causes no exception',
    (tester) async {
      final gate = Completer<ChatConversation?>();
      when(
        repo.generateWorkoutPlan(
          goal: anyNamed('goal'),
          experienceLevel: anyNamed('experienceLevel'),
          daysPerWeek: anyNamed('daysPerWeek'),
          equipment: anyNamed('equipment'),
          limitations: anyNamed('limitations'),
        ),
      ).thenAnswer((_) => gate.future);

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MultiProvider(
          // Wraps MaterialApp itself - a route pushed via
          // navigatorKey.currentState!.push is a SIBLING of `home`'s
          // route, not a descendant of it, so a provider scoped only
          // inside `home` would be invisible to the pushed screen.
          providers: [
            ChangeNotifierProvider<ChatProvider>.value(value: provider),
            ChangeNotifierProvider<ConnectivityService>.value(
              value: ConnectivityService.instance,
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: SizedBox()),
            routes: {RouteNames.chatConversation: (_) => const Scaffold()},
          ),
        ),
      );

      navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (_) => const WorkoutPlanFormScreen()),
      );
      await tester.pumpAndSettle();

      await fillValidForm(tester);
      await tapGenerate(tester);
      await tester.pump();

      // Pop the form screen itself (and its loading dialog) while the
      // request is still pending, then resolve it as a failure.
      navigatorKey.currentState!.popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutPlanFormScreen), findsNothing);

      gate.completeError(Exception('resolves after disposal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'at narrow width and 2x text scale, with a simulated keyboard inset, '
    'every field and the primary action remain reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            );
          },
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ChatProvider>.value(value: provider),
              ChangeNotifierProvider<ConnectivityService>.value(
                value: ConnectivityService.instance,
              ),
            ],
            child: const WorkoutPlanFormScreen(),
          ),
          routes: {RouteNames.chatConversation: (_) => const Scaffold()},
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Simulate a keyboard covering roughly the bottom half of the
      // narrow viewport, as happens once a text field gains focus.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'The form must not overflow once the Scaffold resizes for '
            'the simulated keyboard inset.',
      );

      // "Experience Level" and "Available Equipment" are
      // DropdownButtonFormFields, not TextFormFields - find.text matches
      // either kind of field's InputDecoration label without caring which.
      for (final label in [
        'Fitness Goal',
        'Experience Level',
        'Available Equipment',
        'Injuries or Limitations (Optional)',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label unreachable');
        expect(find.text(label), findsOneWidget);
      }

      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Generate Workout Plan'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithText(ElevatedButton, 'Generate Workout Plan'),
        findsOneWidget,
      );

      // Reachable also means tappable: this must not require an
      // additional confirm/tap-elsewhere-first step.
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Generate Workout Plan'),
        warnIfMissed: true,
      );
      await tester.pump();
    },
  );
}
