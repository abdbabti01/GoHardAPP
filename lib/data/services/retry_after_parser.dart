import 'dart:io';

/// Pure, dependency-light parser for an HTTP `Retry-After` header value.
///
/// Used only by [RateLimitedException.fromDioException] (`ApiService`'s
/// centralized 429 detection) - never touches Dio, never reads the header
/// itself (callers pass the already-extracted string; header-name lookup is
/// case-insensitive by construction in Dio's `Headers` class, which stores
/// names in a case-insensitive map).
///
/// Per RFC 7231 §7.1.3, `Retry-After` is either an integer number of
/// delta-seconds or an HTTP-date. Both forms are accepted here. Anything
/// else - missing, empty, unparseable, negative, or an HTTP-date in the past
/// - returns `null` ("no trusted duration"), never a negative or zero-ish
/// guess. A successfully parsed value is clamped to [maxRetryAfter] so a
/// misbehaving or malicious server can never make the client back off for an
/// unbounded amount of time.
abstract final class RetryAfterParser {
  /// The longest duration this parser will ever return. Chosen well above
  /// the app's own periodic sync interval (5 minutes - see
  /// `SyncService._syncInterval`) so a legitimate long cooldown is still
  /// mostly honored, while bounding the worst case a server response could
  /// ever impose on this client.
  static const Duration maxRetryAfter = Duration(minutes: 15);

  /// Parses [headerValue] (the raw `Retry-After` header string, or `null`
  /// if the header was absent) into a trusted, clamped [Duration], or
  /// `null` if none could be trusted.
  ///
  /// [nowUtc] is a test seam for the HTTP-date branch - defaults to
  /// `DateTime.now().toUtc()` in production. Never called for the
  /// delta-seconds branch, which needs no clock at all.
  static Duration? parse(String? headerValue, {DateTime Function()? nowUtc}) {
    if (headerValue == null) return null;
    final trimmed = headerValue.trim();
    if (trimmed.isEmpty) return null;

    final seconds = int.tryParse(trimmed);
    if (seconds != null) {
      if (seconds < 0) return null;
      if (seconds > maxRetryAfter.inSeconds) return maxRetryAfter;
      return Duration(seconds: seconds);
    }

    // Not an integer - try the HTTP-date form. Deliberately bounds the
    // integer branch above BEFORE ever constructing a Duration, so an
    // absurdly large delta-seconds string can never risk a Duration
    // overflow; HttpDate.parse only ever produces a DateTime within Dart's
    // own supported range, so the date-branch's difference() below is safe
    // without a similar pre-check.
    final DateTime parsedDate;
    try {
      parsedDate = HttpDate.parse(trimmed);
    } catch (_) {
      return null;
    }

    final now = (nowUtc ?? _defaultNowUtc)();
    final delta = parsedDate.toUtc().difference(now);
    if (delta.isNegative) return null;
    return delta > maxRetryAfter ? maxRetryAfter : delta;
  }

  static DateTime _defaultNowUtc() => DateTime.now().toUtc();
}
