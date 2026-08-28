import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/models/local_food_item.dart';
import 'package:go_hard_app/data/local/models/local_food_template.dart';
import 'package:go_hard_app/data/local/models/local_meal_entry.dart';
import 'package:go_hard_app/data/local/models/local_meal_log.dart';
import 'package:go_hard_app/data/local/models/local_nutrition_goal.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/food_item.dart';
import 'package:go_hard_app/data/models/food_template.dart';
import 'package:go_hard_app/data/models/nutrition_goal.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'nutrition_repository_background_session_test.mocks.dart';

@GenerateMocks([AuthService, ConnectivityService])
/// Proves that every detached/background HTTP operation NutritionRepository
/// schedules is bound to the session that was active at SCHEDULING time -
/// never whichever session happens to be active when the detached work
/// finally runs - and that every local acknowledgment it may perform is
/// re-guarded against a session change at each of the three checkpoints
/// (post-HTTP, pre-writeTxn, first-statement-inside-writeTxn).
///
/// Uses a REAL [ApiService] wired to a fake [HttpClientAdapter] rather than
/// a mocked ApiService, so credential pinning (the actual `Authorization`
/// header Dio would send) and dispatch-time staleness rejection are proven
/// against the real production interceptor pipeline, not a stub of it.
void main() {
  late Isar isar;
  late Directory tempDir;
  late MockAuthService mockAuthService;
  late MockConnectivityService mockConnectivity;
  late LocalDatabaseService localDb;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late NutritionRepository repository;

  const userA = 1;
  const userB = 2;

  // The user AuthService currently reports as logged in - kept in lockstep
  // with sessionEpoch by loginAs()/logout() below, exactly like
  // AuthProvider keeps the two in sync in production.
  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'nutrition_repo_bg_session_',
    );
    isar = await Isar.open(
      [
        LocalMealLogSchema,
        LocalMealEntrySchema,
        LocalFoodItemSchema,
        LocalNutritionGoalSchema,
        LocalFoodTemplateSchema,
      ],
      directory: tempDir.path,
      inspector: false,
    );

    currentAuthUserId = null;
    mockAuthService = MockAuthService();
    mockConnectivity = MockConnectivityService();
    when(mockConnectivity.isOnline).thenReturn(true);
    when(
      mockAuthService.getUserId(),
    ).thenAnswer((_) async => currentAuthUserId);
    when(mockAuthService.getToken()).thenAnswer(
      (_) async => currentAuthUserId == null ? null : 'jwt-$currentAuthUserId',
    );

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch();
    sessionCoordinator = SessionRequestCoordinator(
      sessionEpoch,
      mockAuthService,
    );
    apiService = ApiService(mockAuthService, sessionEpoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;

    repository = NutritionRepository(
      apiService,
      localDb,
      mockConnectivity,
      mockAuthService,
      sessionEpoch,
      sessionCoordinator,
    );
  });

  tearDown(() async {
    repository.beforeWriteTxnForTesting = null;
    repository.insideWriteTxnForTesting = null;
    repository.afterWriteTxnForTesting = null;
    repository.beforeBackgroundHttpDispatchForTesting = null;
    repository.afterBackgroundHttpResponseForTesting = null;
    repository.insideBackgroundWriteTxnForTesting = null;
    apiService.beforeDispatchEpochCheckForTesting = null;
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  void loginAs(int userId) {
    currentAuthUserId = userId;
    sessionEpoch.activate(userId);
  }

  void logout() {
    currentAuthUserId = null;
    sessionEpoch.invalidate();
  }

  DateTime todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<LocalMealLog> insertMealLog({
    required int uid,
    DateTime? date,
    int? serverId,
    double waterIntake = 0,
  }) async {
    final now = DateTime.now();
    final log = LocalMealLog(
      serverId: serverId,
      userId: uid,
      date: date ?? DateTime(2026, 1, 1),
      waterIntake: waterIntake,
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localMealLogs.put(log));
    return log;
  }

  Future<LocalMealEntry> insertMealEntry({
    required int mealLogLocalId,
    int? serverId,
    bool isConsumed = false,
  }) async {
    final now = DateTime.now();
    final entry = LocalMealEntry(
      serverId: serverId,
      mealLogLocalId: mealLogLocalId,
      mealType: 'Breakfast',
      isConsumed: isConsumed,
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localMealEntrys.put(entry));
    return entry;
  }

  Future<LocalFoodTemplate> insertFoodTemplate({required int serverId}) async {
    final now = DateTime.now();
    final template = LocalFoodTemplate(
      serverId: serverId,
      name: 'Banana',
      calories: 105,
      protein: 1.3,
      carbohydrates: 27,
      fat: 0.4,
      createdAt: now,
      isSynced: true,
      syncStatus: 'synced',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localFoodTemplates.put(template));
    return template;
  }

  Future<LocalNutritionGoal> insertNutritionGoal({
    required int uid,
    int? serverId,
    double dailyCalories = 2000,
  }) async {
    final now = DateTime.now();
    final goal = LocalNutritionGoal(
      serverId: serverId,
      userId: uid,
      dailyCalories: dailyCalories,
      createdAt: now,
      isSynced: serverId != null,
      syncStatus: serverId != null ? 'synced' : 'pending_create',
      lastModifiedLocal: now,
    );
    await isar.writeTxn(() => isar.localNutritionGoals.put(goal));
    return goal;
  }

  ResponseBody jsonResponse(Object json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  Map<String, dynamic> foodItemJson({
    required int id,
    required int mealEntryId,
  }) => {
    'id': id,
    'mealEntryId': mealEntryId,
    'name': 'Banana',
    'calories': 105,
    'protein': 1.3,
    'carbohydrates': 27,
    'fat': 0.4,
    'createdAt': '2026-01-01T00:00:00.000Z',
  };

  Map<String, dynamic> nutritionGoalJson({
    required int id,
    required int userId,
  }) => {'id': id, 'userId': userId, 'createdAt': '2026-01-01T00:00:00.000Z'};

  Map<String, dynamic> mealLogJson({
    required int id,
    required int userId,
    DateTime? date,
  }) => {
    'id': id,
    'userId': userId,
    'date': (date ?? DateTime(2026, 1, 1)).toIso8601String(),
    'waterIntake': 0,
    'totalCalories': 0,
    'totalProtein': 0,
    'totalCarbohydrates': 0,
    'totalFat': 0,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'mealEntries': <dynamic>[],
  };

  // ============ 1 & 2. Capture at scheduling time / JWT pinning ============

  group('captures the initiating session before any yield', () {
    test('a delayed JWT read still pins A\'s epoch and JWT into the request '
        'when the session has not changed in the meantime (test 2)', () async {
      loginAs(userA);
      final log = await insertMealLog(uid: userA, serverId: 10);

      final tokenCompleter = Completer<String?>();
      when(mockAuthService.getToken()).thenAnswer((_) => tokenCompleter.future);

      await repository.updateWaterIntake(log.serverId!, 500);
      tokenCompleter.complete('jwt-a-delayed');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(adapter.capturedRequests, hasLength(1));
      final sent = adapter.capturedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer jwt-a-delayed');
      final epochToken =
          sent.extra[ApiService.sessionEpochExtraKey] as UserSessionToken;
      expect(epochToken.userId, userA);
    });

    test('the epoch is captured synchronously at scheduling time, not '
        'deferred until the JWT read resolves: a session change while the '
        'read is still in flight is caught (rejecting the whole capture) '
        'rather than silently adopting the new session (test 1)', () async {
      loginAs(userA);
      final log = await insertMealLog(uid: userA, serverId: 13);

      final tokenCompleter = Completer<String?>();
      when(mockAuthService.getToken()).thenAnswer((_) => tokenCompleter.future);

      await repository.updateWaterIntake(log.serverId!, 500);
      // The local write is done and the background push has been
      // scheduled - captureContext() already ran UserSessionEpoch.capture()
      // synchronously (capturing A's generation) and is now suspended
      // awaiting getToken(). If capture were instead deferred until this
      // point, it would now (wrongly) capture B's generation below.

      loginAs(userB);
      tokenCompleter.complete('jwt-issued-after-switch');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Because A's generation was already captured before the switch,
      // SessionRequestCoordinator's post-read recheck finds it no longer
      // current and returns null - the request is never sent under
      // EITHER session, rather than being wrongly sent under B's.
      expect(adapter.capturedRequests, isEmpty);
    });
  });

  // ============ 3 & 4. Staleness/logout before dispatch ============

  group('staleness before dispatch prevents any network request', () {
    test(
      'A logs out before dispatch: zero network requests (test 3)',
      () async {
        loginAs(userA);
        final log = await insertMealLog(uid: userA, serverId: 11);

        repository.beforeBackgroundHttpDispatchForTesting = () async {
          logout();
        };

        await repository.updateWaterIntake(log.serverId!, 600);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('A logs out and B logs in before dispatch: zero network requests, '
        'the operation does not adopt B\'s context (test 4)', () async {
      loginAs(userA);
      final log = await insertMealLog(uid: userA, serverId: 12);

      repository.beforeBackgroundHttpDispatchForTesting = () async {
        loginAs(userB);
      };

      await repository.updateWaterIntake(log.serverId!, 700);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(adapter.capturedRequests, isEmpty);
    });
  });

  // ============ 5 & 6. Response arrives after the session changes ============

  group('a response arriving after the session changes cannot acknowledge', () {
    test('HTTP request starts under A, then B logs in before success: the '
        'response cannot acknowledge any row, including a pre-existing row '
        'owned by B (tests 5, 6)', () async {
      loginAs(userA);
      final log = await insertMealLog(uid: userA);
      final entry = await insertMealEntry(
        mealLogLocalId: log.localId,
        serverId: 501,
      );
      await insertFoodTemplate(serverId: 900);

      // A pre-existing row genuinely owned by B, to prove the response
      // cannot land on ANY row, not just the one it was meant for.
      final logB = await insertMealLog(uid: userB);
      final entryB = await insertMealEntry(
        mealLogLocalId: logB.localId,
        serverId: 601,
      );

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      await repository.quickAddFood(
        mealEntryId: entry.localId,
        foodTemplateId: 900,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.capturedRequests, hasLength(1)); // dispatched under A

      loginAs(userB);
      responseCompleter.complete(
        jsonResponse(foodItemJson(id: 9001, mealEntryId: 501)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final storedItems = await isar.localFoodItems.where().findAll();
      expect(storedItems, hasLength(1));
      expect(storedItems.single.isSynced, isFalse);
      expect(storedItems.single.serverId, isNull);

      final entryBAfter = await isar.localMealEntrys.get(entryB.localId);
      expect(entryBAfter, isNotNull);
    });
  });

  group('acknowledgment resolves by stable local identity, not server ID', () {
    test('a foreign row that happens to already carry the same server ID the '
        'response assigns is never touched - only the row identified by its '
        'own stable local ID gets acknowledged', () async {
      loginAs(userB);
      // A pre-existing row owned by B that happens to already carry the
      // exact server ID the response below will assign to A's new item -
      // an unscoped serverId lookup would find THIS row instead of A's.
      final logB = await insertMealLog(uid: userB);
      final entryB = await insertMealEntry(
        mealLogLocalId: logB.localId,
        serverId: 950,
      );
      final foreignFood = LocalFoodItem(
        serverId: 9200,
        mealEntryLocalId: entryB.localId,
        name: 'Foreign',
        quantity: 1,
        calories: 1,
        protein: 1,
        carbohydrates: 1,
        fat: 1,
        createdAt: DateTime.now(),
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
      );
      await isar.writeTxn(() => isar.localFoodItems.put(foreignFood));

      loginAs(userA);
      final log = await insertMealLog(uid: userA);
      final entry = await insertMealEntry(
        mealLogLocalId: log.localId,
        serverId: 951,
      );
      await insertFoodTemplate(serverId: 940);
      adapter.responder =
          (_) async => jsonResponse(foodItemJson(id: 9200, mealEntryId: 951));

      await repository.quickAddFood(
        mealEntryId: entry.localId,
        foodTemplateId: 940,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final ownItem =
          await isar.localFoodItems
              .filter()
              .mealEntryLocalIdEqualTo(entry.localId)
              .findFirst();
      expect(
        ownItem!.serverId,
        9200,
        reason:
            'the caller\'s own row, resolved by its stable local ID, '
            'is the one that gets acknowledged',
      );
      expect(ownItem.isSynced, isTrue);

      final foreignAfter = await isar.localFoodItems.get(foreignFood.localId);
      expect(
        foreignAfter,
        isNotNull,
        reason:
            'the foreign row sharing the same server ID must be '
            'completely untouched',
      );
      expect(foreignAfter!.name, 'Foreign');
    });
  });

  // ============ 7 & 8. Checkpoints around the acknowledging writeTxn ============

  group('acknowledgment checkpoints around the writeTxn', () {
    test('server success followed by invalidation before the writeTxn: '
        'acknowledgment is skipped (test 7)', () async {
      loginAs(userA);
      final log = await insertMealLog(uid: userA);
      final entry = await insertMealEntry(
        mealLogLocalId: log.localId,
        serverId: 602,
      );
      await insertFoodTemplate(serverId: 910);
      adapter.responder =
          (_) async => jsonResponse(foodItemJson(id: 9101, mealEntryId: 602));

      // Fires AFTER the post-HTTP checkpoint has already run and passed
      // (session was still A then) - invalidating here specifically
      // exercises the pre-writeTxn checkpoint, not the post-HTTP one.
      var enteredWriteTxn = false;
      repository.afterBackgroundHttpResponseForTesting = () async {
        logout();
      };
      repository.insideBackgroundWriteTxnForTesting = () async {
        enteredWriteTxn = true;
      };

      await repository.quickAddFood(
        mealEntryId: entry.localId,
        foodTemplateId: 910,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        enteredWriteTxn,
        isFalse,
        reason:
            'the pre-writeTxn checkpoint should reject before ever calling '
            'db.writeTxn, not rely on the in-transaction checkpoint',
      );
      final stored = await isar.localFoodItems.where().findFirst();
      expect(stored!.isSynced, isFalse);
      expect(stored.serverId, isNull);
    });

    test('invalidation while the acknowledgment writeTxn is waiting: the '
        'first-statement guard prevents the mutation (test 8)', () async {
      loginAs(userA);
      final log = await insertMealLog(uid: userA);
      final entry = await insertMealEntry(
        mealLogLocalId: log.localId,
        serverId: 603,
      );
      await insertFoodTemplate(serverId: 911);
      adapter.responder =
          (_) async => jsonResponse(foodItemJson(id: 9102, mealEntryId: 603));

      repository.insideBackgroundWriteTxnForTesting = () async {
        logout();
      };

      await repository.quickAddFood(
        mealEntryId: entry.localId,
        foodTemplateId: 911,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final stored = await isar.localFoodItems.where().findFirst();
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_create');
    });
  });

  // ============ 9 & 10. Cancellation/staleness preserve pending state ============

  group('cancellation and staleness preserve pending state', () {
    test('cancelling the current generation mid-flight is an expected '
        'lifecycle outcome: no permanent failure, pending state intact, '
        'nothing thrown to the caller (tests 9, 10)', () async {
      loginAs(userA);
      final log = await insertMealLog(uid: userA);
      final entry = await insertMealEntry(
        mealLogLocalId: log.localId,
        serverId: 604,
      );
      await insertFoodTemplate(serverId: 920);

      // Never resolves - the request is cancelled instead of completing.
      adapter.responder = (_) => Completer<ResponseBody>().future;

      final captured = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };

      try {
        await repository.quickAddFood(
          mealEntryId: entry.localId,
          foodTemplateId: 920,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(adapter.capturedRequests, hasLength(1));

        sessionCoordinator.cancelCurrentGeneration();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } finally {
        debugPrint = originalDebugPrint;
      }

      final stored = await isar.localFoodItems.where().findFirst();
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_create');
      expect(stored.serverId, isNull);

      // A cancellation is an expected lifecycle outcome, not a failure -
      // it must never be logged as one (distinct from an ordinary network
      // failure, which test 11 confirms IS still logged that way).
      expect(
        captured.any((line) => line.contains('Background sync failed')),
        isFalse,
      );
    });
  });

  // ============ 11. Ordinary failures preserve existing behavior ============

  group('ordinary server/network failures preserve existing behavior', () {
    test('a real 500 response leaves the row pending exactly as before, '
        'without throwing out of the repository call (test 11)', () async {
      loginAs(userA);
      final log = await insertMealLog(uid: userA);
      final entry = await insertMealEntry(
        mealLogLocalId: log.localId,
        serverId: 605,
      );
      await insertFoodTemplate(serverId: 930);
      adapter.responder =
          (_) async => jsonResponse({'message': 'boom'}, statusCode: 500);

      await repository.quickAddFood(
        mealEntryId: entry.localId,
        foodTemplateId: 930,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final stored = await isar.localFoodItems.where().findFirst();
      expect(stored!.isSynced, isFalse);
      expect(stored.syncStatus, 'pending_create');
    });
  });

  // ============ 12, 13, 14. Background refresh protection ============

  group('background refresh protection', () {
    test('a MealLog refresh started under A cannot cache into local storage '
        'after the session has moved on - the epoch check protects it even '
        'though the response still legitimately names A as the owner '
        '(test 12)', () async {
      loginAs(userA);
      final today = todayDate();
      // A distinguishing local value the (rejected) server response does
      // NOT share (mealLogJson always returns waterIntake: 0), and which
      // the unrelated legacy consumed-totals repair never touches - if
      // the refresh wrongly wrote through, this would be overwritten.
      await insertMealLog(
        uid: userA,
        serverId: 42,
        date: today,
        waterIntake: 777,
      );

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      await repository.getTodaysMealLog();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.capturedRequests, hasLength(1));

      loginAs(userB);
      responseCompleter.complete(
        jsonResponse(mealLogJson(id: 42, userId: userA, date: today)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final logs = await isar.localMealLogs.where().findAll();
      expect(logs, hasLength(1), reason: 'no new row for B was created');
      expect(logs.single.waterIntake, 777);
    });

    test('a NutritionGoal refresh started under A cannot replace the cached '
        'goal after the session has moved on (test 13)', () async {
      loginAs(userA);
      // A distinguishing local value the (rejected) server response does
      // NOT share (nutritionGoalJson always defaults dailyCalories to
      // 2000) - if the refresh wrongly wrote through, this would be
      // overwritten.
      await insertNutritionGoal(uid: userA, serverId: 42, dailyCalories: 3333);

      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      await repository.getActiveNutritionGoal();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.capturedRequests, hasLength(1));

      loginAs(userB);
      responseCompleter.complete(
        jsonResponse(nutritionGoalJson(id: 42, userId: userA)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final goals = await isar.localNutritionGoals.where().findAll();
      expect(goals, hasLength(1));
      expect(goals.single.dailyCalories, 3333);
    });

    test('a food-template refresh caches shared-catalog items regardless of '
        'which user created them - no false per-user restriction is applied '
        '(test 14)', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse([
            {
              'id': 77,
              'name': 'Shared Template',
              'calories': 50,
              'protein': 1,
              'carbohydrates': 2,
              'fat': 0.5,
              'isCustom': true,
              'createdByUserId': userB,
              'createdAt': '2026-01-01T00:00:00.000Z',
            },
          ]);

      await repository.getFoodTemplates();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final cached =
          await isar.localFoodTemplates
              .filter()
              .serverIdEqualTo(77)
              .findFirst();
      expect(cached, isNotNull);
      expect(cached!.createdByUserId, userB);
    });
  });

  // ============ 15. createNutritionGoal acknowledgment semantics ============

  group('locally created nutrition goal acknowledgment', () {
    test(
      'a success under the same session acknowledges correctly (test 15a)',
      () async {
        loginAs(userA);
        adapter.responder =
            (_) async =>
                jsonResponse(nutritionGoalJson(id: 500, userId: userA));

        await repository.createNutritionGoal(
          NutritionGoal(id: 0, userId: userA, createdAt: DateTime.now()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final stored =
            await isar.localNutritionGoals
                .filter()
                .serverIdEqualTo(500)
                .findFirst();
        expect(stored, isNotNull);
        expect(stored!.isSynced, isTrue);
        expect(stored.syncStatus, 'synced');
      },
    );

    test('a success after B logs in does not acknowledge (test 15b)', () async {
      loginAs(userA);
      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;

      await repository.createNutritionGoal(
        NutritionGoal(id: 0, userId: userA, createdAt: DateTime.now()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.capturedRequests, hasLength(1));

      loginAs(userB);
      responseCompleter.complete(
        jsonResponse(nutritionGoalJson(id: 501, userId: userA)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final stored =
          await isar.localNutritionGoals
              .filter()
              .serverIdEqualTo(501)
              .findFirst();
      expect(stored, isNull);
    });

    test('invalidation after the post-HTTP checkpoint has already passed, but '
        'before the writeTxn, is still caught by the pre-writeTxn checkpoint '
        'specifically - the transaction is never entered', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse(nutritionGoalJson(id: 502, userId: userA));

      var enteredWriteTxn = false;
      repository.afterBackgroundHttpResponseForTesting = () async {
        logout();
      };
      repository.insideBackgroundWriteTxnForTesting = () async {
        enteredWriteTxn = true;
      };

      await repository.createNutritionGoal(
        NutritionGoal(id: 0, userId: userA, createdAt: DateTime.now()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        enteredWriteTxn,
        isFalse,
        reason:
            'the pre-writeTxn checkpoint should reject before ever '
            'calling db.writeTxn',
      );
      final stored =
          await isar.localNutritionGoals
              .filter()
              .serverIdEqualTo(502)
              .findFirst();
      expect(stored, isNull);
    });
  });

  // ============ 16. Same-user online behavior across operation shapes ============

  group('legitimate same-user background behavior is unchanged', () {
    test('the fire-and-forget push shapes (delete/quantity/clear/add) still '
        'dispatch session-bound requests and succeed (test 16)', () async {
      loginAs(userA);
      adapter.responder = (_) async => jsonResponse({});

      final log = await insertMealLog(uid: userA, serverId: 700);
      final entryForQuantity = await insertMealEntry(
        mealLogLocalId: log.localId,
        serverId: 701,
      );
      final now = DateTime.now();
      late int foodLocalId;
      await isar.writeTxn(() async {
        foodLocalId = await isar.localFoodItems.put(
          LocalFoodItem(
            serverId: 702,
            mealEntryLocalId: entryForQuantity.localId,
            name: 'X',
            quantity: 1,
            calories: 10,
            protein: 1,
            carbohydrates: 1,
            fat: 1,
            createdAt: now,
            isSynced: true,
            syncStatus: 'synced',
            lastModifiedLocal: now,
          ),
        );
      });
      await repository.updateFoodQuantity(foodLocalId, 2);

      final entryForDelete = await insertMealEntry(
        mealLogLocalId: log.localId,
        serverId: 703,
      );
      late int foodToDeleteId;
      await isar.writeTxn(() async {
        foodToDeleteId = await isar.localFoodItems.put(
          LocalFoodItem(
            serverId: 704,
            mealEntryLocalId: entryForDelete.localId,
            name: 'Y',
            quantity: 1,
            calories: 10,
            protein: 1,
            carbohydrates: 1,
            fat: 1,
            createdAt: now,
            isSynced: true,
            syncStatus: 'synced',
            lastModifiedLocal: now,
          ),
        );
      });
      await repository.deleteFoodItem(foodToDeleteId);

      await repository.clearAllFood(log.serverId!);

      final entryForAdd = await insertMealEntry(
        mealLogLocalId: log.localId,
        serverId: 705,
      );
      await repository.addFoodItem(
        FoodItem(
          id: 0,
          mealEntryId: entryForAdd.localId,
          name: 'Z',
          calories: 10,
          protein: 1,
          carbohydrates: 1,
          fat: 1,
          createdAt: now,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(adapter.capturedRequests.length, greaterThanOrEqualTo(4));
      for (final sent in adapter.capturedRequests) {
        expect(
          sent.extra.containsKey(ApiService.sessionEpochExtraKey),
          isTrue,
          reason: '${sent.path} must be session-bound',
        );
      }
    });

    test('createFoodTemplate still acknowledges a custom template created '
        'in-session (test 16)', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse({
            'id': 800,
            'name': 'Custom',
            'calories': 10,
            'protein': 1,
            'carbohydrates': 1,
            'fat': 1,
            'createdAt': '2026-01-01T00:00:00.000Z',
          });

      await repository.createFoodTemplate(
        FoodTemplate(
          id: 0,
          name: 'Custom',
          calories: 10,
          protein: 1,
          carbohydrates: 1,
          fat: 1,
          createdAt: DateTime.now(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final stored =
          await isar.localFoodTemplates
              .filter()
              .serverIdEqualTo(800)
              .findFirst();
      expect(stored, isNotNull);
      expect(stored!.isSynced, isTrue);
    });

    test('createFoodTemplate: a stale completion never marks the template '
        'synced (test 7)', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse({
            'id': 801,
            'name': 'Custom',
            'calories': 10,
            'protein': 1,
            'carbohydrates': 1,
            'fat': 1,
            'createdAt': '2026-01-01T00:00:00.000Z',
          });

      repository.afterBackgroundHttpResponseForTesting = () async {
        logout();
      };

      await repository.createFoodTemplate(
        FoodTemplate(
          id: 0,
          name: 'Custom',
          calories: 10,
          protein: 1,
          carbohydrates: 1,
          fat: 1,
          createdAt: DateTime.now(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final stored = await isar.localFoodTemplates.where().findFirst();
      expect(stored!.isSynced, isFalse);
      expect(stored.serverId, isNull);
    });
  });

  // ============ markMealAsConsumed: inline-awaited but still bound ============

  group(
    'markMealAsConsumed binds its inline HTTP call to a captured session',
    () {
      test('the request carries the session-bound extra key', () async {
        loginAs(userA);
        final log = await insertMealLog(uid: userA);
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          serverId: 703,
        );
        adapter.responder = (_) async => jsonResponse({});

        await repository.markMealAsConsumed(entry.localId, isConsumed: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(adapter.capturedRequests, hasLength(1));
        expect(
          adapter.capturedRequests.single.extra.containsKey(
            ApiService.sessionEpochExtraKey,
          ),
          isTrue,
        );
      });

      test('staleness at dispatch is an expected lifecycle outcome, not a '
          'thrown error - the local change is preserved regardless', () async {
        loginAs(userA);
        final log = await insertMealLog(uid: userA);
        final entry = await insertMealEntry(
          mealLogLocalId: log.localId,
          serverId: 704,
          isConsumed: false,
        );

        apiService.beforeDispatchEpochCheckForTesting = () async {
          logout();
        };

        await repository.markMealAsConsumed(entry.localId, isConsumed: true);

        expect(adapter.capturedRequests, isEmpty);
        final stored = await isar.localMealEntrys.get(entry.localId);
        expect(stored!.isConsumed, isTrue);
      });
    },
  );

  // ============ 18. JWT never appears in background log output ============

  group('the JWT never appears in background sync log output (test 18)', () {
    test('debugPrint output for a stale/cancelled/failed background push '
        'never contains the pinned JWT', () async {
      loginAs(userA);
      when(
        mockAuthService.getToken(),
      ).thenAnswer((_) async => 'super-secret-jwt');
      final log = await insertMealLog(uid: userA, serverId: 706);

      final captured = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };

      adapter.responder =
          (_) async => jsonResponse({'message': 'boom'}, statusCode: 500);

      try {
        await repository.updateWaterIntake(log.serverId!, 999);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } finally {
        debugPrint = originalDebugPrint;
      }

      for (final line in captured) {
        expect(line, isNot(contains('super-secret-jwt')));
      }
    });
  });
}

/// A deterministic fake Dio transport. Records every [RequestOptions] Dio
/// actually attempts to send, so tests can assert on the real
/// headers/extra/cancelToken the real interceptor pipeline produced -
/// never a stub of the interceptor itself. Mirrors the fake adapter used in
/// api_service_session_context_test.dart.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  /// Called for every request; return a Future that resolves (or never
  /// resolves, for cancellation tests) with the response to hand back.
  Future<ResponseBody> Function(RequestOptions options)? responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
    final respond = responder;
    if (respond != null) {
      return respond(options);
    }
    return Future.value(
      ResponseBody.fromString(
        '{}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}
