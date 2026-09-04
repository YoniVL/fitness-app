import 'package:flutter/material.dart';

import '../../../domain/rowing_ftp.dart';
import '../../../domain/rowing_format.dart';
import '../../../domain/rowing_workouts.dart' show RowIntensity;

/// The target 500 m split (as `m:ss`) for a training zone, given the user's FTP
/// and the trainer's calibrated drag factor. Null when there is no FTP or the
/// zone is rest.
String? targetSplitLabel(RowIntensity zone, RowingFtp? ftp, double dragK) {
  final s = targetSplitSeconds(zone, ftp, dragK);
  return s == null ? null : paceLabel(s, withUnit: false);
}

/// The target 500 m split in seconds, or null.
double? targetSplitSeconds(RowIntensity zone, RowingFtp? ftp, double dragK) {
  if (ftp == null || zone == RowIntensity.rest) return null;
  return RowingZones.fromFtp(ftp.watts, dragK: dragK)[zone]?.targetSplitSeconds;
}

/// A silent on-pace indicator: compares the live split to the block's target.
/// Null when there is no plausible live pace or target.
({String label, Color color})? paceCue(
  double? livePace,
  double? targetSplit,
  ColorScheme scheme,
) {
  if (livePace == null ||
      livePace <= 40 ||
      livePace > 900 ||
      targetSplit == null ||
      targetSplit <= 0) {
    return null;
  }
  final delta = livePace - targetSplit; // + = slower than target
  if (delta <= -3) {
    return (label: 'iets rustiger', color: const Color(0xFF64B5F6));
  }
  if (delta >= 3) {
    return (label: 'aandrukken', color: const Color(0xFFFF7043));
  }
  return (label: 'op tempo', color: scheme.primary);
}

/// Compact "doel 2:05 /500m" line with an optional live cue dot.
class TargetPace extends StatelessWidget {
  const TargetPace({super.key, required this.splitLabel, this.cue});

  final String splitLabel;
  final ({String label, Color color})? cue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('doel $splitLabel /500m',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (cue case final c?) ...[
          const SizedBox(width: 10),
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c.color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(c.label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: c.color, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }
}
