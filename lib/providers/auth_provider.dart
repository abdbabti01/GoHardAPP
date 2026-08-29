import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/login_request.dart';
import '../data/models/signup_request.dart';
import '../data/repositories/auth_repository.dart';
import '../data/services/auth_service.dart';
import '../data/services/api_service.dart';
import '../data/local/services/local_database_service.dart';
import '../core/services/background_service.dart';
import '../core/services/push_notification_service.dart';
import '../core/services/session_request_coordinator.dart';
import '../core/services/user_session_epoch.dart';

/// Provider for authentication state management
/// Combines LoginViewModel and SignupViewModel from MAUI app
class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository;
  final AuthService _authService;
  final ApiService _apiService;
  final LocalDatabaseService _localDb;

  /// The app's single shared session-identity service. AuthProvider is the
  /// sole owner of both activate() (on every authentication-success path
  /// below) and invalidate() (at the start of every logout pass) - no
  /// other class calls either method, so there is exactly one place that
  /// can ever advance the generation, and no risk of a double-increment
  /// from, say, SessionCleanupCoordinator also invalidating independently.
  /// This is not a circular dependency: UserSessionEpoch depends on
  /// nothing, so injecting it here (and into every Provider that needs to
  /// capture/check it) never creates a cycle.
  final UserSessionEpoch _sessionEpoch;

  /// The app's single shared session-bound HTTP request coordinator (see
  /// its own class-level doc comment). AuthProvider is the only class that
  /// calls [SessionRequestCoordinator.cancelCurrentGeneration] - it does so
  /// immediately after [UserSessionEpoch.invalidate] in every logout pass,
  /// so any request still bound to the session being ended is cancelled
  /// rather than left to complete against a now-stale session.
  final SessionRequestCoordinator _sessionRequestCoordinator;

  // Login fields
  String _email = '';
  String _password = '';

  // Signup fields
  String _signupName = '';
  String _signupUsername = '';
  String _signupEmail = '';
  String _signupPassword = '';
  String _signupConfirmPassword = '';

  // UI state
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isInitializing = true; // Track if initial auth check is in progress

  // Authentication state
  bool _isAuthenticated = false;
  int? _currentUserId;
  String? _currentUserName;
  String? _currentUserEmail;

  /// Awaited at the very start of every logout pass (manual or forced),
  /// before credentials/Isar are touched - the single seam through which
  /// active-resource teardown (GPS, timers, polling, Isar watchers) and
  /// settled-state clearing happens for every logout trigger. Set once from
  /// main.dart after the full Provider graph exists (mirroring the
  /// `_apiService.onUnauthorized` wiring below), so this class never needs
  /// to depend on the 15+ feature Providers a SessionCleanupCoordinator
  /// clears - avoiding a circular dependency in either direction.
  Future<void> Function()? onSessionEnding;

  /// Invoked exactly once per completed logout pass, after credentials and
  /// Isar are cleared and this provider's own state has settled - the
  /// single centralized navigation trigger for every logout path (manual
  /// button, 401/session-expiry). Set from app.dart via a global
  /// `NavigatorState` key, so this file never needs a `BuildContext`.
  void Function()? onLoggedOut;

  // Guards logout()/_forceLogout() so concurrent or repeated calls from
  // either trigger collapse into a single cleanup+navigation pass instead
  // of running it twice (e.g. a 401 arriving while a manual logout is
  // already in flight). Every caller after the first awaits this same
  // Future rather than starting a second pass; it is cleared once the pass
  // completes (success or failure) so a later authenticated session's own
  // eventual logout starts a fresh one.
  Future<void>? _logoutInFlight;

  /// True while a logout pass (cleanup + credential/Isar clearing) is in
  /// progress. Exposed for tests/diagnostics.
  bool get isLoggingOut => _logoutInFlight != null;

  AuthProvider(
    this._authRepository,
    this._authService,
    this._apiService,
    this._localDb,
    this._sessionEpoch,
    this._sessionRequestCoordinator,
  ) {
    // Set up callback for 401 unauthorized errors
    _apiService.onUnauthorized = _handleSessionExpired;
    _checkAuthStatus();
  }

  /// Handle session expired (401 from API)
  /// Called when any API request returns 401 Unauthorized
  void _handleSessionExpired() {
    if (!_isAuthenticated) return; // Already logged out

    debugPrint('⚠️ Session expired - logging out user');
    // Trigger logout without showing loading state. _forceLogout()'s own
    // security boundary (_performLogout) is already non-throwing by
    // construction - every step inside it, including the navigation
    // callback, is individually guarded - but this outer catch remains a
    // deliberate last-resort backstop: nothing here is watching this
    // unawaited Future, so if some future change ever let an exception
    // past that inner boundary, it must still never surface as an
    // unhandled asynchronous error.
    unawaited(
      _forceLogout().catchError((Object e, StackTrace stackTrace) {
        debugPrint('⚠️ Forced logout encountered an unexpected error: $e');
      }),
    );
  }

  /// Force logout due to session expiry (silent, no FCM unregister attempt)
  Future<void> _forceLogout() {
    return _runLogout(
      unregisterFcm: false,
      resetSignupFields: false,
      resultErrorMessage: 'Session expired - please login again',
    );
  }

  /// Runs one logout pass, or - if one is already in flight from a
  /// concurrent caller (either trigger) - awaits that same pass instead of
  /// starting a second one. This is what makes concurrent
  /// manual-logout-plus-401 and repeated logout calls collapse into exactly
  /// one cleanup, one credential/Isar clear, and one navigation.
  Future<void> _runLogout({
    required bool unregisterFcm,
    required bool resetSignupFields,
    required String resultErrorMessage,
  }) {
    final inFlight = _logoutInFlight;
    if (inFlight != null) return inFlight;

    final future = _performLogout(
      unregisterFcm: unregisterFcm,
      resetSignupFields: resetSignupFields,
      resultErrorMessage: resultErrorMessage,
    );
    _logoutInFlight = future;
    return future.whenComplete(() {
      _logoutInFlight = null;
    });
  }

  /// Runs every security-critical logout step as an independent,
  /// best-effort attempt: session cleanup, credential removal, background
  /// auth-task cleanup, Isar clearing, and the navigation callback are each
  /// wrapped in their own try/catch (a flat sequence, not nested), so a
  /// failure in any one of them is logged and never prevents the next step
  /// from running - including the navigation step itself, so a throwing
  /// `onLoggedOut` cannot propagate out of this method. The in-memory state
  /// reset is unconditional - outside any try/catch, since assigning local
  /// fields cannot fail - so this method itself can never throw and
  /// AuthProvider always reaches the logged-out state with navigation
  /// attempted exactly once, regardless of which step (if any) failed.
  Future<void> _performLogout({
    required bool unregisterFcm,
    required bool resetSignupFields,
    required String resultErrorMessage,
  }) async {
    // 0. Invalidate the session identity FIRST, synchronously, before
    // anything else in this logout pass runs - including the FCM
    // unregister call below. AuthProvider owns this call exclusively (no
    // other class ever calls activate()/invalidate()), and _runLogout's
    // _logoutInFlight guard ensures _performLogout - and therefore this
    // line - runs exactly once per logical logout pass, regardless of how
    // many concurrent/repeated manual-logout or forced-401 triggers
    // arrive. This does not depend on onSessionEnding being wired at all:
    // a bare AuthProvider (e.g. in a test, or in any alternate app wiring
    // that never constructs a SessionCleanupCoordinator) still invalidates
    // correctly, because this call has nothing to do with the coordinator
    // - it is unconditional and always runs. The coordinator itself must
    // never independently call invalidate() - doing so would double the
    // generation increment for a single logical logout.
    _sessionEpoch.invalidate();

    // 0b. Cancel every in-flight HTTP request still bound to the session
    // just invalidated above - its own independent failure boundary, since
    // SessionRequestCoordinator.cancelCurrentGeneration() is designed to be
    // non-throwing but must never be trusted to stay that way from here.
    // Deliberately not nested around the rest of this method: a failure
    // here must never skip FCM unregister, SessionCleanupCoordinator,
    // credential clearing, background-service cleanup, Isar clearing, the
    // in-memory reset, or navigation below.
    try {
      _sessionRequestCoordinator.cancelCurrentGeneration();
    } catch (e) {
      debugPrint('⚠️ Failed to cancel in-flight session requests: $e');
    }

    if (unregisterFcm) {
      // Unregister FCM token from server (non-blocking)
      try {
        await PushNotificationService().unregisterToken();
      } catch (e) {
        debugPrint('⚠️ Failed to unregister FCM token: $e');
      }
    }

    // 1. Stop active resources (GPS/timers/polling/watchers) and clear
    // settled Provider state - individually best-effort per operation
    // inside the coordinator already, guarded again here regardless.
    try {
      await onSessionEnding?.call();
    } catch (e) {
      debugPrint('⚠️ Session cleanup coordinator failed: $e');
    }

    // 2. Remove every session/user-identity secure-storage key (token,
    // user id/name/email, cached profile). clearSessionCredentials()
    // itself never throws (each key is deleted independently inside it),
    // but this step is guarded regardless, matching every other step here.
    try {
      await _authService.clearSessionCredentials();
    } catch (e) {
      debugPrint('⚠️ Failed to clear session credentials: $e');
    }

    // 3. Clear background service token and cancel scheduled tasks.
    try {
      await BackgroundService.clearAuthToken();
      await BackgroundService.cancelNutritionCheck();
    } catch (e) {
      debugPrint('⚠️ Failed to clear background service: $e');
    }

    // 4. Clear all local database data for privacy/security.
    try {
      await _localDb.clearAll();
      debugPrint('✅ Local database cleared on logout');
    } catch (e) {
      debugPrint('⚠️ Failed to clear local database: $e');
    }

    // 5. In-memory state reset - unconditional, regardless of any failure
    // above.
    _isAuthenticated = false;
    _currentUserId = null;
    _currentUserName = null;
    _currentUserEmail = null;
    _email = '';
    _password = '';
    if (resetSignupFields) {
      _signupName = '';
      _signupUsername = '';
      _signupEmail = '';
      _signupPassword = '';
      _signupConfirmPassword = '';
    }
    _errorMessage = resultErrorMessage;
    notifyListeners();

    // 6. Navigate to login - attempted exactly once per logout pass. Guarded
    // like every step above: if the callback itself throws, this method
    // must still complete normally (not propagate to the manual-logout
    // caller, MeScreen) rather than relying solely on the outer defensive
    // catch that only the forced/401 trigger's unawaited call site has.
    // That outer catch remains as a last-resort backstop for anything
    // unforeseen; this is the first line of defense for both triggers
    // alike, so they share identical failure behavior.
    try {
      onLoggedOut?.call();
    } catch (e) {
      debugPrint('⚠️ onLoggedOut callback failed: $e');
    }
  }

  // Getters
  String get email => _email;
  String get password => _password;
  String get signupName => _signupName;
  String get signupUsername => _signupUsername;
  String get signupEmail => _signupEmail;
  String get signupPassword => _signupPassword;
  String get signupConfirmPassword => _signupConfirmPassword;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  bool get isInitializing => _isInitializing;
  bool get isAuthenticated => _isAuthenticated;
  int? get currentUserId => _currentUserId;
  String? get currentUserName => _currentUserName;
  String? get currentUserEmail => _currentUserEmail;

  // Setters
  void setEmail(String value) {
    _email = value;
    notifyListeners();
  }

  void setPassword(String value) {
    _password = value;
    notifyListeners();
  }

  void setSignupName(String value) {
    _signupName = value;
    notifyListeners();
  }

  void setSignupUsername(String value) {
    _signupUsername = value;
    notifyListeners();
  }

  void setSignupEmail(String value) {
    _signupEmail = value;
    notifyListeners();
  }

  void setSignupPassword(String value) {
    _signupPassword = value;
    notifyListeners();
  }

  void setSignupConfirmPassword(String value) {
    _signupConfirmPassword = value;
    notifyListeners();
  }

  /// Check if user is already authenticated on app start
  Future<void> _checkAuthStatus() async {
    try {
      _isAuthenticated = await _authService.isAuthenticated();
      if (_isAuthenticated) {
        _currentUserId = await _authService.getUserId();
        _currentUserName = await _authService.getUserName();
        _currentUserEmail = await _authService.getUserEmail();

        // A restored session is a live authentication-success path just
        // like login()/signup() - activate() before this state becomes
        // observable (notifyListeners() below), so anything that reacts
        // to isAuthenticated flipping true captures the correct, already
        // -activated generation from its very first load. If the stored
        // token is somehow missing its user ID, this is not a valid
        // restorable session - fall through without activating.
        final userId = _currentUserId;
        if (userId != null) {
          _sessionEpoch.activate(userId);
        } else {
          _isAuthenticated = false;
        }
      }
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Login user
  Future<bool> login() async {
    if (_email.trim().isEmpty || _password.isEmpty) {
      _errorMessage = 'Please enter both email and password';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final request = LoginRequest(email: _email.trim(), password: _password);

      final response = await _authRepository.login(request);

      // Save token and user info to secure storage
      await _authService.saveToken(
        token: response.token,
        userId: response.userId,
        name: response.name,
        email: response.email,
      );

      // Update local state
      _isAuthenticated = true;
      _currentUserId = response.userId;
      _currentUserName = response.name;
      _currentUserEmail = response.email;

      // Mint a fresh session generation now that the authoritative user ID
      // is known, before notifyListeners() (in the finally block below)
      // can cause any authenticated-screen Provider to start loading data
      // - every such load's captured token is guaranteed to be this new
      // generation, never a stale one from a previous session or a
      // logged-out gap.
      _sessionEpoch.activate(response.userId);

      // Reset the unauthorized flag for fresh session
      _apiService.resetUnauthorizedFlag();

      // Save token for background service (non-blocking)
      try {
        await BackgroundService.saveAuthToken(response.token);
      } catch (e) {
        debugPrint('⚠️ Failed to save token for background service: $e');
      }

      // Clear password for security
      _password = '';

      return true;
    } catch (e) {
      _errorMessage =
          'Login failed: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Login error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Signup new user
  Future<bool> signup() async {
    // Validation
    if (_signupName.trim().isEmpty) {
      _errorMessage = 'Please enter your name';
      notifyListeners();
      return false;
    }

    if (_signupUsername.trim().isEmpty) {
      _errorMessage = 'Please enter a username';
      notifyListeners();
      return false;
    }

    if (_signupUsername.trim().length < 3) {
      _errorMessage = 'Username must be at least 3 characters';
      notifyListeners();
      return false;
    }

    if (_signupEmail.trim().isEmpty) {
      _errorMessage = 'Please enter your email';
      notifyListeners();
      return false;
    }

    if (_signupPassword.length < 6) {
      _errorMessage = 'Password must be at least 6 characters';
      notifyListeners();
      return false;
    }

    if (_signupPassword != _signupConfirmPassword) {
      _errorMessage = 'Passwords do not match';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final request = SignupRequest(
        name: _signupName.trim(),
        username: _signupUsername.trim(),
        email: _signupEmail.trim(),
        password: _signupPassword,
      );

      final response = await _authRepository.signup(request);

      // Save token and user info to secure storage
      await _authService.saveToken(
        token: response.token,
        userId: response.userId,
        name: response.name,
        email: response.email,
      );

      // Update local state
      _isAuthenticated = true;
      _currentUserId = response.userId;
      _currentUserName = response.name;
      _currentUserEmail = response.email;

      // Signup authenticates immediately (same as login) - mint a fresh
      // session generation before notifyListeners() (in the finally block
      // below) can cause any authenticated-screen Provider to start
      // loading data.
      _sessionEpoch.activate(response.userId);

      // Save token for background service (non-blocking)
      try {
        await BackgroundService.saveAuthToken(response.token);
      } catch (e) {
        debugPrint('⚠️ Failed to save token for background service: $e');
      }

      // Clear passwords for security
      _signupPassword = '';
      _signupConfirmPassword = '';

      return true;
    } catch (e) {
      _errorMessage =
          'Signup failed: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Signup error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout user
  Future<void> logout() {
    return _runLogout(
      unregisterFcm: true,
      resetSignupFields: true,
      resultErrorMessage: '',
    );
  }

  /// Clear error message
  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }

  /// Set error message manually
  void setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// Convenience methods for updating fields
  void updateEmail(String value) {
    _email = value;
    _signupEmail = value;
  }

  void updatePassword(String value) {
    _password = value;
    _signupPassword = value;
  }

  void updateName(String value) {
    _signupName = value;
  }
}
