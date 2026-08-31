import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/friend.dart';
import 'package:go_hard_app/data/models/friend_request.dart';
import 'package:go_hard_app/data/models/friendship_status.dart';
import 'package:go_hard_app/data/models/public_profile.dart';
import 'package:go_hard_app/data/models/user_search_result.dart';
import 'package:go_hard_app/data/repositories/friends_repository.dart';
import 'package:go_hard_app/providers/friends_provider.dart';

@GenerateMocks([FriendsRepository])
import 'friends_provider_session_ownership_test.mocks.dart';

/// Proves [FriendsProvider] never lets a repository result, error,
/// `finally` cleanup, or timer callback started under user A land on the
/// state user B now sees through this same app-scoped provider instance,
/// and that within one session an older request can never overwrite a
/// newer one.
///
/// Real [UserSessionEpoch]; the repository is mocked so `Completer`s give
/// exact control over when each continuation resolves. Timer/polling tests
/// use `fakeAsync`; the rest drive continuations by awaiting the method
/// future directly. Nothing in this file waits on wall-clock time.
void main() {
  late MockFriendsRepository repo;
  late UserSessionEpoch epoch;
  late FriendsProvider provider;
  late int notifyCount;

  Friend friend(int userId) => Friend(
    userId: userId,
    username: 'u$userId',
    name: 'n$userId',
    friendsSince: DateTime(2026, 1, 1),
  );

  FriendRequest request(int friendshipId, {int? userId}) => FriendRequest(
    friendshipId: friendshipId,
    userId: userId ?? (1000 + friendshipId),
    username: 'r$friendshipId',
    name: 'rn$friendshipId',
    requestedAt: DateTime(2026, 1, 1),
  );

  UserSearchResult searchResult(int userId) => UserSearchResult(
    userId: userId,
    username: 'su$userId',
    name: 'sn$userId',
  );

  void stubDefaults() {
    when(repo.getFriends()).thenAnswer((_) async => <Friend>[]);
    when(repo.getIncomingRequests()).thenAnswer((_) async => <FriendRequest>[]);
    when(repo.getOutgoingRequests()).thenAnswer((_) async => <FriendRequest>[]);
    when(repo.searchUsers(any)).thenAnswer((_) async => <UserSearchResult>[]);
    when(repo.sendFriendRequest(any)).thenAnswer((_) => Future<void>.value());
    when(repo.acceptRequest(any)).thenAnswer((_) => Future<void>.value());
    when(repo.declineRequest(any)).thenAnswer((_) => Future<void>.value());
    when(repo.cancelFriendRequest(any)).thenAnswer((_) => Future<void>.value());
    when(repo.removeFriend(any)).thenAnswer((_) => Future<void>.value());
    when(
      repo.getFriendshipStatus(any),
    ).thenAnswer((_) async => FriendshipStatus(status: 'none'));
  }

  setUp(() {
    repo = MockFriendsRepository();
    stubDefaults();
    epoch = UserSessionEpoch();
    provider = FriendsProvider(repo, epoch);
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
    test('11/21: slow loadAll completing after logout cannot repopulate the '
        'cleared lists and does not notify', () async {
      epoch.activate(1);
      final c = Completer<List<Friend>>();
      when(repo.getFriends()).thenAnswer((_) => c.future);
      when(
        repo.getIncomingRequests(),
      ).thenAnswer((_) async => [request(5, userId: 55)]);

      final f = provider.loadAll();
      epoch.invalidate();
      provider.clear();
      final notifiesBefore = notifyCount;

      c.complete([friend(9)]);
      await f;

      expect(provider.friends, isEmpty);
      expect(provider.incomingRequests, isEmpty);
      expect(notifyCount, notifiesBefore);
    });

    test('12: the same loadAll completion after user B logs in cannot expose '
        "A's data to B", () async {
      epoch.activate(1);
      final aC = Completer<List<Friend>>();
      when(repo.getFriends()).thenAnswer((_) => aC.future);

      final aF = provider.loadAll();
      epoch.invalidate();
      epoch.activate(2);
      provider.clear();

      when(repo.getFriends()).thenAnswer((_) async => [friend(2)]);
      await provider.loadAll();
      expect(provider.friends.single.userId, 2);

      aC.complete([friend(999)]);
      await aF;
      expect(provider.friends.single.userId, 2);
    });

    test('13: slow loadFriends cannot overwrite B', () async {
      epoch.activate(1);
      final c = Completer<List<Friend>>();
      when(repo.getFriends()).thenAnswer((_) => c.future);

      final f = provider.loadFriends();
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete([friend(7), friend(8)]);
      await f;

      expect(provider.friends, isEmpty);
      expect(provider.isLoading, isFalse);
    });

    test("14: slow loadIncomingRequests cannot expose A's incoming requests "
        'to B', () async {
      epoch.activate(1);
      final c = Completer<List<FriendRequest>>();
      when(repo.getIncomingRequests()).thenAnswer((_) => c.future);

      final f = provider.loadIncomingRequests();
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete([request(1), request(2)]);
      await f;

      expect(provider.incomingRequests, isEmpty);
    });

    test('15: slow loadOutgoingRequests cannot overwrite B', () async {
      epoch.activate(1);
      final c = Completer<List<FriendRequest>>();
      when(repo.getOutgoingRequests()).thenAnswer((_) => c.future);

      final f = provider.loadOutgoingRequests();
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete([request(3)]);
      await f;

      expect(provider.outgoingRequests, isEmpty);
    });

    test('16: a stale search success cannot publish into B', () async {
      epoch.activate(1);
      final c = Completer<List<UserSearchResult>>();
      when(repo.searchUsers('bob')).thenAnswer((_) => c.future);

      final f = provider.searchUsers('bob');
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete([searchResult(42)]);
      await f;

      expect(provider.searchResults, isEmpty);
      expect(provider.isSearching, isFalse);
    });

    test('17: a stale search failure cannot publish an error into B', () async {
      epoch.activate(1);
      final c = Completer<List<UserSearchResult>>();
      when(repo.searchUsers('bob')).thenAnswer((_) => c.future);

      final f = provider.searchUsers('bob');
      epoch.invalidate();
      provider.clear();
      final notifiesBefore = notifyCount;

      c.completeError(Exception('boom'));
      await f;

      expect(provider.searchResults, isEmpty);
      expect(provider.errorMessage, isNull);
      expect(notifyCount, notifiesBefore);
    });

    test(
      '18: a stale mutation success (removeFriend) cannot modify B',
      () async {
        epoch.activate(1);
        final c = Completer<void>();
        when(repo.removeFriend(3)).thenAnswer((_) => c.future);
        when(repo.getFriends()).thenAnswer((_) async => [friend(3), friend(4)]);
        await provider.loadFriends();

        final f = provider.removeFriend(3);
        epoch.invalidate();
        provider.clear();
        epoch.activate(2);
        when(repo.getFriends()).thenAnswer((_) async => [friend(3)]);
        await provider.loadFriends();
        expect(provider.friends.single.userId, 3);

        c.complete();
        expect(await f, isFalse);
        expect(
          provider.friends.single.userId,
          3,
          reason: "A's stale removeFriend must not prune B's friend 3",
        );
      },
    );

    test('19: a stale mutation failure/rollback cannot modify B or publish an '
        'error', () async {
      epoch.activate(1);
      final c = Completer<void>();
      when(repo.declineRequest(11)).thenAnswer((_) => c.future);

      final f = provider.declineRequest(11);
      epoch.invalidate();
      provider.clear();
      final notifiesBefore = notifyCount;

      c.completeError(Exception('boom'));
      expect(await f, isFalse);
      expect(provider.errorMessage, isNull);
      expect(notifyCount, notifiesBefore);
    });

    test('20: a stale catch cannot set B error (loadFriends)', () async {
      epoch.activate(1);
      final c = Completer<List<Friend>>();
      when(repo.getFriends()).thenAnswer((_) => c.future);

      final f = provider.loadFriends();
      epoch.invalidate();
      provider.clear();

      c.completeError(Exception('boom'));
      await f;

      expect(provider.errorMessage, isNull);
    });

    test('21: a stale finally cannot clear B\'s newer loading flag', () async {
      epoch.activate(1);
      final aC = Completer<List<Friend>>();
      final bC = Completer<List<Friend>>();
      var call = 0;
      when(
        repo.getFriends(),
      ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

      final aF = provider.loadFriends();
      final bF = provider.loadFriends();
      expect(provider.isLoading, isTrue);

      aC.complete([]);
      await aF;
      expect(provider.isLoading, isTrue, reason: 'older op must not reset it');

      bC.complete([]);
      await bF;
      expect(provider.isLoading, isFalse);
    });

    test(
      '22: listener count proves stale continuations do not notify',
      () async {
        epoch.activate(1);
        final c = Completer<List<Friend>>();
        when(repo.getFriends()).thenAnswer((_) => c.future);

        final f = provider.loadFriends(showLoading: false);
        epoch.invalidate();
        provider.clear();
        final notifiesBefore = notifyCount;

        c.complete([friend(1)]);
        await f;

        expect(notifyCount, notifiesBefore);
      },
    );
  });

  // ================================================================
  // 23-33. Same-session ordering
  // ================================================================

  group('same-session ordering', () {
    test('23: an older loadAll completing last loses - its stale partial '
        'result cannot commit and its stale finally cannot clear a newer '
        "operation's spinner", () async {
      epoch.activate(1);
      final a1 = Completer<List<Friend>>();
      final a2 = Completer<List<Friend>>();
      final a3 = Completer<List<Friend>>();
      var call = 0;
      when(repo.getFriends()).thenAnswer((_) {
        switch (call++) {
          case 0:
            return a1.future;
          case 1:
            return a2.future;
          default:
            return a3.future;
        }
      });

      final f1 = provider.loadAll(); // aggregate generation 1
      final f2 = provider.loadAll(); // aggregate generation 2

      a2.complete([friend(2)]);
      await f2;
      expect(provider.isLoading, isFalse);

      // A brand-new direct load turns the spinner back on.
      final f3 = provider.loadFriends();
      expect(provider.isLoading, isTrue);

      // The obsolete first loadAll now finishes last - it must neither
      // publish friend 1 nor clear f3's spinner.
      a1.complete([friend(1)]);
      await f1;
      expect(
        provider.isLoading,
        isTrue,
        reason: "stale loadAll finally must not clear the newer load's spinner",
      );

      a3.complete([friend(9)]);
      await f3;
      expect(provider.friends.single.userId, 9);
      expect(provider.isLoading, isFalse);
    });

    test('24: an older friends-list request completing last loses', () async {
      epoch.activate(1);
      final c1 = Completer<List<Friend>>();
      final c2 = Completer<List<Friend>>();
      var call = 0;
      when(
        repo.getFriends(),
      ).thenAnswer((_) => (call++ == 0) ? c1.future : c2.future);

      final f1 = provider.loadFriends();
      final f2 = provider.loadFriends();

      c2.complete([friend(2)]);
      await f2;
      c1.complete([friend(1)]);
      await f1;

      expect(provider.friends.single.userId, 2);
      expect(provider.isLoading, isFalse);
    });

    test('25: an older incoming-request load completing last loses', () async {
      epoch.activate(1);
      final c1 = Completer<List<FriendRequest>>();
      final c2 = Completer<List<FriendRequest>>();
      var call = 0;
      when(
        repo.getIncomingRequests(),
      ).thenAnswer((_) => (call++ == 0) ? c1.future : c2.future);

      final f1 = provider.loadIncomingRequests();
      final f2 = provider.loadIncomingRequests();

      c2.complete([request(2)]);
      await f2;
      c1.complete([request(1)]);
      await f1;

      expect(provider.incomingRequests.single.friendshipId, 2);
    });

    test('26: an older outgoing-request load completing last loses', () async {
      epoch.activate(1);
      final c1 = Completer<List<FriendRequest>>();
      final c2 = Completer<List<FriendRequest>>();
      var call = 0;
      when(
        repo.getOutgoingRequests(),
      ).thenAnswer((_) => (call++ == 0) ? c1.future : c2.future);

      final f1 = provider.loadOutgoingRequests();
      final f2 = provider.loadOutgoingRequests();

      c2.complete([request(2)]);
      await f2;
      c1.complete([request(1)]);
      await f1;

      expect(provider.outgoingRequests.single.friendshipId, 2);
    });

    test(
      '27: search A->B->A is resolved by generation, not query equality',
      () async {
        epoch.activate(1);
        final cs = [
          Completer<List<UserSearchResult>>(),
          Completer<List<UserSearchResult>>(),
          Completer<List<UserSearchResult>>(),
        ];
        var call = 0;
        when(repo.searchUsers(any)).thenAnswer((_) => cs[call++].future);

        final f1 = provider.searchUsers('al'); // query A, generation 1
        final f2 = provider.searchUsers('bo'); // query B, generation 2
        final f3 = provider.searchUsers('al'); // query A again, generation 3

        // Resolve newest-first, then the older A completion LAST. If
        // ordering were decided by query-string equality, f1's 'al' result
        // would be accepted here because it matches the current query 'al';
        // only a generation check rejects it.
        cs[2].complete([searchResult(3)]);
        await f3;
        cs[1].complete([searchResult(2)]);
        await f2;
        cs[0].complete([searchResult(1)]);
        await f1;

        expect(provider.searchResults.single.userId, 3);
      },
    );

    test(
      '28: an older search completion cannot overwrite a newer query',
      () async {
        epoch.activate(1);
        final cOld = Completer<List<UserSearchResult>>();
        final cNew = Completer<List<UserSearchResult>>();
        var call = 0;
        when(
          repo.searchUsers(any),
        ).thenAnswer((_) => (call++ == 0) ? cOld.future : cNew.future);

        final fOld = provider.searchUsers('al');
        final fNew = provider.searchUsers('alice');

        cNew.complete([searchResult(10)]);
        await fNew;
        cOld.complete([searchResult(1)]);
        await fOld;

        expect(provider.searchResults.single.userId, 10);
      },
    );

    test('29: an older poll completion cannot overwrite a newer manual '
        'refresh of incoming requests', () async {
      epoch.activate(1);
      final poll = Completer<List<FriendRequest>>();
      final manual = Completer<List<FriendRequest>>();
      var call = 0;
      when(
        repo.getIncomingRequests(),
      ).thenAnswer((_) => (call++ == 0) ? poll.future : manual.future);

      final pollF = provider.loadIncomingRequests();
      final manualF = provider.loadIncomingRequests();

      manual.complete([request(2)]);
      await manualF;
      poll.complete([request(9)]);
      await pollF;

      expect(provider.incomingRequests.single.friendshipId, 2);
    });

    test('30: a stale refresh cannot reverse a newer accepted/declined/removed '
        'mutation', () async {
      epoch.activate(1);
      when(
        repo.getIncomingRequests(),
      ).thenAnswer((_) async => [request(11), request(12)]);
      await provider.loadIncomingRequests();

      // A refresh starts (will return the still-pending request 11)...
      final staleRefresh = Completer<List<FriendRequest>>();
      when(repo.getIncomingRequests()).thenAnswer((_) => staleRefresh.future);
      final refreshF = provider.loadIncomingRequests();

      // ...then the user declines request 11 and it completes first.
      expect(await provider.declineRequest(11), isTrue);
      expect(provider.incomingRequests.map((r) => r.friendshipId), [12]);

      // The stale refresh now resolves with 11 still present - it must not
      // resurrect it.
      staleRefresh.complete([request(11), request(12)]);
      await refreshF;

      expect(provider.incomingRequests.map((r) => r.friendshipId), [12]);
    });

    test(
      '31: overlapping mutations for different targets remain isolated',
      () async {
        epoch.activate(1);
        when(
          repo.getIncomingRequests(),
        ).thenAnswer((_) async => [request(11), request(12)]);
        await provider.loadIncomingRequests();

        final cA = Completer<void>();
        final cB = Completer<void>();
        when(repo.declineRequest(11)).thenAnswer((_) => cA.future);
        when(repo.declineRequest(12)).thenAnswer((_) => cB.future);

        final fA = provider.declineRequest(11);
        final fB = provider.declineRequest(12);

        cA.complete();
        expect(await fA, isTrue);
        cB.complete();
        expect(await fB, isTrue);

        expect(provider.incomingRequests, isEmpty);
      },
    );

    test('32: overlapping mutations for the same target resolve '
        'deterministically (last wins, older writes nothing)', () async {
      epoch.activate(1);
      when(repo.getFriends()).thenAnswer((_) async => [friend(3)]);
      await provider.loadFriends();

      final c1 = Completer<void>();
      final c2 = Completer<void>();
      var call = 0;
      when(
        repo.removeFriend(3),
      ).thenAnswer((_) => (call++ == 0) ? c1.future : c2.future);

      final f1 = provider.removeFriend(3);
      final f2 = provider.removeFriend(3);

      c2.complete();
      expect(await f2, isTrue);
      expect(provider.friends, isEmpty);
      final notifiesAfterS2 = notifyCount;

      c1.completeError(Exception('boom'));
      expect(await f1, isFalse);
      expect(provider.errorMessage, isNull);
      expect(notifyCount, notifiesAfterS2);
    });

    test('33: a stale failure rollback cannot undo a newer successful '
        'mutation to the same target', () async {
      epoch.activate(1);
      when(repo.getOutgoingRequests()).thenAnswer((_) async => [request(20)]);
      await provider.loadOutgoingRequests();

      final c1 = Completer<void>();
      final c2 = Completer<void>();
      var call = 0;
      when(
        repo.cancelFriendRequest(20),
      ).thenAnswer((_) => (call++ == 0) ? c1.future : c2.future);

      final f1 = provider.cancelFriendRequest(20);
      final f2 = provider.cancelFriendRequest(20);

      c2.complete();
      expect(await f2, isTrue);
      expect(provider.outgoingRequests, isEmpty);

      c1.completeError(Exception('network lost'));
      expect(await f1, isFalse);
      expect(provider.outgoingRequests, isEmpty);
      expect(provider.errorMessage, isNull);
    });

    test(
      'NB: a bare clear() (no epoch change) drops an in-flight mutation',
      () async {
        epoch.activate(1);
        final s = Completer<void>();
        when(repo.sendFriendRequest(7)).thenAnswer((_) => s.future);
        when(repo.searchUsers('xy')).thenAnswer((_) async => [searchResult(7)]);
        await provider.searchUsers('xy');

        final f = provider.sendFriendRequest(7);
        provider.clear(); // NOTE: no epoch.invalidate()

        s.complete();
        expect(await f, isFalse);
        expect(provider.searchResults, isEmpty);
      },
    );
  });

  // ================================================================
  // 34-42. Polling / timers
  // ================================================================

  group('polling', () {
    test('34: logged-out scheduling creates no timer', () {
      fakeAsync((async) {
        provider.startRequestPolling();
        expect(async.periodicTimerCount, 0);
        async.elapse(const Duration(seconds: 180));
        async.flushMicrotasks();
        verifyNever(repo.getIncomingRequests());
        expect(async.periodicTimerCount, 0);
      });
    });

    test('35: polling scheduled under A no-ops AND self-cancels after '
        'invalidation', () {
      fakeAsync((async) {
        epoch.activate(1);
        provider.startRequestPolling();
        async.flushMicrotasks();
        expect(async.periodicTimerCount, 1);
        clearInteractions(repo);

        epoch.invalidate();
        async.elapse(const Duration(seconds: 180));
        async.flushMicrotasks();

        verifyNever(repo.getIncomingRequests());
        // The stale timer must cancel ITSELF on its first tick, not keep
        // ticking (and re-checking) forever.
        expect(async.periodicTimerCount, 0);
      });
    });

    test('36: polling scheduled under A no-ops AND self-cancels after B '
        "login - it never recaptures B's session", () {
      fakeAsync((async) {
        epoch.activate(1);
        provider.startRequestPolling();
        async.flushMicrotasks();
        clearInteractions(repo);

        epoch.invalidate();
        epoch.activate(2);
        async.elapse(const Duration(seconds: 180));
        async.flushMicrotasks();

        verifyNever(repo.getIncomingRequests());
        expect(async.periodicTimerCount, 0);
      });
    });

    test("37: an old A timer callback cannot cancel B's replacement timer", () {
      fakeAsync((async) {
        epoch.activate(1);
        provider.startRequestPolling(); // A's timer (generation 1)
        async.flushMicrotasks();

        epoch.invalidate();
        epoch.activate(2);
        provider.startRequestPolling(); // B's timer
        async.flushMicrotasks();
        clearInteractions(repo);

        async.elapse(const Duration(seconds: 200));
        async.flushMicrotasks();

        verify(repo.getIncomingRequests()).called(greaterThanOrEqualTo(3));
      });
    });

    test('37b: a re-scheduled poll in the SAME session supersedes the old '
        'timer by generation - the leaked old timer self-cancels and only '
        'one poll runs per interval', () {
      fakeAsync((async) {
        epoch.activate(1);
        var maxConcurrent = 0;
        var inFlight = 0;
        when(repo.getIncomingRequests()).thenAnswer((_) {
          inFlight++;
          maxConcurrent = max(maxConcurrent, inFlight);
          return Future<List<FriendRequest>>.value(
            <FriendRequest>[],
          ).whenComplete(() => inFlight--);
        });

        provider.startRequestPolling(); // generation 1
        provider.startRequestPolling(); // generation 2 (old timer leaked)
        async.flushMicrotasks();
        clearInteractions(repo);

        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        // On its first tick the leaked generation-1 timer must recognise it
        // is superseded and cancel ITSELF, leaving exactly one live timer.
        expect(async.periodicTimerCount, 1);

        async.elapse(const Duration(seconds: 140));
        async.flushMicrotasks();

        // If the leaked generation-1 timer kept firing there would be two
        // polls per interval.
        expect(maxConcurrent, 1);
        verify(repo.getIncomingRequests()).called(3);
      });
    });

    test('38: polling does not overlap itself', () {
      fakeAsync((async) {
        epoch.activate(1);
        var inFlight = 0;
        var maxConcurrent = 0;
        final pending = <Completer<List<FriendRequest>>>[];
        when(repo.getIncomingRequests()).thenAnswer((_) {
          inFlight++;
          maxConcurrent = max(maxConcurrent, inFlight);
          final comp = Completer<List<FriendRequest>>();
          pending.add(comp);
          return comp.future.whenComplete(() => inFlight--);
        });

        provider.startRequestPolling();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(maxConcurrent, 1);

        for (final comp in pending) {
          if (!comp.isCompleted) comp.complete(<FriendRequest>[]);
        }
        async.flushMicrotasks();
      });
    });

    test('39: an in-flight poll resolving after clear() cannot repopulate', () {
      fakeAsync((async) {
        epoch.activate(1);
        final c = Completer<List<FriendRequest>>();
        when(repo.getIncomingRequests()).thenAnswer((_) => c.future);

        provider.startRequestPolling();
        async.elapse(
          const Duration(seconds: 60),
        ); // first tick -> poll in flight
        async.flushMicrotasks();

        provider.clear();
        c.complete([request(1), request(2)]);
        async.flushMicrotasks();

        expect(provider.incomingRequests, isEmpty);
      });
    });

    test('40: a stale poll cannot restart its timer', () {
      fakeAsync((async) {
        epoch.activate(1);
        provider.startRequestPolling();
        async.flushMicrotasks();

        epoch.invalidate();
        // Let several intervals pass; a stale tick must self-cancel and
        // never re-arm.
        async.elapse(const Duration(seconds: 300));
        async.flushMicrotasks();

        epoch.activate(2);
        clearInteractions(repo);
        async.elapse(const Duration(seconds: 300));
        async.flushMicrotasks();

        verifyNever(repo.getIncomingRequests());
      });
    });

    test('41: a manual refresh and a poll refresh have deterministic '
        'ordering (manual newer wins)', () {
      fakeAsync((async) {
        epoch.activate(1);
        final poll = Completer<List<FriendRequest>>();
        final manual = Completer<List<FriendRequest>>();
        var call = 0;
        when(
          repo.getIncomingRequests(),
        ).thenAnswer((_) => (call++ == 0) ? poll.future : manual.future);

        provider.startRequestPolling();
        async.elapse(const Duration(seconds: 60)); // tick -> call 0 (poll)
        async.flushMicrotasks();

        provider.loadIncomingRequests(); // call 1 (manual)
        manual.complete([request(2)]);
        async.flushMicrotasks();

        poll.complete([request(9)]);
        async.flushMicrotasks();

        expect(provider.incomingRequests.single.friendshipId, 2);
      });
    });

    test('42: dispose() prevents later timer callbacks and publication', () {
      fakeAsync((async) {
        epoch.activate(1);
        provider.startRequestPolling();
        async.flushMicrotasks();

        provider.dispose();
        clearInteractions(repo);

        async.elapse(const Duration(seconds: 300));
        async.flushMicrotasks();

        verifyNever(repo.getIncomingRequests());
      });
    });
  });

  // ================================================================
  // 43-48. Cleanup / regression
  // ================================================================

  group('cleanup and regression', () {
    test('43: clear() empties every Friends state field and stops polling', () {
      fakeAsync((async) {
        epoch.activate(1);
        when(repo.getFriends()).thenAnswer((_) async => [friend(7)]);
        when(repo.getIncomingRequests()).thenAnswer((_) async => [request(1)]);
        when(repo.getOutgoingRequests()).thenAnswer((_) async => [request(2)]);
        when(repo.searchUsers('ab')).thenAnswer((_) async => [searchResult(3)]);
        when(
          repo.getFriendshipStatus(4),
        ).thenAnswer((_) async => FriendshipStatus(status: 'friends'));
        when(repo.getPublicProfile(4)).thenAnswer((_) async => _profile(4));

        provider.loadAll();
        provider.searchUsers('ab');
        provider.loadPublicProfile(4);
        provider.startRequestPolling();
        async.flushMicrotasks();

        provider.clearError();
        provider.clear();
        clearInteractions(repo);

        async.elapse(const Duration(seconds: 180));
        async.flushMicrotasks();

        expect(provider.friends, isEmpty);
        expect(provider.incomingRequests, isEmpty);
        expect(provider.outgoingRequests, isEmpty);
        expect(provider.searchResults, isEmpty);
        expect(provider.selectedProfile, isNull);
        expect(provider.selectedProfileStatus, isNull);
        expect(provider.isLoading, isFalse);
        expect(provider.isSearching, isFalse);
        expect(provider.isLoadingProfile, isFalse);
        expect(provider.errorMessage, isNull);
        verifyNever(repo.getIncomingRequests());
      });
    });

    test('44: a bare clear() (no epoch invalidation) still invalidates '
        'in-flight Friends operations', () async {
      epoch.activate(1);
      final c = Completer<List<Friend>>();
      when(repo.getFriends()).thenAnswer((_) => c.future);

      final f = provider.loadFriends(showLoading: false);
      provider.clear(); // NOTE: no epoch.invalidate()

      c.complete([friend(5)]);
      await f;

      expect(provider.friends, isEmpty);
    });

    test(
      '45: a fresh User-B request after clear() succeeds normally',
      () async {
        epoch.activate(1);
        provider.clear();

        epoch.activate(2);
        when(repo.getFriends()).thenAnswer((_) async => [friend(42)]);
        await provider.loadFriends();

        expect(provider.friends.single.userId, 42);
      },
    );

    test('46: happy path within one session still works end to end', () async {
      epoch.activate(1);
      when(repo.getFriends()).thenAnswer((_) async => [friend(7), friend(8)]);
      when(repo.getIncomingRequests()).thenAnswer((_) async => [request(11)]);
      when(
        repo.getOutgoingRequests(),
      ).thenAnswer((_) async => <FriendRequest>[]);

      await provider.loadAll();
      expect(provider.friends, hasLength(2));
      expect(provider.pendingRequestCount, 1);

      expect(await provider.acceptRequest(11), isTrue);

      when(repo.searchUsers('bob')).thenAnswer((_) async => [searchResult(9)]);
      await provider.searchUsers('bob');
      expect(provider.searchResults.single.userId, 9);

      expect(await provider.sendFriendRequest(9), isTrue);
      expect(provider.searchResults, isEmpty);
    });

    test('47: clear() is idempotent', () {
      epoch.activate(1);
      provider.clear();
      provider.clear();
      expect(provider.friends, isEmpty);
      expect(provider.incomingRequests, isEmpty);
    });

    test(
      '48: loadPublicProfile stale completion cannot expose profile to B',
      () async {
        epoch.activate(1);
        final pc = Completer<PublicProfile>();
        final sc = Completer<FriendshipStatus>();
        when(repo.getPublicProfile(4)).thenAnswer((_) => pc.future);
        when(repo.getFriendshipStatus(4)).thenAnswer((_) => sc.future);

        final f = provider.loadPublicProfile(4);
        epoch.invalidate();
        provider.clear();
        epoch.activate(2);

        pc.complete(_profile(4));
        sc.complete(FriendshipStatus(status: 'friends'));
        await f;

        expect(provider.selectedProfile, isNull);
        expect(provider.isLoadingProfile, isFalse);
      },
    );
  });
}

PublicProfile _profile(int userId) => PublicProfile(
  userId: userId,
  username: 'u$userId',
  name: 'n$userId',
  memberSince: DateTime(2026, 1, 1),
  isFriend: false,
  sharedWorkoutsCount: 0,
);
