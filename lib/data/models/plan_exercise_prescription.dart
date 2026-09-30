/// Structured prescription + identity read from one
/// `ProgramWorkout.exercisesJson` entry at session materialization
/// (Phase 2D spec §2). Mirrors `GoHardAPI.Services
/// .ProgramWorkoutSessionMaterializer` exactly: only JSON integers count;
/// strings and fractional numbers are never parsed.
class PlanExercisePrescription {
  final int? exerciseTemplateId;
  final int? targetSets;
  final int? targetRepsMin;
  final int? targetRepsMax;

  const PlanExercisePrescription({
    this.exerciseTemplateId,
    this.targetSets,
    this.targetRepsMin,
    this.targetRepsMax,
  });

  // Mirrors the API's `JsonElement.TryGetInt32` (GoHardAPI.Services
  // .ProgramWorkoutSessionMaterializer.IntOrNull): an int outside Int32's
  // range is treated as not-an-integer, i.e. null - never clamped, never
  // parsed as a double.
  static const _int32Min = -2147483648;
  static const _int32Max = 2147483647;

  factory PlanExercisePrescription.fromPlanEntry(Map<String, dynamic> entry) {
    int? asInt32(Object? v) =>
        v is int && v >= _int32Min && v <= _int32Max ? v : null;
    int? positive(Object? v) {
      final i = asInt32(v);
      return i != null && i >= 1 ? i : null;
    }

    final templateId = asInt32(entry['exerciseTemplateId']);
    final repsMin = positive(entry['reps']);
    final repsMax = asInt32(entry['repsMax']);
    return PlanExercisePrescription(
      exerciseTemplateId: templateId,
      targetSets: positive(entry['sets']),
      targetRepsMin: repsMin,
      targetRepsMax:
          repsMin == null
              ? null
              : (repsMax != null && repsMax >= repsMin ? repsMax : repsMin),
    );
  }
}
