/// A single logged set of a strength exercise.
class StrengthSet {
  const StrengthSet({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.setIndex,
    required this.reps,
    required this.weight,
    this.restSeconds,
    this.isWarmup = false,
    required this.completedAt,
  });

  final int id;
  final int sessionId;
  final int exerciseId;

  /// 1-based position of this set within its exercise for the session.
  final int setIndex;
  final int reps;
  final double weight;

  /// Rest actually taken after this set, in seconds (filled when the rest timer
  /// finishes or is skipped). Null while the set is the most recent one.
  final int? restSeconds;
  final bool isWarmup;
  final DateTime completedAt;

  double get volume => reps * weight;

  factory StrengthSet.fromMap(Map<String, Object?> map) => StrengthSet(
        id: map['id'] as int,
        sessionId: map['session_id'] as int,
        exerciseId: map['exercise_id'] as int,
        setIndex: map['set_index'] as int,
        reps: map['reps'] as int,
        weight: (map['weight'] as num).toDouble(),
        restSeconds: map['rest_seconds'] as int?,
        isWarmup: (map['is_warmup'] as int? ?? 0) == 1,
        completedAt: DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int),
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'session_id': sessionId,
        'exercise_id': exerciseId,
        'set_index': setIndex,
        'reps': reps,
        'weight': weight,
        'rest_seconds': restSeconds,
        'is_warmup': isWarmup ? 1 : 0,
        'completed_at': completedAt.millisecondsSinceEpoch,
      };

  StrengthSet copyWith({int? restSeconds}) => StrengthSet(
        id: id,
        sessionId: sessionId,
        exerciseId: exerciseId,
        setIndex: setIndex,
        reps: reps,
        weight: weight,
        restSeconds: restSeconds ?? this.restSeconds,
        isWarmup: isWarmup,
        completedAt: completedAt,
      );
}
