import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/workout_template.dart';
import 'package:go_hard_app/data/repositories/workout_template_repository.dart';
import 'package:go_hard_app/providers/workout_template_provider.dart';

@GenerateMocks([WorkoutTemplateRepository, ConnectivityService])
import 'workout_template_provider_session_ownership_test.mocks.dart';

/// Proves [WorkoutTemplateProvider] drops any repository result, error, or
/// finally-block cleanup that resolves after the session that requested it
/// has ended - so a response or loading-flag reset for user A can never land
/// on user B who now owns this shared provider instance.
void main() {
  late MockWorkoutTemplateRepository repo;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late UserSessionEpoch epoch;
  late WorkoutTemplateProvider provider;

  WorkoutTemplate template(
    int localId, {
    int? serverId,
    int cachedForUserId = 1,
    int? createdByUserId = 1,
    bool isActive = true,
    int usageCount = 0,
  }) => WorkoutTemplate(
    localId: localId,
    serverId: serverId ?? localId,
    cachedForUserId: cachedForUserId,
    createdByUserId: createdByUserId,
    name: 'Template $localId',
    exercisesJson: '[]',
    recurrencePattern: 'daily',
    isActive: isActive,
    usageCount: usageCount,
    createdAt: DateTime(2026, 1, 1),
  );

  void stubGetTemplates(Future<List<WorkoutTemplate>> Function() answer) {
    when(
      repo.getTemplates(activeOnly: anyNamed('activeOnly')),
    ).thenAnswer((_) => answer());
  }

  setUp(() {
    repo = MockWorkoutTemplateRepository();
    connectivity = MockConnectivityService();
    connectivityController = StreamController<bool>.broadcast();
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    epoch = UserSessionEpoch();
    provider = WorkoutTemplateProvider(repo, connectivity, epoch);
  });

  tearDown(() async {
    await connectivityController.close();
  });

  test('logged-out methods never call the repository', () async {
    await provider.loadTemplates();
    await provider.loadCommunityTemplates();
    await provider.loadTemplateById(1);
    await provider.createTemplate(
      name: 'x',
      exercisesJson: '[]',
      recurrencePattern: 'daily',
    );
    await provider.updateTemplate(template(1));
    await provider.toggleActive(template(1));
    await provider.deleteTemplate(template(1));
    await provider.incrementUsageCount(template(1));
    await provider.refresh();

    verifyZeroInteractions(repo);
  });

  test('a stale load success cannot populate B', () async {
    epoch.activate(1);
    final completer = Completer<List<WorkoutTemplate>>();
    stubGetTemplates(() => completer.future);

    final future = provider.loadTemplates();
    epoch.invalidate();
    epoch.activate(2);
    completer.complete([template(1)]);
    await future;

    expect(provider.templates, isEmpty);
  });

  test("a stale load error cannot set B's error", () async {
    epoch.activate(1);
    final completer = Completer<List<WorkoutTemplate>>();
    stubGetTemplates(() => completer.future);

    final future = provider.loadTemplates();
    epoch.invalidate();
    epoch.activate(2);
    completer.completeError(Exception('boom'));
    await future;

    expect(provider.errorMessage, isNull);
  });

  test("a stale finally cannot clear B's loading state", () async {
    epoch.activate(1);
    final completerA = Completer<List<WorkoutTemplate>>();
    stubGetTemplates(() => completerA.future);

    final futureA = provider.loadTemplates();
    expect(provider.isLoading, isTrue);

    epoch.invalidate();
    provider.clear();
    epoch.activate(2);
    expect(provider.isLoading, isFalse);

    final completerB = Completer<List<WorkoutTemplate>>();
    stubGetTemplates(() => completerB.future);
    final futureB = provider.loadTemplates();
    expect(provider.isLoading, isTrue);

    completerA.complete([template(1)]);
    await futureA;
    expect(
      provider.isLoading,
      isTrue,
      reason: "A's stale finally must not clear B's loading state",
    );

    completerB.complete([template(2, cachedForUserId: 2)]);
    await futureB;
    expect(provider.isLoading, isFalse);
    expect(provider.templates.map((t) => t.localId), [2]);
  });

  test('a stale create success cannot insert into B', () async {
    epoch.activate(1);
    final completer = Completer<WorkoutTemplate>();
    when(
      repo.createTemplate(
        name: anyNamed('name'),
        description: anyNamed('description'),
        exercisesJson: anyNamed('exercisesJson'),
        recurrencePattern: anyNamed('recurrencePattern'),
        daysOfWeek: anyNamed('daysOfWeek'),
        intervalDays: anyNamed('intervalDays'),
        estimatedDuration: anyNamed('estimatedDuration'),
        category: anyNamed('category'),
        isActive: anyNamed('isActive'),
        isPublic: anyNamed('isPublic'),
      ),
    ).thenAnswer((_) => completer.future);

    final future = provider.createTemplate(
      name: 'x',
      exercisesJson: '[]',
      recurrencePattern: 'daily',
    );
    epoch.invalidate();
    provider.clear();
    epoch.activate(2);
    completer.complete(template(7, cachedForUserId: 1));
    await future;

    expect(provider.templates, isEmpty);
  });

  test("a stale toggleActive success cannot mutate B's list", () async {
    epoch.activate(1);
    stubGetTemplates(() async => [template(1, isActive: true)]);
    await provider.loadTemplates();

    final completer = Completer<WorkoutTemplate?>();
    when(repo.toggleActive(any)).thenAnswer((_) => completer.future);
    final future = provider.toggleActive(provider.templates.first);

    epoch.invalidate();
    provider.clear();
    epoch.activate(2);
    stubGetTemplates(
      () async => [template(1, cachedForUserId: 2, isActive: true)],
    );
    await provider.loadTemplates();

    completer.complete(template(1, cachedForUserId: 1, isActive: false));
    await future;

    expect(provider.templates.single.isActive, isTrue);
    expect(provider.errorMessage, isNull);
  });

  test("a stale mutation failure cannot set B's error", () async {
    epoch.activate(1);
    stubGetTemplates(() async => [template(1, isActive: true)]);
    await provider.loadTemplates();

    final toggleC = Completer<WorkoutTemplate?>();
    final updateC = Completer<WorkoutTemplate>();
    when(repo.toggleActive(any)).thenAnswer((_) => toggleC.future);
    when(repo.updateTemplate(any)).thenAnswer((_) => updateC.future);
    final toggleF = provider.toggleActive(provider.templates.first);
    final updateF = provider.updateTemplate(provider.templates.first);

    epoch.invalidate();
    provider.clear();
    epoch.activate(2);

    toggleC.completeError(Exception('boom'));
    updateC.completeError(Exception('boom'));
    await toggleF;
    await updateF;

    expect(provider.errorMessage, isNull);
    expect(provider.isLoading, isFalse);
  });

  test("a stale delete success cannot remove B's item", () async {
    epoch.activate(1);
    final completer = Completer<bool>();
    when(repo.deleteTemplate(any)).thenAnswer((_) => completer.future);

    final future = provider.deleteTemplate(template(1));
    epoch.invalidate();
    epoch.activate(2);
    stubGetTemplates(() async => [template(1, cachedForUserId: 2)]);
    await provider.loadTemplates();

    completer.complete(true);
    final result = await future;

    expect(result, isFalse);
    expect(provider.templates.map((t) => t.localId), [1]);
  });

  test(
    'connectivity restoration while logged out performs no repository call',
    () async {
      connectivityController.add(true);
      await Future<void>.value();

      verifyNever(repo.getTemplates(activeOnly: anyNamed('activeOnly')));
    },
  );

  test("the connectivity handler's own logged-out guard short-circuits before "
      'ever entering loadTemplates', () async {
    final spyController = StreamController<bool>.broadcast();
    addTearDown(spyController.close);
    final spyConnectivity = MockConnectivityService();
    when(spyConnectivity.isOnline).thenReturn(true);
    when(
      spyConnectivity.connectivityStream,
    ).thenAnswer((_) => spyController.stream);
    final spy = _LoadSpyProvider(repo, spyConnectivity, epoch);
    addTearDown(spy.dispose);

    // Logged out: the handler must not even call loadTemplates.
    spyController.add(true);
    await Future<void>.value();
    expect(spy.loadCalls, 0);

    // Logged in: the same event now drives exactly one load.
    epoch.activate(1);
    when(
      repo.getTemplates(activeOnly: anyNamed('activeOnly')),
    ).thenAnswer((_) async => <WorkoutTemplate>[]);
    spyController.add(true);
    await Future<void>.value();
    expect(spy.loadCalls, 1);
  });

  test('a connectivity refresh invalidated mid-flight is discarded', () async {
    epoch.activate(1);
    final completer = Completer<List<WorkoutTemplate>>();
    stubGetTemplates(() => completer.future);

    connectivityController.add(true);
    await Future<void>.value();
    await Future<void>.value();

    epoch.invalidate();
    epoch.activate(2);
    completer.complete([template(1, cachedForUserId: 1)]);
    await Future<void>.value();

    expect(provider.templates, isEmpty);
  });

  test('clear resets every list, flag, filter, and error field', () async {
    epoch.activate(1);
    stubGetTemplates(() async => [template(1)]);
    when(
      repo.getCommunityTemplates(
        category: anyNamed('category'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => [template(2, cachedForUserId: 1)]);

    await provider.loadTemplates();
    await provider.loadCommunityTemplates();
    provider.setCategory('Strength');
    expect(provider.templates, isNotEmpty);
    expect(provider.selectedCategory, 'Strength');

    provider.clear();

    expect(provider.templates, isEmpty);
    expect(provider.communityTemplates, isEmpty);
    expect(provider.selectedTemplate, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.selectedCategory, isNull);
    expect(provider.showActiveOnly, isTrue);
  });

  // ============ Per-load request ordering (latest wins) ============

  group('request ordering', () {
    test('an older owner-list request completing last cannot overwrite the '
        'newer one', () async {
      epoch.activate(1);
      final first = Completer<List<WorkoutTemplate>>();
      final second = Completer<List<WorkoutTemplate>>();
      var call = 0;
      when(
        repo.getTemplates(activeOnly: anyNamed('activeOnly')),
      ).thenAnswer((_) => (call++ == 0) ? first.future : second.future);

      final f1 = provider.loadTemplates(); // request 1
      final f2 = provider.loadTemplates(); // request 2 (newer)

      second.complete([template(2)]);
      await f2;
      expect(provider.templates.map((t) => t.localId), [2]);

      // The older request resolves last with different data - it must be
      // dropped.
      first.complete([template(9)]);
      await f1;
      expect(provider.templates.map((t) => t.localId), [2]);
    });

    test('an older community request completing last cannot overwrite the '
        'newer one', () async {
      epoch.activate(1);
      final first = Completer<List<WorkoutTemplate>>();
      final second = Completer<List<WorkoutTemplate>>();
      var call = 0;
      when(
        repo.getCommunityTemplates(
          category: anyNamed('category'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) => (call++ == 0) ? first.future : second.future);

      final f1 = provider.loadCommunityTemplates();
      final f2 = provider.loadCommunityTemplates();

      second.complete([template(2, cachedForUserId: 1)]);
      await f2;
      expect(provider.communityTemplates.map((t) => t.localId), [2]);

      first.complete([template(9, cachedForUserId: 1)]);
      await f1;
      expect(provider.communityTemplates.map((t) => t.localId), [2]);
    });

    test(
      'template A detail completing after template B cannot replace B',
      () async {
        epoch.activate(1);
        final a = Completer<WorkoutTemplate?>();
        final b = Completer<WorkoutTemplate?>();
        when(repo.getTemplateById(10)).thenAnswer((_) => a.future);
        when(repo.getTemplateById(20)).thenAnswer((_) => b.future);

        final fa = provider.loadTemplateById(10); // request 1
        final fb = provider.loadTemplateById(20); // request 2 (newer)

        b.complete(template(20, serverId: 20));
        await fb;
        expect(provider.selectedTemplate!.serverId, 20);

        a.complete(template(10, serverId: 10));
        await fa;
        expect(provider.selectedTemplate!.serverId, 20);
      },
    );

    test('a connectivity-triggered owner refresh cannot overwrite a newer '
        'manual refresh', () async {
      epoch.activate(1);
      final connectivityLoad = Completer<List<WorkoutTemplate>>();
      final manualLoad = Completer<List<WorkoutTemplate>>();
      var call = 0;
      when(repo.getTemplates(activeOnly: anyNamed('activeOnly'))).thenAnswer(
        (_) => (call++ == 0) ? connectivityLoad.future : manualLoad.future,
      );

      connectivityController.add(
        true,
      ); // fires loadTemplates(showLoading:false)
      await Future<void>.value();
      await Future<void>.value();

      final manual = provider.loadTemplates(); // newer manual pull-to-refresh
      manualLoad.complete([template(2)]);
      await manual;
      expect(provider.templates.map((t) => t.localId), [2]);

      connectivityLoad.complete([template(9)]); // stale, resolves last
      await Future<void>.value();
      expect(provider.templates.map((t) => t.localId), [2]);
    });

    test(
      'clear() invalidates every pending load so none commits afterward',
      () async {
        epoch.activate(1);
        final owner = Completer<List<WorkoutTemplate>>();
        final community = Completer<List<WorkoutTemplate>>();
        final detail = Completer<WorkoutTemplate?>();
        stubGetTemplates(() => owner.future);
        when(
          repo.getCommunityTemplates(
            category: anyNamed('category'),
            limit: anyNamed('limit'),
          ),
        ).thenAnswer((_) => community.future);
        when(repo.getTemplateById(any)).thenAnswer((_) => detail.future);

        final fo = provider.loadTemplates();
        final fc = provider.loadCommunityTemplates();
        final fd = provider.loadTemplateById(5);

        provider.clear();

        owner.complete([template(1)]);
        community.complete([template(2, cachedForUserId: 1)]);
        detail.complete(template(3, serverId: 3));
        await Future.wait([fo, fc, fd]);

        expect(provider.templates, isEmpty);
        expect(provider.communityTemplates, isEmpty);
        expect(provider.selectedTemplate, isNull);
      },
    );
  });
}

/// Counts every entry into [loadTemplates] so a test can prove the
/// connectivity handler's own logged-out guard short-circuits before ever
/// reaching it.
class _LoadSpyProvider extends WorkoutTemplateProvider {
  _LoadSpyProvider(super.repository, super.connectivity, super.sessionEpoch);

  int loadCalls = 0;

  @override
  Future<void> loadTemplates({bool showLoading = true}) {
    loadCalls++;
    return super.loadTemplates(showLoading: showLoading);
  }
}
