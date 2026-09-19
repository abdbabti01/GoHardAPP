import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/chat_conversation.dart';
import 'package:go_hard_app/data/models/chat_message.dart';
import 'package:go_hard_app/data/repositories/chat_repository.dart';
import 'package:go_hard_app/providers/chat_provider.dart';
import 'package:go_hard_app/ui/screens/chat/chat_conversation_screen.dart';

@GenerateMocks([ChatRepository])
import 'chat_conversation_screen_test.mocks.dart';

/// Regression coverage for a real-device finding: sending a chat message
/// that fails (e.g. the AI backend returning no response) left the screen
/// showing the plain "No messages yet" empty state with no indication
/// anything went wrong - the provider correctly rolled back the optimistic
/// message and set `errorMessage`, but `_sendMessage()` in
/// ChatConversationScreen only used the `success` flag to decide whether
/// to scroll, so the error was never surfaced to the user.
///
/// Follow-up audit: the first fix read the SHARED `provider.errorMessage`
/// after the await, which is written by every other ChatProvider operation
/// on this same screen (loadConversation, deleteConversation,
/// createProgramFromPlan, applyMealPlanToToday, regenerate, ...) and can
/// race with an in-flight send. `_sendMessage()` and `ChatProvider.sendMessage`
/// were changed to the same operation-local `onError` callback contract
/// `generateWorkoutPlan`/`generateMealPlan` already use elsewhere in this
/// provider, so the screen never reads shared state to decide what to show.
/// The tests below are the load-bearing proof of that ownership contract.
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

  ChatMessage aiMessage(int conversationId) => ChatMessage(
    id: 99,
    conversationId: conversationId,
    role: 'assistant',
    content: 'Here is your plan',
    createdAt: DateTime.utc(2024, 1, 1),
  );

  setUp(() {
    repo = MockChatRepository();
    epoch = UserSessionEpoch()..activate(1);
    provider = ChatProvider(repo, ConnectivityService.instance, epoch);
  });

  Widget hostApp(Widget child) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatProvider>.value(value: provider),
          ChangeNotifierProvider<ConnectivityService>.value(
            value: ConnectivityService.instance,
          ),
        ],
        child: child,
      ),
    );
  }

  Future<void> openConversation(WidgetTester tester) async {
    when(repo.getConversation(1)).thenAnswer((_) async => conversation(1));
    await tester.pumpWidget(
      hostApp(const ChatConversationScreen(conversationId: 1)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a genuine send failure (no AI response) shows that call\'s own '
      'sanitized message instead of silently reverting to the '
      'empty-conversation state', (tester) async {
    await openConversation(tester);
    when(
      repo.sendMessage(
        conversationId: anyNamed('conversationId'),
        message: anyNamed('message'),
      ),
    ).thenAnswer((_) async => null);

    await tester.enterText(find.byType(TextField), 'Build me a plan');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Failed to get AI response'), findsOneWidget);
  });

  testWidgets('a pre-existing shared error from a DIFFERENT operation is never '
      'displayed for a later send, even when that send itself goes stale', (
    tester,
  ) async {
    await openConversation(tester);

    // Poison the shared provider.errorMessage via an unrelated operation
    // BEFORE the send under test ever starts.
    when(
      repo.deleteConversation(999),
    ).thenThrow(Exception('unrelated delete failure'));
    await provider.deleteConversation(999);
    expect(provider.errorMessage, contains('unrelated delete failure'));

    final gate = Completer<ChatMessage?>();
    when(
      repo.sendMessage(
        conversationId: anyNamed('conversationId'),
        message: anyNamed('message'),
      ),
    ).thenAnswer((_) => gate.future);

    await tester.enterText(find.byType(TextField), 'Build me a plan');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(); // send is now in flight

    // The session ends while this send is still in flight - the eventual
    // resolution below must be treated as stale. Deliberately pump()
    // rather than pumpAndSettle(): once the session is invalidated,
    // ChatProvider's own `finally` block (by design - see its doc comment)
    // never clears `isSending` for a no-longer-current token, so the
    // screen's indeterminate "AI is thinking..." spinner keeps animating
    // forever and pumpAndSettle() would never quiesce.
    epoch.invalidate();
    gate.complete(null);
    await tester.pump();
    // The optimistic user message added at the start of sendMessage()
    // triggers the message list's own post-frame auto-scroll, which
    // schedules a 100ms Future.delayed - advance past it explicitly so no
    // timer is left pending at teardown (pumpAndSettle can't be used here;
    // see the reason above).
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.text('unrelated delete failure'),
      findsNothing,
      reason:
          'the stale send must never surface a different operation\'s '
          'leftover shared error text',
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'a session ending (logout / user switch) while the send is in flight '
    'produces no feedback at all',
    (tester) async {
      await openConversation(tester);
      final gate = Completer<ChatMessage?>();
      when(
        repo.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) => gate.future);

      await tester.enterText(find.byType(TextField), 'Build me a plan');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      epoch.invalidate(); // logout mid-flight
      gate.complete(null); // would have been a genuine failure otherwise
      // pump(), not pumpAndSettle() - see the comment in the previous test
      // on why the spinner never settles once the session is invalidated.
      // The duration on the second pump lets the message list's own
      // post-frame auto-scroll (a 100ms Future.delayed, triggered by the
      // optimistic user message) finish, so no timer is left pending.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Failed to get AI response'), findsNothing);
    },
  );

  testWidgets(
    'a screen disposed while the send is in flight produces no feedback '
    'and no exception',
    (tester) async {
      await openConversation(tester);
      final gate = Completer<ChatMessage?>();
      when(
        repo.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) => gate.future);

      await tester.enterText(find.byType(TextField), 'Build me a plan');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Replace the entire widget tree - ChatConversationScreen (and its
      // TextEditingController/ScrollController) is disposed while the
      // send is still awaiting the repository.
      await tester.pumpWidget(hostApp(const SizedBox()));
      gate.complete(null);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  // Provider-level, not a widget test: the screen's own UI already makes an
  // overlapping SEND impossible to trigger through the send button - the
  // Consumer<ChatProvider> that owns the input row replaces the TextField
  // and send IconButton with an "AI is thinking..." indicator for the
  // entire time `isSending` is true (see chat_conversation_screen.dart),
  // so there is never a second send button to tap while one is in flight.
  // That is itself a reassuring finding, but it means the real guarantee
  // to prove lives one layer down, in ChatProvider.sendMessage's own
  // `_isSending` reentrancy guard - exercised directly here.
  test('ChatProvider.sendMessage: an overlapping call blocked by the '
      'reentrancy guard reports no error of its own, and does not disturb '
      'the original call\'s own eventual failure', () async {
    epoch.activate(1);
    when(repo.getConversation(1)).thenAnswer((_) async => conversation(1));
    await provider.loadConversation(1);

    final gate = Completer<ChatMessage?>();
    when(
      repo.sendMessage(
        conversationId: anyNamed('conversationId'),
        message: anyNamed('message'),
      ),
    ).thenAnswer((_) => gate.future);

    String? firstError;
    String? secondError;
    final firstCall = provider.sendMessage(
      'first',
      onError: (message) => firstError = message,
    );

    // Second call while the first is still in flight - _isSending is
    // already true, so this returns false synchronously without ever
    // touching onError.
    final secondResult = await provider.sendMessage(
      'second',
      onError: (message) => secondError = message,
    );

    expect(secondResult, isFalse);
    expect(
      secondError,
      isNull,
      reason: 'a blocked overlapping call must report no error of its own',
    );

    gate.complete(null); // the FIRST call's own genuine failure
    final firstResult = await firstCall;

    expect(firstResult, isFalse);
    expect(
      firstError,
      'Failed to get AI response',
      reason:
          "the first call's own failure must still surface correctly, "
          'unsuppressed and unswapped by the blocked second attempt',
    );
  });

  testWidgets(
    'a successful send after another operation left a stale shared error '
    'never resurfaces that stale error',
    (tester) async {
      await openConversation(tester);
      when(
        repo.deleteConversation(999),
      ).thenThrow(Exception('unrelated delete failure'));
      await provider.deleteConversation(999);
      expect(provider.errorMessage, contains('unrelated delete failure'));

      when(
        repo.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) async => aiMessage(1));

      await tester.enterText(find.byType(TextField), 'Build me a plan');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('unrelated delete failure'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Here is your plan'), findsOneWidget);
    },
  );
}
