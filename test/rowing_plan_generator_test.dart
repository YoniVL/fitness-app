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

  GeneratedRowingPlan gen(RowingPlanInput i) =>
      RowingPlanGenerator(rng: Random(42)).generate(i);

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

  test('the deload week is lighter than the week before it', () {
    final plan = gen(input(weeks: 10));
    final deload = 10 ~/ 2;
    int weekSeconds(int w) => plan.sessions
        .where((s) => s.weekIndex == w)
        .fold(0, (sum, s) => sum + s.totalSeconds);
    expect(weekSeconds(deload), lessThan(weekSeconds(deload - 1)));
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
