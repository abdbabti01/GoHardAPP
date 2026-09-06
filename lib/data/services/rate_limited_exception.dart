import 'package:dio/dio.dart';

import 'retry_after_parser.dart';

/// Thrown by [ApiService] for any HTTP `429 Too Many Requests` response,
/// regardless of which limiter tier produced it (the GlobalLimiter / the
/// auth-attempt limiter, which return an empty body and no `Retry-After`, or
/// the session-write limiter, which returns `{"code":"rate_limited"}` and a
/// `Retry-After` in seconds).
///
/// A `429` is never an authentication failure - [ApiService] detects it
/// before its ordinary [DioException]/[ApiException] mapping and before its
/// 401 handling, so this type is never confused with `UnauthorizedException`
/// (there is no such type in this app - see `handleResponseError`),
/// `SessionStaleException`, or `RequestCancelledException`, and never
/// triggers logout, token refresh, or offline/network-unavailable state.
///
/// Carries ONLY two pieces of already-sanitized, already-copied data - no
/// field on this type is, wraps, or transitively references a
/// [DioException], [RequestOptions], [Response], [Headers], request/response
/// body, or any other Dio-owned object:
///  - [retryAfter]: a trusted, clamped [Duration] value parsed from the
///    response's `Retry-After` header, or `null` if the header was absent,
///    malformed, or untrustworthy (see `RetryAfterParser`) - a plain value
///    type, never a reference into the original response;
///  - [code]: a short, allow-listed [String] (e.g. `rate_limited`) copied out
///    of the response body, or `null` if the body was empty, not a JSON
///    object, or the `code` value didn't look like a safe token.
///
/// Deliberately has NO `originalError` field, unlike this app's sibling
/// exception `RequestCancelledException` - keeping a reference to the
/// triggering
/// [DioException] here would risk retaining its [RequestOptions] (which can
/// carry the `Authorization` header/JWT, a login request's email/password
/// body, or any other mutation payload), its [Response] (which can carry a
/// raw, unsanitized response body), or its resolved URL/query values -
/// exactly the sensitive state a "typed, sanitized" exception must not hold,
/// regardless of whether anything currently reads or prints that field.
/// [ApiService._mapError] extracts [retryAfter]/[code] from the
/// [DioException] and then lets it go - nothing here keeps it alive.
///
/// [toString] is a fixed, generic, user-safe message so this type is always
/// safe to surface directly (via the existing
/// `e.toString().replaceAll('Exception: ', '')` pattern every provider in
/// this app already uses for its error messages) without any caller needing
/// to special-case it.
class RateLimitedException implements Exception {
  const RateLimitedException({this.retryAfter, this.code});

  /// Builds a [RateLimitedException] from a `429` [DioException] - the
  /// single place this app turns a raw response into this type. Called by
  /// `ApiService._mapError` before its ordinary [ApiException] mapping. Only
  /// ever reads from [error] here - never stores [error] itself, nor
  /// anything owned by it (`requestOptions`, `response`, headers, body).
  ///
  /// Reads the `Retry-After` header via Dio's own case-insensitive
  /// [Headers.value] lookup (never a manual case-insensitive search - Dio's
  /// `Headers` already stores names in a case-insensitive map) and parses it
  /// with [RetryAfterParser]. Recognizes `{"code": "..."}` without
  /// requiring a body at all - the GlobalLimiter's/auth-attempt limiter's
  /// bare 429 with an empty body is exactly as valid as the session-write
  /// limiter's structured one; both produce this same type.
  factory RateLimitedException.fromDioException(DioException error) {
    final response = error.response;
    return RateLimitedException(
      retryAfter: RetryAfterParser.parse(
        response?.headers.value('retry-after'),
      ),
      code: _sanitizedCode(response?.data),
    );
  }

  /// Extracts a short, allow-listed `code` from a response body - never the
  /// raw body itself. Rejects anything that isn't a short
  /// lowercase-letters/digits/underscore token, so a stray oversized or
  /// unexpected value from the server can never ride along into [code] (and
  /// from there into a debug log line).
  static String? _sanitizedCode(dynamic responseData) {
    if (responseData is! Map) return null;
    final code = responseData['code'];
    if (code is! String || code.isEmpty || code.length > 40) return null;
    return RegExp(r'^[a-z0-9_]+$').hasMatch(code) ? code : null;
  }

  /// A trusted, already-clamped duration to wait before the next attempt,
  /// or `null` if the server gave none / gave one that could not be
  /// trusted. See `RetryAfterParser.maxRetryAfter` for the clamp ceiling.
  final Duration? retryAfter;

  /// A short, sanitized server error code (e.g. `rate_limited`), or `null`.
  /// Never the raw response body.
  final String? code;

  /// Fixed, generic, user-safe text - deliberately never includes
  /// [retryAfter] or [code] verbatim, so nothing here can ever leak a raw
  /// header/body value into UI text.
  @override
  String toString() => 'Too many requests. Please wait and try again.';
}
