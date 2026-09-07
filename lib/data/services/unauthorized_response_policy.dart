/// How [ApiService] should treat a 401 response to ONE specific request,
/// decided explicitly at dispatch time by which [ApiService] method the
/// caller used - never inferred later from whether an active session
/// happened to exist, and never decided by inspecting the request's URL.
///
/// This exists because "was there an active session when this request was
/// sent" is NOT the same question as "should a 401 for this request be
/// allowed to end that session." A public, unauthenticated endpoint (login,
/// signup, a future password-reset) can be dispatched while a completely
/// unrelated session is already active in the same app (e.g. the user opens
/// a second "switch account" login form while still signed in as someone
/// else) - its own 401 (wrong credentials for the NEW account) must never
/// be able to reach out and end the ALREADY-active, unrelated session just
/// because a live session token happened to be capturable at the moment the
/// public request was dispatched. See `ApiService.postPublic` and
/// `ApiService.handleResponseError`.
enum UnauthorizedResponsePolicy {
  /// A 401 for this request may end the CURRENT session (subject to every
  /// other ownership check in `ApiService.handleResponseError`: the
  /// dispatch-time token must be non-null, still current, and not already
  /// claimed for this generation). Used by every authenticated/protected
  /// API call - the default for the generic `get`/`post`/`put`/`patch`/
  /// `delete` methods.
  expireCurrentSession,

  /// A 401 for this request is reported to the caller as an ordinary typed
  /// failure ([ApiException]) and nothing else: no epoch invalidation, no
  /// request cancellation, no provider cleanup, no credential deletion, no
  /// navigation, no expiration message. Used exclusively by public,
  /// unauthenticated endpoints - see `ApiService.postPublic`. A request
  /// dispatched under this policy never captures or stores a session token
  /// for forced-expiration ownership in the first place (see
  /// `ApiService._requestOptions`), so even if one were somehow read back,
  /// there would be nothing there to misuse.
  reportOnly,
}
