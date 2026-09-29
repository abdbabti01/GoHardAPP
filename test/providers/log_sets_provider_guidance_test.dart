import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/exercise_guidance.dart';
import 'package:go_hard_app/data/repositories/exercise_repository.dart';
import 'package:go_hard_app/providers/log_sets_provider.dart';

@GenerateMocks([ExerciseRepository])
import 'log_sets_provider_guidance_test.mocks.dart';

/// Proves [LogSetsProvider.loadGuidance] clears and republishes `null`
/// SYNCHRONOUSLY (notifying immediately) when a new exercise's guidance
/// starts loading, so a screen that just navigated from exercise A to
/// exercise B never renders A's stale target/previous-performance card
/// while B's request is still in flight.
void main() {
  late MockExerciseRepository repo;
  late UserSessionEpoch epoch;
  late LogSetsProvider provider;
  late int notifyCount;

  final guidanceA = ExerciseGuidance(targetSets: 3, targetRepsMin: 8);

  setUp(() {
    repo = MockExerciseRepository();
    epoch = UserSessionEpoch()..activate(1);
    provider = LogSetsProvider(repo, epoch);
    notifyCount = 0;
    provider.addListener(() => notifyCount++);
  });

  test('loadGuidance(B), called after loadGuidance(A) completed, clears '
      '`guidance` and notifies before B resolves - A\'s guidance never '
      'flashes on B\'s screen', () async {
    when(repo.getExerciseGuidance(1)).thenAnswer((_) async => guidanceA);
    await provider.loadGuidance(1);
    expect(provider.guidance, same(guidanceA));

    final bC = Completer<ExerciseGuidance?>();
    when(repo.getExerciseGuidance(2)).thenAnswer((_) => bC.future);
    notifyCount = 0;
    final bF = provider.loadGuidance(2);

    // Still awaiting B's response, but A's guidance must already be gone.
    expect(provider.guidance, isNull);
    expect(
      notifyCount,
      greaterThanOrEqualTo(1),
      reason: 'must notify before B resolves, not only after',
    );

    bC.complete(null);
    await bF;
    expect(provider.guidance, isNull);
  });
}
