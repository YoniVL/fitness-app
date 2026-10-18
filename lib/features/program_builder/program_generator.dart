import 'dart:math';

import '../../domain/models/exercise.dart';
import '../../domain/models/program.dart';
import '../../domain/taxonomy.dart';

/// One generated exercise slot.
class GeneratedExercise {
  const GeneratedExercise({
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.restBetweenSets,
    required this.restAfterExercise,
  });

  final Exercise exercise;
  final int sets;
  final int reps;
  final int restBetweenSets;
  final int restAfterExercise;
}

class GeneratedDay {
  const GeneratedDay({required this.label, required this.exercises});
  final String label;
  final List<GeneratedExercise> exercises;
}

class GeneratedProgram {
  const GeneratedProgram({
    required this.name,
    required this.level,
    required this.daysPerWeek,
    required this.equipmentProfile,
    required this.days,
    this.warnings = const [],
  });

  final String name;
  final ProgramLevel level;
  final int daysPerWeek;
  final List<String> equipmentProfile;
  final List<GeneratedDay> days;

  /// Non-fatal notes for the UI (e.g. "verticaal trekken beperkt zonder stang").
  final List<String> warnings;
}

/// How a 4-day week is split. Other day counts have one fixed structure.
enum FourDaySplit {
  /// Duwen / Trekken / Benen / Full-body — one dedicated leg day, so a rowing
  /// habit on top doesn't pile fatigue onto the same muscles.
  pushPullLegsFull('Duwen / Trekken / Benen / Full-body'),

  /// Bovenlichaam / Onderlichaam, twice — every muscle group twice a week.
  upperLower('Bovenlichaam / Onderlichaam ×2');

  const FourDaySplit(this.label);
  final String label;
}

class GeneratorInput {
  const GeneratorInput({
    required this.daysPerWeek,
    required this.level,
    required this.muscleGroups,
    required this.equipment,
    this.name,
    this.minutesPerSession,
    this.restBetweenSets = 30,
    this.restAfterExercise = 60,
    this.fourDaySplit = FourDaySplit.pushPullLegsFull,
  });

  /// Only used when [daysPerWeek] is 4.
  final FourDaySplit fourDaySplit;

  final int daysPerWeek;
  final ProgramLevel level;
  final Set<String> muscleGroups;
  final Set<String> equipment;
  final String? name;

  /// If set, the time budget per training day drives the number of exercises;
  /// otherwise the level's default is used.
  final int? minutesPerSession;
  final int restBetweenSets;
  final int restAfterExercise;
}

/// A kind of training day. [patterns] is in *priority* order: a short day keeps
/// the front of the list, a long one cycles through it again for variety. The
/// day is displayed compounds → core → isolation regardless.
enum _DayKind {
  push('Duwen', [
    MovementPattern.horizontalPush,
    MovementPattern.verticalPush,
    MovementPattern.horizontalPush,
    MovementPattern.tricepsIso,
    MovementPattern.sideDeltIso,
    MovementPattern.core,
    MovementPattern.verticalPush,
    MovementPattern.tricepsIso,
  ]),
  pull('Trekken', [
    MovementPattern.horizontalPull,
    MovementPattern.verticalPull,
    MovementPattern.horizontalPull,
    MovementPattern.bicepsIso,
    MovementPattern.core,
    MovementPattern.verticalPull,
    MovementPattern.bicepsIso,
    MovementPattern.horizontalPull,
  ]),
  legs('Benen', [
    MovementPattern.squat,
    MovementPattern.hinge,
    MovementPattern.lunge,
    MovementPattern.calfIso,
    MovementPattern.core,
    MovementPattern.squat,
    MovementPattern.hinge,
    MovementPattern.lunge,
  ]),
  // Hinge-led lower day, so two lower days in a week differ.
  legsHinge('Benen', [
    MovementPattern.hinge,
    MovementPattern.squat,
    MovementPattern.lunge,
    MovementPattern.calfIso,
    MovementPattern.core,
    MovementPattern.hinge,
    MovementPattern.squat,
    MovementPattern.lunge,
  ]),
  upperA('Bovenlichaam', [
    MovementPattern.horizontalPush,
    MovementPattern.horizontalPull,
    MovementPattern.verticalPush,
    MovementPattern.verticalPull,
    MovementPattern.tricepsIso,
    MovementPattern.sideDeltIso,
    MovementPattern.bicepsIso,
    MovementPattern.core,
  ]),
  upperB('Bovenlichaam', [
    MovementPattern.horizontalPull,
    MovementPattern.horizontalPush,
    MovementPattern.verticalPull,
    MovementPattern.verticalPush,
    MovementPattern.bicepsIso,
    MovementPattern.sideDeltIso,
    MovementPattern.tricepsIso,
    MovementPattern.core,
  ]),
  fullA('Full-body', [
    MovementPattern.squat,
    MovementPattern.horizontalPush,
    MovementPattern.horizontalPull,
    MovementPattern.core,
    MovementPattern.verticalPush,
    MovementPattern.hinge,
    MovementPattern.bicepsIso,
    MovementPattern.tricepsIso,
  ]),
  fullB('Full-body', [
    MovementPattern.hinge,
    MovementPattern.verticalPush,
    MovementPattern.verticalPull,
    MovementPattern.core,
    MovementPattern.horizontalPush,
    MovementPattern.lunge,
    MovementPattern.sideDeltIso,
    MovementPattern.bicepsIso,
  ]),
  fullC('Full-body', [
    MovementPattern.lunge,
    MovementPattern.horizontalPush,
    MovementPattern.horizontalPull,
    MovementPattern.core,
    MovementPattern.verticalPull,
    MovementPattern.squat,
    MovementPattern.calfIso,
    MovementPattern.tricepsIso,
  ]),
  // Full-body with light legs (single-leg only) — follows a heavy leg day.
  fullLight('Full-body', [
    MovementPattern.horizontalPush,
    MovementPattern.horizontalPull,
    MovementPattern.lunge,
    MovementPattern.verticalPush,
    MovementPattern.core,
    MovementPattern.verticalPull,
    MovementPattern.bicepsIso,
    MovementPattern.tricepsIso,
  ]);

  const _DayKind(this.label, this.patterns);
  final String label;
  final List<MovementPattern> patterns;
}

/// What a day without any usable pattern (e.g. a leg day when no leg muscle
/// group is selected) is swapped for, in rotation.
const _substitutes = [
  _DayKind.upperA,
  _DayKind.upperB,
  _DayKind.push,
  _DayKind.pull,
];

List<_DayKind> _weekStructure(int days, FourDaySplit split) => switch (days) {
      2 => [_DayKind.fullA, _DayKind.fullB],
      3 => [_DayKind.fullA, _DayKind.fullB, _DayKind.fullC],
      4 => switch (split) {
          FourDaySplit.pushPullLegsFull => [
              _DayKind.push,
              _DayKind.pull,
              _DayKind.legs,
              _DayKind.fullLight,
            ],
          FourDaySplit.upperLower => [
              _DayKind.upperA,
              _DayKind.legs,
              _DayKind.upperB,
              _DayKind.legsHinge,
            ],
        },
      _ => [
          _DayKind.push,
          _DayKind.pull,
          _DayKind.legs,
          _DayKind.upperA,
          _DayKind.legsHinge,
        ],
    };

/// Builds a weekly strength program from a fixed split (see [_weekStructure]),
/// filling each day's movement-pattern slots with equipment-compatible
/// exercises and keeping only the patterns relevant to the chosen muscle groups.
class ProgramGenerator {
  ProgramGenerator(this.catalogue, {Random? rng}) : _rng = rng ?? Random();

  final List<Exercise> catalogue;
  final Random _rng;

  GeneratedProgram generate(GeneratorInput input) {
    if (input.muscleGroups.isEmpty) {
      throw ArgumentError('Kies minstens één spiergroep om te trainen.');
    }
    final days = input.daysPerWeek.clamp(2, 5);

    // 1. Patterns relevant to the selected muscle groups. Leg patterns only
    // count when an actual leg muscle group is selected (hinge also trains the
    // lower back, but "geen benen" should still drop it).
    const legPatterns = {
      MovementPattern.squat,
      MovementPattern.hinge,
      MovementPattern.lunge,
      MovementPattern.calfIso,
    };
    bool relevantPattern(MovementPattern p) {
      final mgs = patternMuscleGroups[p]!;
      if (legPatterns.contains(p)) {
        return input.muscleGroups
            .any((m) => MuscleGroups.legs.contains(m) && mgs.contains(m));
      }
      return mgs.any(input.muscleGroups.contains);
    }

    final relevant = MovementPattern.values.where(relevantPattern).toList();

    // 2. Equipment-compatible exercise options per pattern.
    final options = <MovementPattern, List<Exercise>>{};
    for (final p in relevant) {
      final opts = catalogue
          .where((e) =>
              e.pattern == p && e.canPerformWith(input.equipment))
          .toList()
        ..shuffle(_rng);
      if (opts.isNotEmpty) options[p] = opts;
    }
    if (options.isEmpty) {
      throw StateError(
          'Geen oefeningen gevonden voor deze combinatie van materiaal en spiergroepen.');
    }

    final sets = input.level.setsPerExercise;
    // Time budget (if given) drives the exercise count: roughly
    // 3 min setup + sets * (~40s work + rest) per exercise.
    final exPerDay = input.minutesPerSession == null
        ? input.level.exercisesPerDay
        : (input.minutesPerSession! /
                (3 + sets * (40 + input.restBetweenSets) / 60))
            .round()
            .clamp(3, 9);

    // Per-pattern cursor so consecutive days pick different exercises.
    final exerciseCursor = <MovementPattern, int>{};

    Exercise pick(MovementPattern p, Set<int> usedToday) {
      final list = options[p]!;
      final start = exerciseCursor[p] ?? _rng.nextInt(list.length);
      for (var i = 0; i < list.length; i++) {
        final e = list[(start + i) % list.length];
        if (!usedToday.contains(e.id)) {
          exerciseCursor[p] = (start + i + 1) % list.length;
          return e;
        }
      }
      exerciseCursor[p] = (start + 1) % list.length;
      return list[start % list.length];
    }

    GeneratedExercise slot(MovementPattern pattern, Exercise ex) {
      // One-arm / single-leg work: keep the set count even so both sides match.
      final s = ex.isUnilateral && sets.isOdd ? sets + 1 : sets;
      return GeneratedExercise(
        exercise: ex,
        sets: s,
        reps: ex.isTimeBased ? defaultHoldSeconds : defaultRepsFor(pattern),
        restBetweenSets: input.restBetweenSets,
        restAfterExercise: input.restAfterExercise,
      );
    }

    // Core alone doesn't make a training day, so it doesn't count as usable.
    List<MovementPattern> usable(_DayKind k) {
      final ps = k.patterns.where(options.containsKey).toList();
      return ps.any((p) => p != MovementPattern.core) ? ps : const [];
    }

    final structure = _weekStructure(days, input.fourDaySplit);
    var substituteCursor = 0;
    final generatedDays = <GeneratedDay>[];
    for (var d = 0; d < days; d++) {
      var kind = structure[d];
      var patterns = usable(kind);
      if (patterns.isEmpty) {
        // Nothing of this day type is trainable with the chosen muscle groups /
        // equipment (e.g. a leg day without legs) — swap in an upper-body day.
        for (var i = 0; i < _substitutes.length && patterns.isEmpty; i++) {
          kind = _substitutes[(substituteCursor + i) % _substitutes.length];
          patterns = usable(kind);
        }
        substituteCursor++;
        // Last resort: whatever is left (e.g. only core or only isolation).
        if (patterns.isEmpty) patterns = options.keys.toList();
      }

      // Walk the priority list (repeating it when the day is longer), skipping
      // exercises already used today, until the day is full.
      final usedToday = <int>{};
      final picked = <(MovementPattern, Exercise)>[];
      for (final pattern in [...patterns, ...patterns, ...patterns]) {
        if (picked.length >= exPerDay) break;
        final ex = pick(pattern, usedToday);
        if (usedToday.contains(ex.id)) continue; // pattern is used up
        usedToday.add(ex.id);
        picked.add((pattern, ex));
      }

      // Display order: compounds, then core, then isolation.
      int rank(MovementPattern p) =>
          p.isCompound ? 0 : (p == MovementPattern.core ? 1 : 2);
      final slots = [
        for (var r = 0; r < 3; r++)
          for (final (pattern, ex) in picked)
            if (rank(pattern) == r) slot(pattern, ex),
      ];

      generatedDays.add(GeneratedDay(
          label: 'Dag ${d + 1} · ${kind.label}', exercises: slots));
    }

    final warnings = <String>[];
    if (input.muscleGroups.contains(MuscleGroups.rug) &&
        !options.containsKey(MovementPattern.verticalPull)) {
      warnings.add(
          'Verticaal trekken (pull-ups) ontbreekt — voeg een optrekstang toe voor meer rugwerk.');
    }
    // Muscle groups selected but never hit.
    final hit = <String>{};
    for (final day in generatedDays) {
      for (final ge in day.exercises) {
        hit.addAll(patternMuscleGroups[ge.exercise.pattern] ?? const {});
      }
    }
    final missed = input.muscleGroups.difference(hit);
    if (missed.isNotEmpty) {
      warnings.add('Niet ingepland: ${missed.join(', ')}.');
    }

    return GeneratedProgram(
      name: input.name?.trim().isNotEmpty == true
          ? input.name!.trim()
          : 'Mijn schema (${input.level.label})',
      level: input.level,
      daysPerWeek: days,
      equipmentProfile: input.equipment.toList(),
      days: generatedDays,
      warnings: warnings,
    );
  }
}
