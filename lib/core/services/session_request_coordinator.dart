import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../data/services/auth_service.dart';
import '../../data/services/session_request_context.dart';
import 'user_session_epoch.dart';

/// Captures `SessionRequestContext`s and owns the generation-scoped Dio
/// [CancelToken] each one carries.
///
/// Depends only on [UserSessionEpoch] and [AuthService] - both already
/// dependency-free leaf services in this codebase - so it can be injected
/// into `ApiService`, `AuthProvider`, repositories, and `SyncService` alike
/// without ever creating a cycle back toward any of them. It never depends
/// on `ApiService`, `AuthProvider`, `BuildContext`, or any feature
/// Provider, and never calls [UserSessionEpoch.activate]/[invalidate] -
/// only [UserSessionEpoch.capture]/[isCurrent], exactly like every other
/// read-only consumer of the shared epoch.
///
/// This PR only implements capture and cancellation as standalone,
/// independently-tested primitives. Nothing yet calls
/// [cancelCurrentGeneration] from `AuthProvider`'s logout pass - that wiring
/// is deliberately deferred to PR C (see the class-level doc comment on
/// `ApiService` for the full deferred-migration sequence).
class SessionRequestCoordinator {
  SessionRequestCoordinator(this._sessionEpoch, this._authService);

  final UserSessionEpoch _sessionEpoch;
  final AuthService _authService;

  CancelToken? _cancelToken;
  int? _cancelTokenGeneration;

  /// Test-only override for how a generation's [CancelToken] is minted -
  /// lets a test inject a token whose `cancel()` throws, to prove
  /// [cancelCurrentGeneration] swallows a failure from the underlying
  /// cancellation machinery rather than propagating it. Defaults to null in
  /// production, in which case the real [CancelToken.new] is used;
  /// production behavior/performance are unaffected.
  @visibleForTesting
  CancelToken Function()? cancelTokenFactoryForTesting;

  /// Returns the [CancelToken] for [generation], minting a fresh one the
  /// first time this generation is seen. [UserSessionEpoch.activate] always
  /// bumps the generation - including for the same user re-authenticating -
  /// so a same-user relogin naturally mints a fresh token here too; a
  /// previously-cancelled token is never handed out again, because
  /// [captureContext] can only ever reach this method with the generation
  /// [UserSessionEpoch.capture] just reported as CURRENTLY active, never a
  /// stale/invalidated one.
  ///
  /// Deliberately synchronous, with no `await` anywhere in its body -
  /// [captureContext] calls this BEFORE awaiting [AuthService.getToken],
  /// so a logout that invalidates and cancels while that read is in flight
  /// always finds a real, already-minted token to cancel rather than a gap
  /// where a not-yet-created token would be missed entirely.
  CancelToken _cancelTokenFor(int generation) {
    if (_cancelTokenGeneration != generation) {
      _cancelToken = (cancelTokenFactoryForTesting ?? CancelToken.new)();
      _cancelTokenGeneration = generation;
    }
    return _cancelToken!;
  }

  /// Captures one [SessionRequestContext] for the currently active session,
  /// or `null` if there is nothing to capture for (logged out, or the
  /// session changed while the JWT read below was in flight).
  ///
  /// 1. Capture the [UserSessionToken] synchronously.
  /// 2. If there is no active session, return null.
  /// 3. Obtain that generation's [CancelToken] synchronously, before the
  ///    first `await` (see [_cancelTokenFor]'s doc comment for why this
  ///    ordering matters).
  /// 4. Await [AuthService.getToken].
  /// 5. Recheck [UserSessionEpoch.isCurrent] - a logout/relogin race during
  ///    step 4 must not silently adopt a different session's token.
  /// 6. Reject a null/empty JWT - never build a context around one.
  /// 7. Return the immutable context.
  Future<SessionRequestContext?> captureContext() async {
    final epochToken = _sessionEpoch.capture();
    if (epochToken == null) return null;

    final cancelToken = _cancelTokenFor(epochToken.generation);

    final jwt = await _authService.getToken();

    if (!_sessionEpoch.isCurrent(epochToken)) return null;
    if (jwt == null || jwt.isEmpty) return null;

    return SessionRequestContext(
      epochToken: epochToken,
      jwt: jwt,
      cancelToken: cancelToken,
    );
  }

  /// Best-effort, non-throwing cancellation of the most recently active
  /// generation's [CancelToken]. Safe to call even if no context was ever
  /// captured (no-op) and even if the underlying cancellation machinery
  /// itself throws - callers (a future logout pass) must never be blocked
  /// or fail because of this.
  ///
  /// Cancelling generation A's token never affects generation B's: once
  /// [_cancelTokenFor] has minted a token for a newer generation, this
  /// method only ever sees and cancels that newer token.
  void cancelCurrentGeneration() {
    try {
      final token = _cancelToken;
      if (token != null && !token.isCancelled) {
        token.cancel('Session ended');
      }
    } catch (_) {
      // Best-effort - deliberately swallowed.
    }
  }
}
