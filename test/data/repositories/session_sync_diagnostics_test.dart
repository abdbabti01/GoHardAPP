import 'package:flutter_test/flutter_test.dart';

import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';

/// Pure, deterministic tests for [SessionSyncDiagnostics.deriveFrom] - the
/// single place a [LocalSession] row's sync state is classified for UI
/// purposes. No Isar, no streams, no async - a plain function over a plain
/// object, so every case is exercised directly and instantly.
void main() {
  LocalSession session({
    required String syncStatus,
    String? syncError,
    int syncRetryCount = 0,
    DateTime? lastSyncAttempt,
    DateTime? conflictDetectedAt,
    int userId = 1,
  }) => LocalSession(
    userId: userId,
    date: DateTime(2026, 1, 1),
    status: 'draft',
    syncStatus: syncStatus,
    syncRetryCount: syncRetryCount,
    syncError: syncError,
    lastSyncAttempt: lastSyncAttempt,
    conflictDetectedAt: conflictDetectedAt,
    lastModifiedLocal: DateTime(2026, 1, 1),
  );

  test('1. a saturated pending_create with a retained error is retrying, '
      'not terminal - classification never consults syncRetryCount', () {
    final s = session(
      syncStatus: 'pending_create',
      syncError: 'Exception: boom',
      syncRetryCount: 3, // == _maxRetries, saturated
    );
    final d = SessionSyncDiagnostics.deriveFrom(s);
    expect(d, isNotNull);
    expect(d!.state, SessionSyncState.retryingFailure);
    expect(d.isRetryingFailure, isTrue);
    expect(d.isConflict, isFalse);
  });

  test('a pending_create with a retained error but syncRetryCount == 0 '
      '(soft-error path) is still classified retrying', () {
    final s = session(syncStatus: 'pending_create', syncError: 'boom');
    final d = SessionSyncDiagnostics.deriveFrom(s);
    expect(d?.state, SessionSyncState.retryingFailure);
  });

  test('2. a failed pending_update is visible as a retrying failure', () {
    final s = session(
      syncStatus: 'pending_update',
      syncError: 'Exception: 500',
    );
    expect(
      SessionSyncDiagnostics.deriveFrom(s)?.state,
      SessionSyncState.retryingFailure,
    );
  });

  test('a failed pending_delete is classified retrying (contributes to the '
      'aggregate even though it is excluded from the visible list at the '
      'repository layer - see the join test)', () {
    final s = session(
      syncStatus: 'pending_delete',
      syncError: 'Exception: 429',
    );
    expect(
      SessionSyncDiagnostics.deriveFrom(s)?.state,
      SessionSyncState.retryingFailure,
    );
  });

  test('4. conflict is a distinct state and never "retrying", even if a '
      'stale syncError string is still present from before the conflict '
      'was detected', () {
    final s = session(
      syncStatus: 'conflict',
      syncError: 'stale error text from a previous pass',
      conflictDetectedAt: DateTime(2026, 2, 2),
    );
    final d = SessionSyncDiagnostics.deriveFrom(s);
    expect(d!.state, SessionSyncState.conflict);
    expect(d.isConflict, isTrue);
    expect(d.isRetryingFailure, isFalse);
    expect(d.lastAttemptAt, DateTime(2026, 2, 2));
  });

  test('5a. a synced row is healthy - no diagnostics', () {
    final s = session(syncStatus: 'synced');
    expect(SessionSyncDiagnostics.deriveFrom(s), isNull);
  });

  test('5b. a pending row with no retained syncError is healthy - not '
      'labelled an error merely because it has not synced yet', () {
    for (final status in [
      'pending_create',
      'pending_update',
      'pending_delete',
    ]) {
      final s = session(syncStatus: status, syncError: null);
      expect(
        SessionSyncDiagnostics.deriveFrom(s),
        isNull,
        reason: '$status with no syncError must be healthy',
      );
    }
  });

  test('lifecycle cancellation never sets syncError, so a row whose last '
      'outcome was a stale-session/cancellation exit is healthy - never '
      'appears as a failure', () {
    // SessionStaleException / RequestCancelledException are rethrown before
    // _markSyncError runs (see SyncService._syncSessions), so syncError stays
    // null. This models exactly that resulting row shape.
    final s = session(syncStatus: 'pending_update', syncError: null);
    expect(SessionSyncDiagnostics.deriveFrom(s), isNull);
  });

  test('retryingFailure carries lastSyncAttempt as its timestamp', () {
    final t = DateTime(2026, 3, 3, 8);
    final s = session(
      syncStatus: 'pending_create',
      syncError: 'boom',
      lastSyncAttempt: t,
    );
    expect(SessionSyncDiagnostics.deriveFrom(s)!.lastAttemptAt, t);
  });

  test('SessionSyncStateCopy never exposes raw syncError text - only the '
      'closed friendly-message set', () {
    const rawLeak =
        'System.NullReferenceException at /var/app/Controllers.cs:42';
    final s = session(syncStatus: 'pending_update', syncError: rawLeak);
    final d = SessionSyncDiagnostics.deriveFrom(s)!;
    expect(d.state.friendlyMessage.contains(rawLeak), isFalse);
    expect(d.state.shortLabel.contains(rawLeak), isFalse);
    // The closed set is exactly two known-safe strings.
    expect(
      d.state.friendlyMessage,
      "This workout hasn't synced yet. Your changes are saved and the app "
      'will keep trying.',
    );
  });

  test('SessionSyncSnapshot.empty has no issues', () {
    expect(SessionSyncSnapshot.empty.hasAnyIssue, isFalse);
    expect(SessionSyncSnapshot.empty.visibleEntries, isEmpty);
  });

  test('SessionSyncSnapshot.hasAnyIssue is true for either count alone', () {
    const retrying = SessionSyncSnapshot(
      visibleEntries: [],
      retryingFailureCount: 1,
      conflictCount: 0,
    );
    const conflict = SessionSyncSnapshot(
      visibleEntries: [],
      retryingFailureCount: 0,
      conflictCount: 1,
    );
    expect(retrying.hasAnyIssue, isTrue);
    expect(conflict.hasAnyIssue, isTrue);
  });
}
