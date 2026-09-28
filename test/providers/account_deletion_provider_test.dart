import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/lifted_weight_contract_migration.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_program.dart';
import 'package:go_hard_app/data/local/models/local_program_workout.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/local_database_service.dart';
import 'package:go_hard_app/data/repositories/account_repository.dart';
import 'package:go_hard_app/providers/account_deletion_provider.dart';
import 'package:go_hard_app/providers/auth_provider.dart';

@GenerateMocks([AccountRepository, AuthProvider, LocalDatabaseService])
import 'account_deletion_provider_test.mocks.dart';

void main() {
  late MockAccountRepository mockAccountRepository;
  late MockAuthProvider mockAuthProvider;
  late MockLocalDatabaseService mockLocalDb;
  late AccountDeletionProvider provider;

  setUp(() {
    mockAccountRepository = MockAccountRepository();
    mockAuthProvider = MockAuthProvider();
    mockLocalDb = MockLocalDatabaseService();
    when(mockAuthProvider.logout()).thenAnswer((_) async {});
    when(mockLocalDb.clearAll()).thenAnswer((_) async {});
    provider = AccountDeletionProvider(
      mockAccountRepository,
      mockAuthProvider,
      mockLocalDb,
    );
  });

  test(
    'wrong password: reports the error, never logs out or clears data',
    () async {
      when(
        mockAccountRepository.deleteAccount(any),
      ).thenAnswer((_) async => AccountDeletionOutcome.invalidPassword);

      final result = await provider.deleteAccount('wrong');

      expect(result, isFalse);
      expect(provider.errorMessage, 'Incorrect password');
      verifyNever(mockAuthProvider.logout());
      verifyNever(mockLocalDb.clearAll());
    },
  );

  test('server/network failure: reports a generic error, never logs out or '
      'clears data - the account may still exist', () async {
    when(mockAccountRepository.deleteAccount(any)).thenThrow(Exception('boom'));

    final result = await provider.deleteAccount('correct');

    expect(result, isFalse);
    expect(provider.errorMessage, isNotNull);
    verifyNever(mockAuthProvider.logout());
    verifyNever(mockLocalDb.clearAll());
  });

  test('success: logs out THEN clears local data, in that order', () async {
    when(
      mockAccountRepository.deleteAccount(any),
    ).thenAnswer((_) async => AccountDeletionOutcome.success);
    final calls = <String>[];
    when(mockAuthProvider.logout()).thenAnswer((_) async {
      calls.add('logout');
    });
    when(mockLocalDb.clearAll()).thenAnswer((_) async {
      calls.add('clearAll');
    });

    final result = await provider.deleteAccount('correct');

    expect(result, isTrue);
    expect(provider.errorMessage, isNull);
    expect(calls, [
      'logout',
      'clearAll',
    ], reason: 'local data must never be cleared before the session is ended');
  });

  test('success even if the local logout/cleanup steps individually throw - '
      'the server deletion already committed', () async {
    when(
      mockAccountRepository.deleteAccount(any),
    ).thenAnswer((_) async => AccountDeletionOutcome.success);
    when(mockAuthProvider.logout()).thenThrow(Exception('logout blew up'));
    when(mockLocalDb.clearAll()).thenThrow(Exception('isar blew up'));

    final result = await provider.deleteAccount('correct');

    expect(result, isTrue);
  });

  test('double-submit protection: a second call while one is in flight is '
      'ignored, only one network call is made', () async {
    final gate = Completer<AccountDeletionOutcome>();
    when(
      mockAccountRepository.deleteAccount(any),
    ).thenAnswer((_) => gate.future);

    final first = provider.deleteAccount('correct');
    expect(provider.isDeleting, isTrue);
    final second = await provider.deleteAccount('correct');

    expect(second, isFalse, reason: 'the second call must be a no-op');
    gate.complete(AccountDeletionOutcome.success);
    await first;

    verify(mockAccountRepository.deleteAccount(any)).called(1);
  });

  test('success: after clearAll, a PENDING lifted-weight migration has its '
      'cutoffs re-tightened to the emptied Isar (0), so rows created with '
      'restarted ids are never purged as legacy', () async {
    await Isar.initializeIsarCore(download: true);
    final dir = await Directory.systemTemp.createTemp('account_delete_lw_');
    final isar = await Isar.open(
      [
        LocalSessionSchema,
        LocalExerciseSchema,
        LocalExerciseSetSchema,
        LocalProgramSchema,
        LocalProgramWorkoutSchema,
      ],
      directory: dir.path,
      inspector: false,
    );
    addTearDown(() async {
      if (isar.isOpen) await isar.close();
      await dir.delete(recursive: true);
    });
    final now = DateTime.utc(2026, 9, 1);
    await isar.writeTxn(
      () => isar.localSessions.putAll([
        for (var i = 0; i < 3; i++)
          LocalSession(
            userId: 1,
            date: now,
            isSynced: false,
            syncStatus: 'pending_create',
            lastModifiedLocal: now,
          ),
      ]),
    );
    String? state;
    final migration = LiftedWeightContractMigration(
      database: () => isar,
      readState: () async => state,
      writeState: (json) async => state = json,
    );
    await migration.snapshotIfNeeded();
    expect((jsonDecode(state!)['cutoffs'] as Map)['sessions'], 3);

    when(
      mockAccountRepository.deleteAccount(any),
    ).thenAnswer((_) async => AccountDeletionOutcome.success);
    when(
      mockLocalDb.clearAll(),
    ).thenAnswer((_) => isar.writeTxn(() => isar.clear()));
    provider = AccountDeletionProvider(
      mockAccountRepository,
      mockAuthProvider,
      mockLocalDb,
      liftedWeightMigration: migration,
    );

    expect(await provider.deleteAccount('correct'), isTrue);

    expect(jsonDecode(state!), {
      'status': 'pending',
      'cutoffs': {
        'sessions': 0,
        'exercises': 0,
        'sets': 0,
        'programs': 0,
        'programWorkouts': 0,
      },
    });
  });
}
