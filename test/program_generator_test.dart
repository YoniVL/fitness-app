import 'dart:math';

import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:fitnesstracker/data/repositories/exercise_repository.dart';
import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/taxonomy.dart';
import 'package:fitnesstracker/features/program_builder/program_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late ProgramGenerator generator;

  setUp(() async {
    await initTestDatabase();
    final catalogue =
        await ExerciseRepository(AppDatabase.instance).strengthCatalogue();
    generator = ProgramGenerator(catalogue, rng: Random(42));
  });
  tearDown(closeTestDatabase);

  const home = {Equipment.dumbbell, Equipment.bench, Equipment.benchIncline};

  test('produces the requested number of days and exercises', () {
    final program = generator.generate(GeneratorInput(
      daysPerWeek: 4,
      level: ProgramLevel.medium,
      muscleGroups: {...MuscleGroups.all},
      equipment: home,
    ));
    expect(program.days.length, 4);
    for (final day in program.days) {
      expect(day.exercises.length, ProgramLevel.medium.exercisesPerDay);
    }
  });

  test('only uses equipment-compatible exercises', () {
    final program = generator.generate(GeneratorInput(
      daysPerWeek: 3,
      level: ProgramLevel.beginner,
      muscleGroups: {...MuscleGroups.all},
      equipment: home,
    ));
    for (final day in program.days) {
      for (final ge in day.exercises) {
        expect(ge.exercise.canPerformWith(home), isTrue,
            reason: '${ge.exercise.name} needs ${ge.exercise.equipmentTags}');
      }
    }
  });

  test('skips leg work when legs are not selected', () {
    final selected = {...MuscleGroups.all}..removeAll(MuscleGroups.legs);
    final program = generator.generate(GeneratorInput(
      daysPerWeek: 4,
      level: ProgramLevel.medium,
      muscleGroups: selected,
      equipment: home,
    ));
    const legPatterns = {
      MovementPattern.squat,
      MovementPattern.hinge,
      MovementPattern.lunge,
      MovementPattern.calfIso,
    };
    for (final day in program.days) {
      for (final ge in day.exercises) {
        expect(legPatterns.contains(ge.exercise.pattern), isFalse,
            reason: '${ge.exercise.name} is a leg exercise');
      }
    }
  });

  test('covers every selected muscle group at least once', () {
    final selected = {MuscleGroups.borst, MuscleGroups.rug, MuscleGroups.core};
    final program = generator.generate(GeneratorInput(
      daysPerWeek: 3,
      level: ProgramLevel.medium,
      muscleGroups: selected,
      equipment: home,
    ));
    final hit = <String>{};
    for (final day in program.days) {
      for (final ge in day.exercises) {
        hit.addAll(patternMuscleGroups[ge.exercise.pattern] ?? const {});
      }
    }
    expect(hit.containsAll(selected), isTrue);
  });

  test('does not crash without a pull-up bar', () {
    final program = generator.generate(GeneratorInput(
      daysPerWeek: 3,
      level: ProgramLevel.beginner,
      muscleGroups: {MuscleGroups.rug, MuscleGroups.biceps},
      equipment: home,
    ));
    expect(program.days, isNotEmpty);
  });

  test('keeps unilateral exercises on an even number of sets', () {
    final program = generator.generate(GeneratorInput(
      daysPerWeek: 4,
      level: ProgramLevel.medium, // 3 sets by default -> odd
      muscleGroups: {...MuscleGroups.all},
      equipment: home,
    ));
    for (final day in program.days) {
      for (final ge in day.exercises) {
        if (ge.exercise.isUnilateral) {
          expect(ge.sets.isEven, isTrue,
              reason: '${ge.exercise.name} has ${ge.sets} sets');
        }
      }
    }
  });

  test('time budget drives the exercise count', () {
    final short = generator.generate(GeneratorInput(
      daysPerWeek: 3,
      level: ProgramLevel.medium,
      muscleGroups: {...MuscleGroups.all},
      equipment: home,
      minutesPerSession: 20,
    ));
    final long = generator.generate(GeneratorInput(
      daysPerWeek: 3,
      level: ProgramLevel.medium,
      muscleGroups: {...MuscleGroups.all},
      equipment: home,
      minutesPerSession: 60,
    ));
    expect(short.days.first.exercises.length,
        lessThan(long.days.first.exercises.length));
  });

  group('week structure', () {
    GeneratedProgram gen(int days,
            {FourDaySplit split = FourDaySplit.pushPullLegsFull,
            Set<String>? groups}) =>
        generator.generate(GeneratorInput(
          daysPerWeek: days,
          level: ProgramLevel.medium,
          muscleGroups: groups ?? {...MuscleGroups.all},
          equipment: home,
          fourDaySplit: split,
        ));

    const legPatterns = {
      MovementPattern.squat,
      MovementPattern.hinge,
      MovementPattern.lunge,
      MovementPattern.calfIso,
    };
    const pushPatterns = {
      MovementPattern.horizontalPush,
      MovementPattern.verticalPush,
      MovementPattern.tricepsIso,
      MovementPattern.sideDeltIso,
    };
    const pullPatterns = {
      MovementPattern.horizontalPull,
      MovementPattern.verticalPull,
      MovementPattern.bicepsIso,
    };

    Set<MovementPattern> patternsOf(GeneratedDay d) =>
        d.exercises.map((e) => e.exercise.pattern).whereType<MovementPattern>().toSet();

    test('days are named after their purpose', () {
      expect(gen(2).days.map((d) => d.label.split(' · ').last),
          ['Full-body', 'Full-body']);
      expect(gen(4).days.map((d) => d.label.split(' · ').last),
          ['Duwen', 'Trekken', 'Benen', 'Full-body']);
      expect(
          gen(4, split: FourDaySplit.upperLower)
              .days
              .map((d) => d.label.split(' · ').last),
          ['Bovenlichaam', 'Benen', 'Bovenlichaam', 'Benen']);
      expect(gen(5).days.map((d) => d.label.split(' · ').last),
          ['Duwen', 'Trekken', 'Benen', 'Bovenlichaam', 'Benen']);
    });

    test('push day only pushes, pull day only pulls, leg day only legs/core', () {
      final days = gen(4).days;
      for (final e in days[0].exercises) {
        expect(pushPatterns.contains(e.exercise.pattern) ||
            e.exercise.pattern == MovementPattern.core, isTrue,
            reason: 'Duwen has ${e.exercise.name}');
      }
      for (final e in days[1].exercises) {
        expect(pullPatterns.contains(e.exercise.pattern) ||
            e.exercise.pattern == MovementPattern.core, isTrue,
            reason: 'Trekken has ${e.exercise.name}');
      }
      for (final e in days[2].exercises) {
        expect(legPatterns.contains(e.exercise.pattern) ||
            e.exercise.pattern == MovementPattern.core, isTrue,
            reason: 'Benen has ${e.exercise.name}');
      }
    });

    test('the 4th day of push/pull/legs/full has no heavy bilateral leg work', () {
      final full = gen(4).days[3];
      expect(patternsOf(full).contains(MovementPattern.squat), isFalse);
      expect(patternsOf(full).contains(MovementPattern.hinge), isFalse);
      expect(patternsOf(full).contains(MovementPattern.horizontalPush), isTrue);
      expect(patternsOf(full).contains(MovementPattern.lunge), isTrue);
    });

    test('upper/lower hits every main pattern twice a week', () {
      final days = gen(4, split: FourDaySplit.upperLower).days;
      for (final i in [0, 2]) {
        expect(patternsOf(days[i]).containsAll({
          MovementPattern.horizontalPush,
          MovementPattern.horizontalPull,
          MovementPattern.verticalPush,
        }), isTrue);
        expect(patternsOf(days[i]).intersection(legPatterns), isEmpty);
      }
      for (final i in [1, 3]) {
        expect(patternsOf(days[i]).containsAll({
          MovementPattern.squat,
          MovementPattern.hinge,
        }), isTrue);
      }
    });

    test('heavy leg days never sit next to each other in a 5-day week', () {
      final days = gen(5).days;
      bool legDay(GeneratedDay d) =>
          d.exercises.where((e) => legPatterns.contains(e.exercise.pattern))
              .length >= 3;
      for (var i = 0; i < days.length; i++) {
        final next = days[(i + 1) % days.length];
        expect(legDay(days[i]) && legDay(next), isFalse,
            reason: 'day ${i + 1} and next are both leg days');
      }
    });

    test('no exercise repeats within a day, for every supported week', () {
      for (final d in [2, 3, 4, 5]) {
        for (final split in FourDaySplit.values) {
          for (final day in gen(d, split: split).days) {
            final ids = day.exercises.map((e) => e.exercise.id).toList();
            expect(ids.toSet().length, ids.length,
                reason: '${day.label} repeats an exercise');
          }
        }
      }
    });

    test('a leg day is replaced by upper-body work when legs are skipped', () {
      final noLegs = {...MuscleGroups.all}..removeAll(MuscleGroups.legs);
      final days = gen(4, groups: noLegs).days;
      expect(days.length, 4);
      expect(days.any((d) => d.label.endsWith('Benen')), isFalse);
      for (final d in days) {
        expect(d.exercises, isNotEmpty);
      }
    });
  });

  test('rejects an empty muscle group selection', () {
    expect(
      () => generator.generate(GeneratorInput(
        daysPerWeek: 3,
        level: ProgramLevel.beginner,
        muscleGroups: const {},
        equipment: home,
      )),
      throwsArgumentError,
    );
  });
}
