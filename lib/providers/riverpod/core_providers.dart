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
import '../../core/services/user_session_epoch.dart';

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

/// User session epoch provider. This unused/unmounted Riverpod scaffold
/// already constructs its own separate service instances rather than the
/// ones main.dart's MultiProvider wires up (see authServiceProvider above),
/// so a dedicated instance here follows the file's existing pattern.
final userSessionEpochProvider = Provider<UserSessionEpoch>((ref) {
  return UserSessionEpoch();
});

/// API service provider (depends on AuthService)
final apiServiceProvider = Provider<ApiService>((ref) {
  final authService = ref.watch(authServiceProvider);
  final sessionEpoch = ref.watch(userSessionEpochProvider);
  return ApiService(authService, sessionEpoch);
});
