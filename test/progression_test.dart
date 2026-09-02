import 'package:fitnesstracker/domain/progression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round 1 is the program as written', () {
    expect(progressTargets(baseSets: 3, baseReps: 9, round: 1),
        (sets: 3, reps: 9));
  });

  test('adds one rep per round up to +3', () {
    expect(progressTargets(baseSets: 3, baseReps: 9, round: 2),
        (sets: 3, reps: 10));
    expect(progressTargets(baseSets: 3, baseReps: 9, round: 3),
        (sets: 3, reps: 11));
  });

  test('the fourth round converts +3 reps into +1 set', () {
    expect(progressTargets(baseSets: 3, baseReps: 9, round: 4),
        (sets: 4, reps: 9));
    expect(progressTargets(baseSets: 3, baseReps: 9, round: 5),
        (sets: 4, reps: 10));
  });

  test('caps at +2 sets / +2 reps and then plateaus', () {
    expect(progressTargets(baseSets: 3, baseReps: 9, round: 9),
        (sets: 5, reps: 11));
    expect(progressTargets(baseSets: 3, baseReps: 9, round: 20),
        (sets: 5, reps: 11));
  });
}
