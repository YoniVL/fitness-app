import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';
import 'seed_data.dart';

/// Opens and owns the local SQLite database. Single instance for the app.
///
/// - `onConfigure` enables foreign keys.
/// - `onCreate` builds the current schema and seeds reference data + programs.
/// - `onUpgrade` runs the numbered migrations in `migrations.dart`.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _fileName = 'fitnesstracker.db';
  static const schemaVersion = 7;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  /// Test hook: open at an explicit path (or `inMemoryDatabasePath`) and keep it
  /// as the singleton instance.
  Future<Database> openAt(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    _db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Absolute path of the SQLite file — for the backup export/import.
  Future<String> filePath() async =>
      p.join(await getDatabasesPath(), _fileName);

  Future<Database> _open() async {
    final path = await filePath();
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final stmt in _schema) {
      batch.execute(stmt);
    }
    await batch.commit(noResult: true);
    await seedDatabase(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      switch (v) {
        case 2:
          await migrateV1toV2(db);
        case 3:
          await migrateV2toV3(db);
        case 4:
          await migrateV3toV4(db);
        case 5:
          await migrateV4toV5(db);
        case 6:
          await migrateV5toV6(db);
        case 7:
          await migrateV6toV7(db);
      }
    }
  }

  static const List<String> _schema = [
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
      is_unilateral            INTEGER NOT NULL DEFAULT 0,
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
      equipment_profile  TEXT NOT NULL DEFAULT '',
      goal               TEXT
    )
    ''',
    '''
    CREATE TABLE program_days (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      program_id       INTEGER NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
      day_index        INTEGER NOT NULL,
      label            TEXT NOT NULL,
      row_session_type TEXT
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
      is_rest            INTEGER NOT NULL DEFAULT 0,
      drill_key          TEXT,
      zone               TEXT
    )
    ''',
    '''
    CREATE TABLE program_progress (
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
      program_day_id    INTEGER REFERENCES program_days(id),
      segments_json     TEXT,
      kind              TEXT,
      active_elapsed_ms INTEGER
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
    '''
    CREATE TABLE app_settings (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
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
}
