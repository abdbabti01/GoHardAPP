import 'package:flutter_test/flutter_test.dart';
import 'package:go_hard_app/data/models/session.dart';
import 'package:go_hard_app/data/models/exercise.dart';
import 'package:go_hard_app/data/models/exercise_set.dart';
import 'package:go_hard_app/data/models/exercise_template.dart';
import 'package:go_hard_app/data/local/models/local_session.dart';
import 'package:go_hard_app/data/local/models/local_exercise.dart';
import 'package:go_hard_app/data/local/models/local_exercise_set.dart';
import 'package:go_hard_app/data/local/models/local_exercise_template.dart';
import 'package:go_hard_app/data/local/services/model_mapper.dart';

void main() {
  group('ModelMapper - Session Conversion', () {
    test('sessionToLocal should convert API Session to LocalSession', () {
      // Arrange
      final apiSession = Session(
        id: 123,
        userId: 456,
        date: DateTime(2024, 1, 15),
        duration: 3600,
        notes: 'Test workout',
        type: 'strength',
        status: 'completed',
        startedAt: DateTime(2024, 1, 15, 10, 0),
        completedAt: DateTime(2024, 1, 15, 11, 0),
        pausedAt: null,
        exercises: [],
      );

      // Act
      final localSession = ModelMapper.sessionToLocal(apiSession);

      // Assert
      expect(localSession.serverId, 123);
      expect(localSession.userId, 456);
      expect(localSession.date, DateTime(2024, 1, 15));
      expect(localSession.duration, 3600);
      expect(localSession.notes, 'Test workout');
      expect(localSession.type, 'strength');
      expect(localSession.status, 'completed');
      expect(localSession.isSynced, true);
      expect(localSession.syncStatus, 'synced');
      expect(localSession.startedAt, DateTime(2024, 1, 15, 10, 0));
      expect(localSession.completedAt, DateTime(2024, 1, 15, 11, 0));
      expect(localSession.pausedAt, null);
    });

    test(
      'sessionToLocal should mark as pending_update when unsynced with server id',
      () {
        // Arrange - Session that exists on server (has id)
        final apiSession = Session(
          id: 123,
          userId: 456,
          date: DateTime(2024, 1, 15),
          duration: 3600,
          notes: 'Test workout',
          type: 'strength',
          status: 'in_progress',
          exercises: [],
        );

        // Act
        final localSession = ModelMapper.sessionToLocal(
          apiSession,
          isSynced: false,
        );

        // Assert - Should be pending_update since session exists on server
        expect(localSession.serverId, 123);
        expect(localSession.isSynced, false);
        expect(localSession.syncStatus, 'pending_update');
      },
    );

    test(
      'sessionToLocal should mark as pending_create when unsynced without server id',
      () {
        // Arrange - New session that doesn't exist on server yet
        final apiSession = Session(
          id: 0, // No server id
          userId: 456,
          date: DateTime(2024, 1, 15),
          duration: 3600,
          notes: 'Test workout',
          type: 'strength',
          status: 'in_progress',
          exercises: [],
        );

        // Act
        final localSession = ModelMapper.sessionToLocal(
          apiSession,
          isSynced: false,
        );

        // Assert - Should be pending_create since session is new
        expect(localSession.serverId, 0);
        expect(localSession.isSynced, false);
        expect(localSession.syncStatus, 'pending_create');
      },
    );

    test('localToSession should convert LocalSession to API Session', () {
      // Arrange
      // Real Isar returns DateTime fields as local-flagged, but preserving
      // the correct absolute instant (verified against a real Isar instance
      // in model_mapper_isar_roundtrip_test.dart) - i.e. equivalent to
      // calling .toLocal() on the originally-stored UTC value, NOT a local
      // DateTime that merely repeats the same wall-clock digits. Simulate
      // that here rather than constructing a plain local DateTime with the
      // target UTC digits, which does not reflect what Isar actually
      // returns and would silently mask a mapper regression.
      final startedAtUtc = DateTime.utc(2024, 1, 15, 10, 0);
      final completedAtUtc = DateTime.utc(2024, 1, 15, 11, 0);
      final localSession = LocalSession(
        serverId: 123,
        userId: 456,
        date: DateTime(2024, 1, 15),
        duration: 3600,
        notes: 'Test workout',
        type: 'strength',
        status: 'completed',
        startedAt: startedAtUtc.toLocal(),
        completedAt: completedAtUtc.toLocal(),
        pausedAt: null,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
      );

      // Act
      final apiSession = ModelMapper.localToSession(localSession);

      // Assert
      expect(apiSession.id, 123);
      expect(apiSession.userId, 456);
      expect(apiSession.date, DateTime(2024, 1, 15));
      expect(apiSession.duration, 3600);
      expect(apiSession.notes, 'Test workout');
      expect(apiSession.type, 'strength');
      expect(apiSession.status, 'completed');
      // The absolute instant must be preserved - not merely a UTC flag
      // slapped onto whatever wall-clock digits Isar happened to display.
      expect(apiSession.startedAt!.isUtc, true);
      expect(
        apiSession.startedAt!.microsecondsSinceEpoch,
        startedAtUtc.microsecondsSinceEpoch,
      );
      expect(apiSession.completedAt!.isUtc, true);
      expect(
        apiSession.completedAt!.microsecondsSinceEpoch,
        completedAtUtc.microsecondsSinceEpoch,
      );
      expect(apiSession.pausedAt, null);
    });

    test(
      'localToSession should use 0 for unsynced sessions without serverId',
      () {
        // Arrange
        final localSession = LocalSession(
          serverId: null, // Not synced yet
          userId: 456,
          date: DateTime(2024, 1, 15),
          duration: 3600,
          notes: 'Test workout',
          type: 'strength',
          status: 'in_progress',
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime.now(),
        )..localId = 0; // Explicitly set localId for testing

        // Act
        final apiSession = ModelMapper.localToSession(localSession);

        // Assert
        expect(apiSession.id, 0); // Should use localId when serverId is null
        expect(apiSession.userId, 456);
        expect(apiSession.status, 'in_progress');
      },
    );

    test('sessionToLocal and localToSession should be bidirectional', () {
      // Arrange
      final originalSession = Session(
        id: 999,
        userId: 111,
        date: DateTime(2024, 1, 15),
        duration: 7200,
        notes: 'Bidirectional test',
        type: 'cardio',
        status: 'completed',
        exercises: [],
      );

      // Act - Convert to local and back to API
      final localSession = ModelMapper.sessionToLocal(originalSession);
      final convertedSession = ModelMapper.localToSession(localSession);

      // Assert - Should match original
      expect(convertedSession.id, originalSession.id);
      expect(convertedSession.userId, originalSession.userId);
      expect(convertedSession.date, originalSession.date);
      expect(convertedSession.duration, originalSession.duration);
      expect(convertedSession.notes, originalSession.notes);
      expect(convertedSession.type, originalSession.type);
      expect(convertedSession.status, originalSession.status);
    });
  });

  group('ModelMapper - Version Handling', () {
    test('sessionToLocal preserves the API session version', () {
      final apiSession = Session(
        id: 123,
        userId: 456,
        date: DateTime(2024, 1, 15),
        status: 'in_progress',
        exercises: [],
        version: 7,
      );

      final localSession = ModelMapper.sessionToLocal(apiSession);

      expect(localSession.version, 7);
    });

    test(
      'localToSession falls back to 1 for display only when version is unknown',
      () {
        final localSession = LocalSession(
          serverId: 123,
          userId: 456,
          date: DateTime(2024, 1, 15),
          status: 'in_progress',
          isSynced: false,
          syncStatus: 'pending_update',
          lastModifiedLocal: DateTime.now(),
          version: null,
        );

        final apiSession = ModelMapper.localToSession(localSession);

        expect(apiSession.version, 1);
      },
    );

    test('localToSession preserves a known version', () {
      final localSession = LocalSession(
        serverId: 123,
        userId: 456,
        date: DateTime(2024, 1, 15),
        status: 'in_progress',
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
        version: 9,
      );

      final apiSession = ModelMapper.localToSession(localSession);

      expect(apiSession.version, 9);
    });
  });

  group('ModelMapper - buildSessionUpdateRequest', () {
    test('sends the persisted version, not a fallback of 1', () {
      final localSession = LocalSession(
        serverId: 123,
        userId: 456,
        date: DateTime(2024, 1, 15),
        name: 'Leg day',
        status: 'in_progress',
        isSynced: false,
        syncStatus: 'pending_update',
        lastModifiedLocal: DateTime.now(),
        version: 5,
      );

      final request = ModelMapper.buildSessionUpdateRequest(localSession);

      expect(request['version'], 5);
    });

    test(
      'sends a null version untouched when the local row never learned one',
      () {
        final localSession = LocalSession(
          serverId: 123,
          userId: 456,
          date: DateTime(2024, 1, 15),
          status: 'in_progress',
          isSynced: false,
          syncStatus: 'pending_update',
          lastModifiedLocal: DateTime.now(),
          version: null,
        );

        final request = ModelMapper.buildSessionUpdateRequest(localSession);

        expect(request.containsKey('version'), true);
        expect(request['version'], isNull);
      },
    );

    test('omits id and userId, matching the server contract', () {
      final localSession = LocalSession(
        serverId: 123,
        userId: 456,
        date: DateTime(2024, 1, 15),
        status: 'in_progress',
        isSynced: false,
        syncStatus: 'pending_update',
        lastModifiedLocal: DateTime.now(),
        version: 1,
      );

      final request = ModelMapper.buildSessionUpdateRequest(localSession);

      expect(request.containsKey('id'), false);
      expect(request.containsKey('userId'), false);
    });

    test('includes the current mutable fields', () {
      final localSession = LocalSession(
        serverId: 123,
        userId: 456,
        date: DateTime(2024, 3, 2),
        duration: 1800,
        notes: 'Felt strong',
        type: 'strength',
        name: 'Push day',
        status: 'completed',
        programId: 10,
        programWorkoutId: 20,
        isSynced: false,
        syncStatus: 'pending_update',
        lastModifiedLocal: DateTime.now(),
        version: 2,
      );

      final request = ModelMapper.buildSessionUpdateRequest(localSession);

      expect(request['date'], '2024-03-02');
      expect(request['duration'], 1800);
      expect(request['notes'], 'Felt strong');
      expect(request['type'], 'strength');
      expect(request['name'], 'Push day');
      expect(request['status'], 'completed');
    });

    test(
      'omits programId and programWorkoutId, matching SessionUpdateRequestDto',
      () {
        // Program relationships are server-controlled and not part of the
        // API's update DTO, even though the local session still carries
        // them for display/caching purposes.
        final localSession = LocalSession(
          serverId: 123,
          userId: 456,
          date: DateTime(2024, 3, 2),
          status: 'in_progress',
          programId: 10,
          programWorkoutId: 20,
          isSynced: false,
          syncStatus: 'pending_update',
          lastModifiedLocal: DateTime.now(),
          version: 2,
        );

        final request = ModelMapper.buildSessionUpdateRequest(localSession);

        expect(request.containsKey('programId'), false);
        expect(request.containsKey('programWorkoutId'), false);
      },
    );
  });

  group('ModelMapper - Exercise Conversion', () {
    test('exerciseToLocal should convert API Exercise to LocalExercise', () {
      // Arrange
      final apiExercise = Exercise(
        id: 10,
        sessionId: 20,
        name: 'Bench Press',
        duration: 300,
        restTime: 90,
        notes: 'Heavy day',
        exerciseTemplateId: 5,
        exerciseSets: [],
      );

      // Act
      final localExercise = ModelMapper.exerciseToLocal(
        apiExercise,
        sessionLocalId: 100,
        sessionServerId: 20,
      );

      // Assert
      expect(localExercise.serverId, 10);
      expect(localExercise.sessionLocalId, 100);
      expect(localExercise.sessionServerId, 20);
      expect(localExercise.name, 'Bench Press');
      expect(localExercise.duration, 300);
      expect(localExercise.restTime, 90);
      expect(localExercise.notes, 'Heavy day');
      expect(localExercise.exerciseTemplateId, 5);
      expect(localExercise.isSynced, true);
      expect(localExercise.syncStatus, 'synced');
    });

    test('localToExercise should convert LocalExercise to API Exercise', () {
      // Arrange
      final localExercise = LocalExercise(
        serverId: 10,
        sessionLocalId: 100,
        sessionServerId: 20,
        name: 'Bench Press',
        duration: 300,
        restTime: 90,
        notes: 'Heavy day',
        exerciseTemplateId: 5,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
      );

      // Act
      final apiExercise = ModelMapper.localToExercise(localExercise);

      // Assert
      expect(apiExercise.id, 10);
      expect(apiExercise.sessionId, 20);
      expect(apiExercise.name, 'Bench Press');
      expect(apiExercise.duration, 300);
      expect(apiExercise.restTime, 90);
      expect(apiExercise.notes, 'Heavy day');
      expect(apiExercise.exerciseTemplateId, 5);
    });

    test(
      'localToExercise exposes an unsynced exercise under the collision-free '
      'namespace: id == -localId (never a positive local id, never 0)',
      () {
        final offline = LocalExercise(
          serverId: null,
          sessionLocalId: 100,
          name: 'Squat',
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime.now(),
        );
        offline.localId = 7;

        expect(ModelMapper.localToExercise(offline).id, -7);

        // A legacy `serverId == 0` sentinel is also "unsynced".
        final legacyZero = LocalExercise(
          serverId: 0,
          sessionLocalId: 100,
          name: 'Squat',
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: DateTime.now(),
        );
        legacyZero.localId = 9;
        expect(ModelMapper.localToExercise(legacyZero).id, -9);
      },
    );

    test('publicRowId / decode helpers round-trip', () {
      expect(ModelMapper.publicRowId(serverId: 42, localId: 5), 42);
      expect(ModelMapper.publicRowId(serverId: null, localId: 5), -5);
      expect(ModelMapper.publicRowId(serverId: 0, localId: 5), -5);
      expect(ModelMapper.publicRowId(serverId: null, localId: 0), 0);
      expect(ModelMapper.isOfflinePublicId(-5), isTrue);
      expect(ModelMapper.isOfflinePublicId(42), isFalse);
      expect(ModelMapper.localIdFromPublicId(-5), 5);
      expect(ModelMapper.localIdFromPublicId(42), 0);
    });
  });

  group('ModelMapper - ExerciseSet Conversion', () {
    test(
      'exerciseSetToLocal should convert API ExerciseSet to LocalExerciseSet',
      () {
        // Arrange
        final apiSet = ExerciseSet(
          id: 1,
          exerciseId: 10,
          setNumber: 1,
          reps: 10,
          weight: 135.0,
          duration: 30,
          isCompleted: true,
          completedAt: DateTime(2024, 1, 15, 10, 30),
          notes: 'Good form',
        );

        // Act
        final localSet = ModelMapper.exerciseSetToLocal(
          apiSet,
          exerciseLocalId: 50,
          exerciseServerId: 10,
        );

        // Assert
        expect(localSet.serverId, 1);
        expect(localSet.exerciseLocalId, 50);
        expect(localSet.exerciseServerId, 10);
        expect(localSet.setNumber, 1);
        expect(localSet.reps, 10);
        expect(localSet.weight, 135.0);
        expect(localSet.duration, 30);
        expect(localSet.isCompleted, true);
        expect(localSet.completedAt, DateTime(2024, 1, 15, 10, 30));
        expect(localSet.notes, 'Good form');
        expect(localSet.isSynced, true);
        expect(localSet.syncStatus, 'synced');
      },
    );

    test(
      'localToExerciseSet should convert LocalExerciseSet to API ExerciseSet',
      () {
        // Arrange
        final localSet = LocalExerciseSet(
          serverId: 1,
          exerciseLocalId: 50,
          exerciseServerId: 10,
          setNumber: 2,
          reps: 8,
          weight: 140.0,
          duration: 35,
          isCompleted: false,
          completedAt: null,
          notes: null,
          isSynced: true,
          syncStatus: 'synced',
          lastModifiedLocal: DateTime.now(),
        );

        // Act
        final apiSet = ModelMapper.localToExerciseSet(localSet);

        // Assert
        expect(apiSet.id, 1);
        expect(apiSet.exerciseId, 10);
        expect(apiSet.setNumber, 2);
        expect(apiSet.reps, 8);
        expect(apiSet.weight, 140.0);
        expect(apiSet.duration, 35);
        expect(apiSet.isCompleted, false);
        expect(apiSet.completedAt, null);
        expect(apiSet.notes, null);
      },
    );

    test('localToExerciseSet exposes an unsynced set as id == -localId (never '
        '0), and its parent id likewise', () {
      final offline = LocalExerciseSet(
        serverId: null,
        exerciseLocalId: 3,
        exerciseServerId: null,
        setNumber: 1,
        reps: 10,
        weight: 100,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: DateTime.now(),
      );
      offline.localId = 7;

      final api = ModelMapper.localToExerciseSet(offline);
      expect(api.id, -7);
      expect(api.exerciseId, -3);

      // A synced set keeps its positive server ids.
      final synced = LocalExerciseSet(
        serverId: 42,
        exerciseLocalId: 3,
        exerciseServerId: 200,
        setNumber: 1,
        reps: 10,
        weight: 100,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
      );
      synced.localId = 7;
      final syncedApi = ModelMapper.localToExerciseSet(synced);
      expect(syncedApi.id, 42);
      expect(syncedApi.exerciseId, 200);
    });

    test('exerciseSetToLocal maps a non-positive incoming id to a null '
        'serverId', () {
      final zeroId = ExerciseSet(id: 0, exerciseId: 200, setNumber: 1);
      expect(
        ModelMapper.exerciseSetToLocal(zeroId, exerciseLocalId: 3).serverId,
        isNull,
      );
      final negId = ExerciseSet(id: -7, exerciseId: 200, setNumber: 1);
      expect(
        ModelMapper.exerciseSetToLocal(negId, exerciseLocalId: 3).serverId,
        isNull,
      );
    });
  });

  group('ModelMapper - ExerciseTemplate Conversion', () {
    test('exerciseTemplateToLocal should convert API ExerciseTemplate', () {
      // Arrange
      final apiTemplate = ExerciseTemplate(
        id: 5,
        name: 'Bench Press',
        description: 'Classic chest exercise',
        category: 'Strength',
        muscleGroup: 'Chest',
        equipment: 'Barbell',
        difficulty: 'Intermediate',
        videoUrl: 'https://example.com/video',
        imageUrl: 'https://example.com/image',
        instructions: '1. Lie on bench\n2. Lower bar\n3. Press up',
        isCustom: false,
        createdByUserId: null,
      );

      // Act
      final localTemplate = ModelMapper.exerciseTemplateToLocal(apiTemplate);

      // Assert
      expect(localTemplate.serverId, 5);
      expect(localTemplate.name, 'Bench Press');
      expect(localTemplate.description, 'Classic chest exercise');
      expect(localTemplate.category, 'Strength');
      expect(localTemplate.muscleGroup, 'Chest');
      expect(localTemplate.equipment, 'Barbell');
      expect(localTemplate.difficulty, 'Intermediate');
      expect(localTemplate.videoUrl, 'https://example.com/video');
      expect(localTemplate.imageUrl, 'https://example.com/image');
      expect(
        localTemplate.instructions,
        '1. Lie on bench\n2. Lower bar\n3. Press up',
      );
      expect(localTemplate.isCustom, false);
      expect(localTemplate.createdByUserId, null);
      expect(localTemplate.isSynced, true);
      expect(localTemplate.syncStatus, 'synced');
    });

    test('localToExerciseTemplate should convert LocalExerciseTemplate', () {
      // Arrange
      final localTemplate = LocalExerciseTemplate(
        serverId: 5,
        name: 'Squat',
        description: 'Leg exercise',
        category: 'Strength',
        muscleGroup: 'Legs',
        equipment: 'Barbell',
        difficulty: 'Advanced',
        videoUrl: null,
        imageUrl: null,
        instructions: 'Squat down',
        isCustom: true,
        createdByUserId: 123,
        isSynced: true,
        syncStatus: 'synced',
        lastModifiedLocal: DateTime.now(),
      );

      // Act
      final apiTemplate = ModelMapper.localToExerciseTemplate(localTemplate);

      // Assert
      expect(apiTemplate.id, 5);
      expect(apiTemplate.name, 'Squat');
      expect(apiTemplate.description, 'Leg exercise');
      expect(apiTemplate.category, 'Strength');
      expect(apiTemplate.muscleGroup, 'Legs');
      expect(apiTemplate.equipment, 'Barbell');
      expect(apiTemplate.difficulty, 'Advanced');
      expect(apiTemplate.isCustom, true);
      expect(apiTemplate.createdByUserId, 123);
    });
  });

  group('ModelMapper - Batch Conversions', () {
    test('sessionsToLocal should convert list of sessions', () {
      // Arrange
      final apiSessions = [
        Session(id: 1, userId: 100, date: DateTime(2024, 1, 1), exercises: []),
        Session(id: 2, userId: 100, date: DateTime(2024, 1, 2), exercises: []),
        Session(id: 3, userId: 100, date: DateTime(2024, 1, 3), exercises: []),
      ];

      // Act
      final localSessions = ModelMapper.sessionsToLocal(apiSessions);

      // Assert
      expect(localSessions.length, 3);
      expect(localSessions[0].serverId, 1);
      expect(localSessions[1].serverId, 2);
      expect(localSessions[2].serverId, 3);
      expect(localSessions.every((s) => s.isSynced), true);
    });

    test('localToSessions should convert list of local sessions', () {
      // Arrange
      final localSessions = [
        LocalSession(
          serverId: 1,
          userId: 100,
          date: DateTime(2024, 1, 1),
          isSynced: true,
          syncStatus: 'synced',
          lastModifiedLocal: DateTime.now(),
        ),
        LocalSession(
          serverId: 2,
          userId: 100,
          date: DateTime(2024, 1, 2),
          isSynced: true,
          syncStatus: 'synced',
          lastModifiedLocal: DateTime.now(),
        ),
      ];

      // Act
      final apiSessions = ModelMapper.localToSessions(localSessions);

      // Assert
      expect(apiSessions.length, 2);
      expect(apiSessions[0].id, 1);
      expect(apiSessions[1].id, 2);
    });
  });
}
