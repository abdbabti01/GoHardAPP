import '../../models/session.dart';
import '../../models/exercise.dart';
import '../../models/exercise_set.dart';
import '../../models/exercise_template.dart';
import '../../models/meal_log.dart';
import '../../models/meal_entry.dart';
import '../../models/food_item.dart';
import '../../models/nutrition_goal.dart';
import '../../models/food_template.dart';
import '../models/local_session.dart';
import '../models/local_exercise.dart';
import '../models/local_exercise_set.dart';
import '../models/local_exercise_template.dart';
import '../models/local_meal_log.dart';
import '../models/local_meal_entry.dart';
import '../models/local_food_item.dart';
import '../models/local_nutrition_goal.dart';
import '../models/local_food_template.dart';

/// Service for converting between API models and local database models
class ModelMapper {
  // ========== Session Mapping ==========

  /// Convert API Session to LocalSession
  /// Used when caching data from server
  static LocalSession sessionToLocal(
    Session apiSession, {
    int? localId,
    bool isSynced = true,
  }) {
    // Determine sync status:
    // - If synced: 'synced'
    // - If not synced and has serverId (exists on server): 'pending_update'
    // - If not synced and no serverId (new local): 'pending_create'
    String syncStatus;
    if (isSynced) {
      syncStatus = 'synced';
    } else if (apiSession.id > 0) {
      // Session exists on server, we're updating it
      syncStatus = 'pending_update';
    } else {
      // New session not yet on server
      syncStatus = 'pending_create';
    }

    final session = LocalSession(
      serverId: apiSession.id,
      userId: apiSession.userId,
      date: apiSession.date,
      duration: apiSession.duration,
      notes: apiSession.notes,
      type: apiSession.type,
      name: apiSession.name,
      status: apiSession.status,
      startedAt: apiSession.startedAt,
      completedAt: apiSession.completedAt,
      pausedAt: apiSession.pausedAt,
      programId: apiSession.programId, // Fix: preserve programId when caching
      programWorkoutId:
          apiSession
              .programWorkoutId, // Fix: preserve programWorkoutId when caching
      isSynced: isSynced,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: DateTime.now(),
    );

    // Preserve existing localId if updating an existing session
    if (localId != null) {
      session.localId = localId;
    }

    return session;
  }

  /// Convert LocalSession to API Session
  /// Used when sending local data to server or displaying in UI
  static Session localToSession(
    LocalSession localSession, {
    List<Exercise> exercises = const [],
  }) {
    // CRITICAL: Isar stores DateTime without timezone info.
    // When we stored UTC timestamps, they come back as local DateTime with the same raw value.
    // We need to reconstruct them as UTC to avoid timezone drift.
    // Example: Stored 15:00 UTC -> Isar returns 15:00 local -> must convert to 15:00 UTC
    DateTime? toUtcTimestamp(DateTime? dt) {
      if (dt == null) return null;
      // If already UTC, return as-is
      if (dt.isUtc) return dt;
      // Construct UTC DateTime from the raw components (not using toUtc which would shift the time)
      return DateTime.utc(
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second,
        dt.millisecond,
        dt.microsecond,
      );
    }

    return Session(
      id:
          localSession.serverId ??
          localSession.localId, // Use localId for unsynced items
      userId: localSession.userId,
      date: localSession.date,
      duration: localSession.duration,
      notes: localSession.notes,
      type: localSession.type,
      name: localSession.name,
      status: localSession.status,
      startedAt: toUtcTimestamp(localSession.startedAt),
      completedAt: toUtcTimestamp(localSession.completedAt),
      pausedAt: toUtcTimestamp(localSession.pausedAt),
      programId: localSession.programId,
      programWorkoutId: localSession.programWorkoutId,
      exercises: exercises,
    );
  }

  // ========== Exercise Mapping ==========

  /// Convert API Exercise to LocalExercise
  /// Requires localSessionId for parent reference
  static LocalExercise exerciseToLocal(
    Exercise apiExercise, {
    required int sessionLocalId,
    int? sessionServerId,
    int? localId,
    bool isSynced = true,
  }) {
    final exercise = LocalExercise(
      serverId: apiExercise.id,
      sessionLocalId: sessionLocalId,
      sessionServerId: sessionServerId ?? apiExercise.sessionId,
      name: apiExercise.name,
      duration: apiExercise.duration,
      restTime: apiExercise.restTime,
      notes: apiExercise.notes,
      exerciseTemplateId: apiExercise.exerciseTemplateId,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: DateTime.now(),
    );

    // Preserve existing localId if updating an existing exercise
    if (localId != null) {
      exercise.localId = localId;
    }

    return exercise;
  }

  /// Convert LocalExercise to API Exercise
  static Exercise localToExercise(
    LocalExercise localExercise, {
    List<ExerciseSet> exerciseSets = const [],
  }) {
    return Exercise(
      id: localExercise.serverId ?? localExercise.localId,
      sessionId: localExercise.sessionServerId ?? 0,
      name: localExercise.name,
      duration: localExercise.duration,
      restTime: localExercise.restTime,
      notes: localExercise.notes,
      exerciseTemplateId: localExercise.exerciseTemplateId,
      exerciseSets: exerciseSets,
    );
  }

  // ========== ExerciseSet Mapping ==========

  /// Convert API ExerciseSet to LocalExerciseSet
  /// Requires exerciseLocalId for parent reference
  static LocalExerciseSet exerciseSetToLocal(
    ExerciseSet apiSet, {
    required int exerciseLocalId,
    int? exerciseServerId,
    int? localId,
    bool isSynced = true,
  }) {
    final set = LocalExerciseSet(
      serverId: apiSet.id,
      exerciseLocalId: exerciseLocalId,
      exerciseServerId: exerciseServerId ?? apiSet.exerciseId,
      setNumber: apiSet.setNumber,
      reps: apiSet.reps,
      weight: apiSet.weight,
      duration: apiSet.duration,
      isCompleted: apiSet.isCompleted,
      completedAt: apiSet.completedAt,
      notes: apiSet.notes,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: DateTime.now(),
    );

    // Preserve existing localId if updating an existing set
    if (localId != null) {
      set.localId = localId;
    }

    return set;
  }

  /// Convert LocalExerciseSet to API ExerciseSet
  static ExerciseSet localToExerciseSet(LocalExerciseSet localSet) {
    return ExerciseSet(
      id: localSet.serverId ?? 0,
      exerciseId: localSet.exerciseServerId ?? 0,
      setNumber: localSet.setNumber,
      reps: localSet.reps,
      weight: localSet.weight,
      duration: localSet.duration,
      isCompleted: localSet.isCompleted,
      completedAt: localSet.completedAt,
      notes: localSet.notes,
    );
  }

  // ========== ExerciseTemplate Mapping ==========

  /// Convert API ExerciseTemplate to LocalExerciseTemplate
  static LocalExerciseTemplate exerciseTemplateToLocal(
    ExerciseTemplate apiTemplate, {
    int? localId,
    bool isSynced = true,
  }) {
    return LocalExerciseTemplate(
      serverId: apiTemplate.id,
      name: apiTemplate.name,
      description: apiTemplate.description,
      category: apiTemplate.category,
      muscleGroup: apiTemplate.muscleGroup,
      equipment: apiTemplate.equipment,
      difficulty: apiTemplate.difficulty,
      videoUrl: apiTemplate.videoUrl,
      imageUrl: apiTemplate.imageUrl,
      instructions: apiTemplate.instructions,
      isCustom: apiTemplate.isCustom,
      createdByUserId: apiTemplate.createdByUserId,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: DateTime.now(),
    );
  }

  /// Convert LocalExerciseTemplate to API ExerciseTemplate
  static ExerciseTemplate localToExerciseTemplate(
    LocalExerciseTemplate localTemplate,
  ) {
    return ExerciseTemplate(
      id: localTemplate.serverId ?? 0,
      name: localTemplate.name,
      description: localTemplate.description,
      category: localTemplate.category,
      muscleGroup: localTemplate.muscleGroup,
      equipment: localTemplate.equipment,
      difficulty: localTemplate.difficulty,
      videoUrl: localTemplate.videoUrl,
      imageUrl: localTemplate.imageUrl,
      instructions: localTemplate.instructions,
      isCustom: localTemplate.isCustom,
      createdByUserId: localTemplate.createdByUserId,
    );
  }

  // ========== Batch Mapping Helpers ==========

  /// Convert a list of API Sessions to LocalSessions
  static List<LocalSession> sessionsToLocal(
    List<Session> apiSessions, {
    bool isSynced = true,
  }) {
    return apiSessions
        .map((session) => sessionToLocal(session, isSynced: isSynced))
        .toList();
  }

  /// Convert a list of LocalSessions to API Sessions
  static List<Session> localToSessions(List<LocalSession> localSessions) {
    return localSessions.map((session) => localToSession(session)).toList();
  }

  /// Convert a list of API Exercises to LocalExercises
  static List<LocalExercise> exercisesToLocal(
    List<Exercise> apiExercises, {
    required int sessionLocalId,
    int? sessionServerId,
    bool isSynced = true,
  }) {
    return apiExercises
        .map(
          (exercise) => exerciseToLocal(
            exercise,
            sessionLocalId: sessionLocalId,
            sessionServerId: sessionServerId,
            isSynced: isSynced,
          ),
        )
        .toList();
  }

  /// Convert a list of LocalExercises to API Exercises
  static List<Exercise> localToExercises(List<LocalExercise> localExercises) {
    return localExercises.map((exercise) => localToExercise(exercise)).toList();
  }

  /// Convert a list of API ExerciseSets to LocalExerciseSets
  static List<LocalExerciseSet> exerciseSetsToLocal(
    List<ExerciseSet> apiSets, {
    required int exerciseLocalId,
    int? exerciseServerId,
    bool isSynced = true,
  }) {
    return apiSets
        .map(
          (set) => exerciseSetToLocal(
            set,
            exerciseLocalId: exerciseLocalId,
            exerciseServerId: exerciseServerId,
            isSynced: isSynced,
          ),
        )
        .toList();
  }

  /// Convert a list of LocalExerciseSets to API ExerciseSets
  static List<ExerciseSet> localToExerciseSets(
    List<LocalExerciseSet> localSets,
  ) {
    return localSets.map((set) => localToExerciseSet(set)).toList();
  }

  /// Convert a list of API ExerciseTemplates to LocalExerciseTemplates
  static List<LocalExerciseTemplate> exerciseTemplatesToLocal(
    List<ExerciseTemplate> apiTemplates, {
    bool isSynced = true,
  }) {
    return apiTemplates
        .map(
          (template) => exerciseTemplateToLocal(template, isSynced: isSynced),
        )
        .toList();
  }

  /// Convert a list of LocalExerciseTemplates to API ExerciseTemplates
  static List<ExerciseTemplate> localToExerciseTemplates(
    List<LocalExerciseTemplate> localTemplates,
  ) {
    return localTemplates
        .map((template) => localToExerciseTemplate(template))
        .toList();
  }

  // ========== MealLog Mapping ==========

  /// Convert API MealLog to LocalMealLog
  static LocalMealLog mealLogToLocal(
    MealLog apiMealLog, {
    int? localId,
    bool isSynced = true,
  }) {
    String syncStatus;
    if (isSynced) {
      syncStatus = 'synced';
    } else if (apiMealLog.id > 0) {
      syncStatus = 'pending_update';
    } else {
      syncStatus = 'pending_create';
    }

    final mealLog = LocalMealLog(
      serverId: apiMealLog.id > 0 ? apiMealLog.id : null,
      userId: apiMealLog.userId,
      date: apiMealLog.date,
      notes: apiMealLog.notes,
      waterIntake: apiMealLog.waterIntake,
      totalCalories: apiMealLog.totalCalories,
      totalProtein: apiMealLog.totalProtein,
      totalCarbohydrates: apiMealLog.totalCarbohydrates,
      totalFat: apiMealLog.totalFat,
      totalFiber: apiMealLog.totalFiber,
      totalSodium: apiMealLog.totalSodium,
      createdAt: apiMealLog.createdAt,
      updatedAt: apiMealLog.updatedAt,
      isSynced: isSynced,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      mealLog.localId = localId;
    }

    return mealLog;
  }

  /// Convert LocalMealLog to API MealLog
  static MealLog localToMealLog(
    LocalMealLog localMealLog, {
    List<MealEntry>? mealEntries,
  }) {
    return MealLog(
      id: localMealLog.serverId ?? localMealLog.localId,
      userId: localMealLog.userId,
      date: localMealLog.date,
      notes: localMealLog.notes,
      waterIntake: localMealLog.waterIntake,
      totalCalories: localMealLog.totalCalories,
      totalProtein: localMealLog.totalProtein,
      totalCarbohydrates: localMealLog.totalCarbohydrates,
      totalFat: localMealLog.totalFat,
      totalFiber: localMealLog.totalFiber,
      totalSodium: localMealLog.totalSodium,
      createdAt: localMealLog.createdAt,
      updatedAt: localMealLog.updatedAt,
      mealEntries: mealEntries,
    );
  }

  // ========== MealEntry Mapping ==========

  /// Convert API MealEntry to LocalMealEntry
  static LocalMealEntry mealEntryToLocal(
    MealEntry apiMealEntry, {
    required int mealLogLocalId,
    int? mealLogServerId,
    int? localId,
    bool isSynced = true,
  }) {
    final mealEntry = LocalMealEntry(
      serverId: apiMealEntry.id > 0 ? apiMealEntry.id : null,
      mealLogLocalId: mealLogLocalId,
      mealLogServerId: mealLogServerId ?? apiMealEntry.mealLogId,
      mealType: apiMealEntry.mealType,
      name: apiMealEntry.name,
      scheduledTime: apiMealEntry.scheduledTime,
      isConsumed: apiMealEntry.isConsumed,
      consumedAt: apiMealEntry.consumedAt,
      notes: apiMealEntry.notes,
      totalCalories: apiMealEntry.totalCalories,
      totalProtein: apiMealEntry.totalProtein,
      totalCarbohydrates: apiMealEntry.totalCarbohydrates,
      totalFat: apiMealEntry.totalFat,
      totalFiber: apiMealEntry.totalFiber,
      totalSodium: apiMealEntry.totalSodium,
      createdAt: apiMealEntry.createdAt,
      updatedAt: apiMealEntry.updatedAt,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      mealEntry.localId = localId;
    }

    return mealEntry;
  }

  /// Convert LocalMealEntry to API MealEntry
  static MealEntry localToMealEntry(
    LocalMealEntry localMealEntry, {
    List<FoodItem>? foodItems,
  }) {
    return MealEntry(
      id: localMealEntry.serverId ?? localMealEntry.localId,
      mealLogId:
          localMealEntry.mealLogServerId ?? localMealEntry.mealLogLocalId,
      mealType: localMealEntry.mealType,
      name: localMealEntry.name,
      scheduledTime: localMealEntry.scheduledTime,
      isConsumed: localMealEntry.isConsumed,
      consumedAt: localMealEntry.consumedAt,
      notes: localMealEntry.notes,
      totalCalories: localMealEntry.totalCalories,
      totalProtein: localMealEntry.totalProtein,
      totalCarbohydrates: localMealEntry.totalCarbohydrates,
      totalFat: localMealEntry.totalFat,
      totalFiber: localMealEntry.totalFiber,
      totalSodium: localMealEntry.totalSodium,
      createdAt: localMealEntry.createdAt,
      updatedAt: localMealEntry.updatedAt,
      foodItems: foodItems,
    );
  }

  // ========== FoodItem Mapping ==========

  /// Convert API FoodItem to LocalFoodItem
  static LocalFoodItem foodItemToLocal(
    FoodItem apiFoodItem, {
    required int mealEntryLocalId,
    int? mealEntryServerId,
    int? localId,
    bool isSynced = true,
  }) {
    final foodItem = LocalFoodItem(
      serverId: apiFoodItem.id > 0 ? apiFoodItem.id : null,
      mealEntryLocalId: mealEntryLocalId,
      mealEntryServerId: mealEntryServerId ?? apiFoodItem.mealEntryId,
      foodTemplateId: apiFoodItem.foodTemplateId,
      name: apiFoodItem.name,
      brand: apiFoodItem.brand,
      quantity: apiFoodItem.quantity,
      servingSize: apiFoodItem.servingSize,
      servingUnit: apiFoodItem.servingUnit,
      calories: apiFoodItem.calories,
      protein: apiFoodItem.protein,
      carbohydrates: apiFoodItem.carbohydrates,
      fat: apiFoodItem.fat,
      fiber: apiFoodItem.fiber,
      sugar: apiFoodItem.sugar,
      sodium: apiFoodItem.sodium,
      createdAt: apiFoodItem.createdAt,
      updatedAt: apiFoodItem.updatedAt,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      foodItem.localId = localId;
    }

    return foodItem;
  }

  /// Convert LocalFoodItem to API FoodItem
  static FoodItem localToFoodItem(LocalFoodItem localFoodItem) {
    return FoodItem(
      id: localFoodItem.serverId ?? localFoodItem.localId,
      mealEntryId:
          localFoodItem.mealEntryServerId ?? localFoodItem.mealEntryLocalId,
      foodTemplateId: localFoodItem.foodTemplateId,
      name: localFoodItem.name,
      brand: localFoodItem.brand,
      quantity: localFoodItem.quantity,
      servingSize: localFoodItem.servingSize,
      servingUnit: localFoodItem.servingUnit,
      calories: localFoodItem.calories,
      protein: localFoodItem.protein,
      carbohydrates: localFoodItem.carbohydrates,
      fat: localFoodItem.fat,
      fiber: localFoodItem.fiber,
      sugar: localFoodItem.sugar,
      sodium: localFoodItem.sodium,
      createdAt: localFoodItem.createdAt,
      updatedAt: localFoodItem.updatedAt,
    );
  }

  // ========== NutritionGoal Mapping ==========

  /// Convert API NutritionGoal to LocalNutritionGoal
  static LocalNutritionGoal nutritionGoalToLocal(
    NutritionGoal apiGoal, {
    int? localId,
    bool isSynced = true,
  }) {
    String syncStatus;
    if (isSynced) {
      syncStatus = 'synced';
    } else if (apiGoal.id > 0) {
      syncStatus = 'pending_update';
    } else {
      syncStatus = 'pending_create';
    }

    final goal = LocalNutritionGoal(
      serverId: apiGoal.id > 0 ? apiGoal.id : null,
      userId: apiGoal.userId,
      name: apiGoal.name,
      dailyCalories: apiGoal.dailyCalories,
      dailyProtein: apiGoal.dailyProtein,
      dailyCarbohydrates: apiGoal.dailyCarbohydrates,
      dailyFat: apiGoal.dailyFat,
      dailyFiber: apiGoal.dailyFiber,
      dailySodium: apiGoal.dailySodium,
      dailySugar: apiGoal.dailySugar,
      dailyWater: apiGoal.dailyWater,
      proteinPercentage: apiGoal.proteinPercentage,
      carbohydratesPercentage: apiGoal.carbohydratesPercentage,
      fatPercentage: apiGoal.fatPercentage,
      isActive: apiGoal.isActive,
      createdAt: apiGoal.createdAt,
      updatedAt: apiGoal.updatedAt,
      isSynced: isSynced,
      syncStatus: syncStatus,
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      goal.localId = localId;
    }

    return goal;
  }

  /// Convert LocalNutritionGoal to API NutritionGoal
  static NutritionGoal localToNutritionGoal(LocalNutritionGoal localGoal) {
    return NutritionGoal(
      id: localGoal.serverId ?? localGoal.localId,
      userId: localGoal.userId,
      name: localGoal.name,
      dailyCalories: localGoal.dailyCalories,
      dailyProtein: localGoal.dailyProtein,
      dailyCarbohydrates: localGoal.dailyCarbohydrates,
      dailyFat: localGoal.dailyFat,
      dailyFiber: localGoal.dailyFiber,
      dailySodium: localGoal.dailySodium,
      dailySugar: localGoal.dailySugar,
      dailyWater: localGoal.dailyWater,
      proteinPercentage: localGoal.proteinPercentage,
      carbohydratesPercentage: localGoal.carbohydratesPercentage,
      fatPercentage: localGoal.fatPercentage,
      isActive: localGoal.isActive,
      createdAt: localGoal.createdAt,
      updatedAt: localGoal.updatedAt,
    );
  }

  // ========== FoodTemplate Mapping ==========

  /// Convert API FoodTemplate to LocalFoodTemplate
  static LocalFoodTemplate foodTemplateToLocal(
    FoodTemplate apiTemplate, {
    int? localId,
    bool isSynced = true,
  }) {
    final template = LocalFoodTemplate(
      serverId: apiTemplate.id > 0 ? apiTemplate.id : null,
      name: apiTemplate.name,
      brand: apiTemplate.brand,
      category: apiTemplate.category,
      barcode: apiTemplate.barcode,
      servingSize: apiTemplate.servingSize,
      servingUnit: apiTemplate.servingUnit,
      calories: apiTemplate.calories,
      protein: apiTemplate.protein,
      carbohydrates: apiTemplate.carbohydrates,
      fat: apiTemplate.fat,
      fiber: apiTemplate.fiber,
      sugar: apiTemplate.sugar,
      sodium: apiTemplate.sodium,
      description: apiTemplate.description,
      imageUrl: apiTemplate.imageUrl,
      isCustom: apiTemplate.isCustom,
      createdByUserId: apiTemplate.createdByUserId,
      createdAt: apiTemplate.createdAt,
      updatedAt: apiTemplate.updatedAt,
      isSynced: isSynced,
      syncStatus: isSynced ? 'synced' : 'pending_create',
      lastModifiedLocal: DateTime.now(),
      lastModifiedServer: isSynced ? DateTime.now() : null,
    );

    if (localId != null) {
      template.localId = localId;
    }

    return template;
  }

  /// Convert LocalFoodTemplate to API FoodTemplate
  static FoodTemplate localToFoodTemplate(LocalFoodTemplate localTemplate) {
    return FoodTemplate(
      id: localTemplate.serverId ?? localTemplate.localId,
      name: localTemplate.name,
      brand: localTemplate.brand,
      category: localTemplate.category,
      barcode: localTemplate.barcode,
      servingSize: localTemplate.servingSize,
      servingUnit: localTemplate.servingUnit,
      calories: localTemplate.calories,
      protein: localTemplate.protein,
      carbohydrates: localTemplate.carbohydrates,
      fat: localTemplate.fat,
      fiber: localTemplate.fiber,
      sugar: localTemplate.sugar,
      sodium: localTemplate.sodium,
      description: localTemplate.description,
      imageUrl: localTemplate.imageUrl,
      isCustom: localTemplate.isCustom,
      createdByUserId: localTemplate.createdByUserId,
      createdAt: localTemplate.createdAt,
      updatedAt: localTemplate.updatedAt,
    );
  }
}
