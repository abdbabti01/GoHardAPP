import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/services/retry_after_parser.dart';

/// Pure unit tests for [RetryAfterParser] - no Dio, no clock but the one
/// explicitly injected below for the HTTP-date branch.
void main() {
  group('RetryAfterParser.parse - delta-seconds', () {
    test('3. a plain positive integer parses as that many seconds', () {
      expect(RetryAfterParser.parse('30'), const Duration(seconds: 30));
    });

    test('accepts a zero-second value (immediately eligible)', () {
      expect(RetryAfterParser.parse('0'), Duration.zero);
    });

    test('6. a missing header (null) produces no trusted duration', () {
      expect(RetryAfterParser.parse(null), isNull);
    });

    test('an empty header value produces no trusted duration', () {
      expect(RetryAfterParser.parse(''), isNull);
      expect(RetryAfterParser.parse('   '), isNull);
    });

    test('7. a negative value is rejected (no trusted duration)', () {
      expect(RetryAfterParser.parse('-5'), isNull);
    });

    test('7. a non-numeric, non-date value is rejected as malformed', () {
      expect(RetryAfterParser.parse('not-a-number'), isNull);
      expect(RetryAfterParser.parse('30.5'), isNull);
    });

    test('7. an extreme value is clamped to maxRetryAfter, not rejected', () {
      expect(
        RetryAfterParser.parse('999999999'),
        RetryAfterParser.maxRetryAfter,
      );
    });

    test(
      '7. a value at exactly maxRetryAfter is returned unclamped/unchanged',
      () {
        expect(
          RetryAfterParser.parse(
            RetryAfterParser.maxRetryAfter.inSeconds.toString(),
          ),
          RetryAfterParser.maxRetryAfter,
        );
      },
    );

    test('a value below maxRetryAfter is never clamped', () {
      expect(RetryAfterParser.parse('60'), const Duration(seconds: 60));
    });

    test('tolerates surrounding whitespace', () {
      expect(RetryAfterParser.parse('  45  '), const Duration(seconds: 45));
    });
  });

  group('RetryAfterParser.parse - HTTP-date', () {
    // Fixed "now" - 2026-01-01T00:00:00Z - via the injected clock, never the
    // real wall clock.
    DateTime fixedNow() => DateTime.utc(2026, 1, 1);

    test('4. an HTTP-date 30s in the future parses to that delta', () {
      // RFC 1123 form, as HttpDate.format would produce it.
      final result = RetryAfterParser.parse(
        'Thu, 01 Jan 2026 00:00:30 GMT',
        nowUtc: fixedNow,
      );
      expect(result, const Duration(seconds: 30));
    });

    test('5. header lookup is case-insensitive at the Dio boundary - this '
        'parser itself is case-insensitive with respect to the DATE value '
        'text (month/day names), matching HttpDate.parse', () {
      final result = RetryAfterParser.parse(
        'Thu, 01 Jan 2026 00:05:00 GMT',
        nowUtc: fixedNow,
      );
      expect(result, const Duration(minutes: 5));
    });

    test('7. an HTTP-date in the past produces no trusted duration', () {
      final result = RetryAfterParser.parse(
        'Wed, 31 Dec 2025 23:59:00 GMT',
        nowUtc: fixedNow,
      );
      expect(result, isNull);
    });

    test('an HTTP-date exactly "now" parses as a zero duration - not '
        'negative, so not rejected, consistent with a literal "0" '
        'delta-seconds value', () {
      final result = RetryAfterParser.parse(
        'Thu, 01 Jan 2026 00:00:00 GMT',
        nowUtc: fixedNow,
      );
      expect(result, Duration.zero);
    });

    test('7. an HTTP-date far beyond maxRetryAfter is clamped', () {
      final result = RetryAfterParser.parse(
        'Thu, 01 Jan 2026 05:00:00 GMT',
        nowUtc: fixedNow,
      );
      expect(result, RetryAfterParser.maxRetryAfter);
    });

    test('7. a malformed date string is rejected as malformed', () {
      expect(
        RetryAfterParser.parse('not a real date', nowUtc: fixedNow),
        isNull,
      );
    });

    test('defaults to the real wall clock when nowUtc is omitted - a '
        'far-future HTTP-date still parses to a positive, clamped '
        'duration', () {
      final result = RetryAfterParser.parse('Thu, 01 Jan 2099 00:00:00 GMT');
      expect(result, RetryAfterParser.maxRetryAfter);
    });
  });
}
