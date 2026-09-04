import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/rowing_ftp.dart';
import 'package:fitnesstracker/domain/rowing_workouts.dart' show RowIntensity;
import 'package:fitnesstracker/features/rowing/widgets/target_pace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProgramRowSegment _seg(String zone,
        {bool rest = false, double? watts, int? spm}) =>
    ProgramRowSegment(
      id: 0,
      programDayId: 0,
      orderIndex: 0,
      durationSeconds: 300,
      targetStrokeRate: spm,
      intensityLabel: zone,
      isRest: rest,
      zone: rest ? null : zone,
      targetWatts: watts,
    );

void main() {
  const scheme = ColorScheme.dark();
  final ftp = RowingFtp(
      watts: 200, setAt: DateTime(2026, 9, 1), source: FtpSource.manual);

  group('targetSplitLabel', () {
    test('null without an FTP', () {
      expect(targetSplitLabel(RowIntensity.steady, null, kGeneric), isNull);
    });

    test('null for a rest block', () {
      expect(targetSplitLabel(RowIntensity.rest, ftp, kGeneric), isNull);
    });

    test('formatted m:ss for a real zone', () {
      final label = targetSplitLabel(RowIntensity.threshold, ftp, kGeneric)!;
      expect(label, matches(RegExp(r'^\d:\d\d$')));
    });
  });

  group('paceCue', () {
    double target(RowIntensity z) =>
        targetSplitSeconds(z, ftp, kGeneric)!;

    test('null without a live pace or target', () {
      expect(paceCue(null, target(RowIntensity.steady), scheme), isNull);
      expect(paceCue(125, null, scheme), isNull);
    });

    test('on pace within the dead-band', () {
      final t = target(RowIntensity.steady);
      expect(paceCue(t + 1, t, scheme)!.label, 'op tempo');
    });

    test('faster than target → rustiger', () {
      final t = target(RowIntensity.steady);
      expect(paceCue(t - 6, t, scheme)!.label, 'iets rustiger');
    });

    test('slower than target → aandrukken', () {
      final t = target(RowIntensity.steady);
      expect(paceCue(t + 6, t, scheme)!.label, 'aandrukken');
    });

    test('ignores an implausible live pace', () {
      expect(paceCue(5, target(RowIntensity.steady), scheme), isNull);
      expect(paceCue(1000, target(RowIntensity.steady), scheme), isNull);
    });
  });

  group('segmentTargetSplitSeconds', () {
    test('a baked-in target wins over the live FTP zone calc', () {
      final baked = _seg('steady', watts: 100); // very easy → slow split
      final live = _seg('steady'); // 75 % of 200 = 150 W
      expect(segmentTargetSplitSeconds(baked, ftp, kGeneric),
          greaterThan(segmentTargetSplitSeconds(live, ftp, kGeneric)!));
      expect(segmentTargetSplitSeconds(baked, null, kGeneric),
          closeTo(splitForWatts(100), 0.01));
    });

    test('null for rest and when there is nothing to go on', () {
      expect(segmentTargetSplitSeconds(_seg('steady', rest: true), ftp, kGeneric),
          isNull);
      expect(segmentTargetSplitSeconds(_seg('steady'), null, kGeneric), isNull);
    });
  });

  group('dayPaceSummary', () {
    test('null when no segment has a target', () {
      expect(dayPaceSummary([_seg('steady'), _seg('hard')], null, kGeneric),
          isNull);
    });

    test('one zone → a single split', () {
      final s = dayPaceSummary([_seg('steady', watts: 150)], null, kGeneric)!;
      expect(s, startsWith('richttempo '));
      expect(s, contains('/500m'));
    });

    test('two zones → duur + piek', () {
      final s = dayPaceSummary(
          [_seg('easy', watts: 120), _seg('hard', watts: 200)],
          null,
          kGeneric)!;
      expect(s, contains('duur'));
      expect(s, contains('piek'));
    });
  });

  group('rowTargetsStale', () {
    test('false without a current FTP', () {
      expect(rowTargetsStale(180, null), isFalse);
    });
    test('true when the plan was built without an FTP', () {
      expect(rowTargetsStale(null, 200), isTrue);
    });
    test('within 4 % is not stale', () {
      expect(rowTargetsStale(197, 200), isFalse);
      expect(rowTargetsStale(180, 200), isTrue);
    });
  });
}
