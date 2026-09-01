/// Training discipline for a program or session.
enum Discipline {
  strength,
  rowing;

  static Discipline fromName(String value) =>
      Discipline.values.firstWhere((d) => d.name == value, orElse: () => Discipline.strength);
}

/// Category / variation of a program. Kept as a plain string in the DB so new
/// categories can be added without a migration; these are the seeded ones.
class ProgramCategory {
  static const strengthFullbody = 'strength_fullbody';
  static const strengthPpl = 'strength_ppl';
  static const rowSteady = 'row_steady';
  static const rowInterval = 'row_interval';
  static const rowPyramid = 'row_pyramid';
}

/// A training program. Templates ([isTemplate] == true) are read-only starting
/// points; a per-session copy can override reps/sets/weight/rest without
/// touching the template (handled in the strength feature, not persisted as a
/// new program in iteratie 1).
class Program {
  const Program({
    required this.id,
    required this.name,
    required this.category,
    required this.discipline,
    this.isTemplate = true,
    this.sourceTemplateId,
  });

  final int id;
  final String name;
  final String category;
  final Discipline discipline;
  final bool isTemplate;
  final int? sourceTemplateId;

  factory Program.fromMap(Map<String, Object?> map) => Program(
        id: map['id'] as int,
        name: map['name'] as String,
        category: map['category'] as String,
        discipline: Discipline.fromName(map['discipline'] as String),
        isTemplate: (map['is_template'] as int? ?? 1) == 1,
        sourceTemplateId: map['source_template_id'] as int?,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'name': name,
        'category': category,
        'discipline': discipline.name,
        'is_template': isTemplate ? 1 : 0,
        'source_template_id': sourceTemplateId,
      };
}

/// One day within a program (e.g. "Push", "Pull", "Legs", or "Interval 4x500m").
class ProgramDay {
  const ProgramDay({
    required this.id,
    required this.programId,
    required this.dayIndex,
    required this.label,
  });

  final int id;
  final int programId;
  final int dayIndex;
  final String label;

  factory ProgramDay.fromMap(Map<String, Object?> map) => ProgramDay(
        id: map['id'] as int,
        programId: map['program_id'] as int,
        dayIndex: map['day_index'] as int,
        label: map['label'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'program_id': programId,
        'day_index': dayIndex,
        'label': label,
      };
}

/// A prescribed exercise within a [ProgramDay] (strength only).
class ProgramExercise {
  const ProgramExercise({
    required this.id,
    required this.programDayId,
    required this.exerciseId,
    required this.orderIndex,
    required this.targetSets,
    required this.targetReps,
    this.targetWeight,
    required this.restSeconds,
  });

  final int id;
  final int programDayId;
  final int exerciseId;
  final int orderIndex;
  final int targetSets;
  final int targetReps;
  final double? targetWeight;
  final int restSeconds;

  factory ProgramExercise.fromMap(Map<String, Object?> map) => ProgramExercise(
        id: map['id'] as int,
        programDayId: map['program_day_id'] as int,
        exerciseId: map['exercise_id'] as int,
        orderIndex: map['order_index'] as int,
        targetSets: map['target_sets'] as int,
        targetReps: map['target_reps'] as int,
        targetWeight: (map['target_weight'] as num?)?.toDouble(),
        restSeconds: map['rest_seconds'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'program_day_id': programDayId,
        'exercise_id': exerciseId,
        'order_index': orderIndex,
        'target_sets': targetSets,
        'target_reps': targetReps,
        'target_weight': targetWeight,
        'rest_seconds': restSeconds,
      };
}

/// A rowing segment within a [ProgramDay] (pace changes / intervals). Data is
/// seeded now; the rowing UI arrives in a later iteratie.
class ProgramRowSegment {
  const ProgramRowSegment({
    required this.id,
    required this.programDayId,
    required this.orderIndex,
    required this.durationSeconds,
    this.targetStrokeRate,
    required this.intensityLabel,
    this.isRest = false,
  });

  final int id;
  final int programDayId;
  final int orderIndex;
  final int durationSeconds;
  final int? targetStrokeRate;
  final String intensityLabel;
  final bool isRest;

  factory ProgramRowSegment.fromMap(Map<String, Object?> map) => ProgramRowSegment(
        id: map['id'] as int,
        programDayId: map['program_day_id'] as int,
        orderIndex: map['order_index'] as int,
        durationSeconds: map['duration_seconds'] as int,
        targetStrokeRate: map['target_stroke_rate'] as int?,
        intensityLabel: map['intensity_label'] as String,
        isRest: (map['is_rest'] as int? ?? 0) == 1,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'program_day_id': programDayId,
        'order_index': orderIndex,
        'duration_seconds': durationSeconds,
        'target_stroke_rate': targetStrokeRate,
        'intensity_label': intensityLabel,
        'is_rest': isRest ? 1 : 0,
      };
}

/// A program day together with its prescribed exercises, resolved for display.
class ProgramDayDetail {
  const ProgramDayDetail({
    required this.day,
    required this.exercises,
  });

  final ProgramDay day;
  final List<ProgramExercise> exercises;
}
