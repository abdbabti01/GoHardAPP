import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/user.dart';
import 'package:go_hard_app/data/repositories/profile_repository.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/providers/auth_provider.dart';
import 'package:go_hard_app/providers/friends_provider.dart';
import 'package:go_hard_app/providers/messages_provider.dart';
import 'package:go_hard_app/providers/profile_provider.dart';
import 'package:go_hard_app/ui/screens/me/me_screen.dart';
import 'package:go_hard_app/ui/widgets/common/user_avatar.dart';

@GenerateMocks([ProfileRepository, AuthService])
import 'me_screen_test.mocks.dart';

class _FakeFriends extends ChangeNotifier implements FriendsProvider {
  @override
  int get pendingRequestCount => 0;
  @override
  Future<void> loadIncomingRequests() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMessages extends ChangeNotifier implements MessagesProvider {
  @override
  int get totalUnreadCount => 0;
  @override
  Future<void> loadUnreadCount() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  String? get currentUserName => 'Bob Roberts';
  @override
  String? get currentUserEmail => 'bob@example.com';
  @override
  String? get currentUsername => 'bob01';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late MockProfileRepository repo;
  late MockAuthService authService;
  late UserSessionEpoch epoch;
  late ProfileProvider profile;

  User buildUser({String? photoUrl}) => User(
    id: 7,
    name: 'Bob Roberts',
    username: 'bob01',
    email: 'bob@example.com',
    dateCreated: DateTime.utc(2024, 1, 1),
    unitPreference: 'Metric',
    profilePhotoUrl: photoUrl,
  );

  setUp(() {
    repo = MockProfileRepository();
    authService = MockAuthService();
    epoch = UserSessionEpoch()..activate(7);
    when(authService.getThemePreference()).thenAnswer((_) async => null);
    when(authService.saveThemePreference(any)).thenAnswer((_) async {});
    profile = ProfileProvider(repo, authService, epoch);
  });

  Widget host() => MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileProvider>.value(value: profile),
      ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth()),
      ChangeNotifierProvider<FriendsProvider>.value(value: _FakeFriends()),
      ChangeNotifierProvider<MessagesProvider>.value(value: _FakeMessages()),
    ],
    child: const MaterialApp(home: Scaffold(body: MeScreen())),
  );

  UserAvatar headerAvatar(WidgetTester tester) => tester.widget<UserAvatar>(
    find.descendant(of: find.byType(Row), matching: find.byType(UserAvatar)),
  );

  testWidgets('on first open (fresh provider) it loads the profile and renders '
      'the server photo URL', (tester) async {
    when(repo.getProfile()).thenAnswer(
      (_) async => buildUser(photoUrl: '/uploads/profiles/user_7.jpg'),
    );

    await tester.pumpWidget(host());
    await tester.pump(); // post-frame load
    await tester.pump(); // resolve

    expect(headerAvatar(tester).photoUrl, '/uploads/profiles/user_7.jpg');
  });

  testWidgets('a successful photo upload publishes the new server URL to the '
      'Profile header immediately', (tester) async {
    when(repo.getProfile()).thenAnswer((_) async => buildUser());

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    // No photo yet -> avatar falls back (no network image URL).
    expect(headerAvatar(tester).photoUrl, isNull);

    // Upload succeeds; the provider's post-upload reload returns the new URL.
    when(
      repo.uploadProfilePhoto(any),
    ).thenAnswer((_) async => '/uploads/profiles/user_7_new.jpg');
    when(repo.getProfile()).thenAnswer(
      (_) async => buildUser(photoUrl: '/uploads/profiles/user_7_new.jpg'),
    );

    final ok = await profile.uploadProfilePhoto(File('new.jpg'));
    expect(ok, isTrue);
    await tester.pump();

    expect(headerAvatar(tester).photoUrl, '/uploads/profiles/user_7_new.jpg');
  });

  testWidgets('a profile response for a superseded session never reaches the '
      'header', (tester) async {
    final gate = Completer<User>();
    when(repo.getProfile()).thenAnswer((_) => gate.future);

    await tester.pumpWidget(host());
    await tester.pump(); // initState -> loadUserProfile captures user 7's epoch

    // A different account becomes current before the load resolves.
    epoch.activate(99);
    gate.complete(buildUser(photoUrl: '/uploads/profiles/OLD_ACCOUNT.jpg'));
    await tester.pump();
    await tester.pump();

    expect(headerAvatar(tester).photoUrl, isNull);
    expect(profile.currentUser, isNull);
  });
}
