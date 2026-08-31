import 'package:isar/isar.dart';

part 'workout_template.g.dart';

/// Workout template for creating recurring workout plans.
///
/// ## Identity
///
/// Three identities are kept strictly separate and never conflated:
///
/// - [localId] - the local Isar row identity. Auto-incremented, never sent
///   to or received from the server.
/// - [serverId] - the server-assigned template id, or `null` for a template
///   created offline that has not yet been pushed. Server-round-tripping
///   operations look a row up via [serverId], never via [localId].
/// - [cachedForUserId] - the authenticated device user this row was cached
///   for. Stamped from the captured session context at every write, never
///   from response JSON. A legacy row written before this field existed
///   deserializes with `cachedForUserId == null` and stays invisible to
///   every authenticated read until the next valid online refresh restamps
///   it. Isar treats a new nullable property as a compatible schema
///   upgrade, so no manual migration is required.
///
/// [createdByUserId] is a fourth, unrelated identity: the server identity of
/// the template's *creator* (`null` for system templates). It is identical
/// on every device that caches the row and can never identify the cache
/// owner - use [cachedForUserId] for that.
@collection
class WorkoutTemplate {
  /// Local Isar identity. Never crosses the network boundary.
  Id localId = Isar.autoIncrement;

  /// Server-assigned id, or `null` for an offline-created template that has
  /// not been pushed yet.
  @Index()
  int? serverId;

  /// The authenticated user this cached row was personalized for. Always
  /// stamped from `SessionRequestContext.epochToken.userId` at write time -
  /// never from response JSON, never from a live `AuthService` read. `null`
  /// for a legacy row; such rows are invisible to every authenticated read
  /// until the next valid online refresh restamps them.
  @Index()
  int? cachedForUserId;

  late String name;
  String? description;

  /// Template exercises (stored as JSON)
  late String exercisesJson;

  /// Recurrence pattern: 'weekly', 'daily', 'custom'
  late String recurrencePattern;

  /// Days of week for weekly pattern (1=Mon, 7=Sun), comma-separated: "1,3,5"
  String? daysOfWeek;

  /// Interval for custom pattern (e.g., every 2 days)
  int? intervalDays;

  /// Duration in minutes (estimated)
  int? estimatedDuration;

  /// Category/type of workout
  String? category;

  /// Is this template active?
  @Index()
  late bool isActive;

  /// Server-owned: user-created (`true`) vs system template (`false`).
  late bool isCustom;

  /// Explicit community publication flag. Community visibility is never
  /// inferred from [createdByUserId].
  late bool isPublic;

  /// Server identity of the template's creator; `null` for system
  /// templates. Not the cache owner - see [cachedForUserId].
  int? createdByUserId;

  /// Display name of the creator, or `null` for system templates.
  String? createdByUserName;

  /// Number of times this template has been used
  late int usageCount;

  /// Average rating (1-5) for community templates
  double? rating;

  /// Number of ratings
  late int ratingCount;

  late DateTime createdAt;

  /// UTC timestamp the template was last used (via increment-usage), or
  /// `null`. Retains its real meaning - it is not an "updated at" audit
  /// column.
  DateTime? lastUsedAt;

  WorkoutTemplate({
    this.localId = Isar.autoIncrement,
    this.serverId,
    this.cachedForUserId,
    required this.name,
    this.description,
    required this.exercisesJson,
    required this.recurrencePattern,
    this.daysOfWeek,
    this.intervalDays,
    this.estimatedDuration,
    this.category,
    this.isActive = true,
    // Defaults to the "system template" value, matching what Isar returns for
    // a row persisted before this field existed. The server DTO always
    // supplies `isCustom`, so `fromJson` never relies on this default; a
    // client never constructs a custom template locally.
    this.isCustom = false,
    this.isPublic = false,
    this.createdByUserId,
    this.createdByUserName,
    this.usageCount = 0,
    this.rating,
    this.ratingCount = 0,
    required this.createdAt,
    this.lastUsedAt,
  });

  /// Get days of week as list
  List<int> get daysOfWeekList {
    if (daysOfWeek == null || daysOfWeek!.isEmpty) return [];
    return daysOfWeek!.split(',').map((e) => int.parse(e.trim())).toList();
  }

  /// Set days of week from list
  set daysOfWeekList(List<int> days) {
    daysOfWeek = days.join(',');
  }

  /// Get next scheduled date based on recurrence pattern
  DateTime? getNextScheduledDate(DateTime fromDate) {
    switch (recurrencePattern) {
      case 'daily':
        return fromDate.add(const Duration(days: 1));

      case 'weekly':
        if (daysOfWeekList.isEmpty) return null;
        final currentWeekday = fromDate.weekday;

        // Find next day in the week
        for (var day in daysOfWeekList.where((d) => d > currentWeekday)) {
          return fromDate.add(Duration(days: day - currentWeekday));
        }

        // If no day found this week, get first day of next week
        final firstDay = daysOfWeekList.first;
        final daysUntilNextWeek = 7 - currentWeekday + firstDay;
        return fromDate.add(Duration(days: daysUntilNextWeek));

      case 'custom':
        if (intervalDays == null) return null;
        return fromDate.add(Duration(days: intervalDays!));

      default:
        return null;
    }
  }

  /// Format recurrence pattern for display
  String get recurrenceDisplay {
    switch (recurrencePattern) {
      case 'daily':
        return 'Every day';
      case 'weekly':
        if (daysOfWeekList.isEmpty) return 'Weekly';
        final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final days = daysOfWeekList.map((d) => dayNames[d - 1]).join(', ');
        return 'Every $days';
      case 'custom':
        if (intervalDays == null) return 'Custom';
        return 'Every $intervalDays days';
      default:
        return recurrencePattern;
    }
  }

  /// Copy with method
  WorkoutTemplate copyWith({
    int? localId,
    int? serverId,
    int? cachedForUserId,
    String? name,
    String? description,
    String? exercisesJson,
    String? recurrencePattern,
    String? daysOfWeek,
    int? intervalDays,
    int? estimatedDuration,
    String? category,
    bool? isActive,
    bool? isCustom,
    bool? isPublic,
    int? createdByUserId,
    String? createdByUserName,
    int? usageCount,
    double? rating,
    int? ratingCount,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  }) {
    return WorkoutTemplate(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      cachedForUserId: cachedForUserId ?? this.cachedForUserId,
      name: name ?? this.name,
      description: description ?? this.description,
      exercisesJson: exercisesJson ?? this.exercisesJson,
      recurrencePattern: recurrencePattern ?? this.recurrencePattern,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      intervalDays: intervalDays ?? this.intervalDays,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      category: category ?? this.category,
      isActive: isActive ?? this.isActive,
      isCustom: isCustom ?? this.isCustom,
      isPublic: isPublic ?? this.isPublic,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByUserName: createdByUserName ?? this.createdByUserName,
      usageCount: usageCount ?? this.usageCount,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}

/// JSON mapping for [WorkoutTemplate] against the deployed
/// `GoHardAPI` WorkoutTemplates contract.
///
/// Response fields (every read/create endpoint):
/// `id, name, description, exercisesJson, recurrencePattern, daysOfWeek,
/// intervalDays, estimatedDuration, category, isActive, isCustom, isPublic,
/// createdByUserId, createdByUserName, usageCount, rating, ratingCount,
/// createdAt, lastUsedAt`.
///
/// The client never sends `id`, `createdByUserId`, `isCustom`, `usageCount`,
/// `rating`, `ratingCount`, `createdAt` or `lastUsedAt` - those are
/// server-owned and not bindable on the create/update requests. There are no
/// `userId`, `isCommunity` or `updatedAt` aliases in either direction.
extension WorkoutTemplateJson on WorkoutTemplate {
  /// Body for `POST`/`PUT /workouttemplates`. Only client-owned fields.
  Map<String, dynamic> toRequestJson() {
    return {
      'name': name,
      'description': description,
      'exercisesJson': exercisesJson,
      'recurrencePattern': recurrencePattern,
      'daysOfWeek': daysOfWeek,
      'intervalDays': intervalDays,
      'estimatedDuration': estimatedDuration,
      'category': category,
      'isActive': isActive,
      'isPublic': isPublic,
    };
  }

  static WorkoutTemplate fromJson(Map<String, dynamic> json) {
    return WorkoutTemplate(
      // The server id lands in [serverId]; [localId] stays auto-incremented
      // and [cachedForUserId] stays null until the repository stamps it.
      serverId: json['id'] as int?,
      name: json['name'] as String,
      description: json['description'] as String?,
      exercisesJson: json['exercisesJson'] as String,
      recurrencePattern: json['recurrencePattern'] as String,
      daysOfWeek: json['daysOfWeek'] as String?,
      intervalDays: json['intervalDays'] as int?,
      estimatedDuration: json['estimatedDuration'] as int?,
      category: json['category'] as String?,
      // The response DTO always supplies these three booleans and the two
      // counts (see GoHardAPI WorkoutTemplateDto) - read them straight so a
      // contract regression surfaces instead of being masked by a default.
      isActive: json['isActive'] as bool,
      isCustom: json['isCustom'] as bool,
      isPublic: json['isPublic'] as bool,
      createdByUserId: json['createdByUserId'] as int?,
      createdByUserName: json['createdByUserName'] as String?,
      usageCount: json['usageCount'] as int,
      rating: (json['rating'] as num?)?.toDouble(),
      ratingCount: json['ratingCount'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt:
          json['lastUsedAt'] != null
              ? DateTime.parse(json['lastUsedAt'] as String)
              : null,
    );
  }
}
