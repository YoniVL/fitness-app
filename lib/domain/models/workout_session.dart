import 'program.dart';
import 'strength_set.dart';

/// A logged training session (strength or rowing).
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.discipline,
    this.programDayId,
    required this.startedAt,
    this.endedAt,
    this.notes,
  });

  final int id;
  final Discipline discipline;
  final int? programDayId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? notes;

  Duration? get duration => endedAt?.difference(startedAt);

  bool get isFinished => endedAt != null;

  factory WorkoutSession.fromMap(Map<String, Object?> map) => WorkoutSession(
        id: map['id'] as int,
        discipline: Discipline.fromName(map['discipline'] as String),
        programDayId: map['program_day_id'] as int?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
        endedAt: map['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['ended_at'] as int),
        notes: map['notes'] as String?,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'discipline': discipline.name,
        'program_day_id': programDayId,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'notes': notes,
      };

  WorkoutSession copyWith({DateTime? endedAt, String? notes}) => WorkoutSession(
        id: id,
        discipline: discipline,
        programDayId: programDayId,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        notes: notes ?? this.notes,
      );
}

/// A finished session with its sets resolved, for the summary / log detail
/// screen.
class WorkoutSessionDetail {
  const WorkoutSessionDetail({
    required this.session,
    required this.sets,
    this.muscleGroupSetCount = const {},
  });

  final WorkoutSession session;
  final List<StrengthSet> sets;

  /// Muscle group id -> number of working sets that hit it (primary + secondary).
  final Map<int, int> muscleGroupSetCount;

  int get workingSetCount => sets.where((s) => !s.isWarmup).length;

  int get totalReps =>
      sets.where((s) => !s.isWarmup).fold(0, (sum, s) => sum + s.reps);

  int get exerciseCount => sets.map((s) => s.exerciseId).toSet().length;

  WorkoutSessionDetail withMuscleGroups(Map<int, int> counts) =>
      WorkoutSessionDetail(
        session: session,
        sets: sets,
        muscleGroupSetCount: counts,
      );
}
