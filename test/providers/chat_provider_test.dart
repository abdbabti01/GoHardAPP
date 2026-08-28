import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/chat_conversation.dart';
import 'package:go_hard_app/data/models/chat_message.dart';
import 'package:go_hard_app/data/repositories/chat_repository.dart';
import 'package:go_hard_app/providers/chat_provider.dart';

@GenerateMocks([ChatRepository, ConnectivityService])
import 'chat_provider_test.mocks.dart';

/// Logout PR 2A coverage: proves ChatProvider drops any response that
/// resolves after the session that requested it has ended, and - most
/// importantly - that [ChatProvider.sendMessage] can never append a
/// response into a conversation that now belongs to a different account
/// (the confirmed defect this PR fixes).
void main() {
  late MockChatRepository mockChatRepository;
  late UserSessionEpoch sessionEpoch;
  late ChatProvider provider;

  ChatConversation conversation(int id, {int userId = 1}) => ChatConversation(
    id: id,
    userId: userId,
    title: 'Conversation $id',
    type: 'general',
    createdAt: DateTime.utc(2024, 1, 1),
  );

  ChatMessage aiMessage(int conversationId) => ChatMessage(
    id: 99,
    conversationId: conversationId,
    role: 'assistant',
    content: 'response',
    createdAt: DateTime.utc(2024, 1, 1),
  );

  setUp(() {
    mockChatRepository = MockChatRepository();
    sessionEpoch = UserSessionEpoch();
    provider = ChatProvider(
      mockChatRepository,
      ConnectivityService.instance,
      sessionEpoch,
    );
  });

  group('loadConversations', () {
    test('with no active session, never calls the repository', () async {
      await provider.loadConversations();

      verifyNever(mockChatRepository.getConversations());
      expect(provider.conversations, isEmpty);
    });

    test('a response that resolves after logout is dropped: conversations '
        'and errorMessage are left untouched', () async {
      sessionEpoch.activate(1);
      final completer = Completer<List<ChatConversation>>();
      when(
        mockChatRepository.getConversations(),
      ).thenAnswer((_) => completer.future);

      final future = provider.loadConversations();
      sessionEpoch.invalidate();
      completer.complete([conversation(1)]);
      await future;

      expect(provider.conversations, isEmpty);
      expect(provider.errorMessage, isNull);
    });

    test('a response that resolves after a different user has logged in does '
        'not leak into that user\'s conversation list', () async {
      sessionEpoch.activate(1);
      final completerA = Completer<List<ChatConversation>>();
      when(
        mockChatRepository.getConversations(),
      ).thenAnswer((_) => completerA.future);

      final futureA = provider.loadConversations();
      sessionEpoch.invalidate();
      sessionEpoch.activate(2);
      completerA.complete([conversation(1)]);
      await futureA;

      expect(provider.conversations, isEmpty);
    });
  });

  group('sendMessage - cross-account corruption fix', () {
    test('with no active session, never calls the repository', () async {
      final result = await provider.sendMessage('hello');

      expect(result, isFalse);
      verifyNever(
        mockChatRepository.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      );
    });

    test('when the session ends while the AI response is in flight, the '
        'response is dropped WITHOUT touching currentConversation - closing '
        'both the null-assert crash (if clear() ran) and the cross-account '
        'corruption path', () async {
      sessionEpoch.activate(1);
      // Simulate an already-loaded conversation for User A.
      when(
        mockChatRepository.getConversation(1),
      ).thenAnswer((_) async => conversation(1));
      await provider.loadConversation(1);
      expect(provider.currentConversation, isNotNull);

      final completer = Completer<ChatMessage?>();
      when(
        mockChatRepository.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) => completer.future);

      final future = provider.sendMessage('hi');

      // Logout runs mid-flight: AuthProvider's real logout path also
      // calls ChatProvider.clear(), which nulls currentConversation -
      // reproduce that here to prove sendMessage's post-await check
      // prevents the null-assert crash this defect used to cause.
      sessionEpoch.invalidate();
      provider.clear();

      completer.complete(aiMessage(1));
      final result = await future;

      expect(result, isFalse);
      expect(provider.currentConversation, isNull);
    });

    test('when a DIFFERENT user logs in while the AI response is in flight, '
        'the response is dropped instead of being appended into the new '
        'user\'s now-active conversation', () async {
      sessionEpoch.activate(1);
      when(
        mockChatRepository.getConversation(1),
      ).thenAnswer((_) async => conversation(1, userId: 1));
      await provider.loadConversation(1);

      final completer = Completer<ChatMessage?>();
      when(
        mockChatRepository.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) => completer.future);

      final future = provider.sendMessage('hi');

      // User A logs out, User B logs in and loads their own conversation
      // into this same shared provider instance - all before A's AI
      // response comes back.
      sessionEpoch.invalidate();
      sessionEpoch.activate(2);
      when(
        mockChatRepository.getConversation(2),
      ).thenAnswer((_) async => conversation(2, userId: 2));
      await provider.loadConversation(2);
      expect(provider.currentConversation?.id, 2);

      completer.complete(aiMessage(1));
      final result = await future;

      expect(result, isFalse);
      expect(
        provider.currentConversation?.id,
        2,
        reason:
            "User A's stale AI response must never be appended into "
            "User B's conversation",
      );
      expect(
        provider.currentConversation!.messages,
        isEmpty,
        reason: "User B's freshly-loaded conversation must stay untouched",
      );
    });

    test('a same-session send is applied normally', () async {
      sessionEpoch.activate(1);
      when(
        mockChatRepository.getConversation(1),
      ).thenAnswer((_) async => conversation(1));
      await provider.loadConversation(1);

      when(
        mockChatRepository.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) async => aiMessage(1));

      final result = await provider.sendMessage('hi');

      expect(result, isTrue);
      expect(
        provider.currentConversation!.messages.map((m) => m.role),
        containsAll(['user', 'assistant']),
      );
    });
  });

  group('sendMessage - same-user cross-conversation race (A -> B)', () {
    test(
      'switching to conversation B before A\'s AI response arrives does not '
      'append A\'s response into B, and does not modify B\'s list entry',
      () async {
        sessionEpoch.activate(1);
        when(
          mockChatRepository.getConversation(1),
        ).thenAnswer((_) async => conversation(1));
        when(
          mockChatRepository.getConversation(2),
        ).thenAnswer((_) async => conversation(2));
        when(
          mockChatRepository.getConversations(),
        ).thenAnswer((_) async => [conversation(1), conversation(2)]);
        await provider.loadConversations();
        await provider.loadConversation(1);

        final completer = Completer<ChatMessage?>();
        when(
          mockChatRepository.sendMessage(
            conversationId: anyNamed('conversationId'),
            message: anyNamed('message'),
          ),
        ).thenAnswer((_) => completer.future);

        final future = provider.sendMessage('hi from A');

        // Same session/user throughout - switches to B before A's response
        // lands, so the session token alone would not catch this.
        await provider.loadConversation(2);
        expect(provider.currentConversation?.id, 2);

        completer.complete(aiMessage(1));
        final result = await future;

        expect(result, isFalse);
        expect(provider.currentConversation?.id, 2);
        expect(
          provider.currentConversation!.messages,
          isEmpty,
          reason: "B's messages must not receive A's response",
        );
        final bInList = provider.conversations.firstWhere((c) => c.id == 2);
        expect(
          bInList.messages,
          isEmpty,
          reason: "B's list entry must not be modified by A's completion",
        );
      },
    );

    test('switching to conversation B before A\'s send fails does not roll '
        'back B\'s messages and does not set B\'s error state', () async {
      sessionEpoch.activate(1);
      when(
        mockChatRepository.getConversation(1),
      ).thenAnswer((_) async => conversation(1));
      when(
        mockChatRepository.getConversation(2),
      ).thenAnswer((_) async => conversation(2));
      await provider.loadConversation(1);

      final completer = Completer<ChatMessage?>();
      when(
        mockChatRepository.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) => completer.future);

      final future = provider.sendMessage('hi from A');

      await provider.loadConversation(2);
      expect(provider.currentConversation?.id, 2);

      completer.completeError(Exception('network boom'));
      final result = await future;

      expect(result, isFalse);
      expect(provider.currentConversation?.id, 2);
      expect(provider.currentConversation!.messages, isEmpty);
      expect(
        provider.errorMessage,
        isNull,
        reason: "A's failure must not surface as B's error message",
      );
    });

    test('clearing the current conversation before A\'s response arrives is '
        'ignored safely with no null-assertion crash', () async {
      sessionEpoch.activate(1);
      when(
        mockChatRepository.getConversation(1),
      ).thenAnswer((_) async => conversation(1));
      await provider.loadConversation(1);

      final completer = Completer<ChatMessage?>();
      when(
        mockChatRepository.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) => completer.future);

      final future = provider.sendMessage('hi');

      // Same session stays valid throughout - only the current
      // conversation reference is nulled, independent of logout.
      provider.clearCurrentConversation();
      completer.complete(aiMessage(1));

      final result = await future;

      expect(result, isFalse);
      expect(provider.currentConversation, isNull);
    });

    test('remaining in conversation A preserves normal optimistic-message '
        'and response behavior', () async {
      sessionEpoch.activate(1);
      when(
        mockChatRepository.getConversation(1),
      ).thenAnswer((_) async => conversation(1));
      await provider.loadConversation(1);

      when(
        mockChatRepository.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) async => aiMessage(1));

      final result = await provider.sendMessage('hi');

      expect(result, isTrue);
      expect(provider.currentConversation!.messages, hasLength(2));
      expect(
        provider.currentConversation!.messages.map((m) => m.role),
        containsAllInOrder(['user', 'assistant']),
      );
    });

    test('a response whose own conversationId differs from the request\'s '
        'conversation is rejected even though ownership checks pass', () async {
      sessionEpoch.activate(1);
      when(
        mockChatRepository.getConversation(1),
      ).thenAnswer((_) async => conversation(1));
      await provider.loadConversation(1);

      when(
        mockChatRepository.sendMessage(
          conversationId: anyNamed('conversationId'),
          message: anyNamed('message'),
        ),
      ).thenAnswer((_) async => aiMessage(999));

      final result = await provider.sendMessage('hi');

      expect(result, isFalse);
      expect(
        provider.currentConversation!.messages,
        isEmpty,
        reason:
            'a response claiming a different conversation must never be '
            'attached, and the optimistic user message must be rolled '
            'back rather than left stuck in a pending-looking state',
      );
    });

    test(
      'overlapping sendMessage calls are rejected: a second call while one '
      'is already in flight returns false without a second repository call',
      () async {
        sessionEpoch.activate(1);
        when(
          mockChatRepository.getConversation(1),
        ).thenAnswer((_) async => conversation(1));
        await provider.loadConversation(1);

        final completer = Completer<ChatMessage?>();
        when(
          mockChatRepository.sendMessage(
            conversationId: anyNamed('conversationId'),
            message: anyNamed('message'),
          ),
        ).thenAnswer((_) => completer.future);

        final first = provider.sendMessage('first');
        final second = await provider.sendMessage('second');

        expect(
          second,
          isFalse,
          reason: 'a send already in flight must block a second one',
        );
        verify(
          mockChatRepository.sendMessage(
            conversationId: anyNamed('conversationId'),
            message: anyNamed('message'),
          ),
        ).called(1);

        completer.complete(aiMessage(1));
        await first;
      },
    );
  });

  group('deleteAllConversations', () {
    test('stops issuing further deletes/state mutations once the session '
        'ends mid-batch', () async {
      sessionEpoch.activate(1);
      when(
        mockChatRepository.getConversations(),
      ).thenAnswer((_) async => [conversation(1), conversation(2)]);
      await provider.loadConversations();
      expect(provider.conversations, hasLength(2));

      final completer1 = Completer<bool>();
      when(
        mockChatRepository.deleteConversation(1),
      ).thenAnswer((_) => completer1.future);
      when(
        mockChatRepository.deleteConversation(2),
      ).thenAnswer((_) async => true);

      final future = provider.deleteAllConversations();
      sessionEpoch.invalidate();
      completer1.complete(true);

      final result = await future;

      expect(result, isFalse);
      verifyNever(mockChatRepository.deleteConversation(2));
    });
  });

  group('connectivity-restored callback', () {
    late StreamController<bool> connectivityController;
    late MockConnectivityService mockConnectivity;

    setUp(() {
      connectivityController = StreamController<bool>.broadcast();
      mockConnectivity = MockConnectivityService();
      when(
        mockConnectivity.connectivityStream,
      ).thenAnswer((_) => connectivityController.stream);
    });

    tearDown(() async {
      await connectivityController.close();
    });

    test('while logged out, a connectivity-restored event does not call the '
        'repository or alter loading/error/data state', () async {
      // No sessionEpoch.activate() - simulates a connectivity flap
      // during the logged-out gap between two sessions.
      final loggedOutProvider = ChatProvider(
        mockChatRepository,
        mockConnectivity,
        sessionEpoch,
      );

      connectivityController.add(true);
      await pumpEventQueue();

      verifyNever(mockChatRepository.getConversations());
      expect(loggedOutProvider.conversations, isEmpty);
      expect(loggedOutProvider.errorMessage, isNull);
      expect(loggedOutProvider.isLoading, isFalse);
    });

    test('while authenticated, a connectivity-restored event triggers the '
        'intended refresh', () async {
      sessionEpoch.activate(1);
      when(
        mockChatRepository.getConversations(),
      ).thenAnswer((_) async => [conversation(1)]);

      final onlineProvider = ChatProvider(
        mockChatRepository,
        mockConnectivity,
        sessionEpoch,
      );

      connectivityController.add(true);
      await pumpEventQueue();

      verify(mockChatRepository.getConversations()).called(1);
      expect(onlineProvider.conversations, hasLength(1));
    });

    test('if the session becomes invalid while the connectivity-triggered '
        'refresh is in flight, its completion is discarded', () async {
      sessionEpoch.activate(1);
      final refreshCompleter = Completer<List<ChatConversation>>();
      when(
        mockChatRepository.getConversations(),
      ).thenAnswer((_) => refreshCompleter.future);

      final onlineProvider = ChatProvider(
        mockChatRepository,
        mockConnectivity,
        sessionEpoch,
      );

      connectivityController.add(true);
      await pumpEventQueue();

      sessionEpoch.invalidate();
      refreshCompleter.complete([conversation(1)]);
      await pumpEventQueue();

      expect(
        onlineProvider.conversations,
        isEmpty,
        reason:
            'the stale refresh must not populate a logged-out '
            'provider\'s conversation list',
      );
    });
  });
}
