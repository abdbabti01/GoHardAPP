import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/sync_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_goal.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'sync_service_scheduling_ownership_test.mocks.dart';

@GenerateMocks([ApiService, AuthService, ConnectivityService])
/// Proves that periodic/connectivity/debounce scheduling captures its
/// owning session at SCHEDULING time (inside `initialize()`), not at fire
/// time - see the "Session-owned scheduling" section of `SyncService`'s
/// class doc comment.
///
/// Uses `fakeAsync` to advance the virtual clock so a `Timer.periodic`
/// (5-minute interval) or debounce (3-second) timer fires deterministically,
/// with no real sleep. Every `Timer`/stream-listener a single test needs to
/// observe firing is created and elapsed within ONE `fakeAsync` call -
/// `Timer`s registered inside one `fakeAsync` zone are never visible to a
/// later, separate `fakeAsync` call's virtual clock.
///
/// Assertions are made on `debugPrint` output reaching (or not reaching)
/// "Starting sync"/"Periodic sync triggered", not on the sync pass's full
/// completion: `sync()` prints "Starting sync..." as its very first action
/// and only reaches genuine Isar I/O afterward, so this signal resolves
/// purely from `flushMicrotasks()` (mocked `AuthService`/`ApiService` calls
/// involved before that point are plain Dart Futures) without depending on
/// real native I/O completing inside the fake zone, which is not
/// guaranteed.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockApiService mockApiService;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late SyncService syncService;
  late StreamController<bool> connectivityController;
  late bool isOnline;

  const userA = 1;
  const userB = 2;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sync_service_scheduling_ownership_',
    );
    // Deliberately registers a schema (Isar requires at least one) OTHER
    // than LocalSession. This file only needs to observe whether a
    // scheduled callback reaches sync() at all (via debugPrint), never
    // whether a full pass completes - and letting `_syncSessions` actually
    // reach genuine native Isar I/O from inside a `fakeAsync` zone is
    // unsafe (that I/O does not resolve via the fake clock/microtask queue
    // and orphans, hanging a later `isar.close()`). With `LocalSession`
    // unregistered, `db.localSessions` throws immediately (a pure-Dart
    // check, resolved entirely by `flushMicrotasks()`), which
    // `_startSyncPass`'s catch-all logs and swallows exactly like any
    // other ordinary sync failure - "Starting sync..." still prints first.
    isar = await Isar.open(
      [LocalGoalSchema],
      directory: tempDir.path,
      inspector: false,
    );

    mockApiService = MockApiService();
    mockAuthService = MockAuthService();
    when(mockAuthService.getUserId()).thenAnswer((_) async => userA);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt');

    isOnline = true;
    connectivityController = StreamController<bool>.broadcast();
    mockConnectivity = MockConnectivityService();
    when(mockConnectivity.isOnline).thenAnswer((_) => isOnline);
    when(
      mockConnectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch();
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );

    SyncService.reset();
    syncService = SyncService(
      apiService: mockApiService,
      authService: mockAuthService,
      localDb: localDb,
      connectivity: mockConnectivity,
      sessionEpoch: sessionEpoch,
      sessionCoordinator: sessionCoordinator,
    );

    when(
      mockApiService.post<Map<String, dynamic>>(
        any,
        data: anyNamed('data'),
        sessionContext: anyNamed('sessionContext'),
      ),
    ).thenAnswer((_) async => {'id': 1});
  });

  tearDown(() async {
    SyncService.reset();
    await connectivityController.close();
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  List<String> captureDebugPrint(void Function() body) {
    final captured = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) captured.add(message);
    };
    try {
      body();
    } finally {
      debugPrint = originalDebugPrint;
    }
    return captured;
  }

  /// Like [captureDebugPrint], but returns the mutable list itself (instead
  /// of restoring `debugPrint` when [body] returns) so a caller running a
  /// multi-stage `fakeAsync` body can `clear()` it partway through - e.g.
  /// to discard an earlier, legitimate sync's output before observing only
  /// what a later stage under test produces. The caller MUST restore
  /// `debugPrint` itself once finished (see `finishCapture` below).
  List<String> beginDebugPrintCapture() {
    final captured = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) captured.add(message);
    };
    return captured;
  }

  test('a periodic callback scheduled by A no-ops after B logs in - it never '
      'adopts B\'s token at fire time (test 7)', () {
    final originalDebugPrint = debugPrint;
    late List<String> captured;
    try {
      fakeAsync((async) {
        sessionEpoch.activate(userA);
        syncService.initialize();
        async.flushMicrotasks();
        // Let the initial online-triggered debounced sync settle before
        // the periodic timer (the thing under test) is what fires -
        // captured separately below so its legitimate "Starting sync"
        // output can't be confused with the stale-timer assertion.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        // Session changes WITHOUT calling dispose() first - proving the
        // callback's OWN check is what protects it, not merely that
        // dispose() already cancelled the timer. Capture only begins
        // here.
        captured = beginDebugPrintCapture();
        sessionEpoch.invalidate();
        sessionEpoch.activate(userB);

        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
      });
    } finally {
      debugPrint = originalDebugPrint;
    }

    expect(
      captured.any((l) => l.contains('Periodic sync triggered')),
      isTrue,
      reason: 'sanity check: the timer itself must still fire',
    );
    expect(
      captured.any((l) => l.contains('superseded session')),
      isTrue,
      reason:
          'A\'s stale periodic timer must recognize its token is no '
          'longer current and no-op',
    );
    expect(
      captured.any((l) => l.contains('Starting sync')),
      isFalse,
      reason:
          'it must never adopt B\'s session and proceed into sync() at '
          'all',
    );
  });

  test('a connectivity-triggered debounce scheduled by A cannot become B\'s '
      'sync (test 8)', () {
    final originalDebugPrint = debugPrint;
    late List<String> captured;
    try {
      fakeAsync((async) {
        sessionEpoch.activate(userA);
        syncService.initialize();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        captured = beginDebugPrintCapture();
        sessionEpoch.invalidate();
        sessionEpoch.activate(userB);

        // An online event on the SAME stream/listener A's initialize()
        // subscribed to - the debounce it schedules still closes over
        // A's token, captured at scheduling (initialize) time.
        connectivityController.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
      });
    } finally {
      debugPrint = originalDebugPrint;
    }

    expect(
      captured.any((l) => l.contains('superseded session')),
      isTrue,
      reason:
          'the debounce fired under a token that is no longer current '
          'and must no-op',
    );
    expect(captured.any((l) => l.contains('Starting sync')), isFalse);
  });

  test('logged-out initialize() schedules nothing (test 9)', () {
    final captured = captureDebugPrint(() {
      fakeAsync((async) {
        // No sessionEpoch.activate() call - stays logged out.
        syncService.initialize();
        async.flushMicrotasks();

        connectivityController.add(true);
        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
      });
    });

    expect(
      captured.any((l) => l.contains('SyncService initialized')),
      isFalse,
      reason: 'initialize() must not have completed scheduling setup',
    );
    expect(captured.any((l) => l.contains('Periodic sync triggered')), isFalse);
  });

  test('B\'s own initialize() after A creates fresh, live scheduling for B '
      '(test 10)', () {
    final captured = captureDebugPrint(() {
      fakeAsync((async) {
        sessionEpoch.activate(userA);
        syncService.initialize();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        syncService.dispose();
        sessionEpoch.invalidate();
        sessionEpoch.activate(userB);

        syncService.initialize();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
      });
    });

    expect(
      captured.where((l) => l.contains('SyncService initialized')),
      hasLength(2),
      reason: 'sanity check: both initialize() calls completed setup',
    );
    expect(
      captured.any((l) => l.contains('Starting sync')),
      isTrue,
      reason:
          'B\'s freshly-initialized periodic timer must be live and '
          'reach sync() under B\'s own, current token',
    );
    expect(captured.any((l) => l.contains('superseded session')), isFalse);
  });

  test(
    'repeated initialize()/dispose() creates no duplicate timers (test 11)',
    () {
      final captured = captureDebugPrint(() {
        fakeAsync((async) {
          sessionEpoch.activate(userA);

          // Two initialize() calls back-to-back without an intervening
          // dispose() - idempotent, must not create a second periodic
          // timer.
          syncService.initialize();
          syncService.initialize();
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();

          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();
        });
      });

      expect(
        captured.where((l) => l.contains('SyncService initialized')),
        hasLength(1),
        reason: 'the second initialize() call must be a no-op',
      );
      expect(
        captured.where((l) => l.contains('Periodic sync triggered')),
        hasLength(1),
        reason: 'exactly one periodic timer must have fired, not two',
      );

      // dispose()/initialize() repeated a few times must also stay clean -
      // no crash, and still exactly one live periodic timer afterward.
      final capturedSecondRound = captureDebugPrint(() {
        fakeAsync((async) {
          syncService.dispose();
          syncService.dispose();
          syncService.initialize();
          syncService.initialize();
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();

          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();
        });
      });

      expect(
        capturedSecondRound.where((l) => l.contains('SyncService initialized')),
        hasLength(1),
      );
      expect(
        capturedSecondRound.where((l) => l.contains('Periodic sync triggered')),
        hasLength(1),
      );
    },
  );
}
