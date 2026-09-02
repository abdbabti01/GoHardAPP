import 'dart:async';
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
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/models/program.dart';
import 'package:go_hard_app/data/models/program_workout.dart';
import 'package:go_hard_app/data/repositories/programs_repository.dart';
import 'package:go_hard_app/data/services/api_exception.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';
import 'package:go_hard_app/data/services/session_request_context.dart';
import 'package:go_hard_app/data/services/session_request_exceptions.dart';

@GenerateMocks([AuthService, ConnectivityService])
import 'programs_repository_session_ownership_test.mocks.dart';

/// Proves [ProgramsRepository] is fully session-bound: every authenticated
/// HTTP call carries the [SessionRequestContext] captured at operation entry
/// (pinned JWT + generation `CancelToken`), a logged-out call dispatches
/// nothing (matching each method's pre-existing empty/exception convention),
/// mid-flight session invalidation surfaces as [SessionStaleException],
/// cancellation surfaces as [RequestCancelledException] - never as a generic
/// error and never through `onUnauthorized` - and the local completion
/// overlay is scoped to the user captured at entry, never a live
/// `AuthService.getUserId()` re-read, and throws [SessionStaleException]
/// (never returning captured-user data, overlaid or not) if the session ends
/// while its Isar read is in flight, while an ordinary Isar failure keeps the
/// established "return the un-overlaid Program" fallback.
///
/// Uses a REAL [ApiService] + [SessionRequestCoordinator] + [UserSessionEpoch]
/// wired to a deterministic fake [HttpClientAdapter], plus a real temp Isar
/// db for the overlay. No test uses a wall-clock delay, `Future.delayed`,
/// `Timer`, or event-queue pumping - synchronization is via `Completer`s tied
/// to the fake adapter's actual dispatch and the repository's
/// `afterLocalSessionsReadForTesting` seam.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  Completer<void> dispatched = Completer<void>();

  bool holdForever = false;
  // When set, `fetch` awaits this before returning the response - lets a test
  // land a logout AFTER dispatch but BEFORE the response is delivered.
  Completer<void>? releaseGate;
  int statusCode = 200;
  String body = '{}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequests.add(options);
    if (!dispatched.isCompleted) dispatched.complete();
    if (holdForever) {
      return Completer<ResponseBody>().future;
    }
    final gate = releaseGate;
    if (gate != null) await gate.future;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Isar isar;
  late Directory tempDir;
  late UserSessionEpoch epoch;
  late MockAuthService authService;
  late MockConnectivityService connectivity;
  late SessionRequestCoordinator coordinator;
  late ApiService apiService;
  late _FakeHttpClientAdapter adapter;
  late LocalDatabaseService localDb;
  late ProgramsRepository repository;
  late int unauthorizedCalls;

  // A program (server) JSON with a single not-yet-completed workout id 10.
  String programJson({int id = 1, int workoutId = 10}) =>
      '{"id":$id,"userId":1,"title":"P$id","totalWeeks":4,"currentWeek":1,'
      '"currentDay":1,"startDate":"2024-01-01","isActive":true,'
      '"isCompleted":false,"createdAt":"2024-01-01T00:00:00Z","workouts":['
      '{"id":$workoutId,"programId":$id,"weekNumber":1,"dayNumber":1,'
      '"workoutName":"W","exercisesJson":"[]","isCompleted":false,'
      '"orderIndex":0}]}';

  // A program (server) JSON with NO workouts - exercises the helper's
  // early-return path.
  String programJsonNoWorkouts({int id = 1}) =>
      '{"id":$id,"userId":1,"title":"P$id","totalWeeks":4,"currentWeek":1,'
      '"currentDay":1,"startDate":"2024-01-01","isActive":true,'
      '"isCompleted":false,"createdAt":"2024-01-01T00:00:00Z","workouts":[]}';

  final workoutJson =
      '{"id":10,"programId":1,"weekNumber":1,"dayNumber":1,"workoutName":"W",'
      '"exercisesJson":"[]","isCompleted":false,"orderIndex":0}';

  const impactJson = '{"sessionsCount":3}';

  Program program(int id) => Program(
    id: id,
    userId: 1,
    title: 'P$id',
    totalWeeks: 4,
    currentWeek: 1,
    currentDay: 1,
    startDate: DateTime.utc(2024, 1, 1),
    isActive: true,
    isCompleted: false,
    createdAt: DateTime.utc(2024, 1, 1),
  );

  ProgramWorkout workout(int id) => ProgramWorkout(
    id: id,
    programId: 1,
    weekNumber: 1,
    dayNumber: 1,
    workoutName: 'W',
    exercisesJson: '[]',
    isCompleted: false,
    orderIndex: 0,
  );

  Future<void> seedSession({
    required int userId,
    required int programId,
    required int programWorkoutId,
    String status = 'completed',
  }) async {
    await isar.writeTxn(() async {
      await isar.localSessions.put(
        LocalSession(
          userId: userId,
          date: DateTime.utc(2024, 1, 1),
          status: status,
          isSynced: true,
          syncStatus: 'synced',
          lastModifiedLocal: DateTime.utc(2024, 1, 1),
          programId: programId,
          programWorkoutId: programWorkoutId,
        ),
      );
    });
  }

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('programs_repo_owner_');
    isar = await Isar.open(
      [LocalSessionSchema],
      directory: tempDir.path,
      inspector: false,
    );

    epoch = UserSessionEpoch();
    authService = MockAuthService();
    connectivity = MockConnectivityService();
    when(connectivity.isOnline).thenReturn(true);
    // getUserId is deliberately stubbed to a user that owns NO local rows:
    // any overlay that still reads it live would find nothing.
    when(authService.getUserId()).thenAnswer((_) async => 999);
    coordinator = SessionRequestCoordinator(epoch, authService);
    apiService = ApiService(authService, epoch);
    adapter = _FakeHttpClientAdapter();
    apiService.testHttpClientAdapter = adapter;
    unauthorizedCalls = 0;
    apiService.onUnauthorized = () => unauthorizedCalls++;

    localDb = LocalDatabaseService.instance;
    localDb.setTestDatabase(isar);

    repository = ProgramsRepository(
      apiService,
      epoch,
      coordinator,
      connectivity,
      localDb,
    );
  });

  tearDown(() async {
    repository.afterLocalSessionsReadForTesting = null;
    apiService.beforeDispatchEpochCheckForTesting = null;
    await isar.close(deleteFromDisk: true);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  void login(int id) {
    epoch.activate(id);
    when(authService.getToken()).thenAnswer((_) async => 'jwt-$id');
  }

  UserSessionToken? extraToken(RequestOptions o) =>
      o.extra[ApiService.sessionEpochExtraKey] as UserSessionToken?;

  // ===========================================================================
  group('1. logged-out calls dispatch no HTTP', () {
    test('no session: getPrograms returns empty, every other op throws '
        'SessionStaleException, adapter never touched', () async {
      when(authService.getToken()).thenAnswer((_) async => null);

      expect(await repository.getPrograms(), isEmpty);
      await expectLater(
        repository.getProgramById(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.createProgram(program(1)),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.updateProgram(1, program(1)),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.getDeletionImpact(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.deleteProgram(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.completeProgram(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.recalibrateProgram(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.advanceProgram(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.getWeekWorkouts(1, 1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.getTodaysWorkout(1),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.addWorkout(1, workout(10)),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.updateWorkout(10, workout(10)),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.swapWorkouts(10, 11),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.completeWorkout(10),
        throwsA(isA<SessionStaleException>()),
      );
      await expectLater(
        repository.deleteWorkout(10),
        throwsA(isA<SessionStaleException>()),
      );

      expect(adapter.capturedRequests, isEmpty);
    });

    test(
      'session invalidated before the call: getPrograms empty, no HTTP',
      () async {
        login(1);
        epoch.invalidate();

        expect(await repository.getPrograms(), isEmpty);
        expect(adapter.capturedRequests, isEmpty);
      },
    );
  });

  // ===========================================================================
  group('2-3. every authenticated call carries the captured context', () {
    test(
      'getPrograms: pinned JWT, epoch token, generation CancelToken',
      () async {
        login(1);
        adapter.body = '[]';
        final probe = await coordinator.captureContext();

        await repository.getPrograms();

        final sent = adapter.capturedRequests.single;
        expect(sent.headers['Authorization'], 'Bearer jwt-1');
        expect(extraToken(sent)!.userId, 1);
        expect(identical(sent.cancelToken, probe!.cancelToken), isTrue);
      },
    );

    test('every method is bound to the entry-captured context', () async {
      login(1);
      adapter.body = programJson();
      await repository.getProgramById(1);
      await repository.createProgram(program(1));
      await repository.advanceProgram(1);
      adapter.body = '{}';
      await repository.updateProgram(1, program(1));
      await repository.completeProgram(1);
      await repository.recalibrateProgram(1);
      await repository.updateWorkout(10, workout(10));
      await repository.swapWorkouts(10, 11);
      await repository.completeWorkout(10, notes: 'ok');
      await repository.deleteProgram(1);
      await repository.deleteWorkout(10);
      adapter.body = workoutJson;
      await repository.addWorkout(1, workout(10));
      await repository.getTodaysWorkout(1);
      adapter.body = '[]';
      await repository.getWeekWorkouts(1, 1);
      adapter.body = impactJson;
      await repository.getDeletionImpact(1);

      expect(adapter.capturedRequests, hasLength(15));
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

        await repository.getPrograms();

        expect(
          adapter.capturedRequests.single.headers['Authorization'],
          'Bearer jwt-1',
        );
      },
    );
  });

  // ===========================================================================
  group('4. invalidation before dispatch -> SessionStaleException', () {
    test(
      'getPrograms rethrows SessionStaleException, no request sent',
      () async {
        login(1);
        apiService.beforeDispatchEpochCheckForTesting = () async {
          epoch.invalidate();
        };

        await expectLater(
          repository.getPrograms(),
          throwsA(isA<SessionStaleException>()),
        );
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('advanceProgram rethrows SessionStaleException', () async {
      login(1);
      apiService.beforeDispatchEpochCheckForTesting = () async {
        epoch.invalidate();
      };

      await expectLater(
        repository.advanceProgram(1),
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

  // ===========================================================================
  group('5-6. in-flight cancellation -> RequestCancelledException', () {
    test('cancelling the generation surfaces RequestCancelledException, '
        'distinct from ApiException', () async {
      login(1);
      adapter.holdForever = true;

      final future = repository.getPrograms();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('cancellation does not invoke onUnauthorized', () async {
      login(1);
      adapter.holdForever = true;

      final future = repository.advanceProgram(1);
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();

      await expectLater(future, throwsA(isA<RequestCancelledException>()));
      expect(unauthorizedCalls, 0);
    });
  });

  // ===========================================================================
  group('7-8. user B is unaffected by user A', () {
    test(
      'after A logs out and B logs in, B captures a fresh context',
      () async {
        login(1);
        epoch.invalidate();
        login(2);
        adapter.body = '[]';

        await repository.getPrograms();

        final sent = adapter.capturedRequests.single;
        expect(sent.headers['Authorization'], 'Bearer jwt-2');
        expect(extraToken(sent)!.userId, 2);
      },
    );

    test("A's cancelled generation cannot cancel B's later request", () async {
      login(1);
      adapter.holdForever = true;
      final aFuture = repository.getPrograms();
      await adapter.dispatched.future;
      coordinator.cancelCurrentGeneration();
      await expectLater(aFuture, throwsA(isA<RequestCancelledException>()));

      epoch.invalidate();
      login(2);
      adapter
        ..holdForever = false
        ..dispatched = Completer<void>()
        ..body = '[]';

      final bResult = await repository.getPrograms();
      expect(bResult, isEmpty);
      expect(
        adapter.capturedRequests.last.headers['Authorization'],
        'Bearer jwt-2',
      );
    });
  });

  // ===========================================================================
  group('9. single bound request per method (no nested/follow-up HTTP)', () {
    test('getPrograms with the local overlay still dispatches exactly one '
        'bound request', () async {
      login(1);
      await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
      adapter.body = '[${programJson()}]';

      final result = await repository.getPrograms(isActive: true);

      expect(adapter.capturedRequests, hasLength(1));
      final sent = adapter.capturedRequests.single;
      expect(sent.uri.queryParameters['isActive'], 'true');
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
      expect(extraToken(sent), isNotNull);
      // Overlay applied from the captured user's local session.
      expect(result.single.workouts!.single.isCompleted, isTrue);
    });

    test('getProgramById dispatches exactly one bound request', () async {
      login(1);
      adapter.body = programJson();

      await repository.getProgramById(7);

      expect(adapter.capturedRequests, hasLength(1));
      expect(adapter.capturedRequests.single.uri.path, contains('programs/7'));
    });
  });

  // ===========================================================================
  group('10. ordinary failures preserve existing public behavior', () {
    test('getPrograms: a 500 rethrows an ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(repository.getPrograms(), throwsA(isA<ApiException>()));
    });

    test('advanceProgram: a 500 propagates as ApiException', () async {
      login(1);
      adapter
        ..statusCode = 500
        ..body = '{"message":"boom"}';

      await expectLater(
        repository.advanceProgram(1),
        throwsA(isA<ApiException>()),
      );
    });

    test('offline: getPrograms returns empty, no HTTP', () async {
      login(1);
      when(connectivity.isOnline).thenReturn(false);

      expect(await repository.getPrograms(), isEmpty);
      expect(adapter.capturedRequests, isEmpty);
    });
  });

  // ===========================================================================
  group('11-13. local completion overlay is bound to the captured user', () {
    test('10: overlay uses the entry-captured epoch user, never a live '
        'getUserId() re-read', () async {
      login(1);
      // getUserId() returns 999 (no rows). Only epoch user 1 owns this row.
      await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
      adapter.body = '[${programJson()}]';

      final result = await repository.getPrograms();

      expect(result.single.workouts!.single.isCompleted, isTrue);
      verifyNever(authService.getUserId());
    });

    test(
      "10: a different user's local sessions never overlay this user's program",
      () async {
        login(1);
        await seedSession(userId: 2, programId: 1, programWorkoutId: 10);
        adapter.body = '[${programJson()}]';

        final result = await repository.getPrograms();

        expect(result.single.workouts!.single.isCompleted, isFalse);
      },
    );

    test('getProgramById overlay is scoped to the captured user too', () async {
      login(1);
      await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
      adapter.body = programJson();

      final result = await repository.getProgramById(1);

      expect(result.workouts!.single.isCompleted, isTrue);
    });

    test('9: an ordinary (non-lifecycle) Isar overlay failure still returns '
        'the un-overlaid Program', () async {
      login(1);
      await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
      adapter.body = '[${programJson()}]';
      // A non-lifecycle throw from inside the overlay - session stays current.
      repository.afterLocalSessionsReadForTesting = () async {
        throw StateError('isar boom');
      };

      final result = await repository.getPrograms();

      expect(result, hasLength(1));
      expect(result.single.workouts!.single.isCompleted, isFalse);
    });
  });

  // ===========================================================================
  group(
    '14. stale-during-overlay -> SessionStaleException, no A data leaks',
    () {
      test(
        '1-5: getPrograms - epoch invalidated during the overlay await '
        'throws and returns neither the original nor a partial A list',
        () async {
          login(1);
          await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
          adapter.body = '[${programJson()}]';
          repository.afterLocalSessionsReadForTesting = () async {
            epoch.invalidate();
          };

          await expectLater(
            repository.getPrograms(),
            throwsA(isA<SessionStaleException>()),
          );
        },
      );

      test('1-5: getPrograms - user B activated during the overlay await also '
          'throws (never returns A data)', () async {
        login(1);
        await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
        adapter.body = '[${programJson()}]';
        repository.afterLocalSessionsReadForTesting = () async {
          epoch.invalidate();
          login(2);
        };

        await expectLater(
          repository.getPrograms(),
          throwsA(isA<SessionStaleException>()),
        );
      });

      test(
        'getProgramById - session changes during the overlay await -> throws',
        () async {
          login(1);
          await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
          adapter.body = programJson();
          repository.afterLocalSessionsReadForTesting = () async {
            epoch.invalidate();
          };

          await expectLater(
            repository.getProgramById(1),
            throwsA(isA<SessionStaleException>()),
          );
        },
      );

      test('6-8: multi-Program list - first overlay runs while A is current, '
          'session changes before the second - the WHOLE operation throws, no '
          'partially processed list is returned', () async {
        login(1);
        await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
        await seedSession(userId: 1, programId: 2, programWorkoutId: 20);
        adapter.body =
            '[${programJson(id: 1, workoutId: 10)},'
            '${programJson(id: 2, workoutId: 20)}]';

        var overlayCalls = 0;
        repository.afterLocalSessionsReadForTesting = () async {
          // Let the first Program's overlay complete, then break the session
          // just before the second Program's post-read check.
          if (++overlayCalls == 2) epoch.invalidate();
        };

        await expectLater(
          repository.getPrograms(),
          throwsA(isA<SessionStaleException>()),
        );
      });

      test('cancellation during the overlay is not converted to an overlay '
          'fallback', () async {
        login(1);
        await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
        adapter.body = '[${programJson()}]';
        repository.afterLocalSessionsReadForTesting = () async {
          throw const RequestCancelledException();
        };

        await expectLater(
          repository.getPrograms(),
          throwsA(isA<RequestCancelledException>()),
        );
      });

      test('a generic catch never swallows SessionStaleException from the '
          'overlay', () async {
        // Regression guard for "generic catch swallows SessionStaleException":
        // the helper rethrows lifecycle exceptions ahead of its `return
        // program` fallback.
        login(1);
        await seedSession(userId: 1, programId: 1, programWorkoutId: 10);
        adapter.body = programJson();
        repository.afterLocalSessionsReadForTesting = () async {
          epoch.invalidate();
        };

        Object? caught;
        try {
          await repository.getProgramById(1);
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<SessionStaleException>());
      });

      test(
        'workout-less Program: getProgramById still throws when the '
        'session is invalidated in the gap after the HTTP response - the '
        'entry pre-read check runs ahead of the "no workouts" early return',
        () async {
          login(1);
          adapter
            ..body = programJsonNoWorkouts()
            ..releaseGate = Completer<void>();

          final f = repository.getProgramById(1);
          await adapter.dispatched.future;
          epoch.invalidate();
          adapter.releaseGate!.complete();

          await expectLater(f, throwsA(isA<SessionStaleException>()));
        },
      );

      test(
        'all-workout-less list: getPrograms throws (never returns the '
        'un-overlaid A list) when the session dies after the HTTP response',
        () async {
          login(1);
          adapter
            ..body =
                '[${programJsonNoWorkouts(id: 1)},'
                '${programJsonNoWorkouts(id: 2)}]'
            ..releaseGate = Completer<void>();

          final f = repository.getPrograms();
          await adapter.dispatched.future;
          epoch.invalidate();
          adapter.releaseGate!.complete();

          await expectLater(f, throwsA(isA<SessionStaleException>()));
        },
      );
    },
  );
}
