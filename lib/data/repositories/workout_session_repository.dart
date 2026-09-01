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

/// One (weekStart, working reps) point for progress charts (charts land later).
class WeeklyRepsPoint {
  const WeeklyRepsPoint(this.weekStart, this.reps);
  final DateTime weekStart;
  final int reps;
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

  /// Working reps per ISO week (Monday start), oldest first.
  Future<List<WeeklyRepsPoint>> weeklyReps({int weeks = 12}) async {
    final db = await _appDb.database;
    final rows = await db.rawQuery(
      '''
      SELECT ws.started_at AS started_at, ss.reps AS reps
      FROM strength_sets ss
      JOIN workout_sessions ws ON ws.id = ss.session_id
      WHERE ss.is_warmup = 0 AND ws.discipline = 'strength'
      ''',
    );
    final byWeek = <DateTime, int>{};
    for (final r in rows) {
      final date = DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int);
      final monday = DateTime(date.year, date.month, date.day)
          .subtract(Duration(days: date.weekday - 1));
      byWeek.update(monday, (v) => v + (r['reps'] as int),
          ifAbsent: () => r['reps'] as int);
    }
    final points = byWeek.entries
        .map((e) => WeeklyRepsPoint(e.key, e.value))
        .toList()
      ..sort((a, b) => a.weekStart.compareTo(b.weekStart));
    return points.length <= weeks
        ? points
        : points.sublist(points.length - weeks);
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
