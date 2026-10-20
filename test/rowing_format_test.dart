import 'package:fitnesstracker/domain/rowing_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hmsLabel', () {
    expect(hmsLabel(const Duration(seconds: 5)), '0:05');
    expect(hmsLabel(const Duration(minutes: 14, seconds: 2)), '14:02');
    expect(hmsLabel(const Duration(hours: 1, minutes: 3, seconds: 20)),
        '1:03:20');
  });

  test('paceLabel', () {
    expect(paceLabel(131), '2:11 /500m');
    expect(paceLabel(131, withUnit: false), '2:11');
    expect(paceLabel(null), '–');
    expect(paceLabel(0), '–');
  });

  test('paceSecPer500 derives pace from distance + time', () {
    // 2000 m in 8:00 -> 2:00 /500m -> 120 s.
    final p = paceSecPer500(2000, const Duration(minutes: 8));
    expect(p, closeTo(120, 0.01));
    expect(paceSecPer500(0, const Duration(minutes: 8)), isNull);
  });

  test('distanceLabel', () {
    expect(distanceLabel(850), '850 m');
    expect(distanceLabel(3200), '3,2 km');
    expect(distanceLabel(12000), '12 km');
  });

  test('spm / power labels', () {
    expect(spmLabel(23.6), '24 SPM');
    expect(spmLabel(null), '–');
    expect(powerLabel(141.2), '141 W');
    expect(powerLabel(0), '–');
  });

  group('paceFromStrokes', () {
    test('is metres per stroke turned into a split', () {
      // 21 spm x 9.06 m = 190.26 m/min -> 500 m in 157.7 s.
      expect(paceFromStrokes(21, 9.06), closeTo(157.7, 0.1));
      // The trainer's own model: 6.25 m/stroke -> pace = 4800 / spm.
      expect(paceFromStrokes(24, kTrainerPaceMetersPerStroke), closeTo(200, 0.01));
    });

    test('more metres per stroke is a faster split', () {
      expect(paceFromStrokes(22, 10)!, lessThan(paceFromStrokes(22, 8)!));
    });

    test('no stroke rate or metres -> no split', () {
      expect(paceFromStrokes(null, 9), isNull);
      expect(paceFromStrokes(0, 9), isNull);
      expect(paceFromStrokes(20, 0), isNull);
    });
  });
}
