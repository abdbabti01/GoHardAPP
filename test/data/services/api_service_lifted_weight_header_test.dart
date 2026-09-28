import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/constants/api_config.dart';
import 'package:go_hard_app/core/services/session_request_coordinator.dart';
import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'api_service_lifted_weight_header_test.mocks.dart';

/// Task 5: the API rejects a lifted-weight set POST/PUT with no
/// `X-Lifted-Weight-Unit: kg` header once the server-side contract is
/// enabled (see the global constraints doc). Every request this app sends -
/// plain or session-bound, any HTTP verb, public or authenticated - must
/// always carry it, proven against the real Dio interceptor pipeline via a
/// fake [HttpClientAdapter] (never a stub of [ApiService] itself).
@GenerateMocks([AuthService])
void main() {
  late MockAuthService authService;
  late UserSessionEpoch sessionEpoch;
  late SessionRequestCoordinator sessionCoordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;

  setUp(() {
    authService = MockAuthService();
    when(authService.getUserId()).thenAnswer((_) async => 1);
    when(authService.getToken()).thenAnswer((_) async => 'jwt-1');

    sessionEpoch = UserSessionEpoch()..activate(1);
    sessionCoordinator = SessionRequestCoordinator(sessionEpoch, authService);
    apiService = ApiService(authService, sessionEpoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
  });

  ResponseBody okBody() => ResponseBody.fromString(
    '{}',
    200,
    headers: {
      'content-type': ['application/json'],
    },
  );

  String? headerOf(RequestOptions options) =>
      options.headers[ApiConfig.liftedWeightUnitHeader] as String?;

  test('a plain (unbound) GET carries the header', () async {
    adapter.responder = (_) async => okBody();

    await apiService.get<Map<String, dynamic>>('exercisesets');

    expect(
      headerOf(adapter.capturedRequests.single),
      ApiConfig.liftedWeightCanonicalUnit,
    );
  });

  test('every unbound wrapper (POST/PUT/PATCH/DELETE) and the public POST '
      'carry the header', () async {
    adapter.responder = (_) async => okBody();

    await apiService.post<Map<String, dynamic>>('exercisesets', data: {});
    await apiService.put<void>('exercisesets/1', data: {});
    await apiService.patch<void>('exercisesets/1', data: {});
    await apiService.delete('exercisesets/1');
    await apiService.postPublic<Map<String, dynamic>>('auth/login', data: {});

    expect(adapter.capturedRequests, hasLength(5));
    for (final req in adapter.capturedRequests) {
      expect(
        headerOf(req),
        ApiConfig.liftedWeightCanonicalUnit,
        reason: '${req.method} ${req.path}',
      );
    }
  });

  test(
    'a session-bound request (SessionRequestContext) also carries the header',
    () async {
      adapter.responder = (_) async => okBody();
      final context = await sessionCoordinator.captureContext();

      await apiService.get<Map<String, dynamic>>(
        'exercisesets',
        sessionContext: context,
      );
      await apiService.post<Map<String, dynamic>>(
        'exercisesets',
        data: {},
        sessionContext: context,
      );

      expect(adapter.capturedRequests, hasLength(2));
      for (final req in adapter.capturedRequests) {
        expect(headerOf(req), ApiConfig.liftedWeightCanonicalUnit);
      }
    },
  );

  test('the header value is always exactly kg, never any other unit', () {
    expect(ApiConfig.liftedWeightCanonicalUnit, 'kg');
    expect(ApiConfig.liftedWeightUnitHeader, 'X-Lifted-Weight-Unit');
  });
}

/// Minimal fake Dio transport - records every dispatched [RequestOptions]
/// and answers with [responder] (default: an empty 200 JSON body). Mirrors
/// the fake adapter used in analytics_repository_session_ownership_test.dart.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];
  Future<ResponseBody> Function(RequestOptions options)? responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    capturedRequests.add(options);
    final respond = responder;
    if (respond != null) return respond(options);
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
