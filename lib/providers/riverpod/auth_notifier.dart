/// Auth state management using Riverpod.
/// Replaces AuthProvider ChangeNotifier with a more scalable pattern.
///
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/login_request.dart';
import '../../data/models/signup_request.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/local/services/local_database_service.dart';
import 'repository_providers.dart';
import 'core_providers.dart';

// ============================================================
// Auth State
// ============================================================

/// Immutable state class for authentication
class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? errorMessage;
  final int? userId;
  final String? userName;
  final String? userEmail;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.errorMessage,
    this.userId,
    this.userName,
    this.userEmail,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? errorMessage,
    int? userId,
    String? userName,
    String? userEmail,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      errorMessage: errorMessage,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
    );
  }
}

// ============================================================
// Auth Notifier
// ============================================================

/// StateNotifier for auth state management
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  final AuthService _authService;
  final LocalDatabaseService _localDb;

  AuthNotifier(this._authRepository, this._authService, this._localDb)
    : super(const AuthState());

  /// Check if user is already authenticated
  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);

    try {
      final isAuthenticated = await _authService.isAuthenticated();
      if (isAuthenticated) {
        final userId = await _authService.getUserId();
        final userName = await _authService.getUserName();
        final userEmail = await _authService.getUserEmail();

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          userId: userId,
          userName: userName,
          userEmail: userEmail,
        );
      } else {
        state = state.copyWith(isLoading: false, isAuthenticated: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Login with email and password
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final request = LoginRequest(email: email, password: password);
      final response = await _authRepository.login(request);

      // Store credentials
      await _authService.saveToken(
        token: response.token,
        userId: response.userId,
        name: response.name,
        email: response.email,
      );

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        userId: response.userId,
        userName: response.name,
        userEmail: response.email,
      );

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Signup with name, email, and password
  Future<bool> signup(String name, String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final request = SignupRequest(
        name: name,
        email: email,
        password: password,
      );
      final response = await _authRepository.signup(request);

      // Store credentials
      await _authService.saveToken(
        token: response.token,
        userId: response.userId,
        name: response.name,
        email: response.email,
      );

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        userId: response.userId,
        userName: response.name,
        userEmail: response.email,
      );

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Logout and clear all data
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);

    try {
      // Clear auth credentials
      await _authService.clearToken();

      // Clear local database
      await _localDb.database.writeTxn(() async {
        await _localDb.database.clear();
      });

      state = const AuthState();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

// ============================================================
// Provider Definition
// ============================================================

/// Auth state notifier provider
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((
  ref,
) {
  final authRepository = ref.watch(authRepositoryProvider);
  final authService = ref.watch(authServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  return AuthNotifier(authRepository, authService, localDb);
});

/// Convenience provider for checking if authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authNotifierProvider).isAuthenticated;
});

/// Convenience provider for current user ID
final currentUserIdProvider = Provider<int?>((ref) {
  return ref.watch(authNotifierProvider).userId;
});
