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
  });

  final int durationSeconds;
  final int? targetSpm;
  final String intensityLabel;
  final bool isRest;
  final String? drillKey;

  factory GeneratedRowSegment.fromBlock(RowBlock b) => GeneratedRowSegment(
        durationSeconds: b.seconds,
        targetSpm: b.spm,
        intensityLabel: b.label,
        isRest: b.isRest,
        drillKey: b.drillKey,
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

/// Builds a multi-week rowing plan by drawing named workouts from
/// [rowWorkouts]: a weekly mix of session archetypes driven by [RowingGoal],
/// periodised over the weeks (a deload near the middle, a taper at the end).
class RowingPlanGenerator {
  RowingPlanGenerator({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  GeneratedRowingPlan generate(RowingPlanInput input) {
    final spw = input.sessionsPerWeek.clamp(2, 5);
    final weeks = input.weeks.clamp(4, 16);
    final bands = (input.bands.isEmpty ? {(20, 30)} : input.bands).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));

    // Remember the last workout id picked per (slot, type) so weeks vary.
    final lastPick = <String, String>{};

    final sessions = <GeneratedRowSession>[];
    for (var w = 0; w < weeks; w++) {
      final deload = weeks >= 6 && w == weeks ~/ 2;
      final types = _weeklyTypes(input.goal, spw, deload: deload);
      final weekProgress = weeks <= 1 ? 1.0 : w / (weeks - 1);
      final buildFactor = deload
          ? 0.4
          : (w == weeks - 1 ? 0.8 : 0.75 + 0.25 * weekProgress);

      for (var slot = 0; slot < types.length; slot++) {
        final type = types[slot];
        // Deload week: short, easy — always the smallest sessions.
        final band = deload ? (12, 20) : _bandForWeek(bands, weekProgress, false);
        final workout = _pickWorkout(
          type,
          band,
          slotKey: '$slot-${type.name}',
          lastPick: lastPick,
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
          : 'Roeiplan · ${input.goal.label.toLowerCase()}',
      goal: input.goal,
      level: input.level,
      sessionsPerWeek: spw,
      weeks: weeks,
      sessions: sessions,
    );
  }

  // --- Weekly structure ---------------------------------------------

  List<RowSessionType> _weeklyTypes(RowingGoal goal, int spw,
      {required bool deload}) {
    final base = switch (goal) {
      RowingGoal.vetverlies => [
          RowSessionType.endurance,
          RowSessionType.intervalKort,
          RowSessionType.endurance,
          RowSessionType.herstel,
          RowSessionType.drempel,
        ],
      RowingGoal.uithouding => [
          RowSessionType.endurance,
          RowSessionType.drempel,
          RowSessionType.endurance,
          RowSessionType.intervalLang,
          RowSessionType.herstel,
        ],
      RowingGoal.kracht => [
          RowSessionType.krachtStroken,
          RowSessionType.intervalKort,
          RowSessionType.endurance,
          RowSessionType.drempel,
          RowSessionType.herstel,
        ],
      RowingGoal.techniek => [
          RowSessionType.techniek,
          RowSessionType.endurance,
          RowSessionType.techniek,
          RowSessionType.herstel,
          RowSessionType.drempel,
        ],
      RowingGoal.algemeen => [
          RowSessionType.endurance,
          RowSessionType.intervalKort,
          RowSessionType.piramide,
          RowSessionType.endurance,
          RowSessionType.herstel,
        ],
    };
    var types = base.take(spw).toList();
    if (deload) {
      types = types
          .map((t) => t == RowSessionType.herstel
              ? RowSessionType.herstel
              : RowSessionType.endurance)
          .toList();
    }
    return types;
  }

  /// Early weeks favour the shorter bands, later weeks the longer ones.
  (int, int) _bandForWeek(
      List<(int, int)> bands, double weekProgress, bool deload) {
    if (bands.length == 1) return bands.first;
    if (deload) return bands.first;
    // Index scales with progress, with a little jitter.
    final t = (weekProgress + (_rng.nextDouble() - 0.5) * 0.3).clamp(0.0, 1.0);
    final idx = (t * (bands.length - 1)).round().clamp(0, bands.length - 1);
    return bands[idx];
  }

  RowWorkout _pickWorkout(
    RowSessionType type,
    (int, int) band, {
    required String slotKey,
    required Map<String, String> lastPick,
  }) {
    var candidates = workoutsOfType(type)
        .where((w) =>
            w.approxMinutes >= band.$1 - 4 && w.approxMinutes <= band.$2 + 6)
        .toList();
    if (candidates.isEmpty) {
      // Nothing in range: take the whole type, closest by duration.
      candidates = workoutsOfType(type).toList()
        ..sort((a, b) => (a.approxMinutes - band.$2)
            .abs()
            .compareTo((b.approxMinutes - band.$2).abs()));
      candidates = candidates.take(3).toList();
    }
    if (candidates.isEmpty) {
      // Type has no workouts at all (shouldn't happen) — fall back to endurance.
      candidates = workoutsOfType(RowSessionType.endurance).toList();
    }
    final prev = lastPick[slotKey];
    final fresh = candidates.where((w) => w.id != prev).toList();
    final pool = fresh.isNotEmpty ? fresh : candidates;
    final chosen = pool[_rng.nextInt(pool.length)];
    lastPick[slotKey] = chosen.id;
    return chosen;
  }
}
