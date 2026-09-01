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

  test('session -> 3 sets -> total volume', () async {
    final session = await repo.startSession(discipline: Discipline.strength);

    await repo.addSet(sessionId: session.id, exerciseId: 1, reps: 10, weight: 40);
    await repo.addSet(sessionId: session.id, exerciseId: 1, reps: 8, weight: 40);
    await repo.addSet(sessionId: session.id, exerciseId: 1, reps: 8, weight: 45);
    // Warm-up set must not count toward volume.
    await repo.addSet(
        sessionId: session.id, exerciseId: 1, reps: 5, weight: 20, isWarmup: true);

    await repo.finishSession(session.id);

    final detail = await repo.sessionDetail(session.id);
    expect(detail, isNotNull);
    expect(detail!.sets.length, 4);
    // 10*40 + 8*40 + 8*45 = 400 + 320 + 360 = 1080
    expect(detail.totalVolume, 1080);
    expect(detail.exerciseCount, 1);

    // set_index is assigned 1..n per exercise.
    expect(detail.sets.map((s) => s.setIndex).toList(), [1, 2, 3, 4]);
  });

  test('recentSessions aggregates set/exercise counts and volume', () async {
    final s = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 5, weight: 100);
    await repo.addSet(sessionId: s.id, exerciseId: 2, reps: 5, weight: 60);
    await repo.finishSession(s.id);

    final recent = await repo.recentSessions();
    expect(recent, hasLength(1));
    expect(recent.first.setCount, 2);
    expect(recent.first.exerciseCount, 2);
    expect(recent.first.totalVolume, 5 * 100 + 5 * 60);
  });

  test('lastPerformance returns the previous finished session for that exercise',
      () async {
    final older = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: older.id, exerciseId: 7, reps: 5, weight: 80);
    await repo.addSet(sessionId: older.id, exerciseId: 7, reps: 5, weight: 80);
    await repo.finishSession(older.id);

    final current = await repo.startSession(discipline: Discipline.strength);
    final last = await repo.lastPerformance(7);
    expect(last.map((s) => s.weight), everyElement(80));
    expect(last.length, 2);

    // No history for an exercise never trained.
    expect(await repo.lastPerformance(99), isEmpty);
    await repo.deleteSession(current.id);
  });

  test('deleteSession cascades to its sets', () async {
    final s = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 5, weight: 50);
    await repo.deleteSession(s.id);

    final db = await AppDatabase.instance.database;
    final remaining = await db.query('strength_sets', where: 'session_id = ?', whereArgs: [s.id]);
    expect(remaining, isEmpty);
  });

  test('weeklyVolume buckets working sets by ISO week', () async {
    final s = await repo.startSession(discipline: Discipline.strength);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 10, weight: 20);
    await repo.addSet(sessionId: s.id, exerciseId: 1, reps: 10, weight: 20);
    await repo.finishSession(s.id);

    final points = await repo.weeklyVolume();
    expect(points, hasLength(1));
    expect(points.single.volume, 400);
    expect(points.single.weekStart.weekday, DateTime.monday);
  });
}
