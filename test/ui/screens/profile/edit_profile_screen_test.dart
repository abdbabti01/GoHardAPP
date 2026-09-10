import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/profile_update_request.dart';
import 'package:go_hard_app/data/models/user.dart';
import 'package:go_hard_app/data/repositories/profile_repository.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/providers/auth_provider.dart';
import 'package:go_hard_app/providers/profile_provider.dart';
import 'package:go_hard_app/routes/route_names.dart';
import 'package:go_hard_app/ui/screens/profile/edit_profile_screen.dart';
import 'package:go_hard_app/ui/widgets/common/user_avatar.dart';

@GenerateMocks([ProfileRepository, AuthService, ConnectivityService])
import 'edit_profile_screen_test.mocks.dart';

/// Minimal stand-in so `EditProfileScreen` can `context.read<AuthProvider>()`
/// without wiring the full auth graph. Only [applyUpdatedUsername] is exercised.
class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  final List<String> appliedUsernames = [];

  @override
  UserSessionToken? captureSessionToken() => null;

  @override
  void applyUpdatedUsername(String username, Object? token) =>
      appliedUsernames.add(username);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockProfileRepository repo;
  late MockAuthService authService;
  late UserSessionEpoch epoch;
  late ProfileProvider provider;
  late _FakeAuthProvider auth;
  late Directory tmpDir;

  User buildUser({
    String name = 'Bob Roberts',
    String username = 'bob01',
    double? height = 180,
    String? photoUrl,
    DateTime? dateOfBirth,
  }) => User(
    id: 7,
    name: name,
    username: username,
    email: 'bob@example.com',
    dateCreated: DateTime.utc(2024, 1, 1),
    height: height,
    bio: 'lifter',
    experienceLevel: 'Intermediate',
    primaryGoal: 'Strength',
    unitPreference: 'Metric',
    profilePhotoUrl: photoUrl,
    dateOfBirth: dateOfBirth,
  );

  File writeJpeg(String name) => File('${tmpDir.path}/$name')..writeAsBytesSync(
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(256, 0)]),
  );

  File writeHeic(String name) => File('${tmpDir.path}/$name')..writeAsBytesSync(
    Uint8List.fromList([
      0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, //
      0x68, 0x65, 0x69, 0x63, 0, 0, 0, 0, ...List.filled(64, 0),
    ]),
  );

  /// Route the image_picker platform channel to [path] (or null to cancel).
  void mockPicker(String? path) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (call) async => path,
        );
  }

  setUp(() {
    repo = MockProfileRepository();
    authService = MockAuthService();
    epoch = UserSessionEpoch()..activate(7);
    auth = _FakeAuthProvider();
    tmpDir = Directory.systemTemp.createTempSync('edit_profile_test');

    when(authService.getThemePreference()).thenAnswer((_) async => null);
    when(authService.saveThemePreference(any)).thenAnswer((_) async {});

    provider = ProfileProvider(repo, authService, epoch);
  });

  tearDown(() {
    mockPicker(null);
    // On Windows a FileImage can still hold the picked file open; best effort.
    try {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget host({bool pushed = false}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileProvider>.value(value: provider),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
    ],
    child: MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name == RouteNames.bodyMetrics) {
          return MaterialPageRoute(
            builder:
                (_) => Scaffold(
                  appBar: AppBar(title: const Text('Body Metrics')),
                  body: const Text('BODY METRICS SCREEN'),
                ),
          );
        }
        return MaterialPageRoute(builder: (_) => const EditProfileScreen());
      },
      home:
          pushed
              ? Builder(
                builder:
                    (context) => Scaffold(
                      body: Center(
                        child: ElevatedButton(
                          onPressed:
                              () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const EditProfileScreen(),
                                ),
                              ),
                          child: const Text('open'),
                        ),
                      ),
                    ),
              )
              : const EditProfileScreen(),
    ),
  );

  Future<void> pumpLoaded(
    WidgetTester tester, {
    User? user,
    bool pushed = false,
  }) async {
    when(repo.getProfile()).thenAnswer((_) async => user ?? buildUser());
    await tester.pumpWidget(host(pushed: pushed));
    if (pushed) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }
    await tester.pump(); // post-frame load
    await tester.pump(); // resolve
  }

  Future<void> pickPhoto(WidgetTester tester, File file) async {
    mockPicker(file.path);
    await tester.tap(find.byTooltip('Change profile photo'));
    await tester.pumpAndSettle();
    expect(find.text('Take a Photo'), findsOneWidget, reason: 'picker sheet');
    // _pickImage does real dart:io reads (image-format sniff), which only
    // complete on the real event loop - trigger it inside runAsync so its
    // await chain is not stuck in FakeAsync.
    await tester.runAsync(() async {
      await tester.tap(find.text('Take a Photo'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  // ---- existing coverage -------------------------------------------------

  testWidgets('shows a loader until the profile arrives, then hydrates the '
      'name field from the loaded user', (tester) async {
    final completer = Completer<User>();
    when(repo.getProfile()).thenAnswer((_) => completer.future);

    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);

    completer.complete(buildUser(name: 'Bob Roberts'));
    await tester.pump();
    await tester.pump();

    final nameField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Name'),
    );
    expect(nameField.controller?.text, 'Bob Roberts');
  });

  testWidgets('height is read-only (not a text field) and links out to Body '
      'Metrics, then refreshes the profile on return', (tester) async {
    var loads = 0;
    when(repo.getProfile()).thenAnswer((_) async {
      loads++;
      return buildUser(height: 180);
    });

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'Height'), findsNothing);
    expect(find.text('180 cm'), findsOneWidget);
    expect(loads, 1);

    await tester.ensureVisible(find.text('Manage measurements'));
    await tester.tap(find.text('Manage measurements'));
    await tester.pumpAndSettle();
    expect(find.text('BODY METRICS SCREEN'), findsOneWidget);

    // Back to Edit Profile -> it pulls the authoritative profile again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('Save sends name/username(diff only)/fitness but never height or '
      'activityLevel', (tester) async {
    ProfileUpdateRequest? sent;
    when(repo.updateProfile(any)).thenAnswer((invocation) async {
      sent = invocation.positionalArguments.first as ProfileUpdateRequest;
      return buildUser();
    });
    await pumpLoaded(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'New Name',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    await tester.pump();

    expect(sent, isNotNull);
    final json = sent!.toJson();
    expect(json['name'], 'New Name');
    expect(json.containsKey('username'), isFalse); // unchanged -> omitted
    expect(json.containsKey('height'), isFalse);
    expect(json.containsKey('activityLevel'), isFalse);
  });

  testWidgets('renders the saved server photo (no device file path) once '
      'loaded', (tester) async {
    await pumpLoaded(
      tester,
      user: buildUser(photoUrl: '/uploads/profiles/user_7_x.jpg'),
    );

    final avatar = tester.widget<UserAvatar>(
      find.descendant(
        of: find.byType(Stack),
        matching: find.byType(UserAvatar),
      ),
    );
    expect(avatar.photoUrl, '/uploads/profiles/user_7_x.jpg');

    final fileBackedAvatars = tester
        .widgetList<CircleAvatar>(find.byType(CircleAvatar))
        .where((a) => a.backgroundImage is FileImage);
    expect(fileBackedAvatars, isEmpty);
  });

  // ---- Save / Cancel photo semantics -----------------------------------

  testWidgets('picking a photo stages a draft but uploads NOTHING until Save', (
    tester,
  ) async {
    await pumpLoaded(tester);
    await pickPhoto(tester, writeJpeg('pick.jpg'));

    expect(find.text('New photo - not saved yet'), findsOneWidget);
    verifyNever(repo.uploadProfilePhoto(any));
  });

  testWidgets('leaving the screen after picking never uploads (Cancel/back = '
      'no server change)', (tester) async {
    await pumpLoaded(tester, pushed: true);

    await pickPhoto(tester, writeJpeg('pick.jpg'));
    expect(find.text('New photo - not saved yet'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    verifyNever(repo.uploadProfilePhoto(any));
  });

  testWidgets('Save uploads the picked photo, reloads, and pops on full '
      'success', (tester) async {
    when(
      repo.uploadProfilePhoto(any),
    ).thenAnswer((_) async => '/uploads/profiles/user_7_new.jpg');
    when(repo.updateProfile(any)).thenAnswer((_) async => buildUser());
    await pumpLoaded(tester, pushed: true);
    // getProfile is called again by the post-upload reload.
    when(repo.getProfile()).thenAnswer(
      (_) async => buildUser(photoUrl: '/uploads/profiles/user_7_new.jpg'),
    );

    await pickPhoto(tester, writeJpeg('pick.jpg'));
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    await tester.pump();

    verify(repo.uploadProfilePhoto(any)).called(1);
    expect(find.text('Profile updated'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsNothing); // popped
  });

  testWidgets('a HEIC pick is rejected client-side with a clear message and no '
      'draft', (tester) async {
    await pumpLoaded(tester);
    await pickPhoto(tester, writeHeic('photo.heic'));

    expect(find.textContaining('HEIC/HEIF'), findsOneWidget);
    expect(find.text('New photo - not saved yet'), findsNothing);
    verifyNever(repo.uploadProfilePhoto(any));
  });

  // ---- partial save --------------------------------------------------

  testWidgets('photo saved but fields fail: photo kept, message says which '
      'part failed, screen stays (no "success")', (tester) async {
    when(
      repo.uploadProfilePhoto(any),
    ).thenAnswer((_) async => '/uploads/profiles/user_7_new.jpg');
    when(
      repo.updateProfile(any),
    ).thenThrow(ApiException('Server error: boom', statusCode: 500));
    await pumpLoaded(tester);
    when(repo.getProfile()).thenAnswer(
      (_) async => buildUser(photoUrl: '/uploads/profiles/user_7_new.jpg'),
    );

    await pickPhoto(tester, writeJpeg('pick.jpg'));
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsOneWidget); // stayed
    expect(find.text('Profile updated'), findsNothing);
    expect(find.textContaining('Your photo was saved.'), findsOneWidget);
  });

  testWidgets('fields saved but photo fails: draft retained for retry, screen '
      'stays', (tester) async {
    when(
      repo.uploadProfilePhoto(any),
    ).thenThrow(ApiException('Network error - cannot connect to server'));
    when(repo.updateProfile(any)).thenAnswer((_) async => buildUser());
    await pumpLoaded(tester);

    await pickPhoto(tester, writeJpeg('pick.jpg'));
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(find.textContaining('Your details were saved.'), findsOneWidget);
    // The failed photo draft is still on screen to retry.
    expect(find.text('New photo - not saved yet'), findsOneWidget);
  });

  testWidgets('photo 409 conflict refreshes authoritative state and offers an '
      'explicit retry, never auto-overwrites', (tester) async {
    var uploads = 0;
    when(repo.uploadProfilePhoto(any)).thenAnswer((_) async {
      uploads++;
      throw ApiException('changed', statusCode: 409);
    });
    when(repo.updateProfile(any)).thenAnswer((_) async => buildUser());
    var getProfileCalls = 0;
    when(repo.getProfile()).thenAnswer((_) async {
      getProfileCalls++;
      return buildUser();
    });

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump();
    final callsAfterLoad = getProfileCalls;

    await pickPhoto(tester, writeJpeg('pick.jpg'));
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(uploads, 1); // tried once, did NOT silently retry
    expect(getProfileCalls, greaterThan(callsAfterLoad)); // refreshed
    expect(find.textContaining('changed on another device'), findsOneWidget);
    expect(find.text('New photo - not saved yet'), findsOneWidget); // retriable
  });

  // ---- username editing --------------------------------------------

  testWidgets('changing the username sends it, reconciles AuthProvider, and '
      'pops', (tester) async {
    ProfileUpdateRequest? sent;
    when(repo.updateProfile(any)).thenAnswer((invocation) async {
      sent = invocation.positionalArguments.first as ProfileUpdateRequest;
      return buildUser(username: 'bob_new');
    });
    await pumpLoaded(tester, pushed: true);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'bob_new',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    await tester.pump();

    expect(sent!.toJson()['username'], 'bob_new');
    expect(auth.appliedUsernames, ['bob_new']);
    expect(find.text('Profile updated'), findsOneWidget);
  });

  testWidgets('a taken username (409) shows an inline field error and does not '
      'pop', (tester) async {
    when(
      repo.updateProfile(any),
    ).thenThrow(ApiException('Username already taken', statusCode: 409));
    await pumpLoaded(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'taken_name',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('That username is already taken.'), findsOneWidget);
    expect(find.byType(EditProfileScreen), findsOneWidget);
    expect(auth.appliedUsernames, isEmpty);
  });

  testWidgets(
    'an invalid username fails client validation before any request',
    (tester) async {
      await pumpLoaded(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'bad name!',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Use 1-30 letters, numbers or _'), findsOneWidget);
      verifyNever(repo.updateProfile(any));
    },
  );

  // ---- async hydration must not clobber edits --------------------------

  testWidgets('a late background profile refresh does not overwrite what the '
      'user has typed', (tester) async {
    await pumpLoaded(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'User Edited Name',
    );
    await tester.pump();

    // Simulate a second load completing (e.g. connectivity refresh) with a
    // different server name.
    when(
      repo.getProfile(),
    ).thenAnswer((_) async => buildUser(name: 'Server Changed Name'));
    await provider.loadUserProfile();
    await tester.pump();

    final nameField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Name'),
    );
    expect(nameField.controller?.text, 'User Edited Name');
  });

  testWidgets('a stale-account profile response is ignored (epoch changed)', (
    tester,
  ) async {
    final gate = Completer<User>();
    when(repo.getProfile()).thenAnswer((_) => gate.future);

    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Another account logs in before the first profile resolves.
    epoch.activate(99);
    gate.complete(buildUser(name: 'Account 7 Name'));
    await tester.pump();
    await tester.pump();

    // The old account's response never hydrates this screen.
    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
    expect(provider.currentUser, isNull);
  });
}
