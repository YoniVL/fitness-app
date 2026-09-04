import 'package:fitnesstracker/domain/rowing_ftp.dart';
import 'package:fitnesstracker/domain/rowing_workouts.dart' show RowIntensity;
import 'package:fitnesstracker/features/rowing/widgets/target_pace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
