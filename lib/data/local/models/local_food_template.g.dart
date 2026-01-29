// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_food_template.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLocalFoodTemplateCollection on Isar {
  IsarCollection<LocalFoodTemplate> get localFoodTemplates => this.collection();
}

const LocalFoodTemplateSchema = CollectionSchema(
  name: r'LocalFoodTemplate',
  id: -6288083692596001195,
  properties: {
    r'barcode': PropertySchema(
      id: 0,
      name: r'barcode',
      type: IsarType.string,
    ),
    r'brand': PropertySchema(
      id: 1,
      name: r'brand',
      type: IsarType.string,
    ),
    r'calories': PropertySchema(
      id: 2,
      name: r'calories',
      type: IsarType.double,
    ),
    r'carbohydrates': PropertySchema(
      id: 3,
      name: r'carbohydrates',
      type: IsarType.double,
    ),
    r'category': PropertySchema(
      id: 4,
      name: r'category',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 5,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'createdByUserId': PropertySchema(
      id: 6,
      name: r'createdByUserId',
      type: IsarType.long,
    ),
    r'description': PropertySchema(
      id: 7,
      name: r'description',
      type: IsarType.string,
    ),
    r'fat': PropertySchema(
      id: 8,
      name: r'fat',
      type: IsarType.double,
    ),
    r'fiber': PropertySchema(
      id: 9,
      name: r'fiber',
      type: IsarType.double,
    ),
    r'imageUrl': PropertySchema(
      id: 10,
      name: r'imageUrl',
      type: IsarType.string,
    ),
    r'isCustom': PropertySchema(
      id: 11,
      name: r'isCustom',
      type: IsarType.bool,
    ),
    r'isSynced': PropertySchema(
      id: 12,
      name: r'isSynced',
      type: IsarType.bool,
    ),
    r'lastModifiedLocal': PropertySchema(
      id: 13,
      name: r'lastModifiedLocal',
      type: IsarType.dateTime,
    ),
    r'lastModifiedServer': PropertySchema(
      id: 14,
      name: r'lastModifiedServer',
      type: IsarType.dateTime,
    ),
    r'lastSyncAttempt': PropertySchema(
      id: 15,
      name: r'lastSyncAttempt',
      type: IsarType.dateTime,
    ),
    r'name': PropertySchema(
      id: 16,
      name: r'name',
      type: IsarType.string,
    ),
    r'protein': PropertySchema(
      id: 17,
      name: r'protein',
      type: IsarType.double,
    ),
    r'serverId': PropertySchema(
      id: 18,
      name: r'serverId',
      type: IsarType.long,
    ),
    r'servingSize': PropertySchema(
      id: 19,
      name: r'servingSize',
      type: IsarType.double,
    ),
    r'servingUnit': PropertySchema(
      id: 20,
      name: r'servingUnit',
      type: IsarType.string,
    ),
    r'sodium': PropertySchema(
      id: 21,
      name: r'sodium',
      type: IsarType.double,
    ),
    r'sugar': PropertySchema(
      id: 22,
      name: r'sugar',
      type: IsarType.double,
    ),
    r'syncError': PropertySchema(
      id: 23,
      name: r'syncError',
      type: IsarType.string,
    ),
    r'syncRetryCount': PropertySchema(
      id: 24,
      name: r'syncRetryCount',
      type: IsarType.long,
    ),
    r'syncStatus': PropertySchema(
      id: 25,
      name: r'syncStatus',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 26,
      name: r'updatedAt',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _localFoodTemplateEstimateSize,
  serialize: _localFoodTemplateSerialize,
  deserialize: _localFoodTemplateDeserialize,
  deserializeProp: _localFoodTemplateDeserializeProp,
  idName: r'localId',
  indexes: {
    r'name': IndexSchema(
      id: 879695947855722453,
      name: r'name',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'name',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'category': IndexSchema(
      id: -7560358558326323820,
      name: r'category',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'category',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'barcode': IndexSchema(
      id: 1156800733621869998,
      name: r'barcode',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'barcode',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'isCustom': IndexSchema(
      id: -2539866887983386444,
      name: r'isCustom',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'isCustom',
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
  getId: _localFoodTemplateGetId,
  getLinks: _localFoodTemplateGetLinks,
  attach: _localFoodTemplateAttach,
  version: '3.1.0+1',
);

int _localFoodTemplateEstimateSize(
  LocalFoodTemplate object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.barcode;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.brand;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.category;
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
  {
    final value = object.imageUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.servingUnit.length * 3;
  {
    final value = object.syncError;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.syncStatus.length * 3;
  return bytesCount;
}

void _localFoodTemplateSerialize(
  LocalFoodTemplate object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.barcode);
  writer.writeString(offsets[1], object.brand);
  writer.writeDouble(offsets[2], object.calories);
  writer.writeDouble(offsets[3], object.carbohydrates);
  writer.writeString(offsets[4], object.category);
  writer.writeDateTime(offsets[5], object.createdAt);
  writer.writeLong(offsets[6], object.createdByUserId);
  writer.writeString(offsets[7], object.description);
  writer.writeDouble(offsets[8], object.fat);
  writer.writeDouble(offsets[9], object.fiber);
  writer.writeString(offsets[10], object.imageUrl);
  writer.writeBool(offsets[11], object.isCustom);
  writer.writeBool(offsets[12], object.isSynced);
  writer.writeDateTime(offsets[13], object.lastModifiedLocal);
  writer.writeDateTime(offsets[14], object.lastModifiedServer);
  writer.writeDateTime(offsets[15], object.lastSyncAttempt);
  writer.writeString(offsets[16], object.name);
  writer.writeDouble(offsets[17], object.protein);
  writer.writeLong(offsets[18], object.serverId);
  writer.writeDouble(offsets[19], object.servingSize);
  writer.writeString(offsets[20], object.servingUnit);
  writer.writeDouble(offsets[21], object.sodium);
  writer.writeDouble(offsets[22], object.sugar);
  writer.writeString(offsets[23], object.syncError);
  writer.writeLong(offsets[24], object.syncRetryCount);
  writer.writeString(offsets[25], object.syncStatus);
  writer.writeDateTime(offsets[26], object.updatedAt);
}

LocalFoodTemplate _localFoodTemplateDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LocalFoodTemplate(
    barcode: reader.readStringOrNull(offsets[0]),
    brand: reader.readStringOrNull(offsets[1]),
    calories: reader.readDouble(offsets[2]),
    carbohydrates: reader.readDouble(offsets[3]),
    category: reader.readStringOrNull(offsets[4]),
    createdAt: reader.readDateTime(offsets[5]),
    createdByUserId: reader.readLongOrNull(offsets[6]),
    description: reader.readStringOrNull(offsets[7]),
    fat: reader.readDouble(offsets[8]),
    fiber: reader.readDoubleOrNull(offsets[9]),
    imageUrl: reader.readStringOrNull(offsets[10]),
    isCustom: reader.readBoolOrNull(offsets[11]) ?? false,
    isSynced: reader.readBoolOrNull(offsets[12]) ?? false,
    lastModifiedLocal: reader.readDateTime(offsets[13]),
    lastModifiedServer: reader.readDateTimeOrNull(offsets[14]),
    lastSyncAttempt: reader.readDateTimeOrNull(offsets[15]),
    name: reader.readString(offsets[16]),
    protein: reader.readDouble(offsets[17]),
    serverId: reader.readLongOrNull(offsets[18]),
    servingSize: reader.readDoubleOrNull(offsets[19]) ?? 100,
    servingUnit: reader.readStringOrNull(offsets[20]) ?? 'g',
    sodium: reader.readDoubleOrNull(offsets[21]),
    sugar: reader.readDoubleOrNull(offsets[22]),
    syncError: reader.readStringOrNull(offsets[23]),
    syncRetryCount: reader.readLongOrNull(offsets[24]) ?? 0,
    syncStatus: reader.readStringOrNull(offsets[25]) ?? 'pending_create',
    updatedAt: reader.readDateTimeOrNull(offsets[26]),
  );
  object.localId = id;
  return object;
}

P _localFoodTemplateDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readDouble(offset)) as P;
    case 3:
      return (reader.readDouble(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readDateTime(offset)) as P;
    case 6:
      return (reader.readLongOrNull(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readDouble(offset)) as P;
    case 9:
      return (reader.readDoubleOrNull(offset)) as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 12:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 13:
      return (reader.readDateTime(offset)) as P;
    case 14:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 15:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 16:
      return (reader.readString(offset)) as P;
    case 17:
      return (reader.readDouble(offset)) as P;
    case 18:
      return (reader.readLongOrNull(offset)) as P;
    case 19:
      return (reader.readDoubleOrNull(offset) ?? 100) as P;
    case 20:
      return (reader.readStringOrNull(offset) ?? 'g') as P;
    case 21:
      return (reader.readDoubleOrNull(offset)) as P;
    case 22:
      return (reader.readDoubleOrNull(offset)) as P;
    case 23:
      return (reader.readStringOrNull(offset)) as P;
    case 24:
      return (reader.readLongOrNull(offset) ?? 0) as P;
    case 25:
      return (reader.readStringOrNull(offset) ?? 'pending_create') as P;
    case 26:
      return (reader.readDateTimeOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _localFoodTemplateGetId(LocalFoodTemplate object) {
  return object.localId;
}

List<IsarLinkBase<dynamic>> _localFoodTemplateGetLinks(
    LocalFoodTemplate object) {
  return [];
}

void _localFoodTemplateAttach(
    IsarCollection<dynamic> col, Id id, LocalFoodTemplate object) {
  object.localId = id;
}

extension LocalFoodTemplateQueryWhereSort
    on QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QWhere> {
  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhere> anyLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhere>
      anyIsCustom() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isCustom'),
      );
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhere>
      anyIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'isSynced'),
      );
    });
  }
}

extension LocalFoodTemplateQueryWhere
    on QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QWhereClause> {
  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      localIdEqualTo(Id localId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: localId,
        upper: localId,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      localIdGreaterThan(Id localId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: localId, includeLower: include),
      );
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      localIdLessThan(Id localId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: localId, includeUpper: include),
      );
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      nameEqualTo(String name) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'name',
        value: [name],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      nameNotEqualTo(String name) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [],
              upper: [name],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [name],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [name],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [],
              upper: [name],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      categoryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'category',
        value: [null],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      categoryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'category',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      categoryEqualTo(String? category) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'category',
        value: [category],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      categoryNotEqualTo(String? category) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'category',
              lower: [],
              upper: [category],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'category',
              lower: [category],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'category',
              lower: [category],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'category',
              lower: [],
              upper: [category],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      barcodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'barcode',
        value: [null],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      barcodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'barcode',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      barcodeEqualTo(String? barcode) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'barcode',
        value: [barcode],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      barcodeNotEqualTo(String? barcode) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'barcode',
              lower: [],
              upper: [barcode],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'barcode',
              lower: [barcode],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'barcode',
              lower: [barcode],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'barcode',
              lower: [],
              upper: [barcode],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      isCustomEqualTo(bool isCustom) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'isCustom',
        value: [isCustom],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      isCustomNotEqualTo(bool isCustom) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isCustom',
              lower: [],
              upper: [isCustom],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isCustom',
              lower: [isCustom],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isCustom',
              lower: [isCustom],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'isCustom',
              lower: [],
              upper: [isCustom],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      isSyncedEqualTo(bool isSynced) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'isSynced',
        value: [isSynced],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
      syncStatusEqualTo(String syncStatus) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'syncStatus',
        value: [syncStatus],
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterWhereClause>
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

extension LocalFoodTemplateQueryFilter
    on QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QFilterCondition> {
  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'barcode',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'barcode',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'barcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'barcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'barcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'barcode',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'barcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'barcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'barcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'barcode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'barcode',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      barcodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'barcode',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'brand',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'brand',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'brand',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'brand',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'brand',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'brand',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'brand',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'brand',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'brand',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'brand',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'brand',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      brandIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'brand',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      caloriesEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'calories',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      caloriesGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'calories',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      caloriesLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'calories',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      caloriesBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'calories',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      carbohydratesEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'carbohydrates',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      carbohydratesGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'carbohydrates',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      carbohydratesLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'carbohydrates',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      carbohydratesBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'carbohydrates',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'category',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'category',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'category',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'category',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'category',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'category',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      categoryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'category',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      createdByUserIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'createdByUserId',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      createdByUserIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'createdByUserId',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      createdByUserIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdByUserId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      createdByUserIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdByUserId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      createdByUserIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdByUserId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      createdByUserIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdByUserId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'description',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'description',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'description',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'description',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      descriptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fatEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'fat',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fatGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'fat',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fatLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'fat',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fatBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'fat',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fiberIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'fiber',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fiberIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'fiber',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fiberEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'fiber',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fiberGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'fiber',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fiberLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'fiber',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      fiberBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'fiber',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'imageUrl',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'imageUrl',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'imageUrl',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'imageUrl',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'imageUrl',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'imageUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      imageUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'imageUrl',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      isCustomEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isCustom',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      isSyncedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isSynced',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      lastModifiedLocalEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastModifiedLocal',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      lastModifiedServerIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastModifiedServer',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      lastModifiedServerIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastModifiedServer',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      lastModifiedServerEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastModifiedServer',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      lastSyncAttemptIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastSyncAttempt',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      lastSyncAttemptIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastSyncAttempt',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      lastSyncAttemptEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastSyncAttempt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      localIdEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      nameEqualTo(
    String value, {
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      nameGreaterThan(
    String value, {
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      nameLessThan(
    String value, {
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      nameBetween(
    String lower,
    String upper, {
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      proteinEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'protein',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      proteinGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'protein',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      proteinLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'protein',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      proteinBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'protein',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      serverIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'serverId',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      serverIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'serverId',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      serverIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'serverId',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingSizeEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'servingSize',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingSizeGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'servingSize',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingSizeLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'servingSize',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingSizeBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'servingSize',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'servingUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'servingUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'servingUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'servingUnit',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'servingUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'servingUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'servingUnit',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'servingUnit',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'servingUnit',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      servingUnitIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'servingUnit',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sodiumIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sodium',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sodiumIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sodium',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sodiumEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sodium',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sodiumGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sodium',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sodiumLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sodium',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sodiumBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sodium',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sugarIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'sugar',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sugarIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'sugar',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sugarEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sugar',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sugarGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sugar',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sugarLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sugar',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      sugarBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sugar',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncErrorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'syncError',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncErrorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'syncError',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncErrorContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'syncError',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncErrorMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'syncError',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncErrorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncError',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncErrorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'syncError',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncRetryCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncRetryCount',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncStatusContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'syncStatus',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncStatusMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'syncStatus',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncStatusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncStatus',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      syncStatusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'syncStatus',
        value: '',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      updatedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'updatedAt',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      updatedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'updatedAt',
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
      updatedAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterFilterCondition>
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
}

extension LocalFoodTemplateQueryObject
    on QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QFilterCondition> {}

extension LocalFoodTemplateQueryLinks
    on QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QFilterCondition> {}

extension LocalFoodTemplateQuerySortBy
    on QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QSortBy> {
  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByBarcode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'barcode', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByBarcodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'barcode', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByBrand() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'brand', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByBrandDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'brand', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCalories() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'calories', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCaloriesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'calories', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCarbohydrates() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carbohydrates', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCarbohydratesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carbohydrates', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'category', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'category', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCreatedByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdByUserId', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByCreatedByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdByUserId', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy> sortByFat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fat', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByFatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fat', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByFiber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fiber', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByFiberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fiber', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByImageUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByImageUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByIsCustom() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCustom', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByIsCustomDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCustom', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByLastModifiedLocalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByLastModifiedServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByLastSyncAttemptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByProtein() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'protein', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByProteinDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'protein', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByServingSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'servingSize', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByServingSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'servingSize', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByServingUnit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'servingUnit', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByServingUnitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'servingUnit', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySodium() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sodium', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySodiumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sodium', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySugar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sugar', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySugarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sugar', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySyncError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySyncErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySyncRetryCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension LocalFoodTemplateQuerySortThenBy
    on QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QSortThenBy> {
  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByBarcode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'barcode', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByBarcodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'barcode', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByBrand() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'brand', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByBrandDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'brand', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCalories() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'calories', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCaloriesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'calories', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCarbohydrates() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carbohydrates', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCarbohydratesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'carbohydrates', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCategory() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'category', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCategoryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'category', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCreatedByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdByUserId', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByCreatedByUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdByUserId', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy> thenByFat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fat', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByFatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fat', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByFiber() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fiber', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByFiberDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fiber', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByImageUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByImageUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'imageUrl', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByIsCustom() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCustom', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByIsCustomDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isCustom', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByIsSyncedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isSynced', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByLastModifiedLocalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedLocal', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByLastModifiedServerDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastModifiedServer', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByLastSyncAttemptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAttempt', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localId', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByProtein() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'protein', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByProteinDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'protein', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByServerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'serverId', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByServingSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'servingSize', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByServingSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'servingSize', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByServingUnit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'servingUnit', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByServingUnitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'servingUnit', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySodium() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sodium', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySodiumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sodium', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySugar() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sugar', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySugarDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sugar', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySyncError() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySyncErrorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncError', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySyncRetryCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncRetryCount', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension LocalFoodTemplateQueryWhereDistinct
    on QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct> {
  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByBarcode({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'barcode', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct> distinctByBrand(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'brand', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByCalories() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'calories');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByCarbohydrates() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'carbohydrates');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByCategory({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'category', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByCreatedByUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdByUserId');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByDescription({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'description', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByFat() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'fat');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByFiber() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'fiber');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByImageUrl({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'imageUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByIsCustom() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isCustom');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByIsSynced() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isSynced');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByLastModifiedLocal() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastModifiedLocal');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByLastModifiedServer() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastModifiedServer');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByLastSyncAttempt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncAttempt');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByProtein() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'protein');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByServerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'serverId');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByServingSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'servingSize');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByServingUnit({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'servingUnit', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctBySodium() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sodium');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctBySugar() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sugar');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctBySyncError({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncError', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctBySyncRetryCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncRetryCount');
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctBySyncStatus({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncStatus', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension LocalFoodTemplateQueryProperty
    on QueryBuilder<LocalFoodTemplate, LocalFoodTemplate, QQueryProperty> {
  QueryBuilder<LocalFoodTemplate, int, QQueryOperations> localIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localId');
    });
  }

  QueryBuilder<LocalFoodTemplate, String?, QQueryOperations> barcodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'barcode');
    });
  }

  QueryBuilder<LocalFoodTemplate, String?, QQueryOperations> brandProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'brand');
    });
  }

  QueryBuilder<LocalFoodTemplate, double, QQueryOperations> caloriesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'calories');
    });
  }

  QueryBuilder<LocalFoodTemplate, double, QQueryOperations>
      carbohydratesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'carbohydrates');
    });
  }

  QueryBuilder<LocalFoodTemplate, String?, QQueryOperations>
      categoryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'category');
    });
  }

  QueryBuilder<LocalFoodTemplate, DateTime, QQueryOperations>
      createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<LocalFoodTemplate, int?, QQueryOperations>
      createdByUserIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdByUserId');
    });
  }

  QueryBuilder<LocalFoodTemplate, String?, QQueryOperations>
      descriptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'description');
    });
  }

  QueryBuilder<LocalFoodTemplate, double, QQueryOperations> fatProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'fat');
    });
  }

  QueryBuilder<LocalFoodTemplate, double?, QQueryOperations> fiberProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'fiber');
    });
  }

  QueryBuilder<LocalFoodTemplate, String?, QQueryOperations>
      imageUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'imageUrl');
    });
  }

  QueryBuilder<LocalFoodTemplate, bool, QQueryOperations> isCustomProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isCustom');
    });
  }

  QueryBuilder<LocalFoodTemplate, bool, QQueryOperations> isSyncedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isSynced');
    });
  }

  QueryBuilder<LocalFoodTemplate, DateTime, QQueryOperations>
      lastModifiedLocalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastModifiedLocal');
    });
  }

  QueryBuilder<LocalFoodTemplate, DateTime?, QQueryOperations>
      lastModifiedServerProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastModifiedServer');
    });
  }

  QueryBuilder<LocalFoodTemplate, DateTime?, QQueryOperations>
      lastSyncAttemptProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncAttempt');
    });
  }

  QueryBuilder<LocalFoodTemplate, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<LocalFoodTemplate, double, QQueryOperations> proteinProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'protein');
    });
  }

  QueryBuilder<LocalFoodTemplate, int?, QQueryOperations> serverIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'serverId');
    });
  }

  QueryBuilder<LocalFoodTemplate, double, QQueryOperations>
      servingSizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'servingSize');
    });
  }

  QueryBuilder<LocalFoodTemplate, String, QQueryOperations>
      servingUnitProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'servingUnit');
    });
  }

  QueryBuilder<LocalFoodTemplate, double?, QQueryOperations> sodiumProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sodium');
    });
  }

  QueryBuilder<LocalFoodTemplate, double?, QQueryOperations> sugarProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sugar');
    });
  }

  QueryBuilder<LocalFoodTemplate, String?, QQueryOperations>
      syncErrorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncError');
    });
  }

  QueryBuilder<LocalFoodTemplate, int, QQueryOperations>
      syncRetryCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncRetryCount');
    });
  }

  QueryBuilder<LocalFoodTemplate, String, QQueryOperations>
      syncStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncStatus');
    });
  }

  QueryBuilder<LocalFoodTemplate, DateTime?, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
