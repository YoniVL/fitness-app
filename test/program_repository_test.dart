import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:fitnesstracker/data/repositories/program_repository.dart';
import 'package:fitnesstracker/data/repositories/settings_repository.dart';
import 'package:fitnesstracker/data/repositories/workout_session_repository.dart';
import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/rowing_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late ProgramRepository repo;
  late WorkoutSessionRepository sessions;

  setUp(() async {
    await initTestDatabase();
    repo = ProgramRepository(AppDatabase.instance, SettingsRepository(AppDatabase.instance));
    sessions = WorkoutSessionRepository(AppDatabase.instance);
  });
  tearDown(closeTestDatabase);

  test('createProgram persists a rowing draft with segments', () async {
    final id = await repo.createProgram(NewProgramDraft(
      name: 'Mijn roeiplan',
      category: ProgramCategory.rowGenerated,
      discipline: Discipline.rowing,
      equipmentProfile: const [],
      daysPerWeek: 2,
      rowingGoal: RowingGoal.uithouding,
      days: [
        NewProgramDayDraft(label: 'Wk 1 · Duurloop', segments: [
          NewRowSegmentDraft(
              durationSeconds: 180, targetStrokeRate: 18, intensityLabel: 'Warming-up'),
          NewRowSegmentDraft(
              durationSeconds: 1200, targetStrokeRate: 21, intensityLabel: 'Duur'),
        ]),
        NewProgramDayDraft(label: 'Wk 1 · Techniek', segments: [
          NewRowSegmentDraft(
              durationSeconds: 120,
              targetStrokeRate: 18,
              intensityLabel: 'Techniek — Alleen benen',
              drillKey: 'benen'),
        ]),
      ],
    ));

    final program = await repo.programById(id);
    expect(program!.discipline, Discipline.rowing);
    expect(program.goal, RowingGoal.uithouding);
    expect(program.isTemplate, isFalse);

    final days = await repo.daysForProgram(id);
    expect(days, hasLength(2));
    final segs = await repo.rowSegmentsForDay(days.first.id);
    expect(segs, hasLength(2));
    expect(segs.last.intensityLabel, 'Duur');
    final drillSegs = await repo.rowSegmentsForDay(days[1].id);
    expect(drillSegs.single.drillKey, 'benen');
  });

  test('updateProgramContent replaces days/exercises in place for an own program',
      () async {
    final ownId = await repo.createProgram(NewProgramDraft(
      name: 'Mijn testschema',
      category: ProgramCategory.strengthGenerated,
      equipmentProfile: const ['dumbbell'],
      days: [
        NewProgramDayDraft(label: 'Dag 1', exercises: [
          NewProgramExerciseDraft(
              exerciseId: 1, sets: 3, reps: 10, restBetweenSets: 30, restAfterExercise: 60),
        ]),
      ],
    ));

    final beforeDays = await repo.daysForProgram(ownId);
    final oldDayId = beforeDays.single.id;

    // A session logged against the old day.
    final session =
        await sessions.startSession(discipline: Discipline.strength, programDayId: oldDayId);

    await repo.updateProgramContent(
      ownId,
      name: 'Mijn testschema v2',
      days: [
        NewProgramDayDraft(label: 'Dag A', exercises: [
          NewProgramExerciseDraft(
              exerciseId: 2, sets: 4, reps: 8, restBetweenSets: 45, restAfterExercise: 90),
        ]),
        NewProgramDayDraft(label: 'Dag B', exercises: [
          NewProgramExerciseDraft(
              exerciseId: 3, sets: 3, reps: 12, restBetweenSets: 30, restAfterExercise: 60),
        ]),
      ],
    );

    // Same program id (in-place), new content.
    final program = await repo.programById(ownId);
    expect(program!.name, 'Mijn testschema v2');
    final afterDays = await repo.daysForProgram(ownId);
    expect(afterDays.length, 2);
    expect(afterDays.map((d) => d.label), ['Dag A', 'Dag B']);
    final dayAExercises = await repo.exercisesForDay(afterDays.first.id);
    expect(dayAExercises.single.exerciseId, 2);
    expect(dayAExercises.single.targetSets, 4);

    // Old day is gone; the session that referenced it keeps its row but the
    // link is cleared instead of throwing a FK violation.
    final db = await AppDatabase.instance.database;
    final oldDayRows =
        await db.query('program_days', where: 'id = ?', whereArgs: [oldDayId]);
    expect(oldDayRows, isEmpty);
    final refreshedSession = await sessions.setsForSession(session.id);
    expect(refreshedSession, isEmpty); // no sets logged, just checking no crash
    final sessionRow =
        await db.query('workout_sessions', where: 'id = ?', whereArgs: [session.id]);
    expect(sessionRow.single['program_day_id'], isNull);
  });

  test('editing a template forks a new owned program, leaving the template intact',
      () async {
    final templates = await repo.allStrengthPrograms();
    final template =
        templates.firstWhere((p) => p.category == ProgramCategory.strengthFullbody && p.isTemplate);
    final templateDaysBefore = await repo.daysForProgram(template.id);
    final firstDayExercisesBefore =
        await repo.exercisesForDay(templateDaysBefore.first.id);

    final forkedId = await repo.createProgram(NewProgramDraft(
      name: '${template.name} (aangepast)',
      category: ProgramCategory.strengthGenerated,
      equipmentProfile: template.equipmentProfile,
      level: template.level,
      days: [
        NewProgramDayDraft(label: 'Aangepaste dag', exercises: [
          NewProgramExerciseDraft(
              exerciseId: firstDayExercisesBefore.first.exerciseId,
              sets: 99,
              reps: 99,
              restBetweenSets: 5,
              restAfterExercise: 5),
        ]),
      ],
    ));

    expect(forkedId, isNot(template.id));
    final forked = await repo.programById(forkedId);
    expect(forked!.isTemplate, isFalse);

    // Template untouched.
    final templateDaysAfter = await repo.daysForProgram(template.id);
    expect(templateDaysAfter.length, templateDaysBefore.length);
    final firstDayExercisesAfter =
        await repo.exercisesForDay(templateDaysAfter.first.id);
    expect(firstDayExercisesAfter.first.targetSets,
        firstDayExercisesBefore.first.targetSets);
  });
}
