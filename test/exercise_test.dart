import 'package:fitnesstracker/domain/models/exercise.dart';
import 'package:fitnesstracker/domain/taxonomy.dart';
import 'package:flutter_test/flutter_test.dart';

Exercise _ex({bool timeBased = false}) => Exercise(
      id: 1,
      name: 'Test',
      primaryMuscleGroupId: 1,
      isTimeBased: timeBased,
    );

void main() {
  test('rep-based exercises format plainly', () {
    final ex = _ex();
    expect(ex.repsFieldLabel, 'Reps');
    expect(ex.formatReps(9), '9');
  });

  test('time-based exercises format as a hold in seconds', () {
    final ex = _ex(timeBased: true);
    expect(ex.repsFieldLabel, 'Seconden');
    expect(ex.formatReps(30), '30s');
  });

  test('is_time_based round-trips through the map', () {
    final ex = _ex(timeBased: true);
    final restored = Exercise.fromMap(ex.toMap());
    expect(restored.isTimeBased, isTrue);
  });

  test('defaultHoldSeconds is a sane plank starting point', () {
    expect(defaultHoldSeconds, greaterThanOrEqualTo(15));
  });
}
