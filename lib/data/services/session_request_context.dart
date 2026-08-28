import 'package:dio/dio.dart';

import '../../core/services/user_session_epoch.dart';

/// An immutable bundle of everything a single outgoing [ApiService] request
/// needs to stay bound to the authenticated session that initiated it.
///
/// Captured exactly once via
/// `SessionRequestCoordinator.captureContext()` and never mutated or
/// re-derived afterward - the JWT it carries is the one read from secure
/// storage at capture time, not whatever secure storage holds later. This
/// app has no refresh-token concept (see `AuthService`'s own doc comment),
/// so a single capture is valid for this context's entire lifetime.
///
/// Deliberately does not duplicate [UserSessionToken.userId] as a separate
/// field - [epochToken] is already the single source of truth for both
/// generation and userId, exactly as [UserSessionToken]'s own doc comment
/// argues against redundant duplication.
final class SessionRequestContext {
  const SessionRequestContext({
    required this.epochToken,
    required String jwt,
    required this.cancelToken,
  }) : _jwt = jwt;

  /// The session identity (generation + userId) this context was captured
  /// for. [ApiService] rechecks [UserSessionEpoch.isCurrent] against this
  /// both in the wrapper (before calling Dio at all) and again inside the
  /// request interceptor (immediately before actual dispatch) - a single
  /// check at either checkpoint alone is not sufficient, since a logout can
  /// land in the gap between them.
  final UserSessionToken epochToken;

  /// The JWT captured at the moment this context was created. Private -
  /// never exposed via a public getter, so nothing outside
  /// [applyAuthorizationHeader] can read, log, or print it.
  final String _jwt;

  /// The current generation's shared Dio [CancelToken], owned and rotated
  /// by `SessionRequestCoordinator` - not by this context. Cancelling it
  /// cancels every in-flight request captured under the same generation,
  /// and only that generation; a later generation always gets a distinct
  /// [CancelToken] instance.
  final CancelToken cancelToken;

  /// Writes the pinned bearer token into [headers]. The only sanctioned way
  /// to read the captured JWT - callers must never otherwise access it.
  void applyAuthorizationHeader(Map<String, dynamic> headers) {
    headers['Authorization'] = 'Bearer $_jwt';
  }

  /// Deliberately excludes the JWT from every debug/log surface.
  @override
  String toString() => 'SessionRequestContext(epochToken: $epochToken)';
}
