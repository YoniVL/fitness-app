import 'dart:math';

import 'models/program.dart';
import 'models/rowing_plan.dart';

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
    required this.minMinutes,
    required this.maxMinutes,
    required this.sessions,
  });

  final String name;
  final RowingGoal goal;
  final ProgramLevel level;
  final int sessionsPerWeek;
  final int weeks;
  final int minMinutes;
  final int maxMinutes;
  final List<GeneratedRowSession> sessions;
}

class RowingPlanInput {
  const RowingPlanInput({
    required this.sessionsPerWeek,
    required this.goal,
    required this.level,
    required this.minMinutes,
    required this.maxMinutes,
    this.weeks = 8,
    this.name,
  });

  final int sessionsPerWeek;
  final RowingGoal goal;
  final ProgramLevel level;
  final int minMinutes;
  final int maxMinutes;
  final int weeks;
  final String? name;
}

/// Builds a multi-week rowing plan: a weekly mix of session archetypes driven by
/// [RowingGoal], with volume/intensity periodised over the weeks (a deload near
/// the middle and a taper at the end).
class RowingPlanGenerator {
  RowingPlanGenerator({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  GeneratedRowingPlan generate(RowingPlanInput input) {
    final spw = input.sessionsPerWeek.clamp(2, 5);
    final weeks = input.weeks.clamp(4, 16);
    final lo = min(input.minMinutes, input.maxMinutes);
    final hi = max(input.minMinutes, input.maxMinutes);

    final sessions = <GeneratedRowSession>[];
    for (var w = 0; w < weeks; w++) {
      final deload = w == weeks ~/ 2 && weeks >= 6;
      final types = _weeklyTypes(input.goal, spw, deload: deload);
      final wf = _weekFactor(w, weeks);
      final progress = weeks <= 1 ? 1.0 : w / (weeks - 1);

      for (final type in types) {
        final targetSec =
            (_targetMinutes(type, lo, hi) * wf).round().clamp(
                  (lo * 0.7).round(),
                  hi + 3,
                ) *
                60;
        sessions.add(GeneratedRowSession(
          weekIndex: w,
          type: type,
          label: 'Wk ${w + 1} · ${type.label}',
          segments: _buildSession(type, targetSec, input.level, progress),
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
      minMinutes: lo,
      maxMinutes: hi,
      sessions: sessions,
    );
  }

  // --- Weekly structure -------------------------------------------------

  List<RowSessionType> _weeklyTypes(RowingGoal goal, int spw,
      {required bool deload}) {
    final base = switch (goal) {
      RowingGoal.vetverlies => [
          RowSessionType.duur,
          RowSessionType.intervalKort,
          RowSessionType.duur,
          RowSessionType.herstel,
          RowSessionType.drempel,
        ],
      RowingGoal.uithouding => [
          RowSessionType.duur,
          RowSessionType.drempel,
          RowSessionType.duur,
          RowSessionType.intervalLang,
          RowSessionType.herstel,
        ],
      RowingGoal.kracht => [
          RowSessionType.krachtStroken,
          RowSessionType.intervalKort,
          RowSessionType.duur,
          RowSessionType.drempel,
          RowSessionType.herstel,
        ],
      RowingGoal.techniek => [
          RowSessionType.techniek,
          RowSessionType.duur,
          RowSessionType.techniek,
          RowSessionType.herstel,
          RowSessionType.drempel,
        ],
      RowingGoal.algemeen => [
          RowSessionType.duur,
          RowSessionType.intervalKort,
          RowSessionType.drempel,
          RowSessionType.duur,
          RowSessionType.herstel,
        ],
    };
    var types = base.take(spw).toList();
    if (deload) {
      // Deload week: everything easy — only steady + recovery.
      types = types
          .map((t) => t == RowSessionType.herstel
              ? RowSessionType.herstel
              : RowSessionType.duur)
          .toList();
    }
    return types;
  }

  /// 0.68 on the deload week, 0.8 in the final taper week, otherwise a gentle
  /// ramp from 0.85 to 1.0.
  double _weekFactor(int w, int weeks) {
    if (weeks >= 6 && w == weeks ~/ 2) return 0.68;
    if (w == weeks - 1) return 0.8;
    final peak = max(1, weeks - 2);
    final t = (w / peak).clamp(0.0, 1.0);
    return 0.85 + 0.15 * t;
  }

  /// The unscaled minutes target for a session type, positioned within the
  /// user's [lo]..[hi] band.
  double _targetMinutes(RowSessionType type, int lo, int hi) {
    final pos = switch (type) {
      RowSessionType.duur => 0.95,
      RowSessionType.intervalLang => 0.7,
      RowSessionType.drempel => 0.7,
      RowSessionType.piramide => 0.6,
      RowSessionType.intervalKort => 0.55,
      RowSessionType.krachtStroken => 0.55,
      RowSessionType.techniek => 0.5,
      RowSessionType.herstel => 0.25,
    };
    return lo + (hi - lo) * pos;
  }

  // --- Session builders ------------------------------------------------

  List<GeneratedRowSegment> _buildSession(
      RowSessionType type, int targetSec, ProgramLevel level, double progress) {
    return switch (type) {
      RowSessionType.duur => _steady(targetSec, level),
      RowSessionType.herstel => _recovery(targetSec),
      RowSessionType.drempel => _threshold(targetSec, level, progress),
      RowSessionType.intervalKort => _shortIntervals(targetSec, level, progress),
      RowSessionType.intervalLang => _longIntervals(targetSec, level, progress),
      RowSessionType.piramide => _pyramid(targetSec, level, progress),
      RowSessionType.krachtStroken => _powerStrokes(targetSec, level),
      RowSessionType.techniek => _technique(targetSec, level, progress),
    };
  }

  int _lerpInt(num a, num b, double t) => (a + (b - a) * t).round();

  GeneratedRowSegment _warmup([int seconds = 180]) => GeneratedRowSegment(
      durationSeconds: seconds, targetSpm: 18, intensityLabel: 'Warming-up');

  GeneratedRowSegment _cooldown([int seconds = 120]) => GeneratedRowSegment(
      durationSeconds: seconds, targetSpm: 16, intensityLabel: 'Uitroeien');

  GeneratedRowSegment _rest(int seconds) => GeneratedRowSegment(
      durationSeconds: seconds,
      targetSpm: 18,
      intensityLabel: 'Rust',
      isRest: true);

  int _steadySpm(ProgramLevel l) => switch (l) {
        ProgramLevel.beginner => 20,
        ProgramLevel.medium => 21,
        ProgramLevel.advanced => 22,
      };

  List<GeneratedRowSegment> _steady(int targetSec, ProgramLevel level) {
    final main = (targetSec - 180 - 120).clamp(300, 100000);
    return [
      _warmup(),
      GeneratedRowSegment(
          durationSeconds: main,
          targetSpm: _steadySpm(level),
          intensityLabel: 'Duur'),
      _cooldown(),
    ];
  }

  List<GeneratedRowSegment> _recovery(int targetSec) {
    final main = (targetSec - 120).clamp(240, 100000);
    return [
      _warmup(120),
      GeneratedRowSegment(
          durationSeconds: main, targetSpm: 17, intensityLabel: 'Rustig'),
    ];
  }

  List<GeneratedRowSegment> _intervalSet({
    required int targetSec,
    required int workSec,
    required int workSpm,
    required int restSec,
    required String workLabel,
    required int minReps,
    required int maxReps,
    int warmupSec = 180,
    int cooldownSec = 120,
  }) {
    final available = (targetSec - warmupSec - cooldownSec).clamp(60, 100000);
    final unit = workSec + restSec;
    final reps = (available / unit).round().clamp(minReps, maxReps);
    final out = <GeneratedRowSegment>[_warmup(warmupSec)];
    for (var i = 0; i < reps; i++) {
      out.add(GeneratedRowSegment(
          durationSeconds: workSec,
          targetSpm: workSpm,
          intensityLabel: '$workLabel ${i + 1}/$reps'));
      if (i < reps - 1) out.add(_rest(restSec));
    }
    out.add(_cooldown(cooldownSec));
    return out;
  }

  List<GeneratedRowSegment> _threshold(
      int targetSec, ProgramLevel level, double progress) {
    final workSec = _lerpInt(240, 360, progress) + (level.index * 30);
    final restSec = (workSec *
            switch (level) {
              ProgramLevel.beginner => 0.5,
              ProgramLevel.medium => 0.4,
              ProgramLevel.advanced => 0.35,
            })
        .round();
    return _intervalSet(
      targetSec: targetSec,
      workSec: workSec,
      workSpm: 24 + level.index,
      restSec: restSec,
      workLabel: 'Drempel',
      minReps: 2,
      maxReps: 5,
    );
  }

  List<GeneratedRowSegment> _shortIntervals(
      int targetSec, ProgramLevel level, double progress) {
    final workSec = _lerpInt(45, 75, progress);
    final restSec = (workSec *
            switch (level) {
              ProgramLevel.beginner => 1.3,
              ProgramLevel.medium => 1.0,
              ProgramLevel.advanced => 0.8,
            })
        .round();
    return _intervalSet(
      targetSec: targetSec,
      workSec: workSec,
      workSpm: 27 + level.index,
      restSec: restSec,
      workLabel: 'Hard',
      minReps: 5,
      maxReps: 10,
    );
  }

  List<GeneratedRowSegment> _longIntervals(
      int targetSec, ProgramLevel level, double progress) {
    final workSec = _lerpInt(180, 240, progress);
    return _intervalSet(
      targetSec: targetSec,
      workSec: workSec,
      workSpm: 25 + level.index,
      restSec: (workSec * 0.5).round(),
      workLabel: 'Interval',
      minReps: 3,
      maxReps: 6,
    );
  }

  List<GeneratedRowSegment> _pyramid(
      int targetSec, ProgramLevel level, double progress) {
    final scale = 0.8 + progress * 0.4;
    final steps = <(int, int, String)>[
      ((60 * scale).round(), 22 + level.index, 'Opbouw'),
      ((120 * scale).round(), 24 + level.index, 'Middel'),
      ((180 * scale).round(), 26 + level.index, 'Piek'),
      ((120 * scale).round(), 24 + level.index, 'Middel'),
      ((60 * scale).round(), 22 + level.index, 'Afbouw'),
    ];
    final out = <GeneratedRowSegment>[_warmup()];
    for (var i = 0; i < steps.length; i++) {
      final (dur, spm, label) = steps[i];
      out.add(GeneratedRowSegment(
          durationSeconds: dur, targetSpm: spm, intensityLabel: label));
      if (i < steps.length - 1) out.add(_rest(60));
    }
    out.add(_cooldown());
    return out;
  }

  List<GeneratedRowSegment> _powerStrokes(int targetSec, ProgramLevel level) {
    final spm = 18 + level.index;
    return _intervalSet(
      targetSec: targetSec,
      workSec: 40,
      workSpm: spm,
      restSec: 40,
      workLabel: 'Krachthaal',
      minReps: 6,
      maxReps: 14,
    ).map((s) => s.intensityLabel.startsWith('Krachthaal')
        ? GeneratedRowSegment(
            durationSeconds: s.durationSeconds,
            targetSpm: s.targetSpm,
            intensityLabel: s.intensityLabel,
            drillKey: RowDrill.krachtHaal.key)
        : s).toList();
  }

  List<GeneratedRowSegment> _technique(
      int targetSec, ProgramLevel level, double progress) {
    final drills = [
      RowDrill.benenOnly,
      RowDrill.armenOnly,
      RowDrill.armenRomp,
      RowDrill.pauzeHaal,
      RowDrill.opbouwHaal,
      RowDrill.omgekeerdeRatio,
    ]..shuffle(_rng);

    final drillSec = _lerpInt(90, 150, progress);
    final steadySec = 210;
    final available =
        (targetSec - 120 - steadySec - 120).clamp(drillSec, 100000);
    final n = (available / drillSec).round().clamp(3, drills.length);

    final out = <GeneratedRowSegment>[_warmup(120)];
    for (var i = 0; i < n; i++) {
      final d = drills[i % drills.length];
      out.add(GeneratedRowSegment(
        durationSeconds: drillSec,
        targetSpm: 18,
        intensityLabel: 'Techniek — ${d.label}',
        drillKey: d.key,
      ));
    }
    out.add(GeneratedRowSegment(
        durationSeconds: steadySec,
        targetSpm: _steadySpm(level),
        intensityLabel: 'Duur'));
    out.add(_cooldown());
    return out;
  }
}
