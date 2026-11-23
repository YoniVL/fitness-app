import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/rowing_plan.dart';
import 'package:fitnesstracker/domain/rowing_format.dart';
import 'package:fitnesstracker/domain/rowing_workouts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the catalogue is sizeable and every type is covered', () {
    expect(rowWorkouts.length, greaterThanOrEqualTo(30));
    for (final type in RowSessionType.values) {
      if (type == RowSessionType.herstel ||
          type == RowSessionType.intervalLang ||
          type == RowSessionType.piramide ||
          type == RowSessionType.krachtStroken ||
          type == RowSessionType.techniek) {
        expect(workoutsOfType(type), isNotEmpty, reason: type.name);
      }
    }
    expect(workoutsOfType(RowSessionType.endurance).length,
        greaterThanOrEqualTo(4));
    expect(workoutsOfType(RowSessionType.intervalKort).length,
        greaterThanOrEqualTo(4));
  });

  test('every plan-scheduled type has a 40–60 min option', () {
    for (final type in const [
      RowSessionType.endurance,
      RowSessionType.drempel,
      RowSessionType.intervalLang,
      RowSessionType.piramide,
    ]) {
      final long = workoutsOfType(type)
          .where((w) => w.approxMinutes >= 40 && w.approxMinutes <= 62);
      expect(long, isNotEmpty, reason: type.name);
    }
  });

  test('the test type covers the standard benchmarks', () {
    final ids = workoutsOfType(RowSessionType.test).map((w) => w.id).toSet();
    expect(ids, containsAll(<String>['test_2k', 'test_5k', 'test_500']));
    expect(workoutsOfType(RowSessionType.test).length, greaterThanOrEqualTo(5));
  });

  test('ids are unique', () {
    final ids = rowWorkouts.map((w) => w.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('every workout builds valid blocks at every level', () {
    for (final w in rowWorkouts) {
      for (final level in ProgramLevel.values) {
        for (final build in const [0.0, 0.5, 1.0]) {
          final blocks = w.blocks(level, build);
          expect(blocks, isNotEmpty, reason: '${w.id} $level $build');
          for (final b in blocks) {
            expect(b.seconds, greaterThan(0), reason: '${w.id}: ${b.label}');
            expect(b.label, isNotEmpty);
          }
          final minutes = blocks.fold(0, (s, b) => s + b.seconds) / 60;
          // approxMinutes should be in the right ballpark.
          expect((minutes - w.approxMinutes).abs(), lessThan(15),
              reason: '${w.id}: $minutes vs ${w.approxMinutes}');
        }
      }
    }
  });

  test('drill blocks carry a valid drill key', () {
    for (final w in rowWorkouts) {
      for (final b in w.blocks(ProgramLevel.medium, 0.5)) {
        if (b.drillKey != null) {
          expect(RowDrill.fromKey(b.drillKey), isNotNull, reason: w.id);
        }
      }
    }
  });

  test('zoneFor derives a sensible intensity', () {
    expect(RowBlock.zoneFor(spm: null, isRest: true), RowIntensity.rest);
    expect(RowBlock.zoneFor(spm: 16, isRest: false), RowIntensity.easy);
    expect(RowBlock.zoneFor(spm: 20, isRest: false), RowIntensity.steady);
    expect(RowBlock.zoneFor(spm: 24, isRest: false), RowIntensity.threshold);
    expect(RowBlock.zoneFor(spm: 28, isRest: false), RowIntensity.hard);
    expect(RowBlock.zoneFor(spm: 34, isRest: false), RowIntensity.max);
  });

  group('distance workouts', () {
    final distance = rowWorkouts.where(workoutHasDistance).toList();

    test('there are plenty, across the quality types', () {
      expect(distance.length, greaterThanOrEqualTo(12));
      final types = distance.map((w) => w.type).toSet();
      expect(
          types,
          containsAll(<RowSessionType>[
            RowSessionType.endurance,
            RowSessionType.drempel,
            RowSessionType.intervalKort,
            RowSessionType.intervalLang,
            RowSessionType.piramide,
          ]));
    });

    test('only work blocks carry metres; their seconds are the estimate', () {
      for (final w in distance) {
        for (final level in ProgramLevel.values) {
          for (final b in w.blocks(level, 1.0)) {
            if (b.meters == null) continue;
            expect(b.isRest, isFalse, reason: '${w.id}: rest with metres');
            expect(b.meters, greaterThan(0));
            expect(b.spm, isNotNull, reason: '${w.id} needs a stroke rate');
            expect(b.seconds, estimateSeconds(b.meters!, b.spm),
                reason: '${w.id} ${b.label}');
          }
        }
      }
    });

    test('the minutes in the catalogue match the blocks (within 2 min)', () {
      for (final w in distance) {
        final blocks = w.blocks(ProgramLevel.medium, 1.0);
        final minutes = blocks.fold(0, (a, b) => a + b.seconds) / 60;
        expect((minutes - w.approxMinutes).abs(), lessThanOrEqualTo(2),
            reason: '${w.id}: ${minutes.toStringAsFixed(1)} vs ${w.approxMinutes}');
      }
    });

    test('a faster stroke rate shortens the estimate, not the distance', () {
      final w = workoutById('end_5k')!;
      final slow = w.blocks(ProgramLevel.beginner, 1.0);
      final fast = w.blocks(ProgramLevel.advanced, 1.0);
      int meters(List<RowBlock> bs) =>
          bs.firstWhere((b) => b.meters != null).meters!;
      int seconds(List<RowBlock> bs) =>
          bs.firstWhere((b) => b.meters != null).seconds;
      expect(meters(slow), meters(fast));
      expect(seconds(fast), lessThan(seconds(slow)));
    });

    test('the named distances are the real thing', () {
      List<int> metres(String id) => [
            for (final b in workoutById(id)!.blocks(ProgramLevel.medium, 1.0))
              if (b.meters != null) b.meters!,
          ];
      expect(metres('end_5k'), [5000]);
      expect(metres('end_10k'), [10000]);
      expect(metres('thr_4x2000'), [2000, 2000, 2000, 2000]);
      expect(metres('thr_3x3000'), [3000, 3000, 3000]);
      expect(metres('sh_4x1000'), [1000, 1000, 1000, 1000]);
      expect(metres('pyr_dist'), [250, 500, 750, 500, 250]);
      expect(metres('lo_4x1500'), [1500, 1500, 1500, 1500]);
    });

    test('the benchmark tests stay timed (their result is a time)', () {
      for (final id in ['test_2k', 'test_5k', 'test_500']) {
        expect(workoutHasDistance(workoutById(id)!), isFalse, reason: id);
      }
    });
  });
}
