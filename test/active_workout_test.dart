import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:fitnesstracker/data/repositories/program_repository.dart';
import 'package:fitnesstracker/data/repositories/workout_session_repository.dart';
import 'package:fitnesstracker/features/strength/state/active_workout_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    await initTestDatabase();
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    await closeTestDatabase();
  });

  ActiveWorkoutController controller() =>
      container.read(activeWorkoutProvider.notifier);
  ProgramRepository programs() => container.read(programRepositoryProvider);

  test('starts empty, logs sets, and persists them immediately', () async {
    await container.read(activeWorkoutProvider.future);
    await controller().startEmpty();
    await controller().addExercise(1);
    await controller().logSet(0, reps: 8);
    await controller().logSet(0, reps: 8);

    final state = container.read(activeWorkoutProvider).requireValue!;
    expect(state.blocks.single.sets.length, 2);
    expect(state.totalSets, 2);

    final repo = WorkoutSessionRepository(AppDatabase.instance);
    final live = await repo.setsForSession(state.session.id);
    expect(live.length, 2);
  });

  test('editing per-session targets does not touch the program row', () async {
    await container.read(activeWorkoutProvider.future);
    final all = await programs().allStrengthPrograms();
    final ppl = all.firstWhere((p) => p.category == 'strength_ppl');
    final days = await programs().daysForProgram(ppl.id);
    final push = days.first;

    final before = await programs().exercisesForDay(push.id);
    final firstPrescription = before.first;

    await controller().startFromDay(push);
    controller().updateBlockTargets(0,
        targetSets: 99, targetReps: 99, restBetweenSets: 5);

    final after = await programs().exercisesForDay(push.id);
    expect(after.first.targetSets, firstPrescription.targetSets);
    expect(after.first.targetReps, firstPrescription.targetReps);
    expect(after.first.restBetweenSets, firstPrescription.restBetweenSets);

    final block =
        container.read(activeWorkoutProvider).requireValue!.blocks.first;
    expect(block.targetSets, 99);
    expect(block.restBetweenSets, 5);
  });

  test('finishing with no sets discards the session row', () async {
    await container.read(activeWorkoutProvider.future);
    await controller().startEmpty();
    final id = container.read(activeWorkoutProvider).requireValue!.session.id;

    final result = await controller().finish();
    expect(result, isNull);

    final db = await AppDatabase.instance.database;
    final rows =
        await db.query('workout_sessions', where: 'id = ?', whereArgs: [id]);
    expect(rows, isEmpty);
  });

  test('advances the active-program cursor when its current day finishes',
      () async {
    await container.read(activeWorkoutProvider.future);
    final home = (await programs().allStrengthPrograms())
        .firstWhere((p) => p.name == 'Full-body Medium');
    await programs().setActiveProgram(home.id);

    final active1 = await programs().activeProgram();
    expect(active1!.currentDayIndex, 0);

    await controller().startFromDay(active1.currentDay);
    await controller().logSet(0, reps: 10);
    await controller().finish();

    final active2 = await programs().activeProgram();
    expect(active2!.currentDayIndex, 1);
  });

  test('auto-progression bumps targets on later rounds of the active program',
      () async {
    await container.read(activeWorkoutProvider.future);
    final prog = (await programs().allStrengthPrograms())
        .firstWhere((p) => p.name == 'Full-body Medium');
    await programs().setActiveProgram(prog.id);

    final active = await programs().activeProgram();
    final day = active!.currentDay;
    final baseReps = (await programs().exercisesForDay(day.id)).first.targetReps;

    // Round 1 → exactly as written.
    await controller().startFromDay(day);
    expect(container.read(activeWorkoutProvider).requireValue!.blocks.first
        .targetReps, baseReps);
    await controller().discard();

    // Jump the cursor a full lap so round becomes 2.
    for (var i = 0; i < active.dayCount; i++) {
      await programs().advanceIfCurrentDay(
          (await programs().activeProgram())!.currentDay.id);
    }
    expect((await programs().activeProgram())!.round, 2);

    await controller().startFromDay(day);
    final block =
        container.read(activeWorkoutProvider).requireValue!.blocks.first;
    expect(block.targetReps, baseReps + 1);
    expect(block.baseTargetReps, baseReps);
    expect(block.isProgressed, isTrue);
  });

  test('rehydrates an unfinished session on rebuild', () async {
    await container.read(activeWorkoutProvider.future);
    await controller().startEmpty();
    await controller().addExercise(2);
    await controller().logSet(0, reps: 6);
    final sessionId =
        container.read(activeWorkoutProvider).requireValue!.session.id;

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    final recovered = await container2.read(activeWorkoutProvider.future);
    expect(recovered, isNotNull);
    expect(recovered!.session.id, sessionId);
    expect(recovered.blocks.single.sets.single.reps, 6);
  });
}
