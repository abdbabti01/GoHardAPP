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
/// Today's client sends no `clientOperationId`, so the `409`/`410`
/// operation-state responses are effectively unreachable - they are
/// recognised here only so that if one is ever received (misconfigured proxy,
/// partial rollout) it fails safe instead of destroying unsynced data.
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
  /// NOTE: [throttled] and [operationIncomplete] are genuinely transient.
  /// [programNotFound], [operationCanceled] and [operationTargetDeleted] are
  /// semantically TERMINAL on the server - re-POSTing the identical body can
  /// never succeed. They are still treated as soft here on purpose: this PR
  /// must not delete unsynced local data on their account, and today they are
  /// unreachable (the client sends no `clientOperationId`, and
  /// `SyncService._syncCreateSession` strips `programId`/`programWorkoutId`
  /// from the body, so the server always takes the legacy 201 path). The
  /// follow-up durable-operation-key / tombstone PR MUST revisit this split
  /// and route the terminal codes to an explicit needs-attention / conflict
  /// state instead of indefinite silent retry.
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
