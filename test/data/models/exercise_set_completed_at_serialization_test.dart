import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:go_hard_app/core/utils/datetime_helper.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/models/exercise.dart';
import 'package:go_hard_app/data/models/exercise_set.dart';
import 'package:go_hard_app/data/models/session.dart';

/// Deterministic proof that `ExerciseSet.completedAt` crosses the wire as an
/// absolute UTC instant (ISO-8601 with a `Z` suffix), never as an unzoned
/// local wall-clock string.
///
/// `completedAt` is an instant: the API's `PATCH /exercisesets/{id}/complete`
/// stamps it with `DateTime.UtcNow` and every API response serializes it with
/// a `Z` suffix (GoHardAPI `NullableUtcDateTimeConverter`). The gap this file
/// guards is the *outbound* encoding - `_$ExerciseSetToJson` used to emit
/// `completedAt?.toIso8601String()`, which for a **local-flagged** `DateTime`
/// (Isar hands every `DateTime` back with `isUtc == false`) produces a string
/// with NO `Z` and the device-local wall-clock digits.
///
/// Dart semantics this file pins (see the "pinned Dart runtime" group):
/// `DateTime.parse` of a string with an explicit numeric offset
/// (`...-04:00`) returns a value with `isUtc == true`, already normalised to
/// the equivalent UTC instant - Dart does NOT retain the original offset and
/// the result is NOT local-flagged. Only a suffix-less string parses
/// local-flagged.
///
/// Host-timezone independence: every input is a `DateTime.utc(...)` literal or
/// an explicit-offset `DateTime.parse(...)` (both `isUtc == true`, so their
/// broken-out fields are the UTC fields on every host), and assertions compare
/// exact expected UTC ISO strings / `millisecondsSinceEpoch`. Where a
/// **local-flagged** input is used (`utcInstant.toLocal()`, the Isar
/// round-trip), assertions are epoch-based so the real code's instant
/// preservation is proven on any host.
void main() {
  // A fixed instant: 2026-09-03 14:15:30.000 UTC.
  final utcInstant = DateTime.utc(2026, 9, 3, 14, 15, 30);
  const expectedIso = '2026-09-03T14:15:30.000Z';

  ExerciseSet setWith(DateTime? completedAt) => ExerciseSet(
    id: 5,
    exerciseId: 9,
    setNumber: 1,
    reps: 10,
    weight: 100,
    isCompleted: completedAt != null,
    completedAt: completedAt,
  );

  // ---------------------------------------------------------------------------
  // Pinned Dart runtime behaviour for DateTime.parse.
  //
  // The correction the rest of this file relies on: an explicit-offset parse is
  // NOT "local-flagged". It is UTC-flagged and already normalised. These
  // assertions document the behaviour of the pinned Dart SDK (3.7.2) so a
  // future SDK change that alters it is caught here rather than silently
  // shifting what the mutation tests below actually exercise.
  // ---------------------------------------------------------------------------
  group('pinned Dart runtime: DateTime.parse offset semantics', () {
    test('explicit negative offset -> isUtc == true, normalised to the UTC '
        'instant, no retained offset', () {
      final parsed = DateTime.parse('2026-09-03T10:15:30.000-04:00');

      expect(parsed.isUtc, isTrue, reason: 'pinned SDK 3.7.2 behaviour');
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 9, 3, 14, 15, 30).millisecondsSinceEpoch,
      );
      // The broken-out fields are the UTC fields (14:xx), not the pre-offset
      // digits (10:xx) - Dart applied and discarded the offset.
      expect(parsed.hour, 14);
      expect(parsed.toIso8601String(), '2026-09-03T14:15:30.000Z');

      // ...and it serialises through the helper to the same UTC instant.
      expect(DateTimeHelper.formatTimestampOrNull(parsed), expectedIso);
    });

    test('explicit positive offset -> same, normalised to the UTC instant', () {
      final parsed = DateTime.parse('2026-09-03T19:45:30.000+05:30');
      expect(parsed.isUtc, isTrue);
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 9, 3, 14, 15, 30).millisecondsSinceEpoch,
      );
      expect(DateTimeHelper.formatTimestampOrNull(parsed), expectedIso);
    });

    test('a suffix-less string is the only local-flagged parse', () {
      expect(DateTime.parse('2026-09-03T10:15:30.000').isUtc, isFalse);
      expect(DateTime.parse('2026-09-03T10:15:30.000Z').isUtc, isTrue);
      expect(DateTime.parse('2026-09-03T10:15:30.000-04:00').isUtc, isTrue);
    });
  });

  group('DateTimeHelper.formatTimestampOrNull (serialization helper)', () {
    test('1. null serializes as null', () {
      expect(DateTimeHelper.formatTimestampOrNull(null), isNull);
    });

    test('2. UTC input serializes with a Z suffix', () {
      final out = DateTimeHelper.formatTimestampOrNull(utcInstant)!;
      expect(out, expectedIso);
      expect(out.endsWith('Z'), isTrue);
    });

    test('3. positive-offset input converts to the equivalent UTC instant', () {
      // 2026-09-03T19:45:30+05:30 == 2026-09-03T14:15:30Z
      final input = DateTime.parse('2026-09-03T19:45:30.000+05:30');
      final out = DateTimeHelper.formatTimestampOrNull(input)!;
      expect(out, expectedIso);
      expect(
        DateTime.parse(out).millisecondsSinceEpoch,
        input.millisecondsSinceEpoch,
      );
    });

    test('4. negative-offset input converts to the equivalent UTC instant', () {
      // 2026-09-03T10:15:30-04:00 == 2026-09-03T14:15:30Z
      final input = DateTime.parse('2026-09-03T10:15:30.000-04:00');
      final out = DateTimeHelper.formatTimestampOrNull(input)!;
      expect(out, expectedIso);
      expect(
        DateTime.parse(out).millisecondsSinceEpoch,
        input.millisecondsSinceEpoch,
      );
    });

    test('5. fractional seconds remain semantically correct', () {
      final input = DateTime.parse('2026-09-03T10:15:30.123-04:00');
      final out = DateTimeHelper.formatTimestampOrNull(input)!;
      expect(out, '2026-09-03T14:15:30.123Z');
      expect(
        DateTime.parse(out).millisecondsSinceEpoch,
        input.millisecondsSinceEpoch,
      );
    });

    test('6. conversion preserves millisecondsSinceEpoch', () {
      for (final input in <DateTime>[
        utcInstant,
        DateTime.parse('2026-01-01T00:00:00.000+05:30'),
        DateTime.parse('2026-12-31T23:59:59.999-08:00'),
      ]) {
        final out = DateTimeHelper.formatTimestampOrNull(input)!;
        expect(
          DateTime.parse(out).millisecondsSinceEpoch,
          input.millisecondsSinceEpoch,
          reason: 'instant must be preserved for $input',
        );
      }
    });

    test('7. an explicit-offset input is emitted as a canonical UTC-Z string, '
        'not a value that keeps a numeric offset', () {
      // Pinned runtime: this input is already isUtc==true, instant 14:15:30Z.
      final input = DateTime.parse('2026-09-03T10:15:30.000-04:00');
      final out = DateTimeHelper.formatTimestampOrNull(input)!;
      expect(out, expectedIso);
      expect(out.endsWith('Z'), isTrue);
      expect(out.contains('+'), isFalse);
      expect(out.substring(11).contains('-'), isFalse); // no offset in the time
      expect(
        DateTime.parse(out).millisecondsSinceEpoch,
        input.millisecondsSinceEpoch,
      );
    });

    // NOTE on "convert vs. relabel". A mutation that reconstructs the instant
    // from broken-out fields - `DateTime.utc(v.year, v.month, ..., v.microsecond)`
    // - or that appends `Z` to `v.toIso8601String()` without converting, is
    // *equivalent* to the real code for every input constructible here without
    // depending on the host timezone: all such inputs are `isUtc == true`, so
    // their fields ARE the UTC fields and `v.toIso8601String()` already ends in
    // `Z`. The divergence appears only for a local-flagged `v`, and its size is
    // exactly the host UTC offset - so no host-independent test can kill those
    // two mutants, and they are classified EQUIVALENT-for-host-independent-input
    // rather than counted as killed.
    //
    // What the local-flagged-input tests below ("...converted, not relabelled",
    // the Isar round-trip group, repo tests 8a/9a) DO pin host-independently:
    //  - the `endsWith('Z')` assertions catch the actual regression this PR
    //    targets - a bare `.toIso8601String()` on a local-flagged value emits
    //    NO `Z` on any host;
    //  - the `millisecondsSinceEpoch` assertions confirm the real code
    //    preserves the instant (which `.toUtc()` does on any host by
    //    construction); on a non-UTC host they additionally happen to catch the
    //    relabel mutants, but that extra kill is not relied upon.
  });

  group('ExerciseSet.toJson() (real outbound serialization path)', () {
    test('null completedAt -> null on the wire', () {
      expect(setWith(null).toJson()['completedAt'], isNull);
    });

    test('UTC completedAt -> ISO-8601 UTC with Z', () {
      final json = setWith(utcInstant).toJson();
      expect(json['completedAt'], expectedIso);
      expect((json['completedAt'] as String).endsWith('Z'), isTrue);
    });

    test('local-flagged completedAt is converted, not relabelled', () {
      // A genuinely local-flagged DateTime (isUtc == false) for the same
      // instant as `utcInstant`. Its broken-out fields are the device-local
      // projection, so the assertions here are epoch-based: they prove the real
      // code preserves the instant on ANY host (a bare `.toIso8601String()`
      // would drop the `Z`; a relabel would shift the epoch by the host
      // offset).
      final local = utcInstant.toLocal();
      expect(local.isUtc, isFalse);
      final json = setWith(local).toJson();
      expect((json['completedAt'] as String).endsWith('Z'), isTrue);
      expect(
        DateTime.parse(json['completedAt'] as String).millisecondsSinceEpoch,
        utcInstant.millisecondsSinceEpoch,
      );
    });

    test('offset-bearing completedAt -> equivalent UTC instant', () {
      final json =
          setWith(DateTime.parse('2026-09-03T10:15:30.000-04:00')).toJson();
      expect(json['completedAt'], expectedIso);
    });

    test('every non-timestamp field matches the generated encoding', () {
      final set = ExerciseSet(
        id: 3,
        exerciseId: 7,
        setNumber: 2,
        reps: 8,
        weight: 92.5,
        duration: 30,
        isCompleted: true,
        completedAt: utcInstant,
        notes: 'n',
      );
      final json = set.toJson();
      expect(json['id'], 3);
      expect(json['exerciseId'], 7);
      expect(json['setNumber'], 2);
      expect(json['reps'], 8);
      expect(json['weight'], 92.5);
      expect(json['duration'], 30);
      expect(json['isCompleted'], true);
      expect(json['notes'], 'n');
      expect(json.keys.toSet(), {
        'id',
        'exerciseId',
        'setNumber',
        'reps',
        'weight',
        'duration',
        'isCompleted',
        'completedAt',
        'notes',
      });
    });

    test('fromJson -> toJson round-trip on a fully-populated set keeps every '
        'field (field-parity guard: the generated encoder must carry every '
        'field the generated decoder reads)', () {
      const wire = <String, dynamic>{
        'id': 3,
        'exerciseId': 7,
        'setNumber': 2,
        'reps': 8,
        'weight': 92.5,
        'duration': 30,
        'isCompleted': true,
        'completedAt': expectedIso,
        'notes': 'n',
      };
      final reEncoded = ExerciseSet.fromJson(wire).toJson();
      expect(reEncoded, wire);
    });

    test('nested inside a jsonEncode(Session.toJson()) create body: the set '
        'completedAt is UTC (Z) too', () {
      final session = Session(
        id: 1,
        userId: 2,
        date: DateTime(2026, 9, 3),
        status: 'completed',
        exercises: [
          Exercise(
            id: 5,
            sessionId: 1,
            name: 'Bench',
            exerciseSets: [
              setWith(DateTime.parse('2026-09-03T10:15:30.000-04:00')),
            ],
          ),
        ],
      );
      // This is what actually crosses the wire (Dio json-encodes the body).
      final decoded =
          jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>;
      final nestedSet =
          ((decoded['exercises'] as List).single
                  as Map<String, dynamic>)['exerciseSets']
              as List;
      expect(
        (nestedSet.single as Map<String, dynamic>)['completedAt'],
        expectedIso,
      );
    });
  });

  group('inbound parsing and round-trip', () {
    test('21. a Z response parses as the expected UTC instant', () {
      final set = ExerciseSet.fromJson(<String, dynamic>{
        'id': 1,
        'exerciseId': 2,
        'setNumber': 1,
        'isCompleted': true,
        'completedAt': expectedIso,
      });
      expect(set.completedAt!.toUtc(), utcInstant);
      expect(
        set.completedAt!.millisecondsSinceEpoch,
        utcInstant.millisecondsSinceEpoch,
      );
    });

    test('22. an explicit numeric offset response parses to the same '
        'instant', () {
      final set = ExerciseSet.fromJson(<String, dynamic>{
        'id': 1,
        'exerciseId': 2,
        'setNumber': 1,
        'isCompleted': true,
        'completedAt': '2026-09-03T10:15:30.000-04:00',
      });
      expect(
        set.completedAt!.millisecondsSinceEpoch,
        utcInstant.millisecondsSinceEpoch,
      );
    });

    test('24. a parsed value serialized outbound again represents the same '
        'epoch instant', () {
      for (final wire in <String>[
        expectedIso,
        '2026-09-03T10:15:30.000-04:00',
        '2026-09-03T19:45:30.000+05:30',
      ]) {
        final parsed = ExerciseSet.fromJson(<String, dynamic>{
          'id': 1,
          'exerciseId': 2,
          'setNumber': 1,
          'isCompleted': true,
          'completedAt': wire,
        });
        final reEncoded = parsed.toJson()['completedAt'] as String;
        expect(reEncoded, expectedIso, reason: 'round-trip of $wire');
        expect(
          DateTime.parse(reEncoded).millisecondsSinceEpoch,
          utcInstant.millisecondsSinceEpoch,
        );
      }
    });
  });

  group('23. Isar persistence round-trip preserves the instant', () {
    late Isar isar;
    late Directory tempDir;
    late String dbName;

    setUpAll(() async {
      await Isar.initializeIsarCore(download: true);
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('exset_completedat_');
      dbName = 'exset_${DateTime.now().microsecondsSinceEpoch}';
      isar = await Isar.open(
        [LocalExerciseSetSchema],
        directory: tempDir.path,
        name: dbName,
        inspector: false,
      );
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('write UTC -> reopen -> read -> ExerciseSet.toJson() emits the same '
        'instant with Z', () async {
      final row = LocalExerciseSet(
        exerciseLocalId: 1,
        setNumber: 1,
        reps: 10,
        weight: 100,
        isCompleted: true,
        completedAt: utcInstant,
        lastModifiedLocal: DateTime.now().toUtc(),
        isSynced: false,
        syncStatus: 'pending_create',
      );
      late int localId;
      await isar.writeTxn(() async {
        localId = await isar.localExerciseSets.put(row);
      });

      await isar.close();
      isar = await Isar.open(
        [LocalExerciseSetSchema],
        directory: tempDir.path,
        name: dbName,
        inspector: false,
      );

      final reread = (await isar.localExerciseSets.get(localId))!;
      // Isar hands the value back local-flagged, but the instant is intact.
      expect(reread.completedAt!.isUtc, isFalse);
      expect(
        reread.completedAt!.millisecondsSinceEpoch,
        utcInstant.millisecondsSinceEpoch,
      );

      final wire =
          ExerciseSet(
                id: 1,
                exerciseId: 1,
                setNumber: reread.setNumber,
                isCompleted: reread.isCompleted,
                completedAt: reread.completedAt,
              ).toJson()['completedAt']
              as String;

      expect(wire, expectedIso);
      expect(
        DateTime.parse(wire).millisecondsSinceEpoch,
        utcInstant.millisecondsSinceEpoch,
      );
    });
  });
}
