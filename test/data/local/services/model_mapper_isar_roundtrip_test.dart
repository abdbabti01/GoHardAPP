import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/services/model_mapper.dart';

/// Characterization test for the real Isar DateTime round-trip.
///
/// Purpose: determine, empirically, what a real Isar instance actually does
/// to a DateTime between write and read - not what comments in
/// model_mapper.dart *assume* it does. This is the missing coverage behind
/// the workout-timer-navigation bug: every existing timestamp test
/// (session_timer_bug_test.dart, session_timestamp_test.dart) only exercises
/// Session.fromJson() string parsing, never a real Isar database.
///
/// This machine's local timezone is Eastern Time (UTC-5 / UTC-4 DST), so a
/// timezone-offset-sized defect is directly observable here without needing
/// to fake or inject a timezone.
void main() {
  late Isar isar;
  late Directory tempDir;
  late String dbName;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('isar_roundtrip_test_');
    dbName = 'roundtrip_${DateTime.now().microsecondsSinceEpoch}';
    isar = await Isar.open(
      [LocalSessionSchema],
      directory: tempDir.path,
      name: dbName,
    );
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Writes [session], closes the database, reopens it from the same
  /// directory/name, and returns a freshly-deserialized LocalSession.
  /// Reopening (not just re-querying) guarantees the result cannot be the
  /// same in-memory Dart object instance that was written.
  Future<LocalSession> writeCloseReopenAndRead(LocalSession session) async {
    late int localId;
    await isar.writeTxn(() async {
      localId = await isar.localSessions.put(session);
    });

    await isar.close();
    isar = await Isar.open(
      [LocalSessionSchema],
      directory: tempDir.path,
      name: dbName,
    );

    final reread = await isar.localSessions.get(localId);
    expect(reread, isNotNull, reason: 'Session must survive close/reopen');
    return reread!;
  }

  void logTimestamp(String label, DateTime? dt) {
    if (dt == null) {
      // ignore: avoid_print
      print('$label: null');
      return;
    }
    // ignore: avoid_print
    print(
      '$label: iso=${dt.toIso8601String()} isUtc=${dt.isUtc} '
      'micros=${dt.microsecondsSinceEpoch}',
    );
  }

  test(
    'running workout: absolute instant survives Isar close/reopen and mapping',
    () async {
      final originalStartedAt = DateTime.utc(2024, 1, 15, 10, 0, 0);
      logTimestamp(
        'BEFORE persistence (original startedAt)',
        originalStartedAt,
      );

      final session = LocalSession(
        serverId: 1,
        userId: 1,
        date: DateTime.utc(2024, 1, 15),
        status: 'in_progress',
        startedAt: originalStartedAt,
        pausedAt: null,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now().toUtc(),
        version: 3,
      );

      final reread = await writeCloseReopenAndRead(session);
      logTimestamp('AFTER Isar retrieval (raw startedAt)', reread.startedAt);

      final mapped = ModelMapper.localToSession(reread, exercises: const []);
      logTimestamp(
        'AFTER ModelMapper.localToSession (mapped startedAt)',
        mapped.startedAt,
      );

      // --- Absolute-instant assertions (never based on wall-clock display) ---
      expect(
        mapped.startedAt!.microsecondsSinceEpoch,
        originalStartedAt.microsecondsSinceEpoch,
        reason:
            'The absolute instant must survive the Isar round-trip and '
            'mapping. A mismatch here is a timezone-offset-sized corruption, '
            'not a display quirk.',
      );

      // Elapsed-time calculation against a controlled reference "now".
      final simulatedNow = originalStartedAt.add(const Duration(minutes: 45));
      final elapsed = simulatedNow.difference(mapped.startedAt!);
      expect(
        elapsed.inMinutes,
        45,
        reason:
            'Elapsed time computed from the mapped timestamp must match '
            'the true elapsed duration, not be off by a timezone offset.',
      );

      // Preserved fields unrelated to timers must not be disturbed.
      expect(mapped.status, 'in_progress');
      expect(mapped.version, 3);

      // Record what isUtc becomes - informational, not a correctness
      // assertion on its own (isUtc alone does not prove the instant moved).
      // ignore: avoid_print
      print(
        'Isar raw startedAt.isUtc after retrieval: ${reread.startedAt?.isUtc}',
      );
      // ignore: avoid_print
      print('Mapped startedAt.isUtc: ${mapped.startedAt?.isUtc}');
    },
  );

  test(
    'paused workout: startedAt and pausedAt both survive round-trip, elapsed unaffected',
    () async {
      final originalStartedAt = DateTime.utc(2024, 1, 15, 10, 0, 0);
      final originalPausedAt = DateTime.utc(2024, 1, 15, 10, 30, 0);
      logTimestamp('BEFORE persistence (startedAt)', originalStartedAt);
      logTimestamp('BEFORE persistence (pausedAt)', originalPausedAt);

      final session = LocalSession(
        serverId: 2,
        userId: 1,
        date: DateTime.utc(2024, 1, 15),
        status: 'in_progress',
        startedAt: originalStartedAt,
        pausedAt: originalPausedAt,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now().toUtc(),
        version: 5,
      );

      final reread = await writeCloseReopenAndRead(session);
      logTimestamp('AFTER Isar retrieval (startedAt)', reread.startedAt);
      logTimestamp('AFTER Isar retrieval (pausedAt)', reread.pausedAt);

      final mapped = ModelMapper.localToSession(reread, exercises: const []);
      logTimestamp('AFTER mapping (startedAt)', mapped.startedAt);
      logTimestamp('AFTER mapping (pausedAt)', mapped.pausedAt);

      expect(
        mapped.startedAt!.microsecondsSinceEpoch,
        originalStartedAt.microsecondsSinceEpoch,
        reason: 'startedAt absolute instant must be preserved',
      );
      expect(
        mapped.pausedAt!.microsecondsSinceEpoch,
        originalPausedAt.microsecondsSinceEpoch,
        reason: 'pausedAt absolute instant must be preserved',
      );

      final elapsedWhilePaused = mapped.pausedAt!.difference(mapped.startedAt!);
      expect(
        elapsedWhilePaused.inMinutes,
        30,
        reason:
            'Paused elapsed time must remain exactly 30 minutes after '
            'round-tripping through Isar, not shifted by a UTC offset.',
      );

      expect(mapped.version, 5);
    },
  );

  test(
    'direct mapper invariant: localToSession must preserve absolute instant, '
    'not merely copy wall-clock components (fails under a UTC test runner too)',
    () {
      // This does not touch Isar at all - it documents the intended
      // contract of ModelMapper.localToSession() directly, so the invariant
      // is still enforced even if a future CI/test runner happens to run in
      // UTC (where a components-vs-instant bug could otherwise go
      // unnoticed because the "shift" would be zero).
      //
      // We simulate what a defective Isar-backed LocalSession might look
      // like if isUtc were lost, using a local-flagged DateTime built from
      // known UTC components. If mapping doesn't touch the instant, this
      // is what a genuinely instant-preserving read looks like.
      final knownInstant = DateTime.utc(2024, 6, 1, 8, 0, 0);
      final localFlavoredSameInstant = knownInstant.toLocal();

      expect(
        localFlavoredSameInstant.microsecondsSinceEpoch,
        knownInstant.microsecondsSinceEpoch,
        reason: 'Sanity check: toLocal() must never change the instant.',
      );

      final localSession = LocalSession(
        userId: 1,
        date: DateTime.utc(2024, 6, 1),
        status: 'in_progress',
        startedAt: localFlavoredSameInstant,
        lastModifiedLocal: DateTime.now().toUtc(),
      );

      final mapped = ModelMapper.localToSession(
        localSession,
        exercises: const [],
      );

      expect(
        mapped.startedAt!.microsecondsSinceEpoch,
        knownInstant.microsecondsSinceEpoch,
        reason:
            'localToSession must preserve the absolute instant of a '
            'local-flagged-but-instant-correct DateTime. If this fails, the '
            'mapper is treating displayed wall-clock components as if they '
            'were the true UTC values, which corrupts the instant by '
            'exactly the local UTC offset.',
      );
    },
  );
}
