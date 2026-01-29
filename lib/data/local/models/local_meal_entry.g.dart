// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_meal_entry.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalMealEntryCollection on Isar {
  IsarCollection<LocalMealEntry> get localMealEntrys => this.collection();
}

const LocalMealEntrySchema = CollectionSchema(
  name: r'LocalMealEntry',
  id: 4944937046980804178,
  properties: {
    r'consumedAt': PropertySchema(
      id: 0,
      name: r'consumedAt',
      type: IsarType.dateTime,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'isConsumed': PropertySchema(
      id: 2,
      name: r'isConsumed',
      type: IsarType.bool,
    ),
    r'isSynced': PropertySchema(id: 3, name: r'isSynced', type: IsarType.bool),
    r'lastModifiedLocal': PropertySchema(
      id: 4,
      name: r'lastModifiedLocal',
      type: IsarType.dateTime,
    ),
    r'lastModifiedServer': PropertySchema(
      id: 5,
      name: r'lastModifiedServer',
      type: IsarType.dateTime,
    ),
    r'lastSyncAttempt': PropertySchema(
      id: 6,
      name: r'lastSyncAttempt',
      type: IsarType.dateTime,
    ),
    r'mealLogLocalId': PropertySchema(
      id: 7,
      name: r'mealLogLocalId',
      type: IsarType.long,
    ),
    r'mealLogServerId': PropertySchema(
      id: 8,
      name: r'mealLogServerId',
      type: IsarType.long,
    ),
    r'mealType': PropertySchema(
      id: 9,
      name: r'mealType',
      type: IsarType.string,
    ),
    r'name': PropertySchema(id: 10, name: r'name', type: IsarType.string),
    r'notes': PropertySchema(id: 11, name: r'notes', type: IsarType.string),
    r'scheduledTime': PropertySchema(
      id: 12,
      name: r'scheduledTime',
      type: IsarType.dateTime,
    ),
    r'serverId': PropertySchema(id: 13, name: r'serverId', type: IsarType.long),
    r'syncError': PropertySchema(
      id: 14,
      name: r'syncError',
      type: IsarType.string,
    ),
    r'syncRetryCount': PropertySchema(
      id: 15,
      name: r'syncRetryCount',
      type: IsarType.long,
    ),
    r'syncStatus': PropertySchema(
      id: 16,
      name: r'syncStatus',
      type: IsarType.string,
    ),
    r'totalCalories': PropertySchema(
      id: 17,
      name: r'totalCalories',
      type: IsarType.double,
    ),
    r'totalCarbohydrates': PropertySchema(
      id: 18,
      name: r'totalCarbohydrates',
      type: IsarType.double,
    ),
    r'totalFat': PropertySchema(
      id: 19,
      name: r'totalFat',
      type: IsarType.double,
    ),
    r'totalFiber': PropertySchema(
      id: 20,
      name: r'totalFiber',
      type: IsarType.double,
    ),
    r'totalProtein': PropertySchema(
      id: 21,
      name: r'totalProtein',
      type: IsarType.double,
    ),
    r'totalSodium': PropertySchema(
      id: 22,
      name: r'totalSodium',
      type: IsarType.double,
    ),
    r'updatedAt': PropertySchema(
      id: 23,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
  },
  estimateSize: _localMealEntryEstimateSize,
  serialize: _localMealEntrySerialize,
  deserialize: _localMealEntryDeserialize,
  deserializeProp: _localMealEntryDeserializeProp,
  idName: r'localId',
  indexes: {
    r'mealLogLocalId': IndexSchema(
      id: -8353227398655238441,
      name: r'mealLogLocalId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'mealLogLocalId',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'mealType': IndexSchema(
      id: -959027890258449294,
      name: r'mealType',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'mealType',
          type: IndexType.hash,
          caseSensitive: true,
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
  getId: _localMealEntryGetId,
  getLinks: _localMealEntryGetLinks,
  attach: _localMealEntryAttach,
  version: '3.1.0+1',
);

int _localMealEntryEstimateSize(
  LocalMealEntry object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.mealType.length * 3;
  {
    final value = object.name;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.notes;
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

void _localMealEntrySerialize(
  LocalMealEntry object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.consumedAt);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeBool(offsets[2], object.isConsumed);
  writer.writeBool(offsets[3], object.isSynced);
  writer.writeDateTime(offsets[4], object.lastModifiedLocal);
  writer.writeDateTime(offsets[5], object.lastModifiedServer);
  writer.writeDateTime(offsets[6], object.lastSyncAttempt);
  writer.writeLong(offsets[7], object.mealLogLocalId);
  writer.writeLong(offsets[8], object.mealLogServerId);
  writer.writeString(offsets[9], object.mealType);
  writer.writeString(offsets[10], object.name);
  writer.writeString(offsets[11], object.notes);
  writer.writeDateTime(offsets[12], object.scheduledTime);
  writer.writeLong(offsets[13], object.serverId);
  writer.writeString(offsets[14], object.syncError);
  writer.writeLong(offsets[15], object.syncRetryCount);
  writer.writeString(offsets[16], object.syncStatus);
  writer.writeDouble(offsets[17], object.totalCalories);
  writer.writeDouble(offsets[18], object.totalCarbohydrates);
  writer.writeDouble(offsets[19], object.totalFat);
  writer.writeDouble(offsets[20], object.totalFiber);
  writer.writeDouble(offsets[21], object.totalProtein);
  writer.writeDouble(offsets[22], object.totalSodium);
  writer.writeDateTime(offsets[23], object.updatedAt);
}

LocalMealEntry _localMealEntryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalMealEntry(
    consumedAt: reader.readDateTimeOrNull(offsets[0]),
    createdAt: reader.readDateTime(offsets[1]),
    isConsumed: reader.readBoolOrNull(offsets[2]) ?? false,
    isSynced: reader.readBoolOrNull(offsets[3]) ?? false,
    lastModifiedLocal: reader.readDateTime(offsets[4]),
    lastModifiedServer: reader.readDateTimeOrNull(offsets[5]),
    lastSyncAttempt: reader.readDateTimeOrNull(offsets[6]),
    mealLogLocalId: reader.readLong(offsets[7]),
    mealLogServerId: reader.readLongOrNull(offsets[8]),
    mealType: reader.readStringOrNull(offsets[9]) ?? 'Snack',
    name: reader.readStringOrNull(offsets[10]),
    notes: reader.readStringOrNull(offsets[11]),
    scheduledTime: reader.readDateTimeOrNull(offsets[12]),
    serverId: reader.readLongOrNull(offsets[13]),
    syncError: reader.readStringOrNull(offsets[14]),
    syncRetryCount: reader.readLongOrNull(offsets[15]) ?? 0,
    syncStatus: reader.readStringOrNull(offsets[16]) ?? 'pending_create',
    totalCalories: reader.readDoubleOrNull(offsets[17]) ?? 0,
    totalCarbohydrates: reader.readDoubleOrNull(offsets[18]) ?? 0,
    totalFat: reader.readDoubleOrNull(offsets[19]) ?? 0,
    totalFiber: reader.readDoubleOrNull(offsets[20]),
    totalProtein: reader.readDoubleOrNull(offsets[21]) ?? 0,
    totalSodium: reader.readDoubleOrNull(offsets[22]),
    updatedAt: reader.readDateTimeOrNull(offsets[23]),
  );
  object.localId = id;
  return object;
}

P _localMealEntryDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 3:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 4:
      return (reader.readDateTime(offset)) as P;
    case 5:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 6:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 7:
      return (reader.readLong(offset)) as P;
    case 8:
      return (reader.readLongOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset) ?? 'Snack') as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 13:
      return (reader.readLongOrNull(offset)) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 16:
      return (reader.readStringOrNull(offset) ?? 'pending_create') as P;
    case 17:
      return (reader.readDoubleOrNull(offset) ?? 0) as P;
    case 18:
      return (reader.readDoubleOrNull(offset) ?? 0) as P;
    case 19:
      return (reader.readDoubleOrNull(offset) ?? 0) as P;
    case 20:
      return (reader.readDoubleOrNull(offset)) as P;
    case 21:
      return (reader.readDoubleOrNull(offset) ?? 0) as P;
    case 22:
      return (reader.readDoubleOrNull(offset)) as P;
    case 23:
      return (reader.readDateTimeOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localMealEntryGetId(LocalMealEntry object) {
  return object.localId;
}

List<IsarLinkBase<dynamic>> _localMealEntryGetLinks(LocalMealEntry object) {
  return [];
}

void _localMealEntryAttach(
  IsarCollection<dynamic> col,
  Id id,
  LocalMealEntry object,
) {
  object.localId = id;
}

extension LocalMealEntryQueryWhereSort
    on QueryBuilder<LocalMealEntry, LocalMealEntry, QWhere> {
  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhere> anyLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhere>
  anyMealLogLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'mealLogLocalId'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhere> anyIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isSynced'),
      );
    });
  }
}

extension LocalMealEntryQueryWhere
    on QueryBuilder<LocalMealEntry, LocalMealEntry, QWhereClause> {
  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  localIdEqualTo(Id localId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(lower: localId, upper: localId),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  localIdGreaterThan(Id localId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: localId, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  localIdLessThan(Id localId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: localId, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  mealLogLocalIdEqualTo(int mealLogLocalId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'mealLogLocalId',
          value: [mealLogLocalId],
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  mealLogLocalIdNotEqualTo(int mealLogLocalId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mealLogLocalId',
                lower: [],
                upper: [mealLogLocalId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mealLogLocalId',
                lower: [mealLogLocalId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mealLogLocalId',
                lower: [mealLogLocalId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mealLogLocalId',
                lower: [],
                upper: [mealLogLocalId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  mealLogLocalIdGreaterThan(int mealLogLocalId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'mealLogLocalId',
          lower: [mealLogLocalId],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  mealLogLocalIdLessThan(int mealLogLocalId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'mealLogLocalId',
          lower: [],
          upper: [mealLogLocalId],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  mealLogLocalIdBetween(
    int lowerMealLogLocalId,
    int upperMealLogLocalId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'mealLogLocalId',
          lower: [lowerMealLogLocalId],
          includeLower: includeLower,
          upper: [upperMealLogLocalId],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  mealTypeEqualTo(String mealType) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'mealType', value: [mealType]),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  mealTypeNotEqualTo(String mealType) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mealType',
                lower: [],
                upper: [mealType],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mealType',
                lower: [mealType],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mealType',
                lower: [mealType],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'mealType',
                lower: [],
                upper: [mealType],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  isSyncedEqualTo(bool isSynced) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'isSynced', value: [isSynced]),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
  syncStatusEqualTo(String syncStatus) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'syncStatus', value: [syncStatus]),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterWhereClause>
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

extension LocalMealEntryQueryFilter
    on QueryBuilder<LocalMealEntry, LocalMealEntry, QFilterCondition> {
  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  consumedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'consumedAt'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  consumedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'consumedAt'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  consumedAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'consumedAt', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  consumedAtGreaterThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'consumedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  consumedAtLessThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'consumedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  consumedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'consumedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  createdAtGreaterThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  createdAtLessThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  isConsumedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isConsumed', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  isSyncedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isSynced', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  lastModifiedLocalEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastModifiedLocal', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  lastModifiedServerIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastModifiedServer'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  lastModifiedServerIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastModifiedServer'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  lastModifiedServerEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastModifiedServer', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  lastSyncAttemptIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastSyncAttempt'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  lastSyncAttemptIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastSyncAttempt'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  lastSyncAttemptEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastSyncAttempt', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  localIdEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'localId', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogLocalIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mealLogLocalId', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogLocalIdGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mealLogLocalId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogLocalIdLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mealLogLocalId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogLocalIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mealLogLocalId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogServerIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'mealLogServerId'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogServerIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'mealLogServerId'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogServerIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mealLogServerId', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogServerIdGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mealLogServerId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogServerIdLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mealLogServerId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealLogServerIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mealLogServerId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mealType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mealType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mealType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mealType',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mealType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mealType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mealType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mealType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mealType', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  mealTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mealType', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'name'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'name'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'name',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'name',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'notes'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'notes'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'notes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'notes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'notes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'notes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'notes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'notes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'notes',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'notes',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'notes', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  notesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'notes', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  scheduledTimeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'scheduledTime'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  scheduledTimeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'scheduledTime'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  scheduledTimeEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'scheduledTime', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  scheduledTimeGreaterThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'scheduledTime',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  scheduledTimeLessThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'scheduledTime',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  scheduledTimeBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'scheduledTime',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  serverIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'serverId'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  serverIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'serverId'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  serverIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'serverId', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  syncErrorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'syncError'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  syncErrorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'syncError'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  syncErrorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'syncError', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  syncErrorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'syncError', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  syncRetryCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'syncRetryCount', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
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

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  syncStatusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'syncStatus', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  syncStatusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'syncStatus', value: ''),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalCaloriesEqualTo(double value, {double epsilon = Query.epsilon}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'totalCalories',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalCaloriesGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'totalCalories',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalCaloriesLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'totalCalories',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalCaloriesBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'totalCalories',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalCarbohydratesEqualTo(double value, {double epsilon = Query.epsilon}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'totalCarbohydrates',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalCarbohydratesGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'totalCarbohydrates',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalCarbohydratesLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'totalCarbohydrates',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalCarbohydratesBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'totalCarbohydrates',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFatEqualTo(double value, {double epsilon = Query.epsilon}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'totalFat',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFatGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'totalFat',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFatLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'totalFat',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFatBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'totalFat',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFiberIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'totalFiber'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFiberIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'totalFiber'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFiberEqualTo(double? value, {double epsilon = Query.epsilon}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'totalFiber',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFiberGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'totalFiber',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFiberLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'totalFiber',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalFiberBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'totalFiber',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalProteinEqualTo(double value, {double epsilon = Query.epsilon}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'totalProtein',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalProteinGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'totalProtein',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalProteinLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'totalProtein',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalProteinBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'totalProtein',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalSodiumIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'totalSodium'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalSodiumIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'totalSodium'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalSodiumEqualTo(double? value, {double epsilon = Query.epsilon}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'totalSodium',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalSodiumGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'totalSodium',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalSodiumLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'totalSodium',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  totalSodiumBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'totalSodium',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  updatedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'updatedAt'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  updatedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'updatedAt'),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  updatedAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'updatedAt', value: value),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  updatedAtGreaterThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  updatedAtLessThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterFilterCondition>
  updatedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'updatedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension LocalMealEntryQueryObject
    on QueryBuilder<LocalMealEntry, LocalMealEntry, QFilterCondition> {}

extension LocalMealEntryQueryLinks
    on QueryBuilder<LocalMealEntry, LocalMealEntry, QFilterCondition> {}

extension LocalMealEntryQuerySortBy
    on QueryBuilder<LocalMealEntry, LocalMealEntry, QSortBy> {
  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByConsumedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'consumedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByConsumedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'consumedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByIsConsumed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isConsumed', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByIsConsumedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isConsumed', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByLastModifiedLocalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByLastModifiedServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByLastSyncAttemptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByMealLogLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealLogLocalId', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByMealLogLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealLogLocalId', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByMealLogServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealLogServerId', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByMealLogServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealLogServerId', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByMealType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealType', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByMealTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealType', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByNotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notes', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByNotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notes', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByScheduledTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scheduledTime', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByScheduledTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scheduledTime', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortBySyncError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortBySyncErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortBySyncRetryCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalCalories() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCalories', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalCaloriesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCalories', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalCarbohydrates() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCarbohydrates', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalCarbohydratesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCarbohydrates', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByTotalFat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalFat', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalFatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalFat', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalFiber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalFiber', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalFiberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalFiber', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalProtein() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalProtein', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalProteinDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalProtein', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalSodium() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalSodium', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByTotalSodiumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalSodium', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension LocalMealEntryQuerySortThenBy
    on QueryBuilder<LocalMealEntry, LocalMealEntry, QSortThenBy> {
  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByConsumedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'consumedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByConsumedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'consumedAt', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByIsConsumed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isConsumed', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByIsConsumedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isConsumed', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByLastModifiedLocalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByLastModifiedServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByLastSyncAttemptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByMealLogLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealLogLocalId', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByMealLogLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealLogLocalId', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByMealLogServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealLogServerId', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByMealLogServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealLogServerId', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByMealType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealType', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByMealTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mealType', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByNotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notes', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByNotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notes', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByScheduledTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scheduledTime', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByScheduledTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scheduledTime', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenBySyncError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenBySyncErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenBySyncRetryCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalCalories() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCalories', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalCaloriesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCalories', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalCarbohydrates() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCarbohydrates', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalCarbohydratesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalCarbohydrates', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByTotalFat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalFat', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalFatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalFat', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalFiber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalFiber', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalFiberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalFiber', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalProtein() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalProtein', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalProteinDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalProtein', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalSodium() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalSodium', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByTotalSodiumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'totalSodium', Sort.desc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QAfterSortBy>
  thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension LocalMealEntryQueryWhereDistinct
    on QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct> {
  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByConsumedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'consumedAt');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByIsConsumed() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isConsumed');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct> distinctByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isSynced');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastModifiedLocal');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastModifiedServer');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncAttempt');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByMealLogLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mealLogLocalId');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByMealLogServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mealLogServerId');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct> distinctByMealType({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mealType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct> distinctByName({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct> distinctByNotes({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'notes', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByScheduledTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'scheduledTime');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct> distinctByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'serverId');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct> distinctBySyncError({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncError', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncRetryCount');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct> distinctBySyncStatus({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncStatus', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByTotalCalories() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalCalories');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByTotalCarbohydrates() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalCarbohydrates');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct> distinctByTotalFat() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalFat');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByTotalFiber() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalFiber');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByTotalProtein() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalProtein');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByTotalSodium() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'totalSodium');
    });
  }

  QueryBuilder<LocalMealEntry, LocalMealEntry, QDistinct>
  distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension LocalMealEntryQueryProperty
    on QueryBuilder<LocalMealEntry, LocalMealEntry, QQueryProperty> {
  QueryBuilder<LocalMealEntry, int, QQueryOperations> localIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localId');
    });
  }

  QueryBuilder<LocalMealEntry, DateTime?, QQueryOperations>
  consumedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'consumedAt');
    });
  }

  QueryBuilder<LocalMealEntry, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<LocalMealEntry, bool, QQueryOperations> isConsumedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isConsumed');
    });
  }

  QueryBuilder<LocalMealEntry, bool, QQueryOperations> isSyncedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isSynced');
    });
  }

  QueryBuilder<LocalMealEntry, DateTime, QQueryOperations>
  lastModifiedLocalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastModifiedLocal');
    });
  }

  QueryBuilder<LocalMealEntry, DateTime?, QQueryOperations>
  lastModifiedServerProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastModifiedServer');
    });
  }

  QueryBuilder<LocalMealEntry, DateTime?, QQueryOperations>
  lastSyncAttemptProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncAttempt');
    });
  }

  QueryBuilder<LocalMealEntry, int, QQueryOperations> mealLogLocalIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mealLogLocalId');
    });
  }

  QueryBuilder<LocalMealEntry, int?, QQueryOperations>
  mealLogServerIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mealLogServerId');
    });
  }

  QueryBuilder<LocalMealEntry, String, QQueryOperations> mealTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mealType');
    });
  }

  QueryBuilder<LocalMealEntry, String?, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<LocalMealEntry, String?, QQueryOperations> notesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'notes');
    });
  }

  QueryBuilder<LocalMealEntry, DateTime?, QQueryOperations>
  scheduledTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'scheduledTime');
    });
  }

  QueryBuilder<LocalMealEntry, int?, QQueryOperations> serverIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'serverId');
    });
  }

  QueryBuilder<LocalMealEntry, String?, QQueryOperations> syncErrorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncError');
    });
  }

  QueryBuilder<LocalMealEntry, int, QQueryOperations> syncRetryCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncRetryCount');
    });
  }

  QueryBuilder<LocalMealEntry, String, QQueryOperations> syncStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncStatus');
    });
  }

  QueryBuilder<LocalMealEntry, double, QQueryOperations>
  totalCaloriesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalCalories');
    });
  }

  QueryBuilder<LocalMealEntry, double, QQueryOperations>
  totalCarbohydratesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalCarbohydrates');
    });
  }

  QueryBuilder<LocalMealEntry, double, QQueryOperations> totalFatProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalFat');
    });
  }

  QueryBuilder<LocalMealEntry, double?, QQueryOperations> totalFiberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalFiber');
    });
  }

  QueryBuilder<LocalMealEntry, double, QQueryOperations>
  totalProteinProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalProtein');
    });
  }

  QueryBuilder<LocalMealEntry, double?, QQueryOperations>
  totalSodiumProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'totalSodium');
    });
  }

  QueryBuilder<LocalMealEntry, DateTime?, QQueryOperations>
  updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
