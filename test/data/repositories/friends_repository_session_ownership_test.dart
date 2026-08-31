import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/repositories/friends_repository.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_context.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

@GenerateMocks([AuthService, ConnectivityService])
import 'friends_repository_session_ownership_test.mocks.dart';

/// Proves [FriendsRepository] is fully session-bound: every authenticated
/// HTTP call carries the [SessionRequestContext] captured at operation entry
/// (pinned JWT + generation `CancelToken`), a logged-out call dispatches
/// nothing, mid-flight session invalidation surfaces as
/// [SessionStaleException], and cancellation surfaces as
/// [RequestCancelledException] - never as a generic error and never through
/// `onUnauthorized`.
///
/// Uses a REAL [ApiService] + [SessionRequestCoordinator] + [UserSessionEpoch]
/// wired to a deterministic fake [HttpClientAdapter], so binding is proven
/// against the real production interceptor pipeline, not a stub of it. No
/// test uses a wall-clock delay.
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
  late FriendsRepository repository;

  setUp(() {
    epoch = UserSessionEpoch();
    authService = MockAuthService();
    connectivity = MockConnectivityService();
    when(connectivity.isOnline).thenReturn(true);
    coordinator = SessionRequestCoordinator(epoch, authService);
    apiService = ApiService(authService, epoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
    repository = FriendsRepository(
      apiService,
      connectivity,
      epoch,
      coordinator,
    );
  });

  void login(int id) {
    epoch.activate(id);
    when(authService.getToken()).thenAnswer((_) async => 'jwt-$id');
  }

  UserSessionToken? extraToken(RequestOptions o) =>
      o.extra[ApiService.sessionEpochExtraKey] as UserSessionToken?;

  // Drives every read + every mutation once, with a body that satisfies its
  // deserializer. Used by the "all calls are bound" sweep.
  Future<void> exerciseEveryOperation() async {
    adapter.body = '[]';
    await repository.getFriends();
    await repository.getIncomingRequests();
    await repository.getOutgoingRequests();
    await repository.searchUsers('ab');
    adapter.body = '{}';
    await repository.sendFriendRequest(2);
    await repository.acceptRequest(10);
    await repository.declineRequest(11);
    await repository.removeFriend(3);
    await repository.cancelFriendRequest(12);
    adapter.body = '{"status":"none"}';
    await repository.getFriendshipStatus(4);
    adapter.body =
        '{"userId":4,"username":"u4","name":"n4","memberSince":"2026-01-01T00:00:00.000Z",'
        '"isFriend":false,"sharedWorkoutsCount":0}';
    await repository.getPublicProfile(4);
  }

  group('1. logged-out calls dispatch no HTTP', () {
    test('no session: reads return the empty/none result, mutations throw, '
        'adapter never touched', () async {
      when(authService.getToken()).thenAnswer((_) async => null);

      expect(await repository.getFriends(), isEmpty);
      expect(await repository.getIncomingRequests(), isEmpty);
      expect(await repository.getOutgoingRequests(), isEmpty);
      expect(await repository.searchUsers('ab'), isEmpty);
      expect((await repository.getFriendshipStatus(4)).status, 'none');

      await expectLater(
        repository.sendFriendRequest(2),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.acceptRequest(10),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.declineRequest(11),
        throwsA(isA<Exception>()),
      );
      await expectLater(repository.removeFriend(3), throwsA(isA<Exception>()));
      await expectLater(
        repository.cancelFriendRequest(12),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        repository.getPublicProfile(4),
        throwsA(isA<Exception>()),
      );

      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'session invalidated before the call: same empty result, no HTTP',
      () async {
        login(1);
        epoch.invalidate();

        expect(await repository.getFriends(), isEmpty);
        expect(adapter.capturedRequests, isEmpty);
      },
    );
  });

  group('2-3. every authenticated call carries the captured context', () {
    test(
      'getFriends: pinned JWT, epoch token, generation CancelToken',
      () async {
        login(1);
        adapter.body = '[]';
        final probe = await coordinator.captureContext();

        await repository.getFriends();

        final sent = adapter.capturedRequests.single;
        expect(sent.headers['Authorization'], 'Bearer jwt-1');
        expect(extraToken(sent)!.userId, 1);
        expect(identical(sent.cancelToken, probe!.cancelToken), isTrue);
      },
    );

    test('all 11 authenticated operations are bound (JWT + token + '
        'CancelToken on every request)', () async {
      login(1);

      await exerciseEveryOperation();

      expect(adapter.capturedRequests, hasLength(11));
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

        await repository.getFriends();

        expect(
          adapter.capturedRequests.single.headers['Authorization'],
          'Bearer jwt-1',
        );
      },
    );
  });

  group('4. invalidation before dispatch -> SessionStaleException', () {
    setUp(() {
      login(1);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };
    });

    test(
      'getFriends rethrows SessionStaleException, no request sent',
      () async {
        await expectLater(
          repository.getFriends(),
          throwsA(isA<SessionStaleException>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('sendFriendRequest rethrows SessionStaleException (not a generic '
        'Exception)', () async {
      await expectLater(
        repository.sendFriendRequest(2),
        throwsA(isA<SessionStaleException>()),
      );
    });

    test('getFriendshipStatus rethrows SessionStaleException rather than '
        'converting it into a successful status: none', () async {
      await expectLater(
        repository.getFriendshipStatus(4),
        throwsA(isA<SessionStaleException>()),
      );
    });

    test('searchUsers rethrows SessionStaleException', () async {
      await expectLater(
        repository.searchUsers('ab'),
        throwsA(isA<SessionStaleException>()),
      );
    });

    test('EVERY authenticated operation rethrows SessionStaleException '
        'rather than a generic failure or a false-success result', () async {
      final ops = <String, Future<Object?> Function()>{
        'getFriends': () => repository.getFriends(),
        'getIncomingRequests': () => repository.getIncomingRequests(),
        'getOutgoingRequests': () => repository.getOutgoingRequests(),
        'searchUsers': () => repository.searchUsers('ab'),
        'sendFriendRequest': () => repository.sendFriendRequest(2),
        'acceptRequest': () => repository.acceptRequest(10),
        'declineRequest': () => repository.declineRequest(11),
        'removeFriend': () => repository.removeFriend(3),
        'cancelFriendRequest': () => repository.cancelFriendRequest(12),
        'getFriendshipStatus': () => repository.getFriendshipStatus(4),
        'getPublicProfile': () => repository.getPublicProfile(4),
      };
      for (final entry in ops.entries) {
        login(1); // re-establish a session; the pre-dispatch hook kills it
        await expectLater(
          entry.value(),
          throwsA(isA<SessionStaleException>()),
          reason: '${entry.key} must rethrow SessionStaleException',
        );
      }
      expect(adapter.capturedRequests, isEmpty);
    });
  });

  group('5-6. in-flight cancellation -> RequestCancelledException', () {
    test('cancelling the generation surfaces RequestCancelledException, '
        'distinct from ApiException', () async {
      login(1);
      adapter.holdForever = true;

      final future = repository.getFriends();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('cancellation does not invoke onUnauthorized', () async {
      login(1);
      adapter.holdForever = true;
      var unauthorized = 0;
      apiService.onUnauthorized = () => unauthorized++;

      final future = repository.getIncomingRequests();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
      expect(unauthorized, 0);
    });

    test('getFriendshipStatus: cancellation is rethrown, not swallowed as '
        'status: none', () async {
      login(1);
      adapter.holdForever = true;

      final future = repository.getFriendshipStatus(4);
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('EVERY authenticated operation surfaces RequestCancelledException '
        'when its in-flight request is cancelled', () async {
      final ops = <String, Future<Object?> Function()>{
        'getFriends': () => repository.getFriends(),
        'getIncomingRequests': () => repository.getIncomingRequests(),
        'getOutgoingRequests': () => repository.getOutgoingRequests(),
        'searchUsers': () => repository.searchUsers('ab'),
        'sendFriendRequest': () => repository.sendFriendRequest(2),
        'acceptRequest': () => repository.acceptRequest(10),
        'declineRequest': () => repository.declineRequest(11),
        'removeFriend': () => repository.removeFriend(3),
        'cancelFriendRequest': () => repository.cancelFriendRequest(12),
        'getFriendshipStatus': () => repository.getFriendshipStatus(4),
        'getPublicProfile': () => repository.getPublicProfile(4),
      };
      for (final entry in ops.entries) {
        login(1); // fresh generation + CancelToken per op
        adapter
          ..holdForever = true
          ..dispatched = Completer<void>();

        final future = entry.value();
        await adapter.dispatched.future;
        coordinator.cancelCurrentGeneration();

        await expectLater(
          future,
          throwsA(isA<RequestCancelledException>()),
          reason: '${entry.key} must surface RequestCancelledException',
        );
        epoch.invalidate();
      }
    });
  });

  group('7-8. user B is unaffected by user A', () {
    test('after A logs out and B logs in, B captures a fresh context and '
        'completes normally', () async {
      login(1);
      epoch.invalidate();
      login(2);
      adapter.body = '[]';

      await repository.getFriends();

      final sent = adapter.capturedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer jwt-2');
      expect(extraToken(sent)!.userId, 2);
    });

    test("A's cancelled generation cannot cancel B's later request", () async {
      login(1);
      adapter.holdForever = true;
      final aFuture = repository.getFriends();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();
      await expectLater(aFuture, throwsA(isA<RequestCancelledException>()));

      epoch.invalidate();
      login(2);
      adapter
        ..holdForever = false
        ..dispatched = Completer<void>()
        ..body = '[]';

      final bResult = await repository.getFriends();
      expect(bResult, isEmpty);
      expect(
        adapter.capturedRequests.last.headers['Authorization'],
        'Bearer jwt-2',
      );
    });
  });

  group('9. search query param is carried on the bound request', () {
    test(
      'searchUsers(query) is a single bound request with the query',
      () async {
        login(1);
        adapter.body = '[]';

        await repository.searchUsers('alice');

        final sent = adapter.capturedRequests.single;
        expect(sent.uri.toString(), contains('alice'));
        expect(sent.headers['Authorization'], 'Bearer jwt-1');
        expect(extraToken(sent), isNotNull);
      },
    );

    test('a too-short query never dispatches, even logged in', () async {
      login(1);
      expect(await repository.searchUsers('a'), isEmpty);
      expect(adapter.capturedRequests, isEmpty);
    });
  });

  group('10. ordinary failures preserve existing public behavior', () {
    test('getFriends: a 500 rethrows an ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(repository.getFriends(), throwsA(isA<ApiException>()));
    });

    test(
      'getFriendshipStatus: an ordinary failure still returns status: none',
      () async {
        login(1);
        adapter
          ..statusCode = 500
          ..body = '{"message":"boom"}';

        expect((await repository.getFriendshipStatus(4)).status, 'none');
      },
    );

    test('sendFriendRequest: a 400 rethrows an ApiException', () async {
      login(1);
      adapter
        ..statusCode = 400
        ..body = '{"message":"already sent"}';

      await expectLater(
        repository.sendFriendRequest(2),
        throwsA(isA<ApiException>()),
      );
    });

    test('offline: reads return empty/none, no HTTP', () async {
      login(1);
      when(connectivity.isOnline).thenReturn(false);

      expect(await repository.getFriends(), isEmpty);
      expect(await repository.getIncomingRequests(), isEmpty);
      expect(await repository.getOutgoingRequests(), isEmpty);
      expect(await repository.searchUsers('ab'), isEmpty);
      expect((await repository.getFriendshipStatus(4)).status, 'none');
      expect(adapter.capturedRequests, isEmpty);
    });

    test('offline: mutations still throw', () async {
      login(1);
      when(connectivity.isOnline).thenReturn(false);

      await expectLater(
        repository.sendFriendRequest(2),
        throwsA(isA<Exception>()),
      );
      await expectLater(repository.removeFriend(3), throwsA(isA<Exception>()));
      expect(adapter.capturedRequests, isEmpty);
    });
  });
}
