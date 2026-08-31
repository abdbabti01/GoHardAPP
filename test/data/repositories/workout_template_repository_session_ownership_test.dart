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
import 'package:go_hard_app/data/models/workout_template.dart';
import 'package:go_hard_app/data/repositories/workout_template_repository.dart';
import 'package:go_hard_app/data/services/api_service.dart';
import 'package:go_hard_app/data/services/auth_service.dart';

@GenerateMocks([AuthService, ConnectivityService])
import 'workout_template_repository_session_ownership_test.mocks.dart';

/// Proves [WorkoutTemplateRepository] is fully session-bound (every HTTP call
/// carries the session that started the operation) and cache-ownership-safe
/// (every local read/write/delete is scoped to
/// `WorkoutTemplate.cachedForUserId`, which is distinct from the author
/// identity `createdByUserId` and from the local/server id split), mirroring
/// `shared_workout_repository_session_ownership_test.dart`.
///
/// Uses a REAL [ApiService] wired to a fake [HttpClientAdapter] so credential
/// pinning and dispatch-time staleness rejection are proven against the real
/// production interceptor pipeline, and a REAL [UserSessionEpoch] /
/// [SessionRequestCoordinator].
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
  late WorkoutTemplateRepository repository;
  late List<Future<void>> scheduledBackgroundSyncs;

  const userA = 1;
  const userB = 2;

  int? currentAuthUserId;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('workout_template_repo_');
    isar = await Isar.open(
      [WorkoutTemplateSchema],
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

    repository = WorkoutTemplateRepository(
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

  // ============ Fixtures ============

  Future<WorkoutTemplate> seed({
    int? serverId,
    int? cachedForUserId,
    int? createdByUserId,
    bool isActive = true,
    bool isCustom = true,
    bool isPublic = false,
    String name = 'Seed template',
    String? category = 'Strength',
    int usageCount = 0,
    double? rating,
    int ratingCount = 0,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  }) async {
    final t = WorkoutTemplate(
      serverId: serverId,
      cachedForUserId: cachedForUserId,
      createdByUserId: createdByUserId,
      name: name,
      exercisesJson: '[]',
      recurrencePattern: 'daily',
      category: category,
      isActive: isActive,
      isCustom: isCustom,
      isPublic: isPublic,
      usageCount: usageCount,
      rating: rating,
      ratingCount: ratingCount,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
      lastUsedAt: lastUsedAt,
    );
    await isar.writeTxn(() => isar.workoutTemplates.put(t));
    return t;
  }

  Map<String, dynamic> dto({
    required int id,
    int? createdByUserId,
    String? createdByUserName,
    bool isActive = true,
    bool isCustom = true,
    bool isPublic = false,
    String name = 'Server template',
    String? category = 'Strength',
    int usageCount = 0,
    double? rating,
    int ratingCount = 0,
    String? lastUsedAt,
  }) => {
    'id': id,
    'name': name,
    'description': null,
    'exercisesJson': '[]',
    'recurrencePattern': 'daily',
    'daysOfWeek': null,
    'intervalDays': null,
    'estimatedDuration': 30,
    'category': category,
    'isActive': isActive,
    'isCustom': isCustom,
    'isPublic': isPublic,
    'createdByUserId': createdByUserId,
    'createdByUserName': createdByUserName,
    'usageCount': usageCount,
    'rating': rating,
    'ratingCount': ratingCount,
    'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    'lastUsedAt': lastUsedAt,
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

  group('logged out', () {
    test('every operation does zero HTTP and zero Isar mutation', () async {
      final row = await seed(
        serverId: 10,
        cachedForUserId: userA,
        createdByUserId: userA,
      );

      expect(await repository.getTemplates(), isEmpty);
      expect(await repository.getCommunityTemplates(), isEmpty);
      expect(await repository.getTemplateById(10), isNull);
      await expectLater(
        () => repository.createTemplate(
          name: 'x',
          exercisesJson: '[]',
          recurrencePattern: 'daily',
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => repository.updateTemplate(row),
        throwsA(isA<Exception>()),
      );
      expect(await repository.toggleActive(row), isNull);
      expect(await repository.deleteTemplate(row), isFalse);
      await repository.incrementUsageCount(row);
      await expectLater(
        () => repository.rateTemplate(10, 4),
        throwsA(isA<Exception>()),
      );

      expect(adapter.capturedRequests, isEmpty);
      expect(scheduledBackgroundSyncs, isEmpty);
      final stored = await isar.workoutTemplates.get(row.localId);
      expect(stored, isNotNull);
      expect(stored!.usageCount, 0);
      expect(stored.isActive, isTrue);
    });
  });

  // ============ 2. Offline cache-ownership reads ============

  group('offline reads are scoped to the captured cache owner', () {
    setUp(() => when(mockConnectivity.isOnline).thenReturn(false));

    test(
      'my-templates returns only rows this user cached AND authored',
      () async {
        await seed(serverId: 1, cachedForUserId: userA, createdByUserId: userA);
        await seed(serverId: 2, cachedForUserId: userB, createdByUserId: userB);
        // Cached for A but authored by B - not "my template".
        await seed(serverId: 3, cachedForUserId: userA, createdByUserId: userB);
        // Authored by A but cached for B - not visible to A.
        await seed(serverId: 4, cachedForUserId: userB, createdByUserId: userA);
        loginAs(userA);

        final mine = await repository.getTemplates();

        expect(mine.map((t) => t.serverId), [1]);
        expect(adapter.capturedRequests, isEmpty);
      },
    );

    test('legacy null-owner rows are invisible', () async {
      await seed(serverId: 1, cachedForUserId: null, createdByUserId: userA);
      loginAs(userA);

      expect(await repository.getTemplates(), isEmpty);
      expect(await repository.getCommunityTemplates(), isEmpty);
    });

    test(
      'community read is scoped to the cache owner and visibility',
      () async {
        // system template cached for A
        await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: null,
          isCustom: false,
          name: 'system',
        );
        // published custom cached for A
        await seed(
          serverId: 2,
          cachedForUserId: userA,
          createdByUserId: userB,
          isPublic: true,
          name: 'published',
        );
        // private custom cached for A - excluded
        await seed(
          serverId: 3,
          cachedForUserId: userA,
          createdByUserId: userA,
          isPublic: false,
          name: 'private',
        );
        // published but cached for B - invisible to A
        await seed(
          serverId: 4,
          cachedForUserId: userB,
          createdByUserId: userB,
          isPublic: true,
          name: 'B only',
        );
        loginAs(userA);

        final community = await repository.getCommunityTemplates();
        expect(community.map((t) => t.serverId).toList()..sort(), [1, 2]);
      },
    );

    test('activeOnly filters inactive rows out of my-templates', () async {
      await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
        isActive: true,
      );
      await seed(
        serverId: 2,
        cachedForUserId: userA,
        createdByUserId: userA,
        isActive: false,
      );
      loginAs(userA);

      expect(
        (await repository.getTemplates(
          activeOnly: true,
        )).map((t) => t.serverId),
        [1],
      );
      expect(
        (await repository.getTemplates(
            activeOnly: false,
          )).map((t) => t.serverId).toList()
          ..sort(),
        [1, 2],
      );
    });
  });

  // ============ 3. HTTP binding ============

  group('HTTP binding', () {
    test(
      'every HTTP call carries the captured sessionContext + pinned JWT',
      () async {
        loginAs(userA);
        final tokenA = sessionEpoch.capture();
        // localId (auto-increment, 1) is deliberately distinct from serverId
        // (5), so every server-round-trip URL below is checked to use the
        // server id, never the local id.
        await seed(serverId: 5, cachedForUserId: userA, createdByUserId: userA);

        adapter.responder = (options) async {
          final p = options.path;
          if (options.method == 'GET' && p.contains('/community')) {
            return jsonResponse([
              dto(id: 8, createdByUserId: null, isCustom: false),
            ]);
          }
          if (options.method == 'GET' && RegExp(r'/\d+$').hasMatch(p)) {
            return jsonResponse(dto(id: 5, createdByUserId: userA));
          }
          if (options.method == 'GET') {
            return jsonResponse([dto(id: 5, createdByUserId: userA)]);
          }
          if (options.method == 'POST' && p.contains('/increment-usage')) {
            return jsonResponse({'usageCount': 3});
          }
          if (options.method == 'POST' && p.contains('/rate')) {
            return jsonResponse({'rating': 4.0, 'ratingCount': 2});
          }
          if (options.method == 'POST') {
            return jsonResponse(dto(id: 9, createdByUserId: userA));
          }
          if (options.method == 'PUT') {
            return ResponseBody.fromString('', 204);
          }
          if (options.method == 'PATCH') {
            return jsonResponse({'isActive': false});
          }
          if (options.method == 'DELETE') {
            return ResponseBody.fromString('', 204);
          }
          return jsonResponse(<dynamic>[]);
        };

        await repository.getTemplates();
        await scheduledBackgroundSyncs.first;
        await repository.getCommunityTemplates();
        await scheduledBackgroundSyncs.last;
        await repository.getTemplateById(5);
        final created = await repository.createTemplate(
          name: 'x',
          exercisesJson: '[]',
          recurrencePattern: 'daily',
        );
        await repository.updateTemplate(created..serverId = 5);
        final owned5 = await repository.getTemplateById(5);
        await repository.toggleActive(owned5!);
        await repository.incrementUsageCount(owned5);
        await repository.rateTemplate(5, 4);
        await repository.deleteTemplate(owned5);

        expect(adapter.capturedRequests, isNotEmpty);
        for (final req in adapter.capturedRequests) {
          expect(
            boundEpochOf(req),
            tokenA,
            reason: '${req.method} ${req.path} must be session-bound',
          );
          expect(req.headers['Authorization'], 'Bearer jwt-$userA');
        }

        // Every id-addressed server round-trip uses serverId (5), never the
        // local Isar id (1). (create POSTs to the collection, no id.)
        final byIdRequests = adapter.capturedRequests.where(
          (r) => RegExp(r'workouttemplates/\d+').hasMatch(r.path),
        );
        expect(byIdRequests.length, greaterThanOrEqualTo(5));
        for (final req in byIdRequests) {
          expect(
            RegExp(r'workouttemplates/(\d+)').firstMatch(req.path)!.group(1),
            '5',
            reason: '${req.method} ${req.path} must target serverId 5',
          );
        }
      },
    );

    test('a detached list refresh binds the JWT captured at scheduling time, '
        'never one re-read at dispatch', () async {
      loginAs(userA);
      // Storage silently flips to B before the refresh HTTP is dispatched;
      // the epoch is untouched. The refresh must still send jwt-1.
      repository.beforeBackgroundHttpDispatchForTesting = () async {
        currentAuthUserId = userB;
      };
      adapter.responder =
          (_) async => jsonResponse([dto(id: 1, createdByUserId: userA)]);

      await repository.getTemplates();
      await scheduledBackgroundSyncs.single;

      expect(
        adapter.capturedRequests.single.headers['Authorization'],
        'Bearer jwt-$userA',
      );
    });
  });

  // ============ 4. Detached refresh & stale sessions ============

  group('detached list refresh', () {
    test(
      'captures context at scheduling time, not inside the closure',
      () async {
        loginAs(userA);
        final tokenA = sessionEpoch.capture();
        final responseCompleter = Completer<ResponseBody>();
        adapter.responder = (_) => responseCompleter.future;

        final dispatched = adapter.nextDispatch();
        final future = repository.getTemplates();
        await dispatched;

        currentAuthUserId = userB; // storage flips before the response
        responseCompleter.complete(
          jsonResponse([dto(id: 1, createdByUserId: userA)]),
        );
        await future;
        await scheduledBackgroundSyncs.single;

        final req = adapter.capturedRequests.single;
        expect(boundEpochOf(req), tokenA);
        expect(req.headers['Authorization'], 'Bearer jwt-$userA');
        final stored =
            await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst();
        expect(stored!.cachedForUserId, userA);
      },
    );

    test('logout before dispatch produces no request and no write', () async {
      loginAs(userA);
      repository.beforeBackgroundHttpDispatchForTesting = () async => logout();

      final result = await repository.getTemplates();

      expect(result, isEmpty);
      await scheduledBackgroundSyncs.single;
      expect(adapter.capturedRequests, isEmpty);
      expect(await isar.workoutTemplates.count(), 0);
    });

    test(
      'account switch after HTTP but before the cache write produces no write',
      () async {
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse([dto(id: 1, createdByUserId: userA)]);
        repository.afterBackgroundHttpResponseForTesting =
            () async => loginAs(userB);

        await repository.getTemplates();
        await scheduledBackgroundSyncs.single;

        expect(await isar.workoutTemplates.count(), 0);
      },
    );

    test('a stale A refresh after clearAll cannot resurrect A rows', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse([dto(id: 1, createdByUserId: userA)]);
      repository.afterBackgroundHttpResponseForTesting = () async {
        logout();
        await isar.writeTxn(() => isar.workoutTemplates.clear());
        loginAs(userB);
      };

      await repository.getTemplates();
      await scheduledBackgroundSyncs.single;

      expect(await isar.workoutTemplates.count(), 0);
    });

    test(
      'the pre-writeTxn checkpoint skips the transaction once stale',
      () async {
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse([dto(id: 1, createdByUserId: userA)]);
        var enteredTxn = false;
        repository.afterBackgroundHttpResponseForTesting = () async => logout();
        repository.insideWriteTxnForTesting = () async => enteredTxn = true;

        await repository.getTemplates();
        await scheduledBackgroundSyncs.single;

        expect(enteredTxn, isFalse);
        expect(await isar.workoutTemplates.count(), 0);
      },
    );

    test('the first-statement-inside-writeTxn check blocks a logout that lands '
        'after the pre-writeTxn check passed', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse([dto(id: 1, createdByUserId: userA)]);
      // Session is still current at the pre-writeTxn check; it ends only once
      // execution is already inside the transaction.
      repository.insideWriteTxnForTesting = () async => logout();

      await repository.getTemplates();
      await scheduledBackgroundSyncs.single;

      expect(await isar.workoutTemplates.count(), 0);
    });

    test(
      'a valid response stamps the captured cache owner and preserves localId',
      () async {
        final existing = await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
          name: 'old',
        );
        loginAs(userA);
        adapter.responder =
            (_) async =>
                jsonResponse([dto(id: 1, createdByUserId: userA, name: 'new')]);

        await repository.getTemplates();
        await scheduledBackgroundSyncs.single;

        final rows = await isar.workoutTemplates.where().findAll();
        expect(rows, hasLength(1));
        expect(rows.single.localId, existing.localId);
        expect(rows.single.name, 'new');
        expect(rows.single.cachedForUserId, userA);
      },
    );

    test('a hostile cachedForUserId in the response JSON is ignored', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse([
            {...dto(id: 1, createdByUserId: userA), 'cachedForUserId': userB},
          ]);

      await repository.getTemplates();
      await scheduledBackgroundSyncs.single;

      final stored =
          await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst();
      expect(stored!.cachedForUserId, userA);
    });

    test(
      "a B refresh never overwrites A's own row for the same serverId",
      () async {
        final aRow = await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
          name: 'A row',
        );
        loginAs(userB);
        adapter.responder =
            (_) async => jsonResponse([
              dto(id: 1, createdByUserId: userB, name: 'B row'),
            ]);

        await repository.getTemplates();
        await scheduledBackgroundSyncs.single;

        final stored = await isar.workoutTemplates.get(aRow.localId);
        expect(stored!.name, 'A row');
        expect(stored.cachedForUserId, userA);
        final bRow =
            await isar.workoutTemplates
                .filter()
                .serverIdEqualTo(1)
                .and()
                .cachedForUserIdEqualTo(userB)
                .findFirst();
        expect(bRow!.name, 'B row');
      },
    );

    test('the own-list refresh sweeps this user\'s own rows deleted elsewhere, '
        'but never offline-only or foreign rows', () async {
      final keep = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
        name: 'still on server',
      );
      final deletedElsewhere = await seed(
        serverId: 2,
        cachedForUserId: userA,
        createdByUserId: userA,
        name: 'deleted on device B',
      );
      final offlineOnly = await seed(
        cachedForUserId: userA,
        createdByUserId: userA,
        name: 'offline draft',
      );
      final foreign = await seed(
        serverId: 3,
        cachedForUserId: userB,
        createdByUserId: userB,
        name: 'B row',
      );
      // A community template A has cached (cached for A, authored by someone
      // else). The owner-list refresh must never sweep it just because it is
      // absent from the owner list.
      final communityCached = await seed(
        serverId: 4,
        cachedForUserId: userA,
        createdByUserId: userB,
        isPublic: true,
        name: 'community cached',
      );
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse([dto(id: 1, createdByUserId: userA)]);

      await repository.getTemplates();
      await scheduledBackgroundSyncs.single;

      expect(await isar.workoutTemplates.get(keep.localId), isNotNull);
      expect(await isar.workoutTemplates.get(deletedElsewhere.localId), isNull);
      expect(await isar.workoutTemplates.get(offlineOnly.localId), isNotNull);
      expect(await isar.workoutTemplates.get(foreign.localId), isNotNull);
      expect(
        await isar.workoutTemplates.get(communityCached.localId),
        isNotNull,
      );
    });

    test('a stale own-list refresh never sweeps rows', () async {
      final row = await seed(
        serverId: 9,
        cachedForUserId: userA,
        createdByUserId: userA,
      );
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse(<dynamic>[]); // server: user has none
      repository.afterBackgroundHttpResponseForTesting = () async => logout();

      await repository.getTemplates();
      await scheduledBackgroundSyncs.single;

      expect(await isar.workoutTemplates.get(row.localId), isNotNull);
    });

    test('a community refresh never sweeps - its list is limit-capped, not '
        'authoritative', () async {
      final mine = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
        isPublic: true,
        name: 'my published',
      );
      final system = await seed(
        serverId: 2,
        cachedForUserId: userA,
        createdByUserId: null,
        isCustom: false,
        name: 'cached system',
      );
      loginAs(userA);
      // Community response omits both (e.g. beyond the page limit).
      adapter.responder = (_) async => jsonResponse(<dynamic>[]);

      await repository.getCommunityTemplates();
      await scheduledBackgroundSyncs.single;

      expect(await isar.workoutTemplates.get(mine.localId), isNotNull);
      expect(await isar.workoutTemplates.get(system.localId), isNotNull);
    });
  });

  // ============ 5. Mutation acknowledgments ============

  group('mutations', () {
    test('createTemplate online stamps the captured cache owner', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse(dto(id: 42, createdByUserId: userA));

      final created = await repository.createTemplate(
        name: 'x',
        exercisesJson: '[]',
        recurrencePattern: 'daily',
      );

      expect(created.cachedForUserId, userA);
      final stored =
          await isar.workoutTemplates.filter().serverIdEqualTo(42).findFirst();
      expect(stored!.cachedForUserId, userA);
      expect(stored.createdByUserId, userA);

      final body = adapter.capturedRequests.single.data as Map;
      expect(body.keys, isNot(contains('id')));
      expect(body.keys, isNot(contains('createdByUserId')));
      expect(body.keys, isNot(contains('isCustom')));
      expect(body.keys, isNot(contains('usageCount')));
      expect(body.keys, isNot(contains('cachedForUserId')));
      expect(body.keys, isNot(contains('userId')));
      expect(body.keys, isNot(contains('isCommunity')));
      expect(body.keys, isNot(contains('updatedAt')));
    });

    test(
      'updateTemplate online PUTs then re-fetches and preserves localId',
      () async {
        final row = await seed(
          serverId: 7,
          cachedForUserId: userA,
          createdByUserId: userA,
          name: 'before',
        );
        loginAs(userA);
        var putSeen = false;
        adapter.responder = (options) async {
          if (options.method == 'PUT') {
            putSeen = true;
            return ResponseBody.fromString('', 204);
          }
          return jsonResponse(
            dto(id: 7, createdByUserId: userA, name: 'after-server'),
          );
        };

        final updated = await repository.updateTemplate(
          row..name = 'after-local',
        );

        expect(putSeen, isTrue);
        expect(updated.localId, row.localId);
        expect(updated.name, 'after-server');
        final rows = await isar.workoutTemplates.where().findAll();
        expect(rows, hasLength(1));
        expect(rows.single.name, 'after-server');
      },
    );

    test(
      'toggleActive applies the acknowledged state to the owned row only',
      () async {
        await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
          isActive: true,
        );
        final foreign = await seed(
          serverId: 1,
          cachedForUserId: userB,
          createdByUserId: userA,
          isActive: true,
        );
        loginAs(userA);
        adapter.responder = (_) async => jsonResponse({'isActive': false});

        final owned = await repository.getTemplateById(1);
        final updated = await repository.toggleActive(owned!);

        expect(updated!.isActive, isFalse);
        expect(
          (await isar.workoutTemplates.get(foreign.localId))!.isActive,
          isTrue,
        );
      },
    );

    test('a stale toggle ack cannot overwrite a foreign-owned row', () async {
      final bRow = await seed(
        serverId: 1,
        cachedForUserId: userB,
        createdByUserId: userB,
        isActive: true,
      );
      loginAs(userA);
      adapter.responder = (_) async => jsonResponse({'isActive': false});

      // A has no owned row for serverId 1 - the ack must create nothing.
      final t = WorkoutTemplate(
        serverId: 1,
        name: 'x',
        exercisesJson: '[]',
        recurrencePattern: 'daily',
        createdAt: DateTime(2026, 1, 1),
      );
      await repository.toggleActive(t);

      expect(await isar.workoutTemplates.count(), 1);
      expect((await isar.workoutTemplates.get(bRow.localId))!.isActive, isTrue);
    });

    test(
      'incrementUsageCount applies {usageCount} + lastUsedAt to owned row',
      () async {
        await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
          usageCount: 2,
        );
        loginAs(userA);
        adapter.responder = (_) async => jsonResponse({'usageCount': 3});

        final owned = await repository.getTemplateById(1);
        await repository.incrementUsageCount(owned!);

        final stored =
            await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst();
        expect(stored!.usageCount, 3);
        expect(stored.lastUsedAt, isNotNull);
      },
    );

    test(
      'rateTemplate applies {rating, ratingCount} to the owned row',
      () async {
        await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userB,
          isPublic: true,
          rating: null,
          ratingCount: 0,
        );
        loginAs(userA);
        adapter.responder =
            (_) async => jsonResponse({'rating': 4.5, 'ratingCount': 1});

        await repository.rateTemplate(1, 4.5);

        final stored =
            await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst();
        expect(stored!.rating, 4.5);
        expect(stored.ratingCount, 1);
      },
    );

    test('delete removes only the captured user\'s owned row', () async {
      final a = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
      );
      final b = await seed(
        serverId: 1,
        cachedForUserId: userB,
        createdByUserId: userA,
      );
      final legacy = await seed(serverId: 2, cachedForUserId: null);
      loginAs(userA);
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      final ownedA = await repository.getTemplateById(1);
      expect(await repository.deleteTemplate(ownedA!), isTrue);

      expect(await isar.workoutTemplates.get(a.localId), isNull);
      expect(await isar.workoutTemplates.get(b.localId), isNotNull);
      expect(await isar.workoutTemplates.get(legacy.localId), isNotNull);
    });
  });

  // ============ 5b. Offline mutations all fail explicitly ============
  //
  // Phase 2 contract: reads are offline-first, every mutation is online-only.
  // An offline attempt throws, makes zero HTTP requests, performs zero Isar
  // writes, allocates no local id, and never returns a success object.

  group('offline mutations fail explicitly and change nothing', () {
    setUp(() => when(mockConnectivity.isOnline).thenReturn(false));

    test('createTemplate', () async {
      loginAs(userA);
      final before = await isar.workoutTemplates.count();

      await expectLater(
        () => repository.createTemplate(
          name: 'x',
          exercisesJson: '[]',
          recurrencePattern: 'daily',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('offline'),
          ),
        ),
      );

      expect(adapter.capturedRequests, isEmpty);
      expect(await isar.workoutTemplates.count(), before);
    });

    test('updateTemplate', () async {
      final row = await seed(
        serverId: 7,
        cachedForUserId: userA,
        createdByUserId: userA,
        name: 'before',
      );
      loginAs(userA);

      await expectLater(
        () => repository.updateTemplate(row..name = 'after'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('offline'),
          ),
        ),
      );

      expect(adapter.capturedRequests, isEmpty);
      expect((await isar.workoutTemplates.get(row.localId))!.name, 'before');
    });

    test('toggleActive', () async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
        isActive: true,
      );
      loginAs(userA);

      await expectLater(
        () => repository.toggleActive(row),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('offline'),
          ),
        ),
      );

      expect(adapter.capturedRequests, isEmpty);
      expect((await isar.workoutTemplates.get(row.localId))!.isActive, isTrue);
    });

    test('deleteTemplate', () async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
      );
      loginAs(userA);

      await expectLater(
        () => repository.deleteTemplate(row),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('offline'),
          ),
        ),
      );

      expect(adapter.capturedRequests, isEmpty);
      expect(await isar.workoutTemplates.get(row.localId), isNotNull);
    });

    test('incrementUsageCount', () async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
        usageCount: 3,
      );
      loginAs(userA);

      await expectLater(
        () => repository.incrementUsageCount(row),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('offline'),
          ),
        ),
      );

      expect(adapter.capturedRequests, isEmpty);
      expect((await isar.workoutTemplates.get(row.localId))!.usageCount, 3);
    });

    test('rateTemplate', () async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userB,
        isPublic: true,
        rating: 2.0,
        ratingCount: 1,
      );
      loginAs(userA);

      await expectLater(
        () => repository.rateTemplate(1, 4),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('offline'),
          ),
        ),
      );

      expect(adapter.capturedRequests, isEmpty);
      final stored = await isar.workoutTemplates.get(row.localId);
      expect(stored!.rating, 2.0);
      expect(stored.ratingCount, 1);
    });

    test('even online, an unsynced target (serverId == null) fails without '
        'HTTP or a write', () async {
      // The shape a row written by the previous implementation deserializes
      // into: no serverId. It is invisible to reads; a mutation against one
      // still fails fast rather than inventing a sync path.
      final legacy = await seed(cachedForUserId: null, createdByUserId: null);
      loginAs(userA);
      when(mockConnectivity.isOnline).thenReturn(true);

      await expectLater(
        () => repository.updateTemplate(legacy),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => repository.toggleActive(legacy),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => repository.deleteTemplate(legacy),
        throwsA(isA<Exception>()),
      );
      expect(adapter.capturedRequests, isEmpty);
      expect(await isar.workoutTemplates.count(), 1);
    });
  });

  // ============ 6. Lifecycle exceptions are silent expected outcomes ========

  group('lifecycle exceptions', () {
    test(
      'toggleActive swallows a stale-at-dispatch SessionStaleException',
      () async {
        final row = await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
          isActive: true,
        );
        loginAs(userA);
        apiService.beforeDispatchEpochCheckForTesting = () async => logout();

        final result = await repository.toggleActive(row);

        expect(result, isNull);
        expect(
          (await isar.workoutTemplates.get(row.localId))!.isActive,
          isTrue,
        );
      },
    );

    test(
      'createTemplate converts a stale dispatch to the unauthenticated outcome',
      () async {
        loginAs(userA);
        apiService.beforeDispatchEpochCheckForTesting = () async => logout();

        await expectLater(
          () => repository.createTemplate(
            name: 'x',
            exercisesJson: '[]',
            recurrencePattern: 'daily',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('No authenticated user'),
            ),
          ),
        );
        expect(await isar.workoutTemplates.count(), 0);
      },
    );

    test(
      'deleteTemplate swallows a mid-flight generation cancellation',
      () async {
        final row = await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
        );
        loginAs(userA);
        adapter.responder = (_) => Completer<ResponseBody>().future;

        final dispatched = adapter.nextDispatch();
        final future = repository.deleteTemplate(row);
        await dispatched;
        sessionCoordinator.cancelCurrentGeneration();

        expect(await future, isFalse);
        expect(await isar.workoutTemplates.get(row.localId), isNotNull);
      },
    );

    test('createTemplate still fails the caller when the session ends after '
        'the cache write commits', () async {
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse(dto(id: 5, createdByUserId: userA));
      // Session ends in the gap between the writeTxn returning and the
      // repository reporting success - the post-txn checkpoint must reject.
      repository.afterWriteTxnForTesting = () async => logout();

      await expectLater(
        () => repository.createTemplate(
          name: 'x',
          exercisesJson: '[]',
          recurrencePattern: 'daily',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No authenticated user'),
          ),
        ),
      );
    });

    test('createTemplate rejects - without caching - if the session ends '
        'between the HTTP response and the cache write', () async {
      loginAs(userA);
      final resp = Completer<ResponseBody>();
      adapter.responder = (_) => resp.future;
      var hookFired = false;
      repository.afterForegroundHttpResponseForTesting = () async {
        hookFired = true;
      };

      final dispatched = adapter.nextDispatch();
      final future = repository.createTemplate(
        name: 'x',
        exercisesJson: '[]',
        recurrencePattern: 'daily',
      );
      await dispatched;
      logout();
      resp.complete(jsonResponse(dto(id: 1, createdByUserId: userA)));

      await expectLater(
        future,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No authenticated user'),
          ),
        ),
      );
      // The post-HTTP checkpoint rejected before the foreground hook and the
      // cache write were ever reached.
      expect(hookFired, isFalse);
      expect(await isar.workoutTemplates.count(), 0);
    });

    test('deleteTemplate rethrows a non-lifecycle server error and keeps the '
        'local row', () async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
      );
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse({'error': 'boom'}, statusCode: 500);

      await expectLater(
        () => repository.deleteTemplate(row),
        throwsA(anything),
      );
      expect(await isar.workoutTemplates.get(row.localId), isNotNull);
    });
  });

  // ============ 7. Local-only metadata ============

  group('cachedForUserId / server-owned fields are local-only', () {
    test('fromJson never reads cachedForUserId and puts id in serverId', () {
      final parsed = WorkoutTemplateJson.fromJson({
        ...dto(id: 7, createdByUserId: 99),
        'cachedForUserId': 999,
      });

      expect(parsed.cachedForUserId, isNull);
      expect(parsed.serverId, 7);
      expect(parsed.localId, Isar.autoIncrement);
      expect(parsed.createdByUserId, 99);
    });

    test('toRequestJson only carries client-owned fields', () {
      final t = WorkoutTemplate(
        serverId: 7,
        cachedForUserId: 12345,
        createdByUserId: 5,
        name: 'w',
        exercisesJson: '[]',
        recurrencePattern: 'weekly',
        daysOfWeek: '1,3',
        isActive: false,
        isPublic: true,
        usageCount: 9,
        rating: 4.0,
        ratingCount: 3,
        createdAt: DateTime(2026, 1, 1),
      );

      final json = t.toRequestJson();

      expect(json.keys.toSet(), {
        'name',
        'description',
        'exercisesJson',
        'recurrencePattern',
        'daysOfWeek',
        'intervalDays',
        'estimatedDuration',
        'category',
        'isActive',
        'isPublic',
      });
    });
  });

  // ============ 8. Schema upgrade compatibility ============

  group('schema upgrade: legacy rows without cachedForUserId', () {
    test('a null-owner row round-trips as null, is invisible offline, and is '
        'restamped by a valid online response', () async {
      await seed(serverId: 1, cachedForUserId: userA, createdByUserId: userA);
      await isar.writeTxn(() async {
        final legacy =
            await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst();
        legacy!.cachedForUserId = null;
        await isar.workoutTemplates.put(legacy);
      });

      await isar.close();
      isar = await Isar.open(
        [WorkoutTemplateSchema],
        directory: tempDir.path,
        inspector: false,
      );
      localDb.setTestDatabase(isar);

      final reopened =
          await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst();
      expect(reopened!.cachedForUserId, isNull);

      when(mockConnectivity.isOnline).thenReturn(false);
      loginAs(userA);
      expect(await repository.getTemplates(), isEmpty);

      when(mockConnectivity.isOnline).thenReturn(true);
      adapter.responder =
          (_) async => jsonResponse([dto(id: 1, createdByUserId: userA)]);
      await repository.getTemplates();
      await scheduledBackgroundSyncs.single;

      final restamped =
          await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst();
      expect(restamped!.cachedForUserId, userA);

      when(mockConnectivity.isOnline).thenReturn(false);
      expect((await repository.getTemplates()).map((t) => t.serverId), [1]);
    });
  });

  // ============ 9. Scheduling ============

  group('scheduling', () {
    test('getTemplatesForDate returns only this user\'s active scheduled '
        'templates', () async {
      when(mockConnectivity.isOnline).thenReturn(false);
      await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
        isActive: true,
        name: 'daily active',
      );
      await seed(
        serverId: 2,
        cachedForUserId: userA,
        createdByUserId: userA,
        isActive: false,
        name: 'daily inactive',
      );
      await seed(
        serverId: 3,
        cachedForUserId: userB,
        createdByUserId: userB,
        isActive: true,
        name: 'B daily',
      );
      loginAs(userA);

      final due = await repository.getTemplatesForDate(DateTime(2026, 6, 1));
      expect(due.map((t) => t.serverId), [1]);
    });
  });

  // ============ 10. Query encoding ============

  group('community query parameters are properly encoded', () {
    test('a category with spaces, &, /, + and Unicode reaches the server '
        'verbatim', () async {
      loginAs(userA);
      const raw = 'Arms & Legs / Full+Body — 힘';
      adapter.responder = (_) async => jsonResponse(<dynamic>[]);

      await repository.getCommunityTemplates(category: raw, limit: 25);
      await scheduledBackgroundSyncs.single;

      final req = adapter.capturedRequests.single;
      expect(req.uri.queryParameters['category'], raw);
      expect(req.uri.queryParameters['limit'], '25');
      // The raw value must not appear unencoded in the query string.
      expect(req.uri.query, isNot(contains(' ')));
      expect(req.uri.query, contains('category='));
    });
  });

  // ============ 11. Delete failure preserves the cache ============

  group('deleteTemplate failure modes', () {
    Future<void> expectDeleteThrowsAndKeeps(int statusCode) async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
      );
      loginAs(userA);
      adapter.responder =
          (_) async => jsonResponse({'error': 'no'}, statusCode: statusCode);

      await expectLater(
        () => repository.deleteTemplate(row),
        throwsA(anything),
      );
      expect(await isar.workoutTemplates.get(row.localId), isNotNull);
    }

    test('403 leaves the cache intact', () => expectDeleteThrowsAndKeeps(403));
    test('404 leaves the cache intact', () => expectDeleteThrowsAndKeeps(404));
    test('500 leaves the cache intact', () => expectDeleteThrowsAndKeeps(500));

    test('a transport failure leaves the cache intact', () async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
      );
      loginAs(userA);
      adapter.responder = (_) async => throw const SocketExceptionStub();

      await expectLater(
        () => repository.deleteTemplate(row),
        throwsA(anything),
      );
      expect(await isar.workoutTemplates.get(row.localId), isNotNull);
    });

    test(
      'a stale-at-dispatch outcome is a silent false and never deletes',
      () async {
        final row = await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
        );
        loginAs(userA);
        apiService.beforeDispatchEpochCheckForTesting = () async => logout();

        expect(await repository.deleteTemplate(row), isFalse);
        expect(await isar.workoutTemplates.get(row.localId), isNotNull);
      },
    );

    test('a mid-flight generation cancellation is a silent false and never '
        'deletes', () async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
      );
      loginAs(userA);
      adapter.responder = (_) => Completer<ResponseBody>().future;

      final dispatched = adapter.nextDispatch();
      final future = repository.deleteTemplate(row);
      await dispatched;
      sessionCoordinator.cancelCurrentGeneration();

      expect(await future, isFalse);
      expect(await isar.workoutTemplates.get(row.localId), isNotNull);
    });

    test('only a successful 204 deletes the owned row', () async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
      );
      loginAs(userA);
      adapter.responder = (_) async => ResponseBody.fromString('', 204);

      expect(await repository.deleteTemplate(row), isTrue);
      expect(await isar.workoutTemplates.get(row.localId), isNull);
    });

    test(
      'a 2xx response that is not 200/204 does not delete locally',
      () async {
        final row = await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
        );
        loginAs(userA);
        adapter.responder = (_) async => ResponseBody.fromString('', 202);

        expect(await repository.deleteTemplate(row), isFalse);
        expect(await isar.workoutTemplates.get(row.localId), isNotNull);
      },
    );
  });

  // ============ 12. Per-serverId write ordering ============
  //
  // A slower stale write can never overwrite a newer one for the same
  // serverId, in either operation order.

  group('refresh vs. mutation ordering', () {
    /// Routes the fake transport by method/path for the ordering scenarios.
    void routeOrdering({
      required Completer<ResponseBody> listResponse,
      Completer<void>? listDispatched,
      Completer<ResponseBody>? putResponse,
      Completer<void>? putDispatched,
      String detailName = 'via-mutation',
      int statusForDetail = 200,
      int statusForPut = 204,
    }) {
      adapter.responder = (opts) async {
        if (opts.method == 'GET' && opts.path == 'workouttemplates') {
          if (listDispatched != null && !listDispatched.isCompleted) {
            listDispatched.complete();
          }
          return listResponse.future;
        }
        if (opts.method == 'PUT') {
          if (putDispatched != null && !putDispatched.isCompleted) {
            putDispatched.complete();
          }
          return putResponse?.future ??
              Future.value(ResponseBody.fromString('', statusForPut));
        }
        if (opts.method == 'DELETE') {
          return ResponseBody.fromString('', 204);
        }
        // GET workouttemplates/{id} - the mutation's re-fetch.
        return jsonResponse(
          dto(id: 1, createdByUserId: userA, name: detailName),
          statusCode: statusForDetail,
        );
      };
    }

    test(
      'a stale refresh completing last cannot overwrite a newer update',
      () async {
        await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
          name: 'v0',
        );
        loginAs(userA);
        final listResponse = Completer<ResponseBody>();
        final listDispatched = Completer<void>();
        routeOrdering(
          listResponse: listResponse,
          listDispatched: listDispatched,
          detailName: 'v1-updated',
        );

        await repository.getTemplates(); // schedules the refresh (ticket 1)
        await listDispatched.future; // refresh GET is now in flight
        await repository.updateTemplate(
          WorkoutTemplate(
            serverId: 1,
            name: 'v1',
            exercisesJson: '[]',
            recurrencePattern: 'daily',
            createdAt: DateTime(2026, 1, 1),
          ),
        ); // ticket 2, applied

        listResponse.complete(
          jsonResponse([dto(id: 1, createdByUserId: userA, name: 'v0-stale')]),
        );
        await scheduledBackgroundSyncs.single;

        expect(
          (await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst())!
              .name,
          'v1-updated',
        );
      },
    );

    test(
      'a stale refresh completing last cannot resurrect a newer delete',
      () async {
        final row = await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
        );
        loginAs(userA);
        final listResponse = Completer<ResponseBody>();
        final listDispatched = Completer<void>();
        routeOrdering(
          listResponse: listResponse,
          listDispatched: listDispatched,
        );

        await repository.getTemplates(); // refresh ticket 1
        await listDispatched.future;
        expect(await repository.deleteTemplate(row), isTrue); // ticket 2

        listResponse.complete(
          jsonResponse([dto(id: 1, createdByUserId: userA, name: 'back')]),
        );
        await scheduledBackgroundSyncs.single;

        expect(
          await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst(),
          isNull,
        );
      },
    );

    test(
      'an in-flight update completing last cannot resurrect a newer delete',
      () async {
        final row = await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
        );
        loginAs(userA);
        final putResponse = Completer<ResponseBody>();
        final putDispatched = Completer<void>();
        routeOrdering(
          listResponse: Completer<ResponseBody>(),
          putResponse: putResponse,
          putDispatched: putDispatched,
          detailName: 'resurrected',
        );

        when(mockConnectivity.isOnline).thenReturn(true);
        final updateFuture = repository.updateTemplate(
          WorkoutTemplate(
            serverId: 1,
            name: 'v1',
            exercisesJson: '[]',
            recurrencePattern: 'daily',
            createdAt: DateTime(2026, 1, 1),
          ),
        ); // ticket 1, PUT held
        await putDispatched.future;
        expect(await repository.deleteTemplate(row), isTrue); // ticket 2

        putResponse.complete(ResponseBody.fromString('', 204));
        await updateFuture.then((_) {}, onError: (_) {});

        expect(
          await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst(),
          isNull,
        );
      },
    );

    test(
      'the genuinely newer of two updates wins regardless of ack order',
      () async {
        await seed(
          serverId: 1,
          cachedForUserId: userA,
          createdByUserId: userA,
          name: 'v0',
        );
        loginAs(userA);
        final put1 = Completer<ResponseBody>();
        final put1Dispatched = Completer<void>();
        var detailName = 'from-update-2';
        adapter.responder = (opts) async {
          if (opts.method == 'PUT') {
            if (!put1Dispatched.isCompleted) {
              put1Dispatched.complete();
              return put1.future;
            }
            return ResponseBody.fromString('', 204);
          }
          return jsonResponse(
            dto(id: 1, createdByUserId: userA, name: detailName),
          );
        };

        final update1 = repository.updateTemplate(
          WorkoutTemplate(
            serverId: 1,
            name: 'a',
            exercisesJson: '[]',
            recurrencePattern: 'daily',
            createdAt: DateTime(2026, 1, 1),
          ),
        ); // ticket 1, PUT held
        await put1Dispatched.future;

        await repository.updateTemplate(
          WorkoutTemplate(
            serverId: 1,
            name: 'b',
            exercisesJson: '[]',
            recurrencePattern: 'daily',
            createdAt: DateTime(2026, 1, 1),
          ),
        ); // ticket 2 -> applies name 'from-update-2'

        detailName = 'from-update-1-stale';
        put1.complete(ResponseBody.fromString('', 204));
        await update1;

        expect(
          (await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst())!
              .name,
          'from-update-2',
        );
      },
    );

    test('a delete after a completed update stands (server 404 on the stale '
        'update path)', () async {
      final row = await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
      );
      loginAs(userA);
      // Delete first, then an update whose PUT the server 404s (row gone).
      adapter.responder = (opts) async {
        if (opts.method == 'DELETE') return ResponseBody.fromString('', 204);
        return jsonResponse({'error': 'gone'}, statusCode: 404);
      };

      expect(await repository.deleteTemplate(row), isTrue);
      await expectLater(
        () => repository.updateTemplate(
          WorkoutTemplate(
            serverId: 1,
            name: 'late',
            exercisesJson: '[]',
            recurrencePattern: 'daily',
            createdAt: DateTime(2026, 1, 1),
          ),
        ),
        throwsA(anything),
      );

      expect(
        await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst(),
        isNull,
      );
    });

    test('documents the model boundary: a refresh that STARTS after a mutation '
        'but observes a pre-mutation snapshot and completes last lands the '
        '(server-authoritative) refresh value', () async {
      await seed(
        serverId: 1,
        cachedForUserId: userA,
        createdByUserId: userA,
        name: 'v0',
      );
      loginAs(userA);

      // Mutation goes first (ticket 1), completes fully - caches 'toggled'.
      adapter.responder = (opts) async {
        if (opts.method == 'PATCH') return jsonResponse({'isActive': false});
        return jsonResponse(dto(id: 1, createdByUserId: userA, name: 'v0'));
      };
      final owned = await repository.getTemplateById(1);
      await repository.toggleActive(owned!);
      expect(
        (await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst())!
            .isActive,
        isFalse,
      );

      // Now a refresh (higher ticket) whose server snapshot predates the
      // toggle. The write clock orders by operation-start, not server
      // version, so this later-ticket refresh is NOT gated - it lands the
      // server's (slightly stale, still authoritative) value. This is the
      // explicit conflict model: content is server-authoritative and the
      // next refresh converges.
      adapter.responder =
          (_) async => jsonResponse([
            dto(id: 1, createdByUserId: userA, name: 'v0', isActive: true),
          ]);
      await repository.getTemplates();
      await scheduledBackgroundSyncs.last;

      expect(
        (await isar.workoutTemplates.filter().serverIdEqualTo(1).findFirst())!
            .isActive,
        isTrue,
        reason: 'server-authoritative: the refresh value wins by design',
      );
    });
  });
}

/// Stand-in for a transport-layer failure the fake adapter can throw.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketExceptionStub';
}

/// A deterministic fake Dio transport - mirrors the fake adapter in
/// `shared_workout_repository_session_ownership_test.dart`.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> capturedRequests = [];

  Future<ResponseBody> Function(RequestOptions options)? responder;

  Completer<void>? _dispatchSignal;

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
