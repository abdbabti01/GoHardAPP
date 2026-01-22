// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_program_workout.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalProgramWorkoutCollection on Isar {
  IsarCollection<LocalProgramWorkout> get localProgramWorkouts =>
      this.collection();
}

const LocalProgramWorkoutSchema = CollectionSchema(
  name: r'LocalProgramWorkout',
  id: 2404861955248013790,
  properties: {
    r'completedAt': PropertySchema(
      id: 0,
      name: r'completedAt',
      type: IsarType.dateTime,
    ),
    r'completionNotes': PropertySchema(
      id: 1,
      name: r'completionNotes',
      type: IsarType.string,
    ),
    r'coolDown': PropertySchema(
      id: 2,
      name: r'coolDown',
      type: IsarType.string,
    ),
    r'dayName': PropertySchema(id: 3, name: r'dayName', type: IsarType.string),
    r'dayNumber': PropertySchema(
      id: 4,
      name: r'dayNumber',
      type: IsarType.long,
    ),
    r'description': PropertySchema(
      id: 5,
      name: r'description',
      type: IsarType.string,
    ),
    r'estimatedDuration': PropertySchema(
      id: 6,
      name: r'estimatedDuration',
      type: IsarType.long,
    ),
    r'exercisesJson': PropertySchema(
      id: 7,
      name: r'exercisesJson',
      type: IsarType.string,
    ),
    r'isCompleted': PropertySchema(
      id: 8,
      name: r'isCompleted',
      type: IsarType.bool,
    ),
    r'isSynced': PropertySchema(id: 9, name: r'isSynced', type: IsarType.bool),
    r'lastModifiedLocal': PropertySchema(
      id: 10,
      name: r'lastModifiedLocal',
      type: IsarType.dateTime,
    ),
    r'lastModifiedServer': PropertySchema(
      id: 11,
      name: r'lastModifiedServer',
      type: IsarType.dateTime,
    ),
    r'lastSyncAttempt': PropertySchema(
      id: 12,
      name: r'lastSyncAttempt',
      type: IsarType.dateTime,
    ),
    r'orderIndex': PropertySchema(
      id: 13,
      name: r'orderIndex',
      type: IsarType.long,
    ),
    r'programLocalId': PropertySchema(
      id: 14,
      name: r'programLocalId',
      type: IsarType.long,
    ),
    r'programServerId': PropertySchema(
      id: 15,
      name: r'programServerId',
      type: IsarType.long,
    ),
    r'serverId': PropertySchema(id: 16, name: r'serverId', type: IsarType.long),
    r'syncError': PropertySchema(
      id: 17,
      name: r'syncError',
      type: IsarType.string,
    ),
    r'syncRetryCount': PropertySchema(
      id: 18,
      name: r'syncRetryCount',
      type: IsarType.long,
    ),
    r'syncStatus': PropertySchema(
      id: 19,
      name: r'syncStatus',
      type: IsarType.string,
    ),
    r'warmUp': PropertySchema(id: 20, name: r'warmUp', type: IsarType.string),
    r'weekNumber': PropertySchema(
      id: 21,
      name: r'weekNumber',
      type: IsarType.long,
    ),
    r'workoutName': PropertySchema(
      id: 22,
      name: r'workoutName',
      type: IsarType.string,
    ),
    r'workoutType': PropertySchema(
      id: 23,
      name: r'workoutType',
      type: IsarType.string,
    ),
  },
  estimateSize: _localProgramWorkoutEstimateSize,
  serialize: _localProgramWorkoutSerialize,
  deserialize: _localProgramWorkoutDeserialize,
  deserializeProp: _localProgramWorkoutDeserializeProp,
  idName: r'localId',
  indexes: {
    r'weekNumber': IndexSchema(
      id: 3113799900175558897,
      name: r'weekNumber',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'weekNumber',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'isSynced': IndexSchema(
      id: -39763503327887510,
      name: r'isSynced',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'isSynced',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'syncStatus': IndexSchema(
      id: 8239539375045684509,
      name: r'syncStatus',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'syncStatus',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _localProgramWorkoutGetId,
  getLinks: _localProgramWorkoutGetLinks,
  attach: _localProgramWorkoutAttach,
  version: '3.1.0+1',
);

int _localProgramWorkoutEstimateSize(
  LocalProgramWorkout object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.completionNotes;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.coolDown;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.dayName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.description;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.exercisesJson.length * 3;
  {
    final value = object.syncError;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.syncStatus.length * 3;
  {
    final value = object.warmUp;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.workoutName.length * 3;
  {
    final value = object.workoutType;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _localProgramWorkoutSerialize(
  LocalProgramWorkout object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.completedAt);
  writer.writeString(offsets[1], object.completionNotes);
  writer.writeString(offsets[2], object.coolDown);
  writer.writeString(offsets[3], object.dayName);
  writer.writeLong(offsets[4], object.dayNumber);
  writer.writeString(offsets[5], object.description);
  writer.writeLong(offsets[6], object.estimatedDuration);
  writer.writeString(offsets[7], object.exercisesJson);
  writer.writeBool(offsets[8], object.isCompleted);
  writer.writeBool(offsets[9], object.isSynced);
  writer.writeDateTime(offsets[10], object.lastModifiedLocal);
  writer.writeDateTime(offsets[11], object.lastModifiedServer);
  writer.writeDateTime(offsets[12], object.lastSyncAttempt);
  writer.writeLong(offsets[13], object.orderIndex);
  writer.writeLong(offsets[14], object.programLocalId);
  writer.writeLong(offsets[15], object.programServerId);
  writer.writeLong(offsets[16], object.serverId);
  writer.writeString(offsets[17], object.syncError);
  writer.writeLong(offsets[18], object.syncRetryCount);
  writer.writeString(offsets[19], object.syncStatus);
  writer.writeString(offsets[20], object.warmUp);
  writer.writeLong(offsets[21], object.weekNumber);
  writer.writeString(offsets[22], object.workoutName);
  writer.writeString(offsets[23], object.workoutType);
}

LocalProgramWorkout _localProgramWorkoutDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalProgramWorkout(
    completedAt: reader.readDateTimeOrNull(offsets[0]),
    completionNotes: reader.readStringOrNull(offsets[1]),
    coolDown: reader.readStringOrNull(offsets[2]),
    dayName: reader.readStringOrNull(offsets[3]),
    dayNumber: reader.readLong(offsets[4]),
    description: reader.readStringOrNull(offsets[5]),
    estimatedDuration: reader.readLongOrNull(offsets[6]),
    exercisesJson: reader.readString(offsets[7]),
    isCompleted: reader.readBoolOrNull(offsets[8]) ?? false,
    isSynced: reader.readBoolOrNull(offsets[9]) ?? false,
    lastModifiedLocal: reader.readDateTime(offsets[10]),
    lastModifiedServer: reader.readDateTimeOrNull(offsets[11]),
    lastSyncAttempt: reader.readDateTimeOrNull(offsets[12]),
    orderIndex: reader.readLong(offsets[13]),
    programLocalId: reader.readLong(offsets[14]),
    programServerId: reader.readLongOrNull(offsets[15]),
    serverId: reader.readLongOrNull(offsets[16]),
    syncError: reader.readStringOrNull(offsets[17]),
    syncRetryCount: reader.readLongOrNull(offsets[18]) ?? 0,
    syncStatus: reader.readStringOrNull(offsets[19]) ?? 'pending_create',
    warmUp: reader.readStringOrNull(offsets[20]),
    weekNumber: reader.readLong(offsets[21]),
    workoutName: reader.readString(offsets[22]),
    workoutType: reader.readStringOrNull(offsets[23]),
  );
  object.localId = id;
  return object;
}

P _localProgramWorkoutDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readLongOrNull(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 9:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 10:
      return (reader.readDateTime(offset)) as P;
    case 11:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 12:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 13:
      return (reader.readLong(offset)) as P;
    case 14:
      return (reader.readLong(offset)) as P;
    case 15:
      return (reader.readLongOrNull(offset)) as P;
    case 16:
      return (reader.readLongOrNull(offset)) as P;
    case 17:
      return (reader.readStringOrNull(offset)) as P;
    case 18:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 19:
      return (reader.readStringOrNull(offset) ?? 'pending_create') as P;
    case 20:
      return (reader.readStringOrNull(offset)) as P;
    case 21:
      return (reader.readLong(offset)) as P;
    case 22:
      return (reader.readString(offset)) as P;
    case 23:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localProgramWorkoutGetId(LocalProgramWorkout object) {
  return object.localId;
}

List<IsarLinkBase<dynamic>> _localProgramWorkoutGetLinks(
  LocalProgramWorkout object,
) {
  return [];
}

void _localProgramWorkoutAttach(
  IsarCollection<dynamic> col,
  Id id,
  LocalProgramWorkout object,
) {
  object.localId = id;
}

extension LocalProgramWorkoutQueryWhereSort
    on QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QWhere> {
  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhere>
  anyLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhere>
  anyWeekNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'weekNumber'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhere>
  anyIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isSynced'),
      );
    });
  }
}

extension LocalProgramWorkoutQueryWhere
    on QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QWhereClause> {
  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  localIdEqualTo(Id localId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(lower: localId, upper: localId),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  localIdNotEqualTo(Id localId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: localId, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: localId, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: localId, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: localId, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  localIdGreaterThan(Id localId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: localId, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  localIdLessThan(Id localId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: localId, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  localIdBetween(
    Id lowerLocalId,
    Id upperLocalId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerLocalId,
          includeLower: includeLower,
          upper: upperLocalId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  weekNumberEqualTo(int weekNumber) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'weekNumber', value: [weekNumber]),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  weekNumberNotEqualTo(int weekNumber) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'weekNumber',
                lower: [],
                upper: [weekNumber],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'weekNumber',
                lower: [weekNumber],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'weekNumber',
                lower: [weekNumber],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'weekNumber',
                lower: [],
                upper: [weekNumber],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  weekNumberGreaterThan(int weekNumber, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'weekNumber',
          lower: [weekNumber],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  weekNumberLessThan(int weekNumber, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'weekNumber',
          lower: [],
          upper: [weekNumber],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  weekNumberBetween(
    int lowerWeekNumber,
    int upperWeekNumber, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'weekNumber',
          lower: [lowerWeekNumber],
          includeLower: includeLower,
          upper: [upperWeekNumber],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  isSyncedEqualTo(bool isSynced) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'isSynced', value: [isSynced]),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  isSyncedNotEqualTo(bool isSynced) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'isSynced',
                lower: [],
                upper: [isSynced],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'isSynced',
                lower: [isSynced],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'isSynced',
                lower: [isSynced],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'isSynced',
                lower: [],
                upper: [isSynced],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  syncStatusEqualTo(String syncStatus) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'syncStatus', value: [syncStatus]),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterWhereClause>
  syncStatusNotEqualTo(String syncStatus) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'syncStatus',
                lower: [],
                upper: [syncStatus],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'syncStatus',
                lower: [syncStatus],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'syncStatus',
                lower: [syncStatus],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'syncStatus',
                lower: [],
                upper: [syncStatus],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension LocalProgramWorkoutQueryFilter
    on
        QueryBuilder<
          LocalProgramWorkout,
          LocalProgramWorkout,
          QFilterCondition
        > {
  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'completedAt'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'completedAt'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completedAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'completedAt', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completedAtGreaterThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'completedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completedAtLessThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'completedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'completedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'completionNotes'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'completionNotes'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'completionNotes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'completionNotes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'completionNotes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'completionNotes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'completionNotes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'completionNotes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'completionNotes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'completionNotes',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'completionNotes', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  completionNotesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'completionNotes', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'coolDown'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'coolDown'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'coolDown',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'coolDown',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'coolDown',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'coolDown',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'coolDown',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'coolDown',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'coolDown',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'coolDown',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'coolDown', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  coolDownIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'coolDown', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'dayName'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'dayName'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'dayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'dayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'dayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'dayName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'dayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'dayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'dayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'dayName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'dayName', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'dayName', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNumberEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'dayNumber', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNumberGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'dayNumber',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNumberLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'dayNumber',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  dayNumberBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'dayNumber',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'description'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'description'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'description',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'description',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'description', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  descriptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'description', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  estimatedDurationIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'estimatedDuration'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  estimatedDurationIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'estimatedDuration'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  estimatedDurationEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'estimatedDuration', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  estimatedDurationGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'estimatedDuration',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  estimatedDurationLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'estimatedDuration',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  estimatedDurationBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'estimatedDuration',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'exercisesJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'exercisesJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'exercisesJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'exercisesJson',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'exercisesJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'exercisesJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'exercisesJson',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'exercisesJson',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'exercisesJson', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  exercisesJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'exercisesJson', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  isCompletedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isCompleted', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  isSyncedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isSynced', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedLocalEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastModifiedLocal', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedLocalGreaterThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastModifiedLocal',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedLocalLessThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastModifiedLocal',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedLocalBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastModifiedLocal',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedServerIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastModifiedServer'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedServerIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastModifiedServer'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedServerEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastModifiedServer', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedServerGreaterThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastModifiedServer',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedServerLessThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastModifiedServer',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastModifiedServerBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastModifiedServer',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastSyncAttemptIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastSyncAttempt'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastSyncAttemptIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastSyncAttempt'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastSyncAttemptEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastSyncAttempt', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastSyncAttemptGreaterThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastSyncAttempt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastSyncAttemptLessThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastSyncAttempt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  lastSyncAttemptBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastSyncAttempt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  localIdEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'localId', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  localIdGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'localId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  localIdLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'localId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  localIdBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'localId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  orderIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'orderIndex', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  orderIndexGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'orderIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  orderIndexLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'orderIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  orderIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'orderIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programLocalIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'programLocalId', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programLocalIdGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'programLocalId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programLocalIdLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'programLocalId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programLocalIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'programLocalId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programServerIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'programServerId'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programServerIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'programServerId'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programServerIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'programServerId', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programServerIdGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'programServerId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programServerIdLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'programServerId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  programServerIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'programServerId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  serverIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'serverId'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  serverIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'serverId'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  serverIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'serverId', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  serverIdGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'serverId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  serverIdLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'serverId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  serverIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'serverId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'syncError'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'syncError'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'syncError',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'syncError',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'syncError',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'syncError',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'syncError',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'syncError',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'syncError',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'syncError',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'syncError', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncErrorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'syncError', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncRetryCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'syncRetryCount', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncRetryCountGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'syncRetryCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncRetryCountLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'syncRetryCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncRetryCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'syncRetryCount',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'syncStatus',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'syncStatus',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'syncStatus',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'syncStatus',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'syncStatus',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'syncStatus',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'syncStatus',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'syncStatus',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'syncStatus', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  syncStatusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'syncStatus', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'warmUp'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'warmUp'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'warmUp',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'warmUp',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'warmUp',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'warmUp',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'warmUp',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'warmUp',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'warmUp',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'warmUp',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'warmUp', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  warmUpIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'warmUp', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  weekNumberEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'weekNumber', value: value),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  weekNumberGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'weekNumber',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  weekNumberLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'weekNumber',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  weekNumberBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'weekNumber',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'workoutName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'workoutName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'workoutName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'workoutName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'workoutName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'workoutName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'workoutName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'workoutName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'workoutName', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'workoutName', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'workoutType'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'workoutType'),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'workoutType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'workoutType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'workoutType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'workoutType',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'workoutType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'workoutType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'workoutType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'workoutType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'workoutType', value: ''),
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterFilterCondition>
  workoutTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'workoutType', value: ''),
      );
    });
  }
}

extension LocalProgramWorkoutQueryObject
    on
        QueryBuilder<
          LocalProgramWorkout,
          LocalProgramWorkout,
          QFilterCondition
        > {}

extension LocalProgramWorkoutQueryLinks
    on
        QueryBuilder<
          LocalProgramWorkout,
          LocalProgramWorkout,
          QFilterCondition
        > {}

extension LocalProgramWorkoutQuerySortBy
    on QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QSortBy> {
  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByCompletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByCompletionNotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completionNotes', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByCompletionNotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completionNotes', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByCoolDown() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coolDown', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByCoolDownDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coolDown', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByDayName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayName', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByDayNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayName', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByDayNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayNumber', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByDayNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayNumber', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByEstimatedDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'estimatedDuration', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByEstimatedDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'estimatedDuration', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByExercisesJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exercisesJson', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByExercisesJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exercisesJson', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByIsCompleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCompleted', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByIsCompletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCompleted', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByLastModifiedLocalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByLastModifiedServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByLastSyncAttemptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByOrderIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'orderIndex', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByOrderIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'orderIndex', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByProgramLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'programLocalId', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByProgramLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'programLocalId', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByProgramServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'programServerId', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByProgramServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'programServerId', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortBySyncError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortBySyncErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortBySyncRetryCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByWarmUp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'warmUp', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByWarmUpDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'warmUp', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByWeekNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weekNumber', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByWeekNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weekNumber', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByWorkoutName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'workoutName', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByWorkoutNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'workoutName', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByWorkoutType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'workoutType', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  sortByWorkoutTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'workoutType', Sort.desc);
    });
  }
}

extension LocalProgramWorkoutQuerySortThenBy
    on QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QSortThenBy> {
  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByCompletedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByCompletionNotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completionNotes', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByCompletionNotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'completionNotes', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByCoolDown() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coolDown', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByCoolDownDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coolDown', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByDayName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayName', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByDayNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayName', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByDayNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayNumber', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByDayNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dayNumber', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByEstimatedDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'estimatedDuration', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByEstimatedDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'estimatedDuration', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByExercisesJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exercisesJson', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByExercisesJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exercisesJson', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByIsCompleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCompleted', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByIsCompletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCompleted', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByLastModifiedLocalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByLastModifiedServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByLastSyncAttemptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByOrderIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'orderIndex', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByOrderIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'orderIndex', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByProgramLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'programLocalId', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByProgramLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'programLocalId', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByProgramServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'programServerId', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByProgramServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'programServerId', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenBySyncError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenBySyncErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenBySyncRetryCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByWarmUp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'warmUp', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByWarmUpDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'warmUp', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByWeekNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weekNumber', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByWeekNumberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'weekNumber', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByWorkoutName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'workoutName', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByWorkoutNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'workoutName', Sort.desc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByWorkoutType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'workoutType', Sort.asc);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QAfterSortBy>
  thenByWorkoutTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'workoutType', Sort.desc);
    });
  }
}

extension LocalProgramWorkoutQueryWhereDistinct
    on QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct> {
  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByCompletedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'completedAt');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByCompletionNotes({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'completionNotes',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByCoolDown({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'coolDown', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByDayName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dayName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByDayNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dayNumber');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByDescription({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'description', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByEstimatedDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'estimatedDuration');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByExercisesJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'exercisesJson',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByIsCompleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isCompleted');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isSynced');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastModifiedLocal');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastModifiedServer');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncAttempt');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByOrderIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'orderIndex');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByProgramLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'programLocalId');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByProgramServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'programServerId');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'serverId');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctBySyncError({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncError', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncRetryCount');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctBySyncStatus({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncStatus', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByWarmUp({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'warmUp', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByWeekNumber() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'weekNumber');
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByWorkoutName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'workoutName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QDistinct>
  distinctByWorkoutType({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'workoutType', caseSensitive: caseSensitive);
    });
  }
}

extension LocalProgramWorkoutQueryProperty
    on QueryBuilder<LocalProgramWorkout, LocalProgramWorkout, QQueryProperty> {
  QueryBuilder<LocalProgramWorkout, int, QQueryOperations> localIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localId');
    });
  }

  QueryBuilder<LocalProgramWorkout, DateTime?, QQueryOperations>
  completedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'completedAt');
    });
  }

  QueryBuilder<LocalProgramWorkout, String?, QQueryOperations>
  completionNotesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'completionNotes');
    });
  }

  QueryBuilder<LocalProgramWorkout, String?, QQueryOperations>
  coolDownProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'coolDown');
    });
  }

  QueryBuilder<LocalProgramWorkout, String?, QQueryOperations>
  dayNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dayName');
    });
  }

  QueryBuilder<LocalProgramWorkout, int, QQueryOperations> dayNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dayNumber');
    });
  }

  QueryBuilder<LocalProgramWorkout, String?, QQueryOperations>
  descriptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'description');
    });
  }

  QueryBuilder<LocalProgramWorkout, int?, QQueryOperations>
  estimatedDurationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'estimatedDuration');
    });
  }

  QueryBuilder<LocalProgramWorkout, String, QQueryOperations>
  exercisesJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'exercisesJson');
    });
  }

  QueryBuilder<LocalProgramWorkout, bool, QQueryOperations>
  isCompletedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isCompleted');
    });
  }

  QueryBuilder<LocalProgramWorkout, bool, QQueryOperations> isSyncedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isSynced');
    });
  }

  QueryBuilder<LocalProgramWorkout, DateTime, QQueryOperations>
  lastModifiedLocalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastModifiedLocal');
    });
  }

  QueryBuilder<LocalProgramWorkout, DateTime?, QQueryOperations>
  lastModifiedServerProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastModifiedServer');
    });
  }

  QueryBuilder<LocalProgramWorkout, DateTime?, QQueryOperations>
  lastSyncAttemptProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncAttempt');
    });
  }

  QueryBuilder<LocalProgramWorkout, int, QQueryOperations>
  orderIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'orderIndex');
    });
  }

  QueryBuilder<LocalProgramWorkout, int, QQueryOperations>
  programLocalIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'programLocalId');
    });
  }

  QueryBuilder<LocalProgramWorkout, int?, QQueryOperations>
  programServerIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'programServerId');
    });
  }

  QueryBuilder<LocalProgramWorkout, int?, QQueryOperations> serverIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'serverId');
    });
  }

  QueryBuilder<LocalProgramWorkout, String?, QQueryOperations>
  syncErrorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncError');
    });
  }

  QueryBuilder<LocalProgramWorkout, int, QQueryOperations>
  syncRetryCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncRetryCount');
    });
  }

  QueryBuilder<LocalProgramWorkout, String, QQueryOperations>
  syncStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncStatus');
    });
  }

  QueryBuilder<LocalProgramWorkout, String?, QQueryOperations>
  warmUpProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'warmUp');
    });
  }

  QueryBuilder<LocalProgramWorkout, int, QQueryOperations>
  weekNumberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'weekNumber');
    });
  }

  QueryBuilder<LocalProgramWorkout, String, QQueryOperations>
  workoutNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'workoutName');
    });
  }

  QueryBuilder<LocalProgramWorkout, String?, QQueryOperations>
  workoutTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'workoutType');
    });
  }
}
