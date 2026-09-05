import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';

@GenerateMocks([SessionRepository, ConnectivityService])
import 'sessions_provider_publication_race_test.mocks.dart';

/// Proves the authoritative-publication invariant: once the joined watch is
/// installed for the current user, a plain `getSessions()` result must
/// never replace or clear a watch-owned (possibly diagnostics-bearing)
/// snapshot - regardless of which of the two completes first. Real
/// [UserSessionEpoch]; `getSessions()` is gated by a per-call
/// [Completer]&lt;List&lt;Session&gt;&gt; so both completion orders are
/// constructed deterministically - no `Future.delayed`, no `Timer`, no
/// `pumpEventQueue`.
void main() {
  late MockSessionRepository repo;
  late UserSessionEpoch epoch;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late SessionsProvider provider;

  late List<({int userId, StreamController<SessionSyncSnapshot> controller})>
  watches;

  Session session(int id, {int userId = 1}) =>
      Session(id: id, userId: userId, date: DateTime(2026, 1, 1));

  const retrying = SessionSyncDiagnostics(
    state: SessionSyncState.retryingFailure,
  );

  SessionSyncSnapshot snapshotWithFailure(int id) => SessionSyncSnapshot(
    visibleEntries: [
      SessionListEntry(
        session: session(id),
        localId: id,
        diagnostics: retrying,
      ),
    ],
    retryingFailureCount: 1,
    conflictCount: 0,
  );

  StreamController<SessionSyncSnapshot> newWatch(int userId) {
    final c = StreamController<SessionSyncSnapshot>(sync: true);
    watches.add((userId: userId, controller: c));
    return c;
  }

  // Queue of Completers consumed in call order - lets each successive
  // getSessions() call be resolved independently and deterministically.
  late List<Completer<List<Session>>> getSessionsCompleters;

  setUp(() {
    repo = MockSessionRepository();
    watches = [];
    getSessionsCompleters = [];
    when(repo.getSessions(waitForSync: anyNamed('waitForSync'))).thenAnswer((
      _,
    ) {
      final c = Completer<List<Session>>();
      getSessionsCompleters.add(c);
      return c.future;
    });
    when(
      repo.watchSessionSyncSnapshot(any),
    ).thenAnswer((inv) => newWatch(inv.positionalArguments[0] as int).stream);

    epoch = UserSessionEpoch();
    connectivity = MockConnectivityService();
    connectivityController = StreamController<bool>.broadcast(sync: true);
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    provider = SessionsProvider(repo, epoch, connectivity);
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

  test('Order A: an existing watch emits a failure while a SECOND '
      'loadSessions() is still awaiting its plain repository call; once '
      'that plain call completes afterward, the diagnostic remains visible '
      'and correctly attached', () async {
    epoch.activate(1);

    // First loadSessions(): resolves immediately (empty list), installs
    // watch #1, and becomes the "already active" watch for this user.
    final firstLoad = provider.loadSessions();
    getSessionsCompleters[0].complete(<Session>[]);
    await firstLoad;
    expect(watches, hasLength(1));

    // The already-installed watch emits a failure - the authoritative
    // source of truth going forward.
    watches[0].controller.add(snapshotWithFailure(1));
    expect(provider.retryingFailureCount, 1);
    expect(provider.diagnosticsForLocalId(1), retrying);

    // A SECOND loadSessions() (e.g. pull-to-refresh) begins and is still
    // awaiting its own plain getSessions() call.
    final secondLoad = provider.loadSessions();
    expect(provider.retryingFailureCount, 1, reason: 'still awaiting');

    // The plain repository call now completes, with a plain list that
    // carries no diagnostics at all.
    getSessionsCompleters[1].complete([session(1)]);
    await secondLoad;

    // The diagnostic must remain visible and correctly attached - the
    // watch, already active for this user, is the sole publisher; the
    // plain list result must not have cleared it.
    expect(provider.retryingFailureCount, 1);
    expect(provider.diagnosticsForLocalId(1), retrying);
    expect(provider.sessions, hasLength(1));

    // No second/parallel watch was installed to achieve this.
    expect(watches, hasLength(2)); // #2 installed by the second load...
    expect(
      watches[0].controller.hasListener,
      isFalse,
      reason: 'superseded by the second load\'s own re-arm',
    );
    expect(watches[1].controller.hasListener, isTrue);
  });

  test(
    'Order B: the foreground load completes BEFORE any watch has ever '
    'emitted; the watch snapshot that follows becomes authoritative',
    () async {
      epoch.activate(1);

      final load = provider.loadSessions();
      // No watch has emitted yet - this is the FIRST-EVER load, so the plain
      // list is allowed to paint (there are no diagnostics to lose).
      getSessionsCompleters[0].complete([session(1)]);
      await load;

      expect(provider.sessions, hasLength(1));
      expect(provider.retryingFailureCount, 0);
      expect(provider.diagnosticsForLocalId(1), isNull);

      // The watch installed by that load now emits its first real snapshot,
      // carrying a failure.
      watches[0].controller.add(snapshotWithFailure(1));

      expect(provider.retryingFailureCount, 1);
      expect(provider.diagnosticsForLocalId(1), retrying);
    },
  );

  test('a stale foreground load from User A cannot clear User B\'s '
      'diagnostics', () async {
    epoch.activate(1);
    final aLoad = provider.loadSessions(); // A's plain call pending

    epoch.invalidate();
    epoch.activate(2);
    final bLoad = provider.loadSessions();
    getSessionsCompleters[1].complete([session(9, userId: 2)]);
    await bLoad;
    // A's getSessions() is still pending, so B's loadSessions() is the
    // first to reach _installWatch - B's watch is watches[0], not [1].
    expect(watches, hasLength(1));
    watches[0].controller.add(snapshotWithFailure(9));
    expect(provider.retryingFailureCount, 1);

    // A's long-pending plain call finally resolves - it must be rejected by
    // owns() before it can touch state at all.
    getSessionsCompleters[0].complete([session(1, userId: 1)]);
    await aLoad;

    expect(provider.sessions.map((s) => s.id), [9]);
    expect(provider.retryingFailureCount, 1);
    expect(provider.diagnosticsForLocalId(9), retrying);
  });

  test(
    'clear() still removes diagnostics immediately, even mid-race',
    () async {
      epoch.activate(1);
      final load = provider.loadSessions();
      getSessionsCompleters[0].complete([session(1)]);
      await load;
      watches[0].controller.add(snapshotWithFailure(1));
      expect(provider.hasSyncIssues, isTrue);

      provider.clear();

      expect(provider.hasSyncIssues, isFalse);
      expect(provider.sessions, isEmpty);
    },
  );

  test('a foreground load before the first watch emission does not '
      'associate diagnostics using ambiguous IDs - the direct-publish '
      'branch touches no diagnostics state at all', () async {
    epoch.activate(1);
    final load = provider.loadSessions();
    getSessionsCompleters[0].complete([session(1), session(2)]);
    await load;

    // Right after the plain publish and before any watch emission: no
    // diagnostics exist, none were guessed from the plain Session.id list.
    expect(provider.retryingFailureCount, 0);
    expect(provider.conflictCount, 0);
    expect(provider.diagnosticsForLocalId(1), isNull);
    expect(provider.diagnosticsForLocalId(2), isNull);
  });

  test('no second watch/subscription is ever concurrently active across '
      'either completion order', () async {
    epoch.activate(1);
    final load1 = provider.loadSessions();
    getSessionsCompleters[0].complete([session(1)]);
    await load1;
    watches[0].controller.add(snapshotWithFailure(1));

    final load2 = provider.loadSessions();
    getSessionsCompleters[1].complete([session(1)]);
    await load2;

    // At most one controller has a listener at any point after both loads
    // have settled.
    final activeCount = watches.where((w) => w.controller.hasListener).length;
    expect(activeCount, 1);
  });

  test(
    'the seqAtEntry staleness check alone (independent of '
    'watchAlreadyActiveForThisUser) still blocks a stale direct-publish: '
    "the ALREADY-ACTIVE watch publishes a failure and THEN goes done "
    "(onDone) - both DURING a second load's own in-flight getSessions() "
    "await - so by the time that load resolves, watchAlreadyActiveForThisUser "
    'is false too, and only seqAtEntry protects the failure from being wiped',
    () async {
      epoch.activate(1);

      // load1 installs watch #1 and becomes the active watch for user 1.
      final load1 = provider.loadSessions();
      getSessionsCompleters[0].complete(<Session>[]);
      await load1;
      expect(watches, hasLength(1));

      // load2 begins (e.g. pull-to-refresh); captures seqAtEntry BEFORE
      // watch #1 has published anything.
      final load2 = provider.loadSessions();

      // While load2's own getSessions() is still pending: the ALREADY-ACTIVE
      // watch #1 (installed by load1, not by load2) publishes a failure...
      watches[0].controller.add(snapshotWithFailure(1));
      expect(provider.retryingFailureCount, 1);

      // ...and then goes done, so by the time load2's getSessions()
      // resolves, watchAlreadyActiveForThisUser will ALSO read false -
      // seqAtEntry is the ONLY thing left standing between this failure and
      // an unconditional overwrite.
      await watches[0].controller.close();
      expect(provider.watchedUserId, isNull);

      // load2's own plain getSessions() now resolves with a diagnostics-free
      // list.
      getSessionsCompleters[1].complete([session(1)]);
      await load2;

      // The failure published in step 3 must survive - seqAtEntry(captured
      // before that publish) no longer equals the current, bumped
      // _streamPublishSeq, so the direct-publish branch must still skip.
      expect(provider.retryingFailureCount, 1);
      expect(provider.diagnosticsForLocalId(1), retrying);
    },
  );

  test("a load whose user logged out mid-flight (no second login, so neither "
      "watchAlreadyActiveForThisUser nor the seqAtEntry check has anything to "
      "catch it) is still rejected - isolating owns()'s own "
      "UserSessionEpoch.isCurrent(token) check as the thing that must reject "
      'it: no watch was ever installed, and _streamPublishSeq never moved, so '
      'only owns() stands between a stale logged-out continuation and '
      'publishing into the next (nobody\'s) session', () async {
    epoch.activate(1);
    final load = provider.loadSessions(); // getSessions() still pending

    // Logged out mid-flight - no second loadSessions(), no second login,
    // no watch ever installed for anyone yet.
    epoch.invalidate();

    getSessionsCompleters[0].complete([session(1)]);
    await load;

    // Must publish nothing: no sessions, no watch installed, no
    // diagnostics - a stale, now-logged-out continuation touches no state.
    expect(provider.sessions, isEmpty);
    expect(provider.watchedUserId, isNull);
    expect(watches, isEmpty);
  });
}
