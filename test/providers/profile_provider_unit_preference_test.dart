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
import 'profile_provider_unit_preference_test.mocks.dart';

/// Task 4: [ProfileProvider.unitPreference] must be available offline, cached
/// in secure storage the same way [ProfileProvider.themeMode] already caches
/// theme preference (see profile_provider_test.dart's `themeMode` group).
void main() {
  late MockProfileRepository mockProfileRepository;
  late MockAuthService mockAuthService;
  late UserSessionEpoch sessionEpoch;

  User user(String unitPreference) => User(
    id: 1,
    name: 'User 1',
    email: 'user1@example.com',
    dateCreated: DateTime.utc(2024, 1, 1),
    unitPreference: unitPreference,
  );

  setUp(() {
    mockProfileRepository = MockProfileRepository();
    mockAuthService = MockAuthService();
    sessionEpoch = UserSessionEpoch();

    when(mockAuthService.getThemePreference()).thenAnswer((_) async => null);
    when(mockAuthService.saveThemePreference(any)).thenAnswer((_) async {});
    when(mockAuthService.saveUnitPreference(any)).thenAnswer((_) async {});
  });

  test(
    'offline cold start with cached Imperial and no user reports Imperial',
    () async {
      when(
        mockAuthService.getUnitPreference(),
      ).thenAnswer((_) async => 'Imperial');

      final provider = ProfileProvider(
        mockProfileRepository,
        mockAuthService,
        sessionEpoch,
      );
      await Future<void>.delayed(Duration.zero);

      expect(provider.unitPreference, 'Imperial');
    },
  );

  test('no user and no cache reports Metric', () async {
    when(mockAuthService.getUnitPreference()).thenAnswer((_) async => null);

    final provider = ProfileProvider(
      mockProfileRepository,
      mockAuthService,
      sessionEpoch,
    );
    await Future<void>.delayed(Duration.zero);

    expect(provider.unitPreference, 'Metric');
  });

  test(
    'loadUserProfile returning a user with Metric writes the cache',
    () async {
      when(mockAuthService.getUnitPreference()).thenAnswer((_) async => null);
      sessionEpoch.activate(1);
      when(
        mockProfileRepository.getProfile(),
      ).thenAnswer((_) async => user('Metric'));

      final provider = ProfileProvider(
        mockProfileRepository,
        mockAuthService,
        sessionEpoch,
      );
      await Future<void>.delayed(Duration.zero);

      await provider.loadUserProfile();

      expect(provider.unitPreference, 'Metric');
      verify(mockAuthService.saveUnitPreference('Metric')).called(1);
    },
  );

  test('toggling the preference writes the cache', () async {
    when(mockAuthService.getUnitPreference()).thenAnswer((_) async => null);
    sessionEpoch.activate(1);
    when(
      mockProfileRepository.getProfile(),
    ).thenAnswer((_) async => user('Metric'));
    when(
      mockProfileRepository.updateProfile(any),
    ).thenAnswer((_) async => user('Imperial'));

    final provider = ProfileProvider(
      mockProfileRepository,
      mockAuthService,
      sessionEpoch,
    );
    await Future<void>.delayed(Duration.zero);
    await provider.loadUserProfile();

    await provider.toggleUnitPreference();

    expect(provider.unitPreference, 'Imperial');
    verify(mockAuthService.saveUnitPreference('Imperial')).called(1);
    final captured =
        verify(mockProfileRepository.updateProfile(captureAny)).captured.single
            as ProfileUpdateRequest;
    expect(captured.unitPreference, 'Imperial');
  });
}
