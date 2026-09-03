import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/rowing_plan.dart';
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
}
