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
  });

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

/// Builds a weekly strength program from movement-pattern slots, using only
/// equipment-compatible exercises and only the patterns relevant to the chosen
/// muscle groups.
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

    final compounds = options.keys.where((p) => p.isCompound).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final cores =
        options.keys.where((p) => p == MovementPattern.core).toList();
    final isos = options.keys.where((p) => p.isIsolation).toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final sets = input.level.setsPerExercise;
    // Time budget (if given) drives the exercise count: roughly
    // 3 min setup + sets * (~40s work + rest) per exercise.
    final exPerDay = input.minutesPerSession == null
        ? input.level.exercisesPerDay
        : (input.minutesPerSession! /
                (3 + sets * (40 + input.restBetweenSets) / 60))
            .round()
            .clamp(3, 9);

    // Day composition: mostly compounds, then core, then isolation.
    final coreSlots = cores.isEmpty ? 0 : (exPerDay >= 4 ? 1 : 0);
    var isoSlots = isos.isEmpty
        ? 0
        : (input.level == ProgramLevel.advanced ? 2 : (exPerDay >= 5 ? 1 : 0));
    var compoundSlots = exPerDay - coreSlots - isoSlots;
    if (compounds.isEmpty) {
      // No compounds available — everything becomes core/iso.
      compoundSlots = 0;
      isoSlots = exPerDay - coreSlots;
    }

    // Round-robin cursors so consecutive days pick different patterns/exercises.
    var compoundCursor = 0;
    var coreCursor = 0;
    var isoCursor = 0;
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
        reps: defaultRepsFor(pattern),
        restBetweenSets: input.restBetweenSets,
        restAfterExercise: input.restAfterExercise,
      );
    }

    final generatedDays = <GeneratedDay>[];
    for (var d = 0; d < days; d++) {
      final usedToday = <int>{};
      final slots = <GeneratedExercise>[];

      void addFrom(List<MovementPattern> patterns, int count, int Function() cursor,
          void Function(int) bump) {
        if (patterns.isEmpty) return;
        var c = cursor();
        for (var i = 0; i < count; i++) {
          final pattern = patterns[c % patterns.length];
          c++;
          final ex = pick(pattern, usedToday);
          usedToday.add(ex.id);
          slots.add(slot(pattern, ex));
        }
        bump(c);
      }

      addFrom(compounds, compoundSlots, () => compoundCursor,
          (v) => compoundCursor = v);
      addFrom(cores, coreSlots, () => coreCursor, (v) => coreCursor = v);
      addFrom(isos, isoSlots, () => isoCursor, (v) => isoCursor = v);

      // Top up if a category was empty and we came up short.
      while (slots.length < exPerDay) {
        final pool = [
          ...compounds,
          ...isos,
          ...cores,
        ];
        if (pool.isEmpty) break;
        final pattern = pool[slots.length % pool.length];
        final ex = pick(pattern, usedToday);
        if (usedToday.contains(ex.id)) break; // nothing new to add
        usedToday.add(ex.id);
        slots.add(slot(pattern, ex));
      }

      generatedDays.add(GeneratedDay(label: 'Dag ${d + 1}', exercises: slots));
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
