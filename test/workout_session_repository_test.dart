import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:fitnesstracker/data/repositories/workout_session_repository.dart';
import 'package:fitnesstracker/domain/models/program.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late WorkoutSessionRepository repo;

  setUp(() async {
    await initTestDatabase();
    repo = WorkoutSessionRepository(AppDatabase.instance);
  });
  tearDown(closeTestDatabase);

  test('session -> sets -> reps + set counts', () async {
    final session = await repo.startSession(discipline: Discipline.strength);

    await repo.addSet(sessionId: session.id, exerciseId: 1, reps: 10);
    await repo.addSet(sessionId: session.id, exerciseId: 1, reps: 8);
    await repo.addSet(sessionId: session.id, exerciseId: 1, reps: 8);
    await repo.addSet(
        sessionId: session.id, exerciseId: 1, reps: 5, isWarmup: true);

    await repo.finishSession(session.id);

    final detail = await repo.sessionDetail(session.id);
    expect(detail, isNotNull);
    expect(detail!.sets.length, 4);
    expect(detail.workingSetCount, 3);
    expect(detail.totalReps, 26); // warm-up excluded
    expect(detail.exerciseCount, 1);
    expect(detail.sets.map((s) => s.setIndex).toList(), [1, 2, 3, 4]);
    // Exercise 1 (Bankdrukken) hits Borst primary.
    expect(detail.muscleGroupSetCount.values.reduce((a, b) => a + b),
        greaterThan(0));
  });

  test('recentSessions aggregates set/exercise counts', () async {
    final s = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 5);
    await repo.addSet(sessionId: s.id, exerciseId: 2, reps: 5);
    await repo.finishSession(s.id);

    final recent = await repo.recentSessions();
    expect(recent, hasLength(1));
    expect(recent.first.setCount, 2);
    expect(recent.first.exerciseCount, 2);
    expect(recent.first.muscleGroups, isNotEmpty);
  });

  test('lastPerformance returns the previous finished session for an exercise',
      () async {
    final older = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: older.id, exerciseId: 7, reps: 5);
    await repo.addSet(sessionId: older.id, exerciseId: 7, reps: 5);
    await repo.finishSession(older.id);

    final current = await repo.startSession(discipline: Discipline.strength);
    final last = await repo.lastPerformance(7);
    expect(last.map((s) => s.reps), everyElement(5));
    expect(last.length, 2);
    expect(await repo.lastPerformance(99), isEmpty);
    await repo.deleteSession(current.id);
  });

  test('deleteSession cascades to its sets', () async {
    final s = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 5);
    await repo.deleteSession(s.id);

    final db = await AppDatabase.instance.database;
    final remaining = await db
        .query('strength_sets', where: 'session_id = ?', whereArgs: [s.id]);
    expect(remaining, isEmpty);
  });

  test('weeklySets counts finished working sets, gap-filled to this week',
      () async {
    final s = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 10);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 10);
    await repo.finishSession(s.id);

    final points = await repo.weeklySets(weeks: 4);
    expect(points, hasLength(4)); // gap-filled window
    expect(points.every((p) => p.weekStart.weekday == DateTime.monday), isTrue);
    expect(points.last.value, 2); // current week has the 2 sets
  });

  test('muscleGroupLoad and exerciseHistory aggregate finished sessions',
      () async {
    final s1 = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s1.id, exerciseId: 1, reps: 8);
    await repo.addSet(sessionId: s1.id, exerciseId: 1, reps: 6);
    await repo.finishSession(s1.id);

    final load = await repo.muscleGroupLoad(
        DateTime.now().subtract(const Duration(days: 30)));
    expect(load, isNotEmpty);
    expect(load.first.sets, greaterThan(0));

    final trained = await repo.trainedStrengthExercises();
    expect(trained.map((t) => t.id), contains(1));

    final history = await repo.exerciseHistory(1);
    expect(history, hasLength(1));
    expect(history.single.bestReps, 8);
    expect(history.single.totalSets, 2);
  });

  test('personalRecords: best working set per exercise', () async {
    final s1 = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s1.id, exerciseId: 1, reps: 8);
    await repo.addSet(sessionId: s1.id, exerciseId: 1, reps: 12); // PR
    await repo.addSet(sessionId: s1.id, exerciseId: 2, reps: 20, isWarmup: true);
    await repo.addSet(sessionId: s1.id, exerciseId: 2, reps: 9);
    await repo.finishSession(s1.id);

    final prs = await repo.personalRecords();
    expect(prs.first.reps, 12); // sorted desc
    expect(prs.map((r) => r.reps), contains(9));
    expect(prs.map((r) => r.reps), isNot(contains(20))); // warm-up ignored
  });

  test('trainingWeekStreak counts consecutive trained weeks', () async {
    expect(await repo.trainingWeekStreak(), 0);

    final s1 = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s1.id, exerciseId: 1, reps: 8);
    await repo.finishSession(s1.id);

    expect(await repo.trainingWeekStreak(), 1);
  });
}
