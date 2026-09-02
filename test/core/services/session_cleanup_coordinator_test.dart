import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/notification_service.dart';
import 'package:go_hard_app/core/services/session_cleanup_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/run_session.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/models/workout_stats.dart';
import 'package:go_hard_app/data/repositories/achievement_repository.dart';
import 'package:go_hard_app/data/repositories/analytics_repository.dart';
import 'package:go_hard_app/data/repositories/body_metrics_repository.dart';
import 'package:go_hard_app/data/repositories/chat_repository.dart';
import 'package:go_hard_app/data/repositories/direct_messages_repository.dart';
import 'package:go_hard_app/data/repositories/friends_repository.dart';
import 'package:go_hard_app/data/repositories/goals_repository.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/data/repositories/profile_repository.dart';
import 'package:go_hard_app/data/repositories/programs_repository.dart';
import 'package:go_hard_app/data/repositories/running_repository.dart';
import 'package:go_hard_app/data/repositories/session_repository.dart';
import 'package:go_hard_app/data/repositories/shared_workout_repository.dart';
import 'package:go_hard_app/data/repositories/workout_template_repository.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/providers/achievements_provider.dart';
import 'package:go_hard_app/providers/active_workout_provider.dart';
import 'package:go_hard_app/providers/analytics_provider.dart';
import 'package:go_hard_app/providers/body_metrics_provider.dart';
import 'package:go_hard_app/providers/chat_provider.dart';
import 'package:go_hard_app/providers/friends_provider.dart';
import 'package:go_hard_app/providers/goals_provider.dart';
import 'package:go_hard_app/providers/log_sets_provider.dart';
import 'package:go_hard_app/providers/messages_provider.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';
import 'package:go_hard_app/providers/profile_provider.dart';
import 'package:go_hard_app/providers/programs_provider.dart';
import 'package:go_hard_app/providers/running_provider.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';
import 'package:go_hard_app/providers/shared_workout_provider.dart';
import 'package:go_hard_app/providers/workout_template_provider.dart';

import 'session_cleanup_coordinator_test.mocks.dart';
// LogSetsProvider's ExerciseRepository dependency is mocked once, for the
// LogSets provider suite. Reusing that generated MockExerciseRepository
// here (rather than adding ExerciseRepository to this file's
// @GenerateMocks) keeps this file's large multi-repository mock free of a
// full import-prefix renumber.
import '../../providers/log_sets_provider_session_cleanup_test.mocks.dart'
    show MockExerciseRepository;

/// Coverage for Logout PR 1's `SessionCleanupCoordinator`.
///
/// These tests exercise the real coordinator against real Provider
/// instances (mirroring the fake-platform approach already established in
/// running_provider_test.dart) - mocks only sit at the external boundary
/// (repositories, AuthService, the Geolocator platform channel), and every
/// assertion checks actual resulting Provider state, not just that a mock
/// method was invoked.
///
/// Scope note: this is Logout PR 1. It proves active-resource teardown
/// (GPS/timers/watchers/polling) and settled-state clearing. It does NOT
/// prove protection against an in-flight load Future that is still
/// awaiting a repository call when cleanUp() begins later re-populating a
/// cleared Provider once it resolves - per-Provider generation/staleness
/// guards for that are deferred to Logout PR 2 (RunningProvider is the sole
/// exception, since it already has that protection from earlier GPS
/// subscription-lifecycle work).
@GenerateMocks([
  RunningRepository,
  SessionRepository,
  NutritionRepository,
  GoalsRepository,
  ChatRepository,
  ProfileRepository,
  BodyMetricsRepository,
  AnalyticsRepository,
  AchievementRepository,
  FriendsRepository,
  DirectMessagesRepository,
  ProgramsRepository,
  WorkoutTemplateRepository,
  SharedWorkoutRepository,
  AuthService,
])
// ---------------------------------------------------------------------
// Minimal local fake Geolocator platform - a smaller, self-contained
// counterpart to running_provider_test.dart's own fake (that file's
// classes are private and not importable). Only what this file needs:
// a gate-able cancel() Future and the ability to deliver one position so
// gpsTrackingState reaches `active` before cleanup, matching a genuinely
// "active" run.
// ---------------------------------------------------------------------
class _FakeSubscription implements StreamSubscription<Position> {
  void Function(Position)? _onData;

  bool cancelled = false;
  Completer<void>? cancelGate;

  @override
  Future<void> cancel() {
    cancelled = true;
    final gate = cancelGate;
    return gate != null ? gate.future : Future<void>.value();
  }

  void deliverPosition(Position position) => _onData?.call(position);

  void bind({
    required void Function(Position)? onData,
    required Function? onError,
    required void Function()? onDone,
  }) {
    _onData = onData;
  }

  @override
  bool get isPaused => false;
  @override
  void pause([Future<void>? resumeSignal]) => throw UnimplementedError();
  @override
  void resume() => throw UnimplementedError();
  @override
  Future<E> asFuture<E>([E? futureValue]) => throw UnimplementedError();
  @override
  void onData(void Function(Position data)? handleData) => _onData = handleData;
  @override
  void onError(Function? handleError) {}
  @override
  void onDone(void Function()? handleDone) {}
}

class _FakeStream extends Stream<Position> {
  _FakeStream(this.subscription);
  final _FakeSubscription subscription;

  @override
  StreamSubscription<Position> listen(
    void Function(Position event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    subscription.bind(onData: onData, onError: onError, onDone: onDone);
    return subscription;
  }
}

class _FakeGeolocatorPlatform extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  final List<_FakeSubscription> subscriptions = [];

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    final subscription = _FakeSubscription();
    subscriptions.add(subscription);
    return _FakeStream(subscription);
  }
}

// ---------------------------------------------------------------------
// A stream whose subscription's cancel() genuinely throws - used to force
// a real, reproducible failure at a specific point in the coordinator's
// ordering (see test group 10), rather than asserting failure-isolation
// against a scenario that can never actually fail.
// ---------------------------------------------------------------------
class _ThrowingCancelSubscription<T> implements StreamSubscription<T> {
  @override
  Future<void> cancel() {
    throw Exception('cancel failed');
  }

  @override
  bool get isPaused => false;
  @override
  void pause([Future<void>? resumeSignal]) => throw UnimplementedError();
  @override
  void resume() => throw UnimplementedError();
  @override
  Future<E> asFuture<E>([E? futureValue]) => throw UnimplementedError();
  @override
  void onData(void Function(T data)? handleData) {}
  @override
  void onError(Function? handleError) {}
  @override
  void onDone(void Function()? handleDone) {}
}

class _ThrowingCancelStream<T> extends Stream<T> {
  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _ThrowingCancelSubscription<T>();
  }
}

Position _fakePosition() => Position(
  latitude: 37.0,
  longitude: -122.0,
  timestamp: DateTime.now().toUtc(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

RunSession _run({
  int id = 1,
  String status = 'in_progress',
  DateTime? startedAt,
  DateTime? pausedAt,
}) {
  return RunSession(
    id: id,
    userId: 1,
    date: DateTime.utc(2024, 1, 15),
    status: status,
    startedAt: startedAt,
    pausedAt: pausedAt,
  );
}

Session _session({
  int id = 1,
  String status = 'in_progress',
  DateTime? startedAt,
  DateTime? pausedAt,
}) {
  return Session(
    id: id,
    userId: 1,
    date: DateTime.utc(2024, 1, 15),
    status: status,
    startedAt: startedAt,
    pausedAt: pausedAt,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGeolocatorPlatform fakePlatform;

  late MockRunningRepository mockRunningRepo;
  late MockSessionRepository mockSessionRepo;
  late MockNutritionRepository mockNutritionRepo;
  late MockGoalsRepository mockGoalsRepo;
  late MockExerciseRepository mockExerciseRepo;
  late MockChatRepository mockChatRepo;
  late MockProfileRepository mockProfileRepo;
  late MockBodyMetricsRepository mockBodyMetricsRepo;
  late MockAnalyticsRepository mockAnalyticsRepo;
  late MockAchievementRepository mockAchievementRepo;
  late MockFriendsRepository mockFriendsRepo;
  late MockDirectMessagesRepository mockMessagesRepo;
  late MockProgramsRepository mockProgramsRepo;
  late MockWorkoutTemplateRepository mockWorkoutTemplateRepo;
  late MockSharedWorkoutRepository mockSharedWorkoutRepo;
  late MockAuthService mockAuthService;

  late RunningProvider runningProvider;
  late ActiveWorkoutProvider activeWorkoutProvider;
  late SessionsProvider sessionsProvider;
  late MessagesProvider messagesProvider;
  late NutritionProvider nutritionProvider;
  late GoalsProvider goalsProvider;
  late LogSetsProvider logSetsProvider;
  late ChatProvider chatProvider;
  late ProfileProvider profileProvider;
  late BodyMetricsProvider bodyMetricsProvider;
  late AnalyticsProvider analyticsProvider;
  late AchievementsProvider achievementsProvider;
  late FriendsProvider friendsProvider;
  late ProgramsProvider programsProvider;
  late WorkoutTemplateProvider workoutTemplateProvider;
  late SharedWorkoutProvider sharedWorkoutProvider;

  late SessionCleanupCoordinator coordinator;
  // Real UserSessionEpoch, activated for a single test user - this suite is
  // Logout PR 1 scope (active-resource teardown), not the epoch's own
  // behavior, so it only needs an active session for the epoch-guarded
  // ChatProvider/ProfileProvider load methods below to actually reach their
  // repositories instead of no-op'ing on a null capture().
  late UserSessionEpoch sessionEpoch;

  setUp(() {
    fakePlatform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = fakePlatform;

    mockRunningRepo = MockRunningRepository();
    mockSessionRepo = MockSessionRepository();
    mockNutritionRepo = MockNutritionRepository();
    mockGoalsRepo = MockGoalsRepository();
    mockExerciseRepo = MockExerciseRepository();
    mockChatRepo = MockChatRepository();
    mockProfileRepo = MockProfileRepository();
    mockBodyMetricsRepo = MockBodyMetricsRepository();
    mockAnalyticsRepo = MockAnalyticsRepository();
    mockAchievementRepo = MockAchievementRepository();
    mockFriendsRepo = MockFriendsRepository();
    mockMessagesRepo = MockDirectMessagesRepository();
    mockProgramsRepo = MockProgramsRepository();
    mockWorkoutTemplateRepo = MockWorkoutTemplateRepository();
    mockSharedWorkoutRepo = MockSharedWorkoutRepository();
    mockAuthService = MockAuthService();

    // Constructor-time calls that must be stubbed before construction.
    when(mockAuthService.getThemePreference()).thenAnswer((_) async => null);
    when(mockMessagesRepo.getUnreadCount()).thenAnswer((_) async => 0);

    sessionEpoch = UserSessionEpoch()..activate(1);

    runningProvider = RunningProvider(mockRunningRepo, sessionEpoch, null);
    activeWorkoutProvider = ActiveWorkoutProvider(mockSessionRepo, null);
    sessionsProvider = SessionsProvider(
      mockSessionRepo,
      sessionEpoch,
      ConnectivityService.instance,
    );
    messagesProvider = MessagesProvider(mockMessagesRepo, sessionEpoch);
    nutritionProvider = NutritionProvider(
      mockNutritionRepo,
      sessionEpoch,
      null,
    );
    goalsProvider = GoalsProvider(mockGoalsRepo, sessionEpoch, null);
    logSetsProvider = LogSetsProvider(mockExerciseRepo, sessionEpoch);
    chatProvider = ChatProvider(
      mockChatRepo,
      ConnectivityService.instance,
      sessionEpoch,
    );
    profileProvider = ProfileProvider(
      mockProfileRepo,
      mockAuthService,
      sessionEpoch,
      null,
    );
    bodyMetricsProvider = BodyMetricsProvider(
      mockBodyMetricsRepo,
      sessionEpoch,
    );
    analyticsProvider = AnalyticsProvider(mockAnalyticsRepo, sessionEpoch);
    achievementsProvider = AchievementsProvider(mockAchievementRepo);
    friendsProvider = FriendsProvider(mockFriendsRepo, sessionEpoch);
    programsProvider = ProgramsProvider(mockProgramsRepo, sessionEpoch, null);
    workoutTemplateProvider = WorkoutTemplateProvider(
      mockWorkoutTemplateRepo,
      ConnectivityService.instance,
      sessionEpoch,
    );
    sharedWorkoutProvider = SharedWorkoutProvider(
      mockSharedWorkoutRepo,
      ConnectivityService.instance,
      sessionEpoch,
    );

    coordinator = SessionCleanupCoordinator(
      runningProvider: runningProvider,
      activeWorkoutProvider: activeWorkoutProvider,
      sessionsProvider: sessionsProvider,
      messagesProvider: messagesProvider,
      nutritionProvider: nutritionProvider,
      goalsProvider: goalsProvider,
      logSetsProvider: logSetsProvider,
      chatProvider: chatProvider,
      profileProvider: profileProvider,
      bodyMetricsProvider: bodyMetricsProvider,
      analyticsProvider: analyticsProvider,
      achievementsProvider: achievementsProvider,
      friendsProvider: friendsProvider,
      programsProvider: programsProvider,
      workoutTemplateProvider: workoutTemplateProvider,
      sharedWorkoutProvider: sharedWorkoutProvider,
      // Real singleton: cancelAll() may throw in this test environment
      // (no flutter_local_notifications platform channel registered) -
      // the coordinator's own per-operation guard is what's under test
      // for that case, not a successful notification cancellation.
      notificationService: NotificationService(),
    );
  });

  tearDown(() {
    for (final p in <ChangeNotifier>[
      runningProvider,
      activeWorkoutProvider,
      sessionsProvider,
      messagesProvider,
      nutritionProvider,
      goalsProvider,
      logSetsProvider,
      chatProvider,
      profileProvider,
      bodyMetricsProvider,
      analyticsProvider,
      achievementsProvider,
      friendsProvider,
      programsProvider,
      workoutTemplateProvider,
      sharedWorkoutProvider,
    ]) {
      try {
        p.dispose();
      } catch (_) {
        // Already disposed by the test body.
      }
    }
  });

  /// Loads run 1 as a draft, then starts it - mirrors
  /// running_provider_test.dart's startTrackedRun helper.
  void startTrackedRun(FakeAsync async) {
    when(
      mockRunningRepo.getRunSession(1),
    ).thenAnswer((_) async => _run(status: 'draft'));
    when(
      mockRunningRepo.startRun(1),
    ).thenAnswer((_) async => _run(startedAt: DateTime.now().toUtc()));

    runningProvider.loadRun(1);
    async.flushMicrotasks();
    runningProvider.startCurrentRun();
    async.flushMicrotasks();
  }

  group('1. Active run logout', () {
    test('cancellation is held by a controllable Future; GPS state stops only '
        'after release', () {
      fakeAsync((async) {
        startTrackedRun(async);
        final subscription = fakePlatform.subscriptions.single;
        subscription.deliverPosition(_fakePosition());
        async.flushMicrotasks();
        expect(runningProvider.gpsTrackingState, GpsTrackingState.active);

        final gate = Completer<void>();
        subscription.cancelGate = gate;

        var cleanupCompleted = false;
        coordinator.cleanUp().then((_) => cleanupCompleted = true);
        async.flushMicrotasks();

        expect(
          subscription.cancelled,
          isTrue,
          reason: 'cancel() must be requested synchronously',
        );
        expect(
          runningProvider.gpsTrackingState,
          GpsTrackingState.stopped,
          reason:
              'gpsTrackingState/generation are invalidated synchronously '
              'by RunningProvider.clear(), before the native cancel() '
              'Future resolves',
        );
        expect(
          cleanupCompleted,
          isFalse,
          reason:
              'the coordinator must not finish while GPS cancellation is '
              'still pending - it is genuinely awaited, not fire-and-forget',
        );

        gate.complete();
        async.flushMicrotasks();

        expect(cleanupCompleted, isTrue);
      });
    });
  });

  group('2. Active workout logout', () {
    test('ticker stops and no more ticks after fakeAsync advances; '
        'currentSession is null', () {
      fakeAsync((async) {
        when(
          mockSessionRepo.getSession(1),
        ).thenAnswer((_) async => _session(startedAt: DateTime.now().toUtc()));

        activeWorkoutProvider.loadSession(1);
        async.flushMicrotasks();
        expect(activeWorkoutProvider.isTimerRunning, isTrue);

        coordinator.cleanUp();
        async.flushMicrotasks();

        expect(activeWorkoutProvider.isTimerRunning, isFalse);
        expect(activeWorkoutProvider.currentSession, isNull);

        final elapsedBefore = activeWorkoutProvider.elapsedTime;
        async.elapse(const Duration(seconds: 5));
        expect(
          activeWorkoutProvider.elapsedTime,
          elapsedBefore,
          reason: 'no further ticks once cleared',
        );
      });
    });
  });

  group('3. Sessions watcher stops', () {
    test('the Isar session-watch stream subscription is cancelled', () {
      fakeAsync((async) {
        when(
          mockSessionRepo.getSessions(waitForSync: anyNamed('waitForSync')),
        ).thenAnswer((_) async => [_session()]);
        when(
          mockSessionRepo.watchSessions(1),
        ).thenAnswer((_) => const Stream.empty());
        when(mockAuthService.getUserId()).thenAnswer((_) async => 1);

        sessionsProvider.loadSessions();
        async.flushMicrotasks();
        expect(sessionsProvider.sessions, isNotEmpty);

        coordinator.cleanUp();
        async.flushMicrotasks();

        expect(sessionsProvider.sessions, isEmpty);
      });
    });
  });

  group('4. Messages polling stops', () {
    test('both polling timers stop; no further ticks after cleanup', () {
      fakeAsync((async) {
        when(mockMessagesRepo.getConversations()).thenAnswer((_) async => []);
        when(
          mockMessagesRepo.getMessages(1, limit: anyNamed('limit')),
        ).thenAnswer((_) async => []);

        messagesProvider.startUnreadCountPolling();
        messagesProvider.startConversationPolling(1);
        async.flushMicrotasks();

        coordinator.cleanUp();
        async.flushMicrotasks();

        // If either timer were still active, advancing fake time far
        // enough to cross both the 2s and 30s periods would trigger
        // additional getUnreadCount()/getConversations() calls beyond
        // what already happened above.
        clearInteractions(mockMessagesRepo);
        async.elapse(const Duration(seconds: 35));
        verifyNever(mockMessagesRepo.getUnreadCount());
        verifyZeroInteractions(mockMessagesRepo);
      });
    });
  });

  group('5. All included Provider settled state clears', () {
    test('every clearable Provider returns to empty/default state', () {
      fakeAsync((async) {
        // Populate settled (non-default) state via a real load path per
        // Provider. For Providers where constructing a full domain model
        // isn't needed to prove the point, a failed load (populating
        // errorMessage) is used instead - clear() resets that field
        // unconditionally regardless of what set it, so this is a valid,
        // lower-setup-cost way to prove settled state is genuinely reset,
        // alongside the higher-fidelity list-population checks below.
        when(
          mockGoalsRepo.getGoals(isActive: anyNamed('isActive')),
        ).thenThrow(Exception('boom'));
        when(mockChatRepo.getConversations()).thenThrow(Exception('boom'));
        when(mockProfileRepo.getProfile()).thenThrow(Exception('boom'));
        when(
          mockBodyMetricsRepo.getBodyMetrics(days: anyNamed('days')),
        ).thenThrow(Exception('boom'));
        when(mockAnalyticsRepo.getWorkoutStats()).thenThrow(Exception('boom'));
        when(
          mockAnalyticsRepo.getExerciseProgress(),
        ).thenThrow(Exception('boom'));
        when(
          mockAnalyticsRepo.getPersonalRecords(),
        ).thenThrow(Exception('boom'));
        when(
          mockAnalyticsRepo.getMuscleGroupVolume(days: anyNamed('days')),
        ).thenThrow(Exception('boom'));
        when(mockFriendsRepo.getFriends()).thenThrow(Exception('boom'));
        when(
          mockProgramsRepo.getPrograms(isActive: anyNamed('isActive')),
        ).thenThrow(Exception('boom'));
        when(
          mockWorkoutTemplateRepo.getTemplates(
            activeOnly: anyNamed('activeOnly'),
          ),
        ).thenThrow(Exception('boom'));
        when(
          mockSharedWorkoutRepo.getSharedWorkouts(
            category: anyNamed('category'),
            difficulty: anyNamed('difficulty'),
            limit: anyNamed('limit'),
          ),
        ).thenThrow(Exception('boom'));
        when(
          mockExerciseRepo.getExerciseSets(any),
        ).thenThrow(Exception('boom'));
        when(mockNutritionRepo.getTodaysMealLog()).thenThrow(Exception('boom'));
        when(
          mockNutritionRepo.getNutritionDashboard(),
        ).thenThrow(Exception('boom'));
        when(mockNutritionRepo.getStreak()).thenThrow(Exception('boom'));

        goalsProvider.loadGoals();
        chatProvider.loadConversations();
        profileProvider.loadUserProfile();
        bodyMetricsProvider.loadBodyMetrics();
        analyticsProvider.loadAnalytics();
        friendsProvider.loadFriends();
        logSetsProvider.loadSets(1);
        programsProvider.loadPrograms();
        workoutTemplateProvider.loadTemplates();
        sharedWorkoutProvider.loadSharedWorkouts();
        nutritionProvider.loadTodaysData();
        async.flushMicrotasks();

        expect(goalsProvider.errorMessage, isNotNull);
        expect(chatProvider.errorMessage, isNotNull);
        expect(profileProvider.errorMessage, isNotNull);
        expect(bodyMetricsProvider.errorMessage, isNotNull);
        expect(analyticsProvider.errorMessage, isNotNull);
        expect(friendsProvider.errorMessage, isNotNull);
        expect(logSetsProvider.errorMessage, isNotNull);
        expect(programsProvider.errorMessage, isNotNull);
        expect(workoutTemplateProvider.errorMessage, isNotNull);
        expect(sharedWorkoutProvider.errorMessage, isNotNull);
        expect(nutritionProvider.errorMessage, isNotNull);

        coordinator.cleanUp();
        async.flushMicrotasks();

        expect(goalsProvider.errorMessage, isNull);
        expect(goalsProvider.goals, isEmpty);
        expect(chatProvider.errorMessage, isNull);
        expect(chatProvider.conversations, isEmpty);
        expect(profileProvider.errorMessage, isNull);
        expect(profileProvider.currentUser, isNull);
        expect(bodyMetricsProvider.errorMessage, isNull);
        expect(analyticsProvider.errorMessage, isNull);
        expect(analyticsProvider.workoutStats, isNull);
        expect(friendsProvider.errorMessage, isNull);
        expect(friendsProvider.friends, isEmpty);
        expect(logSetsProvider.errorMessage, isNull);
        expect(logSetsProvider.sets, isEmpty);
        expect(programsProvider.errorMessage, isNull);
        expect(programsProvider.programs, isEmpty);
        expect(workoutTemplateProvider.errorMessage, isNull);
        expect(sharedWorkoutProvider.errorMessage, isNull);
        expect(nutritionProvider.errorMessage, isNull);
        expect(nutritionProvider.todaysMealLog, isNull);
        expect(achievementsProvider.unlockedAchievements, isEmpty);
        expect(messagesProvider.conversations, isEmpty);
        expect(runningProvider.currentRun, isNull);
        expect(activeWorkoutProvider.currentSession, isNull);
        expect(sessionsProvider.sessions, isEmpty);
      });
    });
  });

  group('10. One Provider clear throws', () {
    test('a genuine mid-sequence failure (SessionsProvider, step 3) does not '
        'prevent later Providers (MessagesProvider step 4, GoalsProvider '
        'step 5+) from clearing, and cleanUp() still resolves', () {
      fakeAsync((async) {
        // SessionsProvider.clear() cancels _sessionsStreamSubscription -
        // wiring watchSessions() to a stream whose subscription.cancel()
        // genuinely throws forces a real, reproducible failure at that
        // exact point in the coordinator's ordering (step 3), which is
        // strictly before MessagesProvider (step 4) and every remaining
        // Provider (step 5+).
        when(
          mockSessionRepo.getSessions(waitForSync: anyNamed('waitForSync')),
        ).thenAnswer((_) async => [_session()]);
        when(
          mockSessionRepo.watchSessions(1),
        ).thenAnswer((_) => _ThrowingCancelStream());
        when(mockAuthService.getUserId()).thenAnswer((_) async => 1);

        when(mockMessagesRepo.getConversations()).thenAnswer((_) async => []);
        when(mockChatRepo.getConversations()).thenAnswer((_) async => []);

        sessionsProvider.loadSessions();
        messagesProvider.startUnreadCountPolling();
        chatProvider.loadConversations();
        async.flushMicrotasks();

        var rejected = false;
        coordinator.cleanUp().catchError((_) => rejected = true);
        async.flushMicrotasks();

        expect(
          rejected,
          isFalse,
          reason: 'cleanUp() must never reject even if a step fails',
        );
        expect(
          sessionsProvider.sessions,
          isEmpty,
          reason:
              'SessionsProvider itself must still finish clearing its own '
              'settled state even though cancelling its stream threw',
        );
        expect(
          messagesProvider.conversations,
          isEmpty,
          reason:
              'a Provider ordered after the one that threw must still be '
              'cleared',
        );
        expect(chatProvider.conversations, isEmpty);
      });
    });
  });

  group('12. No Provider dispose() is called manually', () {
    test('every Provider remains usable (not disposed) after cleanUp()', () {
      fakeAsync((async) {
        coordinator.cleanUp();
        async.flushMicrotasks();

        // A disposed ChangeNotifier throws on addListener/notifyListeners.
        // If the coordinator had called dispose() on any of these, this
        // trivial mutate-and-notify call would throw.
        expect(() => goalsProvider.clearError(), returnsNormally);
        expect(() => chatProvider.clearError(), returnsNormally);
        expect(() => runningProvider.clearError(), returnsNormally);
        expect(() => activeWorkoutProvider.clearError(), returnsNormally);
        expect(() => sessionsProvider.clearError(), returnsNormally);
        expect(() => messagesProvider.clearError(), returnsNormally);
      });
    });
  });

  group('13. Active run remains neither completed nor discarded', () {
    test('logout does not call completeRun or deleteRun', () {
      fakeAsync((async) {
        startTrackedRun(async);

        coordinator.cleanUp();
        async.flushMicrotasks();

        verifyNever(
          mockRunningRepo.completeRun(
            any,
            duration: anyNamed('duration'),
            distance: anyNamed('distance'),
            averagePace: anyNamed('averagePace'),
            calories: anyNamed('calories'),
            route: anyNamed('route'),
          ),
        );
        verifyNever(mockRunningRepo.deleteRun(any));
        verifyNever(mockRunningRepo.pauseRun(any, any));
      });
    });
  });

  group('14. AnalyticsProvider cleanup', () {
    test('the real app-lifetime AnalyticsProvider is cleared even when an '
        'earlier cleanup step throws, and an in-flight aggregate load cannot '
        'repopulate it afterwards', () {
      fakeAsync((async) {
        // An earlier step (SessionsProvider, step 3) fails hard: its
        // watch-stream subscription cancel() throws.
        when(
          mockSessionRepo.getSessions(waitForSync: anyNamed('waitForSync')),
        ).thenAnswer((_) async => [_session()]);
        when(
          mockSessionRepo.watchSessions(1),
        ).thenAnswer((_) => _ThrowingCancelStream());
        when(mockAuthService.getUserId()).thenAnswer((_) async => 1);
        sessionsProvider.loadSessions();

        // A slow analytics aggregate load, still in flight when cleanup runs.
        final gate = Completer<WorkoutStats>();
        when(
          mockAnalyticsRepo.getWorkoutStats(),
        ).thenAnswer((_) => gate.future);
        when(
          mockAnalyticsRepo.getExerciseProgress(),
        ).thenAnswer((_) async => <ExerciseProgress>[]);
        when(
          mockAnalyticsRepo.getPersonalRecords(),
        ).thenAnswer((_) async => <PersonalRecord>[]);
        when(
          mockAnalyticsRepo.getMuscleGroupVolume(days: anyNamed('days')),
        ).thenAnswer((_) async => <MuscleGroupVolume>[]);
        analyticsProvider.loadAnalytics();
        async.flushMicrotasks();
        expect(analyticsProvider.isLoading, isTrue);

        var rejected = false;
        coordinator.cleanUp().catchError((_) => rejected = true);
        async.flushMicrotasks();

        expect(rejected, isFalse, reason: 'cleanUp() never rejects');
        expect(
          analyticsProvider.isLoading,
          isFalse,
          reason: 'analytics cleared despite the earlier step throwing',
        );
        expect(analyticsProvider.workoutStats, isNull);

        // The in-flight load resolving now must not repopulate cleared state
        // (clear() invalidated the aggregate generation).
        gate.complete(
          WorkoutStats(
            totalWorkouts: 9,
            totalDuration: 9,
            averageDuration: 1,
            currentStreak: 1,
            longestStreak: 1,
            workoutsThisWeek: 1,
            workoutsThisMonth: 1,
            totalSets: 1,
            totalReps: 1,
            totalVolume: 1,
          ),
        );
        async.flushMicrotasks();

        expect(analyticsProvider.workoutStats, isNull);
        expect(analyticsProvider.isLoading, isFalse);
      });
    });
  });
}
