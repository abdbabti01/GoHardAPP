import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models/user.dart';
import '../data/models/profile_update_request.dart';
import '../data/repositories/profile_repository.dart';
import '../data/services/api_exception.dart';
import '../data/services/auth_service.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/user_session_epoch.dart';

/// Why the last [ProfileProvider.uploadProfilePhoto] attempt failed, so the
/// UI can react appropriately without re-parsing an error string. [none] means
/// "no attempt yet, or the last one succeeded".
enum PhotoUploadError {
  none,

  /// Server rejected the image (400) - wrong format / not a real image.
  validation,

  /// Server rejected the image as too large (413).
  tooLarge,

  /// Server photo changed under us (409) - the caller must refresh
  /// authoritative state and offer an explicit retry, never silently
  /// overwrite the concurrent change.
  conflict,

  /// Transport/5xx/other failure - retryable.
  network,
}

/// Why the last [ProfileProvider.updateProfile] attempt failed.
enum ProfileFieldsError {
  none,

  /// The requested username is taken by another account (409).
  usernameTaken,

  /// Server-side validation rejected the request (400) - e.g. an invalid
  /// username.
  validation,

  /// Transport/5xx/other failure - retryable.
  network,
}

/// Provider for user profile management
/// Replaces ProfileViewModel from MAUI app
class ProfileProvider extends ChangeNotifier {
  final ProfileRepository _profileRepository;
  final AuthService _authService;
  final UserSessionEpoch _sessionEpoch;
  final ConnectivityService? _connectivity;

  User? _currentUser;
  bool _isLoading = false;
  bool _isUpdating = false;
  bool _isUploadingPhoto = false;
  String? _errorMessage;
  PhotoUploadError _photoError = PhotoUploadError.none;
  ProfileFieldsError _fieldsError = ProfileFieldsError.none;
  String? _cachedThemePreference; // Theme loaded from local storage

  StreamSubscription<bool>? _connectivitySubscription;

  ProfileProvider(
    this._profileRepository,
    this._authService,
    this._sessionEpoch, [
    this._connectivity,
  ]) {
    // Load theme from local storage on init - deliberately NOT
    // session-epoch-guarded: theme preference is device-wide, not
    // user-specific (see clear()'s own comment below), so it is meant to
    // survive across accounts, unlike every other field this provider
    // holds.
    _loadCachedTheme();

    // Listen for connectivity changes and refresh when going online. This
    // callback can fire at any point in the app's lifetime, including
    // during a logged-out gap between one user's logout and the next
    // user's login - capture a token fresh on every invocation (not once
    // at listener-registration time) and skip entirely if there is no
    // active session, so a connectivity flap while logged out can never
    // dispatch a profile load for nobody.
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
      final token = _sessionEpoch.capture();
      if (token == null) return;
      if (isOnline && _currentUser != null) {
        debugPrint('📡 Connection restored - refreshing profile');
        loadUserProfile();
      }
    });
  }

  /// Load theme preference from local storage (fast, offline-first)
  Future<void> _loadCachedTheme() async {
    _cachedThemePreference = await _authService.getThemePreference();
    notifyListeners();
  }

  // Getters
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isUpdating => _isUpdating;
  bool get isUploadingPhoto => _isUploadingPhoto;
  String? get errorMessage => _errorMessage;

  /// Classified reason the last [uploadProfilePhoto] failed (or [none]).
  PhotoUploadError get photoError => _photoError;

  /// Classified reason the last [updateProfile] failed (or [none]).
  ProfileFieldsError get fieldsError => _fieldsError;

  /// Get current theme mode based on user preference
  /// Uses cached theme from local storage first (offline-first)
  /// Defaults to dark mode for the new UI design
  ThemeMode get themeMode {
    // First check cached theme (from local storage - fast!)
    final preference = _cachedThemePreference ?? _currentUser?.themePreference;
    switch (preference?.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.dark; // Default to dark mode
    }
  }

  /// Load current user profile with stats.
  ///
  /// Session-epoch guarded: [token] is captured before any await, and
  /// re-checked after every await (including inside catch/finally) before
  /// touching any field or calling notifyListeners(). If the session that
  /// requested this load has since ended - logout, or a different user
  /// logging in - the response is dropped silently rather than
  /// overwriting whatever the current session's own state already is.
  Future<void> loadUserProfile() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _profileRepository.getProfile();
      if (!_sessionEpoch.isCurrent(token)) return;
      _currentUser = user;

      // Save theme preference to local storage for offline access
      if (_currentUser?.themePreference != null) {
        _cachedThemePreference = _currentUser!.themePreference;
        await _authService.saveThemePreference(_currentUser!.themePreference!);
      }
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return;
      _errorMessage =
          'Failed to load profile: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load profile error: $e');
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Update user profile. Same session-epoch guarding as [loadUserProfile].
  ///
  /// On failure, [fieldsError] is set to a classified reason (username taken,
  /// generic validation, or network) so the caller can show an inline field
  /// error vs. a retryable message without re-parsing [errorMessage].
  Future<bool> updateProfile(ProfileUpdateRequest request) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    _isUpdating = true;
    _errorMessage = null;
    _fieldsError = ProfileFieldsError.none;
    notifyListeners();

    try {
      final user = await _profileRepository.updateProfile(request);
      if (!_sessionEpoch.isCurrent(token)) return false;
      _currentUser = user;

      // Save theme preference to local storage if updated
      if (_currentUser?.themePreference != null) {
        _cachedThemePreference = _currentUser!.themePreference;
        await _authService.saveThemePreference(_currentUser!.themePreference!);
        if (!_sessionEpoch.isCurrent(token)) return false;
      }

      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _fieldsError = _classifyFieldsError(e);
      _errorMessage =
          'Failed to update profile: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update profile error: $e');
      return false;
    } finally {
      if (_sessionEpoch.isCurrent(token)) {
        _isUpdating = false;
        notifyListeners();
      }
    }
  }

  static ProfileFieldsError _classifyFieldsError(Object e) {
    if (e is ApiException) {
      switch (e.statusCode) {
        case 409:
          return ProfileFieldsError.usernameTaken;
        case 400:
          return ProfileFieldsError.validation;
      }
    }
    return ProfileFieldsError.network;
  }

  /// Upload profile photo. [loadUserProfile]'s own nested call is
  /// independently session-epoch guarded; this method additionally guards
  /// its own [_isUploadingPhoto]/[_errorMessage] assignments with the same
  /// token captured at the start.
  Future<bool> uploadProfilePhoto(File imageFile) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    _isUploadingPhoto = true;
    _errorMessage = null;
    _photoError = PhotoUploadError.none;
    notifyListeners();

    try {
      await _profileRepository.uploadProfilePhoto(imageFile);
      if (!_sessionEpoch.isCurrent(token)) return false;

      // Reload profile so the authoritative server photo URL is published to
      // every screen immediately (never a local File preview).
      await loadUserProfile();
      if (!_sessionEpoch.isCurrent(token)) return false;

      _isUploadingPhoto = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _photoError = _classifyPhotoError(e);
      _errorMessage =
          'Failed to upload photo: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Upload photo error: $e');
      _isUploadingPhoto = false;
      notifyListeners();
      return false;
    }
  }

  static PhotoUploadError _classifyPhotoError(Object e) {
    if (e is ApiException) {
      switch (e.statusCode) {
        case 413:
          return PhotoUploadError.tooLarge;
        case 400:
          return PhotoUploadError.validation;
        case 409:
          return PhotoUploadError.conflict;
      }
    }
    return PhotoUploadError.network;
  }

  /// Delete profile photo. Same session-epoch guarding as
  /// [uploadProfilePhoto].
  Future<bool> deleteProfilePhoto() async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    _isUploadingPhoto = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _profileRepository.deleteProfilePhoto();
      if (!_sessionEpoch.isCurrent(token)) return false;

      // Reload profile to get updated data
      await loadUserProfile();
      if (!_sessionEpoch.isCurrent(token)) return false;

      _isUploadingPhoto = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (!_sessionEpoch.isCurrent(token)) return false;
      _errorMessage =
          'Failed to delete photo: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete photo error: $e');
      _isUploadingPhoto = false;
      notifyListeners();
      return false;
    }
  }

  /// Toggle unit preference between Metric and Imperial
  Future<void> toggleUnitPreference() async {
    if (_currentUser == null) return;

    final currentPreference = _currentUser!.unitPreference ?? 'Metric';
    final newPreference = currentPreference == 'Metric' ? 'Imperial' : 'Metric';

    final request = ProfileUpdateRequest(unitPreference: newPreference);

    await updateProfile(request);
  }

  /// Get user name from auth service (cached)
  Future<String> getUserName() async {
    return await _authService.getUserName() ?? 'User';
  }

  /// Get user email from auth service (cached)
  Future<String> getUserEmail() async {
    return await _authService.getUserEmail() ?? '';
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    _photoError = PhotoUploadError.none;
    _fieldsError = ProfileFieldsError.none;
    notifyListeners();
  }

  /// Clear all profile data (called on logout)
  void clear() {
    _currentUser = null;
    _errorMessage = null;
    _photoError = PhotoUploadError.none;
    _fieldsError = ProfileFieldsError.none;
    _isLoading = false;
    _isUpdating = false;
    _isUploadingPhoto = false;
    // Keep theme preference for UX
    notifyListeners();
    debugPrint('🧹 ProfileProvider cleared');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
