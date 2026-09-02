import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/goal.dart';
import 'package:go_hard_app/data/models/goal_progress.dart';
import 'package:go_hard_app/data/repositories/goals_repository.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';
import 'package:go_hard_app/providers/goals_provider.dart';

@GenerateMocks([GoalsRepository, ConnectivityService])
import 'goals_provider_session_ownership_test.mocks.dart';

/// Proves [GoalsProvider] never lets a repository result, error, or `finally`
/// cleanup started under user A land on the state user B now sees through
/// this same app-scoped provider instance; that within one session an older
/// request/mutation can never overwrite a newer one on the same resource;
/// and that [GoalsProvider.clear] invalidates every generation before
/// resetting state.
///
/// Real [UserSessionEpoch]; the repository is mocked so `Completer`s give
/// exact control over when each continuation resolves - no wall-clock delay,
/// no `Future.delayed`, no `Future.value()`/`pumpEventQueue`/`_settle` as a
/// pump, no `Timer`, no `sleep`. Ordering is synchronized only through
/// explicit `Completer.complete()` calls, awaiting the exact `Future` under
/// test, a `sync: true` broadcast `StreamController` and the
/// `onConnectivityRefreshForTesting` seam.
void main() {
  late MockGoalsRepository repo;
  late UserSessionEpoch epoch;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late GoalsProvider provider;
  late int notifyCount;

  Future<void>? connectivityRefresh;

  Goal goal(
    int id, {
    bool completed = false,
    bool active = true,
    double target = 150,
  }) => Goal(
    id: id,
    userId: 1,
    goalType: 'Weight',
    targetValue: target,
    currentValue: 200,
    startDate: DateTime(2024, 1, 1),
    isActive: active,
    isCompleted: completed,
    createdAt: DateTime(2024, 1, 1),
  );

  GoalProgress progress(int id, {double value = 5}) => GoalProgress(
    id: id,
    goalId: 1,
    recordedAt: DateTime(2024, 1, 1),
    value: value,
  );

  void stubDefaults() {
    when(
      repo.getGoals(isActive: anyNamed('isActive')),
    ).thenAnswer((_) async => <Goal>[]);
    when(repo.getGoalById(any)).thenAnswer((_) async => goal(1));
    // Echo the submitted goal back so multi-goal tests get distinct rows.
    when(
      repo.createGoal(any),
    ).thenAnswer((inv) async => inv.positionalArguments[0] as Goal);
    when(repo.addProgress(any, any)).thenAnswer((_) async => progress(1));
    when(
      repo.getProgressHistory(any),
    ).thenAnswer((_) async => <GoalProgress>[]);
    when(
      repo.getDeletionImpact(any),
    ).thenAnswer((_) async => {'programsCount': 0, 'sessionsCount': 0});
    // updateGoal / deleteGoal / completeGoal are intentionally NOT stubbed:
    // the generated mock supplies a completed void future for a missing
    // stub, and tests that care about timing install their own Completer.
  }

  setUp(() {
    repo = MockGoalsRepository();
    stubDefaults();
    epoch = UserSessionEpoch();
    connectivity = MockConnectivityService();
    connectivityController = StreamController<bool>.broadcast(sync: true);
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    provider = GoalsProvider(repo, epoch, connectivity);
    connectivityRefresh = null;
    provider.onConnectivityRefreshForTesting = (f) => connectivityRefresh = f;
    notifyCount = 0;
    provider.addListener(() => notifyCount++);
  });

  tearDown(() async {
    try {
      provider.dispose();
    } catch (_) {
      // Some tests dispose explicitly; a second dispose asserts.
    }
    await connectivityController.close();
  });

  // Seeds the goals list with one real row (id [id]) via the optimistic
  // create path, under the currently-active session.
  Future<void> seedGoal(int id) async {
    when(repo.createGoal(any)).thenAnswer((_) async => goal(id));
    await provider.createGoal(goal(id));
    stubDefaults();
  }

  // ================================================================
  // Repository binding is proven in
  // goals_repository_session_ownership_test.dart. Items 1-10 there.
  // ================================================================

  // ================================================================
  // 11-24. Cross-session Provider protection
  // ================================================================

  group('cross-session protection', () {
    test('11: a slow loadGoals completing after clear() cannot repopulate the '
        'cleared list and does not notify', () async {
      epoch.activate(1);
      final c = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadGoals();
      epoch.invalidate();
      provider.clear();
      final notifiesBefore = notifyCount;

      c.complete([goal(1)]);
      await f;

      expect(provider.goals, isEmpty);
      expect(notifyCount, notifiesBefore);
    });

    test(
      '12: the same completion after user B logs in cannot overwrite B',
      () async {
        epoch.activate(1);
        final aC = Completer<List<Goal>>();
        final bC = Completer<List<Goal>>();
        var call = 0;
        when(
          repo.getGoals(isActive: anyNamed('isActive')),
        ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

        final aF = provider.loadGoals();
        epoch.invalidate();
        epoch.activate(2);
        final bF = provider.loadGoals();

        bC.complete([goal(9)]);
        await bF;
        expect(provider.goals.single.id, 9);

        aC.complete([goal(1)]);
        await aF;

        expect(provider.goals.single.id, 9);
      },
    );

    test('13: a stale getGoalById result never reaches its caller once the '
        'session has ended', () async {
      epoch.activate(1);
      final c = Completer<Goal>();
      when(repo.getGoalById(1)).thenAnswer((_) => c.future);

      final f = provider.getGoalById(1);
      epoch.invalidate();

      c.complete(goal(1));
      final result = await f;

      expect(result, isNull);
      expect(provider.errorMessage, isNull);
    });

    test('14: a stale getProgressHistory result never reaches its caller once '
        'the session has ended', () async {
      epoch.activate(1);
      final c = Completer<List<GoalProgress>>();
      when(repo.getProgressHistory(1)).thenAnswer((_) => c.future);

      final f = provider.getProgressHistory(1);
      epoch.invalidate();

      c.complete([progress(1)]);
      final result = await f;

      expect(result, isEmpty);
    });

    test('15: a stale getDeletionImpact throws SessionStaleException rather '
        'than returning stale counts', () async {
      epoch.activate(1);
      final c = Completer<Map<String, int>>();
      when(repo.getDeletionImpact(1)).thenAnswer((_) => c.future);

      final f = provider.getDeletionImpact(1);
      epoch.invalidate();

      c.complete({'programsCount': 5, 'sessionsCount': 5});
      await expectLater(f, throwsA(isA<SessionStaleException>()));
    });

    test('16: a stale createGoal success cannot append into B', () async {
      epoch.activate(1);
      final c = Completer<Goal>();
      when(repo.createGoal(any)).thenAnswer((_) => c.future);

      final f = provider.createGoal(goal(1));
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete(goal(1));
      final result = await f;

      expect(result, isNull);
      expect(provider.goals, isEmpty);
    });

    test('17: a stale updateGoal success cannot modify B', () async {
      epoch.activate(1);
      await seedGoal(1);
      final c = Completer<void>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateGoal(1, goal(1, target: 40));
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete();
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.goals, isEmpty);
    });

    test('18: a stale deleteGoal success cannot remove from B', () async {
      epoch.activate(1);
      final c = Completer<void>();
      when(repo.deleteGoal(1)).thenAnswer((_) => c.future);

      await seedGoal(1);
      final f = provider.deleteGoal(1);
      epoch.invalidate();
      epoch.activate(2);
      await seedGoal(1); // B creates their own id-1 goal

      c.complete();
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.goals, hasLength(1)); // B's row survives
    });

    test('19: a stale completeGoal success cannot modify B', () async {
      epoch.activate(1);
      await seedGoal(1);
      final c = Completer<void>();
      when(repo.completeGoal(1)).thenAnswer((_) => c.future);

      final f = provider.completeGoal(1);
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete();
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.goals, isEmpty);
    });

    test(
      '20: a stale addProgress success cannot modify B (no reload into B)',
      () async {
        epoch.activate(1);
        final c = Completer<GoalProgress>();
        when(repo.addProgress(1, any)).thenAnswer((_) => c.future);

        final f = provider.addProgress(1, progress(1));
        epoch.invalidate();
        provider.clear();
        epoch.activate(2);

        c.complete(progress(1));
        final ok = await f;

        expect(ok, isFalse);
        expect(provider.goals, isEmpty);
        verifyNever(repo.getGoals(isActive: anyNamed('isActive')));
      },
    );

    test('21: a stale mutation failure/rollback cannot modify B', () async {
      epoch.activate(1);
      await seedGoal(1);
      final c = Completer<void>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateGoal(1, goal(1, target: 40));
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);
      await seedGoal(5); // B's own list

      c.completeError(Exception('boom'));
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.goals.single.id, 5); // B's row untouched
      expect(provider.errorMessage, isNull);
    });

    test("22: a stale loadGoals catch cannot set B's error", () async {
      epoch.activate(1);
      final c = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadGoals();
      epoch.invalidate();
      epoch.activate(2);

      c.completeError(Exception('network down'));
      await f;

      expect(provider.errorMessage, isNull);
    });

    test("23: a stale finally cannot clear B's newer loading flag", () async {
      epoch.activate(1);
      final aC = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => aC.future);
      final aF = provider.loadGoals();

      epoch.invalidate();
      epoch.activate(2);
      final bC = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => bC.future);
      // ignore: unawaited_futures
      provider.loadGoals(); // B's own load - still spinning
      expect(provider.isLoading, isTrue);

      aC.complete([goal(1)]); // A's stale load resolves
      await aF;

      expect(provider.isLoading, isTrue); // A's finally must not clear it
      bC.complete([]);
    });

    test('24: stale continuations never call notifyListeners()', () async {
      epoch.activate(1);
      final listC = Completer<List<Goal>>();
      final detailC = Completer<Goal>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => listC.future);
      when(repo.getGoalById(any)).thenAnswer((_) => detailC.future);

      final listF = provider.loadGoals();
      final detailF = provider.getGoalById(1);
      epoch.invalidate();
      final notifiesAtInvalidate = notifyCount;

      listC.complete([goal(1)]);
      detailC.complete(goal(1));
      await listF;
      await detailF;

      expect(notifyCount, notifiesAtInvalidate);
    });
  });

  // ================================================================
  // 25-38. Same-session ordering
  // ================================================================

  group('same-session ordering', () {
    test('25: an older list request completing last loses', () async {
      epoch.activate(1);
      final first = Completer<List<Goal>>();
      final second = Completer<List<Goal>>();
      var call = 0;
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => (call++ == 0) ? first.future : second.future);

      final f1 = provider.loadGoals();
      final f2 = provider.loadGoals();

      second.complete([goal(2)]);
      await f2;
      first.complete([goal(1)]); // stale, resolves last
      await f1;

      expect(provider.goals.map((g) => g.id), [2]);
    });

    test('26: getGoalById A completing after B loses (error axis)', () async {
      epoch.activate(1);
      final first = Completer<Goal>(); // detail for goal 5
      final second = Completer<Goal>(); // detail for goal 7
      when(repo.getGoalById(5)).thenAnswer((_) => first.future);
      when(repo.getGoalById(7)).thenAnswer((_) => second.future);

      final f1 = provider.getGoalById(5);
      final f2 = provider.getGoalById(7);

      second.completeError(Exception('goal 7 not found'));
      await f2;
      expect(provider.errorMessage, contains('goal 7'));

      first.completeError(Exception('goal 5 stale error')); // resolves last
      await f1;

      expect(provider.errorMessage, contains('goal 7'));
    });

    test('27: getGoalById A -> B -> A resolves through generation identity, '
        'not id equality', () async {
      epoch.activate(1);
      final firstA = Completer<Goal>();
      final b = Completer<Goal>();
      final secondA = Completer<Goal>();
      var call = 0;
      when(
        repo.getGoalById(5),
      ).thenAnswer((_) => (call++ == 0) ? firstA.future : secondA.future);
      when(repo.getGoalById(7)).thenAnswer((_) => b.future);

      final f1 = provider.getGoalById(5); // A
      final f2 = provider.getGoalById(7); // B
      final f3 = provider.getGoalById(5); // A again - newest owner

      secondA.completeError(Exception('third call, newest'));
      await f3;
      expect(provider.errorMessage, contains('newest'));

      b.completeError(Exception('second call, stale'));
      await f2;
      expect(provider.errorMessage, contains('newest'));

      firstA.completeError(Exception('first call, stale, same id as f3'));
      await f1;
      expect(provider.errorMessage, contains('newest'));
    });

    test(
      '28: an older getProgressHistory request loses (error axis)',
      () async {
        epoch.activate(1);
        final first = Completer<List<GoalProgress>>();
        final second = Completer<List<GoalProgress>>();
        var call = 0;
        when(
          repo.getProgressHistory(any),
        ).thenAnswer((_) => (call++ == 0) ? first.future : second.future);

        final f1 = provider.getProgressHistory(5);
        final f2 = provider.getProgressHistory(7);

        second.completeError(Exception('history 7 failed'));
        await f2;
        expect(provider.errorMessage, contains('history 7'));

        first.completeError(Exception('history 5 stale'));
        await f1;

        expect(provider.errorMessage, contains('history 7'));
      },
    );

    test(
      '29: an older getDeletionImpact request loses (newer supersedes)',
      () async {
        epoch.activate(1);
        final first = Completer<Map<String, int>>();
        final second = Completer<Map<String, int>>();
        var call = 0;
        when(
          repo.getDeletionImpact(any),
        ).thenAnswer((_) => (call++ == 0) ? first.future : second.future);

        final f1 = provider.getDeletionImpact(5);
        final f2 = provider.getDeletionImpact(7);

        second.complete({'programsCount': 7, 'sessionsCount': 7});
        expect(await f2, {'programsCount': 7, 'sessionsCount': 7});

        first.complete({'programsCount': 5, 'sessionsCount': 5}); // stale
        await expectLater(f1, throwsA(isA<SessionStaleException>()));
      },
    );

    test('30: a connectivity-triggered refresh cannot overwrite a newer manual '
        'refresh', () async {
      epoch.activate(1);
      final connectivityLoad = Completer<List<Goal>>();
      final manualLoad = Completer<List<Goal>>();
      var call = 0;
      when(repo.getGoals(isActive: anyNamed('isActive'))).thenAnswer(
        (_) => (call++ == 0) ? connectivityLoad.future : manualLoad.future,
      );

      connectivityController.add(true);
      expect(connectivityRefresh, isNotNull);
      final manualFuture = provider.loadGoals(); // newer, manual

      manualLoad.complete([goal(2)]);
      await manualFuture;
      connectivityLoad.complete([goal(1)]); // stale
      await connectivityRefresh;

      expect(provider.goals.map((g) => g.id), [2]);
    });

    test(
      '31: a stale list refresh cannot overwrite a newer delete mutation',
      () async {
        epoch.activate(1);
        await seedGoal(1);
        final refresh = Completer<List<Goal>>();
        when(
          repo.getGoals(isActive: anyNamed('isActive')),
        ).thenAnswer((_) => refresh.future);

        final refreshFuture = provider.loadGoals(); // slow refresh
        await provider.deleteGoal(1); // fast mutation, completes first
        expect(provider.goals, isEmpty);

        refresh.complete([goal(1)]); // stale snapshot still has goal 1
        await refreshFuture;

        expect(provider.goals, isEmpty); // delete's result survives
      },
    );

    test('32: a late update cannot resurrect a goal whose newer delete '
        'completed', () async {
      epoch.activate(1);
      await seedGoal(1);
      final updateC = Completer<void>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => updateC.future);

      final updateFuture = provider.updateGoal(1, goal(1, target: 40));
      await provider.deleteGoal(1); // newer, completes first
      expect(provider.goals, isEmpty);

      updateC.complete(); // older update resolves after the delete
      final ok = await updateFuture;

      expect(ok, isFalse);
      expect(provider.goals, isEmpty); // must not resurrect
    });

    test('33: an older update cannot undo a newer completion', () async {
      epoch.activate(1);
      await seedGoal(1);
      final updateC = Completer<void>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => updateC.future);

      final updateFuture = provider.updateGoal(
        1,
        goal(1, target: 40),
      ); // older, still in flight
      await provider.completeGoal(1); // newer, completes first
      expect(provider.goals.single.isCompleted, isTrue);

      updateC.complete(); // older update resolves
      final ok = await updateFuture;

      expect(ok, isFalse);
      expect(provider.goals.single.isCompleted, isTrue); // completion survives
    });

    test('34: an older addProgress acknowledgment cannot overwrite newer goal '
        'state', () async {
      epoch.activate(1);
      await seedGoal(1);
      final addC = Completer<GoalProgress>();
      when(repo.addProgress(1, any)).thenAnswer((_) => addC.future);

      final addFuture = provider.addProgress(1, progress(1)); // older
      await provider.deleteGoal(1); // newer, completes first
      expect(provider.goals, isEmpty);

      addC.complete(progress(1));
      final ok = await addFuture;

      expect(ok, isFalse);
      expect(provider.goals, isEmpty);
      // The stale addProgress must NOT have triggered its reload.
      verifyNever(repo.getGoals(isActive: anyNamed('isActive')));
    });

    test('35: optimistic rollback belongs to its exact operation', () async {
      epoch.activate(1);
      await seedGoal(1);
      final failing = Completer<void>();
      final succeeding = Completer<void>();
      var call = 0;
      when(
        repo.updateGoal(1, any),
      ).thenAnswer((_) => (call++ == 0) ? failing.future : succeeding.future);

      final f1 = provider.updateGoal(1, goal(1, target: 10)); // stale
      final f2 = provider.updateGoal(1, goal(1, target: 20)); // newest

      succeeding.complete();
      expect(await f2, isTrue);
      expect(provider.goals.single.targetValue, 20);

      failing.completeError(Exception('stale failure'));
      expect(await f1, isFalse);

      // The stale failure must not roll back over the newer success.
      expect(provider.goals.single.targetValue, 20);
      expect(provider.errorMessage, isNull);
    });

    test(
      '36: concurrent mutations to different goals remain independent',
      () async {
        epoch.activate(1);
        await seedGoal(1);
        await seedGoal(2);
        final c1 = Completer<void>();
        final c2 = Completer<void>();
        when(repo.updateGoal(1, any)).thenAnswer((_) => c1.future);
        when(repo.updateGoal(2, any)).thenAnswer((_) => c2.future);

        final f1 = provider.updateGoal(1, goal(1, target: 11));
        final f2 = provider.updateGoal(2, goal(2, target: 22));

        c2.complete();
        expect(await f2, isTrue);
        c1.complete();
        expect(await f1, isTrue);

        expect(provider.goals.firstWhere((g) => g.id == 1).targetValue, 11);
        expect(provider.goals.firstWhere((g) => g.id == 2).targetValue, 22);
      },
    );

    test('37: same-goal update replacement is ordered correctly', () async {
      epoch.activate(1);
      await seedGoal(1);
      final older = Completer<void>();
      final newer = Completer<void>();
      var call = 0;
      when(
        repo.updateGoal(1, any),
      ).thenAnswer((_) => (call++ == 0) ? older.future : newer.future);

      final fOld = provider.updateGoal(1, goal(1, target: 10));
      final fNew = provider.updateGoal(1, goal(1, target: 99));

      newer.complete();
      expect(await fNew, isTrue);
      expect(provider.goals.single.targetValue, 99);

      older.complete(); // resolves last, superseded
      expect(await fOld, isFalse);
      expect(provider.goals.single.targetValue, 99); // newest value survives
    });

    test(
      '38: shared error is last-claimant-owned across operation axes',
      () async {
        epoch.activate(1);
        final detailC = Completer<Goal>();
        final listC = Completer<List<Goal>>();
        when(repo.getGoalById(7)).thenAnswer((_) => detailC.future);
        when(
          repo.getGoals(isActive: anyNamed('isActive')),
        ).thenAnswer((_) => listC.future);

        final detailF = provider.getGoalById(7); // older, axis = detail
        final listF = provider.loadGoals(); // newer, axis = list

        listC.completeError(Exception('list request failed'));
        await listF;
        expect(provider.errorMessage, contains('list request'));

        detailC.completeError(Exception('stale detail failure'));
        await detailF;

        expect(provider.errorMessage, contains('list request'));
      },
    );
  });

  // ================================================================
  // 39-44. Optimistic mutation ownership
  // ================================================================

  group('optimistic mutation ownership', () {
    test('39: a stale update failure cannot restore a deleted goal', () async {
      epoch.activate(1);
      await seedGoal(1);
      final updateC = Completer<void>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => updateC.future);

      final updateF = provider.updateGoal(1, goal(1, target: 40));
      await provider.deleteGoal(1); // newer delete wins
      expect(provider.goals, isEmpty);

      updateC.completeError(Exception('update failed'));
      expect(await updateF, isFalse);

      expect(provider.goals, isEmpty); // rollback must not resurrect
    });

    test('40: a stale delete failure cannot reinsert into another user\'s '
        'list', () async {
      epoch.activate(1);
      await seedGoal(1);
      final deleteC = Completer<void>();
      when(repo.deleteGoal(1)).thenAnswer((_) => deleteC.future);

      final deleteF = provider.deleteGoal(1);
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);
      await seedGoal(5); // B's list

      deleteC.completeError(Exception('delete failed'));
      expect(await deleteF, isFalse);

      expect(provider.goals.map((g) => g.id), [5]); // no id-1 reinserted
    });

    test('41: create failure removes only its own optimistic placeholder, not '
        'a newer independently-created goal', () async {
      epoch.activate(1);
      final firstC = Completer<Goal>();
      final secondC = Completer<Goal>();
      var call = 0;
      when(
        repo.createGoal(any),
      ).thenAnswer((_) => (call++ == 0) ? firstC.future : secondC.future);

      final f1 = provider.createGoal(goal(1)); // optimistic temp id -1
      final f2 = provider.createGoal(goal(2)); // optimistic temp id -2
      expect(provider.goals, hasLength(2));

      secondC.complete(goal(2));
      expect((await f2)!.id, 2);
      expect(provider.goals.map((g) => g.id), containsAll(<int>[2]));

      firstC.completeError(Exception('create 1 failed'));
      expect(await f1, isNull);

      // The newer create's row (id 2) must survive; only the failed create's
      // own placeholder is gone.
      expect(provider.goals.map((g) => g.id), [2]);
    });

    test(
      '42: a superseded older create cleaning up its own placeholder does '
      'NOT disturb a newer create still in flight (proves unique tempIds - '
      'a shared constant id would remove the newer placeholder too)',
      () async {
        epoch.activate(1);
        final firstC = Completer<Goal>();
        final secondC = Completer<Goal>(); // deliberately never completed here
        var call = 0;
        when(
          repo.createGoal(any),
        ).thenAnswer((_) => (call++ == 0) ? firstC.future : secondC.future);

        final f1 = provider.createGoal(goal(1)); // older, temp id -1
        // ignore: unawaited_futures
        provider.createGoal(goal(2)); // newer, still in flight, temp id -2
        expect(provider.goals, hasLength(2));

        firstC.complete(goal(1)); // older resolves, superseded -> owns() false
        expect(await f1, isNull);

        // The newer create's optimistic placeholder must still be there: exactly
        // one row, and it is the still-pending negative-id placeholder.
        expect(provider.goals, hasLength(1));
        expect(provider.goals.single.id, isNegative);
        secondC.complete(goal(2)); // let the newer create finish cleanly
      },
    );

    test('42b: clear() during an in-flight createGoal - the failing '
        'continuation cleans its placeholder but publishes nothing', () async {
      epoch.activate(1);
      final c = Completer<Goal>();
      when(repo.createGoal(any)).thenAnswer((_) => c.future);

      final f = provider.createGoal(goal(1));
      provider.clear(); // bare clear(), no epoch.invalidate()
      final notifiesAfterClear = notifyCount;

      c.completeError(Exception('create failed'));
      expect(await f, isNull);

      expect(provider.goals, isEmpty);
      expect(provider.errorMessage, isNull);
      expect(notifyCount, notifiesAfterClear); // no publish after clear()
    });

    test(
      '42c: dispose() during an in-flight createGoal - the failing '
      'continuation never calls notifyListeners() on the disposed notifier',
      () async {
        epoch.activate(1);
        final c = Completer<Goal>();
        when(repo.createGoal(any)).thenAnswer((_) => c.future);

        final f = provider.createGoal(goal(1));
        provider.dispose(); // bare dispose(), session still active
        final notifiesAfterDispose = notifyCount;

        c.completeError(Exception('create failed'));
        // No FlutterError('used after being disposed') is thrown.
        expect(await f, isNull);
        expect(notifyCount, notifiesAfterDispose);
      },
    );

    test(
      '42d: a lifecycle exception from createGoal after dispose() cleans the '
      'placeholder without notifying the disposed notifier',
      () async {
        epoch.activate(1);
        final c = Completer<Goal>();
        when(repo.createGoal(any)).thenAnswer((_) => c.future);

        final f = provider.createGoal(goal(1));
        provider.dispose();
        final notifiesAfterDispose = notifyCount;

        c.completeError(const SessionStaleException());
        expect(await f, isNull);
        // _discardOptimisticCreate is called with owns=false -> no notify.
        expect(notifyCount, notifiesAfterDispose);
      },
    );

    test(
      '43: a progress rollback is not applied over a newer goal state',
      () async {
        epoch.activate(1);
        await seedGoal(1);
        final addC = Completer<GoalProgress>();
        when(repo.addProgress(1, any)).thenAnswer((_) => addC.future);

        final addF = provider.addProgress(1, progress(1));
        await provider.completeGoal(1); // newer mutation on goal 1
        expect(provider.goals.single.isCompleted, isTrue);

        addC.completeError(Exception('add progress failed'));
        expect(await addF, isFalse);

        // addProgress shares the per-goal mutation gen; superseded -> no error,
        // no state change.
        expect(provider.goals.single.isCompleted, isTrue);
        expect(provider.errorMessage, isNull);
      },
    );

    test('44: updateGoal on a missing goal reports "Goal not found" without a '
        'repository call', () async {
      epoch.activate(1);
      final ok = await provider.updateGoal(42, goal(42));
      expect(ok, isFalse);
      expect(provider.errorMessage, 'Goal not found');
      verifyNever(repo.updateGoal(any, any));
    });
  });

  // ================================================================
  // 45-49. Connectivity and cleanup
  // ================================================================

  group('connectivity and cleanup', () {
    test(
      '45: a logged-out connectivity event performs no repository call',
      () async {
        // No epoch.activate() - stays logged out throughout.
        connectivityController.add(true);

        expect(connectivityRefresh, isNull);
        verifyNever(repo.getGoals(isActive: anyNamed('isActive')));
        expect(provider.isLoading, isFalse);
      },
    );

    test('46: a connectivity event uses the real Provider load path', () async {
      epoch.activate(1);
      final c = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => c.future);

      connectivityController.add(true);
      expect(connectivityRefresh, isNotNull);
      expect(provider.isLoading, isTrue); // loadGoals() entered

      c.complete([goal(1)]);
      await connectivityRefresh;
      expect(provider.goals.single.id, 1);
    });

    test('47: an in-flight connectivity refresh after clear() cannot '
        'repopulate', () async {
      epoch.activate(1);
      final c = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => c.future);

      connectivityController.add(true);
      expect(connectivityRefresh, isNotNull);
      provider.clear();

      c.complete([goal(1)]);
      await connectivityRefresh;

      expect(provider.goals, isEmpty);
    });

    test(
      '48: clear() invalidates an in-flight load without an epoch change',
      () async {
        epoch.activate(1);
        final c = Completer<List<Goal>>();
        when(
          repo.getGoals(isActive: anyNamed('isActive')),
        ).thenAnswer((_) => c.future);

        final f = provider.loadGoals();
        provider.clear(); // no epoch.invalidate()

        c.complete([goal(1)]);
        await f;

        expect(provider.goals, isEmpty);
        expect(epoch.isCurrent(epoch.capture()!), isTrue); // epoch untouched
      },
    );

    test('49: clear() invalidates an in-flight mutation without an epoch '
        'change', () async {
      epoch.activate(1);
      await seedGoal(1);
      final c = Completer<void>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateGoal(1, goal(1, target: 40));
      provider.clear();

      c.complete();
      final ok = await f;

      expect(ok, isFalse);
      expect(provider.goals, isEmpty);
    });

    test(
      '50: clear() empties the SAME list instance a caller already holds',
      () async {
        epoch.activate(1);
        await seedGoal(1);
        final held = provider.goals;

        provider.clear();

        expect(held, isEmpty);
        expect(identical(held, provider.goals), isTrue);
      },
    );

    test('51: dispose() prevents later state publication', () async {
      epoch.activate(1);
      final c = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadGoals();
      provider.dispose();

      c.complete([goal(1)]);
      await f;

      expect(provider.goals, isEmpty);
    });

    test('52: clearError() claims the error slot so an older in-flight failure '
        'cannot re-populate the dismissed error', () async {
      epoch.activate(1);
      final detailC = Completer<Goal>();
      when(repo.getGoalById(1)).thenAnswer((_) => detailC.future);

      final f = provider.getGoalById(1);
      provider.clearError(); // user dismisses; newer slot claim

      detailC.completeError(Exception('stale detail failure'));
      await f;

      expect(provider.errorMessage, isNull);
    });

    test(
      '53: SessionCleanupCoordinator-style clear() resets every axis',
      () async {
        epoch.activate(1);
        await seedGoal(1);
        expect(provider.goals, isNotEmpty);

        provider.clear();

        expect(provider.goals, isEmpty);
        expect(provider.errorMessage, isNull);
        expect(provider.isLoading, isFalse);
      },
    );
  });

  // ================================================================
  // 54-65. Adversarial "Order B": optimistic mutation applies, THEN a
  // loadGoals() both starts AND completes (returning the pre-mutation
  // server list) BEFORE the mutation's own HTTP acknowledgment lands.
  // The owned-success continuation must re-converge the list.
  //
  // Completers are tied directly to the repository Futures; ordering is
  // driven only by explicit .complete() + awaiting the exact Future.
  // ================================================================

  group('adversarial refresh-then-ack convergence (Order B)', () {
    test('54: createGoal - refresh wipes the temp placeholder before the POST '
        'ack; final list is exactly the one returned server row', () async {
      epoch.activate(1);
      final createC = Completer<Goal>();
      final refreshC = Completer<List<Goal>>();
      when(repo.createGoal(any)).thenAnswer((_) => createC.future);
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final createF = provider.createGoal(goal(7)); // optimistic temp row
      expect(provider.goals.single.id, isNegative);

      final refreshF = provider.loadGoals(); // starts AFTER the optimistic add
      refreshC.complete(<Goal>[]); // server has not processed the create yet
      await refreshF;
      expect(provider.goals, isEmpty); // placeholder wiped

      createC.complete(goal(7));
      final result = await createF;

      expect(result!.id, 7);
      expect(provider.goals.map((g) => g.id), [7]); // inserted, no temp dup
      expect(provider.goals.where((g) => g.id < 0), isEmpty);
    });

    test('55: updateGoal - refresh restores the old value before the PUT ack; '
        'final list holds the intended updated value', () async {
      epoch.activate(1);
      await seedGoal(1); // goal(1) target 150
      final updateC = Completer<void>();
      final refreshC = Completer<List<Goal>>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => updateC.future);
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final updateF = provider.updateGoal(1, goal(1, target: 40));
      expect(provider.goals.single.targetValue, 40); // optimistic

      final refreshF = provider.loadGoals();
      refreshC.complete([goal(1)]); // old server row, target 150
      await refreshF;
      expect(provider.goals.single.targetValue, 150); // optimistic displaced

      updateC.complete();
      final ok = await updateF;

      expect(ok, isTrue);
      expect(provider.goals.single.targetValue, 40); // re-converged
      expect(provider.goals, hasLength(1));
    });

    test('56: deleteGoal - refresh resurrects the row before the DELETE ack; '
        'final list does not contain the deleted id', () async {
      epoch.activate(1);
      await seedGoal(1);
      final deleteC = Completer<void>();
      final refreshC = Completer<List<Goal>>();
      when(repo.deleteGoal(1)).thenAnswer((_) => deleteC.future);
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final deleteF = provider.deleteGoal(1);
      expect(provider.goals, isEmpty); // optimistic removal

      final refreshF = provider.loadGoals();
      refreshC.complete([goal(1)]); // resurrects
      await refreshF;
      expect(provider.goals, hasLength(1));

      deleteC.complete();
      final ok = await deleteF;

      expect(ok, isTrue);
      expect(provider.goals.where((g) => g.id == 1), isEmpty); // re-removed
    });

    test('57: completeGoal - refresh restores the incomplete row before the '
        'complete ack; final list stays completed', () async {
      epoch.activate(1);
      await seedGoal(1); // active, not completed
      final completeC = Completer<void>();
      final refreshC = Completer<List<Goal>>();
      when(repo.completeGoal(1)).thenAnswer((_) => completeC.future);
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final completeF = provider.completeGoal(1);
      expect(provider.goals.single.isCompleted, isTrue); // optimistic

      final refreshF = provider.loadGoals();
      refreshC.complete([goal(1)]); // incomplete server row
      await refreshF;
      expect(provider.goals.single.isCompleted, isFalse); // displaced

      completeC.complete();
      final ok = await completeF;

      expect(ok, isTrue);
      expect(provider.goals.single.isCompleted, isTrue); // re-converged
      expect(provider.goals.single.isActive, isFalse);
    });

    test(
      '58: a newer same-goal update makes the older Order-B ack lose',
      () async {
        epoch.activate(1);
        await seedGoal(1);
        final olderC = Completer<void>();
        final newerC = Completer<void>();
        var call = 0;
        when(
          repo.updateGoal(1, any),
        ).thenAnswer((_) => (call++ == 0) ? olderC.future : newerC.future);
        final refreshC = Completer<List<Goal>>();
        when(
          repo.getGoals(isActive: anyNamed('isActive')),
        ).thenAnswer((_) => refreshC.future);

        final olderF = provider.updateGoal(1, goal(1, target: 40)); // older
        final refreshF = provider.loadGoals();
        refreshC.complete([goal(1)]);
        await refreshF;
        final newerF = provider.updateGoal(1, goal(1, target: 99)); // newer

        // Newer ack lands FIRST and converges to 99.
        newerC.complete();
        expect(await newerF, isTrue);
        expect(provider.goals.single.targetValue, 99);

        // Older ack lands LAST: it is superseded (per-goal generation bumped
        // by the newer update), so its owned-only reapplication must do
        // nothing - 99 must survive, not revert to 40.
        olderC.complete();
        expect(await olderF, isFalse);
        expect(provider.goals.single.targetValue, 99);
      },
    );

    test(
      '59: Order-B timeline crossing clear()/User-B does not publish into B',
      () async {
        epoch.activate(1);
        await seedGoal(1);
        final updateC = Completer<void>();
        final refreshC = Completer<List<Goal>>();
        when(repo.updateGoal(1, any)).thenAnswer((_) => updateC.future);
        when(
          repo.getGoals(isActive: anyNamed('isActive')),
        ).thenAnswer((_) => refreshC.future);

        final updateF = provider.updateGoal(1, goal(1, target: 40));
        final refreshF = provider.loadGoals();
        refreshC.complete([goal(1)]);
        await refreshF;

        epoch.invalidate();
        provider.clear();
        epoch.activate(2);
        final notifiesAfterClear = notifyCount;

        updateC.complete();
        expect(await updateF, isFalse);

        expect(provider.goals, isEmpty);
        expect(notifyCount, notifiesAfterClear); // no publish into B
      },
    );

    test('60: Order-B acks for different goals stay independent', () async {
      epoch.activate(1);
      await seedGoal(1);
      await seedGoal(2);
      final c1 = Completer<void>();
      final c2 = Completer<void>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => c1.future);
      when(repo.updateGoal(2, any)).thenAnswer((_) => c2.future);
      final refreshC = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final f1 = provider.updateGoal(1, goal(1, target: 11));
      final f2 = provider.updateGoal(2, goal(2, target: 22));
      final refreshF = provider.loadGoals();
      refreshC.complete([goal(1), goal(2)]); // both restored to 150
      await refreshF;

      c1.complete();
      expect(await f1, isTrue);
      // Goal 1's ack re-converged goal 1 only; goal 2 still the refreshed 150.
      expect(provider.goals.firstWhere((g) => g.id == 1).targetValue, 11);
      expect(provider.goals.firstWhere((g) => g.id == 2).targetValue, 150);

      c2.complete();
      expect(await f2, isTrue);
      expect(provider.goals.firstWhere((g) => g.id == 1).targetValue, 11);
      expect(provider.goals.firstWhere((g) => g.id == 2).targetValue, 22);
    });

    test('60b: an Order-B delete ack for Goal A removes only Goal A; Goal B '
        'survives', () async {
      epoch.activate(1);
      await seedGoal(1);
      await seedGoal(2);
      final deleteC = Completer<void>();
      when(repo.deleteGoal(1)).thenAnswer((_) => deleteC.future);
      final refreshC = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final deleteF = provider.deleteGoal(1);
      final refreshF = provider.loadGoals();
      refreshC.complete([goal(1), goal(2)]); // resurrects goal 1
      await refreshF;
      expect(provider.goals.map((g) => g.id), containsAll(<int>[1, 2]));

      deleteC.complete();
      expect(await deleteF, isTrue);

      expect(provider.goals.map((g) => g.id), [2]); // only goal 1 removed
    });

    test('61: create success upsert does not duplicate an already-present '
        'returned server id', () async {
      epoch.activate(1);
      final createC = Completer<Goal>();
      final refreshC = Completer<List<Goal>>();
      when(repo.createGoal(any)).thenAnswer((_) => createC.future);
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final createF = provider.createGoal(goal(7));
      final refreshF = provider.loadGoals();
      // Refresh already contains a row with the id the create will return.
      refreshC.complete([goal(7)]);
      await refreshF;
      expect(provider.goals.map((g) => g.id), [7]);

      createC.complete(goal(7));
      expect((await createF)!.id, 7);

      expect(provider.goals.where((g) => g.id == 7), hasLength(1)); // no dup
      expect(provider.goals, hasLength(1));
    });

    test('62: create success removes only its own exact temporary row, never '
        "a concurrent create's placeholder", () async {
      epoch.activate(1);
      final olderC = Completer<Goal>(); // temp id -1, still pending
      final newerC = Completer<Goal>(); // temp id -2, newest -> owns
      var call = 0;
      when(
        repo.createGoal(any),
      ).thenAnswer((_) => (call++ == 0) ? olderC.future : newerC.future);

      final olderF = provider.createGoal(goal(1)); // placeholder -1
      final newerF = provider.createGoal(goal(2)); // placeholder -2, newest
      expect(provider.goals.map((g) => g.id), [-1, -2]);

      newerC.complete(goal(2)); // owns() true -> upsert path
      expect((await newerF)!.id, 2);

      // Only -2 was removed; the older create's -1 placeholder survives.
      expect(provider.goals.map((g) => g.id), [-1, 2]);

      olderC.complete(goal(1)); // let the older create finish cleanly
      await olderF;
    });

    test('63: listener count - the converged final state is published exactly '
        'once by the owned acknowledgment', () async {
      epoch.activate(1);
      await seedGoal(1);
      final updateC = Completer<void>();
      final refreshC = Completer<List<Goal>>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => updateC.future);
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final updateF = provider.updateGoal(1, goal(1, target: 40));
      final refreshF = provider.loadGoals();
      refreshC.complete([goal(1)]);
      await refreshF;

      final before = notifyCount;
      updateC.complete();
      expect(await updateF, isTrue);

      expect(notifyCount, before + 1); // exactly one publish from the ack
      expect(provider.goals.single.targetValue, 40);
    });

    test('64: failure rollback stays correct when a refresh displaced the '
        'optimistic row before the failure', () async {
      epoch.activate(1);
      await seedGoal(1);
      final updateC = Completer<void>();
      final refreshC = Completer<List<Goal>>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => updateC.future);
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final updateF = provider.updateGoal(1, goal(1, target: 40));
      final refreshF = provider.loadGoals();
      refreshC.complete([goal(1)]); // restores target 150
      await refreshF;

      updateC.completeError(Exception('update failed'));
      expect(await updateF, isFalse);

      // The subject of this test: rollback located the row by stable id (not
      // a stale index) even though the refresh had rebuilt the list, so the
      // final state is exactly one row at the original value - no duplicate,
      // no orphaned optimistic value. (The error string itself is suppressed
      // here by the documented cross-axis `_errorGen` gate: the intervening
      // successful `loadGoals()` claimed and vacated the shared error slot.
      // That is pre-existing behaviour shared with BodyMetricsProvider and is
      // not the concern of this convergence pass.)
      expect(provider.goals, hasLength(1));
      expect(provider.goals.single.targetValue, 150);
    });

    test('64b: delete failure after a refresh resurrected the row does not '
        'produce a duplicate', () async {
      epoch.activate(1);
      await seedGoal(1);
      final deleteC = Completer<void>();
      final refreshC = Completer<List<Goal>>();
      when(repo.deleteGoal(1)).thenAnswer((_) => deleteC.future);
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final deleteF = provider.deleteGoal(1);
      final refreshF = provider.loadGoals();
      refreshC.complete([goal(1)]); // resurrects
      await refreshF;

      deleteC.completeError(Exception('delete failed'));
      expect(await deleteF, isFalse);

      // `_reinsertGoalUnchecked` sees the row already present (the refresh
      // put it back) and does NOT insert a second copy. (Error string
      // suppressed by the same documented `_errorGen` cross-axis gate.)
      expect(provider.goals.where((g) => g.id == 1), hasLength(1)); // no dup
    });

    test('65: Order A still holds - an older refresh completing AFTER the '
        'update ack loses', () async {
      epoch.activate(1);
      await seedGoal(1);
      final refreshC = Completer<List<Goal>>();
      when(
        repo.getGoals(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      final refreshF = provider.loadGoals(); // starts first
      await provider.updateGoal(1, goal(1, target: 40)); // ack lands first
      expect(provider.goals.single.targetValue, 40);

      refreshC.complete([goal(1)]); // stale, resolves last
      await refreshF;

      expect(provider.goals.single.targetValue, 40); // mutation still wins
    });
  });

  // ================================================================
  // 66-72. Filtered-list convergence: `loadGoals(isActive:)` publishes a
  // filtered view; a mutation ack / rollback must never leave a Goal in
  // `_goals` that does not belong in that filter identity.
  // ================================================================

  group('filtered-list convergence', () {
    // Publishes an `isActive`-filtered list via a real `loadGoals` call whose
    // repository future is controlled by [c]; leaves `_publishedIsActiveFilter`
    // set to [filter]. Returns a fresh Completer for the NEXT getGoals call so
    // an adversarial mid-flight refresh can be driven deterministically.
    Completer<List<Goal>> nextGetGoals = Completer<List<Goal>>();

    setUp(() {
      nextGetGoals = Completer<List<Goal>>();
      when(repo.getGoals(isActive: anyNamed('isActive'))).thenAnswer((_) {
        final c = nextGetGoals;
        nextGetGoals = Completer<List<Goal>>();
        return c.future;
      });
    });

    Future<void> publish(bool? filter, List<Goal> rows) async {
      final pending = nextGetGoals;
      final f = provider.loadGoals(isActive: filter);
      pending.complete(rows);
      await f;
    }

    test(
      '66: completeGoal under an isActive:true list - the now-inactive Goal '
      'is neither kept optimistically nor re-added by the Order-B ack',
      () async {
        epoch.activate(1);
        await publish(true, [goal(1, active: true)]);
        expect(provider.goals.single.id, 1);

        final completeC = Completer<void>();
        when(repo.completeGoal(1)).thenAnswer((_) => completeC.future);

        final completeF = provider.completeGoal(1);
        expect(provider.goals, isEmpty); // optimistic: fell out of the filter

        // Order B: an active-only refresh completes and excludes goal 1.
        await publish(true, <Goal>[]);
        expect(provider.goals, isEmpty);

        completeC.complete();
        expect(await completeF, isTrue);

        expect(
          provider.goals,
          isEmpty,
        ); // ack must NOT re-add the inactive Goal
      },
    );

    test('67: createGoal whose server row does not match the published filter '
        'is returned to the caller but not inserted into the list', () async {
      epoch.activate(1);
      await publish(true, <Goal>[]); // _publishedIsActiveFilter == true

      final createC = Completer<Goal>();
      when(repo.createGoal(any)).thenAnswer((_) => createC.future);

      final createF = provider.createGoal(goal(7, active: false));
      // optimistic placeholder is inactive -> not added under isActive:true
      expect(provider.goals, isEmpty);

      createC.complete(goal(7, active: false));
      final result = await createF;

      expect(result!.id, 7); // caller still gets the created Goal
      expect(provider.goals, isEmpty); // but it is not in the active-only list
    });

    test('68: updateGoal that flips isActive out of the published filter drops '
        'the row on the Order-B ack', () async {
      epoch.activate(1);
      await publish(true, [goal(1, active: true)]);

      final updateC = Completer<void>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => updateC.future);

      final updateF = provider.updateGoal(1, goal(1, active: false));
      expect(provider.goals, isEmpty); // optimistic: reconciled out

      await publish(true, [goal(1, active: true)]); // refresh restores it
      expect(provider.goals.single.id, 1);

      updateC.complete();
      expect(await updateF, isTrue);

      expect(provider.goals, isEmpty); // ack reconciles it back out
    });

    test('69: update failure rollback after a refresh changed the published '
        'filter does not reinsert a now-non-matching original', () async {
      epoch.activate(1);
      await publish(true, [goal(1, active: true)]);

      final updateC = Completer<void>();
      when(repo.updateGoal(1, any)).thenAnswer((_) => updateC.future);

      final updateF = provider.updateGoal(1, goal(1, active: true, target: 40));
      expect(provider.goals.single.targetValue, 40);

      // A refresh switches the published filter to isActive:false.
      await publish(false, <Goal>[]);
      expect(provider.goals, isEmpty);

      updateC.completeError(Exception('update failed'));
      expect(await updateF, isFalse);

      // originalGoal is active -> does not belong in the isActive:false list.
      expect(provider.goals, isEmpty);
    });

    test('70: delete failure rollback after a refresh changed the published '
        'filter does not reinsert a now-non-matching original', () async {
      epoch.activate(1);
      await publish(true, [goal(1, active: true)]);

      final deleteC = Completer<void>();
      when(repo.deleteGoal(1)).thenAnswer((_) => deleteC.future);

      final deleteF = provider.deleteGoal(1);
      expect(provider.goals, isEmpty);

      await publish(false, <Goal>[]); // filter now isActive:false
      expect(provider.goals, isEmpty);

      deleteC.completeError(Exception('delete failed'));
      expect(await deleteF, isFalse);

      expect(provider.goals, isEmpty); // active original not reinserted
    });

    test(
      '71: regression - with no filter (_publishedIsActiveFilter == null) '
      'the Order-B completeGoal ack still upserts the completed Goal',
      () async {
        epoch.activate(1);
        await publish(null, [goal(1, active: true)]); // unfiltered

        final completeC = Completer<void>();
        when(repo.completeGoal(1)).thenAnswer((_) => completeC.future);

        final completeF = provider.completeGoal(1);
        expect(provider.goals.single.isCompleted, isTrue); // optimistic kept

        await publish(null, [
          goal(1, active: true),
        ]); // refresh restores incomplete
        expect(provider.goals.single.isCompleted, isFalse);

        completeC.complete();
        expect(await completeF, isTrue);

        expect(provider.goals.single.isCompleted, isTrue); // re-converged
      },
    );

    test('72: clear() resets _publishedIsActiveFilter so a later unfiltered '
        'create is inserted again', () async {
      epoch.activate(1);
      await publish(true, <Goal>[]); // filter == true

      provider.clear();

      // After clear the filter identity is null again: an inactive create now
      // belongs in the (unfiltered) list.
      when(
        repo.createGoal(any),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Goal);
      final result = await provider.createGoal(goal(9, active: false));

      expect(result!.id, 9);
      expect(provider.goals.map((g) => g.id), [9]);
    });
  });
}
