import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for managing authentication tokens and user data in secure storage
/// Matches the AuthService.cs from MAUI app
class AuthService {
  // iOS: Use first_unlock to persist across app restarts/background termination
  // Android: Use encryptedSharedPreferences for better compatibility
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _tokenKey = 'jwt_token';
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';
  static const String _userEmailKey = 'user_email';
  static const String _themePreferenceKey = 'theme_preference';
  static const String _cachedProfileKey = 'cached_user_profile';

  /// Top-level field names of the owner-tagged profile-cache envelope written
  /// by [writeCachedProfile] and validated by [readCachedProfile].
  static const String _cachedProfileOwnerField = 'cachedForUserId';
  static const String _cachedProfileDataField = 'profile';

  /// Save authentication data to secure storage
  Future<void> saveToken({
    required String token,
    required int userId,
    required String name,
    required String email,
  }) async {
    await Future.wait([
      _storage.write(key: _tokenKey, value: token),
      _storage.write(key: _userIdKey, value: userId.toString()),
      _storage.write(key: _userNameKey, value: name),
      _storage.write(key: _userEmailKey, value: email),
    ]);
  }

  /// Get JWT token from secure storage
  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (e) {
      return null;
    }
  }

  /// Get user ID from secure storage
  Future<int?> getUserId() async {
    try {
      final userIdString = await _storage.read(key: _userIdKey);
      if (userIdString != null) {
        return int.tryParse(userIdString);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get user name from secure storage
  Future<String?> getUserName() async {
    try {
      return await _storage.read(key: _userNameKey);
    } catch (e) {
      return null;
    }
  }

  /// Get user email from secure storage
  Future<String?> getUserEmail() async {
    try {
      return await _storage.read(key: _userEmailKey);
    } catch (e) {
      return null;
    }
  }

  /// Check if user is authenticated (has valid token)
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Clear all authentication data from secure storage.
  ///
  /// Kept for the legacy (unreachable/dead - no ProviderScope is ever
  /// mounted) Riverpod auth_notifier.dart call site. The live logout path
  /// (AuthProvider) uses [clearSessionCredentials] below instead, which
  /// also removes the cached profile payload this method omits.
  Future<void> clearToken() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _userIdKey),
      _storage.delete(key: _userNameKey),
      _storage.delete(key: _userEmailKey),
      // Don't delete theme preference - user's theme choice persists across logins
    ]);
  }

  /// Every secure-storage key that identifies the signed-in user or their
  /// session, in the order [clearSessionCredentials] attempts to delete
  /// them. Deliberately excludes [_themePreferenceKey]: it is a
  /// device-wide UI preference, not user-identifying data, and is meant to
  /// persist across logins (see [saveThemePreference]'s doc comment).
  ///
  /// There is no separate refresh-token key: this app's auth model only
  /// ever stores a single JWT ([_tokenKey]) - [saveToken] has no
  /// refresh-token parameter and none is persisted anywhere.
  static const List<String> _sessionCredentialKeys = [
    _tokenKey,
    _userIdKey,
    _userNameKey,
    _userEmailKey,
    _cachedProfileKey,
  ];

  /// Removes every session/user-identity key from secure storage - the JWT,
  /// user id/name/email, and the cached profile payload
  /// ([_cachedProfileKey], which the older [clearToken] does not touch,
  /// and whose survival past logout is what let a previous user's cached
  /// profile be shown to whoever logs in next on the same device).
  ///
  /// Each key is deleted independently: a failure deleting one key is
  /// logged and does not prevent attempting the rest. This method never
  /// throws - it is a deliberately best-effort operation. Logout must
  /// always be able to proceed to the next step (Isar clearing, in-memory
  /// state reset, navigation) regardless of secure-storage failures; a
  /// failure here is reported via debug logging, not by claiming a
  /// guarantee this method cannot actually make if the underlying secure
  /// storage itself is unavailable.
  Future<void> clearSessionCredentials() async {
    for (final key in _sessionCredentialKeys) {
      try {
        await _storage.delete(key: key);
      } catch (e) {
        debugPrint(
          '⚠️ AuthService: failed to delete secure-storage key "$key": $e',
        );
      }
    }
  }

  /// Save theme preference to secure storage
  Future<void> saveThemePreference(String theme) async {
    try {
      await _storage.write(key: _themePreferenceKey, value: theme);
    } catch (e) {
      // Fail silently - theme preference is not critical
    }
  }

  /// Get theme preference from secure storage
  Future<String?> getThemePreference() async {
    try {
      return await _storage.read(key: _themePreferenceKey);
    } catch (e) {
      return null; // Default to system theme
    }
  }

  /// Legacy **unowned** profile cache write. Retained only so the committed
  /// generated `MockAuthService`s across the test suite keep compiling
  /// without a full mock regen; production writes exclusively through
  /// [writeCachedProfile]. A value stored here carries no owner id and is
  /// therefore rejected by [readCachedProfile].
  Future<void> saveCachedProfile(String profileJson) async {
    try {
      await _storage.write(key: _cachedProfileKey, value: profileJson);
    } catch (e) {
      // Fail silently - cache is not critical
    }
  }

  /// Legacy **unowned** profile cache read. Superseded by [readCachedProfile]
  /// (which enforces ownership); retained for generated-mock ABI
  /// compatibility. Returns the raw stored value, which for a
  /// [writeCachedProfile] entry is the owner envelope, not a bare profile -
  /// callers must use [readCachedProfile] instead.
  Future<String?> getCachedProfile() async {
    try {
      return await _storage.read(key: _cachedProfileKey);
    } catch (e) {
      return null;
    }
  }

  /// Persist [profileJson] for offline access, stamped with the id of the
  /// user it belongs to.
  ///
  /// [ownerUserId] MUST be supplied by the caller from its captured session
  /// context (`SessionRequestContext.epochToken.userId`) - it is never
  /// derived from the profile body, so a forged `cachedForUserId` inside the
  /// server JSON cannot influence ownership. The stored value is an envelope:
  /// `{"cachedForUserId": <owner>, "profile": <the profile JSON>}`.
  ///
  /// Overwrites any previous entry (including a legacy unowned one). This is
  /// deliberately owner-tagged rather than user-keyed: a single key keeps
  /// logout cleanup and storage-format handling simple, and an entry that a
  /// stale write recreates after logout can still only ever be read back by
  /// the same user (see [readCachedProfile]). Best-effort: a storage failure
  /// or an unparseable [profileJson] is swallowed - the cache is not
  /// critical.
  Future<void> writeCachedProfile(String profileJson, int ownerUserId) async {
    try {
      final envelope = jsonEncode({
        _cachedProfileOwnerField: ownerUserId,
        _cachedProfileDataField: jsonDecode(profileJson),
      });
      await _storage.write(key: _cachedProfileKey, value: envelope);
    } catch (e) {
      // Fail silently - cache is not critical
    }
  }

  /// Return the cached profile JSON **only** if the stored envelope is
  /// owner-tagged for [expectedUserId].
  ///
  /// Every other case fails closed (returns `null`): no entry, a legacy
  /// untagged entry, a missing or non-integer `cachedForUserId`, an owner
  /// mismatch, a missing `profile` payload, or any decode error. An offline
  /// fallback must never hand one user another user's profile, so a stale
  /// cross-user entry surfaces as a cache miss, never as data.
  Future<String?> readCachedProfile(int expectedUserId) async {
    try {
      final raw = await _storage.read(key: _cachedProfileKey);
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final owner = decoded[_cachedProfileOwnerField];
      if (owner is! int || owner != expectedUserId) return null;

      final profile = decoded[_cachedProfileDataField];
      if (profile == null) return null;

      return jsonEncode(profile);
    } catch (e) {
      return null;
    }
  }
}
