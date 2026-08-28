import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/profile_update_request.dart';
import 'package:go_hard_app/data/models/user.dart';
import 'package:go_hard_app/data/repositories/profile_repository.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/providers/profile_provider.dart';

@GenerateMocks([ProfileRepository, AuthService, ConnectivityService])
import 'profile_provider_test.mocks.dart';

/// Logout PR 2A coverage: proves ProfileProvider drops any response that
/// resolves after the session that requested it has ended - logout, or a
/// different user logging in - instead of writing stale data into a shared
/// provider instance the next session also uses.
void main() {
  late MockProfileRepository mockProfileRepository;
  late MockAuthService mockAuthService;
  late UserSessionEpoch sessionEpoch;
  late ProfileProvider provider;

  User user(int id) => User(
    id: id,
    name: 'User $id',
    email: 'user$id@example.com',
    dateCreated: DateTime.utc(2024, 1, 1),
  );

  setUp(() {
    mockProfileRepository = MockProfileRepository();
    mockAuthService = MockAuthService();
    sessionEpoch = UserSessionEpoch();

    when(mockAuthService.getThemePreference()).thenAnswer((_) async => null);
    when(mockAuthService.saveThemePreference(any)).thenAnswer((_) async {});

    provider = ProfileProvider(
      mockProfileRepository,
      mockAuthService,
      sessionEpoch,
    );
  });

  group('loadUserProfile', () {
    test('with no active session, never calls the repository', () async {
      await provider.loadUserProfile();

      verifyNever(mockProfileRepository.getProfile());
      expect(provider.currentUser, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('a response that resolves after logout is dropped: currentUser, '
        'errorMessage and isLoading are left untouched', () async {
      sessionEpoch.activate(1);
      final completer = Completer<User>();
      when(
        mockProfileRepository.getProfile(),
      ).thenAnswer((_) => completer.future);

      final future = provider.loadUserProfile();
      expect(provider.isLoading, isTrue);

      // Logout happens while the request is still in flight.
      sessionEpoch.invalidate();
      completer.complete(user(1));
      await future;

      expect(provider.currentUser, isNull);
      expect(provider.errorMessage, isNull);
      expect(
        provider.isLoading,
        isTrue,
        reason:
            'stale completion must not touch isLoading either - '
            'clear() (called during logout cleanup) owns resetting it',
      );
    });

    test('a response that resolves after a DIFFERENT user has logged in is '
        'dropped and does not corrupt the new user\'s state', () async {
      sessionEpoch.activate(1);
      final completerA = Completer<User>();
      when(
        mockProfileRepository.getProfile(),
      ).thenAnswer((_) => completerA.future);

      final futureA = provider.loadUserProfile();

      // User A logs out, User B logs in - all before A's response lands.
      sessionEpoch.invalidate();
      sessionEpoch.activate(2);

      completerA.complete(user(1));
      await futureA;

      expect(
        provider.currentUser,
        isNull,
        reason: "User A's stale profile must never become User B's data",
      );
    });

    test(
      'an error that resolves after logout does not set errorMessage',
      () async {
        sessionEpoch.activate(1);
        final completer = Completer<User>();
        when(
          mockProfileRepository.getProfile(),
        ).thenAnswer((_) => completer.future);

        final future = provider.loadUserProfile();
        sessionEpoch.invalidate();
        completer.completeError(Exception('boom'));
        await future;

        expect(provider.errorMessage, isNull);
      },
    );

    test('a same-session response is applied normally', () async {
      sessionEpoch.activate(1);
      when(mockProfileRepository.getProfile()).thenAnswer((_) async => user(1));

      await provider.loadUserProfile();

      expect(provider.currentUser?.id, 1);
      expect(provider.isLoading, isFalse);
    });
  });

  group('connectivity-restored callback', () {
    late StreamController<bool> connectivityController;
    late MockConnectivityService mockConnectivity;

    setUp(() {
      connectivityController = StreamController<bool>.broadcast();
      mockConnectivity = MockConnectivityService();
      when(
        mockConnectivity.connectivityStream,
      ).thenAnswer((_) => connectivityController.stream);
    });

    tearDown(() async {
      await connectivityController.close();
    });

    test('while logged out, a connectivity-restored event does not call the '
        'repository or alter loading/error/data state', () async {
      // No sessionEpoch.activate() - simulates a connectivity flap
      // during the logged-out gap between two sessions.
      final loggedOutProvider = ProfileProvider(
        mockProfileRepository,
        mockAuthService,
        sessionEpoch,
        mockConnectivity,
      );

      connectivityController.add(true);
      await pumpEventQueue();

      verifyNever(mockProfileRepository.getProfile());
      expect(loggedOutProvider.currentUser, isNull);
      expect(loggedOutProvider.errorMessage, isNull);
      expect(loggedOutProvider.isLoading, isFalse);
    });

    test('while authenticated with an already-loaded profile, a '
        'connectivity-restored event triggers the intended refresh', () async {
      sessionEpoch.activate(1);
      when(mockProfileRepository.getProfile()).thenAnswer((_) async => user(1));

      final onlineProvider = ProfileProvider(
        mockProfileRepository,
        mockAuthService,
        sessionEpoch,
        mockConnectivity,
      );
      // The listener only refreshes when a profile is already loaded
      // (see the `_currentUser != null` check in the source) - establish
      // that first, matching how the app actually reaches this state.
      await onlineProvider.loadUserProfile();
      verify(mockProfileRepository.getProfile()).called(1);

      connectivityController.add(true);
      await pumpEventQueue();

      verify(mockProfileRepository.getProfile()).called(1);
    });

    test('if the session becomes invalid while the connectivity-triggered '
        'refresh is in flight, its completion is discarded', () async {
      sessionEpoch.activate(1);
      when(mockProfileRepository.getProfile()).thenAnswer((_) async => user(1));

      final onlineProvider = ProfileProvider(
        mockProfileRepository,
        mockAuthService,
        sessionEpoch,
        mockConnectivity,
      );
      await onlineProvider.loadUserProfile();
      expect(onlineProvider.currentUser?.id, 1);

      final refreshCompleter = Completer<User>();
      when(
        mockProfileRepository.getProfile(),
      ).thenAnswer((_) => refreshCompleter.future);

      connectivityController.add(true);
      await pumpEventQueue();
      expect(
        onlineProvider.isLoading,
        isTrue,
        reason: 'the connectivity-triggered refresh must have started',
      );

      sessionEpoch.invalidate();
      refreshCompleter.complete(user(1));
      await pumpEventQueue();

      expect(
        onlineProvider.currentUser?.id,
        1,
        reason: 'the stale refresh must not overwrite the prior state',
      );
    });
  });

  group('updateProfile', () {
    test('with no active session, never calls the repository', () async {
      final result = await provider.updateProfile(ProfileUpdateRequest());

      expect(result, isFalse);
      verifyNever(mockProfileRepository.updateProfile(any));
    });

    test('a response that resolves after logout returns false and does not '
        'set currentUser', () async {
      sessionEpoch.activate(1);
      final completer = Completer<User>();
      when(
        mockProfileRepository.updateProfile(any),
      ).thenAnswer((_) => completer.future);

      final future = provider.updateProfile(
        ProfileUpdateRequest(name: 'New Name'),
      );
      sessionEpoch.invalidate();
      completer.complete(user(1));

      expect(await future, isFalse);
      expect(provider.currentUser, isNull);
    });

    test(
      'when the response includes a themePreference update, a logout '
      'during the trailing saveThemePreference() await still returns '
      'false and does not flip isUpdating/notify for the stale session',
      () async {
        sessionEpoch.activate(1);
        final updateCompleter = Completer<User>();
        when(
          mockProfileRepository.updateProfile(any),
        ).thenAnswer((_) => updateCompleter.future);
        final saveThemeCompleter = Completer<void>();
        when(
          mockAuthService.saveThemePreference(any),
        ).thenAnswer((_) => saveThemeCompleter.future);

        final future = provider.updateProfile(
          ProfileUpdateRequest(name: 'New Name'),
        );

        // Resolve the first await while the session is still current, and
        // pump the event loop so execution actually advances past the
        // first isCurrent() check and into the second await
        // (saveThemePreference) - only THEN is the session invalidated,
        // isolating the check this test targets from the one already
        // covered by the "resolves after logout" test above.
        updateCompleter.complete(
          User(
            id: 1,
            name: 'User 1',
            email: 'user1@example.com',
            dateCreated: DateTime.utc(2024, 1, 1),
            themePreference: 'dark',
          ),
        );
        await Future.delayed(Duration.zero);

        sessionEpoch.invalidate();
        saveThemeCompleter.complete();

        expect(await future, isFalse);
        expect(
          provider.isUpdating,
          isTrue,
          reason:
              'a stale completion must not touch isUpdating either - '
              'clear() (called during logout cleanup) owns resetting it',
        );
      },
    );
  });

  group('uploadProfilePhoto / deleteProfilePhoto', () {
    test('uploadProfilePhoto dropped after logout does not call the nested '
        'reload and returns false', () async {
      sessionEpoch.activate(1);
      final completer = Completer<void>();
      when(
        mockProfileRepository.uploadProfilePhoto(any),
      ).thenAnswer((_) => completer.future.then((_) => 'https://x/photo.png'));

      final future = provider.uploadProfilePhoto(File('fake.png'));
      sessionEpoch.invalidate();
      completer.complete();

      expect(await future, isFalse);
      verifyNever(mockProfileRepository.getProfile());
    });

    test(
      'deleteProfilePhoto with no active session never calls the repository',
      () async {
        final result = await provider.deleteProfilePhoto();

        expect(result, isFalse);
        verifyNever(mockProfileRepository.deleteProfilePhoto());
      },
    );
  });
}
