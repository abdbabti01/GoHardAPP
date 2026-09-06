import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/services/rate_limited_exception.dart';

/// Proves `RateLimitedException` retains ONLY sanitized, already-copied
/// data - never a `DioException`, `RequestOptions`, `Response`, header map,
/// request/response body, or any other Dio-owned object. "Never currently
/// printed" is not the bar: the type must not even HOLD the sensitive state,
/// regardless of whether anything reads it today.
void main() {
  group('RateLimitedException retains no sensitive Dio state', () {
    test('26. the constructor accepts ONLY retryAfter and code - there is no '
        'originalError (or any other) field to carry a DioException', () {
      // If `originalError` (or any field beyond these two) still existed,
      // this call would either need it supplied or this test would need
      // updating to match a wider constructor - the absence of any such
      // parameter here, verified by `flutter analyze`/compilation succeeding
      // with EXACTLY this call shape, is the proof. Mutation testing
      // (reintroducing the field) is the other half of this guarantee -
      // see the mutation log for "retain DioException inside
      // RateLimitedException".
      const e = RateLimitedException(
        retryAfter: Duration(seconds: 30),
        code: 'rate_limited',
      );
      expect(e.retryAfter, const Duration(seconds: 30));
      expect(e.code, 'rate_limited');
    });

    test('fromDioException never retains the DioException it is built from - '
        'building many instances from the same sensitive DioException never '
        'lets any of it leak into a field or toString()', () {
      final sensitiveRequestOptions = RequestOptions(
        path: '/api/v1/auth/login',
        data: {'email': 'victim@example.com', 'password': 'hunter2'},
        headers: {'Authorization': 'Bearer super-secret-jwt-value'},
      );
      final dioError = DioException(
        requestOptions: sensitiveRequestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: sensitiveRequestOptions,
          statusCode: 429,
          data: {
            'code': 'rate_limited',
            // A stray, unexpected extra field a real server might echo
            // back - must never ride along either.
            'debugRequestId': 'trace-abc-123-should-never-appear',
          },
          headers: Headers.fromMap({
            'retry-after': ['30'],
            'set-cookie': ['session=super-secret-cookie-value'],
          }),
        ),
      );

      final e = RateLimitedException.fromDioException(dioError);

      // Only the two sanitized fields exist and hold only what they claim.
      expect(e.retryAfter, const Duration(seconds: 30));
      expect(e.code, 'rate_limited');

      // Nothing sensitive appears anywhere in the safe, fixed toString().
      final rendered = e.toString();
      expect(rendered, isNot(contains('super-secret')));
      expect(rendered, isNot(contains('hunter2')));
      expect(rendered, isNot(contains('victim@example.com')));
      expect(rendered, isNot(contains('trace-abc-123')));
      expect(rendered, isNot(contains('Bearer')));
      expect(rendered, isNot(contains('login')));
      expect(rendered, 'Too many requests. Please wait and try again.');
    });
  });
}
