import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/exercise_set.dart';
import 'package:go_hard_app/data/repositories/exercise_repository.dart';
import 'package:go_hard_app/providers/log_sets_provider.dart';

@GenerateMocks([ExerciseRepository])
import 'log_sets_provider_session_cleanup_test.mocks.dart';

/// Proves [LogSetsProvider] never lets a repository result, error, or
/// `finally` cleanup started under user A land on the state user B now
/// sees through this same app-scoped provider instance, that logout
/// clears the retained set list synchronously, and that within one session
/// an older request can never overwrite a newer one.
///
/// Real [UserSessionEpoch]; the repository is mocked so `Completer`s give
/// exact control over when each continuation resolves. Nothing in this
/// file waits on wall-clock time.
void main() {
  late MockExerciseRepository repo;
  late UserSessionEpoch epoch;
  late LogSetsProvider provider;
  late int notifyCount;

  ExerciseSet set(
    int id, {
    int exerciseId = 1,
    int setNumber = 1,
    int reps = 10,
    double weight = 100,
    bool isCompleted = false,
  }) => ExerciseSet(
    id: id,
    exerciseId: exerciseId,
    setNumber: setNumber,
    reps: reps,
    weight: weight,
    isCompleted: isCompleted,
  );

  void stubDefaults() {
    when(repo.getExerciseSets(any)).thenAnswer((_) async => <ExerciseSet>[]);
    when(
      repo.createExerciseSet(any),
    ).thenAnswer((inv) async => inv.positionalArguments.first as ExerciseSet);
    when(
      repo.completeExerciseSet(any),
    ).thenAnswer((inv) async => set(inv.positionalArguments.first as int));
    when(repo.deleteExerciseSet(any)).thenAnswer((_) async => true);
  }

  setUp(() {
    repo = MockExerciseRepository();
    stubDefaults();
    epoch = UserSessionEpoch();
    provider = LogSetsProvider(repo, epoch);
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
  // 1-7. Direct disclosure and clear()
  // ================================================================

  group('direct disclosure and clear()', () {
    test('1: a provider populated with A\'s sets becomes empty synchronously '
        'on clear()', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(1, setNumber: 1), set(2, setNumber: 2)]);
      await provider.loadSets(1);
      expect(provider.sets, isNotEmpty);

      provider.clear();

      expect(provider.sets, isEmpty);
    });

    test('2/3: every user-visible field (sets, loading flag, error) is reset '
        'by clear()', () async {
      epoch.activate(1);

      // A load in flight -> _isLoading is true, _errorMessage is null.
      final c = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(2)).thenAnswer((_) => c.future);
      final f = provider.loadSets(2);

      // An addSet failure sets _errorMessage WITHOUT touching _isLoading,
      // so both a non-default loading flag and a non-null error are live
      // simultaneously when clear() runs.
      when(repo.createExerciseSet(any)).thenThrow(Exception('boom'));
      expect(await provider.addSet(exerciseId: 9, reps: 1, weight: 1), isFalse);
      expect(provider.isLoading, isTrue);
      expect(provider.errorMessage, isNotNull);

      provider.clear();

      expect(provider.sets, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);

      c.complete([set(9)]);
      await f;
    });

    test('4: clear() notifies exactly once', () {
      epoch.activate(1);
      notifyCount = 0;
      provider.clear();
      expect(notifyCount, 1);
    });

    test('5: repeated clear() is safe and each call notifies once', () {
      epoch.activate(1);
      provider.clear();
      notifyCount = 0;
      provider.clear();
      provider.clear();
      expect(notifyCount, 2);
      expect(provider.sets, isEmpty);
    });

    test('6: provider remains usable for user B after clear()', () async {
      epoch.activate(1);
      when(repo.getExerciseSets(1)).thenAnswer((_) async => [set(1)]);
      await provider.loadSets(1);

      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      when(repo.getExerciseSets(1)).thenAnswer((_) async => [set(50)]);
      await provider.loadSets(1);
      expect(provider.sets.single.id, 50);
    });

    test('7: a `sets` reference captured before clear() is itself emptied by '
        'clear() - the retained list does not keep the previous user\'s '
        'data', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(1, setNumber: 1), set(2, setNumber: 2)]);
      await provider.loadSets(1);

      final retained = provider.sets;
      expect(retained, isNotEmpty);

      provider.clear();

      expect(provider.sets, isEmpty);
      expect(
        retained,
        isEmpty,
        reason:
            'a reference obtained before clear() must not still hold User '
            "A's sets afterwards",
      );
    });

    test('7b: the list exposed by `sets` cannot be mutated by an external '
        'caller', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(1, setNumber: 1)]);
      await provider.loadSets(1);

      final view = provider.sets;
      expect(() => view.add(set(99)), throwsUnsupportedError);
      expect(() => view.removeAt(0), throwsUnsupportedError);
      expect(() => view.clear(), throwsUnsupportedError);
      expect(() => view[0] = set(99), throwsUnsupportedError);
      expect(provider.sets.single.id, 1, reason: 'state is unchanged');
    });

    test('7c: a `sets` reference captured before clear() reflects a fresh '
        'User B load through the same live view', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(1, setNumber: 1)]);
      await provider.loadSets(1);
      final retained = provider.sets;

      epoch.invalidate();
      provider.clear();
      epoch.activate(2);
      expect(retained, isEmpty);

      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(50, setNumber: 1)]);
      await provider.loadSets(1);

      expect(provider.sets.single.id, 50);
      expect(
        retained.single.id,
        50,
        reason:
            'the getter is a live unmodifiable view over the one backing '
            'list, so it never detaches into a stale snapshot',
      );
    });
  });

  // ================================================================
  // 13-21. Cross-session async protection
  // ================================================================

  group('cross-session async protection', () {
    test('13: a slow loadSets completing after logout cannot repopulate the '
        'cleared list and does not notify', () async {
      epoch.activate(1);
      final c = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => c.future);

      final f = provider.loadSets(1);
      epoch.invalidate();
      provider.clear();
      final notifiesBefore = notifyCount;

      c.complete([set(1), set(2)]);
      await f;

      expect(provider.sets, isEmpty);
      expect(notifyCount, notifiesBefore);
    });

    test('13b: a slow loadSets completing after a bare logout - no clear(), no '
        'newer load - cannot publish or notify', () async {
      epoch.activate(1);
      final c = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => c.future);

      final f = provider.loadSets(1);
      epoch.invalidate();
      final notifiesBefore = notifyCount;

      c.complete([set(1), set(2)]);
      await f;

      expect(provider.sets, isEmpty);
      expect(notifyCount, notifiesBefore);
    });

    test('14: the same completion after user B logs in cannot expose A\'s sets '
        'to B', () async {
      epoch.activate(1);
      final aC = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => aC.future);

      final aF = provider.loadSets(1);
      epoch.invalidate();
      epoch.activate(2);
      provider.clear();

      when(repo.getExerciseSets(1)).thenAnswer((_) async => [set(2)]);
      await provider.loadSets(1);
      expect(provider.sets.single.id, 2);

      aC.complete([set(999)]);
      await aF;
      expect(provider.sets.single.id, 2);
    });

    test('15: a stale load catch cannot set B\'s error', () async {
      epoch.activate(1);
      final c = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => c.future);

      final f = provider.loadSets(1);
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);
      final notifiesBefore = notifyCount;

      c.completeError(Exception('boom'));
      await f;

      expect(provider.errorMessage, isNull);
      expect(notifyCount, notifiesBefore);
    });

    test(
      '16: a stale load finally cannot clear B\'s newer loading state',
      () async {
        epoch.activate(1);
        final aC = Completer<List<ExerciseSet>>();
        when(repo.getExerciseSets(1)).thenAnswer((_) => aC.future);
        final aF = provider.loadSets(1);

        epoch.invalidate();
        epoch.activate(2);
        provider.clear();

        final bC = Completer<List<ExerciseSet>>();
        when(repo.getExerciseSets(2)).thenAnswer((_) => bC.future);
        final bF = provider.loadSets(2);
        expect(provider.isLoading, isTrue);

        aC.complete([set(1)]);
        await aF;
        expect(
          provider.isLoading,
          isTrue,
          reason: 'stale A finally must not clear B\'s spinner',
        );

        bC.complete([set(2)]);
        await bF;
        expect(provider.isLoading, isFalse);
      },
    );

    test('17: a stale addSet success cannot modify B', () async {
      epoch.activate(1);
      final c = Completer<ExerciseSet>();
      when(repo.createExerciseSet(any)).thenAnswer((_) => c.future);

      final f = provider.addSet(exerciseId: 1, reps: 5, weight: 20);
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);
      final notifiesBefore = notifyCount;

      c.complete(set(1));
      expect(await f, isFalse);

      expect(provider.sets, isEmpty);
      expect(notifyCount, notifiesBefore);
    });

    test(
      '17b: a stale completeSet success cannot modify B or notify',
      () async {
        epoch.activate(1);
        when(
          repo.getExerciseSets(1),
        ).thenAnswer((_) async => [set(1, setNumber: 1)]);
        await provider.loadSets(1);

        final c = Completer<ExerciseSet>();
        when(repo.completeExerciseSet(1)).thenAnswer((_) => c.future);
        final f = provider.completeSet(set(1, setNumber: 1));

        epoch.invalidate();
        provider.clear();
        epoch.activate(2);
        final notifiesBefore = notifyCount;

        c.complete(set(1, setNumber: 1, isCompleted: true));
        await f;

        expect(provider.sets, isEmpty);
        expect(notifyCount, notifiesBefore);
      },
    );

    test('18: a stale mutation failure cannot modify B', () async {
      epoch.activate(1);
      final c = Completer<bool>();
      when(repo.deleteExerciseSet(7)).thenAnswer((_) => c.future);

      final f = provider.deleteSet(set(7));
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);
      final notifiesBefore = notifyCount;

      c.completeError(Exception('boom'));
      expect(await f, isFalse);

      expect(provider.errorMessage, isNull);
      expect(notifyCount, notifiesBefore);
    });

    test('19: a bare clear() without epoch invalidation blocks an '
        'already-running load completion', () async {
      epoch.activate(1);
      final c = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => c.future);

      final f = provider.loadSets(1);
      provider.clear(); // no epoch.invalidate()
      final notifiesBefore = notifyCount;

      c.complete([set(1), set(2)]);
      await f;

      expect(provider.sets, isEmpty);
      expect(notifyCount, notifiesBefore);
    });

    test('20: a fresh user-B load after clear() completes normally', () async {
      epoch.activate(1);
      provider.clear();
      epoch.invalidate();
      epoch.activate(2);

      when(repo.getExerciseSets(3)).thenAnswer((_) async => [set(3)]);
      await provider.loadSets(3);
      expect(provider.sets.single.id, 3);
    });

    test('21: loadSets started while logged out never starts work', () async {
      // no epoch.activate()
      await provider.loadSets(1);
      expect(provider.isLoading, isFalse);
      expect(provider.sets, isEmpty);
      verifyNever(repo.getExerciseSets(any));
    });
  });

  // ================================================================
  // 22-28. Same-session ordering
  // ================================================================

  group('same-session ordering', () {
    test('22: an older loadSets completing last loses', () async {
      epoch.activate(1);
      final firstC = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => firstC.future);
      final first = provider.loadSets(1);

      final secondC = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => secondC.future);
      final second = provider.loadSets(1);

      secondC.complete([set(2)]);
      await second;
      expect(provider.sets.single.id, 2);

      firstC.complete([set(1)]);
      await first;
      expect(
        provider.sets.single.id,
        2,
        reason: 'the superseded first load must not overwrite the newer one',
      );
    });

    test('23: a load for exercise A completing after exercise B cannot replace '
        'B\'s sets', () async {
      epoch.activate(1);
      final aC = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(10)).thenAnswer((_) => aC.future);
      final aF = provider.loadSets(10);

      when(
        repo.getExerciseSets(20),
      ).thenAnswer((_) async => [set(200, exerciseId: 20)]);
      await provider.loadSets(20);
      expect(provider.sets.single.exerciseId, 20);

      aC.complete([set(100, exerciseId: 10)]);
      await aF;
      expect(provider.sets.single.exerciseId, 20);
    });

    test(
      '24: A->B->A is resolved by generation identity, not exercise id',
      () async {
        epoch.activate(1);
        final a1C = Completer<List<ExerciseSet>>();
        when(repo.getExerciseSets(1)).thenAnswer((_) => a1C.future);
        final a1 = provider.loadSets(1);

        when(repo.getExerciseSets(2)).thenAnswer((_) async => [set(2)]);
        await provider.loadSets(2);

        final a2C = Completer<List<ExerciseSet>>();
        when(repo.getExerciseSets(1)).thenAnswer((_) => a2C.future);
        final a2 = provider.loadSets(1);

        a1C.complete([set(11)]);
        await a1;
        expect(provider.sets.single.id, 2, reason: 'first A load is stale');

        a2C.complete([set(12)]);
        await a2;
        expect(provider.sets.single.id, 12, reason: 'newest A load wins');
      },
    );

    test('25: a stale load cannot overwrite a newer add', () async {
      epoch.activate(1);
      final loadC = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => loadC.future);
      final loadF = provider.loadSets(1);

      when(
        repo.createExerciseSet(any),
      ).thenAnswer((_) async => set(500, exerciseId: 1, setNumber: 1));
      expect(await provider.addSet(exerciseId: 1, reps: 8, weight: 40), isTrue);
      expect(provider.sets.single.id, 500);

      loadC.complete([set(1), set(2)]);
      await loadF;
      expect(
        provider.sets.single.id,
        500,
        reason: 'the stale list load must not drop the newly added set',
      );
      expect(
        provider.isLoading,
        isFalse,
        reason:
            'the superseded load still owns its spinner and must clear it - '
            'a mutation must not strand _isLoading',
      );
    });

    test('25b: a completeSet/deleteSet succeeding during an in-flight load '
        'does not strand the load spinner', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(1, setNumber: 1), set(2, setNumber: 2)]);
      await provider.loadSets(1);

      final reloadC = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => reloadC.future);
      final reloadF = provider.loadSets(1);
      expect(provider.isLoading, isTrue);

      when(
        repo.completeExerciseSet(1),
      ).thenAnswer((_) async => set(1, setNumber: 1, isCompleted: true));
      await provider.completeSet(set(1, setNumber: 1));

      reloadC.complete([set(1, setNumber: 1), set(2, setNumber: 2)]);
      await reloadF;

      expect(provider.isLoading, isFalse);
    });

    test('26: an update completing after a newer delete for the same set is '
        'superseded and cannot publish', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(1, setNumber: 1), set(2, setNumber: 2)]);
      await provider.loadSets(1);

      // completeSet(1) goes in flight...
      final completeC = Completer<ExerciseSet>();
      when(repo.completeExerciseSet(1)).thenAnswer((_) => completeC.future);
      final completeF = provider.completeSet(set(1, setNumber: 1));

      // ...then a NEWER delete for the same set goes in flight. It shares the
      // per-set mutation generation, so it supersedes the complete.
      final deleteC = Completer<bool>();
      when(repo.deleteExerciseSet(1)).thenAnswer((_) => deleteC.future);
      final deleteF = provider.deleteSet(set(1, setNumber: 1));

      // The superseded complete resolves first. Set 1 is still in the list
      // (delete has not landed yet) - but the complete must NOT mark it
      // completed, because a newer delete owns the set now.
      completeC.complete(set(1, setNumber: 1, isCompleted: true));
      await completeF;
      expect(
        provider.sets.firstWhere((s) => s.id == 1).isCompleted,
        isFalse,
        reason: 'the superseded complete must not publish its update',
      );

      deleteC.complete(true);
      await deleteF;
      expect(provider.sets.any((s) => s.id == 1), isFalse);
    });

    test('27: different-set mutations remain independent', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(1, setNumber: 1), set(2, setNumber: 2)]);
      await provider.loadSets(1);

      final c1 = Completer<ExerciseSet>();
      when(repo.completeExerciseSet(1)).thenAnswer((_) => c1.future);
      final f1 = provider.completeSet(set(1));

      when(
        repo.completeExerciseSet(2),
      ).thenAnswer((_) async => set(2, setNumber: 2, isCompleted: true));
      await provider.completeSet(set(2, setNumber: 2));
      expect(provider.sets.firstWhere((s) => s.id == 2).isCompleted, isTrue);

      c1.complete(set(1, isCompleted: true));
      await f1;
      expect(
        provider.sets.firstWhere((s) => s.id == 1).isCompleted,
        isTrue,
        reason: 'a mutation to set 2 must not supersede one to set 1',
      );
    });

    test('28: same-set overlapping mutations resolve deterministically '
        '(newer wins)', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(1, setNumber: 1)]);
      await provider.loadSets(1);

      final firstC = Completer<ExerciseSet>();
      when(repo.completeExerciseSet(1)).thenAnswer((_) => firstC.future);
      final first = provider.completeSet(set(1));

      final secondC = Completer<bool>();
      when(repo.deleteExerciseSet(1)).thenAnswer((_) => secondC.future);
      final second = provider.deleteSet(set(1));

      secondC.complete(true);
      await second;
      expect(provider.sets, isEmpty);

      firstC.complete(set(1, isCompleted: true));
      await first;
      expect(provider.sets, isEmpty, reason: 'newer delete wins');
    });
  });

  // ================================================================
  // 29-30. Dispose
  // ================================================================

  group('dispose', () {
    test('29/30: dispose() prevents a later continuation from publishing or '
        'notifying', () async {
      epoch.activate(1);
      final c = Completer<List<ExerciseSet>>();
      when(repo.getExerciseSets(1)).thenAnswer((_) => c.future);
      final f = provider.loadSets(1);

      final notifiesBefore = notifyCount;
      provider.dispose();

      c.complete([set(1), set(2)]);
      await f;

      expect(notifyCount, notifiesBefore);
    });
  });

  // ================================================================
  // Retained behavior coverage (happy paths).
  // ================================================================

  group('behavior', () {
    test('loadSets populates and sorts by set number', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(2, setNumber: 3), set(1, setNumber: 1)]);
      await provider.loadSets(1);
      expect(provider.sets.map((s) => s.setNumber), [1, 3]);
      expect(provider.isLoading, isFalse);
    });

    test(
      'loadSets sets the loading flag synchronously and clears a prior error',
      () async {
        epoch.activate(1);
        when(repo.getExerciseSets(1)).thenThrow(Exception('boom'));
        await provider.loadSets(1);
        expect(provider.errorMessage, isNotNull);

        final c = Completer<List<ExerciseSet>>();
        when(repo.getExerciseSets(2)).thenAnswer((_) => c.future);
        final f = provider.loadSets(2);
        expect(provider.isLoading, isTrue);
        expect(provider.errorMessage, isNull);
        c.complete([]);
        await f;
      },
    );

    test(
      'addSet appends the created set and assigns the next set number',
      () async {
        epoch.activate(1);
        when(
          repo.getExerciseSets(1),
        ).thenAnswer((_) async => [set(1, setNumber: 1)]);
        await provider.loadSets(1);

        when(repo.createExerciseSet(any)).thenAnswer(
          (inv) async => (inv.positionalArguments.first as ExerciseSet),
        );
        expect(
          await provider.addSet(exerciseId: 1, reps: 5, weight: 60),
          isTrue,
        );
        expect(provider.sets.last.setNumber, 2);
      },
    );

    test('addSet reports an error on repository failure', () async {
      epoch.activate(1);
      when(repo.createExerciseSet(any)).thenThrow(Exception('nope'));
      expect(
        await provider.addSet(exerciseId: 1, reps: 5, weight: 60),
        isFalse,
      );
      expect(provider.errorMessage, contains('Failed to add set'));
    });

    test('deleteSet removes the set and renumbers the remainder', () async {
      epoch.activate(1);
      when(repo.getExerciseSets(1)).thenAnswer(
        (_) async => [
          set(1, setNumber: 1),
          set(2, setNumber: 2),
          set(3, setNumber: 3),
        ],
      );
      await provider.loadSets(1);

      when(repo.deleteExerciseSet(1)).thenAnswer((_) async => true);
      expect(await provider.deleteSet(set(1)), isTrue);
      expect(provider.sets.map((s) => s.id), [2, 3]);
      expect(provider.sets.map((s) => s.setNumber), [1, 2]);
    });

    test('completeSet updates the set in place', () async {
      epoch.activate(1);
      when(
        repo.getExerciseSets(1),
      ).thenAnswer((_) async => [set(1, setNumber: 1)]);
      await provider.loadSets(1);

      when(
        repo.completeExerciseSet(1),
      ).thenAnswer((_) async => set(1, setNumber: 1, isCompleted: true));
      await provider.completeSet(set(1));
      expect(provider.sets.single.isCompleted, isTrue);
    });

    test('clearError resets the error and notifies', () async {
      epoch.activate(1);
      when(repo.getExerciseSets(1)).thenThrow(Exception('boom'));
      await provider.loadSets(1);
      expect(provider.errorMessage, isNotNull);

      notifyCount = 0;
      provider.clearError();
      expect(provider.errorMessage, isNull);
      expect(notifyCount, 1);
    });
  });
}
