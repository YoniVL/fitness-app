import 'package:flutter/material.dart';

/// How prominent a [StatTile]'s value reads — from a compact summary row up to
/// the live-screen hero number.
enum StatSize { small, medium, big, hero }

/// Whether the label sits above or below the value.
enum StatLabelPosition { above, below }

/// A "label + value" pair — the one stat widget for the whole app. Replaces
/// the half-dozen near-identical `_Stat`/`_MiniStat`/`_Big`/`_Small` locals
/// that used to live in individual screens.
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
    final scheme = theme.colorScheme;

    final valueStyle = switch (size) {
      StatSize.small => theme.textTheme.titleLarge,
      StatSize.medium => theme.textTheme.headlineSmall,
      StatSize.big => theme.textTheme.displaySmall
          ?.copyWith(fontWeight: FontWeight.w700, height: 1.05),
      StatSize.hero =>
        theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w800),
    }?.copyWith(color: color);

    final labelStyle = (size == StatSize.small
            ? theme.textTheme.labelSmall
            : theme.textTheme.labelMedium)
        ?.copyWith(color: scheme.onSurfaceVariant);

    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: labelStyle),
        if (badge != null && badge!.isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(badge!,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
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
        if (labelPosition == StatLabelPosition.above) labelRow,
        valueWidget,
        if (labelPosition == StatLabelPosition.below) labelRow,
        if (sub != null)
          Text(sub!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
