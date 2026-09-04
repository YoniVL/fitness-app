import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/rowing.dart';
import 'package:fitnesstracker/domain/rowing_ftp.dart';
import 'package:fitnesstracker/domain/rowing_workouts.dart' show RowIntensity;
import 'package:flutter_test/flutter_test.dart';

RowingSample _s(int tMs, {double? w, double? pace}) => RowingSample(
      id: 0,
      rowingSessionId: 1,
      tOffsetMs: tMs,
      powerW: w,
      paceSec500m: pace,
    );

void main() {
  group('watt ↔ split', () {
    test('200 W is about 2:00 /500m at the generic drag', () {
      expect(splitForWatts(200), closeTo(120.5, 1.0));
    });

    test('round-trips', () {
      for (final w in [90.0, 150.0, 210.0, 300.0]) {
        expect(wattsForSplit(splitForWatts(w)), closeTo(w, 0.5));
      }
    });

    test('honours a calibrated drag factor', () {
      expect(splitForWatts(200, dragK: 3.2),
          greaterThan(splitForWatts(200, dragK: 2.8)));
    });
  });

  group('calibrateDragK', () {
    test('recovers the drag factor from clean paired samples', () {
      const kTrue = 3.0;
      const pace = 120.0; // v = 0.24 m/s per metre
      final w = kTrue / (0.24 * 0.24 * 0.24);
      final samples = [for (var i = 0; i < 30; i++) _s(i * 3000, w: w, pace: pace)];
      expect(calibrateDragK(samples), closeTo(kTrue, 0.02));
    });

    test('returns null with too few samples', () {
      expect(calibrateDragK([for (var i = 0; i < 10; i++) _s(i, w: 200, pace: 120)]),
          isNull);
    });
  });

  group('RowingZones', () {
    test('easy is slower than threshold is slower than max', () {
      final z = RowingZones.fromFtp(200);
      expect(z[RowIntensity.easy]!.targetSplitSeconds,
          greaterThan(z[RowIntensity.threshold]!.targetSplitSeconds));
      expect(z[RowIntensity.threshold]!.targetSplitSeconds,
          greaterThan(z[RowIntensity.max]!.targetSplitSeconds));
    });

    test('threshold target is ~89% of FTP watts', () {
      expect(RowingZones.fromFtp(200)[RowIntensity.threshold]!.targetWatts,
          closeTo(178, 0.1));
    });

    test('fast band split is faster than the slow band split', () {
      final steady = RowingZones.fromFtp(200)[RowIntensity.steady]!;
      expect(steady.splitFastSeconds, lessThan(steady.splitSlowSeconds));
    });
  });

  group('computeFtp', () {
    FtpSessionData session(FtpProtocol p, double effortWatts) {
      final segs = ftpTestSegments(p, ProgramLevel.medium);
      final total = segs.fold(0, (a, s) => a + s.durationSeconds);
      final window = p.effortWindow(segs)!;
      return (
        planSegments: segs,
        totalDistanceM: 5000,
        durationSeconds: total,
        samples: [
          for (var t = 0; t < total * 1000; t += 3000)
            _s(t,
                w: t >= window.startSec * 1000 && t <= window.endSec * 1000
                    ? effortWatts
                    : 90,
                pace: 120),
        ],
      );
    }

    test('20-min test applies the 0.95 factor over the effort window', () {
      final r = computeFtp(session(FtpProtocol.test20, 220), FtpProtocol.test20);
      expect(r.watts, closeTo(209, 1)); // 220 * 0.95
      expect(r.effortWatts, closeTo(220, 1));
      expect(r.lowConfidence, isFalse);
    });

    test('short test applies the 0.88 factor', () {
      final r =
          computeFtp(session(FtpProtocol.testShort, 260), FtpProtocol.testShort);
      expect(r.watts, closeTo(228.8, 1)); // 260 * 0.88
    });

    test('ramp with a rising curve fits Critical Power', () {
      final samples = [
        for (var t = 0; t < 600000; t += 3000)
          _s(t, w: 100 + t / 3000, pace: 120), // rises ~1 W per sample
      ];
      final r = computeFtp(
        (
          planSegments: const <ProgramRowSegment>[],
          totalDistanceM: 0,
          durationSeconds: 600,
          samples: samples,
        ),
        FtpProtocol.ramp,
      );
      expect(r.method, FtpMethod.criticalPower);
      final cp = criticalPower(
        (seconds: 60, watts: bestAvgWatts(samples, 60)),
        (seconds: 240, watts: bestAvgWatts(samples, 240)),
      )!;
      expect(r.watts, closeTo(cp.cp, 0.01));
      // CP is the asymptote — below any finite effort, but not far below.
      expect(r.watts, lessThan(bestAvgWatts(samples, 60)));
      expect(r.watts, greaterThan(bestAvgWatts(samples, 240) * 0.85));
      expect(r.cpWPrime, greaterThan(0));
    });

    test('ramp with a flat curve falls back to best-minute × 0.75', () {
      final samples = [
        for (var t = 0; t < 300000; t += 3000) _s(t, w: 180, pace: 120),
      ];
      final r = computeFtp(
        (
          planSegments: const <ProgramRowSegment>[],
          totalDistanceM: 0,
          durationSeconds: 300,
          samples: samples,
        ),
        FtpProtocol.ramp,
      );
      expect(r.method, FtpMethod.multiplier);
      expect(r.watts, closeTo(180 * 0.75, 0.01));
    });

    test('falls back to distance/time when there are no samples', () {
      final r = computeFtp(
        (
          planSegments: ftpTestSegments(FtpProtocol.test20, ProgramLevel.medium),
          totalDistanceM: 5000,
          durationSeconds: 1200,
          samples: const <RowingSample>[],
        ),
        FtpProtocol.test20,
      );
      expect(r.lowConfidence, isTrue);
      expect(r.watts, greaterThan(0));
    });
  });

  group('criticalPower', () {
    test('recovers CP and W\' from two points on P = W\'/t + CP', () {
      // CP = 250, W' = 3000 J → P(60) = 300, P(240) = 262.5
      final r = criticalPower(
          (seconds: 60, watts: 300), (seconds: 240, watts: 262.5))!;
      expect(r.cp, closeTo(250, 0.01));
      expect(r.wPrime, closeTo(3000, 0.5));
    });

    test('order of the two points does not matter', () {
      final a = criticalPower(
          (seconds: 60, watts: 300), (seconds: 240, watts: 262.5))!;
      final b = criticalPower(
          (seconds: 240, watts: 262.5), (seconds: 60, watts: 300))!;
      expect(a.cp, closeTo(b.cp, 0.001));
    });

    test('null when power does not fall with duration', () {
      expect(
          criticalPower(
              (seconds: 60, watts: 250), (seconds: 240, watts: 250)),
          isNull);
    });

    test('null when the windows are too close together', () {
      expect(
          criticalPower(
              (seconds: 60, watts: 300), (seconds: 120, watts: 290)),
          isNull);
    });
  });

  group('bestAvgWatts', () {
    test('a longer window cannot beat a shorter one', () {
      final samples = [
        for (var t = 0; t < 600000; t += 3000) _s(t, w: 100 + t / 3000),
      ];
      expect(bestAvgWatts(samples, 60),
          greaterThan(bestAvgWatts(samples, 240)));
    });

    test('bestMinuteWatts is the 60 s window', () {
      final samples = [for (var t = 0; t < 120000; t += 3000) _s(t, w: 200)];
      expect(bestMinuteWatts(samples), bestAvgWatts(samples, 60));
    });
  });

  group('suggestedLevelFromFtp', () {
    test('bands', () {
      expect(suggestedLevelFromFtp(90), ProgramLevel.beginner);
      expect(suggestedLevelFromFtp(130), ProgramLevel.medium);
      expect(suggestedLevelFromFtp(210), ProgramLevel.advanced);
    });
  });

  group('RampProtocol', () {
    test('seeds the start from a prior FTP', () {
      expect(RampProtocol.seeded(200).startWatts, 110); // 200*0.55 → 110
      expect(RampProtocol.seeded(null).startWatts, 100);
    });

    test('target rises by the increment each step', () {
      const r = RampProtocol(startWatts: 100, incrementWatts: 25);
      expect(r.targetForStep(0), 100);
      expect(r.targetForStep(4), 200);
    });
  });
}
