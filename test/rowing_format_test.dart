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
    expect(spmLabel(23.6), '24 spm');
    expect(spmLabel(null), '–');
    expect(powerLabel(141.2), '141 W');
    expect(powerLabel(0), '–');
  });
}
