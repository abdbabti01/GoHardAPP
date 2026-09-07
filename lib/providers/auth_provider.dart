import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models/login_request.dart';
import '../data/models/signup_request.dart';
import '../data/repositories/auth_repository.dart';
import '../data/services/auth_service.dart';
import '../data/services/api_service.dart';
import '../data/services/rate_limited_exception.dart';
import '../core/services/background_service.dart';
import '../core/services/push_notification_service.dart';
import '../core/services/session_request_coordinator.dart';
import '../core/services/user_session_epoch.dart';

/// Which kind of session-termination a [_TerminationPass] currently is -
/// see [_TerminationPass] and `AuthProvider._runTerminationPass`.
enum _TerminationKind { forcedExpiration, explicitLogout }

/// One shared, mutable record of "ending the session that was active when
/// this pass started" - see `AuthProvider._beginOrJoinTermination` and
/// `AuthProvider._runTerminationPass`. [kind] may be upgraded from
/// [_TerminationKind.forcedExpiration] to [_TerminationKind.explicitLogout]
/// while the pass is in flight (never the reverse).
class _TerminationPass {
  _TerminationPass(this.kind);
  _TerminationKind kind;

  /// The [UserSessionEpoch.generation] value immediately AFTER this pass's
  /// own `invalidate()` call - set synchronously, as the very first thing
  /// `_runTerminationPass` does, before any `await`. A joining caller
  /// matches against this (never against a generation it read itself
  /// before deciding whether to join) precisely because `invalidate()`
  /// changes what `UserSessionEpoch.generation` reads: comparing two
  /// callers' own independently-read snapshots would spuriously fail to
  /// match depending on exactly when each one happened to read it
  /// relative to this pass's `invalidate()` call. Null only during the
  /// infinitesimal window before that first line runs - which, since
  /// Dart's single-threaded execution never yields before then, no other
  /// caller can ever actually observe.
  int? endedGeneration;
}

/// Provider for authentication state management
/// Combines LoginViewModel and SignupViewModel from MAUI app
class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository;
  final AuthService _authService;
  final ApiService _apiService;

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
  /// before credentials are touched - the single seam through which
  /// active-resource teardown (GPS, timers, polling, Isar watcher/stream
  /// SUBSCRIPTION cancellation - never a data write or delete) and
  /// settled-state clearing happens for every logout trigger. Set once from
  /// main.dart after the full Provider graph exists (mirroring the
  /// `_apiService.onUnauthorized` wiring below), so this class never needs
  /// to depend on the 15+ feature Providers a SessionCleanupCoordinator
  /// clears - avoiding a circular dependency in either direction.
  Future<void> Function()? onSessionEnding;

  /// Invoked exactly once per completed logout pass, after credentials are
  /// cleared and this provider's own state has settled - the single
  /// centralized navigation trigger for every logout path (manual button,
  /// 401/session-expiry). Set from app.dart via a global `NavigatorState`
  /// key, so this file never needs a `BuildContext`.
  void Function()? onLoggedOut;

  AuthProvider(
    this._authRepository,
    this._authService,
    this._apiService,
    this._sessionEpoch,
    this._sessionRequestCoordinator,
  ) {
    // Set up callback for 401 unauthorized errors
    _apiService.onUnauthorized = _handleSessionExpired;
    _checkAuthStatus();
  }

  /// The safe, generic message shown after a forced-expiration-only pass -
  /// deliberately never varies with the server's response body, the
  /// specific request that failed, or which of the app's endpoints
  /// triggered it, and never implies any offline work was lost. Never
  /// shown if explicit logout ever participates in the same termination
  /// pass - see [_TerminationKind] precedence in [_runTerminationPass].
  static const String _forcedExpirationMessage =
      'Your session expired. Sign in again. Your offline changes are safe.';

  /// Which kind of session-termination a [_TerminationPass] is - decides
  /// whether FCM unregister runs and which final message/state the
  /// terminal step selects. Neither kind touches durable local (Isar) data
  /// - explicit logout and forced expiration are both non-destructive; see
  /// [_runTerminationPass]'s class doc comment. A pass may be UPGRADED from
  /// [forcedExpiration] to [explicitLogout] while in flight if explicit
  /// logout joins it (see [_beginOrJoinTermination]), but is NEVER
  /// downgraded: once any participant for a generation is an explicit
  /// logout, that generation's outcome is always a deliberate logout,
  /// never a "session expired" message.
  void _handleSessionExpired() {
    debugPrint('⚠️ Session expired - requesting non-destructive expiration');
    // _runTerminationPass() is already non-throwing by construction - every
    // step inside it is individually guarded - but this outer catch
    // remains a deliberate last-resort backstop: nothing here is watching
    // this unawaited Future (onUnauthorized is a fire-and-forget `void
    // Function()` callback), so if some future change ever let an
    // exception past that inner boundary, it must still never surface as
    // an unhandled asynchronous error.
    unawaited(
      _beginOrJoinTermination(_TerminationKind.forcedExpiration).catchError((
        Object e,
        StackTrace stackTrace,
      ) {
        debugPrint('⚠️ Forced expiration encountered an unexpected error: $e');
      }),
    );
  }

  /// One shared, single-flight record of "ending the session that was
  /// active when this pass started" - explicit logout and forced
  /// expiration both go through [_beginOrJoinTermination], which either
  /// starts a NEW pass (recorded here) or, if one is already in flight for
  /// the session currently being ended, joins the existing one instead of
  /// starting a second. This is what makes concurrent
  /// manual-logout-plus-forced-401, a burst of concurrent 401s, and
  /// repeated logout() calls all collapse into exactly one shared
  /// cleanup+notify+navigate for that session, regardless of which
  /// trigger(s) participate or their relative timing.
  _TerminationPass? _activeTermination;
  Future<void>? _activeTerminationFuture;

  /// True while ANY termination pass (explicit logout, forced expiration,
  /// or one upgraded from the latter to the former) is in progress.
  /// Exposed for tests/diagnostics - the kind-agnostic signal to poll when
  /// a race between the two triggers is possible; [isLoggingOut] and
  /// [isExpiringSession] below report the pass's CURRENT kind instead, and
  /// can flip mid-pass if a joining explicit logout upgrades it.
  bool get isTerminating => _activeTermination != null;

  /// True while the in-flight termination pass's current kind is explicit
  /// logout. Exposed for tests/diagnostics.
  bool get isLoggingOut =>
      _activeTermination?.kind == _TerminationKind.explicitLogout;

  /// True while the in-flight termination pass's current kind is forced
  /// expiration (i.e. no explicit logout has joined it - yet). Exposed for
  /// tests/diagnostics.
  bool get isExpiringSession =>
      _activeTermination?.kind == _TerminationKind.forcedExpiration;

  /// Starts a new termination pass, or - if one is already in flight for
  /// the SAME session (see [_TerminationPass.endedGeneration]) - joins it
  /// instead, upgrading its kind to [kind] if [kind] is
  /// [_TerminationKind.explicitLogout] (never the reverse).
  ///
  /// A caller is "joining the same pass" exactly when [_activeTermination]
  /// is non-null and its [_TerminationPass.endedGeneration] equals
  /// [_sessionEpoch]'s CURRENT generation, read fresh right here. This is
  /// deliberately NOT a comparison against a generation either side
  /// captured before deciding to join: `invalidate()` (the very first
  /// thing [_runTerminationPass] does, synchronously, before any `await`)
  /// changes what that read returns, and Dart's single-threaded execution
  /// guarantees no other code can run between a pass's own `invalidate()`
  /// call and [_TerminationPass.endedGeneration] being recorded - so ANY
  /// later caller, triggered at any point after that, reading the epoch's
  /// generation fresh will see exactly [_TerminationPass.endedGeneration]
  /// if and only if no NEWER session has begun since. If a newer session
  /// HAS begun (a different user's login, or this same user
  /// re-authenticating), the generation has moved past it, this join
  /// condition correctly fails, and this call starts its own fresh,
  /// independent pass instead - never joining or disturbing a pass that
  /// belongs to a session that has already superseded the one it
  /// nominally started for.
  ///
  /// Forced expiration additionally no-ops (a harmless, deliberate no-op -
  /// covers a spurious/late signal, e.g. one arriving after a manual
  /// logout already finished) if nothing is active to terminate at all:
  /// no pass in flight AND not currently authenticated. Explicit logout has
  /// no such guard - it always runs its full pass unconditionally, even if
  /// called while already signed out, exactly like before this pass ever
  /// existed: a safe, idempotent, always-available user-initiated
  /// operation, not merely a reaction to being authenticated.
  Future<void> _beginOrJoinTermination(_TerminationKind kind) {
    final existing = _activeTermination;
    final existingFuture = _activeTerminationFuture;

    if (existing != null &&
        existingFuture != null &&
        existing.endedGeneration != null &&
        existing.endedGeneration == _sessionEpoch.generation) {
      if (kind == _TerminationKind.explicitLogout) {
        existing.kind = _TerminationKind.explicitLogout;
      }
      return existingFuture;
    }

    if (kind == _TerminationKind.forcedExpiration && !_isAuthenticated) {
      return Future<void>.value();
    }

    final pass = _TerminationPass(kind);
    _activeTermination = pass;
    final future = _runTerminationPass(pass).whenComplete(() {
      if (identical(_activeTermination, pass)) {
        _activeTermination = null;
        _activeTerminationFuture = null;
      }
    });
    _activeTerminationFuture = future;
    return future;
  }

  /// FCM unregister - reachable ONLY for a pass whose kind is (at the time
  /// this step runs) [_TerminationKind.explicitLogout]; a pure
  /// forced-expiration pass never reaches this. Must run BEFORE
  /// [_authService].clearSessionCredentials() below - never after - so
  /// this authenticated call is never sent once the token has already been
  /// removed from secure storage.
  Future<void> _unregisterFcmForExplicitLogout() async {
    try {
      await PushNotificationService().unregisterToken();
    } catch (e) {
      debugPrint('⚠️ Failed to unregister FCM token: $e');
    }
  }

  /// Runs every security-critical termination step as an independent,
  /// best-effort attempt (its own try/catch, a flat sequence, not nested),
  /// so a failure in any one of them is logged and never prevents the next
  /// eligible step from running. Shared by BOTH explicit logout and forced
  /// expiration - [pass.kind] is re-read FRESH at each decision point
  /// below (never captured once at the top), so a joining explicit logout
  /// that upgrades [pass] partway through still reliably gets its FCM
  /// unregister / final-message precedence, no matter which step the pass
  /// had already reached at the moment it joined.
  ///
  /// NEITHER kind ever touches durable local (Isar) data. Explicit logout
  /// and forced expiration are both non-destructive: every step here only
  /// invalidates in-memory/session identity, cancels in-flight requests,
  /// clears already-settled Provider state, removes secure-storage
  /// credentials, and (for explicit logout) best-effort unregisters the
  /// FCM push token - never `LocalDatabaseService.clearAll()`, never any
  /// other Isar write or delete. A user's offline-created/pending/synced
  /// records survive every termination path; only signing back in changes
  /// what is currently visible. See
  /// `test/providers/auth_provider_non_destructive_logout_test.dart` for
  /// the behavioral proof and
  /// `test/providers/auth_provider_composition_proof_test.dart` for the
  /// source-level guarantee that this file contains no reference to
  /// `clearAll` at all.
  ///
  /// Every step from [stillOwnsThisGeneration] onward is guarded by that
  /// snapshot-generation recheck against [_sessionEpoch]: if a NEWER
  /// session (a different user's login, or this same user
  /// re-authenticating) has begun since this pass started invalidating the
  /// OLD one, every remaining step - including credential clearing, the
  /// in-memory reset, and navigation - is skipped outright, so a
  /// slow/stale pass can never revive, disturb, or delete state belonging
  /// to the session that superseded it.
  Future<void> _runTerminationPass(_TerminationPass pass) async {
    // 0. Invalidate the session identity FIRST, synchronously - before
    // anything else in this pass runs, including recording
    // [pass.endedGeneration] itself, which [_beginOrJoinTermination] relies
    // on to decide whether a later caller is joining THIS pass. Every
    // later step in this method can also use this same snapshot to detect
    // whether a NEWER session has since begun.
    _sessionEpoch.invalidate();
    pass.endedGeneration = _sessionEpoch.generation;
    final endedGeneration = pass.endedGeneration!;
    bool stillOwnsThisGeneration() =>
        _sessionEpoch.generation == endedGeneration;

    // 0a. Reset AuthProvider's own public-facing identity fields
    // SYNCHRONOUSLY, immediately after invalidate() and before this pass's
    // first `await` - Dart's single-threaded execution guarantees nothing
    // else can run in between, so this is always safe: no newer session
    // can possibly have begun yet, and [_beginOrJoinTermination]'s join
    // condition depends on `_isAuthenticated` already being `false` by the
    // time ANY subsequent trigger (even one arriving on the very next
    // microtask) checks it. This closes a real gap the previous design
    // had: a caller reading `isAuthenticated`/`currentUserId` mid-pass
    // (after invalidate() but before the awaited cleanup steps finished)
    // would see a STALE, already-invalidated session still reported as
    // authenticated. `_errorMessage`/`notifyListeners()` are deliberately
    // NOT touched here - the FINAL message depends on which kind this
    // pass ultimately resolves to, which can still be upgraded by a
    // joining explicit logout after this point; only the raw identity
    // fields are safe to commit immediately.
    _isAuthenticated = false;
    _currentUserId = null;
    _currentUserName = null;
    _currentUserEmail = null;
    _email = '';
    _password = '';

    // 0b. Cancel every in-flight HTTP request still bound to the session
    // just invalidated above. Safe regardless of ownership staleness -
    // see `SessionRequestCoordinator.cancelCurrentGeneration`'s own doc
    // comment: cancelling an old generation's token can never affect a
    // newer one's.
    try {
      _sessionRequestCoordinator.cancelCurrentGeneration();
    } catch (e) {
      debugPrint('⚠️ Failed to cancel in-flight session requests: $e');
    }

    // 1. Stop active resources (GPS/timers/polling/watchers) and clear
    // settled Provider state - in-memory only, never Isar (see every
    // provider's own `clear()`, none of which perform a database write) -
    // shared, exactly once regardless of which kind(s) participated.
    try {
      await onSessionEnding?.call();
    } catch (e) {
      debugPrint('⚠️ Session cleanup coordinator failed: $e');
    }

    if (!stillOwnsThisGeneration()) return;

    // 1b. FCM unregister - explicit-logout-only, checked fresh HERE rather
    // than in this pass's synchronous prefix (before step 1's `await`
    // above): every other step below this point sits after a real `await`
    // and is genuinely reachable by a LATE-joining explicit logout that
    // upgrades `pass.kind` while this pass is suspended inside
    // onSessionEnding - a check placed any earlier (in the synchronous
    // window between `_activeTermination = pass` in
    // `_beginOrJoinTermination` and this pass's first `await`) can NEVER
    // observe an upgrade, since nothing else can run in that window at
    // all (Dart's single-threaded execution), so a pass that STARTED as
    // forced-expiration-only would always find `pass.kind` still
    // `forcedExpiration` there, permanently skipping FCM-unregister even
    // after a later join upgrades it. Still runs before
    // `clearSessionCredentials()` below - never after - so this
    // authenticated call is never sent once the token has already been
    // removed from secure storage.
    if (pass.kind == _TerminationKind.explicitLogout) {
      await _unregisterFcmForExplicitLogout();
    }

    if (!stillOwnsThisGeneration()) return;

    // 2. Remove every session/user-identity secure-storage key - shared,
    // exactly once.
    try {
      await _authService.clearSessionCredentials();
    } catch (e) {
      debugPrint('⚠️ Failed to clear session credentials: $e');
    }

    if (!stillOwnsThisGeneration()) return;

    // 3. Clear background service token and cancel scheduled tasks -
    // shared, exactly once. No Isar, no network call.
    try {
      await BackgroundService.clearAuthToken();
      await BackgroundService.cancelNutritionCheck();
    } catch (e) {
      debugPrint('⚠️ Failed to clear background service: $e');
    }

    if (!stillOwnsThisGeneration()) return;

    // 4. Terminal step: remaining state reset, final message (precedence:
    // explicit logout always wins - checked fresh one last time, so even a
    // very-late-joining logout still overrides the generic expiration
    // message), and the single notifyListeners() for this whole pass.
    if (pass.kind == _TerminationKind.explicitLogout) {
      _signupName = '';
      _signupUsername = '';
      _signupEmail = '';
      _signupPassword = '';
      _signupConfirmPassword = '';
      _errorMessage = '';
    } else {
      _errorMessage = _forcedExpirationMessage;
    }
    notifyListeners();

    // 5. Navigate to login - attempted exactly once per pass, guarded like
    // every step above so a throwing `onLoggedOut` cannot propagate out of
    // this method.
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
      // A 429 is never an authentication failure: never logs the user out,
      // never wipes the entered password (untouched above on this path -
      // only the SUCCESS path clears it), never discloses whether the
      // account exists, and never triggers an automatic retry - the user
      // stays on this screen and can retry manually whenever they choose.
      _errorMessage =
          e is RateLimitedException
              ? 'Too many attempts. Please wait and try again.'
              : 'Login failed: ${e.toString().replaceAll('Exception: ', '')}';
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
      // Same treatment as login() above: a 429 never logs out, never
      // discloses account existence, and never auto-retries. Entered
      // signup fields are untouched here - only the SUCCESS path clears
      // the password fields.
      _errorMessage =
          e is RateLimitedException
              ? 'Too many attempts. Please wait and try again.'
              : 'Signup failed: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Signup error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Explicit, user-initiated logout - non-destructive: clears
  /// authentication (credentials, session identity, in-memory Provider
  /// state) but never durable local data. A later login as the SAME
  /// account sees every offline-created/pending/synced record exactly as
  /// it was left; a DIFFERENT account never sees it at all (every
  /// repository read/watch stays scoped to the currently authenticated
  /// user - see [_runTerminationPass]'s class doc comment).
  Future<void> logout() {
    return _beginOrJoinTermination(_TerminationKind.explicitLogout);
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
