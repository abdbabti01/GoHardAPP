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
import 'package:go_hard_app/data/local/models/local_food_item.dart';
import 'package:go_hard_app/data/local/models/local_food_template.dart';
import 'package:go_hard_app/data/local/models/local_meal_entry.dart';
import 'package:go_hard_app/data/local/models/local_meal_log.dart';
import 'package:go_hard_app/data/local/models/local_nutrition_goal.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/repositories/nutrition_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

import 'nutrition_repository_error_mapping_test.mocks.dart';

@GenerateMocks([AuthService, ConnectivityService])
/// Proves `NutritionRepository.calculateAndSaveNutrition` classifies a real
/// 400 MISSING_WEIGHT/MISSING_HEIGHT response into [MissingMetricsException]
/// through the ACTUAL production `ApiService` error-mapping pipeline
/// (`ApiService.post` -> `_mapError` -> `ApiException`), not a stub of it.
///
/// `ApiService.post` always wraps a Dio failure into an [ApiException]
/// before it reaches any repository, so a repository-level
/// `on DioException catch` can never fire - it is silently dead code. This
/// file exists because `NutritionRepository.calculateAndSaveNutrition` had
/// exactly that bug: the missing-metrics branch never ran, so a real 400
/// response fell through to the generic catch and returned `null` instead of
/// throwing `MissingMetricsException` - silently breaking the
/// `SmartGoalDialog` nutrition-setup step's promised "send the user to Body
/// Metrics" recovery (`smart_goal_dialog.dart`'s
/// `on MissingMetricsException catch` around `_applyNutritionPreview`'s call
/// to this method).
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

  const userId = 1;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'nutrition_repo_error_mapping_',
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

    mockAuthService = MockAuthService();
    mockConnectivity = MockConnectivityService();
    when(mockConnectivity.isOnline).thenReturn(true);
    when(mockAuthService.getUserId()).thenAnswer((_) async => userId);
    when(mockAuthService.getToken()).thenAnswer((_) async => 'jwt-$userId');

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    sessionEpoch = UserSessionEpoch()..activate(userId);
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
    await isar.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ResponseBody jsonResponse(Object json, {int statusCode = 200}) =>
      ResponseBody.fromString(
        jsonEncode(json),
        statusCode,
        headers: {
          'content-type': ['application/json'],
        },
      );

  group('calculateAndSaveNutrition error mapping', () {
    test('a real 400 MISSING_WEIGHT response throws MissingMetricsException, '
        'not a swallowed null', () async {
      adapter.responder =
          (_) async => jsonResponse({
            'code': 'MISSING_WEIGHT',
            'message': 'Please add your current weight first.',
            'action': 'GO_TO_BODY_METRICS',
            'missingFields': ['weight'],
          }, statusCode: 400);

      await expectLater(
        repository.calculateAndSaveNutrition(goalType: 'WeightLoss'),
        throwsA(
          isA<MissingMetricsException>()
              .having((e) => e.code, 'code', 'MISSING_WEIGHT')
              .having(
                (e) => e.message,
                'message',
                'Please add your current weight first.',
              ),
        ),
      );
    });

    test(
      'a real 400 MISSING_HEIGHT response throws MissingMetricsException',
      () async {
        adapter.responder =
            (_) async => jsonResponse({
              'code': 'MISSING_HEIGHT',
              'message': 'Please add your height first.',
              'action': 'GO_TO_BODY_METRICS',
              'missingFields': ['height'],
            }, statusCode: 400);

        await expectLater(
          repository.calculateAndSaveNutrition(goalType: 'WeightLoss'),
          throwsA(
            isA<MissingMetricsException>().having(
              (e) => e.code,
              'code',
              'MISSING_HEIGHT',
            ),
          ),
        );
      },
    );

    test(
      'an unrelated 400 (no missing-metrics code) returns null rather than '
      'throwing - only the specific missing-metrics codes are reclassified',
      () async {
        adapter.responder =
            (_) async => jsonResponse({
              'code': 'SOME_OTHER_VALIDATION_ERROR',
              'message': 'nope',
            }, statusCode: 400);

        final result = await repository.calculateAndSaveNutrition(
          goalType: 'WeightLoss',
        );

        expect(result, isNull);
      },
    );

    test('a real 500 response returns null (existing generic-failure behavior '
        'unaffected)', () async {
      adapter.responder =
          (_) async => jsonResponse({'message': 'boom'}, statusCode: 500);

      final result = await repository.calculateAndSaveNutrition(
        goalType: 'WeightLoss',
      );

      expect(result, isNull);
    });
  });
}

/// A deterministic fake Dio transport, mirroring the one in
/// `nutrition_repository_background_session_test.dart`.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  Future<ResponseBody> Function(RequestOptions options)? responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
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
