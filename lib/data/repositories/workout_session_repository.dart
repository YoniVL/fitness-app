import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/program.dart';
import '../../domain/models/strength_set.dart';
import '../../domain/models/workout_session.dart';
import '../database/app_database.dart';

/// A finished session plus the numbers the log list needs, in one query pass.
class SessionSummary {
  const SessionSummary({
    required this.session,
    required this.setCount,
    required this.exerciseCount,
    this.muscleGroups = const [],
  });

  final WorkoutSession session;
  final int setCount;
  final int exerciseCount;
  final List<String> muscleGroups;
}

/// One (weekStart, value) point for a weekly progress chart.
class WeeklyPoint {
  const WeeklyPoint(this.weekStart, this.value);
  final DateTime weekStart;
  final int value;
}

/// A muscle group with its recent working-set count.
class MuscleGroupLoad {
  const MuscleGroupLoad(this.name, this.sets);
  final String name;
  final int sets;
}

/// A named exercise that appears in the finished-session history.
class TrainedExercise {
  const TrainedExercise(this.id, this.name);
  final int id;
  final String name;
}

/// One finished-session datapoint for a single exercise.
class ExerciseHistoryPoint {
  const ExerciseHistoryPoint(this.date, this.bestReps, this.totalSets);
  final DateTime date;
  final int bestReps;
  final int totalSets;
}

/// Best-ever working set for an exercise (no weight — reps are the record).
class PersonalRecord {
  const PersonalRecord(this.name, this.reps, this.date);
  final String name;
  final int reps;
  final DateTime date;
}

class WorkoutSessionRepository {
  WorkoutSessionRepository(this._appDb);

  final AppDatabase _appDb;

  // --- Session lifecycle -------------------------------------------------

  Future<WorkoutSession> startSession({
    required Discipline discipline,
    int? programDayId,
  }) async {
    final db = await _appDb.database;
    final now = DateTime.now();
    final id = await db.insert('workout_sessions', {
      'discipline': discipline.name,
      'program_day_id': programDayId,
      'started_at': now.millisecondsSinceEpoch,
      'ended_at': null,
    });
    return WorkoutSession(
      id: id,
      discipline: discipline,
      programDayId: programDayId,
      startedAt: now,
    );
  }

  Future<void> finishSession(int sessionId, {String? notes}) async {
    final db = await _appDb.database;
    await db.update(
      'workout_sessions',
      {'ended_at': DateTime.now().millisecondsSinceEpoch, 'notes': ?notes},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> deleteSession(int sessionId) async {
    final db = await _appDb.database;
    await db.delete('workout_sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  /// Updates only the note of a session (leaves `ended_at` untouched).
  Future<void> updateNotes(int sessionId, String? notes) async {
    final db = await _appDb.database;
    await db.update('workout_sessions', {'notes': notes},
        where: 'id = ?', whereArgs: [sessionId]);
  }

  /// The most recent session that was never finished (crash / app kill).
  Future<WorkoutSession?> activeSession() async {
    final db = await _appDb.database;
    final rows = await db.query('workout_sessions',
        where: 'ended_at IS NULL', orderBy: 'started_at DESC', limit: 1);
    return rows.isEmpty ? null : WorkoutSession.fromMap(rows.first);
  }

  // --- Sets -----------------------------------------------------------

  /// Appends a set, auto-assigning its 1-based [StrengthSet.setIndex] within the
  /// exercise for this session. Returns the row id.
  Future<int> addSet({
    required int sessionId,
    required int exerciseId,
    required int reps,
    bool isWarmup = false,
  }) async {
    final db = await _appDb.database;
    final existing = firstIntOr(
      await db.rawQuery(
        'SELECT COUNT(*) c FROM strength_sets WHERE session_id = ? AND exercise_id = ?',
        [sessionId, exerciseId],
      ),
      'c',
      0,
    );
    return db.insert('strength_sets', {
      'session_id': sessionId,
      'exercise_id': exerciseId,
      'set_index': existing + 1,
      'reps': reps,
      'weight': 0,
      'is_warmup': isWarmup ? 1 : 0,
      'completed_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> setRestForSet(int setId, int restSeconds) async {
    final db = await _appDb.database;
    await db.update('strength_sets', {'rest_seconds': restSeconds},
        where: 'id = ?', whereArgs: [setId]);
  }

  Future<void> deleteSet(int setId) async {
    final db = await _appDb.database;
    await db.delete('strength_sets', where: 'id = ?', whereArgs: [setId]);
  }

  Future<List<StrengthSet>> setsForSession(int sessionId) async {
    final db = await _appDb.database;
    final rows = await db.query('strength_sets',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'completed_at, id');
    return rows.map(StrengthSet.fromMap).toList();
  }

  /// Sets of the last finished session that included [exerciseId] — used to
  /// pre-fill reps when the exercise is added again.
  Future<List<StrengthSet>> lastPerformance(int exerciseId) async {
    final db = await _appDb.database;
    final lastSession = await db.rawQuery(
      '''
      SELECT s.id FROM workout_sessions s
      JOIN strength_sets ss ON ss.session_id = s.id
      WHERE ss.exercise_id = ? AND s.ended_at IS NOT NULL
      ORDER BY s.started_at DESC LIMIT 1
      ''',
      [exerciseId],
    );
    if (lastSession.isEmpty) return [];
    final sessionId = lastSession.first['id'] as int;
    final rows = await db.query('strength_sets',
        where: 'session_id = ? AND exercise_id = ?',
        whereArgs: [sessionId, exerciseId],
        orderBy: 'set_index');
    return rows.map(StrengthSet.fromMap).toList();
  }

  // --- Log / reporting ----------------------------------------------

  Future<List<SessionSummary>> recentSessions({int limit = 50}) async {
    final db = await _appDb.database;
    final rows = await db.rawQuery(
      '''
      SELECT ws.*,
             COUNT(ss.id) AS set_count,
             COUNT(DISTINCT ss.exercise_id) AS exercise_count
      FROM workout_sessions ws
      LEFT JOIN strength_sets ss ON ss.session_id = ws.id
      GROUP BY ws.id
      ORDER BY ws.started_at DESC
      LIMIT ?
      ''',
      [limit],
    );

    // Primary muscle groups per session (small extra query, list is short).
    final muscleRows = await db.rawQuery(
      '''
      SELECT ss.session_id AS session_id, mg.name AS name
      FROM strength_sets ss
      JOIN exercises e ON e.id = ss.exercise_id
      JOIN muscle_groups mg ON mg.id = e.primary_muscle_group_id
      GROUP BY ss.session_id, mg.name
      ''',
    );
    final musclesBySession = <int, List<String>>{};
    for (final r in muscleRows) {
      musclesBySession
          .putIfAbsent(r['session_id'] as int, () => [])
          .add(r['name'] as String);
    }

    return rows.map((r) {
      final session = WorkoutSession.fromMap(r);
      return SessionSummary(
        session: session,
        setCount: (r['set_count'] as int?) ?? 0,
        exerciseCount: (r['exercise_count'] as int?) ?? 0,
        muscleGroups: musclesBySession[session.id] ?? const [],
      );
    }).toList();
  }

  Future<WorkoutSessionDetail?> sessionDetail(int sessionId) async {
    final db = await _appDb.database;
    final rows = await db.query('workout_sessions',
        where: 'id = ?', whereArgs: [sessionId], limit: 1);
    if (rows.isEmpty) return null;
    final sets = await setsForSession(sessionId);

    // Working-set count per muscle group (primary counts full, secondary too).
    final mg = <int, int>{};
    final ids = sets.where((s) => !s.isWarmup).map((s) => s.exerciseId).toSet();
    if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      final exRows = await db.query('exercises',
          columns: ['id', 'primary_muscle_group_id', 'secondary_muscle_groups'],
          where: 'id IN ($placeholders)',
          whereArgs: ids.toList());
      final primary = <int, int>{};
      final secondary = <int, List<int>>{};
      for (final e in exRows) {
        primary[e['id'] as int] = e['primary_muscle_group_id'] as int;
        secondary[e['id'] as int] = (e['secondary_muscle_groups'] as String)
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
      }
      for (final s in sets.where((s) => !s.isWarmup)) {
        final p = primary[s.exerciseId];
        if (p != null) mg.update(p, (v) => v + 1, ifAbsent: () => 1);
        for (final sec in secondary[s.exerciseId] ?? const <int>[]) {
          mg.update(sec, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }

    return WorkoutSessionDetail(
      session: WorkoutSession.fromMap(rows.first),
      sets: sets,
      muscleGroupSetCount: mg,
    );
  }

  /// Working sets per ISO week (Monday start), oldest first, most recent [weeks].
  Future<List<WeeklyPoint>> weeklySets({int weeks = 10}) async {
    final db = await _appDb.database;
    final rows = await db.rawQuery(
      '''
      SELECT ws.started_at AS started_at
      FROM strength_sets ss
      JOIN workout_sessions ws ON ws.id = ss.session_id
      WHERE ss.is_warmup = 0 AND ws.discipline = 'strength'
        AND ws.ended_at IS NOT NULL
      ''',
    );
    final byWeek = <DateTime, int>{};
    for (final r in rows) {
      final date = DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int);
      final monday = DateTime(date.year, date.month, date.day)
          .subtract(Duration(days: date.weekday - 1));
      byWeek.update(monday, (v) => v + 1, ifAbsent: () => 1);
    }
    // Fill gaps so the trend line has no holes.
    if (byWeek.isEmpty) return const [];
    final now = DateTime.now();
    final thisMonday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final points = <WeeklyPoint>[];
    for (var i = weeks - 1; i >= 0; i--) {
      final wk = thisMonday.subtract(Duration(days: 7 * i));
      points.add(WeeklyPoint(wk, byWeek[wk] ?? 0));
    }
    return points;
  }

  /// Working-set count per muscle group (primary + secondary) since [since].
  Future<List<MuscleGroupLoad>> muscleGroupLoad(DateTime since) async {
    final db = await _appDb.database;
    final rows = await db.rawQuery(
      '''
      SELECT ss.exercise_id AS exercise_id
      FROM strength_sets ss
      JOIN workout_sessions ws ON ws.id = ss.session_id
      WHERE ss.is_warmup = 0 AND ws.discipline = 'strength'
        AND ws.ended_at IS NOT NULL AND ws.started_at >= ?
      ''',
      [since.millisecondsSinceEpoch],
    );
    if (rows.isEmpty) return const [];

    final exIds = rows.map((r) => r['exercise_id'] as int).toSet().toList();
    final placeholders = List.filled(exIds.length, '?').join(',');
    final exRows = await db.query('exercises',
        columns: ['id', 'primary_muscle_group_id', 'secondary_muscle_groups'],
        where: 'id IN ($placeholders)',
        whereArgs: exIds);
    final names = {
      for (final g in await db.query('muscle_groups'))
        g['id'] as int: g['name'] as String
    };
    final primary = <int, int>{};
    final secondary = <int, List<int>>{};
    for (final e in exRows) {
      primary[e['id'] as int] = e['primary_muscle_group_id'] as int;
      secondary[e['id'] as int] = (e['secondary_muscle_groups'] as String)
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
    }
    final counts = <int, int>{};
    for (final r in rows) {
      final id = r['exercise_id'] as int;
      final p = primary[id];
      if (p != null) counts.update(p, (v) => v + 1, ifAbsent: () => 1);
      for (final s in secondary[id] ?? const <int>[]) {
        counts.update(s, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final out = counts.entries
        .map((e) => MuscleGroupLoad(names[e.key] ?? '?', e.value))
        .toList()
      ..sort((a, b) => b.sets.compareTo(a.sets));
    return out;
  }

  /// Exercises that appear in finished strength sessions, for the picker.
  Future<List<TrainedExercise>> trainedStrengthExercises() async {
    final db = await _appDb.database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT e.id AS id, e.name AS name
      FROM strength_sets ss
      JOIN workout_sessions ws ON ws.id = ss.session_id
      JOIN exercises e ON e.id = ss.exercise_id
      WHERE ws.discipline = 'strength' AND ws.ended_at IS NOT NULL
      ORDER BY e.name COLLATE NOCASE
      ''',
    );
    return rows
        .map((r) => TrainedExercise(r['id'] as int, r['name'] as String))
        .toList();
  }

  /// Per finished session that included [exerciseId]: best (max reps) working
  /// set and the number of working sets. Oldest first.
  Future<List<ExerciseHistoryPoint>> exerciseHistory(int exerciseId) async {
    final db = await _appDb.database;
    final rows = await db.rawQuery(
      '''
      SELECT ws.started_at AS started_at,
             MAX(ss.reps) AS best_reps,
             COUNT(ss.id) AS total_sets
      FROM strength_sets ss
      JOIN workout_sessions ws ON ws.id = ss.session_id
      WHERE ss.exercise_id = ? AND ss.is_warmup = 0
        AND ws.discipline = 'strength' AND ws.ended_at IS NOT NULL
      GROUP BY ws.id
      ORDER BY ws.started_at
      ''',
      [exerciseId],
    );
    return rows
        .map((r) => ExerciseHistoryPoint(
              DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
              (r['best_reps'] as int?) ?? 0,
              (r['total_sets'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Best working set (max reps) per exercise across all finished sessions, with
  /// the date it was first hit. Most reps first.
  Future<List<PersonalRecord>> personalRecords() async {
    final db = await _appDb.database;
    final rows = await db.rawQuery(
      '''
      SELECT e.name AS name, best.reps AS reps, MIN(ws.started_at) AS date
      FROM (
        SELECT ss.exercise_id AS eid, MAX(ss.reps) AS reps
        FROM strength_sets ss
        JOIN workout_sessions ws ON ws.id = ss.session_id
        WHERE ss.is_warmup = 0 AND ws.ended_at IS NOT NULL
        GROUP BY ss.exercise_id
      ) best
      JOIN strength_sets ss ON ss.exercise_id = best.eid AND ss.reps = best.reps
                            AND ss.is_warmup = 0
      JOIN workout_sessions ws ON ws.id = ss.session_id AND ws.ended_at IS NOT NULL
      JOIN exercises e ON e.id = best.eid
      GROUP BY best.eid
      ORDER BY best.reps DESC, e.name COLLATE NOCASE
      ''',
    );
    return rows
        .map((r) => PersonalRecord(
              r['name'] as String,
              (r['reps'] as int?) ?? 0,
              DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
            ))
        .toList();
  }

  /// Number of consecutive weeks (Monday start), ending at the current or last
  /// week, with at least one finished strength session.
  Future<int> trainingWeekStreak() async {
    final db = await _appDb.database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT ws.started_at AS started_at
      FROM workout_sessions ws
      JOIN strength_sets ss ON ss.session_id = ws.id
      WHERE ws.discipline = 'strength' AND ws.ended_at IS NOT NULL
      ''',
    );
    if (rows.isEmpty) return 0;
    DateTime weekOf(DateTime d) => DateTime(d.year, d.month, d.day)
        .subtract(Duration(days: d.weekday - 1));
    final weeks = <DateTime>{
      for (final r in rows)
        weekOf(DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int)),
    };
    final now = DateTime.now();
    var cursor = weekOf(now);
    // Allow the streak to "hang on" if this week hasn't been trained yet.
    if (!weeks.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 7));
    }
    var streak = 0;
    while (weeks.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 7));
    }
    return streak;
  }
}

/// Reads an aggregate scalar from a `rawQuery` result.
int firstIntOr(List<Map<String, Object?>> rows, String column, int fallback) {
  if (rows.isEmpty) return fallback;
  final v = rows.first[column];
  return v is int ? v : fallback;
}

final workoutSessionRepositoryProvider = Provider<WorkoutSessionRepository>(
  (ref) => WorkoutSessionRepository(AppDatabase.instance),
);

final recentSessionsProvider = FutureProvider<List<SessionSummary>>(
  (ref) => ref.watch(workoutSessionRepositoryProvider).recentSessions(),
);

final sessionDetailProvider = FutureProvider.family<WorkoutSessionDetail?, int>(
  (ref, sessionId) =>
      ref.watch(workoutSessionRepositoryProvider).sessionDetail(sessionId),
);

final weeklySetsProvider = FutureProvider<List<WeeklyPoint>>(
  (ref) => ref.watch(workoutSessionRepositoryProvider).weeklySets(),
);

final muscleGroupLoadProvider = FutureProvider<List<MuscleGroupLoad>>(
  (ref) => ref.watch(workoutSessionRepositoryProvider).muscleGroupLoad(
        DateTime.now().subtract(const Duration(days: 30)),
      ),
);

final trainedExercisesProvider = FutureProvider<List<TrainedExercise>>(
  (ref) => ref.watch(workoutSessionRepositoryProvider).trainedStrengthExercises(),
);

final exerciseHistoryProvider =
    FutureProvider.family<List<ExerciseHistoryPoint>, int>(
  (ref, exerciseId) =>
      ref.watch(workoutSessionRepositoryProvider).exerciseHistory(exerciseId),
);

final personalRecordsProvider = FutureProvider<List<PersonalRecord>>(
  (ref) => ref.watch(workoutSessionRepositoryProvider).personalRecords(),
);

final trainingWeekStreakProvider = FutureProvider<int>(
  (ref) => ref.watch(workoutSessionRepositoryProvider).trainingWeekStreak(),
);

/// Sets of the last finished session that included this exercise — shown on the
/// exercise page as a "last time" reference (there is no weight to compare).
final lastPerformanceProvider =
    FutureProvider.family<List<StrengthSet>, int>(
  (ref, exerciseId) =>
      ref.watch(workoutSessionRepositoryProvider).lastPerformance(exerciseId),
);
