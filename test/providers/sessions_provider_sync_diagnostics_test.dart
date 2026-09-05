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
import 'sessions_provider_sync_diagnostics_test.mocks.dart';

/// Proves the read-only sync-diagnostics surface `SessionsProvider` derives
/// from its single joined watch: correctly scoped to the captured user,
/// reset by `clear()`/`dispose()`, immune to a stale watch callback from a
/// previous user or a previous subscription instance, and reactive to a
/// later snapshot that clears a previously-reported failure. No action that
/// mutates sync state is exercised here - there is none to exercise.
///
/// Real [UserSessionEpoch]; the repository is mocked with a per-install
/// `sync: true` [StreamController]&lt;[SessionSyncSnapshot]&gt; so `.add()`
/// delivers synchronously - no `Future.delayed`, no `Timer`, no
/// `pumpEventQueue`.
void main() {
  late MockSessionRepository repo;
  late UserSessionEpoch epoch;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late SessionsProvider provider;

  // One controller per _installWatch call, in install order.
  late List<({int userId, StreamController<SessionSyncSnapshot> controller})>
  watches;

  Session session(int id, {int userId = 1, String? name}) =>
      Session(id: id, userId: userId, date: DateTime(2026, 1, 1), name: name);

  SessionListEntry entry(
    int id, {
    int userId = 1,
    SessionSyncDiagnostics? diagnostics,
  }) => SessionListEntry(
    session: session(id, userId: userId),
    localId: id,
    diagnostics: diagnostics,
  );

  const retrying = SessionSyncDiagnostics(
    state: SessionSyncState.retryingFailure,
  );
  const conflict = SessionSyncDiagnostics(state: SessionSyncState.conflict);

  SessionSyncSnapshot snapshot(
    List<SessionListEntry> entries, {
    int? retryingCount,
    int? conflictCount,
  }) => SessionSyncSnapshot(
    visibleEntries: entries,
    retryingFailureCount:
        retryingCount ??
        entries.where((e) => e.diagnostics?.isRetryingFailure ?? false).length,
    conflictCount:
        conflictCount ??
        entries.where((e) => e.diagnostics?.isConflict ?? false).length,
  );

  StreamController<SessionSyncSnapshot> newWatch(int userId) {
    final c = StreamController<SessionSyncSnapshot>(sync: true);
    watches.add((userId: userId, controller: c));
    return c;
  }

  setUp(() {
    repo = MockSessionRepository();
    watches = [];
    when(
      repo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => <Session>[]);
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

  test('11. one subscription supplies both the visible list and '
      'diagnostics - loadSessions installs exactly one watch', () async {
    epoch.activate(1);
    await provider.loadSessions();
    expect(watches, hasLength(1));
  });

  test('13. multiple simultaneous failures aggregate correctly, retrying '
      'and conflict counted separately', () async {
    epoch.activate(1);
    await provider.loadSessions();

    final e1 = entry(1, diagnostics: retrying);
    final e2 = entry(2, diagnostics: retrying);
    final e3 = entry(3, diagnostics: conflict);
    final e4 = entry(4); // healthy

    watches.last.controller.add(snapshot([e1, e2, e3, e4]));

    expect(provider.retryingFailureCount, 2);
    expect(provider.conflictCount, 1);
    expect(provider.hasSyncIssues, isTrue);
    expect(provider.diagnosticsFor(e1.session), retrying);
    expect(provider.diagnosticsFor(e3.session), conflict);
    expect(provider.diagnosticsFor(e4.session), isNull);
  });

  test('a failing pending_delete (absent from visibleEntries) still counts '
      'in the aggregate published to the provider', () async {
    epoch.activate(1);
    await provider.loadSessions();

    watches.last.controller.add(
      SessionSyncSnapshot(
        visibleEntries: [entry(1)], // healthy, visible
        retryingFailureCount: 1, // the hidden pending_delete failure
        conflictCount: 0,
      ),
    );

    expect(provider.sessions, hasLength(1));
    expect(provider.retryingFailureCount, 1);
  });

  test('14. a later snapshot that clears a previously-reported failure '
      'makes the warning disappear reactively', () async {
    epoch.activate(1);
    await provider.loadSessions();
    final e1 = entry(1, diagnostics: retrying);

    watches.last.controller.add(snapshot([e1]));
    expect(provider.retryingFailureCount, 1);
    expect(provider.hasSyncIssues, isTrue);

    // A background sync succeeded: the next snapshot has no diagnostics for
    // this session at all.
    watches.last.controller.add(snapshot([entry(1)]));
    expect(provider.retryingFailureCount, 0);
    expect(provider.hasSyncIssues, isFalse);
    expect(provider.diagnosticsFor(entry(1).session), isNull);
  });

  test('7. clear() resets diagnostics/counts immediately', () async {
    epoch.activate(1);
    await provider.loadSessions();
    watches.last.controller.add(
      snapshot([
        entry(1, diagnostics: retrying),
        entry(2, diagnostics: conflict),
      ]),
    );
    expect(provider.hasSyncIssues, isTrue);

    provider.clear();

    expect(provider.retryingFailureCount, 0);
    expect(provider.conflictCount, 0);
    expect(provider.hasSyncIssues, isFalse);
    expect(provider.sessions, isEmpty);
  });

  test(
    '8/9. a stale User-A watch emission after B logs in never reaches '
    "B's diagnostics - the old subscription's late add() is rejected",
    () async {
      epoch.activate(1);
      await provider.loadSessions();
      final staleWatch = watches.single.controller;

      epoch.invalidate();
      epoch.activate(2);
      await provider.loadSessions();
      expect(watches, hasLength(2));

      // B's fresh snapshot lands first.
      watches.last.controller.add(snapshot([entry(9, userId: 2)]));
      expect(provider.retryingFailureCount, 0);

      // A's stale subscription (detached, no listener) tries to publish a
      // failure. It must be rejected outright - never reach B's state.
      expect(staleWatch.hasListener, isFalse);
      staleWatch.add(snapshot([entry(1, userId: 1, diagnostics: retrying)]));

      expect(provider.retryingFailureCount, 0);
      expect(provider.conflictCount, 0);
      expect(provider.sessions.map((s) => s.id), [9]);
    },
  );

  test('9b. User A logs out (clear()), then a late emission on the '
      "now-detached subscription never repopulates diagnostics", () async {
    epoch.activate(1);
    await provider.loadSessions();
    final staleWatch = watches.single.controller;

    epoch.invalidate();
    provider.clear();
    expect(provider.hasSyncIssues, isFalse);

    staleWatch.add(snapshot([entry(1, diagnostics: retrying)]));

    expect(provider.hasSyncIssues, isFalse);
    expect(provider.sessions, isEmpty);
  });

  test('10. dispose() prevents late publication of diagnostics', () async {
    epoch.activate(1);
    await provider.loadSessions();
    final watch = watches.single.controller;

    provider.dispose();

    // A post-dispose add() must not throw and must not be observable (the
    // provider is torn down; asserting no exception propagates is the
    // meaningful check here, mirroring the existing ownership suite's
    // equivalent dispose-safety test).
    expect(
      () => watch.add(snapshot([entry(1, diagnostics: retrying)])),
      returnsNormally,
    );
  });

  test('diagnosticsForLocalId resolves by the unambiguous localId - never '
      'by the public Session.id', () async {
    epoch.activate(1);
    await provider.loadSessions();
    final e1 = entry(1, diagnostics: retrying);
    watches.last.controller.add(snapshot([e1]));

    expect(provider.diagnosticsForLocalId(1), retrying);
    expect(provider.diagnosticsForLocalId(999), isNull);
  });

  test('localIdFor resolves the unambiguous localId for a live Session '
      'instance, healthy or not, and returns null for an instance not in '
      'the current list', () async {
    epoch.activate(1);
    await provider.loadSessions();
    final e1 = entry(1, diagnostics: retrying);
    final e2 = entry(2); // healthy
    watches.last.controller.add(snapshot([e1, e2]));

    expect(provider.localIdFor(e1.session), 1);
    expect(provider.localIdFor(e2.session), 2);
    expect(provider.localIdFor(session(999)), isNull);
  });

  test('1/2/3/4/5. the local-ID/server-ID collision fixture: a synced row '
      "(Session.id == N) and a pending row (Session.id == N) - opening "
      "either's detail screen (by localId) never crosses over, and no "
      'lookup ever goes through Session.id', () async {
    epoch.activate(1);
    await provider.loadSessions();

    // Row A: synced, Session.id == N (its serverId).
    // Row B: pending, Session.id == N too (its localId) - a genuine
    // collision in the ambiguous `serverId ?? localId` public id space, as
    // ModelMapper.localToSession would actually produce.
    const collidingPublicId = 42;
    final rowA = Session(
      id: collidingPublicId,
      userId: 1,
      date: DateTime(2026, 1, 1),
      name: 'synced row A',
    );
    final rowB = Session(
      id: collidingPublicId,
      userId: 1,
      date: DateTime(2026, 1, 2),
      name: 'pending row B',
    );
    const rowALocalId = 7; // A's real localId, unrelated to the collision
    const rowBLocalId = collidingPublicId; // B's localId IS the collision

    watches.last.controller.add(
      SessionSyncSnapshot(
        visibleEntries: [
          SessionListEntry(session: rowA, localId: rowALocalId), // healthy
          SessionListEntry(
            session: rowB,
            localId: rowBLocalId,
            diagnostics: retrying,
          ),
        ],
        retryingFailureCount: 1,
        conflictCount: 0,
      ),
    );

    // 1/2. Confirmed collision in the public id space.
    expect(rowA.id, collidingPublicId);
    expect(rowB.id, collidingPublicId);
    expect(rowA.id, rowB.id);

    // 3. "Opening A's detail screen" = looking up diagnostics by A's real
    // localId - never shows B's diagnostic.
    expect(provider.diagnosticsForLocalId(rowALocalId), isNull);
    // 4. "Opening B's detail screen" = looking up by B's localId - shows
    // exactly B's diagnostic.
    expect(provider.diagnosticsForLocalId(rowBLocalId), retrying);

    // 5. localIdFor (the only sanctioned way to obtain a localId for
    // navigation) resolves each row to ITS OWN localId, never the other's,
    // and never derives it from the shared public id.
    expect(provider.localIdFor(rowA), rowALocalId);
    expect(provider.localIdFor(rowB), rowBLocalId);

    // Identity-based diagnosticsFor (used by card badges) is unaffected and
    // stays correct too.
    expect(provider.diagnosticsFor(rowA), isNull);
    expect(provider.diagnosticsFor(rowB), retrying);
  });

  test('6. an entry point with no local ID gets no diagnostic - '
      'diagnosticsForLocalId never guesses via a public id, and there is no '
      'method left that accepts one', () {
    // diagnosticsForSessionId no longer exists (compile-time proof: the
    // provider does not expose it - see the removed method). The only
    // lookup surface left is diagnosticsForLocalId(int localId), which
    // simply returns null for any id it has no entry for - there is no
    // fallback path that resolves a public/ambiguous id to a row.
    expect(provider.diagnosticsForLocalId(-1), isNull);
  });

  test('diagnosticsForLocalId(N) never falls back to treating N as a public '
      "Session.id when N is nobody's real localId - even when some OTHER "
      'row happens to have that exact value as its public (serverId) id AND '
      "carries a genuine failure. A fallback-to-public-id mutant would wrongly "
      "surface that other row's diagnostics here; the correct implementation "
      'returns null because 999 is not registered as any localId.', () async {
    epoch.activate(1);
    await provider.loadSessions();

    // rowD: synced, public id (serverId) == 999, real localId == 8,
    // and IS currently retrying a failed sync of a later update - so a
    // fallback-to-public-id lookup on 999 would find a row with a real,
    // non-null diagnostic to wrongly return.
    final rowD = Session(
      id: 999,
      userId: 1,
      date: DateTime(2026, 1, 1),
      name: 'rowD',
    );
    watches.last.controller.add(
      SessionSyncSnapshot(
        visibleEntries: [
          SessionListEntry(session: rowD, localId: 8, diagnostics: retrying),
        ],
        retryingFailureCount: 1,
        conflictCount: 0,
      ),
    );

    // Sanity: rowD's diagnostic IS reachable by its real localId.
    expect(provider.diagnosticsForLocalId(8), retrying);

    // 999 is nobody's real localId (only rowD's unrelated public id) -
    // must be null, never rowD's retrying diagnostic.
    expect(provider.diagnosticsForLocalId(999), isNull);
  });
}
