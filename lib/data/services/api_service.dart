import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import 'api_exception.dart';
import 'auth_service.dart';

/// HTTP API service using Dio
/// Matches the ApiService.cs from MAUI app with automatic JWT token injection
class ApiService {
  late final Dio _dio;
  final AuthService _authService;

  /// Callback for handling 401 Unauthorized errors
  /// Set this to trigger proper logout flow through AuthProvider
  void Function()? onUnauthorized;

  /// Track if we've already triggered unauthorized to prevent multiple calls
  bool _unauthorizedTriggered = false;

  ApiService(this._authService) {
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

    // Add interceptor for automatic JWT token injection
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Inject Bearer token for all requests
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

  /// Generic GET request
  Future<T> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await _dio.get<T>(
        path,
        queryParameters: queryParameters,
      );
      return response.data as T;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Generic POST request
  Future<T> post<T>(String path, {dynamic data}) async {
    try {
      final response = await _dio.post<T>(path, data: data);
      return response.data as T;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Generic PUT request
  Future<T> put<T>(String path, {dynamic data}) async {
    try {
      final response = await _dio.put<T>(path, data: data);
      return response.data as T;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Generic PATCH request
  Future<T?> patch<T>(String path, {dynamic data}) async {
    try {
      final response = await _dio.patch<T>(path, data: data);
      // Handle NoContent (204) responses
      if (response.statusCode == 204 || response.data == null) {
        return null;
      }
      return response.data as T;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Generic DELETE request
  Future<bool> delete(String path, {dynamic data}) async {
    try {
      final response = await _dio.delete(path, data: data);
      return response.statusCode == 200 || response.statusCode == 204;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
