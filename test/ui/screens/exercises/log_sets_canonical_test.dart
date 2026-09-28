import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/exercise_set.dart';
import 'package:go_hard_app/data/models/user.dart';
import 'package:go_hard_app/data/repositories/exercise_repository.dart';
import 'package:go_hard_app/data/repositories/profile_repository.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/providers/log_sets_provider.dart';
import 'package:go_hard_app/providers/profile_provider.dart';
import 'package:go_hard_app/ui/screens/exercises/log_sets_screen.dart';

import 'log_sets_canonical_test.mocks.dart';

/// Task 5: Log Sets is the canonical input/display boundary for lifted-weight
/// unit conversion. The field label and the list rendering follow
/// [ProfileProvider.unitPreference]; the value that actually reaches
/// [ExerciseRepository.createExerciseSet] (and therefore local storage and
/// sync) is always canonical kg, converted via `UnitConverter` at the
/// screen's edge ONLY - `LogSetsProvider`/`ExerciseRepository` never
/// convert. Supersedes `log_sets_weight_semantics_test.dart` (Phase 2A),
/// which pinned the old "typed lbs persisted unchanged" contract.
@GenerateMocks([ExerciseRepository, ProfileRepository, AuthService])
void main() {
  late MockExerciseRepository exerciseRepo;
  late MockProfileRepository profileRepo;
  late MockAuthService authService;
  late UserSessionEpoch epoch;

  setUp(() {
    exerciseRepo = MockExerciseRepository();
    profileRepo = MockProfileRepository();
    authService = MockAuthService();
    epoch = UserSessionEpoch()..activate(1);

    when(authService.getThemePreference()).thenAnswer((_) async => null);
    when(authService.saveThemePreference(any)).thenAnswer((_) async {});
    when(authService.saveUnitPreference(any)).thenAnswer((_) async {});
    when(
      exerciseRepo.createExerciseSet(any),
    ).thenAnswer((inv) async => inv.positionalArguments.first as ExerciseSet);
  });

  // Widget tests run inside Flutter's fake-async clock: a real
  // `Future.delayed` never resolves on its own (nothing advances the fake
  // clock while it's awaited directly), so the pending cached-preference
  // load is flushed via `tester.pump()` instead - never a real delay.
  Future<ProfileProvider> buildProfileProvider(
    WidgetTester tester,
    String unitPreference,
  ) async {
    when(
      authService.getUnitPreference(),
    ).thenAnswer((_) async => unitPreference);
    final provider = ProfileProvider(profileRepo, authService, epoch);
    await tester.pump();
    return provider;
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    ProfileProvider profileProvider, {
    List<ExerciseSet> initialSets = const [],
  }) async {
    // A fresh growable copy each call - LogSetsProvider.loadSets sorts the
    // list it gets back in place, which throws on the default `const []`.
    when(
      exerciseRepo.getExerciseSets(any),
    ).thenAnswer((_) async => List<ExerciseSet>.of(initialSets));

    final logProvider = LogSetsProvider(exerciseRepo, epoch);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileProvider>.value(value: profileProvider),
          ChangeNotifierProvider<LogSetsProvider>.value(value: logProvider),
        ],
        child: const MaterialApp(home: LogSetsScreen(exerciseId: 1)),
      ),
    );
    await tester.pumpAndSettle();
  }

  ExerciseSet storedSet({required double weight, int reps = 5}) => ExerciseSet(
    id: 1,
    exerciseId: 1,
    setNumber: 1,
    reps: reps,
    weight: weight,
    isCompleted: false,
  );

  group('Imperial', () {
    testWidgets('the weight field is labelled Weight (lb)', (tester) async {
      final profile = await buildProfileProvider(tester, 'Imperial');
      await pumpScreen(tester, profile);

      expect(find.widgetWithText(TextField, 'Weight (lb)'), findsOneWidget);
    });

    testWidgets('entering 135 persists canonical kg, not the typed lb value', (
      tester,
    ) async {
      final profile = await buildProfileProvider(tester, 'Imperial');
      await pumpScreen(tester, profile);

      await tester.enterText(find.widgetWithText(TextField, 'Reps'), '5');
      await tester.enterText(
        find.widgetWithText(TextField, 'Weight (lb)'),
        '135',
      );
      await tester.tap(find.text('Add Set'));
      await tester.pumpAndSettle();

      final sent =
          verify(exerciseRepo.createExerciseSet(captureAny)).captured.single
              as ExerciseSet;
      expect(sent.weight, closeTo(61.23496995, 1e-9));
    });

    testWidgets('a stored 61.23496995 kg set renders as 5 reps × 135 lb', (
      tester,
    ) async {
      final profile = await buildProfileProvider(tester, 'Imperial');
      await pumpScreen(
        tester,
        profile,
        initialSets: [storedSet(weight: 61.23496995)],
      );

      expect(find.text('5 reps × 135 lb'), findsOneWidget);
    });
  });

  group('Metric', () {
    testWidgets('the weight field is labelled Weight (kg)', (tester) async {
      final profile = await buildProfileProvider(tester, 'Metric');
      await pumpScreen(tester, profile);

      expect(find.widgetWithText(TextField, 'Weight (kg)'), findsOneWidget);
    });

    testWidgets('entering 60 persists 60 unchanged (already canonical kg)', (
      tester,
    ) async {
      final profile = await buildProfileProvider(tester, 'Metric');
      await pumpScreen(tester, profile);

      await tester.enterText(find.widgetWithText(TextField, 'Reps'), '5');
      await tester.enterText(
        find.widgetWithText(TextField, 'Weight (kg)'),
        '60',
      );
      await tester.tap(find.text('Add Set'));
      await tester.pumpAndSettle();

      final sent =
          verify(exerciseRepo.createExerciseSet(captureAny)).captured.single
              as ExerciseSet;
      expect(sent.weight, 60);
    });

    testWidgets('a stored 60 kg set renders as 5 reps × 60 kg', (tester) async {
      final profile = await buildProfileProvider(tester, 'Metric');
      await pumpScreen(tester, profile, initialSets: [storedSet(weight: 60)]);

      expect(find.text('5 reps × 60 kg'), findsOneWidget);
    });
  });

  testWidgets(
    'the same stored set renders 135 lb under Imperial and 61.2 kg under '
    'Metric; switching the preference issues no repository write',
    (tester) async {
      final profile = await buildProfileProvider(tester, 'Imperial');
      await pumpScreen(
        tester,
        profile,
        initialSets: [storedSet(weight: 61.23496995)],
      );
      expect(find.text('5 reps × 135 lb'), findsOneWidget);

      // Switch the live preference by hydrating from a server profile that
      // reports Metric - LogSetsScreen must react via context.select without
      // any set ever being re-persisted.
      when(profileRepo.getProfile()).thenAnswer(
        (_) async => User(
          id: 1,
          name: 'User 1',
          email: 'user1@example.com',
          dateCreated: DateTime.utc(2024, 1, 1),
          unitPreference: 'Metric',
        ),
      );
      await profile.loadUserProfile();
      await tester.pumpAndSettle();

      expect(find.text('5 reps × 61.2 kg'), findsOneWidget);
      verifyNever(exerciseRepo.createExerciseSet(any));
      verifyNever(exerciseRepo.completeExerciseSet(any));
      verifyNever(exerciseRepo.deleteExerciseSet(any));
    },
  );
}
