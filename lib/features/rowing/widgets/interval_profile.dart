import 'package:flutter/material.dart';

import '../../../domain/models/program.dart';
import '../../../domain/rowing_plan_generator.dart';
import '../../../domain/rowing_workouts.dart';

/// A block reduced to what the profile needs.
typedef ProfileBlock = ({int seconds, int? spm, bool isRest, RowIntensity? zone});

RowIntensity? _zone(String? name) => rowIntensityFromName(name);

/// Parse a stored `RowIntensity.name`, or null.
RowIntensity? rowIntensityFromName(String? name) {
  if (name == null) return null;
  for (final z in RowIntensity.values) {
    if (z.name == name) return z;
  }
  return null;
}

/// The zone to colour a segment by: its stored [zone], else derived from the
/// stroke rate and rest flag.
RowIntensity segmentZone({
  required String? zone,
  required int? spm,
  required bool isRest,
}) {
  if (isRest) return RowIntensity.rest;
  return rowIntensityFromName(zone) ??
      RowBlock.zoneFor(spm: spm, isRest: isRest);
}

List<ProfileBlock> profileFromSegments(List<ProgramRowSegment> segs) => [
      for (final s in segs)
        (
          seconds: s.durationSeconds,
          spm: s.targetStrokeRate,
          isRest: s.isRest,
          zone: _zone(s.zone),
        ),
    ];

List<ProfileBlock> profileFromGenerated(List<GeneratedRowSegment> segs) => [
      for (final s in segs)
        (
          seconds: s.durationSeconds,
          spm: s.targetSpm,
          isRest: s.isRest,
          zone: _zone(s.zone),
        ),
    ];

/// Colour for an intensity zone. Echoes the reference chart: blue → green →
/// yellow → orange → red, rest grey.
Color intensityColor(RowIntensity zone, ColorScheme scheme) => switch (zone) {
      RowIntensity.rest => scheme.outlineVariant,
      RowIntensity.easy => const Color(0xFF64B5F6),
      RowIntensity.steady => const Color(0xFF66BB6A),
      RowIntensity.threshold => const Color(0xFFFFCA28),
      RowIntensity.hard => const Color(0xFFFF7043),
      RowIntensity.max => const Color(0xFFEF5350),
    };

/// A horizontal strip of blocks: width ∝ duration, height ∝ stroke rate,
/// colour by intensity zone. The visual signature of a rowing session.
class IntervalProfile extends StatelessWidget {
  const IntervalProfile({
    super.key,
    required this.blocks,
    this.height = 64,
    this.progressFraction,
  });

  final List<ProfileBlock> blocks;
  final double height;

  /// 0..1 — draws a "you are here" marker (live screen).
  final double? progressFraction;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    final rates = blocks
        .where((b) => !b.isRest && b.spm != null)
        .map((b) => b.spm!)
        .toList();
    final maxRate = rates.isEmpty ? 30 : rates.reduce((a, b) => a > b ? a : b);
    final minRate = rates.isEmpty ? 16 : rates.reduce((a, b) => a < b ? a : b);
    final span = (maxRate - minRate).clamp(1, 100);

    double frac(ProfileBlock b) {
      if (b.isRest) return 0.28;
      final r = b.spm ?? minRate;
      return (0.4 + 0.6 * (r - minRate) / span).clamp(0.28, 1.0);
    }

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in blocks)
                  Expanded(
                    flex: b.seconds.clamp(1, 1 << 20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.5),
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: frac(b),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: intensityColor(
                              b.isRest
                                  ? RowIntensity.rest
                                  : (b.zone ??
                                      RowBlock.zoneFor(
                                          spm: b.spm, isRest: b.isRest)),
                              scheme,
                            ), // zone resolved by the profile adapters
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (progressFraction != null)
              Positioned(
                left: (c.maxWidth * progressFraction!.clamp(0.0, 1.0)) - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: scheme.onSurface),
              ),
          ],
        ),
      ),
    );
  }
}
