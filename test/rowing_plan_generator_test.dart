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
    int lo = 25,
    int hi = 40,
    int weeks = 9,
  }) =>
      RowingPlanInput(
        sessionsPerWeek: spw,
        goal: goal,
        level: level,
        minMinutes: lo,
        maxMinutes: hi,
        weeks: weeks,
      );

  GeneratedRowingPlan gen(RowingPlanInput i) =>
      RowingPlanGenerator(rng: Random(42)).generate(i);

  test('produces weeks × sessionsPerWeek sessions', () {
    final plan = gen(input(spw: 3, weeks: 9));
    expect(plan.sessions, hasLength(27));
    expect(plan.weeks, 9);
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

  test('session length stays roughly within the chosen band', () {
    final plan = gen(input(lo: 25, hi: 40, weeks: 9));
    for (final s in plan.sessions) {
      final minutes = s.totalSeconds / 60;
      // Deload / recovery sessions dip lower; long sessions run a touch over.
      expect(minutes, greaterThan(25 * 0.6));
      expect(minutes, lessThan(40 + 8));
    }
  });

  test('the deload week is lighter than the week before it', () {
    final plan = gen(input(weeks: 10));
    final deload = 10 ~/ 2;
    int weekSeconds(int w) => plan.sessions
        .where((s) => s.weekIndex == w)
        .fold(0, (sum, s) => sum + s.totalSeconds);
    expect(weekSeconds(deload), lessThan(weekSeconds(deload - 1)));
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

  test('power goal uses low stroke rates for the krachthaal work', () {
    final plan = gen(input(goal: RowingGoal.kracht));
    final power = plan.sessions
        .expand((s) => s.segments)
        .where((seg) => seg.drillKey == RowDrill.krachtHaal.key)
        .toList();
    expect(power, isNotEmpty);
    expect(power.every((seg) => (seg.targetSpm ?? 99) <= 21), isTrue);
  });

  test('respects sessionsPerWeek bounds', () {
    expect(gen(input(spw: 2)).sessionsPerWeek, 2);
    expect(gen(input(spw: 5)).sessionsPerWeek, 5);
    expect(gen(input(spw: 5, weeks: 8)).sessions, hasLength(40));
  });
}
