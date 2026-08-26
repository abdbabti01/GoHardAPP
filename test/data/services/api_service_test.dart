import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

DioException _unauthorizedError() {
  final options = RequestOptions(path: '/sessions/1');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: 401,
      data: {'message': 'Unauthorized'},
    ),
  );
}

void main() {
  group('ApiService - 401 callback behavior', () {
    late ApiService apiService;

    setUp(() {
      apiService = ApiService(AuthService());
    });

    test('invokes onUnauthorized exactly once for repeated 401s', () {
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      apiService.handleResponseError(_unauthorizedError());
      apiService.handleResponseError(_unauthorizedError());
      apiService.handleResponseError(_unauthorizedError());

      expect(callCount, 1);
    });

    test('does not invoke onUnauthorized for non-401 errors', () {
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      final options = RequestOptions(path: '/sessions/1');
      apiService.handleResponseError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: 500),
        ),
      );

      expect(callCount, 0);
    });

    test('resetUnauthorizedFlag allows the callback to fire again', () {
      var callCount = 0;
      apiService.onUnauthorized = () => callCount++;

      apiService.handleResponseError(_unauthorizedError());
      expect(callCount, 1);

      apiService.resetUnauthorizedFlag();
      apiService.handleResponseError(_unauthorizedError());
      expect(callCount, 2);
    });
  });
}
