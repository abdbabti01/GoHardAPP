import 'api_exception.dart';
import 'rate_limited_exception.dart';

/// Internal, typed classification of a failure observed while creating a
/// Session on the server (`POST /api/v1/sessions`).
///
/// The sync layer uses this to decide retry / terminal-cleanup behavior
/// WITHOUT string-matching a human-readable error message, and it gives the
/// later durable-operation-key work a stable value to branch on instead of
/// re-parsing response bodies.
///
/// The deployed GoHardAPI contract for this endpoint (and its
/// `from-program-workout` sibling, which shares the SAME
/// `(userId, clientOperationId)` idempotency contract) is:
///
/// * `201` - legacy create accepted (`SessionResponseDto`)
/// * `200` - keyed replay of an already-committed create (`SessionResponseDto`)
/// * `404 { "code": "program_not_found" }`
/// * `409 { "code": "operation_canceled" }`
/// * `409 { "code": "operation_incomplete" }`
/// * `410 { "code": "operation_target_deleted" }`
/// * `400 { "code": "program_workout_data_invalid" }` -
///   `from-program-workout` ONLY: the source `ProgramWorkout.ExercisesJson`
///   was unparseable. No tombstone - a later retry succeeds if the
///   underlying data is fixed, but blindly retrying the SAME unparseable
///   data will not, so this is classified [SessionCreateErrorKind
///   .programWorkoutDataInvalid] and treated as a hard (non-soft-retryable)
///   failure like [unknownStructured] - never a terminal-conversion target,
///   never a reason to rotate the operation key.
/// * `429` - throttling, from either the session-write limiter OR the
///   deployed API's GlobalLimiter (which can return 429 from ANY endpoint).
///   Arrives as a [RateLimitedException] (`ApiService` detects 429
///   centrally, before its ordinary [ApiException] mapping - see
///   `ApiService._mapError`), not as an [ApiException] with `statusCode ==
///   429` - [classify] recognizes both forms (see below) so a directly
///   constructed [ApiException] (e.g. in a test, or any future caller that
///   builds one without going through `ApiService`) still classifies
///   correctly. `isSoftRetryable` still governs only the per-row retry-count
///   diagnostic for THIS Session row; `SyncService`'s own
///   `on RateLimitedException` clause (in `_syncSessions`) separately
///   rethrows the same exception past this classification to abort the
///   entire remaining sync pass - the two concerns are independent, and
///   this classifier knows nothing about the pass-level behavior.
///
/// A recognised `code` is honoured ONLY on the exact HTTP status the contract
/// pairs it with above. On 404/409/410, the same known code on any OTHER of
/// those three statuses - or an unknown code - classifies as
/// [SessionCreateErrorKind.unknownStructured]. 400 is handled separately: only
/// `program_workout_data_invalid` is recognized there; every other 400 (no
/// code, an unknown code, or a code this classifier recognizes on a
/// DIFFERENT status) classifies as [SessionCreateErrorKind.ordinary] -
/// preserving exactly how an arbitrary 400 classified before
/// `program_workout_data_invalid` existed. Both `ordinary` and
/// `unknownStructured` keep the same established hard / fail-closed
/// `isSoftRetryable` behavior regardless. Both keyed CREATE paths
/// (`SessionRepository`/`SyncService`, for the
/// generic endpoint AND `from-program-workout`) now send a durable
/// `clientOperationId` on every dispatch they can (see
/// `LocalSession.clientOperationId`), so the `404`/`409`/`410` operation-state
/// responses ARE reachable in production for both - they are no longer a
/// misconfigured-proxy-only edge case.
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

  /// HTTP 400 `{ "code": "program_workout_data_invalid" }` -
  /// `from-program-workout` ONLY. See the class doc comment.
  programWorkoutDataInvalid,

  /// A 400/404/409/410 whose `(status, code)` pair this client build does not
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
    'program_workout_data_invalid': (
      status: 400,
      kind: SessionCreateErrorKind.programWorkoutDataInvalid,
    ),
  };

  /// Classify a caught Session-CREATE failure. Lifecycle exceptions
  /// ([SessionStaleException] / [RequestCancelledException]) are NOT
  /// [ApiException]s or [RateLimitedException]s and classify as
  /// [SessionCreateErrorKind.ordinary] - the sync layer handles them on a
  /// separate path and must never route them through here.
  static SessionCreateErrorKind classify(Object? error) {
    // The real, production shape of a 429 - checked first so it never falls
    // through to the `is! ApiException` early-return below.
    if (error is RateLimitedException) return SessionCreateErrorKind.throttled;

    if (error is! ApiException) return SessionCreateErrorKind.ordinary;

    final status = error.statusCode;
    // Kept for defense-in-depth / any ApiException constructed directly
    // with statusCode 429 (e.g. existing tests) - ApiService itself never
    // produces one anymore; see the class doc comment above.
    if (status == 429) return SessionCreateErrorKind.throttled;

    if (status == 400) {
      // `program_workout_data_invalid` is the ONLY recognized code on 400 -
      // added for `from-program-workout`, which never previously reached
      // this branch. Every OTHER 400 (unknown code, no code, or a code this
      // classifier recognizes only on a DIFFERENT status, e.g. a stray
      // `operation_canceled` on 400) keeps its pre-existing `ordinary`
      // classification - never reclassified to `unknownStructured` - so the
      // generic CREATE path's established behavior for an arbitrary 400 is
      // unchanged by this addition.
      final code = _codeOf(error.responseData);
      if (code == 'program_workout_data_invalid') {
        return SessionCreateErrorKind.programWorkoutDataInvalid;
      }
      return SessionCreateErrorKind.ordinary;
    }

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
      case SessionCreateErrorKind.programWorkoutDataInvalid:
      // Blindly retrying the SAME unparseable ProgramWorkout data will not
      // self-heal - hard failure, like unknownStructured/ordinary. See
      // the class doc comment.
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
