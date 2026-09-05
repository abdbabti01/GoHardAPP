import 'api_exception.dart';

/// Internal, typed classification of a failure observed while creating a
/// Session on the server (`POST /api/v1/sessions`).
///
/// The sync layer uses this to decide retry / terminal-cleanup behavior
/// WITHOUT string-matching a human-readable error message, and it gives the
/// later durable-operation-key work a stable value to branch on instead of
/// re-parsing response bodies.
///
/// The deployed GoHardAPI contract for this endpoint is:
///
/// * `201` - legacy create accepted (`SessionResponseDto`)
/// * `200` - keyed replay of an already-committed create (`SessionResponseDto`)
/// * `404 { "code": "program_not_found" }`
/// * `409 { "code": "operation_canceled" }`
/// * `409 { "code": "operation_incomplete" }`
/// * `410 { "code": "operation_target_deleted" }`
/// * `429` - throttling, empty body (bounded only by the shared per-IP
///   limiter today; a per-user Session-write limiter is a later PR)
///
/// A recognised `code` is honoured ONLY on the exact HTTP status the contract
/// pairs it with above. The same known code on any other status - or an
/// unknown code - on 404/409/410 classifies as [SessionCreateErrorKind
/// .unknownStructured] and keeps the established hard / fail-closed behavior.
/// The generic create path (`SessionRepository`/`SyncService`) now sends a
/// durable `clientOperationId` on every dispatch it can (see
/// `LocalSession.clientOperationId`), so the `404`/`409`/`410` operation-state
/// responses ARE reachable in production - they are no longer a
/// misconfigured-proxy-only edge case. The `from-program-workout` offline
/// fallback's ORIGINAL request is still unkeyed (see the boundary note on
/// `SyncService._syncCreateSession`), so these codes remain unreachable for
/// that one specific path until its own lost-acknowledgment defect is fixed
/// separately.
enum SessionCreateErrorKind {
  /// HTTP 429. Throttling / backpressure. Always retryable; never terminal.
  throttled,

  /// HTTP 404 `{ "code": "program_not_found" }`.
  programNotFound,

  /// HTTP 409 `{ "code": "operation_canceled" }`.
  operationCanceled,

  /// HTTP 409 `{ "code": "operation_incomplete" }` - a concurrent create for
  /// the same operation key is still in flight; explicitly retryable.
  operationIncomplete,

  /// HTTP 410 `{ "code": "operation_target_deleted" }`.
  operationTargetDeleted,

  /// A 404/409/410 whose `(status, code)` pair this client build does not
  /// recognise (unknown code, or a known code on the wrong status). Fails
  /// closed: the caller keeps its established hard-failure behavior.
  unknownStructured,

  /// Anything else - ordinary 4xx, 5xx, transport failure, or a non-HTTP
  /// error. The caller keeps its established hard-failure behavior.
  ordinary,
}

/// Pure, dependency-light classifier for [SessionCreateErrorKind]. Reads only
/// [ApiException.statusCode] and the structured `code` in
/// [ApiException.responseData]; never inspects the message text.
abstract final class SessionCreateError {
  /// The deployed contract: each recognised `code` mapped to the EXACT HTTP
  /// status it is returned with and the [SessionCreateErrorKind] it means.
  /// A known code on any other status is deliberately NOT matched here.
  static const Map<String, ({int status, SessionCreateErrorKind kind})>
  _recognized = {
    'program_not_found': (
      status: 404,
      kind: SessionCreateErrorKind.programNotFound,
    ),
    'operation_canceled': (
      status: 409,
      kind: SessionCreateErrorKind.operationCanceled,
    ),
    'operation_incomplete': (
      status: 409,
      kind: SessionCreateErrorKind.operationIncomplete,
    ),
    'operation_target_deleted': (
      status: 410,
      kind: SessionCreateErrorKind.operationTargetDeleted,
    ),
  };

  /// Classify a caught Session-CREATE failure. Lifecycle exceptions
  /// ([SessionStaleException] / [RequestCancelledException]) are NOT
  /// [ApiException]s and classify as [SessionCreateErrorKind.ordinary] - the
  /// sync layer handles them on a separate path and must never route them
  /// through here.
  static SessionCreateErrorKind classify(Object? error) {
    if (error is! ApiException) return SessionCreateErrorKind.ordinary;

    final status = error.statusCode;
    if (status == 429) return SessionCreateErrorKind.throttled;

    if (status == 404 || status == 409 || status == 410) {
      final code = _codeOf(error.responseData);
      final match = code == null ? null : _recognized[code];
      // Honour a known code ONLY on the exact status the contract pairs it
      // with; a mismatched or unknown pair fails closed.
      if (match != null && match.status == status) return match.kind;
      return SessionCreateErrorKind.unknownStructured;
    }

    return SessionCreateErrorKind.ordinary;
  }

  /// True when a `pending_create` row and its unsynced children must be left
  /// exactly as they are - not marked synced, not deleted, and NOT counted
  /// toward the terminal retry / cleanup threshold - because the current
  /// client cannot yet reconcile this response and the row is still
  /// legitimately retryable on the next normal sync pass.
  ///
  /// Unknown structured errors and every ordinary 4xx/5xx/transport failure
  /// return `false` so the caller keeps its established fail-closed behavior.
  ///
  /// NOTE: [throttled] is genuinely transient (a throttling window that
  /// passes). [operationIncomplete] is safe to retry - the deployed
  /// `SessionCreateService` fails closed rather than ever creating a second
  /// Session for it - but it is NOT genuinely self-healing in production:
  /// under the real, relational (Postgres/SQL Server) advisory-lock-serialized
  /// path, an operation row left "present, not canceled, not completed" is
  /// documented server-side as unreachable in normal operation (the creating
  /// transaction always commits or rolls back the operation row and the
  /// Session together), and nothing there will ever later set its
  /// `CompletedAt`/`CanceledAt` without server/manual intervention if it is
  /// ever actually observed. [programNotFound], [operationCanceled] and
  /// [operationTargetDeleted] are semantically TERMINAL on the server -
  /// re-POSTing the identical body/key can never succeed. All four
  /// (excluding [throttled]) are still treated as soft here on purpose: this
  /// PR only adds the durable `clientOperationId` these codes need to become
  /// reachable at all - it intentionally leaves this classification
  /// unchanged. A follow-up PR must introduce an explicit terminal
  /// "needs-attention" classification for the three truly-terminal codes
  /// instead of indefinite silent retry; that PR is also where
  /// `operationIncomplete`'s "safe but not self-healing" nuance should be
  /// reflected in behavior, not just in this comment.
  static bool isSoftRetryable(Object? error) {
    switch (classify(error)) {
      case SessionCreateErrorKind.throttled:
      case SessionCreateErrorKind.programNotFound:
      case SessionCreateErrorKind.operationCanceled:
      case SessionCreateErrorKind.operationIncomplete:
      case SessionCreateErrorKind.operationTargetDeleted:
        return true;
      case SessionCreateErrorKind.unknownStructured:
      case SessionCreateErrorKind.ordinary:
        return false;
    }
  }

  static String? _codeOf(Object? responseData) {
    if (responseData is Map) {
      final code = responseData['code'];
      if (code is String && code.isNotEmpty) return code;
    }
    return null;
  }
}
