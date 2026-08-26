import 'package:dio/dio.dart';

/// Exception thrown by [ApiService] for HTTP failures.
///
/// Unlike a plain [Exception], this preserves the server's status code and
/// raw response body alongside a human-readable message, so callers that
/// need structured details (e.g. a 409 conflict's `serverData`) don't have
/// to re-parse a stringified error.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic responseData;
  final Object? originalError;

  ApiException(
    this.message, {
    this.statusCode,
    this.responseData,
    this.originalError,
  });

  /// Build an [ApiException] from a Dio failure, preserving the existing
  /// user-facing message text so provider/UI code that strips the
  /// `Exception: ` prefix keeps working unchanged.
  factory ApiException.fromDioException(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout) {
      return ApiException(
        'Connection timeout - please check your internet connection',
        originalError: error,
      );
    }
    if (error.type == DioExceptionType.receiveTimeout) {
      return ApiException(
        'Request timeout - server took too long to respond',
        originalError: error,
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return ApiException(
        'Network error - cannot connect to server',
        originalError: error,
      );
    }

    final response = error.response;
    if (response == null) {
      return ApiException(
        'Network error: ${error.message}',
        originalError: error,
      );
    }

    final statusCode = response.statusCode;
    final data = response.data;

    // Extract validation errors for 400 Bad Request
    if (statusCode == 400 && data is Map) {
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final errorMessages = <String>[];
        errors.forEach((key, value) {
          if (value is List && value.isNotEmpty) {
            errorMessages.add('$key: ${value.first}');
          }
        });
        if (errorMessages.isNotEmpty) {
          return ApiException(
            'Validation errors:\n${errorMessages.join('\n')}',
            statusCode: statusCode,
            responseData: data,
            originalError: error,
          );
        }
      }
    }

    final message = _extractMessage(data, response.statusMessage);

    final String finalMessage;
    switch (statusCode) {
      case 400:
        finalMessage = 'Bad request: $message';
        break;
      case 401:
        finalMessage = 'Unauthorized - please login again';
        break;
      case 403:
        finalMessage = 'Forbidden - you don\'t have permission';
        break;
      case 404:
        finalMessage = 'Not found: $message';
        break;
      case 500:
        finalMessage = 'Server error: $message';
        break;
      default:
        finalMessage = 'Error ($statusCode): $message';
    }

    return ApiException(
      finalMessage,
      statusCode: statusCode,
      responseData: data,
      originalError: error,
    );
  }

  /// Safely pull a readable message out of a response body that may be a
  /// Map, a plain string, or null/something unexpected.
  static String _extractMessage(dynamic data, String? statusMessage) {
    if (data is Map) {
      final value = data['message'] ?? data['title'];
      if (value != null) return value.toString();
    } else if (data is String && data.isNotEmpty) {
      return data;
    }
    return statusMessage ?? 'Server error';
  }

  /// Matches the format of Dart's built-in `Exception('...')`, so existing
  /// call sites that do `e.toString().replaceAll('Exception: ', '')` keep
  /// producing the same readable text.
  @override
  String toString() => 'Exception: $message';
}
