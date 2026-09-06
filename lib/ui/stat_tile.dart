import 'package:flutter/material.dart';

import '../app/theme.dart';

/// How prominent a [StatTile]'s value reads — from a compact summary row up to
/// the live-screen hero number.
enum StatSize { small, medium, big, hero }

/// Whether the label sits above or below the value.
enum StatLabelPosition { above, below }

/// A "label + value" pair — the one stat widget for the whole app. Modernist:
/// the value is set in extra-bold tabular figures with tight tracking, the
/// label small and all-caps.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.size = StatSize.medium,
    this.labelPosition = StatLabelPosition.below,
    this.color,
    this.sub,
    this.badge,
  });

  final String label;
  final String value;
  final StatSize size;
  final StatLabelPosition labelPosition;

  /// Overrides the value's colour (e.g. a live on-pace/off-pace cue).
  final Color? color;

  /// A small caption under the value (e.g. a converted unit).
  final String? sub;

  /// A short highlighted word next to the label (e.g. "op tempo").
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;

    final valueSize = switch (size) {
      StatSize.small => 24.0,
      StatSize.medium => 32.0,
      StatSize.big => 38.0,
      StatSize.hero => 56.0,
    };
    final valueStyle =
        AppTheme.numeric(size: valueSize, color: color ?? p.ink);

    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
      color: p.mute,
    );

    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: labelStyle),
        if (badge != null && badge!.isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(badge!.toUpperCase(),
              style: labelStyle?.copyWith(
                  color: color ?? p.accent, fontWeight: FontWeight.w800)),
        ],
      ],
    );

    final valueWidget = size == StatSize.small
        ? Text(value, style: valueStyle)
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: valueStyle),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (labelPosition == StatLabelPosition.above) ...[
          labelRow,
          const SizedBox(height: 2),
        ],
        valueWidget,
        if (labelPosition == StatLabelPosition.below) ...[
          const SizedBox(height: 2),
          labelRow,
        ],
        if (sub != null)
          Text(sub!,
              style: theme.textTheme.bodySmall?.copyWith(color: p.mute)),
      ],
    );
  }
}
