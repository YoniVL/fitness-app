import 'package:flutter/material.dart';

import '../app/theme.dart';

/// A "nothing here yet" placeholder — an icon, a short message, and an
/// optional action. Modernist: flush-left, muted, square.
class EmptyState extends StatelessWidget {
  const EmptyState(
    this.text, {
    super.key,
    this.icon,
    this.action,
    this.padding = const EdgeInsets.symmetric(vertical: 28),
  });

  final String text;
  final IconData? icon;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 28, color: p.mute),
            const SizedBox(height: 10),
          ],
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(color: p.mute),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}
