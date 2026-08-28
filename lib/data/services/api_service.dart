import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/user_session_epoch.dart';
import 'api_exception.dart';
import 'auth_service.dart';
import 'session_request_context.dart';
import 'session_request_exceptions.dart';

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

  /// Track if we've already triggered unauthorized to prevent multiple calls
  bool _unauthorizedTriggered = false;

  /// Key used on the per-call [Options.extra] (and therefore
  /// [RequestOptions.extra]) to mark a request as session-bound and carry
  /// the [UserSessionToken] the interceptor rechecks immediately before
  /// dispatch. Deliberately never carries the JWT itself - the pinned
  /// Authorization header already does that.
  @visibleForTesting
  static const String sessionEpochExtraKey = '_sessionEpochToken';

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

          // Legacy/unbound request - unchanged: read the live token fresh
          // on every request.
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

  /// Reset the unauthorized flag (call after successful login)
  void resetUnauthorizedFlag() {
    _unauthorizedTriggered = false;
  }

  /// Test-only seam: swaps the real network transport for a deterministic
  /// fake [HttpClientAdapter], so tests can exercise the full real
  /// interceptor pipeline (this class's own `onRequest`/`onError`, not a
  /// stub of it) without ever making a network call.
  @visibleForTesting
  set testHttpClientAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
  }

  /// Handle 401 Unauthorized - notify app to trigger proper logout.
  /// Extracted from the interceptor so it can be unit tested without a real
  /// network round-trip.
  @visibleForTesting
  void handleResponseError(DioException error) {
    if (error.response?.statusCode == 401 && !_unauthorizedTriggered) {
      _unauthorizedTriggered = true;
      onUnauthorized?.call();
    }
  }

  /// Builds the per-call [Options] for [sessionContext], pinning the
  /// captured JWT into the Authorization header and marking the request as
  /// session-bound via [sessionEpochExtraKey] so the interceptor knows to
  /// recheck the epoch instead of reading a live token. Returns `null` for
  /// an unbound call, which is behaviorally identical to omitting `options`
  /// entirely on the underlying Dio call.
  Options? _boundOptions(SessionRequestContext? sessionContext) {
    if (sessionContext == null) return null;

    final headers = <String, dynamic>{};
    sessionContext.applyAuthorizationHeader(headers);

    return Options(
      headers: headers,
      extra: {sessionEpochExtraKey: sessionContext.epochToken},
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
  /// [RequestCancelledException] if its [CancelToken] was cancelled, or the
  /// existing [ApiException] mapping for every ordinary network/server
  /// failure - unchanged from before this PR.
  Object _mapError(DioException e) {
    final error = e.error;
    if (error is SessionStaleException) {
      return error;
    }
    if (e.type == DioExceptionType.cancel) {
      return RequestCancelledException(originalError: e);
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
        options: _boundOptions(sessionContext),
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
        options: _boundOptions(sessionContext),
        cancelToken: sessionContext?.cancelToken,
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
        options: _boundOptions(sessionContext),
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
        options: _boundOptions(sessionContext),
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
        options: _boundOptions(sessionContext),
        cancelToken: sessionContext?.cancelToken,
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }
}
