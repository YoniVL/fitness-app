import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/program.dart';
import '../../domain/models/rowing.dart';
import '../../domain/models/workout_session.dart';
import '../../domain/rowing_achievements.dart';
import '../database/app_database.dart';

/// Compact JSON for the segments of an ad-hoc (catalogue) rowing workout, so
/// the structure survives an app restart (there is no `program_day` to reload).
String encodeRowSegments(List<ProgramRowSegment> segs) => jsonEncode([
      for (final s in segs)
        {
          'd': s.durationSeconds,
          'spm': s.targetStrokeRate,
          'label': s.intensityLabel,
          'rest': s.isRest,
          'drill': s.drillKey,
          'zone': s.zone,
          'w': s.targetWatts,
        }
    ]);

List<ProgramRowSegment> decodeRowSegments(String json) {
  final list = (jsonDecode(json) as List).cast<Map<String, Object?>>();
  return [
    for (var i = 0; i < list.length; i++)
      ProgramRowSegment(
        id: 0,
        programDayId: 0,
        orderIndex: i,
        durationSeconds: (list[i]['d'] as num).toInt(),
        targetStrokeRate: (list[i]['spm'] as num?)?.toInt(),
        intensityLabel: list[i]['label'] as String? ?? '',
        isRest: list[i]['rest'] as bool? ?? false,
        drillKey: list[i]['drill'] as String?,
        zone: list[i]['zone'] as String?,
        targetWatts: (list[i]['w'] as num?)?.toDouble(),
      ),
  ];
}

/// The rowing numbers the log list needs for one session.
class RowingSummary {
  const RowingSummary({
    required this.distanceM,
    required this.durationSeconds,
    required this.avgStrokeRate,
    required this.avgPower,
  });

  final double distanceM;
  final int durationSeconds;
  final double avgStrokeRate;
  final double avgPower;

  Duration get duration => Duration(seconds: durationSeconds);

  /// Average pace in seconds per 500 m, derived from distance + time.
  double? get avgPaceSec500 {
    if (distanceM <= 0 || durationSeconds <= 0) return null;
    return durationSeconds / distanceM * 500;
  }

  factory RowingSummary.fromMap(Map<String, Object?> map) => RowingSummary(
        distanceM: (map['total_distance_m'] as num?)?.toDouble() ?? 0,
        durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
        avgStrokeRate: (map['avg_stroke_rate'] as num?)?.toDouble() ?? 0,
        avgPower: (map['avg_power'] as num?)?.toDouble() ?? 0,
      );
}

/// A finished rowing session with its aggregate row and time-series samples,
/// for the log detail screen.
class RowingSessionDetail {
  const RowingSessionDetail({
    required this.session,
    required this.rowing,
    required this.samples,
    this.planSegments = const [],
  });

  final WorkoutSession session;
  final RowingSession rowing;
  final List<RowingSample> samples;

  /// The plan-day segments this session followed, if it came from a plan.
  final List<ProgramRowSegment> planSegments;
}

/// New rowing session ids: the `workout_sessions` row and its `rowing_sessions`
/// child, returned by [RowingRepository.startSession].
typedef RowingSessionIds = ({int sessionId, int rowingSessionId});

/// One (weekStart, metres, sessions) point for the weekly rowing chart.
class RowingWeekPoint {
  const RowingWeekPoint(this.weekStart, this.distanceM, this.sessions);
  final DateTime weekStart;
  final double distanceM;
  final int sessions;
}

/// Average pace (sec/500 m) of one finished rowing session.
class RowingPacePoint {
  const RowingPacePoint(this.date, this.paceSec500);
  final DateTime date;
  final double paceSec500;
}

/// Totals over a recent window.
class RowingTotals {
  const RowingTotals(this.sessions, this.distanceM, this.durationSeconds);
  final int sessions;
  final double distanceM;
  final int durationSeconds;
}

/// The history of one benchmark distance (e.g. 2000 m) — every timed attempt,
/// oldest first, plus the personal best.
class RowingBenchmark {
  RowingBenchmark(this.distanceM, this.attempts);
  final int distanceM;

  /// (date, total seconds), oldest first.
  final List<({DateTime date, int seconds})> attempts;

  int get bestSeconds =>
      attempts.map((a) => a.seconds).reduce((a, b) => a < b ? a : b);
  ({DateTime date, int seconds}) get latest => attempts.last;
}

class RowingRepository {
  RowingRepository(this._appDb);

  final AppDatabase _appDb;

  // --- Live sessions --------------------------------------------------

  /// Opens a rowing session plus its (zeroed) `rowing_sessions` child so live
  /// samples have something to attach to. Finalise with [finalize].
  Future<RowingSessionIds> startSession({
    int? programDayId,
    String? segmentsJson,
    String? kind,
  }) async {
    final db = await _appDb.database;
    final now = DateTime.now();
    final sessionId = await db.insert('workout_sessions', {
      'discipline': Discipline.rowing.name,
      'program_day_id': programDayId,
      'started_at': now.millisecondsSinceEpoch,
      'ended_at': null,
    });
    final rowingSessionId = await db.insert('rowing_sessions', {
      'session_id': sessionId,
      'program_day_id': programDayId,
      'segments_json': segmentsJson,
      'kind': kind,
      'active_elapsed_ms': 0,
    });
    return (sessionId: sessionId, rowingSessionId: rowingSessionId);
  }

  /// Live checkpoint of the real elapsed time (excludes paused stretches) so a
  /// rehydrate after an app kill doesn't count wall-clock time spent away.
  Future<void> checkpointElapsed(int sessionId, Duration elapsed) async {
    final db = await _appDb.database;
    await db.update(
      'rowing_sessions',
      {'active_elapsed_ms': elapsed.inMilliseconds},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> addSamples(
      int rowingSessionId, List<RowingSample> samples) async {
    if (samples.isEmpty) return;
    final db = await _appDb.database;
    final batch = db.batch();
    for (final s in samples) {
      batch.insert('rowing_samples', {
        'rowing_session_id': rowingSessionId,
        't_offset_ms': s.tOffsetMs,
        'stroke_rate': s.strokeRate,
        'stroke_count': s.strokeCount,
        'distance_m': s.distanceM,
        'pace_sec_500m': s.paceSec500m,
        'power_w': s.powerW,
        'energy_kcal': s.energyKcal,
        'heart_rate': s.heartRate,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Writes the aggregate numbers onto the `rowing_sessions` row and closes the
  /// parent `workout_sessions` row.
  Future<void> finalize(
    int sessionId, {
    required double distanceM,
    required Duration duration,
    double avgStrokeRate = 0,
    double avgPower = 0,
    double energyKcal = 0,
    String? notes,
  }) async {
    final db = await _appDb.database;
    // `kind` was set at startSession — not touched here.
    await db.update(
      'rowing_sessions',
      {
        'total_distance_m': distanceM,
        'total_energy_kcal': energyKcal,
        'avg_stroke_rate': avgStrokeRate,
        'avg_power': avgPower,
        'duration_seconds': duration.inSeconds,
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    await db.update(
      'workout_sessions',
      {'ended_at': DateTime.now().millisecondsSinceEpoch, 'notes': ?notes},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> discardSession(int sessionId) async {
    final db = await _appDb.database;
    await db.delete('workout_sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  // --- Manual entry --------------------------------------------------

  /// Logs a finished rowing session in one go (no samples). [when] is the moment
  /// the session ended (default now); [kind] is a `RowSessionType.name`.
  Future<int> logManualSession({
    required double distanceM,
    required Duration duration,
    double avgStrokeRate = 0,
    double avgPower = 0,
    double energyKcal = 0,
    String? notes,
    int? programDayId,
    String? kind,
    DateTime? when,
  }) async {
    final db = await _appDb.database;
    final endedAt = when ?? DateTime.now();
    final startedAt = endedAt.subtract(duration);
    final sessionId = await db.insert('workout_sessions', {
      'discipline': Discipline.rowing.name,
      'program_day_id': programDayId,
      'started_at': startedAt.millisecondsSinceEpoch,
      'ended_at': endedAt.millisecondsSinceEpoch,
      'notes': ?notes,
    });
    await db.insert('rowing_sessions', {
      'session_id': sessionId,
      'program_day_id': programDayId,
      'total_distance_m': distanceM,
      'total_energy_kcal': energyKcal,
      'avg_stroke_rate': avgStrokeRate,
      'avg_power': avgPower,
      'duration_seconds': duration.inSeconds,
      'kind': kind,
    });
    return sessionId;
  }

  // --- Reading -----------------------------------------------------

  Future<RowingSessionDetail?> rowingDetail(int sessionId) async {
    final db = await _appDb.database;
    final sessionRows = await db.query('workout_sessions',
        where: 'id = ?', whereArgs: [sessionId], limit: 1);
    if (sessionRows.isEmpty) return null;
    final rowingRows = await db.query('rowing_sessions',
        where: 'session_id = ?', whereArgs: [sessionId], limit: 1);
    if (rowingRows.isEmpty) return null;
    final sampleRows = await db.query('rowing_samples',
        where: 'rowing_session_id = ?',
        whereArgs: [rowingRows.first['id']],
        orderBy: 't_offset_ms');
    final rowing = RowingSession.fromMap(rowingRows.first);
    var planSegments = const <ProgramRowSegment>[];
    if (rowing.programDayId != null) {
      final segRows = await db.query('program_row_segments',
          where: 'program_day_id = ?',
          whereArgs: [rowing.programDayId],
          orderBy: 'order_index');
      planSegments = segRows.map(ProgramRowSegment.fromMap).toList();
    } else if (rowing.segmentsJson != null &&
        rowing.segmentsJson!.isNotEmpty) {
      planSegments = decodeRowSegments(rowing.segmentsJson!);
    }
    return RowingSessionDetail(
      session: WorkoutSession.fromMap(sessionRows.first),
      rowing: rowing,
      samples: sampleRows.map(RowingSample.fromMap).toList(),
      planSegments: planSegments,
    );
  }

  // --- Progress ---------------------------------------------------

  Future<List<Map<String, Object?>>> _finishedRows() async {
    final db = await _appDb.database;
    return db.rawQuery('''
      SELECT ws.started_at AS started_at,
             rs.total_distance_m AS distance_m,
             rs.duration_seconds AS duration_seconds,
             rs.kind AS kind
      FROM rowing_sessions rs
      JOIN workout_sessions ws ON ws.id = rs.session_id
      WHERE ws.ended_at IS NOT NULL
      ORDER BY ws.started_at
    ''');
  }

  static DateTime _weekOf(DateTime d) => DateTime(d.year, d.month, d.day)
      .subtract(Duration(days: d.weekday - 1));

  /// Distance + session count per ISO week (Monday), oldest first, last [weeks].
  Future<List<RowingWeekPoint>> weeklyDistance({int weeks = 10}) async {
    final rows = await _finishedRows();
    if (rows.isEmpty) return const [];
    final dist = <DateTime, double>{};
    final count = <DateTime, int>{};
    for (final r in rows) {
      final wk = _weekOf(
          DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int));
      dist.update(wk, (v) => v + ((r['distance_m'] as num?)?.toDouble() ?? 0),
          ifAbsent: () => (r['distance_m'] as num?)?.toDouble() ?? 0);
      count.update(wk, (v) => v + 1, ifAbsent: () => 1);
    }
    final thisMonday = _weekOf(DateTime.now());
    return [
      for (var i = weeks - 1; i >= 0; i--)
        () {
          final wk = thisMonday.subtract(Duration(days: 7 * i));
          return RowingWeekPoint(wk, dist[wk] ?? 0, count[wk] ?? 0);
        }(),
    ];
  }

  /// Average pace per finished session that covered distance, oldest first.
  /// [kinds] filters on `rowing_sessions.kind` (null kind excluded when set).
  Future<List<RowingPacePoint>> paceHistory({Set<String>? kinds}) async {
    final rows = await _finishedRows();
    final out = <RowingPacePoint>[];
    for (final r in rows) {
      final d = (r['distance_m'] as num?)?.toDouble() ?? 0;
      final s = (r['duration_seconds'] as num?)?.toInt() ?? 0;
      if (d <= 0 || s <= 0) continue;
      if (kinds != null && !kinds.contains(r['kind'] as String?)) continue;
      out.add(RowingPacePoint(
        DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
        s / d * 500,
      ));
    }
    return out;
  }

  /// Consecutive weeks (Monday start) ending at the current or last week with at
  /// least one finished rowing session.
  Future<int> weekStreak() async {
    final rows = await _finishedRows();
    if (rows.isEmpty) return 0;
    final weeks = <DateTime>{
      for (final r in rows)
        _weekOf(DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int)),
    };
    var cursor = _weekOf(DateTime.now());
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

  Future<RowingTotals> totalsSince(DateTime since) async {
    final rows = await _finishedRows();
    var n = 0;
    var dist = 0.0;
    var dur = 0;
    for (final r in rows) {
      final t = DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int);
      if (t.isBefore(since)) continue;
      n++;
      dist += (r['distance_m'] as num?)?.toDouble() ?? 0;
      dur += (r['duration_seconds'] as num?)?.toInt() ?? 0;
    }
    return RowingTotals(n, dist, dur);
  }

  /// The standard test distances tracked on the Progress screen.
  static const benchmarkDistances = <int>[500, 2000, 5000];

  /// Finished `kind == 'test'` sessions, grouped by the standard distance they
  /// land nearest (within 12 %). One [RowingBenchmark] per distance that has data.
  Future<List<RowingBenchmark>> benchmarkHistory() async {
    final rows = await _finishedRows();
    final byDist = <int, List<({DateTime date, int seconds})>>{};
    for (final r in rows) {
      if (r['kind'] != 'test') continue;
      final d = (r['distance_m'] as num?)?.toDouble() ?? 0;
      final s = (r['duration_seconds'] as num?)?.toInt() ?? 0;
      if (d <= 0 || s <= 0) continue;
      for (final std in benchmarkDistances) {
        if ((d - std).abs() <= std * 0.12) {
          byDist.putIfAbsent(std, () => []).add((
            date: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
            seconds: s,
          ));
          break;
        }
      }
    }
    return [
      for (final std in benchmarkDistances)
        if (byDist[std]?.isNotEmpty ?? false)
          RowingBenchmark(
              std, byDist[std]!..sort((a, b) => a.date.compareTo(b.date))),
    ];
  }

  /// One pass over the finished rowing sessions for the achievement engine.
  /// FTP fields are left null/zero — the provider merges those from settings.
  Future<AchievementStats> achievementStats() async {
    final rows = await _finishedRows();
    if (rows.isEmpty) return const AchievementStats();

    final dates = <DateTime>[];
    var totalD = 0.0, longestD = 0.0;
    var totalT = 0, longestT = 0;
    double? bestSplit;
    final kinds = <String>{};
    var weekend = false, comeback = false, ftpSessions = 0;
    int? earliestH, latestH;

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final at = DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int);
      final d = (r['distance_m'] as num?)?.toDouble() ?? 0;
      final t = (r['duration_seconds'] as num?)?.toInt() ?? 0;
      dates.add(at);
      totalD += d;
      totalT += t;
      if (d > longestD) longestD = d;
      if (t > longestT) longestT = t;
      if (d >= 1000 && t > 0) {
        final split = t / d * 500;
        if (bestSplit == null || split < bestSplit) bestSplit = split;
      }
      if (r['kind'] != null) {
        kinds.add(r['kind'] as String);
        if ((r['kind'] as String).startsWith('ftp_')) ftpSessions++;
      }
      if (at.weekday == DateTime.saturday || at.weekday == DateTime.sunday) {
        weekend = true;
      }
      earliestH = earliestH == null ? at.hour : (at.hour < earliestH ? at.hour : earliestH);
      latestH = latestH == null ? at.hour : (at.hour > latestH ? at.hour : latestH);
      if (i > 0) {
        final prev =
            DateTime.fromMillisecondsSinceEpoch(rows[i - 1]['started_at'] as int);
        if (at.difference(prev).inDays >= 30) comeback = true;
      }
    }

    final benchmarks = {
      for (final b in await benchmarkHistory()) b.distanceM: b.bestSeconds,
    };
    final first = dates.first;
    final now = DateTime.now();
    final months =
        (now.year - first.year) * 12 + now.month - first.month - (now.day < first.day ? 1 : 0);

    return AchievementStats(
      totalDistanceM: totalD,
      totalDurationSeconds: totalT,
      sessionCount: rows.length,
      longestSessionM: longestD,
      longestSessionSeconds: longestT,
      bestAvgSplitSeconds: bestSplit,
      currentWeekStreak: currentWeekStreak(dates),
      longestWeekStreak: longestWeekStreak(dates),
      currentDayStreak: currentDayStreak(dates),
      longestDayStreak: longestDayStreak(dates),
      sessionKinds: kinds,
      monthsSinceFirst: months < 0 ? 0 : months,
      best2kSeconds: benchmarks[2000],
      best5kSeconds: benchmarks[5000],
      best500mSeconds: benchmarks[500],
      ftpTestCount: ftpSessions,
      didRampTest: kinds.contains('ftp_ramp'),
      rowedWeekendDay: weekend,
      earliestStartHour: earliestH,
      latestStartHour: latestH,
      hadComeback: comeback,
    );
  }
}

final rowingRepositoryProvider = Provider<RowingRepository>(
  (ref) => RowingRepository(AppDatabase.instance),
);

final rowingSessionDetailProvider =
    FutureProvider.family<RowingSessionDetail?, int>(
  (ref, sessionId) =>
      ref.watch(rowingRepositoryProvider).rowingDetail(sessionId),
);

final rowingWeeklyDistanceProvider = FutureProvider<List<RowingWeekPoint>>(
  (ref) => ref.watch(rowingRepositoryProvider).weeklyDistance(),
);

/// Pace trend, optionally filtered by session kind. `null` key = every session.
final rowingPaceHistoryProvider =
    FutureProvider.family<List<RowingPacePoint>, Set<String>?>(
  (ref, kinds) => ref.watch(rowingRepositoryProvider).paceHistory(kinds: kinds),
);

final rowingBenchmarkHistoryProvider =
    FutureProvider<List<RowingBenchmark>>(
  (ref) => ref.watch(rowingRepositoryProvider).benchmarkHistory(),
);

final rowingWeekStreakProvider = FutureProvider<int>(
  (ref) => ref.watch(rowingRepositoryProvider).weekStreak(),
);

final rowingMonthTotalsProvider = FutureProvider<RowingTotals>(
  (ref) => ref
      .watch(rowingRepositoryProvider)
      .totalsSince(DateTime.now().subtract(const Duration(days: 30))),
);

/// Every rowing-progress provider — invalidate them all after a session is
/// logged or deleted.
final rowingProgressProviders = <ProviderOrFamily>[
  rowingWeeklyDistanceProvider,
  rowingPaceHistoryProvider,
  rowingBenchmarkHistoryProvider,
  rowingWeekStreakProvider,
  rowingMonthTotalsProvider,
];
