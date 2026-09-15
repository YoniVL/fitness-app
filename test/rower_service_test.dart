import 'package:fitnesstracker/features/rowing/rower_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RowerSnapshot.withPace replaces only the pace, keeping every other field', () {
    const snap = RowerSnapshot(
      strokeRate: 22,
      strokeCount: 340,
      distanceM: 1234,
      paceSec500m: 150,
      powerW: 180,
      energyKcal: 42,
      heartRate: 150,
      elapsedSeconds: 900,
    );

    final corrected = snap.withPace(130);

    expect(corrected.paceSec500m, 130);
    expect(corrected.strokeRate, snap.strokeRate);
    expect(corrected.strokeCount, snap.strokeCount);
    expect(corrected.distanceM, snap.distanceM);
    expect(corrected.powerW, snap.powerW);
    expect(corrected.energyKcal, snap.energyKcal);
    expect(corrected.heartRate, snap.heartRate);
    expect(corrected.elapsedSeconds, snap.elapsedSeconds);
  });

  test('withPace accepts null (no plausible reading)', () {
    const snap = RowerSnapshot(paceSec500m: 150);
    expect(snap.withPace(null).paceSec500m, isNull);
  });
}
