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

  group('pace correction', () {
    test('0% leaves the split unchanged', () {
      expect(correctedPace(150, 0), 150);
    });

    test('a positive correction makes the split faster (fewer seconds)', () {
      // +10% real speed -> split divided by 1.10.
      expect(correctedPace(220, 10), closeTo(200, 0.01));
    });

    test('a negative correction makes the split slower', () {
      expect(correctedPace(200, -20), closeTo(250, 0.01));
    });

    test('round-trips through the same factor', () {
      const pct = 12.5;
      final corrected = correctedPace(180, pct)!;
      // Undoing it with the opposite percent (of the corrected value) should
      // land back close to the original — sanity check on the direction.
      expect(corrected, lessThan(180));
      expect(corrected * paceCorrectionFactor(pct), closeTo(180, 0.01));
    });

    test('null / non-positive / an absurd correction pass through', () {
      expect(correctedPace(null, 10), isNull);
      expect(correctedPace(0, 10), 0);
      expect(correctedPace(150, -150), 150); // factor <= 0 -> unchanged
    });
  });
}
