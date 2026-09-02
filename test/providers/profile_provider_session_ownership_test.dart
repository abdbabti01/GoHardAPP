import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/user.dart';
import 'package:go_hard_app/data/repositories/profile_repository.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';
import 'package:go_hard_app/providers/profile_provider.dart';

@GenerateMocks([ProfileRepository, AuthService, ConnectivityService])
import 'profile_provider_session_ownership_test.mocks.dart';

/// Regression cover for the profile-photo session-binding PR: now that
/// [ProfileRepository] throws [SessionStaleException] / [RequestCancelledException]
/// as ordinary lifecycle outcomes of a session ending mid-upload,
/// [ProfileProvider]'s existing token guards must keep dropping those
/// completions silently - never surfacing them as an error, never clearing a
/// newer session's loading flags, never notifying listeners for a dead
/// session. These tests do not change the provider; they pin its behaviour
/// against the new repository exception surface.
void main() {
  late MockProfileRepository repo;
  late MockAuthService authService;
  late UserSessionEpoch epoch;
  late ProfileProvider provider;

  User user(int id) => User(
    id: id,
    name: 'User $id',
    email: 'user$id@example.com',
    dateCreated: DateTime.utc(2024, 1, 1),
  );

  setUp(() {
    repo = MockProfileRepository();
    authService = MockAuthService();
    epoch = UserSessionEpoch();
    when(authService.getThemePreference()).thenAnswer((_) async => null);
    when(authService.saveThemePreference(any)).thenAnswer((_) async {});
    provider = ProfileProvider(repo, authService, epoch);
  });

  group('stale upload completion after logout', () {
    test('a slow upload that completes after logout cannot update the '
        'provider and is not shown as an error', () async {
      epoch.activate(1);
      final gate = Completer<String>();
      when(repo.uploadProfilePhoto(any)).thenAnswer((_) => gate.future);

      final future = provider.uploadProfilePhoto(File('a.png'));
      expect(provider.isUploadingPhoto, isTrue);

      epoch.invalidate();
      gate.complete('/uploads/x.jpg');

      expect(await future, isFalse);
      expect(provider.currentUser, isNull);
      expect(provider.errorMessage, isNull);
      verifyNever(repo.getProfile());
    });

    test('a repository SessionStaleException after logout is dropped, not '
        'rendered as a failure', () async {
      epoch.activate(1);
      final gate = Completer<String>();
      when(repo.uploadProfilePhoto(any)).thenAnswer((_) => gate.future);

      final future = provider.uploadProfilePhoto(File('a.png'));
      epoch.invalidate();
      gate.completeError(const SessionStaleException());

      expect(await future, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('a repository RequestCancelledException after logout is dropped, '
        'not rendered as a failure', () async {
      epoch.activate(1);
      final gate = Completer<String>();
      when(repo.uploadProfilePhoto(any)).thenAnswer((_) => gate.future);

      final future = provider.uploadProfilePhoto(File('a.png'));
      epoch.invalidate();
      gate.completeError(const RequestCancelledException());

      expect(await future, isFalse);
      expect(provider.errorMessage, isNull);
    });
  });

  group('stale upload completion after a DIFFERENT user logs in', () {
    test('the completion cannot publish success, data, an error, or clear '
        "user B's newer uploading state", () async {
      epoch.activate(1);
      final gateA = Completer<String>();
      when(repo.uploadProfilePhoto(any)).thenAnswer((_) => gateA.future);
      // B's own in-flight work never resolves during this test.
      when(repo.getProfile()).thenAnswer((_) => Completer<User>().future);

      final futureA = provider.uploadProfilePhoto(File('a.png'));

      // A logs out; B logs in and starts their own upload.
      epoch.invalidate();
      epoch.activate(2);
      when(
        repo.uploadProfilePhoto(any),
      ).thenAnswer((_) => Completer<String>().future);
      provider.uploadProfilePhoto(File('b.png'));
      expect(provider.isUploadingPhoto, isTrue);

      // A's original call now resolves.
      gateA.complete('/uploads/a.jpg');
      expect(await futureA, isFalse);

      expect(provider.currentUser, isNull);
      expect(provider.errorMessage, isNull);
      expect(
        provider.isUploadingPhoto,
        isTrue,
        reason: "A's stale completion must not clear B's uploading flag",
      );
    });

    test(
      "A's stale error completion cannot set user B's errorMessage",
      () async {
        epoch.activate(1);
        final gate = Completer<String>();
        when(repo.uploadProfilePhoto(any)).thenAnswer((_) => gate.future);

        final futureA = provider.uploadProfilePhoto(File('a.png'));
        epoch.invalidate();
        epoch.activate(2);

        gate.completeError(Exception('A boom'));

        expect(await futureA, isFalse);
        expect(provider.errorMessage, isNull);
      },
    );
  });

  group('deleteProfilePhoto has the same guards', () {
    test(
      'a delete that completes after logout cannot update the provider '
      'and a repository SessionStaleException is not shown as an error',
      () async {
        epoch.activate(1);
        final gate = Completer<bool>();
        when(repo.deleteProfilePhoto()).thenAnswer((_) => gate.future);

        final future = provider.deleteProfilePhoto();
        expect(provider.isUploadingPhoto, isTrue);

        epoch.invalidate();
        gate.completeError(const SessionStaleException());

        expect(await future, isFalse);
        expect(provider.errorMessage, isNull);
        verifyNever(repo.getProfile());
      },
    );
  });

  group('nested reload stays guarded', () {
    test('upload succeeds, then logout before the nested loadUserProfile: '
        'the reloaded profile is not applied', () async {
      epoch.activate(1);
      when(
        repo.uploadProfilePhoto(any),
      ).thenAnswer((_) async => '/uploads/x.jpg');
      final reloadGate = Completer<User>();
      final getProfileEntered = Completer<void>();
      when(repo.getProfile()).thenAnswer((_) {
        if (!getProfileEntered.isCompleted) getProfileEntered.complete();
        return reloadGate.future;
      });

      final future = provider.uploadProfilePhoto(File('a.png'));
      // Wait until the nested loadUserProfile has actually reached
      // repo.getProfile() - deterministic, no timing primitive.
      await getProfileEntered.future;

      epoch.invalidate();
      reloadGate.complete(user(1));

      expect(await future, isFalse);
      expect(provider.currentUser, isNull);
    });
  });

  group('listener notifications', () {
    test(
      'a stale upload completion after logout triggers no notifyListeners',
      () async {
        epoch.activate(1);
        final gate = Completer<String>();
        when(repo.uploadProfilePhoto(any)).thenAnswer((_) => gate.future);

        final future = provider.uploadProfilePhoto(File('a.png'));

        var notifications = 0;
        provider.addListener(() => notifications++);

        epoch.invalidate();
        gate.complete('/uploads/x.jpg');
        await future;

        expect(
          notifications,
          0,
          reason: 'no listener callback may fire for a dead session',
        );
      },
    );
  });

  group('happy path still works', () {
    test('a same-session upload reloads and reports success', () async {
      epoch.activate(1);
      when(
        repo.uploadProfilePhoto(any),
      ).thenAnswer((_) async => '/uploads/x.jpg');
      when(repo.getProfile()).thenAnswer((_) async => user(1));

      final ok = await provider.uploadProfilePhoto(File('a.png'));

      expect(ok, isTrue);
      expect(provider.currentUser?.id, 1);
      expect(provider.isUploadingPhoto, isFalse);
      expect(provider.errorMessage, isNull);
    });
  });
}
