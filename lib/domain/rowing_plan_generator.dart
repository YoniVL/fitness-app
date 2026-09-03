import 'dart:math';

import 'models/program.dart';
import 'models/rowing_plan.dart';
import 'rowing_workouts.dart';

/// One segment of a generated rowing session.
class GeneratedRowSegment {
  const GeneratedRowSegment({
    required this.durationSeconds,
    this.targetSpm,
    required this.intensityLabel,
    this.isRest = false,
    this.drillKey,
    this.zone,
  });

  final int durationSeconds;
  final int? targetSpm;
  final String intensityLabel;
  final bool isRest;
  final String? drillKey;
  final String? zone;

  factory GeneratedRowSegment.fromBlock(RowBlock b) => GeneratedRowSegment(
        durationSeconds: b.seconds,
        targetSpm: b.spm,
        intensityLabel: b.label,
        isRest: b.isRest,
        drillKey: b.drillKey,
        zone: b.intensity.name,
      );
}

/// One session (= one `program_day`) of a generated plan.
class GeneratedRowSession {
  const GeneratedRowSession({
    required this.weekIndex,
    required this.type,
    required this.label,
    required this.segments,
  });

  final int weekIndex;
  final RowSessionType type;
  final String label;
  final List<GeneratedRowSegment> segments;

  int get totalSeconds =>
      segments.fold(0, (sum, s) => sum + s.durationSeconds);
}

class GeneratedRowingPlan {
  const GeneratedRowingPlan({
    required this.name,
    required this.goal,
    required this.level,
    required this.sessionsPerWeek,
    required this.weeks,
    required this.sessions,
  });

  final String name;
  final RowingGoal goal;
  final ProgramLevel level;
  final int sessionsPerWeek;
  final int weeks;
  final List<GeneratedRowSession> sessions;
}

class RowingPlanInput {
  const RowingPlanInput({
    required this.sessionsPerWeek,
    required this.goal,
    required this.level,
    required this.bands,
    this.weeks = 8,
    this.name,
  });

  final int sessionsPerWeek;
  final RowingGoal goal;
  final ProgramLevel level;

  /// One or more selected session-length bands, e.g. `{(20, 30), (30, 45)}`.
  final Set<(int, int)> bands;
  final int weeks;
  final String? name;
}

/// The weekly skeleton for a goal: one or more fixed *anchor* sessions plus a
/// *pool* the remaining slots rotate through, so consecutive weeks differ.
typedef _GoalPlan = ({List<RowSessionType> anchors, List<RowSessionType> pool});

_GoalPlan _goalPlan(RowingGoal g) => switch (g) {
      RowingGoal.vetverlies => (
          anchors: [RowSessionType.endurance],
          pool: [
            RowSessionType.intervalKort,
            RowSessionType.endurance,
            RowSessionType.drempel,
            RowSessionType.herstel,
            RowSessionType.piramide,
          ],
        ),
      RowingGoal.uithouding => (
          anchors: [RowSessionType.endurance],
          pool: [
            RowSessionType.drempel,
            RowSessionType.endurance,
            RowSessionType.intervalLang,
            RowSessionType.herstel,
            RowSessionType.drempel,
          ],
        ),
      RowingGoal.kracht => (
          anchors: [RowSessionType.krachtStroken],
          pool: [
            RowSessionType.intervalKort,
            RowSessionType.drempel,
            RowSessionType.endurance,
            RowSessionType.herstel,
            RowSessionType.intervalLang,
          ],
        ),
      RowingGoal.techniek => (
          anchors: [RowSessionType.techniek],
          pool: [
            RowSessionType.endurance,
            RowSessionType.techniek,
            RowSessionType.herstel,
            RowSessionType.drempel,
            RowSessionType.piramide,
          ],
        ),
      RowingGoal.algemeen => (
          anchors: [RowSessionType.endurance],
          pool: [
            RowSessionType.intervalKort,
            RowSessionType.piramide,
            RowSessionType.drempel,
            RowSessionType.endurance,
            RowSessionType.herstel,
            RowSessionType.intervalLang,
          ],
        ),
    };

/// Builds a multi-week rowing plan by drawing named workouts from
/// [rowWorkouts]. The weekly type mix rotates week to week; volume follows a
/// build → peak (~80 % through) → taper curve with a deload every 4th week; a
/// benchmark test is scheduled in the first and last week.
class RowingPlanGenerator {
  RowingPlanGenerator({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  GeneratedRowingPlan generate(RowingPlanInput input) {
    final spw = input.sessionsPerWeek.clamp(2, 5);
    final weeks = input.weeks.clamp(4, 16);
    final bands = (input.bands.isEmpty ? {(20, 30)} : input.bands).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final gp = _goalPlan(input.goal);

    // Remember the last workout id picked per (slot, type) so weeks vary.
    final lastPick = <String, String>{};
    final peakAt = ((weeks - 1) * 0.8).round();

    final sessions = <GeneratedRowSession>[];
    for (var w = 0; w < weeks; w++) {
      final deload = _isDeload(w, weeks);
      final types = _weekTypes(gp, spw, w, input.goal, weeks);
      final buildFactor = _buildFor(w, weeks, peakAt, deload);

      final targetMinutes = _targetMinutes(bands, buildFactor, deload);
      for (var slot = 0; slot < types.length; slot++) {
        final type = types[slot];
        final workout = _pickWorkout(
          type,
          targetMinutes,
          slotKey: '$slot-${type.name}',
          lastPick: lastPick,
          goal: input.goal,
        );
        final blocks = workout.blocks(input.level, buildFactor);
        sessions.add(GeneratedRowSession(
          weekIndex: w,
          type: type,
          label: 'Wk ${w + 1} · ${workout.name}',
          segments: blocks.map(GeneratedRowSegment.fromBlock).toList(),
        ));
      }
    }

    return GeneratedRowingPlan(
      name: input.name?.trim().isNotEmpty == true
          ? input.name!.trim()
          : 'Roeiplan · ${input.goal.label} · '
              '${input.level.label} · $spw×',
      goal: input.goal,
      level: input.level,
      sessionsPerWeek: spw,
      weeks: weeks,
      sessions: sessions,
    );
  }

  // --- Weekly structure ---------------------------------------------

  /// Deload every 4th week (plans of 8 weeks or more), never the last week.
  bool _isDeload(int w, int weeks) =>
      weeks >= 8 && (w + 1) % 4 == 0 && w != weeks - 1;

  List<RowSessionType> _weekTypes(
      _GoalPlan gp, int spw, int w, RowingGoal goal, int weeks) {
    final types = <RowSessionType>[...gp.anchors];
    final need = (spw - types.length).clamp(0, spw);
    var cursor = w * need;
    for (var k = 0; k < need; k++) {
      // Rotate through the pool, skipping a type already in the week so the
      // mix stays varied (and volume isn't dominated by a repeated archetype).
      var tries = 0;
      var pick = gp.pool[cursor % gp.pool.length];
      while (types.contains(pick) && tries < gp.pool.length) {
        cursor++;
        pick = gp.pool[cursor % gp.pool.length];
        tries++;
      }
      types.add(pick);
      cursor++;
    }

    // Baseline + retest: swap the lightest slot for a benchmark test.
    if ((w == 0 || w == weeks - 1) &&
        goal != RowingGoal.techniek &&
        weeks >= 4) {
      var idx = types.indexOf(RowSessionType.herstel);
      if (idx < 1) idx = types.lastIndexOf(RowSessionType.endurance);
      if (idx < 1) idx = types.length - 1;
      types[idx] = RowSessionType.test;
    }
    return types;
  }

  /// Week 1 easy → peak ~1.05 at ~80 % of the plan → taper to ~0.70;
  /// a deload week drops to ~0.5.
  double _buildFor(int w, int weeks, int peakAt, bool deload) {
    if (deload) return 0.5;
    if (w >= peakAt) {
      final span = weeks - 1 - peakAt;
      final t = span <= 0 ? 1.0 : (w - peakAt) / span;
      return 1.05 - 0.35 * t;
    }
    final t = peakAt == 0 ? 1.0 : w / peakAt;
    return 0.55 + 0.5 * t;
  }

  /// The session length (minutes) the week aims for: scales with the build
  /// curve between the shortest and longest selected band, so weekly volume
  /// follows the periodisation rather than which archetypes landed that week.
  double _targetMinutes(
      List<(int, int)> bands, double buildFactor, bool deload) {
    final lo = bands.first.$1.toDouble();
    final hi = bands.last.$2.toDouble();
    final t = ((buildFactor - 0.55) / 0.5).clamp(0.0, 1.0);
    if (deload) return (lo * 0.85).clamp(12, hi);
    return lo + (hi - lo) * t;
  }

  RowWorkout _pickWorkout(
    RowSessionType type,
    double targetMinutes, {
    required String slotKey,
    required Map<String, String> lastPick,
    required RowingGoal goal,
  }) {
    // Benchmarks are fixed so week 1 and the last week compare like for like.
    if (type == RowSessionType.test) {
      final id = goal == RowingGoal.kracht ? 'test_500' : 'test_2k';
      return workoutById(id) ?? workoutsOfType(type).first;
    }

    final all = workoutsOfType(type).toList();
    if (all.isEmpty) return workoutsOfType(RowSessionType.endurance).first;
    all.sort((a, b) => (a.approxMinutes - targetMinutes)
        .abs()
        .compareTo((b.approxMinutes - targetMinutes).abs()));

    // The two closest to the target, minus last week's pick for this slot.
    final prev = lastPick[slotKey];
    final shortlist = all.take(all.length >= 3 ? 3 : all.length).toList();
    final fresh = shortlist.where((w) => w.id != prev).toList();
    final pool = fresh.isNotEmpty ? fresh : shortlist;
    final chosen = pool[_rng.nextInt(pool.length)];
    lastPick[slotKey] = chosen.id;
    return chosen;
  }
}
