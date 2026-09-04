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

    test('ramp uses best-minute power × 0.75', () {
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
      expect(r.watts, greaterThan(0));
      expect(r.watts, closeTo(bestMinuteWatts(samples) * 0.75, 0.01));
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
