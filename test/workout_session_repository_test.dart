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

  test('weeklyReps buckets working sets by ISO week', () async {
    final s = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 10);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 10);
    await repo.finishSession(s.id);

    final points = await repo.weeklyReps();
    expect(points, hasLength(1));
    expect(points.single.reps, 20);
    expect(points.single.weekStart.weekday, DateTime.monday);
  });
}
