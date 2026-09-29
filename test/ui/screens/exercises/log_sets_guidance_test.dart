import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/exercise_guidance.dart';
import 'package:go_hard_app/data/models/exercise_set.dart';
import 'package:go_hard_app/data/repositories/exercise_repository.dart';
import 'package:go_hard_app/data/repositories/profile_repository.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/providers/log_sets_provider.dart';
import 'package:go_hard_app/providers/profile_provider.dart';
import 'package:go_hard_app/ui/screens/exercises/log_sets_screen.dart';

import 'log_sets_guidance_test.mocks.dart';

/// Task 9: minimal UI proof that Log Sets surfaces the snapshotted target
/// and previous performance ([LogSetsProvider.guidance]), and that the
/// previous-set weight follows the live unit preference at the display
/// boundary only (the stored kg value is never touched).
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
    when(
      exerciseRepo.getExerciseSets(any),
    ).thenAnswer((_) async => <ExerciseSet>[]);
  });

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
    ProfileProvider profileProvider,
  ) async {
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

  final guidance = ExerciseGuidance(
    targetSets: 3,
    targetRepsMin: 8,
    targetRepsMax: 10,
    previous: PreviousPerformance(
      sessionLocalId: 1,
      performedAt: DateTime.utc(2026, 1, 1),
      sets: [
        ExerciseSet(
          id: 1,
          exerciseId: 1,
          setNumber: 1,
          reps: 10,
          weight: 61.235,
          isCompleted: true,
        ),
      ],
    ),
  );

  testWidgets('shows target and last time in kg (Metric)', (tester) async {
    when(
      exerciseRepo.getExerciseGuidance(any),
    ).thenAnswer((_) async => guidance);
    await pumpScreen(tester, await buildProfileProvider(tester, 'Metric'));
    expect(find.text('Target  3 × 8–10'), findsOneWidget);
    expect(find.text('61.2 kg × 10'), findsOneWidget);
  });

  testWidgets('Imperial changes only display; stored kg value untouched', (
    tester,
  ) async {
    when(
      exerciseRepo.getExerciseGuidance(any),
    ).thenAnswer((_) async => guidance);
    await pumpScreen(tester, await buildProfileProvider(tester, 'Imperial'));
    expect(find.text('135 lb × 10'), findsOneWidget); // 61.235 kg -> 135 lb
    expect(guidance.previous!.sets.single.weight, 61.235);
    verifyNever(exerciseRepo.updateExerciseSet(any, any));
    verifyNever(exerciseRepo.createExerciseSet(any));
  });

  testWidgets('no guidance renders nothing extra', (tester) async {
    when(exerciseRepo.getExerciseGuidance(any)).thenAnswer((_) async => null);
    await pumpScreen(tester, await buildProfileProvider(tester, 'Metric'));
    expect(find.text('Last time'), findsNothing);
  });
}
