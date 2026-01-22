/// Core Riverpod providers for service layer dependencies.
/// These providers replace the Provider package's service registrations.
///
/// Migration Strategy:
/// 1. Services are defined as Riverpod providers here
/// 2. Existing ChangeNotifier providers can gradually be migrated
/// 3. Both Provider and Riverpod can coexist during transition
///
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/local/services/local_database_service.dart';
import '../../data/services/api_service.dart';
import '../../data/services/auth_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/notification_service.dart';

// ============================================================
// Service Providers (Singletons)
// ============================================================

/// Local database service provider
/// Must be initialized before use via overrideWithValue in main()
final localDatabaseServiceProvider = Provider<LocalDatabaseService>((ref) {
  return LocalDatabaseService.instance;
});

/// Connectivity service provider
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService.instance;
});

/// Notification service provider
/// Must be initialized before use via overrideWithValue in main()
final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError('NotificationService must be overridden');
});

/// Secure storage provider
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// API service provider (depends on AuthService)
final apiServiceProvider = Provider<ApiService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ApiService(authService);
});
