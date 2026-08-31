import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/direct_message.dart';
import 'package:go_hard_app/data/models/dm_conversation.dart';
import 'package:go_hard_app/data/repositories/direct_messages_repository.dart';
import 'package:go_hard_app/providers/messages_provider.dart';

@GenerateMocks([DirectMessagesRepository])
import 'messages_provider_session_ownership_test.mocks.dart';

/// Proves [MessagesProvider] never lets a repository result, error,
/// `finally` cleanup, or timer callback started under user A land on the
/// state user B now sees through this same app-scoped provider instance,
/// and that within one session an older request can never overwrite a
/// newer one.
///
/// Real [UserSessionEpoch]; the repository is mocked so `Completer`s give
/// exact control over when each continuation resolves. Timer tests use
/// `fakeAsync`; the non-timer tests use [_settle] to drain chained `await`
/// continuations. Nothing in this file waits on wall-clock time or a timer.

/// Drains the microtask queue enough times that every chained `await`
/// continuation inside the provider (repo call -> guard -> append ->
/// awaited `markAsRead` -> ...) has run. Instantaneous and deterministic -
/// each `Future.microtask` completes on the very next microtask turn.
Future<void> _settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }
}

void main() {
  late MockDirectMessagesRepository repo;
  late UserSessionEpoch epoch;
  late MessagesProvider provider;
  late int notifyCount;

  DirectMessage msg(int id, {int senderId = 99, bool fromMe = false}) =>
      DirectMessage(
        id: id,
        senderId: senderId,
        content: 'm$id',
        sentAt: DateTime(2026, 1, 1, 0, 0, id),
        isFromMe: fromMe,
      );

  DMConversation conv(int friendId, {int unread = 0, String? last}) =>
      DMConversation(
        friendId: friendId,
        friendUsername: 'u$friendId',
        friendName: 'n$friendId',
        unreadCount: unread,
        lastMessage: last,
      );

  void stubDefaults() {
    when(repo.getUnreadCount()).thenAnswer((_) async => 0);
    when(repo.getConversations()).thenAnswer((_) async => <DMConversation>[]);
    when(
      repo.getMessages(
        any,
        beforeId: anyNamed('beforeId'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => <DirectMessage>[]);
    when(repo.markAsRead(any)).thenAnswer((_) => Future<void>.value());
  }

  setUp(() {
    repo = MockDirectMessagesRepository();
    stubDefaults();
    epoch = UserSessionEpoch();
    // Constructed with NO active session, so _initialize() no-ops (captures
    // null) and never starts a stray timer. Tests activate the epoch
    // themselves.
    provider = MessagesProvider(repo, epoch);
    notifyCount = 0;
    provider.addListener(() => notifyCount++);
  });

  tearDown(() {
    try {
      provider.dispose();
    } catch (_) {
      // Some tests dispose explicitly; a second dispose asserts.
    }
  });

  // ================================================================
  // 11-21. Cross-session Provider state
  // ================================================================

  group('cross-session state', () {
    test('11/21: slow loadConversations completing after logout cannot '
        'repopulate the cleared list and does not notify', () async {
      epoch.activate(1);
      final c = Completer<List<DMConversation>>();
      when(repo.getConversations()).thenAnswer((_) => c.future);

      final f = provider.loadConversations(showLoading: false);
      epoch.invalidate();
      provider.clear();
      final notifiesBefore = notifyCount;

      c.complete([conv(5, last: 'A private preview')]);
      await f;

      expect(provider.conversations, isEmpty);
      expect(notifyCount, notifiesBefore);
    });

    test(
      '12: the same completion after user B logs in cannot overwrite B',
      () async {
        epoch.activate(1);
        final aC = Completer<List<DMConversation>>();
        final bC = Completer<List<DMConversation>>();
        var call = 0;
        when(
          repo.getConversations(),
        ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

        final aF = provider.loadConversations(showLoading: false);
        epoch.invalidate();
        epoch.activate(2);
        final bF = provider.loadConversations(showLoading: false);

        bC.complete([conv(9)]);
        await bF;
        expect(provider.conversations.single.friendId, 9);

        aC.complete([conv(5)]);
        await aF;
        expect(provider.conversations.single.friendId, 9);
      },
    );

    test('13: slow loadMessages(friendA) cannot modify B state', () async {
      epoch.activate(1);
      final c = Completer<List<DirectMessage>>();
      when(
        repo.getMessages(
          any,
          beforeId: anyNamed('beforeId'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) => c.future);

      final f = provider.loadMessages(7);
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete([msg(1), msg(2)]);
      await f;

      expect(provider.getMessagesForFriend(7), isEmpty);
      expect(provider.isLoadingMessages, isFalse);
    });

    test('14: slow pagination completion for A cannot modify B', () async {
      epoch.activate(1);
      when(
        repo.getMessages(
          any,
          beforeId: anyNamed('beforeId'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => [msg(5)]);
      await provider.loadMessages(7);
      expect(provider.getMessagesForFriend(7), hasLength(1));

      final c = Completer<List<DirectMessage>>();
      when(
        repo.getMessages(
          any,
          beforeId: anyNamed('beforeId'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) => c.future);

      final f = provider.loadMoreMessages(7);
      epoch.invalidate();
      provider.clear();

      c.complete([msg(1), msg(2)]);
      await f;

      expect(provider.getMessagesForFriend(7), isEmpty);
    });

    test('15: stale send success cannot append into B', () async {
      epoch.activate(1);
      final c = Completer<DirectMessage>();
      when(repo.sendMessage(7, 'hi')).thenAnswer((_) => c.future);

      final f = provider.sendMessage(7, 'hi');
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete(msg(99, fromMe: true));
      expect(await f, isFalse);
      expect(provider.getMessagesForFriend(7), isEmpty);
    });

    test(
      '16: stale send failure/rollback cannot modify B or publish an error',
      () async {
        epoch.activate(1);
        final c = Completer<DirectMessage>();
        when(repo.sendMessage(7, 'hi')).thenAnswer((_) => c.future);

        final f = provider.sendMessage(7, 'hi');
        epoch.invalidate();
        provider.clear();
        final notifiesBefore = notifyCount;

        c.completeError(Exception('boom'));
        expect(await f, isFalse);
        expect(provider.errorMessage, isNull);
        expect(provider.isSending, isFalse);
        expect(
          notifyCount,
          notifiesBefore,
          reason: 'the stale catch must not notify B',
        );
      },
    );

    test('17: stale markAsRead cannot alter B state', () async {
      epoch.activate(1);
      when(
        repo.getConversations(),
      ).thenAnswer((_) async => [conv(7, unread: 3)]);
      await provider.loadConversations();
      expect(provider.conversations.single.unreadCount, 3);

      final c = Completer<void>();
      when(repo.markAsRead(7)).thenAnswer((_) => c.future);
      final f = provider.markAsRead(7);
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete();
      await f;

      expect(provider.conversations, isEmpty);
      expect(provider.totalUnreadCount, 0);
    });

    test('18: stale unread-count load cannot update B', () async {
      epoch.activate(1);
      final c = Completer<int>();
      when(repo.getUnreadCount()).thenAnswer((_) => c.future);

      final f = provider.loadUnreadCount();
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete(42);
      await f;

      expect(provider.totalUnreadCount, 0);
    });

    test('19: stale catch cannot set B error', () async {
      epoch.activate(1);
      final c = Completer<List<DMConversation>>();
      when(repo.getConversations()).thenAnswer((_) => c.future);

      final f = provider.loadConversations();
      epoch.invalidate();
      provider.clear();

      c.completeError(Exception('boom'));
      await f;

      expect(provider.errorMessage, isNull);
    });

    test('20: stale finally cannot clear a newer loading operation', () async {
      epoch.activate(1);
      final aC = Completer<List<DMConversation>>();
      final bC = Completer<List<DMConversation>>();
      var call = 0;
      when(
        repo.getConversations(),
      ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

      final aF = provider.loadConversations();
      final bF = provider.loadConversations();
      expect(provider.isLoading, isTrue);

      aC.complete([]);
      await aF;
      expect(provider.isLoading, isTrue, reason: 'older op must not reset it');

      bC.complete([]);
      await bF;
      expect(provider.isLoading, isFalse);
    });
  });

  // ================================================================
  // 22-27. Same-session ordering
  // ================================================================

  group('same-session ordering', () {
    test(
      '22: an older conversation-list request completing last loses',
      () async {
        epoch.activate(1);
        final c1 = Completer<List<DMConversation>>();
        final c2 = Completer<List<DMConversation>>();
        var call = 0;
        when(
          repo.getConversations(),
        ).thenAnswer((_) => (call++ == 0) ? c1.future : c2.future);

        final f1 = provider.loadConversations();
        final f2 = provider.loadConversations();

        c2.complete([conv(2)]);
        await f2;
        c1.complete([conv(1)]);
        await f1;

        expect(provider.conversations.single.friendId, 2);
      },
    );

    test('23: friend A detail completing after friend B loses', () async {
      epoch.activate(1);
      final cA = Completer<List<DirectMessage>>();
      final cB = Completer<List<DirectMessage>>();
      var call = 0;
      when(
        repo.getMessages(
          any,
          beforeId: anyNamed('beforeId'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) => (call++ == 0) ? cA.future : cB.future);

      final fA = provider.loadMessages(7);
      final fB = provider.loadMessages(9);

      cB.complete([msg(10)]);
      await fB;
      cA.complete([msg(1)]);
      await fA;

      expect(provider.getMessagesForFriend(9).single.id, 10);
      expect(provider.getMessagesForFriend(7), isEmpty);
      expect(provider.isLoadingMessages, isFalse);
    });

    test(
      '24: A->B->A is resolved by generation identity, not friend-id',
      () async {
        epoch.activate(1);
        final cs = [
          Completer<List<DirectMessage>>(),
          Completer<List<DirectMessage>>(),
          Completer<List<DirectMessage>>(),
        ];
        var call = 0;
        when(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) => cs[call++].future);

        final f1 = provider.loadMessages(7);
        final f2 = provider.loadMessages(9);
        final f3 = provider.loadMessages(7);

        cs[0].complete([msg(1)]);
        cs[1].complete([msg(2)]);
        cs[2].complete([msg(3)]);
        await Future.wait([f1, f2, f3]);

        expect(provider.getMessagesForFriend(7).single.id, 3);
      },
    );

    test(
      '25: an older pagination page cannot overwrite a newer refresh',
      () async {
        epoch.activate(1);
        when(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) async => [msg(5), msg(6)]);
        await provider.loadMessages(7);

        final more = Completer<List<DirectMessage>>();
        final refresh = Completer<List<DirectMessage>>();
        var call = 0;
        when(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) => (call++ == 0) ? more.future : refresh.future);

        final moreF = provider.loadMoreMessages(7);
        final refreshF = provider.loadMessages(7);

        refresh.complete([msg(20), msg(21)]);
        await refreshF;
        more.complete([msg(1)]);
        await moreF;

        expect(provider.getMessagesForFriend(7).map((m) => m.id).toList(), [
          20,
          21,
        ]);
      },
    );

    test(
      '26: an older unread poll cannot overwrite a newer manual refresh',
      () async {
        epoch.activate(1);
        final poll = Completer<int>();
        final manual = Completer<int>();
        var call = 0;
        when(
          repo.getUnreadCount(),
        ).thenAnswer((_) => (call++ == 0) ? poll.future : manual.future);

        final pollF = provider.loadUnreadCount();
        final manualF = provider.loadUnreadCount();

        manual.complete(2);
        await manualF;
        poll.complete(99);
        await pollF;

        expect(provider.totalUnreadCount, 2);
      },
    );

    test('27: overlapping sends to different friends are isolated', () async {
      epoch.activate(1);
      final cA = Completer<DirectMessage>();
      final cB = Completer<DirectMessage>();
      when(repo.sendMessage(7, 'a')).thenAnswer((_) => cA.future);
      when(repo.sendMessage(9, 'b')).thenAnswer((_) => cB.future);

      final fA = provider.sendMessage(7, 'a');
      final fB = provider.sendMessage(9, 'b');

      cA.complete(msg(100, fromMe: true));
      await fA;
      cB.complete(msg(200, fromMe: true));
      await fB;

      expect(provider.getMessagesForFriend(7).single.id, 100);
      expect(provider.getMessagesForFriend(9).single.id, 200);
    });

    test('NB1: an older send to a friend cannot overwrite a newer send to '
        'the SAME friend (per-friend send generation)', () async {
      epoch.activate(1);
      provider.startConversationPolling(
        7,
      ); // friend 7 becomes the active thread
      await _settle();

      final s1 = Completer<DirectMessage>();
      final s2 = Completer<DirectMessage>();
      var call = 0;
      when(
        repo.sendMessage(7, any),
      ).thenAnswer((_) => (call++ == 0) ? s1.future : s2.future);

      final f1 = provider.sendMessage(7, 'first');
      final f2 = provider.sendMessage(7, 'second');

      s2.complete(msg(20, fromMe: true));
      expect(await f2, isTrue);
      final notifiesAfterS2 = notifyCount;

      // The older send now fails, after the newer one already succeeded.
      s1.completeError(Exception('boom'));
      expect(await f1, isFalse);

      expect(
        provider.errorMessage,
        isNull,
        reason: 'a superseded send must not surface an error',
      );
      expect(
        provider.getMessagesForFriend(7).map((m) => m.id).toList(),
        [20],
        reason: 'only the newest send to friend 7 is reflected',
      );
      expect(
        notifyCount,
        notifiesAfterS2,
        reason: 'a superseded send must not notify',
      );
    });

    test(
      'NB1b: a bare clear() (no epoch change) drops an in-flight send - '
      'the per-friend send generation bump is load-bearing on its own',
      () async {
        epoch.activate(1);
        final s = Completer<DirectMessage>();
        when(repo.sendMessage(7, 'hi')).thenAnswer((_) => s.future);

        final f = provider.sendMessage(7, 'hi');
        provider.clear(); // NOTE: no epoch.invalidate()

        s.complete(msg(50, fromMe: true));
        expect(await f, isFalse);
        expect(provider.getMessagesForFriend(7), isEmpty);
      },
    );
  });

  // ================================================================
  // 28-36. Timers
  // ================================================================

  group('timers', () {
    test('28: logged-out scheduling creates no timer', () {
      fakeAsync((async) {
        // epoch not activated
        provider.startConversationPolling(7);
        provider.startUnreadCountPolling();
        async.elapse(const Duration(seconds: 120));
        async.flushMicrotasks();
        verifyNever(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        );
        verifyNever(repo.getUnreadCount());
      });
    });

    test(
      '29: conversation timer scheduled under A no-ops after invalidation',
      () {
        fakeAsync((async) {
          epoch.activate(1);
          provider.startConversationPolling(7);
          async.flushMicrotasks();
          clearInteractions(repo);

          epoch.invalidate();
          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();

          verifyNever(
            repo.getMessages(
              any,
              beforeId: anyNamed('beforeId'),
              limit: anyNamed('limit'),
            ),
          );
        });
      },
    );

    test('30: conversation timer scheduled under A no-ops after B login', () {
      fakeAsync((async) {
        epoch.activate(1);
        provider.startConversationPolling(7);
        async.flushMicrotasks();
        clearInteractions(repo);

        epoch.invalidate();
        epoch.activate(2);
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        verifyNever(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        );
      });
    });

    test('31: unread timer scheduled under A never fetches again once A ends - '
        'and never recaptures user B', () {
      fakeAsync((async) {
        epoch.activate(1);
        when(repo.getUnreadCount()).thenAnswer((_) async => 7);
        provider.startUnreadCountPolling();
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(provider.totalUnreadCount, 7);

        // A logs out, B logs in - a stale A tick that recaptured would
        // now get B's token and fetch B's count.
        epoch.invalidate();
        epoch.activate(2);
        when(repo.getUnreadCount()).thenAnswer((_) async => 99);
        clearInteractions(repo);
        async.elapse(const Duration(seconds: 120));
        async.flushMicrotasks();

        verifyNever(repo.getUnreadCount());
        expect(provider.totalUnreadCount, 7);
      });
    });

    test(
      '32: an old A timer callback cannot cancel B\'s replacement timer',
      () {
        fakeAsync((async) {
          epoch.activate(1);
          provider.startConversationPolling(7); // A's timer (generation 1)
          async.flushMicrotasks();

          epoch.invalidate();
          epoch.activate(2);
          // B's timer (generation 2). A's Timer instance is deliberately
          // NOT hard-cancelled here - it self-cancels on its next tick.
          provider.startConversationPolling(7);
          async.flushMicrotasks();
          clearInteractions(repo);

          // Over the next several ticks A's stale timer fires (and must
          // cancel only itself); B's timer must keep polling throughout.
          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();

          verify(
            repo.getMessages(
              7,
              beforeId: anyNamed('beforeId'),
              limit: anyNamed('limit'),
            ),
          ).called(greaterThanOrEqualTo(3));
        });
      },
    );

    test(
      '33: a poll callback in flight when clear() runs cannot repopulate',
      () async {
        epoch.activate(1);
        final c = Completer<List<DirectMessage>>();
        when(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) => c.future);

        provider.startConversationPolling(7);
        await _settle();

        provider.clear();
        c.complete([msg(1), msg(2)]);
        await _settle();
        await _settle();

        expect(provider.getMessagesForFriend(7), isEmpty);
      },
    );

    test('34: polling does not overlap itself', () {
      fakeAsync((async) {
        epoch.activate(1);
        var inFlight = 0;
        var maxConcurrent = 0;
        final pending = <Completer<List<DirectMessage>>>[];
        when(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) {
          inFlight++;
          maxConcurrent = max(maxConcurrent, inFlight);
          final comp = Completer<List<DirectMessage>>();
          pending.add(comp);
          return comp.future.whenComplete(() => inFlight--);
        });

        provider.startConversationPolling(7);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(maxConcurrent, 1);

        for (final comp in pending) {
          if (!comp.isCompleted) comp.complete(<DirectMessage>[]);
        }
        async.flushMicrotasks();
      });
    });

    test(
      '35: stale polling never calls markAsRead and never repopulates',
      () async {
        epoch.activate(1);
        final c = Completer<List<DirectMessage>>();
        when(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) => c.future);

        provider.startConversationPolling(7);
        await _settle();

        epoch.invalidate();
        provider.clear();
        epoch.activate(2);
        clearInteractions(repo);

        c.complete([msg(1)]);
        await _settle();
        await _settle();

        verifyNever(repo.markAsRead(any));
        expect(provider.getMessagesForFriend(7), isEmpty);
      },
    );

    test('NB2: a poll from a superseded conversation generation neither '
        'appends nor marks read when it finally completes', () async {
      epoch.activate(1);
      final poll1 = Completer<List<DirectMessage>>();
      when(
        repo.getMessages(
          any,
          beforeId: anyNamed('beforeId'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) => poll1.future);

      provider.startConversationPolling(7); // generation 1, poll in flight
      await _settle();

      // Same session, but the conversation timer is torn down and
      // re-established (as conversation_screen dispose + re-init would do).
      provider.stopConversationPolling(); // generation 2
      provider.startConversationPolling(7); // generation 3
      await _settle();
      clearInteractions(repo);

      // Generation 1's poll finally resolves with brand-new messages.
      poll1.complete([msg(1), msg(2)]);
      await _settle();
      await _settle();

      verifyNever(repo.markAsRead(any));
      expect(provider.getMessagesForFriend(7), isEmpty);
    });

    test(
      '21: the poll awaits markAsRead rather than firing and forgetting',
      () async {
        epoch.activate(1);
        when(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) async => [msg(1)]);
        await provider.loadMessages(7); // seed [msg(1)]

        final pollGet = Completer<List<DirectMessage>>();
        final markDone = Completer<void>();
        when(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) => pollGet.future);
        when(repo.markAsRead(7)).thenAnswer((_) => markDone.future);

        provider.startConversationPolling(7); // immediate poll
        await _settle();
        expect(provider.conversationPollInFlightForTesting, isTrue);

        pollGet.complete([msg(9)]); // a genuinely newer message
        await _settle();
        await _settle();

        // Still in flight: the poll is awaiting markAsRead, not done.
        expect(provider.conversationPollInFlightForTesting, isTrue);
        verify(repo.markAsRead(7)).called(1);

        markDone.complete();
        await _settle();
        expect(provider.conversationPollInFlightForTesting, isFalse);
      },
    );

    test(
      '36: dispose() prevents later timer callbacks and state publication',
      () {
        fakeAsync((async) {
          epoch.activate(1);
          when(repo.getUnreadCount()).thenAnswer((_) async => 5);
          provider.startUnreadCountPolling();
          provider.startConversationPolling(7);
          async.flushMicrotasks();

          provider.dispose();
          clearInteractions(repo);

          async.elapse(const Duration(seconds: 120));
          async.flushMicrotasks();

          verifyNever(repo.getUnreadCount());
          verifyNever(
            repo.getMessages(
              any,
              beforeId: anyNamed('beforeId'),
              limit: anyNamed('limit'),
            ),
          );
        });
      },
    );
  });

  // ================================================================
  // 37-40. Cleanup / regression
  // ================================================================

  group('cleanup and regression', () {
    test('37: clear() empties all state and stops both polling timers', () {
      fakeAsync((async) {
        epoch.activate(1);
        when(repo.getConversations()).thenAnswer((_) async => [conv(7)]);
        provider.loadConversations();
        provider.startUnreadCountPolling();
        provider.startConversationPolling(7);
        async.flushMicrotasks();

        provider.clear();
        clearInteractions(repo);

        async.elapse(const Duration(seconds: 120));
        async.flushMicrotasks();

        expect(provider.conversations, isEmpty);
        expect(provider.totalUnreadCount, 0);
        expect(provider.isLoading, isFalse);
        verifyNever(repo.getUnreadCount());
        verifyNever(
          repo.getMessages(
            any,
            beforeId: anyNamed('beforeId'),
            limit: anyNamed('limit'),
          ),
        );
      });
    });

    test('24: clear() drops an in-flight load even with no epoch change '
        '(generation bump is load-bearing on its own)', () async {
      epoch.activate(1);
      final c = Completer<List<DMConversation>>();
      when(repo.getConversations()).thenAnswer((_) => c.future);

      final f = provider.loadConversations(showLoading: false);
      provider.clear(); // NOTE: no epoch.invalidate()

      c.complete([conv(5, last: 'A private preview')]);
      await f;

      expect(provider.conversations, isEmpty);
    });

    test('38: happy path within one session still works end to end', () async {
      epoch.activate(1);
      when(
        repo.getConversations(),
      ).thenAnswer((_) async => [conv(7, unread: 2, last: 'hi')]);
      when(
        repo.getMessages(
          any,
          beforeId: anyNamed('beforeId'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => [msg(1), msg(2)]);
      when(
        repo.sendMessage(7, 'yo'),
      ).thenAnswer((_) async => msg(3, fromMe: true));

      await provider.loadConversations();
      expect(provider.conversations.single.friendId, 7);

      await provider.loadMessages(7);
      expect(provider.getMessagesForFriend(7), hasLength(2));

      final ok = await provider.sendMessage(7, 'yo');
      expect(ok, isTrue);
      expect(provider.getMessagesForFriend(7), hasLength(3));
      expect(provider.isSending, isFalse);
    });

    test(
      '39: clear() is idempotent (both logout triggers route through it)',
      () {
        epoch.activate(1);
        provider.clear();
        provider.clear();
        expect(provider.conversations, isEmpty);
        expect(provider.totalUnreadCount, 0);
      },
    );

    test('a fresh session after clear() loads its own data normally', () async {
      epoch.activate(1);
      provider.clear();

      epoch.activate(2);
      when(repo.getConversations()).thenAnswer((_) async => [conv(42)]);
      await provider.loadConversations();

      expect(provider.conversations.single.friendId, 42);
    });
  });
}
