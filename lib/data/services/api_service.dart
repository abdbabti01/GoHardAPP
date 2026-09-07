import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/user_session_epoch.dart';
import 'api_exception.dart';
import 'auth_service.dart';
import 'rate_limited_exception.dart';
import 'session_request_context.dart';
import 'session_request_exceptions.dart';
import 'unauthorized_response_policy.dart';

/// HTTP API service using Dio
/// Matches the ApiService.cs from MAUI app with automatic JWT token injection
///
/// ## Session-bound requests (PR A)
///
/// Every wrapper below (`get`/`post`/`put`/`patch`/`delete`) accepts an
/// optional [SessionRequestContext] `sessionContext` parameter. Passing one
/// binds that single request to the session that captured it:
///
/// - the request is sent with the JWT captured in [sessionContext], never
///   whatever the live secure-storage token happens to be at send time;
/// - the request carries [sessionContext]'s generation-scoped
///   [CancelToken], so a later cancellation of that generation aborts it;
/// - the epoch is rechecked twice - once synchronously in the wrapper
///   before Dio is touched at all, and again inside the request
///   interceptor immediately before actual dispatch, since a logout can
///   land in the (necessarily async) gap between those two points. Both
///   checkpoints throw the exact same [SessionStaleException].
///
/// Omitting `sessionContext` (every existing call site, unchanged by this
/// PR) preserves today's behavior exactly: the live secure-storage token is
/// read fresh by the interceptor on every request, matching the app's
/// original all-requests-share-one-token model.
///
/// This PR introduces the mechanism only - see [SessionRequestContext] and
/// `SessionRequestCoordinator`. No repository or `SyncService` call site
/// has been migrated to use it yet, and `AuthProvider`'s logout pass does
/// not yet invoke any cancellation. The planned follow-up sequence:
///
/// - PR B1/B2: migrate repository background closures to capture and pass
///   a [SessionRequestContext] completely (JWT pinning AND the
///   acknowledgment-time epoch recheck together, per closure, not split
///   across PRs).
/// - PR C: wire `SessionRequestCoordinator.cancelCurrentGeneration()` into
///   `AuthProvider`'s logout pass, immediately after
///   `UserSessionEpoch.invalidate()`, as its own best-effort guarded step.
/// - PR D: migrate `SyncService` - operation ownership (replacing
///   `_isSyncing` with a captured-token-owned in-flight record) AND the
///   five currently-unfiltered child-entity sync phases' parent-chain
///   ownership filtering land together, in the same PR/safety unit. An
///   intermediate state with SyncService migrated to session-bound HTTP but
///   still uploading unfiltered child rows would not be safe on its own.
///   Also for PR D: periodic/debounce callbacks must capture their
///   [UserSessionToken] at scheduling time, not at fire time - a callback
///   scheduled under User A must no-op if it fires after User B has logged
///   in, not silently adopt User B's token.
class ApiService {
  late final Dio _dio;
  final AuthService _authService;
  final UserSessionEpoch _sessionEpoch;

  /// Callback for handling 401 Unauthorized errors
  /// Set this to trigger proper logout flow through AuthProvider
  void Function()? onUnauthorized;

  /// The session generation a forced-expiration signal has already been
  /// claimed for, or `null` if none has been claimed for the CURRENT
  /// generation yet. Generation-scoped rather than a bare flag: a fresh
  /// login/signup/restored-session always mints a NEW generation via
  /// [UserSessionEpoch.activate], which the comparison in
  /// [handleResponseError] naturally treats as eligible again - no
  /// authentication-success call site needs to remember to reset anything
  /// (unlike the bare-bool predecessor of this field, which required every
  /// such call site to call [resetUnauthorizedFlag] and had at least one
  /// that didn't).
  int? _forcedExpirationClaimedGeneration;

  /// Key used on the per-call [Options.extra] (and therefore
  /// [RequestOptions.extra]) to mark a request as session-bound and carry
  /// the [UserSessionToken] the interceptor rechecks immediately before
  /// dispatch. Deliberately never carries the JWT itself - the pinned
  /// Authorization header already does that.
  @visibleForTesting
  static const String sessionEpochExtraKey = '_sessionEpochToken';

  /// Key used on the per-call [Options.extra] to carry the [UserSessionToken]
  /// (or `null`) that was the CURRENTLY active session at the moment THIS
  /// specific request was dispatched - captured synchronously before Dio is
  /// touched, for EVERY wrapper call below, bound or unbound alike.
  /// Deliberately separate from [sessionEpochExtraKey]: that key exists only
  /// for a request that explicitly opted into JWT-pinning/cancellation via a
  /// [SessionRequestContext]; this key exists for every request, purely so a
  /// later 401 can be checked for OWNERSHIP against the session that was
  /// active when the request was SENT - never against whichever session
  /// happens to be active when the RESPONSE arrives. See
  /// [handleResponseError].
  @visibleForTesting
  static const String dispatchEpochExtraKey = '_dispatchEpochToken';

  /// Key used on the per-call [Options.extra] to carry the
  /// [UnauthorizedResponsePolicy] this exact request was dispatched under -
  /// set explicitly by which [ApiService] method the caller used (never
  /// inferred from the URL, and never left unset). [handleResponseError]
  /// checks this FIRST, before ever looking at [dispatchEpochExtraKey]: a
  /// request dispatched under [UnauthorizedResponsePolicy.reportOnly] never
  /// even has a token captured for it in the first place (see
  /// [_requestOptions]), but this explicit, independently-checked field is
  /// the primary guard, not merely a side effect of the token being absent -
  /// see [postPublic].
  @visibleForTesting
  static const String unauthorizedPolicyExtraKey = '_unauthorizedPolicy';

  /// Test-only seam: awaited, if set, immediately before the interceptor's
  /// actual-dispatch epoch recheck for a session-bound request - after the
  /// wrapper's own pre-check has already passed. Lets a test deterministically
  /// land a logout/relogin in the gap between the two checkpoints without a
  /// real sleep. Defaults to null in production (a no-op await).
  @visibleForTesting
  Future<void> Function()? beforeDispatchEpochCheckForTesting;

  ApiService(this._authService, this._sessionEpoch) {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final epochToken =
              options.extra[sessionEpochExtraKey] as UserSessionToken?;

          if (epochToken != null) {
            // Session-bound request: this is the actual-dispatch
            // checkpoint - the wrapper already checked isCurrent() before
            // calling Dio, but logout can land in the gap between that
            // check and this interceptor running. Reject locally here too,
            // before handler.next(), so a stale request never reaches the
            // network. Never read AuthService.getToken() on this branch -
            // the Authorization header was already pinned by the wrapper
            // and must never be overwritten with a live token.
            await beforeDispatchEpochCheckForTesting?.call();
            if (!_sessionEpoch.isCurrent(epochToken)) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  error: const SessionStaleException(),
                ),
              );
              return;
            }
            return handler.next(options);
          }

          final policy =
              options.extra[unauthorizedPolicyExtraKey]
                  as UnauthorizedResponsePolicy?;
          if (policy == UnauthorizedResponsePolicy.reportOnly) {
            // A public/unauthenticated request (postPublic - login,
            // signup, ...) NEVER carries an Authorization header, even if
            // a completely unrelated session happens to be live in secure
            // storage right now. Skip AuthService.getToken() entirely -
            // reading it here would attach that OTHER session's live JWT
            // to a request that has nothing to do with it (e.g. a
            // "switch account" login attempt while already signed in),
            // needlessly exposing that credential to an endpoint that
            // never needs it and was never meant to see it.
            return handler.next(options);
          }

          // Legacy/unbound PROTECTED request - unchanged: read the live
          // token fresh on every request.
          final token = await _authService.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          handleResponseError(error);
          return handler.next(error);
        },
      ),
    );
  }

  /// Reset the forced-expiration claim (call after successful login).
  ///
  /// Kept as a public, non-test-only method since `AuthProvider.login()`
  /// already calls it on every successful login - but it is no longer
  /// load-bearing for correctness the way it was when this tracked a bare
  /// bool: a genuine new session always advances the generation via
  /// [UserSessionEpoch.activate], which already re-arms
  /// [handleResponseError]'s claim automatically (see
  /// [_forcedExpirationClaimedGeneration]) without requiring any
  /// authentication-success call site to remember to call this. Also
  /// useful for a test that wants to deliberately observe a second
  /// forced-expiration signal for what is, from the epoch's perspective,
  /// still the same session.
  void resetUnauthorizedFlag() {
    _forcedExpirationClaimedGeneration = null;
  }

  /// Test-only seam: swaps the real network transport for a deterministic
  /// fake [HttpClientAdapter], so tests can exercise the full real
  /// interceptor pipeline (this class's own `onRequest`/`onError`, not a
  /// stub of it) without ever making a network call.
  @visibleForTesting
  set testHttpClientAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
  }

  /// Handle 401 Unauthorized - notify app to trigger a forced-expiration
  /// pass, but ONLY for a 401 that actually belongs to the CURRENTLY active
  /// session AND was dispatched under
  /// [UnauthorizedResponsePolicy.expireCurrentSession]. Extracted from the
  /// interceptor so it can be unit tested without a real network round-trip.
  ///
  /// Checked in this exact order - every condition is independent and
  /// none is inferred from another:
  ///
  ///  1. [unauthorizedPolicyExtraKey] must be
  ///     [UnauthorizedResponsePolicy.expireCurrentSession]. A
  ///     [UnauthorizedResponsePolicy.reportOnly] request (see [postPublic] -
  ///     login, signup, any public/unauthenticated endpoint) is excluded
  ///     HERE, explicitly, regardless of whether a token happens to be
  ///     attached - this is deliberately not merely a side effect of step 2
  ///     below. Never decided by inspecting [error.requestOptions.path].
  ///  2. The dispatch-time [UserSessionToken] captured on
  ///     [error.requestOptions] (see [dispatchEpochExtraKey] and
  ///     [_requestOptions]) - NEVER a fresh "who is logged in right now"
  ///     read - must be non-null. A [UnauthorizedResponsePolicy.reportOnly]
  ///     request never has one captured in the first place (belt-and-
  ///     suspenders with step 1); an [UnauthorizedResponsePolicy
  ///     .expireCurrentSession] request dispatched with no authenticated
  ///     session active also has none.
  ///  3. That exact token must still be the CURRENT generation - a token
  ///     from a superseded generation (the session that sent this request
  ///     has since logged out, expired, or been replaced by a different
  ///     user by the time the RESPONSE arrived) is ignored as an ownership
  ///     signal; ownership can never be inherited by whichever session
  ///     happens to be active now.
  ///  4. That generation must not have already claimed a forced-expiration
  ///     signal (never a second one for the same generation, even under a
  ///     burst of concurrent 401s - see [_forcedExpirationClaimedGeneration]).
  ///
  /// Only once all four hold: claim the generation and invoke
  /// [onUnauthorized].
  @visibleForTesting
  void handleResponseError(DioException error) {
    if (error.response?.statusCode != 401) return;

    final policy =
        error.requestOptions.extra[unauthorizedPolicyExtraKey]
            as UnauthorizedResponsePolicy?;
    if (policy != UnauthorizedResponsePolicy.expireCurrentSession) return;

    final dispatchToken =
        error.requestOptions.extra[dispatchEpochExtraKey] as UserSessionToken?;
    if (dispatchToken == null) return;
    if (!_sessionEpoch.isCurrent(dispatchToken)) return;
    if (_forcedExpirationClaimedGeneration == dispatchToken.generation) return;

    _forcedExpirationClaimedGeneration = dispatchToken.generation;
    onUnauthorized?.call();
  }

  /// Builds the per-call [Options] for every wrapper method below - bound
  /// or unbound alike. Always returns a non-null [Options]: every request
  /// carries [unauthorizedPolicyExtraKey] (always set, never omitted) and,
  /// for an [UnauthorizedResponsePolicy.expireCurrentSession] request only,
  /// [dispatchEpochExtraKey] so a later 401 can be checked for ownership -
  /// see [handleResponseError].
  ///
  /// A [UnauthorizedResponsePolicy.reportOnly] request NEVER captures a
  /// dispatch-time token at all, regardless of whether a session happens to
  /// be active - this is the mechanism, not merely the [handleResponseError]
  /// policy check, that guarantees such a request can never carry ownership
  /// over anyone's session (see [postPublic]).
  ///
  /// For a bound call, also pins the captured JWT into the Authorization
  /// header and marks the request as session-bound via [sessionEpochExtraKey]
  /// so the interceptor knows to recheck the epoch instead of reading a live
  /// token - unchanged from before this method's ownership-tracking
  /// addition. For an unbound call, the interceptor's own onRequest hook
  /// still reads the live token fresh, exactly as it always has.
  Options _requestOptions(
    SessionRequestContext? sessionContext,
    UnauthorizedResponsePolicy policy,
  ) {
    final dispatchToken =
        policy == UnauthorizedResponsePolicy.expireCurrentSession
            ? (sessionContext?.epochToken ?? _sessionEpoch.capture())
            : null;

    if (sessionContext == null) {
      return Options(
        extra: {
          dispatchEpochExtraKey: dispatchToken,
          unauthorizedPolicyExtraKey: policy,
        },
      );
    }

    final headers = <String, dynamic>{};
    sessionContext.applyAuthorizationHeader(headers);

    return Options(
      headers: headers,
      extra: {
        sessionEpochExtraKey: sessionContext.epochToken,
        dispatchEpochExtraKey: dispatchToken,
        unauthorizedPolicyExtraKey: policy,
      },
    );
  }

  /// Throws [SessionStaleException] if [sessionContext] is non-null and its
  /// session is no longer current - the wrapper-level checkpoint, run
  /// synchronously before Dio is touched at all. The interceptor performs
  /// the second, actual-dispatch checkpoint (see the constructor) for the
  /// window between this check and the request actually being sent.
  void _checkNotStale(SessionRequestContext? sessionContext) {
    if (sessionContext != null &&
        !_sessionEpoch.isCurrent(sessionContext.epochToken)) {
      throw const SessionStaleException();
    }
  }

  /// Maps a caught [DioException] to the exception callers should see:
  /// [SessionStaleException] if the interceptor rejected it as stale,
  /// [RequestCancelledException] if its [CancelToken] was cancelled,
  /// [RateLimitedException] for any HTTP 429 - checked before the ordinary
  /// [ApiException] mapping below, so a 429 is never translated into a
  /// generic validation/server-error message - or the existing
  /// [ApiException] mapping for every other ordinary network/server
  /// failure - unchanged from before this PR.
  ///
  /// A 429 is never an authentication failure: this method never calls
  /// [handleResponseError]/`onUnauthorized` (that already only ever fires
  /// for a real 401 - see [handleResponseError]), so 429 handling here is
  /// fully independent of it and can never trigger logout.
  Object _mapError(DioException e) {
    final error = e.error;
    if (error is SessionStaleException) {
      return error;
    }
    if (e.type == DioExceptionType.cancel) {
      return RequestCancelledException(originalError: e);
    }
    if (e.response?.statusCode == 429) {
      final rateLimited = RateLimitedException.fromDioException(e);
      // Bounded, safe debug logging only: status code, sanitized code, and
      // a rounded retry duration - never the raw body, headers, or token.
      debugPrint(
        '⏳ HTTP 429 rate limited'
        '${rateLimited.code != null ? ' code=${rateLimited.code}' : ''}'
        '${rateLimited.retryAfter != null ? ' retryAfter=${rateLimited.retryAfter!.inSeconds}s' : ''}',
      );
      return rateLimited;
    }
    return ApiException.fromDioException(e);
  }

  /// Generic GET request
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    SessionRequestContext? sessionContext,
  }) async {
    _checkNotStale(sessionContext);
    try {
      final response = await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: _requestOptions(
          sessionContext,
          UnauthorizedResponsePolicy.expireCurrentSession,
        ),
        cancelToken: sessionContext?.cancelToken,
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Generic POST request
  Future<T> post<T>(
    String path, {
    dynamic data,
    SessionRequestContext? sessionContext,
  }) async {
    _checkNotStale(sessionContext);
    try {
      final response = await _dio.post<T>(
        path,
        data: data,
        options: _requestOptions(
          sessionContext,
          UnauthorizedResponsePolicy.expireCurrentSession,
        ),
        cancelToken: sessionContext?.cancelToken,
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// POST for a PUBLIC, unauthenticated endpoint - login, signup, or any
  /// future password-reset/public-auth call. The ONLY way to get
  /// [UnauthorizedResponsePolicy.reportOnly] semantics: this method's name
  /// and type are the policy, not a parameter a caller could pass
  /// incorrectly (see [UnauthorizedResponsePolicy]'s own doc comment).
  ///
  /// Deliberately has no `sessionContext` parameter - a public endpoint is
  /// never dispatched under, bound to, or pinned to an authenticated
  /// session's identity, regardless of whether one happens to be active in
  /// the app when this is called. A 401 from a request sent through this
  /// method can NEVER end anyone's session: see [handleResponseError] and
  /// [_requestOptions].
  Future<T> postPublic<T>(String path, {dynamic data}) async {
    try {
      final response = await _dio.post<T>(
        path,
        data: data,
        options: _requestOptions(null, UnauthorizedResponsePolicy.reportOnly),
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Generic PUT request
  Future<T> put<T>(
    String path, {
    dynamic data,
    SessionRequestContext? sessionContext,
  }) async {
    _checkNotStale(sessionContext);
    try {
      final response = await _dio.put<T>(
        path,
        data: data,
        options: _requestOptions(
          sessionContext,
          UnauthorizedResponsePolicy.expireCurrentSession,
        ),
        cancelToken: sessionContext?.cancelToken,
      );
      return response.data as T;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Generic PATCH request
  Future<T?> patch<T>(
    String path, {
    dynamic data,
    SessionRequestContext? sessionContext,
  }) async {
    _checkNotStale(sessionContext);
    try {
      final response = await _dio.patch<T>(
        path,
        data: data,
        options: _requestOptions(
          sessionContext,
          UnauthorizedResponsePolicy.expireCurrentSession,
        ),
        cancelToken: sessionContext?.cancelToken,
      );
      // Handle NoContent (204) responses
      if (response.statusCode == 204 || response.data == null) {
        return null;
      }
      return response.data as T;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// Generic DELETE request
  Future<bool> delete(
    String path, {
    dynamic data,
    SessionRequestContext? sessionContext,
  }) async {
    _checkNotStale(sessionContext);
    try {
      final response = await _dio.delete(
        path,
        data: data,
        options: _requestOptions(
          sessionContext,
          UnauthorizedResponsePolicy.expireCurrentSession,
        ),
        cancelToken: sessionContext?.cancelToken,
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }
}
