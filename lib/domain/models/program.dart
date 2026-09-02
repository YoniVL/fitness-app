import '../taxonomy.dart';
import 'rowing_plan.dart';

/// Training discipline for a program or session.
enum Discipline {
  strength,
  rowing;

  static Discipline fromName(String value) => Discipline.values
      .firstWhere((d) => d.name == value, orElse: () => Discipline.strength);
}

/// Difficulty / volume level of a strength program.
enum ProgramLevel {
  beginner,
  medium,
  advanced;

  static ProgramLevel? fromName(String? value) {
    if (value == null) return null;
    for (final l in values) {
      if (l.name == value) return l;
    }
    return null;
  }

  String get label => switch (this) {
        ProgramLevel.beginner => 'Beginner',
        ProgramLevel.medium => 'Medium',
        ProgramLevel.advanced => 'Gevorderd',
      };

  /// Exercises per training day.
  int get exercisesPerDay => switch (this) {
        ProgramLevel.beginner => 4,
        ProgramLevel.medium => 5,
        ProgramLevel.advanced => 6,
      };

  /// Working sets per exercise.
  int get setsPerExercise => switch (this) {
        ProgramLevel.beginner => 3,
        ProgramLevel.medium => 3,
        ProgramLevel.advanced => 4,
      };
}

/// Category / variation of a program. Kept as a plain string in the DB so new
/// categories can be added without a migration; these are the seeded ones.
class ProgramCategory {
  static const strengthFullbody = 'strength_fullbody';
  static const strengthPpl = 'strength_ppl';
  static const strengthGenerated = 'strength_generated';
  static const rowSteady = 'row_steady';
  static const rowInterval = 'row_interval';
  static const rowPyramid = 'row_pyramid';
  static const rowPlan = 'row_plan';
  static const rowGenerated = 'row_generated';
}

/// A training program. Templates ([isTemplate] == true) are read-only starting
/// points; generated / duplicated programs are user-owned ([isTemplate] false).
class Program {
  const Program({
    required this.id,
    required this.name,
    required this.category,
    required this.discipline,
    this.isTemplate = true,
    this.sourceTemplateId,
    this.level,
    this.daysPerWeek,
    this.equipmentProfile = const [],
    this.goal,
  });

  final int id;
  final String name;
  final String category;
  final Discipline discipline;
  final bool isTemplate;
  final int? sourceTemplateId;
  final ProgramLevel? level;
  final int? daysPerWeek;

  /// The rowing training goal, for generated / preset rowing plans.
  final RowingGoal? goal;

  /// Equipment tags this program assumes (see [Equipment]). A template is only
  /// shown in the library when the user owns all of these.
  final List<String> equipmentProfile;

  bool fitsEquipment(Set<String> owned) =>
      equipmentProfile.where((t) => t != Equipment.bodyweight).every(owned.contains);

  factory Program.fromMap(Map<String, Object?> map) => Program(
        id: map['id'] as int,
        name: map['name'] as String,
        category: map['category'] as String,
        discipline: Discipline.fromName(map['discipline'] as String),
        isTemplate: (map['is_template'] as int? ?? 1) == 1,
        sourceTemplateId: map['source_template_id'] as int?,
        level: ProgramLevel.fromName(map['level'] as String?),
        daysPerWeek: map['days_per_week'] as int?,
        equipmentProfile: Equipment.parse(map['equipment_profile'] as String?),
        goal: RowingGoal.fromName(map['goal'] as String?),
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'name': name,
        'category': category,
        'discipline': discipline.name,
        'is_template': isTemplate ? 1 : 0,
        'source_template_id': sourceTemplateId,
        'level': level?.name,
        'days_per_week': daysPerWeek,
        'equipment_profile': equipmentProfile.join(','),
        'goal': goal?.name,
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
    required this.restBetweenSets,
    this.restAfterExercise,
  });

  final int id;
  final int programDayId;
  final int exerciseId;
  final int orderIndex;
  final int targetSets;
  final int targetReps;

  /// Rest after a non-final set of this exercise, in seconds.
  final int restBetweenSets;

  /// Rest after the last set before moving on. Null → fall back to the global
  /// default.
  final int? restAfterExercise;

  factory ProgramExercise.fromMap(Map<String, Object?> map) => ProgramExercise(
        id: map['id'] as int,
        programDayId: map['program_day_id'] as int,
        exerciseId: map['exercise_id'] as int,
        orderIndex: map['order_index'] as int,
        targetSets: map['target_sets'] as int,
        targetReps: map['target_reps'] as int,
        restBetweenSets: map['rest_seconds'] as int,
        restAfterExercise: map['rest_after_exercise'] as int?,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'program_day_id': programDayId,
        'exercise_id': exerciseId,
        'order_index': orderIndex,
        'target_sets': targetSets,
        'target_reps': targetReps,
        'target_weight': null,
        'rest_seconds': restBetweenSets,
        'rest_after_exercise': restAfterExercise,
      };
}

/// A rowing segment within a [ProgramDay] (pace changes / intervals).
class ProgramRowSegment {
  const ProgramRowSegment({
    required this.id,
    required this.programDayId,
    required this.orderIndex,
    required this.durationSeconds,
    this.targetStrokeRate,
    required this.intensityLabel,
    this.isRest = false,
    this.drillKey,
  });

  final int id;
  final int programDayId;
  final int orderIndex;
  final int durationSeconds;
  final int? targetStrokeRate;
  final String intensityLabel;
  final bool isRest;

  /// A [RowDrill] key when this segment is a technique drill, else null.
  final String? drillKey;

  factory ProgramRowSegment.fromMap(Map<String, Object?> map) => ProgramRowSegment(
        id: map['id'] as int,
        programDayId: map['program_day_id'] as int,
        orderIndex: map['order_index'] as int,
        durationSeconds: map['duration_seconds'] as int,
        targetStrokeRate: map['target_stroke_rate'] as int?,
        intensityLabel: map['intensity_label'] as String,
        isRest: (map['is_rest'] as int? ?? 0) == 1,
        drillKey: map['drill_key'] as String?,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'program_day_id': programDayId,
        'order_index': orderIndex,
        'duration_seconds': durationSeconds,
        'target_stroke_rate': targetStrokeRate,
        'intensity_label': intensityLabel,
        'is_rest': isRest ? 1 : 0,
        'drill_key': drillKey,
      };
}

/// The active program plus where the user is in it.
class ActiveProgram {
  const ActiveProgram({
    required this.program,
    required this.days,
    required this.currentDayIndex,
    required this.round,
  });

  final Program program;
  final List<ProgramDay> days;
  final int currentDayIndex;
  final int round;

  ProgramDay get currentDay => days[currentDayIndex.clamp(0, days.length - 1)];
  int get dayCount => days.length;
}
