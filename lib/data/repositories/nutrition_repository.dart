import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../models/food_template.dart';
import '../models/meal_log.dart';
import '../models/meal_entry.dart';
import '../models/food_item.dart';
import '../models/nutrition_goal.dart';
import '../models/nutrition_summary.dart';
import '../models/daily_nutrition_progress.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../local/services/local_database_service.dart';
import '../local/services/model_mapper.dart';
import '../local/models/local_meal_log.dart';
import '../local/models/local_meal_entry.dart';
import '../local/models/local_food_item.dart';
import '../local/models/local_nutrition_goal.dart';
import '../local/models/local_food_template.dart';

/// Repository for nutrition operations with offline-first support
class NutritionRepository {
  final ApiService _apiService;
  final LocalDatabaseService _localDb;
  final ConnectivityService _connectivity;
  final AuthService _authService;

  NutritionRepository(
    this._apiService,
    this._localDb,
    this._connectivity,
    this._authService,
  );

  // ============ Helper Methods ============

  /// Background sync operation with standard logging
  void _backgroundSync(
    Future<void> Function() syncOperation,
    String successMessage,
  ) {
    syncOperation()
        .then((_) => debugPrint('✅ Background sync: $successMessage'))
        .catchError((e) => debugPrint('⚠️ Background sync failed: $e'));
  }

  // ============ Meal Logs - Offline First ============

  /// Get today's meal log - offline-first
  /// Creates locally if not exists, syncs in background
  Future<MealLog> getTodaysMealLog() async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Normalize today's date (strip time component)
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    // 1. Check local cache first
    var localLog =
        await db.localMealLogs
            .filter()
            .userIdEqualTo(userId)
            .dateEqualTo(today)
            .findFirst();

    // 2. If found locally, return immediately and sync in background
    if (localLog != null) {
      debugPrint('📦 Found today\'s meal log in cache');

      if (_connectivity.isOnline) {
        _backgroundSync(
          () => _syncMealLogFromServer(db, localLog.serverId, userId, today),
          'Synced today\'s meal log',
        );
      }

      return await _localMealLogToMealLogWithEntries(db, localLog);
    }

    // 3. If not found and online, fetch from server
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.mealLogToday,
        );
        final mealLog = MealLog.fromJson(data);

        // Cache locally with entries
        await _cacheMealLogWithEntries(db, mealLog);
        debugPrint('✅ Fetched and cached today\'s meal log from server');

        return mealLog;
      } catch (e) {
        debugPrint('⚠️ API failed, creating local meal log: $e');
        // Fall through to create locally
      }
    }

    // 4. Create locally (offline or API failed)
    debugPrint('📴 Creating meal log locally');
    return await _createLocalMealLog(db, userId, today);
  }

  /// Sync meal log from server
  Future<void> _syncMealLogFromServer(
    Isar db,
    int? serverId,
    int userId,
    DateTime date,
  ) async {
    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.mealLogToday,
      );
      final serverMealLog = MealLog.fromJson(data);
      await _cacheMealLogWithEntries(db, serverMealLog);
    } catch (e) {
      debugPrint('⚠️ Failed to sync meal log from server: $e');
    }
  }

  /// Cache a MealLog with all its entries and food items
  Future<void> _cacheMealLogWithEntries(Isar db, MealLog mealLog) async {
    await db.writeTxn(() async {
      // Find or create local meal log
      var existingLog =
          await db.localMealLogs
              .filter()
              .serverIdEqualTo(mealLog.id)
              .findFirst();

      LocalMealLog savedLog;
      if (existingLog != null) {
        // Update existing
        savedLog = ModelMapper.mealLogToLocal(
          mealLog,
          localId: existingLog.localId,
          isSynced: true,
        );
      } else {
        savedLog = ModelMapper.mealLogToLocal(mealLog, isSynced: true);
      }
      await db.localMealLogs.put(savedLog);

      // Cache meal entries
      for (final entry in mealLog.mealEntries ?? <MealEntry>[]) {
        var existingEntry =
            await db.localMealEntrys
                .filter()
                .serverIdEqualTo(entry.id)
                .findFirst();

        LocalMealEntry savedEntry;
        if (existingEntry != null) {
          savedEntry = ModelMapper.mealEntryToLocal(
            entry,
            mealLogLocalId: savedLog.localId,
            mealLogServerId: savedLog.serverId,
            localId: existingEntry.localId,
            isSynced: true,
          );
        } else {
          savedEntry = ModelMapper.mealEntryToLocal(
            entry,
            mealLogLocalId: savedLog.localId,
            mealLogServerId: savedLog.serverId,
            isSynced: true,
          );
        }
        await db.localMealEntrys.put(savedEntry);

        // Cache food items
        for (final food in entry.foodItems ?? <FoodItem>[]) {
          var existingFood =
              await db.localFoodItems
                  .filter()
                  .serverIdEqualTo(food.id)
                  .findFirst();

          LocalFoodItem savedFood;
          if (existingFood != null) {
            savedFood = ModelMapper.foodItemToLocal(
              food,
              mealEntryLocalId: savedEntry.localId,
              mealEntryServerId: savedEntry.serverId,
              localId: existingFood.localId,
              isSynced: true,
            );
          } else {
            savedFood = ModelMapper.foodItemToLocal(
              food,
              mealEntryLocalId: savedEntry.localId,
              mealEntryServerId: savedEntry.serverId,
              isSynced: true,
            );
          }
          await db.localFoodItems.put(savedFood);
        }
      }
    });
  }

  /// Create a local meal log with default entries
  Future<MealLog> _createLocalMealLog(
    Isar db,
    int userId,
    DateTime date,
  ) async {
    final now = DateTime.now();

    late LocalMealLog savedLog;
    final entries = <MealEntry>[];

    await db.writeTxn(() async {
      // Create meal log
      final localLog = LocalMealLog(
        userId: userId,
        date: date,
        waterIntake: 0,
        totalCalories: 0,
        totalProtein: 0,
        totalCarbohydrates: 0,
        totalFat: 0,
        createdAt: now,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: now,
      );
      await db.localMealLogs.put(localLog);
      savedLog = localLog;

      // Create default meal entries
      for (final mealType in ['Breakfast', 'Lunch', 'Dinner', 'Snack']) {
        final localEntry = LocalMealEntry(
          mealLogLocalId: savedLog.localId,
          mealType: mealType,
          isConsumed: false,
          totalCalories: 0,
          totalProtein: 0,
          totalCarbohydrates: 0,
          totalFat: 0,
          createdAt: now,
          isSynced: false,
          syncStatus: 'pending_create',
          lastModifiedLocal: now,
        );
        await db.localMealEntrys.put(localEntry);

        entries.add(
          MealEntry(
            id: localEntry.localId,
            mealLogId: savedLog.localId,
            mealType: mealType,
            isConsumed: false,
            totalCalories: 0,
            totalProtein: 0,
            totalCarbohydrates: 0,
            totalFat: 0,
            createdAt: now,
          ),
        );
      }
    });

    debugPrint('💾 Created local meal log for $date');

    return MealLog(
      id: savedLog.localId,
      userId: userId,
      date: date,
      waterIntake: 0,
      totalCalories: 0,
      totalProtein: 0,
      totalCarbohydrates: 0,
      totalFat: 0,
      createdAt: now,
      mealEntries: entries,
    );
  }

  /// Convert LocalMealLog to MealLog with entries loaded
  Future<MealLog> _localMealLogToMealLogWithEntries(
    Isar db,
    LocalMealLog localLog,
  ) async {
    // Load meal entries
    final localEntries =
        await db.localMealEntrys
            .filter()
            .mealLogLocalIdEqualTo(localLog.localId)
            .findAll();

    final entries = <MealEntry>[];
    for (final localEntry in localEntries) {
      // Load food items for this entry
      final localFoods =
          await db.localFoodItems
              .filter()
              .mealEntryLocalIdEqualTo(localEntry.localId)
              .findAll();

      final foods =
          localFoods.map((f) => ModelMapper.localToFoodItem(f)).toList();

      entries.add(ModelMapper.localToMealEntry(localEntry, foodItems: foods));
    }

    return ModelMapper.localToMealLog(localLog, mealEntries: entries);
  }

  /// Get meal logs for date range - offline-first
  Future<List<MealLog>> getMealLogs({
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int pageSize = 30,
  }) async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) return [];

    // Get from local cache first
    var query = db.localMealLogs.filter().userIdEqualTo(userId);

    if (startDate != null) {
      // Normalize to start of day for inclusive start boundary
      final startDay = DateTime(startDate.year, startDate.month, startDate.day);
      query = query.dateGreaterThan(startDay.subtract(const Duration(days: 1)));
    }
    if (endDate != null) {
      // Normalize to start of NEXT day for inclusive end boundary
      // This ensures we include all of endDate but exclude the next day
      final nextDay = DateTime(endDate.year, endDate.month, endDate.day + 1);
      query = query.dateLessThan(nextDay);
    }

    final localLogs = await query.sortByDateDesc().findAll();

    // Convert to MealLog models
    final logs = <MealLog>[];
    for (final localLog in localLogs) {
      logs.add(await _localMealLogToMealLogWithEntries(db, localLog));
    }

    // Sync in background if online
    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _syncMealLogsFromServer(startDate, endDate),
        'Synced meal logs history',
      );
    }

    return logs;
  }

  /// Sync meal logs from server
  Future<void> _syncMealLogsFromServer(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      final queryParams = <String, String>{};
      if (startDate != null) {
        queryParams['startDate'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['endDate'] = endDate.toIso8601String();
      }

      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.mealLogs,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final db = _localDb.database;
      for (final json in data) {
        final mealLog = MealLog.fromJson(json as Map<String, dynamic>);
        await _cacheMealLogWithEntries(db, mealLog);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to sync meal logs from server: $e');
    }
  }

  /// Update water intake - offline-first
  Future<void> updateWaterIntake(int mealLogId, double waterIntake) async {
    final db = _localDb.database;

    // Find local meal log
    var localLog =
        await db.localMealLogs.filter().serverIdEqualTo(mealLogId).findFirst();
    localLog ??= await db.localMealLogs.get(mealLogId);

    if (localLog == null) {
      throw Exception('Meal log not found');
    }

    // Update locally first
    await db.writeTxn(() async {
      localLog!.waterIntake = waterIntake;
      localLog.lastModifiedLocal = DateTime.now().toUtc();
      localLog.isSynced = false;
      if (localLog.serverId != null) {
        localLog.syncStatus = 'pending_update';
      }
      await db.localMealLogs.put(localLog);
    });

    debugPrint('💧 Updated water intake locally: $waterIntake ml');

    // Sync in background if online
    if (_connectivity.isOnline && localLog.serverId != null) {
      _backgroundSync(
        () => _apiService.put<void>(
          ApiConfig.mealLogWater(localLog!.serverId!),
          data: waterIntake,
        ),
        'Synced water intake',
      );
    }
  }

  // ============ Food Items - Offline First ============

  /// Quick add food from template - offline-first
  Future<FoodItem> quickAddFood({
    required int mealEntryId,
    required int foodTemplateId,
    double quantity = 1,
  }) async {
    final db = _localDb.database;

    // Find local meal entry
    var localEntry =
        await db.localMealEntrys
            .filter()
            .serverIdEqualTo(mealEntryId)
            .findFirst();
    localEntry ??= await db.localMealEntrys.get(mealEntryId);

    if (localEntry == null) {
      throw Exception('Meal entry not found');
    }

    // Get food template from cache or API
    FoodTemplate? template = await _getFoodTemplateById(foodTemplateId);

    if (template == null) {
      throw Exception('Food template not found');
    }

    // Capture non-nullable references for use in closure
    final entry = localEntry;
    final foodTemplate = template;

    // Create food item locally
    final now = DateTime.now();
    late LocalFoodItem savedFood;

    await db.writeTxn(() async {
      final localFood = LocalFoodItem(
        mealEntryLocalId: entry.localId,
        mealEntryServerId: entry.serverId,
        foodTemplateId: foodTemplateId,
        name: foodTemplate.name,
        brand: foodTemplate.brand,
        quantity: quantity,
        servingSize: foodTemplate.servingSize,
        servingUnit: foodTemplate.servingUnit,
        calories: foodTemplate.calories * quantity,
        protein: foodTemplate.protein * quantity,
        carbohydrates: foodTemplate.carbohydrates * quantity,
        fat: foodTemplate.fat * quantity,
        fiber:
            foodTemplate.fiber != null ? foodTemplate.fiber! * quantity : null,
        sugar:
            foodTemplate.sugar != null ? foodTemplate.sugar! * quantity : null,
        sodium:
            foodTemplate.sodium != null
                ? foodTemplate.sodium! * quantity
                : null,
        createdAt: now,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: now,
      );
      await db.localFoodItems.put(localFood);
      savedFood = localFood;

      // Update meal entry totals
      entry.totalCalories += localFood.calories;
      entry.totalProtein += localFood.protein;
      entry.totalCarbohydrates += localFood.carbohydrates;
      entry.totalFat += localFood.fat;
      entry.lastModifiedLocal = now;
      entry.isSynced = false;
      if (entry.serverId != null) {
        entry.syncStatus = 'pending_update';
      }
      await db.localMealEntrys.put(entry);

      // Update meal log totals
      final localLog = await db.localMealLogs.get(entry.mealLogLocalId);
      if (localLog != null) {
        localLog.totalCalories += localFood.calories;
        localLog.totalProtein += localFood.protein;
        localLog.totalCarbohydrates += localFood.carbohydrates;
        localLog.totalFat += localFood.fat;
        localLog.lastModifiedLocal = now;
        localLog.isSynced = false;
        if (localLog.serverId != null) {
          localLog.syncStatus = 'pending_update';
        }
        await db.localMealLogs.put(localLog);
      }
    });

    debugPrint('➕ Added food "${foodTemplate.name}" locally');

    // Sync in background if online and entry has server ID
    if (_connectivity.isOnline && entry.serverId != null) {
      _backgroundSync(
        () => _syncFoodItemToServer(savedFood, entry.serverId!),
        'Synced food item to server',
      );
    }

    return ModelMapper.localToFoodItem(savedFood);
  }

  /// Sync food item to server
  Future<void> _syncFoodItemToServer(
    LocalFoodItem localFood,
    int mealEntryServerId,
  ) async {
    try {
      final data = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.foodItemQuickAdd,
        data: {
          'mealEntryId': mealEntryServerId,
          'foodTemplateId': localFood.foodTemplateId,
          'quantity': localFood.quantity,
        },
      );
      final serverFood = FoodItem.fromJson(data);

      // Update local with server ID
      final db = _localDb.database;
      await db.writeTxn(() async {
        localFood.serverId = serverFood.id;
        localFood.isSynced = true;
        localFood.syncStatus = 'synced';
        await db.localFoodItems.put(localFood);
      });
    } catch (e) {
      debugPrint('⚠️ Failed to sync food item: $e');
    }
  }

  /// Delete food item - offline-first
  Future<void> deleteFoodItem(int id) async {
    final db = _localDb.database;

    // Find local food item
    var localFood =
        await db.localFoodItems.filter().serverIdEqualTo(id).findFirst();
    localFood ??= await db.localFoodItems.get(id);

    if (localFood == null) {
      throw Exception('Food item not found');
    }

    final serverId = localFood.serverId;

    await db.writeTxn(() async {
      // Update meal entry totals
      final localEntry = await db.localMealEntrys.get(
        localFood!.mealEntryLocalId,
      );
      if (localEntry != null) {
        localEntry.totalCalories -= localFood.calories;
        localEntry.totalProtein -= localFood.protein;
        localEntry.totalCarbohydrates -= localFood.carbohydrates;
        localEntry.totalFat -= localFood.fat;
        localEntry.lastModifiedLocal = DateTime.now().toUtc();
        localEntry.isSynced = false;
        if (localEntry.serverId != null) {
          localEntry.syncStatus = 'pending_update';
        }
        await db.localMealEntrys.put(localEntry);

        // Update meal log totals
        final localLog = await db.localMealLogs.get(localEntry.mealLogLocalId);
        if (localLog != null) {
          localLog.totalCalories -= localFood.calories;
          localLog.totalProtein -= localFood.protein;
          localLog.totalCarbohydrates -= localFood.carbohydrates;
          localLog.totalFat -= localFood.fat;
          localLog.lastModifiedLocal = DateTime.now().toUtc();
          localLog.isSynced = false;
          if (localLog.serverId != null) {
            localLog.syncStatus = 'pending_update';
          }
          await db.localMealLogs.put(localLog);
        }
      }

      // Delete the food item
      await db.localFoodItems.delete(localFood.localId);
    });

    debugPrint('🗑️ Deleted food item locally');

    // Sync in background if online and had server ID
    if (_connectivity.isOnline && serverId != null) {
      _backgroundSync(
        () => _apiService.delete(ApiConfig.foodItemById(serverId)),
        'Deleted food item on server',
      );
    }
  }

  // ============ Food Templates ============

  /// Get food template by ID - checks cache first
  Future<FoodTemplate?> _getFoodTemplateById(int id) async {
    final db = _localDb.database;

    // Check local cache first
    final localTemplate =
        await db.localFoodTemplates.filter().serverIdEqualTo(id).findFirst();

    if (localTemplate != null) {
      return ModelMapper.localToFoodTemplate(localTemplate);
    }

    // Fetch from API if online
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.foodTemplateById(id),
        );
        final template = FoodTemplate.fromJson(data);

        // Cache locally
        await db.writeTxn(() async {
          final local = ModelMapper.foodTemplateToLocal(template);
          await db.localFoodTemplates.put(local);
        });

        return template;
      } catch (e) {
        debugPrint('⚠️ Failed to fetch food template: $e');
      }
    }

    return null;
  }

  /// Get all food templates with optional filtering
  Future<List<FoodTemplate>> getFoodTemplates({
    String? category,
    bool? isCustom,
    int page = 1,
    int pageSize = 50,
  }) async {
    final db = _localDb.database;

    // Get from local cache first
    var query = db.localFoodTemplates.where();
    final localTemplates = await query.findAll();

    // Filter locally
    var filtered =
        localTemplates.where((t) {
          if (category != null && t.category != category) return false;
          if (isCustom != null && t.isCustom != isCustom) return false;
          return true;
        }).toList();

    // Sync in background if online
    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _syncFoodTemplatesFromServer(category, isCustom),
        'Synced food templates',
      );
    }

    return filtered.map((t) => ModelMapper.localToFoodTemplate(t)).toList();
  }

  /// Sync food templates from server
  Future<void> _syncFoodTemplatesFromServer(
    String? category,
    bool? isCustom,
  ) async {
    try {
      final queryParams = <String, String>{};
      if (category != null) queryParams['category'] = category;
      if (isCustom != null) queryParams['isCustom'] = isCustom.toString();

      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.foodTemplates,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final db = _localDb.database;
      await db.writeTxn(() async {
        for (final json in data) {
          final template = FoodTemplate.fromJson(json as Map<String, dynamic>);

          var existing =
              await db.localFoodTemplates
                  .filter()
                  .serverIdEqualTo(template.id)
                  .findFirst();

          if (existing != null) {
            final updated = ModelMapper.foodTemplateToLocal(
              template,
              localId: existing.localId,
            );
            await db.localFoodTemplates.put(updated);
          } else {
            final local = ModelMapper.foodTemplateToLocal(template);
            await db.localFoodTemplates.put(local);
          }
        }
      });
    } catch (e) {
      debugPrint('⚠️ Failed to sync food templates: $e');
    }
  }

  /// Search foods
  Future<List<FoodTemplate>> searchFoods(
    String query, {
    String? category,
    int limit = 20,
  }) async {
    final db = _localDb.database;

    // Search local cache first
    final localTemplates =
        await db.localFoodTemplates
            .filter()
            .nameContains(query, caseSensitive: false)
            .findAll();

    var results =
        localTemplates
            .where((t) => category == null || t.category == category)
            .take(limit)
            .map((t) => ModelMapper.localToFoodTemplate(t))
            .toList();

    // If online and few local results, also search server
    if (_connectivity.isOnline && results.length < limit) {
      try {
        final queryParams = <String, String>{
          'query': query,
          'limit': limit.toString(),
        };
        if (category != null) queryParams['category'] = category;

        final data = await _apiService.get<List<dynamic>>(
          '${ApiConfig.foodTemplates}/search',
          queryParameters: queryParams,
        );

        final serverResults =
            data
                .map(
                  (json) => FoodTemplate.fromJson(json as Map<String, dynamic>),
                )
                .toList();

        // Cache new results
        await db.writeTxn(() async {
          for (final template in serverResults) {
            var existing =
                await db.localFoodTemplates
                    .filter()
                    .serverIdEqualTo(template.id)
                    .findFirst();

            if (existing == null) {
              await db.localFoodTemplates.put(
                ModelMapper.foodTemplateToLocal(template),
              );
            }
          }
        });

        // Merge results (avoid duplicates)
        final existingIds = results.map((r) => r.id).toSet();
        for (final template in serverResults) {
          if (!existingIds.contains(template.id)) {
            results.add(template);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Server search failed, using local results: $e');
      }
    }

    return results.take(limit).toList();
  }

  /// Get food categories
  Future<List<String>> getFoodCategories() async {
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<List<dynamic>>(
          ApiConfig.foodTemplateCategories,
        );
        return data.cast<String>();
      } catch (e) {
        debugPrint('⚠️ Failed to fetch categories: $e');
      }
    }

    // Fallback to local categories
    final db = _localDb.database;
    final templates = await db.localFoodTemplates.where().findAll();
    final categories =
        templates.map((t) => t.category).whereType<String>().toSet().toList();
    categories.sort();
    return categories;
  }

  /// Get food by barcode
  Future<FoodTemplate?> getFoodByBarcode(String barcode) async {
    final db = _localDb.database;

    // Check local cache first
    final local =
        await db.localFoodTemplates
            .filter()
            .barcodeEqualTo(barcode)
            .findFirst();

    if (local != null) {
      return ModelMapper.localToFoodTemplate(local);
    }

    // Fetch from API if online
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.foodTemplateByBarcode(barcode),
        );
        final template = FoodTemplate.fromJson(data);

        // Cache locally
        await db.writeTxn(() async {
          await db.localFoodTemplates.put(
            ModelMapper.foodTemplateToLocal(template),
          );
        });

        return template;
      } catch (e) {
        debugPrint('Food not found for barcode: $barcode');
      }
    }

    return null;
  }

  /// Create custom food template
  Future<FoodTemplate> createFoodTemplate(FoodTemplate template) async {
    final db = _localDb.database;
    final now = DateTime.now();

    // Create locally first
    late LocalFoodTemplate savedTemplate;
    await db.writeTxn(() async {
      final local = LocalFoodTemplate(
        name: template.name,
        brand: template.brand,
        category: template.category,
        barcode: template.barcode,
        servingSize: template.servingSize,
        servingUnit: template.servingUnit,
        calories: template.calories,
        protein: template.protein,
        carbohydrates: template.carbohydrates,
        fat: template.fat,
        fiber: template.fiber,
        sugar: template.sugar,
        sodium: template.sodium,
        description: template.description,
        imageUrl: template.imageUrl,
        isCustom: true,
        createdByUserId: await _authService.getUserId(),
        createdAt: now,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: now,
      );
      await db.localFoodTemplates.put(local);
      savedTemplate = local;
    });

    debugPrint('💾 Created custom food template locally: ${template.name}');

    // Sync in background if online
    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _syncFoodTemplateToServer(savedTemplate),
        'Synced custom food template',
      );
    }

    return ModelMapper.localToFoodTemplate(savedTemplate);
  }

  /// Sync food template to server
  Future<void> _syncFoodTemplateToServer(LocalFoodTemplate local) async {
    try {
      final template = ModelMapper.localToFoodTemplate(local);
      final data = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.foodTemplates,
        data: template.toJson(),
      );
      final serverTemplate = FoodTemplate.fromJson(data);

      final db = _localDb.database;
      await db.writeTxn(() async {
        local.serverId = serverTemplate.id;
        local.isSynced = true;
        local.syncStatus = 'synced';
        await db.localFoodTemplates.put(local);
      });
    } catch (e) {
      debugPrint('⚠️ Failed to sync food template: $e');
    }
  }

  // ============ Nutrition Goals - Offline First ============

  /// Get active nutrition goal - offline-first
  Future<NutritionGoal> getActiveNutritionGoal() async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // Check local cache first
    final localGoal =
        await db.localNutritionGoals
            .filter()
            .userIdEqualTo(userId)
            .isActiveEqualTo(true)
            .findFirst();

    if (localGoal != null) {
      debugPrint('📦 Found active nutrition goal in cache');

      if (_connectivity.isOnline) {
        _backgroundSync(
          () => _syncNutritionGoalFromServer(db, userId),
          'Synced nutrition goal',
        );
      }

      return ModelMapper.localToNutritionGoal(localGoal);
    }

    // Fetch from API if online
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.nutritionGoalActive,
        );
        final goal = NutritionGoal.fromJson(data);

        // Cache locally
        await db.writeTxn(() async {
          final local = ModelMapper.nutritionGoalToLocal(goal);
          await db.localNutritionGoals.put(local);
        });

        return goal;
      } catch (e) {
        debugPrint('⚠️ Failed to fetch nutrition goal: $e');
      }
    }

    // Return default goal
    return NutritionGoal.defaultGoal(userId);
  }

  /// Sync nutrition goal from server
  Future<void> _syncNutritionGoalFromServer(Isar db, int userId) async {
    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.nutritionGoalActive,
      );
      final goal = NutritionGoal.fromJson(data);

      await db.writeTxn(() async {
        var existing =
            await db.localNutritionGoals
                .filter()
                .serverIdEqualTo(goal.id)
                .findFirst();

        if (existing != null) {
          final updated = ModelMapper.nutritionGoalToLocal(
            goal,
            localId: existing.localId,
          );
          await db.localNutritionGoals.put(updated);
        } else {
          await db.localNutritionGoals.put(
            ModelMapper.nutritionGoalToLocal(goal),
          );
        }
      });
    } catch (e) {
      debugPrint('⚠️ Failed to sync nutrition goal: $e');
    }
  }

  /// Update nutrition goal - offline-first
  Future<void> updateNutritionGoal(int id, NutritionGoal goal) async {
    final db = _localDb.database;

    // Find local goal
    var localGoal =
        await db.localNutritionGoals.filter().serverIdEqualTo(id).findFirst();
    localGoal ??= await db.localNutritionGoals.get(id);

    if (localGoal == null) {
      throw Exception('Nutrition goal not found');
    }

    // Update locally first
    await db.writeTxn(() async {
      localGoal!.dailyCalories = goal.dailyCalories;
      localGoal.dailyProtein = goal.dailyProtein;
      localGoal.dailyCarbohydrates = goal.dailyCarbohydrates;
      localGoal.dailyFat = goal.dailyFat;
      localGoal.dailyFiber = goal.dailyFiber;
      localGoal.dailyWater = goal.dailyWater;
      localGoal.name = goal.name;
      localGoal.updatedAt = DateTime.now();
      localGoal.lastModifiedLocal = DateTime.now().toUtc();
      localGoal.isSynced = false;
      if (localGoal.serverId != null) {
        localGoal.syncStatus = 'pending_update';
      }
      await db.localNutritionGoals.put(localGoal);
    });

    debugPrint('✅ Updated nutrition goal locally');

    // Sync in background if online
    if (_connectivity.isOnline && localGoal.serverId != null) {
      _backgroundSync(
        () => _apiService.put<void>(
          ApiConfig.nutritionGoalById(localGoal!.serverId!),
          data: goal.toJson(),
        ),
        'Synced nutrition goal update',
      );
    }
  }

  /// Create nutrition goal - offline-first
  Future<NutritionGoal> createNutritionGoal(NutritionGoal goal) async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final now = DateTime.now();
    late LocalNutritionGoal savedGoal;

    await db.writeTxn(() async {
      // Deactivate other goals
      final activeGoals =
          await db.localNutritionGoals
              .filter()
              .userIdEqualTo(userId)
              .isActiveEqualTo(true)
              .findAll();

      for (final g in activeGoals) {
        g.isActive = false;
        g.lastModifiedLocal = now;
        g.isSynced = false;
        if (g.serverId != null) {
          g.syncStatus = 'pending_update';
        }
        await db.localNutritionGoals.put(g);
      }

      // Create new goal
      final local = LocalNutritionGoal(
        userId: userId,
        name: goal.name,
        dailyCalories: goal.dailyCalories,
        dailyProtein: goal.dailyProtein,
        dailyCarbohydrates: goal.dailyCarbohydrates,
        dailyFat: goal.dailyFat,
        dailyFiber: goal.dailyFiber,
        dailySodium: goal.dailySodium,
        dailySugar: goal.dailySugar,
        dailyWater: goal.dailyWater,
        isActive: true,
        createdAt: now,
        isSynced: false,
        syncStatus: 'pending_create',
        lastModifiedLocal: now,
      );
      await db.localNutritionGoals.put(local);
      savedGoal = local;
    });

    debugPrint('💾 Created nutrition goal locally');

    // Sync in background if online
    if (_connectivity.isOnline) {
      _backgroundSync(
        () => _syncNutritionGoalToServer(savedGoal),
        'Synced new nutrition goal',
      );
    }

    return ModelMapper.localToNutritionGoal(savedGoal);
  }

  /// Sync nutrition goal to server
  Future<void> _syncNutritionGoalToServer(LocalNutritionGoal local) async {
    try {
      final goal = ModelMapper.localToNutritionGoal(local);
      final data = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.nutritionGoals,
        data: goal.toJson(),
      );
      final serverGoal = NutritionGoal.fromJson(data);

      final db = _localDb.database;
      await db.writeTxn(() async {
        local.serverId = serverGoal.id;
        local.isSynced = true;
        local.syncStatus = 'synced';
        await db.localNutritionGoals.put(local);
      });
    } catch (e) {
      debugPrint('⚠️ Failed to sync nutrition goal: $e');
    }
  }

  // ============ Analytics (Server-only) ============

  /// Get nutrition progress
  Future<NutritionProgress> getNutritionProgress({DateTime? date}) async {
    if (_connectivity.isOnline) {
      final queryParams =
          date != null ? {'date': date.toIso8601String().split('T')[0]} : null;

      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.nutritionGoalProgress,
        queryParameters: queryParams,
      );
      return NutritionProgress.fromJson(data);
    }

    // Calculate locally if offline
    final db = _localDb.database;
    final userId = await _authService.getUserId();
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final targetDate = date ?? DateTime.now();
    final normalizedDate = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );

    final localLog =
        await db.localMealLogs
            .filter()
            .userIdEqualTo(userId)
            .dateEqualTo(normalizedDate)
            .findFirst();

    final localGoal =
        await db.localNutritionGoals
            .filter()
            .userIdEqualTo(userId)
            .isActiveEqualTo(true)
            .findFirst();

    final goal =
        localGoal != null
            ? ModelMapper.localToNutritionGoal(localGoal)
            : NutritionGoal.defaultGoal(userId);

    final consumed = NutritionTotals(
      calories: localLog?.totalCalories ?? 0,
      protein: localLog?.totalProtein ?? 0,
      carbohydrates: localLog?.totalCarbohydrates ?? 0,
      fat: localLog?.totalFat ?? 0,
    );

    final remaining = NutritionTotals(
      calories: (goal.dailyCalories - consumed.calories).clamp(
        0,
        double.infinity,
      ),
      protein: (goal.dailyProtein - consumed.protein).clamp(0, double.infinity),
      carbohydrates: (goal.dailyCarbohydrates - consumed.carbohydrates).clamp(
        0,
        double.infinity,
      ),
      fat: (goal.dailyFat - consumed.fat).clamp(0, double.infinity),
    );

    final percentageConsumed = NutritionPercentages(
      calories:
          goal.dailyCalories > 0
              ? (consumed.calories / goal.dailyCalories) * 100
              : 0,
      protein:
          goal.dailyProtein > 0
              ? (consumed.protein / goal.dailyProtein) * 100
              : 0,
      carbohydrates:
          goal.dailyCarbohydrates > 0
              ? (consumed.carbohydrates / goal.dailyCarbohydrates) * 100
              : 0,
      fat: goal.dailyFat > 0 ? (consumed.fat / goal.dailyFat) * 100 : 0,
    );

    return NutritionProgress(
      date: normalizedDate,
      goal: goal,
      consumed: consumed,
      remaining: remaining,
      percentageConsumed: percentageConsumed,
    );
  }

  /// Get nutrition dashboard data (goal + progress for a date)
  /// This is the primary method for dashboard display
  Future<NutritionDashboardData> getNutritionDashboard({DateTime? date}) async {
    final db = _localDb.database;
    final userId = await _authService.getUserId();

    if (userId == null) {
      throw Exception('User not authenticated');
    }

    if (_connectivity.isOnline) {
      try {
        final queryParams = date != null
            ? {'date': date.toIso8601String().split('T')[0]}
            : null;

        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.nutritionGoalDashboard,
          queryParameters: queryParams,
        );

        final goal = data['goal'] != null
            ? NutritionGoal.fromJson(data['goal'] as Map<String, dynamic>)
            : null;

        final progress = DailyNutritionProgress.fromJson(
          data['progress'] as Map<String, dynamic>,
        );

        debugPrint(
          '✅ Fetched nutrition dashboard - planned: ${progress.plannedCalories}, consumed: ${progress.consumedCalories}',
        );

        return NutritionDashboardData(
          date: date ?? DateTime.now(),
          goal: goal,
          progress: progress,
        );
      } catch (e) {
        debugPrint('⚠️ Failed to fetch nutrition dashboard: $e');
        // Fall through to offline calculation
      }
    }

    // Offline: calculate from local data
    final targetDate = date ?? DateTime.now();
    final normalizedDate = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );

    final localGoal = await db.localNutritionGoals
        .filter()
        .userIdEqualTo(userId)
        .isActiveEqualTo(true)
        .findFirst();

    final goal = localGoal != null
        ? ModelMapper.localToNutritionGoal(localGoal)
        : NutritionGoal.defaultGoal(userId);

    // Get meal log for the date to calculate planned/consumed
    final localLog = await db.localMealLogs
        .filter()
        .userIdEqualTo(userId)
        .dateEqualTo(normalizedDate)
        .findFirst();

    double plannedCalories = 0;
    double plannedProtein = 0;
    double plannedCarbs = 0;
    double plannedFat = 0;
    double consumedCalories = 0;
    double consumedProtein = 0;
    double consumedCarbs = 0;
    double consumedFat = 0;

    if (localLog != null) {
      final entries = await db.localMealEntrys
          .filter()
          .mealLogLocalIdEqualTo(localLog.localId)
          .findAll();

      for (final entry in entries) {
        plannedCalories += entry.totalCalories;
        plannedProtein += entry.totalProtein;
        plannedCarbs += entry.totalCarbohydrates;
        plannedFat += entry.totalFat;

        if (entry.isConsumed) {
          consumedCalories += entry.totalCalories;
          consumedProtein += entry.totalProtein;
          consumedCarbs += entry.totalCarbohydrates;
          consumedFat += entry.totalFat;
        }
      }
    }

    final progress = DailyNutritionProgress(
      id: 0,
      userId: userId,
      date: normalizedDate,
      nutritionGoalId: goal.id,
      plannedCalories: plannedCalories,
      plannedProtein: plannedProtein,
      plannedCarbohydrates: plannedCarbs,
      plannedFat: plannedFat,
      consumedCalories: consumedCalories,
      consumedProtein: consumedProtein,
      consumedCarbohydrates: consumedCarbs,
      consumedFat: consumedFat,
      createdAt: DateTime.now(),
    );

    return NutritionDashboardData(
      date: normalizedDate,
      goal: goal,
      progress: progress,
    );
  }

  /// Get streak info
  Future<StreakInfo> getStreak() async {
    if (_connectivity.isOnline) {
      try {
        final data = await _apiService.get<Map<String, dynamic>>(
          ApiConfig.nutritionAnalyticsStreak,
        );
        return StreakInfo.fromJson(data);
      } catch (e) {
        debugPrint('⚠️ Failed to fetch streak: $e');
      }
    }

    // Return default if offline
    return StreakInfo(currentStreak: 0, longestStreak: 0);
  }

  // ============ Meal Entries ============

  /// Mark meal as consumed - offline-first
  Future<void> markMealAsConsumed(
    int entryId, {
    bool isConsumed = true,
    DateTime? consumedAt,
  }) async {
    final db = _localDb.database;

    var localEntry =
        await db.localMealEntrys.filter().serverIdEqualTo(entryId).findFirst();
    localEntry ??= await db.localMealEntrys.get(entryId);

    if (localEntry == null) {
      throw Exception('Meal entry not found');
    }

    await db.writeTxn(() async {
      localEntry!.isConsumed = isConsumed;
      localEntry.consumedAt =
          isConsumed ? (consumedAt ?? DateTime.now()) : null;
      localEntry.lastModifiedLocal = DateTime.now().toUtc();
      localEntry.isSynced = false;
      if (localEntry.serverId != null) {
        localEntry.syncStatus = 'pending_update';
      }
      await db.localMealEntrys.put(localEntry);
    });

    if (_connectivity.isOnline && localEntry.serverId != null) {
      _backgroundSync(
        () => _apiService.put<void>(
          ApiConfig.mealEntryConsume(localEntry!.serverId!),
          data: {
            'isConsumed': isConsumed,
            if (consumedAt != null) 'consumedAt': consumedAt.toIso8601String(),
          },
        ),
        'Synced meal consumed status',
      );
    }
  }

  /// Clear all food for today
  Future<MealLog> clearAllFood(int mealLogId) async {
    final db = _localDb.database;

    var localLog =
        await db.localMealLogs.filter().serverIdEqualTo(mealLogId).findFirst();
    localLog ??= await db.localMealLogs.get(mealLogId);

    if (localLog == null) {
      throw Exception('Meal log not found');
    }

    await db.writeTxn(() async {
      // Get all entries for this log
      final entries =
          await db.localMealEntrys
              .filter()
              .mealLogLocalIdEqualTo(localLog!.localId)
              .findAll();

      for (final entry in entries) {
        // Delete all food items
        await db.localFoodItems
            .filter()
            .mealEntryLocalIdEqualTo(entry.localId)
            .deleteAll();

        // Reset entry totals
        entry.totalCalories = 0;
        entry.totalProtein = 0;
        entry.totalCarbohydrates = 0;
        entry.totalFat = 0;
        entry.isConsumed = false;
        entry.consumedAt = null;
        entry.lastModifiedLocal = DateTime.now().toUtc();
        entry.isSynced = false;
        if (entry.serverId != null) {
          entry.syncStatus = 'pending_update';
        }
        await db.localMealEntrys.put(entry);
      }

      // Reset log totals
      localLog.totalCalories = 0;
      localLog.totalProtein = 0;
      localLog.totalCarbohydrates = 0;
      localLog.totalFat = 0;
      localLog.lastModifiedLocal = DateTime.now().toUtc();
      localLog.isSynced = false;
      if (localLog.serverId != null) {
        localLog.syncStatus = 'pending_update';
      }
      await db.localMealLogs.put(localLog);
    });

    debugPrint('🗑️ Cleared all food locally');

    if (_connectivity.isOnline && localLog.serverId != null) {
      _backgroundSync(
        () => _apiService.post<Map<String, dynamic>>(
          ApiConfig.mealLogClear(localLog!.serverId!),
        ),
        'Synced clear all food',
      );
    }

    return await _localMealLogToMealLogWithEntries(db, localLog);
  }

  // ============ Food Item Operations ============

  /// Add a food item to a meal entry - offline-first
  Future<FoodItem> addFoodItem(FoodItem foodItem) async {
    final db = _localDb.database;

    // Find the parent meal entry
    var parentEntry =
        await db.localMealEntrys
            .filter()
            .serverIdEqualTo(foodItem.mealEntryId)
            .findFirst();
    parentEntry ??= await db.localMealEntrys.get(foodItem.mealEntryId);

    if (parentEntry == null) {
      throw Exception('Meal entry not found');
    }

    // Create local food item
    final localFoodItem = LocalFoodItem(
      serverId: null,
      mealEntryLocalId: parentEntry.localId,
      mealEntryServerId: parentEntry.serverId,
      foodTemplateId: foodItem.foodTemplateId,
      name: foodItem.name,
      brand: foodItem.brand,
      quantity: foodItem.quantity,
      servingSize: foodItem.servingSize,
      servingUnit: foodItem.servingUnit,
      calories: foodItem.calories,
      protein: foodItem.protein,
      carbohydrates: foodItem.carbohydrates,
      fat: foodItem.fat,
      fiber: foodItem.fiber,
      sugar: foodItem.sugar,
      sodium: foodItem.sodium,
      createdAt: DateTime.now().toUtc(),
      isSynced: false,
      syncStatus: 'pending_create',
      lastModifiedLocal: DateTime.now().toUtc(),
    );

    int insertedId = 0;
    await db.writeTxn(() async {
      insertedId = await db.localFoodItems.put(localFoodItem);

      // Update entry totals
      parentEntry!.totalCalories += foodItem.calories;
      parentEntry.totalProtein += foodItem.protein;
      parentEntry.totalCarbohydrates += foodItem.carbohydrates;
      parentEntry.totalFat += foodItem.fat;
      parentEntry.lastModifiedLocal = DateTime.now().toUtc();
      parentEntry.isSynced = false;
      if (parentEntry.serverId != null) {
        parentEntry.syncStatus = 'pending_update';
      }
      await db.localMealEntrys.put(parentEntry);

      // Update meal log totals
      final parentLog = await db.localMealLogs.get(parentEntry.mealLogLocalId);
      if (parentLog != null) {
        parentLog.totalCalories += foodItem.calories;
        parentLog.totalProtein += foodItem.protein;
        parentLog.totalCarbohydrates += foodItem.carbohydrates;
        parentLog.totalFat += foodItem.fat;
        parentLog.lastModifiedLocal = DateTime.now().toUtc();
        parentLog.isSynced = false;
        if (parentLog.serverId != null) {
          parentLog.syncStatus = 'pending_update';
        }
        await db.localMealLogs.put(parentLog);
      }
    });

    debugPrint('✅ Added food item locally: ${foodItem.name}');

    // Background sync if online
    if (_connectivity.isOnline && parentEntry.serverId != null) {
      _backgroundSync(
        () => _apiService.post<Map<String, dynamic>>(
          ApiConfig.foodItems,
          data: {
            'mealEntryId': parentEntry!.serverId,
            'foodTemplateId': foodItem.foodTemplateId,
            'name': foodItem.name,
            'brand': foodItem.brand,
            'quantity': foodItem.quantity,
            'servingSize': foodItem.servingSize,
            'servingUnit': foodItem.servingUnit,
            'calories': foodItem.calories,
            'protein': foodItem.protein,
            'carbohydrates': foodItem.carbohydrates,
            'fat': foodItem.fat,
            'fiber': foodItem.fiber,
            'sugar': foodItem.sugar,
            'sodium': foodItem.sodium,
          },
        ),
        'Synced new food item',
      );
    }

    return FoodItem(
      id: insertedId,
      mealEntryId: parentEntry.localId,
      foodTemplateId: foodItem.foodTemplateId,
      name: foodItem.name,
      brand: foodItem.brand,
      quantity: foodItem.quantity,
      servingSize: foodItem.servingSize,
      servingUnit: foodItem.servingUnit,
      calories: foodItem.calories,
      protein: foodItem.protein,
      carbohydrates: foodItem.carbohydrates,
      fat: foodItem.fat,
      fiber: foodItem.fiber,
      sugar: foodItem.sugar,
      sodium: foodItem.sodium,
      createdAt: localFoodItem.createdAt,
    );
  }

  /// Update food item quantity - offline-first
  Future<void> updateFoodQuantity(int foodItemId, double quantity) async {
    final db = _localDb.database;

    var localItem =
        await db.localFoodItems
            .filter()
            .serverIdEqualTo(foodItemId)
            .findFirst();
    localItem ??= await db.localFoodItems.get(foodItemId);

    if (localItem == null) {
      throw Exception('Food item not found');
    }

    // Calculate the difference for updating totals
    final oldQuantity = localItem.quantity;
    final quantityRatio = quantity / oldQuantity;

    final oldCalories = localItem.calories;
    final oldProtein = localItem.protein;
    final oldCarbs = localItem.carbohydrates;
    final oldFat = localItem.fat;

    final newCalories = oldCalories * quantityRatio;
    final newProtein = oldProtein * quantityRatio;
    final newCarbs = oldCarbs * quantityRatio;
    final newFat = oldFat * quantityRatio;

    await db.writeTxn(() async {
      // Update item
      localItem!.quantity = quantity;
      localItem.calories = newCalories;
      localItem.protein = newProtein;
      localItem.carbohydrates = newCarbs;
      localItem.fat = newFat;
      localItem.lastModifiedLocal = DateTime.now().toUtc();
      localItem.isSynced = false;
      if (localItem.serverId != null) {
        localItem.syncStatus = 'pending_update';
      }
      await db.localFoodItems.put(localItem);

      // Update entry totals
      final parentEntry = await db.localMealEntrys.get(
        localItem.mealEntryLocalId,
      );
      if (parentEntry != null) {
        parentEntry.totalCalories += (newCalories - oldCalories);
        parentEntry.totalProtein += (newProtein - oldProtein);
        parentEntry.totalCarbohydrates += (newCarbs - oldCarbs);
        parentEntry.totalFat += (newFat - oldFat);
        parentEntry.lastModifiedLocal = DateTime.now().toUtc();
        parentEntry.isSynced = false;
        if (parentEntry.serverId != null) {
          parentEntry.syncStatus = 'pending_update';
        }
        await db.localMealEntrys.put(parentEntry);

        // Update meal log totals
        final parentLog = await db.localMealLogs.get(
          parentEntry.mealLogLocalId,
        );
        if (parentLog != null) {
          parentLog.totalCalories += (newCalories - oldCalories);
          parentLog.totalProtein += (newProtein - oldProtein);
          parentLog.totalCarbohydrates += (newCarbs - oldCarbs);
          parentLog.totalFat += (newFat - oldFat);
          parentLog.lastModifiedLocal = DateTime.now().toUtc();
          parentLog.isSynced = false;
          if (parentLog.serverId != null) {
            parentLog.syncStatus = 'pending_update';
          }
          await db.localMealLogs.put(parentLog);
        }
      }
    });

    debugPrint('✅ Updated food quantity locally');

    // Background sync if online
    if (_connectivity.isOnline && localItem.serverId != null) {
      _backgroundSync(
        () => _apiService.patch<void>(
          ApiConfig.foodItemQuantity(localItem!.serverId!),
          data: {'quantity': quantity},
        ),
        'Synced food quantity update',
      );
    }
  }

  // ============ Nutrition Calculator ============

  /// Calculate personalized nutrition targets from user metrics and goal
  Future<CalculatedNutrition?> calculateNutritionFromMetrics({
    required String goalType,
    double? targetWeightChange,
    int? timeframeWeeks,
  }) async {
    if (!_connectivity.isOnline) {
      return null;
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.nutritionCalculate,
        data: {
          'goalType': goalType,
          if (targetWeightChange != null)
            'targetWeightChange': targetWeightChange,
          if (timeframeWeeks != null) 'timeframeWeeks': timeframeWeeks,
        },
      );

      return CalculatedNutrition.fromJson(response);
    } catch (e) {
      debugPrint('Failed to calculate nutrition: $e');
      return null;
    }
  }

  /// Calculate and save nutrition targets as active goal
  /// Throws [OfflineException] if not connected to internet
  Future<CalculatedNutrition?> calculateAndSaveNutrition({
    required String goalType,
    double? targetWeightChange,
    int? timeframeWeeks,
  }) async {
    if (!_connectivity.isOnline) {
      throw OfflineNutritionException(
        'Nutrition calculation requires an internet connection. '
        'Your goal has been saved and nutrition targets will be calculated when you\'re back online.',
      );
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.nutritionCalculateAndSave,
        data: {
          'goalType': goalType,
          if (targetWeightChange != null)
            'targetWeightChange': targetWeightChange,
          if (timeframeWeeks != null) 'timeframeWeeks': timeframeWeeks,
        },
      );

      final result = CalculatedNutrition.fromJson(response);

      // Update local cache with new goal
      if (result.nutritionGoalId != null) {
        final db = _localDb.database;
        final userId = await _authService.getUserId();
        if (userId != null) {
          await _syncNutritionGoalFromServer(db, userId);
        }
      }

      return result;
    } on DioException catch (e) {
      // Check for missing metrics error (400 with specific code)
      if (e.response?.statusCode == 400) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> &&
            (data['code'] == 'MISSING_WEIGHT' ||
                data['code'] == 'MISSING_HEIGHT')) {
          throw MissingMetricsException.fromJson(data);
        }
      }
      debugPrint('Failed to calculate and save nutrition: $e');
      return null;
    } catch (e) {
      debugPrint('Failed to calculate and save nutrition: $e');
      return null;
    }
  }

  /// Get available activity levels
  Future<List<ActivityLevelOption>> getActivityLevels() async {
    if (_connectivity.isOnline) {
      try {
        final response = await _apiService.get<List<dynamic>>(
          ApiConfig.activityLevels,
        );
        return response
            .map(
              (json) =>
                  ActivityLevelOption.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      } catch (e) {
        debugPrint('Failed to fetch activity levels: $e');
      }
    }

    // Return default activity levels if offline
    return [
      ActivityLevelOption(
        value: 'Sedentary',
        label: 'Sedentary',
        description: 'Little or no exercise, desk job',
      ),
      ActivityLevelOption(
        value: 'LightlyActive',
        label: 'Lightly Active',
        description: 'Light exercise 1-3 days/week',
      ),
      ActivityLevelOption(
        value: 'ModeratelyActive',
        label: 'Moderately Active',
        description: 'Moderate exercise 3-5 days/week',
      ),
      ActivityLevelOption(
        value: 'VeryActive',
        label: 'Very Active',
        description: 'Hard exercise 6-7 days/week',
      ),
      ActivityLevelOption(
        value: 'ExtremelyActive',
        label: 'Extremely Active',
        description: 'Very hard exercise, physical job',
      ),
    ];
  }

  // ============ AI Food Alternatives ============

  /// Get AI-powered food alternatives
  Future<List<FoodAlternative>> getFoodAlternatives({
    required String foodName,
    required double calories,
    required double protein,
    required double carbohydrates,
    required double fat,
  }) async {
    if (!_connectivity.isOnline) {
      return [];
    }

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.chatFoodSuggestion,
        data: {
          'foodName': foodName,
          'calories': calories,
          'protein': protein,
          'carbohydrates': carbohydrates,
          'fat': fat,
        },
      );

      final alternatives = response['alternatives'] as List<dynamic>? ?? [];
      return alternatives
          .map((alt) => FoodAlternative.fromJson(alt as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Failed to get food alternatives: $e');
      return [];
    }
  }
}

/// Model for AI-suggested food alternatives
class FoodAlternative {
  final String name;
  final String? brand;
  final double servingSize;
  final String servingUnit;
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;
  final String? reason;
  final String? category;

  FoodAlternative({
    required this.name,
    this.brand,
    required this.servingSize,
    required this.servingUnit,
    required this.calories,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
    this.reason,
    this.category,
  });

  factory FoodAlternative.fromJson(Map<String, dynamic> json) {
    return FoodAlternative(
      name: json['name'] as String,
      brand: json['brand'] as String?,
      servingSize: (json['servingSize'] as num?)?.toDouble() ?? 100,
      servingUnit: json['servingUnit'] as String? ?? 'g',
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      carbohydrates: (json['carbohydrates'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      reason: json['reason'] as String?,
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'brand': brand,
    'servingSize': servingSize,
    'servingUnit': servingUnit,
    'calories': calories,
    'protein': protein,
    'carbohydrates': carbohydrates,
    'fat': fat,
    'reason': reason,
    'category': category,
  };
}

/// Model for calculated nutrition targets
class CalculatedNutrition {
  final int? nutritionGoalId;
  final double dailyCalories;
  final double dailyProtein;
  final double dailyCarbohydrates;
  final double dailyFat;
  final double dailyFiber;
  final double dailyWater;
  final double bmr;
  final double tdee;
  final double calorieAdjustment;
  final double expectedWeeklyWeightChange;
  final String explanation;
  final String? warning;
  final String? recommendation;
  final UserMetricsSummary? userMetrics;

  CalculatedNutrition({
    this.nutritionGoalId,
    required this.dailyCalories,
    required this.dailyProtein,
    required this.dailyCarbohydrates,
    required this.dailyFat,
    required this.dailyFiber,
    required this.dailyWater,
    required this.bmr,
    required this.tdee,
    required this.calorieAdjustment,
    required this.expectedWeeklyWeightChange,
    required this.explanation,
    this.warning,
    this.recommendation,
    this.userMetrics,
  });

  /// Returns true if there's a warning about aggressive targets
  bool get hasWarning => warning != null && warning!.isNotEmpty;

  factory CalculatedNutrition.fromJson(Map<String, dynamic> json) {
    return CalculatedNutrition(
      nutritionGoalId: json['nutritionGoalId'] as int?,
      dailyCalories: (json['dailyCalories'] as num).toDouble(),
      dailyProtein: (json['dailyProtein'] as num).toDouble(),
      dailyCarbohydrates: (json['dailyCarbohydrates'] as num).toDouble(),
      dailyFat: (json['dailyFat'] as num).toDouble(),
      dailyFiber: (json['dailyFiber'] as num?)?.toDouble() ?? 25,
      dailyWater: (json['dailyWater'] as num?)?.toDouble() ?? 2000,
      bmr: (json['bmr'] as num).toDouble(),
      tdee: (json['tdee'] as num).toDouble(),
      calorieAdjustment: (json['calorieAdjustment'] as num).toDouble(),
      expectedWeeklyWeightChange:
          (json['expectedWeeklyWeightChange'] as num).toDouble(),
      explanation: json['explanation'] as String? ?? '',
      warning: json['warning'] as String?,
      recommendation: json['recommendation'] as String?,
      userMetrics:
          json['userMetrics'] != null
              ? UserMetricsSummary.fromJson(
                json['userMetrics'] as Map<String, dynamic>,
              )
              : null,
    );
  }
}

/// Summary of user metrics used in calculation
class UserMetricsSummary {
  final double weightKg;
  final double weightLbs;
  final double heightCm;
  final int age;
  final String gender;
  final String activityLevel;

  UserMetricsSummary({
    required this.weightKg,
    required this.weightLbs,
    required this.heightCm,
    required this.age,
    required this.gender,
    required this.activityLevel,
  });

  factory UserMetricsSummary.fromJson(Map<String, dynamic> json) {
    return UserMetricsSummary(
      weightKg: (json['weightKg'] as num).toDouble(),
      weightLbs: (json['weightLbs'] as num).toDouble(),
      heightCm: (json['heightCm'] as num).toDouble(),
      age: json['age'] as int,
      gender: json['gender'] as String? ?? '',
      activityLevel: json['activityLevel'] as String? ?? '',
    );
  }
}

/// Activity level option for dropdown
class ActivityLevelOption {
  final String value;
  final String label;
  final String description;

  ActivityLevelOption({
    required this.value,
    required this.label,
    required this.description,
  });

  factory ActivityLevelOption.fromJson(Map<String, dynamic> json) {
    return ActivityLevelOption(
      value: json['value'] as String,
      label: json['label'] as String,
      description: json['description'] as String? ?? '',
    );
  }
}

/// Exception thrown when nutrition calculation is attempted offline
class OfflineNutritionException implements Exception {
  final String message;

  OfflineNutritionException(this.message);

  @override
  String toString() => message;
}

/// Exception thrown when required body metrics are missing
class MissingMetricsException implements Exception {
  final String message;
  final String code;
  final String action;
  final List<String> missingFields;

  MissingMetricsException({
    required this.message,
    required this.code,
    this.action = 'GO_TO_BODY_METRICS',
    this.missingFields = const [],
  });

  @override
  String toString() => message;

  factory MissingMetricsException.fromJson(Map<String, dynamic> json) {
    return MissingMetricsException(
      message: json['message'] as String? ?? 'Missing required body metrics',
      code: json['code'] as String? ?? 'MISSING_METRICS',
      action: json['action'] as String? ?? 'GO_TO_BODY_METRICS',
      missingFields:
          (json['missingFields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

/// Combined dashboard data with goal and progress
class NutritionDashboardData {
  final DateTime date;
  final NutritionGoal? goal;
  final DailyNutritionProgress progress;

  NutritionDashboardData({
    required this.date,
    this.goal,
    required this.progress,
  });
}
