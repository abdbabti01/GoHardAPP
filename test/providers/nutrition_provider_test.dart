import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/daily_nutrition_progress.dart';
import 'package:go_hard_app/data/models/food_item.dart';
import 'package:go_hard_app/data/models/meal_log.dart';
import 'package:go_hard_app/data/models/nutrition_goal.dart';
import 'package:go_hard_app/data/models/nutrition_summary.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/providers/nutrition_provider.dart';

@GenerateMocks([NutritionRepository, ConnectivityService])
import 'nutrition_provider_test.mocks.dart';

/// Nutrition lifecycle PR 1 coverage: proves NutritionProvider drops any
/// response that resolves after the session that requested it has ended -
/// logout, or a different user logging in - instead of writing stale data
/// into a shared provider instance the next session also uses, and that
/// [NutritionProvider.loadNutritionHistory] always commits the most
/// recently *requested* history filter regardless of resolution order.
///
/// Scope note: this only proves NutritionProvider's own in-memory state is
/// protected. It does NOT prove NutritionRepository's local Isar writes or
/// background sync pushes are session-scoped - those are explicitly
/// deferred to a later PR (see the investigation this PR is based on).
void main() {
  late MockNutritionRepository mockRepository;
  late UserSessionEpoch sessionEpoch;
  late NutritionProvider provider;

  MealLog mealLog(int id, {int userId = 1}) => MealLog(
    id: id,
    userId: userId,
    date: DateTime.utc(2024, 1, 1),
    createdAt: DateTime.utc(2024, 1, 1),
  );

  NutritionGoal goal(int id, {int userId = 1, double dailyCalories = 2000}) =>
      NutritionGoal(
        id: id,
        userId: userId,
        dailyCalories: dailyCalories,
        createdAt: DateTime.utc(2024, 1, 1),
      );

  DailyNutritionProgress progress(int userId) => DailyNutritionProgress(
    id: 1,
    userId: userId,
    date: DateTime.utc(2024, 1, 1),
    createdAt: DateTime.utc(2024, 1, 1),
  );

  NutritionDashboardData dashboard({NutritionGoal? g, int userId = 1}) =>
      NutritionDashboardData(
        date: DateTime.utc(2024, 1, 1),
        goal: g,
        progress: progress(userId),
      );

  StreakInfo streak() => StreakInfo(currentStreak: 0, longestStreak: 0);

  FoodItem foodItem(int id) => FoodItem(
    id: id,
    mealEntryId: 1,
    name: 'Test food',
    calories: 100,
    protein: 10,
    carbohydrates: 10,
    fat: 5,
    createdAt: DateTime.utc(2024, 1, 1),
  );

  void stubHappyLoadTodaysData({MealLog? log, NutritionGoal? g}) {
    when(
      mockRepository.getTodaysMealLog(),
    ).thenAnswer((_) async => log ?? mealLog(1));
    when(
      mockRepository.getNutritionDashboard(date: anyNamed('date')),
    ).thenAnswer((_) async => dashboard(g: g));
    when(mockRepository.getStreak()).thenAnswer((_) async => streak());
  }

  setUp(() {
    mockRepository = MockNutritionRepository();
    sessionEpoch = UserSessionEpoch();
    provider = NutritionProvider(mockRepository, sessionEpoch);
  });

  group('loadTodaysData', () {
    test('1. with no active session, never calls the repository', () async {
      await provider.loadTodaysData();

      verifyNever(mockRepository.getTodaysMealLog());
      expect(provider.todaysMealLog, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('2. a response that resolves after logout is dropped', () async {
      sessionEpoch.activate(1);
      final completer = Completer<MealLog>();
      when(
        mockRepository.getTodaysMealLog(),
      ).thenAnswer((_) => completer.future);
      when(
        mockRepository.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer((_) async => dashboard());
      when(mockRepository.getStreak()).thenAnswer((_) async => streak());

      final future = provider.loadTodaysData();
      expect(provider.isLoading, isTrue);

      sessionEpoch.invalidate();
      completer.complete(mealLog(1));
      await future;

      expect(provider.todaysMealLog, isNull);
      expect(provider.errorMessage, isNull);
      expect(
        provider.isLoading,
        isTrue,
        reason:
            'stale completion must not touch isLoading either - '
            'clear() (called during logout cleanup) owns resetting it',
      );
    });

    test('3. a response that resolves after User B login is dropped', () async {
      sessionEpoch.activate(1);
      final completer = Completer<MealLog>();
      when(
        mockRepository.getTodaysMealLog(),
      ).thenAnswer((_) => completer.future);
      when(
        mockRepository.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer((_) async => dashboard());
      when(mockRepository.getStreak()).thenAnswer((_) async => streak());

      final futureA = provider.loadTodaysData();

      sessionEpoch.invalidate();
      sessionEpoch.activate(2);

      completer.complete(mealLog(1));
      await futureA;

      expect(
        provider.todaysMealLog,
        isNull,
        reason: "User A's stale meal log must never become User B's data",
      );
    });

    test('4/5/6. User B\'s legitimate load can start while User A\'s stale '
        'load remains pending; A\'s late error does not surface, and A\'s '
        'stale finally does not clear B\'s in-flight loading state', () async {
      sessionEpoch.activate(1);
      final completerA = Completer<MealLog>();
      when(
        mockRepository.getTodaysMealLog(),
      ).thenAnswer((_) => completerA.future);
      when(
        mockRepository.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer((_) async => dashboard());
      when(mockRepository.getStreak()).thenAnswer((_) async => streak());

      final futureA = provider.loadTodaysData();
      expect(provider.isLoading, isTrue);

      // User A logs out, User B logs in - A's request is still pending.
      sessionEpoch.invalidate();
      sessionEpoch.activate(2);

      final completerB = Completer<MealLog>();
      when(
        mockRepository.getTodaysMealLog(),
      ).thenAnswer((_) => completerB.future);

      // B's own load must be allowed to start - no blanket "already
      // loading" guard blocks it just because A's obsolete request is
      // still in flight.
      final futureB = provider.loadTodaysData();
      expect(provider.isLoading, isTrue);

      // A's request now fails - this must never surface as an error on
      // whatever session is now active (B's).
      completerA.completeError(Exception('stale boom'));
      await futureA;

      expect(provider.errorMessage, isNull);
      expect(
        provider.isLoading,
        isTrue,
        reason:
            "A's stale finally must not clear B's own in-flight loading "
            'state',
      );

      // B's own request now resolves normally.
      completerB.complete(mealLog(2, userId: 2));
      await futureB;

      expect(provider.isLoading, isFalse);
      expect(provider.todaysMealLog?.id, 2);
    });

    test('23. a same-session response is applied normally', () async {
      sessionEpoch.activate(1);
      stubHappyLoadTodaysData(g: goal(1));

      await provider.loadTodaysData();

      expect(provider.todaysMealLog?.id, 1);
      expect(provider.activeGoal?.id, 1);
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

    test('7. while logged out, a connectivity-restored event does not call '
        'the repository or alter state', () async {
      // loadTodaysData() independently self-guards on a null capture()
      // too, so a plain repository-call-count assertion alone cannot
      // distinguish "the listener's own guard skipped this" from "the
      // listener called loadTodaysData(), which then no-op'd on its own."
      // Intercept debugPrint to prove the listener itself never even
      // attempts the refresh while logged out, not just that the
      // repository was never reached.
      final originalDebugPrint = debugPrint;
      final printedMessages = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printedMessages.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final loggedOutProvider = NutritionProvider(
        mockRepository,
        sessionEpoch,
        mockConnectivity,
      );

      connectivityController.add(true);
      await pumpEventQueue();

      verifyNever(mockRepository.getTodaysMealLog());
      expect(loggedOutProvider.todaysMealLog, isNull);
      expect(loggedOutProvider.errorMessage, isNull);
      expect(loggedOutProvider.isLoading, isFalse);
      expect(
        printedMessages.any((m) => m.contains('Connection restored')),
        isFalse,
        reason:
            'the connectivity listener must never even attempt a refresh '
            'while logged out',
      );
    });

    test('8. while authenticated, a connectivity-restored event triggers the '
        'intended refresh', () async {
      sessionEpoch.activate(1);
      stubHappyLoadTodaysData();

      final onlineProvider = NutritionProvider(
        mockRepository,
        sessionEpoch,
        mockConnectivity,
      );

      // The listener only refreshes when _todaysMealLog is still null -
      // true for a freshly constructed provider, matching how the app
      // actually reaches this state.
      connectivityController.add(true);
      await pumpEventQueue();

      verify(mockRepository.getTodaysMealLog()).called(1);
      expect(onlineProvider.todaysMealLog?.id, 1);
    });

    test('9. a connectivity-triggered refresh invalidated mid-flight is '
        'discarded', () async {
      sessionEpoch.activate(1);
      final completer = Completer<MealLog>();
      when(
        mockRepository.getTodaysMealLog(),
      ).thenAnswer((_) => completer.future);
      when(
        mockRepository.getNutritionDashboard(date: anyNamed('date')),
      ).thenAnswer((_) async => dashboard());
      when(mockRepository.getStreak()).thenAnswer((_) async => streak());

      final onlineProvider = NutritionProvider(
        mockRepository,
        sessionEpoch,
        mockConnectivity,
      );

      connectivityController.add(true);
      await pumpEventQueue();
      expect(onlineProvider.isLoading, isTrue);

      sessionEpoch.invalidate();
      completer.complete(mealLog(1));
      await pumpEventQueue();

      expect(onlineProvider.todaysMealLog, isNull);
    });
  });

  group('updateNutritionGoal / createNutritionGoal', () {
    test('10. createNutritionGoal completion from A cannot overwrite B\'s '
        'active goal', () async {
      sessionEpoch.activate(1);
      final completer = Completer<NutritionGoal>();
      when(
        mockRepository.createNutritionGoal(any),
      ).thenAnswer((_) => completer.future);

      final future = provider.createNutritionGoal(
        dailyCalories: 1800,
        dailyProtein: 140,
        dailyCarbohydrates: 180,
        dailyFat: 60,
      );
      sessionEpoch.invalidate();
      sessionEpoch.activate(2);
      completer.complete(goal(1, dailyCalories: 1800));

      final result = await future;

      expect(result, isFalse);
      expect(
        provider.activeGoal,
        isNull,
        reason: "A's created goal must never become B's active goal",
      );
    });

    test('11. updateNutritionGoal completion from A cannot overwrite B\'s '
        'active goal', () async {
      sessionEpoch.activate(1);
      stubHappyLoadTodaysData(g: goal(1, dailyCalories: 2000));
      await provider.loadTodaysData();
      expect(provider.activeGoal?.dailyCalories, 2000);

      final completer = Completer<void>();
      when(
        mockRepository.updateNutritionGoal(any, any),
      ).thenAnswer((_) => completer.future);

      final future = provider.updateNutritionGoal(
        dailyCalories: 1500,
        dailyProtein: 120,
        dailyCarbohydrates: 150,
        dailyFat: 50,
      );

      sessionEpoch.invalidate();
      sessionEpoch.activate(2);
      completer.complete();

      final result = await future;

      expect(result, isFalse);
      // No clear() has run in this raw unit test (the real logout path
      // would call it via SessionCleanupCoordinator, tested separately),
      // so `_activeGoal` still holds whatever it was before A's edit -
      // the point is that it must NOT have been overwritten with A's
      // 1500-calorie edit now that B's session is active.
      expect(
        provider.activeGoal?.dailyCalories,
        2000,
        reason:
            "A's stale edit must never be applied once a different "
            'session is active',
      );
    });
  });

  group('nested reload ownership', () {
    test('12. quickAddFood finishing after session invalidation does not '
        'start a nested reload', () async {
      sessionEpoch.activate(1);
      stubHappyLoadTodaysData();
      await provider.loadTodaysData();
      verify(mockRepository.getTodaysMealLog()).called(1);

      final completer = Completer<FoodItem>();
      when(
        mockRepository.quickAddFood(
          mealEntryId: anyNamed('mealEntryId'),
          foodTemplateId: anyNamed('foodTemplateId'),
          quantity: anyNamed('quantity'),
        ),
      ).thenAnswer((_) => completer.future);

      final future = provider.quickAddFood(mealEntryId: 1, foodTemplateId: 2);
      sessionEpoch.invalidate();
      completer.complete(foodItem(1));

      final result = await future;

      expect(result, isFalse);
      verifyNever(mockRepository.getTodaysMealLog());
    });

    test('13. markMealAsConsumed finishing after invalidation does not start '
        'a nested reload', () async {
      sessionEpoch.activate(1);
      stubHappyLoadTodaysData();
      await provider.loadTodaysData();
      verify(mockRepository.getTodaysMealLog()).called(1);

      final completer = Completer<void>();
      when(
        mockRepository.markMealAsConsumed(
          any,
          isConsumed: anyNamed('isConsumed'),
          consumedAt: anyNamed('consumedAt'),
        ),
      ).thenAnswer((_) => completer.future);

      final future = provider.markMealAsConsumed(1);
      sessionEpoch.invalidate();
      completer.complete();

      final result = await future;

      expect(result, isFalse);
      verifyNever(mockRepository.getTodaysMealLog());
    });

    test('14. updateWaterIntake finishing after invalidation does not start '
        'a nested reload', () async {
      sessionEpoch.activate(1);
      stubHappyLoadTodaysData();
      await provider.loadTodaysData();
      verify(mockRepository.getTodaysMealLog()).called(1);

      final completer = Completer<void>();
      when(
        mockRepository.updateWaterIntake(any, any),
      ).thenAnswer((_) => completer.future);

      final future = provider.updateWaterIntake(500);
      sessionEpoch.invalidate();
      completer.complete();

      final result = await future;

      expect(result, isFalse);
      verifyNever(mockRepository.getTodaysMealLog());
    });

    test('15. clearAllFood finishing after invalidation does not start a '
        'nested reload', () async {
      sessionEpoch.activate(1);
      stubHappyLoadTodaysData();
      await provider.loadTodaysData();
      verify(mockRepository.getTodaysMealLog()).called(1);

      final completer = Completer<MealLog>();
      when(
        mockRepository.clearAllFood(any),
      ).thenAnswer((_) => completer.future);

      final future = provider.clearAllFood();
      sessionEpoch.invalidate();
      completer.complete(mealLog(1));

      final result = await future;

      expect(result, isFalse);
      verifyNever(mockRepository.getTodaysMealLog());
    });

    test('16. a nested reload already in flight cannot repopulate B\'s '
        'MealLog', () async {
      sessionEpoch.activate(1);
      stubHappyLoadTodaysData();
      await provider.loadTodaysData();
      verify(mockRepository.getTodaysMealLog()).called(1);

      // The mutation itself succeeds while the session is still valid,
      // so the nested reload DOES start (unlike tests 12-15).
      when(
        mockRepository.quickAddFood(
          mealEntryId: anyNamed('mealEntryId'),
          foodTemplateId: anyNamed('foodTemplateId'),
          quantity: anyNamed('quantity'),
        ),
      ).thenAnswer((_) async => foodItem(1));

      final reloadCompleter = Completer<MealLog>();
      when(
        mockRepository.getTodaysMealLog(),
      ).thenAnswer((_) => reloadCompleter.future);

      final future = provider.quickAddFood(mealEntryId: 1, foodTemplateId: 2);

      // Session ends while the nested loadTodaysData() call it started
      // is itself still in flight. The reload resolves with a distinctly
      // different id so a corruption would be observable rather than
      // masked by coincidentally-identical fixture data.
      sessionEpoch.invalidate();
      sessionEpoch.activate(2);
      reloadCompleter.complete(mealLog(999));

      final result = await future;

      expect(result, isFalse);
      // No clear() has run in this raw unit test, so `_todaysMealLog`
      // still holds whatever the initial loadTodaysData() set it to - the
      // point is that A's stale reload must not have overwritten it with
      // its own (id: 999) result once B's session is active.
      expect(
        provider.todaysMealLog?.id,
        1,
        reason:
            "A's in-flight nested reload must not repopulate "
            "todaysMealLog once B is active",
      );
    });
  });

  group('clear()', () {
    test('17/18. clear() immediately clears all nutrition state while work '
        'remains pending, and the stale completion afterward does not '
        'restore it', () async {
      sessionEpoch.activate(1);
      stubHappyLoadTodaysData(g: goal(1));
      await provider.loadTodaysData();
      expect(provider.todaysMealLog, isNotNull);
      expect(provider.activeGoal, isNotNull);

      final completer = Completer<void>();
      when(
        mockRepository.updateWaterIntake(any, any),
      ).thenAnswer((_) => completer.future);

      final future = provider.updateWaterIntake(250);
      expect(provider.todaysMealLog, isNotNull);

      // clear() runs immediately, synchronously, while the mutation
      // above is still pending.
      provider.clear();

      expect(provider.todaysMealLog, isNull);
      expect(provider.activeGoal, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);

      // The real logout path also invalidates the session at this point;
      // reproduce that so the still-pending mutation's own guard also
      // sees a stale token.
      sessionEpoch.invalidate();
      completer.complete();
      final result = await future;

      expect(result, isFalse);
      expect(
        provider.todaysMealLog,
        isNull,
        reason: 'a stale catch/finally must not restore cleared state',
      );
    });

    test('22. clear() invalidates all outstanding history requests', () async {
      sessionEpoch.activate(1);
      final completer = Completer<List<MealLog>>();
      when(
        mockRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) => completer.future);

      final future = provider.loadNutritionHistory();
      expect(provider.isLoadingHistory, isTrue);

      provider.clear();
      expect(provider.isLoadingHistory, isFalse);

      completer.complete([mealLog(1)]);
      await future;

      expect(
        provider.nutritionHistory,
        isEmpty,
        reason:
            'clear() must invalidate the in-flight history request '
            'even though the session token alone did not change',
      );
      expect(provider.isLoadingHistory, isFalse);
    });
  });

  group('history request generation', () {
    test(
      '19. History Filter A resolving after Filter B cannot overwrite B',
      () async {
        sessionEpoch.activate(1);
        final completerWeek = Completer<List<MealLog>>();
        final completerMonth = Completer<List<MealLog>>();
        when(
          mockRepository.getMealLogs(
            startDate: anyNamed('startDate'),
            endDate: anyNamed('endDate'),
          ),
        ).thenAnswer((_) => completerWeek.future);

        final futureWeek = provider.loadNutritionHistory(); // filter='week'

        when(
          mockRepository.getMealLogs(
            startDate: anyNamed('startDate'),
            endDate: anyNamed('endDate'),
          ),
        ).thenAnswer((_) => completerMonth.future);
        provider.setHistoryFilter('month');
        expect(provider.historyFilter, 'month');

        // The OLDER request (week) resolves AFTER the newer one (month)
        // was requested.
        completerWeek.complete([mealLog(1)]);
        await futureWeek;

        expect(
          provider.nutritionHistory,
          isEmpty,
          reason:
              "the stale 'week' response must not overwrite whatever "
              "'month' eventually loads",
        );
        expect(
          provider.isLoadingHistory,
          isTrue,
          reason: "the still-pending 'month' request owns isLoadingHistory",
        );

        completerMonth.complete([mealLog(2), mealLog(3)]);
        await Future<void>.delayed(Duration.zero);

        expect(provider.nutritionHistory, hasLength(2));
        expect(provider.isLoadingHistory, isFalse);
      },
    );

    test('20. History A -> B -> A commits only the third request, not the '
        'first', () async {
      sessionEpoch.activate(1);
      final completer1 = Completer<List<MealLog>>();
      final completer2 = Completer<List<MealLog>>();
      final completer3 = Completer<List<MealLog>>();

      when(
        mockRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) => completer1.future);
      final future1 = provider.loadNutritionHistory(); // request #1, week

      when(
        mockRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) => completer2.future);
      provider.setHistoryFilter('month'); // request #2, month

      when(
        mockRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) => completer3.future);
      provider.setHistoryFilter('week'); // request #3, week again - same
      // filter string as #1, but a strictly newer generation.

      // Resolve out of order: #1 first, then #3, then #2. Only #3 (the
      // latest requested generation) may ever commit, even though #1
      // shares its filter string.
      completer1.complete([mealLog(101)]);
      await future1;
      expect(provider.nutritionHistory, isEmpty);

      completer3.complete([mealLog(303)]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.nutritionHistory, hasLength(1));
      expect(provider.nutritionHistory.single.id, 303);

      completer2.complete([mealLog(202), mealLog(204)]);
      await Future<void>.delayed(Duration.zero);
      expect(
        provider.nutritionHistory.single.id,
        303,
        reason:
            "request #2 ('month') resolving last must still lose to "
            "request #3's generation",
      );
      expect(provider.isLoadingHistory, isFalse);
    });

    test('21. a stale history finally cannot clear the newest request\'s '
        'loading state', () async {
      sessionEpoch.activate(1);
      final completerOld = Completer<List<MealLog>>();
      final completerNew = Completer<List<MealLog>>();

      when(
        mockRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) => completerOld.future);
      final futureOld = provider.loadNutritionHistory();

      when(
        mockRepository.getMealLogs(
          startDate: anyNamed('startDate'),
          endDate: anyNamed('endDate'),
        ),
      ).thenAnswer((_) => completerNew.future);
      provider.setHistoryFilter('month');
      expect(provider.isLoadingHistory, isTrue);

      completerOld.completeError(Exception('stale boom'));
      await futureOld;

      expect(
        provider.isLoadingHistory,
        isTrue,
        reason:
            "the old request's finally must not clear the newest "
            "request's isLoadingHistory",
      );

      completerNew.complete([mealLog(1)]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.isLoadingHistory, isFalse);
    });
  });
}
