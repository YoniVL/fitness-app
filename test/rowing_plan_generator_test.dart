import 'dart:math';

import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/rowing_plan.dart';
import 'package:fitnesstracker/domain/rowing_plan_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RowingPlanInput input({
    int spw = 3,
    RowingGoal goal = RowingGoal.uithouding,
    ProgramLevel level = ProgramLevel.medium,
    Set<(int, int)> bands = const {(25, 40)},
    int weeks = 9,
  }) =>
      RowingPlanInput(
        sessionsPerWeek: spw,
        goal: goal,
        level: level,
        bands: bands,
        weeks: weeks,
      );

  GeneratedRowingPlan gen(RowingPlanInput i, {double? ftpWatts}) =>
      RowingPlanGenerator(rng: Random(42)).generate(i, ftpWatts: ftpWatts);

  test('produces weeks × sessionsPerWeek sessions', () {
    final plan = gen(input(spw: 3, weeks: 9));
    expect(plan.sessions, hasLength(27));
    for (var w = 0; w < 9; w++) {
      expect(plan.sessions.where((s) => s.weekIndex == w), hasLength(3));
    }
  });

  test('every segment has a label and a positive duration', () {
    final plan = gen(input());
    for (final s in plan.sessions) {
      expect(s.segments, isNotEmpty);
      for (final seg in s.segments) {
        expect(seg.intensityLabel, isNotEmpty);
        expect(seg.durationSeconds, greaterThan(0));
      }
    }
  });

  test('every session has a sensible total duration', () {
    final plan = gen(input(bands: {(25, 40)}, weeks: 10));
    for (final s in plan.sessions) {
      final minutes = s.totalSeconds / 60;
      expect(minutes, greaterThan(10));
      expect(minutes, lessThan(70));
    }
  });

  int weekSeconds(GeneratedRowingPlan plan, int w) => plan.sessions
      .where((s) => s.weekIndex == w)
      .fold(0, (sum, s) => sum + s.totalSeconds);

  bool isDeloadWeek(int w, int weeks) =>
      weeks >= 8 && (w + 1) % 4 == 0 && w != weeks - 1;

  test('the deload week (every 4th) is lighter than the same week at full load',
      () {
    // Week index 3 is a deload for an 8-week plan but a normal week for a
    // 7-week plan.
    final withDeload = gen(input(bands: {(25, 40)}, weeks: 8));
    final fullLoad = gen(input(bands: {(25, 40)}, weeks: 7));
    expect(weekSeconds(withDeload, 3),
        lessThan((weekSeconds(fullLoad, 3) * 0.8).round()));
  });

  test('weekly volume builds to a mid/late peak, then tapers', () {
    final plan = gen(input(weeks: 10));
    final vols = [for (var w = 0; w < 10; w++) weekSeconds(plan, w)];
    final peak = vols.reduce((a, b) => a > b ? a : b);
    final peakWeek = vols.indexOf(peak);
    expect(peakWeek, greaterThan(2), reason: 'peak should not be at the start');
    expect(peakWeek, lessThan(9), reason: 'plan should taper at the end');
    expect(vols.last, lessThan(peak));
    expect(vols.first, lessThan(peak));
  });

  test('weekly volume does not oscillate between non-deload weeks', () {
    // Recovery weeks used to swing the total ~30 %; weekly-load periodisation
    // should keep neighbouring build weeks within ~25 % of each other.
    for (final goal in RowingGoal.values) {
      final plan = gen(input(goal: goal, spw: 4, weeks: 12));
      final build = [
        for (var w = 0; w < 12; w++)
          if (!isDeloadWeek(w, 12) && w != 0 && w != 11)
            weekSeconds(plan, w),
      ];
      for (var i = 1; i < build.length; i++) {
        final ratio = build[i] / build[i - 1];
        expect(ratio, inInclusiveRange(0.72, 1.38),
            reason: '${goal.name}: $build');
      }
    }
  });

  test('a benchmark test is scheduled in the first and last week', () {
    final plan = gen(input(goal: RowingGoal.uithouding, weeks: 9));
    bool hasTest(int w) => plan.sessions
        .any((s) => s.weekIndex == w && s.type == RowSessionType.test);
    expect(hasTest(0), isTrue);
    expect(hasTest(8), isTrue);
    // ...and nowhere in between.
    for (var w = 1; w < 8; w++) {
      expect(hasTest(w), isFalse, reason: 'week ${w + 1}');
    }
  });

  test('a week does not repeat a quality session type', () {
    // Endurance may appear twice in a hard week (a recovery slot becomes an
    // extra endurance row); no other archetype should repeat within a week.
    for (final goal in RowingGoal.values) {
      final plan = gen(input(goal: goal, spw: 4, weeks: 10));
      for (var w = 0; w < 10; w++) {
        final types = plan.sessions
            .where((s) => s.weekIndex == w)
            .map((s) => s.type)
            .where((t) => t != RowSessionType.endurance)
            .toList();
        expect(types.toSet().length, types.length,
            reason: '${goal.name} week ${w + 1}: $types');
      }
    }
  });

  test('the technique goal gets no benchmark tests', () {
    final plan = gen(input(goal: RowingGoal.techniek, weeks: 8));
    expect(plan.sessions.any((s) => s.type == RowSessionType.test), isFalse);
  });

  test('segments carry the workout intensity zone', () {
    final plan = gen(input(level: ProgramLevel.advanced));
    final work = plan.sessions
        .expand((s) => s.segments)
        .where((seg) => !seg.isRest && seg.intensityLabel == 'Endurance');
    expect(work, isNotEmpty);
    // Advanced endurance rows at r22 — a raw-spm zone would call that
    // "threshold"; the stored zone must keep it "steady".
    for (final seg in work) {
      expect(seg.zone, 'steady', reason: seg.intensityLabel);
    }
  });

  test('without an FTP, segments carry no target watts', () {
    final plan = gen(input());
    expect(plan.ftpWattsAtGen, isNull);
    expect(plan.sessions.expand((s) => s.segments).every((s) => s.targetWatts == null),
        isTrue);
  });

  test('with an FTP, non-rest segments get a zone-scaled target power', () {
    final plan = gen(input(), ftpWatts: 200);
    expect(plan.ftpWattsAtGen, 200);
    final work = plan.sessions
        .expand((s) => s.segments)
        .where((s) => !s.isRest && s.zone == 'steady');
    expect(work, isNotEmpty);
    for (final s in work) {
      // steady is 75 % of FTP → 150 W.
      expect(s.targetWatts, 150);
    }
    // Rest segments never carry a target.
    expect(
        plan.sessions.expand((s) => s.segments).where((s) => s.isRest).every(
            (s) => s.targetWatts == null),
        isTrue);
    // Harder zones pull a higher target than easier ones.
    final byZone = <String, double>{};
    for (final s in plan.sessions.expand((s) => s.segments)) {
      if (!s.isRest && s.targetWatts != null) byZone[s.zone!] = s.targetWatts!;
    }
    if (byZone.containsKey('easy') && byZone.containsKey('threshold')) {
      expect(byZone['threshold']!, greaterThan(byZone['easy']!));
    }
  });

  test('auto-name is unique per goal/level/sessions-per-week', () {
    final a = gen(input(goal: RowingGoal.uithouding, level: ProgramLevel.medium, spw: 3));
    final b = gen(input(goal: RowingGoal.uithouding, level: ProgramLevel.advanced, spw: 3));
    final c = gen(input(goal: RowingGoal.vetverlies, level: ProgramLevel.medium, spw: 4));
    expect({a.name, b.name, c.name}, hasLength(3));
  });

  test('consecutive weeks are not identical for the same slot', () {
    final plan = gen(input(spw: 3, weeks: 8));
    for (var w = 0; w < 7; w++) {
      final thisWeek =
          plan.sessions.where((s) => s.weekIndex == w).map((s) => s.label);
      final nextWeek = plan.sessions
          .where((s) => s.weekIndex == w + 1)
          .map((s) => s.label)
          .toList();
      // At least one session differs from the same slot next week.
      final differs =
          thisWeek.toList().asMap().entries.any((e) => e.value != nextWeek[e.key]);
      expect(differs, isTrue, reason: 'week $w vs ${w + 1}');
    }
  });

  test('technique goal weaves in drill segments', () {
    final plan = gen(input(goal: RowingGoal.techniek));
    final drillSegs = plan.sessions
        .expand((s) => s.segments)
        .where((seg) => seg.drillKey != null);
    expect(drillSegs, isNotEmpty);
    for (final seg in drillSegs) {
      expect(RowDrill.fromKey(seg.drillKey), isNotNull);
    }
  });

  test('multiple bands spread session lengths further apart', () {
    final one = gen(input(bands: {(20, 30)}, weeks: 10));
    final many = gen(input(bands: {(15, 25), (30, 45), (45, 60)}, weeks: 10));
    double spread(GeneratedRowingPlan p) {
      final mins = p.sessions.map((s) => s.totalSeconds / 60).toList()..sort();
      return mins.last - mins.first;
    }

    expect(spread(many), greaterThan(spread(one)));
  });

  test('endurance sessions are labelled Endurance', () {
    expect(RowSessionType.endurance.label, 'Endurance');
  });

  test('respects sessionsPerWeek bounds', () {
    expect(gen(input(spw: 2)).sessionsPerWeek, 2);
    expect(gen(input(spw: 5, weeks: 8)).sessions, hasLength(40));
  });
}
