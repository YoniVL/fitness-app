import 'package:sqflite/sqflite.dart';

import '../../domain/models/program.dart';

/// Seeds reference data (muscle groups, exercises), default settings, and the
/// starter templates. Runs once, inside `onCreate`.
Future<void> seedDatabase(DatabaseExecutor db) async {
  final muscleGroupIds = await _seedMuscleGroups(db);
  final exerciseIds = await _seedExercises(db, muscleGroupIds);
  await _seedSettings(db);
  await _seedStrengthTemplates(db, exerciseIds);
  await _seedRowingTemplates(db);
}

// --- Muscle groups ----------------------------------------------------------

/// name -> icon key (UI maps the key to a Material icon).
const _muscleGroups = <String, String>{
  'Borst': 'chest',
  'Rug': 'back',
  'Benen': 'legs',
  'Schouders': 'shoulders',
  'Biceps': 'biceps',
  'Triceps': 'triceps',
  'Core': 'core',
  'Bilspieren': 'glutes',
  'Kuiten': 'calves',
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

// --- Exercises -------------------------------------------------------------

class _Ex {
  const _Ex(this.name, this.primary, this.equipment, {this.secondary = const []});
  final String name;
  final String primary;
  final String equipment;
  final List<String> secondary;
}

const _exercises = <_Ex>[
  // Borst
  _Ex('Bankdrukken', 'Borst', 'barbell', secondary: ['Triceps', 'Schouders']),
  _Ex('Halter bankdruk', 'Borst', 'dumbbell', secondary: ['Triceps', 'Schouders']),
  _Ex('Incline bankdruk', 'Borst', 'barbell', secondary: ['Schouders', 'Triceps']),
  _Ex('Dips', 'Borst', 'bodyweight', secondary: ['Triceps']),
  _Ex('Push-up', 'Borst', 'bodyweight', secondary: ['Triceps', 'Core']),
  _Ex('Kabel fly', 'Borst', 'cable'),
  // Rug
  _Ex('Deadlift', 'Rug', 'barbell', secondary: ['Benen', 'Bilspieren']),
  _Ex('Barbell row', 'Rug', 'barbell', secondary: ['Biceps']),
  _Ex('Pull-up', 'Rug', 'bodyweight', secondary: ['Biceps']),
  _Ex('Lat pulldown', 'Rug', 'cable', secondary: ['Biceps']),
  _Ex('Seated cable row', 'Rug', 'cable', secondary: ['Biceps']),
  _Ex('Face pull', 'Schouders', 'cable', secondary: ['Rug']),
  // Benen
  _Ex('Squat', 'Benen', 'barbell', secondary: ['Bilspieren', 'Core']),
  _Ex('Front squat', 'Benen', 'barbell', secondary: ['Core']),
  _Ex('Leg press', 'Benen', 'machine', secondary: ['Bilspieren']),
  _Ex('Lunges', 'Benen', 'dumbbell', secondary: ['Bilspieren']),
  _Ex('Romanian deadlift', 'Benen', 'barbell', secondary: ['Bilspieren', 'Rug']),
  _Ex('Leg extension', 'Benen', 'machine'),
  _Ex('Leg curl', 'Benen', 'machine'),
  // Schouders
  _Ex('Overhead press', 'Schouders', 'barbell', secondary: ['Triceps']),
  _Ex('Dumbbell shoulder press', 'Schouders', 'dumbbell', secondary: ['Triceps']),
  _Ex('Lateral raise', 'Schouders', 'dumbbell'),
  _Ex('Reverse fly', 'Schouders', 'dumbbell', secondary: ['Rug']),
  // Biceps
  _Ex('Barbell curl', 'Biceps', 'barbell'),
  _Ex('Dumbbell curl', 'Biceps', 'dumbbell'),
  _Ex('Hammer curl', 'Biceps', 'dumbbell'),
  // Triceps
  _Ex('Triceps pushdown', 'Triceps', 'cable'),
  _Ex('Skull crusher', 'Triceps', 'barbell'),
  _Ex('Overhead triceps extension', 'Triceps', 'dumbbell'),
  // Core
  _Ex('Plank', 'Core', 'bodyweight'),
  _Ex('Hanging leg raise', 'Core', 'bodyweight'),
  _Ex('Cable crunch', 'Core', 'cable'),
  // Bilspieren
  _Ex('Hip thrust', 'Bilspieren', 'barbell', secondary: ['Benen']),
  _Ex('Glute bridge', 'Bilspieren', 'bodyweight'),
  // Kuiten
  _Ex('Standing calf raise', 'Kuiten', 'machine'),
  _Ex('Seated calf raise', 'Kuiten', 'machine'),
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
      'equipment': ex.equipment,
      'media_key': null,
      'is_custom': 0,
    });
  }
  return ids;
}

// --- Settings -------------------------------------------------------------

Future<void> _seedSettings(DatabaseExecutor db) async {
  const defaults = <String, String>{
    'default_rest_seconds': '120',
    'rest_timer_sound': 'true',
    'weekly_schedule': '{}', // JSON: weekday index -> program_day_id
  };
  for (final entry in defaults.entries) {
    await db.insert('app_settings', {'key': entry.key, 'value': entry.value});
  }
}

// --- Strength templates --------------------------------------------------

class _PE {
  const _PE(this.exercise, this.sets, this.reps, {this.rest = 120});
  final String exercise;
  final int sets;
  final int reps;
  final int rest;
}

Future<void> _seedStrengthTemplates(
  DatabaseExecutor db,
  Map<String, int> exerciseIds,
) async {
  Future<void> insertDay(int programId, int dayIndex, String label, List<_PE> items) async {
    final dayId = await db.insert('program_days', {
      'program_id': programId,
      'day_index': dayIndex,
      'label': label,
    });
    for (var i = 0; i < items.length; i++) {
      final pe = items[i];
      await db.insert('program_exercises', {
        'program_day_id': dayId,
        'exercise_id': exerciseIds[pe.exercise],
        'order_index': i,
        'target_sets': pe.sets,
        'target_reps': pe.reps,
        'target_weight': null,
        'rest_seconds': pe.rest,
      });
    }
  }

  // Full-body A/B
  final fullBodyId = await db.insert('programs', {
    'name': 'Full-body A/B',
    'category': ProgramCategory.strengthFullbody,
    'discipline': Discipline.strength.name,
    'is_template': 1,
  });
  await insertDay(fullBodyId, 0, 'Full-body A', const [
    _PE('Squat', 3, 5, rest: 180),
    _PE('Bankdrukken', 3, 5, rest: 180),
    _PE('Barbell row', 3, 8, rest: 120),
    _PE('Overhead press', 3, 8, rest: 120),
    _PE('Barbell curl', 3, 12, rest: 60),
  ]);
  await insertDay(fullBodyId, 1, 'Full-body B', const [
    _PE('Deadlift', 3, 5, rest: 210),
    _PE('Overhead press', 3, 5, rest: 180),
    _PE('Lat pulldown', 3, 10, rest: 120),
    _PE('Halter bankdruk', 3, 10, rest: 120),
    _PE('Triceps pushdown', 3, 12, rest: 60),
  ]);

  // Push / Pull / Legs
  final pplId = await db.insert('programs', {
    'name': 'Push / Pull / Legs',
    'category': ProgramCategory.strengthPpl,
    'discipline': Discipline.strength.name,
    'is_template': 1,
  });
  await insertDay(pplId, 0, 'Push', const [
    _PE('Bankdrukken', 4, 6, rest: 180),
    _PE('Dumbbell shoulder press', 3, 10, rest: 120),
    _PE('Incline bankdruk', 3, 10, rest: 120),
    _PE('Lateral raise', 3, 15, rest: 60),
    _PE('Triceps pushdown', 3, 12, rest: 60),
    _PE('Overhead triceps extension', 3, 12, rest: 60),
  ]);
  await insertDay(pplId, 1, 'Pull', const [
    _PE('Deadlift', 3, 5, rest: 210),
    _PE('Pull-up', 3, 8, rest: 120),
    _PE('Barbell row', 3, 10, rest: 120),
    _PE('Seated cable row', 3, 12, rest: 90),
    _PE('Face pull', 3, 15, rest: 60),
    _PE('Barbell curl', 3, 12, rest: 60),
    _PE('Hammer curl', 3, 12, rest: 60),
  ]);
  await insertDay(pplId, 2, 'Legs', const [
    _PE('Squat', 4, 6, rest: 180),
    _PE('Romanian deadlift', 3, 10, rest: 150),
    _PE('Leg press', 3, 12, rest: 120),
    _PE('Leg curl', 3, 12, rest: 90),
    _PE('Standing calf raise', 4, 15, rest: 60),
    _PE('Hanging leg raise', 3, 12, rest: 60),
  ]);
}

// --- Rowing templates --------------------------------------------------

class _Seg {
  const _Seg(this.duration, this.label, {this.spm, this.rest = false});
  final int duration;
  final String label;
  final int? spm;
  final bool rest;
}

Future<void> _seedRowingTemplates(DatabaseExecutor db) async {
  Future<void> insertRowProgram(
    String name,
    String category,
    String dayLabel,
    List<_Seg> segments,
  ) async {
    final programId = await db.insert('programs', {
      'name': name,
      'category': category,
      'discipline': Discipline.rowing.name,
      'is_template': 1,
    });
    final dayId = await db.insert('program_days', {
      'program_id': programId,
      'day_index': 0,
      'label': dayLabel,
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

  await insertRowProgram(
    'Steady state 20 min',
    ProgramCategory.rowSteady,
    'Steady 20 min',
    const [_Seg(1200, 'Steady', spm: 22)],
  );

  await insertRowProgram(
    'Intervallen 4x500m',
    ProgramCategory.rowInterval,
    '4 x 500m',
    const [
      _Seg(110, 'Hard', spm: 28),
      _Seg(90, 'Rust', spm: 18, rest: true),
      _Seg(110, 'Hard', spm: 28),
      _Seg(90, 'Rust', spm: 18, rest: true),
      _Seg(110, 'Hard', spm: 28),
      _Seg(90, 'Rust', spm: 18, rest: true),
      _Seg(110, 'Hard', spm: 28),
      _Seg(120, 'Uitroeien', spm: 16, rest: true),
    ],
  );

  await insertRowProgram(
    'Pyramide',
    ProgramCategory.rowPyramid,
    'Pyramide 1-2-3-2-1',
    const [
      _Seg(60, 'Opbouw', spm: 24),
      _Seg(60, 'Rust', spm: 18, rest: true),
      _Seg(120, 'Middel', spm: 26),
      _Seg(60, 'Rust', spm: 18, rest: true),
      _Seg(180, 'Piek', spm: 28),
      _Seg(60, 'Rust', spm: 18, rest: true),
      _Seg(120, 'Middel', spm: 26),
      _Seg(60, 'Rust', spm: 18, rest: true),
      _Seg(60, 'Afbouw', spm: 24),
    ],
  );
}
