/// Thrown by [ApiService] when a caller-provided `SessionRequestContext`'s
/// session has stopped being the current one - either because the calling
/// wrapper's own pre-dispatch check caught it, or because the request
/// interceptor caught it in the (necessarily later) window between the
/// wrapper's check and Dio actually sending the request. Both checkpoints
/// deliberately throw this exact same type - callers must not be able to
/// tell which one caught the staleness, only that the request was never
/// sent under a mismatched or logged-out session.
///
/// Carries no JWT/header/token content - see the redaction requirement on
/// `SessionRequestContext`.
class SessionStaleException implements Exception {
  const SessionStaleException();

  @override
  String toString() => 'SessionStaleException: session is no longer current';
}

/// Thrown by [ApiService] when a session-bound request's `CancelToken` was
/// cancelled - distinct from `ApiException`, which represents an ordinary
/// network/server failure. Callers must treat cancellation as "this
/// session ended," never as a retryable sync error.
///
/// [originalError] is kept only for diagnostics; nothing in this class
/// prints it, and it must never be surfaced to the user.
class RequestCancelledException implements Exception {
  const RequestCancelledException({this.originalError});

  final Object? originalError;

  @override
  String toString() => 'RequestCancelledException: request was cancelled';
}
