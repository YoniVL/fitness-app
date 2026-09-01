import 'package:sqflite/sqflite.dart';

import 'seed_data.dart';

/// v1 -> v2
///
/// The exercise catalogue, the programs and (in v1) the exercise ids all change
/// meaning, so v2 is a clean rebuild of every table except `app_settings`.
/// `onUpgrade` runs inside a transaction where `PRAGMA foreign_keys` cannot be
/// toggled, so tables are dropped leaf-first with foreign keys still on.
Future<void> migrateV1toV2(Database db) async {
  for (final table in const [
    'rowing_samples',
    'strength_sets',
    'rowing_sessions',
    'program_exercises',
    'program_row_segments',
    'workout_sessions',
    'program_days',
    'programs',
    'exercises',
    'muscle_groups',
  ]) {
    await db.execute('DROP TABLE IF EXISTS $table');
  }

  const ddl = [
    '''
    CREATE TABLE muscle_groups (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      name      TEXT NOT NULL,
      icon_key  TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE exercises (
      id                       INTEGER PRIMARY KEY AUTOINCREMENT,
      name                     TEXT NOT NULL,
      primary_muscle_group_id  INTEGER NOT NULL REFERENCES muscle_groups(id),
      secondary_muscle_groups  TEXT NOT NULL DEFAULT '',
      equipment                TEXT NOT NULL DEFAULT 'bodyweight',
      pattern                  TEXT,
      media_key                TEXT,
      is_custom                INTEGER NOT NULL DEFAULT 0,
      notes                    TEXT
    )
    ''',
    '''
    CREATE TABLE programs (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      name               TEXT NOT NULL,
      category           TEXT NOT NULL,
      discipline         TEXT NOT NULL,
      is_template        INTEGER NOT NULL DEFAULT 1,
      source_template_id INTEGER REFERENCES programs(id),
      level              TEXT,
      days_per_week      INTEGER,
      equipment_profile  TEXT NOT NULL DEFAULT ''
    )
    ''',
    '''
    CREATE TABLE program_days (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      program_id INTEGER NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
      day_index  INTEGER NOT NULL,
      label      TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE program_exercises (
      id                  INTEGER PRIMARY KEY AUTOINCREMENT,
      program_day_id      INTEGER NOT NULL REFERENCES program_days(id) ON DELETE CASCADE,
      exercise_id         INTEGER NOT NULL REFERENCES exercises(id),
      order_index         INTEGER NOT NULL,
      target_sets         INTEGER NOT NULL,
      target_reps         INTEGER NOT NULL,
      target_weight       REAL,
      rest_seconds        INTEGER NOT NULL DEFAULT 30,
      rest_after_exercise INTEGER
    )
    ''',
    '''
    CREATE TABLE program_row_segments (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      program_day_id     INTEGER NOT NULL REFERENCES program_days(id) ON DELETE CASCADE,
      order_index        INTEGER NOT NULL,
      duration_seconds   INTEGER NOT NULL,
      target_stroke_rate INTEGER,
      intensity_label    TEXT NOT NULL,
      is_rest            INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS program_progress (
      program_id        INTEGER PRIMARY KEY REFERENCES programs(id) ON DELETE CASCADE,
      current_day_index INTEGER NOT NULL DEFAULT 0,
      round             INTEGER NOT NULL DEFAULT 1,
      last_completed_at INTEGER
    )
    ''',
    '''
    CREATE TABLE workout_sessions (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      discipline     TEXT NOT NULL,
      program_day_id INTEGER REFERENCES program_days(id),
      started_at     INTEGER NOT NULL,
      ended_at       INTEGER,
      notes          TEXT
    )
    ''',
    '''
    CREATE TABLE strength_sets (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id   INTEGER NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
      exercise_id  INTEGER NOT NULL REFERENCES exercises(id),
      set_index    INTEGER NOT NULL,
      reps         INTEGER NOT NULL,
      weight       REAL NOT NULL,
      rest_seconds INTEGER,
      is_warmup    INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE rowing_sessions (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id        INTEGER NOT NULL UNIQUE REFERENCES workout_sessions(id) ON DELETE CASCADE,
      total_distance_m  REAL NOT NULL DEFAULT 0,
      total_energy_kcal REAL NOT NULL DEFAULT 0,
      avg_stroke_rate   REAL NOT NULL DEFAULT 0,
      avg_power         REAL NOT NULL DEFAULT 0,
      duration_seconds  INTEGER NOT NULL DEFAULT 0,
      program_day_id    INTEGER REFERENCES program_days(id)
    )
    ''',
    '''
    CREATE TABLE rowing_samples (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      rowing_session_id INTEGER NOT NULL REFERENCES rowing_sessions(id) ON DELETE CASCADE,
      t_offset_ms       INTEGER NOT NULL,
      stroke_rate       REAL,
      stroke_count      INTEGER,
      distance_m        REAL,
      pace_sec_500m     REAL,
      power_w           REAL,
      energy_kcal       REAL,
      heart_rate        INTEGER
    )
    ''',
    'CREATE INDEX idx_exercises_primary_mg ON exercises(primary_muscle_group_id)',
    'CREATE INDEX idx_program_days_program ON program_days(program_id)',
    'CREATE INDEX idx_program_exercises_day ON program_exercises(program_day_id)',
    'CREATE INDEX idx_program_row_segments_day ON program_row_segments(program_day_id)',
    'CREATE INDEX idx_sets_session ON strength_sets(session_id)',
    'CREATE INDEX idx_sets_exercise ON strength_sets(exercise_id)',
    'CREATE INDEX idx_sessions_started ON workout_sessions(started_at)',
    'CREATE INDEX idx_rowing_samples_session ON rowing_samples(rowing_session_id)',
  ];
  final batch = db.batch();
  for (final stmt in ddl) {
    batch.execute(stmt);
  }
  await batch.commit(noResult: true);

  await db.delete('app_settings',
      where: 'key IN (?, ?)',
      whereArgs: ['weekly_schedule', 'default_rest_seconds']);

  await seedDatabase(db);
}
