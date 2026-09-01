/// Shared vocabulary for equipment, muscle groups and movement patterns.
/// Used by the exercise catalogue, the program generator and the library filters.
library;

/// Equipment tags. An exercise lists the tags it requires (minus [bodyweight],
/// which everyone has); the user lists the tags they own.
class Equipment {
  static const bodyweight = 'bodyweight';
  static const dumbbell = 'dumbbell';
  static const bench = 'bench';
  static const benchIncline = 'bench_incline';
  static const barbell = 'barbell';
  static const machine = 'machine';
  static const cable = 'cable';
  static const pullupBar = 'pullup_bar';
  static const bands = 'bands';
  static const kettlebell = 'kettlebell';

  /// Order shown in the settings checklist.
  static const all = <String>[
    dumbbell,
    bench,
    benchIncline,
    barbell,
    machine,
    cable,
    pullupBar,
    bands,
    kettlebell,
  ];

  static const _labels = <String, String>{
    bodyweight: 'Lichaamsgewicht',
    dumbbell: 'Verstelbare dumbbells',
    bench: 'Vlakke bank',
    benchIncline: 'Incline-bank',
    barbell: 'Barbell (gym)',
    machine: 'Fitnesstoestellen (gym)',
    cable: 'Kabelmachine (gym)',
    pullupBar: 'Optrekstang',
    bands: 'Weerstandsbanden',
    kettlebell: 'Kettlebell',
  };

  /// One-line hint shown under the checklist.
  static const machineHint =
      'Fitnesstoestellen = geleide gewichtsmachines uit een fitnesszaal '
      '(lat pulldown, leg press, leg curl/extension, cable row).';

  static String label(String tag) => _labels[tag] ?? tag;

  /// Default for a fresh install (the user's home setup).
  static const defaultOwned = <String>{dumbbell, bench, benchIncline};

  static List<String> parse(String? csv) => (csv ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  static String join(Iterable<String> tags) => tags.join(',');
}

/// Muscle group names — the canonical keys, matching `muscle_groups.name` in the
/// seed. Kept as strings so the DB stays the source of truth for ids.
class MuscleGroups {
  static const borst = 'Borst';
  static const rug = 'Rug';
  static const benen = 'Benen';
  static const schouders = 'Schouders';
  static const biceps = 'Biceps';
  static const triceps = 'Triceps';
  static const core = 'Core';
  static const bilspieren = 'Bilspieren';
  static const kuiten = 'Kuiten';

  static const all = <String>[
    borst,
    rug,
    benen,
    schouders,
    biceps,
    triceps,
    core,
    bilspieren,
    kuiten,
  ];

  /// Muscle groups that belong to "legs" — the ones the user often skips.
  static const legs = <String>{benen, bilspieren, kuiten};
}

/// Movement patterns. Every strength exercise is tagged with exactly one; the
/// generator fills a day by cycling through patterns.
enum MovementPattern {
  horizontalPush,
  verticalPush,
  horizontalPull,
  verticalPull,
  squat,
  hinge,
  lunge,
  core,
  bicepsIso,
  tricepsIso,
  sideDeltIso,
  calfIso;

  static MovementPattern? fromName(String? value) {
    if (value == null) return null;
    for (final p in values) {
      if (p.name == value) return p;
    }
    return null;
  }

  String get label => switch (this) {
        MovementPattern.horizontalPush => 'Horizontaal duwen',
        MovementPattern.verticalPush => 'Verticaal duwen',
        MovementPattern.horizontalPull => 'Horizontaal trekken',
        MovementPattern.verticalPull => 'Verticaal trekken',
        MovementPattern.squat => 'Squat',
        MovementPattern.hinge => 'Hip hinge',
        MovementPattern.lunge => 'Lunge',
        MovementPattern.core => 'Core',
        MovementPattern.bicepsIso => 'Biceps',
        MovementPattern.tricepsIso => 'Triceps',
        MovementPattern.sideDeltIso => 'Zijdelingse schouder',
        MovementPattern.calfIso => 'Kuiten',
      };

  bool get isCompound => const {
        MovementPattern.horizontalPush,
        MovementPattern.verticalPush,
        MovementPattern.horizontalPull,
        MovementPattern.verticalPull,
        MovementPattern.squat,
        MovementPattern.hinge,
        MovementPattern.lunge,
      }.contains(this);

  bool get isIsolation => const {
        MovementPattern.bicepsIso,
        MovementPattern.tricepsIso,
        MovementPattern.sideDeltIso,
        MovementPattern.calfIso,
      }.contains(this);
}

/// Which muscle groups each pattern trains (primary drivers). Used to decide
/// whether a pattern is relevant to the user's selected muscle groups.
const Map<MovementPattern, Set<String>> patternMuscleGroups = {
  MovementPattern.horizontalPush: {
    MuscleGroups.borst,
    MuscleGroups.triceps,
    MuscleGroups.schouders,
  },
  MovementPattern.verticalPush: {MuscleGroups.schouders, MuscleGroups.triceps},
  MovementPattern.horizontalPull: {MuscleGroups.rug, MuscleGroups.biceps},
  MovementPattern.verticalPull: {MuscleGroups.rug, MuscleGroups.biceps},
  MovementPattern.squat: {MuscleGroups.benen, MuscleGroups.bilspieren},
  MovementPattern.hinge: {
    MuscleGroups.bilspieren,
    MuscleGroups.benen,
    MuscleGroups.rug,
  },
  MovementPattern.lunge: {MuscleGroups.benen, MuscleGroups.bilspieren},
  MovementPattern.core: {MuscleGroups.core},
  MovementPattern.bicepsIso: {MuscleGroups.biceps},
  MovementPattern.tricepsIso: {MuscleGroups.triceps},
  MovementPattern.sideDeltIso: {MuscleGroups.schouders},
  MovementPattern.calfIso: {MuscleGroups.kuiten},
};

/// Reasonable rep target for a pattern.
int defaultRepsFor(MovementPattern pattern) => pattern.isIsolation ? 13 : 9;
