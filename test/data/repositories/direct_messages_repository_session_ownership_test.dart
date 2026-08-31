import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/repositories/direct_messages_repository.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_context.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

@GenerateMocks([AuthService, ConnectivityService])
import 'direct_messages_repository_session_ownership_test.mocks.dart';

/// Proves [DirectMessagesRepository] is fully session-bound: every
/// authenticated HTTP call carries the [SessionRequestContext] captured at
/// operation entry (pinned JWT + generation `CancelToken`), a logged-out
/// call dispatches nothing, mid-flight session invalidation surfaces as
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

  /// Completes the instant the fake transport's [fetch] is actually
  /// invoked - lets a test act deterministically once a request is truly
  /// in flight, with no sleep.
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
  late DirectMessagesRepository repository;

  setUp(() {
    epoch = UserSessionEpoch();
    authService = MockAuthService();
    connectivity = MockConnectivityService();
    when(connectivity.isOnline).thenReturn(true);
    coordinator = SessionRequestCoordinator(epoch, authService);
    apiService = ApiService(authService, epoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
    repository = DirectMessagesRepository(
      apiService,
      connectivity,
      epoch,
      coordinator,
    );
  });

  /// Activates user [id] and points `getToken()` at that user's JWT.
  void login(int id) {
    epoch.activate(id);
    when(authService.getToken()).thenAnswer((_) async => 'jwt-$id');
  }

  UserSessionToken? extraToken(RequestOptions o) =>
      o.extra[ApiService.sessionEpochExtraKey] as UserSessionToken?;

  group('1. logged-out calls dispatch no HTTP', () {
    test('no session: reads return the empty result, send throws, adapter '
        'never touched', () async {
      when(authService.getToken()).thenAnswer((_) async => null);

      expect(await repository.getConversations(), isEmpty);
      expect(await repository.getMessages(7), isEmpty);
      expect(await repository.getUnreadCount(), 0);
      await repository.markAsRead(7); // no throw
      await expectLater(
        repository.sendMessage(7, 'hi'),
        throwsA(isA<Exception>()),
      );

      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'session invalidated before the call: same empty result, no HTTP',
      () async {
        login(1);
        epoch.invalidate();

        expect(await repository.getConversations(), isEmpty);
        expect(adapter.capturedRequests, isEmpty);
      },
    );
  });

  group('2-3. every authenticated call carries the captured context', () {
    test(
      'getConversations: pinned JWT, epoch token, generation CancelToken',
      () async {
        login(1);
        adapter.body = '[]';
        final probe = await coordinator.captureContext();

        await repository.getConversations();

        final sent = adapter.capturedRequests.single;
        expect(sent.headers['Authorization'], 'Bearer jwt-1');
        expect(extraToken(sent)!.userId, 1);
        expect(identical(sent.cancelToken, probe!.cancelToken), isTrue);
      },
    );

    test('getMessages, markAsRead, getUnreadCount are all bound', () async {
      login(1);
      adapter.body = '[]';
      await repository.getMessages(7);
      adapter.body = '{}';
      await repository.markAsRead(7);
      adapter.body = '{"unreadCount": 3}';
      await repository.getUnreadCount();

      expect(adapter.capturedRequests, hasLength(3));
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
        // Storage flips to user 2 in the gap between the wrapper check and the
        // interceptor's dispatch - the pinned jwt-1 must still be sent.
        apiService.beforeDispatchEpochCheckForTesting = () async {
          when(authService.getToken()).thenAnswer((_) async => 'jwt-2');
        };

        await repository.getConversations();

        expect(
          adapter.capturedRequests.single.headers['Authorization'],
          'Bearer jwt-1',
        );
      },
    );
  });

  group('4. invalidation before dispatch -> SessionStaleException', () {
    test(
      'getConversations rethrows SessionStaleException, no request sent',
      () async {
        login(1);
        apiService.beforeDispatchEpochCheckForTesting = () async {
          epoch.invalidate();
        };

        await expectLater(
          repository.getConversations(),
          throwsA(isA<SessionStaleException>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test(
      'sendMessage rethrows SessionStaleException (not a generic Exception)',
      () async {
        login(1);
        apiService.beforeDispatchEpochCheckForTesting = () async {
          epoch.invalidate();
        };

        await expectLater(
          repository.sendMessage(7, 'hi'),
          throwsA(isA<SessionStaleException>()),
        );
      },
    );

    test('markAsRead rethrows SessionStaleException rather than swallowing it '
        'as a generic failure', () async {
      login(1);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };

      await expectLater(
        repository.markAsRead(7),
        throwsA(isA<SessionStaleException>()),
      );
    });
  });

  group('5-6. in-flight cancellation -> RequestCancelledException', () {
    test('cancelling the generation surfaces RequestCancelledException, '
        'distinct from ApiException', () async {
      login(1);
      adapter.holdForever = true;

      final future = repository.getConversations();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('cancellation does not invoke onUnauthorized', () async {
      login(1);
      adapter.holdForever = true;
      var unauthorized = 0;
      apiService.onUnauthorized = () => unauthorized++;

      final future = repository.getMessages(7);
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
      expect(unauthorized, 0);
    });
  });

  group('7-8. user B is unaffected by user A', () {
    test('after A logs out and B logs in, B captures a fresh context and '
        'completes normally', () async {
      login(1);
      epoch.invalidate();
      login(2);
      adapter.body = '[]';

      await repository.getConversations();

      final sent = adapter.capturedRequests.single;
      expect(sent.headers['Authorization'], 'Bearer jwt-2');
      expect(extraToken(sent)!.userId, 2);
    });

    test("A's cancelled generation cannot cancel B's later request", () async {
      login(1);
      adapter.holdForever = true;
      final aFuture = repository.getConversations();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();
      await expectLater(aFuture, throwsA(isA<RequestCancelledException>()));

      // B logs in; a brand new generation CancelToken is minted.
      epoch.invalidate();
      login(2);
      adapter
        ..holdForever = false
        ..dispatched = Completer<void>()
        ..body = '[]';

      final bResult = await repository.getConversations();
      expect(bResult, isEmpty);
      expect(
        adapter.capturedRequests.last.headers['Authorization'],
        'Bearer jwt-2',
      );
    });
  });

  group('9. pagination reuses the original context', () {
    test('getMessages(beforeId:) is a single bound request', () async {
      login(1);
      adapter.body = '[]';

      await repository.getMessages(7, beforeId: 42);

      final sent = adapter.capturedRequests.single;
      expect(sent.uri.queryParameters['beforeId'], '42');
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
      expect(extraToken(sent), isNotNull);
    });

    test('the pagination request is session-bound too - stale-before-dispatch '
        'rejects it with SessionStaleException, no request sent', () async {
      login(1);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };

      await expectLater(
        repository.getMessages(7, beforeId: 42),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);
    });
  });

  group('10. ordinary failures preserve existing public behavior', () {
    test('getConversations: a 500 rethrows an ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(
        repository.getConversations(),
        throwsA(isA<ApiException>()),
      );
    });

    test('markAsRead: an ordinary failure is still swallowed', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await repository.markAsRead(7); // no throw
    });

    test('getUnreadCount: an ordinary failure still returns 0', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      expect(await repository.getUnreadCount(), 0);
    });

    test('offline: reads return empty, no HTTP', () async {
      login(1);
      when(connectivity.isOnline).thenReturn(false);

      expect(await repository.getConversations(), isEmpty);
      expect(await repository.getMessages(7), isEmpty);
      expect(await repository.getUnreadCount(), 0);
      expect(adapter.capturedRequests, isEmpty);
    });
  });
}
