import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/rowing.dart';
import 'package:fitnesstracker/domain/rowing_format.dart';
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
    test('no reading yet → on pace, not a collapse', () {
      expect(rampHold(0, 200), RampHold.onPace);
    });
  });

  group('rampHoldSpm', () {
    test('on pace within half a spm of the target', () {
      expect(rampHoldSpm(25.6, 26), RampHold.onPace);
    });
    test('close up to 1.5 spm under', () {
      expect(rampHoldSpm(24.8, 26), RampHold.close);
    });
    test('dropping more than 1.5 spm under', () {
      expect(rampHoldSpm(23.9, 26), RampHold.dropping);
    });
    test('no reading or no target → on pace, not a collapse', () {
      expect(rampHoldSpm(0, 26), RampHold.onPace);
      expect(rampHoldSpm(24, 0), RampHold.onPace);
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
    test('defaults to stroke-rate mode; watt mode is opt-in', () {
      expect(const RampTestState().spmMode, isTrue);
      expect(const RampTestState().copyWith(spmMode: false).spmMode, isFalse);
    });
  });

  group('ramp FTP computation', () {
    test('a flat ramp trace falls back to 0.75 × best 60-second power', () {
      // Constant power → no CP fit possible.
      final samples = [
        for (var t = 0; t < 300000; t += 3000)
          RowingSample(
              id: 0, rowingSessionId: 0, tOffsetMs: t, powerW: 200),
      ];
      final r = computeFtp((
        samples: samples,
        planSegments: const [],
        totalDistanceM: 800,
        durationSeconds: 300,
      ), FtpProtocol.ramp);
      expect(r.method, FtpMethod.multiplier);
      expect(r.watts, closeTo(bestMinuteWatts(samples) * 0.75, 0.01));
      expect(r.effortWatts, closeTo(bestMinuteWatts(samples), 0.01));
    });

    test('a rising ramp trace fits Critical Power', () {
      final samples = [
        for (var t = 0; t < 360000; t += 3000)
          RowingSample(
              id: 0, rowingSessionId: 0, tOffsetMs: t, powerW: 100 + t / 3000),
      ];
      final r = computeFtp((
        samples: samples,
        planSegments: const [],
        totalDistanceM: 800,
        durationSeconds: 360,
      ), FtpProtocol.ramp);
      expect(r.method, FtpMethod.criticalPower);
      expect(r.watts, greaterThan(0));
      expect(r.watts, lessThan(bestMinuteWatts(samples)));
    });
  });

  test('RampProtocol seeds and steps', () {
    final p = RampProtocol.seeded(200); // 200*0.55 = 110
    expect(p.startWatts, 110);
    expect(p.targetForStep(0), 110);
    expect(p.targetForStep(3), 110 + 75);
  });

  group('stroke-rate ramp', () {
    test('starts at 18 spm and rises one spm a step without a prior FTP', () {
      final p = RampProtocol.seeded(null);
      expect(p.targetSpmForStep(0), 18);
      expect(p.targetSpmForStep(5), 23);
    });

    test('a known FTP seeds the start at ~55 % of it, as a stroke rate', () {
      // 146 W -> 80 W at 55 % -> ~20 spm.
      final p = RampProtocol.seeded(146);
      expect(p.startSpm, spmForWatts(146 * 0.55).roundToDouble());
      expect(p.startSpm, inInclusiveRange(19, 21));
      expect(RampProtocol.seeded(10).startSpm, 16); // never below 16
    });

    test('without a power meter the stroke rate stands in for power', () {
      // The trainer's own power field is junk (~11 W); the ramp must ignore it.
      final samples = [
        for (var t = 0; t < 420000; t += 3000)
          RowingSample(
            id: 0,
            rowingSessionId: 0,
            tOffsetMs: t,
            strokeRate: 20 + t / 60000, // 1 spm more every minute
            powerW: 11,
          ),
      ];
      final data = (
        samples: samples,
        planSegments: const <ProgramRowSegment>[],
        totalDistanceM: 900.0,
        durationSeconds: 420,
      );
      final junk = computeFtp(data, FtpProtocol.ramp);
      final real = computeFtp(data, FtpProtocol.ramp, hasPowerMeter: false);
      expect(junk.watts, lessThan(15)); // what the old code reported
      expect(real.watts, greaterThan(60));
      // ...and it maps back to a believable stroke rate.
      expect(spmForWatts(real.watts), inInclusiveRange(18, 27));
    });

    test('watts <-> stroke rate are inverses and rise with the stroke rate', () {
      expect(spmForWatts(wattsForSpm(24)), closeTo(24, 0.001));
      expect(wattsForSpm(26), greaterThan(wattsForSpm(22)));
      expect(wattsForSpm(0), 0);
      expect(spmForWatts(0), 0);
    });

    test('matches the split-based watts for the same stroke rate', () {
      // pace = 30000 / (spm x 9.06) -> the old pace-derived power.
      final pace = paceFromStrokes(24, kSpmWattMetersPerStroke)!;
      expect(wattsForSpm(24), closeTo(wattsForSplit(pace), 0.001));
    });
  });
}
