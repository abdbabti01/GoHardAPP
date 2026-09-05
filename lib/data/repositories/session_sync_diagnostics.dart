import 'package:flutter/foundation.dart';

import '../local/models/local_session.dart';
import '../models/session.dart';

/// Derived, non-persisted classification of a [LocalSession]'s sync state,
/// safe to show to a user. Never carries [LocalSession.syncError]'s raw
/// text - that may contain HTTP response bodies, implementation exception
/// text (including local filesystem paths), or other content that was
/// never meant to be user-facing. UI code must translate [SessionSyncState]
/// into a closed set of friendly strings itself; this type intentionally
/// gives it nothing else to render.
enum SessionSyncState {
  /// `syncStatus == 'pending_*'` with a retained `syncError` - the session
  /// has not synced and at least one attempt has failed, but this is NEVER
  /// terminal: automatic retries continue regardless of `syncRetryCount`
  /// (which only saturates, never gates retry - see `SyncService`). A
  /// lifecycle cancellation (session ended / request cancelled mid-sync)
  /// never sets `syncError`, so it can never produce this state.
  retryingFailure,

  /// `syncStatus == 'conflict'` - a well-formed 409 was received and the
  /// server's snapshot was captured; the row is deliberately excluded from
  /// the automatic retry loop pending a manual resolution this app does not
  /// yet offer. Distinct from [retryingFailure]: never call this "retrying".
  conflict,
}

/// A single [LocalSession] row's derived sync diagnostics, or `null` if the
/// row is healthy (synced, or still pending with no retained failure - see
/// [deriveFrom]). Immutable, non-persisted, carries no raw error text.
@immutable
class SessionSyncDiagnostics {
  final SessionSyncState state;

  /// When this diagnostic condition was last observed - the conflict
  /// detection time for [SessionSyncState.conflict], or the last failed
  /// sync attempt time for [SessionSyncState.retryingFailure]. May be null
  /// (e.g. a conflict row with no recorded detection timestamp).
  final DateTime? lastAttemptAt;

  const SessionSyncDiagnostics({required this.state, this.lastAttemptAt});

  bool get isConflict => state == SessionSyncState.conflict;
  bool get isRetryingFailure => state == SessionSyncState.retryingFailure;

  /// Pure derivation from a single [LocalSession] row - reads existing
  /// fields only (`syncStatus`, `syncError`, `lastSyncAttempt`,
  /// `conflictDetectedAt`), performs no Isar write, no HTTP call, and no
  /// `SyncService` call. Returns `null` for:
  ///  - a fully `synced` row;
  ///  - a `pending_*` row with no retained `syncError` (healthy pending
  ///    work that simply hasn't synced yet - never presented as an error);
  ///  - a row whose last outcome was a lifecycle cancellation/stale-session
  ///    exit, since those never set `syncError` (see `SyncService`'s
  ///    `_syncSessions`, which rethrows `SessionStaleException` /
  ///    `RequestCancelledException` before `_markSyncError` ever runs).
  ///
  /// `syncRetryCount` is deliberately NOT consulted here: reaching
  /// `_maxRetries` is a bounded diagnostic, never a terminal state (see
  /// `SyncService._markSyncError`), so classification must not change at
  /// the saturation point - a session that failed once and a session
  /// saturated at `_maxRetries` are both simply "retrying".
  static SessionSyncDiagnostics? deriveFrom(LocalSession session) {
    if (session.syncStatus == 'conflict') {
      return SessionSyncDiagnostics(
        state: SessionSyncState.conflict,
        lastAttemptAt: session.conflictDetectedAt,
      );
    }

    final isPending =
        session.syncStatus == 'pending_create' ||
        session.syncStatus == 'pending_update' ||
        session.syncStatus == 'pending_delete';

    if (isPending && session.syncError != null) {
      return SessionSyncDiagnostics(
        state: SessionSyncState.retryingFailure,
        lastAttemptAt: session.lastSyncAttempt,
      );
    }

    return null;
  }
}

/// Closed set of user-safe copy for a single session's [SessionSyncState] -
/// the ONLY place this app turns a sync-diagnostic state into displayed
/// text. Never derived from `LocalSession.syncError`, which may contain raw
/// HTTP response bodies, implementation exception text, or local filesystem
/// paths - see [SessionSyncDiagnostics.deriveFrom].
extension SessionSyncStateCopy on SessionSyncState {
  /// One-line badge/detail-screen-icon description.
  String get shortLabel => switch (this) {
    SessionSyncState.retryingFailure => 'Not synced yet',
    SessionSyncState.conflict => 'Needs review',
  };

  /// Full passive explanation, safe for a detail dialog or a card's
  /// accessibility label. Always states that local changes are preserved
  /// and (for a retrying failure) that automatic retry continues - never
  /// implies retry count reaching its cap is a stopping point.
  String get friendlyMessage => switch (this) {
    SessionSyncState.retryingFailure =>
      "This workout hasn't synced yet. Your changes are saved and the app "
          'will keep trying.',
    SessionSyncState.conflict =>
      'This workout changed elsewhere. Your local changes are preserved '
          'and need review.',
  };
}

/// One entry in the visible session list, pairing a mapped [Session] with
/// its owning [LocalSession.localId] and derived [diagnostics] - built from
/// the SAME [LocalSession] instance in the SAME pass, so there is never a
/// later lookup keyed by the ambiguous `Session.id`
/// (`serverId ?? localId`, which can collide between the server-id and
/// local-id namespaces - see `ModelMapper.localToSession`). Consumers must
/// key off [localId], never off `session.id`.
@immutable
class SessionListEntry {
  final Session session;
  final int localId;

  /// Null when the session is healthy (synced, or pending with no retained
  /// failure) - absence of diagnostics IS the healthy state; there is no
  /// separate "healthy" enum value to render.
  final SessionSyncDiagnostics? diagnostics;

  const SessionListEntry({
    required this.session,
    required this.localId,
    this.diagnostics,
  });
}

/// One joined, single-watch snapshot of a user's sessions plus their sync
/// diagnostics - see `SessionRepository.watchSessionSyncSnapshot`.
///
/// [retryingFailureCount] and [conflictCount] are computed over EVERY
/// matching row for the user, including a failing `pending_delete` row
/// that is intentionally absent from [visibleEntries] (it stays excluded
/// from the visible list for the same reason `watchSessions` excludes it -
/// a session mid-deletion has no place in a "your workouts" list - but its
/// failure must still be counted, or a stuck delete becomes invisible even
/// to an aggregate banner).
@immutable
class SessionSyncSnapshot {
  final List<SessionListEntry> visibleEntries;
  final int retryingFailureCount;
  final int conflictCount;

  const SessionSyncSnapshot({
    required this.visibleEntries,
    required this.retryingFailureCount,
    required this.conflictCount,
  });

  static const empty = SessionSyncSnapshot(
    visibleEntries: [],
    retryingFailureCount: 0,
    conflictCount: 0,
  );

  bool get hasAnyIssue => retryingFailureCount > 0 || conflictCount > 0;
}
