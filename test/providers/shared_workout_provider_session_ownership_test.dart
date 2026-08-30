import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/shared_workout.dart';
import 'package:go_hard_app/data/repositories/shared_workout_repository.dart';
import 'package:go_hard_app/providers/shared_workout_provider.dart';

@GenerateMocks([SharedWorkoutRepository, ConnectivityService])
import 'shared_workout_provider_session_ownership_test.mocks.dart';

/// Proves [SharedWorkoutProvider] drops any repository result, error, or
/// finally-block cleanup that resolves after the session that requested it
/// has ended - so a response, rollback, or loading-flag reset for user A
/// can never land on user B who now owns this shared provider instance.
void main() {
  late MockSharedWorkoutRepository repo;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late UserSessionEpoch epoch;
  late SharedWorkoutProvider provider;

  SharedWorkout workout(
    int id, {
    int cachedForUserId = 1,
    int sharedByUserId = 99,
    bool isLiked = false,
    bool isSaved = false,
    int likeCount = 0,
    int saveCount = 0,
  }) => SharedWorkout(
    id: id,
    originalId: id * 10,
    type: 'session',
    sharedByUserId: sharedByUserId,
    sharedByUserName: 'author',
    workoutName: 'Workout $id',
    exercisesJson: '[]',
    duration: 20,
    category: 'strength',
    difficulty: 'beginner',
    likeCount: likeCount,
    saveCount: saveCount,
    isLikedByCurrentUser: isLiked,
    isSavedByCurrentUser: isSaved,
    sharedAt: DateTime(2026, 1, 1),
    cachedForUserId: cachedForUserId,
  );

  setUp(() {
    repo = MockSharedWorkoutRepository();
    connectivity = MockConnectivityService();
    connectivityController = StreamController<bool>.broadcast();
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    epoch = UserSessionEpoch();
    provider = SharedWorkoutProvider(repo, connectivity, epoch);
  });

  tearDown(() async {
    await connectivityController.close();
  });

  // ============ 1. Logged out ============

  test('logged-out methods never call the repository (req 1)', () async {
    await provider.loadSharedWorkouts();
    await provider.loadSavedWorkouts();
    await provider.loadMySharedWorkouts();
    await provider.shareWorkout(
      originalId: 1,
      type: 'session',
      workoutName: 'x',
      exercisesJson: '[]',
      duration: 10,
      category: 'strength',
    );
    await provider.toggleLike(1);
    await provider.toggleSave(1);
    await provider.deleteSharedWorkout(1);
    await provider.refresh();

    verifyZeroInteractions(repo);
  });

  // ============ 2-4. Stale load ============

  test('a stale load success cannot populate B (req 2)', () async {
    epoch.activate(1);
    final completer = Completer<List<SharedWorkout>>();
    when(
      repo.getSharedWorkouts(
        category: anyNamed('category'),
        difficulty: anyNamed('difficulty'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) => completer.future);

    final future = provider.loadSharedWorkouts();
    epoch.invalidate();
    epoch.activate(2);
    completer.complete([workout(1, cachedForUserId: 1)]);
    await future;

    expect(provider.sharedWorkouts, isEmpty);
  });

  test('a stale load error cannot set B\'s error (req 3)', () async {
    epoch.activate(1);
    final completer = Completer<List<SharedWorkout>>();
    when(
      repo.getSharedWorkouts(
        category: anyNamed('category'),
        difficulty: anyNamed('difficulty'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) => completer.future);

    final future = provider.loadSharedWorkouts();
    epoch.invalidate();
    epoch.activate(2);
    completer.completeError(Exception('boom'));
    await future;

    expect(provider.errorMessage, isNull);
  });

  test('a stale finally cannot clear B\'s loading state (req 4)', () async {
    epoch.activate(1);
    final completerA = Completer<List<SharedWorkout>>();
    when(
      repo.getSharedWorkouts(
        category: anyNamed('category'),
        difficulty: anyNamed('difficulty'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) => completerA.future);

    final futureA = provider.loadSharedWorkouts();
    expect(provider.isLoading, isTrue);

    // Logout cleanup resets loading; then B logs in and starts its load.
    epoch.invalidate();
    provider.clear();
    epoch.activate(2);
    expect(provider.isLoading, isFalse);

    final completerB = Completer<List<SharedWorkout>>();
    when(
      repo.getSharedWorkouts(
        category: anyNamed('category'),
        difficulty: anyNamed('difficulty'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) => completerB.future);
    final futureB = provider.loadSharedWorkouts();
    expect(provider.isLoading, isTrue);

    // A's delayed completion must not flip B's loading flag off.
    completerA.complete([workout(1)]);
    await futureA;
    expect(
      provider.isLoading,
      isTrue,
      reason: "A's stale finally must not clear B's loading state",
    );

    completerB.complete([workout(2, cachedForUserId: 2)]);
    await futureB;
    expect(provider.isLoading, isFalse);
    expect(provider.sharedWorkouts.map((w) => w.id), [2]);
  });

  test('B\'s active load remains unaffected while A\'s completion is pending '
      '(req 14)', () async {
    epoch.activate(1);
    final completerA = Completer<List<SharedWorkout>>();
    when(repo.getSavedWorkouts()).thenAnswer((_) => completerA.future);
    final futureA = provider.loadSavedWorkouts();

    epoch.invalidate();
    epoch.activate(2);
    when(
      repo.getSavedWorkouts(),
    ).thenAnswer((_) async => [workout(5, cachedForUserId: 2, isSaved: true)]);
    await provider.loadSavedWorkouts();
    expect(provider.savedWorkouts.map((w) => w.id), [5]);

    completerA.complete([workout(1, cachedForUserId: 1, isSaved: true)]);
    await futureA;
    expect(provider.savedWorkouts.map((w) => w.id), [5]);
  });

  // ============ 5. Stale share ============

  test('a stale share success cannot insert into B (req 5)', () async {
    epoch.activate(1);
    final completer = Completer<SharedWorkout>();
    when(
      repo.shareWorkout(
        originalId: anyNamed('originalId'),
        type: anyNamed('type'),
        workoutName: anyNamed('workoutName'),
        description: anyNamed('description'),
        exercisesJson: anyNamed('exercisesJson'),
        duration: anyNamed('duration'),
        category: anyNamed('category'),
        difficulty: anyNamed('difficulty'),
      ),
    ).thenAnswer((_) => completer.future);

    final future = provider.shareWorkout(
      originalId: 1,
      type: 'session',
      workoutName: 'x',
      exercisesJson: '[]',
      duration: 10,
      category: 'strength',
    );
    epoch.invalidate();
    provider.clear();
    epoch.activate(2);
    completer.complete(workout(7, cachedForUserId: 1));
    await future;

    expect(provider.sharedWorkouts, isEmpty);
    expect(provider.mySharedWorkouts, isEmpty);
  });

  // ============ 6-9. Stale optimistic toggles ============

  /// Loads [rows] into the provider's lists for the currently-active
  /// session, through the real `loadSharedWorkouts` path (no test-only
  /// production hook).
  Future<void> seedFeed(List<SharedWorkout> rows) async {
    when(
      repo.getSharedWorkouts(
        category: anyNamed('category'),
        difficulty: anyNamed('difficulty'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => rows);
    await provider.loadSharedWorkouts();
  }

  test('a stale like success cannot mutate B (req 6)', () async {
    epoch.activate(1);
    await seedFeed([workout(1, isLiked: false, likeCount: 3)]);
    final completer = Completer<void>();
    when(repo.toggleLike(1, true)).thenAnswer((_) => completer.future);

    final future = provider.toggleLike(1);

    epoch.invalidate();
    provider.clear();
    epoch.activate(2);
    final bWorkout = workout(
      1,
      cachedForUserId: 2,
      isLiked: false,
      likeCount: 10,
    );
    await seedFeed([bWorkout]);

    completer.complete();
    await future;

    expect(bWorkout.isLikedByCurrentUser, isFalse);
    expect(bWorkout.likeCount, 10);
  });

  test('a stale like failure cannot roll back B (req 7)', () async {
    epoch.activate(1);
    await seedFeed([workout(1, isLiked: false, likeCount: 3)]);
    final completer = Completer<void>();
    when(repo.toggleLike(1, true)).thenAnswer((_) => completer.future);

    final future = provider.toggleLike(1);

    epoch.invalidate();
    provider.clear();
    epoch.activate(2);
    final bWorkout = workout(
      1,
      cachedForUserId: 2,
      isLiked: true,
      likeCount: 10,
    );
    await seedFeed([bWorkout]);

    completer.completeError(Exception('boom'));
    await future;

    expect(bWorkout.isLikedByCurrentUser, isTrue);
    expect(bWorkout.likeCount, 10);
    expect(provider.errorMessage, isNull);
  });

  test('a stale save success cannot mutate B (req 8)', () async {
    epoch.activate(1);
    await seedFeed([workout(1, isSaved: false, saveCount: 1)]);
    final completer = Completer<void>();
    when(repo.toggleSave(1, true)).thenAnswer((_) => completer.future);

    final future = provider.toggleSave(1);

    epoch.invalidate();
    provider.clear();
    epoch.activate(2);
    final bWorkout = workout(
      1,
      cachedForUserId: 2,
      isSaved: false,
      saveCount: 4,
    );
    await seedFeed([bWorkout]);

    completer.complete();
    await future;

    expect(bWorkout.isSavedByCurrentUser, isFalse);
    expect(provider.savedWorkouts, isEmpty);
  });

  test('a stale save failure cannot roll back B (req 9)', () async {
    epoch.activate(1);
    await seedFeed([workout(1, isSaved: false, saveCount: 1)]);
    final completer = Completer<void>();
    when(repo.toggleSave(1, true)).thenAnswer((_) => completer.future);

    final future = provider.toggleSave(1);

    epoch.invalidate();
    provider.clear();
    epoch.activate(2);
    final bWorkout = workout(
      1,
      cachedForUserId: 2,
      isSaved: true,
      saveCount: 9,
    );
    when(repo.getSavedWorkouts()).thenAnswer((_) async => [bWorkout]);
    await provider.loadSavedWorkouts();
    await seedFeed([bWorkout]);

    completer.completeError(Exception('boom'));
    await future;

    expect(bWorkout.isSavedByCurrentUser, isTrue);
    expect(provider.savedWorkouts.map((w) => w.id), [1]);
    expect(provider.errorMessage, isNull);
  });

  // ============ 10. Stale delete ============

  test('a stale delete success cannot remove B\'s item (req 10)', () async {
    epoch.activate(1);
    final completer = Completer<void>();
    when(repo.deleteSharedWorkout(1)).thenAnswer((_) => completer.future);

    final future = provider.deleteSharedWorkout(1);
    epoch.invalidate();
    epoch.activate(2);
    await seedFeed([workout(1, cachedForUserId: 2)]);

    completer.complete();
    final result = await future;

    expect(result, isFalse);
    expect(provider.sharedWorkouts.map((w) => w.id), [1]);
  });

  // ============ 11-12. Connectivity ============

  test('connectivity restoration while logged out performs no repository call '
      '(req 11)', () async {
    connectivityController.add(true);
    await Future<void>.value();

    verifyNever(
      repo.getSharedWorkouts(
        category: anyNamed('category'),
        difficulty: anyNamed('difficulty'),
        limit: anyNamed('limit'),
      ),
    );
  });

  test('the connectivity handler\'s own logged-out guard short-circuits '
      'before ever entering loadSharedWorkouts (req 11)', () async {
    final spyController = StreamController<bool>.broadcast();
    addTearDown(spyController.close);
    final spyConnectivity = MockConnectivityService();
    when(spyConnectivity.isOnline).thenReturn(true);
    when(
      spyConnectivity.connectivityStream,
    ).thenAnswer((_) => spyController.stream);
    final spy = _LoadSpyProvider(repo, spyConnectivity, epoch);
    addTearDown(spy.dispose);

    // Logged out: the handler must not even call loadSharedWorkouts.
    spyController.add(true);
    await Future<void>.value();
    expect(spy.loadCalls, 0);

    // Logged in: the same event now drives exactly one load.
    epoch.activate(1);
    when(
      repo.getSharedWorkouts(
        category: anyNamed('category'),
        difficulty: anyNamed('difficulty'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => <SharedWorkout>[]);
    spyController.add(true);
    await Future<void>.value();
    expect(spy.loadCalls, 1);
  });

  test(
    'a connectivity refresh invalidated mid-flight is discarded (req 12)',
    () async {
      epoch.activate(1);
      final completer = Completer<List<SharedWorkout>>();
      when(
        repo.getSharedWorkouts(
          category: anyNamed('category'),
          difficulty: anyNamed('difficulty'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) => completer.future);

      connectivityController.add(true);
      await Future<void>.value();
      await Future<void>.value();

      epoch.invalidate();
      epoch.activate(2);
      completer.complete([workout(1, cachedForUserId: 1)]);
      await Future<void>.value();

      expect(provider.sharedWorkouts, isEmpty);
    },
  );

  // ============ 13. clear() ============

  test(
    'clear resets every list, flag, filter, and error field (req 13)',
    () async {
      epoch.activate(1);
      when(
        repo.getSharedWorkouts(
          category: anyNamed('category'),
          difficulty: anyNamed('difficulty'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => [workout(1)]);
      when(
        repo.getSavedWorkouts(),
      ).thenAnswer((_) async => [workout(1, isSaved: true)]);
      when(repo.getMySharedWorkouts()).thenAnswer((_) async => [workout(1)]);

      await provider.loadSharedWorkouts();
      await provider.loadSavedWorkouts();
      await provider.loadMySharedWorkouts();
      provider.setCategory('strength');
      provider.setDifficulty('beginner');
      expect(provider.sharedWorkouts, isNotEmpty);
      expect(provider.selectedCategory, 'strength');

      provider.clear();

      expect(provider.sharedWorkouts, isEmpty);
      expect(provider.savedWorkouts, isEmpty);
      expect(provider.mySharedWorkouts, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.selectedCategory, isNull);
      expect(provider.selectedDifficulty, isNull);
    },
  );
}

/// Counts every entry into [loadSharedWorkouts] so a test can prove the
/// connectivity handler's own logged-out guard short-circuits before ever
/// reaching it - rather than relying on `loadSharedWorkouts`'s internal
/// guard to produce the same externally-quiet outcome.
class _LoadSpyProvider extends SharedWorkoutProvider {
  _LoadSpyProvider(super.repository, super.connectivity, super.sessionEpoch);

  int loadCalls = 0;

  @override
  Future<void> loadSharedWorkouts({bool showLoading = true}) {
    loadCalls++;
    return super.loadSharedWorkouts(showLoading: showLoading);
  }
}
