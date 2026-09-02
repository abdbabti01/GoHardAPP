import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/user.dart';
import '../models/profile_update_request.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';

/// Repository for profile operations with offline caching.
///
/// ## Session binding
///
/// Every authenticated operation below captures exactly one
/// [SessionRequestContext] via [_sessionCoordinator] at operation entry -
/// before any other `await`, including before the profile photo file is
/// read - and passes that SAME context to each of its [ApiService] calls, so
/// the request carries the JWT pinned at capture time (never the live
/// secure-storage token) and the generation-scoped `CancelToken` that a
/// logout aborts. Live credentials are never reread after an operation
/// starts.
///
/// The photo upload previously built its own bare [Dio] instance with a
/// manually assembled `Authorization` header, bypassing [ApiService]'s
/// interceptor pipeline entirely (no session-epoch recheck, no shared
/// `CancelToken`, no `onUnauthorized` 401 handling). It now goes through the
/// same [ApiService.post] every other call uses - Dio already serializes a
/// [FormData] body as `multipart/form-data`, so no new [ApiService] method
/// was needed.
///
/// A `null` capture (logged out, or the session changed while the JWT read
/// was in flight) throws [SessionStaleException] for **every** method,
/// including [getProfile]: there is no verified session owner, so no
/// authenticated cached profile may be returned. This matches the sibling
/// session-bound repositories' logged-out convention.
///
/// ## Cache ownership
///
/// The offline profile cache is **owner-tagged** by
/// `AuthService.writeCachedProfile` / `readCachedProfile`: every entry
/// carries the `userId` from the operation's captured
/// [SessionRequestContext] (never a value parsed from the response body),
/// and a read is satisfied only for a matching owner. This closes the
/// response-to-write TOCTOU by design rather than by timing:
///
/// - [getProfile] still revalidates [UserSessionEpoch.isCurrent] after the
///   response lands, so a response that outlived its session neither writes
///   the cache nor publishes.
/// - Even if a write nonetheless lands after the session ends (the
///   secure-storage write is async), it is stamped for the original user, so
///   the next user's [getProfile] fallback gets a cache *miss*, never
///   another user's profile. Such a write can recreate an
///   original-user-owned envelope at rest after logout has already deleted
///   the key; this orphan is owner-gated (unreadable by anyone but the
///   now-logged-out original user) and is cleared again by the next logout,
///   so it is accepted rather than chased with a post-write delete.
/// - Every fallback read passes `context.epochToken.userId`, so a stale
///   cross-user entry is invisible.
///
/// `AuthService.clearSessionCredentials` still deletes the cache key on every
/// logout as defense-in-depth.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures:
/// [getProfile] rethrows both instead of folding them into its cache
/// fallback, and the other methods let them propagate untouched.
/// `ProfileProvider`'s own session-epoch guards then discard them without
/// publishing.
class ProfileRepository {
  final ApiService _apiService;
  final AuthService _authService;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// `AuthProvider`, `GoalsRepository`, etc. (see main.dart). Only
  /// `AuthProvider` calls activate()/invalidate(); this repository only
  /// reads it, via [UserSessionEpoch.isCurrent], for the post-response
  /// currency check [getProfile] runs before writing the offline cache.
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext]
  /// (pinned JWT + generation-scoped `CancelToken`) for every session-bound
  /// HTTP call. The SAME instance handed to every other session-bound
  /// repository; never constructed privately.
  final SessionRequestCoordinator _sessionCoordinator;

  final ConnectivityService? _connectivity;

  ProfileRepository(
    this._apiService,
    this._authService,
    this._sessionEpoch,
    this._sessionCoordinator, [
    this._connectivity,
  ]);

  /// Captures the session context for one operation, or `null` if there is
  /// no authenticated session to act for.
  Future<SessionRequestContext?> _capture() =>
      _sessionCoordinator.captureContext();

  /// Get current user's profile with stats.
  ///
  /// Offline-first: on an API/transport failure or while offline it falls
  /// back to the cached profile - but only the entry owned by the user
  /// captured at entry. A logged-out call (null capture) throws
  /// [SessionStaleException] and returns no cached data.
  Future<User> getProfile() async {
    final context = await _capture();
    if (context == null) {
      // No verified session owner - never hand back an authenticated cached
      // profile. Matches the sibling repositories' logged-out convention.
      throw const SessionStaleException();
    }

    final ownerUserId = context.epochToken.userId;
    final isOnline = _connectivity?.isOnline ?? true;

    if (isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.profile,
          sessionContext: context,
        );
        final user = User.fromJson(data);

        // Post-response currency check: a response that outlived its session
        // must not begin a cache write and must not publish.
        if (!_sessionEpoch.isCurrent(context.epochToken)) {
          throw const SessionStaleException();
        }

        // Cache for offline use, stamped for the captured user.
        await _cacheProfile(user, ownerUserId);

        return user;
      } on SessionStaleException {
        rethrow;
      } on RequestCancelledException {
        rethrow;
      } catch (e) {
        debugPrint('⚠️ API failed, falling back to cached profile: $e');
        return _getCachedProfile(ownerUserId);
      }
    } else {
      debugPrint('📴 Offline - returning cached profile');
      return _getCachedProfile(ownerUserId);
    }
  }

  /// Cache [user] for [ownerUserId] - the id captured in the operation's
  /// session context, never read from [user]. Owner-tagging means a write
  /// that lands after this session ends can still only ever be read back by
  /// the same user; another user's [getProfile] fallback gets a cache miss.
  Future<void> _cacheProfile(User user, int ownerUserId) async {
    try {
      final jsonString = jsonEncode(user.toJson());
      await _authService.writeCachedProfile(jsonString, ownerUserId);
      debugPrint('✅ Profile cached to local storage');
    } catch (e) {
      debugPrint('⚠️ Failed to cache profile: $e');
    }
  }

  /// Read the cached profile owned by [expectedUserId]. A legacy/untagged
  /// entry, a wrong-owner entry, or malformed metadata is treated as absent.
  Future<User> _getCachedProfile(int expectedUserId) async {
    try {
      final jsonString = await _authService.readCachedProfile(expectedUserId);

      if (jsonString == null) {
        throw Exception('No cached profile available');
      }

      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      return User.fromJson(jsonData);
    } catch (e) {
      debugPrint('⚠️ Failed to load cached profile: $e');
      throw Exception('No profile available offline');
    }
  }

  /// Update current user's profile
  Future<User> updateProfile(ProfileUpdateRequest request) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.put<Map<String, dynamic>>(
      ApiConfig.profile,
      data: request.toJson(),
      sessionContext: context,
    );
    return User.fromJson(data);
  }

  /// Upload profile photo
  /// Returns the photo URL on success
  Future<String> uploadProfilePhoto(File imageFile) async {
    // Capture the session context BEFORE the file is read: a logged-out or
    // just-invalidated call must send no HTTP and touch no file.
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    // Multipart body. The API binds this to `IFormFile photo`
    // (ProfileController.UploadPhoto), so the field name must stay `photo`.
    final formData = FormData.fromMap({
      'photo': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });

    // Same shared ApiService every other call uses: Dio serializes the
    // FormData as multipart/form-data, the request carries the pinned JWT
    // and generation CancelToken from [context], and the interceptor's 401
    // handling / staleness rejection apply exactly as for a JSON call.
    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.profilePhoto,
      data: formData,
      sessionContext: context,
    );

    final photoUrl = data['photoUrl'];
    if (photoUrl == null) {
      throw Exception('Failed to upload photo - no URL returned');
    }
    return photoUrl as String;
  }

  /// Delete profile photo
  Future<bool> deleteProfilePhoto() async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    return _apiService.delete(ApiConfig.profilePhoto, sessionContext: context);
  }
}
