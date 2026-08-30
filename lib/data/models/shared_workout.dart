import 'package:isar/isar.dart';

part 'shared_workout.g.dart';

/// Represents a shared workout in the community
@collection
class SharedWorkout {
  Id id = Isar.autoIncrement;

  /// Original session/template ID
  late int originalId;

  /// Type: 'session' or 'template'
  late String type;

  /// User who shared it (the workout's author). This is server identity of
  /// the creator and is the SAME value for every device that caches this
  /// row - it can never identify which authenticated device user a cached,
  /// personalized response was built for. Use [cachedForUserId] for that.
  @Index()
  late int sharedByUserId;

  late String sharedByUserName;

  /// The authenticated device user for whom this cached row was
  /// personalized, or `null` for a legacy row written before this field
  /// existed. Always stamped from the captured
  /// `SessionRequestContext.epochToken.userId` at write time - never from
  /// response JSON and never from a live `AuthService` read.
  ///
  /// The requester-specific fields on this row ([isLikedByCurrentUser],
  /// [isSavedByCurrentUser]) are only valid for this user, so every cache
  /// read/write/sweep/delete is scoped to a matching [cachedForUserId].
  /// The collection is keyed by the server ID (see [id]), so there is only
  /// ever one row per shared workout - a valid full response for the
  /// current user atomically replaces a legacy (`null`) or foreign-owned
  /// row rather than coexisting with it.
  ///
  /// Backward compatibility: existing rows deserialize with
  /// `cachedForUserId == null` and stay invisible to every authenticated
  /// read until the next valid online refresh restamps them for the
  /// current user. Isar treats a new nullable property as a
  /// compatible schema upgrade, so no manual migration is required.
  int? cachedForUserId;

  /// Workout details
  late String workoutName;
  String? description;
  late String exercisesJson;

  /// Stats
  late int duration; // minutes
  late String category;
  String? difficulty;

  /// Social metrics
  late int likeCount;
  late int saveCount;
  late int commentCount;

  /// Has current user liked/saved this?
  late bool isLikedByCurrentUser;
  late bool isSavedByCurrentUser;

  late DateTime sharedAt;

  SharedWorkout({
    this.id = Isar.autoIncrement,
    required this.originalId,
    required this.type,
    required this.sharedByUserId,
    required this.sharedByUserName,
    required this.workoutName,
    this.description,
    required this.exercisesJson,
    required this.duration,
    required this.category,
    this.difficulty,
    this.likeCount = 0,
    this.saveCount = 0,
    this.commentCount = 0,
    this.isLikedByCurrentUser = false,
    this.isSavedByCurrentUser = false,
    required this.sharedAt,
    this.cachedForUserId,
  });

  /// Format duration
  String get formattedDuration {
    if (duration < 60) return '${duration}m';
    final hours = duration ~/ 60;
    final mins = duration % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  /// Get time since shared
  String get timeSinceShared {
    final now = DateTime.now();
    final difference = now.difference(sharedAt);

    if (difference.inDays > 30) {
      final months = difference.inDays ~/ 30;
      return '$months month${months > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  SharedWorkout copyWith({
    int? id,
    int? originalId,
    String? type,
    int? sharedByUserId,
    String? sharedByUserName,
    String? workoutName,
    String? description,
    String? exercisesJson,
    int? duration,
    String? category,
    String? difficulty,
    int? likeCount,
    int? saveCount,
    int? commentCount,
    bool? isLikedByCurrentUser,
    bool? isSavedByCurrentUser,
    DateTime? sharedAt,
    int? cachedForUserId,
  }) {
    return SharedWorkout(
      id: id ?? this.id,
      originalId: originalId ?? this.originalId,
      type: type ?? this.type,
      sharedByUserId: sharedByUserId ?? this.sharedByUserId,
      sharedByUserName: sharedByUserName ?? this.sharedByUserName,
      workoutName: workoutName ?? this.workoutName,
      description: description ?? this.description,
      exercisesJson: exercisesJson ?? this.exercisesJson,
      duration: duration ?? this.duration,
      category: category ?? this.category,
      difficulty: difficulty ?? this.difficulty,
      likeCount: likeCount ?? this.likeCount,
      saveCount: saveCount ?? this.saveCount,
      commentCount: commentCount ?? this.commentCount,
      isLikedByCurrentUser: isLikedByCurrentUser ?? this.isLikedByCurrentUser,
      isSavedByCurrentUser: isSavedByCurrentUser ?? this.isSavedByCurrentUser,
      sharedAt: sharedAt ?? this.sharedAt,
      cachedForUserId: cachedForUserId ?? this.cachedForUserId,
    );
  }
}
