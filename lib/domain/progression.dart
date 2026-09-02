/// Progressive overload without logging weight: the target volume grows with the
/// program's round counter (each completed pass through all days = one round).
///
/// Rule: +1 rep per round up to +3, then that converts to +1 set with reps back
/// at the base; capped at +2 sets / +2 reps (round 9+ plateaus). A round-1
/// session is exactly the program as written.
({int sets, int reps}) progressTargets({
  required int baseSets,
  required int baseReps,
  required int round,
}) {
  final added = (round - 1).clamp(0, 8);
  return (sets: baseSets + added ~/ 3, reps: baseReps + added % 3);
}
