import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/services/rate_limited_exception.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

// Reuses the Mockito mocks generated for sync_service_test.dart (same
// ApiService / AuthService surface, unchanged by this PR) - no new
// build_runner output.
import 'sync_service_test.mocks.dart';

/// Proves `SyncService`'s session-write-limiter (HTTP 429) cooldown: a
/// trustworthy `Retry-After` arms a session-bound gate on `sync()` that
/// coalesces every trigger source (manual call, standing in for the
/// periodic timer / debounce / pull-to-refresh, which all funnel through
/// the same `sync()` method) until the deadline elapses; a missing
/// `Retry-After` arms nothing, leaving the existing periodic/debounce
/// cadence as the only backoff; the cooldown is strictly session-bound
/// (logout / a different user is never gated by it); and while the
/// cooldown is active `sync()` never touches Isar at all, so a newer local
/// edit made during the window is completely untouched, not merely
/// "not overwritten"; and once the cooldown arms mid-pass, the REST of that
/// SAME pass's pending-session batch is never dispatched either - not just
/// the next `sync()` call.
///
/// Real Isar, real `UserSessionEpoch`, real `SessionRequestCoordinator`;
/// `MockApiService` with synchronous throwing responders and
/// `SyncService.nowUtcForTesting` for a fully deterministic clock - no real
/// `Future.delayed`, no `Timer`, no wall-clock waits.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late SyncService syncService;
  late DateTime fakeNow;

  const userA = 1;
  const userB = 2;

  // A plain counter, not `verify(...).callCount` - mockito-dart's `verify`
  // consumes/marks matched invocations as verified, so calling it more than
  // once per test only ever reports the calls made SINCE the previous
  // `verify` call, not a running total. Counting directly in the stub is
  // simple and avoids that pitfall entirely. Reset in `setUp` below.
  var postCalls = 0;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  Future<Isar> openIsar() => Isar.open(
    [LocalSessionSchema, LocalExerciseSchema, LocalExerciseSetSchema],
    directory: tempDir.path,
    inspector: false,
  );

  void buildSyncServiceFor(int uid) {
    SyncService.reset();
    when(mockAuthService.getUserId()).thenAnswer((_) async => uid);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$uid');
    sessionEpoch = UserSessionEpoch()..activate(uid);
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );
    syncService = SyncService(
      apiService: mockApiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: ConnectivityService.instance,
      sessionEpoch: sessionEpoch,
      sessionCoordinator: sessionCoordinator,
    )..nowUtcForTesting = () => fakeNow;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_rate_limit_');
    isar = await openIsar();
    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);
    fakeNow = DateTime.utc(2026, 1, 1);
    postCalls = 0;
    buildSyncServiceFor(userA);
  });

  tearDown(() async {
    SyncService.reset();
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ---- fixtures -------------------------------------------------------------

  Future<LocalSession> insertSession({
    int uid = userA,
    int? serverId,
    int? version,
    required String syncStatus,
  }) async {
    final s = LocalSession(
      serverId: serverId,
      userId: uid,
      date: DateTime(2026, 1, 1),
      name: 'Workout',
      status: 'draft',
      isSynced: false,
      syncStatus: syncStatus,
      version: version,
      lastModifiedLocal: DateTime(2026, 1, 1, 8),
    );
    await isar.writeTxn(() => isar.localSessions.put(s));
    return s;
  }

  void stubPost({Object? throws, Map<String, dynamic>? returns}) {
    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async {
      postCalls++;
      if (throws != null) throw throws;
      return returns!;
    });
  }

  Future<LocalSession?> reload(int localId) => isar.localSessions.get(localId);

  group('SyncService rate-limit cooldown (HTTP 429 Retry-After)', () {
    test('16. just before expiry remains blocked - one millisecond short of '
        'untilUtc is still "cooling down", not eligible', () async {
      await insertSession(syncStatus: 'pending_create');
      stubPost(
        throws: const RateLimitedException(retryAfter: Duration(seconds: 60)),
      );

      await syncService.sync();
      expect(postCalls, 1);

      fakeNow = fakeNow.add(
        const Duration(seconds: 60) - const Duration(milliseconds: 1),
      );
      await syncService.sync();
      expect(
        postCalls,
        1,
        reason: 'one millisecond before the deadline must still be blocked',
      );
    });

    test('14. multiple triggers during cooldown result in zero additional '
        'HTTP calls, regardless of how many times sync() is called', () async {
      await insertSession(syncStatus: 'pending_create');
      stubPost(
        throws: const RateLimitedException(retryAfter: Duration(seconds: 120)),
      );

      await syncService.sync(); // Arms the cooldown.
      for (var i = 0; i < 5; i++) {
        await syncService.sync();
      }

      expect(
        postCalls,
        1,
        reason:
            'every trigger during the cooldown - standing in for the '
            'periodic timer, debounce, and manual pull-to-refresh, which '
            'all call this same sync() - must be coalesced into zero '
            'additional dispatches',
      );
    });

    test(
      '6. no second row in the current phase is dispatched after the '
      'first 429 - a valid Retry-After stops the REST of the current '
      'pass\'s pending-session batch, not just the next sync() call',
      () async {
        await insertSession(syncStatus: 'pending_create');
        await insertSession(syncStatus: 'pending_create');
        await insertSession(syncStatus: 'pending_create');
        stubPost(
          throws: const RateLimitedException(retryAfter: Duration(seconds: 60)),
        );

        await syncService.sync();

        expect(
          postCalls,
          1,
          reason:
              'the first row\'s 429 should arm the cooldown and stop the '
              'other two pending rows from being dispatched in the SAME '
              'pass, not just gate a later sync() call',
        );
      },
    );

    test('7. a bare 429 (no Retry-After at all - the GlobalLimiter/'
        'auth-attempt-limiter shape) arms the documented 60s DEFAULT cooldown '
        '- corrected behavior: this used to arm nothing', () async {
      await insertSession(syncStatus: 'pending_create');
      stubPost(throws: const RateLimitedException());

      await syncService.sync();
      expect(postCalls, 1);

      // Still well inside the 60s default.
      fakeNow = fakeNow.add(const Duration(seconds: 30));
      await syncService.sync();
      expect(
        postCalls,
        1,
        reason:
            'a bare 429 must still arm a bounded cooldown - the existing '
            'periodic/debounce cadence alone is not a bound on a manual '
            'pull-to-refresh or connectivity-restoration trigger',
      );

      // Past the 60s default.
      fakeNow = fakeNow.add(const Duration(seconds: 31));
      await syncService.sync();
      expect(postCalls, 2, reason: 'the default cooldown must still expire');
    });

    test('8. a malformed Retry-After (never reaches SyncService as anything '
        'but retryAfter == null, since RetryAfterParser already rejected it) '
        'arms the default cooldown - same as bare', () async {
      await insertSession(syncStatus: 'pending_create');
      // RetryAfterParser normalizes malformed/negative/missing headers to
      // `null` before RateLimitedException is ever constructed (see
      // api_service_rate_limit_test.dart for that boundary) - so at the
      // SyncService level, "malformed" and "bare" are the same input.
      stubPost(throws: const RateLimitedException(retryAfter: null));

      await syncService.sync();
      expect(postCalls, 1);

      // Still well inside the 60s default - must be blocked. Checking this
      // (not just that dispatch eventually resumes after the window) is
      // what actually distinguishes "a cooldown was armed" from "no
      // cooldown was ever armed" - both look identical once enough time has
      // passed regardless.
      fakeNow = fakeNow.add(const Duration(seconds: 30));
      await syncService.sync();
      expect(
        postCalls,
        1,
        reason: 'the default cooldown must still be active at 30s',
      );

      fakeNow = fakeNow.add(const Duration(seconds: 31));
      await syncService.sync();
      expect(postCalls, 2, reason: 'default cooldown armed and expires');
    });

    test(
      '9. a negative Retry-After (already normalized to null by '
      'RetryAfterParser before reaching here) arms the default cooldown',
      () async {
        await insertSession(syncStatus: 'pending_create');
        stubPost(throws: const RateLimitedException(retryAfter: null));

        await syncService.sync();
        expect(postCalls, 1);
        fakeNow = fakeNow.add(const Duration(seconds: 30));
        await syncService.sync();
        expect(
          postCalls,
          1,
          reason: 'default cooldown must still be active at 30s',
        );
      },
    );

    test(
      '10. a Retry-After of exactly zero must NOT create an immediate '
      'retry loop - it arms the default cooldown, never a zero-length one',
      () async {
        await insertSession(syncStatus: 'pending_create');
        stubPost(throws: const RateLimitedException(retryAfter: Duration.zero));

        await syncService.sync();
        expect(postCalls, 1);

        // Even a single microtask/tick later (no wall-clock advance at
        // all), a second trigger must still be blocked - a zero-length
        // cooldown would let this dispatch again immediately.
        await syncService.sync();
        expect(
          postCalls,
          1,
          reason:
              'Retry-After: 0 must not be treated as "retry immediately" - '
              'it must fall back to the same bounded default as no header '
              'at all',
        );
      },
    );

    test('11. a valid positive Retry-After is respected exactly (not widened '
        'to the default, not shortened)', () async {
      await insertSession(syncStatus: 'pending_create');
      stubPost(
        throws: const RateLimitedException(retryAfter: Duration(seconds: 5)),
      );

      await syncService.sync();
      expect(postCalls, 1);

      // Still within the 5s window - blocked.
      fakeNow = fakeNow.add(const Duration(seconds: 4));
      await syncService.sync();
      expect(postCalls, 1);

      // Past the 5s window (NOT the 60s default) - dispatches again.
      fakeNow = fakeNow.add(const Duration(seconds: 2));
      await syncService.sync();
      expect(
        postCalls,
        2,
        reason:
            'a real 5s Retry-After must be honored on its own terms, not '
            'silently widened to the 60s default',
      );
    });

    test('12. an extreme Retry-After (already clamped to maxRetryAfter by '
        'RetryAfterParser before construction) is applied as clamped, never '
        're-clamped or re-widened by SyncService', () async {
      await insertSession(syncStatus: 'pending_create');
      stubPost(
        throws: const RateLimitedException(
          retryAfter: Duration(minutes: 15), // RetryAfterParser.maxRetryAfter
        ),
      );

      await syncService.sync();
      expect(postCalls, 1);

      fakeNow = fakeNow.add(const Duration(minutes: 14, seconds: 59));
      await syncService.sync();
      expect(postCalls, 1, reason: 'still within the clamped 15-minute window');

      fakeNow = fakeNow.add(const Duration(seconds: 2));
      await syncService.sync();
      expect(postCalls, 2);
    });

    test(
      '17. at/after expiry exactly one owned sync attempt proceeds - the '
      'boundary itself (untilUtc, not before it) is already eligible',
      () async {
        await insertSession(syncStatus: 'pending_create');
        stubPost(
          throws: const RateLimitedException(retryAfter: Duration(seconds: 30)),
        );

        await syncService.sync();
        expect(postCalls, 1);

        // One second past the deadline.
        fakeNow = fakeNow.add(const Duration(seconds: 31));
        await syncService.sync();
        expect(postCalls, 2);
      },
    );

    test(
      '19. a later successful retry after the cooldown elapses converges '
      'normally - syncError/syncRetryCount reset, row marked synced',
      () async {
        final s = await insertSession(syncStatus: 'pending_create');
        stubPost(
          throws: const RateLimitedException(retryAfter: Duration(seconds: 30)),
        );

        await syncService.sync();
        var stored = await reload(s.localId);
        expect(stored!.syncStatus, 'pending_create');
        expect(stored.isSynced, isFalse);

        fakeNow = fakeNow.add(const Duration(seconds: 31));
        stubPost(
          returns: {
            'id': 999,
            'userId': userA,
            'date': '2026-01-01',
            'duration': null,
            'notes': null,
            'type': null,
            'name': 'Workout',
            'status': 'draft',
            'startedAt': null,
            'completedAt': null,
            'pausedAt': null,
            'exercises': <dynamic>[],
            'programId': null,
            'programWorkoutId': null,
            'version': 1,
          },
        );

        await syncService.sync();

        stored = await reload(s.localId);
        expect(stored!.isSynced, isTrue);
        expect(stored.syncError, isNull);
        expect(stored.syncRetryCount, 0);
        expect(postCalls, 2);
      },
    );

    test('20. logout before the cooldown elapses prevents any retry - sync() '
        'returns immediately once there is no active session, never even '
        'reaching the cooldown check', () async {
      await insertSession(syncStatus: 'pending_create');
      stubPost(
        throws: const RateLimitedException(retryAfter: Duration(seconds: 60)),
      );

      await syncService.sync();
      expect(postCalls, 1);

      sessionEpoch.invalidate(); // Logout.
      await syncService.sync();

      expect(
        postCalls,
        1,
        reason: 'a logged-out session must never dispatch, cooldown or not',
      );
    });

    test(
      '21. a user switch (A -> B) does not inherit A\'s cooldown - B '
      'dispatches immediately even though A is still "cooling down"',
      () async {
        await insertSession(uid: userA, syncStatus: 'pending_create');
        stubPost(
          throws: const RateLimitedException(
            retryAfter: Duration(seconds: 300),
          ),
        );

        await syncService.sync(); // Arms A's cooldown.
        expect(postCalls, 1);

        // Switch to user B WITHOUT rebuilding SyncService, UserSessionEpoch,
        // or SessionRequestCoordinator - a real app's singleton SyncService
        // is never recreated on login; only the shared epoch's active user
        // changes. Rebuilding any of those here would trivially "pass" by
        // starting from a fresh, empty _rateLimitCooldown instead of
        // actually exercising the token comparison this test is for.
        sessionEpoch.invalidate();
        sessionEpoch.activate(userB);
        when(mockAuthService.getUserId()).thenAnswer((_) async => userB);
        when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$userB');
        await insertSession(uid: userB, syncStatus: 'pending_create');
        stubPost(
          returns: {
            'id': 1,
            'userId': userB,
            'date': '2026-01-01',
            'duration': null,
            'notes': null,
            'type': null,
            'name': 'Workout',
            'status': 'draft',
            'startedAt': null,
            'completedAt': null,
            'pausedAt': null,
            'exercises': <dynamic>[],
            'programId': null,
            'programWorkoutId': null,
            'version': 1,
          },
        );

        await syncService.sync();

        expect(
          postCalls,
          2,
          reason: "B's own sync must not be gated by A's cooldown",
        );
      },
    );

    test(
      '25. while the cooldown is active, sync() never touches Isar at all - '
      'a newer local edit made during the window is completely untouched',
      () async {
        final s = await insertSession(syncStatus: 'pending_create');
        stubPost(
          throws: const RateLimitedException(retryAfter: Duration(seconds: 60)),
        );

        await syncService.sync(); // Arms the cooldown.
        expect(postCalls, 1);

        // A newer local edit lands during the cooldown window.
        final edited = (await reload(s.localId))!;
        edited.name = 'Edited mid-cooldown';
        edited.lastModifiedLocal = DateTime(2026, 1, 1, 9);
        await isar.writeTxn(() => isar.localSessions.put(edited));

        fakeNow = fakeNow.add(const Duration(seconds: 5));
        await syncService.sync(); // Skipped entirely by the cooldown gate.

        expect(postCalls, 1, reason: 'no dispatch during cooldown');
        final stored = await reload(s.localId);
        expect(stored!.name, 'Edited mid-cooldown');
        expect(stored.syncStatus, 'pending_create');
        expect(
          stored.syncRetryCount,
          0,
          reason:
              'the older cooled-down operation must not be able to touch '
              "(and can't, since it never dispatches) a row a newer local "
              'edit has since modified',
        );
      },
    );

    test('13/14 (retryFailedSyncs trigger). retryFailedSyncs() is not a second '
        'scheduler - it also funnels through sync() and is coalesced by an '
        'active cooldown exactly like every other trigger', () async {
      final s = await insertSession(
        syncStatus: 'pending_create',
        serverId: null,
      );
      // Saturate the retry counter first, as retryFailedSyncs() targets it.
      await isar.writeTxn(() async {
        final row = (await reload(s.localId))!;
        row.syncRetryCount = 5;
        await isar.localSessions.put(row);
      });

      stubPost(
        throws: const RateLimitedException(retryAfter: Duration(seconds: 60)),
      );
      await syncService.sync(); // Arms the cooldown.
      expect(postCalls, 1);

      await syncService.retryFailedSyncs();

      expect(
        postCalls,
        1,
        reason:
            'retryFailedSyncs() resets the saturated counter (existing '
            'behavior, unrelated to rate limiting) but its own trailing '
            'sync() call must still respect the active cooldown - it must '
            'not dispatch a second HTTP call',
      );
    });

    test('18. overlapping post-expiry triggers still coalesce into one owned '
        'attempt via the existing operation-ownership machinery', () async {
      await insertSession(syncStatus: 'pending_create');
      stubPost(
        returns: {
          'id': 1,
          'userId': userA,
          'date': '2026-01-01',
          'duration': null,
          'notes': null,
          'type': null,
          'name': 'Workout',
          'status': 'draft',
          'startedAt': null,
          'completedAt': null,
          'pausedAt': null,
          'exercises': <dynamic>[],
          'programId': null,
          'programWorkoutId': null,
          'version': 1,
        },
      );

      // No cooldown active - two overlapping (un-awaited-between) calls
      // must still coalesce into a single in-flight pass via
      // `_activeOperation`, exactly like any other pair of concurrent
      // sync() calls for the same session (pre-existing machinery this
      // rate-limit work does not alter).
      final f1 = syncService.sync();
      final f2 = syncService.sync();
      await Future.wait([f1, f2]);

      expect(
        postCalls,
        1,
        reason:
            'two overlapping triggers for the same session must be '
            'coalesced into one physical pass, not two',
      );
    });

    test(
      'dispose() cancels scheduling but never disturbs the token-scoped '
      'cooldown check itself (dispose has no special authority over it, '
      'matching the class doc comment\'s policy for _activeOperation)',
      () async {
        await insertSession(syncStatus: 'pending_create');
        stubPost(
          throws: const RateLimitedException(retryAfter: Duration(seconds: 60)),
        );

        await syncService.sync(); // Arms the cooldown.
        expect(postCalls, 1);

        syncService.dispose();

        // A manual call after dispose() is still possible (dispose() only
        // tears down timers/listeners) and must still respect the cooldown.
        await syncService.sync();
        expect(
          postCalls,
          1,
          reason:
              'dispose() must not accidentally clear or bypass the '
              'cooldown gate',
        );
      },
    );

    test(
      '24. RequestCancelledException and SessionStaleException reaching the '
      'orchestration handler remain typed as themselves - never arm the '
      'rate-limit cooldown, never get relabeled as RateLimitedException, and '
      'never get recorded as a diagnostic sync failure (a swallowed rethrow '
      'that let it fall into the generic per-row catch would record one)',
      () async {
        final s = await insertSession(syncStatus: 'pending_create');
        // An independently-pending exercise under a SEPARATE, already-synced
        // parent session - if the lifecycle exception were swallowed instead
        // of propagating out of the sessions phase to abort the whole pass,
        // this row's own CREATE would ALSO dispatch (and also throw the same
        // stub), incrementing postCalls a second time. This is what makes
        // "swallowed and the pass continues" observable, distinct from "the
        // pass genuinely aborted immediately".
        final parent = LocalSession(
          serverId: 500,
          userId: userA,
          date: DateTime(2026, 1, 1),
          name: 'Parent',
          status: 'draft',
          isSynced: true,
          syncStatus: 'synced',
          version: 1,
          lastModifiedLocal: DateTime(2026, 1, 1, 8),
        );
        await isar.writeTxn(() => isar.localSessions.put(parent));
        final exercise = LocalExercise(
          sessionLocalId: parent.localId,
          sessionServerId: parent.serverId,
          name: 'Bench press',
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime(2026, 1, 1, 8),
        );
        await isar.writeTxn(() => isar.localExercises.put(exercise));

        stubPost(throws: const RequestCancelledException());

        await syncService.sync();
        expect(
          postCalls,
          1,
          reason:
              'only the session CREATE should ever be attempted - a '
              'genuine lifecycle abort must stop the pass before the '
              'exercise phase even starts',
        );

        final stored = await reload(s.localId);
        expect(
          stored!.syncRetryCount,
          0,
          reason:
              'a lifecycle abort must never be recorded as a diagnostic '
              'failure - only a genuine hard/soft sync error advances this',
        );
        expect(stored.syncError, isNull);

        // If RequestCancelledException had been mishandled as a rate limit,
        // this second call would be blocked. It must not be - cancellation
        // is a lifecycle outcome, never a cooldown trigger.
        await syncService.sync();
        expect(
          postCalls,
          2,
          reason:
              'a cancelled request must never arm a cooldown or be '
              'reclassified as rate limiting',
        );
      },
    );

    test('24b. SessionStaleException likewise never arms the cooldown and is '
        'never recorded as a diagnostic sync failure', () async {
      final s = await insertSession(syncStatus: 'pending_create');
      stubPost(throws: const SessionStaleException());

      await syncService.sync();
      expect(postCalls, 1);

      final stored = await reload(s.localId);
      expect(stored!.syncRetryCount, 0);
      expect(stored.syncError, isNull);

      await syncService.sync();
      expect(postCalls, 2, reason: 'staleness must never arm a cooldown');
    });

    test('22a. a bare (no Retry-After) global 429 preserves a pending_update '
        'Session row unchanged - the row is never acknowledged, deleted, or '
        'flipped to conflict', () async {
      final s = await insertSession(
        syncStatus: 'pending_update',
        serverId: 42,
        version: 1,
      );
      when(
        mockApiService.put<dynamic>(
          any,
          data: anyNamed('data'),
          sessionContext: anyNamed('sessionContext'),
        ),
      ).thenAnswer((_) async {
        postCalls++;
        throw const RateLimitedException();
      });

      await syncService.sync();

      final stored = await reload(s.localId);
      expect(stored!.syncStatus, 'pending_update');
      expect(stored.isSynced, isFalse);
      expect(postCalls, 1);
    });

    test('22b. a bare global 429 preserves a pending_delete Session row '
        'unchanged', () async {
      final s = await insertSession(
        syncStatus: 'pending_delete',
        serverId: 4242,
      );
      when(
        mockApiService.delete(any, sessionContext: anyNamed('sessionContext')),
      ).thenAnswer((_) async {
        postCalls++;
        throw const RateLimitedException();
      });

      await syncService.sync();

      final stored = await reload(s.localId);
      expect(stored, isNotNull, reason: 'the row must still exist');
      expect(stored!.syncStatus, 'pending_delete');
      expect(postCalls, 1);
    });

    test('a RateLimitedException on a pending_create row is soft - '
        'syncRetryCount stays at 0, mirroring the existing '
        'ApiException(429)-based soft-path guarantee for the real production '
        'exception type', () async {
      final s = await insertSession(syncStatus: 'pending_create');
      stubPost(throws: const RateLimitedException());

      // Advance past the default cooldown between calls so each one
      // actually dispatches and re-hits the soft path, rather than being
      // skipped by the gate itself.
      await syncService.sync();
      fakeNow = fakeNow.add(const Duration(seconds: 61));
      await syncService.sync();
      fakeNow = fakeNow.add(const Duration(seconds: 61));
      await syncService.sync();

      final stored = await reload(s.localId);
      expect(
        stored!.syncRetryCount,
        0,
        reason:
            'SessionCreateError.isSoftRetryable(RateLimitedException) '
            'must suppress the retry-count bump for a still-pending_create '
            'row across repeated 429s, exactly like the legacy '
            'ApiException(429) shape already tested in '
            'sync_service_create_soft_error_test.dart',
      );
      expect(stored.syncStatus, 'pending_create');
    });

    test(
      '23. children of a session hit by a bare global 429 remain intact',
      () async {
        final s = await insertSession(syncStatus: 'pending_create');
        final exercise = LocalExercise(
          sessionLocalId: s.localId,
          name: 'Bench press',
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime(2026, 1, 1, 8),
        );
        late LocalExerciseSet set;
        await isar.writeTxn(() async {
          await isar.localExercises.put(exercise);
          set = LocalExerciseSet(
            exerciseLocalId: exercise.localId,
            setNumber: 1,
            reps: 5,
            weight: 100,
            isSynced: false,
            syncStatus: 'pending_create',
            lastModifiedLocal: DateTime(2026, 1, 1, 8),
          );
          await isar.localExerciseSets.put(set);
        });

        stubPost(throws: const RateLimitedException());
        await syncService.sync();

        expect(await isar.localExercises.get(exercise.localId), isNotNull);
        expect(await isar.localExerciseSets.get(set.localId), isNotNull);
      },
    );
  });
}
