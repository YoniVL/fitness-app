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

  test('starts empty, logs sets, and persists them immediately', () async {
    await container.read(activeWorkoutProvider.future);
    await controller().startEmpty();
    await controller().addExercise(1);
    await controller().logSet(0, reps: 8, weight: 50);
    await controller().logSet(0, reps: 8, weight: 50);

    final state = container.read(activeWorkoutProvider).requireValue!;
    expect(state.blocks.single.sets.length, 2);
    expect(state.totalVolume, 800);

    // Written to the DB even before finishing.
    final repo = WorkoutSessionRepository(AppDatabase.instance);
    final live = await repo.setsForSession(state.session.id);
    expect(live.length, 2);
  });

  test('editing per-session targets does not touch the template row', () async {
    await container.read(activeWorkoutProvider.future);
    final programs = ProgramRepository(AppDatabase.instance);
    final ppl = await programs.templates();
    final pplStrength =
        ppl.firstWhere((p) => p.category == 'strength_ppl');
    final days = await programs.daysForProgram(pplStrength.id);
    final push = days.first;

    final before = await programs.exercisesForDay(push.id);
    final firstPrescription = before.first;

    await controller().startFromDay(push);
    controller().updateBlockTargets(0, targetSets: 99, targetReps: 99, restSeconds: 5);

    final after = await programs.exercisesForDay(push.id);
    expect(after.first.targetSets, firstPrescription.targetSets);
    expect(after.first.targetReps, firstPrescription.targetReps);
    expect(after.first.restSeconds, firstPrescription.restSeconds);

    final block = container.read(activeWorkoutProvider).requireValue!.blocks.first;
    expect(block.targetSets, 99);
    expect(block.restSeconds, 5);
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

  test('rehydrates an unfinished session on rebuild', () async {
    await container.read(activeWorkoutProvider.future);
    await controller().startEmpty();
    await controller().addExercise(2);
    await controller().logSet(0, reps: 6, weight: 70);
    final sessionId =
        container.read(activeWorkoutProvider).requireValue!.session.id;

    // Fresh container = fresh notifier; build() should recover the session.
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    final recovered = await container2.read(activeWorkoutProvider.future);
    expect(recovered, isNotNull);
    expect(recovered!.session.id, sessionId);
    expect(recovered.blocks.single.sets.single.reps, 6);
  });
}
