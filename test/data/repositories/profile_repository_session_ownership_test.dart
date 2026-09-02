import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/connectivity_service.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/profile_update_request.dart';
import 'package:go_hard_app/data/repositories/profile_repository.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

@GenerateMocks([AuthService, ConnectivityService])
import 'profile_repository_session_ownership_test.mocks.dart';

/// Proves [ProfileRepository] is fully session-bound after the raw-Dio photo
/// upload bypass was removed:
///
/// * every authenticated HTTP call ([getProfile] GET, [updateProfile] PUT,
///   [uploadProfilePhoto] POST, [deleteProfilePhoto] DELETE) carries the
///   [SessionRequestContext] captured at operation entry - pinned JWT +
///   generation `CancelToken` - and goes through the shared [ApiService]
///   interceptor pipeline (no second Dio instance);
/// * a logged-out call dispatches nothing;
/// * the photo file is read only after the context is captured;
/// * the multipart body keeps the deployed contract (POST `profile/photo`,
///   field name `photo`, filename, `multipart/form-data`);
/// * mid-flight invalidation surfaces as [SessionStaleException], in-flight
///   cancellation as [RequestCancelledException] - never a generic error and
///   never through `onUnauthorized`;
/// * a stale or cancelled [getProfile] never rewrites the offline cache.
///
/// Uses a REAL [ApiService] + [SessionRequestCoordinator] + [UserSessionEpoch]
/// wired to a deterministic fake [HttpClientAdapter]. No wall-clock delay,
/// `Future.delayed`, `Timer`, or event-queue pumping - synchronization is via
/// `Completer`s tied to the fake adapter's actual dispatch.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];
  final List<Uint8List> capturedBodies = [];

  Completer<void> dispatched = Completer<void>();

  /// When set, `fetch` returns this instead of an immediate response, so a
  /// test can land an invalidation in the window between actual dispatch and
  /// the response resolving.
  Completer<ResponseBody>? responseGate;

  bool holdForever = false;
  int statusCode = 200;
  String body = '{}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequests.add(options);
    if (requestStream != null) {
      final builder = BytesBuilder();
      await for (final chunk in requestStream) {
        builder.add(chunk);
      }
      capturedBodies.add(builder.takeBytes());
    }
    if (!dispatched.isCompleted) dispatched.complete();
    if (holdForever) return Completer<ResponseBody>().future;
    if (responseGate != null) return responseGate!.future;
    return _response();
  }

  ResponseBody _response() => ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      'content-type': ['application/json'],
    },
  );

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
  late ProfileRepository repository;
  late Directory tmpDir;
  late File imageFile;

  const profileJson =
      '{"id":1,"name":"Alice","username":"alice","email":"a@example.com",'
      '"dateCreated":"2024-01-01T00:00:00Z"}';
  const photoJson = '{"photoUrl":"/uploads/profiles/user_1_x.jpg"}';

  setUp(() {
    epoch = UserSessionEpoch();
    authService = MockAuthService();
    connectivity = MockConnectivityService();
    when(connectivity.isOnline).thenReturn(true);
    when(authService.writeCachedProfile(any, any)).thenAnswer((_) async {});
    when(authService.readCachedProfile(any)).thenAnswer((_) async => null);
    coordinator = SessionRequestCoordinator(epoch, authService);
    apiService = ApiService(authService, epoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
    repository = ProfileRepository(
      apiService,
      authService,
      epoch,
      coordinator,
      connectivity,
    );

    tmpDir = Directory.systemTemp.createTempSync('profile_repo_test');
    imageFile = File('${tmpDir.path}/avatar.png')
      ..writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 7)));
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  void login(int id) {
    epoch.activate(id);
    when(authService.getToken()).thenAnswer((_) async => 'jwt-$id');
  }

  UserSessionToken? extraToken(RequestOptions o) =>
      o.extra[ApiService.sessionEpochExtraKey] as UserSessionToken?;

  String bodyText(Uint8List bytes) => String.fromCharCodes(bytes);

  group('1. logged-out calls dispatch no HTTP and read no cache', () {
    test(
      'no session: every op (getProfile included) throws '
      'SessionStaleException, adapter never touched, cache never read',
      () async {
        when(authService.getToken()).thenAnswer((_) async => null);
        when(
          authService.readCachedProfile(any),
        ).thenAnswer((_) async => profileJson);

        await expectLater(
          repository.getProfile(),
          throwsA(isA<SessionStaleException>()),
        );
        await expectLater(
          repository.updateProfile(ProfileUpdateRequest(name: 'x')),
          throwsA(isA<SessionStaleException>()),
        );
        await expectLater(
          repository.uploadProfilePhoto(imageFile),
          throwsA(isA<SessionStaleException>()),
        );
        await expectLater(
          repository.deleteProfilePhoto(),
          throwsA(isA<SessionStaleException>()),
        );

        expect(adapter.capturedRequests, isEmpty);
        verifyNever(authService.readCachedProfile(any));
        verifyNever(authService.writeCachedProfile(any, any));
      },
    );

    test('session invalidated before the call: getProfile throws '
        'SessionStaleException, no HTTP, no cache read', () async {
      login(1);
      epoch.invalidate();
      when(
        authService.readCachedProfile(any),
      ).thenAnswer((_) async => profileJson);

      await expectLater(
        repository.getProfile(),
        throwsA(isA<SessionStaleException>()),
      );
      expect(adapter.capturedRequests, isEmpty);
      verifyNever(authService.readCachedProfile(any));
    });
  });

  group('2. context is captured before the photo file is read', () {
    test(
      'logged out + a non-existent file: SessionStaleException, not a '
      'FileSystemException (proves capture precedes MultipartFile.fromFile)',
      () async {
        when(authService.getToken()).thenAnswer((_) async => null);
        final missing = File('${tmpDir.path}/does-not-exist.png');

        await expectLater(
          repository.uploadProfilePhoto(missing),
          throwsA(isA<SessionStaleException>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );
  });

  group('3. every authenticated call carries the entry-captured context', () {
    test(
      'getProfile / updateProfile / uploadProfilePhoto / deleteProfilePhoto '
      'each send the pinned JWT + epoch token + generation CancelToken',
      () async {
        login(1);
        final probe = await coordinator.captureContext();

        adapter.body = profileJson;
        await repository.getProfile();
        await repository.updateProfile(ProfileUpdateRequest(name: 'New'));
        adapter.body = photoJson;
        await repository.uploadProfilePhoto(imageFile);
        adapter
          ..body = ''
          ..statusCode = 204;
        await repository.deleteProfilePhoto();

        expect(adapter.capturedRequests, hasLength(4));
        for (final sent in adapter.capturedRequests) {
          expect(sent.headers['Authorization'], 'Bearer jwt-1');
          expect(extraToken(sent)!.userId, 1);
          expect(identical(sent.cancelToken, probe!.cancelToken), isTrue);
        }
      },
    );

    test('the JWT sent by the upload is the one captured at entry, not a '
        'later live token', () async {
      login(1);
      adapter.body = photoJson;
      apiService.beforeDispatchEpochCheckForTesting = () async {
        when(authService.getToken()).thenAnswer((_) async => 'jwt-99');
      };

      await repository.uploadProfilePhoto(imageFile);

      expect(
        adapter.capturedRequests.single.headers['Authorization'],
        'Bearer jwt-1',
      );
    });

    test('each authenticated method dispatches exactly one bound request '
        '(no nested/follow-up HTTP in the repository)', () async {
      login(1);

      adapter.body = profileJson;
      await repository.getProfile();
      expect(adapter.capturedRequests, hasLength(1));

      await repository.updateProfile(ProfileUpdateRequest(name: 'New'));
      expect(adapter.capturedRequests, hasLength(2));

      adapter.body = photoJson;
      await repository.uploadProfilePhoto(imageFile);
      expect(adapter.capturedRequests, hasLength(3));

      adapter
        ..body = ''
        ..statusCode = 204;
      await repository.deleteProfilePhoto();
      expect(adapter.capturedRequests, hasLength(4));
    });
  });

  group('4. multipart upload preserves the deployed API contract', () {
    test('POST profile/photo, field name "photo", filename, multipart '
        'content-type', () async {
      login(1);
      adapter.body = photoJson;

      final url = await repository.uploadProfilePhoto(imageFile);
      expect(url, '/uploads/profiles/user_1_x.jpg');

      final sent = adapter.capturedRequests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.path, endsWith('/profile/photo'));
      expect(
        sent.headers[Headers.contentTypeHeader].toString(),
        contains('multipart/form-data'),
      );

      final text = bodyText(adapter.capturedBodies.single);
      expect(text, contains('name="photo"'));
      expect(text, contains('filename="avatar.png"'));
    });

    test('a 200 response with no photoUrl throws rather than returning a '
        'publishable success', () async {
      login(1);
      adapter.body = '{}';

      await expectLater(
        repository.uploadProfilePhoto(imageFile),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('no URL returned'),
          ),
        ),
      );
    });

    test('deleteProfilePhoto accepts the API 204 NoContent contract', () async {
      login(1);
      adapter
        ..body = ''
        ..statusCode = 204;

      expect(await repository.deleteProfilePhoto(), isTrue);
    });
  });

  group('5. invalidation before dispatch -> SessionStaleException', () {
    setUp(() {
      login(1);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };
    });

    test('getProfile rethrows SessionStaleException instead of falling back '
        'to cache, and does not write cache', () async {
      when(
        authService.readCachedProfile(any),
      ).thenAnswer((_) async => profileJson);

      await expectLater(
        repository.getProfile(),
        throwsA(isA<SessionStaleException>()),
      );
      verifyNever(authService.writeCachedProfile(any, any));
    });

    test('updateProfile rethrows SessionStaleException', () async {
      await expectLater(
        repository.updateProfile(ProfileUpdateRequest(name: 'x')),
        throwsA(isA<SessionStaleException>()),
      );
    });

    test(
      'uploadProfilePhoto rethrows SessionStaleException, no request sent',
      () async {
        await expectLater(
          repository.uploadProfilePhoto(imageFile),
          throwsA(isA<SessionStaleException>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('deleteProfilePhoto rethrows SessionStaleException', () async {
      await expectLater(
        repository.deleteProfilePhoto(),
        throwsA(isA<SessionStaleException>()),
      );
    });
  });

  group('6. in-flight cancellation -> RequestCancelledException', () {
    test('cancelling the generation surfaces RequestCancelledException for '
        'the upload, distinct from ApiException', () async {
      login(1);
      adapter.holdForever = true;

      final future = repository.uploadProfilePhoto(imageFile);
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('cancellation does not invoke onUnauthorized', () async {
      login(1);
      adapter.holdForever = true;
      var unauthorized = 0;
      apiService.onUnauthorized = () => unauthorized++;

      final future = repository.uploadProfilePhoto(imageFile);
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
      expect(unauthorized, 0);
    });

    test('a cancelled getProfile does not write cache', () async {
      login(1);
      adapter.holdForever = true;
      when(
        authService.readCachedProfile(any),
      ).thenAnswer((_) async => profileJson);

      final future = repository.getProfile();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
      verifyNever(authService.writeCachedProfile(any, any));
    });
  });

  group(
    '7. a real current-session 401 -> established unauthorized behavior',
    () {
      test('upload 401 calls onUnauthorized exactly once and surfaces an '
          'ApiException', () async {
        login(1);
        adapter
          ..statusCode = 401
          ..body = '{"message":"nope"}';
        var unauthorized = 0;
        apiService.onUnauthorized = () => unauthorized++;

        await expectLater(
          repository.uploadProfilePhoto(imageFile),
          throwsA(isA<ApiException>()),
        );
        expect(unauthorized, 1);
      });
    },
  );

  group('8. user B is unaffected by user A', () {
    test(
      'after A logs out and B logs in, B upload captures a fresh context',
      () async {
        login(1);
        epoch.invalidate();
        login(2);
        adapter.body = photoJson;

        await repository.uploadProfilePhoto(imageFile);

        final sent = adapter.capturedRequests.single;
        expect(sent.headers['Authorization'], 'Bearer jwt-2');
        expect(extraToken(sent)!.userId, 2);
      },
    );

    test("A's cancelled generation cannot cancel B's later upload", () async {
      login(1);
      adapter.holdForever = true;
      final aFuture = repository.uploadProfilePhoto(imageFile);
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();
      await expectLater(aFuture, throwsA(isA<RequestCancelledException>()));

      epoch.invalidate();
      login(2);
      adapter
        ..holdForever = false
        ..dispatched = Completer<void>()
        ..body = photoJson;

      final url = await repository.uploadProfilePhoto(imageFile);
      expect(url, '/uploads/profiles/user_1_x.jpg');
      expect(
        adapter.capturedRequests.last.headers['Authorization'],
        'Bearer jwt-2',
      );
    });
  });

  group('9. ordinary failures preserve existing public behavior', () {
    test('updateProfile: a 500 rethrows an ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(
        repository.updateProfile(ProfileUpdateRequest(name: 'x')),
        throwsA(isA<ApiException>()),
      );
    });

    test('uploadProfilePhoto: a 400 rethrows an ApiException', () async {
      login(1);
      adapter
        ..statusCode = 400
        ..body = 'File type not allowed';

      await expectLater(
        repository.uploadProfilePhoto(imageFile),
        throwsA(isA<ApiException>()),
      );
    });

    test('getProfile: a 500 falls back to the cached profile for the captured '
        'user only', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';
      when(
        authService.readCachedProfile(any),
      ).thenAnswer((_) async => profileJson);

      final user = await repository.getProfile();
      expect(user.id, 1);
      verify(authService.readCachedProfile(1)).called(1);
    });

    test('offline: getProfile returns the captured user\'s cached profile, '
        'no HTTP', () async {
      login(1);
      when(connectivity.isOnline).thenReturn(false);
      when(
        authService.readCachedProfile(any),
      ).thenAnswer((_) async => profileJson);

      final user = await repository.getProfile();
      expect(user.id, 1);
      expect(adapter.capturedRequests, isEmpty);
      verify(authService.readCachedProfile(1)).called(1);
    });
  });

  group('10. cache acknowledgment', () {
    test(
      'a normal successful getProfile writes the offline cache once, '
      'stamped with the captured user id (not the response body id)',
      () async {
        login(7);
        // Response body lies about the id.
        adapter.body =
            '{"id":999,"name":"x","username":"x","email":"x@x.com",'
            '"dateCreated":"2024-01-01T00:00:00Z"}';

        await repository.getProfile();

        verify(authService.writeCachedProfile(any, 7)).called(1);
        verifyNever(authService.writeCachedProfile(any, 999));
      },
    );

    test('a getProfile whose response lands after logout throws '
        'SessionStaleException and never writes the cache', () async {
      login(1);
      adapter.responseGate = Completer<ResponseBody>();
      when(
        authService.readCachedProfile(any),
      ).thenAnswer((_) async => profileJson);

      final future = repository.getProfile();
      await adapter.dispatched.future;

      // Logout lands while the response is still in flight.
      epoch.invalidate();
      adapter.responseGate!.complete(
        ResponseBody.fromString(
          profileJson,
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );

      await expectLater(future, throwsA(isA<SessionStaleException>()));
      verifyNever(authService.writeCachedProfile(any, any));
    });
  });
}
