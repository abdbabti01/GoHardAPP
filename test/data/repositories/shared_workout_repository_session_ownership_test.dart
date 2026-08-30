import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/shared_workout.dart';
import 'package:go_hard_app/data/repositories/shared_workout_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

@GenerateMocks([AuthService, ConnectivityService])
import 'shared_workout_repository_session_ownership_test.mocks.dart';

/// Proves [SharedWorkoutRepository] is fully session-bound (every one of the
/// seven HTTP calls carries the session that started the operation) and
/// cache-ownership-safe (every local read/write/sweep/delete is scoped to
/// `SharedWorkout.cachedForUserId`, which is distinct from the author
/// identity `sharedByUserId`), mirroring
/// `running_repository_session_ownership_test.dart` /
/// `chat_repository_session_ownership_test.dart`.
///
/// Uses a REAL [ApiService] wired to a fake [HttpClientAdapter] so
/// credential pinning and dispatch-time staleness rejection are proven
/// against the real production interceptor pipeline, and a REAL
/// [UserSessionEpoch] / [SessionRequestCoordinator].
///
/// ## Deterministic synchronization
///
/// No test uses a wall-clock delay or an event-queue pump to prove detached
/// work has finished:
/// - [_FakeHttpClientAdapter.nextDispatch] completes the instant `fetch()`
///   is actually invoked.
/// - `scheduledBackgroundSyncs` collects the exact `Future<void>` each
///   [SharedWorkoutRepository._backgroundSync] call hands back via
///   `onBackgroundSyncScheduledForTesting` - it completes only once that
///   specific detached operation has fully settled.
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
  late SharedWorkoutRepository repository;
  late List<Future<void>> scheduledBackgroundSyncs;

  const userA = 1;
  const userB = 2;
  const author = 99;

  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'shared_workout_repo_owner_',
    );
    isar = await Isar.open(
      [SharedWorkoutSchema],
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
    when(
      mockAuthService.getUserName(),
    ).thenAnswer((_) async => 'name-$currentAuthUserId');
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

    repository = SharedWorkoutRepository(
      apiService,
      localDb,
      mockConnectivity,
      mockAuthService,
      sessionEpoch,
      sessionCoordinator,
    );

    scheduledBackgroundSyncs = [];
    repository.onBackgroundSyncScheduledForTesting =
        scheduledBackgroundSyncs.add;
  });

  tearDown(() async {
    repository.beforeWriteTxnForTesting = null;
    repository.insideWriteTxnForTesting = null;
    repository.afterWriteTxnForTesting = null;
    repository.beforeBackgroundHttpDispatchForTesting = null;
    repository.afterBackgroundHttpResponseForTesting = null;
    repository.afterForegroundHttpResponseForTesting = null;
    repository.onBackgroundSyncScheduledForTesting = null;
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

  // ============ Seed / fixture helpers ============

  Future<SharedWorkout> seed({
    required int id,
    int? cachedForUserId,
    int sharedByUserId = author,
    bool isSaved = false,
    bool isLiked = false,
    int likeCount = 0,
    int saveCount = 0,
    String category = 'strength',
    String? difficulty = 'beginner',
    String name = 'Seed workout',
    DateTime? sharedAt,
  }) async {
    final w = SharedWorkout(
      id: id,
      originalId: id * 10,
      type: 'session',
      sharedByUserId: sharedByUserId,
      sharedByUserName: 'author-$sharedByUserId',
      workoutName: name,
      exercisesJson: '[]',
      duration: 30,
      category: category,
      difficulty: difficulty,
      likeCount: likeCount,
      saveCount: saveCount,
      isLikedByCurrentUser: isLiked,
      isSavedByCurrentUser: isSaved,
      sharedAt: sharedAt ?? DateTime(2026, 1, 1),
      cachedForUserId: cachedForUserId,
    );
    await isar.writeTxn(() => isar.sharedWorkouts.put(w));
    return w;
  }

  Map<String, dynamic> workoutJson({
    required int id,
    int sharedByUserId = author,
    bool isLiked = false,
    bool isSaved = false,
    int likeCount = 0,
    int saveCount = 0,
    String category = 'strength',
    String? difficulty = 'beginner',
    String name = 'Server workout',
  }) => {
    'id': id,
    'originalId': id * 10,
    'type': 'session',
    'sharedByUserId': sharedByUserId,
    'sharedByUserName': 'author-$sharedByUserId',
    'workoutName': name,
    'description': null,
    'exercisesJson': '[]',
    'duration': 30,
    'category': category,
    'difficulty': difficulty,
    'likeCount': likeCount,
    'saveCount': saveCount,
    'commentCount': 0,
    'isLikedByCurrentUser': isLiked,
    'isSavedByCurrentUser': isSaved,
    'sharedAt': DateTime(2026, 1, 1).toIso8601String(),
  };

  ResponseBody jsonResponse(Object? json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  Object? boundEpochOf(RequestOptions req) =>
      req.extra[ApiService.sessionEpochExtraKey];

  // ============ 1. Logged out ============

  group('logged out (req 1)', () {
    test('every operation does zero Isar mutation and zero HTTP', () async {
      final row = await seed(id: 10, cachedForUserId: userA);

      expect(await repository.getSharedWorkouts(), isEmpty);
      expect(await repository.getSharedWorkoutsByUser(author), isEmpty);
      expect(await repository.getMySharedWorkouts(), isEmpty);
      expect(await repository.getSavedWorkouts(), isEmpty);
      await expectLater(
        () => repository.shareWorkout(
          originalId: 1,
          type: 'session',
          workoutName: 'x',
          exercisesJson: '[]',
          duration: 10,
          category: 'strength',
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => repository.toggleLike(10, true),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => repository.toggleSave(10, true),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => repository.deleteSharedWorkout(10),
        throwsA(isA<Exception>()),
      );

      expect(adapter.capturedRequests, isEmpty);
      expect(scheduledBackgroundSyncs, isEmpty);
      final stored = await isar.sharedWorkouts.get(10);
      expect(stored, isNotNull);
      expect(stored!.cachedForUserId, userA);
      expect(stored.workoutName, row.workoutName);
      expect(stored.isLikedByCurrentUser, isFalse);
    });
  });

  // ============ 2-7. Offline cache-ownership reads ============

  group('offline reads are scoped to the captured cache owner', () {
    setUp(() => when(mockConnectivity.isOnline).thenReturn(false));

    test('feed returns only current cachedForUserId rows (req 2, 4)', () async {
      await seed(id: 1, cachedForUserId: userA, name: 'A row');
      await seed(id: 2, cachedForUserId: userB, name: 'B row');
      loginAs(userA);

      final result = await repository.getSharedWorkouts();

      expect(result.map((w) => w.id), [1]);
      expect(adapter.capturedRequests, isEmpty);
    });

    test('legacy null-owner rows are invisible (req 3, 19)', () async {
      // A legacy row that is BOTH saved and authored by the reader - it
      // must still stay invisible on every read until an online refresh
      // restamps it, because its cachedForUserId is null.
      await seed(
        id: 1,
        cachedForUserId: null,
        sharedByUserId: userA,
        isSaved: true,
        name: 'legacy',
      );
      loginAs(userA);

      expect(await repository.getSharedWorkouts(), isEmpty);
      expect(await repository.getSavedWorkouts(), isEmpty);
      expect(await repository.getMySharedWorkouts(), isEmpty);
    });

    test('sharedByUserId matching the reader is NOT a substitute for cache '
        'ownership (req 5)', () async {
      // Row authored by userA but personalized-cached for userB.
      await seed(id: 1, cachedForUserId: userB, sharedByUserId: userA);
      loginAs(userA);

      expect(await repository.getSharedWorkouts(), isEmpty);
      expect(await repository.getMySharedWorkouts(), isEmpty);
    });

    test(
      'my-shares requires BOTH cache owner AND author to match (req 6)',
      () async {
        await seed(id: 1, cachedForUserId: userA, sharedByUserId: userA);
        await seed(id: 2, cachedForUserId: userA, sharedByUserId: author);
        await seed(id: 3, cachedForUserId: userB, sharedByUserId: userA);
        loginAs(userA);

        final mine = await repository.getMySharedWorkouts();
        expect(mine.map((w) => w.id), [1]);
      },
    );

    test(
      'saved rows and personalized flags are isolated by cache owner (req 7)',
      () async {
        await seed(
          id: 1,
          cachedForUserId: userA,
          isSaved: true,
          isLiked: true,
          name: 'A saved',
        );
        await seed(
          id: 2,
          cachedForUserId: userB,
          isSaved: true,
          isLiked: true,
          name: 'B saved',
        );
        loginAs(userA);

        final saved = await repository.getSavedWorkouts();
        expect(saved.map((w) => w.id), [1]);
        expect(saved.single.isLikedByCurrentUser, isTrue);
      },
    );

    test('by-user offline read is scoped to the cache owner', () async {
      await seed(id: 1, cachedForUserId: userA, sharedByUserId: author);
      await seed(id: 2, cachedForUserId: userB, sharedByUserId: author);
      loginAs(userA);

      final result = await repository.getSharedWorkoutsByUser(author);
      expect(result.map((w) => w.id), [1]);
    });
  });

  // ============ 8-9. HTTP binding ============

  group('HTTP binding', () {
    test(
      'all seven HTTP calls carry the captured sessionContext (req 8)',
      () async {
        loginAs(userA);
        final tokenA = sessionEpoch.capture();
        adapter.responder = (options) async {
          if (options.method == 'GET' && options.path.contains('/saved')) {
            return jsonResponse([workoutJson(id: 3)]);
          }
          if (options.method == 'GET' && options.path.contains('/user/')) {
            return jsonResponse([workoutJson(id: 4)]);
          }
          if (options.method == 'GET') {
            return jsonResponse([workoutJson(id: 1)]);
          }
          if (options.method == 'DELETE') {
            return ResponseBody.fromString('', 204);
          }
          if (options.path.contains('/like')) {
            return jsonResponse({'liked': true, 'likeCount': 1});
          }
          if (options.path.contains('/save')) {
            return jsonResponse({'saved': true, 'saveCount': 1});
          }
          return jsonResponse(workoutJson(id: 7, sharedByUserId: userA));
        };

        await repository.getSharedWorkouts();
        await scheduledBackgroundSyncs.single;
        await repository.getSharedWorkoutsByUser(author);
        await repository.getMySharedWorkouts();
        await repository.getSavedWorkouts();
        await repository.shareWorkout(
          originalId: 1,
          type: 'session',
          workoutName: 'x',
          exercisesJson: '[]',
          duration: 10,
          category: 'strength',
        );
        await repository.toggleLike(1, true);
        await repository.toggleSave(1, true);
        await repository.deleteSharedWorkout(1);

        expect(adapter.capturedRequests, hasLength(8));
        for (final req in adapter.capturedRequests) {
          expect(
            boundEpochOf(req),
            tokenA,
            reason: '${req.method} ${req.path} must be session-bound',
          );
          expect(req.headers['Authorization'], 'Bearer jwt-$userA');
        }
      },
    );

    test('getMySharedWorkouts uses the captured userId, never a live '
        'AuthService reread (req 9)', () async {
      loginAs(userA);
      adapter.responder = (_) async => jsonResponse(<dynamic>[]);

      // Storage flips to B mid-flight without touching the real epoch.
      adapter.responder = (options) async {
        currentAuthUserId = userB;
        return jsonResponse(<dynamic>[]);
      };

      await repository.getMySharedWorkouts();

      final req = adapter.capturedRequests.single;
      expect(
        req.path,
        contains('/user/$userA'),
        reason: 'target must be the captured user, not the re-read one',
      );
      expect(req.headers['Authorization'], 'Bearer jwt-$userA');
    });
  });

  // ============ 10-13. Detached refresh & stale sessions ============

  group('detached feed cache refresh', () {
    test(
      'captures context at scheduling time, not inside the closure (req 10)',
      () async {
        loginAs(userA);
        final tokenA = sessionEpoch.capture();
        final responseCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => responseCompleter.future;

        final dispatched = adapter.nextDispatch();
        final future = repository.getSharedWorkouts();
        await dispatched;

        // Storage flips to B before the response is delivered.
        currentAuthUserId = userB;
        responseCompleter.complete(jsonResponse([workoutJson(id: 1)]));
        await future;
        await scheduledBackgroundSyncs.single;

        final req = adapter.capturedRequests.single;
        expect(boundEpochOf(req), tokenA);
        expect(req.headers['Authorization'], 'Bearer jwt-$userA');
        final stored = await isar.sharedWorkouts.get(1);
        expect(stored!.cachedForUserId, userA);
      },
    );

    test(
      'logout before dispatch produces no request and no write (req 11)',
      () async {
        loginAs(userA);
        repository.beforeBackgroundHttpDispatchForTesting = () async {
          logout();
        };

        final result = await repository.getSharedWorkouts();

        expect(result, isEmpty);
        expect(adapter.capturedRequests, isEmpty);
        expect(await isar.sharedWorkouts.count(), 0);
      },
    );

    test('account switch after HTTP but before the cache write produces no '
        'write (req 12)', () async {
      loginAs(userA);
      adapter.responder = (_) async => jsonResponse([workoutJson(id: 1)]);
      repository.afterBackgroundHttpResponseForTesting = () async {
        loginAs(userB);
      };

      await repository.getSharedWorkouts();
      await scheduledBackgroundSyncs.single;

      expect(await isar.sharedWorkouts.count(), 0);
    });

    test(
      'a stale A refresh after clearAll cannot resurrect A rows (req 13)',
      () async {
        loginAs(userA);
        adapter.responder = (_) async => jsonResponse([workoutJson(id: 1)]);
        repository.afterBackgroundHttpResponseForTesting = () async {
          logout();
          await isar.writeTxn(() => isar.sharedWorkouts.clear());
          loginAs(userB);
        };

        await repository.getSharedWorkouts();
        await scheduledBackgroundSyncs.single;

        expect(await isar.sharedWorkouts.count(), 0);
      },
    );

    test('a stale A sweep cannot delete B rows (req 14)', () async {
      await seed(id: 500, cachedForUserId: userB, name: 'B keeps this');
      loginAs(userA);
      adapter.responder = (_) async => jsonResponse([workoutJson(id: 1)]);
      repository.afterBackgroundHttpResponseForTesting = () async {
        loginAs(userB);
      };

      // A's response omits id 500; a stale sweep must never run at all.
      await repository.getSharedWorkouts();
      await scheduledBackgroundSyncs.single;

      expect(await isar.sharedWorkouts.get(500), isNotNull);
      expect(await isar.sharedWorkouts.get(1), isNull);
    });

    test(
      'a live sweep removes only the cache owner\'s own dropped rows (req 14b)',
      () async {
        await seed(id: 500, cachedForUserId: userB);
        await seed(id: 501, cachedForUserId: userA);
        await seed(id: 502, cachedForUserId: userA, isSaved: true);
        loginAs(userA);
        adapter.responder =
            (_) async =>
                jsonResponse([workoutJson(id: 1, sharedByUserId: author)]);

        await repository.getSharedWorkouts();
        await scheduledBackgroundSyncs.single;

        expect(await isar.sharedWorkouts.get(500), isNotNull, reason: 'B row');
        expect(await isar.sharedWorkouts.get(501), isNull, reason: 'A dropped');
        expect(
          await isar.sharedWorkouts.get(502),
          isNotNull,
          reason: 'A saved row retained',
        );
        expect((await isar.sharedWorkouts.get(1))!.cachedForUserId, userA);
      },
    );

    test(
      'a valid B full response replaces an A/null-owned row (req 15, 25, 26)',
      () async {
        await seed(
          id: 1,
          cachedForUserId: userA,
          sharedByUserId: author,
          isLiked: true,
          name: 'A cached',
        );
        await seed(id: 2, cachedForUserId: null, name: 'legacy');
        loginAs(userB);
        adapter.responder =
            (_) async => jsonResponse([
              workoutJson(id: 1, sharedByUserId: author, isLiked: false),
              workoutJson(id: 2, sharedByUserId: author, isLiked: false),
            ]);

        await repository.getSharedWorkouts();
        await scheduledBackgroundSyncs.single;

        final one = await isar.sharedWorkouts.get(1);
        final two = await isar.sharedWorkouts.get(2);
        expect(one!.cachedForUserId, userB);
        expect(one.isLikedByCurrentUser, isFalse);
        expect(one.sharedByUserId, author, reason: 'author identity preserved');
        expect(two!.cachedForUserId, userB);
      },
    );

    test(
      'the background seam settles only after the cache write (req 24)',
      () async {
        loginAs(userA);
        adapter.responder = (_) async => jsonResponse([workoutJson(id: 1)]);
        var writeObserved = false;
        repository.afterWriteTxnForTesting = () async {
          writeObserved = true;
        };

        await repository.getSharedWorkouts();
        final settled = scheduledBackgroundSyncs.single;
        // Not yet awaited -> assert the seam future is what gates completion.
        await settled;
        expect(writeObserved, isTrue);
        expect(await isar.sharedWorkouts.get(1), isNotNull);
      },
    );
  });

  // ============ 16-21. Mutation acknowledgments ============

  group('partial toggle acknowledgments', () {
    test(
      'a partial A toggle ack cannot overwrite a B-owned row (req 16)',
      () async {
        await seed(id: 1, cachedForUserId: userB, isLiked: false, likeCount: 5);
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse({'liked': true, 'likeCount': 6});

        await repository.toggleLike(1, true);

        final stored = await isar.sharedWorkouts.get(1);
        expect(stored!.cachedForUserId, userB);
        expect(stored.isLikedByCurrentUser, isFalse);
        expect(stored.likeCount, 5);
      },
    );

    test(
      'toggleLike updates only a row owned by the captured user (req 17)',
      () async {
        await seed(id: 1, cachedForUserId: userA, isLiked: false, likeCount: 2);
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse({'liked': true, 'likeCount': 3});

        await repository.toggleLike(1, true);

        final stored = await isar.sharedWorkouts.get(1);
        expect(stored!.isLikedByCurrentUser, isTrue);
        expect(stored.likeCount, 3);
      },
    );

    test(
      'toggleSave updates only a row owned by the captured user (req 18)',
      () async {
        await seed(id: 1, cachedForUserId: userA, isSaved: false, saveCount: 1);
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse({'saved': true, 'saveCount': 2});

        await repository.toggleSave(1, true);

        final stored = await isar.sharedWorkouts.get(1);
        expect(stored!.isSavedByCurrentUser, isTrue);
        expect(stored.saveCount, 2);
      },
    );

    test(
      'a toggle ack never creates a missing row from a partial response',
      () async {
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse({'liked': true, 'likeCount': 1});

        await repository.toggleLike(777, true);

        expect(await isar.sharedWorkouts.get(777), isNull);
      },
    );

    test(
      'delete removes only a row owned by the captured user (req 19, 20)',
      () async {
        await seed(id: 1, cachedForUserId: userA);
        await seed(id: 2, cachedForUserId: userB);
        await seed(id: 3, cachedForUserId: null);
        loginAs(userA);
        adapter.responder = (_) async => ResponseBody.fromString('', 204);

        await repository.deleteSharedWorkout(1);
        await repository.deleteSharedWorkout(2);
        await repository.deleteSharedWorkout(3);

        expect(await isar.sharedWorkouts.get(1), isNull);
        expect(await isar.sharedWorkouts.get(2), isNotNull);
        expect(await isar.sharedWorkouts.get(3), isNotNull);
      },
    );

    test(
      'share response is stamped with the captured cache owner (req 20b)',
      () async {
        loginAs(userA);
        adapter.responder =
            (_) async =>
                jsonResponse(workoutJson(id: 42, sharedByUserId: userA));

        final created = await repository.shareWorkout(
          originalId: 1,
          type: 'session',
          workoutName: 'x',
          exercisesJson: '[]',
          duration: 10,
          category: 'strength',
        );

        expect(created.cachedForUserId, userA);
        final stored = await isar.sharedWorkouts.get(42);
        expect(stored!.cachedForUserId, userA);
        expect(stored.sharedByUserId, userA);
      },
    );

    test(
      'every saved response row is stamped with the cache owner (req 21)',
      () async {
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse([
              workoutJson(id: 1, isSaved: true),
              workoutJson(id: 2, isSaved: true),
            ]);

        final saved = await repository.getSavedWorkouts();

        expect(saved.map((w) => w.cachedForUserId), everyElement(userA));
        expect((await isar.sharedWorkouts.get(1))!.cachedForUserId, userA);
        expect((await isar.sharedWorkouts.get(2))!.cachedForUserId, userA);
      },
    );
  });

  // ============ 22-23. Lifecycle exceptions ============

  group('lifecycle exceptions are silent expected outcomes', () {
    test('toggleLike swallows a stale-at-dispatch SessionStaleException '
        'without a write or a throw (req 22)', () async {
      await seed(id: 1, cachedForUserId: userA, isLiked: false);
      loginAs(userA);

      // Session goes stale exactly at dispatch: the real interceptor
      // throws SessionStaleException.
      apiService.beforeDispatchEpochCheckForTesting = () async {
        logout();
      };

      await repository.toggleLike(1, true);

      final stored = await isar.sharedWorkouts.get(1);
      expect(stored, isNotNull);
      expect(stored!.isLikedByCurrentUser, isFalse);
    });

    test(
      'deleteSharedWorkout swallows a stale-at-dispatch '
      'SessionStaleException without deleting or throwing (req 22)',
      () async {
        await seed(id: 1, cachedForUserId: userA);
        loginAs(userA);
        apiService.beforeDispatchEpochCheckForTesting = () async {
          logout();
        };

        await repository.deleteSharedWorkout(1);

        expect(await isar.sharedWorkouts.get(1), isNotNull);
      },
    );

    test(
      'share converts a stale dispatch to the unauthenticated outcome',
      () async {
        loginAs(userA);
        apiService.beforeDispatchEpochCheckForTesting = () async {
          logout();
        };

        await expectLater(
          () => repository.shareWorkout(
            originalId: 1,
            type: 'session',
            workoutName: 'x',
            exercisesJson: '[]',
            duration: 10,
            category: 'strength',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('No authenticated user'),
            ),
          ),
        );
        expect(await isar.sharedWorkouts.count(), 0);
      },
    );

    test('toggleSave treats a mid-flight generation cancellation as a silent '
        'no-op (req 22 - RequestCancelledException)', () async {
      await seed(id: 1, cachedForUserId: userA, isSaved: false);
      loginAs(userA);
      adapter.responder = (_) => Completer<ResponseBody>().future;

      final dispatched = adapter.nextDispatch();
      final future = repository.toggleSave(1, true);
      await dispatched;
      sessionCoordinator.cancelCurrentGeneration();
      await future; // must settle silently, not hang or throw

      expect((await isar.sharedWorkouts.get(1))!.isSavedByCurrentUser, isFalse);
    });

    test(
      'B gets a fresh context and works normally after A ends (req 23)',
      () async {
        loginAs(userA);
        final hang = Completer<ResponseBody>();
        adapter.responder = (_) => hang.future;
        final dispatched = adapter.nextDispatch();
        final futureA = repository.getSharedWorkouts();
        await dispatched;

        // A's session ends while its fetch is in flight.
        logout();
        hang.complete(jsonResponse(<dynamic>[]));
        expect(await futureA, isEmpty);
        expect(
          scheduledBackgroundSyncs,
          isEmpty,
          reason: 'a stale foreground fetch schedules no detached write',
        );

        loginAs(userB);
        final tokenB = sessionEpoch.capture();
        adapter.responder = (_) async => jsonResponse([workoutJson(id: 9)]);

        final resultB = await repository.getSharedWorkouts();
        await scheduledBackgroundSyncs.single;

        expect(resultB.map((w) => w.id), [9]);
        expect(boundEpochOf(adapter.capturedRequests.last), tokenB);
        expect((await isar.sharedWorkouts.get(9))!.cachedForUserId, userB);
      },
    );
  });

  // ============ Isolated checkpoint hooks (req 7-9 of the checkpoint
  // sequence; mutation-test targets that a later check would shadow) ======

  group('write-helper checkpoints are individually load-bearing', () {
    test('the pre-writeTxn checkpoint in the feed cache write avoids entering '
        'the transaction once already stale', () async {
      loginAs(userA);
      adapter.responder = (_) async => jsonResponse([workoutJson(id: 1)]);
      var enteredTxn = false;
      repository.afterBackgroundHttpResponseForTesting = () async => logout();
      repository.insideWriteTxnForTesting = () async {
        enteredTxn = true;
      };

      await repository.getSharedWorkouts();
      await scheduledBackgroundSyncs.single;

      expect(
        enteredTxn,
        isFalse,
        reason:
            'once already stale immediately before writeTxn, the checkpoint '
            'there must skip starting the transaction altogether rather than '
            'relying solely on the first-statement-inside check',
      );
      expect(await isar.sharedWorkouts.get(1), isNull);
    });

    test('the pre-writeTxn checkpoint in the toggle ack avoids entering the '
        'transaction once already stale', () async {
      await seed(id: 1, cachedForUserId: userA, isLiked: false);
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse({'liked': true, 'likeCount': 1});
      var enteredTxn = false;
      repository.beforeWriteTxnForTesting = () async => logout();
      repository.insideWriteTxnForTesting = () async {
        enteredTxn = true;
      };

      await repository.toggleLike(1, true);

      expect(enteredTxn, isFalse);
      expect((await isar.sharedWorkouts.get(1))!.isLikedByCurrentUser, isFalse);
    });

    test('the pre-writeTxn checkpoint in delete avoids entering the '
        'transaction once already stale', () async {
      await seed(id: 1, cachedForUserId: userA);
      loginAs(userA);
      adapter.responder = (_) async => ResponseBody.fromString('', 204);
      var enteredTxn = false;
      repository.beforeWriteTxnForTesting = () async => logout();
      repository.insideWriteTxnForTesting = () async {
        enteredTxn = true;
      };

      await repository.deleteSharedWorkout(1);

      expect(enteredTxn, isFalse);
      expect(await isar.sharedWorkouts.get(1), isNotNull);
    });

    test(
      'first-statement-in-writeTxn check blocks a mid-transaction logout',
      () async {
        loginAs(userA);
        adapter.responder = (_) async => jsonResponse([workoutJson(id: 1)]);
        repository.insideWriteTxnForTesting = () async {
          logout();
        };

        await repository.getSharedWorkouts();
        await scheduledBackgroundSyncs.single;

        expect(await isar.sharedWorkouts.get(1), isNull);
      },
    );

    test('the post-HTTP checkpoint in share rejects before the foreground '
        'write hook fires', () async {
      loginAs(userA);
      final responseCompleter = Completer<ResponseBody>();
      adapter.responder = (_) => responseCompleter.future;
      var hookFired = false;
      repository.afterForegroundHttpResponseForTesting = () async {
        hookFired = true;
      };

      final dispatched = adapter.nextDispatch();
      final future = repository.shareWorkout(
        originalId: 1,
        type: 'session',
        workoutName: 'x',
        exercisesJson: '[]',
        duration: 10,
        category: 'strength',
      );
      await dispatched;
      logout();
      responseCompleter.complete(
        jsonResponse(workoutJson(id: 1, sharedByUserId: userA)),
      );
      await future.then((_) {}, onError: (_) {});

      expect(hookFired, isFalse);
      expect(await isar.sharedWorkouts.count(), 0);
    });
  });

  // ============ cachedForUserId is strictly local-only metadata ============
  //
  // Proves the server can neither read, choose, nor override cache
  // ownership: it is never serialized outbound, never deserialized inbound,
  // and only ever stamped from the captured session context.

  group('cachedForUserId is local-only cache metadata', () {
    test('fromJson ignores a malicious cachedForUserId and leaves it null '
        'until repository stamping', () {
      final parsed = SharedWorkoutJson.fromJson({
        ...workoutJson(id: 7, sharedByUserId: author),
        'cachedForUserId': 999,
      });

      expect(parsed.cachedForUserId, isNull);
      expect(parsed.sharedByUserId, author);
    });

    test(
      'toJson excludes cachedForUserId even when the object carries one',
      () {
        final w = SharedWorkout(
          id: 7,
          originalId: 70,
          type: 'session',
          sharedByUserId: author,
          sharedByUserName: 'a',
          workoutName: 'w',
          exercisesJson: '[]',
          duration: 10,
          category: 'strength',
          sharedAt: DateTime(2026, 1, 1),
          cachedForUserId: 12345,
        );

        final json = w.toJson();

        expect(json.containsKey('cachedForUserId'), isFalse);
        expect(json.keys, isNot(contains('cachedForUserId')));
      },
    );

    test('copyWith preserves cachedForUserId when it is omitted', () {
      final w = SharedWorkout(
        originalId: 1,
        type: 'session',
        sharedByUserId: author,
        sharedByUserName: 'a',
        workoutName: 'w',
        exercisesJson: '[]',
        duration: 10,
        category: 'strength',
        sharedAt: DateTime(2026, 1, 1),
        cachedForUserId: 42,
      );

      expect(w.copyWith(workoutName: 'renamed').cachedForUserId, 42);
    });

    test(
      'shareWorkout\'s outgoing request body excludes cachedForUserId',
      () async {
        loginAs(userA);
        adapter.responder =
            (_) async =>
                jsonResponse(workoutJson(id: 42, sharedByUserId: userA));

        await repository.shareWorkout(
          originalId: 1,
          type: 'session',
          workoutName: 'x',
          exercisesJson: '[]',
          duration: 10,
          category: 'strength',
        );

        final body = adapter.capturedRequests.single.data as Map;
        expect(body.containsKey('cachedForUserId'), isFalse);
        // Defence in depth: the author id in the body is inert (server
        // overwrites from the JWT), but the cache-owner field must never
        // appear at all.
        expect(body.keys, isNot(contains('cachedForUserId')));
      },
    );

    test(
      'a server response supplying cachedForUserId cannot cache a row for '
      'that user - it is stamped for the captured session user only',
      () async {
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse([
              {
                ...workoutJson(id: 1, sharedByUserId: author, isLiked: true),
                'cachedForUserId': userB, // hostile / spoofed field
              },
            ]);

        await repository.getSharedWorkouts();
        await scheduledBackgroundSyncs.single;

        final stored = await isar.sharedWorkouts.get(1);
        expect(stored!.cachedForUserId, userA);
        // And it is only visible to userA offline, never userB.
        when(mockConnectivity.isOnline).thenReturn(false);
        loginAs(userB);
        expect(await repository.getSharedWorkouts(), isEmpty);
      },
    );

    test('repository stamping sets the captured context user on every write '
        'path (feed, share, saved)', () async {
      loginAs(userA);
      adapter.responder = (options) async {
        if (options.method == 'GET' && options.path.contains('/saved')) {
          return jsonResponse([workoutJson(id: 3, isSaved: true)]);
        }
        if (options.method == 'GET') return jsonResponse([workoutJson(id: 1)]);
        return jsonResponse(workoutJson(id: 2, sharedByUserId: userA));
      };

      await repository.getSharedWorkouts();
      await scheduledBackgroundSyncs.single;
      await repository.shareWorkout(
        originalId: 1,
        type: 'session',
        workoutName: 'x',
        exercisesJson: '[]',
        duration: 10,
        category: 'strength',
      );
      await repository.getSavedWorkouts();

      for (final id in [1, 2, 3]) {
        expect((await isar.sharedWorkouts.get(id))!.cachedForUserId, userA);
      }
    });
  });

  // ============ Isar schema-upgrade compatibility ============
  //
  // Isar treats an added nullable property as a compatible schema upgrade
  // (no manual migration): a row written before `cachedForUserId` existed
  // simply reads back `null` for it. This group does NOT exercise a
  // separate pre-field generated schema binary - the established test
  // infrastructure has only the current `SharedWorkoutSchema`, and sibling
  // repo tests take the same shortcut. What it DOES prove, against the real
  // Isar engine (open -> write -> close -> reopen -> read), is the
  // behaviour this fix depends on: a `cachedForUserId == null` row round
  // -trips as null, stays invisible to every authenticated offline read,
  // and is restamped for the current user by the next valid online refresh
  // - so nothing is permanently hidden.

  group('schema upgrade: legacy rows without cachedForUserId', () {
    test('a null-owner row round-trips as null, is invisible offline, and is '
        'restamped by a valid online response', () async {
      // 1. Persist a row, then force cachedForUserId back to null via a
      //    direct write - the state a row written before the field existed
      //    would deserialize into.
      await seed(id: 1, cachedForUserId: userA, isSaved: true, isLiked: true);
      await isar.writeTxn(() async {
        final legacy = await isar.sharedWorkouts.get(1);
        legacy!.cachedForUserId = null;
        await isar.sharedWorkouts.put(legacy);
      });

      // 2. Reopen the collection (new Isar instance, same schema + dir) -
      //    the row must load without error and preserve the null.
      await isar.close();
      isar = await Isar.open(
        [SharedWorkoutSchema],
        directory: tempDir.path,
        inspector: false,
      );
      localDb.setTestDatabase(isar);

      final reopened = await isar.sharedWorkouts.get(1);
      expect(reopened, isNotNull);
      expect(reopened!.cachedForUserId, isNull);

      // 3. Invisible to an authenticated offline reader.
      when(mockConnectivity.isOnline).thenReturn(false);
      loginAs(userA);
      expect(await repository.getSharedWorkouts(), isEmpty);
      expect(await repository.getSavedWorkouts(), isEmpty);

      // 4. A valid online response restamps it for the current user.
      when(mockConnectivity.isOnline).thenReturn(true);
      adapter.responder =
          (_) async => jsonResponse([
            workoutJson(id: 1, sharedByUserId: author, isLiked: false),
          ]);
      await repository.getSharedWorkouts();
      await scheduledBackgroundSyncs.single;

      final restamped = await isar.sharedWorkouts.get(1);
      expect(restamped!.cachedForUserId, userA);

      when(mockConnectivity.isOnline).thenReturn(false);
      expect((await repository.getSharedWorkouts()).map((w) => w.id), [1]);
    });
  });
}

/// A deterministic fake Dio transport. Records every [RequestOptions] Dio
/// actually attempts to send, so tests assert on the real headers/extra the
/// production interceptor pipeline produced - never a stub of it. Mirrors
/// the fake adapter in `running_repository_session_ownership_test.dart`.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  Future<ResponseBody> Function(RequestOptions options)? responder;

  Completer<void>? _dispatchSignal;

  /// Completes deterministically the next time [fetch] is invoked - i.e.
  /// the moment a request actually reaches this fake transport. Must be
  /// called before the operation that triggers the dispatch.
  Future<void> nextDispatch() {
    final completer = Completer<void>();
    _dispatchSignal = completer;
    return completer.future;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
    _dispatchSignal?.complete();
    _dispatchSignal = null;
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
