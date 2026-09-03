import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/program.dart';
import '../../domain/models/rowing_plan.dart';
import '../../domain/rowing_plan_generator.dart';
import '../../domain/taxonomy.dart';

/// Seeds reference data (muscle groups, exercises), default settings, and the
/// starter programs. Runs on fresh install and again from the v1->v2 migration,
/// so every write is idempotent-friendly.
Future<void> seedDatabase(DatabaseExecutor db) async {
  final muscleGroupIds = await _seedMuscleGroups(db);
  final exerciseIds = await _seedExercises(db, muscleGroupIds);
  await _seedSettings(db);
  await _seedHomePrograms(db, exerciseIds);
  await _seedGymPrograms(db, exerciseIds);
  await seedRowingTemplates(db);
}

// --- Muscle groups ---------------------------------------------------------

const _muscleGroups = <String, String>{
  MuscleGroups.borst: 'chest',
  MuscleGroups.rug: 'back',
  MuscleGroups.benen: 'legs',
  MuscleGroups.schouders: 'shoulders',
  MuscleGroups.biceps: 'biceps',
  MuscleGroups.triceps: 'triceps',
  MuscleGroups.core: 'core',
  MuscleGroups.bilspieren: 'glutes',
  MuscleGroups.kuiten: 'calves',
};

Future<Map<String, int>> _seedMuscleGroups(DatabaseExecutor db) async {
  final ids = <String, int>{};
  for (final entry in _muscleGroups.entries) {
    ids[entry.key] = await db.insert('muscle_groups', {
      'name': entry.key,
      'icon_key': entry.value,
    });
  }
  return ids;
}

// --- Exercises -----------------------------------------------------------

class _Ex {
  const _Ex(this.name, this.primary, this.equipment, this.pattern,
      {this.secondary = const []});
  final String name;
  final String primary;
  final List<String> equipment;
  final MovementPattern pattern;
  final List<String> secondary;
}

/// Exercises trained one side at a time — the generator keeps their set count
/// even so both sides get the same volume.
const unilateralExerciseNames = <String>[
  'Dumbbell one-arm row',
  'Dumbbell split squat',
  'Dumbbell Bulgarian split squat',
  'Dumbbell step-up',
  'Dumbbell single-leg RDL',
  'Dumbbell concentration curl',
  'Dumbbell kickback',
  'Dumbbell side bend',
];

/// v3 name -> v4 canonical name. Names are English with an equipment prefix
/// (Barbell / Dumbbell / Cable / Machine); bodyweight moves stay bare.
const exerciseRenamesV3toV4 = <String, String>{
  'Bankdrukken': 'Barbell bench press',
  'Halter bankdruk': 'Dumbbell bench press',
  'Incline dumbbell press': 'Dumbbell incline press',
  'Incline bankdruk': 'Barbell incline press',
  'Kabel fly': 'Cable fly',
  'One-arm dumbbell row': 'Dumbbell one-arm row',
  'Chest-supported dumbbell row': 'Dumbbell chest-supported row',
  'Seated cable row': 'Cable seated row',
  'Reverse fly': 'Dumbbell reverse fly',
  'Face pull': 'Cable face pull',
  'Lat pulldown': 'Cable lat pulldown',
  'Overhead press': 'Barbell overhead press',
  'Arnold press': 'Dumbbell Arnold press',
  'Squat': 'Barbell back squat',
  'Front squat': 'Barbell front squat',
  'Goblet squat': 'Dumbbell goblet squat',
  'Leg press': 'Machine leg press',
  'Leg extension': 'Machine leg extension',
  'Bulgarian split squat': 'Dumbbell Bulgarian split squat',
  'Walking lunge': 'Dumbbell walking lunge',
  'Deadlift': 'Barbell deadlift',
  'Romanian deadlift': 'Barbell Romanian deadlift',
  'Leg curl': 'Machine leg curl',
  'Hip thrust': 'Barbell hip thrust',
  'Hammer curl': 'Dumbbell hammer curl',
  'Incline dumbbell curl': 'Dumbbell incline curl',
  'Concentration curl': 'Dumbbell concentration curl',
  'Triceps pushdown': 'Cable triceps pushdown',
  'Skull crusher': 'Barbell skull crusher',
  'Overhead dumbbell triceps extension': 'Dumbbell overhead triceps extension',
  'Close-grip dumbbell press': 'Dumbbell close-grip press',
  'Lateral raise': 'Dumbbell lateral raise',
  'Front raise': 'Dumbbell front raise',
  'Standing calf raise': 'Machine standing calf raise',
  'Seated calf raise': 'Machine seated calf raise',
};

const _db = Equipment.dumbbell;
const _bench = Equipment.bench;
const _incl = Equipment.benchIncline;
const _bw = Equipment.bodyweight;
const _bar = Equipment.barbell;
const _mach = Equipment.machine;
const _cable = Equipment.cable;
const _pull = Equipment.pullupBar;

const _exercises = <_Ex>[
  // Horizontal push
  _Ex('Barbell bench press', MuscleGroups.borst, [_bar, _bench],
      MovementPattern.horizontalPush,
      secondary: [MuscleGroups.triceps, MuscleGroups.schouders]),
  _Ex('Dumbbell bench press', MuscleGroups.borst, [_db, _bench],
      MovementPattern.horizontalPush,
      secondary: [MuscleGroups.triceps, MuscleGroups.schouders]),
  _Ex('Dumbbell incline press', MuscleGroups.borst, [_db, _incl],
      MovementPattern.horizontalPush,
      secondary: [MuscleGroups.schouders, MuscleGroups.triceps]),
  _Ex('Barbell incline press', MuscleGroups.borst, [_bar, _incl],
      MovementPattern.horizontalPush,
      secondary: [MuscleGroups.schouders, MuscleGroups.triceps]),
  _Ex('Dumbbell floor press', MuscleGroups.borst, [_db],
      MovementPattern.horizontalPush, secondary: [MuscleGroups.triceps]),
  _Ex('Push-up', MuscleGroups.borst, [_bw], MovementPattern.horizontalPush,
      secondary: [MuscleGroups.triceps, MuscleGroups.core]),
  _Ex('Dips', MuscleGroups.borst, [_bw], MovementPattern.horizontalPush,
      secondary: [MuscleGroups.triceps]),
  _Ex('Dumbbell fly', MuscleGroups.borst, [_db, _bench],
      MovementPattern.horizontalPush),
  _Ex('Cable fly', MuscleGroups.borst, [_cable], MovementPattern.horizontalPush),

  // Horizontal pull
  _Ex('Barbell row', MuscleGroups.rug, [_bar], MovementPattern.horizontalPull,
      secondary: [MuscleGroups.biceps]),
  _Ex('Dumbbell one-arm row', MuscleGroups.rug, [_db, _bench],
      MovementPattern.horizontalPull, secondary: [MuscleGroups.biceps]),
  _Ex('Dumbbell chest-supported row', MuscleGroups.rug, [_db, _incl],
      MovementPattern.horizontalPull, secondary: [MuscleGroups.biceps]),
  _Ex('Cable seated row', MuscleGroups.rug, [_cable],
      MovementPattern.horizontalPull, secondary: [MuscleGroups.biceps]),
  _Ex('Dumbbell reverse fly', MuscleGroups.schouders, [_db],
      MovementPattern.horizontalPull, secondary: [MuscleGroups.rug]),
  _Ex('Cable face pull', MuscleGroups.schouders, [_cable],
      MovementPattern.horizontalPull, secondary: [MuscleGroups.rug]),

  // Vertical pull
  _Ex('Pull-up', MuscleGroups.rug, [_pull], MovementPattern.verticalPull,
      secondary: [MuscleGroups.biceps]),
  _Ex('Cable lat pulldown', MuscleGroups.rug, [_cable],
      MovementPattern.verticalPull, secondary: [MuscleGroups.biceps]),
  _Ex('Dumbbell pullover', MuscleGroups.rug, [_db, _bench],
      MovementPattern.verticalPull),
  _Ex('Dumbbell high-incline row', MuscleGroups.rug, [_db, _incl],
      MovementPattern.verticalPull, secondary: [MuscleGroups.biceps]),

  // Vertical push
  _Ex('Barbell overhead press', MuscleGroups.schouders, [_bar],
      MovementPattern.verticalPush, secondary: [MuscleGroups.triceps]),
  _Ex('Dumbbell shoulder press', MuscleGroups.schouders, [_db],
      MovementPattern.verticalPush, secondary: [MuscleGroups.triceps]),
  _Ex('Dumbbell Arnold press', MuscleGroups.schouders, [_db],
      MovementPattern.verticalPush, secondary: [MuscleGroups.triceps]),

  // Squat
  _Ex('Barbell back squat', MuscleGroups.benen, [_bar], MovementPattern.squat,
      secondary: [MuscleGroups.bilspieren, MuscleGroups.core]),
  _Ex('Barbell front squat', MuscleGroups.benen, [_bar], MovementPattern.squat,
      secondary: [MuscleGroups.core]),
  _Ex('Dumbbell goblet squat', MuscleGroups.benen, [_db], MovementPattern.squat,
      secondary: [MuscleGroups.bilspieren, MuscleGroups.core]),
  _Ex('Machine leg press', MuscleGroups.benen, [_mach], MovementPattern.squat,
      secondary: [MuscleGroups.bilspieren]),
  _Ex('Machine leg extension', MuscleGroups.benen, [_mach],
      MovementPattern.squat),

  // Lunge
  _Ex('Dumbbell split squat', MuscleGroups.benen, [_db], MovementPattern.lunge,
      secondary: [MuscleGroups.bilspieren]),
  _Ex('Dumbbell Bulgarian split squat', MuscleGroups.benen, [_db, _bench],
      MovementPattern.lunge, secondary: [MuscleGroups.bilspieren]),
  _Ex('Dumbbell walking lunge', MuscleGroups.benen, [_db],
      MovementPattern.lunge, secondary: [MuscleGroups.bilspieren]),
  _Ex('Dumbbell step-up', MuscleGroups.benen, [_db, _bench],
      MovementPattern.lunge, secondary: [MuscleGroups.bilspieren]),

  // Hinge
  _Ex('Barbell deadlift', MuscleGroups.rug, [_bar], MovementPattern.hinge,
      secondary: [MuscleGroups.benen, MuscleGroups.bilspieren]),
  _Ex('Barbell Romanian deadlift', MuscleGroups.benen, [_bar],
      MovementPattern.hinge,
      secondary: [MuscleGroups.bilspieren, MuscleGroups.rug]),
  _Ex('Dumbbell Romanian deadlift', MuscleGroups.benen, [_db],
      MovementPattern.hinge,
      secondary: [MuscleGroups.bilspieren, MuscleGroups.rug]),
  _Ex('Dumbbell single-leg RDL', MuscleGroups.bilspieren, [_db],
      MovementPattern.hinge, secondary: [MuscleGroups.benen]),
  _Ex('Machine leg curl', MuscleGroups.benen, [_mach], MovementPattern.hinge),
  _Ex('Barbell hip thrust', MuscleGroups.bilspieren, [_bar, _bench],
      MovementPattern.hinge, secondary: [MuscleGroups.benen]),
  _Ex('Dumbbell hip thrust', MuscleGroups.bilspieren, [_db, _bench],
      MovementPattern.hinge, secondary: [MuscleGroups.benen]),
  _Ex('Glute bridge', MuscleGroups.bilspieren, [_bw], MovementPattern.hinge),
  _Ex('Dumbbell swing', MuscleGroups.bilspieren, [_db], MovementPattern.hinge,
      secondary: [MuscleGroups.benen]),

  // Biceps isolation
  _Ex('Barbell curl', MuscleGroups.biceps, [_bar], MovementPattern.bicepsIso),
  _Ex('Dumbbell curl', MuscleGroups.biceps, [_db], MovementPattern.bicepsIso),
  _Ex('Dumbbell hammer curl', MuscleGroups.biceps, [_db],
      MovementPattern.bicepsIso),
  _Ex('Dumbbell incline curl', MuscleGroups.biceps, [_db, _incl],
      MovementPattern.bicepsIso),
  _Ex('Dumbbell concentration curl', MuscleGroups.biceps, [_db, _bench],
      MovementPattern.bicepsIso),

  // Triceps isolation
  _Ex('Cable triceps pushdown', MuscleGroups.triceps, [_cable],
      MovementPattern.tricepsIso),
  _Ex('Barbell skull crusher', MuscleGroups.triceps, [_bar, _bench],
      MovementPattern.tricepsIso),
  _Ex('Dumbbell overhead triceps extension', MuscleGroups.triceps, [_db],
      MovementPattern.tricepsIso),
  _Ex('Dumbbell kickback', MuscleGroups.triceps, [_db],
      MovementPattern.tricepsIso),
  _Ex('Dumbbell close-grip press', MuscleGroups.triceps, [_db, _bench],
      MovementPattern.tricepsIso, secondary: [MuscleGroups.borst]),

  // Side / front delt isolation
  _Ex('Dumbbell lateral raise', MuscleGroups.schouders, [_db],
      MovementPattern.sideDeltIso),
  _Ex('Dumbbell front raise', MuscleGroups.schouders, [_db],
      MovementPattern.sideDeltIso),

  // Core
  _Ex('Plank', MuscleGroups.core, [_bw], MovementPattern.core),
  _Ex('Hanging leg raise', MuscleGroups.core, [_pull], MovementPattern.core),
  _Ex('Lying leg raise', MuscleGroups.core, [_bw], MovementPattern.core),
  _Ex('Dead bug', MuscleGroups.core, [_bw], MovementPattern.core),
  _Ex('Dumbbell Russian twist', MuscleGroups.core, [_db], MovementPattern.core),
  _Ex('Cable crunch', MuscleGroups.core, [_cable], MovementPattern.core),
  _Ex('Dumbbell side bend', MuscleGroups.core, [_db], MovementPattern.core),

  // Calves
  _Ex('Machine standing calf raise', MuscleGroups.kuiten, [_mach],
      MovementPattern.calfIso),
  _Ex('Machine seated calf raise', MuscleGroups.kuiten, [_mach],
      MovementPattern.calfIso),
  _Ex('Dumbbell standing calf raise', MuscleGroups.kuiten, [_db],
      MovementPattern.calfIso),
  _Ex('Dumbbell seated calf raise', MuscleGroups.kuiten, [_db, _bench],
      MovementPattern.calfIso),
];

Future<Map<String, int>> _seedExercises(
  DatabaseExecutor db,
  Map<String, int> muscleGroupIds,
) async {
  final ids = <String, int>{};
  for (final ex in _exercises) {
    final secondary = ex.secondary
        .map((n) => muscleGroupIds[n])
        .whereType<int>()
        .join(',');
    ids[ex.name] = await db.insert('exercises', {
      'name': ex.name,
      'primary_muscle_group_id': muscleGroupIds[ex.primary],
      'secondary_muscle_groups': secondary,
      'equipment': ex.equipment.join(','),
      'pattern': ex.pattern.name,
      'is_unilateral': unilateralExerciseNames.contains(ex.name) ? 1 : 0,
      'media_key': null,
      'is_custom': 0,
    });
  }
  return ids;
}

// --- Settings -----------------------------------------------------------

Future<void> _seedSettings(DatabaseExecutor db) async {
  const defaults = <String, String>{
    'owned_equipment': 'dumbbell,bench,bench_incline',
    'default_rest_between_sets': '30',
    'default_rest_after_exercise': '60',
    'rest_timer_sound': 'true',
  };
  for (final entry in defaults.entries) {
    await db.insert(
      'app_settings',
      {'key': entry.key, 'value': entry.value},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

// --- Programs ----------------------------------------------------------

class _PE {
  const _PE(this.exercise, this.sets, this.reps,
      {this.restBetween = 30, this.restAfter = 60});
  final String exercise;
  final int sets;
  final int reps;
  final int restBetween;
  final int restAfter;
}

Future<void> _insertProgram(
  DatabaseExecutor db,
  Map<String, int> exerciseIds, {
  required String name,
  required String category,
  required List<String> equipmentProfile,
  ProgramLevel? level,
  int? daysPerWeek,
  bool isTemplate = true,
  required List<({String label, List<_PE> items})> days,
}) async {
  final programId = await db.insert('programs', {
    'name': name,
    'category': category,
    'discipline': Discipline.strength.name,
    'is_template': isTemplate ? 1 : 0,
    'level': level?.name,
    'days_per_week': daysPerWeek,
    'equipment_profile': equipmentProfile.join(','),
  });
  for (var d = 0; d < days.length; d++) {
    final day = days[d];
    final dayId = await db.insert('program_days', {
      'program_id': programId,
      'day_index': d,
      'label': day.label,
    });
    for (var i = 0; i < day.items.length; i++) {
      final pe = day.items[i];
      await db.insert('program_exercises', {
        'program_day_id': dayId,
        'exercise_id': exerciseIds[pe.exercise],
        'order_index': i,
        'target_sets': pe.sets,
        'target_reps': pe.reps,
        'target_weight': null,
        'rest_seconds': pe.restBetween,
        'rest_after_exercise': pe.restAfter,
      });
    }
  }
}

const _homeProfile = [
  Equipment.dumbbell,
  Equipment.bench,
  Equipment.benchIncline,
];

Future<void> _seedHomePrograms(
    DatabaseExecutor db, Map<String, int> exerciseIds) async {
  // Beginner — 3 days, 5 exercises, 3 sets.
  await _insertProgram(
    db,
    exerciseIds,
    name: 'Full-body Beginner',
    category: ProgramCategory.strengthFullbody,
    level: ProgramLevel.beginner,
    daysPerWeek: 3,
    equipmentProfile: _homeProfile,
    days: const [
      (label: 'Dag 1', items: [
        _PE('Dumbbell goblet squat', 3, 10),
        _PE('Dumbbell bench press', 3, 10),
        _PE('Dumbbell one-arm row', 3, 10),
        _PE('Dumbbell shoulder press', 3, 10),
        _PE('Dead bug', 3, 10),
      ]),
      (label: 'Dag 2', items: [
        _PE('Dumbbell Romanian deadlift', 3, 10),
        _PE('Dumbbell incline press', 3, 10),
        _PE('Dumbbell chest-supported row', 3, 10),
        _PE('Dumbbell lateral raise', 3, 13),
        _PE('Lying leg raise', 3, 12),
      ]),
      (label: 'Dag 3', items: [
        _PE('Dumbbell split squat', 3, 10),
        _PE('Push-up', 3, 12),
        _PE('Dumbbell pullover', 3, 12),
        _PE('Dumbbell hammer curl', 3, 12),
        _PE('Dumbbell Russian twist', 3, 14),
      ]),
    ],
  );

  // Medium — 4 days, 6 exercises, 3 sets.
  await _insertProgram(
    db,
    exerciseIds,
    name: 'Full-body Medium',
    category: ProgramCategory.strengthFullbody,
    level: ProgramLevel.medium,
    daysPerWeek: 4,
    equipmentProfile: _homeProfile,
    days: const [
      (label: 'Dag 1 · Duwen', items: [
        _PE('Dumbbell bench press', 3, 9),
        _PE('Dumbbell shoulder press', 3, 10),
        _PE('Dumbbell incline press', 3, 10),
        _PE('Dumbbell lateral raise', 3, 14),
        _PE('Dumbbell overhead triceps extension', 3, 12),
        _PE('Dead bug', 3, 10),
      ]),
      (label: 'Dag 2 · Trekken', items: [
        _PE('Dumbbell one-arm row', 3, 10),
        _PE('Dumbbell chest-supported row', 3, 10),
        _PE('Dumbbell high-incline row', 3, 12),
        _PE('Dumbbell curl', 3, 12),
        _PE('Dumbbell hammer curl', 3, 12),
        _PE('Lying leg raise', 3, 12),
      ]),
      (label: 'Dag 3 · Benen', items: [
        _PE('Dumbbell goblet squat', 3, 10),
        _PE('Dumbbell Romanian deadlift', 3, 10),
        _PE('Dumbbell Bulgarian split squat', 3, 10),
        _PE('Dumbbell hip thrust', 3, 12),
        _PE('Dumbbell standing calf raise', 3, 15),
        _PE('Dumbbell Russian twist', 3, 14),
      ]),
      (label: 'Dag 4 · Full-body', items: [
        _PE('Dumbbell incline press', 3, 10),
        _PE('Dumbbell one-arm row', 3, 10),
        _PE('Dumbbell split squat', 3, 10),
        _PE('Dumbbell Arnold press', 3, 11),
        _PE('Dumbbell incline curl', 3, 12),
        _PE('Dumbbell kickback', 3, 13),
      ]),
    ],
  );

  // Gevorderd — 4 days, 6 exercises, 4 sets.
  await _insertProgram(
    db,
    exerciseIds,
    name: 'Full-body Gevorderd',
    category: ProgramCategory.strengthFullbody,
    level: ProgramLevel.advanced,
    daysPerWeek: 4,
    equipmentProfile: _homeProfile,
    days: const [
      (label: 'Dag 1 · Duwen', items: [
        _PE('Dumbbell bench press', 4, 8),
        _PE('Dumbbell incline press', 4, 9),
        _PE('Dumbbell shoulder press', 4, 10),
        _PE('Dumbbell lateral raise', 4, 15),
        _PE('Dumbbell close-grip press', 4, 10),
        _PE('Dumbbell overhead triceps extension', 3, 12),
      ]),
      (label: 'Dag 2 · Trekken', items: [
        _PE('Dumbbell one-arm row', 4, 9),
        _PE('Dumbbell chest-supported row', 4, 10),
        _PE('Dumbbell high-incline row', 4, 11),
        _PE('Dumbbell reverse fly', 3, 14),
        _PE('Dumbbell incline curl', 4, 11),
        _PE('Dumbbell hammer curl', 3, 12),
      ]),
      (label: 'Dag 3 · Benen', items: [
        _PE('Dumbbell goblet squat', 4, 9),
        _PE('Dumbbell Romanian deadlift', 4, 9),
        _PE('Dumbbell Bulgarian split squat', 3, 10),
        _PE('Dumbbell hip thrust', 4, 12),
        _PE('Dumbbell single-leg RDL', 3, 12),
        _PE('Dumbbell standing calf raise', 4, 15),
      ]),
      (label: 'Dag 4 · Full-body', items: [
        _PE('Dumbbell floor press', 4, 9),
        _PE('Dumbbell pullover', 4, 11),
        _PE('Dumbbell walking lunge', 3, 12),
        _PE('Dumbbell Arnold press', 4, 10),
        _PE('Dumbbell concentration curl', 3, 12),
        _PE('Dumbbell Russian twist', 3, 16),
      ]),
    ],
  );
}

Future<void> _seedGymPrograms(
    DatabaseExecutor db, Map<String, int> exerciseIds) async {
  await _insertProgram(
    db,
    exerciseIds,
    name: 'Full-body A/B',
    category: ProgramCategory.strengthFullbody,
    level: ProgramLevel.beginner,
    daysPerWeek: 3,
    equipmentProfile: const [Equipment.barbell],
    days: const [
      (label: 'Full-body A', items: [
        _PE('Barbell back squat', 3, 5, restBetween: 120, restAfter: 120),
        _PE('Barbell bench press', 3, 5, restBetween: 120, restAfter: 120),
        _PE('Barbell row', 3, 8, restBetween: 90, restAfter: 90),
        _PE('Barbell overhead press', 3, 8, restBetween: 90, restAfter: 90),
        _PE('Barbell curl', 3, 12, restBetween: 60, restAfter: 60),
      ]),
      (label: 'Full-body B', items: [
        _PE('Barbell deadlift', 3, 5, restBetween: 150, restAfter: 150),
        _PE('Barbell overhead press', 3, 5, restBetween: 120, restAfter: 120),
        _PE('Barbell row', 3, 10, restBetween: 90, restAfter: 90),
        _PE('Dumbbell bench press', 3, 10, restBetween: 90, restAfter: 90),
        _PE('Barbell skull crusher', 3, 12, restBetween: 60, restAfter: 60),
      ]),
    ],
  );

  await _insertProgram(
    db,
    exerciseIds,
    name: 'Push / Pull / Legs',
    category: ProgramCategory.strengthPpl,
    level: ProgramLevel.medium,
    daysPerWeek: 3,
    equipmentProfile: const [
      Equipment.barbell,
      Equipment.pullupBar,
      Equipment.cable,
      Equipment.machine,
    ],
    days: const [
      (label: 'Push', items: [
        _PE('Barbell bench press', 4, 6, restBetween: 120, restAfter: 120),
        _PE('Dumbbell shoulder press', 3, 10, restBetween: 90, restAfter: 90),
        _PE('Barbell incline press', 3, 10, restBetween: 90, restAfter: 90),
        _PE('Dumbbell lateral raise', 3, 15),
        _PE('Cable triceps pushdown', 3, 12),
        _PE('Dumbbell overhead triceps extension', 3, 12),
      ]),
      (label: 'Pull', items: [
        _PE('Barbell deadlift', 3, 5, restBetween: 150, restAfter: 150),
        _PE('Pull-up', 3, 8, restBetween: 90, restAfter: 90),
        _PE('Barbell row', 3, 10, restBetween: 90, restAfter: 90),
        _PE('Cable seated row', 3, 12, restBetween: 75, restAfter: 75),
        _PE('Cable face pull', 3, 15),
        _PE('Barbell curl', 3, 12),
      ]),
      (label: 'Legs', items: [
        _PE('Barbell back squat', 4, 6, restBetween: 120, restAfter: 120),
        _PE('Barbell Romanian deadlift', 3, 10, restBetween: 100, restAfter: 100),
        _PE('Machine leg press', 3, 12, restBetween: 90, restAfter: 90),
        _PE('Machine leg curl', 3, 12, restBetween: 75, restAfter: 75),
        _PE('Machine standing calf raise', 4, 15),
        _PE('Hanging leg raise', 3, 12),
      ]),
    ],
  );
}

// --- Rowing templates -------------------------------------------------

class _Seg {
  const _Seg(this.duration, this.label, {this.spm, this.rest = false});
  final int duration;
  final String label;
  final int? spm;
  final bool rest;
}

/// The preset plans shown in the library — each a fixed-seed run of the
/// generator so they stay realistic and consistent across installs.
final _presetPlans = <RowingPlanInput>[
  const RowingPlanInput(
    sessionsPerWeek: 3,
    goal: RowingGoal.vetverlies,
    level: ProgramLevel.beginner,
    bands: {(20, 30), (25, 40)},
    weeks: 9,
    name: 'Vetverlies · 3×/week · beginner',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 4,
    goal: RowingGoal.vetverlies,
    level: ProgramLevel.medium,
    bands: {(25, 40), (30, 45), (45, 60)},
    weeks: 12,
    name: 'Vetverlies · 4×/week · opbouw',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 3,
    goal: RowingGoal.uithouding,
    level: ProgramLevel.medium,
    bands: {(30, 45), (45, 60)},
    weeks: 10,
    name: 'Uithouding opbouwen · 3×/week',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 4,
    goal: RowingGoal.uithouding,
    level: ProgramLevel.advanced,
    bands: {(30, 45), (45, 60)},
    weeks: 12,
    name: 'Uithouding · 4×/week · gevorderd',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 3,
    goal: RowingGoal.kracht,
    level: ProgramLevel.medium,
    bands: {(20, 30), (25, 40)},
    weeks: 8,
    name: 'Kracht & vermogen · 3×/week',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 4,
    goal: RowingGoal.kracht,
    level: ProgramLevel.advanced,
    bands: {(20, 30), (25, 40)},
    weeks: 8,
    name: 'Kort & krachtig · 4×/week',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 3,
    goal: RowingGoal.techniek,
    level: ProgramLevel.beginner,
    bands: {(15, 25), (20, 30)},
    weeks: 8,
    name: 'Techniek & basis · 3×/week',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 3,
    goal: RowingGoal.techniek,
    level: ProgramLevel.medium,
    bands: {(20, 30), (25, 40)},
    weeks: 10,
    name: 'Techniek verfijnen · 3×/week',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 2,
    goal: RowingGoal.algemeen,
    level: ProgramLevel.beginner,
    bands: {(20, 30)},
    weeks: 8,
    name: 'Algemene conditie · 2×/week',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 3,
    goal: RowingGoal.algemeen,
    level: ProgramLevel.medium,
    bands: {(20, 30), (25, 40)},
    weeks: 10,
    name: 'Algemene conditie · 3×/week',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 4,
    goal: RowingGoal.algemeen,
    level: ProgramLevel.medium,
    bands: {(20, 30), (25, 40), (30, 45)},
    weeks: 12,
    name: 'Allround · 4×/week · 12 weken',
  ),
  const RowingPlanInput(
    sessionsPerWeek: 3,
    goal: RowingGoal.uithouding,
    level: ProgramLevel.beginner,
    bands: {(20, 30), (25, 40)},
    weeks: 8,
    name: 'Instap uithouding · 3×/week',
  ),
];

Future<void> seedRowingTemplates(DatabaseExecutor db) async {
  await _insertLooseSession(
    db,
    'Endurance 20 min',
    ProgramCategory.rowSteady,
    const [
      _Seg(180, 'Warming-up', spm: 18),
      _Seg(1020, 'Endurance', spm: 21),
      _Seg(120, 'Uitroeien', spm: 16),
    ],
  );
  await _insertLooseSession(
    db,
    'Intervallen 4×500m',
    ProgramCategory.rowInterval,
    const [
      _Seg(180, 'Warming-up', spm: 18),
      _Seg(110, 'Hard 1/4', spm: 28),
      _Seg(90, 'Rust', spm: 18, rest: true),
      _Seg(110, 'Hard 2/4', spm: 28),
      _Seg(90, 'Rust', spm: 18, rest: true),
      _Seg(110, 'Hard 3/4', spm: 28),
      _Seg(90, 'Rust', spm: 18, rest: true),
      _Seg(110, 'Hard 4/4', spm: 28),
      _Seg(120, 'Uitroeien', spm: 16),
    ],
  );
  await _insertLooseSession(
    db,
    'Piramide 1-2-3-2-1',
    ProgramCategory.rowPyramid,
    const [
      _Seg(180, 'Warming-up', spm: 18),
      _Seg(60, 'Opbouw', spm: 24),
      _Seg(60, 'Rust', spm: 18, rest: true),
      _Seg(120, 'Middel', spm: 26),
      _Seg(60, 'Rust', spm: 18, rest: true),
      _Seg(180, 'Piek', spm: 28),
      _Seg(60, 'Rust', spm: 18, rest: true),
      _Seg(120, 'Middel', spm: 26),
      _Seg(60, 'Rust', spm: 18, rest: true),
      _Seg(60, 'Afbouw', spm: 24),
      _Seg(120, 'Uitroeien', spm: 16),
    ],
  );

  for (var i = 0; i < _presetPlans.length; i++) {
    final plan =
        RowingPlanGenerator(rng: Random(1000 + i)).generate(_presetPlans[i]);
    await _insertRowingPlan(db, plan, isTemplate: true);
  }
}

Future<void> _insertLooseSession(
  DatabaseExecutor db,
  String name,
  String category,
  List<_Seg> segments,
) async {
  final programId = await db.insert('programs', {
    'name': name,
    'category': category,
    'discipline': Discipline.rowing.name,
    'is_template': 1,
    'equipment_profile': '',
  });
  final dayId = await db.insert('program_days', {
    'program_id': programId,
    'day_index': 0,
    'label': name,
  });
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    await db.insert('program_row_segments', {
      'program_day_id': dayId,
      'order_index': i,
      'duration_seconds': s.duration,
      'target_stroke_rate': s.spm,
      'intensity_label': s.label,
      'is_rest': s.rest ? 1 : 0,
    });
  }
}

/// Persists a generated rowing plan. [isTemplate] true for the library presets,
/// false for a user-built plan.
Future<int> _insertRowingPlan(
  DatabaseExecutor db,
  GeneratedRowingPlan plan, {
  required bool isTemplate,
}) async {
  final programId = await db.insert('programs', {
    'name': plan.name,
    'category': ProgramCategory.rowPlan,
    'discipline': Discipline.rowing.name,
    'is_template': isTemplate ? 1 : 0,
    'level': plan.level.name,
    'days_per_week': plan.sessionsPerWeek,
    'equipment_profile': '',
    'goal': plan.goal.name,
  });
  for (var d = 0; d < plan.sessions.length; d++) {
    final session = plan.sessions[d];
    final dayId = await db.insert('program_days', {
      'program_id': programId,
      'day_index': d,
      'label': session.label,
      'row_session_type': session.type.name,
    });
    for (var i = 0; i < session.segments.length; i++) {
      final seg = session.segments[i];
      await db.insert('program_row_segments', {
        'program_day_id': dayId,
        'order_index': i,
        'duration_seconds': seg.durationSeconds,
        'target_stroke_rate': seg.targetSpm,
        'intensity_label': seg.intensityLabel,
        'is_rest': seg.isRest ? 1 : 0,
        'drill_key': seg.drillKey,
        'zone': seg.zone,
      });
    }
  }
  return programId;
}
