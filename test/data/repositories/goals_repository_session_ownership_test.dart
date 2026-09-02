import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/goal.dart';
import 'package:go_hard_app/data/models/goal_progress.dart';
import 'package:go_hard_app/data/repositories/goals_repository.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_context.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

@GenerateMocks([AuthService, ConnectivityService])
import 'goals_repository_session_ownership_test.mocks.dart';

/// Proves [GoalsRepository] is fully session-bound: every authenticated HTTP
/// call carries the [SessionRequestContext] captured at operation entry
/// (pinned JWT + generation `CancelToken`), a logged-out call dispatches
/// nothing (matching each method's pre-existing empty/exception convention),
/// mid-flight session invalidation surfaces as [SessionStaleException], and
/// cancellation surfaces as [RequestCancelledException] - never as a generic
/// error and never through `onUnauthorized`.
///
/// Uses a REAL [ApiService] + [SessionRequestCoordinator] + [UserSessionEpoch]
/// wired to a deterministic fake [HttpClientAdapter], so binding is proven
/// against the real production interceptor pipeline. No test uses a
/// wall-clock delay, `Future.delayed`, `Timer`, or event-queue pumping -
/// synchronization is via `Completer`s tied to the fake adapter's actual
/// dispatch.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  Completer<void> dispatched = Completer<void>();

  bool holdForever = false;
  int statusCode = 200;
  String body = '{}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
    if (!dispatched.isCompleted) dispatched.complete();
    if (holdForever) {
      return Completer<ResponseBody>().future;
    }
    return Future.value(
      ResponseBody.fromString(
        body,
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late UserSessionEpoch epoch;
  late MockAuthService authService;
  late MockConnectivityService connectivity;
  late SessionRequestCoordinator coordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late GoalsRepository repository;

  const goalJson =
      '{"id":1,"userId":1,"goalType":"Weight","targetValue":150.0,'
      '"currentValue":200.0,"startDate":"2024-01-01","isActive":true,'
      '"isCompleted":false,"createdAt":"2024-01-01T00:00:00Z"}';
  const progressJson =
      '{"id":1,"goalId":1,"recordedAt":"2024-01-01T00:00:00Z","value":5.0}';
  const impactJson = '{"programsCount":2,"sessionsCount":3}';

  setUp(() {
    epoch = UserSessionEpoch();
    authService = MockAuthService();
    connectivity = MockConnectivityService();
    when(connectivity.isOnline).thenReturn(true);
    coordinator = SessionRequestCoordinator(epoch, authService);
    apiService = ApiService(authService, epoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
    repository = GoalsRepository(apiService, epoch, coordinator, connectivity);
  });

  void login(int id) {
    epoch.activate(id);
    when(authService.getToken()).thenAnswer((_) async => 'jwt-$id');
  }

  UserSessionToken? extraToken(RequestOptions o) =>
      o.extra[ApiService.sessionEpochExtraKey] as UserSessionToken?;

  Goal goal(int id) => Goal(
    id: id,
    userId: 1,
    goalType: 'Weight',
    targetValue: 150,
    currentValue: 200,
    startDate: DateTime.utc(2024, 1, 1),
    isActive: true,
    isCompleted: false,
    createdAt: DateTime.utc(2024, 1, 1),
  );

  GoalProgress progress(int id) => GoalProgress(
    id: id,
    goalId: 1,
    recordedAt: DateTime.utc(2024, 1, 1),
    value: 5,
  );

  group('1. logged-out calls dispatch no HTTP', () {
    test('no session: getGoals returns empty, every other op throws '
        'SessionStaleException, adapter never touched', () async {
      when(authService.getToken()).thenAnswer((_) async => null);

      expect(await repository.getGoals(), isEmpty);
      await expectLater(
        repository.getGoalById(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.createGoal(goal(1)),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.updateGoal(1, goal(1)),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.deleteGoal(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.completeGoal(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.addProgress(1, progress(1)),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.getProgressHistory(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.getDeletionImpact(1),
        throwsA(isA<SessionStaleException>()),
      );

      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'session invalidated before the call: same empty result, no HTTP',
      () async {
        login(1);
        epoch.invalidate();

        expect(await repository.getGoals(), isEmpty);
        expect(adapter.capturedRequests, isEmpty);
      },
    );
  });

  group('2-3. every authenticated call carries the captured context', () {
    test('getGoals: pinned JWT, epoch token, generation CancelToken', () async {
      login(1);
      adapter.body = '[]';
      final probe = await coordinator.captureContext();

      await repository.getGoals();

      final sent = adapter.capturedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
      expect(extraToken(sent)!.userId, 1);
      expect(identical(sent.cancelToken, probe!.cancelToken), isTrue);
    });

    test('every method is bound to the entry-captured context', () async {
      login(1);
      adapter.body = goalJson;
      await repository.getGoalById(1);
      await repository.createGoal(goal(1));
      adapter.body = '';
      await repository.updateGoal(1, goal(1));
      await repository.completeGoal(1);
      await repository.deleteGoal(1);
      adapter.body = progressJson;
      await repository.addProgress(1, progress(1));
      adapter.body = '[]';
      await repository.getProgressHistory(1);
      adapter.body = impactJson;
      await repository.getDeletionImpact(1);

      expect(adapter.capturedRequests, hasLength(8));
      for (final sent in adapter.capturedRequests) {
        expect(sent.headers['Authorization'], 'Bearer jwt-1');
        expect(extraToken(sent), isNotNull);
        expect(sent.cancelToken, isNotNull);
      }
    });

    test(
      'the JWT sent is the one captured at entry, not a later live token',
      () async {
        login(1);
        adapter.body = '[]';
        apiService.beforeDispatchEpochCheckForTesting = () async {
          when(authService.getToken()).thenAnswer((_) async => 'jwt-2');
        };

        await repository.getGoals();

        expect(
          adapter.capturedRequests.single.headers['Authorization'],
          'Bearer jwt-1',
        );
      },
    );
  });

  group('4. invalidation before dispatch -> SessionStaleException', () {
    test('getGoals rethrows SessionStaleException, no request sent', () async {
      login(1);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };

      await expectLater(
        repository.getGoals(),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });

    test('createGoal rethrows SessionStaleException', () async {
      login(1);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };

      await expectLater(
        repository.createGoal(goal(1)),
        throwsA(isA<SessionStaleException>()),
      );
    });

    test(
      'getDeletionImpact rethrows SessionStaleException, not empty counts',
      () async {
        login(1);
        apiService.beforeDispatchEpochCheckForTesting = () async {
          epoch.invalidate();
        };

        await expectLater(
          repository.getDeletionImpact(1),
          throwsA(isA<SessionStaleException>()),
        );
      },
    );
  });

  group('5-6. in-flight cancellation -> RequestCancelledException', () {
    test('cancelling the generation surfaces RequestCancelledException, '
        'distinct from ApiException', () async {
      login(1);
      adapter.holdForever = true;

      final future = repository.getGoals();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('cancellation does not invoke onUnauthorized', () async {
      login(1);
      adapter.holdForever = true;
      var unauthorized = 0;
      apiService.onUnauthorized = () => unauthorized++;

      final future = repository.getGoalById(1);
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
      expect(unauthorized, 0);
    });
  });

  group('7-8. user B is unaffected by user A', () {
    test(
      'after A logs out and B logs in, B captures a fresh context',
      () async {
        login(1);
        epoch.invalidate();
        login(2);
        adapter.body = '[]';

        await repository.getGoals();

        final sent = adapter.capturedRequests.single;
        expect(sent.headers['Authorization'], 'Bearer jwt-2');
        expect(extraToken(sent)!.userId, 2);
      },
    );

    test("A's cancelled generation cannot cancel B's later request", () async {
      login(1);
      adapter.holdForever = true;
      final aFuture = repository.getGoals();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();
      await expectLater(aFuture, throwsA(isA<RequestCancelledException>()));

      epoch.invalidate();
      login(2);
      adapter
        ..holdForever = false
        ..dispatched = Completer<void>()
        ..body = '[]';

      final bResult = await repository.getGoals();
      expect(bResult, isEmpty);
      expect(
        adapter.capturedRequests.last.headers['Authorization'],
        'Bearer jwt-2',
      );
    });
  });

  group('9. single bound request per method (no nested/follow-up HTTP)', () {
    test('getGoals with isActive filter is a single bound request', () async {
      login(1);
      adapter.body = '[]';

      await repository.getGoals(isActive: true);

      expect(adapter.capturedRequests, hasLength(1));
      final sent = adapter.capturedRequests.single;
      expect(sent.uri.queryParameters['isActive'], 'true');
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
      expect(extraToken(sent), isNotNull);
    });

    test('getProgressHistory / getDeletionImpact each dispatch exactly one '
        'bound request', () async {
      login(1);
      adapter.body = '[]';
      await repository.getProgressHistory(7);
      adapter.body = impactJson;
      await repository.getDeletionImpact(7);

      expect(adapter.capturedRequests, hasLength(2));
      expect(adapter.capturedRequests[0].uri.path, contains('goals/7/history'));
      expect(
        adapter.capturedRequests[1].uri.path,
        contains('goals/7/deletion-impact'),
      );
      for (final sent in adapter.capturedRequests) {
        expect(sent.headers['Authorization'], 'Bearer jwt-1');
        expect(extraToken(sent), isNotNull);
      }
    });
  });

  group('10. ordinary failures preserve existing public behavior', () {
    test('getGoals: a 500 rethrows an ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(repository.getGoals(), throwsA(isA<ApiException>()));
    });

    test('createGoal: a 500 propagates as ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(
        repository.createGoal(goal(1)),
        throwsA(isA<ApiException>()),
      );
    });

    test('offline: getGoals returns empty, no HTTP', () async {
      login(1);
      when(connectivity.isOnline).thenReturn(false);

      expect(await repository.getGoals(), isEmpty);
      expect(adapter.capturedRequests, isEmpty);
    });
  });
}
