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
