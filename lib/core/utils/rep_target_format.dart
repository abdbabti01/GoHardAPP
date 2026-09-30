/// Display text for a structured rep prescription (Phase 2D). Formats
/// structured values only - never parses strings.
String? formatRepTarget({int? sets, int? repsMin, int? repsMax}) {
  final reps =
      repsMin == null
          ? null
          : (repsMax != null && repsMax > repsMin
              ? '$repsMin–$repsMax'
              : '$repsMin');
  if (sets != null && reps != null) return '$sets × $reps';
  if (reps != null) return '$reps reps';
  if (sets != null) return '$sets sets';
  return null;
}
