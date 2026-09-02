import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/exercise.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';

@GenerateMocks([SessionRepository, ConnectivityService])
import 'sessions_provider_session_ownership_test.mocks.dart';

/// Proves [SessionsProvider] never lets a repository result, error, `finally`
/// cleanup, or Isar-watch stream event that began under user A land on the
/// state user B now sees through this same app-scoped instance; that within
/// one session an older request / mutation can never overwrite a newer one;
/// that the reactive watch is bound to the captured user + generation +
/// exact subscription instance; and that `clear()` / `dispose()` invalidate
/// every generation before resetting state.
///
/// Real [UserSessionEpoch]; the repository is mocked so `Completer`s give
/// exact control over when each continuation resolves - no wall-clock delay,
/// no `Future.delayed`, no `Timer`, no `pumpEventQueue` / `_settle`, no
/// generic `Future.value()` pumping. The Isar watch is a per-install
/// `sync: true` [StreamController] so `.add()` delivers synchronously.
void main() {
  late MockSessionRepository repo;
  late UserSessionEpoch epoch;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late SessionsProvider provider;
  late int notifyCount;
  Future<void>? connectivityRefresh;

  // One controller per _installWatch call, in install order.
  late List<({int userId, StreamController<List<Session>> controller})> watches;

  // Date DESCENDING with id, so the provider's date-desc sort makes list
  // order equal to ascending id order - assertions can use plain id lists.
  Session session(
    int id, {
    int userId = 1,
    String status = 'draft',
    String? name,
    int? programId,
    int? programWorkoutId,
    DateTime? date,
  }) => Session(
    id: id,
    userId: userId,
    date: date ?? DateTime(2024, 6, 1).subtract(Duration(days: id)),
    type: 'Workout',
    status: status,
    name: name,
    programId: programId,
    programWorkoutId: programWorkoutId,
  );

  StreamController<List<Session>> newWatch(int userId) {
    final c = StreamController<List<Session>>(sync: true);
    watches.add((userId: userId, controller: c));
    return c;
  }

  void stubDefaults() {
    when(
      repo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => <Session>[]);
    when(
      repo.watchSessions(any),
    ).thenAnswer((inv) => newWatch(inv.positionalArguments[0] as int).stream);
    when(repo.getSession(any)).thenAnswer((_) async => session(1));
    when(
      repo.createSession(any),
    ).thenAnswer((inv) async => inv.positionalArguments[0] as Session);
    when(repo.deleteSession(any)).thenAnswer((_) async => true);
    when(repo.archiveSession(any)).thenAnswer((_) async => true);
    when(repo.updateSessionStatus(any, any)).thenAnswer(
      (inv) async => session(
        inv.positionalArguments[0] as int,
        status: inv.positionalArguments[1] as String,
      ),
    );
    when(repo.updateWorkoutDate(any, any)).thenAnswer((_) async {});
    when(
      repo.createSessionFromProgramWorkout(any, any, any, any),
    ).thenAnswer((_) async => session(99, programId: 5));
  }

  setUp(() {
    repo = MockSessionRepository();
    watches = [];
    stubDefaults();
    epoch = UserSessionEpoch();
    connectivity = MockConnectivityService();
    connectivityController = StreamController<bool>.broadcast(sync: true);
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    provider = SessionsProvider(repo, epoch, connectivity);
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
    for (final w in watches) {
      if (!w.controller.isClosed) await w.controller.close();
    }
  });

  // Seed the list under an active session (user 1) and settle the watch.
  Future<void> seed(List<Session> list) async {
    if (epoch.capture() == null) epoch.activate(1);
    when(
      repo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => list);
    await provider.loadSessions();
    stubDefaults();
  }

  // ==========================================================================
  group('1. async continuation ownership', () {
    test('a slow loadSessions completing after clear() cannot repopulate the '
        'list or notify', () async {
      epoch.activate(1);
      final c = Completer<List<Session>>();
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadSessions();
      epoch.invalidate();
      provider.clear();
      final before = notifyCount;

      c.complete([session(1)]);
      await f;

      expect(provider.sessions, isEmpty);
      expect(provider.watchedUserId, isNull);
      expect(notifyCount, before);
    });

    test('a slow loadSessions completing after user B logs in cannot overwrite '
        "B's list", () async {
      epoch.activate(1);
      final aC = Completer<List<Session>>();
      final bC = Completer<List<Session>>();
      var call = 0;
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

      final aF = provider.loadSessions();
      epoch.invalidate();
      epoch.activate(2);
      final bF = provider.loadSessions();

      bC.complete([session(9, userId: 2)]);
      await bF;
      expect(provider.sessions.single.id, 9);

      aC.complete([session(1)]);
      await aF;
      expect(provider.sessions.single.id, 9);
      expect(provider.watchedUserId, 2);
    });

    test(
      'a stale deleteSession success cannot edit B\'s list or notify',
      () async {
        await seed([session(1), session(2)]);
        final c = Completer<bool>();
        when(repo.deleteSession(1)).thenAnswer((_) => c.future);

        final f = provider.deleteSession(1);
        epoch.invalidate();
        provider.clear();
        final before = notifyCount;

        c.complete(true);
        expect(await f, isFalse);
        expect(provider.sessions, isEmpty);
        expect(notifyCount, before);
      },
    );

    test('a stale mutation failure does not publish its error', () async {
      await seed([session(1)]);
      final c = Completer<bool>();
      when(repo.archiveSession(1)).thenAnswer((_) => c.future);

      final f = provider.archiveSession(1);
      epoch.invalidate();
      provider.clear();

      c.completeError(Exception('boom'));
      expect(await f, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test(
      'a stale archiveSession SUCCESS cannot edit B\'s list or notify',
      () async {
        await seed([session(1), session(2)]);
        final c = Completer<bool>();
        when(repo.archiveSession(1)).thenAnswer((_) => c.future);

        final f = provider.archiveSession(1);
        epoch.invalidate();
        provider.clear();
        final before = notifyCount;

        c.complete(true);
        expect(await f, isFalse);
        expect(provider.sessions, isEmpty);
        expect(notifyCount, before);
      },
    );

    test(
      'a stale startNewWorkout SUCCESS cannot insert into B\'s list',
      () async {
        epoch.activate(1);
        final c = Completer<Session>();
        when(repo.createSession(any)).thenAnswer((_) => c.future);

        final f = provider.startNewWorkout(name: 'x');
        epoch.invalidate();
        provider.clear();
        epoch.activate(2);
        final before = notifyCount;

        c.complete(session(50, userId: 1));
        expect(await f, isNull);
        expect(provider.sessions, isEmpty);
        expect(notifyCount, before);
      },
    );

    test('a stale loadSessions finally cannot clear a newer session\'s '
        'isLoading', () async {
      epoch.activate(1);
      final aC = Completer<List<Session>>();
      final bC = Completer<List<Session>>();
      var call = 0;
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

      final aF = provider.loadSessions();
      epoch.invalidate();
      epoch.activate(2);
      final bF = provider.loadSessions();
      expect(provider.isLoading, isTrue);

      aC.complete([session(1)]);
      await aF;
      expect(provider.isLoading, isTrue);

      bC.complete([session(2, userId: 2)]);
      await bF;
      expect(provider.isLoading, isFalse);
    });

    test('a same-session mutation that bumps _listGen mid-load does NOT strand '
        'the spinner (finally is _loadGen-guarded)', () async {
      await seed([session(1)]);
      final loadC = Completer<List<Session>>();
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => loadC.future);
      when(repo.deleteSession(1)).thenAnswer((_) async => true);

      final loadF = provider.loadSessions();
      expect(provider.isLoading, isTrue);
      await provider.deleteSession(1); // bumps _listGen while load is awaiting

      loadC.complete([session(1)]);
      await loadF;

      // The load lost its publication (deleteSession won _listGen), but the
      // spinner is off and the delete stands.
      expect(provider.isLoading, isFalse);
      expect(provider.sessions, isEmpty);
    });

    test('an older same-session loadSessions(showLoading) finally cannot clear '
        "a newer one's spinner", () async {
      epoch.activate(1);
      final aC = Completer<List<Session>>();
      final bC = Completer<List<Session>>();
      var call = 0;
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => (call++ == 0) ? aC.future : bC.future);

      final aF = provider.loadSessions(); // A, showLoading
      final bF = provider.loadSessions(); // B, same session, showLoading
      expect(provider.isLoading, isTrue);

      aC.complete([session(1)]);
      await aF;
      // A's finally must not have flipped B's spinner off (loadGen guard).
      expect(provider.isLoading, isTrue);

      bC.complete([session(2)]);
      await bF;
      expect(provider.isLoading, isFalse);
    });

    test('an older loadSessions loses to a newer one', () async {
      epoch.activate(1);
      final c1 = Completer<List<Session>>();
      final c2 = Completer<List<Session>>();
      var call = 0;
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => (call++ == 0) ? c1.future : c2.future);

      final f1 = provider.loadSessions();
      final f2 = provider.loadSessions();

      c2.complete([session(2)]);
      await f2;
      c1.complete([session(1)]);
      await f1;

      expect(provider.sessions.single.id, 2);
    });

    test('a stale getSessionById result never reaches its caller', () async {
      epoch.activate(1);
      final c = Completer<Session>();
      when(repo.getSession(7)).thenAnswer((_) => c.future);

      final f = provider.getSessionById(7);
      epoch.invalidate();

      c.complete(session(7));
      expect(await f, isNull);
    });
  });

  // ==========================================================================
  group('2. A -> B -> A uses generation identity', () {
    test('an A-generation loadSessions that resolves after B then A-again does '
        'not publish', () async {
      epoch.activate(1); // A gen 1
      final c = Completer<List<Session>>();
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadSessions();
      epoch.invalidate(); // gen 2
      epoch.activate(2); // B gen 3
      epoch.invalidate(); // gen 4
      epoch.activate(1); // A again, gen 5 - same userId, different generation

      c.complete([session(1)]);
      await f;

      // The A-gen-1 token is not current (gen 5 now), so nothing published.
      expect(provider.sessions, isEmpty);
      expect(provider.watchedUserId, isNull);
    });
  });

  // ==========================================================================
  group('3. same-session per-session ordering', () {
    test('deletes to two different sessions run independently', () async {
      await seed([session(1), session(2), session(3)]);
      final c1 = Completer<bool>();
      final c2 = Completer<bool>();
      when(repo.deleteSession(1)).thenAnswer((_) => c1.future);
      when(repo.deleteSession(2)).thenAnswer((_) => c2.future);

      final f1 = provider.deleteSession(1);
      final f2 = provider.deleteSession(2);

      c2.complete(true);
      await f2;
      expect(provider.sessions.map((s) => s.id), [1, 3]);

      c1.complete(true);
      await f1;
      expect(provider.sessions.map((s) => s.id), [3]);
    });

    test('an older updateWorkoutDate cannot resurrect a newer deleteSession '
        'on the same id', () async {
      await seed([session(1), session(2)]);
      final updC = Completer<void>();
      when(repo.updateWorkoutDate(1, any)).thenAnswer((_) => updC.future);
      when(repo.deleteSession(1)).thenAnswer((_) async => true);

      final updF = provider.updateWorkoutDate(1, DateTime(2025, 5, 5));
      await provider.deleteSession(1);
      expect(provider.sessions.map((s) => s.id), [2]);

      updC.complete();
      expect(await updF, isFalse);
      expect(provider.sessions.map((s) => s.id), [2]);
    });

    test('an older deleteSession cannot remove a session a newer '
        'updateWorkoutDate on the same id kept', () async {
      await seed([session(1), session(2)]);
      final delC = Completer<bool>();
      when(repo.deleteSession(1)).thenAnswer((_) => delC.future);
      when(repo.updateWorkoutDate(1, any)).thenAnswer((_) async {});

      final delF = provider.deleteSession(1);
      await provider.updateWorkoutDate(1, DateTime(2025, 7, 7));
      expect(provider.sessions.map((s) => s.id), [1, 2]);

      delC.complete(true);
      expect(await delF, isFalse);
      // The stale delete must not remove the session the newer update kept.
      expect(provider.sessions.map((s) => s.id), [1, 2]);
      expect(
        provider.sessions.firstWhere((s) => s.id == 1).date,
        DateTime(2025, 7, 7),
      );
    });

    test('an older updateSessionDateForProgramWorkout cannot overwrite a date '
        'a newer updateWorkoutDate on the same session set', () async {
      await seed([session(1, programWorkoutId: 77, status: 'planned')]);
      final pwC = Completer<void>();
      var call = 0;
      when(repo.updateWorkoutDate(1, any)).thenAnswer((_) {
        // first call = the program-workout date update (held); second = the
        // newer plain updateWorkoutDate (immediate).
        return (call++ == 0) ? pwC.future : Future<void>.value();
      });

      final pwF = provider.updateSessionDateForProgramWorkout(
        programWorkoutId: 77,
        newScheduledDate: DateTime(2025, 3, 3),
      );
      await provider.updateWorkoutDate(1, DateTime(2025, 9, 9));
      expect(provider.sessions.single.date, DateTime(2025, 9, 9));

      pwC.complete();
      expect(await pwF, isFalse);
      // The stale program-workout date update must not clobber the newer date.
      expect(provider.sessions.single.date, DateTime(2025, 9, 9));
    });

    test('an older startPlannedWorkout cannot undo a newer archiveSession on '
        'the same id', () async {
      await seed([session(1, status: 'planned'), session(2)]);
      final startC = Completer<Session>();
      when(
        repo.updateSessionStatus(1, 'in_progress'),
      ).thenAnswer((_) => startC.future);
      when(repo.archiveSession(1)).thenAnswer((_) async => true);

      final startF = provider.startPlannedWorkout(1);
      await provider.archiveSession(1);
      expect(provider.sessions.map((s) => s.id), [2]);

      startC.complete(session(1, status: 'in_progress'));
      expect(await startF, isFalse);
      expect(provider.sessions.map((s) => s.id), [2]);
    });
  });

  // ==========================================================================
  group('4. shared error / activity ownership', () {
    test('an older loadSessions error cannot clobber a newer deleteSession '
        'error', () async {
      await seed([session(1)]);
      final loadC = Completer<List<Session>>();
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => loadC.future);
      final delC = Completer<bool>();
      when(repo.deleteSession(1)).thenAnswer((_) => delC.future);

      final loadF = provider.loadSessions();
      final delF = provider.deleteSession(1);

      delC.complete(false); // repo says "not deleted"
      await delF;
      expect(provider.errorMessage, 'Failed to delete session');

      loadC.completeError(Exception('load failed'));
      await loadF;
      expect(provider.errorMessage, 'Failed to delete session');
    });

    test('clearError claims the slot so an older in-flight op cannot '
        're-populate it', () async {
      await seed([session(1)]);
      final delC = Completer<bool>();
      when(repo.deleteSession(1)).thenAnswer((_) => delC.future);

      final delF = provider.deleteSession(1);
      provider.clearError();

      delC.complete(false);
      await delF;
      expect(provider.errorMessage, isNull);
    });
  });

  // ==========================================================================
  group('5. watch installation ownership', () {
    test(
      'a logged-out loadSessions installs no watch and calls no repo',
      () async {
        // no epoch.activate
        await provider.loadSessions();

        expect(watches, isEmpty);
        expect(provider.watchedUserId, isNull);
        verifyNever(repo.watchSessions(any));
        verifyNever(repo.getSessions(waitForSync: anyNamed('waitForSync')));
      },
    );

    test('a loadSessions under A installs a watch explicitly for A', () async {
      epoch.activate(1);
      await provider.loadSessions();

      expect(watches, hasLength(1));
      expect(watches.single.userId, 1);
      expect(provider.watchedUserId, 1);
      verify(repo.watchSessions(1)).called(1);
    });

    test('a loadSessions started under A but completing after logout / B '
        'login installs no A watch', () async {
      epoch.activate(1);
      final c = Completer<List<Session>>();
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadSessions();
      epoch.invalidate();
      epoch.activate(2);

      c.complete([session(1)]);
      await f;

      expect(watches, isEmpty);
      expect(provider.watchedUserId, isNull);
      verifyNever(repo.watchSessions(any));
    });

    test(
      'the watched user is exactly token.userId, never a live re-read',
      () async {
        epoch.activate(3);
        await provider.loadSessions();
        expect(watches.single.userId, 3);
        expect(provider.watchedUserId, 3);
      },
    );
  });

  // ==========================================================================
  group('6. stream event ownership', () {
    test(
      "a data event from A's watch after B logs in does not publish",
      () async {
        await seed([session(1)]);
        final aWatch = watches.single.controller;

        epoch.invalidate();
        epoch.activate(2);
        final before = notifyCount;

        aWatch.add([session(1), session(5)]);

        expect(provider.sessions.map((s) => s.id), [1]);
        expect(notifyCount, before);
      },
    );

    test(
      'an error event is swallowed (list + notify unchanged) but does NOT '
      'kill the current watch - a later data event still publishes',
      () async {
        await seed([session(1)]);
        final watch = watches.single.controller;
        final before = notifyCount;

        // Error on the CURRENT (owned) watch: no publish, no notify.
        watch.addError(Exception('stream boom'));
        expect(provider.sessions.map((s) => s.id), [1]);
        expect(notifyCount, before);

        // The subscription survived the error (cancelOnError: false): a
        // subsequent valid data event still publishes.
        watch.add([session(1), session(2)]);
        expect(provider.sessions.map((s) => s.id), [1, 2]);
        expect(notifyCount, greaterThan(before));
      },
    );

    test('an error event from A\'s watch after B logs in is dropped', () async {
      await seed([session(1)]);
      final aWatch = watches.single.controller;

      epoch.invalidate();
      epoch.activate(2);
      final before = notifyCount;

      aWatch.addError(Exception('stream boom'));
      // A valid data event from A's stale watch is also dropped.
      aWatch.add([session(1), session(5)]);

      expect(provider.sessions.map((s) => s.id), [1]);
      expect(notifyCount, before);
    });

    test('a done event from a superseded watch does not detach the current '
        'subscription', () async {
      await seed([session(1)]);
      final aWatch = watches.single.controller;

      // Reinstall (still user 1) -> aWatch is superseded.
      await provider.loadSessions();
      expect(watches, hasLength(2));
      expect(provider.watchedUserId, 1);

      await aWatch.close(); // fires onDone for the OLD subscription

      // Current watch (watches[1]) is still owned.
      expect(provider.watchedUserId, 1);
    });

    test('a stale data event cannot resurrect a session a newer delete '
        'removed', () async {
      await seed([session(1), session(2)]);
      final preWatch = watches.first.controller;

      await provider.deleteSession(1);
      expect(provider.sessions.map((s) => s.id), [2]);

      // The delete re-armed the watch: the pre-mutation subscription is no
      // longer current, so a stale snapshot still containing session 1 that
      // it delivers cannot resurrect it.
      expect(preWatch.hasListener, isFalse);
      preWatch.add([session(1), session(2)]);
      expect(provider.sessions.map((s) => s.id), [2]);

      // The re-armed subscription is the authority; its post-delete snapshot
      // (session 1 already filtered as pending_delete) stays converged.
      watches.last.controller.add([session(2)]);
      expect(provider.sessions.map((s) => s.id), [2]);
    });
  });

  // ==========================================================================
  group('7. subscription replacement ordering', () {
    test('a replacement cancels exactly the old subscription instance and '
        'keeps the new one', () async {
      await seed([session(1)]);
      final first = watches.single.controller;
      expect(first.hasListener, isTrue);

      await provider.loadSessions();
      final second = watches[1].controller;

      expect(first.hasListener, isFalse);
      expect(second.hasListener, isTrue);
      expect(provider.watchedUserId, 1);
    });

    test('an older (superseded) loadSessions cannot replace a newer '
        "session's watch", () async {
      epoch.activate(1);
      final aC = Completer<List<Session>>();
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => aC.future);

      final aF = provider.loadSessions(); // A, pending
      epoch.invalidate();
      epoch.activate(2);
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => [session(9, userId: 2)]);
      await provider.loadSessions(); // B installs its watch
      expect(watches.single.userId, 2);
      final bWatch = watches.single.controller;

      aC.complete([session(1)]);
      await aF; // A resolves last - must NOT install/replace

      expect(watches, hasLength(1));
      expect(bWatch.hasListener, isTrue);
      expect(provider.watchedUserId, 2);
    });

    test(
      'duplicate refresh() calls do not create duplicate active watches',
      () async {
        epoch.activate(1);
        final c1 = Completer<List<Session>>();
        final c2 = Completer<List<Session>>();
        var call = 0;
        when(
          repo.getSessions(waitForSync: anyNamed('waitForSync')),
        ).thenAnswer((_) => (call++ == 0) ? c1.future : c2.future);

        final f1 = provider.refresh();
        final f2 = provider.refresh();

        c1.complete([session(1)]);
        await f1;
        c2.complete([session(1)]);
        await f2;

        // Only the newest load installs a watch.
        expect(watches.where((w) => w.controller.hasListener), hasLength(1));
      },
    );
  });

  // ==========================================================================
  group('8. watch / list convergence', () {
    test(
      'an initial load result cannot overwrite a newer stream snapshot',
      () async {
        // First load installs a watch.
        await seed([session(1)]);
        final watch = watches.single.controller;

        // A second load whose getSessions is slow.
        final slow = Completer<List<Session>>();
        when(
          repo.getSessions(waitForSync: anyNamed('waitForSync')),
        ).thenAnswer((_) => slow.future);
        final f = provider.loadSessions(showLoading: false);

        // The still-current watch publishes a fresher snapshot mid-load.
        watch.add([session(1), session(2), session(3)]);
        expect(provider.sessions.map((s) => s.id), [1, 2, 3]);

        // The slow initial load resolves with an OLDER, smaller snapshot.
        slow.complete([session(1)]);
        await f;

        // It must not have overwritten the fresher stream snapshot.
        expect(provider.sessions.map((s) => s.id), [1, 2, 3]);
      },
    );
  });

  // ==========================================================================
  group('9. mutation / stream convergence (no duplicates)', () {
    test('startNewWorkout insert + a watch snapshot containing it -> no '
        'duplicate', () async {
      await seed(<Session>[]);
      final created = session(50, name: 'W');
      when(repo.createSession(any)).thenAnswer((_) async => created);

      final result = await provider.startNewWorkout(name: 'W');
      expect(result!.id, 50);
      expect(provider.sessions.map((s) => s.id), [50]);

      // The create re-armed the watch; its authoritative snapshot already
      // contains the new row -> no duplicate.
      watches.last.controller.add([created]);
      expect(provider.sessions.map((s) => s.id), [50]);
    });

    test(
      'deleteSession removeWhere + a post-delete watch snapshot -> stable',
      () async {
        await seed([session(1), session(2)]);
        await provider.deleteSession(1);
        watches.last.controller.add([session(2)]);
        expect(provider.sessions.map((s) => s.id), [2]);
      },
    );
  });

  // ==========================================================================
  group('10. connectivity / lifecycle ownership', () {
    test('a connectivity online event while logged in as A refreshes and '
        'installs the A watch', () async {
      epoch.activate(1);
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) async => [session(1)]);

      connectivityController.add(true);
      expect(connectivityRefresh, isNotNull);
      await connectivityRefresh;

      expect(provider.sessions.map((s) => s.id), [1]);
      expect(provider.watchedUserId, 1);
    });

    test(
      'a connectivity online event while logged out dispatches nothing',
      () async {
        // no epoch.activate
        connectivityController.add(true);

        expect(connectivityRefresh, isNull);
        expect(watches, isEmpty);
        verifyNever(repo.getSessions(waitForSync: anyNamed('waitForSync')));
        verifyNever(repo.watchSessions(any));
      },
    );

    test('a connectivity event while a load is already running does not stack '
        'a second load', () async {
      epoch.activate(1);
      final c = Completer<List<Session>>();
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => c.future);

      final f = provider.loadSessions(); // sets _isLoading = true
      connectivityController.add(true); // must be ignored
      c.complete([session(1)]);
      await f;

      verify(repo.getSessions(waitForSync: anyNamed('waitForSync'))).called(1);
    });
  });

  // ==========================================================================
  group('11. clear() and dispose()', () {
    test('clear() cancels the watch, empties in place, and an in-flight load '
        'cannot reinstall', () async {
      await seed([session(1), session(2)]);
      final watch = watches.single.controller;
      final ref = provider.sessions;

      final slow = Completer<List<Session>>();
      when(
        repo.getSessions(waitForSync: anyNamed('waitForSync')),
      ).thenAnswer((_) => slow.future);
      final f = provider.loadSessions();

      provider.clear();
      expect(watch.hasListener, isFalse);
      expect(ref, isEmpty); // cleared in place
      expect(provider.watchedUserId, isNull);

      slow.complete([session(3)]);
      await f;

      expect(provider.sessions, isEmpty);
      expect(provider.watchedUserId, isNull);
      // No new watch installed by the stale load.
      expect(watches.where((w) => w.controller.hasListener), isEmpty);
    });

    test('after clear(), a pending watch event does not publish', () async {
      await seed([session(1)]);
      final watch = watches.single.controller;

      provider.clear();
      final before = notifyCount;
      // The controller may already be cancelled; guard the add.
      if (!watch.isClosed && watch.hasListener) {
        watch.add([session(1), session(9)]);
      }

      expect(provider.sessions, isEmpty);
      expect(notifyCount, before);
    });

    test('a continuation resolving after dispose() publishes nothing and does '
        'not throw', () async {
      await seed([session(1)]);
      final c = Completer<bool>();
      when(repo.deleteSession(1)).thenAnswer((_) => c.future);

      final f = provider.deleteSession(1);
      provider.dispose();

      c.complete(true);
      await f; // must not throw "notifyListeners after dispose"
    });

    test(
      'a watch event after dispose() publishes nothing and does not throw',
      () async {
        await seed([session(1)]);
        final watch = watches.single.controller;

        provider.dispose();
        if (!watch.isClosed && watch.hasListener) {
          watch.add([session(1), session(2)]);
        }
        // no throw, nothing to assert on a disposed provider
      },
    );
  });

  // ==========================================================================
  group('12. logged-out no-ops', () {
    test('every async method short-circuits with no session', () async {
      // no epoch.activate
      await provider.loadSessions();
      expect(provider.sessions, isEmpty);
      expect(await provider.getSessionById(1), isNull);
      expect(await provider.deleteSession(1), isFalse);
      expect(await provider.archiveSession(1), isFalse);
      expect(await provider.startNewWorkout(name: 'x'), isNull);
      expect(await provider.startPlannedWorkout(1), isFalse);
      expect(await provider.updateWorkoutDate(1, DateTime(2025)), isFalse);
      expect(
        await provider.createPlannedWorkout(
          name: 'x',
          scheduledDate: DateTime(2025),
        ),
        isNull,
      );
      expect(
        await provider.createRecurringPlannedWorkouts(
          name: 'x',
          startDate: DateTime(2025),
          frequency: 'daily',
          occurrences: 3,
        ),
        isEmpty,
      );
      expect(
        await provider.updateSessionDateForProgramWorkout(
          programWorkoutId: 1,
          newScheduledDate: DateTime(2025),
        ),
        isTrue, // no linked session found -> nothing to do
      );

      verifyZeroInteractions(repo);
    });

    test(
      'startProgramWorkout with no session returns null and calls no repo',
      () async {
        final pw = ProgramWorkout(
          id: 1,
          programId: 5,
          weekNumber: 1,
          dayNumber: 1,
          workoutName: 'W',
          exercisesJson: '[]',
          isCompleted: false,
          orderIndex: 0,
        );
        expect(
          await provider.startProgramWorkout(1, pw, DateTime(2024, 1, 1), 5),
          isNull,
        );
        verifyNever(repo.createSessionFromProgramWorkout(any, any, any, any));
      },
    );
  });

  // ==========================================================================
  // Isar's Query.watch() is watchLazy().asyncMap((_) => findAll()); the
  // repository adds a second asyncMap (per-row exercise hydration + sort). A
  // findAll() that ran BEFORE a mutation committed can still be DELIVERED to
  // _onWatchData AFTER the mutation's repository Future resolved and its
  // direct _sessions edit published. Each test below delivers S1 - that
  // pre-mutation snapshot - through the SAME subscription that was current
  // when the mutation began, and asserts the mutation's result survives.
  // Stable ids; Completers gate the repo Futures; no wall-clock, no event
  // loop pumping.
  group('13. mutation vs. stale watch snapshot convergence', () {
    test('a pre-delete snapshot delivered after deleteSession success does '
        'not resurrect the deleted session', () async {
      await seed([session(1), session(2)]);
      final preWatch = watches.first.controller;

      final delC = Completer<bool>();
      when(repo.deleteSession(1)).thenAnswer((_) => delC.future);

      final f = provider.deleteSession(1);
      delC.complete(true);
      expect(await f, isTrue);
      expect(provider.sessions.map((s) => s.id), [2]);
      final afterMutation = notifyCount;

      // S1: queried by findAll() before the delete committed.
      preWatch.add([session(1), session(2)]);

      expect(provider.sessions.map((s) => s.id), [2]);
      expect(notifyCount, afterMutation);
      expect(preWatch.hasListener, isFalse);
    });

    test('a pre-archive snapshot delivered after archiveSession success does '
        'not resurrect the archived session', () async {
      await seed([session(1), session(2)]);
      final preWatch = watches.first.controller;

      final arcC = Completer<bool>();
      when(repo.archiveSession(1)).thenAnswer((_) => arcC.future);

      final f = provider.archiveSession(1);
      arcC.complete(true);
      expect(await f, isTrue);
      expect(provider.sessions.map((s) => s.id), [2]);
      final afterMutation = notifyCount;

      preWatch.add([session(1), session(2)]);

      expect(provider.sessions.map((s) => s.id), [2]);
      expect(notifyCount, afterMutation);
    });

    test('a pre-update snapshot delivered after updateWorkoutDate success '
        'does not revert the new date', () async {
      await seed([session(1), session(2)]);
      final preWatch = watches.first.controller;
      final newDate = DateTime(2025, 8, 8);
      final oldDate = session(1).date;

      final updC = Completer<void>();
      when(repo.updateWorkoutDate(1, any)).thenAnswer((_) => updC.future);

      final f = provider.updateWorkoutDate(1, newDate);
      updC.complete();
      expect(await f, isTrue);
      expect(provider.sessions.firstWhere((s) => s.id == 1).date, newDate);
      final afterMutation = notifyCount;

      // S1 still carries the OLD date for session 1.
      preWatch.add([session(1, date: oldDate), session(2)]);

      expect(provider.sessions.firstWhere((s) => s.id == 1).date, newDate);
      expect(notifyCount, afterMutation);
    });

    test('a pre-start snapshot delivered after startPlannedWorkout success '
        'does not revert the status', () async {
      await seed([session(1, status: 'planned'), session(2)]);
      final preWatch = watches.first.controller;

      final startC = Completer<Session>();
      when(
        repo.updateSessionStatus(1, 'in_progress'),
      ).thenAnswer((_) => startC.future);

      final f = provider.startPlannedWorkout(1);
      startC.complete(session(1, status: 'in_progress'));
      expect(await f, isTrue);
      expect(
        provider.sessions.firstWhere((s) => s.id == 1).status,
        'in_progress',
      );
      final afterMutation = notifyCount;

      preWatch.add([session(1, status: 'planned'), session(2)]);

      expect(
        provider.sessions.firstWhere((s) => s.id == 1).status,
        'in_progress',
      );
      expect(notifyCount, afterMutation);
    });

    test(
      'a pre-update snapshot delivered after '
      'updateSessionDateForProgramWorkout success does not revert the date',
      () async {
        await seed([session(1, programWorkoutId: 77, status: 'planned')]);
        final preWatch = watches.first.controller;
        final newDate = DateTime(2025, 4, 4);
        final oldDate = session(1).date;

        final pwC = Completer<void>();
        when(repo.updateWorkoutDate(1, any)).thenAnswer((_) => pwC.future);

        final f = provider.updateSessionDateForProgramWorkout(
          programWorkoutId: 77,
          newScheduledDate: newDate,
        );
        pwC.complete();
        expect(await f, isTrue);
        expect(provider.sessions.single.date, newDate);
        final afterMutation = notifyCount;

        preWatch.add([
          session(1, programWorkoutId: 77, status: 'planned', date: oldDate),
        ]);

        expect(provider.sessions.single.date, newDate);
        expect(notifyCount, afterMutation);
      },
    );

    test('a pre-create snapshot lacking the new session is not authoritative '
        'after startNewWorkout', () async {
      await seed([session(1)]);
      final preWatch = watches.first.controller;
      final created = session(50, name: 'W');
      when(repo.createSession(any)).thenAnswer((_) async => created);

      final r = await provider.startNewWorkout(name: 'W');
      expect(r!.id, 50);
      expect(provider.sessions.map((s) => s.id), [50, 1]);
      final afterMutation = notifyCount;

      // S1 was queried before the create committed -> lacks id 50.
      preWatch.add([session(1)]);

      expect(provider.sessions.map((s) => s.id), [50, 1]);
      expect(notifyCount, afterMutation);
    });

    test('a pre-create snapshot lacking the new session is not authoritative '
        'after createPlannedWorkout', () async {
      await seed([session(1)]);
      final preWatch = watches.first.controller;
      when(
        repo.createSession(any),
      ).thenAnswer((_) async => session(60, status: 'planned'));

      final r = await provider.createPlannedWorkout(
        name: 'P',
        scheduledDate: DateTime(2025, 2, 2),
      );
      expect(r!.id, 60);
      expect(provider.sessions.map((s) => s.id), [60, 1]);
      final afterMutation = notifyCount;

      preWatch.add([session(1)]);

      expect(provider.sessions.map((s) => s.id), [60, 1]);
      expect(notifyCount, afterMutation);
    });

    test('a pre-create snapshot lacking the new session is not authoritative '
        'after createPlannedWorkout WITH exercise templates', () async {
      await seed([session(1)]);
      final preWatch = watches.first.controller;
      when(
        repo.createSession(any),
      ).thenAnswer((_) async => session(60, status: 'planned'));
      when(
        repo.addExerciseToSession(any, any),
      ).thenAnswer((_) async => Exercise(id: 7, sessionId: 60, name: 'Row'));
      when(
        repo.getSession(60),
      ).thenAnswer((_) async => session(60, status: 'planned'));

      final r = await provider.createPlannedWorkout(
        name: 'P',
        scheduledDate: DateTime(2025, 2, 2),
        exerciseTemplateIds: [10],
      );
      expect(r!.id, 60);
      expect(provider.sessions.map((s) => s.id), [60, 1]);
      final afterMutation = notifyCount;

      // S1 was queried before the create committed -> lacks id 60.
      preWatch.add([session(1)]);

      expect(provider.sessions.map((s) => s.id), [60, 1]);
      expect(notifyCount, afterMutation);
    });

    test('a pre-batch snapshot lacking the new sessions is not authoritative '
        'after createRecurringPlannedWorkouts', () async {
      await seed([session(1)]);
      final preWatch = watches.first.controller;
      var next = 70;
      when(
        repo.createSession(any),
      ).thenAnswer((_) async => session(next++, status: 'planned'));

      final r = await provider.createRecurringPlannedWorkouts(
        name: 'R',
        startDate: DateTime(2025, 1, 1),
        frequency: 'daily',
        occurrences: 3,
      );
      expect(r.map((s) => s.id), [70, 71, 72]);
      expect(provider.sessions.map((s) => s.id).toSet(), {70, 71, 72, 1});
      final afterMutation = notifyCount;

      preWatch.add([session(1)]);

      expect(provider.sessions.map((s) => s.id).toSet(), {70, 71, 72, 1});
      expect(notifyCount, afterMutation);
    });

    test('a pre-create snapshot lacking the program session is not '
        'authoritative after startProgramWorkout', () async {
      await seed([session(1)]);
      final preWatch = watches.first.controller;
      final pw = ProgramWorkout(
        id: 9,
        programId: 5,
        weekNumber: 1,
        dayNumber: 1,
        workoutName: 'W',
        exercisesJson: '[]',
        isCompleted: false,
        orderIndex: 0,
      );
      when(
        repo.createSessionFromProgramWorkout(any, any, any, any),
      ).thenAnswer((_) async => session(88, programId: 5));

      final r = await provider.startProgramWorkout(
        9,
        pw,
        DateTime(2024, 1, 1),
        5,
      );
      expect(r!.id, 88);
      expect(provider.sessions.map((s) => s.id), [88, 1]);
      final afterMutation = notifyCount;

      preWatch.add([session(1)]);

      expect(provider.sessions.map((s) => s.id), [88, 1]);
      expect(notifyCount, afterMutation);
    });
  });

  // ==========================================================================
  group('14. watch handoff races', () {
    test('a mutation re-arms the watch: exactly one live subscription, the '
        'old one cancelled', () async {
      await seed([session(1), session(2)]);
      final pre = watches.first.controller;
      expect(pre.hasListener, isTrue);

      await provider.deleteSession(1);

      expect(pre.hasListener, isFalse);
      expect(watches.where((w) => w.controller.hasListener), hasLength(1));
      expect(watches.last.userId, 1);
      expect(provider.watchedUserId, 1);
    });

    test('a superseded mutation does not re-arm or cancel the newer '
        'handoff', () async {
      await seed([session(1), session(2)]);
      final delC = Completer<bool>();
      when(repo.deleteSession(1)).thenAnswer((_) => delC.future);

      final delF = provider.deleteSession(1); // older, held
      await provider.updateWorkoutDate(
        1,
        DateTime(2025, 9, 9),
      ); // newer, re-arms
      final live = watches.where((w) => w.controller.hasListener).toList();
      expect(live, hasLength(1));
      final handoff = live.single.controller;

      delC.complete(true);
      expect(await delF, isFalse); // superseded

      expect(provider.sessions.map((s) => s.id), [1, 2]);
      expect(handoff.hasListener, isTrue);
      final stillLive = watches.where((w) => w.controller.hasListener).toList();
      expect(stillLive, hasLength(1));
      expect(identical(stillLive.single.controller, handoff), isTrue);
    });

    test('concurrent mutations on different sessions leave exactly one live '
        'watch', () async {
      await seed([session(1), session(2), session(3)]);

      await provider.deleteSession(1);
      await provider.archiveSession(2);

      expect(provider.sessions.map((s) => s.id), [3]);
      expect(watches.where((w) => w.controller.hasListener), hasLength(1));
      expect(provider.watchedUserId, 1);
    });

    test(
      'clear() after a mutation re-arm cancels the re-armed watch too',
      () async {
        await seed([session(1)]);
        await provider.deleteSession(1);
        expect(watches.where((w) => w.controller.hasListener), hasLength(1));

        provider.clear();

        expect(watches.where((w) => w.controller.hasListener), isEmpty);
        expect(provider.watchedUserId, isNull);
        expect(provider.sessions, isEmpty);
      },
    );

    test('a mutation-re-armed watch under A does not publish after B logs '
        'in', () async {
      await seed([session(1), session(2)]);
      await provider.deleteSession(1);
      final handoff =
          watches.where((w) => w.controller.hasListener).single.controller;

      epoch.invalidate();
      epoch.activate(2);
      final before = notifyCount;

      handoff.add([session(1), session(2)]);

      expect(provider.sessions.map((s) => s.id), [2]);
      expect(notifyCount, before);
    });

    test(
      'a mutation-re-armed watch event after dispose() does not throw',
      () async {
        await seed([session(1)]);
        await provider.deleteSession(1);
        final handoff =
            watches.where((w) => w.controller.hasListener).single.controller;

        provider.dispose();
        if (!handoff.isClosed && handoff.hasListener) {
          handoff.add([session(1)]);
        }
        // no throw, nothing to assert on a disposed provider
      },
    );

    test(
      'a mutation without a prior loadSessions does not start a watch',
      () async {
        epoch.activate(1);
        when(repo.deleteSession(1)).thenAnswer((_) async => true);

        await provider.deleteSession(1);

        expect(watches, isEmpty);
        verifyNever(repo.watchSessions(any));
        expect(provider.watchedUserId, isNull);
      },
    );
  });
}
