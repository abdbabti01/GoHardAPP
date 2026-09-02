import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/program.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/data/repositories/programs_repository.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';
import 'package:go_hard_app/providers/programs_provider.dart';

@GenerateMocks([ProgramsRepository, ConnectivityService])
import 'programs_provider_session_ownership_test.mocks.dart';

/// Proves [ProgramsProvider] never lets a repository result, error, or
/// `finally` cleanup started under user A land on the state user B now sees
/// through this same app-scoped instance; that within one session an older
/// request / mutation can never overwrite a newer one on the same program or
/// nested workout; that a stale refresh cannot displace a newer mutation
/// (both completion orders); that deleting a parent program invalidates its
/// in-flight child-workout mutations; and that [ProgramsProvider.clear]
/// invalidates every generation before resetting state.
///
/// Real [UserSessionEpoch]; the repository is mocked so `Completer`s give
/// exact control over when each continuation resolves - no wall-clock delay,
/// no `Future.delayed`, no `Future.value()` / `pumpEventQueue` / `_settle` as
/// a pump, no `Timer`, no `sleep`. Ordering is synchronized only through
/// explicit `Completer.complete()` calls, awaiting the exact `Future` under
/// test, a `sync: true` broadcast `StreamController` and the
/// `onConnectivityRefreshForTesting` seam.
void main() {
  late MockProgramsRepository repo;
  late UserSessionEpoch epoch;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late ProgramsProvider provider;
  late int notifyCount;

  Future<void>? connectivityRefresh;

  Program program(
    int id, {
    bool active = true,
    bool completed = false,
    String title = 'P',
    List<ProgramWorkout>? workouts,
  }) => Program(
    id: id,
    userId: 1,
    title: '$title$id',
    totalWeeks: 4,
    currentWeek: 1,
    currentDay: 1,
    startDate: DateTime(2024, 1, 1),
    isActive: active,
    isCompleted: completed,
    createdAt: DateTime(2024, 1, 1),
    workouts: workouts,
  );

  ProgramWorkout workout(
    int id, {
    int programId = 1,
    int day = 1,
    int order = 0,
    bool completed = false,
    String name = 'W',
  }) => ProgramWorkout(
    id: id,
    programId: programId,
    weekNumber: 1,
    dayNumber: day,
    workoutName: name,
    exercisesJson: '[]',
    isCompleted: completed,
    orderIndex: order,
  );

  void stubDefaults() {
    when(
      repo.getPrograms(isActive: anyNamed('isActive')),
    ).thenAnswer((_) async => <Program>[]);
    when(repo.getProgramById(any)).thenAnswer((_) async => program(1));
    when(
      repo.createProgram(any),
    ).thenAnswer((inv) async => inv.positionalArguments[0] as Program);
    when(
      repo.advanceProgram(any),
    ).thenAnswer((inv) async => program(inv.positionalArguments[0] as int));
    when(
      repo.recalibrateProgram(any),
    ).thenAnswer((_) async => <String, dynamic>{'ok': true});
    when(
      repo.getWeekWorkouts(any, any),
    ).thenAnswer((_) async => <ProgramWorkout>[]);
    when(repo.getTodaysWorkout(any)).thenAnswer((_) async => workout(10));
    when(
      repo.getDeletionImpact(any),
    ).thenAnswer((_) async => {'sessionsCount': 0});
    // updateProgram / deleteProgram / completeProgram / updateWorkout /
    // swapWorkouts / completeWorkout / deleteWorkout / addWorkout are left
    // unstubbed: the generated mock supplies a completed future for a missing
    // void stub; tests that care about timing install their own Completer.
    when(
      repo.addWorkout(any, any),
    ).thenAnswer((inv) async => inv.positionalArguments[1] as ProgramWorkout);
  }

  setUp(() {
    repo = MockProgramsRepository();
    stubDefaults();
    epoch = UserSessionEpoch();
    connectivity = MockConnectivityService();
    connectivityController = StreamController<bool>.broadcast(sync: true);
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    provider = ProgramsProvider(repo, epoch, connectivity);
    connectivityRefresh = null;
    provider.onConnectivityRefreshForTesting = (f) => connectivityRefresh = f;
    notifyCount = 0;
    provider.addListener(() => notifyCount++);
  });

  tearDown(() async {
    try {
      provider.dispose();
    } catch (_) {}
    await connectivityController.close();
  });

  // Seed the master cache with the given programs under the active session.
  // Activates user 1 if no session is active yet, so callers can `seed()`
  // first and then re-assert `epoch.activate(1)` harmlessly.
  Future<void> seed(List<Program> programs) async {
    if (epoch.capture() == null) epoch.activate(1);
    when(
      repo.getPrograms(isActive: anyNamed('isActive')),
    ).thenAnswer((_) async => programs);
    await provider.loadPrograms();
    stubDefaults();
  }

  // ==========================================================================
  // Repository binding is proven in
  // programs_repository_session_ownership_test.dart.
  // ==========================================================================

  group('1. cross-session protection - list & direct-return reads', () {
    test('a slow loadPrograms completing after clear() cannot repopulate the '
        'cleared lists and does not notify', () async {
      epoch.activate(1);
      final c = Completer<List<Program>>();
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadPrograms();
      epoch.invalidate();
      provider.clear();
      final notifiesBefore = notifyCount;

      c.complete([program(1)]);
      await f;

      expect(provider.programs, isEmpty);
      expect(provider.activePrograms, isEmpty);
      expect(notifyCount, notifiesBefore);
    });

    test(
      'the same completion after user B logs in cannot overwrite B',
      () async {
        epoch.activate(1);
        final aC = Completer<List<Program>>();
        final bC = Completer<List<Program>>();
        var call = 0;
        when(
          repo.getPrograms(isActive: anyNamed('isActive')),
        ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

        final aF = provider.loadPrograms();
        epoch.invalidate();
        epoch.activate(2);
        final bF = provider.loadPrograms();

        bC.complete([program(9)]);
        await bF;
        expect(provider.programs.single.id, 9);

        aC.complete([program(1)]);
        await aF;
        expect(provider.programs.single.id, 9);
      },
    );

    test('a stale getProgramById result never reaches its caller', () async {
      epoch.activate(1);
      final c = Completer<Program>();
      when(repo.getProgramById(1)).thenAnswer((_) => c.future);

      final f = provider.getProgramById(1);
      epoch.invalidate();

      c.complete(program(1));
      expect(await f, isNull);
      expect(provider.errorMessage, isNull);
    });

    test('a stale getWeekWorkouts result never reaches its caller', () async {
      epoch.activate(1);
      final c = Completer<List<ProgramWorkout>>();
      when(repo.getWeekWorkouts(1, 1)).thenAnswer((_) => c.future);

      final f = provider.getWeekWorkouts(1, 1);
      epoch.invalidate();

      c.complete([workout(10)]);
      expect(await f, isEmpty);
    });

    test('a stale getTodaysWorkout result never reaches its caller', () async {
      epoch.activate(1);
      final c = Completer<ProgramWorkout>();
      when(repo.getTodaysWorkout(1)).thenAnswer((_) => c.future);

      final f = provider.getTodaysWorkout(1);
      epoch.invalidate();

      c.complete(workout(10));
      expect(await f, isNull);
    });

    test('a stale getDeletionImpact throws SessionStaleException rather than '
        'returning stale counts', () async {
      epoch.activate(1);
      final c = Completer<Map<String, int>>();
      when(repo.getDeletionImpact(1)).thenAnswer((_) => c.future);

      final f = provider.getDeletionImpact(1);
      epoch.invalidate();

      c.complete({'sessionsCount': 5});
      await expectLater(f, throwsA(isA<SessionStaleException>()));
    });

    test('A -> B -> A: an A-generation loadPrograms that resolves last does '
        'not overwrite the newer A-generation load', () async {
      epoch.activate(1);
      final c1 = Completer<List<Program>>();
      final c2 = Completer<List<Program>>();
      var call = 0;
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => (call++ == 0) ? c1.future : c2.future);

      final f1 = provider.loadPrograms();
      final f2 = provider.loadPrograms();

      c2.complete([program(2)]);
      await f2;
      c1.complete([program(1)]);
      await f1;

      expect(provider.programs.single.id, 2);
    });
  });

  group('2. stale mutation success cannot publish into another session', () {
    test('a stale createProgram success cannot append into B', () async {
      epoch.activate(1);
      final c = Completer<Program>();
      when(repo.createProgram(any)).thenAnswer((_) => c.future);

      final f = provider.createProgram(program(1));
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);
      final notifiesBefore = notifyCount;

      c.complete(program(1));
      expect(await f, isFalse);

      expect(provider.programs, isEmpty);
      expect(provider.isCreating, isFalse);
      expect(notifyCount, notifiesBefore);
    });

    test('a stale updateProgram success cannot edit B\'s list', () async {
      await seed([program(1, title: 'A')]);
      epoch.activate(1);
      final c = Completer<void>();
      when(repo.updateProgram(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateProgram(1, program(1, title: 'EDIT'));
      epoch.invalidate();
      provider.clear();
      epoch.activate(2);

      c.complete();
      expect(await f, isFalse);
      expect(provider.programs, isEmpty);
    });

    test('a stale deleteProgram success cannot mutate B\'s list', () async {
      await seed([program(1), program(2)]);
      epoch.activate(1);
      final c = Completer<void>();
      when(repo.deleteProgram(1)).thenAnswer((_) => c.future);

      final f = provider.deleteProgram(1);
      epoch.invalidate();
      epoch.activate(2);
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program(7)]);
      await provider.loadPrograms();

      c.complete();
      expect(await f, isFalse);
      expect(provider.programs.single.id, 7);
    });

    test(
      'a stale completeWorkout success cannot edit B\'s nested workouts',
      () async {
        await seed([
          program(1, workouts: [workout(10)]),
        ]);
        epoch.activate(1);
        final c = Completer<void>();
        when(
          repo.completeWorkout(10, notes: anyNamed('notes')),
        ).thenAnswer((_) => c.future);

        final f = provider.completeWorkout(10);
        epoch.invalidate();
        provider.clear();
        epoch.activate(2);

        c.complete();
        expect(await f, isFalse);
        expect(provider.programs, isEmpty);
      },
    );
  });

  group('3. stale catch / finally are silent', () {
    test('a stale loadPrograms failure publishes no error and does not '
        'notify', () async {
      epoch.activate(1);
      final c = Completer<List<Program>>();
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadPrograms();
      epoch.invalidate();
      provider.clear();
      final notifiesBefore = notifyCount;

      c.completeError(Exception('boom'));
      await f;

      expect(provider.errorMessage, isNull);
      expect(notifyCount, notifiesBefore);
    });

    test('a stale updateProgram failure does not publish its error', () async {
      await seed([program(1)]);
      epoch.activate(1);
      final c = Completer<void>();
      when(repo.updateProgram(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateProgram(1, program(1));
      epoch.invalidate();
      provider.clear();

      c.completeError(Exception('nope'));
      await f;

      expect(provider.errorMessage, isNull);
    });

    test('a stale loadPrograms finally cannot clear a newer session\'s '
        'isLoading', () async {
      epoch.activate(1);
      final aC = Completer<List<Program>>();
      final bC = Completer<List<Program>>();
      var call = 0;
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

      final aF = provider.loadPrograms();
      epoch.invalidate();
      epoch.activate(2);
      final bF = provider.loadPrograms();
      expect(provider.isLoading, isTrue);

      aC.complete([program(1)]);
      await aF;
      // A's finally must not have flipped B's spinner off.
      expect(provider.isLoading, isTrue);

      bC.complete([program(2)]);
      await bF;
      expect(provider.isLoading, isFalse);
    });

    test('a same-session mutation that bumps _listGen while a load is in '
        'flight does NOT strand the spinner (the finally is _loadGen-guarded, '
        'not _listGen-guarded)', () async {
      await seed([program(1, title: 'A')]);
      epoch.activate(1);
      final loadC = Completer<List<Program>>();
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => loadC.future);
      when(repo.updateProgram(1, any)).thenAnswer((_) async {});

      final loadF = provider.loadPrograms();
      expect(provider.isLoading, isTrue);
      // A successful mutation bumps _listGen (Order-A protection) while the
      // load is still awaiting its repository call.
      await provider.updateProgram(1, program(1, title: 'EDIT'));

      loadC.complete([program(1, title: 'STALE')]);
      await loadF;

      // The load lost its publication (mutation won), but the spinner is off
      // and the mutation's edit stands.
      expect(provider.isLoading, isFalse);
      expect(provider.programs.single.title, 'EDIT1');
    });
  });

  group('4. same-session per-program ordering', () {
    test(
      'an older updateProgram cannot resurrect a newer deleteProgram',
      () async {
        await seed([program(1, title: 'A')]);
        epoch.activate(1);
        final updC = Completer<void>();
        when(repo.updateProgram(1, any)).thenAnswer((_) => updC.future);
        when(repo.deleteProgram(1)).thenAnswer((_) async {});

        final updF = provider.updateProgram(1, program(1, title: 'EDIT'));
        final delF = provider.deleteProgram(1);
        await delF;
        expect(provider.programs, isEmpty);
        final notifiesAfterDelete = notifyCount;

        updC.complete();
        expect(await updF, isFalse);
        // The superseded update must not have re-added program 1, and must
        // not have notified.
        expect(provider.programs, isEmpty);
        expect(notifyCount, notifiesAfterDelete);
      },
    );

    test(
      'an older updateProgram cannot undo a newer completeProgram',
      () async {
        await seed([program(1, active: true)]);
        epoch.activate(1);
        final updC = Completer<void>();
        when(repo.updateProgram(1, any)).thenAnswer((_) => updC.future);
        when(repo.completeProgram(1)).thenAnswer((_) async {});

        final updF = provider.updateProgram(
          1,
          program(1, active: true, title: 'EDIT'),
        );
        await provider.completeProgram(1);
        expect(provider.programs.single.isCompleted, isTrue);

        updC.complete();
        await updF;
        expect(provider.programs.single.isCompleted, isTrue);
        expect(provider.programs.single.isActive, isFalse);
      },
    );

    test('an older updateProgram cannot undo a newer advanceProgram', () async {
      await seed([program(1)]);
      epoch.activate(1);
      final updC = Completer<void>();
      when(repo.updateProgram(1, any)).thenAnswer((_) => updC.future);
      when(repo.advanceProgram(1)).thenAnswer(
        (_) async => program(1).copyWith(currentWeek: 2, currentDay: 3),
      );

      final updF = provider.updateProgram(1, program(1, title: 'EDIT'));
      await provider.advanceProgram(1);
      expect(provider.programs.single.currentWeek, 2);

      updC.complete();
      await updF;
      expect(provider.programs.single.currentWeek, 2);
      expect(provider.programs.single.currentDay, 3);
    });

    test(
      'recalibrateProgram supersedes an older updateProgram on the same id',
      () async {
        await seed([program(1, title: 'A')]);
        epoch.activate(1);
        final updC = Completer<void>();
        when(repo.updateProgram(1, any)).thenAnswer((_) => updC.future);
        when(repo.recalibrateProgram(1)).thenAnswer((_) async => {'ok': true});
        when(
          repo.getPrograms(isActive: anyNamed('isActive')),
        ).thenAnswer((_) async => [program(1, title: 'SERVER')]);

        final updF = provider.updateProgram(1, program(1, title: 'EDIT'));
        await provider.recalibrateProgram(1);
        expect(provider.programs.single.title, 'SERVER1');

        updC.complete();
        await updF;
        expect(provider.programs.single.title, 'SERVER1');
      },
    );

    test(
      'updates to two different programs run concurrently and both land',
      () async {
        await seed([program(1, title: 'A'), program(2, title: 'B')]);
        epoch.activate(1);
        final c1 = Completer<void>();
        final c2 = Completer<void>();
        when(repo.updateProgram(1, any)).thenAnswer((_) => c1.future);
        when(repo.updateProgram(2, any)).thenAnswer((_) => c2.future);

        final f1 = provider.updateProgram(1, program(1, title: 'A_EDIT'));
        final f2 = provider.updateProgram(2, program(2, title: 'B_EDIT'));
        expect(provider.isUpdating, isTrue);

        c1.complete();
        await f1;
        expect(provider.programs.firstWhere((p) => p.id == 1).title, 'A_EDIT1');
        // program 2's update still in flight - flag stays set.
        expect(provider.isUpdating, isTrue);

        c2.complete();
        await f2;
        expect(provider.programs.firstWhere((p) => p.id == 2).title, 'B_EDIT2');
        expect(provider.isUpdating, isFalse);
      },
    );
  });

  group('5. composite (programId, workoutId) child ordering', () {
    test('updateWorkout for program 1 never touches program 2', () async {
      await seed([
        program(1, workouts: [workout(10, programId: 1, name: 'P1W')]),
        program(2, workouts: [workout(10, programId: 2, name: 'P2W')]),
      ]);
      epoch.activate(1);
      when(repo.updateWorkout(10, any)).thenAnswer((_) async {});

      await provider.updateWorkout(
        10,
        workout(10, programId: 1, name: 'P1W_EDIT'),
      );

      expect(
        provider.programs
            .firstWhere((p) => p.id == 1)
            .workouts!
            .single
            .workoutName,
        'P1W_EDIT',
      );
      expect(
        provider.programs
            .firstWhere((p) => p.id == 2)
            .workouts!
            .single
            .workoutName,
        'P2W',
      );
    });

    test('an older updateWorkout cannot undo a newer deleteWorkout on the '
        'same (program, workout)', () async {
      await seed([
        program(1, workouts: [workout(10), workout(11)]),
      ]);
      epoch.activate(1);
      final updC = Completer<void>();
      when(repo.updateWorkout(10, any)).thenAnswer((_) => updC.future);
      when(repo.deleteWorkout(10)).thenAnswer((_) async {});

      final updF = provider.updateWorkout(10, workout(10, name: 'EDIT'));
      await provider.deleteWorkout(10);
      expect(provider.programs.single.workouts!.map((w) => w.id), [11]);

      updC.complete();
      await updF;
      expect(provider.programs.single.workouts!.map((w) => w.id), [11]);
    });

    test('an older updateWorkout cannot undo a newer swapWorkouts', () async {
      await seed([
        program(
          1,
          workouts: [
            workout(10, day: 1, order: 0),
            workout(11, day: 2, order: 1),
          ],
        ),
      ]);
      epoch.activate(1);
      final updC = Completer<void>();
      when(repo.updateWorkout(10, any)).thenAnswer((_) => updC.future);
      when(repo.swapWorkouts(10, 11)).thenAnswer((_) async {});

      final updF = provider.updateWorkout(
        10,
        workout(10, day: 1, order: 0, name: 'EDIT'),
      );
      await provider.swapWorkouts(10, 11);
      final w10 = provider.programs.single.workouts!.firstWhere(
        (w) => w.id == 10,
      );
      expect(w10.dayNumber, 2);

      updC.complete();
      await updF;
      // Swap's day change survives; stale update wrote nothing.
      final w10After = provider.programs.single.workouts!.firstWhere(
        (w) => w.id == 10,
      );
      expect(w10After.dayNumber, 2);
      expect(w10After.workoutName, 'W');
    });

    test('overlapping swaps are ordered deterministically - the later swap '
        'wins the shared key', () async {
      await seed([
        program(
          1,
          workouts: [
            workout(10, day: 1, order: 0),
            workout(11, day: 2, order: 1),
            workout(12, day: 3, order: 2),
          ],
        ),
      ]);
      epoch.activate(1);
      final swap1 = Completer<void>();
      when(repo.swapWorkouts(10, 11)).thenAnswer((_) => swap1.future);
      when(repo.swapWorkouts(11, 12)).thenAnswer((_) async {});

      final f1 = provider.swapWorkouts(10, 11); // touches keys 10 & 11
      final f2 = provider.swapWorkouts(11, 12); // touches keys 11 & 12
      await f2;

      swap1.complete();
      await f1;

      // swap1 shares key 11 with swap2, so its late completion is discarded.
      final days = {
        for (final w in provider.programs.single.workouts!) w.id: w.dayNumber,
      };
      expect(days[11], 3); // moved by swap2
      expect(days[12], 2); // moved by swap2
      expect(days[10], 1); // swap1 discarded
    });

    test('equal workout ids under different programs stay isolated', () async {
      await seed([
        program(1, workouts: [workout(5, programId: 1, name: 'ONE')]),
        program(2, workouts: [workout(5, programId: 2, name: 'TWO')]),
      ]);
      epoch.activate(1);
      final c1 = Completer<void>();
      when(repo.updateWorkout(5, any)).thenAnswer((inv) {
        final w = inv.positionalArguments[1] as ProgramWorkout;
        return w.programId == 1 ? c1.future : Future<void>.value();
      });

      final f1 = provider.updateWorkout(
        5,
        workout(5, programId: 1, name: 'ONE_EDIT'),
      );
      await provider.updateWorkout(
        5,
        workout(5, programId: 2, name: 'TWO_EDIT'),
      );
      expect(
        provider.programs
            .firstWhere((p) => p.id == 2)
            .workouts!
            .single
            .workoutName,
        'TWO_EDIT',
      );

      c1.complete();
      await f1;
      // program 1's own update still lands - different composite key.
      expect(
        provider.programs
            .firstWhere((p) => p.id == 1)
            .workouts!
            .single
            .workoutName,
        'ONE_EDIT',
      );
    });
  });

  group('6. parent deletion invalidates in-flight child work', () {
    test('a deleteProgram that completes first discards a slower child '
        'updateWorkout for that program', () async {
      await seed([
        program(1, workouts: [workout(10)]),
        program(2, workouts: [workout(20)]),
      ]);
      epoch.activate(1);
      final updC = Completer<void>();
      when(repo.updateWorkout(10, any)).thenAnswer((_) => updC.future);
      when(repo.deleteProgram(1)).thenAnswer((_) async {});

      final updF = provider.updateWorkout(10, workout(10, name: 'EDIT'));
      await provider.deleteProgram(1);
      expect(provider.programs.map((p) => p.id), [2]);
      final notifiesAfterDelete = notifyCount;

      updC.complete();
      // The child mutation is invalidated by the parent delete: it reports
      // failure, publishes nothing, and does not notify.
      expect(await updF, isFalse);
      expect(provider.programs.map((p) => p.id), [2]);
      expect(notifyCount, notifiesAfterDelete);
    });

    test('a child mutation for a DIFFERENT program is unaffected by the '
        'delete', () async {
      await seed([
        program(1, workouts: [workout(10)]),
        program(2, workouts: [workout(20)]),
      ]);
      epoch.activate(1);
      final updC = Completer<void>();
      when(repo.updateWorkout(20, any)).thenAnswer((_) => updC.future);
      when(repo.deleteProgram(1)).thenAnswer((_) async {});

      final updF = provider.updateWorkout(
        20,
        workout(20, programId: 2, name: 'EDIT'),
      );
      await provider.deleteProgram(1);

      updC.complete();
      await updF;
      expect(provider.programs.single.workouts!.single.workoutName, 'EDIT');
    });
  });

  group('7. shared error ownership (last claimant across axes)', () {
    test('an older loadPrograms error cannot clobber a newer updateProgram '
        'error', () async {
      await seed([program(1)]);
      epoch.activate(1);
      final loadC = Completer<List<Program>>();
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => loadC.future);
      final updC = Completer<void>();
      when(repo.updateProgram(1, any)).thenAnswer((_) => updC.future);

      final loadF = provider.loadPrograms();
      final updF = provider.updateProgram(1, program(1));

      updC.completeError(Exception('update failed'));
      await updF;
      expect(provider.errorMessage, contains('update'));

      loadC.completeError(Exception('load failed'));
      await loadF;
      // The newer claimant (update) still owns the slot.
      expect(provider.errorMessage, contains('update'));
    });
  });

  group('8. activity-flag ownership', () {
    test('a superseded createProgram does not flip isCreating off', () async {
      epoch.activate(1);
      final c1 = Completer<Program>();
      when(repo.createProgram(any)).thenAnswer((inv) {
        final p = inv.positionalArguments[0] as Program;
        return p.id == 1 ? c1.future : Future.value(p);
      });

      final f1 = provider.createProgram(program(1));
      await provider.createProgram(program(2)); // newer - owns _isCreating
      expect(provider.isCreating, isFalse); // newer finished

      // Re-open: start a newer create that stays pending.
      final c3 = Completer<Program>();
      when(repo.createProgram(any)).thenAnswer((_) => c3.future);
      final f3 = provider.createProgram(program(3));
      expect(provider.isCreating, isTrue);

      c1.complete(program(1));
      await f1;
      // The old create's finally must not have cleared the newer's flag.
      expect(provider.isCreating, isTrue);

      c3.complete(program(3));
      await f3;
      expect(provider.isCreating, isFalse);
    });

    test(
      'clear() empties active-update tracking (isUpdating -> false)',
      () async {
        await seed([program(1)]);
        epoch.activate(1);
        final c = Completer<void>();
        when(repo.updateProgram(1, any)).thenAnswer((_) => c.future);

        final f = provider.updateProgram(1, program(1));
        expect(provider.isUpdating, isTrue);

        provider.clear();
        expect(provider.isUpdating, isFalse);

        c.complete();
        await f;
        expect(provider.isUpdating, isFalse); // stale finally cannot re-add
      },
    );
  });

  group('9. refresh-vs-mutation convergence (Order A & Order B)', () {
    test('Order A: refresh starts, mutation acks, refresh completes stale -> '
        'refresh loses (updateProgram)', () async {
      await seed([program(1, title: 'A')]);
      epoch.activate(1);
      final refreshC = Completer<List<Program>>();
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);
      when(repo.updateProgram(1, any)).thenAnswer((_) async {});

      final refreshF = provider.loadPrograms();
      await provider.updateProgram(1, program(1, title: 'EDIT'));
      expect(provider.programs.single.title, 'EDIT1');

      refreshC.complete([program(1, title: 'A')]); // pre-mutation server state
      await refreshF;

      expect(provider.programs.single.title, 'EDIT1');
    });

    test(
      'Order B: mutation HTTP in flight, refresh starts AND completes with '
      'old state, then mutation acks -> mutation reconverges (updateProgram)',
      () async {
        await seed([program(1, title: 'A')]);
        epoch.activate(1);
        final updC = Completer<void>();
        when(repo.updateProgram(1, any)).thenAnswer((_) => updC.future);

        final updF = provider.updateProgram(1, program(1, title: 'EDIT'));
        // A full refresh runs to completion with the pre-mutation server list.
        when(
          repo.getPrograms(isActive: anyNamed('isActive')),
        ).thenAnswer((_) async => [program(1, title: 'A')]);
        await provider.loadPrograms();
        expect(provider.programs.single.title, 'A1');

        updC.complete();
        await updF;
        // The post-ack apply is the convergence step.
        expect(provider.programs.single.title, 'EDIT1');
      },
    );

    test('Order B for deleteProgram: refresh re-adds the row, then delete '
        'acks -> row removed again', () async {
      await seed([program(1), program(2)]);
      epoch.activate(1);
      final delC = Completer<void>();
      when(repo.deleteProgram(1)).thenAnswer((_) => delC.future);

      final delF = provider.deleteProgram(1);
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program(1), program(2)]);
      await provider.loadPrograms();
      expect(provider.programs.map((p) => p.id), containsAll([1, 2]));

      delC.complete();
      await delF;
      expect(provider.programs.map((p) => p.id), [2]);
    });

    test('Order B for completeWorkout: refresh restores incomplete workout, '
        'then complete acks -> workout completed again', () async {
      await seed([
        program(1, workouts: [workout(10, completed: false)]),
      ]);
      epoch.activate(1);
      final cwC = Completer<void>();
      when(
        repo.completeWorkout(10, notes: anyNamed('notes')),
      ).thenAnswer((_) => cwC.future);

      final cwF = provider.completeWorkout(10);
      when(repo.getPrograms(isActive: anyNamed('isActive'))).thenAnswer(
        (_) async => [
          program(1, workouts: [workout(10, completed: false)]),
        ],
      );
      await provider.loadPrograms();
      expect(provider.programs.single.workouts!.single.isCompleted, isFalse);

      cwC.complete();
      await cwF;
      expect(provider.programs.single.workouts!.single.isCompleted, isTrue);
    });

    test('Order B for createProgram: refresh already contains the server row, '
        'create acks -> no duplicate', () async {
      epoch.activate(1);
      final createC = Completer<Program>();
      when(repo.createProgram(any)).thenAnswer((_) => createC.future);

      final createF = provider.createProgram(program(5));
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program(5)]);
      await provider.loadPrograms();
      expect(provider.programs.where((p) => p.id == 5), hasLength(1));

      createC.complete(program(5));
      await createF;
      expect(provider.programs.where((p) => p.id == 5), hasLength(1));
    });
  });

  group('10. connectivity ownership', () {
    test('a connectivity event while logged out dispatches nothing', () async {
      connectivityController.add(true);
      expect(connectivityRefresh, isNull);
      verifyNever(repo.getPrograms(isActive: anyNamed('isActive')));
    });

    test('a connectivity event while logged in and idle refreshes via the '
        'same _listGen-ordered loadPrograms', () async {
      epoch.activate(1);
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program(1)]);

      connectivityController.add(true);
      expect(connectivityRefresh, isNotNull);
      await connectivityRefresh;

      expect(provider.programs.single.id, 1);
    });

    test('a connectivity-triggered refresh cannot overwrite a newer '
        'create that landed while it was in flight', () async {
      epoch.activate(1);
      final refreshC = Completer<List<Program>>();
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);

      // _programs is empty and no load is running -> the event fires a load.
      connectivityController.add(true);
      expect(connectivityRefresh, isNotNull);
      final refreshF = connectivityRefresh!;

      when(
        repo.createProgram(any),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Program);
      await provider.createProgram(program(5));
      expect(provider.programs.single.id, 5);

      // Stale refresh completes with the pre-create server list.
      refreshC.complete(<Program>[]);
      await refreshF;
      expect(provider.programs.single.id, 5);
    });

    test('a connectivity event that fires while a loadPrograms is already in '
        'flight does NOT stack a second load', () async {
      epoch.activate(1);
      final c = Completer<List<Program>>();
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => c.future);

      final manual = provider.loadPrograms(); // _isLoading == true
      connectivityController.add(true); // must be ignored - a load is running
      expect(connectivityRefresh, isNull);

      c.complete([program(1)]);
      await manual;

      verify(repo.getPrograms(isActive: anyNamed('isActive'))).called(1);
    });
  });

  group('11. clear() and dispose()', () {
    test('clear() invalidates every axis before resetting state', () async {
      await seed([
        program(1, workouts: [workout(10)]),
      ]);
      epoch.activate(1);

      final loadC = Completer<List<Program>>();
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => loadC.future);
      final updC = Completer<void>();
      when(repo.updateProgram(1, any)).thenAnswer((_) => updC.future);
      final cwC = Completer<void>();
      when(
        repo.completeWorkout(10, notes: anyNamed('notes')),
      ).thenAnswer((_) => cwC.future);
      final advC = Completer<Program>();
      when(repo.advanceProgram(1)).thenAnswer((_) => advC.future);

      final loadF = provider.loadPrograms();
      final updF = provider.updateProgram(1, program(1, title: 'EDIT'));
      final cwF = provider.completeWorkout(10);
      final advF = provider.advanceProgram(1);

      provider.clear();
      final notifiesAfterClear = notifyCount;

      loadC.complete([program(2)]);
      updC.complete();
      cwC.complete();
      advC.complete(program(1).copyWith(currentWeek: 3));
      await Future.wait([loadF, updF, cwF, advF]);

      expect(provider.programs, isEmpty);
      expect(provider.activePrograms, isEmpty);
      expect(provider.completedPrograms, isEmpty);
      expect(provider.errorMessage, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.isCreating, isFalse);
      expect(provider.isUpdating, isFalse);
      expect(provider.newlyCreatedProgramId, isNull);
      expect(notifyCount, notifiesAfterClear);
    });

    test(
      'observable lists are cleared in place (retained references empty)',
      () async {
        await seed([program(1), program(2)]);
        final progsRef = provider.programs;
        final activeRef = provider.activePrograms;

        provider.clear();

        expect(progsRef, isEmpty);
        expect(activeRef, isEmpty);
      },
    );

    test(
      'a continuation resolving after dispose() does not publish or throw',
      () async {
        await seed([program(1)]);
        epoch.activate(1);
        final c = Completer<void>();
        when(repo.updateProgram(1, any)).thenAnswer((_) => c.future);

        final f = provider.updateProgram(1, program(1, title: 'EDIT'));
        provider.dispose();

        c.complete();
        await f; // must not throw "notifyListeners after dispose"
      },
    );

    test('getTodaysWorkouts / cache reads are empty after clear()', () async {
      await seed([
        program(1, workouts: [workout(10)]),
      ]);
      provider.clear();

      expect(provider.getTodaysWorkouts(), isEmpty);
      expect(provider.getProgramFromCache(1), isNull);
    });
  });

  group('12. logged-out no-ops use each method\'s own convention', () {
    test('every async method short-circuits with no session', () async {
      // no epoch.activate
      await provider.loadPrograms();
      expect(provider.programs, isEmpty);
      expect(await provider.getProgramById(1), isNull);
      expect(await provider.createProgram(program(1)), isFalse);
      expect(await provider.updateProgram(1, program(1)), isFalse);
      expect(await provider.deleteProgram(1), isFalse);
      expect(await provider.completeProgram(1), isFalse);
      expect(await provider.recalibrateProgram(1), isFalse);
      expect(await provider.advanceProgram(1), isFalse);
      expect(await provider.getWeekWorkouts(1, 1), isEmpty);
      expect(await provider.getTodaysWorkout(1), isNull);
      expect(await provider.addWorkout(1, workout(10)), isFalse);
      expect(await provider.updateWorkout(10, workout(10)), isFalse);
      expect(await provider.swapWorkouts(10, 11), isFalse);
      expect(await provider.completeWorkout(10), isFalse);
      expect(await provider.deleteWorkout(10), isFalse);
      await expectLater(
        provider.getDeletionImpact(1),
        throwsA(isA<SessionStaleException>()),
      );

      verifyZeroInteractions(repo);
    });
  });

  group('13. same-session supersession of program mutations', () {
    test('a stale updateProgram FAILURE after a bare epoch.invalidate() (no '
        'clear) still publishes no error', () async {
      await seed([program(1)]);
      epoch.activate(1);
      final c = Completer<void>();
      when(repo.updateProgram(1, any)).thenAnswer((_) => c.future);

      final f = provider.updateProgram(1, program(1, title: 'EDIT'));
      epoch.invalidate(); // NO clear() - _errorGen is untouched

      c.completeError(Exception('server 500'));
      expect(await f, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('an older deleteProgram cannot remove a program a newer updateProgram '
        'on the same id kept', () async {
      await seed([program(1, title: 'A')]);
      epoch.activate(1);
      final delC = Completer<void>();
      when(repo.deleteProgram(1)).thenAnswer((_) => delC.future);
      when(repo.updateProgram(1, any)).thenAnswer((_) async {});

      final delF = provider.deleteProgram(1);
      await provider.updateProgram(1, program(1, title: 'EDIT'));
      expect(provider.programs.single.title, 'EDIT1');

      delC.complete();
      expect(await delF, isFalse);
      expect(provider.programs.single.title, 'EDIT1');
    });

    test('an older completeProgram cannot complete a program a newer '
        'updateProgram on the same id kept active', () async {
      await seed([program(1, active: true)]);
      epoch.activate(1);
      final cpC = Completer<void>();
      when(repo.completeProgram(1)).thenAnswer((_) => cpC.future);
      when(repo.updateProgram(1, any)).thenAnswer((_) async {});

      final cpF = provider.completeProgram(1);
      await provider.updateProgram(1, program(1, active: true, title: 'EDIT'));

      cpC.complete();
      expect(await cpF, isFalse);
      expect(provider.programs.single.isCompleted, isFalse);
      expect(provider.programs.single.isActive, isTrue);
    });

    test('an older recalibrateProgram cannot reload over a newer '
        'updateProgram on the same id', () async {
      await seed([program(1, title: 'A')]);
      epoch.activate(1);
      final recC = Completer<Map<String, dynamic>>();
      when(repo.recalibrateProgram(1)).thenAnswer((_) => recC.future);
      when(repo.updateProgram(1, any)).thenAnswer((_) async {});
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program(1, title: 'SERVER')]);

      final recF = provider.recalibrateProgram(1);
      await provider.updateProgram(1, program(1, title: 'EDIT'));
      expect(provider.programs.single.title, 'EDIT1');

      recC.complete({'ok': true});
      expect(await recF, isFalse);
      // recalibrate's loadPrograms() must NOT have run.
      expect(provider.programs.single.title, 'EDIT1');
    });

    test('a stale updateProgram finally still releases its isUpdating slot '
        'when superseded by completeProgram on the same id', () async {
      await seed([program(1, active: true)]);
      epoch.activate(1);
      final updC = Completer<void>();
      when(repo.updateProgram(1, any)).thenAnswer((_) => updC.future);
      when(repo.completeProgram(1)).thenAnswer((_) async {});

      final updF = provider.updateProgram(1, program(1, title: 'EDIT'));
      expect(provider.isUpdating, isTrue);
      await provider.completeProgram(1);

      updC.complete();
      await updF;
      expect(provider.isUpdating, isFalse);
    });

    test(
      'updateProgram locates its target by stable id, not list position',
      () async {
        await seed([
          program(1, title: 'A'),
          program(2, title: 'B'),
          program(3, title: 'C'),
        ]);
        epoch.activate(1);
        when(repo.updateProgram(any, any)).thenAnswer((_) async {});

        await provider.updateProgram(3, program(3, title: 'C_EDIT'));

        expect(
          {for (final p in provider.programs) p.id: p.title},
          {1: 'A1', 2: 'B2', 3: 'C_EDIT3'},
        );
      },
    );
  });

  group('14. same-session supersession of nested-workout mutations', () {
    test('a stale deleteWorkout after clear() returns false and does not '
        'notify', () async {
      await seed([
        program(1, workouts: [workout(10), workout(11)]),
      ]);
      epoch.activate(1);
      final c = Completer<void>();
      when(repo.deleteWorkout(10)).thenAnswer((_) => c.future);

      final f = provider.deleteWorkout(10);
      provider.clear();
      final notifiesAfterClear = notifyCount;

      c.complete();
      expect(await f, isFalse);
      expect(notifyCount, notifiesAfterClear);
    });

    test('an older addWorkout cannot append after a newer addWorkout for the '
        'same program superseded it', () async {
      await seed([
        program(1, workouts: [workout(10)]),
      ]);
      epoch.activate(1);
      final addC = Completer<ProgramWorkout>();
      var call = 0;
      when(repo.addWorkout(1, any)).thenAnswer((inv) {
        if (call++ == 0) return addC.future;
        return Future.value(inv.positionalArguments[1] as ProgramWorkout);
      });

      final f1 = provider.addWorkout(1, workout(20, name: 'OLD'));
      await provider.addWorkout(1, workout(21, name: 'NEW'));
      expect(provider.programs.single.workouts!.map((w) => w.id), [10, 21]);

      addC.complete(workout(20, name: 'OLD'));
      expect(await f1, isFalse);
      expect(provider.programs.single.workouts!.map((w) => w.id), [10, 21]);
    });

    test('Order A for swapWorkouts: an in-flight refresh that completes after '
        'the swap ack cannot restore the pre-swap order', () async {
      await seed([
        program(
          1,
          workouts: [
            workout(10, day: 1, order: 0),
            workout(11, day: 2, order: 1),
          ],
        ),
      ]);
      epoch.activate(1);
      final refreshC = Completer<List<Program>>();
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) => refreshC.future);
      when(repo.swapWorkouts(10, 11)).thenAnswer((_) async {});

      final refreshF = provider.loadPrograms();
      await provider.swapWorkouts(10, 11);
      final swapped = {
        for (final w in provider.programs.single.workouts!) w.id: w.dayNumber,
      };
      expect(swapped[10], 2);

      refreshC.complete([
        program(
          1,
          workouts: [
            workout(10, day: 1, order: 0),
            workout(11, day: 2, order: 1),
          ],
        ),
      ]);
      await refreshF;

      final after = {
        for (final w in provider.programs.single.workouts!) w.id: w.dayNumber,
      };
      expect(after[10], 2); // swap survived the stale refresh
    });
  });

  group('15. published filter / view identity', () {
    // Load an `isActive: true` filtered list and record that identity.
    Future<void> seedActiveFiltered(List<Program> programs) async {
      if (epoch.capture() == null) epoch.activate(1);
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => programs);
      await provider.loadPrograms(isActive: true);
      stubDefaults();
    }

    test('completeProgram drops the just-completed (inactive) row from an '
        'isActive:true published list', () async {
      await seedActiveFiltered([program(1, active: true)]);
      epoch.activate(1);
      when(repo.completeProgram(1)).thenAnswer((_) async {});

      await provider.completeProgram(1);

      expect(provider.programs, isEmpty);
    });

    test('createProgram does not insert a Program that does not match the '
        'published filter', () async {
      await seedActiveFiltered([program(1, active: true)]);
      epoch.activate(1);
      when(
        repo.createProgram(any),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Program);

      await provider.createProgram(program(5, active: false));

      expect(provider.programs.where((p) => p.id == 5), isEmpty);
    });

    test('createProgram DOES insert a Program that matches the published '
        'filter', () async {
      await seedActiveFiltered([program(1, active: true)]);
      epoch.activate(1);
      when(
        repo.createProgram(any),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Program);

      await provider.createProgram(program(5, active: true));

      expect(provider.programs.where((p) => p.id == 5), hasLength(1));
    });

    test('updateProgram that flips isActive out of the published filter drops '
        'the row', () async {
      await seedActiveFiltered([program(1, active: true, title: 'A')]);
      epoch.activate(1);
      when(repo.updateProgram(1, any)).thenAnswer((_) async {});

      await provider.updateProgram(1, program(1, active: false, title: 'EDIT'));

      expect(provider.programs, isEmpty);
    });

    test('advanceProgram that returns an inactive Program drops it from an '
        'isActive:true list', () async {
      await seedActiveFiltered([program(1, active: true)]);
      epoch.activate(1);
      when(
        repo.advanceProgram(1),
      ).thenAnswer((_) async => program(1, active: false, completed: true));

      await provider.advanceProgram(1);

      expect(provider.programs, isEmpty);
    });

    test(
      'an UNfiltered published list (filter == null) keeps a completed row',
      () async {
        await seed([program(1, active: true)]); // seed() loads with no isActive
        epoch.activate(1);
        when(repo.completeProgram(1)).thenAnswer((_) async {});

        await provider.completeProgram(1);

        expect(provider.programs.single.isCompleted, isTrue);
      },
    );

    test('the recorded filter is exactly the isActive argument: after '
        'loadPrograms(isActive: false) an ACTIVE created Program is NOT inserted '
        '(it would be, were the filter null or true)', () async {
      if (epoch.capture() == null) epoch.activate(1);
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => [program(1, active: false, completed: true)]);
      await provider.loadPrograms(isActive: false);
      stubDefaults();
      epoch.activate(1);
      when(
        repo.createProgram(any),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Program);

      await provider.createProgram(program(5, active: true));

      expect(provider.programs.where((p) => p.id == 5), isEmpty);
    });

    test('clear() resets the published-filter identity so the next unfiltered '
        'load admits every Program again', () async {
      await seedActiveFiltered([program(1, active: true)]);
      epoch.activate(1);

      provider.clear();

      when(repo.getPrograms(isActive: anyNamed('isActive'))).thenAnswer(
        (_) async => [program(1, active: true), program(2, active: false)],
      );
      await provider.loadPrograms(); // unfiltered
      when(repo.completeProgram(1)).thenAnswer((_) async {});

      await provider.completeProgram(1);
      // filter is null again -> the now-inactive Program 1 stays.
      expect(provider.programs.map((p) => p.id), containsAll([1, 2]));
    });

    test('clear() resets the published filter even with NO subsequent load - a '
        'later create is admitted unfiltered', () async {
      await seedActiveFiltered([program(1, active: true)]);
      epoch.activate(1);

      provider.clear();
      // No loadPrograms() here - clear() itself must have reset the filter.
      when(
        repo.createProgram(any),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Program);

      await provider.createProgram(program(5, active: false));

      expect(provider.programs.where((p) => p.id == 5), hasLength(1));
    });

    test(
      'deleteProgram removes the id regardless of the published filter',
      () async {
        await seedActiveFiltered([
          program(1, active: true),
          program(2, active: true),
        ]);
        epoch.activate(1);
        when(repo.deleteProgram(1)).thenAnswer((_) async {});

        await provider.deleteProgram(1);

        expect(provider.programs.map((p) => p.id), [2]);
      },
    );
  });

  group(
    '16. provider silently drops a typed stale exception from the repo',
    () {
      test('loadPrograms: repo throws SessionStaleException (e.g. from the '
          'overlay staleness check) -> no error, no list change', () async {
        await seed([program(1)]);
        epoch.activate(1);
        when(
          repo.getPrograms(isActive: anyNamed('isActive')),
        ).thenAnswer((_) async => throw const SessionStaleException());

        await provider.loadPrograms();

        expect(provider.errorMessage, isNull);
        expect(provider.programs.single.id, 1); // unchanged
        expect(provider.isLoading, isFalse);
      });

      test('getProgramById: repo throws SessionStaleException -> returns null, '
          'no error', () async {
        epoch.activate(1);
        when(
          repo.getProgramById(1),
        ).thenAnswer((_) async => throw const SessionStaleException());

        expect(await provider.getProgramById(1), isNull);
        expect(provider.errorMessage, isNull);
      });

      test(
        'recalibrateProgram: repo throws RequestCancelledException -> returns '
        'false, no error',
        () async {
          await seed([program(1)]);
          epoch.activate(1);
          when(
            repo.recalibrateProgram(1),
          ).thenAnswer((_) async => throw const RequestCancelledException());

          expect(await provider.recalibrateProgram(1), isFalse);
          expect(provider.errorMessage, isNull);
        },
      );
    },
  );

  group('17. internal refresh paths forward the latest requested filter', () {
    test('the 4-step race: recalibrateProgram(A) follow-up honours a NEWER '
        'loadPrograms(isActive: false) intent, never reverting to the '
        'isActive:true view that was published when it started', () async {
      // 1. active-only view is published.
      if (epoch.capture() == null) epoch.activate(1);
      when(
        repo.getPrograms(isActive: true),
      ).thenAnswer((_) async => [program(1, active: true, title: 'A')]);
      await provider.loadPrograms(isActive: true);
      expect(provider.programs.single.title, 'A1');
      epoch.activate(1);

      // 2. recalibrateProgram(1) starts (HTTP pending).
      final recC = Completer<Map<String, dynamic>>();
      when(repo.recalibrateProgram(1)).thenAnswer((_) => recC.future);
      final recF = provider.recalibrateProgram(1);

      // 3. a NEWER manual loadPrograms(isActive: false) starts while
      //    recalibration is still pending -> records the newer intent.
      final manualC = Completer<List<Program>>();
      var falseCall = 0;
      when(repo.getPrograms(isActive: false)).thenAnswer(
        (_) =>
            falseCall++ == 0
                ? manualC.future
                : Future.value([
                  program(2, active: false, completed: true, title: 'INACTIVE'),
                ]),
      );
      final manualF = provider.loadPrograms(isActive: false);

      // 4. recalibration acknowledges -> its follow-up reload must target
      //    isActive:false (the newer intent), not the published true.
      recC.complete({'ok': true});
      await recF;

      expect(provider.programs.map((p) => p.title), ['INACTIVE2']);

      // The older manual load loses the _listGen race and publishes nothing.
      manualC.complete([program(9, active: false, title: 'STALE')]);
      await manualF;
      expect(provider.programs.map((p) => p.title), ['INACTIVE2']);

      // The published filter is now `false`: an active create is NOT added.
      when(
        repo.createProgram(any),
      ).thenAnswer((inv) async => inv.positionalArguments[0] as Program);
      await provider.createProgram(program(7, active: true));
      expect(provider.programs.where((p) => p.id == 7), isEmpty);
    });

    test('recalibrateProgram with no concurrent load reloads the current '
        'filtered view (not unfiltered)', () async {
      if (epoch.capture() == null) epoch.activate(1);
      when(
        repo.getPrograms(isActive: true),
      ).thenAnswer((_) async => [program(1, active: true)]);
      await provider.loadPrograms(isActive: true);
      epoch.activate(1);

      when(repo.recalibrateProgram(1)).thenAnswer((_) async => {'ok': true});
      clearInteractions(repo);
      when(
        repo.getPrograms(isActive: true),
      ).thenAnswer((_) async => [program(1, active: true, title: 'RELOADED')]);

      await provider.recalibrateProgram(1);

      expect(provider.programs.single.title, 'RELOADED1');
      verify(repo.getPrograms(isActive: true)).called(1);
      verifyNever(repo.getPrograms(isActive: null));
      verifyNever(repo.getPrograms(isActive: false));
    });

    test(
      'recalibrateProgram follow-up targets the latest REQUESTED filter, not '
      'the published one, when the last requested filtered load FAILED to '
      'publish (repo threw) - standalone kill for recalibrate -> '
      '_publishedIsActiveFilter',
      () async {
        if (epoch.capture() == null) epoch.activate(1);
        // published = true, latestRequested = true
        when(
          repo.getPrograms(isActive: true),
        ).thenAnswer((_) async => [program(1, active: true)]);
        await provider.loadPrograms(isActive: true);

        // a newer isActive:false load is requested but throws -> published
        // stays true while latestRequested becomes false (the two diverge).
        when(
          repo.getPrograms(isActive: false),
        ).thenAnswer((_) async => throw const SessionStaleException());
        await provider.loadPrograms(isActive: false);

        epoch.activate(1);
        when(repo.recalibrateProgram(1)).thenAnswer((_) async => {'ok': true});
        clearInteractions(repo);
        when(repo.getPrograms(isActive: false)).thenAnswer(
          (_) async => [
            program(2, active: false, completed: true, title: 'INACTIVE'),
          ],
        );

        await provider.recalibrateProgram(1);

        expect(provider.programs.map((p) => p.title), ['INACTIVE2']);
        verify(repo.getPrograms(isActive: false)).called(1);
        verifyNever(repo.getPrograms(isActive: true));
        verifyNever(repo.getPrograms(isActive: null));
      },
    );

    test(
      'a connectivity-restored refresh forwards the latest requested filter, '
      'not unfiltered (the weaker "not bare loadPrograms()" guard; the '
      'published-vs-requested divergence is killed by the next test)',
      () async {
        epoch.activate(1);
        when(
          repo.getPrograms(isActive: true),
        ).thenAnswer((_) async => [program(1, active: true)]);
        await provider.loadPrograms(isActive: true);
        clearInteractions(repo);
        when(
          repo.getPrograms(isActive: anyNamed('isActive')),
        ).thenAnswer((_) async => <Program>[]);

        connectivityController.add(true);
        expect(connectivityRefresh, isNotNull);
        await connectivityRefresh;

        verify(repo.getPrograms(isActive: true)).called(1);
        verifyNever(repo.getPrograms(isActive: null));
      },
    );

    test(
      'when the newest loadPrograms(isActive: false) FAILED to publish (repo '
      'threw), a connectivity refresh retries THAT requested filter, not the '
      'older successfully-published one',
      () async {
        epoch.activate(1);
        // 1. a true-filtered load succeeds and publishes.
        when(
          repo.getPrograms(isActive: true),
        ).thenAnswer((_) async => [program(1, active: true)]);
        await provider.loadPrograms(isActive: true);

        // 2. a newer false-filtered load is requested but the repo throws, so
        //    it never publishes: _publishedIsActiveFilter stays `true` while
        //    _latestRequestedIsActiveFilter becomes `false`.
        when(
          repo.getPrograms(isActive: false),
        ).thenAnswer((_) async => throw const SessionStaleException());
        await provider.loadPrograms(isActive: false);

        clearInteractions(repo);
        when(
          repo.getPrograms(isActive: anyNamed('isActive')),
        ).thenAnswer((_) async => <Program>[]);

        // 3. reconnect -> retry the filter the user actually asked for.
        connectivityController.add(true);
        await connectivityRefresh;

        verify(repo.getPrograms(isActive: false)).called(1);
        verifyNever(repo.getPrograms(isActive: true));
      },
    );

    test('clear() resets the latest-requested filter so a later connectivity '
        'refresh is unfiltered again', () async {
      epoch.activate(1);
      when(
        repo.getPrograms(isActive: true),
      ).thenAnswer((_) async => [program(1, active: true)]);
      await provider.loadPrograms(isActive: true);

      provider.clear();
      epoch.activate(1);
      clearInteractions(repo);
      when(
        repo.getPrograms(isActive: anyNamed('isActive')),
      ).thenAnswer((_) async => <Program>[]);

      connectivityController.add(true);
      await connectivityRefresh;

      verify(repo.getPrograms(isActive: null)).called(1);
      verifyNever(repo.getPrograms(isActive: true));
    });
  });
}
