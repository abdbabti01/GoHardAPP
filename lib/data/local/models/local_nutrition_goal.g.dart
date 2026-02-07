// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_nutrition_goal.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalNutritionGoalCollection on Isar {
  IsarCollection<LocalNutritionGoal> get localNutritionGoals =>
      this.collection();
}

const LocalNutritionGoalSchema = CollectionSchema(
  name: r'LocalNutritionGoal',
  id: 5243209746994444450,
  properties: {
    r'bmr': PropertySchema(
      id: 0,
      name: r'bmr',
      type: IsarType.double,
    ),
    r'calorieAdjustment': PropertySchema(
      id: 1,
      name: r'calorieAdjustment',
      type: IsarType.double,
    ),
    r'carbohydratesPercentage': PropertySchema(
      id: 2,
      name: r'carbohydratesPercentage',
      type: IsarType.double,
    ),
    r'createdAt': PropertySchema(
      id: 3,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'dailyCalories': PropertySchema(
      id: 4,
      name: r'dailyCalories',
      type: IsarType.double,
    ),
    r'dailyCarbohydrates': PropertySchema(
      id: 5,
      name: r'dailyCarbohydrates',
      type: IsarType.double,
    ),
    r'dailyFat': PropertySchema(
      id: 6,
      name: r'dailyFat',
      type: IsarType.double,
    ),
    r'dailyFiber': PropertySchema(
      id: 7,
      name: r'dailyFiber',
      type: IsarType.double,
    ),
    r'dailyProtein': PropertySchema(
      id: 8,
      name: r'dailyProtein',
      type: IsarType.double,
    ),
    r'dailySodium': PropertySchema(
      id: 9,
      name: r'dailySodium',
      type: IsarType.double,
    ),
    r'dailySugar': PropertySchema(
      id: 10,
      name: r'dailySugar',
      type: IsarType.double,
    ),
    r'dailyWater': PropertySchema(
      id: 11,
      name: r'dailyWater',
      type: IsarType.double,
    ),
    r'explanation': PropertySchema(
      id: 12,
      name: r'explanation',
      type: IsarType.string,
    ),
    r'fatPercentage': PropertySchema(
      id: 13,
      name: r'fatPercentage',
      type: IsarType.double,
    ),
    r'isActive': PropertySchema(
      id: 14,
      name: r'isActive',
      type: IsarType.bool,
    ),
    r'isSynced': PropertySchema(
      id: 15,
      name: r'isSynced',
      type: IsarType.bool,
    ),
    r'lastModifiedLocal': PropertySchema(
      id: 16,
      name: r'lastModifiedLocal',
      type: IsarType.dateTime,
    ),
    r'lastModifiedServer': PropertySchema(
      id: 17,
      name: r'lastModifiedServer',
      type: IsarType.dateTime,
    ),
    r'lastSyncAttempt': PropertySchema(
      id: 18,
      name: r'lastSyncAttempt',
      type: IsarType.dateTime,
    ),
    r'name': PropertySchema(
      id: 19,
      name: r'name',
      type: IsarType.string,
    ),
    r'proteinPercentage': PropertySchema(
      id: 20,
      name: r'proteinPercentage',
      type: IsarType.double,
    ),
    r'serverId': PropertySchema(
      id: 21,
      name: r'serverId',
      type: IsarType.long,
    ),
    r'syncError': PropertySchema(
      id: 22,
      name: r'syncError',
      type: IsarType.string,
    ),
    r'syncRetryCount': PropertySchema(
      id: 23,
      name: r'syncRetryCount',
      type: IsarType.long,
    ),
    r'syncStatus': PropertySchema(
      id: 24,
      name: r'syncStatus',
      type: IsarType.string,
    ),
    r'tdee': PropertySchema(
      id: 25,
      name: r'tdee',
      type: IsarType.double,
    ),
    r'updatedAt': PropertySchema(
      id: 26,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'userId': PropertySchema(
      id: 27,
      name: r'userId',
      type: IsarType.long,
    )
  },
  estimateSize: _localNutritionGoalEstimateSize,
  serialize: _localNutritionGoalSerialize,
  deserialize: _localNutritionGoalDeserialize,
  deserializeProp: _localNutritionGoalDeserializeProp,
  idName: r'localId',
  indexes: {
    r'userId': IndexSchema(
      id: -2005826577402374815,
      name: r'userId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'userId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'isActive': IndexSchema(
      id: 8092228061260947457,
      name: r'isActive',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'isActive',
          type: IndexType.value,
          caseSensitive: false,
        )
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
        )
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
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _localNutritionGoalGetId,
  getLinks: _localNutritionGoalGetLinks,
  attach: _localNutritionGoalAttach,
  version: '3.1.0+1',
);

int _localNutritionGoalEstimateSize(
  LocalNutritionGoal object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.explanation;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.name;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.syncError;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.syncStatus.length * 3;
  return bytesCount;
}

void _localNutritionGoalSerialize(
  LocalNutritionGoal object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDouble(offsets[0], object.bmr);
  writer.writeDouble(offsets[1], object.calorieAdjustment);
  writer.writeDouble(offsets[2], object.carbohydratesPercentage);
  writer.writeDateTime(offsets[3], object.createdAt);
  writer.writeDouble(offsets[4], object.dailyCalories);
  writer.writeDouble(offsets[5], object.dailyCarbohydrates);
  writer.writeDouble(offsets[6], object.dailyFat);
  writer.writeDouble(offsets[7], object.dailyFiber);
  writer.writeDouble(offsets[8], object.dailyProtein);
  writer.writeDouble(offsets[9], object.dailySodium);
  writer.writeDouble(offsets[10], object.dailySugar);
  writer.writeDouble(offsets[11], object.dailyWater);
  writer.writeString(offsets[12], object.explanation);
  writer.writeDouble(offsets[13], object.fatPercentage);
  writer.writeBool(offsets[14], object.isActive);
  writer.writeBool(offsets[15], object.isSynced);
  writer.writeDateTime(offsets[16], object.lastModifiedLocal);
  writer.writeDateTime(offsets[17], object.lastModifiedServer);
  writer.writeDateTime(offsets[18], object.lastSyncAttempt);
  writer.writeString(offsets[19], object.name);
  writer.writeDouble(offsets[20], object.proteinPercentage);
  writer.writeLong(offsets[21], object.serverId);
  writer.writeString(offsets[22], object.syncError);
  writer.writeLong(offsets[23], object.syncRetryCount);
  writer.writeString(offsets[24], object.syncStatus);
  writer.writeDouble(offsets[25], object.tdee);
  writer.writeDateTime(offsets[26], object.updatedAt);
  writer.writeLong(offsets[27], object.userId);
}

LocalNutritionGoal _localNutritionGoalDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalNutritionGoal(
    bmr: reader.readDoubleOrNull(offsets[0]),
    calorieAdjustment: reader.readDoubleOrNull(offsets[1]),
    carbohydratesPercentage: reader.readDoubleOrNull(offsets[2]),
    createdAt: reader.readDateTime(offsets[3]),
    dailyCalories: reader.readDoubleOrNull(offsets[4]) ?? 0,
    dailyCarbohydrates: reader.readDoubleOrNull(offsets[5]) ?? 0,
    dailyFat: reader.readDoubleOrNull(offsets[6]) ?? 0,
    dailyFiber: reader.readDoubleOrNull(offsets[7]),
    dailyProtein: reader.readDoubleOrNull(offsets[8]) ?? 0,
    dailySodium: reader.readDoubleOrNull(offsets[9]),
    dailySugar: reader.readDoubleOrNull(offsets[10]),
    dailyWater: reader.readDoubleOrNull(offsets[11]),
    explanation: reader.readStringOrNull(offsets[12]),
    fatPercentage: reader.readDoubleOrNull(offsets[13]),
    isActive: reader.readBoolOrNull(offsets[14]) ?? true,
    isSynced: reader.readBoolOrNull(offsets[15]) ?? false,
    lastModifiedLocal: reader.readDateTime(offsets[16]),
    lastModifiedServer: reader.readDateTimeOrNull(offsets[17]),
    lastSyncAttempt: reader.readDateTimeOrNull(offsets[18]),
    name: reader.readStringOrNull(offsets[19]),
    proteinPercentage: reader.readDoubleOrNull(offsets[20]),
    serverId: reader.readLongOrNull(offsets[21]),
    syncError: reader.readStringOrNull(offsets[22]),
    syncRetryCount: reader.readLongOrNull(offsets[23]) ?? 0,
    syncStatus: reader.readStringOrNull(offsets[24]) ?? 'pending_create',
    tdee: reader.readDoubleOrNull(offsets[25]),
    updatedAt: reader.readDateTimeOrNull(offsets[26]),
    userId: reader.readLong(offsets[27]),
  );
  object.localId = id;
  return object;
}

P _localNutritionGoalDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDoubleOrNull(offset)) as P;
    case 1:
      return (reader.readDoubleOrNull(offset)) as P;
    case 2:
      return (reader.readDoubleOrNull(offset)) as P;
    case 3:
      return (reader.readDateTime(offset)) as P;
    case 4:
      return (reader.readDoubleOrNull(offset) ?? 0) as P;
    case 5:
      return (reader.readDoubleOrNull(offset) ?? 0) as P;
    case 6:
      return (reader.readDoubleOrNull(offset) ?? 0) as P;
    case 7:
      return (reader.readDoubleOrNull(offset)) as P;
    case 8:
      return (reader.readDoubleOrNull(offset) ?? 0) as P;
    case 9:
      return (reader.readDoubleOrNull(offset)) as P;
    case 10:
      return (reader.readDoubleOrNull(offset)) as P;
    case 11:
      return (reader.readDoubleOrNull(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readDoubleOrNull(offset)) as P;
    case 14:
      return (reader.readBoolOrNull(offset) ?? true) as P;
    case 15:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 16:
      return (reader.readDateTime(offset)) as P;
    case 17:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 18:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 19:
      return (reader.readStringOrNull(offset)) as P;
    case 20:
      return (reader.readDoubleOrNull(offset)) as P;
    case 21:
      return (reader.readLongOrNull(offset)) as P;
    case 22:
      return (reader.readStringOrNull(offset)) as P;
    case 23:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 24:
      return (reader.readStringOrNull(offset) ?? 'pending_create') as P;
    case 25:
      return (reader.readDoubleOrNull(offset)) as P;
    case 26:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 27:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localNutritionGoalGetId(LocalNutritionGoal object) {
  return object.localId;
}

List<IsarLinkBase<dynamic>> _localNutritionGoalGetLinks(
    LocalNutritionGoal object) {
  return [];
}

void _localNutritionGoalAttach(
    IsarCollection<dynamic> col, Id id, LocalNutritionGoal object) {
  object.localId = id;
}

extension LocalNutritionGoalQueryWhereSort
    on QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QWhere> {
  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhere>
      anyLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhere>
      anyUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'userId'),
      );
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhere>
      anyIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isActive'),
      );
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhere>
      anyIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isSynced'),
      );
    });
  }
}

extension LocalNutritionGoalQueryWhere
    on QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QWhereClause> {
  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      localIdEqualTo(Id localId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: localId,
        upper: localId,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
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

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      localIdGreaterThan(Id localId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: localId, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      localIdLessThan(Id localId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: localId, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      localIdBetween(
    Id lowerLocalId,
    Id upperLocalId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerLocalId,
        includeLower: includeLower,
        upper: upperLocalId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      userIdEqualTo(int userId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'userId',
        value: [userId],
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      userIdNotEqualTo(int userId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userId',
              lower: [],
              upper: [userId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userId',
              lower: [userId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userId',
              lower: [userId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'userId',
              lower: [],
              upper: [userId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      userIdGreaterThan(
    int userId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'userId',
        lower: [userId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      userIdLessThan(
    int userId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'userId',
        lower: [],
        upper: [userId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      userIdBetween(
    int lowerUserId,
    int upperUserId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'userId',
        lower: [lowerUserId],
        includeLower: includeLower,
        upper: [upperUserId],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      isActiveEqualTo(bool isActive) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'isActive',
        value: [isActive],
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      isActiveNotEqualTo(bool isActive) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isActive',
              lower: [],
              upper: [isActive],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isActive',
              lower: [isActive],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isActive',
              lower: [isActive],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isActive',
              lower: [],
              upper: [isActive],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      isSyncedEqualTo(bool isSynced) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'isSynced',
        value: [isSynced],
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      isSyncedNotEqualTo(bool isSynced) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isSynced',
              lower: [],
              upper: [isSynced],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isSynced',
              lower: [isSynced],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isSynced',
              lower: [isSynced],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isSynced',
              lower: [],
              upper: [isSynced],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      syncStatusEqualTo(String syncStatus) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'syncStatus',
        value: [syncStatus],
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterWhereClause>
      syncStatusNotEqualTo(String syncStatus) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'syncStatus',
              lower: [],
              upper: [syncStatus],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'syncStatus',
              lower: [syncStatus],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'syncStatus',
              lower: [syncStatus],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'syncStatus',
              lower: [],
              upper: [syncStatus],
              includeUpper: false,
            ));
      }
    });
  }
}

extension LocalNutritionGoalQueryFilter
    on QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QFilterCondition> {
  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      bmrIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'bmr',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      bmrIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'bmr',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      bmrEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bmr',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      bmrGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'bmr',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      bmrLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'bmr',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      bmrBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'bmr',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      calorieAdjustmentIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'calorieAdjustment',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      calorieAdjustmentIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'calorieAdjustment',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      calorieAdjustmentEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'calorieAdjustment',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      calorieAdjustmentGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'calorieAdjustment',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      calorieAdjustmentLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'calorieAdjustment',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      calorieAdjustmentBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'calorieAdjustment',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      carbohydratesPercentageIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'carbohydratesPercentage',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      carbohydratesPercentageIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'carbohydratesPercentage',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      carbohydratesPercentageEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'carbohydratesPercentage',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      carbohydratesPercentageGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'carbohydratesPercentage',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      carbohydratesPercentageLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'carbohydratesPercentage',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      carbohydratesPercentageBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'carbohydratesPercentage',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyCaloriesEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dailyCalories',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyCaloriesGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dailyCalories',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyCaloriesLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dailyCalories',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyCaloriesBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dailyCalories',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyCarbohydratesEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dailyCarbohydrates',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyCarbohydratesGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dailyCarbohydrates',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyCarbohydratesLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dailyCarbohydrates',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyCarbohydratesBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dailyCarbohydrates',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFatEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dailyFat',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFatGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dailyFat',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFatLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dailyFat',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFatBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dailyFat',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFiberIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'dailyFiber',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFiberIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'dailyFiber',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFiberEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dailyFiber',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFiberGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dailyFiber',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFiberLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dailyFiber',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyFiberBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dailyFiber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyProteinEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dailyProtein',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyProteinGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dailyProtein',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyProteinLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dailyProtein',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyProteinBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dailyProtein',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySodiumIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'dailySodium',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySodiumIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'dailySodium',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySodiumEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dailySodium',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySodiumGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dailySodium',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySodiumLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dailySodium',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySodiumBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dailySodium',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySugarIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'dailySugar',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySugarIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'dailySugar',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySugarEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dailySugar',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySugarGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dailySugar',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySugarLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dailySugar',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailySugarBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dailySugar',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyWaterIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'dailyWater',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyWaterIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'dailyWater',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyWaterEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dailyWater',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyWaterGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dailyWater',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyWaterLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dailyWater',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      dailyWaterBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dailyWater',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'explanation',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'explanation',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'explanation',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'explanation',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'explanation',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'explanation',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'explanation',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'explanation',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'explanation',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'explanation',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'explanation',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      explanationIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'explanation',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      fatPercentageIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'fatPercentage',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      fatPercentageIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'fatPercentage',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      fatPercentageEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'fatPercentage',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      fatPercentageGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'fatPercentage',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      fatPercentageLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'fatPercentage',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      fatPercentageBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'fatPercentage',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      isActiveEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isActive',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      isSyncedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isSynced',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedLocalEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastModifiedLocal',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedLocalGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastModifiedLocal',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedLocalLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastModifiedLocal',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedLocalBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastModifiedLocal',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedServerIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastModifiedServer',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedServerIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastModifiedServer',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedServerEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastModifiedServer',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedServerGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastModifiedServer',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedServerLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastModifiedServer',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastModifiedServerBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastModifiedServer',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastSyncAttemptIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastSyncAttempt',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastSyncAttemptIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastSyncAttempt',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastSyncAttemptEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastSyncAttempt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastSyncAttemptGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastSyncAttempt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastSyncAttemptLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastSyncAttempt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      lastSyncAttemptBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastSyncAttempt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      localIdEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      localIdGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'localId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      localIdLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'localId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      localIdBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'localId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'name',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'name',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      proteinPercentageIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'proteinPercentage',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      proteinPercentageIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'proteinPercentage',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      proteinPercentageEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'proteinPercentage',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      proteinPercentageGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'proteinPercentage',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      proteinPercentageLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'proteinPercentage',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      proteinPercentageBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'proteinPercentage',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      serverIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'serverId',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      serverIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'serverId',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      serverIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'serverId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      serverIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'serverId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      serverIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'serverId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      serverIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'serverId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'syncError',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'syncError',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'syncError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'syncError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'syncError',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'syncError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'syncError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'syncError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'syncError',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncError',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncErrorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'syncError',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncRetryCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncRetryCount',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncRetryCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'syncRetryCount',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncRetryCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'syncRetryCount',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncRetryCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'syncRetryCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncStatus',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'syncStatus',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'syncStatus',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'syncStatus',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'syncStatus',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'syncStatus',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'syncStatus',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'syncStatus',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncStatus',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      syncStatusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'syncStatus',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      tdeeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'tdee',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      tdeeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'tdee',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      tdeeEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tdee',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      tdeeGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tdee',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      tdeeLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tdee',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      tdeeBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tdee',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      updatedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'updatedAt',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      updatedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'updatedAt',
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      updatedAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      updatedAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      updatedAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      updatedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      userIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'userId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      userIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'userId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      userIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'userId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterFilterCondition>
      userIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'userId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension LocalNutritionGoalQueryObject
    on QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QFilterCondition> {}

extension LocalNutritionGoalQueryLinks
    on QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QFilterCondition> {}

extension LocalNutritionGoalQuerySortBy
    on QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QSortBy> {
  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByBmr() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bmr', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByBmrDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bmr', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByCalorieAdjustment() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'calorieAdjustment', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByCalorieAdjustmentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'calorieAdjustment', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByCarbohydratesPercentage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carbohydratesPercentage', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByCarbohydratesPercentageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carbohydratesPercentage', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyCalories() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyCalories', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyCaloriesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyCalories', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyCarbohydrates() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyCarbohydrates', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyCarbohydratesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyCarbohydrates', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyFat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyFat', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyFatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyFat', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyFiber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyFiber', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyFiberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyFiber', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyProtein() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyProtein', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyProteinDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyProtein', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailySodium() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailySodium', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailySodiumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailySodium', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailySugar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailySugar', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailySugarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailySugar', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyWater() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyWater', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByDailyWaterDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyWater', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByExplanation() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'explanation', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByExplanationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'explanation', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByFatPercentage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fatPercentage', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByFatPercentageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fatPercentage', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByIsActiveDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByLastModifiedLocalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByLastModifiedServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByLastSyncAttemptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByProteinPercentage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proteinPercentage', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByProteinPercentageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proteinPercentage', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortBySyncError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortBySyncErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortBySyncRetryCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByTdee() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tdee', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByTdeeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tdee', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      sortByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }
}

extension LocalNutritionGoalQuerySortThenBy
    on QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QSortThenBy> {
  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByBmr() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bmr', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByBmrDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bmr', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByCalorieAdjustment() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'calorieAdjustment', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByCalorieAdjustmentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'calorieAdjustment', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByCarbohydratesPercentage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carbohydratesPercentage', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByCarbohydratesPercentageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carbohydratesPercentage', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyCalories() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyCalories', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyCaloriesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyCalories', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyCarbohydrates() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyCarbohydrates', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyCarbohydratesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyCarbohydrates', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyFat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyFat', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyFatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyFat', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyFiber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyFiber', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyFiberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyFiber', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyProtein() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyProtein', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyProteinDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyProtein', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailySodium() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailySodium', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailySodiumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailySodium', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailySugar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailySugar', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailySugarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailySugar', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyWater() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyWater', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByDailyWaterDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dailyWater', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByExplanation() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'explanation', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByExplanationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'explanation', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByFatPercentage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fatPercentage', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByFatPercentageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fatPercentage', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByIsActiveDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByLastModifiedLocalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByLastModifiedServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByLastSyncAttemptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByProteinPercentage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proteinPercentage', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByProteinPercentageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'proteinPercentage', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenBySyncError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenBySyncErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenBySyncRetryCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByTdee() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tdee', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByTdeeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tdee', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.asc);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QAfterSortBy>
      thenByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'userId', Sort.desc);
    });
  }
}

extension LocalNutritionGoalQueryWhereDistinct
    on QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct> {
  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByBmr() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bmr');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByCalorieAdjustment() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'calorieAdjustment');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByCarbohydratesPercentage() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'carbohydratesPercentage');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByDailyCalories() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dailyCalories');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByDailyCarbohydrates() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dailyCarbohydrates');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByDailyFat() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dailyFat');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByDailyFiber() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dailyFiber');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByDailyProtein() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dailyProtein');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByDailySodium() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dailySodium');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByDailySugar() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dailySugar');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByDailyWater() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dailyWater');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByExplanation({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'explanation', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByFatPercentage() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'fatPercentage');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isActive');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isSynced');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastModifiedLocal');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastModifiedServer');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncAttempt');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByProteinPercentage() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'proteinPercentage');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'serverId');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctBySyncError({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncError', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncRetryCount');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctBySyncStatus({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncStatus', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByTdee() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tdee');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QDistinct>
      distinctByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'userId');
    });
  }
}

extension LocalNutritionGoalQueryProperty
    on QueryBuilder<LocalNutritionGoal, LocalNutritionGoal, QQueryProperty> {
  QueryBuilder<LocalNutritionGoal, int, QQueryOperations> localIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localId');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations> bmrProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bmr');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations>
      calorieAdjustmentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'calorieAdjustment');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations>
      carbohydratesPercentageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'carbohydratesPercentage');
    });
  }

  QueryBuilder<LocalNutritionGoal, DateTime, QQueryOperations>
      createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<LocalNutritionGoal, double, QQueryOperations>
      dailyCaloriesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dailyCalories');
    });
  }

  QueryBuilder<LocalNutritionGoal, double, QQueryOperations>
      dailyCarbohydratesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dailyCarbohydrates');
    });
  }

  QueryBuilder<LocalNutritionGoal, double, QQueryOperations>
      dailyFatProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dailyFat');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations>
      dailyFiberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dailyFiber');
    });
  }

  QueryBuilder<LocalNutritionGoal, double, QQueryOperations>
      dailyProteinProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dailyProtein');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations>
      dailySodiumProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dailySodium');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations>
      dailySugarProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dailySugar');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations>
      dailyWaterProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dailyWater');
    });
  }

  QueryBuilder<LocalNutritionGoal, String?, QQueryOperations>
      explanationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'explanation');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations>
      fatPercentageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'fatPercentage');
    });
  }

  QueryBuilder<LocalNutritionGoal, bool, QQueryOperations> isActiveProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isActive');
    });
  }

  QueryBuilder<LocalNutritionGoal, bool, QQueryOperations> isSyncedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isSynced');
    });
  }

  QueryBuilder<LocalNutritionGoal, DateTime, QQueryOperations>
      lastModifiedLocalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastModifiedLocal');
    });
  }

  QueryBuilder<LocalNutritionGoal, DateTime?, QQueryOperations>
      lastModifiedServerProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastModifiedServer');
    });
  }

  QueryBuilder<LocalNutritionGoal, DateTime?, QQueryOperations>
      lastSyncAttemptProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncAttempt');
    });
  }

  QueryBuilder<LocalNutritionGoal, String?, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations>
      proteinPercentageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'proteinPercentage');
    });
  }

  QueryBuilder<LocalNutritionGoal, int?, QQueryOperations> serverIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'serverId');
    });
  }

  QueryBuilder<LocalNutritionGoal, String?, QQueryOperations>
      syncErrorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncError');
    });
  }

  QueryBuilder<LocalNutritionGoal, int, QQueryOperations>
      syncRetryCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncRetryCount');
    });
  }

  QueryBuilder<LocalNutritionGoal, String, QQueryOperations>
      syncStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncStatus');
    });
  }

  QueryBuilder<LocalNutritionGoal, double?, QQueryOperations> tdeeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tdee');
    });
  }

  QueryBuilder<LocalNutritionGoal, DateTime?, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<LocalNutritionGoal, int, QQueryOperations> userIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'userId');
    });
  }
}
