import 'package:fitnesstracker/domain/models/rowing.dart';
import 'package:fitnesstracker/domain/rowing_ftp.dart';
import 'package:fitnesstracker/features/rowing/state/ramp_test_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rampHold', () {
    test('on pace within 3% of target', () {
      expect(rampHold(198, 200), RampHold.onPace);
    });
    test('close between 90% and 97%', () {
      expect(rampHold(185, 200), RampHold.close);
    });
    test('dropping below 90%', () {
      expect(rampHold(150, 200), RampHold.dropping);
    });
    test('no target → on pace (nothing to fail against)', () {
      expect(rampHold(0, 0), RampHold.onPace);
    });
  });

  group('RampTestState', () {
    test('stepRemaining counts down from 60 s', () {
      const s = RampTestState(stepElapsed: Duration(seconds: 20));
      expect(s.stepRemaining, const Duration(seconds: 40));
    });
    test('copyWith carries the session id once set', () {
      const s = RampTestState();
      expect(s.copyWith(sessionId: 12).sessionId, 12);
    });
  });

  group('ramp FTP computation', () {
    test('FTP is 0.75 × best 60-second power', () {
      // Rising power, 3 s cadence, over 5 minutes.
      final samples = [
        for (var t = 0; t < 300000; t += 3000)
          RowingSample(
              id: 0, rowingSessionId: 0, tOffsetMs: t, powerW: 100 + t / 3000),
      ];
      final r = computeFtp((
        samples: samples,
        planSegments: const [],
        totalDistanceM: 800,
        durationSeconds: 300,
      ), FtpProtocol.ramp);
      expect(r.watts, closeTo(bestMinuteWatts(samples) * 0.75, 0.01));
      expect(r.effortWatts, closeTo(bestMinuteWatts(samples), 0.01));
    });
  });

  test('RampProtocol seeds and steps', () {
    final p = RampProtocol.seeded(200); // 200*0.55 = 110
    expect(p.startWatts, 110);
    expect(p.targetForStep(0), 110);
    expect(p.targetForStep(3), 110 + 75);
  });
}
