import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'helpers.dart';

void main() {
  setUp(initTestDatabase);
  tearDown(closeTestDatabase);

  test('onCreate builds every table', () async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );
    final tables = rows.map((r) => r['name'] as String).toSet();
    expect(
      tables,
      containsAll(<String>[
        'muscle_groups',
        'exercises',
        'programs',
        'program_days',
        'program_exercises',
        'program_row_segments',
        'workout_sessions',
        'strength_sets',
        'rowing_sessions',
        'rowing_samples',
        'app_settings',
      ]),
    );
  });

  test('seed data is present and coherent', () async {
    final db = await AppDatabase.instance.database;

    Future<int> count(String table) async =>
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;

    expect(await count('muscle_groups'), 9);
    expect(await count('exercises'), greaterThanOrEqualTo(30));
    expect(await count('app_settings'), greaterThanOrEqualTo(3));

    // 2 strength templates + 3 rowing templates.
    expect(await count('programs'), 5);
    final strength = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM programs WHERE discipline = 'strength'",
    ));
    expect(strength, 2);

    // Push/Pull/Legs has three days, each with prescribed exercises.
    final ppl = await db.query('programs',
        where: 'category = ?', whereArgs: ['strength_ppl'], limit: 1);
    final days = await db.query('program_days',
        where: 'program_id = ?', whereArgs: [ppl.first['id']]);
    expect(days.length, 3);
    for (final day in days) {
      final exCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM program_exercises WHERE program_day_id = ?',
        [day['id']],
      ));
      expect(exCount, greaterThan(0));
    }

    // Every program_exercise points at a real exercise.
    final orphans = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM program_exercises pe '
      'LEFT JOIN exercises e ON e.id = pe.exercise_id WHERE e.id IS NULL',
    ));
    expect(orphans, 0);

    // Interval rowing template has work + rest segments.
    final interval = await db.query('programs',
        where: 'category = ?', whereArgs: ['row_interval'], limit: 1);
    final intervalDay = await db.query('program_days',
        where: 'program_id = ?', whereArgs: [interval.first['id']], limit: 1);
    final segs = await db.query('program_row_segments',
        where: 'program_day_id = ?', whereArgs: [intervalDay.first['id']]);
    expect(segs.length, greaterThan(1));
    expect(segs.any((s) => (s['is_rest'] as int) == 1), isTrue);
  });

  test('foreign keys are enforced', () async {
    final db = await AppDatabase.instance.database;
    expect(
      () => db.insert('strength_sets', {
        'session_id': 999999,
        'exercise_id': 1,
        'set_index': 1,
        'reps': 5,
        'weight': 20.0,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      }),
      throwsA(isA<Exception>()),
    );
  });
}
