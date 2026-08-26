import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/services/api_exception.dart';

DioException _errorWithResponse({
  required int statusCode,
  dynamic data,
  String? statusMessage,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/sessions/1');
  return DioException(
    requestOptions: options,
    type: type,
    response: Response(
      requestOptions: options,
      statusCode: statusCode,
      statusMessage: statusMessage,
      data: data,
    ),
  );
}

void main() {
  group('ApiException.fromDioException - status/data preservation', () {
    test('preserves 409 status code and structured response data', () {
      final serverData = {'id': 5, 'version': 3};
      final e = _errorWithResponse(
        statusCode: 409,
        data: {
          'message': 'Conflict',
          'currentVersion': 3,
          'serverData': serverData,
        },
      );

      final result = ApiException.fromDioException(e);

      expect(result.statusCode, 409);
      expect(result.responseData, isA<Map>());
      expect(result.responseData['currentVersion'], 3);
      expect(result.responseData['serverData'], serverData);
      expect(result.originalError, e);
    });

    test('preserves status code and data for a generic error response', () {
      final e = _errorWithResponse(
        statusCode: 418,
        data: {'message': "I'm a teapot"},
      );

      final result = ApiException.fromDioException(e);

      expect(result.statusCode, 418);
      expect(result.responseData, {'message': "I'm a teapot"});
      expect(result.message, "Error (418): I'm a teapot");
    });
  });

  group('ApiException.fromDioException - readable messages', () {
    test('400 with message produces "Bad request: <message>"', () {
      final e = _errorWithResponse(
        statusCode: 400,
        data: {'message': 'Name is required'},
      );
      final result = ApiException.fromDioException(e);
      expect(result.message, 'Bad request: Name is required');
      expect(result.toString(), 'Exception: Bad request: Name is required');
    });

    test('400 with validation errors map formats field errors', () {
      final e = _errorWithResponse(
        statusCode: 400,
        data: {
          'errors': {
            'Name': ['Name is required'],
            'Date': ['Date is invalid'],
          },
        },
      );
      final result = ApiException.fromDioException(e);
      expect(result.message, contains('Validation errors:'));
      expect(result.message, contains('Name: Name is required'));
      expect(result.message, contains('Date: Date is invalid'));
    });

    test('401 always produces the fixed unauthorized message', () {
      final e = _errorWithResponse(statusCode: 401, data: {'message': 'nope'});
      final result = ApiException.fromDioException(e);
      expect(result.message, 'Unauthorized - please login again');
    });

    test('403 produces the fixed forbidden message', () {
      final e = _errorWithResponse(statusCode: 403, data: null);
      final result = ApiException.fromDioException(e);
      expect(result.message, "Forbidden - you don't have permission");
    });

    test('404 includes the extracted message', () {
      final e = _errorWithResponse(
        statusCode: 404,
        data: {'title': 'Session not found'},
      );
      final result = ApiException.fromDioException(e);
      expect(result.message, 'Not found: Session not found');
    });

    test('500 includes the extracted message', () {
      final e = _errorWithResponse(
        statusCode: 500,
        data: {'message': 'DB unavailable'},
      );
      final result = ApiException.fromDioException(e);
      expect(result.message, 'Server error: DB unavailable');
    });

    test('connectionTimeout produces a friendly network message', () {
      final options = RequestOptions(path: '/sessions');
      final e = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
      final result = ApiException.fromDioException(e);
      expect(
        result.message,
        'Connection timeout - please check your internet connection',
      );
      expect(result.statusCode, isNull);
    });

    test(
      'toString keeps the "Exception: " prefix used by existing UI code',
      () {
        final e = _errorWithResponse(statusCode: 404, data: {'message': 'x'});
        final result = ApiException.fromDioException(e);
        // Mirrors provider code: e.toString().replaceAll('Exception: ', '')
        final stripped = result.toString().replaceAll('Exception: ', '');
        expect(stripped, 'Not found: x');
      },
    );
  });

  group('ApiException.fromDioException - safe response-data handling', () {
    test('handles a String response body without throwing', () {
      final e = _errorWithResponse(statusCode: 500, data: 'plain text error');
      final result = ApiException.fromDioException(e);
      expect(result.message, 'Server error: plain text error');
    });

    test('handles a null response body using the status message fallback', () {
      final e = _errorWithResponse(
        statusCode: 404,
        data: null,
        statusMessage: 'Not Found',
      );
      final result = ApiException.fromDioException(e);
      expect(result.message, 'Not found: Not Found');
    });

    test('handles a null response body and no status message', () {
      final e = _errorWithResponse(statusCode: 500, data: null);
      final result = ApiException.fromDioException(e);
      expect(result.message, 'Server error: Server error');
    });

    test('handles a Map with neither message nor title present', () {
      final e = _errorWithResponse(
        statusCode: 400,
        data: {'unrelated': 'field'},
        statusMessage: 'Bad Request',
      );
      final result = ApiException.fromDioException(e);
      expect(result.message, 'Bad request: Bad Request');
    });
  });
}
