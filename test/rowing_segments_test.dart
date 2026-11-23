import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/rowing_format.dart';
import 'package:fitnesstracker/domain/rowing_segments.dart';
import 'package:flutter_test/flutter_test.dart';

ProgramRowSegment _timed(int seconds, {bool rest = false}) => ProgramRowSegment(
      id: 0,
      programDayId: 0,
      orderIndex: 0,
      durationSeconds: seconds,
      intensityLabel: rest ? 'Rust' : 'Blok',
      isRest: rest,
    );

ProgramRowSegment _dist(int meters, {int estimate = 300}) => ProgramRowSegment(
      id: 0,
      programDayId: 0,
      orderIndex: 0,
      durationSeconds: estimate,
      intensityLabel: 'Afstand',
      distanceM: meters,
    );

void main() {
  group('segmentComplete', () {
    test('a timed block ends on its duration, whatever the distance', () {
      final s = _timed(60);
      expect(segmentComplete(s, elapsedSeconds: 59, distanceM: 9999), isFalse);
      expect(segmentComplete(s, elapsedSeconds: 60, distanceM: 0), isTrue);
    });

    test('a distance block ends on its metres, whatever the time', () {
      final s = _dist(2000);
      expect(segmentComplete(s, elapsedSeconds: 9999, distanceM: 1999), isFalse);
      expect(segmentComplete(s, elapsedSeconds: 0, distanceM: 2000), isTrue);
    });

    test('a rest block is always timed, even if it carries a distance', () {
      final rest = ProgramRowSegment(
        id: 0,
        programDayId: 0,
        orderIndex: 0,
        durationSeconds: 90,
        intensityLabel: 'Rust',
        isRest: true,
        distanceM: 500,
      );
      expect(rest.isDistance, isFalse);
      expect(segmentComplete(rest, elapsedSeconds: 89, distanceM: 500), isFalse);
      expect(segmentComplete(rest, elapsedSeconds: 90, distanceM: 0), isTrue);
    });
  });

  group('locateSegment', () {
    test('timed blocks: walks by elapsed time, like before', () {
      final segs = [_timed(60), _timed(30, rest: true), _timed(60)];
      final c = locateSegment(segs, const [], const Duration(seconds: 100), 0);
      expect(c.index, 2);
      expect(c.elapsedSeconds, 10);
    });

    test('a session before its first block ends stays in block 0', () {
      final segs = [_timed(60), _timed(60)];
      final c = locateSegment(segs, const [], const Duration(seconds: 20), 0);
      expect((c.index, c.elapsedSeconds), (0, 20));
    });

    test('a distance block is over when the session distance has grown by it', () {
      final segs = [_timed(60), _dist(500), _timed(30, rest: true)];
      // 4 m/s throughout: 60 s warm-up = 240 m, then 500 m takes 125 s.
      final samples = [
        for (var t = 0; t <= 300; t += 3) (tMs: t * 1000, distanceM: t * 4.0),
      ];
      // At 200 s: 800 m rowed -> past the distance block (ended at 185 s).
      final c = locateSegment(
          segs, samples, const Duration(seconds: 200), 800);
      expect(c.index, 2);
      expect(c.elapsedSeconds, closeTo(15, 1));
    });

    test('halfway through a distance block: its start distance is recovered', () {
      final segs = [_timed(60), _dist(1000)];
      final samples = [
        for (var t = 0; t <= 120; t += 3) (tMs: t * 1000, distanceM: t * 3.0),
      ];
      final c = locateSegment(
          segs, samples, const Duration(seconds: 120), 360);
      expect(c.index, 1);
      expect(c.elapsedSeconds, 60);
      expect(c.startDistanceM, closeTo(180, 1)); // 60 s x 3 m/s
    });

    test('a slow distance block keeps the cursor on it however long it takes', () {
      final segs = [_dist(2000), _timed(30, rest: true)];
      final samples = [
        for (var t = 0; t <= 600; t += 3) (tMs: t * 1000, distanceM: t * 2.0),
      ];
      // 600 s x 2 m/s = 1200 m of 2000: still the first block, long past its estimate.
      final c = locateSegment(
          segs, samples, const Duration(seconds: 600), 1200);
      expect(c.index, 0);
      expect(c.elapsedSeconds, 600);
    });

    test('once every block has run its course the cursor sits on the last', () {
      final segs = [_timed(30), _timed(30)];
      final c = locateSegment(segs, const [], const Duration(seconds: 500), 0);
      expect(c.index, 1);
      expect(c.elapsedSeconds, 470);
    });

    test('no blocks: elapsed time only', () {
      final c = locateSegment(const [], const [], const Duration(seconds: 42), 7);
      expect((c.index, c.elapsedSeconds), (0, 42));
    });
  });

  test('segmentLengthLabel shows metres for a distance block, time otherwise', () {
    String time(int s) => '${s}s';
    expect(segmentLengthLabel(_dist(2000), time), '2 km');
    expect(segmentLengthLabel(_dist(500), time), '500 m');
    expect(segmentLengthLabel(_timed(90), time), '90s');
  });

  group('distance helpers', () {
    test('blockDistanceLabel', () {
      expect(blockDistanceLabel(250), '250 m');
      expect(blockDistanceLabel(1000), '1 km');
      expect(blockDistanceLabel(1500), '1,5 km');
      expect(blockDistanceLabel(10000), '10 km');
    });

    test('estimateSeconds follows the stroke rate and metres per stroke', () {
      // 21 spm x 9.06 m = 190.26 m/min -> 5 km in ~26 min.
      expect(estimateSeconds(5000, 21), closeTo(1577, 2));
      // More spm, faster.
      expect(estimateSeconds(2000, 28), lessThan(estimateSeconds(2000, 22)));
      // Unknown rate falls back to 20; nonsense rate does too.
      expect(estimateSeconds(1000, null), estimateSeconds(1000, 20));
      expect(estimateSeconds(1000, 0), estimateSeconds(1000, 20));
      // A user's own metres per stroke.
      expect(estimateSeconds(1000, 20, metersPerStroke: 6.25),
          closeTo(480, 1));
    });
  });
}
