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

  factory PlanExercisePrescription.fromPlanEntry(Map<String, dynamic> entry) {
    int? positive(Object? v) => v is int && v >= 1 ? v : null;
    final templateId = entry['exerciseTemplateId'];
    final repsMin = positive(entry['reps']);
    final repsMax = entry['repsMax'];
    return PlanExercisePrescription(
      exerciseTemplateId: templateId is int ? templateId : null,
      targetSets: positive(entry['sets']),
      targetRepsMin: repsMin,
      targetRepsMax:
          repsMin == null
              ? null
              : (repsMax is int && repsMax >= repsMin ? repsMax : repsMin),
    );
  }
}
