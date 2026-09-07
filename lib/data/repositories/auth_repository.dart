import '../../core/constants/api_config.dart';
import '../models/auth_response.dart';
import '../models/login_request.dart';
import '../models/signup_request.dart';
import '../services/api_service.dart';

/// Repository for authentication operations
///
/// Both endpoints below are PUBLIC and unauthenticated - dispatched via
/// [ApiService.postPublic], never the generic [ApiService.post]. This is
/// deliberate and load-bearing, not a style choice: a 401 from either call
/// (wrong password, a taken username) must never be able to end some OTHER,
/// already-active session in this same app instance just because one
/// happened to be capturable at dispatch time - see
/// `UnauthorizedResponsePolicy`'s doc comment and
/// `test/data/repositories/auth_repository_public_policy_test.dart`, which
/// enumerates and guards exactly these two call sites.
class AuthRepository {
  final ApiService _apiService;

  AuthRepository(this._apiService);

  /// Login user and return authentication response
  Future<AuthResponse> login(LoginRequest request) async {
    final data = await _apiService.postPublic<Map<String, dynamic>>(
      ApiConfig.authLogin,
      data: request.toJson(),
    );
    return AuthResponse.fromJson(data);
  }

  /// Register new user and return authentication response
  Future<AuthResponse> signup(SignupRequest request) async {
    final data = await _apiService.postPublic<Map<String, dynamic>>(
      ApiConfig.authSignup,
      data: request.toJson(),
    );
    return AuthResponse.fromJson(data);
  }
}
