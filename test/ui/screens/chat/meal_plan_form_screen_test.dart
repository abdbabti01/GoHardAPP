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
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/providers/chat_provider.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';
import 'package:go_hard_app/routes/route_names.dart';
import 'package:go_hard_app/ui/screens/chat/meal_plan_form_screen.dart';

@GenerateMocks([ChatRepository, NutritionRepository])
import 'meal_plan_form_screen_test.mocks.dart';

/// Rendered/interaction coverage for MealPlanFormScreen, closing the gap
/// acknowledged in the prior report: the [ChatProvider.generateMealPlan]
/// onError fix was covered at the provider level (chat_provider_test.dart)
/// but never through the real form screen. Reuses that same provider/repo
/// pairing rather than duplicating its full session-ownership matrix -
/// only the screen-level submit/feedback/disposal/layout behavior is new
/// here. NutritionProvider is wired in only because the screen reads its
/// `activeGoal` to prefill macro fields; no nutrition network call is
/// ever made (activeGoal stays null, so the prefill is a no-op).
void main() {
  late MockChatRepository chatRepo;
  late MockNutritionRepository nutritionRepo;
  late UserSessionEpoch epoch;
  late ChatProvider chatProvider;
  late NutritionProvider nutritionProvider;

  ChatConversation conversation(int id) => ChatConversation(
    id: id,
    userId: 1,
    title: 'Meal plan',
    type: 'meal_plan',
    createdAt: DateTime.utc(2024, 1, 1),
  );

  setUp(() {
    chatRepo = MockChatRepository();
    nutritionRepo = MockNutritionRepository();
    epoch = UserSessionEpoch()..activate(1);
    chatProvider = ChatProvider(chatRepo, ConnectivityService.instance, epoch);
    nutritionProvider = NutritionProvider(nutritionRepo, epoch);
  });

  Widget hostApp(Widget child) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
          ChangeNotifierProvider<NutritionProvider>.value(
            value: nutritionProvider,
          ),
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
      find.widgetWithText(TextFormField, 'Dietary Goal'),
      'Fat loss',
    );
  }

  // The Generate button sits below the fold at the default 800x600 test
  // viewport once every field is present - scroll it into view before
  // any tap so a hit-test miss can never silently no-op the tap instead
  // of failing loudly.
  Future<void> tapGenerate(WidgetTester tester) async {
    final button = find.widgetWithText(ElevatedButton, 'Generate Meal Plan');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
  }

  testWidgets(
    'a valid submission reaches ChatRepository.generateMealPlan with the '
    'form\'s own values',
    (tester) async {
      when(
        chatRepo.generateMealPlan(
          dietaryGoal: anyNamed('dietaryGoal'),
          targetCalories: anyNamed('targetCalories'),
          macros: anyNamed('macros'),
          restrictions: anyNamed('restrictions'),
          preferences: anyNamed('preferences'),
        ),
      ).thenAnswer((_) async => conversation(1));

      await tester.pumpWidget(hostApp(const MealPlanFormScreen()));
      await tester.pumpAndSettle();
      await fillValidForm(tester);

      await tapGenerate(tester);
      await tester.pumpAndSettle();

      verify(
        chatRepo.generateMealPlan(
          dietaryGoal: 'Fat loss',
          targetCalories: null,
          macros: null,
          restrictions: null,
          preferences: null,
        ),
      ).called(1);
    },
  );

  testWidgets(
    'a genuine current-operation failure shows its own sanitized message',
    (tester) async {
      when(
        chatRepo.generateMealPlan(
          dietaryGoal: anyNamed('dietaryGoal'),
          targetCalories: anyNamed('targetCalories'),
          macros: anyNamed('macros'),
          restrictions: anyNamed('restrictions'),
          preferences: anyNamed('preferences'),
        ),
      ).thenThrow(Exception('network unreachable'));

      await tester.pumpWidget(hostApp(const MealPlanFormScreen()));
      await tester.pumpAndSettle();
      await fillValidForm(tester);

      await tapGenerate(tester);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('Failed to generate meal plan'),
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
      chatRepo.generateMealPlan(
        dietaryGoal: anyNamed('dietaryGoal'),
        targetCalories: anyNamed('targetCalories'),
        macros: anyNamed('macros'),
        restrictions: anyNamed('restrictions'),
        preferences: anyNamed('preferences'),
      ),
    ).thenAnswer((_) => gate.future);

    await tester.pumpWidget(hostApp(const MealPlanFormScreen()));
    await tester.pumpAndSettle();
    await fillValidForm(tester);

    await tapGenerate(tester);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    epoch.invalidate();
    gate.completeError(Exception('too late'));
    await tester.pumpAndSettle();

    // No snackbar, and no navigation to the conversation screen - the
    // form screen is still the one on top.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(MealPlanFormScreen), findsOneWidget);
  });

  testWidgets(
    'a late failure after the screen is disposed causes no exception',
    (tester) async {
      final gate = Completer<ChatConversation?>();
      when(
        chatRepo.generateMealPlan(
          dietaryGoal: anyNamed('dietaryGoal'),
          targetCalories: anyNamed('targetCalories'),
          macros: anyNamed('macros'),
          restrictions: anyNamed('restrictions'),
          preferences: anyNamed('preferences'),
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
            ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
            ChangeNotifierProvider<NutritionProvider>.value(
              value: nutritionProvider,
            ),
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
        MaterialPageRoute(builder: (_) => const MealPlanFormScreen()),
      );
      await tester.pumpAndSettle();

      await fillValidForm(tester);
      await tapGenerate(tester);
      await tester.pump();

      navigatorKey.currentState!.popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      expect(find.byType(MealPlanFormScreen), findsNothing);

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
              ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
              ChangeNotifierProvider<NutritionProvider>.value(
                value: nutritionProvider,
              ),
              ChangeNotifierProvider<ConnectivityService>.value(
                value: ConnectivityService.instance,
              ),
            ],
            child: const MealPlanFormScreen(),
          ),
          routes: {RouteNames.chatConversation: (_) => const Scaffold()},
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'The form must not overflow once the Scaffold resizes for '
            'the simulated keyboard inset.',
      );

      for (final label in [
        'Dietary Goal',
        'Target Calories',
        'Protein',
        'Carbs',
        'Fat',
        'Dietary Restrictions (Optional)',
        'Food Preferences (Optional)',
      ]) {
        await tester.ensureVisible(find.widgetWithText(TextFormField, label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label unreachable');
        expect(find.widgetWithText(TextFormField, label), findsOneWidget);
      }

      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Generate Meal Plan'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithText(ElevatedButton, 'Generate Meal Plan'),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Generate Meal Plan'),
        warnIfMissed: true,
      );
      await tester.pump();
    },
  );
}
